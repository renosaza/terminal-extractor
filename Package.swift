// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "terminal-extractor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "termex-host", targets: ["TermexHost"]),
        .executable(name: "termex-mcp", targets: ["TermexMCP"]),
        .executable(name: "termex-consent", targets: ["TermexConsent"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
    ],
    targets: [
        .target(name: "TermexCore"),
        .executableTarget(name: "TermexHost", dependencies: ["TermexCore"]),
        .executableTarget(name: "TermexConsent"),
        .executableTarget(name: "TermexMCP", dependencies: [
            "TermexCore", .product(name: "MCP", package: "swift-sdk"),
        ]),
        .executableTarget(name: "TermexConfigCheck", dependencies: ["TermexCore"], path: "Tests/ConfigCheck"),
        .executableTarget(name: "TermexRegistryCheck", dependencies: ["TermexCore"], path: "Tests/RegistryCheck"),
        .executableTarget(name: "TermexExportFileCheck", dependencies: ["TermexCore"], path: "Tests/ExportFileCheck"),
    ]
)
