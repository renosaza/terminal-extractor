import Foundation
import TermexCore

enum ConsentScope: String { case read, control }

struct ConsentResult {
    let session: SessionRef
    let scope: ConsentScope
    let clipboardExport: Bool
}

final class ConnectionGrants: @unchecked Sendable {
    struct Grant {
        let result: ConsentResult
        let token: UUID
        let epoch: UInt64
    }
    private let lock = NSLock()
    private var entries: [UUID: [UUID: Grant]] = [:]
    private var writers: [UUID: UUID] = [:]
    private var epoch: UInt64 = 0

    func currentEpoch() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return epoch
    }

    func allow(_ result: ConsentResult, connection: UUID, expectedEpoch: UInt64) -> Grant? {
        lock.lock()
        defer { lock.unlock() }
        guard epoch == expectedEpoch else { return nil }
        let sessionID = result.session.id
        if result.scope == .control, let writer = writers[sessionID], writer != connection { return nil }
        if entries[connection]?[sessionID]?.result.scope == .control { writers.removeValue(forKey: sessionID) }
        let grant = Grant(result: result, token: UUID(), epoch: epoch)
        entries[connection, default: [:]][sessionID] = grant
        if result.scope == .control { writers[sessionID] = connection }
        return grant
    }

    func check(connection: UUID, session: SessionRef, token: UUID, scope: ConsentScope,
               clipboardExport: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let grant = entries[connection]?[session.id], grant.token == token,
              grant.epoch == epoch, grant.result.session == session else { return false }
        return (grant.result.scope == .control || scope == .read) &&
            (!clipboardExport || grant.result.clipboardExport)
    }

    func revokeAll() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        epoch &+= 1
        entries.removeAll()
        writers.removeAll()
        return epoch
    }

    func list(connection: UUID) -> [[String: Any]] {
        lock.lock()
        let values = Array(entries[connection, default: [:]].values)
        lock.unlock()
        return values.map { ["session_id": $0.result.session.id.uuidString,
                             "generation": $0.result.session.generation,
                             "scope": $0.result.scope.rawValue,
                             "clipboard_export": $0.result.clipboardExport] }
    }

    func remove(connection: UUID) {
        lock.lock()
        for grant in entries[connection, default: [:]].values where grant.result.scope == .control {
            if writers[grant.result.session.id] == connection { writers.removeValue(forKey: grant.result.session.id) }
        }
        entries.removeValue(forKey: connection)
        lock.unlock()
    }
}

final class ConsentFlow: @unchecked Sendable {
    enum Failure: Error { case busy, noChoices, helperUnavailable, invalidReply, timedOut, stopped }

    private let lock = NSLock()
    private var active = false
    private let registry = SessionRegistry()

    private func enter() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !active else { return false }
        active = true
        return true
    }

    private func leave() {
        lock.lock()
        active = false
        lock.unlock()
    }

    private func label(_ choice: GhosttyDiscovery.Choice) -> String {
        func clean(_ value: String, max: Int) -> String {
            String(value.components(separatedBy: .controlCharacters).joined(separator: " ").prefix(max))
        }
        return "W \(clean(choice.windowID, max: 24)) · T \(clean(choice.tabID, max: 24)) · S \(clean(choice.surfaceID, max: 36)) — \(clean(choice.windowName, max: 24)) / \(clean(choice.tabName, max: 24)) / \(clean(choice.surfaceName, max: 24))"
    }

    func request(stopping: @Sendable () -> Bool, clipboardExportAvailable: Bool) throws -> ConsentResult? {
        guard enter() else { throw Failure.busy }
        defer { leave() }
        let deadline = DispatchTime.now().uptimeNanoseconds + 90_000_000_000
        let choices = try GhosttyDiscovery.list()
        guard DispatchTime.now().uptimeNanoseconds < deadline else { throw Failure.timedOut }
        guard !choices.isEmpty else { throw Failure.noChoices }
        var handles: [UUID] = []
        defer { registry.discardOffers(handles) }
        let rows: [[String: String]] = try choices.map { choice in
            let handle = try registry.offer(choice)
            handles.append(handle)
            return ["handle": handle.uuidString, "label": label(choice)]
        }
        let request = try JSONSerialization.data(withJSONObject: [
            "title": "Select one Ghostty session for the requesting local client",
            "choices": rows,
            "clipboard_export_available": clipboardExportAvailable,
        ])
        guard request.count <= 64 * 1024,
              let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            throw Failure.helperUnavailable
        }
        let process = Process()
        process.executableURL = directory.appendingPathComponent("termex-consent")
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.helperUnavailable }
        defer {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }
        input.fileHandleForWriting.write(request)
        input.fileHandleForWriting.closeFile()
        while process.isRunning {
            if stopping() { throw Failure.stopped }
            if DispatchTime.now().uptimeNanoseconds >= deadline { throw Failure.timedOut }
            Thread.sleep(forTimeInterval: 0.1)
        }
        guard process.terminationStatus == 0 else { throw Failure.helperUnavailable }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard data.count <= 4096,
              let reply = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalidReply
        }
        if reply["cancelled"] as? Bool == true { return nil }
        guard reply.count == 3, let text = reply["handle"] as? String,
              let handle = UUID(uuidString: text), handles.contains(handle),
              let scopeText = reply["scope"] as? String,
              let scope = ConsentScope(rawValue: scopeText),
              scope == .read,
              let clipboardExport = reply["clipboard_export"] as? Bool,
              !clipboardExport || clipboardExportAvailable else { throw Failure.invalidReply }
        let session = try registry.bindApproved(handle)
        return ConsentResult(session: session, scope: scope, clipboardExport: clipboardExport)
    }

    func revalidate(_ session: SessionRef) throws -> GhosttyTarget {
        try registry.revalidate(session)
    }
}
