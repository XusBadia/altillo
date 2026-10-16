import AltilloHome
import AppKit
import Foundation
import Observation

/// The Home section's brain (docs/casa.md): one connected home, the user's favourites in their order, the doorbell,
/// and what each tile shows while a command is on its way.
///
/// It talks to its `HomeService` only while the Home section is on, with the notch closed too (the ear and the
/// doorbell need it), and lets go as soon as the section is put away. Everything is event-driven: the service pushes
/// state changes, and the ear's only timer sleeps until the next moment its words change.
///
/// Tiles are optimistic: a click changes the tile at once and it stays "pending" until the next state the server
/// sends for that entity. It only goes back (and says why, briefly) if the command itself fails; a fixed timeout
/// would be wrong for blinds and slow transitions.
@MainActor
@Observable
final class HomeStore {
    let service: any HomeService
    let settings: AltilloSettings

    /// The state a tile shows while its command is on the way (the one we expect), until the next push for it.
    private(set) var pending: [HomeEntityID: HomeEntityState] = [:]
    /// Scenes and scripts being fired right now, and the ones that just went off (a tick for a moment).
    private(set) var firing: Set<HomeEntityID> = []
    private(set) var fired: Set<HomeEntityID> = []
    /// A short line under a tile whose command failed. Clears itself after a few seconds.
    private(set) var problems: [HomeEntityID: String] = [:]
    /// The last ring of the chosen doorbell, with the camera's picture once it arrives.
    private(set) var ring: HomeRing?
    /// Moved forward by the ear's single timer; the ear reads the time from here.
    private(set) var clock = Date.now
    private(set) var isModuleEnabled = false
    /// Settings › Home: connecting right now, and why the last try failed.
    private(set) var isConnecting = false
    private(set) var connectError: String?
    /// A server waiting for "Trust this certificate": kept in memory only, never saved until the connection works.
    private(set) var untrustedServer: HomeServerConfig?
    /// The area chip being explored in the notch (`watchArea`), nil on a page. Its entities are watched meanwhile.
    var selectedArea: String?
    /// How many favourites the first-connect suggestions picked, while the one-time "Altillo picked N to start ·
    /// Change" hint should show; 0 once dismissed or when the user edits Favourites (`HomeStore+Layout.swift`).
    var autoSuggestedCount = 0

    /// Injected so tests control time, throttling and how the address is read.
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored var throttle: Duration = .milliseconds(150)
    @ObservationIgnored var problemDuration: Duration = .seconds(4)
    @ObservationIgnored var normalize: (String) throws -> URL = { try HomeAssistantClient.normalize($0) }

    /// How long the camera card stays at the top of the section after a ring.
    static let ringFreshness: TimeInterval = 120
    /// "Suggest favourites" picks at most this many.
    static let suggestionLimit = 8
    /// The most entities an explored area adds to the watch set.
    static let areaWatchLimit = 40

    /// The colour each light last showed, so one turning on glows with it before the server confirms.
    @ObservationIgnored private var lastColors: [HomeEntityID: HomeRGB] = [:]
    @ObservationIgnored private var lastBrightness: [HomeEntityID: Double] = [:]
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var earTask: Task<Void, Never>?
    @ObservationIgnored private var drags: [HomeEntityID: DragThrottle] = [:]
    /// Bumped each time a tile's expected state changes, so a fallback only clears the state it was armed for.
    @ObservationIgnored private var pendingGeneration: [HomeEntityID: Int] = [:]
    /// The value a finished drag ended on: its tile stays pending until a push reaches it (or the fallback fires),
    /// so the pushes for throttled values on the way don't make it jump back.
    @ObservationIgnored private var settleTargets: [HomeEntityID: Double] = [:]
    /// After a command went through, how long a tile waits for its push before showing the server's state anyway.
    @ObservationIgnored var pendingFallback: Duration = .seconds(10)
    @ObservationIgnored private(set) var watched: Set<HomeEntityID> = []
    @ObservationIgnored private var hasWatched = false

    init(service: any HomeService, settings: AltilloSettings) {
        self.service = service
        self.settings = settings
    }

    // MARK: - Lifecycle

    /// The Home section was switched on or off. On: connect with the saved server and listen. Off: let go.
    func setModuleEnabled(_ enabled: Bool) {
        guard enabled != isModuleEnabled else { return }
        isModuleEnabled = enabled
        if enabled {
            listen()
            if let server = settings.homeServer { service.resume(server) }
            refreshWatch()
            scheduleEar()
        } else {
            eventsTask?.cancel()
            eventsTask = nil
            earTask?.cancel()
            earTask = nil
            drags.values.forEach { $0.task?.cancel() }
            drags.removeAll()
            pending.removeAll()
            selectedArea = nil
            autoSuggestedCount = 0
            hasWatched = false
            watched = []
            service.disconnect(forget: false)
        }
    }

    private func listen() {
        guard eventsTask == nil else { return }
        let stream = service.events()
        eventsTask = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { return }
                self.handle(event)
            }
        }
    }

    /// One event from the service. Internal so tests can drive it without a stream.
    func handle(_ event: HomeServiceEvent) {
        switch event {
        case .connectionChanged:
            if case let .connected(serverName, _) = service.connection, var server = settings.homeServer,
               server.name != serverName, !serverName.isEmpty {
                server.name = serverName
                settings.homeServer = server
            }
            autoSuggestIfNeeded()
            refreshWatch()
            scheduleEar()
        case .catalogChanged:
            for entity in service.entities.values where entity.kind == .light { remember(entity.state, for: entity.id) }
            autoSuggestIfNeeded()
            refreshWatch()
            scheduleEar()
        case let .statesChanged(ids):
            for id in ids {
                remember(service.entities[id]?.state, for: id)
                guard drags[id] == nil, pending[id] != nil else { continue }
                if let target = settleTargets[id] {
                    guard let entity = service.entities[id], Self.reached(target, entity) else { continue }
                    settleTargets[id] = nil
                }
                pending[id] = nil
            }
            if let zone = zoneID, ids.contains(zone) { refreshWatch() }
            scheduleEar()
        case let .triggered(id, at):
            if id == doorbellTrigger { recordRing(at: at) }
        }
    }

    // MARK: - Connection (Settings › Home)

    var connection: HomeConnectionState { service.connection }

    var isConnected: Bool {
        if case .connected = service.connection { true } else { false }
    }

    /// The name shown above the tiles: HA's `location_name`, or plain "Home".
    var homeName: String {
        if case let .connected(serverName, _) = service.connection, !serverName.isEmpty { return serverName }
        if let name = settings.homeServer?.name, !name.isEmpty { return name }
        return String(localized: "Home")
    }

    /// Checks the address and token and stays connected. Keeps the server's id when only the address changes, so
    /// favourites survive a new URL.
    func connect(address: String, token: String) async {
        connectError = nil
        let url: URL
        do {
            url = try normalize(address)
        } catch {
            connectError = Self.message(for: error)
            return
        }
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            connectError = String(localized: "Paste a long-lived access token from your Home Assistant profile.")
            return
        }
        var config = settings.homeServer ?? untrustedServer ?? HomeServerConfig(url: url)
        config.url = url
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await service.connect(config, token: token)
            if case let .connected(serverName, _) = service.connection { config.name = serverName }
            didConnect(config)
        } catch {
            // A self-signed certificate waits for the user's decision. The server stays in memory only: saved
            // before it's trusted, a relaunch would resume it without the pin and read as "token rejected".
            if case .needsTrust = service.connection { untrustedServer = config }
            connectError = Self.message(for: error)
        }
    }

    /// Pins the certificate shown in `.needsTrust` and connects again; the server is saved only once that works.
    func trustCertificate(_ fingerprint: String) async {
        guard isModuleEnabled, !isConnecting else { return }
        connectError = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            var config = try await service.trustCertificate(fingerprint)
            if case let .connected(serverName, _) = service.connection, !serverName.isEmpty { config.name = serverName }
            didConnect(config)
        } catch {
            connectError = Self.message(for: error)
        }
    }

    private func didConnect(_ config: HomeServerConfig) {
        settings.homeServer = config
        untrustedServer = nil
        if isModuleEnabled { listen() }
        autoSuggestIfNeeded()
        refreshWatch()
        scheduleEar()
    }

    /// Tries again now (after "Can't reach your home", or with the Local Network permission just granted).
    func reconnect() {
        guard let server = settings.homeServer else { return }
        service.resume(server)
    }

    /// Disconnect: closes the connection, deletes the token and forgets this server's layout and doorbell. The next
    /// server gets its own first-connect suggestions.
    func forget() {
        service.disconnect(forget: true)
        settings.homeServer = nil
        untrustedServer = nil
        settings.homeLayout = HomeLayout()
        settings.homeDidAutoSuggest = false
        autoSuggestedCount = 0
        selectedArea = nil
        settings.homeDoorbellTrigger = nil
        settings.homeDoorbellCamera = nil
        pending.removeAll()
        problems.removeAll()
        ring = nil
        connectError = nil
        refreshWatch()
    }

    // MARK: - Catalogue

    /// Favourites can be lights, plugs, blinds, scenes, scripts, fans and sensors; never locks, alarms or garage
    /// doors in H1 (they will need press-and-hold).
    static func canFavourite(_ entity: HomeEntity) -> Bool {
        entity.kind.isFavouritable && !entity.isDangerous
    }

    var areas: [HomeArea] { service.areas }

    func area(_ id: String?) -> HomeArea? {
        guard let id else { return nil }
        return service.areas.first { $0.id == id }
    }

    /// What a tile shows: the expected state while a command is on its way, the server's otherwise.
    func state(of entity: HomeEntity) -> HomeEntityState {
        pending[entity.id] ?? entity.state
    }

    func isPending(_ id: HomeEntityID) -> Bool { pending[id] != nil || firing.contains(id) }

    /// The colour a light is (or would be) showing, for its glow. A warm white when the bulb never said.
    func glowColor(for entity: HomeEntity) -> HomeRGB {
        state(of: entity).color ?? lastColors[entity.id] ?? Self.warmWhite
    }

    static let warmWhite = HomeRGB(red: 1, green: 0.78, blue: 0.5)

    // MARK: - Favourites (H1 API, kept for existing callers; the layout API is in HomeStore+Layout.swift)

    /// Favourites' entities in order, hidden tiles included.
    var favouriteIDs: [HomeEntityID] { settings.homeLayout.favouriteEntities }

    /// The favourites the notch shows: known to the server, favouritable, not hidden, in the user's order.
    var favourites: [HomeEntity] { tiles(onPage: nil).map(\.entity) }

    /// Areas holding at least one favourite, in the server's order: the chips above the tiles.
    var favouriteAreas: [HomeArea] {
        let used = Set(favourites.compactMap(\.areaID))
        return service.areas.filter { used.contains($0.id) }
    }

    func setFavourite(_ id: HomeEntityID, _ isFavourite: Bool) {
        if isFavourite { addFavourite(id) } else { removeFavourite(id) }
    }

    /// Settings › Home: a favourite dragged onto another lands just before it (or after it, coming from above).
    func moveFavourite(_ id: HomeEntityID, onto target: HomeEntityID) {
        moveTile(from: id, to: target)
    }

    func moveFavourites(fromOffsets source: IndexSet, toOffset destination: Int) {
        moveTiles(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Doorbell

    var doorbellTrigger: HomeEntityID? { settings.homeDoorbellTrigger.flatMap(HomeEntityID.init(rawValue:)) }
    var doorbellCamera: HomeEntityID? { settings.homeDoorbellCamera.flatMap(HomeEntityID.init(rawValue:)) }

    func setDoorbellTrigger(_ id: HomeEntityID?) {
        settings.homeDoorbellTrigger = id?.rawValue
        refreshWatch()
    }

    func setDoorbellCamera(_ id: HomeEntityID?) {
        settings.homeDoorbellCamera = id?.rawValue
    }

    /// What can ring: `event.*` entities (modern doorbells) and binary sensors (older ones, a button).
    var doorbellCandidates: [HomeEntity] {
        service.entities.values
            .filter { $0.kind == .event || ($0.kind == .binarySensor && !HomeEarLogic.isOpening($0)) }
            .sorted { Self.doorbellRank($0) < Self.doorbellRank($1) }
    }

    var cameras: [HomeEntity] {
        service.entities.values.filter { $0.kind == .camera }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func doorbellRank(_ entity: HomeEntity) -> String {
        let likely = entity.deviceClass == "doorbell" || entity.id.localID.contains("doorbell")
            || entity.id.localID.contains("timbre")
        return (likely ? "0" : "1") + (entity.kind == .event ? "0" : "1") + entity.name
    }

    /// The camera card stays this long after a ring.
    func isRingFresh(at date: Date) -> Bool {
        guard let ring else { return false }
        return date.timeIntervalSince(ring.at) < Self.ringFreshness
    }

    func dismissRing() { ring = nil }

    /// Someone rang: remember when, and fetch the camera's picture for the peek and the card.
    func recordRing(at date: Date) {
        guard let trigger = doorbellTrigger else { return }
        ring = HomeRing(entity: trigger, at: date)
        refreshSnapshot()
    }

    /// Fetches the doorbell camera's picture again (the card's refresh button).
    func refreshSnapshot() {
        guard let camera = doorbellCamera, let at = ring?.at else { return }
        ring?.isLoadingSnapshot = true
        Task { [weak self] in
            let data = try? await self?.service.snapshot(camera: camera)
            guard let self, self.ring?.at == at else { return }
            self.ring?.isLoadingSnapshot = false
            if let data, let image = NSImage(data: data) { self.ring?.snapshot = image }
        }
    }

    // MARK: - Commands

    /// A click on a tile: lights, plugs and fans toggle; blinds open or close (or stop while moving); scenes and
    /// scripts go off.
    func activate(_ entity: HomeEntity) {
        let id = entity.id
        let current = state(of: entity)
        guard current.isAvailable else { return }
        switch entity.kind {
        case .scene, .script:
            fire(entity)
        case .cover:
            var predicted = current
            if current.raw == "opening" || current.raw == "closing" {
                predicted.raw = (current.position ?? 0) > 0 ? "open" : "closed"
                send(.stop(id), predicted: predicted)
            } else if Self.coverIsOpen(current) {
                predicted.raw = "closing"
                send(.close(id), predicted: predicted)
            } else {
                predicted.raw = "opening"
                send(.open(id), predicted: predicted)
            }
        case .light, .switchable, .fan:
            let turnOn = current.isOn != true
            send(turnOn ? .turnOn(id) : .turnOff(id), predicted: predicted(entity, on: turnOn))
        default:
            return
        }
    }

    /// A drag across a tile: brightness for a light, position for a blind. Sends at most one command every
    /// `throttle` while the finger moves, and always the value it ends on (`final`).
    func drag(_ entity: HomeEntity, to value: Double, final: Bool) {
        let id = entity.id
        let value = min(max(value, 0), 1)
        var predicted = state(of: entity)
        let command: HomeCommand
        switch entity.kind {
        case .light:
            predicted = self.predicted(entity, on: value > 0)
            predicted.brightness = value > 0 ? value : nil
            command = .setBrightness(id, value)
        case .cover:
            predicted.position = value
            predicted.raw = value > 0 ? "open" : "closed"
            command = .setPosition(id, value)
        default:
            return
        }
        markPending(id, predicted)
        problems[id] = nil

        var throttle = drags[id] ?? DragThrottle()
        throttle.latest = command
        if final {
            throttle.task?.cancel()
            drags[id] = nil
            settleTargets[id] = value
            if throttle.lastSent != command {
                perform(command, armsFallback: true)
            } else {
                armFallback(for: id)
            }
            return
        }
        let moment = ContinuousClock.now
        if let sentAt = throttle.sentAt, moment - sentAt < self.throttle {
            if throttle.task == nil {
                let wake = sentAt + self.throttle
                throttle.task = Task { [weak self] in
                    try? await Task.sleep(until: wake, clock: .continuous)
                    guard !Task.isCancelled else { return }
                    self?.flushDrag(id)
                }
            }
        } else {
            throttle.sentAt = moment
            throttle.lastSent = command
            perform(command)
        }
        drags[id] = throttle
    }

    private func flushDrag(_ id: HomeEntityID) {
        guard var throttle = drags[id] else { return }
        throttle.task = nil
        if let latest = throttle.latest, latest != throttle.lastSent {
            throttle.sentAt = ContinuousClock.now
            throttle.lastSent = latest
            perform(latest)
        }
        drags[id] = throttle
    }

    private func fire(_ entity: HomeEntity) {
        let id = entity.id
        guard !firing.contains(id) else { return }
        firing.insert(id)
        fired.remove(id)
        problems[id] = nil
        Task { [weak self] in
            do {
                try await self?.service.perform(.activate(id))
                guard let self else { return }
                self.firing.remove(id)
                self.fired.insert(id)
                try? await Task.sleep(for: .milliseconds(1_400))
                self.fired.remove(id)
            } catch {
                self?.firing.remove(id)
                self?.report(error, for: id)
            }
        }
    }

    private func send(_ command: HomeCommand, predicted: HomeEntityState) {
        settleTargets[command.entityID] = nil
        markPending(command.entityID, predicted)
        problems[command.entityID] = nil
        perform(command, armsFallback: true)
    }

    private func markPending(_ id: HomeEntityID, _ state: HomeEntityState) {
        pending[id] = state
        pendingGeneration[id, default: 0] += 1
    }

    /// Throttled drag values don't arm the fallback; a click and a drag's last value do.
    private func perform(_ command: HomeCommand, armsFallback: Bool = false) {
        let id = command.entityID
        Task { [weak self] in
            do {
                try await self?.service.perform(command)
                if armsFallback { self?.armFallback(for: id) }
            } catch {
                guard let self else { return }
                // The command didn't happen: show the server's state again, and why.
                self.drags[id]?.task?.cancel()
                self.drags[id] = nil
                self.pending[id] = nil
                self.settleTargets[id] = nil
                self.report(error, for: id)
            }
        }
    }

    /// One shot per command, not a poll: if no push came for this exact expected state within `pendingFallback`,
    /// the tile shows the server's state (a command that changed nothing, a dropped push).
    private func armFallback(for id: HomeEntityID) {
        guard pending[id] != nil else { return }
        let generation = pendingGeneration[id]
        let wait = pendingFallback
        Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, self.pendingGeneration[id] == generation, self.drags[id] == nil else { return }
            self.pending[id] = nil
            self.settleTargets[id] = nil
        }
    }

    /// Whether the server's state has reached a drag's last value (brightness or position, within rounding).
    nonisolated static func reached(_ target: Double, _ entity: HomeEntity) -> Bool {
        let state = entity.state
        switch entity.kind {
        case .light:
            if target <= 0 { return state.isOn != true }
            return state.isOn == true && abs((state.brightness ?? 1) - target) < 0.02
        case .cover:
            guard let position = state.position else { return true }
            return abs(position - target) < 0.02
        default:
            return true
        }
    }

    private func report(_ error: Error, for id: HomeEntityID) {
        let message = Self.message(for: error)
        problems[id] = message
        let duration = problemDuration
        Task { [weak self] in
            try? await Task.sleep(for: duration)
            if self?.problems[id] == message { self?.problems[id] = nil }
        }
    }

    private func predicted(_ entity: HomeEntity, on: Bool) -> HomeEntityState {
        var next = self.state(of: entity)
        next.isOn = on
        next.raw = on ? "on" : "off"
        if entity.kind == .light {
            if on {
                next.brightness = next.brightness
                    ?? (entity.capabilities.contains(.brightness) ? lastBrightness[entity.id] ?? 1 : nil)
                next.color = next.color ?? lastColors[entity.id] ?? Self.warmWhite
            } else {
                remember(next, for: entity.id)
                next.brightness = nil
                next.color = nil
            }
        }
        return next
    }

    /// Keeps how a light looked while on, for the next time it turns on.
    private func remember(_ state: HomeEntityState?, for id: HomeEntityID) {
        if let color = state?.color { lastColors[id] = color }
        if let brightness = state?.brightness, brightness > 0 { lastBrightness[id] = brightness }
    }

    nonisolated static func coverIsOpen(_ state: HomeEntityState) -> Bool {
        if let position = state.position { return position > 0 }
        return state.raw == "open" || state.raw == "opening"
    }

    nonisolated static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Watching

    /// `zone.home` of the connected server: how many people are home.
    var zoneID: HomeEntityID? {
        settings.homeServer.map { HomeEntityID(provider: "ha", serverID: $0.serverID, localID: "zone.home") }
    }

    /// What the service keeps live: shown tiles, the explored area, the doorbell, `zone.home`, the doors the ear watches and, while
    /// nobody's home, every light (to count the ones left on).
    /// Plus the shown tiles of every page and, while one is explored, the area's entities (`watchArea`).
    func watchSet() -> Set<HomeEntityID> {
        var ids = Set(settings.homeLayout.pages.flatMap { $0.visibleTiles.map(\.entity) })
        ids.formUnion(areaWatchSet())
        if let doorbellTrigger { ids.insert(doorbellTrigger) }
        if let zoneID { ids.insert(zoneID) }
        let entities = service.entities
        ids.formUnion(HomeEarLogic.earSensors(in: entities))
        if HomeEarLogic.isAway(entities, zone: zoneID) { ids.formUnion(HomeEarLogic.lights(in: entities)) }
        return ids
    }

    func refreshWatch() {
        guard isModuleEnabled else { return }
        let ids = watchSet()
        guard !hasWatched || ids != watched else { return }
        hasWatched = true
        watched = ids
        service.watch(ids)
    }

    // MARK: - Ear

    /// What the contextual ear says about the house, if anything (`HomeEarLogic`).
    var contextualSignal: HomeSignal? {
        guard isModuleEnabled, isConnected else { return nil }
        return HomeEarLogic.signal(entities: service.entities, watched: watched, zone: zoneID, now: clock)
    }

    /// One timer at most: asleep until a door crosses the threshold (or its minute changes), never a poll.
    func scheduleEar() {
        earTask?.cancel()
        earTask = nil
        clock = now()
        guard isModuleEnabled, isConnected, earCanShow,
              let next = HomeEarLogic.nextChange(entities: service.entities, watched: watched, now: clock)
        else { return }
        let delay = max(0.05, next.timeIntervalSince(clock))
        earTask = Task { [weak self] in
            // Minute labels: a few seconds late is fine, and lets the system batch the wake-up.
            try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.scheduleEar()
        }
    }

    /// The house only talks in an ear set to "What matters now" (`EarsArrangementLogic`).
    private var earCanShow: Bool {
        settings.leftEar == .automatic || settings.rightEar == .automatic
    }

    /// Whether the ear's single timer is waiting (tests).
    var hasScheduledEar: Bool { earTask != nil }
}

/// The last ring of the doorbell: when, and the camera's picture once it arrives.
struct HomeRing: Equatable {
    let entity: HomeEntityID
    let at: Date
    var snapshot: NSImage?
    var isLoadingSnapshot = false
}

/// A drag's sending rhythm: when the last command went out, which one, and the newest value waiting.
private struct DragThrottle {
    var sentAt: ContinuousClock.Instant?
    var lastSent: HomeCommand?
    var latest: HomeCommand?
    var task: Task<Void, Never>?
}
