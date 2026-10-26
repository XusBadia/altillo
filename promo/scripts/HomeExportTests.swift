import AltilloHome
import AppKit
import QuartzCore
import SwiftUI
import XCTest
@testable import Altillo

/// Exports the real Home section for the Home promo (promo/CASA.md). Only runs with ALTILLO_EXPORT_DIR.
/// ALTILLO_HOME_EXPORT picks what: grid | blind | lamp | peek | settings | settings-page. Each run is a separate process because
/// `-demoHome` (read once, `DesvanHomeDemo.current`) decides which detail the openHome scenario shows.
/// Stills are 3× NSHostingView captures in an offscreen window, like ScenarioExportTests. "Live" sequences record the
/// app's own animations: frames grabbed as fast as possible with their timestamps (`<name>/times.json`).
@MainActor
final class HomeExportTests: XCTestCase {
    private var out: URL!
    private var spanish = false

    private static let esEntities = [
        "light.living_room_lamp": "Lámpara de pie", "light.living_room_ceiling": "Techo", "light.kitchen": "Cocina",
        "light.office_desk": "Escritorio", "light.bedroom": "Mesita", "light.entrance": "Pasillo",
        "switch.coffee_machine": "Cafetera", "cover.living_room_blind": "Persiana", "scene.movie": "Peli",
        "scene.all_off": "Apagar todo", "script.good_night": "Buenas noches", "sensor.living_room_temperature": "Temperatura",
        "sensor.living_room_humidity": "Humedad", "binary_sensor.front_door": "Puerta", "event.front_doorbell": "Timbre",
        "camera.front_door": "Cámara de la entrada",
    ]
    private static let esAreas = [
        "living_room": "Salón", "kitchen": "Cocina", "office": "Despacho", "bedroom": "Dormitorio", "entrance": "Entrada",
    ]

    func testExportHome() throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ALTILLO_EXPORT_DIR"] else { throw XCTSkip("sin ALTILLO_EXPORT_DIR") }
        out = URL(fileURLWithPath: dir)
        spanish = Locale.current.language.languageCode?.identifier == "es"
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let mode = env["ALTILLO_HOME_EXPORT"] ?? "grid"
        // `-demoHome` persists in the test host's defaults: clear what an earlier run left.
        UserDefaults.standard.removeObject(forKey: "demoHome")
        switch mode {
        case "grid": try exportGrid()
        case "blind": try exportBlind()
        case "lamp": try exportLamp()
        case "peek": try exportPeek()
        case "ring": try exportRing()
        case "settings": try exportSettings()
        case "settings-page": try exportSettingsPage()
        case "demo": try exportDemo(env["ALTILLO_HOME_DEMO"] ?? "area")
        default: XCTFail("modo desconocido \(mode)")
        }
    }

    // MARK: - Grid: light-up, dimming the floor lamp, the Movie scene

    private func exportGrid() throws {
        let (model, store, demo) = homeModel(.openHome)
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        // Before the opening stagger runs (it waits 120 ms): every plate still dark.
        try snap(window, "unrevealed")
        try settle(1.6)
        try snap(window, "grid")
        // Floor lamp from 70 % down to 16 %, in 2 % steps (what a 1:1 drag shows).
        let lamp = HomeDemoService.id("light.living_room_lamp")
        var step = 0
        for level in stride(from: 0.70, through: 0.159, by: -0.02) {
            demo.update(lamp) { $0.brightness = level }
            try settle(0.6)
            try snap(window, String(format: "dim-%02d", step))
            step += 1
        }
        // Movie: the scene tag pressed, then the lights change (the app's own animation, recorded).
        if let movie = store.service.entities[HomeDemoService.id("scene.movie")] {
            store.activate(movie)
        }
        try settle(0.8)
        try snap(window, "movie-final")
        // Back from the blind's controls (pulled up to 60 %), then the hallway switched on.
        demo.update(HomeDemoService.id("cover.living_room_blind")) { $0.position = 0.6; $0.raw = "open" }
        try settle(0.8)
        try snap(window, "after-blind")
        if let hallway = store.service.entities[HomeDemoService.id("light.entrance")] {
            store.activate(hallway)
            try settle(0.3)
            demo.update(hallway.id) { $0.brightness = nil }
        }
        try settle(0.8)
        try snap(window, "after-lamp")
        window.orderOut(nil)
    }

    // MARK: - Blind detail: the pull goes down

    private func exportBlind() throws {
        UserDefaults.standard.set("blind", forKey: "demoHome")
        let (model, _, demo) = homeModel(.openHome)
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        try settle(1.2)
        let blind = HomeDemoService.id("cover.living_room_blind")
        var step = 0
        for position in stride(from: 0.60, through: 0.039, by: -0.02) {
            demo.update(blind) { $0.position = position; $0.raw = "open" }
            try settle(0.5)
            try snap(window, String(format: "blind-%02d", step))
            step += 1
        }
        window.orderOut(nil)
    }

    // MARK: - Wall switch: the hallway light, off → on

    private func exportLamp() throws {
        UserDefaults.standard.set("lamp", forKey: "demoHome")
        let (model, store, demo) = homeModel(.openHome)
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        try settle(1.2)
        try snap(window, "lamp-off")
        if let hallway = store.service.entities[HomeDemoService.id("light.entrance")] {
            store.activate(hallway)
            // The hallway only switches: no brightness (the demo home gives every light 80 %).
            try settle(0.3)
            demo.update(hallway.id) { $0.brightness = nil }
        }
        try settle(0.6)
        try snap(window, "lamp-on")
        window.orderOut(nil)
    }

    // MARK: - Any `-demoHome` state as a still

    private func exportDemo(_ demo: String) throws {
        UserDefaults.standard.set(demo, forKey: "demoHome")
        let (model, _, _) = homeModel(.openHome)
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        try settle(1.6)
        try snap(window, "demo-\(demo)")
        window.orderOut(nil)
    }

    // MARK: - After a ring: the Home section with the camera card on top (it stays two minutes)

    private func exportRing() throws {
        let (model, store, demo) = homeModel(.openHome)
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        try settle(1.4)
        // The home as the video leaves it: Movie on, blind at 60 %, hallway on.
        if let movie = store.service.entities[HomeDemoService.id("scene.movie")] { store.activate(movie) }
        try settle(0.8)
        demo.update(HomeDemoService.id("cover.living_room_blind")) { $0.position = 0.6; $0.raw = "open" }
        if let hallway = store.service.entities[HomeDemoService.id("light.entrance")] {
            store.activate(hallway)
            try settle(0.3)
            demo.update(hallway.id) { $0.brightness = nil }
        }
        try settle(0.8)
        store.ringDemoDoorbell()
        try settle(1.6)
        try snap(window, "ring-grid")
        window.orderOut(nil)
    }

    // MARK: - Doorbell peek (closed notch)

    private func exportPeek() throws {
        let (model, store, _) = homeModel(.peekDoorbell)
        model.alert = .demoDoorbell
        store.ringDemoDoorbell()
        let window = try present(NotchRootView(model: model), size: NotchLayout.panelSize)
        try settle(2.0)
        try snap(window, "peekDoorbell")
        let idleModel = NotchModel.preview(.idle, hasNotch: true)
        let idle = try present(NotchRootView(model: idleModel), size: NotchLayout.panelSize)
        try settle(1.0)
        try snap(idle, "idle")
        window.orderOut(nil)
        idle.orderOut(nil)
    }

    // MARK: - Settings: found on the network, sign in with Home Assistant

    private func exportSettings() throws {
        let suite = "dev.altillo.promoexport.settings-home"
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        let settings = AltilloSettings(defaults: UserDefaults(suiteName: suite)!)
        let service = HomeDemoService(connected: false)
        let store = HomeStore(service: service, settings: settings)
        let found = HomeDiscoveredServer(name: "Casa", url: URL(string: "http://homeassistant.local:8123")!,
                                         uuid: "promo", version: "2026.10.1")
        let connect = SettingsHomeConnectModel(dependencies: .init(
            discover: { ([found], false) },
            validate: { _, _ in .homeAssistant(version: "2026.10.1", needsOnboarding: false) },
            signIn: { _, _ in throw CancellationError() },
            cancelSignIn: {}
        ))
        // Settings › Home as SettingsSectionPane lays it out, with the fake discovery above (the sidebar is left out).
        let page = SettingsPane(title: "Home", subtitle: "Home Assistant, favourites and the doorbell.") {
            VStack(alignment: .leading, spacing: 16) {
                SettingsCard { SettingsToggleRow("Show in Altillo", isOn: .constant(true)) }
                SettingsCard {
                    VStack(alignment: .leading, spacing: 0) {
                        SettingsHomeConnect(settings: settings, store: store, model: connect)
                        SettingsCardDivider()
                        SettingsHomeConnections(store: store) {}
                    }
                    .padding(.vertical, 6)
                }
            }
            .padding(.horizontal, 20)
        }
        let size = CGSize(width: SettingsWindowController.contentSize.width - 185, height: 720)
        let view = page.frame(width: size.width, height: size.height, alignment: .top).background(SettingsBackdrop())
        let window = try present(view, size: size, dark: true)
        try settle(2.0)
        try snap(window, "settings")
        window.orderOut(nil)

        // After signing in: connected.
        settings.homeServer = HomeServerConfig(serverID: HomeDemoService.serverID,
                                               url: URL(string: "http://homeassistant.local:8123")!, name: "Casa")
        service.resume(settings.homeServer!)
        let done = try present(view, size: size, dark: true)
        try settle(2.0)
        try snap(done, "settings-connected")
        done.orderOut(nil)
    }

    // MARK: - Helpers

    // MARK: - Settings › Home: the real Settings window on its Home page, with the demo home connected

    private func exportSettingsPage() throws {
        // `-homeSettingsDemo`: SettingsHomeGroup shows the demo home (read once, so set before anything draws it).
        UserDefaults.standard.set(true, forKey: "homeSettingsDemo")
        defer { UserDefaults.standard.removeObject(forKey: "homeSettingsDemo") }
        let demoStore = try XCTUnwrap(SettingsHomeGroup.demo)
        if spanish, let demo = demoStore.service as? HomeDemoService {
            demo.rename(entities: Self.esEntities, areas: Self.esAreas)
        }
        AltilloSettings.shared.setEnabled(.home, true)
        let model = NotchModel.preview(.idle, hasNotch: true)
        let navigation = SettingsNavigation()
        navigation.tab = .home
        let view = SettingsRootView(navigation: navigation, model: model)
        // The window as it opens, then the same page tall enough to show everything on it.
        let window = try present(view, size: SettingsWindowController.contentSize, dark: true)
        try settle(2.0)
        try snap(window, "settings-page")
        window.orderOut(nil)
        let tall = try present(view, size: CGSize(width: SettingsWindowController.contentSize.width, height: 1600),
                               dark: true)
        try settle(2.0)
        try snap(tall, "settings-page-full")
        tall.orderOut(nil)
        // The sidebar's "Sections" page, where Home's row links to its page.
        navigation.tab = .modules
        let sections = try present(view, size: SettingsWindowController.contentSize, dark: true)
        try settle(1.5)
        try snap(sections, "settings-sections")
        sections.orderOut(nil)
    }

    private func homeModel(_ scenario: DesignScenario) -> (NotchModel, HomeStore, HomeDemoService) {
        let model = NotchModel.preview(scenario, hasNotch: true)
        let store = model.shownHome
        let demo = store.service as! HomeDemoService
        model.settings.setEnabled(.home, true)
        // Three tags and the sensors don't fit one row; "Good night" is left out so nothing is cut.
        store.settings.homeLayout = HomeLayout(favourites: HomeDemoService.suggestedFavourites
            .filter { $0.localID != "script.good_night" })
        if spanish {
            demo.rename(entities: Self.esEntities, areas: Self.esAreas)
            store.settings.homeServer = HomeServerConfig(serverID: HomeDemoService.serverID,
                                                         url: URL(string: "http://homeassistant.local:8123")!, name: "Casa")
        }
        return (model, store, demo)
    }

    private func present(_ view: some View, size: CGSize, dark: Bool = false) throws -> NSWindow {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: size.width, height: size.height),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        if dark { window.appearance = NSAppearance(named: .darkAqua) }
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    private func settle(_ seconds: Double) throws {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func bitmap(_ window: NSWindow) throws -> NSBitmapImageRep {
        let host = try XCTUnwrap(window.contentView)
        host.layoutSubtreeIfNeeded()
        let size = host.bounds.size
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * 3), pixelsHigh: Int(size.height * 3),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func snap(_ window: NSWindow, _ name: String) throws {
        let data = try XCTUnwrap(try bitmap(window).representation(using: .png, properties: [:]))
        try data.write(to: out.appendingPathComponent("\(name).png"))
    }

    /// Grabs frames for `seconds` while the run loop keeps animating; writes them with their times.
    private func record(_ window: NSWindow, name: String, seconds: Double) throws {
        let dir = out.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let start = CACurrentMediaTime()
        var frames: [(Double, NSBitmapImageRep)] = []
        while CACurrentMediaTime() - start < seconds {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
            frames.append((CACurrentMediaTime() - start, try bitmap(window)))
        }
        var times: [Double] = []
        for (i, (t, rep)) in frames.enumerated() {
            let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try data.write(to: dir.appendingPathComponent(String(format: "%03d.png", i)))
            times.append(t)
        }
        let json = try JSONSerialization.data(withJSONObject: times)
        try json.write(to: dir.appendingPathComponent("times.json"))
    }
}
