import AppKit
import Foundation

private enum Request {
    struct Choice {
        let handle: String
        let label: String
    }
    case ghostty(title: String, choices: [Choice])
    case terminalManagedNew(nonce: String)
}

private struct Approval: Encodable {
    let handle: String
    let scope: String
}

private struct NewShellConfirmation: Encodable {
    let kind = "terminal_managed_new"
    let confirmed = true
    let nonce: String
}

private func safeLabel(_ text: String) -> Bool {
    !text.unicodeScalars.contains {
        CharacterSet.controlCharacters.contains($0) || $0.properties.generalCategory == .format
    }
}

private func readRequest() throws -> Request {
    var data = Data()
    while let chunk = try FileHandle.standardInput.read(upToCount: 4096), !chunk.isEmpty {
        guard data.count + chunk.count <= 64 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        data.append(chunk)
    }
    let object = try JSONSerialization.jsonObject(with: data)
    guard let fields = object as? [String: Any] else {
        throw CocoaError(.fileReadCorruptFile)
    }
    if fields["kind"] != nil {
        guard Set(fields.keys) == ["kind", "nonce"],
              fields["kind"] as? String == "terminal_managed_new",
              let nonce = fields["nonce"] as? String,
              let id = UUID(uuidString: nonce), nonce == id.uuidString else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return .terminalManagedNew(nonce: nonce)
    }
    guard Set(fields.keys) == ["title", "choices"],
          let title = fields["title"] as? String,
          !title.isEmpty, title.count <= 160, safeLabel(title),
          let rows = fields["choices"] as? [[String: Any]],
          !rows.isEmpty, rows.count <= 256 else { throw CocoaError(.fileReadCorruptFile) }
    var handles = Set<UUID>()
    var choices: [Request.Choice] = []
    for row in rows {
        guard Set(row.keys) == ["handle", "label"],
              let text = row["handle"] as? String, let handle = UUID(uuidString: text),
              handles.insert(handle).inserted,
              let label = row["label"] as? String,
              !label.isEmpty, label.count <= 256, safeLabel(label) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        choices.append(.init(handle: text, label: label))
    }
    return .ghostty(title: title, choices: choices)
}

@MainActor
private func askGhostty(title: String, choices: [Request.Choice]) -> Approval? {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 480, height: 28), pullsDown: false)
    picker.setAccessibilityLabel("Ghostty window, tab, and pane")
    picker.addItem(withTitle: "Choose a Ghostty pane…")
    picker.item(at: 0)?.isEnabled = false
    for choice in choices {
        picker.addItem(withTitle: choice.label)
    }
    picker.selectItem(at: 0)

    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = "Choose one Ghostty pane and scope. Terminal read and input are not available yet."
    alert.accessoryView = picker
    alert.addButton(withTitle: "Select for read")
    alert.addButton(withTitle: "Select for read + control")
    alert.addButton(withTitle: "Cancel")
    app.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    let index = picker.indexOfSelectedItem
    guard index > 0, index <= choices.count else { return nil }
    switch response {
    case .alertFirstButtonReturn:
        return Approval(handle: choices[index - 1].handle, scope: "read")
    case .alertSecondButtonReturn:
        return Approval(handle: choices[index - 1].handle, scope: "control")
    default:
        return nil
    }
}

@MainActor
private func ask(_ request: Request) -> Data? {
    switch request {
    case let .ghostty(title, choices):
        return askGhostty(title: title, choices: choices).flatMap { try? JSONEncoder().encode($0) }
    case let .terminalManagedNew(nonce):
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        let alert = NSAlert()
        alert.messageText = "Create a new managed shell in Terminal.app?"
        alert.informativeText = "This creates a new shell in Terminal.app for the requesting local client. It does not share an existing session."
        alert.addButton(withTitle: "Create new shell")
        alert.addButton(withTitle: "Cancel")
        app.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return try? JSONEncoder().encode(NewShellConfirmation(nonce: nonce))
    }
}

private let approval = await MainActor.run { (try? readRequest()).flatMap { ask($0) } }
if let approval {
    print(String(decoding: approval, as: UTF8.self))
} else {
    print(#"{"cancelled":true}"#)
}
