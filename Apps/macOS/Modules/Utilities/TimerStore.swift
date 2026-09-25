import AppKit
import Foundation
import Observation

/// The «Temporizador» section (phase 12): kitchen timers that peek when they ring.
///
/// Event-driven, never polling (PLAN §1.5): the store sleeps until the next moment something changes on its own
/// (a timer entering its last minute, ringing, or leaving the contextual ear, `TimerLogic.nextBoundary`) and wakes
/// once for it. Running timers keep only their absolute end date, so waking from sleep, a relaunch or a clock
/// change just recomputes from it. The countdown on screen ticks in the views (`TimelineView`), only while visible.
///
/// Running timers are kept in Application Support (`timers.json`) and survive relaunches. A timer that went off
/// while Altillo wasn't running (or the Mac slept) still peeks if it's recent (`TimerLogic.lateRingWindow`).
@MainActor
@Observable
final class TimerStore {
    /// Every timer, in the order they were set (`TimerLogic.ordered` sorts them for display).
    private(set) var timers: [KitchenTimer] = []
    /// What the dial is set to for the next timer, in whole minutes.
    var draftMinutes = 5
    /// "Now" as of the last wake: the contextual ear re-reads the timers exactly when it changes.
    private(set) var clock = Date.now
    /// Bumped each time a timer rings: the open section shakes its dial.
    private(set) var ringCount = 0
    /// The timer that rang last (the open section brings it onto the dial).
    private(set) var lastRungID: UUID?
    /// Set by the view while its name field has focus: typing keeps the notch open.
    var isEditingName = false

    /// While the user types a timer's name, the notch doesn't close when the pointer wanders off.
    var holdsOpen: Bool { isEditingName }

    /// Shows a peek while the notch is idle. Wired by `NotchCoordinator`.
    @ObservationIgnored var postAlert: (NotchAlert) -> Void = { _ in }
    /// Plays the ring. Tests replace it.
    @ObservationIgnored var playSound: () -> Void = { TimerStore.playRing() }
    /// Whether the ring makes a sound (Settings, and the bell in the section).
    @ObservationIgnored var soundEnabled: () -> Bool = { AltilloSettings.shared.timerSound }
    /// Injected so tests control "now".
    @ObservationIgnored var now: () -> Date = { .now }
    /// Where running timers are kept across launches; nil keeps them in memory only (tests).
    @ObservationIgnored let storeURL: URL?

    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var didRestore = false

    init(storeURL: URL? = URL.applicationSupportDirectory.appending(path: "Altillo/timers.json")) {
        self.storeURL = storeURL
    }

    // MARK: - Lifecycle

    /// Restores the timers and sleeps until the next one needs anything. Idempotent. Called by the coordinator at
    /// launch, so a timer rings with the notch closed and after a relaunch.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        restore()
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let recompute: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        // Sleeping stretches or skips the wait; a clock change moves "now". Both: recompute from the end dates.
        observers = [
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recompute),
            center.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recompute),
        ]
        wake()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        wakeTask?.cancel()
        wakeTask = nil
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
    }

    // MARK: - Reading

    /// Running first (soonest to ring), then paused, then the ones that rang.
    var ordered: [KitchenTimer] { TimerLogic.ordered(timers, now: clock) }

    func timer(_ id: UUID) -> KitchenTimer? { timers.first { $0.id == id } }

    /// What the contextual ear says (`NotchActivity.timer`), as of the last wake.
    var contextualSignal: TimerSignal? { TimerLogic.signal(timers, now: clock) }

    // MARK: - Acting

    /// Starts a timer. Ask's timers are marked so the notch can undo them. A second identical request within a few
    /// seconds (the model calling its tool twice) returns the first timer instead of setting another.
    @discardableResult
    func start(seconds: TimeInterval, label: String = "", origin: KitchenTimer.Origin = .user) -> KitchenTimer {
        let moment = now()
        let duration = min(max(seconds.rounded(), 1), TimerLogic.maximumDuration)
        let label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if origin == .ask, let twin = timers.last(where: {
            $0.origin == .ask && $0.label == label && $0.duration == duration && $0.isRunning
                && moment.timeIntervalSince($0.createdAt) < 5
        }) {
            return twin
        }
        let timer = KitchenTimer(label: label, duration: duration,
                                 state: .running(endsAt: moment.addingTimeInterval(duration)),
                                 origin: origin, createdAt: moment)
        timers.append(timer)
        changed()
        return timer
    }

    /// Starts a timer from the dial.
    @discardableResult
    func startDraft(label: String = "") -> KitchenTimer? {
        guard draftMinutes > 0 else { return nil }
        return start(seconds: TimeInterval(draftMinutes * 60), label: label)
    }

    func pause(_ id: UUID) {
        update(id) { timer, moment in
            guard case let .running(endsAt) = timer.state else { return }
            timer.state = .paused(remaining: max(1, endsAt.timeIntervalSince(moment)))
        }
    }

    func resume(_ id: UUID) {
        update(id) { timer, moment in
            guard case let .paused(remaining) = timer.state else { return }
            timer.state = .running(endsAt: moment.addingTimeInterval(remaining))
        }
    }

    func toggle(_ id: UUID) {
        guard let timer = timer(id) else { return }
        timer.isRunning ? pause(id) : resume(id)
    }

    /// Back to its full time, stopped, like turning a kitchen timer back to where it was set.
    func reset(_ id: UUID) {
        update(id) { timer, _ in timer.state = .paused(remaining: timer.duration) }
    }

    /// Runs a timer that rang (or any timer) again from its full time.
    func restart(_ id: UUID) {
        update(id) { timer, moment in timer.state = .running(endsAt: moment.addingTimeInterval(timer.duration)) }
    }

    func remove(_ id: UUID) {
        guard timers.contains(where: { $0.id == id }) else { return }
        timers.removeAll { $0.id == id }
        changed()
    }

    /// Clears every timer that already rang.
    func clearRung() {
        guard timers.contains(where: \.hasRung) else { return }
        timers.removeAll(where: \.hasRung)
        changed()
    }

    /// Ask's most recent timer still running or paused, for the notch's "Undo".
    var lastAskTimer: KitchenTimer? {
        timers.last { $0.origin == .ask && !$0.hasRung }
    }

    /// Undoes what Ask did: the timer it set goes away.
    func undoAsk(_ id: UUID) {
        guard timer(id)?.origin == .ask else { return }
        remove(id)
    }

    /// The timer stays, but it's the user's now (no more "Set by Ask · Undo").
    func keep(_ id: UUID) {
        update(id) { timer, _ in timer.origin = .user }
    }

    // MARK: - Waking

    /// Rings whatever is due, then sleeps until the next boundary. Called at launch, after every change, from the
    /// scheduled wake, on waking from sleep and when the clock changes.
    func wake() {
        let moment = now()
        clock = moment
        let due = TimerLogic.due(timers, now: moment)
        if !due.isEmpty {
            for timer in due {
                guard let index = timers.firstIndex(where: { $0.id == timer.id }) else { continue }
                let endsAt = timer.endsAt ?? moment
                timers[index].state = .rang(at: endsAt)
                // Late by more than a few seconds: it went off while the Mac slept. Still worth a peek if recent.
                let lateness = moment.timeIntervalSince(endsAt)
                if lateness <= TimerLogic.lateRingWindow { announce(timers[index], lateBy: lateness) }
            }
            persist()
        }
        schedule(from: moment)
    }

    private func schedule(from moment: Date) {
        wakeTask?.cancel()
        wakeTask = nil
        guard isStarted, let boundary = TimerLogic.nextBoundary(timers, now: moment) else { return }
        let delay = max(0.05, boundary.timeIntervalSince(moment))
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.wake()
        }
    }

    private func announce(_ timer: KitchenTimer, lateBy lateness: TimeInterval) {
        ringCount += 1
        lastRungID = timer.id
        if soundEnabled() { playSound() }
        let title = timer.label.isEmpty
            ? String(localized: "Time's up")
            : String(localized: "\(timer.label): time's up")
        let detail: String? = lateness > 5
            ? String(localized: "at \(timer.rangAt?.formatted(date: .omitted, time: .shortened) ?? "")")
            : nil
        postAlert(NotchAlert(
            source: .timer, symbol: "timer", title: title, detail: detail,
            trailing: TimerFormat.duration(timer.duration), isUrgent: true, module: .timer,
            duration: .seconds(8)
        ))
    }

    /// A soft, short ring.
    static func playRing() {
        guard let sound = NSSound(named: NSSound.Name("Glass"))?.copy() as? NSSound else { return }
        sound.volume = 0.7
        sound.play()
    }

    // MARK: - Changes and persistence

    private func update(_ id: UUID, _ change: (inout KitchenTimer, Date) -> Void) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        let before = timers[index]
        change(&timers[index], now())
        guard timers[index] != before else { return }
        changed()
    }

    private func changed() {
        persist()
        let moment = now()
        clock = moment
        schedule(from: moment)
    }

    private struct Snapshot: Codable {
        var version = 1
        var timers: [KitchenTimer]
    }

    private func persist() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Snapshot(timers: timers))
            try data.write(to: storeURL, options: .atomic)
        } catch {
            SpikeLog.shared.record("utilities", "timers: couldn't save (\(error.localizedDescription))")
        }
    }

    /// Reads the timers kept by the last run (once), dropping ones that rang long ago.
    func restore() {
        guard !didRestore else { return }
        didRestore = true
        guard let storeURL, let data = try? Data(contentsOf: storeURL),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        let moment = now()
        let kept = snapshot.timers.filter { timer in
            guard let rangAt = timer.rangAt else { return true }
            return moment.timeIntervalSince(rangAt) < TimerLogic.staleRungAge
        }
        // Timers set in this run before the restore (none, in practice) win over stored twins.
        timers = kept.filter { stored in !timers.contains { $0.id == stored.id } } + timers
    }
}
