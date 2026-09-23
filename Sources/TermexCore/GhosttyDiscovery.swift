import AppKit
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

    public enum Failure: Error { case notFound, malformed }

    public static func list() throws -> [Choice] {
        guard let reader = try AppleEventReader(bundleID: "com.mitchellh.ghostty") else { return [] }
        var choices: [Choice] = []
        var identities = Set<[String]>()
        for window in try reader.items(reader.get(reader.all("Gwnd"))) {
            let windowID = try reader.text("ID  ", of: window)
            let windowName = try reader.text("pnam", of: window)
            for tab in try reader.items(reader.get(reader.all("Gtab", in: window))) {
                let tabID = try reader.text("ID  ", of: tab)
                let tabName = try reader.text("pnam", of: tab)
                for surface in try reader.items(reader.get(reader.all("Gtrm", in: tab))) {
                    let surfaceID = try reader.text("ID  ", of: surface)
                    let surfaceName = try reader.text("pnam", of: surface)
                    guard !windowID.isEmpty, !tabID.isEmpty, !surfaceID.isEmpty,
                          identities.insert([windowID, tabID, surfaceID]).inserted,
                          choices.count < 256 else { throw Failure.malformed }
                    choices.append(Choice(appInstanceID: reader.instanceID, windowID: windowID,
                                          windowName: windowName, tabID: tabID, tabName: tabName,
                                          surfaceID: surfaceID, surfaceName: surfaceName))
                }
            }
        }
        try reader.checkInstance()
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

    static func exportScreen(_ target: GhosttyTarget) throws {
        guard let reader = try AppleEventReader(bundleID: "com.mitchellh.ghostty"),
              reader.instanceID == target.appInstanceID else { throw Failure.notFound }
        var matches: [NSAppleEventDescriptor] = []
        for window in try reader.items(reader.get(reader.all("Gwnd")))
        where try reader.text("ID  ", of: window) == target.windowID {
            for tab in try reader.items(reader.get(reader.all("Gtab", in: window)))
            where try reader.text("ID  ", of: tab) == target.tabID {
                for surface in try reader.items(reader.get(reader.all("Gtrm", in: tab)))
                where try reader.text("ID  ", of: surface) == target.surfaceID {
                    matches.append(surface)
                }
            }
        }
        guard matches.count == 1 else { throw Failure.notFound }
        try reader.checkInstance()
        guard try reader.performAction("write_screen_file:copy", on: matches[0]) else {
            throw Failure.notFound
        }
        try reader.checkInstance()
    }
}
