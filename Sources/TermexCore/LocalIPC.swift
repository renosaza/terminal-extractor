import Darwin
import Foundation

public enum LocalIPC {
    public static let maxFrame = 64 * 1024

    public enum Failure: Error {
        case invalidPath, invalidFrame, unauthorizedPeer, disconnected, timedOut, system(Int32)
    }

    public static var defaultPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TerminalExtractor/Run/host.sock").path
    }

    public static func prepareDirectory(for path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        let parent = (directory as NSString).deletingLastPathComponent
        for component in [parent, directory] {
            if mkdir(component, 0o700) != 0 && errno != EEXIST { throw Failure.system(errno) }
            var info = stat()
            guard lstat(component, &info) == 0,
                  info.st_uid == getuid(),
                  info.st_mode & S_IFMT == S_IFDIR,
                  info.st_mode & 0o077 == 0 else { throw Failure.invalidPath }
        }
    }

    private static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        let bytes = Array(path.utf8)
        guard path.hasPrefix("/"), !bytes.contains(0),
              bytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw Failure.invalidPath
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes)
        }
        return address
    }

    private static func configure(_ fd: Int32) throws {
        var yes: Int32 = 1
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0 else {
            throw Failure.system(errno)
        }
    }

    private static func verifyPeer(_ fd: Int32) throws {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { throw Failure.unauthorizedPeer }
        guard uid == geteuid() else { throw Failure.unauthorizedPeer }
    }

    public static func listen(at path: String) throws -> Int32 {
        try prepareDirectory(for: path)
        var address = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system(errno) }
        var bound = false
        do {
            try configure(fd)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw Failure.system(errno) }
            bound = true
            guard chmod(path, 0o600) == 0,
                  Darwin.listen(fd, 8) == 0 else { throw Failure.system(errno) }
            return fd
        } catch {
            Darwin.close(fd)
            if bound { unlink(path) }
            throw error
        }
    }

    public static func connect(to path: String) throws -> Int32 {
        var address = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system(errno) }
        do {
            try configure(fd)
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard result == 0 else { throw Failure.system(errno) }
            try verifyPeer(fd)
            return fd
        } catch {
            Darwin.close(fd)
            throw error
        }
    }

    public static func accept(_ listener: Int32) throws -> Int32 {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { throw Failure.system(errno) }
        do { try configure(fd); try verifyPeer(fd); return fd }
        catch { Darwin.close(fd); throw error }
    }

    private static func ready(_ fd: Int32, for events: Int16, by deadline: UInt64) throws {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { throw Failure.timedOut }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let remaining = Int32(min((deadline - now) / 1_000_000 + 1, 5_000))
            let result = poll(&descriptor, 1, remaining)
            if result < 0 && errno == EINTR { continue }
            guard result > 0 else { throw result == 0 ? Failure.timedOut : Failure.system(errno) }
            guard descriptor.revents & events != 0 else { throw Failure.disconnected }
            return
        }
    }

    private static func readExact(_ fd: Int32, count: Int, by deadline: UInt64) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { buffer in
            var offset = 0
            while offset < count {
                try ready(fd, for: Int16(POLLIN), by: deadline)
                let n = recv(fd, buffer.baseAddress!.advanced(by: offset), count - offset, 0)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw n == 0 ? Failure.disconnected : Failure.system(errno) }
                offset += n
            }
        }
        return data
    }

    public static func readFrame(_ fd: Int32) throws -> Data {
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        let header = try readExact(fd, count: 4, by: deadline)
        let length = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard length > 0 && length <= maxFrame else { throw Failure.invalidFrame }
        return try readExact(fd, count: Int(length), by: deadline)
    }

    public static func writeFrame(_ data: Data, to fd: Int32) throws {
        guard !data.isEmpty && data.count <= maxFrame else { throw Failure.invalidFrame }
        let length = UInt32(data.count)
        let header = Data([UInt8(length >> 24), UInt8(length >> 16), UInt8(length >> 8), UInt8(length)])
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        for part in [header, data] {
            try part.withUnsafeBytes { buffer in
                var offset = 0
                while offset < part.count {
                    try ready(fd, for: Int16(POLLOUT), by: deadline)
                    let n = send(fd, buffer.baseAddress!.advanced(by: offset), part.count - offset, 0)
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw Failure.system(errno) }
                    offset += n
                }
            }
        }
    }
}
