import Darwin
import Foundation
import TermexCore

let root = FileManager.default.temporaryDirectory.appendingPathComponent("termex-export-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }
let start = Date()
let directory = root.appendingPathComponent("ABCDEFGHIJKLMNOPQRSTUV")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
let file = directory.appendingPathComponent("screen.txt")
try Data("selected screen".utf8).write(to: file)
assert(chmod(file.path, 0o600) == 0)
let contents = try GhosttyExportFile.read(file.path, in: root.path, createdAfter: start)
assert(contents == Data("selected screen".utf8))

func rejected(_ path: String, since: Date = start) {
    do {
        _ = try GhosttyExportFile.read(path, in: root.path, createdAfter: since)
        fatalError("unsafe export path was accepted")
    } catch GhosttyExportFile.Failure.invalidPath,
            GhosttyExportFile.Failure.invalidFile,
            GhosttyExportFile.Failure.tooLarge {}
    catch { fatalError("unexpected error: \(error)") }
}

rejected("/etc/passwd")
rejected(directory.appendingPathComponent("../../screen.txt").path)
rejected(file.path, since: Date(timeIntervalSinceNow: 30))
try FileManager.default.removeItem(at: file)
try FileManager.default.createSymbolicLink(at: file, withDestinationURL: URL(fileURLWithPath: "/etc/passwd"))
rejected(file.path)
try FileManager.default.removeItem(at: file)
let fd = open(file.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
assert(fd >= 0)
assert(ftruncate(fd, off_t(GhosttyExportFile.maxBytes + 1)) == 0)
Darwin.close(fd)
rejected(file.path)
print("fresh_private_file=PASS path_escape=PASS stale=PASS symlink=PASS oversize=PASS")
