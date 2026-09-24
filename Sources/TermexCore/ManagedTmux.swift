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

    public struct ClosedCaptureObservation: Equatable, Sendable {
        public let observedBytes: UInt64
        public let gapObserved: Bool
    }

    public struct ScreenMetadata: Equatable, Sendable {
        public let columns: Int
        public let rows: Int
        public let cursorX: Int
        public let cursorY: Int
        public let alternateScreen: Bool
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

    private struct ProcessIdentity: Equatable {
        let pid: Int32
        let startedSeconds: UInt64
        let startedMicroseconds: UInt64
    }

    private let lock = NSLock()
    private let root: String
    private let rootIdentity: Identity
    private let executable: String
    private let executableIdentity: Identity
    private let socket: String
    private var socketIdentity: Identity?
    private var bindings: [UUID: (generation: UInt64, binding: Binding, active: Bool)] = [:]
    private var gates: [UUID: (gate: CaptureGate, paths: [String], pipe: ProcessIdentity, limit: Int,
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
                    try verify(entry.binding, expectedPipe: gates[id]?.pipe)
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
        try verify(binding, expectedPipe: gates[ref.id]?.pipe)
        return binding
    }

    /// Point-in-time tmux grid metadata; no screen text or history leaves this API.
    public func screenMetadata(_ ref: SessionRef) throws -> ScreenMetadata {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        guard !isLaunchIndeterminate(ref.id) else { throw Failure.launchIndeterminate }
        let pipe = gates[ref.id]?.pipe
        try verify(binding, expectedPipe: pipe)
        let format = "#{session_id}\t#{pane_id}\t#{pane_pid}\t#{pane_width}\t#{pane_height}\t#{cursor_x}\t#{cursor_y}\t#{alternate_on}"
        let output = try run(["display-message", "-p", "-t", binding.paneID, format])
        let fields = output.trimmingCharacters(in: .newlines)
            .split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count == 8, fields[0] == binding.sessionID, fields[1] == binding.paneID,
              fields[2] == String(binding.panePID),
              let columns = Int(fields[3]), columns > 0, let rows = Int(fields[4]), rows > 0,
              let cursorX = Int(fields[5]), cursorX >= 0,
              let cursorY = Int(fields[6]), cursorY >= 0,
              fields[7] == "0" || fields[7] == "1" else { throw Failure.invalidPane }
        try verify(binding, expectedPipe: pipe)
        return ScreenMetadata(columns: columns, rows: rows, cursorX: cursorX, cursorY: cursorY,
                              alternateScreen: fields[7] == "1")
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
        let paths = ["segment", "ready", "gap", "clean_eof", "closed"].map {
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
                if let readyPipe = Self.privateMarkerIdentity(paths[1]),
                   try run(["display-message", "-p", "-t", binding.paneID, "#{pane_pipe}"]) == "1\n" {
                    try verify(binding)
                    let pipeOutput = try run(["display-message", "-p", "-t", binding.paneID,
                                              "#{pane_pipe_pid}"])
                    guard let pipePID = Int32(pipeOutput.trimmingCharacters(in: .whitespacesAndNewlines)),
                          pipePID > 0 else { throw Failure.invalidPane }
                    if pipePID != readyPipe.pid || Self.processIdentity(pipePID) != readyPipe {
                        usleep(20_000)
                        continue
                    }
                    guard let segmentInfo = Self.fileStat(paths[0]),
                          segmentInfo.st_mode & S_IFMT == S_IFREG,
                          segmentInfo.st_uid == getuid(), segmentInfo.st_mode & 0o077 == 0 else {
                        throw Failure.invalidPane
                    }
                    let gate = CaptureGate(id: UUID(), sessionID: ref.id, generation: ref.generation)
                    gates[ref.id] = (gate, paths, readyPipe, maxBytes, Identity(info), Identity(segmentInfo),
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
        try verify(binding, expectedPipe: state.pipe)
        let program = try checkedExecutable(executableURL)
        // With no argument tmux executes a shell-command via /bin/sh instead of direct exec.
        guard !arguments.isEmpty,
              arguments.allSatisfy({ !$0.contains("\0") && !$0.contains("\n") && !$0.contains("\r") }) else {
            throw Failure.commandFailed
        }
        state.launchAttempted = true
        gates[ref.id] = state
        let command = ([program] + arguments).map(Self.shellQuote).joined(separator: " ")
        let condition = "#{&&:#{==:#{session_id},\(binding.sessionID)},#{&&:#{==:#{session_name},\(binding.sessionName)},#{&&:#{==:#{pane_pid},\(binding.panePID)},#{==:#{pane_pipe_pid},\(state.pipe.pid)}}}}"
        let start = "respawn-pane -k -t \(binding.paneID) \(command); display-message -p -t \(binding.paneID) '#{session_id}\t#{pane_id}\t#{pane_pid}'"
        let output = try run(["if-shell", "-t", binding.paneID, "-F", condition,
                              start, "display-message -p termex_stale_binding"])
        guard let details = Self.parseDetails(output), details.0 == binding.sessionID,
              details.1 == binding.paneID, details.2 != binding.panePID else {
            throw Failure.invalidPane
        }
        let updated = Binding(sessionName: binding.sessionName, sessionID: binding.sessionID,
                              paneID: binding.paneID, panePID: details.2, socketPath: binding.socketPath)
        try verify(updated, expectedPipe: state.pipe)
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
                                  pipeConnected: pipeOutput == "\(state.pipe.pid)\n" &&
                                                 Self.processIdentity(state.pipe.pid) == state.pipe)
    }

    /// Post-close sink metadata only; nil means no validated close record, not an empty segment.
    public func closedCaptureObservation(_ ref: SessionRef, gate: CaptureGate) throws -> ClosedCaptureObservation? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = bindings[ref.id], entry.generation == ref.generation, !entry.active,
              let state = gates[ref.id], state.gate == gate else { throw Failure.staleSession }
        try checkRoot()
        let directory = URL(fileURLWithPath: state.paths[0]).deletingLastPathComponent().path
        guard let directoryInfo = Self.fileStat(directory),
              directoryInfo.st_mode & S_IFMT == S_IFDIR, directoryInfo.st_uid == getuid(),
              directoryInfo.st_mode & 0o077 == 0,
              Identity(directoryInfo) == state.directory else { throw Failure.invalidPane }
        let segmentFD = open(state.paths[0], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard segmentFD >= 0 else { throw Failure.invalidPane }
        defer { _ = Darwin.close(segmentFD) }
        let recordFD = open(state.paths[4], O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard recordFD >= 0 else {
            if errno == ENOENT { return nil }
            throw Failure.invalidPane
        }
        defer { _ = Darwin.close(recordFD) }
        var recordInfo = stat()
        guard fstat(recordFD, &recordInfo) == 0,
              recordInfo.st_mode & S_IFMT == S_IFREG, recordInfo.st_uid == getuid(),
              recordInfo.st_mode & 0o077 == 0, recordInfo.st_size > 0,
              recordInfo.st_size < 64 else { throw Failure.invalidPane }
        var bytes = [UInt8](repeating: 0, count: 64)
        guard read(recordFD, &bytes, Int(recordInfo.st_size)) == recordInfo.st_size,
              let record = String(bytes: bytes.prefix(Int(recordInfo.st_size)), encoding: .utf8) else {
            throw Failure.invalidPane
        }
        var segmentInfo = stat()
        guard fstat(segmentFD, &segmentInfo) == 0,
              segmentInfo.st_mode & S_IFMT == S_IFREG, segmentInfo.st_uid == getuid(),
              segmentInfo.st_mode & 0o077 == 0, Identity(segmentInfo) == state.segment,
              segmentInfo.st_size >= 0, segmentInfo.st_size <= state.limit else { throw Failure.invalidPane }
        let size = UInt64(segmentInfo.st_size)
        let gap: Bool
        if record == "\(size) clean" { gap = false }
        else if record == "\(size) gapped" { gap = true }
        else { throw Failure.invalidPane }
        let gapMarker = try Self.markerObserved(state.paths[2])
        let cleanMarker = try Self.markerObserved(state.paths[3])
        guard gap ? !cleanMarker : !gapMarker else { throw Failure.invalidPane }
        guard gap ? gapMarker : cleanMarker else { return nil }
        return ClosedCaptureObservation(observedBytes: size, gapObserved: gap)
    }

    public func close(_ ref: SessionRef) throws {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        try checkRoot()
        try checkSocket(allowMissing: false)
        if let pipe = gates[ref.id]?.pipe, Self.processIdentity(pipe.pid) != pipe {
            throw Failure.invalidPane
        }
        // Keep identity check and kill-session in one tmux server command queue.
        let outcome = try run(["if-shell", "-t", binding.paneID, "-F",
                               closeCondition(binding, pipePID: gates[ref.id]?.pipe.pid),
                               "display-message -p termex_closed; kill-session -t =\(binding.sessionName)",
                               "display-message -p termex_stale_binding"])
        guard outcome == "termex_closed\n" else { throw Failure.invalidPane }
        try checkSocket(allowMissing: false)
        bindings[ref.id]?.active = false
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

    private func verify(_ binding: Binding, expectedPipe: ProcessIdentity? = nil) throws {
        try checkRoot()
        try checkSocket(allowMissing: false)
        let format = "#{session_id}\t#{pane_id}\t#{pane_pid}\t#{pane_dead}" +
            (expectedPipe == nil ? "" : "\t#{pane_pipe_pid}")
        let output = try run(["list-panes", "-t", "=\(binding.sessionName)",
                              "-F", format])
        let expected = "\(binding.sessionID)\t\(binding.paneID)\t\(binding.panePID)\t0" +
            (expectedPipe.map { "\t\($0.pid)" } ?? "") + "\n"
        guard output == expected else {
            throw Failure.invalidPane
        }
        // tmux can retain pane_pipe_pid after exit; start identity also rejects PID reuse.
        if let expectedPipe, Self.processIdentity(expectedPipe.pid) != expectedPipe {
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

    private static func processIdentity(_ pid: Int32) -> ProcessIdentity? {
        var value = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard pid > 0, proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &value, size) == size,
              value.pbi_pid == UInt32(pid), value.pbi_uid == getuid(),
              value.pbi_status != UInt32(SZOMB), value.pbi_start_tvsec > 0,
              value.pbi_start_tvusec < 1_000_000 else { return nil }
        return ProcessIdentity(pid: pid, startedSeconds: value.pbi_start_tvsec,
                               startedMicroseconds: value.pbi_start_tvusec)
    }

    private static func privateMarkerIdentity(_ path: String) -> ProcessIdentity? {
        let fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid(), info.st_mode & 0o077 == 0,
              info.st_size > 0, info.st_size < 80 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 80)
        let count = read(fd, &bytes, bytes.count)
        guard count == info.st_size,
              let text = String(bytes: bytes.prefix(count), encoding: .utf8) else { return nil }
        let fields = text.split(separator: " ", omittingEmptySubsequences: false)
        guard fields.count == 3, let pid = Int32(fields[0]), pid > 0,
              let seconds = UInt64(fields[1]), seconds > 0,
              let microseconds = UInt64(fields[2]), microseconds < 1_000_000 else { return nil }
        return ProcessIdentity(pid: pid, startedSeconds: seconds,
                               startedMicroseconds: microseconds)
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
