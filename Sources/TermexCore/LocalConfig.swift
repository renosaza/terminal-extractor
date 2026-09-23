import Darwin
import Foundation

public struct LocalConfig: Codable, Equatable {
    public enum TerminalApp: String, Codable { case terminal, ghostty }
    public enum AttachPolicy: String, Codable { case existing, new, ask }
    public enum Backend: String, Codable { case managed_tmux, native }
    public enum Representation: String, Codable { case compact, exact }
    public enum Compressor: String, Codable { case builtin }

    public struct Recording: Codable, Equatable {
        public var consentRequired = true
        public var sessionLimitBytes = 268_435_456
        public var totalLimitBytes = 2_147_483_648
        public var retentionDays = 7
    }

    public struct Output: Codable, Equatable {
        public var defaultRepresentation: Representation = .compact
        public var targetEstimatedTokens = 4_000
        public var hardMaxBytes = 65_536
        public var compressor: Compressor = .builtin
        public var headroomEnabled = false
    }

    public struct Execution: Codable, Equatable {
        public var defaultWaitMs = 1_000
        public var maxWaitMs = 20_000
        public var busyQueueEnabled = false
    }

    public var schemaVersion = 1
    public var terminalApp: TerminalApp = .terminal
    public var allowedApps: [TerminalApp] = [.terminal, .ghostty]
    public var attachPolicy: AttachPolicy = .ask
    public var newSessionBackend: Backend = .managed_tmux
    public var shellIntegration = "zsh_opt_in"
    public var nativeGhosttyClipboardExport = false
    public var recording = Recording()
    public var output = Output()
    public var execution = Execution()

    public init() {}

    public enum Failure: Error {
        case invalidConfig, invalidEnvironment, invalidFile, tooLarge, system(Int32)
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TerminalExtractor/config.json")
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private static func merge(_ supplied: [String: Any], into base: inout [String: Any]) throws {
        for (key, value) in supplied {
            guard let existing = base[key] else { throw Failure.invalidConfig }
            if var nested = existing as? [String: Any], let nestedValue = value as? [String: Any] {
                try merge(nestedValue, into: &nested)
                base[key] = nested
            } else {
                base[key] = value
            }
        }
    }

    private func validate() throws {
        guard schemaVersion == 1,
              !allowedApps.isEmpty, Set(allowedApps.map(\.rawValue)).count == allowedApps.count,
              allowedApps.contains(terminalApp), shellIntegration == "zsh_opt_in",
              recording.consentRequired,
              recording.sessionLimitBytes > 0,
              recording.totalLimitBytes >= recording.sessionLimitBytes,
              recording.retentionDays >= 0,
              output.targetEstimatedTokens > 0,
              output.hardMaxBytes > 0,
              execution.defaultWaitMs >= 0,
              execution.maxWaitMs >= execution.defaultWaitMs,
              execution.maxWaitMs <= 20_000 else { throw Failure.invalidConfig }
    }

    public static func decode(_ data: Data) throws -> LocalConfig {
        guard data.count <= 64 * 1024,
              let supplied = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              supplied["schema_version"] != nil else { throw Failure.invalidConfig }
        var base = try JSONSerialization.jsonObject(with: encoder().encode(LocalConfig())) as! [String: Any]
        try merge(supplied, into: &base)
        let combined = try JSONSerialization.data(withJSONObject: base)
        let config = try decoder().decode(LocalConfig.self, from: combined)
        try config.validate()
        return config
    }

    public func applyingPreferences(_ environment: [String: String]) throws -> LocalConfig {
        guard environment.keys.filter({ $0.hasPrefix("TERMEX_") }).allSatisfy({
            ["TERMEX_TERMINAL", "TERMEX_ATTACH_POLICY", "TERMEX_NEW_BACKEND"].contains($0)
        }) else { throw Failure.invalidEnvironment }
        var selected = self
        if let value = environment["TERMEX_TERMINAL"] {
            guard let app = TerminalApp(rawValue: value), allowedApps.contains(app) else {
                throw Failure.invalidEnvironment
            }
            selected.terminalApp = app
        }
        if let value = environment["TERMEX_ATTACH_POLICY"] {
            guard let policy = AttachPolicy(rawValue: value) else { throw Failure.invalidEnvironment }
            selected.attachPolicy = policy
        }
        if let value = environment["TERMEX_NEW_BACKEND"] {
            guard let backend = Backend(rawValue: value) else { throw Failure.invalidEnvironment }
            selected.newSessionBackend = backend
        }
        try selected.validate()
        return selected
    }

    public static func load(at url: URL = defaultURL, requireExisting: Bool = false) throws -> LocalConfig {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if fd < 0 && errno == ENOENT {
            if requireExisting { throw Failure.invalidFile }
            return LocalConfig()
        }
        guard fd >= 0 else { throw Failure.system(errno) }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0,
              info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
              info.st_mode & 0o077 == 0 else { throw Failure.invalidFile }
        guard info.st_size <= 64 * 1024 else { throw Failure.tooLarge }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        var data = Data()
        while let part = try handle.read(upToCount: 64 * 1024 + 1 - data.count), !part.isEmpty {
            data.append(part)
            if data.count > 64 * 1024 { throw Failure.tooLarge }
        }
        guard data.count <= 64 * 1024 else { throw Failure.tooLarge }
        return try decode(data)
    }

    public func save(at url: URL = defaultURL) throws {
        try validate()
        let directory = url.deletingLastPathComponent().path
        if mkdir(directory, 0o700) != 0 && errno != EEXIST { throw Failure.system(errno) }
        var info = stat()
        guard lstat(directory, &info) == 0,
              info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o077 == 0 else { throw Failure.invalidFile }
        if lstat(url.path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFREG,
                  info.st_mode & 0o077 == 0 else { throw Failure.invalidFile }
        } else if errno != ENOENT { throw Failure.system(errno) }

        let data = try Self.encoder().encode(self)
        guard data.count <= 64 * 1024 else { throw Failure.tooLarge }
        let temporary = directory + "/.config-" + UUID().uuidString
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.system(errno) }
        var completed = false
        defer { Darwin.close(fd); if !completed { unlink(temporary) } }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < data.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), data.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.system(errno) }
                offset += n
            }
        }
        guard fsync(fd) == 0, rename(temporary, url.path) == 0 else { throw Failure.system(errno) }
        completed = true
        // ponytail: local config writes are last-writer-wins; serialize when multiple UI writers exist.
    }
}
