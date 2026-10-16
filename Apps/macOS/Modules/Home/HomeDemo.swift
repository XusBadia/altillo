import AltilloHome
import Foundation

extension HomeStore {
    /// A store on the demo home (`HomeDemoService`) for the design scenarios and previews: its own throwaway
    /// settings, the suggested favourites, a doorbell with a camera, connected and listening.
    static func demo() -> HomeStore {
        let suite = "me.badia.altillo.design-home"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AltilloSettings(defaults: defaults)
        settings.homeServer = HomeServerConfig(
            serverID: HomeDemoService.serverID, url: URL(string: "http://homeassistant.local:8123")!, name: "Casa"
        )
        settings.homeFavourites = HomeDemoService.suggestedFavourites.map(\.rawValue)
        settings.homeDoorbellTrigger = HomeDemoService.doorbell.rawValue
        settings.homeDoorbellCamera = HomeDemoService.doorbellCamera.rawValue
        let store = HomeStore(service: HomeDemoService(), settings: settings)
        store.setModuleEnabled(true)
        return store
    }

    /// The `-demoHome` design reviews: two favourites with the "picked for you" hint, or twelve (a fuller demo
    /// house). Does nothing on a real home.
    func applyDesignDemo(_ demo: DesvanHomeDemo) {
        guard let service = service as? HomeDemoService else { return }
        switch demo {
        case .few:
            settings.homeLayout = HomeLayout(favourites: [
                HomeDemoService.id("light.living_room_lamp"), HomeDemoService.id("cover.living_room_blind"),
                HomeDemoService.id("scene.movie"), HomeDemoService.id("sensor.living_room_temperature"),
            ])
            autoSuggestedCount = 2
        case .many:
            service.addMoreDemoEntities()
            let tiles = HomeDemoService.suggestedFavourites.filter { !$0.localID.hasPrefix("binary_sensor") }
            settings.homeLayout = HomeLayout(favourites: tiles + HomeDemoService.moreFavourites.prefix(4))
        case .moving:
            // Sent to 15 % and on its way down: Home Assistant reports it closing, at 62 %.
            let blind = HomeDemoService.id("cover.living_room_blind")
            service.update(blind) { state in
                state.raw = "closing"
                state.position = 0.62
            }
            if let entity = service.entities[blind] { stageCoverTrip(entity, to: 0.15) }
        case .lamp:
            // A light that only switches, off: the face of a plain LED strip.
            service.update(HomeDemoService.id("light.entrance")) { $0.lastChanged = Date.now.addingTimeInterval(-5_400) }
        case .area, .detail, .blind, .switch:
            break
        }
        refreshWatch()
    }

    /// The demo doorbell rings (design scenario "Peek: doorbell"). Does nothing on a real home.
    func ringDemoDoorbell() {
        guard let demo = service as? HomeDemoService else { return }
        let now = Date.now
        recordRing(at: now)
        demo.ringDoorbell(at: now)
    }
}
