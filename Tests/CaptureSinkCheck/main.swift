import Foundation
import Darwin

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
    var readyFields: [Substring] = []
    for _ in 0..<100 {
        if let marker = try? String(contentsOf: paths[1], encoding: .utf8) {
            let fields = marker.split(separator: " ", omittingEmptySubsequences: false)
            if fields.count == 3 { readyFields = fields; break }
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    try require(readyFields.count == 3, "ready process identity before input")
    guard let readyPID = Int32(readyFields[0]), let readySeconds = UInt64(readyFields[1]),
          let readyMicroseconds = UInt64(readyFields[2]) else {
        throw CheckFailure(name: "numeric ready process identity")
    }
    var processInfo = proc_bsdinfo()
    let processInfoSize = Int32(MemoryLayout<proc_bsdinfo>.size)
    try require(proc_pidinfo(readyPID, PROC_PIDTBSDINFO, 0, &processInfo, processInfoSize) == processInfoSize &&
                processInfo.pbi_pid == UInt32(readyPID) &&
                processInfo.pbi_start_tvsec == readySeconds &&
                processInfo.pbi_start_tvusec == readyMicroseconds,
                "ready marker matches live sink")
    if denyGap {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    }
    stdin.fileHandleForWriting.write(input)
    try stdin.fileHandleForWriting.close()
    process.waitUntilExit()
    try require(process.terminationStatus == (denyGap ? 1 : 0), "sink exit after gap marker failure")
    try require(FileManager.default.fileExists(atPath: paths[1].path), "ready marker")
    try require(readySeconds > 0 && readyMicroseconds < 1_000_000, "valid ready start time")
    let segment = try Data(contentsOf: paths[0])
    try require(segment == input.prefix(limit), "exact segment bytes")
    try require(FileManager.default.fileExists(atPath: paths[2].path) == (gap && !denyGap), "gap marker")
    try require(FileManager.default.fileExists(atPath: paths[3].path) == !gap, "clean EOF marker")
}

try fixture(Data([0x41, 0x0d, 0x42, 0x1b, 0x5b, 0x33, 0x31, 0x6d, 0xe2, 0x82, 0xac, 0x0a]), limit: 1024, gap: false)
try fixture(Data(repeating: 0x58, count: 200), limit: 64, gap: true)
try fixture(Data(repeating: 0x58, count: 200), limit: 64, gap: true, denyGap: true)
print("exact_bytes=PASS quota_gap=PASS denied_gap_exit=PASS clean_eof=PASS")
