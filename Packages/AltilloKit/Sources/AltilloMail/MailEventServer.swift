#if os(macOS)
import AltilloAgents
import Darwin
import Foundation

/// Event-driven local receiver. The serial queue owns all descriptors and in-memory deduplication state.
/// Callbacks run on that queue; the app hops to MainActor and checks its enabled state before showing content.
public final class MailEventServer: @unchecked Sendable {
    public enum Failure: Error, Equatable, Sendable { case unsafePath, unavailable }
    public let path: String
    private let onEvent: @Sendable (MailEnvelope) -> Void
    private let queue = DispatchQueue(label: "me.badia.altillo.mail.socket", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var listener: UnixSocket.Listener?
    private var source: DispatchSourceRead?
    private var expirySource: DispatchSourceTimer?
    private var connections: [Int32: Connection] = [:]
    private let clock = ContinuousClock()
    private let deduplicationLifetime: Double
    private var seen: [String: ContinuousClock.Instant] = [:]
    private static let connectionLimit = 16

    private final class Connection {
        let fd: Int32
        let token = UUID()
        var source: DispatchSourceRead?
        var framing = LineBuffer(limit: MailWire.byteLimit)
        var receivedBytes = 0
        init(fd: Int32) { self.fd = fd }
    }

    public convenience init(path: String = MailWire.defaultSocketPath, onEvent: @escaping @Sendable (MailEnvelope) -> Void) {
        self.init(path: path, deduplicationLifetime: MailWire.lifetime, onEvent: onEvent)
    }

    /// Short retention is injectable inside the package so expiration can be tested without waiting five minutes.
    init(path: String, deduplicationLifetime: Double, onEvent: @escaping @Sendable (MailEnvelope) -> Void) {
        self.path = path
        self.deduplicationLifetime = max(0.01, min(deduplicationLifetime, MailWire.lifetime))
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: true)
    }

    public func start() throws {
        try synchronously {
            guard listener == nil else { return }
            try validateDirectoryAndSocket()
            let bound = try UnixSocket.listen(path: path)
            listener = bound
            let read = DispatchSource.makeReadSource(fileDescriptor: bound.fd, queue: queue)
            read.setEventHandler { [weak self] in self?.acceptPending(bound.fd) }
            read.setCancelHandler { close(bound.fd) }
            source = read
            read.resume()
        }
    }

    public func stop() {
        synchronously {
            source?.cancel()
            source = nil
            expirySource?.cancel()
            expirySource = nil
            for connection in connections.values { connection.source?.cancel() }
            connections.removeAll()
            if let listener { UnixSocket.removeIfOwned(path: path, listener: listener) }
            listener = nil
            seen.removeAll()
        }
    }

    deinit { stop() }

    /// Metadata count only, used to verify that idle retention actually ends without another incoming message.
    var rememberedMessageCount: Int { synchronously { seen.count } }

    private func synchronously<T>(_ action: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return try action() }
        return try queue.sync(execute: action)
    }

    private func validateDirectoryAndSocket() throws {
        let parent = (path as NSString).deletingLastPathComponent
        guard parent != ".", !parent.isEmpty, path.hasPrefix("/") else { throw Failure.unsafePath }
        var info = stat()
        if lstat(parent, &info) != 0 {
            guard errno == ENOENT else { throw Failure.unsafePath }
            do {
                try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
            } catch { throw Failure.unavailable }
            guard lstat(parent, &info) == 0 else { throw Failure.unsafePath }
        }
        // Validate before calling shared UnixSocket.listen, which reasserts the mode on its parent.
        guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFDIR,
              info.st_mode & 0o777 == 0o700 else { throw Failure.unsafePath }
        if lstat(path, &info) == 0 {
            guard info.st_uid == getuid(), info.st_mode & S_IFMT == S_IFSOCK else { throw Failure.unsafePath }
        } else if errno != ENOENT { throw Failure.unsafePath }
    }

    private func acceptPending(_ fd: Int32) {
        for _ in 0..<32 {
            guard let client = UnixSocket.accept(fd) else { return }
            guard UnixSocket.peerIsSameUser(client), connections.count < Self.connectionLimit else {
                close(client)
                continue
            }
            let connection = Connection(fd: client)
            let read = DispatchSource.makeReadSource(fileDescriptor: client, queue: queue)
            connection.source = read
            connections[client] = connection
            read.setEventHandler { [weak self] in self?.readPending(client) }
            read.setCancelHandler { close(client) }
            read.resume()
            let token = connection.token
            // One deadline for the whole frame, not reset by a peer dribbling individual bytes.
            queue.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard self?.connections[client]?.token == token else { return }
                self?.finish(client, reply: "rejected")
            }
        }
    }

    private func readPending(_ fd: Int32) {
        guard let connection = connections[fd] else { return }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN { return }
                finish(fd, reply: nil)
                return
            }
            if count == 0 { finish(fd, reply: nil); return }
            connection.receivedBytes += count
            guard connection.receivedBytes <= MailWire.byteLimit + 1 else {
                finish(fd, reply: "rejected"); return
            }
            let lines = connection.framing.append(Data(bytes.prefix(count)))
            if lines.isEmpty { continue }
            guard lines.count == 1, let data = lines.first,
                  connection.receivedBytes == data.count + 1,
                  let event = try? MailEnvelope.decode(data) else {
                finish(fd, reply: "rejected"); return
            }
            let now = clock.now
            seen = seen.filter { $0.value > now }
            guard seen[event.messageID] == nil else { finish(fd, reply: "duplicate"); return }
            if seen.count >= 256, let oldest = seen.min(by: { $0.value < $1.value }) { seen[oldest.key] = nil }
            seen[event.messageID] = now.advanced(by: .seconds(deduplicationLifetime))
            scheduleExpiry()
            onEvent(event)
            finish(fd, reply: "accepted")
            return
        }
    }

    private func scheduleExpiry() {
        expirySource?.cancel()
        expirySource = nil
        guard let next = seen.values.min() else { return }
        let remaining = clock.now.duration(to: next).components
        let seconds = max(0, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + seconds, leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = self.clock.now
            self.seen = self.seen.filter { $0.value > now }
            self.scheduleExpiry()
        }
        expirySource = timer
        timer.resume()
    }

    private func finish(_ fd: Int32, reply: String?) {
        guard let connection = connections.removeValue(forKey: fd) else { return }
        if let reply { _ = UnixSocket.writeAll(fd, Data((reply + "\n").utf8), timeout: 0.05) }
        connection.source?.cancel()
    }
}
#endif
