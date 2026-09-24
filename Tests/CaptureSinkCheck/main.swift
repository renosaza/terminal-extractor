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

func fixture(_ input: Data, limit: Int, gap: Bool, denyGap: Bool = false) throws {
    let directory = root.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                            attributes: [.posixPermissions: 0o700])
    defer {
        if denyGap {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }
    let paths = ["segment", "ready", "gap", "clean_eof"].map { directory.appendingPathComponent($0) }
    let process = Process()
    process.executableURL = sink
    process.arguments = ["--sink"] + paths.map(\.path) + [String(limit)]
    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    defer {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
    }
    if denyGap {
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: paths[1].path) {
            Thread.sleep(forTimeInterval: 0.02)
        }
        try require(FileManager.default.fileExists(atPath: paths[1].path), "ready before denied gap")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    }
    stdin.fileHandleForWriting.write(input)
    try stdin.fileHandleForWriting.close()
    process.waitUntilExit()
    try require(process.terminationStatus == (denyGap ? 1 : 0), "sink exit after gap marker failure")
    try require(FileManager.default.fileExists(atPath: paths[1].path), "ready marker")
    let readyPID = try String(contentsOf: paths[1], encoding: .utf8)
    try require(Int32(readyPID) != nil, "ready sink PID")
    let segment = try Data(contentsOf: paths[0])
    try require(segment == input.prefix(limit), "exact segment bytes")
    try require(FileManager.default.fileExists(atPath: paths[2].path) == (gap && !denyGap), "gap marker")
    try require(FileManager.default.fileExists(atPath: paths[3].path) == !gap, "clean EOF marker")
}

try fixture(Data([0x41, 0x0d, 0x42, 0x1b, 0x5b, 0x33, 0x31, 0x6d, 0xe2, 0x82, 0xac, 0x0a]), limit: 1024, gap: false)
try fixture(Data(repeating: 0x58, count: 200), limit: 64, gap: true)
try fixture(Data(repeating: 0x58, count: 200), limit: 64, gap: true, denyGap: true)
print("exact_bytes=PASS quota_gap=PASS denied_gap_exit=PASS clean_eof=PASS")
