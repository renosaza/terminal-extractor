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
print("single_use_handle=PASS same_title_choices=PASS exact_binding=PASS stale_generation=PASS replacement_id=PASS invalidation_race=PASS")
