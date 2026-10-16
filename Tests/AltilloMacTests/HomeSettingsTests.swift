import AltilloHome
import AppKit
import Foundation
import Testing
@testable import Altillo

/// Settings › Home (docs/casa-v2.md §2, §4): the connect flow's logic and the tile grid's actions through the store.
@MainActor
struct HomeSettingsTests {
    typealias Fake = HomeTests.FakeHomeService

    private func makeStore(server: Bool = true) -> (HomeStore, Fake, AltilloSettings) {
        TestDefaultsJanitor.purgeStale()
        let name = "me.badia.altillo.tests.home-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AltilloSettings(defaults: defaults)
        if server {
            settings.homeServer = HomeServerConfig(serverID: HomeTests.server, url: URL(string: "http://ha.local:8123")!)
        }
        let service = Fake()
        let store = HomeStore(service: service, settings: settings)
        return (store, service, settings)
    }

    private func settle(until condition: () -> Bool) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private static func server(_ name: String, _ url: String, uuid: String? = nil, version: String? = nil)
        -> HomeDiscoveredServer {
        HomeDiscoveredServer(name: name, url: URL(string: url)!, uuid: uuid, version: version)
    }

    // MARK: Found servers

    @Test func foundServersAreDeduplicatedByInstanceThenAddress() {
        let rows = HomeSettingsLogic.rows([
            Self.server("Casa", "http://homeassistant.local:8123", uuid: "abc"),
            Self.server("Casa", "http://192.168.1.10:8123", uuid: "abc"),
            Self.server("Home Assistant", "http://HomeAssistant.local:8123"),
            Self.server("Taller", "http://taller.local:8123", uuid: "def"),
        ], current: nil)
        #expect(rows.map(\.name) == ["Casa", "Taller"])
    }

    @Test func theSavedServerIsListedFirst() {
        let rows = HomeSettingsLogic.rows([
            Self.server("Casa", "http://homeassistant.local:8123", uuid: "a"),
            Self.server("Taller", "http://taller.local:8123", uuid: "b"),
        ], current: URL(string: "http://taller.local:8123/")!)
        #expect(rows.map(\.name) == ["Taller", "Casa"])
    }

    @Test func rowsReadNameAndAddress() {
        let local = Self.server("", "http://homeassistant.local:8123")
        #expect(HomeSettingsLogic.title(of: local) == "Home Assistant")
        #expect(local.address == "homeassistant.local:8123")
        #expect(HomeSettingsLogic.fieldText(for: local.url) == "homeassistant.local:8123")
        #expect(HomeSettingsLogic.fieldText(for: URL(string: "https://casa.example.com")!) == "https://casa.example.com")
        #expect(HomeSettingsLogic.sameServer(URL(string: "http://ha.local:8123/")!, URL(string: "http://HA.local:8123")!))
        #expect(!HomeSettingsLogic.sameServer(URL(string: "http://ha.local:8123")!, URL(string: "https://ha.local:8123")!))
    }

    // MARK: Checking an address

    @Test func probesMapToPreciseNotices() {
        let good = HomeSettingsLogic.notice(for: .homeAssistant(version: "2026.10", needsOnboarding: false))
        #expect(good.isGood && good.action == nil && good.message.contains("2026.10"))

        let onboarding = HomeSettingsLogic.notice(for: .homeAssistant(version: nil, needsOnboarding: true))
        #expect(!onboarding.isGood)

        let notHA = HomeSettingsLogic.notice(for: .notHomeAssistant)
        let unreachable = HomeSettingsLogic.notice(for: .unreachable)
        let insecure = HomeSettingsLogic.notice(for: .insecureRemote)
        #expect(!notHA.isGood && !unreachable.isGood && !insecure.isGood)
        #expect(Set([notHA.message, unreachable.message, insecure.message, onboarding.message]).count == 4)
        #expect(insecure.message == HomeServerProbe.insecureRemote.problem)

        let denied = HomeSettingsLogic.notice(for: .localNetworkDenied)
        #expect(denied.action == .openLocalNetworkSettings)

        let trust = HomeSettingsLogic.notice(for: .needsTrust(fingerprintSHA256: "AB12"))
        #expect(trust.action == .trust(fingerprint: "AB12"))
    }

    // MARK: Connect model

    private final class Calls {
        var validated: [URL] = []
        var signedIn: [(URL, String?)] = []
    }

    private func model(found: [HomeDiscoveredServer] = [], denied: Bool = false, probe: HomeServerProbe = .unreachable,
                       signIn: Result<String, Error> = .success("long-lived"), calls: Calls) -> SettingsHomeConnectModel {
        SettingsHomeConnectModel(dependencies: .init(
            discover: { (found, denied) },
            validate: { url, _ in
                calls.validated.append(url)
                return probe
            },
            signIn: { url, pin in
                calls.signedIn.append((url, pin))
                return try signIn.get()
            },
            cancelSignIn: {},
            debounce: .milliseconds(1)
        ))
    }

    @Test func oneFoundServerPrefillsTheAddress() async {
        let (store, service, _) = makeStore(server: false)
        service.connection = .notConfigured
        let calls = Calls()
        let model = model(found: [Self.server("Casa", "http://homeassistant.local:8123", uuid: "a", version: "2026.10")],
                          calls: calls)
        model.appear(store: store)
        await settle { model.hasSearched }
        #expect(model.servers.count == 1)
        #expect(model.address == "homeassistant.local:8123")
        #expect(model.currentCheck?.isGood == true)
    }

    @Test func aDeniedSearchSaysSo() async {
        let (store, service, _) = makeStore(server: false)
        service.connection = .notConfigured
        let model = model(denied: true, calls: Calls())
        model.appear(store: store)
        await settle { model.hasSearched }
        #expect(model.localNetworkDenied)
        #expect(model.address.isEmpty)
    }

    @Test func connectedStoresDontSearch() async {
        let (store, _, _) = makeStore()
        let model = model(found: [Self.server("Casa", "http://homeassistant.local:8123")], calls: Calls())
        model.appear(store: store)
        #expect(model.phase == .idle && !model.hasSearched)
        #expect(model.address == "ha.local:8123")
    }

    @Test func aTypedAddressIsCheckedBeforeTheBrowserOpens() async {
        let (store, _, _) = makeStore(server: false)
        let calls = Calls()
        let model = model(probe: .notHomeAssistant, calls: calls)
        model.address = "nas.local:5000"
        model.signIn(store: store)
        await settle { model.phase == .idle && !calls.validated.isEmpty }
        #expect(calls.validated.first?.host() == "nas.local")
        #expect(calls.signedIn.isEmpty)
        #expect(model.currentCheck?.message == HomeServerProbe.notHomeAssistant.problem)
    }

    @Test func signingInConnectsWithTheNewToken() async {
        let (store, service, settings) = makeStore(server: false)
        service.connection = .notConfigured
        let calls = Calls()
        let server = Self.server("Casa", "http://homeassistant.local:8123", uuid: "a")
        let model = model(found: [server], calls: calls)
        model.appear(store: store)
        await settle { model.hasSearched }
        model.signIn(to: server, store: store)
        await settle { settings.homeServer != nil && model.phase == .idle }
        #expect(calls.validated.isEmpty, "a found server needs no check")
        #expect(calls.signedIn.map(\.0) == [server.url])
        #expect(settings.homeServer?.url == server.url)
        #expect(store.isConnected)
        #expect(model.error == nil)
    }

    @Test func aFailedSignInShowsWhy() async {
        let (store, _, _) = makeStore(server: false)
        let model = model(probe: .homeAssistant(version: nil, needsOnboarding: false),
                          signIn: .failure(HomeServiceError("You didn't allow Altillo.")), calls: Calls())
        model.address = "ha.example.com"
        model.signIn(store: store)
        await settle { model.error != nil }
        #expect(model.error == "You didn't allow Altillo.")
        #expect(model.phase == .idle)
    }

    // MARK: Tiles

    private func storeWithTiles() -> (HomeStore, [HomeEntityID]) {
        let (store, service, _) = makeStore()
        let ids = ["light.a", "light.b", "switch.c"].map(HomeTests.id)
        service.add(HomeTests.entity("light.a", .light))
        service.add(HomeTests.entity("light.b", .light))
        service.add(HomeTests.entity("switch.c", .switchable))
        for id in ids { store.addFavourite(id) }
        return (store, ids)
    }

    @Test func theGridShowsHiddenAndMissingTilesInOrder() {
        let (store, ids) = storeWithTiles()
        store.setHidden(ids[1], true)
        store.addFavourite(HomeTests.id("light.gone"))
        let tiles = store.settingsTiles
        #expect(tiles.map(\.id) == ids + [HomeTests.id("light.gone")])
        #expect(tiles[1].isHidden)
        #expect(tiles[3].entity == nil)
        #expect(store.tiles(onPage: nil).map(\.id) == [ids[0], ids[2]], "the notch leaves hidden and missing out")
    }

    @Test func draggingATileOntoAnotherMovesIt() {
        let (store, ids) = storeWithTiles()
        store.dropTile(ids[2], onto: ids[0])
        #expect(store.settingsTiles.map(\.id) == [ids[2], ids[0], ids[1]])
        store.dropTile(ids[2], onto: ids[2])
        #expect(store.settingsTiles.map(\.id) == [ids[2], ids[0], ids[1]])
    }

    @Test func theInspectorChangesTheTile() {
        let (store, ids) = storeWithTiles()
        store.rename(ids[0], to: "Sofa")
        store.setSymbol(ids[0], "lamp.floor.fill")
        store.setSize(ids[0], .wide)
        store.setHidden(ids[0], true)
        var tile = store.settingsTiles[0]
        #expect(tile.name == "Sofa" && tile.tile.symbol == "lamp.floor.fill" && tile.size == .wide && tile.isHidden)

        store.rename(ids[0], to: nil)
        store.setSymbol(ids[0], nil)
        tile = store.settingsTiles[0]
        #expect(tile.name == "light.a" && tile.tile.symbol == nil)

        store.removeFavourite(ids[0])
        #expect(store.settingsTiles.map(\.id) == [ids[1], ids[2]])
    }

    @Test func theCatalogueGroupsByRoomAndSearches() {
        let (store, service, _) = makeStore()
        service.add(HomeTests.entity("light.sofa", .light, area: "living", name: "Sofa"))
        service.add(HomeTests.entity("light.porch", .light, area: "hall", name: "Porch"))
        service.add(HomeTests.entity("switch.loose", .switchable, area: nil, name: "Loose"))
        service.add(HomeTests.entity("switch.helper", .switchable, area: "living", name: "Helper", technical: true))
        service.add(HomeTests.entity("lock.door", .lock, area: "hall", name: "Door"))
        let groups = store.catalogue(matching: "")
        #expect(groups.map(\.id) == ["living", "hall", ""])
        #expect(groups[0].entities.map(\.name) == ["Sofa"])
        #expect(groups[1].entities.map(\.name) == ["Porch"], "no locks")
        #expect(store.catalogue(matching: "helper").flatMap(\.entities).map(\.name) == ["Helper"])
    }

    @Test func everyCuratedIconExists() {
        for kind in HomeEntityKind.allCases {
            let symbols = HomeStore.curatedSymbols(for: kind)
            #expect(!symbols.isEmpty && symbols.count <= 16)
            #expect(Set(symbols).count == symbols.count)
            for symbol in symbols {
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
            }
        }
    }

    @Test func guidesPointAtHomeAssistantsDocs() {
        typealias Guide = SettingsHomeConnections.Guide
        let guides = [Guide.hue, Guide.googleHome, Guide.alexa, Guide.matter, Guide.tuya]
        #expect(guides.allSatisfy { $0.host() == "www.home-assistant.io" && $0.path().hasPrefix("/integrations/") })
    }
}
