import AppKit
import Foundation

private struct Request: Decodable {
    struct Choice: Decodable {
        let handle: String
        let label: String
    }

    let title: String
    let choices: [Choice]
}

private struct Approval: Encodable {
    let handle: String
    let scope: String
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

    let alert = NSAlert()
    alert.messageText = request.title
    alert.informativeText = "Choose one Ghostty pane and scope. Terminal read and input are not available yet."
    alert.accessoryView = picker
    alert.addButton(withTitle: "Select for read")
    alert.addButton(withTitle: "Select for read + control")
    alert.addButton(withTitle: "Cancel")
    app.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    let index = picker.indexOfSelectedItem
    guard index > 0, index <= request.choices.count else { return nil }
    switch response {
    case .alertFirstButtonReturn:
        return Approval(handle: request.choices[index - 1].handle, scope: "read")
    case .alertSecondButtonReturn:
        return Approval(handle: request.choices[index - 1].handle, scope: "control")
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
