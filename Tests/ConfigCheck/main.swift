import Foundation
import TermexCore

@main
struct ConfigCheck {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("termex-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("config.json")
        let initial = try LocalConfig.load(at: file)
        precondition(initial.terminalApp == .terminal)
        precondition((try? LocalConfig.load(at: file, requireExisting: true)) == nil)
        for app in ["terminal", "ghostty"] {
            for policy in ["existing", "new", "ask"] {
                for backend in ["managed_tmux", "native"] {
                    let json = """
                    {"schema_version":1,"terminal_app":"\(app)","attach_policy":"\(policy)","new_session_backend":"\(backend)"}
                    """
                    let item = try LocalConfig.decode(Data(json.utf8))
                    precondition(item.terminalApp.rawValue == app)
                    precondition(item.attachPolicy.rawValue == policy)
                    precondition(item.newSessionBackend.rawValue == backend)
                }
            }
        }

        let document = Data(#"{"schema_version":1,"terminal_app":"ghostty","attach_policy":"existing"}"#.utf8)
        let config = try LocalConfig.decode(document)
        precondition(config.terminalApp == .ghostty && config.attachPolicy == .existing)
        precondition(config.newSessionBackend == .managed_tmux)
        try config.save(at: file)
        let saved = try LocalConfig.load(at: file)
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        precondition(saved == config && mode == 0o600)

        let selected = try config.applyingPreferences([
            "TERMEX_TERMINAL": "terminal", "TERMEX_ATTACH_POLICY": "new", "TERMEX_NEW_BACKEND": "native",
        ])
        precondition(selected.terminalApp == .terminal && selected.attachPolicy == .new)
        precondition(selected.newSessionBackend == .native && selected.allowedApps == config.allowedApps)
        let unchanged = try LocalConfig.load(at: file)
        precondition(unchanged == config)

        for invalid in [
            #"{"schema_version":2}"#,
            #"{"schema_version":1,"terminal_app":"other"}"#,
            #"{"schema_version":1,"recording":{"consent_required":false}}"#,
            #"{"schema_version":1,"recording":{"unknown":1}}"#,
            #"{"terminal_app":"ghostty"}"#,
            #"{"schema_version":1,"allowed_apps":["terminal"],"terminal_app":"ghostty"}"#,
            #"{"schema_version":1,"unexpected":true}"#,
            #"{"schema_version":1,"recording":42}"#,
            #"{"schema_version":1"#,
        ] {
            precondition((try? LocalConfig.decode(Data(invalid.utf8))) == nil)
        }
        precondition((try? config.applyingPreferences(["TERMEX_ALLOWED_APPS": "ghostty"])) == nil)
        precondition((try? config.applyingPreferences(["TERMEX_TERMINAL": "other"])) == nil)
        let terminalOnly = try LocalConfig.decode(Data(#"{"schema_version":1,"allowed_apps":["terminal"]}"#.utf8))
        precondition((try? terminalOnly.applyingPreferences(["TERMEX_TERMINAL": "ghostty"])) == nil)
        var invalidSave = config
        invalidSave.recording.consentRequired = false
        precondition((try? invalidSave.save(at: file)) == nil)
        let stillSaved = try LocalConfig.load(at: file)
        precondition(stillSaved == config)
        print("defaults=PASS matrix=PASS atomic_save=PASS env_policy=PASS invalid_config=PASS")
    }
}
