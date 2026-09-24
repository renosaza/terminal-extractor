import AppKit
import ApplicationServices
import Foundation

struct AppleEventReader {
    enum Failure: Error { case unavailable, ambiguousApp, changedApp, malformed }

    let pid: pid_t
    let instanceID: String
    private let bundleID: String

    init?(bundleID: String) throws {
        guard let app = try Self.runningApp(bundleID) else { return nil }
        self.bundleID = bundleID
        pid = app.processIdentifier
        guard let launched = app.launchDate else { throw Failure.unavailable }
        instanceID = "\(pid):\(launched.timeIntervalSince1970)"
    }

    private static func runningApp(_ bundleID: String) throws -> NSRunningApplication? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        guard apps.count <= 1 else { throw Failure.ambiguousApp }
        return apps.first
    }

    func checkInstance() throws {
        guard let app = try Self.runningApp(bundleID), let launched = app.launchDate,
              "\(app.processIdentifier):\(launched.timeIntervalSince1970)" == instanceID else {
            throw Failure.changedApp
        }
    }

    private static func code(_ text: String) -> OSType {
        text.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }

    private func specifier(_ desired: OSType, in container: NSAppleEventDescriptor,
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

    func all(_ kind: String, in container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try specifier(Self.code(kind), in: container, form: OSType(formAbsolutePosition),
                      dataType: typeAbsoluteOrdinal, value: Self.code("all "))
    }

    private func property(_ name: String, of object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try specifier(typeProperty, in: object, form: OSType(formPropertyID),
                      dataType: typeType, value: Self.code(name))
    }

    func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        // A PID target fails if the app exits; a bundle-ID AppleScript could relaunch it.
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

    func performAction(_ action: String, on terminal: NSAppleEventDescriptor) throws -> Bool {
        let event = NSAppleEventDescriptor(eventClass: Self.code("Ghst"), eventID: Self.code("PfAc"),
                                           targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(string: action), forKeyword: keyDirectObject)
        event.setParam(terminal, forKeyword: Self.code("GonT"))
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: [.waitForReply], timeout: 5) }
        catch { throw Failure.unavailable }
        guard reply.paramDescriptor(forKeyword: keyErrorNumber) == nil,
              let result = reply.paramDescriptor(forKeyword: keyDirectObject) else {
            throw Failure.unavailable
        }
        return result.booleanValue
    }

    func items(_ descriptor: NSAppleEventDescriptor) throws -> [NSAppleEventDescriptor] {
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

    func value(_ name: String, of object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        try get(property(name, of: object))
    }

    func text(_ name: String, of object: NSAppleEventDescriptor) throws -> String {
        guard let value = try value(name, of: object).stringValue else { throw Failure.malformed }
        return value
    }
}
