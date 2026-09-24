import Foundation
import Darwin

/// Owns only sessions created on its private socket. The placeholder pane is not a user shell.
public final class ManagedTmux: @unchecked Sendable {
    public struct Binding: Equatable, Sendable {
        public let sessionName: String
        public let sessionID: String
        public let paneID: String
        public let panePID: Int32
        public let socketPath: String
    }

    /// Capture bytes remain private; this only proves that the sink opened before workload.
    public struct CaptureGate: Equatable, Sendable {
        public let id: UUID
        public let sessionID: UUID
        public let generation: UInt64
    }

    public struct CaptureObservation: Equatable, Sendable {
        public let gate: CaptureGate
        public let observedBytes: UInt64
        public let gapObserved: Bool
        public let sinkClosedCleanly: Bool
        public let pipeConnected: Bool
    }

    public enum Failure: Error {
        case unsafeRoot, tmuxUnavailable, socketCollision, staleSession, invalidPane, commandFailed,
             launchIndeterminate
    }

    private struct Identity: Equatable {
        let device: dev_t
        let inode: ino_t
        init(_ value: stat) {
            device = value.st_dev
            inode = value.st_ino
        }
    }

    private let lock = NSLock()
    private let root: String
    private let rootIdentity: Identity
    private let executable: String
    private let executableIdentity: Identity
    private let socket: String
    private var socketIdentity: Identity?
    private var bindings: [UUID: (generation: UInt64, binding: Binding, active: Bool)] = [:]
    private var gates: [UUID: (gate: CaptureGate, paths: [String], pipePID: Int32, limit: Int,
                               directory: Identity, segment: Identity, launchAttempted: Bool,
                               launchConfirmed: Bool)] = [:]

    public init(root: URL, tmuxExecutable: URL) throws {
        guard root.isFileURL, tmuxExecutable.isFileURL,
              root.path.hasPrefix("/"), tmuxExecutable.path.hasPrefix("/"),
              root.path == root.standardizedFileURL.path,
              Self.safeTmuxPath(root.path),
              tmuxExecutable.path == tmuxExecutable.standardizedFileURL.path,
              let rootStat = Self.fileStat(root.path),
              rootStat.st_mode & S_IFMT == S_IFDIR,
              rootStat.st_uid == getuid(), rootStat.st_mode & 0o077 == 0 else {
            throw Failure.unsafeRoot
        }
        let resolvedExecutable = tmuxExecutable.resolvingSymlinksInPath().path
        guard let binaryStat = Self.fileStat(resolvedExecutable),
              binaryStat.st_mode & S_IFMT == S_IFREG,
              binaryStat.st_mode & 0o111 != 0,
              binaryStat.st_uid == getuid() || binaryStat.st_uid == 0 else {
            throw Failure.tmuxUnavailable
        }
        self.root = root.path
        rootIdentity = Identity(rootStat)
        executable = resolvedExecutable
        executableIdentity = Identity(binaryStat)
        socket = root.appendingPathComponent("socket").path
        guard socket.utf8.count < 104 else { throw Failure.unsafeRoot }
        guard Self.fileStat(socket) == nil, errno == ENOENT else { throw Failure.socketCollision }
    }

    public func create(_ ref: SessionRef) throws -> Binding {
        lock.lock()
        defer { lock.unlock() }
        try checkRoot()
        guard ref.generation > 0 else { throw Failure.staleSession }
        guard bindings[ref.id] == nil else { throw Failure.staleSession }
        try checkSocket(allowMissing: socketIdentity == nil)
        if socketIdentity != nil {
            // ponytail: require an existing live binding; a fresh namespace is needed after the last one closes.
            var lastError: Error = Failure.staleSession
            var verified = false
            for (id, entry) in bindings where entry.active && !isLaunchIndeterminate(id) {
                do {
                    try verify(entry.binding, expectedPipePID: gates[id]?.pipePID)
                    verified = true
                    break
                } catch { lastError = error }
            }
            guard verified else { throw lastError }
        }
        let name = "te-\(ref.id.uuidString.lowercased().replacingOccurrences(of: "-", with: ""))-g\(ref.generation)"
        let output: String
        do {
            output = try run(["new-session", "-d", "-P", "-F", "#{session_id}\t#{pane_id}\t#{pane_pid}",
                              "-s", name, "/bin/sleep", "3600"])
        } catch {
            // The client may fail after the server creates its pane. Reconcile only our exact name.
            if socketIdentity == nil, let info = Self.fileStat(socket),
               info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() {
                socketIdentity = Identity(info)
            }
            cleanupCreated(name: name, expectedPair: nil)
            throw error
        }
        if socketIdentity == nil {
            guard let info = Self.fileStat(socket), info.st_mode & S_IFMT == S_IFSOCK,
                  info.st_uid == getuid() else { throw Failure.socketCollision }
            socketIdentity = Identity(info)
        }
        try checkSocket(allowMissing: false)
        guard let details = Self.parseDetails(output) else {
            cleanupCreated(name: name, expectedPair: nil)
            throw Failure.invalidPane
        }
        let binding = Binding(sessionName: name, sessionID: details.0, paneID: details.1,
                              panePID: details.2, socketPath: socket)
        do { try verify(binding) }
        catch {
            cleanupCreated(name: name, expectedPair: (details.0, details.1))
            throw error
        }
        bindings[ref.id] = (ref.generation, binding, true)
        return binding
    }

    public func revalidate(_ ref: SessionRef) throws -> Binding {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        guard !isLaunchIndeterminate(ref.id) else { throw Failure.launchIndeterminate }
        try verify(binding, expectedPipePID: gates[ref.id]?.pipePID)
        return binding
    }

    public func armCapture(_ ref: SessionRef, sinkExecutable: URL, maxBytes: Int) throws -> CaptureGate {
        lock.lock()
        defer { lock.unlock() }
        guard (1...1_048_576).contains(maxBytes), gates[ref.id] == nil else { throw Failure.staleSession }
        let binding = try activeBinding(ref)
        try verify(binding)
        let sink = try checkedExecutable(sinkExecutable)
        let directory = URL(fileURLWithPath: root)
            .appendingPathComponent("capture-\(UUID().uuidString.lowercased())").path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        guard let info = Self.fileStat(directory), info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { throw Failure.unsafeRoot }
        let paths = ["segment", "ready", "gap", "clean_eof"].map {
            URL(fileURLWithPath: directory).appendingPathComponent($0).path
        }
        let command = ([sink, "--sink"] + paths + [String(maxBytes)]).map(Self.shellQuote).joined(separator: " ")
        do {
            let start = "pipe-pane -O -t \(binding.paneID) \(Self.shellQuote("exec \(command)"))"
            let condition = "#{&&:#{==:#{session_name},\(binding.sessionName)},#{&&:#{==:#{pane_pid},\(binding.panePID)},#{==:#{pane_pipe},0}}}"
            let outcome = try run(["if-shell", "-t", binding.paneID, "-F", condition,
                                   start, "display-message -p termex_pipe_occupied"])
            guard outcome.isEmpty else { throw Failure.invalidPane }
            let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
            while DispatchTime.now().uptimeNanoseconds < deadline {
                if let readyPID = Self.privateMarkerPID(paths[1]),
                   try run(["display-message", "-p", "-t", binding.paneID, "#{pane_pipe}"]) == "1\n" {
                    try verify(binding)
                    let pipeOutput = try run(["display-message", "-p", "-t", binding.paneID,
                                              "#{pane_pipe_pid}"])
                    guard let pipePID = Int32(pipeOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
                          pipePID > 0 else { throw Failure.invalidPane }
                    if pipePID != readyPID { usleep(20_000); continue }
                    guard let segmentInfo = Self.fileStat(paths[0]),
                          segmentInfo.st_mode & S_IFMT == S_IFREG,
                          segmentInfo.st_uid == getuid(), segmentInfo.st_mode & 0o077 == 0 else {
                        throw Failure.invalidPane
                    }
                    let gate = CaptureGate(id: UUID(), sessionID: ref.id, generation: ref.generation)
                    gates[ref.id] = (gate, paths, pipePID, maxBytes, Identity(info), Identity(segmentInfo),
                                     false, false)
                    return gate
                }
                usleep(20_000)
            }
        } catch { throw error }
        // ponytail: leave an uncertain pipe for exact-session cleanup; a blind detach could close another owner's pipe.
        throw Failure.commandFailed
    }

    /// One-shot transition from the private placeholder; an uncertain launch is never retried.
    public func launchCapturedProcess(_ ref: SessionRef, gate: CaptureGate,
                                      executableURL: URL, arguments: [String]) throws -> Binding {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        guard var state = gates[ref.id], state.gate == gate, !state.launchAttempted else {
            throw Failure.staleSession
        }
        try verify(binding, expectedPipePID: state.pipePID)
        let program = try checkedExecutable(executableURL)
        // With no argument tmux executes a shell-command via /bin/sh instead of direct exec.
        guard !arguments.isEmpty,
              arguments.allSatisfy({ !$0.contains("\0") && !$0.contains("\n") && !$0.contains("\r") }) else {
            throw Failure.commandFailed
        }
        state.launchAttempted = true
        gates[ref.id] = state
        let command = ([program] + arguments).map(Self.shellQuote).joined(separator: " ")
        let condition = "#{&&:#{==:#{session_id},\(binding.sessionID)},#{&&:#{==:#{session_name},\(binding.sessionName)},#{&&:#{==:#{pane_pid},\(binding.panePID)},#{==:#{pane_pipe_pid},\(state.pipePID)}}}}"
        let start = "respawn-pane -k -t \(binding.paneID) \(command); display-message -p -t \(binding.paneID) '#{session_id}\t#{pane_id}\t#{pane_pid}'"
        let output = try run(["if-shell", "-t", binding.paneID, "-F", condition,
                              start, "display-message -p termex_stale_binding"])
        guard let details = Self.parseDetails(output), details.0 == binding.sessionID,
              details.1 == binding.paneID, details.2 != binding.panePID else {
            throw Failure.invalidPane
        }
        let updated = Binding(sessionName: binding.sessionName, sessionID: binding.sessionID,
                              paneID: binding.paneID, panePID: details.2, socketPath: binding.socketPath)
        try verify(updated, expectedPipePID: state.pipePID)
        bindings[ref.id]?.binding = updated
        gates[ref.id]?.launchConfirmed = true
        return updated
    }

    /// A metadata snapshot of one private segment, not a completeness or durable journal claim.
    public func captureObservation(_ ref: SessionRef, gate: CaptureGate) throws -> CaptureObservation {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        guard let state = gates[ref.id], state.gate == gate else { throw Failure.staleSession }
        guard !isLaunchIndeterminate(ref.id) else { throw Failure.launchIndeterminate }
        try verify(binding)
        let directory = URL(fileURLWithPath: state.paths[0]).deletingLastPathComponent().path
        guard let directoryInfo = Self.fileStat(directory),
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0,
              Identity(directoryInfo) == state.directory else { throw Failure.invalidPane }
        let fd = open(state.paths[0], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.invalidPane }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              Identity(info) == state.segment,
              info.st_size >= 0, info.st_size <= state.limit else { throw Failure.invalidPane }
        let pipeOutput = try run(["display-message", "-p", "-t", binding.paneID,
                                  "#{pane_pipe_pid}"])
        return CaptureObservation(gate: gate, observedBytes: UInt64(info.st_size),
                                  gapObserved: try Self.markerObserved(state.paths[2]),
                                  sinkClosedCleanly: try Self.markerObserved(state.paths[3]),
                                  pipeConnected: pipeOutput == "\(state.pipePID)\n")
    }

    public func close(_ ref: SessionRef) throws {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        try checkRoot()
        try checkSocket(allowMissing: false)
        // Keep identity check and kill-session in one tmux server command queue.
        let outcome = try run(["if-shell", "-t", binding.paneID, "-F",
                               closeCondition(binding, pipePID: gates[ref.id]?.pipePID),
                               "display-message -p termex_closed; kill-session -t =\(binding.sessionName)",
                               "display-message -p termex_stale_binding"])
        guard outcome == "termex_closed\n" else { throw Failure.invalidPane }
        try checkSocket(allowMissing: false)
        bindings[ref.id]?.active = false
        gates.removeValue(forKey: ref.id)
    }

    private func activeBinding(_ ref: SessionRef) throws -> Binding {
        guard let entry = bindings[ref.id], entry.active, entry.generation == ref.generation else {
            throw Failure.staleSession
        }
        return entry.binding
    }

    private func isLaunchIndeterminate(_ id: UUID) -> Bool {
        guard let state = gates[id] else { return false }
        return state.launchAttempted && !state.launchConfirmed
    }

    private func verify(_ binding: Binding, expectedPipePID: Int32? = nil) throws {
        try checkRoot()
        try checkSocket(allowMissing: false)
        let format = "#{session_id}\t#{pane_id}\t#{pane_pid}\t#{pane_dead}" +
            (expectedPipePID == nil ? "" : "\t#{pane_pipe_pid}")
        let output = try run(["list-panes", "-t", "=\(binding.sessionName)",
                              "-F", format])
        let expected = "\(binding.sessionID)\t\(binding.paneID)\t\(binding.panePID)\t0" +
            (expectedPipePID.map { "\t\($0)" } ?? "") + "\n"
        guard output == expected else {
            throw Failure.invalidPane
        }
        try checkSocket(allowMissing: false)
    }

    private func cleanupCreated(name: String, expectedPair: (String, String)?) {
        guard (try? checkRoot()) != nil, (try? checkSocket(allowMissing: false)) != nil,
              let output = try? run(["list-panes", "-t", "=\(name)",
                                     "-F", "#{session_id}\t#{pane_id}\t#{pane_pid}"]),
              let details = Self.parseDetails(output),
              expectedPair == nil || (details.0 == expectedPair?.0 && details.1 == expectedPair?.1) else {
            return
        }
        _ = try? run(["kill-session", "-t", details.0])
    }

    private func checkRoot() throws {
        guard let info = Self.fileStat(root), info.st_mode & S_IFMT == S_IFDIR,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              Identity(info) == rootIdentity else { throw Failure.unsafeRoot }
    }

    private func checkSocket(allowMissing: Bool) throws {
        guard let info = Self.fileStat(socket) else {
            guard allowMissing, errno == ENOENT else { throw Failure.socketCollision }
            return
        }
        guard let socketIdentity, info.st_mode & S_IFMT == S_IFSOCK,
              info.st_uid == getuid(), Identity(info) == socketIdentity else {
            throw Failure.socketCollision
        }
    }

    private static func fileStat(_ path: String) -> stat? {
        var info = stat()
        return lstat(path, &info) == 0 ? info : nil
    }

    private func checkedExecutable(_ url: URL) throws -> String {
        guard url.isFileURL, url.path.hasPrefix("/"), url.path == url.standardizedFileURL.path,
              Self.safeTmuxPath(url.path) else {
            throw Failure.tmuxUnavailable
        }
        let path = url.resolvingSymlinksInPath().path
        guard Self.safeTmuxPath(path), let info = Self.fileStat(path), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o111 != 0, info.st_uid == getuid() || info.st_uid == 0 else {
            throw Failure.tmuxUnavailable
        }
        return path
    }

    private static func privateMarkerPID(_ path: String) -> Int32? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 32)
        let count = read(fd, &bytes, bytes.count)
        guard count > 0, count < bytes.count,
              let pid = Int32(String(decoding: bytes.prefix(count), as: UTF8.self)), pid > 0 else { return nil }
        return pid
    }

    private static func markerObserved(_ path: String) throws -> Bool {
        guard let info = fileStat(path) else {
            guard errno == ENOENT else { throw Failure.invalidPane }
            return false
        }
        guard info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else { throw Failure.invalidPane }
        return true
    }

    private static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func safeTmuxPath(_ path: String) -> Bool {
        !path.contains("#") && !path.contains("\n") && !path.contains("\r")
    }

    private static func parseDetails(_ text: String) -> (String, String, Int32)? {
        let parts = text.trimmingCharacters(in: .newlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].first == "$", parts[1].first == "%",
              parts[0].count > 1, parts[1].count > 1,
              parts[0].dropFirst().allSatisfy(\.isNumber),
              parts[1].dropFirst().allSatisfy(\.isNumber),
              let pid = Int32(parts[2]), pid > 0 else { return nil }
        return (String(parts[0]), String(parts[1]), pid)
    }

    private func closeCondition(_ binding: Binding, pipePID: Int32?) -> String {
        let pipeMatch = pipePID.map { "#{==:#{pane_pipe_pid},\($0)}" } ?? "1"
        return "#{&&:#{==:#{session_id},\(binding.sessionID)},#{&&:#{==:#{session_name},\(binding.sessionName)},#{&&:#{==:#{pane_pid},\(binding.panePID)},\(pipeMatch)}}}"
    }

    private func run(_ arguments: [String]) throws -> String {
        guard let info = Self.fileStat(executable), info.st_mode & S_IFMT == S_IFREG,
              Identity(info) == executableIdentity else { throw Failure.tmuxUnavailable }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-S", socket, "-f", "/dev/null"] + arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.tmuxUnavailable }
        stdout.fileHandleForWriting.closeFile()
        let fd = stdout.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        var bytes: [UInt8] = []
        var reachedEOF = false
        while DispatchTime.now().uptimeNanoseconds < deadline {
            var chunk = [UInt8](repeating: 0, count: 1024)
            let count = read(fd, &chunk, chunk.count)
            if count > 0 { bytes.append(contentsOf: chunk.prefix(count)) }
            if count == 0 { reachedEOF = true }
            if bytes.count > 4096 { break }
            if !process.isRunning && reachedEOF { break }
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            usleep(100_000)
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard reachedEOF, process.terminationStatus == 0,
              let text = String(data: Data(bytes), encoding: .utf8) else {
            throw Failure.commandFailed
        }
        return text
    }
}
