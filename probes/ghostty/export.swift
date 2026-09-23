import AppKit
import Foundation

// Usage: swift export.swift <window-id> <terminal-id> <write_screen_file:copy|write_scrollback_file:copy>
guard CommandLine.arguments.count == 4,
      CommandLine.arguments[1].range(of: #"^tab-group-[0-9a-f]+$"#, options: .regularExpression) != nil,
      UUID(uuidString: CommandLine.arguments[2]) != nil,
      ["write_screen_file:copy", "write_scrollback_file:copy"].contains(CommandLine.arguments[3]) else {
    fatalError("expected window ID, terminal ID, and supported action")
}

let board = NSPasteboard.general
let original = try (board.pasteboardItems ?? []).map { item in
    try item.types.map { type -> (NSPasteboard.PasteboardType, Data) in
        guard let data = item.data(forType: type) else { throw CocoaError(.fileReadUnknown) }
        return (type, data)
    }
}
let before = board.changeCount
let script = """
tell application id "com.mitchellh.ghostty"
    set t to terminal id "\(CommandLine.arguments[2])" of window id "\(CommandLine.arguments[1])"
    perform action "\(CommandLine.arguments[3])" on t
end tell
"""
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
process.arguments = ["-e", script]
let output = Pipe()
process.standardOutput = output
process.standardError = output
try process.run()
process.waitUntilExit()
let response = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
let after = board.changeCount
let path = board.string(forType: .string)
let validExport = process.terminationStatus == 0
    && response.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    && after != before
    && path?.hasPrefix("/") == true
let attributes = validExport ? try? FileManager.default.attributesOfItem(atPath: path!) : nil
let ownedFile = attributes?[.type] as? FileAttributeType == .typeRegular
    && attributes?[.ownerAccountID] as? NSNumber == NSNumber(value: getuid())

// Restore only the clipboard value written by this action; never overwrite a later writer.
var restored = false
if validExport && ownedFile && board.changeCount == after && board.string(forType: .string) == path {
    let items = original.map { fields -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in fields { item.setData(data, forType: type) }
        return item
    }
    board.clearContents()
    restored = items.isEmpty || board.writeObjects(items)
}

guard validExport, ownedFile, restored, let path, let attributes else {
    fatalError("action/export/clipboard validation failed")
}
print("path=\(path) bytes=\(attributes[.size] ?? "?") clipboard_restored=\(restored)")
