#if os(macOS)
import AltilloAgents
import Darwin
import Foundation

/// Native endpoint called by the Mail rule's Foundation serializer. The JSON travels only through stdin/socket.
public enum MailBridgeClient {
    public enum Failure: Error, Equatable, Sendable {
        case invalidInput
        case unavailable
        case timedOut
        case rejected
    }

    public enum Delivery: Sendable, Equatable { case accepted, duplicate }

    public static func deliver(_ data: Data, path: String = MailWire.defaultSocketPath) throws(Failure) -> Delivery {
        guard (try? MailEnvelope.decode(data)) != nil else { throw .invalidInput }
        // Re-encode before framing: pretty-printed input can contain literal newlines between JSON fields.
        guard let event = try? JSONDecoder().decode(MailEnvelope.self, from: data),
              var frame = try? JSONEncoder().encode(event), frame.count <= MailWire.byteLimit else { throw .invalidInput }
        frame.append(10)
        let fd: Int32
        do { fd = try UnixSocket.connect(path: path, timeout: 0.3) }
        catch { throw .unavailable }
        defer { close(fd) }
        guard UnixSocket.peerIsSameUser(fd) else { throw .unavailable }
        guard UnixSocket.writeAll(fd, frame, timeout: 0.3),
              let response = readReply(fd, timeout: 0.8) else { throw .timedOut }
        switch String(decoding: response, as: UTF8.self) {
        case "accepted": return .accepted
        case "duplicate": return .duplicate
        default: throw .rejected
        }
    }

    /// Bound both memory and elapsed time for CLI stdin, including a producer that never closes its pipe.
    public static func readInput(fd: Int32 = STDIN_FILENO, timeout: Double = 1) throws(Failure) -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var data = Data(), bytes = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let left = deadline.timeIntervalSinceNow
            let ready = poll(&descriptor, 1, Int32(max(1, min(left * 1_000, 100))))
            if ready < 0 {
                if errno == EINTR { continue }
                throw .invalidInput
            }
            if ready == 0 { continue }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { return data }
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw .invalidInput
            }
            data.append(contentsOf: bytes.prefix(count))
            guard data.count <= MailWire.byteLimit else { throw .invalidInput }
        }
        throw .timedOut
    }

    private static func readReply(_ fd: Int32, timeout: Double) -> Data? {
        let deadline = Date().addingTimeInterval(timeout)
        var result = Data(), bytes = [UInt8](repeating: 0, count: 32)
        while Date() < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let left = max(1, (deadline.timeIntervalSinceNow * 1_000).rounded(.up))
            let ready = poll(&descriptor, 1, Int32(min(left, Double(Int32.max))))
            if ready < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if ready == 0 { continue }
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                return nil
            }
            if count == 0 { return nil }
            result.append(contentsOf: bytes.prefix(count))
            guard result.count <= 32 else { return nil }
            if result.last == 10 { return result.dropLast() }
        }
        return nil
    }
}
#endif
