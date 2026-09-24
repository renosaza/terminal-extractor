import Darwin
import Foundation
import TermexCore

final class HostChannel: @unchecked Sendable {
    private let lock = NSLock()
    private let fd: Int32
    private var poisoned = false
    private var releases: [String: (id: String, generation: Int, status: String)] = [:]
    private var grants: [String: (generation: Int, token: String, clipboard: Bool)] = [:]

    init(fd: Int32) { self.fd = fd }

    func exchange(_ request: [String: Any], timeoutSeconds: UInt64 = 5) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return try exchangeLocked(request, timeoutSeconds: timeoutSeconds)
    }

    private func exchangeLocked(_ request: [String: Any], timeoutSeconds: UInt64 = 5) throws -> [String: Any] {
        guard !poisoned else { throw LocalIPC.Failure.disconnected }
        do {
            try LocalIPC.writeFrame(JSONSerialization.data(withJSONObject: request), to: fd)
            guard let response = try JSONSerialization.jsonObject(
                with: LocalIPC.readFrame(fd, timeoutSeconds: timeoutSeconds)) as? [String: Any] else {
                throw LocalIPC.Failure.invalidFrame
            }
            return response
        } catch {
            poisoned = true
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            throw error
        }
    }

    func ping() { _ = try? exchange(["op": "ping"]) }

    func remember(id: String, generation: Int, token: String, clipboard: Bool) {
        lock.lock()
        grants[id] = (generation, token, clipboard)
        lock.unlock()
    }

    func release(id: String, generation: Int, requestID: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        guard UUID(uuidString: id) != nil, generation > 0,
              (1...128).contains(requestID.utf8.count) else { throw LocalIPC.Failure.invalidFrame }
        if let previous = releases[requestID] {
            guard previous.id == id, previous.generation == generation else {
                return "idempotency_conflict"
            }
            return previous.status
        }
        // ponytail: bounded lifetime replay cache; reconnect after 256 distinct release requests.
        guard releases.count < 256 else { return "request_limit" }
        releases[requestID] = (id, generation, "unavailable")
        guard let grant = grants[id], grant.generation == generation else {
            releases[requestID] = (id, generation, "denied")
            return "denied"
        }
        let reply = try exchangeLocked(["op": "release_session", "session_id": id,
                                        "generation": generation, "grant_token": grant.token])
        guard let released = reply["released"] as? Bool else { throw LocalIPC.Failure.invalidFrame }
        let status = released ? "released" : "denied"
        releases[requestID] = (id, generation, status)
        if released { grants.removeValue(forKey: id) }
        return status
    }

    func screen(id: String, generation: Int, view: String = "screen") throws -> [String: Any] {
        lock.lock()
        let grant = grants[id]
        lock.unlock()
        guard let grant, grant.generation == generation, grant.clipboard else {
            throw LocalIPC.Failure.unauthorizedPeer
        }
        return try exchange(["op": "read_ghostty_screen", "session_id": id,
                             "generation": generation, "grant_token": grant.token,
                             "view": view], timeoutSeconds: 20)
    }

    func screenAvailable() -> Bool {
        guard let status = try? exchange(["op": "access_status"]),
              let sessions = status["sessions"] as? [[String: Any]] else { return false }
        lock.lock()
        defer { lock.unlock() }
        return sessions.contains { session in
            guard let id = session["session_id"] as? String,
                  let generation = session["generation"] as? Int,
                  session["clipboard_export"] as? Bool == true,
                  let grant = grants[id] else { return false }
            return grant.generation == generation && grant.clipboard
        }
    }
}
