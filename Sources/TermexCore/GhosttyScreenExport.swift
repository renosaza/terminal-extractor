import AppKit
import Foundation

/// Serialized, bounded one-shot screen export. Ghostty 1.3.1 leaks directory FDs per action.
public enum GhosttyScreenExport {
    public enum Failure: Error { case clipboardUnavailable, clipboardConflict, unavailable, rateLimited }
    public struct Snapshot {
        public let text: String
        public let observedAt: Date
    }

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var counts: [String: Int] = [:]
        var lastAction: UInt64 = 0
    }
    private static let state = State()

    public static func read(_ target: GhosttyTarget, authorized: () -> Bool) throws -> Snapshot {
        try readForExport(appInstanceID: target.appInstanceID, board: .general,
                          root: (NSTemporaryDirectory() as NSString).resolvingSymlinksInPath,
                          authorized: authorized) {
            try GhosttyDiscovery.exportScreen(target)
        }
    }

    package static func readForExport(appInstanceID: String, board: NSPasteboard, root: String,
                                      authorized: () -> Bool, export: () throws -> Void) throws -> Snapshot {
        state.lock.lock()
        defer { state.lock.unlock() }
        let now = DispatchTime.now().uptimeNanoseconds
        // ponytail: cap the installed Ghostty export FD leak; remove when a fixed release is verified.
        guard state.counts[appInstanceID, default: 0] < 64,
              (state.lastAction == 0 || (now >= state.lastAction && now - state.lastAction >= 5_000_000_000)) else {
            throw Failure.rateLimited
        }
        let before = board.changeCount
        let existingItems = board.pasteboardItems ?? []
        guard existingItems.count <= 32,
              !existingItems.isEmpty || board.types?.isEmpty != false else {
            throw Failure.clipboardUnavailable
        }
        var saved: [[(NSPasteboard.PasteboardType, Data)]] = []
        var total = 0
        for item in existingItems {
            var fields: [(NSPasteboard.PasteboardType, Data)] = []
            guard !item.types.isEmpty else { throw Failure.clipboardUnavailable }
            for type in item.types {
                guard let data = item.data(forType: type), data.count <= 8 * 1024 * 1024 - total else {
                    throw Failure.clipboardUnavailable
                }
                total += data.count
                fields.append((type, data))
            }
            saved.append(fields)
        }
        let restored = try saved.map { fields -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in fields {
                guard item.setData(data, forType: type) else { throw Failure.clipboardUnavailable }
            }
            return item
        }
        let beforeDirectories = try exportDirectories(in: root)
        guard board.changeCount == before else { throw Failure.clipboardConflict }
        guard authorized() else { throw Failure.unavailable }
        guard board.changeCount == before else { throw Failure.clipboardConflict }
        let started = Date()
        state.counts[appInstanceID, default: 0] += 1
        state.lastAction = now
        let action = Result { try export() }
        let observedAt = Date()
        let after = board.changeCount
        guard after != before, let path = board.string(forType: .string) else {
            throw Failure.clipboardConflict
        }
        guard GhosttyExportFile.matchesExpectedPath(path, in: root) else {
            throw Failure.clipboardConflict
        }
        let newDirectories = Result { try exportDirectories(in: root).subtracting(beforeDirectories) }
        guard board.changeCount == after, board.string(forType: .string) == path else {
            throw Failure.clipboardConflict
        }
        board.clearContents()
        guard restored.isEmpty || board.writeObjects(restored) else { throw Failure.clipboardConflict }
        guard authorized() else { throw Failure.unavailable }
        try action.get()
        let created = try newDirectories.get()
        guard created.count == 1, created.contains(URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent) else {
            throw Failure.clipboardConflict
        }
        let bytes = try GhosttyExportFile.read(path, in: root, createdAfter: started)
        let text = String(decoding: bytes, as: UTF8.self).unicodeScalars.filter {
            $0 == "\n" || $0 == "\t" ||
                (!CharacterSet.controlCharacters.contains($0) && $0.properties.generalCategory != .format)
        }
        return Snapshot(text: String(String.UnicodeScalarView(text)), observedAt: observedAt)
    }

    private static func exportDirectories(in root: String) throws -> Set<String> {
        let names = try FileManager.default.contentsOfDirectory(atPath: root)
        guard names.count <= 10_000 else { throw Failure.unavailable }
        return Set(names.filter { GhosttyExportFile.matchesExpectedPath(root + "/" + $0 + "/screen.txt", in: root) })
    }
}
