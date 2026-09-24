import Foundation
import TermexCore

final class Fixture: @unchecked Sendable {
    private let lock = NSLock()
    private var live = true
    private var duringResolve: (@Sendable () -> Void)?

    func setLive(_ value: Bool) {
        lock.lock()
        live = value
        lock.unlock()
    }

    func setDuringResolve(_ callback: (@Sendable () -> Void)?) {
        lock.lock()
        duringResolve = callback
        lock.unlock()
    }

    func resolve(_ target: GhosttyTarget) throws {
        lock.lock()
        let available = live && ["surface-1", "surface-2"].contains(target.surfaceID)
        let callback = duringResolve
        lock.unlock()
        guard available else { throw GhosttyDiscovery.Failure.notFound }
        callback?()
    }
}

let choice = try JSONDecoder().decode(GhosttyDiscovery.Choice.self, from: Data(#"{"appInstanceID":"process-1","windowID":"window-1","windowName":"display only","tabID":"tab-1","tabName":"display only","surfaceID":"surface-1","surfaceName":"display only"}"#.utf8))
let fixture = Fixture()
let registry = SessionRegistry(resolve: fixture.resolve)
let firstHandle = try registry.offer(choice)
let first = try registry.bindApproved(firstHandle)
assert(first.generation == 1)
let resolved = try registry.revalidate(first)
assert(resolved == GhosttyTarget(choice))
do {
    _ = try registry.bindApproved(firstHandle)
    fatalError("selection handle was reused")
} catch SessionRegistry.Failure.staleHandle {}
let secondHandle = try registry.offer(choice)
let sameSession = try registry.bindApproved(secondHandle)
assert(sameSession == first)
let otherChoice = try JSONDecoder().decode(GhosttyDiscovery.Choice.self, from: Data(#"{"appInstanceID":"process-1","windowID":"window-1","windowName":"display only","tabID":"tab-2","tabName":"display only","surfaceID":"surface-2","surfaceName":"display only"}"#.utf8))
let other = try registry.bindApproved(registry.offer(otherChoice))
assert(other.id != first.id)
let outstanding = try registry.offer(choice)
fixture.setLive(false)
do {
    _ = try registry.revalidate(first)
    fatalError("closed surface stayed valid")
} catch SessionRegistry.Failure.staleSession {}
fixture.setLive(true)
do {
    _ = try registry.bindApproved(outstanding)
    fatalError("offer survived target invalidation")
} catch SessionRegistry.Failure.staleHandle {}
let failedHandle = try registry.offer(choice)
fixture.setLive(false)
do {
    _ = try registry.bindApproved(failedHandle)
    fatalError("missing target was bound")
} catch GhosttyDiscovery.Failure.notFound {}
fixture.setLive(true)
do {
    _ = try registry.bindApproved(failedHandle)
    fatalError("failed selection handle was reused")
} catch SessionRegistry.Failure.staleHandle {}
let replacement = try registry.bindApproved(registry.offer(choice))
assert(replacement.id != first.id)
do {
    _ = try registry.revalidate(first)
    fatalError("stale generation resolved to replacement")
} catch SessionRegistry.Failure.staleSession {}
let inFlight = try registry.offer(choice)
fixture.setDuringResolve { registry.invalidate(replacement) }
do {
    _ = try registry.bindApproved(inFlight)
    fatalError("in-flight offer survived invalidation")
} catch SessionRegistry.Failure.staleHandle {}
fixture.setDuringResolve(nil)

func terminalChoice(_ app: String, _ window: String, _ tty: String, tab: Int = 1) throws -> TerminalDiscovery.Choice {
    let object: [String: Any] = ["appInstanceID": app, "windowID": window,
                                 "windowName": "display only", "tabOrdinal": tab, "tty": tty]
    return try JSONDecoder().decode(TerminalDiscovery.Choice.self,
                                    from: JSONSerialization.data(withJSONObject: object))
}

func terminalSnapshot(_ app: String, _ windows: [String], _ choices: [TerminalDiscovery.Choice]) throws -> TerminalDiscovery.Snapshot {
    let encodedChoices = try choices.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
    let object: [String: Any] = ["appInstanceID": app, "windowIDs": windows, "choices": encodedChoices]
    return try JSONDecoder().decode(TerminalDiscovery.Snapshot.self,
                                    from: JSONSerialization.data(withJSONObject: object))
}

func rejectWindow(_ label: String, before: TerminalDiscovery.Snapshot,
                  after: TerminalDiscovery.Snapshot, tty: String) {
    guard (try? TerminalDiscovery.newWindow(before: before, after: after, fixtureTTY: tty)) == nil else {
        fatalError("accepted \(label)")
    }
}

let existing = try terminalChoice("process-1", "1", "/dev/ttys001")
let created = try terminalChoice("process-1", "2", "/dev/ttys002")
let baseline = try terminalSnapshot("process-1", ["1"], [existing])
let createdSnapshot = try terminalSnapshot("process-1", ["1", "2"], [existing, created])
guard try TerminalDiscovery.newWindow(before: baseline, after: createdSnapshot,
                                      fixtureTTY: created.tty) == created else {
    fatalError("new one-tab Terminal window was not selected")
}
let noApp = try JSONDecoder().decode(TerminalDiscovery.Snapshot.self,
                                     from: Data(#"{"appInstanceID":null,"windowIDs":[],"choices":[]}"#.utf8))
guard try TerminalDiscovery.newWindow(before: noApp,
                                      after: terminalSnapshot("process-1", ["2"], [created]),
                                      fixtureTTY: created.tty) == created else {
    fatalError("new window in newly launched Terminal was not selected")
}
rejectWindow("reused existing window", before: baseline, after: baseline, tty: existing.tty)
let emptyWindowBaseline = try terminalSnapshot("process-1", ["2"], [])
rejectWindow("reused empty window", before: emptyWindowBaseline,
             after: try terminalSnapshot("process-1", ["2"], [created]), tty: created.tty)
let ttyCollision = try terminalChoice("process-1", "1", created.tty)
rejectWindow("pre-existing TTY collision", before: try terminalSnapshot("process-1", ["1"], [ttyCollision]),
             after: try terminalSnapshot("process-1", ["1", "2"], [ttyCollision, created]), tty: created.tty)
let duplicateTTY = try terminalChoice("process-1", "3", created.tty)
rejectWindow("ambiguous new TTY", before: baseline,
             after: try terminalSnapshot("process-1", ["1", "2", "3"], [existing, created, duplicateTTY]),
             tty: created.tty)
let secondTab = try terminalChoice("process-1", "2", "/dev/ttys003", tab: 2)
rejectWindow("multiple tabs", before: baseline,
             after: try terminalSnapshot("process-1", ["1", "2"], [existing, created, secondTab]),
             tty: created.tty)
rejectWindow("app restart", before: baseline,
             after: try terminalSnapshot("process-2", ["2"], [try terminalChoice("process-2", "2", created.tty)]),
             tty: created.tty)
rejectWindow("empty fixture TTY", before: baseline, after: createdSnapshot, tty: "")
rejectWindow("malformed fixture TTY", before: baseline, after: createdSnapshot, tty: "ttys002")
print("single_use_handle=PASS same_title_choices=PASS exact_binding=PASS stale_generation=PASS replacement_id=PASS invalidation_race=PASS terminal_new_window=PASS")
