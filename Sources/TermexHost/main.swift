import Darwin
import Foundation
import TermexCore

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--stop"] || (args.count == 3 && args[0] == "--stop" && args[1] == "--socket") {
    let fd = try LocalIPC.connect(to: (args.count == 3 ? args[2] : LocalIPC.defaultPath) + ".stop")
    defer { Darwin.close(fd) }
    let reply = try JSONSerialization.jsonObject(with: LocalIPC.readFrame(fd)) as? [String: Any]
    guard reply?["stopped"] as? Bool == true else { throw LocalIPC.Failure.invalidFrame }
    print("Access revoked")
    exit(0)
}
if args == ["--list-ghostty"] {
    let choices = try GhosttyDiscovery.list()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(choices), as: UTF8.self))
    exit(0)
}
if args == ["--list-terminal"] {
    let choices = try TerminalDiscovery.list()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(choices), as: UTF8.self))
    exit(0)
}
if args.count == 5 && args[0] == "--resolve-ghostty" {
    let choice = try GhosttyDiscovery.resolve(appInstanceID: args[1], windowID: args[2],
                                              tabID: args[3], surfaceID: args[4])
    print(String(decoding: try JSONEncoder().encode(choice), as: UTF8.self))
    exit(0)
}
if args.count == 4 && args[0] == "--resolve-terminal" {
    let choice = try TerminalDiscovery.resolve(appInstanceID: args[1], windowID: args[2], tty: args[3])
    print(String(decoding: try JSONEncoder().encode(choice), as: UTF8.self))
    exit(0)
}
guard args.count.isMultiple(of: 2) else {
    fatalError("usage: termex-host [--socket private-path] [--config private-json-path] | --stop [--socket private-path] | --list-ghostty | --resolve-ghostty app-instance window-id tab-id surface-id | --list-terminal | --resolve-terminal app-instance window-id tty")
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

@Sendable func serve(_ client: Int32, connectionID: UUID, config: LocalConfig,
                     consent: ConsentFlow, grants: ConnectionGrants,
                     stopping: @Sendable () -> Bool) -> Bool {
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
        case "request_ghostty_access":
            guard request.count == 1 else { throw LocalIPC.Failure.invalidFrame }
            let response: [String: Any]
            do {
                guard config.allowedApps.contains(.ghostty) else { throw ConsentFlow.Failure.noChoices }
                let expectedEpoch = grants.currentEpoch()
                if let approved = try consent.request(stopping: { stopping() || grants.currentEpoch() != expectedEpoch }) {
                    guard !stopping() else { throw ConsentFlow.Failure.stopped }
                    if let grant = grants.allow(approved, connection: connectionID, expectedEpoch: expectedEpoch) {
                        response = ["status": "approved", "session_id": approved.session.id.uuidString,
                                    "generation": approved.session.generation,
                                    "scope": approved.scope.rawValue, "grant_token": grant.token.uuidString,
                                    "terminal_access": false]
                    } else { response = ["status": "revoked_or_writer_busy"] }
                } else { response = ["status": "cancelled"] }
            } catch ConsentFlow.Failure.busy { response = ["status": "busy"] }
            catch ConsentFlow.Failure.noChoices { response = ["status": "no_sessions"] }
            catch { response = ["status": "unavailable"] }
            try LocalIPC.writeFrame(JSONSerialization.data(withJSONObject: response), to: client)
        case "access_status":
            guard request.count == 1 else { throw LocalIPC.Failure.invalidFrame }
            let response = try JSONSerialization.data(withJSONObject: ["sessions": grants.list(connection: connectionID)])
            try LocalIPC.writeFrame(response, to: client)
        default:
            throw LocalIPC.Failure.invalidFrame
        }
        return true
    } catch {
        if !stopping() { try? LocalIPC.writeFrame(Data(#"{"ok":false}"#.utf8), to: client) }
        return false
    }
}

let listener = try LocalIPC.listen(at: path)
defer { Darwin.close(listener); unlink(path) }
let stopPath = path + ".stop"
let stopListener = try LocalIPC.listen(at: stopPath)
defer { Darwin.close(stopListener); unlink(stopPath) }

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

final class ClientPool: @unchecked Sendable {
    private let lock = NSLock()
    private let group = DispatchGroup()
    private var clients: [Int32: UUID] = [:]
    private var stopped = false
    private let grants: ConnectionGrants

    init(grants: ConnectionGrants) { self.grants = grants }

    func add(_ fd: Int32) -> UUID? {
        lock.lock()
        defer { lock.unlock() }
        guard !stopped, clients.count < 8 else { return nil }
        let id = UUID() // Socket-local tag; authorization still requires consent and a session binding.
        clients[fd] = id
        group.enter()
        return id
    }

    func isStopped() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func remove(_ fd: Int32, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard clients[fd] == id else { return }
        clients.removeValue(forKey: fd)
        grants.remove(connection: id)
        Darwin.close(fd)
        group.leave()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        for fd in clients.keys { _ = Darwin.shutdown(fd, SHUT_RDWR) }
    }

    func wait() { _ = group.wait(timeout: .now() + 5) }
}

let grants = ConnectionGrants()
let consent = ConsentFlow()
let pool = ClientPool(grants: grants)
defer { pool.stop(); pool.wait() }
while stopping.wait(timeout: .now()) == .timedOut {
    var pending = [pollfd(fd: stopListener, events: Int16(POLLIN), revents: 0),
                   pollfd(fd: listener, events: Int16(POLLIN), revents: 0)]
    let ready = pending.withUnsafeMutableBufferPointer { poll($0.baseAddress, nfds_t($0.count), 250) }
    if ready == 0 || (ready < 0 && errno == EINTR) { continue }
    if ready < 0 || pending.contains(where: { $0.revents & Int16(POLLNVAL | POLLERR) != 0 }) { break }
    if pending[0].revents & Int16(POLLIN) != 0 {
        do {
            let client = try LocalIPC.accept(stopListener)
            let epoch = grants.revokeAll()
            try? LocalIPC.writeFrame(try JSONSerialization.data(withJSONObject: ["stopped": true, "epoch": epoch]), to: client)
            Darwin.close(client)
        } catch LocalIPC.Failure.unauthorizedPeer { continue }
        catch { break }
    }
    if pending[1].revents & Int16(POLLIN) == 0 { continue }
    do {
        let client = try LocalIPC.accept(listener)
        guard let id = pool.add(client) else { Darwin.close(client); continue }
        DispatchQueue.global().async {
            defer { pool.remove(client, id: id) }
            var lastActivity = DispatchTime.now().uptimeNanoseconds
            while !pool.isStopped() {
                var pending = pollfd(fd: client, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pending, 1, 250)
                if ready < 0 && errno == EINTR { continue }
                if ready < 0 || pending.revents & Int16(POLLERR | POLLNVAL) != 0 { break }
                if ready == 0 {
                    if DispatchTime.now().uptimeNanoseconds - lastActivity > 60_000_000_000 { break }
                    continue
                }
                if pending.revents & Int16(POLLIN) != 0 {
                    guard serve(client, connectionID: id, config: config, consent: consent,
                                grants: grants, stopping: pool.isStopped) else { break }
                    lastActivity = DispatchTime.now().uptimeNanoseconds
                } else if pending.revents & Int16(POLLHUP) != 0 { break }
            }
        }
    } catch LocalIPC.Failure.unauthorizedPeer { continue }
    catch { break }
}
