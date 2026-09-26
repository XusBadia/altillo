import AltilloAgents
import Darwin
import Foundation

/// The Unix socket `altillo-hook` talks to (`~/Library/Application Support/Altillo/agents.sock`, 0600 in a 0700
/// folder). Runs entirely on its own serial queue, never on the main actor: one connection per hook call, a
/// fire-and-forget event is read and the connection closed; a PermissionRequest connection (or a stop hook waiting for
/// a reply, phase 14) stays open until the
/// user decides (`reply`) or the hook goes away (timeout, or the user answered in the terminal and the agent
/// killed the hook), which `onRequestClosed` reports.
final class AgentSocketServer: @unchecked Sendable {
    /// Called on the server queue for every complete message.
    var onEnvelope: @Sendable (HookEnvelope) -> Void = { _ in }
    /// Called on the server queue when a waiting hook disconnects before it got a reply.
    var onRequestClosed: @Sendable (String) -> Void = { _ in }

    let path: String
    private let queue = DispatchQueue(label: "me.badia.altillo.agents.socket", qos: .userInitiated)
    private var listener: Int32 = -1
    /// The socket file we created, to never delete another instance's.
    private var bound: UnixSocket.Listener?
    private var acceptSource: (any DispatchSourceRead)?
    private var connections: [Int32: Connection] = [:]
    private var waiting: [String: Int32] = [:]
    private static let maxConnections = 256

    private final class Connection {
        let fd: Int32
        var source: (any DispatchSourceRead)?
        var buffer = LineBuffer(limit: 32 << 20)
        var requestID: String?
        init(fd: Int32) { self.fd = fd }
    }

    init(path: String) {
        self.path = path
    }

    /// Binds and listens. Throws when the socket can't be created, or `.inUse` when another Altillo already
    /// answers on it (the hub then runs on session files only and leaves the other instance's socket alone).
    func start() throws {
        try queue.sync {
            guard listener < 0 else { return }
            let socket = try UnixSocket.listen(path: path)
            bound = socket
            let fd = socket.fd
            listener = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptPending() }
            source.setCancelHandler { close(fd) }
            acceptSource = source
            source.resume()
        }
    }

    /// Stops listening, drops every connection (waiting hooks see EOF and fall back to the terminal) and removes
    /// the socket file, so hooks fired while Altillo is closed return at once.
    func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if let bound { UnixSocket.removeIfOwned(path: path, listener: bound) }
            bound = nil
            listener = -1
            for connection in connections.values { connection.source?.cancel() }
            connections.removeAll()
            waiting.removeAll()
        }
    }

    /// Answers a waiting hook (`text`: a reply typed in the notch, with `.reply`). False when that hook is gone (it
    /// timed out or was killed).
    @discardableResult
    func reply(requestID: String, decision: WireDecision, text: String? = nil) -> Bool {
        queue.sync {
            guard let fd = waiting.removeValue(forKey: requestID), let connection = connections[fd] else { return false }
            connection.requestID = nil
            let delivered = AgentWire.frame(HookReply(requestID: requestID, decision: decision, text: text))
                .map { UnixSocket.writeAll(fd, $0, timeout: 1) } ?? false
            connection.source?.cancel()
            connections[fd] = nil
            return delivered
        }
    }

    /// Hooks currently waiting for an answer (tests, diagnostics).
    var waitingRequestIDs: Set<String> { queue.sync { Set(waiting.keys) } }

    // MARK: - Queue-confined

    private func acceptPending() {
        while true {
            guard let fd = UnixSocket.accept(listener) else { return }
            guard UnixSocket.peerIsSameUser(fd), connections.count < Self.maxConnections else {
                close(fd)
                continue
            }
            let connection = Connection(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(fd) }
            source.setCancelHandler { close(fd) }
            connection.source = source
            connections[fd] = connection
            source.resume()
        }
    }

    private func readAvailable(_ fd: Int32) {
        guard let connection = connections[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 64 << 10)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                for line in connection.buffer.append(Data(chunk[0..<count])) { handle(line, on: connection) }
                if connection.buffer.isOverLimit { drop(connection); return }
                continue
            }
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            // EOF or error: the hook is gone.
            drop(connection)
            return
        }
    }

    private func handle(_ line: Data, on connection: Connection) {
        guard connection.requestID == nil, let envelope = AgentWire.decodeEnvelope(line) else { return }
        if envelope.waits, let requestID = envelope.requestID {
            connection.requestID = requestID
            waiting[requestID] = connection.fd
        }
        onEnvelope(envelope)
    }

    private func drop(_ connection: Connection) {
        connection.source?.cancel()
        connections[connection.fd] = nil
        if let requestID = connection.requestID, waiting.removeValue(forKey: requestID) != nil {
            onRequestClosed(requestID)
        }
    }
}
