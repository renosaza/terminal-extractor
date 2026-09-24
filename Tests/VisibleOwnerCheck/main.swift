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

if !selfCheck {
    print("Temporary private tmux shell: expect \(marker), then press Ctrl-B, D. Up to 4096 bytes are captured in a private test directory; do not type secrets or other commands.")
    fflush(stdout)
    let attach = Process()
    attach.executableURL = tmux
    attach.arguments = ["-S", binding.socketPath, "-f", "/dev/null", "attach-session", "-t", binding.sessionID]
    attach.standardInput = FileHandle.standardInput
    attach.standardOutput = FileHandle.standardOutput
    attach.standardError = FileHandle.standardError
    try attach.run()
    attach.waitUntilExit()
    guard attach.terminationStatus == 0 else { throw CheckFailure.failed }
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
for _ in 0..<100 where !FileManager.default.fileExists(atPath: cleanMarker.path) {
    Thread.sleep(forTimeInterval: 0.02)
}
cleanEOF = FileManager.default.fileExists(atPath: cleanMarker.path)
guard cleanEOF else { throw CheckFailure.failed }
print("private_owner=PASS capture_pipe_marker=PASS screen_metadata=PASS clean_fixture_close=PASS" +
      (selfCheck ? "" : " attach_return=PASS"))
