import Darwin
import Foundation
import TermexCore

var sockets: [Int32] = [0, 0]
precondition(socketpair(AF_UNIX, SOCK_STREAM, 0, &sockets) == 0)
defer { Darwin.close(sockets[0]); Darwin.close(sockets[1]) }
let payload = Data(repeating: 0x41, count: 300)
try LocalIPC.writeFrame(payload, to: sockets[0])
let received = try LocalIPC.readFrame(sockets[1])
precondition(received == payload)
print("large_frame=PASS")
