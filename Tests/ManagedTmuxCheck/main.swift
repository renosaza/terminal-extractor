import Foundation
import TermexCore

let root = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("te-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }

let executable = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TERMEX_TMUX_BIN"]
                     ?? "/opt/homebrew/bin/tmux")
let manager = try ManagedTmux(root: root, tmuxExecutable: executable)
do {
    _ = try ManagedTmux(root: root, tmuxExecutable: root.appendingPathComponent("missing-tmux"))
    fatalError("missing tmux executable was accepted")
} catch ManagedTmux.Failure.tmuxUnavailable {}
let first = SessionRef(id: UUID(), generation: 1)
let second = SessionRef(id: UUID(), generation: 1)
defer { try? manager.close(first); try? manager.close(second) }

let firstBinding = try manager.create(first)
let secondBinding = try manager.create(second)
do {
    _ = try ManagedTmux(root: root, tmuxExecutable: executable)
    fatalError("existing private socket was adopted")
} catch ManagedTmux.Failure.socketCollision {}
precondition(firstBinding.socketPath == secondBinding.socketPath)
precondition(firstBinding.sessionID != secondBinding.sessionID)
precondition(firstBinding.paneID != secondBinding.paneID)

func panePID(_ binding: ManagedTmux.Binding) throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["-S", binding.socketPath, "display-message", "-p",
                         "-t", binding.paneID, "#{pane_pid}"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let pid = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), Int(pid) != nil else {
        throw CocoaError(.fileReadUnknown)
    }
    return pid
}

let secondPID = try panePID(secondBinding)
let firstVerified = try manager.revalidate(first)
let secondVerified = try manager.revalidate(second)
precondition(firstVerified.paneID == firstBinding.paneID)
precondition(secondVerified.paneID == secondBinding.paneID)
do {
    _ = try manager.revalidate(SessionRef(id: first.id, generation: 2))
    fatalError("wrong generation was accepted")
} catch ManagedTmux.Failure.staleSession {}

try manager.close(first)
do {
    _ = try manager.revalidate(first)
    fatalError("closed session remained available")
} catch ManagedTmux.Failure.staleSession {}
let survivor = try manager.revalidate(second)
let survivorPID = try panePID(secondBinding)
precondition(survivor.paneID == secondBinding.paneID)
precondition(survivorPID == secondPID)
try manager.close(second)

print("private_namespace=PASS exact_binding=PASS stale_generation=PASS isolated_close=PASS missing_tmux=PASS socket_collision=PASS")
