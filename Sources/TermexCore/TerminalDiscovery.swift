import Foundation

public enum TerminalDiscovery {
    public struct Choice: Codable, Equatable {
        public let appInstanceID: String
        public let windowID: String
        public let windowName: String
        public let tabOrdinal: Int
        public let tty: String
    }

    public enum Failure: Error { case notFound, malformed }

    public static func list() throws -> [Choice] {
        guard let reader = try AppleEventReader(bundleID: "com.apple.Terminal") else { return [] }
        var choices: [Choice] = []
        var identities = Set<[String]>()
        for window in try reader.items(reader.get(reader.all("cwin"))) {
            let number = try reader.value("ID  ", of: window)
            guard number.descriptorType == typeSInt32, number.int32Value > 0 else { throw Failure.malformed }
            let windowID = String(number.int32Value)
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
        return choices
    }

    public static func resolve(appInstanceID: String, windowID: String, tty: String) throws -> Choice {
        // Diagnostic only: Terminal may reuse a TTY; dispatch needs a host-owned generation.
        guard let choice = try list().first(where: {
            $0.appInstanceID == appInstanceID && $0.windowID == windowID && $0.tty == tty
        }) else { throw Failure.notFound }
        return choice
    }
}
