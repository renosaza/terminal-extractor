import AppKit
import Foundation

private struct Request: Decodable {
    struct Choice: Decodable {
        let handle: String
        let label: String
    }

    let title: String
    let choices: [Choice]
    let clipboardExportAvailable: Bool

    enum CodingKeys: String, CodingKey {
        case title, choices
        case clipboardExportAvailable = "clipboard_export_available"
    }
}

private struct Approval: Encodable {
    let handle: String
    let scope: String
    let clipboardExport: Bool

    enum CodingKeys: String, CodingKey {
        case handle, scope
        case clipboardExport = "clipboard_export"
    }
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
    let request = try JSONDecoder().decode(Request.self, from: data)
    guard !request.title.isEmpty, request.title.count <= 160,
          !request.choices.isEmpty, request.choices.count <= 256,
          safeLabel(request.title) else {
        throw CocoaError(.fileReadCorruptFile)
    }
    var handles = Set<UUID>()
    for choice in request.choices {
        guard let handle = UUID(uuidString: choice.handle), handles.insert(handle).inserted,
              !choice.label.isEmpty, choice.label.count <= 256,
              safeLabel(choice.label) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
    return request
}

@MainActor
private func ask(_ request: Request) -> Approval? {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.finishLaunching()

    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 480, height: 28), pullsDown: false)
    picker.setAccessibilityLabel("Ghostty window, tab, and pane")
    picker.addItem(withTitle: "Choose a Ghostty pane…")
    picker.item(at: 0)?.isEnabled = false
    for choice in request.choices {
        picker.addItem(withTitle: choice.label)
    }
    picker.selectItem(at: 0)

    let clipboard = NSButton(checkboxWithTitle: "Allow screen export through clipboard", target: nil, action: nil)
    clipboard.setAccessibilityLabel("Allow Ghostty screen export through clipboard")
    clipboard.isEnabled = request.clipboardExportAvailable
    let accessory = NSStackView(views: [picker, clipboard])
    accessory.orientation = .vertical
    accessory.spacing = 8
    accessory.frame = NSRect(x: 0, y: 0, width: 480, height: 68)

    let alert = NSAlert()
    alert.messageText = request.title
    alert.informativeText = "Choose one pane and scope. Screen export briefly changes the clipboard and may be visible to clipboard watchers. Input is unavailable."
    alert.accessoryView = accessory
    alert.addButton(withTitle: "Select for read")
    alert.addButton(withTitle: "Select for read + control")
    alert.addButton(withTitle: "Cancel")
    app.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    let index = picker.indexOfSelectedItem
    guard index > 0, index <= request.choices.count else { return nil }
    switch response {
    case .alertFirstButtonReturn:
        return Approval(handle: request.choices[index - 1].handle, scope: "read",
                        clipboardExport: clipboard.state == .on && clipboard.isEnabled)
    case .alertSecondButtonReturn:
        return Approval(handle: request.choices[index - 1].handle, scope: "control",
                        clipboardExport: clipboard.state == .on && clipboard.isEnabled)
    default:
        return nil
    }
}

private let approval = await MainActor.run { (try? readRequest()).flatMap { ask($0) } }
if let approval, let data = try? JSONEncoder().encode(approval) {
    print(String(decoding: data, as: UTF8.self))
} else {
    print(#"{"cancelled":true}"#)
}
