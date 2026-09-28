import AppKit
import ApplicationServices
import Observation
import os

/// Owns the Drawer: which apps keep their menu-bar icons in Altillo, the Accessibility catalog the strip and
/// Settings draw, and opening an icon's menu from the notch.
///
/// Hiding is logical. On macOS 27 a system allow-list (`MenuBarConcealing`) shows every app except the
/// Drawer's; nothing is dragged, no divider sits in the menu bar and nothing needs Screen Recording. On
/// macOS 26 the Drawer lists and opens icons without hiding them.
@MainActor
@Observable
final class MenuBarDrawerStore: NSObject {
    static let shared = MenuBarDrawerStore()

    private(set) var enabled: Bool
    private(set) var hidesDrawerIcons: Bool
    /// Icons of apps Altillo has never seen go straight to the Drawer instead of the menu bar.
    private(set) var newIconsGoToDrawer: Bool
    private(set) var hasAccess = false
    private(set) var isLoading = false
    /// The Drawer's apps are hidden from the menu bar right now.
    private(set) var isConcealing = false
    /// The user asked to see the hidden icons in the menu bar for a while.
    private(set) var isPeeking = false
    private(set) var entries: [MenuBarEntry] = []
    private(set) var problem: String?
    private(set) var membership: DrawerMembership
    private var drawerOrder: [String]

    /// What this macOS can do (see `DrawerSupport.decide`).
    let support: DrawerSupport
    var isSupported: Bool { support.catalog }
    /// The strip above the tabs shows only for an enabled Drawer that works on this macOS.
    var showsStrip: Bool { enabled && support.catalog }
    var drawerEntries: [MenuBarEntry] {
        guard enabled && support.catalog else { return [] }
        return DrawerOrder.sort(entries.filter(isInDrawer), preferredIDs: drawerOrder)
    }
    var menuBarEntries: [MenuBarEntry] { entries.filter { !isInDrawer($0) } }
    var isPerformingMenuBarInteraction: Bool { activationTask != nil || menuSessionTask != nil }

    func isInDrawer(_ entry: MenuBarEntry) -> Bool { membership.contains(entry.application.bundleID) }

    /// macOS keeps its own items (clock, Wi‑Fi, Control Center…) in the menu bar.
    func canMove(_ entry: MenuBarEntry) -> Bool {
        !DrawerMembership.isSystemHosted(entry.application.bundleID) && entry.application.bundleID != ownBundleID
    }

    /// The other icons of the same app. They join and leave the Drawer together.
    func companions(of entry: MenuBarEntry) -> [MenuBarEntry] {
        entries.filter { $0.application.bundleID == entry.application.bundleID && $0.id != entry.id }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let concealer: MenuBarConcealing
    /// Real menu-bar glyphs, with the optional Screen Recording permission.
    let glyphs: MenuBarGlyphCapture
    /// Drawer apps shown in the menu bar for a moment so one of their icons can be clicked.
    @ObservationIgnored private var temporarilyShown: Set<String> = []
    /// The app shown for the menu that's open now.
    @ObservationIgnored private var revealedForMenu: String?
    @ObservationIgnored private let accessibility = MenuBarAccessibility()
    @ObservationIgnored private let menuPresenter = MenuBarMenuPresenter()
    @ObservationIgnored private let ownBundleID = Bundle.main.bundleIdentifier ?? "me.badia.altillo"
    /// Bundles that have had an icon; anything else is new to the `newIconsGoToDrawer` policy.
    @ObservationIgnored private var knownBundleIDs: Set<String>
    /// Apps shown in the menu bar during this assertion. The list only grows while it lives: macOS ignores a
    /// shorter list, and replacing the assertion flashes every icon, so a quitting app simply stays listed.
    @ObservationIgnored private var shownThisSession: Set<String> = []
    @ObservationIgnored private var concealTask: Task<Void, Never>?
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private var menuSessionTask: Task<Void, Never>?
    @ObservationIgnored private var currentMenuSession: MenuBarMenuSession?
    @ObservationIgnored private var currentMenuEntryID: String?
    @ObservationIgnored private var accessRecheckTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var started = false
    /// Nothing polls at rest. Events mark the catalog stale; a scan runs when something that shows the Drawer
    /// is on screen.
    @ObservationIgnored private var visibleConsumers: Set<DrawerConsumer> = []
    @ObservationIgnored private var catalogIsStale = true
    @ObservationIgnored private var lastScan: ContinuousClock.Instant?
    @ObservationIgnored private let scheduledRefresh = MenuBarRefreshDebouncer()
    @ObservationIgnored private var applicationCache = MenuBarApplicationCache()
    @ObservationIgnored private var applicationIcons: [Int32: NSImage] = [:]
    @ObservationIgnored private lazy var genericApplicationIcon = NSWorkspace.shared.icon(for: .applicationBundle)
    /// Reads the bundle ids of every running app. Injected by tests.
    @ObservationIgnored private let runningBundleIDs: @MainActor () -> Set<String>

    static let catalogMaxAge: Duration = .seconds(30)
    /// Bounded permission reconciliation after the user asks for access (2 s × 60 = 2 min).
    static let permissionCheckInterval: Duration = .seconds(2)
    static let permissionCheckCount = 60
    /// `.debug` only: free unless someone streams it (`log stream --level debug --predicate 'category == "drawer"'`).
    static let log = Logger(subsystem: "me.badia.altillo", category: "drawer")
    /// The expanded notch sits above the menu bar. Fold it before opening an item's panel.
    @ObservationIgnored var prepareForMenuBarInteraction: (() -> Void)?

    private enum Key {
        static let enabled = "drawer.enabled"
        static let hidesIcons = "drawer.hidesIcons"
        static let newIconsGoToDrawer = "drawer.newIconsGoToDrawer"
        static let bundleIDs = "drawer.bundleIDs"
        static let knownBundleIDs = "drawer.knownBundleIDs"
        static let order = "drawer.order"
        static let legacyChosenIDs = "drawer.chosenIDs"
    }

    init(defaults: UserDefaults = .standard,
         majorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
         concealer: MenuBarConcealing? = nil,
         glyphs: MenuBarGlyphCapture? = nil,
         runningBundleIDs: (@MainActor () -> Set<String>)? = nil) {
        self.defaults = defaults
        let concealer = concealer ?? (majorVersion >= 27 ? MenuBarConcealer() : UnavailableMenuBarConcealer())
        self.concealer = concealer
        self.glyphs = glyphs ?? MenuBarGlyphCapture()
        self.support = DrawerSupport.decide(majorVersion: majorVersion, canHide: concealer.isAvailable)
        self.runningBundleIDs = runningBundleIDs ?? {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        }
        self.enabled = defaults.bool(forKey: Key.enabled)
        self.hidesDrawerIcons = (defaults.object(forKey: Key.hidesIcons) as? Bool) ?? true
        self.newIconsGoToDrawer = defaults.bool(forKey: Key.newIconsGoToDrawer)
        self.knownBundleIDs = Set(defaults.stringArray(forKey: Key.knownBundleIDs) ?? [])
        self.drawerOrder = defaults.stringArray(forKey: Key.order) ?? []
        if let saved = defaults.stringArray(forKey: Key.bundleIDs) {
            self.membership = DrawerMembership(bundleIDs: saved)
        } else {
            self.membership = .migrating(chosenIDs: defaults.stringArray(forKey: Key.legacyChosenIDs) ?? [])
        }
        super.init()
        Self.forgetLegacyChrome(in: defaults)
        defaults.set(membership.bundleIDs, forKey: Key.bundleIDs)
    }

    /// The divider, arrow and spacers of the previous Drawer are gone; so are their saved positions.
    private static func forgetLegacyChrome(in defaults: UserDefaults) {
        for key in defaults.dictionaryRepresentation().keys where
            key.contains("Altillo.Drawer.") || key.hasPrefix("drawer.v27.") {
            defaults.removeObject(forKey: key)
        }
        for key in [Key.legacyChosenIDs, "drawer.restoreHidden"] { defaults.removeObject(forKey: key) }
    }

    // MARK: - Lifecycle

    func start() {
        guard !started else { return }
        started = true
        hasAccess = AXIsProcessTrusted()
        Self.log.debug("start enabled=\(self.enabled) ax=\(self.hasAccess) hiding=\(self.support.hiding)")
        if enabled, support.catalog, hasAccess {
            // Every icon is on screen until Altillo hides them: read the catalog (and glyphs) first.
            refresh(thenConceal: true)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if let pid { self.forget(pid: pid) }
                // With the assertion held, a new app stays hidden until it's listed: add it right away.
                self.applyConcealment()
                self.catalogIsStale = true
                guard self.enabled else { return }
                // A new app's status item usually appears shortly after launch.
                self.scheduleRefresh(after: .milliseconds(1_200))
            }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self else { return }
                if let pid { self.forget(pid: pid) }
                self.catalogDidChange()
            }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.catalogDidChange() }
            })
        }
        for name in [Notification.Name.menuBarItemsDidChange, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.catalogDidChange() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkAccess()
                self?.glyphs.checkAccess()
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

    func stop() {
        menuPresenter.cancel()
        started = false
        for task in [scanTask, permissionTask, activationTask, menuSessionTask, accessRecheckTask, concealTask] {
            task?.cancel()
        }
        scanTask = nil
        permissionTask = nil
        activationTask = nil
        menuSessionTask = nil
        accessRecheckTask = nil
        concealTask = nil
        scheduledRefresh.cancel()
        Task { [accessibility] in await accessibility.stopObserving() }
        isLoading = false
        releaseConcealment()
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

    // MARK: - Settings

    func setEnabled(_ value: Bool) {
        guard !value || support.catalog else { return }
        enabled = value
        defaults.set(value, forKey: Key.enabled)
        problem = nil
        if value {
            // Enabling the Drawer is the explicit gesture that authorizes asking for Accessibility.
            if !hasAccess { requestAccess() }
            refresh()
            applyConcealment()
        } else {
            menuPresenter.cancel()
            menuSessionTask?.cancel()
            menuSessionTask = nil
            activationTask?.cancel()
            permissionTask?.cancel()
            permissionTask = nil
            scheduledRefresh.cancel()
            Task { [accessibility] in await accessibility.stopObserving() }
            isPeeking = false
            releaseConcealment()
        }
    }

    func setHidesDrawerIcons(_ value: Bool) {
        guard !value || support.hiding else { return }
        hidesDrawerIcons = value
        defaults.set(value, forKey: Key.hidesIcons)
        problem = nil
        if !value { isPeeking = false }
        applyConcealment()
    }

    func setNewIconsGoToDrawer(_ value: Bool) {
        // Whatever already has an icon isn't new: only apps that appear from now on follow the policy.
        rememberBundles(of: entries)
        newIconsGoToDrawer = value
        defaults.set(value, forKey: Key.newIconsGoToDrawer)
        applyConcealment()
    }

    /// Shows the hidden icons in the menu bar until the user hides them again.
    func setPeeking(_ value: Bool) {
        guard value != isPeeking else { return }
        isPeeking = value
        applyConcealment()
    }

    // MARK: - Membership

    /// Moves every icon of `entry`'s app. The native menu bar follows immediately where hiding works.
    @discardableResult
    func move(_ entry: MenuBarEntry, toDrawer: Bool, before target: MenuBarEntry? = nil) -> Bool {
        guard enabled, canMove(entry) else { return false }
        let bundleID = entry.application.bundleID
        let group = [entry] + companions(of: entry)
        let groupIDs = Set(group.map(\.id))
        problem = nil
        if toDrawer {
            membership.insert(bundleID)
            var order = drawerEntries.map(\.id).filter { !groupIDs.contains($0) }
            let index = target.flatMap { target in order.firstIndex(of: target.id) } ?? order.endIndex
            order.insert(contentsOf: group.map(\.id), at: index)
            drawerOrder = order
        } else {
            membership.remove(bundleID)
            drawerOrder.removeAll { groupIDs.contains($0) }
        }
        rememberBundles(of: group)
        defaults.set(membership.bundleIDs, forKey: Key.bundleIDs)
        defaults.set(drawerOrder, forKey: Key.order)
        applyConcealment()
        return true
    }

    /// Reorders the compact Drawer. Dropping on an icon places the dragged one before it; dropping on the
    /// background sends it to the end.
    func reorderDrawerEntry(_ entry: MenuBarEntry, before target: MenuBarEntry?) {
        guard isInDrawer(entry), target?.id != entry.id else { return }
        drawerOrder = DrawerOrder.moving(entry.id, before: target?.id, in: drawerEntries.map(\.id))
        defaults.set(drawerOrder, forKey: Key.order)
    }

    @discardableResult
    private func rememberBundles(of entries: [MenuBarEntry]) -> Bool {
        let bundles = Set(entries.map(\.application.bundleID))
        guard !bundles.isSubset(of: knownBundleIDs) else { return false }
        knownBundleIDs.formUnion(bundles)
        defaults.set(knownBundleIDs.sorted(), forKey: Key.knownBundleIDs)
        return true
    }

    /// New apps with icons join the Drawer under the `newIconsGoToDrawer` policy; either way they become known.
    /// Returns whether the allow-list inputs changed.
    private func adoptNewApps(in scanned: [MenuBarEntry]) -> Bool {
        if knownBundleIDs.isEmpty {
            // First catalog ever: everything already in the menu bar is the user's starting point, not "new".
            return rememberBundles(of: scanned)
        }
        let fresh = scanned.filter { !knownBundleIDs.contains($0.application.bundleID) && canMove($0) }
        if newIconsGoToDrawer, !fresh.isEmpty {
            for entry in fresh { membership.insert(entry.application.bundleID) }
            drawerOrder += fresh.map(\.id).filter { !drawerOrder.contains($0) }
            defaults.set(membership.bundleIDs, forKey: Key.bundleIDs)
            defaults.set(drawerOrder, forKey: Key.order)
        }
        return rememberBundles(of: scanned) || (newIconsGoToDrawer && !fresh.isEmpty)
    }

    // MARK: - Hiding

    /// Hiding needs the Drawer on, Accessibility (without it hidden icons couldn't be opened from Altillo) and
    /// something to hide. Anything else shows every icon.
    private var wantsConcealment: Bool {
        enabled && support.hiding && hidesDrawerIcons && hasAccess && !isPeeking && !membership.isEmpty
    }

    /// One funnel for every change that affects the menu bar. Calls are serialized; each computes the list
    /// when it runs, so a burst of launches settles on the latest state.
    private func applyConcealment() {
        guard wantsConcealment else {
            releaseConcealment()
            return
        }
        let previous = concealTask
        concealTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, self.wantsConcealment else { return }
            let list = self.membership.allowList(
                running: self.runningBundleIDs(), shownThisSession: self.shownThisSession,
                alwaysAllowed: self.temporarilyShown.union([self.ownBundleID]), known: self.knownBundleIDs,
                newAppsJoinDrawer: self.newIconsGoToDrawer
            )
            // Icons about to disappear are still drawn: keep their glyphs for the Drawer.
            let leaving = self.entries.filter { entry in
                self.shownThisSession.contains(entry.application.bundleID) && !list.bundleIDs.contains(entry.application.bundleID)
            }
            if !leaving.isEmpty, self.glyphs.hasAccess {
                await self.glyphs.capture(await self.withCurrentFrames(leaving), force: true)
            }
            guard !Task.isCancelled, self.wantsConcealment else { return }
            let concealed = await self.concealer.conceal(allowing: list)
            guard !Task.isCancelled else { return }
            if concealed {
                self.shownThisSession = list.bundleIDs
                self.isConcealing = true
            } else {
                self.concealer.release()
                self.shownThisSession = []
                self.isConcealing = false
                self.problem = String(localized: "macOS didn't let Altillo hide menu bar icons. They stay visible.")
            }
        }
    }

    private func releaseConcealment() {
        concealTask?.cancel()
        concealTask = nil
        concealer.release()
        shownThisSession = []
        temporarilyShown = []
        revealedForMenu = nil
        isConcealing = false
    }

    // MARK: - Catalog

    /// Something that renders the Drawer (the open notch, the Settings pane) appeared or disappeared.
    /// Appearing is the lazy refresh point: the catalog is rescanned only if stale or old.
    func setVisible(_ visible: Bool, for consumer: DrawerConsumer) {
        if visible {
            visibleConsumers.insert(consumer)
        } else {
            visibleConsumers.remove(consumer)
            return
        }
        checkAccess()
        if DrawerRefreshPolicy.needsScan(isStale: catalogIsStale, hasEntries: !entries.isEmpty,
                                         lastScan: lastScan, now: .now, maxAge: Self.catalogMaxAge) {
            scheduleRefresh(after: .milliseconds(120))
        }
    }

    var isVisible: Bool { !visibleConsumers.isEmpty }

    private func catalogDidChange() {
        catalogIsStale = true
        // At rest this is the whole cost of an event: a flag. Scan only while someone is looking, or when an
        // icon may have just appeared hidden: under "Go to the Drawer" it must reach the Drawer to be reachable.
        guard isVisible || (newIconsGoToDrawer && isConcealing) else { return }
        scheduleRefresh(after: .milliseconds(400))
    }

    private func scheduleRefresh(after delay: Duration) {
        scheduledRefresh.schedule(after: delay) { [weak self] in self?.performScheduledRefresh(delay: delay) }
    }

    private func performScheduledRefresh(delay: Duration) {
        // Never rescan underneath an activation or an open panel; the next appearance catches up.
        guard !isPerformingMenuBarInteraction else {
            catalogIsStale = true
            return
        }
        guard scanTask == nil else {
            scheduleRefresh(after: delay)
            return
        }
        refresh()
    }

    /// Rescans the Accessibility catalog. Concealed icons stay in it: macOS keeps exposing them.
    func refresh(clearProblem: Bool = false) {
        refresh(clearProblem: clearProblem, thenConceal: false)
    }

    /// `thenConceal` hides the Drawer's icons only once the catalog and their glyphs were read, while visible.
    private func refresh(clearProblem: Bool = false, thenConceal: Bool) {
        checkAccess()
        guard hasAccess, scanTask == nil else {
            if thenConceal { applyConcealment() }
            return
        }
        scheduledRefresh.cancel()
        if clearProblem { problem = nil }
        isLoading = true
        catalogIsStale = false
        let applications = runningApplications()
        scanTask = Task { [weak self, accessibility] in
            let result = await accessibility.scan(applications: applications)
            guard !Task.isCancelled, let self else { return }
            Self.log.debug("scan found=\(result.count)")
            self.isLoading = false
            self.scanTask = nil
            self.lastScan = .now
            // Read glyphs before anything this scan triggers can hide their icons.
            if self.enabled, self.glyphs.hasAccess { await self.glyphs.capture(self.drawn(in: result)) }
            guard !Task.isCancelled else { return }
            self.didScan(result)
            if thenConceal { self.applyConcealment() }
        }
    }

    private func didScan(_ result: [MenuBarEntry]) {
        if entries != result { entries = result }
        guard enabled else { return }
        if adoptNewApps(in: result) { applyConcealment() }
    }

    /// Tests feed a catalog and Accessibility state directly; they never scan or touch the real menu bar.
    func setCatalogForTesting(_ entries: [MenuBarEntry], hasAccess: Bool) {
        self.hasAccess = hasAccess
        didScan(entries)
    }

    /// Waits until the menu bar reflects the latest change (tests).
    func settleForTesting() async {
        while let task = concealTask {
            await task.value
            if concealTask == task { return }
        }
    }

    private func forget(pid: Int32) {
        applicationCache.forget(pid: pid)
        applicationIcons[pid] = nil
    }

    // MARK: - Icons

    /// A stable, recognisable image per icon: SF Symbols for macOS's own items, the owner's icon otherwise.
    /// Concealed icons aren't drawn at all, so their pixels can't be captured.
    func stripIcon(for entry: MenuBarEntry) -> NSImage? { glyphs.image(for: entry) ?? catalogIcon(for: entry) }

    func settingsIcon(for entry: MenuBarEntry) -> NSImage { glyphs.image(for: entry) ?? catalogIcon(for: entry) }

    var hasIconAccess: Bool { glyphs.hasAccess }

    /// Asks for Screen Recording, which only adds the real glyphs; everything else works without it.
    func requestIconAccess() {
        glyphs.requestAccess()
        Task { [weak self] in
            // A grant usually lands while System Settings is in front; capture as soon as it does.
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if self.glyphs.hasAccess { await self.captureDrawn(force: true); return }
            }
        }
    }

    /// Icons on screen right now: everything unless the Drawer's apps are hidden.
    private var drawnEntries: [MenuBarEntry] { drawn(in: entries) }

    private func drawn(in catalog: [MenuBarEntry]) -> [MenuBarEntry] {
        guard isConcealing else { return catalog }
        return catalog.filter { !isInDrawer($0) || temporarilyShown.contains($0.application.bundleID) }
    }

    private func captureDrawn(force: Bool = false) async {
        guard glyphs.hasAccess, enabled else { return }
        await glyphs.capture(drawnEntries, force: force)
    }

    /// `entries` with their frames read now; a scan's frames go stale as soon as the menu bar shifts.
    private func withCurrentFrames(_ entries: [MenuBarEntry]) async -> [MenuBarEntry] {
        let frames = await accessibility.currentFrames(ids: entries.map(\.id))
        return entries.compactMap { entry in
            guard let frame = frames[entry.id], frame.width > 0, frame.height > 0 else { return nil }
            return MenuBarEntry(id: entry.id, application: entry.application, title: entry.title, frame: frame)
        }
    }

    private func catalogIcon(for entry: MenuBarEntry) -> NSImage {
        if let symbol = MenuBarAccessibility.systemSymbol(for: entry),
           let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            return image
        }
        return applicationIcon(for: entry)
            ?? NSImage(systemSymbolName: "questionmark", accessibilityDescription: "Icon unavailable")
            ?? NSImage(size: CGSize(width: MenuBarGlyph.box, height: MenuBarGlyph.box))
    }

    /// The owner's icon, drawn once per process at the strip's glyph size.
    private func applicationIcon(for entry: MenuBarEntry) -> NSImage? {
        let pid = entry.application.pid
        if let cached = applicationIcons[pid] { return cached }
        guard pid > 0 else { return nil }
        let glyph: NSImage
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon,
           !MenuBarGlyphFallback.isGenericApplicationIcon(icon, generic: genericApplicationIcon) {
            glyph = MenuBarGlyphFallback.glyph(fromApplicationIcon: icon)
        } else {
            glyph = MenuBarGlyphFallback.monogram(for: entry.application.name)
        }
        applicationIcons[pid] = glyph
        return glyph
    }

    // MARK: - Opening an icon

    /// Opens an icon's menu beside `anchor`, whether or not the icon is hidden: macOS keeps concealed items
    /// in the Accessibility tree with their actions.
    func activate(_ entry: MenuBarEntry, anchor: MenuBarPopupAnchor) {
        checkAccess()
        guard hasAccess, let anchorRect = anchor.screenRect(), activationTask == nil else { return }
        menuSessionTask?.cancel()
        menuSessionTask = nil
        problem = nil
        activationTask = Task { [weak self, accessibility] in
            guard let self else { return }
            defer { self.activationTask = nil }
            if let previous = self.currentMenuSession {
                let wasPresented = await previous.isPresented() == true
                let closesSamePanel = self.currentMenuEntryID == entry.id && wasPresented
                guard await self.dismissMenu(previous, entryID: self.currentMenuEntryID) else {
                    self.problem = String(localized: "Close the open menu, then try again.")
                    return
                }
                self.currentMenuSession = nil
                self.currentMenuEntryID = nil
                if closesSamePanel {
                    self.endRevealForMenu()
                    return
                }
            }
            // Whatever the previous menu showed goes back into hiding (its watcher may have been cancelled).
            self.endRevealForMenu()
            if let snapshot = await accessibility.menuSnapshot(id: entry.id), !snapshot.nodes.isEmpty {
                switch self.menuPresenter.present(snapshot.nodes, at: anchorRect,
                                                hasUnsupportedContent: snapshot.hasUnsupportedContent) {
                case .selected(let actionID):
                    let outcome = await accessibility.performMenuAction(id: actionID)
                    if case .unavailable = outcome {
                        self.problem = String(localized: "This command is no longer available. Open the menu and try again.")
                    }
                case .unavailable:
                    self.problem = String(localized: "This menu couldn't be displayed. Try opening it again.")
                case .cancelled: break
                }
                return
            }
            // No standard menu to mirror: click the real icon, shown for a moment if it's hidden, so its app
            // opens its own menu or panel the way it was written to.
            self.prepareForMenuBarInteraction?()
            let panelOwner = Self.panelOwnerPID(for: entry)
            if case .clicked(let revealed) = await self.clickRealIcon(entry) {
                self.revealedForMenu = revealed
                guard !Task.isCancelled else {
                    self.endRevealForMenu()
                    return
                }
                self.currentMenuEntryID = entry.id
                self.watchMenu(MenuBarMenuSession(pid: panelOwner))
                return
            }
            // The icon can't be shown where a click reaches it (e.g. behind the notch): open it through
            // Accessibility and move its panel beside the Drawer instead.
            let placement = MenuBarPopoverPlacement(pid: panelOwner)
            let session = MenuBarMenuSession(pid: panelOwner)
            let outcome = await accessibility.perform(id: entry.id, showMenu: false)
            guard !Task.isCancelled else { return }
            if case .unavailable = outcome {
                self.problem = String(localized: "This app doesn't expose a menu that Altillo can open.")
                return
            }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let point = CGPoint(x: anchorRect.minX, y: top - anchorRect.minY + 4)
            let screens = NSScreen.screens.map {
                DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: top)
            }
            guard await placement.place(at: point, screens: screens) else {
                if !(await session.dismiss()), await session.isPresented() == true {
                    // Control Center's popovers ignore Escape; their status action toggles them closed.
                    _ = await accessibility.perform(id: entry.id, showMenu: false)
                }
                self.problem = String(localized: "macOS didn't allow this app's panel to open beside its icon.")
                return
            }
            guard !Task.isCancelled else { _ = await session.dismiss(); return }
            self.currentMenuEntryID = entry.id
            self.watchMenu(session)
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

    /// Clicks `entry`'s real icon. A hidden icon's app is shown first (growing the allow-list is seamless) and
    /// its fresh frame awaited. Returns nil when no click happened; otherwise the bundle shown for the click, if any.
    private enum ClickOutcome {
        case notClicked
        /// `revealed`: the Drawer app shown in the menu bar for this click, to hide again when its menu closes.
        case clicked(revealed: String?)
    }

    private func clickRealIcon(_ entry: MenuBarEntry) async -> ClickOutcome {
        let bundleID = entry.application.bundleID
        let reveal = isConcealing && isInDrawer(entry)
        if reveal {
            temporarilyShown.insert(bundleID)
            applyConcealment()
            await concealTask?.value
            // MenuBarAgent draws the icon and updates its Accessibility frame a moment later.
            try? await Task.sleep(for: .milliseconds(150))
        }
        var settled: CGRect?
        var previous: CGRect?
        for _ in 0..<15 {
            guard !Task.isCancelled else { break }
            let frame = await accessibility.currentFrame(id: entry.id)
            // Icons folded into macOS's overflow («) share one frame; a click there opens the overflow instead.
            // Compare with where the neighbours are now: revealing an icon shifts them.
            let neighbours = Array(await accessibility.currentFrames(
                ids: drawnEntries.map(\.id).filter { $0 != entry.id }).values)
            if let frame, frame == previous, MenuBarItemClicker.isClickable(frame),
               !MenuBarGlyphCapture.overlapsAnother(frame, among: neighbours) {
                settled = frame
                break
            }
            previous = frame
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let settled, await MenuBarItemClicker.click(settled) else {
            if reveal { endTemporaryReveal(of: bundleID) }
            return .notClicked
        }
        return .clicked(revealed: reveal ? bundleID : nil)
    }

    private func endRevealForMenu() {
        guard let revealed = revealedForMenu else { return }
        revealedForMenu = nil
        endTemporaryReveal(of: revealed)
    }

    /// Hides an app shown for a click again. Shrinking the list replaces the assertion (a brief flash).
    private func endTemporaryReveal(of bundleID: String) {
        guard temporarilyShown.remove(bundleID) != nil else { return }
        applyConcealment()
    }

    /// Follows an open panel until it closes, so the notch's hover doesn't interfere meanwhile.
    /// A cancelled watcher leaves the reveal to whoever cancelled it (a new activation, or `stop()`).
    private func watchMenu(_ session: MenuBarMenuSession) {
        currentMenuSession = session
        menuSessionTask = Task { [weak self] in
            var observedMenu = false
            var closedSamples = 0
            // A missing AX answer is never grounds to consider a menu closed.
            for sample in 0..<1_200 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.enabled else { return }
                let presented = await session.isPresented()
                guard !Task.isCancelled else { return }
                if presented == true { observedMenu = true; closedSamples = 0 }
                else if presented == false, observedMenu { closedSamples += 1 }
                else { closedSamples = 0 }
                if closedSamples >= 2 || (sample >= 11 && !observedMenu) {
                    // Closed, or an immediate action without any panel.
                    self.currentMenuSession = nil
                    self.currentMenuEntryID = nil
                    self.menuSessionTask = nil
                    self.endRevealForMenu()
                    return
                }
            }
            self?.menuSessionTask = nil
            self?.endRevealForMenu()
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

    // MARK: - Accessibility

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

    private func checkAccess() {
        let trusted = AXIsProcessTrusted()
        guard trusted != hasAccess else { return }
        hasAccess = trusted
        if !trusted {
            // Hidden icons could no longer be opened from Altillo: give them back to the menu bar.
            releaseConcealment()
            activationTask?.cancel()
            scanTask?.cancel()
            scanTask = nil
            isLoading = false
            entries = []
            catalogIsStale = true
            if enabled {
                problem = String(localized: "Accessibility access was turned off. Your menu bar icons are visible again.")
            }
        } else {
            problem = nil
            guard enabled else { return }
            refresh()
            applyConcealment()
        }
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

    /// A short, bounded check after the user asks for access: a grant can land while System Settings owns focus.
    private func monitorAccess() {
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            for _ in 0..<Self.permissionCheckCount {
                try? await Task.sleep(for: Self.permissionCheckInterval)
                guard !Task.isCancelled, let self else { return }
                self.checkAccess()
                if self.hasAccess { break }
            }
            guard !Task.isCancelled else { return }
            self?.permissionTask = nil
        }
    }
}

/// What the Drawer can do on this macOS. The catalog (strip, Settings, opening menus) needs macOS 26; hiding
/// needs the system allow-list that arrived with macOS 27, checked at run time.
struct DrawerSupport: Equatable, Sendable {
    var catalog: Bool
    var hiding: Bool

    static let unavailable = DrawerSupport(catalog: false, hiding: false)

    static func decide(majorVersion: Int, canHide: Bool) -> DrawerSupport {
        guard majorVersion >= 26 else { return .unavailable }
        return DrawerSupport(catalog: true, hiding: majorVersion >= 27 && canHide)
    }
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
