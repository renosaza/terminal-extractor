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

func mutateFixture(_ arguments: [String], socketPath: String = secondBinding.socketPath) throws {
    let process = Process()
    process.executableURL = executable
    process.arguments = ["-S", socketPath] + arguments
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
    arguments: ["-c", "printf 'TE_GATE_OK\\n'; printf '%080d' 0; exec /bin/sleep 3600"])
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
var workloadObservation = try manager.captureObservation(workload, gate: workloadGate)
for _ in 0..<100 where !workloadObservation.gapObserved {
    usleep(20_000)
    workloadObservation = try manager.captureObservation(workload, gate: workloadGate)
}
try require(workloadObservation.observedBytes == 64 && workloadObservation.pipeConnected &&
            workloadObservation.gapObserved && !workloadObservation.sinkClosedCleanly,
            "owner quota gap metadata")
let originalPipePID = try panePID(launched, format: "#{pane_pipe_pid}")
try mutateFixture(["pipe-pane", "-O", "-t", launched.paneID, "cat >/dev/null"])
var replacementPipePID: String?
for _ in 0..<100 {
    replacementPipePID = try? panePID(launched, format: "#{pane_pipe_pid}")
    if replacementPipePID != nil && replacementPipePID != originalPipePID { break }
    usleep(20_000)
}
try require(replacementPipePID != nil && replacementPipePID != originalPipePID,
            "replacement capture pipe PID")
do {
    _ = try manager.revalidate(workload)
    throw CheckFailure(name: "replaced capture pipe retained valid binding")
} catch ManagedTmux.Failure.invalidPane {}
let disconnected = try manager.captureObservation(workload, gate: workloadGate)
try require(!disconnected.pipeConnected, "replaced capture pipe reported disconnected")
do {
    try manager.close(workload)
    throw CheckFailure(name: "replaced capture pipe was closed through old gate")
} catch ManagedTmux.Failure.invalidPane {}
let neighborPID = try panePID(secondBinding)
try require(neighborPID == secondPID, "neighbor PID after launch")
try mutateFixture(["kill-session", "-t", workloadBinding.sessionID])

let shellRef = SessionRef(id: UUID(), generation: 1)
let shellPlaceholder = try manager.create(shellRef)
let shellGate = try manager.armCapture(shellRef, sinkExecutable: sink, maxBytes: 4096)
let shellBinding = try manager.launchCapturedProcess(shellRef, gate: shellGate,
    executableURL: URL(fileURLWithPath: "/bin/zsh"), arguments: ["-f", "-i"])
try require(shellBinding.panePID != shellPlaceholder.panePID, "private shell launch PID")
let shellBefore = try manager.captureObservation(shellRef, gate: shellGate)
let shellState = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
try mutateFixture(["send-keys", "-l", "-t", shellBinding.paneID, "TE_PRIVATE_STATE=\(shellState)"])
try mutateFixture(["send-keys", "-t", shellBinding.paneID, "Enter"])
let shellBetween = try manager.revalidate(shellRef)
try require(shellBetween == shellBinding, "private shell binding between commands")
try mutateFixture(["send-keys", "-l", "-t", shellBinding.paneID,
                   "printf 'TE_ZSH_STATE_%s\\n' \"$TE_PRIVATE_STATE\""])
try mutateFixture(["send-keys", "-t", shellBinding.paneID, "Enter"])
let shellMarker = Data("TE_ZSH_STATE_\(shellState)".utf8)
var shellStateObserved = false
for _ in 0..<150 {
    let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
    for name in names where name.hasPrefix("capture-") {
        let segment = root.appendingPathComponent(name).appendingPathComponent("segment")
        if let bytes = try? Data(contentsOf: segment), bytes.range(of: shellMarker) != nil {
            shellStateObserved = true
        }
    }
    if shellStateObserved { break }
    usleep(20_000)
}
try require(shellStateObserved, "private zsh retained state across commands")
let shellAfter = try manager.captureObservation(shellRef, gate: shellGate)
try require(shellAfter.observedBytes > shellBefore.observedBytes && shellAfter.pipeConnected &&
            !shellAfter.gapObserved, "private shell capture metadata advanced")
let shellVerified = try manager.revalidate(shellRef)
try require(shellVerified == shellBinding, "private shell binding after commands")
let neighborAfterShell = try panePID(secondBinding)
try require(neighborAfterShell == secondPID, "neighbor PID after private shell")
try manager.close(shellRef)

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

let failureRoot = URL(fileURLWithPath: "/tmp").appendingPathComponent("te-fail-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: failureRoot, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: failureRoot) }
let failureSocket = failureRoot.appendingPathComponent("socket").path
defer {
    let cleanup = Process()
    cleanup.executableURL = executable
    cleanup.arguments = ["-S", failureSocket, "kill-server"]
    cleanup.standardOutput = FileHandle.nullDevice
    cleanup.standardError = FileHandle.nullDevice
    if (try? cleanup.run()) != nil { cleanup.waitUntilExit() }
}
func shellQuote(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
}
let failBefore = failureRoot.appendingPathComponent("fail-before")
let wrapper = failureRoot.appendingPathComponent("tmux-wrapper")
let realTmux = shellQuote(executable.resolvingSymlinksInPath().path)
let wrapperSource = """
    #!/bin/sh
    case "$*" in
      *"respawn-pane -k"*)
        if [ -e \(shellQuote(failBefore.path)) ]; then exit 1; fi
        \(realTmux) "$@" >/dev/null 2>&1
        exit 1 ;;
    esac
    exec \(realTmux) "$@"
    """
try wrapperSource.write(to: wrapper, atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: wrapper.path)
let failureManager = try ManagedTmux(root: failureRoot, tmuxExecutable: wrapper)
let failureRef = SessionRef(id: UUID(), generation: 1)
let failurePeer = SessionRef(id: UUID(), generation: 1)
let failureBinding = try failureManager.create(failureRef)
let failurePeerBinding = try failureManager.create(failurePeer)
let failureGate = try failureManager.armCapture(failureRef, sinkExecutable: sink, maxBytes: 64)
do {
    _ = try failureManager.launchCapturedProcess(failureRef, gate: failureGate,
        executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "lost launch acknowledgment was accepted")
} catch ManagedTmux.Failure.commandFailed {}
let changedAfterLostAck = try panePID(failureBinding)
try require(changedAfterLostAck != String(failureBinding.panePID), "server launch changed PID")
do {
    _ = try failureManager.revalidate(failureRef)
    throw CheckFailure(name: "unconfirmed launch was revalidated")
} catch ManagedTmux.Failure.launchIndeterminate {}
do {
    _ = try failureManager.captureObservation(failureRef, gate: failureGate)
    throw CheckFailure(name: "unconfirmed launch reported capture metadata")
} catch ManagedTmux.Failure.launchIndeterminate {}
do {
    _ = try failureManager.launchCapturedProcess(failureRef, gate: failureGate,
        executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "unconfirmed launch was retried")
} catch ManagedTmux.Failure.staleSession {}
do {
    try failureManager.close(failureRef)
    throw CheckFailure(name: "stale close killed an unconfirmed launch")
} catch ManagedTmux.Failure.invalidPane {}
let survivedLostAck = try panePID(failureBinding)
try require(survivedLostAck == changedAfterLostAck, "unconfirmed pane survived stale close")
let peerAfterLostAck = try failureManager.revalidate(failurePeer)
try require(peerAfterLostAck == failurePeerBinding, "peer survived lost acknowledgment")

let staleAnchor = SessionRef(id: UUID(), generation: 1)
let staleAnchorBinding = try failureManager.create(staleAnchor)
_ = try failureManager.armCapture(staleAnchor, sinkExecutable: sink, maxBytes: 64)
let staleAnchorPipePID = try panePID(staleAnchorBinding, format: "#{pane_pipe_pid}")
try mutateFixture(["pipe-pane", "-O", "-t", staleAnchorBinding.paneID, "cat >/dev/null"],
                  socketPath: failureSocket)
var staleAnchorReplacement: String?
for _ in 0..<100 {
    staleAnchorReplacement = try? panePID(staleAnchorBinding, format: "#{pane_pipe_pid}")
    if staleAnchorReplacement != nil && staleAnchorReplacement != staleAnchorPipePID { break }
    usleep(20_000)
}
try require(staleAnchorReplacement != nil && staleAnchorReplacement != staleAnchorPipePID,
            "stale anchor pipe replacement")
do {
    _ = try failureManager.revalidate(staleAnchor)
    throw CheckFailure(name: "stale capture anchor was revalidated")
} catch ManagedTmux.Failure.invalidPane {}
let beforeRef = SessionRef(id: UUID(), generation: 1)
let beforeBinding = try failureManager.create(beforeRef)
let beforeGate = try failureManager.armCapture(beforeRef, sinkExecutable: sink, maxBytes: 64)
try Data().write(to: failBefore)
do {
    _ = try failureManager.launchCapturedProcess(beforeRef, gate: beforeGate,
        executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["3600"])
    throw CheckFailure(name: "pre-dispatch launch failure was accepted")
} catch ManagedTmux.Failure.commandFailed {}
let beforePID = try panePID(beforeBinding)
try require(beforePID == String(beforeBinding.panePID), "pre-dispatch failure changed placeholder")
do {
    _ = try failureManager.revalidate(beforeRef)
    throw CheckFailure(name: "unconfirmed placeholder was revalidated")
} catch ManagedTmux.Failure.launchIndeterminate {}
try failureManager.close(beforeRef)
let peerAfterPlaceholderClose = try failureManager.revalidate(failurePeer)
try require(peerAfterPlaceholderClose == failurePeerBinding, "peer survived exact placeholder close")

print("private_namespace=PASS capture_gate=PASS synthetic_workload=PASS capture_observation=PASS owner_quota_gap=PASS guarded_launch=PASS private_shell_state=PASS no_arg_rejected=PASS pipe_replacement=PASS foreign_pipe=PASS exact_binding=PASS stale_generation=PASS isolated_close=PASS pane_replacement=PASS stale_binding=PASS atomic_stale_close=PASS lost_ack_quarantine=PASS pre_dispatch_quarantine=PASS healthy_anchor=PASS missing_tmux=PASS socket_collision=PASS")
