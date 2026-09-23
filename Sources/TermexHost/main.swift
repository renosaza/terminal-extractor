import Darwin
import Foundation
import TermexCore

let args = CommandLine.arguments
let path = args.count == 3 && args[1] == "--socket" ? args[2] : LocalIPC.defaultPath
guard args.count == 1 || (args.count == 3 && args[1] == "--socket") else {
    fatalError("usage: termex-host [--socket private-path]")
}

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
    catch { break }
    defer { Darwin.close(client) }
    do {
        let data = try LocalIPC.readFrame(client)
        let request = try JSONSerialization.jsonObject(with: data) as? [String: String]
        guard request == ["op": "ping"] else { throw LocalIPC.Failure.invalidFrame }
        try LocalIPC.writeFrame(Data(#"{"ok":true}"#.utf8), to: client)
    } catch {
        try? LocalIPC.writeFrame(Data(#"{"ok":false}"#.utf8), to: client)
    }
}
