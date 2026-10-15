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

    /// The demo doorbell rings (design scenario "Peek: doorbell"). Does nothing on a real home.
    func ringDemoDoorbell() {
        guard let demo = service as? HomeDemoService else { return }
        let now = Date.now
        recordRing(at: now)
        demo.ringDoorbell(at: now)
    }
}
