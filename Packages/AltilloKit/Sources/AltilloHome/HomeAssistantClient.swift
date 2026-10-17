import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Home Assistant over its WebSocket API (docs/casa.md).
///
/// One connection per client. `connect`/`resume` start a lifecycle that keeps the socket up: reconnects with
/// backoff (1, 2, 4… 60 s), pauses while the Mac sleeps and resumes on wake. The only periodic work is a ping
/// every 60 s while connected; everything else is driven by HA's events (no polling).
@MainActor
@Observable
public final class HomeAssistantClient: HomeService {
    public private(set) var connection: HomeConnectionState = .notConfigured
    public private(set) var areas: [HomeArea] = []
    public private(set) var entities: [HomeEntityID: HomeEntity] = [:]
    public private(set) var config: HomeServerConfig?

    @ObservationIgnored private let tokens: any HomeTokenStore
    @ObservationIgnored private let socketFactory: HomeSocketFactory
    @ObservationIgnored let timing: HomeTiming
    @ObservationIgnored private var catalog = HACatalog()
    @ObservationIgnored private var watched: Set<HomeEntityID> = []
    @ObservationIgnored private var token: String?
    @ObservationIgnored private var tokenIsStored = false
    @ObservationIgnored private var live: HALive?
    @ObservationIgnored private var establishing: HALive?
    /// Injected in tests; used to drop stale `event.*` triggers.
    @ObservationIgnored var now: () -> Date = Date.init
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lifecycle: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var catalogRefresh: Task<Void, Never>?
    @ObservationIgnored private var isPaused = false
    @ObservationIgnored private var continuations: [UUID: AsyncStream<HomeServiceEvent>.Continuation] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public convenience init() {
        self.init(tokens: KeychainHomeTokenStore(), socketFactory: URLSessionHomeSocket.make, observesSleep: true)
    }

    init(tokens: any HomeTokenStore, socketFactory: @escaping HomeSocketFactory, timing: HomeTiming = .standard,
         observesSleep: Bool = false) {
        self.tokens = tokens
        self.socketFactory = socketFactory
        self.timing = timing
        if observesSleep { observeSleep() }
    }

    isolated deinit {
        lifecycle?.cancel()
        watchTask?.cancel()
        catalogRefresh?.cancel()
        #if canImport(AppKit)
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        #endif
    }

    // MARK: Events

    public func events() -> AsyncStream<HomeServiceEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: HomeServiceEvent.self, bufferingPolicy: .bufferingNewest(256))
        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            let client = self
            Task { @MainActor in client?.continuations[id] = nil }
        }
        return stream
    }

    private func emit(_ event: HomeServiceEvent) {
        for continuation in continuations.values { continuation.yield(event) }
    }

    private func setConnection(_ state: HomeConnectionState) {
        guard state != connection else { return }
        connection = state
        emit(.connectionChanged)
    }

    // MARK: Lifecycle

    public func connect(_ config: HomeServerConfig, token: String) async throws {
        try await firstConnection(config: config, token: token, save: true)
    }

    public func resume(_ config: HomeServerConfig) {
        guard let token = tokens.token(for: config.serverID) else {
            _ = beginSession(config: config, token: nil)
            setConnection(.unauthorized)
            return
        }
        let generation = beginSession(config: config, token: token)
        tokenIsStored = true
        startLifecycle(token: token, generation: generation, initial: nil)
    }

    public func trustCertificate(_ fingerprintSHA256: String) async throws -> HomeServerConfig {
        guard var config, let token else { throw HomeServiceError(HAFailure.notConnected.message) }
        config.pinnedCertificateSHA256 = fingerprintSHA256.lowercased()
        // Saves the token only if it isn't in the Keychain yet (first connect that stopped at `.needsTrust`).
        try await firstConnection(config: config, token: token, save: !tokenIsStored)
        return self.config ?? config
    }

    public func disconnect(forget: Bool) {
        generation += 1
        teardown()
        isPaused = false
        if forget, let config {
            tokens.delete(for: config.serverID)
            self.config = nil
            catalog = HACatalog()
            areas = []
            entities = [:]
        }
        token = nil
        tokenIsStored = false
        setConnection(.notConfigured)
    }

    /// Stops whatever runs, adopts the config and returns the new session generation.
    private func beginSession(config: HomeServerConfig, token: String?) -> Int {
        generation += 1
        teardown()
        isPaused = false
        if self.config?.serverID != config.serverID {
            catalog = HACatalog()
            areas = []
            entities = [:]
        }
        self.config = config
        self.token = token
        tokenIsStored = false
        setConnection(.connecting)
        return generation
    }

    private func teardown() {
        lifecycle?.cancel()
        lifecycle = nil
        catalogRefresh?.cancel()
        catalogRefresh = nil
        if let live { close(live) }
        live = nil
        // A connection still in its handshake or catalogue load: close it so it can't finish half-open.
        if let establishing { close(establishing) }
        establishing = nil
    }

    private func firstConnection(config: HomeServerConfig, token: String, save: Bool) async throws {
        let generation = beginSession(config: config, token: token)
        let established: HALive
        do {
            established = try await establish(token: token, generation: generation)
        } catch let failure as HAFailure {
            guard generation == self.generation else { throw CancellationError() }
            setConnection(failure.state)
            throw HomeServiceError(failure.message)
        }
        if save {
            do {
                try tokens.save(token, for: config.serverID)
            } catch {
                self.generation += 1
                teardown()
                setConnection(.notConfigured)
                throw HomeServiceError(HAFailure.keychain.message)
            }
        }
        tokenIsStored = true
        startLifecycle(token: token, generation: generation, initial: established)
    }

    /// Keeps the connection up until the generation changes: waits for the socket to drop, then retries with backoff.
    private func startLifecycle(token: String, generation: Int, initial: HALive?) {
        lifecycle?.cancel()
        lifecycle = Task { [weak self] in
            var current = initial
            var attempt = 0
            while !Task.isCancelled {
                guard let self, self.generation == generation else { return }
                if current == nil {
                    do {
                        current = try await self.establish(token: token, generation: generation)
                        attempt = 0
                    } catch {
                        guard !Task.isCancelled, self.generation == generation else { return }
                        let failure = error as? HAFailure ?? .connectionLost
                        self.setConnection(failure.state)
                        if !failure.isRetryable { return }
                        try? await Task.sleep(for: self.timing.backoff(attempt: attempt))
                        attempt += 1
                        continue
                    }
                }
                guard let live = current else { continue }
                await live.reader?.value
                current = nil
                guard !Task.isCancelled, self.generation == generation else { return }
                self.close(live)
                if self.live === live { self.live = nil }
                self.setConnection(.unreachable(reason: HAFailure.connectionLost.message))
                try? await Task.sleep(for: self.timing.backoff(attempt: attempt))
                attempt += 1
            }
        }
    }

    /// Opens the socket, authenticates, loads the catalogue, subscribes to registry changes and the watched entities.
    /// On success the connection is installed and the state is `.connected`. Throws `HAFailure`.
    private func establish(token: String, generation: Int) async throws -> HALive {
        guard let config else { throw HAFailure.connectionLost }
        let delegate = HomeTrustDelegate(pinnedSHA256: config.pinnedCertificateSHA256)
        let socket = socketFactory(HAMapping.websocketURL(for: config.url), delegate)
        let live = HALive(socket: socket, delegate: delegate)
        establishing = live
        defer { if establishing === live { establishing = nil } }
        let watchdog = Task { [timing] in
            try? await Task.sleep(for: timing.handshake)
            guard !Task.isCancelled else { return }
            live.handshakeTimedOut = true
            await socket.close()
        }
        defer { watchdog.cancel() }
        do {
            guard try await Self.decode(socket.receive())?["type"]?.string == "auth_required" else { throw HAFailure.unexpected }
            try await socket.send(JSONValue.object(["type": "auth", "access_token": .string(token)]).encodedString())
            let auth = try await Self.decode(socket.receive())
            switch auth?["type"]?.string {
            case "auth_ok": break
            case "auth_invalid": throw HAFailure.unauthorized
            default: throw HAFailure.unexpected
            }
            watchdog.cancel()
            let version = auth?["ha_version"]?.string ?? ""
            startReader(live)
            let serverConfig = try await request(live, ["type": "get_config"])
            let name = serverConfig["location_name"]?.string ?? config.name ?? "Home Assistant"
            let loaded = try await loadCatalog(live)
            for eventType in ["area_registry_updated", "entity_registry_updated", "device_registry_updated"] {
                let id = live.allocateID()
                live.registrySubscriptions.insert(id)
                _ = try await request(live, ["type": "subscribe_events", "event_type": .string(eventType)], id: id)
            }
            guard generation == self.generation, !Task.isCancelled else { throw CancellationError() }
            self.live = live
            if var current = self.config {
                current.name = name
                self.config = current
            }
            install(loaded)
            setConnection(.connected(serverName: name, version: version))
            emit(.catalogChanged)
            startKeepalive(live)
            scheduleResubscribe()
            return live
        } catch {
            close(live)
            if error is CancellationError { throw HAFailure.cancelled }
            throw classify(error, live: live)
        }
    }

    private func classify(_ error: any Error, live: HALive) -> HAFailure {
        if let fingerprint = live.delegate.untrustedFingerprint { return .needsTrust(fingerprint) }
        if let failure = error as? HAFailure { return failure }
        if live.handshakeTimedOut { return .timedOut }
        if HAMapping.isLocalNetworkDenied(error) { return .localNetworkDenied }
        if HAMapping.isInsecureRemote(error) { return .insecureRemote }
        return .notFound
    }

    // MARK: Socket plumbing

    private func startReader(_ live: HALive) {
        live.reader = Task { [weak self] in
            while true {
                let text: String
                do { text = try await live.socket.receive() } catch { break }
                let message = await Self.decode(text)
                guard let self, let message else { continue }
                for item in message.array ?? [message] { self.dispatch(item, live: live) }
            }
            self?.close(live)
        }
    }

    @concurrent nonisolated private static func decode(_ text: String) async -> JSONValue? {
        try? JSONValue.decode(text)
    }

    private func dispatch(_ message: JSONValue, live: HALive) {
        guard let id = message["id"]?.int else { return }
        switch message["type"]?.string {
        case "result", "pong":
            live.resolve(id, .success(message))
        case "event":
            guard live === self.live else { return }
            if id == live.entitiesSubscription, let event = message["event"] {
                applyEntities(event)
            } else if live.registrySubscriptions.contains(id) {
                scheduleCatalogRefresh(live)
            }
        default: break
        }
    }

    private func request(_ live: HALive, _ message: [String: JSONValue], id: Int? = nil,
                         timeout: Duration? = nil) async throws -> JSONValue {
        guard !live.isClosed else { throw HAFailure.connectionLost }
        let id = id ?? live.allocateID()
        var payload = message
        payload["id"] = .number(Double(id))
        let text = try JSONValue.object(payload).encodedString()
        let pending = HAPending()
        live.pending[id] = pending
        let limit = timeout ?? timing.request
        pending.timeout = Task { [weak live] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled else { return }
            live?.resolve(id, .failure(HAFailure.timedOut))
        }
        do { try await live.socket.send(text) } catch { live.resolve(id, .failure(HAFailure.connectionLost)) }
        let response = try await pending.value()
        if response["type"]?.string == "result", response["success"]?.bool != true {
            throw HAFailure.server(response["error"]?["message"]?.string ?? "")
        }
        return response["result"] ?? .null
    }

    private func close(_ live: HALive) {
        guard !live.isClosed else { return }
        live.isClosed = true
        live.keepalive?.cancel()
        for id in Array(live.pending.keys) { live.resolve(id, .failure(HAFailure.connectionLost)) }
        let socket = live.socket
        Task { await socket.close() }
    }

    private func startKeepalive(_ live: HALive) {
        live.keepalive = Task { [weak self, weak live, timing] in
            while !Task.isCancelled {
                try? await Task.sleep(for: timing.ping)
                guard !Task.isCancelled, let self, let live, !live.isClosed else { return }
                do {
                    _ = try await self.request(live, ["type": "ping"], timeout: timing.pong)
                } catch {
                    if !Task.isCancelled { self.close(live) }
                    return
                }
            }
        }
    }

    // MARK: Catalogue

    private func loadCatalog(_ live: HALive) async throws -> HACatalog {
        let areas = try await request(live, ["type": "config/area_registry/list"], timeout: timing.bulkRequest)
        let devices = try await request(live, ["type": "config/device_registry/list"], timeout: timing.bulkRequest)
        let entities = try await request(live, ["type": "config/entity_registry/list"], timeout: timing.bulkRequest)
        let states = try await request(live, ["type": "get_states"], timeout: timing.bulkRequest)
        return HAMapping.catalog(areas: areas, devices: devices, entities: entities, states: states)
    }

    private func install(_ loaded: HACatalog) {
        guard let serverID = config?.serverID else { return }
        catalog = loaded
        areas = loaded.areas
        entities = HAMapping.entities(loaded, serverID: serverID)
    }

    private func scheduleCatalogRefresh(_ live: HALive) {
        catalogRefresh?.cancel()
        catalogRefresh = Task { [weak self, timing] in
            try? await Task.sleep(for: timing.catalogDebounce)
            guard !Task.isCancelled, let self, self.live === live else { return }
            guard var loaded = try? await self.loadCatalog(live), !Task.isCancelled, self.live === live else { return }
            // Watched states are kept live by the diffs; they are at least as fresh as the refetch.
            for id in self.watched where id.serverID == self.config?.serverID {
                if let state = self.catalog.states[id.localID] { loaded.states[id.localID] = state }
            }
            self.install(loaded)
            self.emit(.catalogChanged)
        }
    }

    // MARK: Watching

    public func watch(_ ids: Set<HomeEntityID>) {
        guard ids != watched else { return }
        watched = ids
        scheduleResubscribe()
    }

    /// Resubscriptions run one after another so unsubscribe/subscribe pairs never interleave.
    private func scheduleResubscribe() {
        let previous = watchTask
        watchTask = Task { [weak self] in
            await previous?.value
            guard let self, let live = self.live, !live.isClosed else { return }
            await self.resubscribe(live)
        }
    }

    private func resubscribe(_ live: HALive) async {
        let serverID = config?.serverID
        let ids = watched.filter { $0.provider == "ha" && $0.serverID == serverID }.map(\.localID).sorted()
        if live.entitiesSubscription != nil, live.subscribedIDs == ids { return }
        live.subscribedIDs = ids
        if let old = live.entitiesSubscription {
            live.entitiesSubscription = nil
            _ = try? await request(live, ["type": "unsubscribe_events", "subscription": .number(Double(old))])
        }
        guard !ids.isEmpty, !live.isClosed else { return }
        let id = live.allocateID()
        live.entitiesSubscription = id
        do {
            _ = try await request(live, ["type": "subscribe_entities", "entity_ids": .array(ids.map { .string($0) })], id: id)
        } catch {
            if live.entitiesSubscription == id {
                live.entitiesSubscription = nil
                live.subscribedIDs = []
            }
        }
    }

    private func applyEntities(_ event: JSONValue) {
        guard let serverID = config?.serverID else { return }
        let result = HAMapping.apply(diff: event, to: &catalog.states, now: now())
        var changed = Set<HomeEntityID>()
        for localID in result.changed {
            let entity = HAMapping.entity(localID: localID, serverID: serverID, meta: catalog.metas[localID],
                                          state: catalog.states[localID])
            entities[entity.id] = entity
            changed.insert(entity.id)
        }
        if !changed.isEmpty { emit(.statesChanged(changed)) }
        for (localID, date) in result.triggered.sorted(by: { $0.value < $1.value }) {
            let id = HomeEntityID(provider: "ha", serverID: serverID, localID: localID)
            if watched.contains(id) { emit(.triggered(id, at: date)) }
        }
    }

    // MARK: Commands

    public func perform(_ command: HomeCommand) async throws {
        guard let config, let live, !live.isClosed, case .connected = connection else {
            throw HomeServiceError(HAFailure.notConnected.message)
        }
        let id = command.entityID
        guard id.provider == "ha", id.serverID == config.serverID else { throw HomeServiceError(HomeStrings.otherServer) }
        guard let call = HAMapping.serviceCall(for: command) else { throw HomeServiceError(HomeStrings.unsupported) }
        var message: [String: JSONValue] = [
            "type": "call_service", "domain": .string(call.domain), "service": .string(call.service),
            "target": ["entity_id": .string(id.localID)],
        ]
        if !call.data.isEmpty { message["service_data"] = .object(call.data) }
        do {
            _ = try await request(live, message)
        } catch let failure as HAFailure {
            throw HomeServiceError(failure.message)
        }
    }

    public func snapshot(camera: HomeEntityID) async throws -> Data {
        guard let config, let token, camera.serverID == config.serverID else {
            throw HomeServiceError(HAFailure.notConnected.message)
        }
        let delegate = HomeTrustDelegate(pinnedSHA256: config.pinnedCertificateSHA256)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let request = HAMapping.snapshotRequest(server: config.url, camera: camera.localID, token: token)
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
            throw HomeServiceError(HomeStrings.camera)
        }
        return data
    }

    // MARK: Sleep and wake

    private func observeSleep() {
        #if canImport(AppKit)
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            let client = self
            MainActor.assumeIsolated { client?.pause() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            let client = self
            MainActor.assumeIsolated { client?.wake() }
        })
        #endif
    }

    func pause() {
        guard tokenIsStored, lifecycle != nil || live != nil else { return }
        generation += 1
        teardown()
        isPaused = true
    }

    func wake() {
        guard isPaused, config != nil, let token else { return }
        isPaused = false
        generation += 1
        setConnection(.connecting)
        startLifecycle(token: token, generation: generation, initial: nil)
    }

    // MARK: Addresses

    /// "homeassistant.local:8123" → http://homeassistant.local:8123. Throws a user-facing error.
    nonisolated public static func normalize(_ raw: String) throws -> URL { try HAMapping.normalize(raw) }
    /// `<server>/profile/security`, where the user creates a long-lived token.
    nonisolated public static func tokenPage(for url: URL) -> URL { url.appending(path: "profile/security") }
}

// MARK: - Support types

struct HomeTiming: Sendable {
    var request: Duration = .seconds(10)
    var bulkRequest: Duration = .seconds(30)
    var handshake: Duration = .seconds(10)
    var ping: Duration = .seconds(60)
    var pong: Duration = .seconds(10)
    var catalogDebounce: Duration = .seconds(1)
    /// Scales the backoff (tests use milliseconds).
    var backoffUnit: Duration = .seconds(1)

    static let standard = HomeTiming()

    func backoff(attempt: Int) -> Duration { backoffUnit * HAMapping.backoffDelay(attempt: attempt) }
}

enum HAFailure: Error, Equatable {
    case unauthorized, needsTrust(String), localNetworkDenied, notFound, timedOut, connectionLost, unexpected
    case server(String), keychain, notConnected, cancelled
    /// A plain http:// address outside the local network: App Transport Security refuses it every time.
    case insecureRemote

    var message: String {
        switch self {
        case .unauthorized: HomeStrings.unauthorized
        case .needsTrust: HomeStrings.needsTrust
        case .localNetworkDenied: HomeStrings.localNetworkDenied
        case .notFound: HomeStrings.notFound
        case .timedOut: HomeStrings.timedOut
        case .connectionLost, .cancelled: HomeStrings.connectionLost
        case .unexpected: HomeStrings.unexpected
        case .server(let message): message.isEmpty ? HomeStrings.unexpected : HomeStrings.haSaid(message)
        case .keychain: HomeStrings.keychain
        case .notConnected: HomeStrings.notConnected
        case .insecureRemote: HomeStrings.insecureRemote
        }
    }

    var state: HomeConnectionState {
        switch self {
        case .unauthorized: .unauthorized
        case .needsTrust(let fingerprint): .needsTrust(fingerprintSHA256: fingerprint)
        case .localNetworkDenied: .localNetworkDenied
        default: .unreachable(reason: message)
        }
    }

    /// Bad tokens and unknown certificates need the user; everything else is retried with backoff.
    var isRetryable: Bool {
        switch self {
        case .unauthorized, .needsTrust, .cancelled, .insecureRemote: false
        default: true
        }
    }
}

/// One open socket and its bookkeeping. Replaced on every reconnect.
@MainActor
final class HALive {
    let socket: any HomeSocket
    let delegate: HomeTrustDelegate
    var nextID = 1
    var pending: [Int: HAPending] = [:]
    var entitiesSubscription: Int?
    var subscribedIDs: [String] = []
    var registrySubscriptions: Set<Int> = []
    var reader: Task<Void, Never>?
    var keepalive: Task<Void, Never>?
    var isClosed = false
    var handshakeTimedOut = false

    init(socket: any HomeSocket, delegate: HomeTrustDelegate) {
        self.socket = socket
        self.delegate = delegate
    }

    func allocateID() -> Int {
        defer { nextID += 1 }
        return nextID
    }

    func resolve(_ id: Int, _ result: Result<JSONValue, any Error>) {
        pending.removeValue(forKey: id)?.fulfil(result)
    }
}

/// A request waiting for its result. The answer may arrive before anyone awaits it.
@MainActor
final class HAPending {
    private var result: Result<JSONValue, any Error>?
    private var continuation: CheckedContinuation<JSONValue, any Error>?
    var timeout: Task<Void, Never>?

    func fulfil(_ result: Result<JSONValue, any Error>) {
        guard self.result == nil else { return }
        self.result = result
        timeout?.cancel()
        if let continuation {
            self.continuation = nil
            continuation.resume(with: result)
        }
    }

    func value() async throws -> JSONValue {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
}
