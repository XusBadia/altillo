import AltilloAgents
import AltilloCore
import CoreServices
import Darwin
import Foundation
import os

/// Follows OpenCode (phase 14) through the HTTP server `opencode serve` (or `opencode web`, or a TUI started with
/// `--port`) runs on this Mac: its SSE stream (`/global/event`) for what every session does, and its API to answer a
/// permission or send a reply. No hooks, nothing written to OpenCode's config.
///
/// No work at rest, with or without OpenCode:
/// - OpenCode writes its log and database under `~/.local/share/opencode` when it starts and while it works (an idle
///   `opencode serve` writes nothing: checked on 1.18.32 over 90 s). An FSEvents stream on that folder is the
///   "launch notification": each burst triggers one cheap process scan (at most every 3 s) that finds OpenCode
///   processes serving HTTP (argv `serve`/`web`/`--port`) and the port they listen on (libproc).
/// - Without that folder (OpenCode never ran), nothing recursive is watched: a non-recursive vnode watch on the
///   nearest folder that exists (`~/.local/share`, else `~/.local`, else the home) wakes only when an entry is added
///   there, and moves down until the folder appears.
/// - One SSE connection per server; on every (re)connection the hub re-reads the pending permissions and session
///   statuses. When the stream ends and the process is gone, its sessions are over.
final class OpenCodeMonitor: NSObject, @unchecked Sendable, URLSessionDataDelegate {
    struct Server: Hashable, Sendable {
        let pid: Int32
        let port: Int
        var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }
    }

    /// What a server says is pending in one directory (read on every connection).
    struct State: Sendable {
        var directory: String?
        var permissions: [OpenCodePermission]
        /// Session id → busy/retry (idle sessions are left out or `idle`).
        var statuses: [String: String]
    }

    /// Called on the monitor's queue for every event of every server.
    var onEvent: @Sendable (OpenCodeEvent, _ directory: String?, _ server: Server) -> Void = { _, _, _ in }
    /// Called on the monitor's queue when a server's stream (re)connects: time to re-read its state.
    var onConnected: @Sendable (Server) -> Void = { _ in }
    /// Called on the monitor's queue when a server's process is gone.
    var onServerGone: @Sendable (Server) -> Void = { _ in }

    /// `$XDG_DATA_HOME/opencode` or `~/.local/share/opencode`.
    static var defaultDataDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        let base = environment["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share")
        return base.appendingPathComponent("opencode")
    }

    let dataDirectory: URL
    private let queue = DispatchQueue(label: "me.badia.altillo.agents.opencode", qos: .utility)
    private var stream: FSEventStreamRef?
    /// Non-recursive watch on the nearest existing ancestor while `dataDirectory` doesn't exist.
    private var ancestorWatch: (any DispatchSourceFileSystemObject)?
    private(set) var watchedAncestor: URL?
    private var session: URLSession?
    /// No proxy, no delegate: permission answers and replies.
    private let calls: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()
    private var tasks: [Int32: URLSessionDataTask] = [:]
    private var servers: [Int: Server] = [:] // task id → server
    private var parsers: [Int: SSEParser] = [:]
    /// Consecutive failed connections per process: after a few, only a new process (or a later scan) retries.
    private var failures: [Int32: Int] = [:]
    private var lastScan = Date.distantPast
    private var scanPending = false
    private var running = false
    /// Process scans done (tests: nothing happens at rest).
    private(set) var scanCount = 0
    private static let log = Logger(subsystem: "me.badia.altillo", category: "agents.opencode")

    init(dataDirectory: URL = OpenCodeMonitor.defaultDataDirectory) {
        self.dataDirectory = dataDirectory
        super.init()
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 60 * 60 * 24
            configuration.timeoutIntervalForResource = 60 * 60 * 24 * 7
            configuration.connectionProxyDictionary = [:]
            let delegateQueue = OperationQueue()
            delegateQueue.underlyingQueue = queue
            delegateQueue.maxConcurrentOperationCount = 1
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: delegateQueue)
            if FileManager.default.fileExists(atPath: dataDirectory.path) {
                startStream()
                scan()
            } else {
                watchNearestAncestor()
            }
        }
    }

    func stop() {
        queue.sync {
            running = false
            stopStream()
            ancestorWatch?.cancel()
            ancestorWatch = nil
            watchedAncestor = nil
            session?.invalidateAndCancel()
            session = nil
            tasks.removeAll()
            servers.removeAll()
            parsers.removeAll()
            failures.removeAll()
        }
    }

    /// Waits for pending queue work (tests).
    func sync<T: Sendable>(_ body: @Sendable () -> T) -> T { queue.sync { body() } }

    // MARK: Calls (the user's answers only)

    /// Answers a permission (`once` / `always` / `reject`). `completion` runs on a background queue.
    func replyPermission(server: Server, requestID: String, directory: String?, decision: AgentDecision,
                         completion: @escaping @Sendable (Bool) -> Void) {
        post(server: server, path: OpenCodeAPI.permissionReplyPath(requestID: requestID, directory: directory),
             body: OpenCodeAPI.permissionReplyBody(decision), completion: completion)
    }

    /// Sends the user's reply as a new message in the session.
    func prompt(server: Server, sessionID: String, directory: String?, text: String,
                completion: @escaping @Sendable (Bool) -> Void) {
        post(server: server, path: OpenCodeAPI.promptPath(sessionID: sessionID, directory: directory),
             body: OpenCodeAPI.promptBody(text), completion: completion)
    }

    /// Pending permissions and session statuses, for each directory (nil: the server's own).
    func fetchState(server: Server, directories: [String?], completion: @escaping @Sendable ([State]) -> Void) {
        Task.detached { [calls] in
            var states: [State] = []
            for directory in directories {
                guard let permissions = await Self.get(calls, server, OpenCodeAPI.pendingPermissionsPath(directory: directory))
                        .flatMap(OpenCodeAPI.permissions(from:)),
                      let statuses = await Self.get(calls, server, OpenCodeAPI.statusPath(directory: directory))
                        .flatMap(OpenCodeAPI.statuses(from:)) else { continue }
                states.append(State(directory: directory, permissions: permissions, statuses: statuses))
            }
            completion(states)
        }
    }

    private static func get(_ session: URLSession, _ server: Server, _ path: String) async -> Data? {
        guard let url = URL(string: path, relativeTo: server.baseURL) else { return nil }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func post(server: Server, path: String, body: Data, completion: @escaping @Sendable (Bool) -> Void) {
        guard let url = URL(string: path, relativeTo: server.baseURL) else { return completion(false) }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let task = calls.dataTask(with: request) { _, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let ok = error == nil && (200..<300).contains(status)
            if !ok { Self.log.error("OpenCode call failed (\(status)): \(String(describing: error), privacy: .public)") }
            completion(ok)
        }
        task.resume()
    }

    // MARK: Watching (queue-confined)

    private func startStream() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<OpenCodeMonitor>.fromOpaque(info).takeUnretainedValue().somethingChanged()
        }
        guard let stream = FSEventStreamCreate(nil, callback, &context, [dataDirectory.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
                                               FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// The nearest existing folder on the way to `dataDirectory` (never above the home, never the root).
    static func nearestExistingAncestor(of url: URL) -> URL? {
        var candidate = url.deletingLastPathComponent().standardizedFileURL
        while candidate.path != "/" {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }

    /// Non-recursive: a vnode source on one folder fires only when an entry in it is added, removed or renamed.
    private func watchNearestAncestor() {
        ancestorWatch?.cancel()
        ancestorWatch = nil
        watchedAncestor = nil
        guard running else { return }
        if FileManager.default.fileExists(atPath: dataDirectory.path) {
            // It appeared: OpenCode ran for the first time.
            startStream()
            scan()
            return
        }
        guard let folder = Self.nearestExistingAncestor(of: dataDirectory) else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .delete, .rename],
                                                               queue: queue)
        source.setEventHandler { [weak self] in self?.watchNearestAncestor() }
        source.setCancelHandler { close(fd) }
        ancestorWatch = source
        watchedAncestor = folder
        source.resume()
        // Something created between looking and watching would be missed: look once more.
        if Self.nearestExistingAncestor(of: dataDirectory)?.path != folder.path
            || FileManager.default.fileExists(atPath: dataDirectory.path) {
            queue.async { [weak self] in self?.watchNearestAncestor() }
        }
    }

    private func somethingChanged() {
        guard running, !scanPending else { return }
        // Busy sessions write constantly; one scan every few seconds is plenty to notice a new server.
        let wait = max(0, 3 - Date().timeIntervalSince(lastScan))
        scanPending = true
        queue.asyncAfter(deadline: .now() + wait) { [self] in
            scanPending = false
            scan()
        }
    }

    private func scan() {
        guard running else { return }
        lastScan = Date()
        scanCount += 1
        let serving = Self.servingProcesses()
        failures = failures.filter { pid, _ in serving.contains { $0.pid == pid } }
        for (pid, port) in serving where tasks[pid] == nil && (failures[pid] ?? 0) < 3 {
            connect(Server(pid: pid, port: port))
        }
    }

    /// OpenCode processes serving HTTP, with the port they really listen on.
    static func servingProcesses() -> [(pid: Int32, port: Int)] {
        var found: [(Int32, Int)] = []
        for pid in allPIDs() where pid > 0 {
            guard processName(pid).hasPrefix("opencode"), let arguments = ProcessTree.arguments(of: pid) else { continue }
            let (serves, argumentPort) = OpenCodeAPI.serverPort(arguments: arguments)
            guard serves, let port = port(argument: argumentPort, listening: listeningPorts(of: pid)) else { continue }
            found.append((pid, port))
        }
        return found
    }

    /// `--port N` counts only if the process really listens on N (a stale or misleading argv never sends Altillo's
    /// answers elsewhere); without one, the port it listens on.
    static func port(argument: Int?, listening: [Int]) -> Int? {
        if let argument { return listening.contains(argument) ? argument : nil }
        return listening.first
    }

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 64)
        let filled = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        return Array(pids.prefix(Int(max(filled, 0))))
    }

    private static func processName(_ pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// TCP ports `pid` listens on (loopback or any), from its socket descriptors.
    static func listeningPorts(of pid: Int32) -> [Int] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let filled = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard filled > 0 else { return [] }
        var ports: [Int] = []
        for fd in fds.prefix(Int(filled) / stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let got = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard got == Int32(MemoryLayout<socket_fdinfo>.size), info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let port = Int(UInt16(bigEndian: UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)))
            if port > 0 { ports.append(port) }
        }
        return ports
    }

    // MARK: SSE (queue-confined)

    private func connect(_ server: Server) {
        guard let session else { return }
        var request = URLRequest(url: server.baseURL.appendingPathComponent("global/event"))
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let task = session.dataTask(with: request)
        tasks[server.pid] = task
        servers[task.taskIdentifier] = server
        parsers[task.taskIdentifier] = SSEParser()
        task.resume()
        Self.log.info("Following OpenCode on port \(server.port) (pid \(server.pid))")
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // 401: the server has a password (OPENCODE_SERVER_PASSWORD); Altillo doesn't ask for it and leaves it alone.
        if status == 200, let server = servers[dataTask.taskIdentifier] {
            failures[server.pid] = nil
            onConnected(server)
        }
        completionHandler(status == 200 ? .allow : .cancel)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let id = dataTask.taskIdentifier
        guard let server = servers[id], var parser = parsers[id] else { return }
        let events = parser.feed(data)
        if parser.isOverLimit {
            dataTask.cancel()
            return
        }
        parsers[id] = parser
        for data in events {
            guard let (event, directory) = OpenCodeEvent.parse(data) else { continue }
            if case .other = event { continue }
            onEvent(event, directory, server)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let id = task.taskIdentifier
        guard let server = servers.removeValue(forKey: id) else { return }
        parsers[id] = nil
        if tasks[server.pid] === task { tasks[server.pid] = nil }
        guard running else { return }
        failures[server.pid, default: 0] += 1
        if ProcessTree.isAlive(server.pid), (task.response as? HTTPURLResponse)?.statusCode != 401,
           (failures[server.pid] ?? 0) < 3 {
            // Still there (a restart of the listener, a hiccup): try again shortly.
            queue.asyncAfter(deadline: .now() + 2) { [self] in
                if tasks[server.pid] == nil, running, ProcessTree.isAlive(server.pid) { connect(server) }
            }
        } else if !ProcessTree.isAlive(server.pid) {
            onServerGone(server)
        }
    }
}
