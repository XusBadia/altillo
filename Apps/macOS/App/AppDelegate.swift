import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = NotchCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `open -n Altillo.app --args -legacyMobileExportSelfTest <id>` only checks the iCloud export and quits
        // (release verification, docs/release.md).
        if OpenUsageMobilePublisher.runSelfTestIfRequested() { return }
        coordinator.start()
        // `open Altillo.app --args -designScenario openShelf` freezes a design-review scenario (screenshots, reviews).
        if let name = UserDefaults.standard.string(forKey: "designScenario"), let scenario = DesignScenario(rawValue: name) {
            coordinator.show(scenario)
        }
        // `open Altillo.app --args -openSettings YES` opens the Settings window on launch (design reviews).
        if SettingsWindowController.shouldOpenOnLaunch {
            SettingsWindowController.shared.show()
        }
        // Opens the live panel for integration reviews, without demo content.
        if UserDefaults.standard.bool(forKey: "openAltillo") {
            coordinator.model.actions.send(.click)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
