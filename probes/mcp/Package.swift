// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "termex-mcp-probe",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .executableTarget(name: "TermexMCPProbe", dependencies: [
            .product(name: "MCP", package: "swift-sdk"),
        ]),
    ]
)
