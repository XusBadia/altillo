import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = NotchCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.start()
        // `open Altillo.app --args -designScenario openShelf` freezes a design-review scenario (screenshots, reviews).
        if let name = UserDefaults.standard.string(forKey: "designScenario"), let scenario = DesignScenario(rawValue: name) {
            coordinator.show(scenario)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
