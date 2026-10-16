import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class SettingsNavigation {
    var tab: SettingsTab = SettingsTab.launchOverride ?? .behaviour
    /// Retains incoming section requests for launch arguments and links from the notch.
    var section: String? = UserDefaults.standard.string(forKey: "settingsSection")
    var sectionRequest = 0

    func open(tab: SettingsTab? = nil, section: String? = nil) {
        if let tab { self.tab = tab }
        if let section {
            self.section = section
            sectionRequest += 1
            if let destination = SettingsTab(rawValue: section), destination.module != nil {
                self.tab = destination
            }
        }
    }

    init() {
        open(section: section)
    }
}

/// The Settings window. Altillo is an `LSUIElement` app, so it owns its window instead of using the
/// `Settings` scene: that way the menu bar item and `-openSettings YES` can both bring it up and focus it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Supplied at launch without instantiating the window controller. Keeping this on the type matters for the
    /// XCTest host: it can wire the live model without constructing any AppKit settings state before test injection.
    static weak var model: NotchModel?

    /// Leaves a full-width detail beside the navigation, within the height of a small MacBook display.
    static let contentSize = CGSize(width: 780, height: 600)

    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    private var menuBarRefocusTask: Task<Void, Never>?

    /// Opens the window, activating Altillo first so it really takes focus from a menu bar app.
    func show(tab: SettingsTab? = nil, section: String? = nil) {
        menuBarRefocusTask?.cancel()
        menuBarRefocusTask = nil
        navigation.open(tab: tab, section: section)
        AltilloSettings.shared.refreshLaunchAtLogin()
        let window = window ?? makeWindow()
        self.window = window
        bringToFront(window)
    }

    /// A synthetic menu-bar drag can finish transferring focus after the move itself has returned.
    /// Restore the already-visible Settings window immediately, then check once more after AppKit
    /// has settled instead of leaving the user to activate it again by hand.
    func restoreAfterMenuBarInteraction(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        guard let window, window.isVisible else { return }

        menuBarRefocusTask?.cancel()
        bringToFront(window)
        menuBarRefocusTask = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let self, let window, window.isVisible else { return }
            if !NSApp.isActive || !window.isKeyWindow {
                self.bringToFront(window)
            }
            if !Task.isCancelled { self.menuBarRefocusTask = nil }
        }
    }

    private func bringToFront(_ window: NSWindow) {
        // Altillo is an LSUIElement app. Plain `activate()` is only advisory after a
        // menu-bar interaction; ignoring the previous app is required to reclaim focus.
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsRootView(navigation: navigation, model: Self.model))
        // The window keeps `contentSize` (title bar included); SwiftUI fills it rather than sizing it.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Altillo Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        // The sidebar replaces the toolbar; use the compact native title bar for window controls.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Desvan.Palette.wood)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(Self.contentSize)
        window.minSize = Self.contentSize
        window.center()
        window.delegate = self
        return window
    }

    /// `open Altillo.app --args -openSettings YES` (and the test harness) open the window on launch.
    static var shouldOpenOnLaunch: Bool { UserDefaults.standard.bool(forKey: "openSettings") }
}
