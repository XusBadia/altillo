import AppKit
import ApplicationServices
import Observation
import os

/// Owns the optional menu-bar section. AX work stays on a separate actor; hiding uses AppKit only.
@MainActor
@Observable
final class MenuBarDrawerStore: NSObject {
    static let shared = MenuBarDrawerStore()

    private(set) var enabled: Bool
    private(set) var hasAccess = false
    private(set) var isHidden = false
    private(set) var isLoading = false
    private(set) var movingEntryID: String?
    private(set) var entries: [MenuBarEntry] = []
    private(set) var problem: String?
    let iconCapture = MenuBarIconCapture()
    @ObservationIgnored private let menuPresenter = MenuBarMenuPresenter()
    var hasIconAccess: Bool { iconCapture.hasAccess }
    var isPerformingMenuBarInteraction: Bool {
        activationTask != nil || movementTask != nil || menuSessionTask != nil
    }
    /// What this macOS can do, feature by feature (see `DrawerSupport.decide`).
    let support: DrawerSupport
    /// The Drawer can be used at all: its catalog and strip work on this macOS.
    var isSupported: Bool { support.catalog }
    /// The strip above the tabs shows only for an enabled Drawer that works on this macOS. Without it the
    /// catalog is empty and every icon would be a placeholder.
    var showsStrip: Bool { enabled && support.catalog }
    var drawerEntries: [MenuBarEntry] {
        guard enabled && support.catalog else { return [] }
        return DrawerOrder.sort(entries.filter { selectedIDs.contains($0.id) }, preferredIDs: drawerOrder)
    }
    var menuBarEntries: [MenuBarEntry] {
        entries.filter { !selectedIDs.contains($0.id) }
    }

    func isInDrawer(_ entry: MenuBarEntry) -> Bool { selectedIDs.contains(entry.id) }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let accessibility = MenuBarAccessibility()
    @ObservationIgnored private var separator: NSStatusItem?
    @ObservationIgnored private var control: NSStatusItem?
    @ObservationIgnored private var movementControlPosition: Int?
    private var selectedIDs: Set<String> = []
    @ObservationIgnored private var chosenIDs: Set<String>
    private var drawerOrder: [String]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var menuSessionTask: Task<Void, Never>?
    @ObservationIgnored private var currentMenuSession: MenuBarMenuSession?
    @ObservationIgnored private var currentMenuEntryID: String?
    @ObservationIgnored private var iconTask: Task<Void, Never>?
    @ObservationIgnored private var movementTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var hideAfterScan = false
    @ObservationIgnored private var lastKnownIconAccess = false
    /// Nothing polls at rest. Events mark the catalog stale; a scan runs when something that shows
    /// the Drawer is on screen (or when the event itself can affect the hidden group).
    @ObservationIgnored private var visibleConsumers: Set<DrawerConsumer> = []
    @ObservationIgnored private var catalogIsStale = true
    @ObservationIgnored private var lastScan: ContinuousClock.Instant?
    @ObservationIgnored private var forceIconsOnNextScan = false
    @ObservationIgnored private let scheduledRefresh = MenuBarRefreshDebouncer()
    @ObservationIgnored private var accessRecheckTask: Task<Void, Never>?
    @ObservationIgnored private var applicationCache = MenuBarApplicationCache()
    @ObservationIgnored private var applicationIcons: [Int32: NSImage] = [:]
    /// A visible catalog older than this is rescanned when the Drawer appears. Scans are cheap AX reads;
    /// pixels are only recaptured when an item's glyph key changes or it is older than `glyphMaxAge`.
    static let catalogMaxAge: Duration = .seconds(30)
    static let glyphMaxAge: Duration = .seconds(60)
    /// Bounded permission reconciliation after the user asks for access (2 s × 60 = 2 min).
    static let permissionCheckInterval: Duration = .seconds(2)
    static let permissionCheckCount = 60
    /// `.debug` only: free unless someone streams it (`log stream --level debug --predicate 'category == "drawer"'`).
    static let log = Logger(subsystem: "me.badia.altillo", category: "drawer")
    /// The expanded notch sits above the native menu bar. Fold it before posting
    /// a Command-drag, otherwise the overlay receives the mouse-down instead of the item.
    @ObservationIgnored var prepareForMenuBarInteraction: (() -> Void)?

    init(defaults: UserDefaults = .standard,
         majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.defaults = defaults
        self.support = DrawerSupport.decide(majorVersion: majorVersion)
        self.enabled = defaults.bool(forKey: "drawer.enabled")
        self.chosenIDs = Set(defaults.stringArray(forKey: "drawer.chosenIDs") ?? [])
        self.drawerOrder = defaults.stringArray(forKey: "drawer.order") ?? []
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        hasAccess = AXIsProcessTrusted()
        Self.log.debug("start enabled=\(self.enabled) ax=\(self.hasAccess) capture=\(self.hasIconAccess)")
        if enabled, support.catalog, hasAccess {
            installSection()
            // Allow status-item positions to settle before discovering the user's section.
            scanTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.scanTask = nil
                if self.support.hiding, self.hasIconAccess, !self.chosenIDs.isEmpty { self.hide() }
                else { self.refresh() }
            }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for (name, delay) in [(NSWorkspace.didLaunchApplicationNotification, Duration.milliseconds(1_200)),
                              (NSWorkspace.didTerminateApplicationNotification, .milliseconds(300)),
                              (NSWorkspace.didWakeNotification, .seconds(1))] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let pid {
                        self.applicationCache.forget(pid: pid)
                        self.applicationIcons[pid] = nil
                    }
                    self.catalogIsStale = true
                    guard self.enabled else { return }
                    // Opening a command can launch another app. Refresh the catalog without
                    // revealing the user's hidden icons in response. A new app's status item
                    // usually appears shortly after launch, so wait for it to settle.
                    self.scheduleRefresh(after: delay)
                }
            })
        }
        // Status items don't change with Spaces, but full-screen Spaces can hide the bar; re-verify lazily.
        observers.append(workspace.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.catalogDidChange() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .menuBarItemsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.catalogDidChange() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A display change can move the separator. Reopen rather than hide the wrong group.
                self?.reveal()
                self?.catalogIsStale = true
                self?.scheduleRefresh(after: .milliseconds(500))
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAccess()
                self?.reconcileIconAccess()
            }
        })
        // Posted system-wide whenever the Accessibility trust list changes; TCC settles shortly after.
        distributedObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.accessibilityTrustChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheckAccessSoon() }
        })
    }

    private static let accessibilityTrustChanged = Notification.Name("com.apple.accessibility.api")

    /// Something that renders the Drawer (the open notch, the Settings pane) appeared or disappeared.
    /// Appearing is the lazy refresh point: the catalog is rescanned only if stale, and pixels are
    /// recaptured only for glyphs whose key changed or that are older than `glyphMaxAge`.
    func setVisible(_ visible: Bool, for consumer: DrawerConsumer) {
        if visible {
            visibleConsumers.insert(consumer)
        } else {
            visibleConsumers.remove(consumer)
            return
        }
        checkAccess()
        reconcileIconAccess()
        if DrawerRefreshPolicy.needsScan(isStale: catalogIsStale, hasEntries: !entries.isEmpty,
                                         lastScan: lastScan, now: .now, maxAge: Self.catalogMaxAge) {
            scheduleRefresh(after: .milliseconds(120))
        } else {
            refreshIcons()
        }
    }

    var isVisible: Bool { !visibleConsumers.isEmpty }

    private func catalogDidChange() {
        catalogIsStale = true
        Self.log.debug("catalog stale visible=\(self.isVisible)")
        // At rest this is the whole cost of an event: a flag. Scan only while someone is looking.
        guard isVisible else { return }
        scheduleRefresh(after: .milliseconds(400))
    }

    private func scheduleRefresh(after delay: Duration) {
        scheduledRefresh.schedule(after: delay) { [weak self] in self?.performScheduledRefresh(delay: delay) }
    }

    private func performScheduledRefresh(delay: Duration) {
        // Never rescan underneath a move, an activation or an open panel; the next appearance catches up.
        guard !isPerformingMenuBarInteraction, movingEntryID == nil else {
            catalogIsStale = true
            return
        }
        guard scanTask == nil else {
            scheduleRefresh(after: delay)
            return
        }
        refresh()
    }

    private func recheckAccessSoon() {
        accessRecheckTask?.cancel()
        accessRecheckTask = Task { [weak self] in
            for delay in [Duration.milliseconds(500), .seconds(2)] {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.checkAccess()
            }
            self?.accessRecheckTask = nil
        }
    }

    func stop() {
        menuPresenter.cancel()
        started = false
        scanTask?.cancel()
        scanTask = nil
        permissionTask?.cancel()
        permissionTask = nil
        activationTask?.cancel()
        activationTask = nil
        menuSessionTask?.cancel()
        menuSessionTask = nil
        iconTask?.cancel()
        iconTask = nil
        movementTask?.cancel()
        scheduledRefresh.cancel()
        accessRecheckTask?.cancel()
        accessRecheckTask = nil
        Task { [accessibility] in await accessibility.stopObserving() }
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
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObservers.removeAll()
    }

    func setEnabled(_ value: Bool) {
        guard !value || support.catalog else { return }
        hideAfterScan = false
        enabled = value
        defaults.set(value, forKey: "drawer.enabled")
        if value {
            if !hasAccess || !hasIconAccess { monitorAccess() }
            // Enabling Drawer is the explicit user gesture that authorizes requesting
            // its two required permissions; don't defer the image permission until a tile click.
            if !hasIconAccess { requestIconAccess() }
            if !hasAccess { requestAccess() }
            if hasAccess {
                installSection()
                beginArranging()
            }
        } else {
            menuPresenter.cancel()
            menuSessionTask?.cancel()
            menuSessionTask = nil
            activationTask?.cancel()
            movementTask?.cancel()
            permissionTask?.cancel()
            permissionTask = nil
            scheduledRefresh.cancel()
            Task { [accessibility] in await accessibility.stopObserving() }
            removeSection()
            selectedIDs.removeAll()
        }
    }

    func requestAccess() {
        // Called only by an explicit button, never on launch or on opening the module.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        checkAccess()
        monitorAccess(restart: true)
        if !hasAccess,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Rescans the AX catalog and captures glyphs that are missing or changed.
    /// `forceIcons` recaptures every glyph (the explicit Refresh button).
    func refresh(forceIcons: Bool = false) {
        checkAccess()
        if forceIcons { forceIconsOnNextScan = true }
        guard hasAccess, scanTask == nil, movingEntryID == nil else { return }
        scheduledRefresh.cancel()
        problem = nil
        isLoading = true
        catalogIsStale = false
        let force = forceIconsOnNextScan
        forceIconsOnNextScan = false
        let applications = runningApplications()
        Self.log.debug("scan apps=\(applications.count) forceIcons=\(force) visible=\(self.isVisible)")
        scanTask = Task { [weak self, accessibility] in
            var result = await accessibility.scan(applications: applications)
            var failedPIDs = await accessibility.failedApplicationPIDs
            guard !Task.isCancelled, let self else { return }
            Self.log.debug("scan found=\(result.count) failures=\(failedPIDs.count)")
            self.setEntries(result)
            await self.captureIcons(for: result, force: force)
            guard !Task.isCancelled else { return }
            if self.hideAfterScan {
                // Capturing can add a system privacy indicator. Verify the current
                // native group after capture, before deciding which items to hide.
                result = await accessibility.scan(applications: self.runningApplications())
                failedPIDs.formUnion(await accessibility.failedApplicationPIDs)
                guard !Task.isCancelled else { return }
                self.setEntries(result)
            }
            self.isLoading = false
            self.scanTask = nil
            self.lastScan = .now
            if self.enabled, let boundary = self.separatorFrame {
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
        guard enabled, support.hiding, hasAccess, hasIconAccess, separator != nil,
              movementTask == nil, activationTask == nil else { return }
        guard !isHidden else { return }
        // A scan begun before the user finished dragging may contain the old layout.
        scanTask?.cancel()
        scanTask = nil
        hideAfterScan = true
        refresh()
    }

    func reveal() {
        menuSessionTask?.cancel()
        menuSessionTask = nil
        hideAfterScan = false
        separator?.length = 20
        isHidden = false
        defaults.set(false, forKey: "drawer.restoreHidden")
        updateControl()
    }

    func statusIcon(for entry: MenuBarEntry) -> NSImage? {
        iconCapture.images[entry.id]
    }

    /// The image the strip shows for an item, never a placeholder: its captured glyph; once a capture pass
    /// couldn't read it, a symbol for macOS's own items or the owning app's icon; otherwise nil (skip it).
    /// Items whose capture is still pending are skipped too, so the strip doesn't flash a fallback.
    func stripIcon(for entry: MenuBarEntry) -> NSImage? {
        let source = MenuBarGlyphFallback.source(
            for: entry, hasCapture: iconCapture.images[entry.id] != nil,
            captureFailed: iconCapture.failedIDs.contains(entry.id),
            hasApplicationIcon: applicationIcon(for: entry) != nil
        )
        return image(for: entry, source: source)
    }

    /// Settings must list every item so it can be arranged, so pending captures fall back immediately
    /// and an item without any icon of its own gets the generic application icon.
    func settingsIcon(for entry: MenuBarEntry) -> NSImage {
        let source = MenuBarGlyphFallback.source(
            for: entry, hasCapture: iconCapture.images[entry.id] != nil, captureFailed: true,
            hasApplicationIcon: applicationIcon(for: entry) != nil
        )
        return image(for: entry, source: source) ?? MenuBarGlyphFallback.glyph(
            fromApplicationIcon: NSWorkspace.shared.icon(for: .application)
        )
    }

    private func image(for entry: MenuBarEntry, source: MenuBarGlyphFallback.Source) -> NSImage? {
        switch source {
        case .captured: iconCapture.images[entry.id]
        case .systemSymbol(let name):
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .applicationIcon: applicationIcon(for: entry)
        case .none: nil
        }
    }

    /// The owner's icon, drawn once per process at the strip's glyph size.
    private func applicationIcon(for entry: MenuBarEntry) -> NSImage? {
        let pid = entry.application.pid
        if let cached = applicationIcons[pid] { return cached }
        guard pid > 0, let icon = NSRunningApplication(processIdentifier: pid)?.icon else { return nil }
        let glyph = MenuBarGlyphFallback.glyph(fromApplicationIcon: icon)
        applicationIcons[pid] = glyph
        return glyph
    }

    func requestIconAccess() {
        iconCapture.requestAccess()
        monitorAccess(restart: true)
        reconcileIconAccess()
        refreshIcons()
    }

    private func reconcileIconAccess() {
        iconCapture.checkAccess()
        let granted = hasIconAccess
        guard granted != lastKnownIconAccess else { return }
        lastKnownIconAccess = granted
        if granted {
            // Capture permission may finish asynchronously after returning from Settings.
            // Refresh the AX catalog as well as its pixels, including an already-enabled Drawer.
            refresh()
            refreshIcons()
        } else {
            reveal()
        }
    }

    /// Captures glyphs for the current catalog without rescanning it. Cached, unchanged glyphs are
    /// kept; while the Drawer is visible, glyphs older than `glyphMaxAge` are renewed.
    func refreshIcons(force: Bool = false) {
        guard iconTask == nil, !entries.isEmpty else { return }
        iconTask = Task { [weak self] in
            guard let self else { return }
            await self.captureIcons(for: self.entries, force: force)
            self.iconTask = nil
        }
    }

    private func captureIcons(for entries: [MenuBarEntry], force: Bool = false) async {
        await iconCapture.refresh(entries: entries, appearance: glyphAppearance,
                                  maxAge: isVisible ? Self.glyphMaxAge : nil, force: force)
    }

    /// Menu-bar glyphs render differently in light/dark bars and at other backing scales.
    private var glyphAppearance: String {
        let button = separator?.button ?? control?.button
        let appearance = button?.effectiveAppearance ?? NSApp.effectiveAppearance
        // The status items' own display decides the pixels ScreenCaptureKit can return.
        let scale = button?.window?.screen?.backingScaleFactor ?? NSScreen.screens.first?.backingScaleFactor ?? 2
        return Self.glyphAppearanceKey(appearance: appearance.name.rawValue, scale: scale)
    }

    nonisolated static func glyphAppearanceKey(appearance: String, scale: CGFloat) -> String {
        "\(appearance)@\(scale)"
    }

    /// Avoids invalidating every observing view when a rescan found the same catalog.
    private func setEntries(_ newEntries: [MenuBarEntry]) {
        if entries != newEntries { entries = newEntries }
    }

    /// The two settings zones represent the real native order, never an optimistic selection.
    /// macOS persists status-item positions; a failed gesture leaves all icons visible.
    func move(_ entry: MenuBarEntry, toDrawer: Bool, before target: MenuBarEntry? = nil) {
        checkAccess()
        guard enabled, support.arranging, hasAccess, movementTask == nil, activationTask == nil else { return }
        scanTask?.cancel()
        scanTask = nil
        movingEntryID = entry.id
        isLoading = true
        problem = nil
        menuSessionTask?.cancel()
        menuSessionTask = nil
        reveal()
        prepareForMenuBarInteraction?()
        let targetOrderID = target?.id
        movementTask = Task { [weak self, accessibility] in
            guard let self else { return }
            var compactedChrome = false
            defer {
                if compactedChrome { self.restoreChromeAfterMovement() }
                self.movementTask = nil
                self.movingEntryID = nil
                self.isLoading = false
            }
            let openMenu = self.currentMenuSession ?? MenuBarMenuSession(pid: Self.panelOwnerPID(for: entry))
            guard await self.dismissMenu(openMenu, entryID: self.currentMenuEntryID ?? entry.id) else {
                self.problem = "Close the open menu, then try moving this icon again."
                return
            }
            self.currentMenuSession = nil
            self.currentMenuEntryID = nil
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let initial = await accessibility.scan(applications: self.runningApplications())
            guard !Task.isCancelled, self.enabled, self.hasAccess else { return }
            self.setEntries(initial)
            guard let target = initial.first(where: { $0.id == entry.id }),
                  let boundary = self.separatorFrame else {
                self.problem = "This icon is no longer available. Refresh and try again."
                return
            }
            if DrawerGeometry.isBeforeSeparator(target.frame, separator: boundary) != toDrawer {
                var result = await MenuBarItemMover.move(
                    frame: target.frame, beside: boundary, toLeft: toDrawer
                )
                if case .unavailable = result {
                    // On a crowded bar our left-hand divider can be just beyond the screen edge.
                    // Temporarily remove Altillo's recovery button and narrow the divider; this
                    // creates a real, visible native insertion point without touching other apps.
                    compactedChrome = self.compactChromeForMovement()
                    if compactedChrome {
                        try? await Task.sleep(for: .milliseconds(180))
                        // Removing a status item changes other items' coordinates too.
                        // Reusing the pre-compaction source can drag a neighbouring app.
                        let compactEntries = await accessibility.scan(applications: self.runningApplications())
                        if let compactTarget = compactEntries.first(where: { $0.id == entry.id }),
                           let compactBoundary = self.separatorFrame {
                            result = await MenuBarItemMover.move(
                                frame: compactTarget.frame, beside: compactBoundary, toLeft: toDrawer
                            )
                        }
                    }
                }
                guard !Task.isCancelled, self.enabled, self.hasAccess else { return }
                switch result {
                case .busy:
                    self.problem = "Finish the current drag, then try again."
                    return
                case .unavailable:
                    self.problem = "This icon needs room in the menu bar before it can move. Close an unused menu bar app and try again."
                    return
                case .posted: break
                }
                try? await Task.sleep(for: .milliseconds(200))
                if compactedChrome {
                    self.restoreChromeAfterMovement()
                    compactedChrome = false
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
            var refreshed = await accessibility.scan(applications: self.runningApplications())
            var failures = await accessibility.failedApplicationPIDs
            guard !Task.isCancelled, self.enabled, self.hasAccess else { return }
            self.setEntries(refreshed)
            await self.captureIcons(for: refreshed)
            guard !Task.isCancelled else { return }
            refreshed = await accessibility.scan(applications: self.runningApplications())
            failures.formUnion(await accessibility.failedApplicationPIDs)
            guard !Task.isCancelled else { return }
            self.setEntries(refreshed)
            self.lastScan = .now
            guard let boundary = self.separatorFrame else { return }
            self.selectedIDs = Set(refreshed.filter {
                DrawerGeometry.isBeforeSeparator($0.frame, separator: boundary)
            }.map(\.id))
            guard let moved = refreshed.first(where: { $0.id == entry.id }),
                  DrawerGeometry.isBeforeSeparator(moved.frame, separator: boundary) == toDrawer else {
                self.problem = "macOS couldn't move this icon. It stays in its current section."
                return
            }
            if toDrawer {
                self.chosenIDs.insert(entry.id)
                let currentOrder = self.drawerEntries.map(\.id)
                self.drawerOrder = DrawerOrder.moving(entry.id, before: targetOrderID, in: currentOrder)
            } else {
                self.chosenIDs.remove(entry.id)
                self.drawerOrder.removeAll { $0 == entry.id }
            }
            self.defaults.set(self.chosenIDs.sorted(), forKey: "drawer.chosenIDs")
            self.defaults.set(self.drawerOrder, forKey: "drawer.order")
            guard failures.isEmpty else {
                self.problem = "Some menu bar icons couldn't be read. They stay visible; try Refresh."
                return
            }
            if !self.selectedIDs.isEmpty { self.collapseSection() }
        }
    }

    /// Reorders the compact Drawer independently from the native menu-bar order.
    /// Dropping on an icon places the dragged item immediately before it; dropping
    /// on the Drawer background sends it to the end.
    func reorderDrawerEntry(_ entry: MenuBarEntry, before target: MenuBarEntry?) {
        guard selectedIDs.contains(entry.id), target?.id != entry.id else { return }
        drawerOrder = DrawerOrder.moving(entry.id, before: target?.id, in: drawerEntries.map(\.id))
        defaults.set(drawerOrder, forKey: "drawer.order")
    }

    func activate(_ entry: MenuBarEntry, anchor: MenuBarPopupAnchor) {
        checkAccess()
        guard hasAccess, let anchorRect = anchor.screenRect(),
              activationTask == nil, movementTask == nil else { return }
        menuSessionTask?.cancel()
        menuSessionTask = nil
        scanTask?.cancel()
        scanTask = nil
        isLoading = false
        problem = nil
        // Only where hiding works: elsewhere the item stays visible in the menu bar and opens from there.
        let needsHiddenIcon = support.hiding && selectedIDs.contains(entry.id)
        if needsHiddenIcon, !isHidden { hide() }
        let pendingHide = scanTask
        activationTask = Task { [weak self, accessibility] in
            guard let self else { return }
            defer { self.activationTask = nil }
            await pendingHide?.value
            guard !Task.isCancelled, self.enabled, self.hasAccess else { return }
            guard !needsHiddenIcon || self.isHidden else { return }
            if let previous = self.currentMenuSession {
                let wasPresented = await previous.isPresented() == true
                let closesSamePanel = self.currentMenuEntryID == entry.id && wasPresented
                guard await self.dismissMenu(previous, entryID: self.currentMenuEntryID) else {
                    self.problem = "Close the open menu, then try again."
                    return
                }
                self.currentMenuSession = nil
                self.currentMenuEntryID = nil
                if closesSamePanel { return }
            }
            if let snapshot = await accessibility.menuSnapshot(id: entry.id), !snapshot.nodes.isEmpty {
                guard !Task.isCancelled, self.hasAccess else { return }
                switch self.menuPresenter.present(snapshot.nodes, at: anchorRect,
                                                hasUnsupportedContent: snapshot.hasUnsupportedContent) {
                case .selected(let actionID):
                    let outcome = await accessibility.performMenuAction(id: actionID)
                    if case .unavailable = outcome {
                        self.problem = "This command is no longer available. Open the menu and try again."
                    }
                case .unavailable:
                    self.problem = "This menu couldn't be displayed. Try opening it again."
                case .cancelled: break
                }
                return
            }
            // Custom popovers have no NSMenu tree. Open the owner's panel with AX
            // while its status item remains hidden, then move the actual window.
            let panelOwner = Self.panelOwnerPID(for: entry)
            let placement = MenuBarPopoverPlacement(pid: panelOwner)
            let session = MenuBarMenuSession(pid: panelOwner)
            let outcome = await accessibility.perform(id: entry.id, showMenu: false)
            guard !Task.isCancelled else { return }
            if case .unavailable = outcome {
                self.problem = "This app doesn't expose a menu that Altillo can open."
                return
            }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let point = CGPoint(x: anchorRect.minX, y: top - anchorRect.minY + 4)
            let screens = NSScreen.screens.map {
                DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: top)
            }
            guard await placement.place(at: point, screens: screens) else {
                if !(await session.dismiss()), await session.isPresented() == true {
                    // Control Center's popovers ignore Escape; their status action
                    // toggles them closed without revealing or moving the icon.
                    _ = await accessibility.perform(id: entry.id, showMenu: false)
                }
                self.problem = "macOS didn't allow this app's panel to open beside its icon."
                return
            }
            guard !Task.isCancelled else { _ = await session.dismiss(); return }
            self.currentMenuEntryID = entry.id
            self.watchMenu(session, restoreHidden: false)
        }
    }

    private func dismissMenu(_ session: MenuBarMenuSession, entryID: String?) async -> Bool {
        if await session.dismiss() { return true }
        guard await session.isPresented() == true, let entryID else { return false }
        _ = await accessibility.perform(id: entryID, showMenu: false)
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return false }
            if await session.isPresented() == false { return true }
        }
        return false
    }

    private func watchMenu(_ session: MenuBarMenuSession, restoreHidden: Bool) {
        currentMenuSession = session
        menuSessionTask = Task { [weak self] in
            var observedMenu = false
            var closedSamples = 0
            // A missing AX answer is never grounds to hide a menu that may be open.
            // Only rehide after observing presentation and two subsequent closed samples.
            for sample in 0..<1_200 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.enabled else { return }
                let presented = await session.isPresented()
                guard !Task.isCancelled else { return }
                if presented == true { observedMenu = true; closedSamples = 0 }
                else if presented == false, observedMenu { closedSamples += 1 }
                else { closedSamples = 0 }
                if closedSamples >= 2 {
                    self.currentMenuSession = nil
                    self.currentMenuEntryID = nil
                    self.menuSessionTask = nil
                    if restoreHidden { self.hide() }
                    return
                }
                if sample >= 11 && !observedMenu {
                    self.menuSessionTask = nil
                    // A status item may perform an immediate action without any menu.
                    // Leave its native icon visible instead of claiming a menu opened.
                    return
                }
            }
            self?.menuSessionTask = nil
        }
    }

    /// macOS 27's MenuBarAgent hosts the system items, but Control Center presents their panels.
    private static func panelOwnerPID(for entry: MenuBarEntry) -> Int32 {
        let owner = MenuBarAccessibility.panelOwnerBundleID(forItemOwner: entry.application.bundleID)
        guard owner != entry.application.bundleID,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: owner).first else {
            return entry.application.pid
        }
        return app.processIdentifier
    }

    /// `NSRunningApplication` properties are LaunchServices lookups. Resolve each process once.
    private func runningApplications() -> [MenuBarApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return applicationCache.applications(
            from: NSWorkspace.shared.runningApplications, pid: \.processIdentifier
        ) { app in
            guard app.processIdentifier != ownPID else { return .ineligible }
            guard app.isFinishedLaunching else { return .pending }
            guard app.bundleURL?.pathExtension == "app", let bundleID = app.bundleIdentifier else { return .ineligible }
            // MenuBarAgent (macOS 27) is an implementation detail; people know these items as Control Center's.
            let name = bundleID == MenuBarAccessibility.menuBarAgentBundleID
                ? NSRunningApplication.runningApplications(withBundleIdentifier: MenuBarAccessibility.controlCenterBundleID)
                    .first?.localizedName ?? String(localized: "Control Center")
                : app.localizedName ?? bundleID
            return .application(MenuBarApplication(pid: app.processIdentifier, bundleID: bundleID, name: name))
        }
    }

    private func checkAccess() {
        let trusted = AXIsProcessTrusted()
        guard trusted != hasAccess else { return }
        hasAccess = trusted
        if !trusted {
            reveal()
            activationTask?.cancel()
            movementTask?.cancel()
            scanTask?.cancel()
            scanTask = nil
            isLoading = false
            entries = []
            catalogIsStale = true
            problem = "Accessibility access was turned off. Your menu bar icons are visible again."
        } else {
            problem = nil
            if enabled, support.catalog { installSection() }
            // Accessibility can be granted while Settings owns focus. Rebuild the catalog
            // on the permission transition instead of waiting for another user action.
            Task { [weak self] in self?.refresh() }
        }
    }

    /// A short, bounded reconciliation window after the user asks for a permission. Screen Recording
    /// has no change notification, and a grant can land while System Settings owns focus. It ends as
    /// soon as both permissions are present, or after `permissionCheckCount` checks. Never runs at rest.
    private func monitorAccess(restart: Bool = false) {
        if restart { permissionTask?.cancel(); permissionTask = nil }
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            for _ in 0..<Self.permissionCheckCount {
                try? await Task.sleep(for: Self.permissionCheckInterval)
                guard !Task.isCancelled, let self else { return }
                self.checkAccess()
                self.reconcileIconAccess()
                if self.hasAccess && self.hasIconAccess { break }
            }
            guard !Task.isCancelled else { return }
            self?.permissionTask = nil
        }
    }

    private var separatorFrame: CGRect? {
        guard let frame = separator?.button?.window?.frame,
              let primary = NSScreen.screens.first else { return nil }
        return DrawerGeometry.accessibilityFrame(frame, primaryScreenHeight: primary.frame.maxY)
    }

    private func installSection() {
        guard separator == nil else { return }
        if defaults.object(forKey: Self.controlPositionKey) == nil,
           let separatorPosition = defaults.object(forKey: Self.separatorPositionKey) as? NSNumber {
            defaults.set(max(0, separatorPosition.intValue - 1), forKey: Self.controlPositionKey)
        }
        installControl()
        let separator = NSStatusBar.system.statusItem(withLength: 20)
        separator.autosaveName = "Altillo.Drawer.Separator"
        separator.button?.title = "│"
        separator.button?.setAccessibilityLabel("Drawer divider")
        separator.button?.toolTip = "Manage these icons in Altillo Settings → Drawer."
        self.separator = separator
        updateControl()
    }

    /// The show/hide button only exists where hiding works.
    private func installControl() {
        guard control == nil, support.hiding else { return }
        let control = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        control.autosaveName = "Altillo.Drawer.Control"
        control.button?.target = self
        control.button?.action = #selector(toggleSection)
        self.control = control
        updateControl()
    }

    private func compactChromeForMovement() -> Bool {
        guard let separator else { return false }
        if let control {
            movementControlPosition = (defaults.object(forKey: Self.controlPositionKey) as? NSNumber)?.intValue
            NSStatusBar.system.removeStatusItem(control)
            self.control = nil
        }
        separator.length = 6
        return true
    }

    private func restoreChromeAfterMovement() {
        guard enabled, separator != nil else { return }
        separator?.length = 20
        if let separatorPosition = defaults.object(forKey: Self.separatorPositionKey) as? NSNumber {
            let immediatelyRight = max(0, separatorPosition.intValue - 1)
            defaults.set(min(movementControlPosition ?? immediatelyRight, immediatelyRight),
                         forKey: Self.controlPositionKey)
        } else if let movementControlPosition {
            defaults.set(movementControlPosition, forKey: Self.controlPositionKey)
        }
        movementControlPosition = nil
        installControl()
    }

    private static let controlPositionKey = "NSStatusItem Preferred Position Altillo.Drawer.Control"
    private static let separatorPositionKey = "NSStatusItem Preferred Position Altillo.Drawer.Separator"

    private func collapseSection() {
        guard enabled, support.hiding, hasAccess, hasIconAccess, separator != nil else { return }
        guard !selectedIDs.isEmpty else {
            reveal()
            problem = "Drag an icon into Altillo in Drawer settings."
            return
        }
        guard selectedIDs.isSubset(of: chosenIDs) else {
            reveal()
            problem = "Other icons are beside Altillo's divider. Move them to Menu bar in Drawer settings before hiding."
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

/// What the Drawer can do on this macOS, per feature, so a partial platform degrades one feature instead of
/// disabling everything. Everything else is decided at run time: the catalog reads whatever Accessibility
/// exposes, icon capture picks the path the system offers, and every move is verified by re-reading positions.
struct DrawerSupport: Equatable, Sendable {
    /// Read menu-bar items through Accessibility, show the strip and open items' menus from it.
    var catalog: Bool
    /// Rearrange items with the native Command-drag. Each move is re-read through Accessibility and only
    /// counts once confirmed, so an unverified macOS fails safely.
    var arranging: Bool
    /// Hide the chosen group by widening Altillo's divider (only verified on macOS 26).
    var hiding: Bool

    static let unavailable = DrawerSupport(catalog: false, arranging: false, hiding: false)
    static let full = DrawerSupport(catalog: true, arranging: true, hiding: true)

    /// macOS 26: everything, as verified. macOS 27: the catalog, menus and Command-drag moves work (verified on
    /// 27.0), but the divider no longer hides anything: MenuBarAgent folds items that don't fit into its own
    /// overflow menu, and a divider wider than the free space is dropped itself while the icons stay visible.
    /// Later versions keep the parts that verify themselves at run time and leave hiding off.
    static func decide(majorVersion: Int) -> DrawerSupport {
        switch majorVersion {
        case ..<26: .unavailable
        case 26: .full
        default: DrawerSupport(catalog: true, arranging: true, hiding: false)
        }
    }

    /// Some of the Drawer works, but not all of it; Settings explains what's missing.
    var isPartial: Bool { catalog && !(arranging && hiding) }
}

enum DrawerOrder {
    static func sort(_ entries: [MenuBarEntry], preferredIDs: [String]) -> [MenuBarEntry] {
        var rank: [String: Int] = [:]
        for (index, id) in preferredIDs.enumerated() where rank[id] == nil { rank[id] = index }
        return entries.enumerated().sorted { left, right in
            let leftRank = rank[left.element.id] ?? Int.max
            let rightRank = rank[right.element.id] ?? Int.max
            return leftRank == rightRank ? left.offset < right.offset : leftRank < rightRank
        }.map(\.element)
    }

    static func moving(_ id: String, before targetID: String?, in order: [String]) -> [String] {
        var result = order.filter { $0 != id }
        if let targetID, let targetIndex = result.firstIndex(of: targetID) {
            result.insert(id, at: targetIndex)
        } else {
            result.append(id)
        }
        return result
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

/// Surfaces that render Drawer icons. While any is on screen, change events trigger a (debounced) scan.
enum DrawerConsumer: Hashable, Sendable {
    case notch
    case settings
}

enum DrawerRefreshPolicy {
    /// Whether the Drawer appearing should rescan the AX catalog, or can reuse the last one.
    static func needsScan(isStale: Bool, hasEntries: Bool, lastScan: ContinuousClock.Instant?,
                          now: ContinuousClock.Instant, maxAge: Duration) -> Bool {
        guard !isStale, hasEntries, let lastScan else { return true }
        return now - lastScan >= maxAge
    }

    /// Trailing debounce with a ceiling: a burst of events postpones the refresh, but a continuous
    /// stream (an animated status item) can't postpone it beyond `maxWait` after the first request.
    static func debounceDeadline(now: ContinuousClock.Instant, delay: Duration,
                                 firstRequest: ContinuousClock.Instant?, maxWait: Duration) -> ContinuousClock.Instant {
        let trailing = now + delay
        guard let firstRequest else { return trailing }
        return min(trailing, max(now, firstRequest + maxWait))
    }
}

/// Coalesces refresh requests into one run on the main actor. It only exists while a request is
/// pending; nothing repeats.
@MainActor
final class MenuBarRefreshDebouncer {
    private let maxWait: Duration
    private var task: Task<Void, Never>?
    private var firstRequest: ContinuousClock.Instant?

    init(maxWait: Duration = .seconds(2)) {
        self.maxWait = maxWait
    }

    var isPending: Bool { task != nil }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        let now = ContinuousClock.now
        let deadline = DrawerRefreshPolicy.debounceDeadline(now: now, delay: delay,
                                                            firstRequest: firstRequest, maxWait: maxWait)
        if firstRequest == nil { firstRequest = now }
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(until: deadline, clock: .continuous)
            guard !Task.isCancelled, let self else { return }
            self.task = nil
            self.firstRequest = nil
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        firstRequest = nil
    }
}

/// Caches `NSRunningApplication` lookups by pid. A process is resolved once it finished launching;
/// dead pids are dropped on every pass.
struct MenuBarApplicationCache {
    enum Resolution {
        /// Not ready yet (still launching): ask again next time.
        case pending
        /// Never a status-item owner we read (Altillo itself, helpers without a bundle id…).
        case ineligible
        case application(MenuBarApplication)
    }

    private var byPID: [Int32: MenuBarApplication?] = [:]

    var count: Int { byPID.count }

    mutating func applications<Source>(from sources: [Source], pid: (Source) -> Int32,
                                       resolve: (Source) -> Resolution) -> [MenuBarApplication] {
        var result: [MenuBarApplication] = []
        var live: Set<Int32> = []
        for source in sources {
            let processID = pid(source)
            live.insert(processID)
            if let cached = byPID[processID] {
                if let cached { result.append(cached) }
                continue
            }
            switch resolve(source) {
            case .pending: continue
            case .ineligible: byPID[processID] = .some(nil)
            case .application(let application):
                byPID[processID] = .some(application)
                result.append(application)
            }
        }
        if byPID.keys.contains(where: { !live.contains($0) }) {
            byPID = byPID.filter { live.contains($0.key) }
        }
        return result
    }

    mutating func forget(pid: Int32) {
        byPID[pid] = nil
    }
}
