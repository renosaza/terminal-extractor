import MCP

@main
struct TermexMCPProbe {
    static func main() async throws {
        let server = Server(
            name: "termex-feasibility",
            version: "0.0.0",
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: [Tool(
                name: "probe_accept",
                description: "Check a bounded structured MCP response",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["text": .object(["type": .string("string")])]),
                    "required": .array([.string("text")]),
                ]),
                outputSchema: .object([
                    "type": .string("object"),
                    "properties": .object(["ok": .object(["type": .string("boolean")])]),
                    "required": .array([.string("ok")]),
                ])
            )])
        }
        await server.withMethodHandler(CallTool.self) { parameters in
            guard parameters.name == "probe_accept",
                  parameters.arguments?["text"]?.stringValue != nil else {
                return .init(content: [.text(text: "invalid request", annotations: nil, _meta: nil)], isError: true)
            }
            return .init(
                content: [.text(text: "accepted", annotations: nil, _meta: nil)],
                structuredContent: .object(["ok": .bool(true)]),
                isError: false
            )
        }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
