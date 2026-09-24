import Foundation

struct CheckFailure: Error { let name: String }
func require(_ condition: @autoclosure () -> Bool, _ name: String) throws {
    guard condition() else { throw CheckFailure(name: name) }
}

let root = URL(fileURLWithPath: "/tmp").appendingPathComponent("te-sink-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: 0o700])
defer { try? FileManager.default.removeItem(at: root) }
let sink = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    .appendingPathComponent("termex-capture-sink")

func fixture(_ input: Data, limit: Int, gap: Bool) throws {
    let directory = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    let paths = ["segment", "ready", "gap", "clean_eof"].map { directory.appendingPathComponent($0) }
    let process = Process()
    process.executableURL = sink
    process.arguments = ["--sink"] + paths.map(\.path) + [String(limit)]
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    stdin.fileHandleForWriting.write(input)
    try stdin.fileHandleForWriting.close()
    process.waitUntilExit()
    try require(process.terminationStatus == 0, "sink exit")
    try require(FileManager.default.fileExists(atPath: paths[1].path), "ready marker")
    let segment = try Data(contentsOf: paths[0])
    try require(segment == input.prefix(limit), "exact segment bytes")
    try require(FileManager.default.fileExists(atPath: paths[2].path) == gap, "gap marker")
    try require(FileManager.default.fileExists(atPath: paths[3].path) != gap, "clean EOF marker")
}

try fixture(Data([0x41, 0x0d, 0x42, 0x1b, 0x5b, 0x33, 0x31, 0x6d, 0xe2, 0x82, 0xac, 0x0a]), limit: 1024, gap: false)
try fixture(Data(repeating: 0x58, count: 200), limit: 64, gap: true)
print("exact_bytes=PASS quota_gap=PASS clean_eof=PASS")
