import Darwin
import Foundation
import MCP
import TermexCore

@main
struct TermexMCP {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 1 || (args.count == 3 && args[1] == "--socket") else {
            fatalError("usage: termex-mcp [--socket private-path]")
        }
        let path = args.count == 3 ? args[2] : LocalIPC.defaultPath
        let preferences = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("TERMEX_") }
        let fd = try LocalIPC.connect(to: path)
        defer { Darwin.close(fd) }
        let request = try JSONSerialization.data(withJSONObject: [
            "op": "resolve_preferences", "environment": preferences,
        ])
        try LocalIPC.writeFrame(request, to: fd)
        guard let selected = try JSONSerialization.jsonObject(with: LocalIPC.readFrame(fd)) as? [String: String],
              selected.count == 3,
              let app = selected["terminal_app"],
              let policy = selected["attach_policy"],
              let backend = selected["new_session_backend"] else { throw LocalIPC.Failure.invalidFrame }

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
            )])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard parameters.name == "terminal_capabilities", parameters.arguments?.isEmpty ?? true else {
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
