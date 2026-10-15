import AltilloHome
import AppKit
import Foundation
import Testing
@testable import Altillo

@MainActor
struct HomeTests {
    // MARK: Fixtures

    final class FakeHomeService: HomeService {
        var connection: HomeConnectionState = .connected(serverName: "Casa", version: "2026.10")
        var areas: [HomeArea] = [HomeArea(id: "living", name: "Living room"), HomeArea(id: "hall", name: "Hall")]
        var entities: [HomeEntityID: HomeEntity] = [:]
        var watched: Set<HomeEntityID> = []
        var performed: [HomeCommand] = []
        var failure: HomeServiceError?
        var resumes = 0
        var connectFailure: (HomeConnectionState, HomeServiceError)?
        var trusted: [String] = []
        var trustFailure: HomeServiceError?
        var lastConfig: HomeServerConfig?
        var disconnects: [Bool] = []
        private var continuations: [AsyncStream<HomeServiceEvent>.Continuation] = []

        func events() -> AsyncStream<HomeServiceEvent> {
            let (stream, continuation) = AsyncStream<HomeServiceEvent>.makeStream()
            continuations.append(continuation)
            return stream
        }

        func connect(_ config: HomeServerConfig, token: String) async throws {
            lastConfig = config
            if let (state, error) = connectFailure {
                connection = state
                throw error
            }
            connection = .connected(serverName: "Casa", version: "2026.10")
        }

        func resume(_ config: HomeServerConfig) { resumes += 1 }

        func trustCertificate(_ fingerprintSHA256: String) async throws -> HomeServerConfig {
            trusted.append(fingerprintSHA256)
            if let trustFailure { throw trustFailure }
            guard var config = lastConfig else { throw HomeServiceError("Nothing to trust.") }
            config.pinnedCertificateSHA256 = fingerprintSHA256
            connection = .connected(serverName: "Casa", version: "2026.10")
            return config
        }
        func disconnect(forget: Bool) { disconnects.append(forget) }
        func watch(_ ids: Set<HomeEntityID>) { watched = ids }
        func snapshot(camera: HomeEntityID) async throws -> Data { Data() }

        func perform(_ command: HomeCommand) async throws {
            performed.append(command)
            if let failure { throw failure }
        }

        func add(_ entity: HomeEntity) { entities[entity.id] = entity }
    }

    static let server = "srv"

    static func id(_ local: String) -> HomeEntityID {
        HomeEntityID(provider: "ha", serverID: server, localID: local)
    }

    static func light(_ local: String, on: Bool = false, area: String? = "living", technical: Bool = false) -> HomeEntity {
        HomeEntity(id: id(local), name: local, kind: .light, areaID: area, capabilities: [.toggle, .brightness],
                   isTechnical: technical,
                   state: HomeEntityState(raw: on ? "on" : "off", isOn: on, brightness: on ? 0.5 : nil))
    }

    static func sensor(_ local: String, deviceClass: String, open: Bool, since: Date) -> HomeEntity {
        HomeEntity(id: id(local), name: "Front door", kind: .binarySensor, deviceClass: deviceClass, areaID: "hall",
                   state: HomeEntityState(raw: open ? "on" : "off", isOn: open, lastChanged: since))
    }

    static func zone(_ people: String) -> HomeEntity {
        HomeEntity(id: id("zone.home"), name: "Home", kind: .other, isTechnical: true,
                   state: HomeEntityState(raw: people))
    }

    private func makeSettings() -> (AltilloSettings, UserDefaults) {
        TestDefaultsJanitor.purgeStale()
        let name = "me.badia.altillo.tests.home-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AltilloSettings(defaults: defaults)
        settings.homeServer = HomeServerConfig(serverID: Self.server, url: URL(string: "http://ha.local:8123")!)
        return (settings, defaults)
    }

    private func makeStore() -> (HomeStore, FakeHomeService, AltilloSettings) {
        let (settings, _) = makeSettings()
        let service = FakeHomeService()
        let store = HomeStore(service: service, settings: settings)
        return (store, service, settings)
    }

    /// Lets the store's command tasks run.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    // MARK: Module

    @Test func homeIsAnOptInSection() {
        let (settings, _) = makeSettings()
        #expect(NotchModule.home.isOptIn)
        #expect(!settings.isEnabled(.home))
        #expect(!NotchPreset.minimal.modules.contains(.home))
        #expect(NotchPreset.everything.modules.contains(.home))
    }

    @Test func connectsOnlyWhileTheSectionIsOn() {
        let (store, service, _) = makeStore()
        #expect(service.resumes == 0)
        store.setModuleEnabled(true)
        #expect(service.resumes == 1)
        store.setModuleEnabled(true)
        #expect(service.resumes == 1, "enabling twice doesn't reconnect")
        store.setModuleEnabled(false)
        #expect(service.disconnects == [false], "putting the section away closes the connection, keeping the token")
    }

    @Test func withoutAServerEnablingDoesNotConnect() {
        let (store, service, settings) = makeStore()
        settings.homeServer = nil
        store.setModuleEnabled(true)
        #expect(service.resumes == 0)
    }

    // MARK: Favourites

    @Test func favouritesPersistInTheirOrder() {
        let (settings, defaults) = makeSettings()
        let store = HomeStore(service: FakeHomeService(), settings: settings)
        let a = Self.id("light.a"), b = Self.id("light.b"), c = Self.id("light.c")
        store.setFavourite(a, true)
        store.setFavourite(b, true)
        store.setFavourite(c, true)
        store.setFavourite(b, true)
        store.moveFavourite(c, onto: a)
        #expect(store.favouriteIDs == [c, a, b])
        store.setFavourite(a, false)
        let reloaded = AltilloSettings(defaults: defaults)
        #expect(reloaded.homeFavourites == [c.rawValue, b.rawValue])
        #expect(reloaded.homeServer?.serverID == Self.server)
    }

    @Test func dangerousAndUnsupportedEntitiesAreNeverFavourites() {
        let lock = HomeEntity(id: Self.id("lock.door"), name: "Lock", kind: .lock, isDangerous: true,
                              state: HomeEntityState(raw: "locked"))
        let garage = HomeEntity(id: Self.id("cover.garage"), name: "Garage", kind: .cover, isDangerous: true,
                                state: HomeEntityState(raw: "closed"))
        #expect(!HomeStore.canFavourite(lock))
        #expect(!HomeStore.canFavourite(garage))
        #expect(HomeStore.canFavourite(Self.light("light.a")))
    }

    @Test func suggestionsSkipTechnicalAndRoomlessAndStopAtEight() {
        let (store, service, _) = makeStore()
        for index in 0..<12 { service.add(Self.light("light.l\(index)", area: index.isMultiple(of: 2) ? "living" : "hall")) }
        service.add(Self.light("light.helper", technical: true))
        service.add(Self.light("light.nowhere", area: nil))
        let suggested = store.suggestedFavourites()
        #expect(suggested.count == HomeStore.suggestionLimit)
        #expect(!suggested.contains(Self.id("light.helper")))
        #expect(!suggested.contains(Self.id("light.nowhere")))
        // Rooms take turns.
        #expect(service.entities[suggested[0]]?.areaID != service.entities[suggested[1]]?.areaID)
    }

    // MARK: Watching

    @Test func watchesFavouritesDoorbellZoneAndDoors() {
        let (store, service, settings) = makeStore()
        let now = Date.now
        service.add(Self.light("light.a"))
        service.add(Self.light("light.b"))
        service.add(Self.sensor("binary_sensor.front", deviceClass: "door", open: false, since: now))
        service.add(Self.sensor("binary_sensor.garage", deviceClass: "garage_door", open: false, since: now))
        service.add(Self.sensor("binary_sensor.window", deviceClass: "window", open: false, since: now))
        service.add(Self.zone("1"))
        settings.homeFavourites = [Self.id("light.a").rawValue]
        settings.homeDoorbellTrigger = Self.id("event.bell").rawValue
        store.setModuleEnabled(true)
        // Garages always; doors and windows only as favourites.
        #expect(service.watched == [Self.id("light.a"), Self.id("event.bell"), Self.id("zone.home"),
                                    Self.id("binary_sensor.garage")])

        // Everybody left: every light is watched, to count the ones left on.
        service.entities[Self.id("zone.home")] = Self.zone("0")
        store.handle(.statesChanged([Self.id("zone.home")]))
        #expect(service.watched.contains(Self.id("light.b")))

        store.setFavourite(Self.id("binary_sensor.window"), true)
        #expect(service.watched.contains(Self.id("binary_sensor.window")))
    }

    // MARK: Optimistic tiles

    @Test func aClickFlipsTheTileAtOnceAndStaysPendingUntilTheServerSpeaks() async {
        let (store, service, _) = makeStore()
        let light = Self.light("light.a")
        service.add(light)
        store.activate(light)
        #expect(store.state(of: light).isOn == true)
        #expect(store.isPending(light.id))
        await settle { !service.performed.isEmpty }
        #expect(service.performed == [.turnOn(light.id)])
        #expect(store.isPending(light.id), "still pending: no state from the server yet")
        service.entities[light.id] = Self.light("light.a", on: true)
        store.handle(.statesChanged([light.id]))
        #expect(!store.isPending(light.id))
        #expect(store.state(of: light).isOn == false, "the store now reads the service's state")
        #expect(store.state(of: service.entities[light.id]!).isOn == true)
    }

    @Test func aFailedCommandRevertsAndSaysWhy() async {
        let (store, service, _) = makeStore()
        store.problemDuration = .seconds(60)
        let light = Self.light("light.a")
        service.add(light)
        service.failure = HomeServiceError("The bulb is offline.")
        store.activate(light)
        #expect(store.state(of: light).isOn == true)
        await settle { store.problems[light.id] != nil }
        #expect(store.problems[light.id] == "The bulb is offline.")
        #expect(!store.isPending(light.id))
        #expect(store.state(of: light).isOn == false)
    }

    @Test func dragsAreThrottledAndAlwaysSendTheFinalValue() async {
        let (store, service, _) = makeStore()
        store.throttle = .seconds(60)
        let light = Self.light("light.a", on: true)
        service.add(light)
        store.drag(light, to: 0.2, final: false)
        store.drag(light, to: 0.4, final: false)
        store.drag(light, to: 0.6, final: false)
        #expect(store.state(of: light).brightness == 0.6)
        store.drag(light, to: 0.7, final: true)
        await settle { service.performed.count >= 2 }
        try? await Task.sleep(for: .milliseconds(30))
        #expect(service.performed == [.setBrightness(light.id, 0.2), .setBrightness(light.id, 0.7)])
    }

    @Test func coversOpenWhenClosedAndCloseWhenOpen() async {
        let (store, service, _) = makeStore()
        let blind = HomeEntity(id: Self.id("cover.blind"), name: "Blind", kind: .cover,
                               capabilities: [.openClose, .position], state: HomeEntityState(raw: "open", position: 0.4))
        service.add(blind)
        store.activate(blind)
        #expect(store.state(of: blind).raw == "closing")
        await settle { !service.performed.isEmpty }
        #expect(service.performed == [.close(blind.id)])
    }

    // MARK: Ear

    @Test func aDoorOpenPastTenMinutesTalksInTheEar() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let door = Self.sensor("binary_sensor.front", deviceClass: "door", open: true, since: now.addingTimeInterval(-12 * 60))
        let entities = [door.id: door]
        #expect(HomeEarLogic.signal(entities: entities, watched: [door.id], zone: nil, now: now)
            == .leftOpen(name: "Front door", deviceClass: "door", since: door.state.lastChanged!))
        #expect(HomeEarLogic.minutes(since: door.state.lastChanged!, now: now) == 12)
        // Not watched: not mentioned.
        #expect(HomeEarLogic.signal(entities: entities, watched: [], zone: nil, now: now) == nil)
        // Next words: the next minute.
        #expect(HomeEarLogic.nextChange(entities: entities, watched: [door.id], now: now)
            == door.state.lastChanged!.addingTimeInterval(13 * 60))
    }

    @Test func aDoorOpenUnderTenMinutesWaitsWithOneTimer() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let since = now.addingTimeInterval(-4 * 60)
        let door = Self.sensor("binary_sensor.front", deviceClass: "door", open: true, since: since)
        let closed = Self.sensor("binary_sensor.back", deviceClass: "door", open: false, since: since)
        let entities = [door.id: door, closed.id: closed]
        #expect(HomeEarLogic.signal(entities: entities, watched: [door.id, closed.id], zone: nil, now: now) == nil)
        #expect(HomeEarLogic.nextChange(entities: entities, watched: [door.id, closed.id], now: now)
            == since.addingTimeInterval(HomeEarLogic.openThreshold))
        #expect(HomeEarLogic.nextChange(entities: [closed.id: closed], watched: [closed.id], now: now) == nil,
                "nothing open: no timer at all")
    }

    @Test func storeSchedulesTheEarTimerOnlyWhileADoorIsOpen() {
        let (store, service, settings) = makeStore()
        let door = Self.sensor("binary_sensor.front", deviceClass: "door", open: false, since: .now)
        service.add(door)
        settings.homeFavourites = [door.id.rawValue]
        store.setModuleEnabled(true)
        #expect(!store.hasScheduledEar)
        service.entities[door.id] = Self.sensor("binary_sensor.front", deviceClass: "door", open: true, since: .now)
        store.handle(.statesChanged([door.id]))
        #expect(store.hasScheduledEar)
        #expect(store.contextualSignal == nil, "just opened: nothing to say yet")
    }

    @Test func lightsLeftOnWhileNobodyIsHome() {
        let zone = Self.zone("0")
        let on1 = Self.light("light.a", on: true), on2 = Self.light("light.b", on: true)
        let off = Self.light("light.c"), helper = Self.light("light.helper", on: true, technical: true)
        var entities = [zone.id: zone, on1.id: on1, on2.id: on2, off.id: off, helper.id: helper]
        #expect(HomeEarLogic.signal(entities: entities, watched: [], zone: zone.id, now: .now) == .lightsOnWhileAway(count: 2))
        entities[zone.id] = Self.zone("1")
        #expect(HomeEarLogic.signal(entities: entities, watched: [], zone: zone.id, now: .now) == nil)
        #expect(HomeEarLogic.sentence(.lightsOnWhileAway(count: 3), now: .now) == "3 lights on")
    }

    @Test func homeRanksBelowAgentsAndImminentEventsButAboveMusic() {
        let now = Date.now
        let inputs = NotchActivityInputs(
            agentRequest: AgentRequestSignal(agentName: "Claude", project: nil),
            nextEvent: nil,
            playback: PlaybackSignal(title: "Song", artist: "A", appName: "Music"),
            usage: nil,
            timer: nil,
            home: .lightsOnWhileAway(count: 3)
        )
        let all: Set<NotchModule> = [.agents, .nowPlaying, .home]
        let activities = NotchActivityLogic.resolveAll(inputs, enabled: all, now: now)
        #expect(activities.count == 3)
        #expect(activities[0].module == .agents)
        #expect(activities[1] == .home(.lightsOnWhileAway(count: 3)))
        #expect(activities[2].module == .nowPlaying)
        // The section off: the house says nothing.
        #expect(!NotchActivityLogic.resolveAll(inputs, enabled: [.agents, .nowPlaying], now: now)
            .contains(.home(.lightsOnWhileAway(count: 3))))
    }

    // MARK: Doorbell

    @Test func theDoorbellPeeksOncePerRingOnlyWhenEnabled() {
        let (store, service, settings) = makeStore()
        let bell = Self.id("event.bell")
        service.add(HomeEntity(id: bell, name: "Front door", kind: .event, deviceClass: "doorbell",
                               state: HomeEntityState(raw: "unknown")))
        settings.homeDoorbellTrigger = bell.rawValue
        var posted: [NotchAlert] = []
        let source = HomeAlertSource(store: store) { posted.append($0) }
        let at = Date.now
        source.handle(.triggered(bell, at: at))
        #expect(posted.isEmpty, "disabled: no peek")
        source.update(enabled: true)
        source.handle(.triggered(bell, at: at))
        source.handle(.triggered(bell, at: at))
        source.handle(.triggered(Self.id("event.other"), at: at.addingTimeInterval(1)))
        #expect(posted.count == 1)
        #expect(posted.first?.source == .home)
        #expect(posted.first?.module == .home)
        #expect(posted.first?.symbol == "bell.fill")
        #expect(posted.first?.detail == "Front door")
        source.update(enabled: false)
    }

    @Test func aRingIsRememberedForTheCameraCard() {
        let (store, _, settings) = makeStore()
        let bell = Self.id("event.bell")
        settings.homeDoorbellTrigger = bell.rawValue
        let at = Date.now
        store.handle(.triggered(bell, at: at))
        #expect(store.ring?.at == at)
        #expect(store.isRingFresh(at: at.addingTimeInterval(60)))
        #expect(!store.isRingFresh(at: at.addingTimeInterval(HomeStore.ringFreshness + 1)))
        store.handle(.triggered(Self.id("event.other"), at: at.addingTimeInterval(5)))
        #expect(store.ring?.at == at, "only the chosen doorbell counts")
    }

    @Test func forgettingClearsTheServerAndItsChoices() {
        let (store, service, settings) = makeStore()
        settings.homeFavourites = [Self.id("light.a").rawValue]
        settings.homeDoorbellTrigger = Self.id("event.bell").rawValue
        store.forget()
        #expect(service.disconnects == [true])
        #expect(settings.homeServer == nil)
        #expect(settings.homeFavourites.isEmpty)
        #expect(settings.homeDoorbellTrigger == nil)
    }

    @Test func theDemoHomeLightsUp() async throws {
        let demo = HomeDemoService()
        let lamp = HomeDemoService.id("light.living_room_lamp")
        #expect(demo.entities[lamp]?.state.color != nil)
        try await demo.perform(.turnOff(lamp))
        #expect(demo.entities[lamp]?.state.isOn == false)
        #expect(demo.entities[lamp]?.state.color == nil)
        try await demo.perform(.turnOn(lamp))
        #expect(demo.entities[lamp]?.state.color != nil)
        let picture = try await demo.snapshot(camera: HomeDemoService.doorbellCamera)
        #expect(NSImage(data: picture) != nil)
    }

    // MARK: Review fixes

    @Test func anUntrustedServerIsNeverSavedUntilTrustWorks() async {
        let (store, service, settings) = makeStore()
        settings.homeServer = nil
        service.connectFailure = (.needsTrust(fingerprintSHA256: "ab"), HomeServiceError("Check the certificate."))
        store.normalize = { URL(string: "https://\($0)")! }
        store.setModuleEnabled(true)
        await store.connect(address: "ha.local:8123", token: "token")
        #expect(settings.homeServer == nil, "a relaunch must not resume an unpinned server")
        #expect(store.untrustedServer != nil)
        #expect(store.connectError == "Check the certificate.")

        service.trustFailure = HomeServiceError("The certificate changed.")
        await store.trustCertificate("ab")
        #expect(settings.homeServer == nil)
        #expect(store.connectError == "The certificate changed.")
        #expect(!store.isConnecting)

        service.trustFailure = nil
        await store.trustCertificate("ab")
        #expect(settings.homeServer?.pinnedCertificateSHA256 == "ab")
        #expect(store.untrustedServer == nil)
        #expect(store.connectError == nil)
    }

    @Test func trustingDoesNothingWithTheSectionOff() async {
        let (store, service, _) = makeStore()
        await store.trustCertificate("ab")
        #expect(service.trusted.isEmpty)
    }

    @Test func aCommandWithoutAPushStopsBeingPendingAfterTheFallback() async {
        let (store, service, _) = makeStore()
        store.pendingFallback = .milliseconds(40)
        let light = Self.light("light.a")
        service.add(light)
        store.activate(light)
        await settle { !service.performed.isEmpty }
        #expect(store.isPending(light.id))
        await settle { !store.isPending(light.id) }
        #expect(!store.isPending(light.id))
    }

    @Test func aFinishedDragWaitsForAPushWithItsLastValue() async {
        let (store, service, _) = makeStore()
        store.throttle = .seconds(60)
        store.pendingFallback = .seconds(60)
        let light = Self.light("light.a", on: true)
        service.add(light)
        store.drag(light, to: 0.3, final: false)
        store.drag(light, to: 0.7, final: true)
        await settle { service.performed.count >= 2 }
        // The push for the throttled 30 % arrives late: the tile keeps showing 70 %.
        var stale = light
        stale.state.brightness = 0.3
        service.entities[light.id] = stale
        store.handle(.statesChanged([light.id]))
        #expect(store.state(of: stale).brightness == 0.7)
        var settled = light
        settled.state.brightness = 0.7
        service.entities[light.id] = settled
        store.handle(.statesChanged([light.id]))
        #expect(!store.isPending(light.id))
    }

    @Test func theEarTimerOnlyRunsWhenConnectedAndAnEarCanShowIt() {
        let (store, service, settings) = makeStore()
        let door = Self.sensor("binary_sensor.front", deviceClass: "door", open: true, since: .now)
        service.add(door)
        settings.homeFavourites = [door.id.rawValue]
        settings.leftEar = .none
        settings.rightEar = .shelf
        store.setModuleEnabled(true)
        #expect(!store.hasScheduledEar, "no ear says what matters now")
        settings.leftEar = .automatic
        store.scheduleEar()
        #expect(store.hasScheduledEar)
        service.connection = .unreachable(reason: "Away.")
        store.handle(.connectionChanged)
        #expect(!store.hasScheduledEar, "disconnected: nothing to time")
    }
}
