import Foundation

public enum TerminalDiscovery {
    public struct Choice: Codable, Equatable {
        public let appInstanceID: String
        public let windowID: String
        public let windowName: String
        public let tabOrdinal: Int
        public let tty: String
    }

    public struct Snapshot: Codable, Equatable {
        public let appInstanceID: String?
        public let windowIDs: Set<String>
        public let choices: [Choice]
    }

    public enum Failure: Error { case notFound, malformed }

    public static func list() throws -> [Choice] {
        try snapshot().choices
    }

    public static func snapshot() throws -> Snapshot {
        guard let reader = try AppleEventReader(bundleID: "com.apple.Terminal") else {
            return Snapshot(appInstanceID: nil, windowIDs: [], choices: [])
        }
        var choices: [Choice] = []
        var windowIDs = Set<String>()
        var identities = Set<[String]>()
        for window in try reader.items(reader.get(reader.all("cwin"))) {
            let number = try reader.value("ID  ", of: window)
            guard number.descriptorType == typeSInt32, number.int32Value > 0 else { throw Failure.malformed }
            let windowID = String(number.int32Value)
            guard windowIDs.insert(windowID).inserted else { throw Failure.malformed }
            let windowName = try reader.text("pnam", of: window)
            for (index, tab) in try reader.items(reader.get(reader.all("ttab", in: window))).enumerated() {
                let tty = try reader.text("ttty", of: tab)
                guard !tty.isEmpty, identities.insert([windowID, tty]).inserted,
                      choices.count < 256 else { throw Failure.malformed }
                choices.append(Choice(appInstanceID: reader.instanceID, windowID: windowID,
                                      windowName: windowName, tabOrdinal: index + 1, tty: tty))
            }
        }
        try reader.checkInstance()
        return Snapshot(appInstanceID: reader.instanceID, windowIDs: windowIDs, choices: choices)
    }

    /// Select only the one new window whose tab reported this fixture TTY; never use focus or order.
    public static func newWindow(before: Snapshot, after: Snapshot, fixtureTTY: String) throws -> Choice {
        let suffix = fixtureTTY.dropFirst("/dev/ttys".count)
        guard fixtureTTY.hasPrefix("/dev/ttys"), !suffix.isEmpty,
              suffix.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              after.appInstanceID != nil,
              before.appInstanceID == nil || before.appInstanceID == after.appInstanceID,
              before.appInstanceID != nil || (before.windowIDs.isEmpty && before.choices.isEmpty),
              before.choices.allSatisfy({ $0.appInstanceID == before.appInstanceID &&
                                            before.windowIDs.contains($0.windowID) }),
              after.choices.allSatisfy({ $0.appInstanceID == after.appInstanceID &&
                                           after.windowIDs.contains($0.windowID) }),
              !before.choices.contains(where: { $0.tty == fixtureTTY }) else {
            throw Failure.malformed
        }
        let matches = after.choices.filter { $0.tty == fixtureTTY }
        guard matches.count == 1, let match = matches.first else { throw Failure.notFound }
        guard !before.windowIDs.contains(match.windowID), match.tabOrdinal == 1,
              after.choices.filter({ $0.windowID == match.windowID }).count == 1 else {
            throw Failure.malformed
        }
        return match
    }

    public static func resolve(appInstanceID: String, windowID: String, tty: String) throws -> Choice {
        // Diagnostic only: Terminal may reuse a TTY; dispatch needs a host-owned generation.
        guard let choice = try list().first(where: {
            $0.appInstanceID == appInstanceID && $0.windowID == windowID && $0.tty == tty
        }) else { throw Failure.notFound }
        return choice
    }
}
