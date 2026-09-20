import AppKit
import ApplicationServices
import Observation

/// Owns the optional menu-bar section. AX work stays on a separate actor; hiding uses AppKit only.
@MainActor
@Observable
final class MenuBarDrawerStore: NSObject {
    static let shared = MenuBarDrawerStore()

    private(set) var enabled: Bool
    private(set) var hasAccess = false
    private(set) var isHidden = false
    private(set) var isLoading = false
    private(set) var entries: [MenuBarEntry] = []
    private(set) var problem: String?
    /// Only the legacy status-item layout is supported. New OS versions fail open.
    let isSupported: Bool
    var drawerEntries: [MenuBarEntry] {
        enabled && isSupported ? entries.filter { selectedIDs.contains($0.id) } : entries
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let accessibility = MenuBarAccessibility()
    @ObservationIgnored private var separator: NSStatusItem?
    @ObservationIgnored private var control: NSStatusItem?
    @ObservationIgnored private var selectedIDs: Set<String> = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var hideAfterScan = false

    init(defaults: UserDefaults = .standard,
         majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.defaults = defaults
        self.isSupported = majorVersion == 26
        self.enabled = defaults.bool(forKey: "drawer.enabled")
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        hasAccess = AXIsProcessTrusted()
        if enabled, isSupported, hasAccess {
            installSection()
            // Allow status-item positions to settle before discovering the user's section.
            scanTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.scanTask = nil
                if self.defaults.bool(forKey: "drawer.restoreHidden") { self.hide() }
                else { self.refresh() }
            }
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.enabled else { return }
                    // New apps can land to the left of the divider. Discover them while visible.
                    self.reveal()
                    self.refresh()
                }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display change can move the separator. Reopen rather than hide the wrong group.
                self?.reveal()
                self?.refresh()
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.checkAccess() } })
        if enabled { monitorAccess() }
    }

    func stop() {
        started = false
        scanTask?.cancel()
        scanTask = nil
        permissionTask?.cancel()
        permissionTask = nil
        activationTask?.cancel()
        activationTask = nil
        hideAfterScan = false
        isLoading = false
        // Leave the items alive through the final run loop: destroying the expanded separator in the
        // same tick can preserve offscreen positions. Process teardown removes the items afterwards.
        separator?.length = 20
        isHidden = false
        updateControl()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func setEnabled(_ value: Bool) {
        guard !value || (isSupported && hasAccess) else { return }
        hideAfterScan = false
        enabled = value
        defaults.set(value, forKey: "drawer.enabled")
        if value {
            installSection()
            monitorAccess()
            beginArranging()
        } else {
            permissionTask?.cancel()
            permissionTask = nil
            removeSection()
            selectedIDs.removeAll()
        }
    }

    func requestAccess() {
        // Called only by an explicit button, never on launch or on opening the module.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        checkAccess()
        monitorAccess()
        if !hasAccess,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refresh() {
        checkAccess()
        guard hasAccess, scanTask == nil else { return }
        problem = nil
        isLoading = true
        let applications = runningApplications()
        scanTask = Task { [weak self, accessibility] in
            let result = await accessibility.scan(applications: applications)
            let failedPIDs = await accessibility.failedApplicationPIDs
            guard !Task.isCancelled, let self else { return }
            self.entries = result
            self.isLoading = false
            self.scanTask = nil
            if self.enabled, !self.isHidden, let boundary = self.separatorFrame {
                self.selectedIDs = Set(result.filter {
                    DrawerGeometry.isBeforeSeparator($0.frame, separator: boundary)
                }.map(\.id))
            }
            if self.hideAfterScan {
                self.hideAfterScan = false
                if failedPIDs.isEmpty, self.separatorFrame != nil {
                    self.collapseSection()
                } else {
                    self.reveal()
                    self.problem = "Some menu bar icons couldn't be read. They stay visible; try Refresh."
                }
            } else if self.isHidden, !failedPIDs.isEmpty {
                self.reveal()
                self.problem = "Some menu bar icons couldn't be read. They are visible again."
            }
        }
    }

    func beginArranging() {
        reveal()
        problem = nil
        refresh()
    }

    func hide() {
        guard enabled, isSupported, hasAccess, separator != nil else { return }
        guard !isHidden else { return }
        // A scan begun before the user finished dragging may contain the old layout.
        scanTask?.cancel()
        scanTask = nil
        hideAfterScan = true
        refresh()
    }

    func reveal() {
        hideAfterScan = false
        separator?.length = 20
        isHidden = false
        defaults.set(false, forKey: "drawer.restoreHidden")
        updateControl()
    }

    func appIcon(for entry: MenuBarEntry) -> NSImage? {
        NSRunningApplication(processIdentifier: entry.application.pid)?.icon
    }

    func activate(_ entry: MenuBarEntry, showMenu: Bool = false, dismiss: @escaping () -> Void) {
        guard activationTask == nil else { return }
        problem = nil
        // AXPress can open a menu thousands of points offscreen if its item is still displaced.
        // Restore its native anchor first and leave the group visible while the menu is in use.
        reveal()
        dismiss()
        activationTask = Task { [weak self, accessibility] in
            // Let the notch fold away before the other app presents its menu.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            let refreshed = await accessibility.scan(applications: self.runningApplications())
            guard !Task.isCancelled else { return }
            self.entries = refreshed
            if let target = refreshed.first(where: { $0.id == entry.id }),
               let primaryTop = NSScreen.screens.first?.frame.maxY {
                let screens = NSScreen.screens.map {
                    DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: primaryTop)
                }
                guard DrawerGeometry.hasVisibleAnchor(target.frame, screens: screens) else {
                    self.activationTask = nil
                    self.problem = "The menu bar is full. Quit an unused menu bar app, then try again."
                    return
                }
            }
            let outcome = await accessibility.perform(id: entry.id, showMenu: showMenu)
            guard !Task.isCancelled else { return }
            self.activationTask = nil
            if case .unavailable = outcome {
                self.problem = "This app couldn't open its menu. Its icon is back in the menu bar."
            }
        }
    }

    private func runningApplications() -> [MenuBarApplication] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  app.isFinishedLaunching, app.activationPolicy != .prohibited,
                  app.bundleURL?.pathExtension == "app",
                  let bundleID = app.bundleIdentifier else { return nil }
            return MenuBarApplication(pid: app.processIdentifier, bundleID: bundleID,
                                      name: app.localizedName ?? bundleID)
        }
    }

    private func checkAccess() {
        let trusted = AXIsProcessTrusted()
        guard trusted != hasAccess else { return }
        hasAccess = trusted
        if !trusted {
            reveal()
            scanTask?.cancel()
            scanTask = nil
            isLoading = false
            entries = []
            problem = "Accessibility access was turned off. Your menu bar icons are visible again."
        } else if enabled, isSupported {
            installSection()
        }
    }

    private func monitorAccess() {
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            var remainingPermissionChecks = 60
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.checkAccess()
                remainingPermissionChecks -= 1
                // No periodic work with the feature off. A request gets a short reconciliation window.
                if !self.enabled && (self.hasAccess || remainingPermissionChecks <= 0) {
                    self.permissionTask = nil
                    return
                }
            }
        }
    }

    private var separatorFrame: CGRect? {
        guard let frame = separator?.button?.window?.frame,
              let primary = NSScreen.screens.first else { return nil }
        return DrawerGeometry.accessibilityFrame(frame, primaryScreenHeight: primary.frame.maxY)
    }

    private func installSection() {
        guard separator == nil else { return }
        let control = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        control.autosaveName = "Altillo.Drawer.Control"
        control.button?.target = self
        control.button?.action = #selector(toggleSection)
        self.control = control
        let separator = NSStatusBar.system.statusItem(withLength: 20)
        separator.autosaveName = "Altillo.Drawer.Separator"
        separator.button?.title = "│"
        separator.button?.setAccessibilityLabel("Drawer divider")
        separator.button?.toolTip = "Hold ⌘ and drag icons to the left of this divider to put them in Drawer."
        self.separator = separator
        updateControl()
    }

    private func collapseSection() {
        guard enabled, isSupported, hasAccess, separator != nil else { return }
        guard !selectedIDs.isEmpty else {
            reveal()
            problem = "⌘-drag an icon to the left of the divider, then choose Hide icons."
            return
        }
        // Keep a recovery control on the right. If the user moved it to the hidden side, fail open.
        guard let divider = separator?.button?.window?.frame,
              let toggle = control?.button?.window?.frame, toggle.minX >= divider.maxX - 1 else {
            problem = "Move the Drawer button to the right of the divider, then try again."
            reveal()
            return
        }
        let widest = NSScreen.screens.map { $0.frame.width }.max() ?? 1440
        separator?.length = min(10_000, max(500, widest * 2))
        isHidden = true
        defaults.set(true, forKey: "drawer.restoreHidden")
        problem = nil
        updateControl()
    }

    private func removeSection() {
        reveal()
        if let separator { NSStatusBar.system.removeStatusItem(separator) }
        if let control { NSStatusBar.system.removeStatusItem(control) }
        separator = nil
        control = nil
    }

    private func updateControl() {
        control?.button?.image = NSImage(systemSymbolName: isHidden ? "chevron.left" : "chevron.right",
                                        accessibilityDescription: isHidden ? "Show Drawer icons" : "Hide Drawer icons")
        control?.button?.toolTip = isHidden ? "Show Drawer icons" : "Hide Drawer icons"
    }

    @objc private func toggleSection() {
        if isHidden { beginArranging() } else { hide() }
    }
}

/// AX uses a global top-left origin; AppKit uses a global bottom-left origin.
enum DrawerGeometry {
    static func accessibilityFrame(_ frame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    static func isBeforeSeparator(_ item: CGRect, separator: CGRect) -> Bool {
        item.width > 0 && item.height > 0 && item.maxX <= separator.minX + 1
            && item.midY >= separator.minY && item.midY <= separator.maxY
    }

    /// An offscreen native anchor can produce a mostly invisible menu even after revealing the section.
    static func hasVisibleAnchor(_ item: CGRect, screens: [CGRect]) -> Bool {
        item.width > 0 && item.height > 0 && screens.contains { $0.contains(item) }
    }
}
