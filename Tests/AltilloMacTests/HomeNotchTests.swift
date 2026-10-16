import AltilloHome
import AppKit
import Foundation
import Testing
@testable import Altillo

/// The notch's Home section (docs/casa-v2.md §1, §3): what a tile says, the icons it offers, the dimmer dial's
/// geometry and the store calls the detail face makes.
@MainActor
struct HomeNotchTests {
    private func entity(_ local: String, kind: HomeEntityKind, caps: HomeCapabilities = [.toggle],
                        state: HomeEntityState, deviceClass: String? = nil) -> HomeEntity {
        HomeEntity(id: HomeEntityID(provider: "ha", serverID: "S", localID: local), name: local, kind: kind,
                   deviceClass: deviceClass, areaID: "living", capabilities: caps, state: state)
    }

    // MARK: The tile's second line

    @Test func tileLineSaysAValueOrTheRoomNeverOff() {
        let dimmable: HomeCapabilities = [.toggle, .brightness]
        let on = entity("light.a", kind: .light, caps: dimmable, state: HomeEntityState(raw: "on", isOn: true, brightness: 0.7))
        #expect(HomeText.tileLine(for: on, state: on.state, room: "Salón") == HomeText.percent(0.7))
        let off = entity("light.b", kind: .light, caps: dimmable, state: HomeEntityState(raw: "off", isOn: false))
        #expect(HomeText.tileLine(for: off, state: off.state, room: "Salón") == "Salón")
        #expect(HomeText.tileLine(for: off, state: off.state, room: nil) == nil)
        // A light that can't dim has no value to say.
        let plain = entity("light.c", kind: .light, state: HomeEntityState(raw: "on", isOn: true, brightness: 1))
        #expect(HomeText.tileLine(for: plain, state: plain.state, room: "Hall") == "Hall")
        let plug = entity("switch.d", kind: .switchable, state: HomeEntityState(raw: "off", isOn: false), deviceClass: "outlet")
        #expect(HomeText.tileLine(for: plug, state: plug.state, room: "Cocina") == "Cocina")
        let offWord = HomeText.stateLine(for: off, state: off.state)
        for item in [off, plug] { #expect(HomeText.tileLine(for: item, state: item.state, room: "X") != offWord) }
    }

    @Test func tileLineForBlinds() {
        let caps: HomeCapabilities = [.openClose, .position]
        let half = entity("cover.a", kind: .cover, caps: caps, state: HomeEntityState(raw: "open", position: 0.65))
        #expect(HomeText.tileLine(for: half, state: half.state, room: "Salón")
            == HomeText.stateLine(for: half, state: half.state))
        #expect(HomeText.tileLine(for: half, state: half.state, room: "Salón")?.contains(HomeText.percent(0.65)) == true)
        let closed = entity("cover.b", kind: .cover, caps: caps, state: HomeEntityState(raw: "closed", position: 0))
        #expect(HomeText.tileLine(for: closed, state: closed.state, room: "Salón") == "Salón")
        let moving = entity("cover.c", kind: .cover, caps: caps, state: HomeEntityState(raw: "opening", position: 0.3))
        #expect(HomeText.tileLine(for: moving, state: moving.state, room: "Salón")
            == String(localized: "home.state.opening", defaultValue: "Opening…"))
        let gone = entity("cover.d", kind: .cover, caps: caps, state: HomeEntityState(raw: "unavailable", isAvailable: false))
        #expect(HomeText.tileLine(for: gone, state: gone.state, room: "Salón") == String(localized: "Unavailable"))
    }

    // MARK: Icons

    @Test func curatedIconsExistAndAreAboutSixteenPerKind() {
        for kind in HomeEntityKind.allCases {
            let symbols = HomeText.curatedSymbols(for: kind)
            #expect(symbols.count == 16, "\(kind)")
            #expect(Set(symbols).count == symbols.count, "\(kind) repeats an icon")
            for symbol in symbols {
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol) isn't an SF Symbol")
            }
        }
    }

    @Test func filledSymbolsExist() {
        let kinds: [(HomeEntityKind, String?)] = [(.switchable, "outlet"), (.switchable, nil), (.fan, nil), (.scene, nil), (.script, nil)]
        for (kind, deviceClass) in kinds {
            for on in [true, false] {
                let item = entity("x.y", kind: kind, state: HomeEntityState(raw: on ? "on" : "off", isOn: on), deviceClass: deviceClass)
                let symbol = HomeText.filledSymbol(for: item, state: item.state)
                #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
            }
        }
    }

    // MARK: Dimmer dial

    @Test func dialMapsAnglesOntoThreeQuartersOfATurn() {
        let center = CGPoint(x: 100, y: 100)
        func point(_ degrees: Double) -> CGPoint {
            CGPoint(x: center.x + 50 * cos(degrees * .pi / 180), y: center.y + 50 * sin(degrees * .pi / 180))
        }
        // 7:30 is 0 %, 12 o'clock 50 %, 4:30 100 %.
        #expect(DesvanHomeDimmerDial.level(at: point(135), around: center, previous: 0.1) == 0)
        #expect(DesvanHomeDimmerDial.level(at: point(270), around: center, previous: 0.5) == 0.5)
        #expect(DesvanHomeDimmerDial.level(at: point(45), around: center, previous: 0.9) == 1)
        // In the gap at the bottom it holds the nearer end.
        #expect(DesvanHomeDimmerDial.level(at: point(80), around: center, previous: 0.95) == 1)
        #expect(DesvanHomeDimmerDial.level(at: point(100), around: center, previous: 0.05) == 0)
        // Never a jump from one end to the other.
        #expect(DesvanHomeDimmerDial.level(at: point(180), around: center, previous: 0.97) == 1)
        #expect(DesvanHomeDimmerDial.level(at: point(0), around: center, previous: 0.02) == 0)
    }

    @Test func levelsOfTiles() {
        let light = entity("light.a", kind: .light, caps: [.toggle, .brightness],
                           state: HomeEntityState(raw: "on", isOn: true, brightness: 0.4))
        #expect(DesvanHomeTile.level(of: light, state: light.state) == 0.4)
        #expect(DesvanHomeTile.hasLevel(light))
        let blind = entity("cover.a", kind: .cover, caps: [.position], state: HomeEntityState(raw: "open", position: 0.25))
        #expect(DesvanHomeTile.level(of: blind, state: blind.state) == 0.25)
        let plug = entity("switch.a", kind: .switchable, state: HomeEntityState(raw: "on", isOn: true))
        #expect(!DesvanHomeTile.hasLevel(plug))
        var gone = light
        gone.state = HomeEntityState(raw: "unavailable", isAvailable: false)
        #expect(!DesvanHomeTile.hasLevel(gone))
        #expect(DesvanHomeDetail.hasControls(light) && DesvanHomeDetail.hasControls(blind) && DesvanHomeDetail.hasControls(plug))
        #expect(!DesvanHomeDetail.hasControls(entity("scene.a", kind: .scene, state: HomeEntityState(raw: "scening"))))
    }

    // MARK: Store

    @Test func browsableAreasAreRoomsWithSomethingToSwitch() {
        let store = HomeStore.demo()
        let areas = store.browsableAreas.map(\.id)
        #expect(areas == ["living_room", "kitchen", "office", "bedroom", "entrance"])
        #expect(store.tiles(inArea: "living_room").map(\.entity.id.localID).prefix(3)
            == ["light.living_room_lamp", "light.living_room_ceiling", "cover.living_room_blind"])
    }

    @Test func colourAndWarmthReachTheService() async throws {
        let store = HomeStore.demo()
        let demo = try #require(store.service as? HomeDemoService)
        let lamp = try #require(store.service.entities[HomeDemoService.id("light.living_room_lamp")])
        let red = HomeRGB(red: 1, green: 0.32, blue: 0.22)
        store.setColor(lamp, red)
        store.setColorTemperature(lamp, kelvin: 3000)
        // A light that can only dim gets no colour.
        let kitchen = try #require(store.service.entities[HomeDemoService.id("light.kitchen")])
        store.setColor(kitchen, red)
        for _ in 0..<50 where demo.performed.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(demo.performed.contains(.setColor(lamp.id, red)))
        #expect(demo.performed.contains(.setColorTemperature(lamp.id, kelvin: 3000)))
        #expect(!demo.performed.contains(.setColor(kitchen.id, red)))
        #expect(demo.entities[lamp.id]?.state.isOn == true)
    }

    @Test func homeAssistantLinkSearchesTheEntity() throws {
        let store = HomeStore.demo()
        let url = try #require(store.homeAssistantURL(for: HomeDemoService.id("light.kitchen")))
        #expect(url.absoluteString == "http://homeassistant.local:8123/config/entities?search=light.kitchen")
        #expect(store.homeAssistantURL(for: HomeEntityID(provider: "ha", serverID: "other", localID: "light.x")) == nil)
    }

    @Test func designDemosFillTheGrid() {
        let few = HomeStore.demo()
        few.applyDesignDemo(.few)
        #expect(few.tiles(onPage: nil).filter { !$0.entity.kind.isAction && $0.entity.kind != .sensor }.count == 2)
        #expect(few.didAutoSuggest)
        let many = HomeStore.demo()
        many.applyDesignDemo(.many)
        let grid = many.tiles(onPage: nil).filter {
            !$0.entity.kind.isAction && $0.entity.kind != .sensor && $0.entity.kind != .binarySensor
        }
        #expect(grid.count == 12)
        let metrics = HomeGridMetrics(sizes: grid.map(\.size), availableHeight: 166, spacing: 8)
        #expect(metrics.columns == 4 && metrics.rows == 3 && metrics.scrolls)
    }
}
