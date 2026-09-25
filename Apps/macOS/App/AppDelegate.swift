import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = NotchCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Installed agent hooks call a stable path in Application Support; point it at this copy of the app.
        AgentHookInstaller.refreshStableHookPath()
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
        // The welcome (phase 15): once for everyone, never in the test host or while a review drives the app.
        // `-showWelcome YES -welcomeStep <n>` opens it on a page for reviews.
        OnboardingWindowController.shared.model = coordinator.model
        OnboardingWindowController.shared.showAtLaunchIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
