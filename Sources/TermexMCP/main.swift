import Darwin
import Foundation
import MCP
import TermexCore

final class HostChannel: @unchecked Sendable {
    private let lock = NSLock()
    private let fd: Int32
    private var poisoned = false

    init(fd: Int32) { self.fd = fd }

    func exchange(_ request: [String: Any], timeoutSeconds: UInt64 = 5) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        guard !poisoned else { throw LocalIPC.Failure.disconnected }
        do {
            try LocalIPC.writeFrame(JSONSerialization.data(withJSONObject: request), to: fd)
            guard let response = try JSONSerialization.jsonObject(
                with: LocalIPC.readFrame(fd, timeoutSeconds: timeoutSeconds)) as? [String: Any] else {
                throw LocalIPC.Failure.invalidFrame
            }
            return response
        } catch {
            poisoned = true
            _ = Darwin.shutdown(fd, SHUT_RDWR)
            throw error
        }
    }

    func ping() { _ = try? exchange(["op": "ping"]) }
}

@main
struct TermexMCP {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 1 || (args.count == 3 && args[1] == "--socket") else {
            fatalError("usage: termex-mcp [--socket private-path]")
        }
        let path = args.count == 3 ? args[2] : LocalIPC.defaultPath
        let keys: Set<String> = ["TERMEX_TERMINAL", "TERMEX_ATTACH_POLICY", "TERMEX_NEW_BACKEND"]
        let environment = ProcessInfo.processInfo.environment
        guard environment.keys.filter({ $0.hasPrefix("TERMEX_") }).allSatisfy(keys.contains) else {
            throw LocalConfig.Failure.invalidEnvironment
        }
        let preferences = environment.filter { keys.contains($0.key) }
        let fd = try LocalIPC.connect(to: path)
        defer { Darwin.close(fd) }
        let channel = HostChannel(fd: fd)
        guard let selected = try channel.exchange(["op": "resolve_preferences", "environment": preferences]) as? [String: String],
              selected.count == 3,
              let app = selected["terminal_app"],
              let policy = selected["attach_policy"],
              let backend = selected["new_session_backend"] else { throw LocalIPC.Failure.invalidFrame }
        let keepalive = DispatchSource.makeTimerSource(queue: .global())
        keepalive.schedule(deadline: .now() + 20, repeating: 20)
        keepalive.setEventHandler { channel.ping() }
        keepalive.resume()
        defer { keepalive.cancel() }

        let server = Server(name: "terminal-extractor", version: "0.0.0",
                            capabilities: .init(tools: .init(listChanged: false)))
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(
                name: "terminal_capabilities",
                description: "Report current selection; terminal access is not available yet",
                inputSchema: .object([
                    "type": .string("object"), "properties": .object([:]),
                    "additionalProperties": .bool(false),
                ]),
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "runtime": .object(["type": .string("string")]),
                        "terminal_access": .object(["type": .string("boolean")]),
                        "terminal_app": .object(["type": .string("string")]),
                        "attach_policy": .object(["type": .string("string")]),
                        "new_session_backend": .object(["type": .string("string")]),
                    ]),
                    "required": .array(["runtime", "terminal_access", "terminal_app", "attach_policy", "new_session_backend"].map { .string($0) }),
                ])
            ), Tool(
                name: "terminal_request_access",
                description: "Ask the local user to choose one Ghostty pane and approve a scope; terminal content and input tools are not available yet",
                inputSchema: .object([
                    "type": .string("object"), "properties": .object([:]),
                    "additionalProperties": .bool(false),
                ]),
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "status": .object(["type": .string("string")]),
                        "session_id": .object(["type": .string("string")]),
                        "generation": .object(["type": .string("integer")]),
                        "scope": .object(["type": .string("string")]),
                        "terminal_access": .object(["type": .string("boolean")]),
                    ]),
                    "required": .array([.string("status")]),
                ])
            )])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard parameters.arguments?.isEmpty ?? true else {
                return .init(content: [.text(text: "invalid request", annotations: nil, _meta: nil)], isError: true)
            }
            if parameters.name == "terminal_request_access" {
                do {
                    let reply = try channel.exchange(["op": "request_ghostty_access"], timeoutSeconds: 110)
                    guard let status = reply["status"] as? String else { throw LocalIPC.Failure.invalidFrame }
                    var fields: [String: Value] = ["status": .string(status)]
                    if status == "approved" {
                        guard let id = reply["session_id"] as? String,
                              let generation = reply["generation"] as? Int,
                              let scope = reply["scope"] as? String else { throw LocalIPC.Failure.invalidFrame }
                        fields["session_id"] = .string(id)
                        fields["generation"] = .int(generation)
                        fields["scope"] = .string(scope)
                        fields["terminal_access"] = .bool(false)
                    }
                    return .init(content: [.text(text: "local selection: \(status); terminal_access=false", annotations: nil, _meta: nil)],
                                 structuredContent: .object(fields), isError: false)
                } catch {
                    return .init(content: [.text(text: "local consent unavailable", annotations: nil, _meta: nil)], isError: true)
                }
            }
            guard parameters.name == "terminal_capabilities" else {
                return .init(content: [.text(text: "invalid request", annotations: nil, _meta: nil)], isError: true)
            }
            return .init(
                content: [.text(text: "foundation; terminal_access=false; app=\(app); policy=\(policy); backend=\(backend)", annotations: nil, _meta: nil)],
                structuredContent: .object([
                    "runtime": .string("foundation"), "terminal_access": .bool(false),
                    "terminal_app": .string(app), "attach_policy": .string(policy),
                    "new_session_backend": .string(backend),
                ]), isError: false
            )
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
