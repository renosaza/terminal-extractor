import Darwin
import Foundation
import TermexCore

let args = Array(CommandLine.arguments.dropFirst())
guard args.count.isMultiple(of: 2) else {
    fatalError("usage: termex-host [--socket private-path] [--config private-json-path]")
}
var path = LocalIPC.defaultPath
var configURL = LocalConfig.defaultURL
var explicitConfig = false
var seen = Set<String>()
for index in stride(from: 0, to: args.count, by: 2) {
    guard seen.insert(args[index]).inserted, args[index + 1].hasPrefix("/") else {
        fatalError("duplicate option or non-absolute path")
    }
    switch args[index] {
    case "--socket": path = args[index + 1]
    case "--config":
        configURL = URL(fileURLWithPath: args[index + 1])
        explicitConfig = true
    default: fatalError("unknown option")
    }
}
let config = try LocalConfig.load(at: configURL, requireExisting: explicitConfig)

let listener = try LocalIPC.listen(at: path)
defer { Darwin.close(listener); unlink(path) }

// The host remains alive across gateway exits; a signal closes only this listener.
signal(SIGINT, SIG_IGN)
signal(SIGTERM, SIG_IGN)
let stopping = DispatchSemaphore(value: 0)
let stop = [SIGINT, SIGTERM].map { value in
    let source = DispatchSource.makeSignalSource(signal: value, queue: .global())
    source.setEventHandler { stopping.signal() }
    source.resume()
    return source
}
_ = stop
fputs("termex-host ready\n", stderr)

// ponytail: serial ping handling is enough for the foundation; add concurrency with real requests.
while stopping.wait(timeout: .now()) == .timedOut {
    var pending = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)
    let ready = poll(&pending, 1, 250)
    if ready == 0 || (ready < 0 && errno == EINTR) { continue }
    if ready < 0 || pending.revents & Int16(POLLIN) == 0 { break }
    let client: Int32
    do { client = try LocalIPC.accept(listener) }
    catch LocalIPC.Failure.unauthorizedPeer { continue }
    catch { break }
    defer { Darwin.close(client) }
    do {
        let data = try LocalIPC.readFrame(client)
        guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let operation = request["op"] as? String else { throw LocalIPC.Failure.invalidFrame }
        switch operation {
        case "ping":
            guard request.count == 1 else { throw LocalIPC.Failure.invalidFrame }
            try LocalIPC.writeFrame(Data(#"{"ok":true}"#.utf8), to: client)
        case "resolve_preferences":
            guard request.count == 2,
                  let environment = request["environment"] as? [String: String] else {
                throw LocalIPC.Failure.invalidFrame
            }
            let selected = try config.applyingPreferences(environment)
            let response = try JSONSerialization.data(withJSONObject: [
                "terminal_app": selected.terminalApp.rawValue,
                "attach_policy": selected.attachPolicy.rawValue,
                "new_session_backend": selected.newSessionBackend.rawValue,
            ])
            try LocalIPC.writeFrame(response, to: client)
        default:
            throw LocalIPC.Failure.invalidFrame
        }
    } catch {
        try? LocalIPC.writeFrame(Data(#"{"ok":false}"#.utf8), to: client)
    }
}
