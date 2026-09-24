import AppKit
import Foundation
import TermexCore

final class Authorization: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true

    func check() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }

    func revoke() {
        lock.lock()
        allowed = false
        lock.unlock()
    }
}

final class Outcome: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<GhosttyScreenExport.Snapshot, Error>?

    func set(_ value: Result<GhosttyScreenExport.Snapshot, Error>) {
        lock.lock()
        result = value
        lock.unlock()
    }

    func get() -> Result<GhosttyScreenExport.Snapshot, Error> {
        lock.lock()
        defer { lock.unlock() }
        return result!
    }
}

// Access from the worker ends before the main thread checks the named pasteboard.
final class NamedBoard: @unchecked Sendable {
    let value = NSPasteboard(name: NSPasteboard.Name("termex-race-\(UUID().uuidString)"))
}

nonisolated func run() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("termex-race-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let board = NamedBoard()
    defer { board.value.releaseGlobally() }
    board.value.clearContents()
    precondition(board.value.setString("original", forType: .string))
    let directory = root.appendingPathComponent("ABCDEFGHIJKLMNOPQRSTUV")
    let path = directory.appendingPathComponent("screen.txt").path
    let authorization = Authorization()
    let entered = DispatchSemaphore(value: 0)
    let resume = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    let outcome = Outcome()

    DispatchQueue.global().async {
        let result = Result {
            try GhosttyScreenExport.readForExport(appInstanceID: "synthetic-revoke", board: board.value,
                                                 root: root.path, authorized: authorization.check) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o755])
                board.value.clearContents()
                precondition(board.value.setString(path, forType: .string))
                entered.signal()
                precondition(resume.wait(timeout: .now() + 5) == .success)
            }
        }
        outcome.set(result)
        finished.signal()
    }
    precondition(entered.wait(timeout: .now() + 5) == .success)
    authorization.revoke()
    resume.signal()
    precondition(finished.wait(timeout: .now() + 5) == .success)
    switch outcome.get() {
    case .failure(GhosttyScreenExport.Failure.unavailable): break
    default: fatalError("revoked export returned unexpected result")
    }
    precondition(board.value.string(forType: .string) == "original")

    // The installed Ghostty rate cap is global even for different app instances.
    Thread.sleep(forTimeInterval: 5.1)
    let writerDirectory = root.appendingPathComponent("ZYXWVUTSRQPONMLKJIHGFE")
    let writerPath = writerDirectory.appendingPathComponent("screen.txt").path
    do {
        _ = try GhosttyScreenExport.readForExport(appInstanceID: "synthetic-writer", board: board.value,
                                                 root: root.path, authorized: { true }) {
            try FileManager.default.createDirectory(at: writerDirectory, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o755])
            board.value.clearContents()
            precondition(board.value.setString(writerPath, forType: .string))
            board.value.clearContents()
            precondition(board.value.setString("writer", forType: .string))
        }
        fatalError("concurrent writer conflict was accepted")
    } catch GhosttyScreenExport.Failure.clipboardConflict {
        precondition(board.value.string(forType: .string) == "writer")
    }
    print("revoked_during_export=PASS writer_conflict=PASS")
}

try run()
