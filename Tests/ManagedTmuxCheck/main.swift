import Foundation
import TermexCore

struct CheckFailure: Error { let name: String }
func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw CheckFailure(name: name) }
}

let root = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("te-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }

let executable = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TERMEX_TMUX_BIN"]
                     ?? "/opt/homebrew/bin/tmux")
let manager = try ManagedTmux(root: root, tmuxExecutable: executable)
defer {
    let cleanup = Process()
    cleanup.executableURL = executable
    cleanup.arguments = ["-S", root.appendingPathComponent("socket").path, "kill-server"]
    cleanup.standardOutput = FileHandle.nullDevice
    cleanup.standardError = FileHandle.nullDevice
    if (try? cleanup.run()) != nil { cleanup.waitUntilExit() }
}
do {
    _ = try ManagedTmux(root: root, tmuxExecutable: root.appendingPathComponent("missing-tmux"))
    throw CheckFailure(name: "missing tmux executable was accepted")
} catch ManagedTmux.Failure.tmuxUnavailable {}
let first = SessionRef(id: UUID(), generation: 1)
let second = SessionRef(id: UUID(), generation: 1)
defer { try? manager.close(first); try? manager.close(second) }

let firstBinding = try manager.create(first)
let secondBinding = try manager.create(second)
do {
    _ = try ManagedTmux(root: root, tmuxExecutable: executable)
    throw CheckFailure(name: "existing private socket was adopted")
} catch ManagedTmux.Failure.socketCollision {}
try require(firstBinding.socketPath == secondBinding.socketPath, "shared private namespace")
try require(firstBinding.sessionID != secondBinding.sessionID, "distinct session IDs")
try require(firstBinding.paneID != secondBinding.paneID, "distinct pane IDs")

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
try require(firstBinding.panePID > 0, "valid pane PID")
try require(String(secondBinding.panePID) == secondPID, "bound pane PID")
let firstVerified = try manager.revalidate(first)
let secondVerified = try manager.revalidate(second)
try require(firstVerified.paneID == firstBinding.paneID, "first pane revalidation")
try require(secondVerified.paneID == secondBinding.paneID, "second pane revalidation")
do {
    _ = try manager.revalidate(SessionRef(id: first.id, generation: 2))
    throw CheckFailure(name: "wrong generation was accepted")
} catch ManagedTmux.Failure.staleSession {}

try manager.close(first)
do {
    _ = try manager.revalidate(first)
    throw CheckFailure(name: "closed session remained available")
} catch ManagedTmux.Failure.staleSession {}
let survivor = try manager.revalidate(second)
let survivorPID = try panePID(secondBinding)
try require(survivor.paneID == secondBinding.paneID, "survivor pane ID")
try require(survivorPID == secondPID, "survivor pane PID")

func mutateFixture(_ arguments: [String]) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["-S", secondBinding.socketPath] + arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
}

try mutateFixture(["respawn-pane", "-k", "-t", secondBinding.paneID, "/bin/sleep", "3600"])
let replacementPID = try panePID(secondBinding)
try require(replacementPID != secondPID, "respawn changed pane PID")
do {
    _ = try manager.revalidate(second)
    throw CheckFailure(name: "replaced pane process retained old binding")
} catch ManagedTmux.Failure.invalidPane {}
do {
    try manager.close(second)
    throw CheckFailure(name: "replaced pane process was closed through stale binding")
} catch ManagedTmux.Failure.invalidPane {}
let preservedPID = try panePID(secondBinding)
try require(preservedPID == replacementPID, "stale close preserved replacement")
try mutateFixture(["kill-session", "-t", secondBinding.sessionID])
do {
    _ = try manager.create(SessionRef(id: UUID(), generation: 1))
    throw CheckFailure(name: "stale binding allowed a new session")
} catch ManagedTmux.Failure.commandFailed {}
catch ManagedTmux.Failure.socketCollision {}

print("private_namespace=PASS exact_binding=PASS stale_generation=PASS isolated_close=PASS pane_replacement=PASS stale_binding=PASS atomic_stale_close=PASS missing_tmux=PASS socket_collision=PASS")
