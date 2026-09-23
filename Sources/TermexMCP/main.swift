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
        let fd = try LocalIPC.connect(to: path)
        defer { Darwin.close(fd) }
        try LocalIPC.writeFrame(Data(#"{"op":"ping"}"#.utf8), to: fd)
        guard let reply = try JSONSerialization.jsonObject(with: LocalIPC.readFrame(fd)) as? [String: Bool],
              reply == ["ok": true] else { throw LocalIPC.Failure.invalidFrame }

        let server = Server(name: "terminal-extractor", version: "0.0.0",
                            capabilities: .init(tools: .init(listChanged: false)))
        await server.withMethodHandler(ListTools.self) { _ in .init(tools: []) }
        try await server.start(transport: StdioTransport())
        await server.waitUntilCompleted()
    }
}
