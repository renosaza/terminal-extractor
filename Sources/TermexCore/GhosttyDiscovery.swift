import AppKit
import ApplicationServices
import Foundation

public enum GhosttyDiscovery {
    public struct Choice: Codable, Equatable {
        public let appInstanceID: String
        public let windowID: String
        public let windowName: String
        public let tabID: String
        public let tabName: String
        public let surfaceID: String
        public let surfaceName: String
    }

    public enum Failure: Error { case unavailable, ambiguousApp, changedApp, notFound, malformed }

    private struct Instance {
        let pid: pid_t
        let id: String
    }

    private static func instance() throws -> Instance? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.mitchellh.ghostty")
        guard apps.count <= 1 else { throw Failure.ambiguousApp }
        guard let app = apps.first else { return nil }
        guard let launched = app.launchDate else { throw Failure.unavailable }
        return Instance(pid: app.processIdentifier,
                        id: "\(app.processIdentifier):\(launched.timeIntervalSince1970)")
    }

    private static func code(_ text: String) -> OSType {
        text.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }

    private static func specifier(_ desired: OSType, in container: NSAppleEventDescriptor,
                                  form: OSType, dataType: OSType, value: OSType) throws -> NSAppleEventDescriptor {
        var value = value
        var data = AEDesc()
        guard withUnsafePointer(to: &value, { AECreateDesc(dataType, $0, 4, &data) }) == noErr else {
            throw Failure.malformed
        }
        defer { AEDisposeDesc(&data) }
        guard let parent = container.aeDesc else { throw Failure.malformed }
        var parentCopy = parent.pointee
        var object = AEDesc()
        guard CreateObjSpecifier(desired, &parentCopy, form, &data, false, &object) == noErr else {
            throw Failure.malformed
        }
        return NSAppleEventDescriptor(aeDescNoCopy: &object)
    }

    private static func all(_ kind: String, in container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try specifier(code(kind), in: container, form: OSType(formAbsolutePosition),
                      dataType: typeAbsoluteOrdinal, value: code("all "))
    }

    private static func property(_ name: String, of object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try specifier(typeProperty, in: object, form: OSType(formPropertyID),
                      dataType: typeType, value: code(name))
    }

    private static func get(_ object: NSAppleEventDescriptor, from pid: pid_t) throws -> NSAppleEventDescriptor {
        // A PID target fails if Ghostty exits; a bundle-ID AppleScript could relaunch it.
        let event = NSAppleEventDescriptor(eventClass: kAECoreSuite, eventID: kAEGetData,
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: keyDirectObject)
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply], timeout: 5) }
        catch { throw Failure.unavailable }
        guard reply.paramDescriptor(forKeyword: keyErrorNumber) == nil,
              let value = reply.paramDescriptor(forKeyword: keyDirectObject) else {
            throw Failure.unavailable
        }
        return value
    }

    private static func items(_ descriptor: NSAppleEventDescriptor) throws -> [NSAppleEventDescriptor] {
        guard descriptor.descriptorType == typeAEList,
              descriptor.numberOfItems >= 0, descriptor.numberOfItems <= 256 else {
            throw Failure.malformed
        }
        if descriptor.numberOfItems == 0 { return [] }
        return try (1...descriptor.numberOfItems).map {
            guard let item = descriptor.atIndex($0) else { throw Failure.malformed }
            return item
        }
    }

    private static func text(_ name: String, of object: NSAppleEventDescriptor, from pid: pid_t) throws -> String {
        guard let value = try get(property(name, of: object), from: pid).stringValue else {
            throw Failure.malformed
        }
        return value
    }

    public static func list() throws -> [Choice] {
        guard let app = try instance() else { return [] }
        var choices: [Choice] = []
        var identities = Set<[String]>()
        for window in try items(get(all("Gwnd", in: .null()), from: app.pid)) {
            let windowID = try text("ID  ", of: window, from: app.pid)
            let windowName = try text("pnam", of: window, from: app.pid)
            for tab in try items(get(all("Gtab", in: window), from: app.pid)) {
                let tabID = try text("ID  ", of: tab, from: app.pid)
                let tabName = try text("pnam", of: tab, from: app.pid)
                for surface in try items(get(all("Gtrm", in: tab), from: app.pid)) {
                    let surfaceID = try text("ID  ", of: surface, from: app.pid)
                    let surfaceName = try text("pnam", of: surface, from: app.pid)
                    guard !windowID.isEmpty, !tabID.isEmpty, !surfaceID.isEmpty,
                          identities.insert([windowID, tabID, surfaceID]).inserted,
                          choices.count < 256 else { throw Failure.malformed }
                    choices.append(Choice(appInstanceID: app.id, windowID: windowID,
                                          windowName: windowName, tabID: tabID, tabName: tabName,
                                          surfaceID: surfaceID, surfaceName: surfaceName))
                }
            }
        }
        guard try instance()?.id == app.id else { throw Failure.changedApp }
        return choices
    }

    public static func resolve(appInstanceID: String, windowID: String, tabID: String,
                               surfaceID: String) throws -> Choice {
        guard let choice = try list().first(where: {
            $0.appInstanceID == appInstanceID && $0.windowID == windowID &&
                $0.tabID == tabID && $0.surfaceID == surfaceID
        }) else { throw Failure.notFound }
        return choice
    }
}
