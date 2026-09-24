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

    public enum Failure: Error {
        case unsafeRoot, tmuxUnavailable, socketCollision, staleSession, invalidPane, commandFailed
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

    public init(root: URL, tmuxExecutable: URL) throws {
        guard root.isFileURL, tmuxExecutable.isFileURL,
              root.path.hasPrefix("/"), tmuxExecutable.path.hasPrefix("/"),
              root.path == root.standardizedFileURL.path,
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
            guard let existing = bindings.values.first(where: { $0.active }) else { throw Failure.staleSession }
            try verify(existing.binding)
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
        try verify(binding)
        return binding
    }

    public func close(_ ref: SessionRef) throws {
        lock.lock()
        defer { lock.unlock() }
        let binding = try activeBinding(ref)
        try verify(binding)
        _ = try run(["kill-session", "-t", binding.sessionID])
        bindings[ref.id]?.active = false
    }

    private func activeBinding(_ ref: SessionRef) throws -> Binding {
        guard let entry = bindings[ref.id], entry.active, entry.generation == ref.generation else {
            throw Failure.staleSession
        }
        return entry.binding
    }

    private func verify(_ binding: Binding) throws {
        try checkRoot()
        try checkSocket(allowMissing: false)
        let output = try run(["list-panes", "-t", "=\(binding.sessionName)",
                              "-F", "#{session_id}\t#{pane_id}\t#{pane_pid}\t#{pane_dead}"])
        guard output == "\(binding.sessionID)\t\(binding.paneID)\t\(binding.panePID)\t0\n" else {
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

    private static func parseDetails(_ text: String) -> (String, String, Int32)? {
        let parts = text.trimmingCharacters(in: .newlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].first == "$", parts[1].first == "%",
              parts[0].count > 1, parts[1].count > 1,
              parts[0].dropFirst().allSatisfy(\.isNumber),
              parts[1].dropFirst().allSatisfy(\.isNumber),
              let pid = Int32(parts[2]), pid > 0 else { return nil }
        return (String(parts[0]), String(parts[1]), pid)
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
