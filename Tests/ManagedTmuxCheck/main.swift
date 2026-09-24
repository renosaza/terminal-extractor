import Foundation
import TermexCore

struct CheckFailure: Error { let name: String }
func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw CheckFailure(name: name) }
}

let root = URL(fileURLWithPath: "/tmp")
    .appendingPathComponent("te-'\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }

let executable = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TERMEX_TMUX_BIN"]
                     ?? "/opt/homebrew/bin/tmux")
let manager = try ManagedTmux(root: root, tmuxExecutable: executable)
let unsafeRoot = URL(fileURLWithPath: "/tmp").appendingPathComponent("te-#\(UUID().uuidString)")
try FileManager.default.createDirectory(at: unsafeRoot, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: unsafeRoot) }
do {
    _ = try ManagedTmux(root: unsafeRoot, tmuxExecutable: executable)
    throw CheckFailure(name: "tmux format path was accepted")
} catch ManagedTmux.Failure.unsafeRoot {}
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
let sink = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("termex-capture-sink")
let gate = try manager.armCapture(first, sinkExecutable: sink, maxBytes: 64)
try require(gate.sessionID == first.id && gate.generation == first.generation, "capture gate session binding")
let observation = try manager.captureObservation(first, gate: gate)
try require(observation.observedBytes == 0 && !observation.gapObserved &&
            !observation.sinkClosedCleanly && observation.pipeConnected, "initial capture observation")
do {
    _ = try manager.captureObservation(second, gate: gate)
    throw CheckFailure(name: "cross-session gate was accepted")
} catch ManagedTmux.Failure.staleSession {}
do {
    _ = try ManagedTmux(root: root, tmuxExecutable: executable)
    throw CheckFailure(name: "existing private socket was adopted")
} catch ManagedTmux.Failure.socketCollision {}
try require(firstBinding.socketPath == secondBinding.socketPath, "shared private namespace")
try require(firstBinding.sessionID != secondBinding.sessionID, "distinct session IDs")
try require(firstBinding.paneID != secondBinding.paneID, "distinct pane IDs")

func panePID(_ binding: ManagedTmux.Binding, format: String = "#{pane_pid}") throws -> String {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["-S", binding.socketPath, "display-message", "-p",
                         "-t", binding.paneID, format]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0,
          let pid = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), Int(pid) != nil else {
        throw CheckFailure(name: "numeric tmux format unavailable: \(format)")
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
    _ = try manager.captureObservation(first, gate: gate)
    throw CheckFailure(name: "closed capture gate remained available")
} catch ManagedTmux.Failure.staleSession {}
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

let workload = SessionRef(id: UUID(), generation: 1)
let workloadBinding = try manager.create(workload)
do {
    _ = try manager.launchCapturedProcess(workload, gate: gate,
                                          executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "cross-session launch gate was accepted")
} catch ManagedTmux.Failure.staleSession {}
let workloadGate = try manager.armCapture(workload, sinkExecutable: sink, maxBytes: 64)
do {
    _ = try manager.launchCapturedProcess(workload, gate: gate,
                                          executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "wrong launch gate was accepted")
} catch ManagedTmux.Failure.staleSession {}
do {
    _ = try manager.launchCapturedProcess(workload, gate: workloadGate,
                                          executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: [])
    throw CheckFailure(name: "shell-interpreted no-argument launch was accepted")
} catch ManagedTmux.Failure.commandFailed {}
let launched = try manager.launchCapturedProcess(workload, gate: workloadGate,
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "printf 'TE_GATE_OK\\n'; exec /bin/sleep 3600"])
try require(launched.panePID != workloadBinding.panePID, "launch changed pane PID")
let launchedVerified = try manager.revalidate(workload)
try require(launchedVerified == launched, "launched pane binding")
do {
    _ = try manager.launchCapturedProcess(workload, gate: workloadGate,
                                          executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "second launch was accepted")
} catch ManagedTmux.Failure.staleSession {}
let syntheticMarker = Data("TE_GATE_OK".utf8)
var observedWorkload = false
for _ in 0..<100 {
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    for name in names where name.hasPrefix("capture-") {
        let segment = root.appendingPathComponent(name).appendingPathComponent("segment")
        if let bytes = try? Data(contentsOf: segment), bytes.range(of: syntheticMarker) != nil {
            observedWorkload = true
        }
    }
    if observedWorkload { break }
    usleep(20_000)
}
try require(observedWorkload, "owner gate captured synthetic workload")
let workloadObservation = try manager.captureObservation(workload, gate: workloadGate)
try require(workloadObservation.observedBytes > 0 && workloadObservation.pipeConnected &&
            !workloadObservation.gapObserved, "launched workload metadata")
let neighborPID = try panePID(secondBinding)
try require(neighborPID == secondPID, "neighbor PID after launch")
try mutateFixture(["kill-session", "-t", workloadBinding.sessionID])

try mutateFixture(["pipe-pane", "-O", "-t", secondBinding.paneID, "sleep 60"])
var foreignPipePID: String?
for _ in 0..<100 {
    foreignPipePID = try? panePID(secondBinding, format: "#{pane_pipe_pid}")
    if foreignPipePID != nil { break }
    usleep(20_000)
}
guard let foreignPipePID else { throw CheckFailure(name: "foreign pipe PID unavailable") }
do {
    _ = try manager.armCapture(second, sinkExecutable: sink, maxBytes: 64)
    throw CheckFailure(name: "existing pane pipe was adopted")
} catch ManagedTmux.Failure.invalidPane {}
let unchangedPipePID = try panePID(secondBinding, format: "#{pane_pipe_pid}")
try require(unchangedPipePID == foreignPipePID, "foreign pipe survived rejected arm")
try mutateFixture(["pipe-pane", "-t", secondBinding.paneID])
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

print("private_namespace=PASS capture_gate=PASS synthetic_workload=PASS capture_observation=PASS guarded_launch=PASS no_arg_rejected=PASS foreign_pipe=PASS exact_binding=PASS stale_generation=PASS isolated_close=PASS pane_replacement=PASS stale_binding=PASS atomic_stale_close=PASS missing_tmux=PASS socket_collision=PASS")
