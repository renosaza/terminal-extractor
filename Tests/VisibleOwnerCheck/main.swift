import Foundation
import Darwin
import TermexCore

enum CheckFailure: Error { case failed }
let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.isEmpty || arguments == ["--self-check"] else { throw CheckFailure.failed }
let selfCheck = arguments == ["--self-check"]
guard selfCheck || (ProcessInfo.processInfo.environment["TMUX"] == nil && isatty(STDIN_FILENO) == 1 &&
                    isatty(STDOUT_FILENO) == 1) else {
    throw CheckFailure.failed
}

let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("te-visible-owner-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
var preserveRoot = false
defer { if !preserveRoot { try? FileManager.default.removeItem(at: root) } }
let tmux = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TERMEX_TMUX_BIN"]
                    ?? "/opt/homebrew/bin/tmux")
let manager = try ManagedTmux(root: root, tmuxExecutable: tmux)
let ref = SessionRef(id: UUID(), generation: 1)
var created = false
var closed = false
var cleanEOF = false
defer {
    if selfCheck && created && !closed { closed = (try? manager.close(ref)) != nil }
    if created && !(closed && cleanEOF) {
        preserveRoot = true
        fputs("private_fixture_retained=\(root.path)\n", stderr)
    }
}

_ = try manager.create(ref)
created = true
let sink = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("termex-capture-sink")
let gate = try manager.armCapture(ref, sinkExecutable: sink, maxBytes: 4096)
let marker = "TE_OWNER_VISIBLE_OK"
let binding = try manager.launchCapturedProcess(ref, gate: gate,
    executableURL: URL(fileURLWithPath: "/bin/sh"),
    arguments: ["-c", "printf '\(marker)\\n'; exec /bin/zsh -f -i"])
let screen = try manager.screenMetadata(ref)
guard screen.columns > 0 && screen.rows > 0 else { throw CheckFailure.failed }

var viewClientObserved = false
if !selfCheck {
    guard let tty = ttyname(STDIN_FILENO) else { throw CheckFailure.failed }
    let expectedTTY = String(cString: tty)
    print("Temporary private tmux shell: expect \(marker), then run tmux detach-client. Up to 4096 bytes are captured in a private test directory; do not type secrets or other commands.")
    fflush(stdout)
    let attach = Process()
    attach.executableURL = tmux
    attach.arguments = ["-S", binding.socketPath, "-f", "/dev/null", "attach-session", "-t", binding.sessionID]
    attach.standardInput = FileHandle.standardInput
    attach.standardOutput = FileHandle.standardOutput
    attach.standardError = FileHandle.standardError
    try attach.run()
    var attachReturned = false
    defer {
        if !attachReturned {
            if attach.isRunning { attach.terminate() }
            for _ in 0..<100 where attach.isRunning { Thread.sleep(forTimeInterval: 0.02) }
            if attach.isRunning { _ = Darwin.kill(attach.processIdentifier, SIGKILL) }
            for _ in 0..<100 where attach.isRunning { Thread.sleep(forTimeInterval: 0.02) }
            if !attach.isRunning { attach.waitUntilExit() }
            closed = (try? manager.close(ref)) != nil
        }
    }
    let deadline = DispatchTime.now().uptimeNanoseconds + 10_000_000_000
    while DispatchTime.now().uptimeNanoseconds < deadline && attach.isRunning {
        if try manager.hasSingleAttachedClient(ref, expectedTTY: expectedTTY) {
            viewClientObserved = true
            break
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    guard viewClientObserved else { throw CheckFailure.failed }
    attach.waitUntilExit()
    guard attach.terminationStatus == 0 else { throw CheckFailure.failed }
    attachReturned = true
}

let directories = try FileManager.default.contentsOfDirectory(atPath: root.path)
    .filter { $0.hasPrefix("capture-") }
guard directories.count == 1 else { throw CheckFailure.failed }
let segment = root.appendingPathComponent(directories[0]).appendingPathComponent("segment")
let markerBytes = Data(marker.utf8)
var captured = false
for _ in 0..<100 {
    if let bytes = try? Data(contentsOf: segment), bytes.range(of: markerBytes) != nil {
        captured = true
        break
    }
    Thread.sleep(forTimeInterval: 0.02)
}
let observation = try manager.captureObservation(ref, gate: gate)
guard captured && observation.pipeConnected && !observation.gapObserved,
      try manager.revalidate(ref) == binding else { throw CheckFailure.failed }
try manager.close(ref)
closed = true
let cleanMarker = root.appendingPathComponent(directories[0]).appendingPathComponent("clean_eof")
let closedRecord = root.appendingPathComponent(directories[0]).appendingPathComponent("closed")
var closure = try manager.closedCaptureObservation(ref, gate: gate)
for _ in 0..<100 where closure == nil {
    Thread.sleep(forTimeInterval: 0.02)
    closure = try manager.closedCaptureObservation(ref, gate: gate)
}
cleanEOF = FileManager.default.fileExists(atPath: cleanMarker.path)
let segmentSize = try FileManager.default.attributesOfItem(atPath: segment.path)[.size] as? NSNumber
let record = try String(contentsOf: closedRecord, encoding: .utf8)
guard cleanEOF, let segmentSize, record == "\(segmentSize.uint64Value) clean",
      closure?.observedBytes == segmentSize.uint64Value, closure?.gapObserved == false else {
    throw CheckFailure.failed
}
if selfCheck {
    do {
        _ = try manager.closedCaptureObservation(SessionRef(id: ref.id, generation: 2), gate: gate)
        throw CheckFailure.failed
    } catch ManagedTmux.Failure.staleSession {}
    try "invalid".write(to: closedRecord, atomically: false, encoding: .utf8)
    do {
        _ = try manager.closedCaptureObservation(ref, gate: gate)
        throw CheckFailure.failed
    } catch ManagedTmux.Failure.invalidPane {}
    try record.write(to: closedRecord, atomically: false, encoding: .utf8)
    let gapMarker = root.appendingPathComponent(directories[0]).appendingPathComponent("gap")
    let gapFD = open(gapMarker.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard gapFD >= 0 else { throw CheckFailure.failed }
    _ = Darwin.close(gapFD)
    do {
        _ = try manager.closedCaptureObservation(ref, gate: gate)
        throw CheckFailure.failed
    } catch ManagedTmux.Failure.invalidPane {}
    try FileManager.default.removeItem(at: gapMarker)
    try FileManager.default.removeItem(at: closedRecord)
    guard try manager.closedCaptureObservation(ref, gate: gate) == nil else {
        throw CheckFailure.failed
    }
}
print("private_owner=PASS capture_pipe_marker=PASS screen_metadata=PASS clean_fixture_close=PASS" +
      (selfCheck ? "" : " view_client=PASS attach_return=PASS"))
