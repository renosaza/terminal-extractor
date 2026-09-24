import Darwin
import Foundation

enum SinkFailure: Error { case invalidArguments, unsafePath, createFailed }

func info(_ path: String) -> stat? {
    var value = stat()
    return lstat(path, &value) == 0 ? value : nil
}

func create(_ path: String) throws {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw SinkFailure.createFailed }
    close(fd)
}

func validate(_ paths: [String]) throws {
    guard paths.count == 4, let root = paths.first.map({ URL(fileURLWithPath: $0).deletingLastPathComponent().path }),
          let rootInfo = info(root), rootInfo.st_mode & S_IFMT == S_IFDIR,
          rootInfo.st_uid == getuid(), rootInfo.st_mode & 0o077 == 0,
          paths.allSatisfy({ URL(fileURLWithPath: $0).isFileURL && URL(fileURLWithPath: $0).path.hasPrefix("/") && URL(fileURLWithPath: $0).deletingLastPathComponent().path == root }) else {
        throw SinkFailure.unsafePath
    }
}

func sink(paths: [String], limit: Int) throws {
    try validate(paths)
    guard (1...1_048_576).contains(limit) else { throw SinkFailure.invalidArguments }
    let segment = paths[0]
    let fd = open(segment, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw SinkFailure.createFailed }
    defer { close(fd) }
    try create(paths[1])
    var written = 0
    var lost = false
    var buffer = [UInt8](repeating: 0, count: 8192)
    while true {
        let count = read(STDIN_FILENO, &buffer, buffer.count)
        guard count >= 0 else { throw SinkFailure.createFailed }
        guard count > 0 else { break }
        var offset = 0
        while !lost && offset < count {
            let remaining = limit - written
            guard remaining > 0 else { lost = true; break }
            let amount = min(remaining, count - offset)
            let result = buffer.withUnsafeBytes { write(fd, $0.baseAddress!.advanced(by: offset), amount) }
            guard result > 0 else { lost = true; break }
            written += result
            offset += result
        }
        if offset < count { lost = true }
        if lost { try? create(paths[2]) }
    }
    if !lost { try create(paths[3]) }
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard arguments.count == 6, arguments[0] == "--sink", let limit = Int(arguments[5]) else {
        throw SinkFailure.invalidArguments
    }
    try sink(paths: Array(arguments[1...4]), limit: limit)
} catch {
    exit(1)
}
