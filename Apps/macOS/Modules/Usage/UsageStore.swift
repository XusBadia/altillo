import AltilloCore
import AltilloUsage
import AppKit
import Foundation
import Observation
import SystemConfiguration

/// How much of each AI provider is left (PLAN §5.2): the numbers behind the usage section, its ear, its alerts,
/// Ask's `usage` tool and every `UsageSnapshotPublisher`.
///
/// Event-driven and quiet (PLAN §1.5):
/// - **One refresh every 5 min**, from a single task asleep in between. Nothing ticks in the UI: views that count down
///   use a `TimelineView` only while they are on screen.
/// - **Stale-while-revalidate:** a failed read keeps the last numbers (and when they were read); past 15 min they're
///   marked stale, never thrown away.
/// - **Launch and wake:** the last snapshot is read from disk so the notch has numbers at once, then a refresh.
///   While the Mac or its screens sleep there is no refresh at all; waking brings one.
/// - **Collectors run in parallel, off the main actor,** each with a time limit; results land on the main actor.
/// - **Alerts** come from `UsageAlertEvaluator`, whose memory starts empty at every launch: the first reading of
///   each window is a baseline and never peeks.
@MainActor
@Observable
final class UsageStore {
    /// One provider as Settings lists it: whether it's set up here, the user's switch and its latest reading.
    struct Entry: Identifiable, Equatable, Sendable {
        var id: UsageProviderID
        var displayName: String
        /// Set up on this Mac (its CLI signed in), or reported by the OpenUsage-compatible app.
        var isAvailable: Bool
        /// From the OpenUsage-compatible app, not one of Altillo's own collectors.
        var isExternal: Bool
        var usage: ProviderUsage?
    }

    /// What the header says about the numbers as a whole.
    enum Freshness: Equatable, Sendable {
        case upToDate(since: Date)
        case stale(since: Date)
        case nothing
    }

    // MARK: State

    /// Every provider known, in display order: Altillo's collectors first, then the external ones.
    private(set) var entries: [Entry] = []
    /// Latest reading per provider (kept across failures).
    private(set) var readings: [UsageProviderID: ProviderUsage] = [:]
    private(set) var isRefreshing = false
    /// The last time a batch finished (successfully or not).
    private(set) var lastAttempt: Date?
    /// True once the catalog has been checked at least once (before that the empty state would be premature).
    private(set) var hasChecked = false
    /// The last snapshot built, as publishers and Ask see it.
    private(set) var snapshot: UsageSnapshot?

    /// Where each snapshot goes after a refresh (the legacy iPhone file, CloudKit later). Registered by the app, at
    /// any time: a publisher that can publish keeps the store refreshing even with the usage section off.
    @ObservationIgnored var publishers: [any UsageSnapshotPublisher] = [] {
        didSet { updateActivity() }
    }
    /// Shows a peek (wired to `NotchCoordinator.post`).
    @ObservationIgnored var postAlert: (NotchAlert) -> Void = { _ in }

    /// The store whose numbers Settings and Ask read: the running app's. Set by `start()`.
    static weak var live: UsageStore?

    // MARK: Configuration

    static let refreshInterval: Duration = .seconds(5 * 60)
    /// Past this the header and cards say "stale" (three missed refreshes).
    nonisolated static let staleAfter: TimeInterval = 15 * 60
    /// Each collector gets this long before its reading counts as unreachable.
    static let collectorTimeout: Duration = .seconds(30)
    /// The network needs a moment after waking up.
    static let wakeDelay: Duration = .seconds(5)

    let settings: AltilloSettings
    @ObservationIgnored private let collectors: () -> [any UsageCollector]
    @ObservationIgnored private let externalSource: (any UsageExternalSource)?
    @ObservationIgnored private let clock: any UsageClock
    @ObservationIgnored private let archiveURL: URL?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let timeout: Duration

    @ObservationIgnored private var alertState = UsageAlertState()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var inFlight: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var sectionIsOn = true
    @ObservationIgnored private var appliedShowsExternal = true
    @ObservationIgnored private var isAsleep = false

    init(
        settings: AltilloSettings,
        collectors: @escaping () -> [any UsageCollector] = { UsageCollectors.all() },
        externalSource: (any UsageExternalSource)? = UsageExternalSources.standard(),
        clock: any UsageClock = SystemUsageClock(),
        archiveURL: URL? = URL.applicationSupportDirectory.appending(path: "Altillo/usage.json"),
        defaults: UserDefaults = .standard,
        timeout: Duration = UsageStore.collectorTimeout
    ) {
        self.settings = settings
        self.collectors = collectors
        self.externalSource = externalSource
        self.clock = clock
        self.archiveURL = archiveURL
        self.defaults = defaults
        self.timeout = timeout
    }

    // MARK: What the notch shows

    /// The providers the notch shows, in order: set up on this Mac (or reported by the OpenUsage-compatible app) and
    /// switched on. One signed out since the last refresh leaves; its last numbers stay for when it's back.
    var providers: [ProviderUsage] {
        entries.compactMap { entry in
            guard entry.isAvailable, settings.isUsageProviderEnabled(entry.id) else { return nil }
            return entry.usage ?? readings[entry.id]
        }
    }

    /// The first provider with a limit to show: the one the ear and the contextual ear talk about.
    var primary: ProviderUsage? { providers.first { $0.headline != nil } }

    /// What the contextual ear gets: the primary provider's fullest limit, only while it's running high (at or
    /// above the lowest alert level) and the numbers are fresh. A calm 30 % isn't "what matters now".
    var contextualSignal: UsageSignal? {
        Self.contextualSignal(primary: primary, thresholds: settings.usageAlertThresholds, now: clock.now)
    }

    nonisolated static func contextualSignal(primary: ProviderUsage?, thresholds: [Int], now: Date) -> UsageSignal? {
        guard let primary, let window = primary.headline, !primary.isStale(now: now, limit: staleAfter) else {
            return nil
        }
        let level = Double(thresholds.min() ?? 80) / 100
        guard window.used >= level else { return nil }
        return UsageSignal(providerName: primary.displayName, fraction: window.used)
    }

    /// How old the numbers on screen are (the oldest of them). The refresh in flight is `isRefreshing`.
    func freshness(now: Date = .now) -> Freshness {
        let dated = providers.filter { !$0.windows.isEmpty }
        guard let oldest = dated.map(\.fetchedAt).min() else { return .nothing }
        return now.timeIntervalSince(oldest) > Self.staleAfter ? .stale(since: oldest) : .upToDate(since: oldest)
    }

    // MARK: Lifecycle

    /// Reads the last snapshot from disk, watches sleep and wake, and starts the 5-minute rhythm.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        Self.live = self
        loadArchive()
        observeWorkspace()
        if isActive { schedule(after: .zero) }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        loop?.cancel()
        loop = nil
        let workspace = NSWorkspace.shared.notificationCenter
        observers.forEach { workspace.removeObserver($0) }
        observers.removeAll()
        if Self.live === self { Self.live = nil }
    }

    /// The usage section was switched on or off. With it off (and no publisher that can publish) nothing refreshes;
    /// the last numbers stay.
    func setSectionEnabled(_ enabled: Bool) {
        sectionIsOn = enabled
        updateActivity()
    }

    private func updateActivity() {
        let active = sectionIsOn || publishers.contains { $0.isEnabled }
        guard active != isActive else { return }
        isActive = active
        guard isStarted, !isAsleep else { return }
        if active { resumeAfterPause(delay: .zero) } else { cancelLoop() }
    }

    /// The providers switched on changed: a provider switched back on gets its numbers now, and the
    /// OpenUsage-compatible app's providers come (or go) as soon as its switch does.
    func providersMayHaveChanged() {
        let showsExternal = settings.usageShowsOpenUsageSource
        defer { appliedShowsExternal = showsExternal }
        if !showsExternal { entries.removeAll { $0.isExternal } }
        guard isStarted, isActive, !isAsleep, hasChecked else { return }
        let missing = entries.contains { entry in
            settings.isUsageProviderEnabled(entry.id) && entry.isAvailable && readings[entry.id] == nil
        }
        if missing || (showsExternal && !appliedShowsExternal) { refreshNow() }
    }

    /// The refresh button, and anything else that wants numbers now. Restarts the 5-minute rhythm from here.
    func refreshNow() {
        guard isActive, !isAsleep else { return }
        schedule(after: .zero)
    }

    /// The usage section appeared: numbers older than `age` are worth refreshing.
    func refreshIfOlder(than age: TimeInterval = 60) {
        guard let lastAttempt else { return refreshNow() }
        if clock.now.timeIntervalSince(lastAttempt) > age { refreshNow() }
    }

    // MARK: Scheduling

    /// One task: wait `delay`, refresh, then every `refreshInterval` until cancelled.
    private func schedule(after delay: Duration) {
        loop?.cancel()
        let clock = self.clock
        loop = Task { [weak self] in
            var wait = delay
            while !Task.isCancelled {
                if wait > .zero {
                    do { try await clock.sleep(for: wait) } catch { return }
                }
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
                wait = Self.refreshInterval
            }
        }
    }

    private func cancelLoop() {
        loop?.cancel()
        loop = nil
    }

    /// After sleep, or after being switched back on: refresh soon if the numbers are older than a minute,
    /// otherwise just pick up the rhythm where it was.
    private func resumeAfterPause(delay: Duration) {
        guard isActive else { return }
        let interval = TimeInterval(Self.refreshInterval.components.seconds)
        guard let lastAttempt else { return schedule(after: delay) }
        let age = clock.now.timeIntervalSince(lastAttempt)
        if age > 60 {
            schedule(after: delay)
        } else {
            schedule(after: .seconds(max(0, interval - age)))
        }
    }

    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sleep() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            })
        }
    }

    /// The Mac or its screens went to sleep (or another user took over): no refresh until they're back.
    func sleep() {
        isAsleep = true
        cancelLoop()
    }

    func wake() {
        guard isAsleep else { return }
        isAsleep = false
        guard isStarted else { return }
        resumeAfterPause(delay: Self.wakeDelay)
    }

    // MARK: Refreshing

    /// One batch: every collector (and the external source) in parallel, then the snapshot, the publishers and the
    /// alerts. A second call while one runs waits for it instead of starting another.
    func refresh() async {
        if let inFlight { return await inFlight.value }
        let task = Task { await self.performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performRefresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let now = clock.now
        let collectors = self.collectors()
        let previous = readings
        let disabled = settings.usageDisabledProviders
        let timeout = self.timeout
        let clock = self.clock

        // Altillo's own collectors, in parallel. Availability is checked for every one (Settings shows it); only
        // the ones switched on are read.
        let own: [(index: Int, entry: Entry)] = await withTaskGroup(of: (Int, Entry).self) { group in
            for (index, collector) in collectors.enumerated() {
                let id = collector.providerID
                let name = collector.displayName
                let last = previous[id]
                let wanted = !disabled.contains(id)
                group.addTask {
                    let available = await collector.isAvailable()
                    guard available, wanted else {
                        return (index, Entry(id: id, displayName: name, isAvailable: available, isExternal: false,
                                             usage: last))
                    }
                    if let last, case let .rateLimited(retryAfter?) = last.problem, retryAfter > now {
                        // Asked to wait: keep what we have until then.
                        return (index, Entry(id: id, displayName: name, isAvailable: true, isExternal: false,
                                             usage: last))
                    }
                    let fresh = await UsageFetch.run(collector, previous: last, now: now, timeout: timeout,
                                                     clock: clock)
                    return (index, Entry(id: id, displayName: name, isAvailable: true, isExternal: false,
                                         usage: UsageMerge.merge(fresh, previous: last)))
                }
            }
            var results: [(index: Int, entry: Entry)] = []
            for await result in group { results.append((result.0, result.1)) }
            return results
        }
        var catalog = own.sorted { $0.index < $1.index }.map(\.entry)

        // The OpenUsage-compatible app, only for providers none of the collectors read.
        if let externalSource, settings.usageShowsOpenUsageSource {
            let known = Set(catalog.map(\.id))
            let lastExternal = previous.values.filter { !known.contains($0.id) }
            let external = await UsageFetch.runExternal(externalSource, excluding: known, previous: lastExternal,
                                                        now: now, timeout: timeout, clock: clock)
            for usage in external where !known.contains(usage.id) {
                let merged = UsageMerge.merge(usage, previous: previous[usage.id])
                catalog.append(Entry(id: usage.id, displayName: usage.displayName, isAvailable: true,
                                     isExternal: true, usage: merged))
            }
        }

        apply(catalog, now: now)
    }

    /// Lands a batch on the main actor: new readings, the snapshot, the archive, publishers and alerts.
    private func apply(_ catalog: [Entry], now: Date) {
        var next: [UsageProviderID: ProviderUsage] = [:]
        for entry in catalog {
            if let usage = entry.usage { next[entry.id] = usage }
        }
        // A provider that fell out of the batch (switched off, external app closed) keeps its last numbers, so
        // switching it back on shows something straight away.
        for (id, usage) in readings where next[id] == nil { next[id] = usage }
        entries = catalog
        readings = next
        lastAttempt = now
        hasChecked = true

        let snapshot = makeSnapshot(now: now)
        self.snapshot = snapshot
        saveArchive(snapshot)
        for publisher in publishers where publisher.isEnabled {
            publisher.publish(snapshot)
        }
        evaluateAlerts(now: now)
    }

    // MARK: Alerts

    private func evaluateAlerts(now: Date) {
        // Fresh readings only: stale numbers are kept for display, not for deciding that something happened.
        let fresh = providers.filter { $0.problem == nil }
        let result = UsageAlertEvaluator.evaluate(fresh, previous: alertState,
                                                  configuration: settings.usageAlertConfiguration, now: now)
        alertState = result.state
        guard settings.alertsForUsage, settings.isEnabled(.usage),
              let alert = UsageAlertPresenter.alert(for: result.events, providers: fresh, now: now)
        else { return }
        postAlert(alert)
    }

    // MARK: Snapshot and archive

    private func makeSnapshot(now: Date) -> UsageSnapshot {
        UsageSnapshot(deviceID: deviceID, deviceName: Self.deviceName, updatedAt: now, providers: providers)
    }

    /// A random id for this Mac, made once and kept in the defaults.
    var deviceID: String {
        if let stored = defaults.string(forKey: Self.deviceIDKey) { return stored }
        let made = UUID().uuidString
        defaults.set(made, forKey: Self.deviceIDKey)
        return made
    }

    static let deviceIDKey = "usageDeviceID"
    static let logCategory = "usage"

    /// "Xus's MacBook Pro", from System Settings › General › Sharing (no network lookup, unlike `Host`).
    nonisolated static var deviceName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "Mac"
    }

    private func loadArchive() {
        guard let archiveURL, let data = try? Data(contentsOf: archiveURL),
              let snapshot = try? UsageArchive.decoder.decode(UsageSnapshot.self, from: data),
              snapshot.schema == UsageSnapshot.schema
        else { return }
        self.snapshot = snapshot
        var restored: [UsageProviderID: ProviderUsage] = [:]
        for usage in snapshot.providers { restored[usage.id] = usage }
        readings = restored
        // Until the first refresh confirms them, the archived providers stand in for the catalog.
        entries = snapshot.providers.map {
            Entry(id: $0.id, displayName: $0.displayName, isAvailable: true, isExternal: false, usage: $0)
        }
    }

    private func saveArchive(_ snapshot: UsageSnapshot) {
        guard let archiveURL, let data = try? UsageArchive.encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: archiveURL, options: .atomic)
        } catch {
            SpikeLog.shared.record(Self.logCategory, "couldn't save usage.json: \(error.localizedDescription)")
        }
    }

    /// Fixed numbers, no collectors: tests and previews.
    func replaceReadings(with usage: [ProviderUsage], at date: Date) {
        entries = usage.map { Entry(id: $0.id, displayName: $0.displayName, isAvailable: true, isExternal: false, usage: $0) }
        readings = Dictionary(uniqueKeysWithValues: usage.map { ($0.id, $0) })
        lastAttempt = date
        hasChecked = true
    }
}

// MARK: - Time

/// The store's sense of time, injected so tests drive the 5-minute rhythm without waiting.
protocol UsageClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

struct SystemUsageClock: UsageClock {
    var now: Date { .now }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}

// MARK: - External source (OpenUsage-compatible)

/// Something that reports several providers at once: an OpenUsage-compatible app's local API. Only providers no
/// collector reads are asked for, and a missing app is simply no providers.
protocol UsageExternalSource: Sendable {
    func fetch(excluding known: Set<UsageProviderID>, previous: [ProviderUsage], now: Date) async -> [ProviderUsage]
}

enum UsageExternalSources {
    /// The local `openusage.limits.v1` API (127.0.0.1:6736), capped at 1 s and silent when nothing listens.
    static func standard() -> (any UsageExternalSource)? { OpenUsageLocalAPI() }
}

/// `OpenUsageCompatibleSource` (AltilloUsage), asked only for the providers Altillo's collectors don't read.
struct OpenUsageLocalAPI: UsageExternalSource {
    func fetch(excluding known: Set<UsageProviderID>, previous: [ProviderUsage], now: Date) async -> [ProviderUsage] {
        await OpenUsageCompatibleSource(excluding: known).fetch(now: now)
    }
}

// MARK: - Fetching (off the main actor)

enum UsageFetch {
    /// One collector's read, or its last numbers marked unreachable if it takes longer than `timeout`. Returns as
    /// soon as either happens: a collector that ignores cancellation can't hold up the batch.
    static func run(_ collector: any UsageCollector, previous: ProviderUsage?, now: Date, timeout: Duration,
                    clock: any UsageClock) async -> ProviderUsage {
        let fallback = timedOut(id: collector.providerID, name: collector.displayName, previous: previous, now: now)
        return await race(timeout: timeout, clock: clock, fallback: fallback) {
            await collector.fetch(previous: previous, now: now)
        }
    }

    static func runExternal(_ source: any UsageExternalSource, excluding known: Set<UsageProviderID>,
                            previous: [ProviderUsage], now: Date, timeout: Duration,
                            clock: any UsageClock) async -> [ProviderUsage] {
        await race(timeout: timeout, clock: clock, fallback: []) {
            await source.fetch(excluding: known, previous: previous, now: now)
        }
    }

    static func timedOut(id: UsageProviderID, name: String, previous: ProviderUsage?, now: Date) -> ProviderUsage {
        var usage = previous ?? ProviderUsage(id: id, displayName: name, plan: nil, windows: [], fetchedAt: now)
        usage.problem = .unreachable("timed out")
        return usage
    }

    private static func race<T: Sendable>(timeout: Duration, clock: any UsageClock, fallback: T,
                                          _ work: @escaping @Sendable () async -> T) async -> T {
        let once = ResumeOnce<T>()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            let job = Task { once.resume(await work()) }
            let timer = Task {
                do { try await clock.sleep(for: timeout) } catch { return }
                job.cancel()
                once.resume(fallback)
            }
            once.onResume = { timer.cancel() }
        }
    }
}

/// Resumes a continuation exactly once, whichever side gets there first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var pending: T?
    private var done = false
    private var cleanup: (@Sendable () -> Void)?

    var onResume: (@Sendable () -> Void)? {
        get { lock.withLock { cleanup } }
        set {
            let runNow = lock.withLock { () -> Bool in
                cleanup = newValue
                return done
            }
            if runNow { newValue?() }
        }
    }

    func set(_ continuation: CheckedContinuation<T, Never>) {
        let value: T? = lock.withLock {
            if let pending { self.pending = nil; return pending }
            self.continuation = continuation
            return nil
        }
        if let value { continuation.resume(returning: value) }
    }

    func resume(_ value: T) {
        let (target, after): (CheckedContinuation<T, Never>?, (@Sendable () -> Void)?) = lock.withLock {
            guard !done else { return (nil, nil) }
            done = true
            if let continuation {
                self.continuation = nil
                return (continuation, cleanup)
            }
            pending = value
            return (nil, cleanup)
        }
        target?.resume(returning: value)
        after?()
    }
}

// MARK: - Stale-while-revalidate (pure)

enum UsageMerge {
    /// A failed read keeps the last good numbers and when they were read; a good one replaces them.
    static func merge(_ fresh: ProviderUsage, previous: ProviderUsage?) -> ProviderUsage {
        guard fresh.problem != nil, let previous, !previous.windows.isEmpty else { return fresh }
        var kept = fresh
        if fresh.windows.isEmpty {
            kept.windows = previous.windows
            kept.balances = previous.balances
        }
        kept.plan = fresh.plan ?? previous.plan
        kept.fetchedAt = previous.fetchedAt
        return kept
    }
}

// MARK: - Archive

enum UsageArchive {
    /// Dates as plain numbers, so a round trip gives back exactly what was saved.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder { JSONDecoder() }
}
