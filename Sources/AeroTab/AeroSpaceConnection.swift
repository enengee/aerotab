import Darwin
import Foundation

struct AeroSpaceError: Error, CustomStringConvertible {
    let description: String
}

struct AeroSpaceAnswer {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

final class AeroSpaceConnection {
    private static let protocolVersion: UInt32 = 1
    private static let socketPath = "/tmp/bobko.aerospace-\(NSUserName()).sock"

    private let fd: Int32

    init() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AeroSpaceError(description: "socket(): \(String(cString: strerror(errno)))") }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(Self.socketPath.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            throw AeroSpaceError(description: "socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.withUnsafeBytes { buffer.copyMemory(from: $0) }
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw AeroSpaceError(description: "can't connect to \(Self.socketPath): \(reason). Is AeroSpace running?")
        }

        do {
            try writeUInt32(Self.protocolVersion)
            let serverVersion = try readUInt32()
            guard serverVersion == Self.protocolVersion else {
                throw AeroSpaceError(description: "unsupported AeroSpace socket protocol \(serverVersion), expected \(Self.protocolVersion)")
            }
        } catch {
            close(fd)
            throw error
        }
    }

    deinit { close(fd) }

    func send(_ args: [String]) throws {
        let request: [String: Any] = ["args": args, "stdin": "", "windowId": NSNull(), "workspace": NSNull()]
        let payload = try JSONSerialization.data(withJSONObject: request)
        try writeUInt32(UInt32(payload.count))
        try writeAll(payload)
    }

    func receiveObject() throws -> [String: Any] {
        let count = try readUInt32()
        let data = try readExactly(Int(count))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AeroSpaceError(description: "malformed AeroSpace message")
        }
        return object
    }

    func run(_ args: [String]) throws -> AeroSpaceAnswer {
        try send(args)
        let object = try receiveObject()
        return AeroSpaceAnswer(
            exitCode: (object["exitCode"] as? NSNumber)?.int32Value ?? 2,
            stdout: object["stdout"] as? String ?? "",
            stderr: object["stderr"] as? String ?? ""
        )
    }

    private func writeUInt32(_ value: UInt32) throws {
        try withUnsafeBytes(of: value.littleEndian) { try writeAll(Data($0)) }
    }

    private func readUInt32() throws -> UInt32 {
        let data = try readExactly(4)
        return data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    }

    private func writeAll(_ data: Data) throws {
        try data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < buffer.count {
                let written = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw AeroSpaceError(description: "write: \(String(cString: strerror(errno)))")
                }
                offset += written
            }
        }
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            var offset = 0
            while offset < count {
                let got = read(fd, buffer.baseAddress! + offset, count - offset)
                if got < 0 {
                    if errno == EINTR { continue }
                    throw AeroSpaceError(description: "read: \(String(cString: strerror(errno)))")
                }
                if got == 0 { throw AeroSpaceError(description: "AeroSpace closed the connection") }
                offset += got
            }
        }
        return data
    }
}
