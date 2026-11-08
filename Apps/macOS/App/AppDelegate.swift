import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var coordinator = NotchCoordinator()
    private var isLiveStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted tests construct their own stores. Starting live services here would read the
        // person's Keychain, install hooks and connect accounts before the test bundle runs.
        guard !OnboardingLaunch.isTestHost(ProcessInfo.processInfo.environment) else { return }
        isLiveStarted = true
        SettingsWindowController.model = coordinator.model
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

    nonisolated static func isUsageReturnURL(_ url: URL) -> Bool {
        url.scheme == "altillo" && url.host == "usage" && url.path.isEmpty
            && url.query == nil && url.fragment == nil && url.user == nil && url.password == nil && url.port == nil
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard isLiveStarted, urls.contains(where: Self.isUsageReturnURL) else { return }
        SettingsWindowController.shared.show(tab: .usage)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isLiveStarted { coordinator.stop() }
    }
}
