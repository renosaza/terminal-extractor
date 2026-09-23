import Foundation

public struct SessionRef: Hashable, Sendable {
    public let id: UUID
    public let generation: UInt64
}

public struct GhosttyTarget: Hashable, Sendable {
    public let appInstanceID: String
    public let windowID: String
    public let tabID: String
    public let surfaceID: String

    public init(_ choice: GhosttyDiscovery.Choice) {
        appInstanceID = choice.appInstanceID
        windowID = choice.windowID
        tabID = choice.tabID
        surfaceID = choice.surfaceID
    }
}

/// Host-local selection state. Call bindApproved only after a separate local consent decision.
public final class SessionRegistry: @unchecked Sendable {
    public enum Failure: Error { case staleHandle, staleSession, tooManyOffers, tooManySessions }

    private let lock = NSLock()
    private let resolve: @Sendable (GhosttyTarget) throws -> Void
    private var offers: [UUID: (target: GhosttyTarget, issued: UInt64, revision: UInt64)] = [:]
    private var sessions: [UUID: (target: GhosttyTarget, generation: UInt64, active: Bool)] = [:]
    private var byTarget: [GhosttyTarget: UUID] = [:]
    // ponytail: one registry revision invalidates all offers; use per-target revisions if selection churn becomes costly.
    private var revision: UInt64 = 0
    private let offerLifetime: UInt64 = 60_000_000_000

    public init(resolve: @escaping @Sendable (GhosttyTarget) throws -> Void = { target in
        _ = try GhosttyDiscovery.resolve(appInstanceID: target.appInstanceID,
                                         windowID: target.windowID, tabID: target.tabID,
                                         surfaceID: target.surfaceID)
    }) {
        self.resolve = resolve
    }

    public func offer(_ choice: GhosttyDiscovery.Choice) throws -> UUID {
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        offers = offers.filter { now >= $0.value.issued && now - $0.value.issued < offerLifetime }
        guard offers.count < 256 else { throw Failure.tooManyOffers }
        let handle = UUID()
        let target = GhosttyTarget(choice)
        offers[handle] = (target, now, revision)
        return handle
    }

    public func bindApproved(_ handle: UUID) throws -> SessionRef {
        lock.lock()
        let offer = offers.removeValue(forKey: handle)
        lock.unlock()
        let now = DispatchTime.now().uptimeNanoseconds
        guard let offer, now >= offer.issued, now - offer.issued < offerLifetime else {
            throw Failure.staleHandle
        }
        try resolve(offer.target)
        lock.lock()
        defer { lock.unlock() }
        guard revision == offer.revision else { throw Failure.staleHandle }
        if let id = byTarget[offer.target], let session = sessions[id], session.active {
            return SessionRef(id: id, generation: session.generation)
        }
        sessions = sessions.filter { $0.value.active }
        guard sessions.count < 256 else { throw Failure.tooManySessions }
        let ref = SessionRef(id: UUID(), generation: 1)
        sessions[ref.id] = (offer.target, ref.generation, true)
        byTarget[offer.target] = ref.id
        return ref
    }

    public func revalidate(_ ref: SessionRef) throws -> GhosttyTarget {
        lock.lock()
        let session = sessions[ref.id]
        lock.unlock()
        guard let session, session.active, session.generation == ref.generation else {
            throw Failure.staleSession
        }
        do { try resolve(session.target) }
        catch {
            invalidate(ref)
            throw Failure.staleSession
        }
        lock.lock()
        defer { lock.unlock() }
        guard let current = sessions[ref.id], current.active,
              current.generation == ref.generation else { throw Failure.staleSession }
        return current.target
    }

    public func invalidate(_ ref: SessionRef) {
        lock.lock()
        defer { lock.unlock() }
        guard var current = sessions[ref.id], current.active,
              current.generation == ref.generation else { return }
        current.generation += 1
        current.active = false
        sessions[ref.id] = current
        byTarget.removeValue(forKey: current.target)
        revision += 1
        offers.removeAll()
    }
}
