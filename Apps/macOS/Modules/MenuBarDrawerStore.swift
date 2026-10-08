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
    /// How the Drawer draws its icons: as they look in the menu bar, or as their apps' icons.
    private(set) var iconStyle: DrawerIconStyle
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
    @ObservationIgnored private var activationTask: Task<Void, Never>? {
        didSet { reportMenuBarInteraction() }
    }
    @ObservationIgnored private var menuSessionTask: Task<Void, Never>? {
        didSet { reportMenuBarInteraction() }
    }
    /// Briefly shows hidden Drawer apps whose menu-bar glyph was never captured, so it can be.
    @ObservationIgnored private var glyphRevealTask: Task<Void, Never>?
    /// Bundles already shown once for their glyph: each is revealed at most once per launch.
    @ObservationIgnored private var glyphRevealAttempts: Set<String> = []
    @ObservationIgnored private var reportedMenuBarInteraction = false
    /// The processes the last scan read. Menu-bar-only apps launch and quit without workspace notifications.
    @ObservationIgnored private var scannedPIDs: Set<Int32> = []
    /// Every Drawer button on screen, by entry id, to recognise a click another app's panel swallowed.
    @ObservationIgnored private var anchors: [String: MenuBarPopupAnchor] = [:]
    /// Identifies the newest activation, so an older one finishing never clears it.
    @ObservationIgnored private var activationToken: UUID?
    /// The icon the newest activation is opening.
    @ObservationIgnored private var activatingEntryID: String?
    /// When the open panel appeared: a second click right after is part of the same gesture, not a close.
    @ObservationIgnored private var menuOpenedAt: ContinuousClock.Instant?
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
    /// An app's own panel is opening from the Drawer (true) or has closed (false). The open notch stays where it
    /// is, but steps down to the status bar's level so the panel can draw over it.
    @ObservationIgnored var menuBarInteractionChanged: ((Bool) -> Void)?
    /// Folds the open notch, for an icon behind it whose app answers nothing but a real click.
    @ObservationIgnored var foldNotchForClick: (() -> Void)?
    /// The open notch's visible shape in screen coordinates, so a panel drawn below its level can open under it.
    @ObservationIgnored var notchVisibleFrame: (() -> CGRect?)?

    private func reportMenuBarInteraction() {
        let active = isPerformingMenuBarInteraction
        guard active != reportedMenuBarInteraction else { return }
        reportedMenuBarInteraction = active
        menuBarInteractionChanged?(active)
    }

    private enum Key {
        static let enabled = "drawer.enabled"
        static let hidesIcons = "drawer.hidesIcons"
        static let newIconsGoToDrawer = "drawer.newIconsGoToDrawer"
        static let iconStyle = "drawer.iconStyle"
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
        self.iconStyle = defaults.string(forKey: Key.iconStyle).flatMap(DrawerIconStyle.init(rawValue:)) ?? .menuBar
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
        for task in [scanTask, permissionTask, activationTask, menuSessionTask, accessRecheckTask, concealTask,
                     glyphRevealTask] {
            task?.cancel()
        }
        glyphRevealTask = nil
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

    func setIconStyle(_ value: DrawerIconStyle) {
        guard value != iconStyle else { return }
        iconStyle = value
        defaults.set(value.rawValue, forKey: Key.iconStyle)
        captureMissingGlyphs()
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
        if catalogIsStale == false, Set(runningApplications().map(\.pid)) != scannedPIDs { catalogIsStale = true }
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
        scannedPIDs = Set(applications.map(\.pid))
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
            if self.isVisible {
                await self.concealTask?.value
                self.captureMissingGlyphs()
            }
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

    /// One image per icon, in the chosen `iconStyle`. Menu-bar style shows the captured glyph and falls back to the
    /// owner's icon until one exists (concealed icons aren't drawn, so `captureMissingGlyphs` shows them once).
    /// App style shows the owner's icon; macOS's own items have no app icon of their own and keep their glyph.
    func stripIcon(for entry: MenuBarEntry) -> NSImage? { icon(for: entry) }

    func settingsIcon(for entry: MenuBarEntry) -> NSImage { icon(for: entry) }

    private func icon(for entry: MenuBarEntry) -> NSImage {
        switch iconStyle {
        case .menuBar:
            return glyphs.image(for: entry) ?? catalogIcon(for: entry)
        case .application:
            if DrawerMembership.isSystemHosted(entry.application.bundleID) {
                return glyphs.image(for: entry) ?? catalogIcon(for: entry)
            }
            return applicationIcon(for: entry) ?? glyphs.image(for: entry) ?? catalogIcon(for: entry)
        }
    }

    /// Hidden Drawer icons never captured (hidden before Screen Recording was allowed, or before they had a
    /// glyph) would otherwise show their app's icon among real glyphs. Shows their apps in the menu bar for a
    /// moment, once per launch: hiding them again captures their glyphs on the way out (`applyConcealment`).
    private func captureMissingGlyphs() {
        guard iconStyle == .menuBar, enabled, isConcealing, glyphs.hasAccess, glyphRevealTask == nil,
              !isPerformingMenuBarInteraction else { return }
        let missing = drawerEntries.filter {
            canMove($0) && glyphs.image(for: $0) == nil && !glyphRevealAttempts.contains($0.application.bundleID)
        }
        let bundles = Set(missing.map(\.application.bundleID)).subtracting(temporarilyShown)
        guard !bundles.isEmpty else { return }
        glyphRevealAttempts.formUnion(bundles)
        Self.log.debug("revealing \(bundles.count) apps for their glyphs")
        glyphRevealTask = Task { [weak self] in
            guard let self else { return }
            defer { self.glyphRevealTask = nil }
            self.temporarilyShown.formUnion(bundles)
            self.applyConcealment()
            await self.concealTask?.value
            // MenuBarAgent draws the icons and updates their Accessibility frames a moment later.
            try? await Task.sleep(for: .milliseconds(400))
            let shownForMenu = self.revealedForMenu
            for bundle in bundles where bundle != shownForMenu { self.temporarilyShown.remove(bundle) }
            self.applyConcealment()
        }
    }

    var hasIconAccess: Bool { glyphs.hasAccess }

    /// Asks for Screen Recording, which only adds the real glyphs; everything else works without it.
    func requestIconAccess() {
        glyphs.requestAccess()
        Task { [weak self] in
            // A grant usually lands while System Settings is in front; capture as soon as it does.
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if self.glyphs.hasAccess {
                    await self.captureDrawn(force: true)
                    self.captureMissingGlyphs()
                    return
                }
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

    /// Opens an icon's menu at its Drawer button, whether or not the icon is hidden: macOS keeps concealed items
    /// in the Accessibility tree with their actions.
    ///
    /// Standard menus are mirrored at the button. Anything else is opened by the app itself: its real icon is
    /// shown for a moment and clicked (Accessibility's press when it can't be clicked or the click didn't take),
    /// and the panel it opens is brought to the button, or just below the open notch when it would draw under it.
    /// A click is never dropped: a newer one replaces whatever is still in progress.
    func activate(_ entry: MenuBarEntry, anchor: MenuBarPopupAnchor) {
        checkAccess()
        guard hasAccess, let anchorRect = anchor.screenRect() else {
            Self.log.debug("activate \(entry.id, privacy: .public) skipped ax=\(self.hasAccess)")
            return
        }
        // A second click on the icon that's still opening is impatience, not a request to close and start over.
        if activationTask != nil, activatingEntryID == entry.id { return }
        if currentMenuEntryID == entry.id, let openedAt = menuOpenedAt, ContinuousClock.now - openedAt < .milliseconds(600) {
            return
        }
        Self.log.debug("activate \(entry.id, privacy: .public) busy=\(self.activationTask != nil)")
        let previousActivation = activationTask
        previousActivation?.cancel()
        problem = nil
        let token = UUID()
        activationToken = token
        activatingEntryID = entry.id
        // Started before the watcher stops, so the notch never leaves its interaction level in between.
        activationTask = Task { [weak self, accessibility] in
            await previousActivation?.value
            guard let self else { return }
            defer {
                if self.activationToken == token {
                    self.activationTask = nil
                    self.activatingEntryID = nil
                }
            }
            guard !Task.isCancelled else { return }
            // A glyph reveal in flight would hide the icon again under the click.
            await self.glyphRevealTask?.value
            if let previous = self.currentMenuSession {
                let previousIsOpen = await previous.isPresented() == true
                let closesSamePanel = self.currentMenuEntryID == entry.id && previousIsOpen
                // Best effort: a panel that won't close (or an app window) never blocks the next icon.
                let dismissed = await self.dismissMenu(previous, entryID: self.currentMenuEntryID)
                Self.log.debug("previous menu dismissed=\(dismissed) samePanel=\(closesSamePanel)")
                self.currentMenuSession = nil
                self.currentMenuEntryID = nil
                if closesSamePanel {
                    self.endRevealForMenu()
                    return
                }
            }
            // Whatever the previous menu showed goes back into hiding (its watcher may have been cancelled).
            self.endRevealForMenu()
            guard !Task.isCancelled else { return }
            // An app that quit and came back has new status items: read them before opening one.
            var entry = entry
            let itemFrame = await accessibility.currentFrame(id: entry.id)
            if NSRunningApplication(processIdentifier: entry.application.pid) == nil || itemFrame == nil {
                Self.log.debug("stale item \(entry.id, privacy: .public): rescanning")
                self.catalogIsStale = true
                self.refresh()
                await self.scanTask?.value
                guard !Task.isCancelled else { return }
                guard let fresh = self.entries.first(where: { $0.id == entry.id }) else {
                    self.problem = String(localized: "This icon is no longer in the menu bar.")
                    return
                }
                entry = fresh
            }
            if let snapshot = await accessibility.menuSnapshot(id: entry.id), !snapshot.nodes.isEmpty {
                Self.log.debug("path=mirrored nodes=\(snapshot.nodes.count)")
                switch self.menuPresenter.present(snapshot.nodes, at: anchorRect,
                                                hasUnsupportedContent: snapshot.hasUnsupportedContent) {
                case .selected(let actionID):
                    let outcome = await accessibility.performMenuAction(id: actionID)
                    if case .unavailable = outcome {
                        self.problem = String(localized: "This command is no longer available. Open the menu and try again.")
                    }
                case .unavailable:
                    self.problem = String(localized: "This menu couldn't be displayed. Try opening it again.")
                case .cancelled:
                    // A click on another Drawer icon closes the menu first, as in the menu bar; then opens that icon.
                    let sinceClick = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .leftMouseDown)
                    if sinceClick < 0.4, let (other, otherAnchor) = self.drawerIcon(at: NSEvent.mouseLocation), other.id != entry.id {
                        Self.log.debug("menu closed by a click on \(other.id, privacy: .public): opening it")
                        self.activate(other, anchor: otherAnchor)
                    }
                }
                return
            }
            await self.openOwnPanel(of: entry, at: anchorRect)
        }
        menuSessionTask?.cancel()
        menuSessionTask = nil
    }

    func registerAnchor(_ anchor: MenuBarPopupAnchor, for entry: MenuBarEntry) {
        anchors[entry.id] = anchor
    }

    /// The Drawer icon at `point` (AppKit screen coordinates), with its button.
    private func drawerIcon(at point: CGPoint) -> (MenuBarEntry, MenuBarPopupAnchor)? {
        for entry in drawerEntries {
            if let anchor = anchors[entry.id], anchor.screenRect()?.contains(point) == true { return (entry, anchor) }
        }
        return nil
    }

    /// While an app's menu or panel is open, a click on another Drawer icon goes to that app (which closes its panel)
    /// rather than to Altillo. Like the menu bar, that one click also opens the icon clicked; a click on the icon
    /// whose panel is open only closes it.
    func handleClickWhileMenuOpen(at point: CGPoint) {
        guard isPerformingMenuBarInteraction, !MenuBarItemClicker.isClicking, let (entry, anchor) = drawerIcon(at: point),
              entry.id != currentMenuEntryID else { return }
        Self.log.debug("click on \(entry.id, privacy: .public) taken by the open panel: opening it")
        activate(entry, anchor: anchor)
    }

    /// Opens the app's own menu or panel (see `activate`) and follows it until it closes.
    private func openOwnPanel(of entry: MenuBarEntry, at anchorRect: CGRect) async {
        let panelOwner = Self.panelOwnerPID(for: entry)
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: top) }
        let button = DrawerGeometry.accessibilityFrame(anchorRect, primaryScreenHeight: top)
        // The open notch, in Accessibility coordinates: panels drawn below its level must clear it, and an icon
        // underneath it can't be clicked.
        let notch = notchVisibleFrame?().map { DrawerGeometry.accessibilityFrame($0, primaryScreenHeight: top) }
        let notchBottom = notch?.maxY ?? button.maxY
        // Both read the owner's windows before anything opens, so its new panel is the one they follow.
        let placement = MenuBarPopoverPlacement(pid: panelOwner)
        let session = MenuBarMenuSession(pid: panelOwner)

        let bundleID = entry.application.bundleID
        let reveal = isConcealing && isInDrawer(entry)
        // A hidden icon keeps a stale frame until MenuBarAgent draws it again.
        let hiddenFrame = reveal ? await accessibility.currentFrame(id: entry.id) : nil
        if reveal {
            temporarilyShown.insert(bundleID)
            revealedForMenu = bundleID
            applyConcealment()
            await concealTask?.value
        }
        var opened = false
        let target = await clickTarget(for: entry, hiddenFrame: hiddenFrame, avoiding: notch)
        if case .clickable(let frame) = target {
            let clicked = await MenuBarItemClicker.click(frame)
            opened = clicked ? await waitUntilPresented(session) : false
            Self.log.debug("path=click target=\(String(describing: frame), privacy: .public) clicked=\(clicked) opened=\(opened)")
        }
        if !opened, !Task.isCancelled {
            // No click to make, or it didn't take: some apps only answer Accessibility's press.
            let outcome = await accessibility.perform(id: entry.id, showMenu: false)
            opened = await waitUntilPresented(session)
            Self.log.debug("path=press outcome=\(String(describing: outcome), privacy: .public) opened=\(opened)")
            if !opened, !Task.isCancelled, case .underNotch(let frame) = target {
                // The app only answers a real click, and the open notch covers its icon: fold the notch first.
                foldNotchForClick?()
                try? await Task.sleep(for: .milliseconds(300))
                let clicked = await MenuBarItemClicker.click(frame)
                opened = clicked ? await waitUntilPresented(session) : false
                Self.log.debug("path=fold+click clicked=\(clicked) opened=\(opened)")
            }
            if !opened, target?.isReachable != true {
                problem = if case .unavailable = outcome {
                    String(localized: "This app doesn't expose a menu that Altillo can open.")
                } else if target == nil {
                    // Drawn where no click reaches it (macOS's overflow «, behind the camera), and no answer to the press.
                    String(localized: "This app didn't open its menu from Altillo. Try it from the menu bar.")
                } else {
                    // Never drawn: usually an icon turned off in System Settings.
                    String(localized: "This app didn't open its menu. Check that its icon is allowed in System Settings › Menu Bar.")
                }
                endRevealForMenu()
                return
            }
        }
        guard !Task.isCancelled else {
            endRevealForMenu()
            return
        }
        let placed = await placement.place(screens: screens) { window in
            // Centred under the button. Panels above the notch's level can overlap it; the rest open below it.
            let x = button.midX - window.content.width / 2
            let y = window.layer >= Int(CGWindowLevelForKey(.statusWindow)) ? button.maxY + 4 : notchBottom + 6
            return CGPoint(x: x, y: y)
        }
        Self.log.debug("placement=\(String(describing: placed), privacy: .public)")
        if placed == .standardWindow {
            // The app opened one of its own windows: it's the app's from here on. The notch closes as usual
            // once the pointer leaves it.
            endRevealForMenu()
            return
        }
        currentMenuEntryID = entry.id
        menuOpenedAt = .now
        watchMenu(session, presentedAlready: opened)
    }

    /// Up to `timeout` for the owner to show a menu or panel.
    private func waitUntilPresented(_ session: MenuBarMenuSession, timeout: Duration = .milliseconds(700)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await session.isPresented() == true { return true }
            guard !Task.isCancelled else { return false }
            try? await Task.sleep(for: .milliseconds(60))
        }
        return false
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

    /// Where a click can reach an icon.
    private enum ClickTarget {
        case clickable(CGRect)
        /// Allowed, but never drawn: macOS itself keeps it out of the menu bar (System Settings › Menu Bar).
        case notDrawn
        /// Drawn, but behind the open notch: reachable only once the notch folds.
        case underNotch(CGRect)

        var isReachable: Bool {
            if case .notDrawn = self { false } else { true }
        }
    }

    /// Where a click reaches `entry`'s icon, or nil when it can't be clicked where it's drawn (behind the camera
    /// housing, folded into macOS's overflow «). A revealed icon's frame is only trusted once MenuBarAgent has
    /// moved it, or after a while.

    private func clickTarget(for entry: MenuBarEntry, hiddenFrame: CGRect?, avoiding notch: CGRect?) async -> ClickTarget? {
        let start = ContinuousClock.now
        var previous: CGRect?
        while ContinuousClock.now - start < .milliseconds(1_200) {
            guard !Task.isCancelled else { return nil }
            let frame = await accessibility.currentFrame(id: entry.id)
            // Icons folded into the overflow share one frame; a click there opens the overflow instead.
            // Compare with where the neighbours are now: revealing an icon shifts them.
            let neighbours = Array(await accessibility.currentFrames(
                ids: drawnEntries.map(\.id).filter { $0 != entry.id }).values)
            let fresh = hiddenFrame == nil || frame != hiddenFrame || ContinuousClock.now - start > .milliseconds(450)
            if let frame, frame == previous, fresh, MenuBarItemClicker.isClickable(frame),
               !MenuBarGlyphCapture.overlapsAnother(frame, among: neighbours) {
                // Under the open notch a click lands on Altillo, not the icon.
                if let notch, notch.intersects(frame) {
                    Self.log.debug("icon under the notch: pressing it instead")
                    return .underNotch(frame)
                }
                return .clickable(frame)
            }
            previous = frame
            try? await Task.sleep(for: .milliseconds(70))
        }
        Self.log.debug("no click target: last=\(String(describing: previous), privacy: .public)")
        if hiddenFrame != nil, let previous, !Self.isInMenuBar(previous) { return .notDrawn }
        return nil
    }

    /// Status items sit in a screen's top band; MenuBarAgent parks undrawn ones elsewhere (bottom-left).
    private static func isInMenuBar(_ frame: CGRect) -> Bool {
        guard let primary = NSScreen.screens.first else { return false }
        let top = primary.frame.maxY
        return NSScreen.screens.contains { screen in
            let bounds = DrawerGeometry.accessibilityFrame(screen.frame, primaryScreenHeight: top)
            return bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) && frame.minY - bounds.minY < 40
        }
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
    private func watchMenu(_ session: MenuBarMenuSession, presentedAlready: Bool = false) {
        currentMenuSession = session
        menuSessionTask = Task { [weak self] in
            var observedMenu = presentedAlready
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
                // Nothing seen after the press either: an immediate action, so don't hold the notch for long.
                if closedSamples >= 2 || (sample >= (presentedAlready ? 11 : 4) && !observedMenu) {
                    Self.log.debug("menu session ended observed=\(observedMenu) sample=\(sample)")
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
/// How the Drawer draws its icons. Menu-bar glyphs need Screen Recording; without it every style shows app icons.
enum DrawerIconStyle: String, CaseIterable, Sendable {
    case menuBar
    case application
}

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
