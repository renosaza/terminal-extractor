import Darwin
import Foundation
import TermexCore

let grants = ConnectionGrants()
let client = UUID(), otherClient = UUID()
let session = SessionRef(id: UUID(), generation: 1)
let otherSession = SessionRef(id: UUID(), generation: 1)
func allow(_ target: SessionRef, _ connection: UUID, scope: ConsentScope = .read) -> ConnectionGrants.Grant {
    grants.allow(ConsentResult(session: target, scope: scope, clipboardExport: false),
                 connection: connection, expectedEpoch: grants.currentEpoch())!
}
let first = allow(session, client, scope: .control)
let sibling = allow(otherSession, client)
let other = allow(session, otherClient)
assert(!grants.release(connection: client, session: session, token: UUID()))
assert(!grants.release(connection: client, session: SessionRef(id: session.id, generation: 2), token: first.token))
assert(!grants.release(connection: otherClient, session: session, token: first.token))
assert(grants.check(connection: client, session: session, token: first.token, scope: .control))
assert(grants.release(connection: client, session: session, token: first.token))
assert(!grants.check(connection: client, session: session, token: first.token, scope: .read))
assert(!grants.release(connection: client, session: session, token: first.token))
assert(grants.check(connection: client, session: otherSession, token: sibling.token, scope: .read))
assert(grants.check(connection: otherClient, session: session, token: other.token, scope: .read))
let replacementWriter = allow(session, otherClient, scope: .control)
assert(grants.check(connection: otherClient, session: session, token: replacementWriter.token, scope: .control))
let renewed = allow(session, client)
assert(!grants.release(connection: client, session: session, token: first.token))
assert(grants.check(connection: client, session: session, token: renewed.token, scope: .read))

var sockets: [Int32] = [0, 0]
assert(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
let clientFD = sockets[0], serverFD = sockets[1]
defer { close(clientFD); close(serverFD) }
let channel = HostChannel(fd: clientFD)
let done = DispatchSemaphore(value: 0)
func serve(_ token: UUID) {
    DispatchQueue.global().async {
        let request = try! JSONSerialization.jsonObject(with: LocalIPC.readFrame(serverFD)) as! [String: Any]
        assert(request.count == 4 && request["op"] as? String == "release_session")
        assert(request["grant_token"] as? String == token.uuidString)
        let released = grants.release(connection: client, session: session, token: token)
        try! LocalIPC.writeFrame(JSONSerialization.data(withJSONObject: ["released": released]), to: serverFD)
        done.signal()
    }
}
channel.remember(id: session.id.uuidString, generation: 1, token: renewed.token.uuidString, clipboard: false)
serve(renewed.token)
let released = try channel.release(id: session.id.uuidString, generation: 1, requestID: "first")
assert(released == "released")
assert(done.wait(timeout: .now() + 5) == .success)
let latest = allow(session, client)
channel.remember(id: session.id.uuidString, generation: 1, token: latest.token.uuidString, clipboard: false)
let replay = try channel.release(id: session.id.uuidString, generation: 1, requestID: "first")
assert(replay == "released")
assert(grants.check(connection: client, session: session, token: latest.token, scope: .read))
let conflict = try channel.release(id: otherSession.id.uuidString, generation: 1, requestID: "first")
assert(conflict == "idempotency_conflict")
let wrongGeneration = try channel.release(id: session.id.uuidString, generation: 2, requestID: "wrong-generation")
assert(wrongGeneration == "denied")
serve(latest.token)
let fresh = try channel.release(id: session.id.uuidString, generation: 1, requestID: "fresh")
assert(fresh == "released")
assert(done.wait(timeout: .now() + 5) == .success)
assert(!grants.check(connection: client, session: session, token: latest.token, scope: .read))
for invalid in ["", String(repeating: "x", count: 129)] {
    do { _ = try channel.release(id: session.id.uuidString, generation: 1, requestID: invalid); assertionFailure() }
    catch {}
}
for index in 0..<253 {
    let denied = try channel.release(id: session.id.uuidString, generation: 1, requestID: "denied-\(index)")
    assert(denied == "denied")
}
let limited = try channel.release(id: session.id.uuidString, generation: 1, requestID: "over-limit")
assert(limited == "request_limit")
let replayAtLimit = try channel.release(id: session.id.uuidString, generation: 1, requestID: "first")
assert(replayAtLimit == "released")
assert(grants.check(connection: otherClient, session: session, token: replacementWriter.token, scope: .control))
assert(grants.check(connection: client, session: otherSession, token: sibling.token, scope: .read))
print("release isolation, stale token, replay after renewed consent, validation and bounds: PASS")

var failedSockets: [Int32] = [0, 0]
assert(socketpair(AF_UNIX, SOCK_STREAM, 0, &failedSockets) == 0)
let failedClientFD = failedSockets[0], failedServerFD = failedSockets[1]
defer { close(failedClientFD); close(failedServerFD) }
let uncertainChannel = HostChannel(fd: failedClientFD)
uncertainChannel.remember(id: session.id.uuidString, generation: 1, token: UUID().uuidString, clipboard: false)
DispatchQueue.global().async {
    _ = try! LocalIPC.readFrame(failedServerFD)
    try! LocalIPC.writeFrame(Data(#"{"ok":false}"#.utf8), to: failedServerFD)
}
do {
    _ = try uncertainChannel.release(id: session.id.uuidString, generation: 1, requestID: "uncertain")
    assertionFailure("invalid IPC result accepted")
} catch {}
uncertainChannel.remember(id: session.id.uuidString, generation: 1, token: UUID().uuidString, clipboard: false)
let uncertainReplay = try uncertainChannel.release(id: session.id.uuidString, generation: 1, requestID: "uncertain")
assert(uncertainReplay == "unavailable")
var byte: UInt8 = 0
assert(recv(failedServerFD, &byte, 1, MSG_DONTWAIT) == -1 && errno == EAGAIN)
print("uncertain release result replay without redispatch: PASS")
