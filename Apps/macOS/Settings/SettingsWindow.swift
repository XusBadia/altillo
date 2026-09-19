import AppKit
import SwiftUI

/// The Settings window. Altillo is an `LSUIElement` app, so it owns its window instead of using the
/// `Settings` scene: that way the menu bar item and `-openSettings YES` can both bring it up and focus it.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    /// Small and legible at a glance (PLAN §4).
    static let contentSize = CGSize(width: 540, height: 502)

    private var window: NSWindow?

    /// Opens the window, activating Altillo first so it really takes focus from a menu bar app.
    func show() {
        AltilloSettings.shared.refreshLaunchAtLogin()
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRootView()))
        window.title = "Ajustes de Altillo"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
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
