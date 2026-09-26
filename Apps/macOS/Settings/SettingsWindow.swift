import AppKit
import SwiftUI
import Observation

@MainActor @Observable
final class SettingsNavigation {
    var tab: SettingsTab = SettingsTab.launchOverride ?? .modules
}

/// The Settings window. Altillo is an `LSUIElement` app, so it owns its window instead of using the
/// `Settings` scene: that way the menu bar item and `-openSettings YES` can both bring it up and focus it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Supplied at launch without instantiating the window controller. Keeping this on the type matters for the
    /// XCTest host: it can wire the live model without constructing any AppKit settings state before test injection.
    static weak var model: NotchModel?

    /// Small and legible at a glance (PLAN §4). The height is the whole window, title bar included (the tab bar
    /// lives in it), and fits the tallest pane that doesn't scroll (Size) with room to spare. It stays well under
    /// the ~630 pt a 13-inch MacBook Air leaves below the menu bar at its "Larger Text" resolution.
    static let contentSize = CGSize(width: 600, height: 580)

    private var window: NSWindow?
    private let navigation = SettingsNavigation()
    /// Opens the window, activating Altillo first so it really takes focus from a menu bar app.
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        AltilloSettings.shared.refreshLaunchAtLogin()
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsRootView(navigation: navigation, model: Self.model))
        // The window keeps `contentSize` (title bar included); SwiftUI fills it rather than sizing it.
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Altillo Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // The section tabs are the title bar: an empty unified toolbar gives it a toolbar's height (so the traffic
        // lights sit centred beside the tabs) and the title stays for the Window menu, Mission Control and VoiceOver
        // without being drawn under the tabs.
        let toolbar = NSToolbar(identifier: "AltilloSettings")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Desvan.Palette.wood)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(Self.contentSize)
        window.center()
        window.delegate = self
        return window
    }

    /// `open Altillo.app --args -openSettings YES` (and the test harness) open the window on launch.
    static var shouldOpenOnLaunch: Bool { UserDefaults.standard.bool(forKey: "openSettings") }
}
