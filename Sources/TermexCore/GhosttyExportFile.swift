import Darwin
import Foundation

/// Accept only a newly created Ghostty screen file inside this user's private temp directory.
public enum GhosttyExportFile {
    public enum Failure: Error { case invalidPath, invalidFile, tooLarge, system(Int32) }
    public static let maxBytes = 16 * 1024

    public static func read(_ path: String, in temporaryRoot: String,
                            createdAfter start: Date) throws -> Data {
        let root = temporaryRoot.hasSuffix("/") ? String(temporaryRoot.dropLast()) : temporaryRoot
        guard let directoryName = directoryName(for: path, in: root) else { throw Failure.invalidPath }

        let rootFD = open(root, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw Failure.system(errno) }
        defer { Darwin.close(rootFD) }
        var rootInfo = stat()
        guard fstat(rootFD, &rootInfo) == 0, rootInfo.st_uid == geteuid(),
              rootInfo.st_mode & S_IFMT == S_IFDIR, rootInfo.st_mode & 0o077 == 0 else {
            throw Failure.invalidPath
        }
        let dirFD = openat(rootFD, directoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw Failure.invalidPath }
        defer { Darwin.close(dirFD) }
        var directory = stat()
        guard fstat(dirFD, &directory) == 0, directory.st_uid == geteuid(),
              directory.st_mode & S_IFMT == S_IFDIR,
              directory.st_mode & 0o022 == 0,
              born(directory, after: start) else {
            throw Failure.invalidPath
        }

        let fd = openat(dirFD, "screen.txt", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.invalidFile }
        defer { Darwin.close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_uid == geteuid(),
              before.st_mode & S_IFMT == S_IFREG, before.st_mode & 0o077 == 0,
              before.st_nlink == 1, before.st_size >= 0,
              before.st_size <= maxBytes,
              born(before, after: start) else {
            throw Failure.invalidFile
        }
        var data = Data(count: Int(before.st_size))
        let count = data.count
        try data.withUnsafeMutableBytes { bytes in
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, bytes.baseAddress!.advanced(by: offset), count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.invalidFile }
                offset += n
            }
        }
        var after = stat()
        guard fstat(fd, &after) == 0,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else {
            throw Failure.invalidFile
        }
        return data
    }

    public static func matchesExpectedPath(_ path: String, in temporaryRoot: String) -> Bool {
        directoryName(for: path, in: temporaryRoot) != nil
    }

    private static func directoryName(for path: String, in temporaryRoot: String) -> String? {
        let root = temporaryRoot.hasSuffix("/") ? String(temporaryRoot.dropLast()) : temporaryRoot
        var prefix = root
        if !path.hasPrefix(root + "/") {
            guard let canonical = realpath(root, nil) else { return nil }
            defer { free(canonical) }
            prefix = String(cString: canonical)
            guard path.hasPrefix(prefix + "/") else { return nil }
        }
        let parts = path.dropFirst(prefix.count + 1).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[1] == "screen.txt", parts[0].utf8.count == 22,
              parts[0].utf8.allSatisfy({
                  (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 95
              }) else { return nil }
        return String(parts[0])
    }

    private static func born(_ info: stat, after start: Date) -> Bool {
        Double(info.st_birthtimespec.tv_sec) + Double(info.st_birthtimespec.tv_nsec) / 1_000_000_000
            >= start.timeIntervalSince1970 - 0.25
    }
}
