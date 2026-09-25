import AppKit
import SwiftUI

/// The welcome window (PLAN phase 15). Like Settings it's a window of its own rather than a scene: Altillo is an
/// `LSUIElement` app, so it activates itself to bring the window forward, from launch, the menu bar or Settings.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    /// Roomy but modest: fits a 13-inch MacBook Air at "Larger Text" with the menu bar and the Dock.
    static let contentSize = CGSize(width: 640, height: 580)

    /// The notch's model, set at launch. The welcome watches it (the notch opening on the first page) and uses its
    /// stores (usage, calendar, mirror, Drawer).
    var model: NotchModel?

    private var window: NSWindow?
    private var flow: OnboardingFlow?

    var isVisible: Bool { window?.isVisible ?? false }

    /// Opens the welcome at `step` (the first page by default). If it's already open it just comes forward.
    func show(step: OnboardingStep? = nil) {
        guard let model else { return }
        if let window, window.isVisible {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let flow = OnboardingFlow(model: model, step: step ?? .hello)
        flow.close = { [weak self] in self?.window?.close() }
        self.flow = flow
        let window = makeWindow(flow: flow)
        self.window = window
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// At launch: once for everyone (people who had Altillo before the welcome existed too), never for the unit-test
    /// host or while a review drives the app. `-showWelcome YES -welcomeStep <n>` opens it on a page.
    func showAtLaunchIfNeeded(launch: OnboardingLaunch = .current()) {
        guard let model, launch.shouldShow(hasCompletedOnboarding: model.settings.hasCompletedOnboarding) else {
            return
        }
        // A beat after launch, so the notch is in place before the welcome points at it.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            self?.show(step: launch.step)
        }
    }

    private func makeWindow(flow: OnboardingFlow) -> NSWindow {
        let hosting = NSHostingController(rootView: OnboardingRootView(flow: flow))
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = String(localized: "Welcome to Altillo")
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Desvan.Palette.wood)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.setContentSize(Self.contentSize)
        // A fixed size: every page is laid out for it (the longer ones scroll rather than grow the window).
        window.contentMinSize = Self.contentSize
        window.contentMaxSize = Self.contentSize
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        flow?.windowClosed()
        flow = nil
        // A fresh window (and flow) next time: the welcome always starts over.
        window?.contentViewController = nil
        window = nil
    }
}
