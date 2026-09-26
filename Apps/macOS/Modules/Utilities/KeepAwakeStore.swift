import AppKit
import Foundation
import Observation

/// The explicit lengths offered by Keep Awake. Nothing here is persisted: reopening Altillo always starts asleep.
enum KeepAwakeDuration: String, CaseIterable, Identifiable, Sendable {
    case thirtyMinutes, oneHour, twoHours, untilStopped

    var id: Self { self }

    var interval: TimeInterval? {
        switch self {
        case .thirtyMinutes: 30 * 60
        case .oneHour: 60 * 60
        case .twoHours: 2 * 60 * 60
        case .untilStopped: nil
        }
    }

    var title: String {
        switch self {
        case .thirtyMinutes: String(localized: "30 minutes")
        case .oneHour: String(localized: "1 hour")
        case .twoHours: String(localized: "2 hours")
        case .untilStopped: String(localized: "Until I stop it")
        }
    }
}

/// Small seam around ProcessInfo so tests can prove that every assertion is balanced.
@MainActor
protocol KeepAwakeActivityBackend: AnyObject {
    func begin(reason: String) -> NSObjectProtocol
    func end(_ token: NSObjectProtocol)
}

@MainActor
final class ProcessInfoKeepAwakeBackend: KeepAwakeActivityBackend {
    func begin(reason: String) -> NSObjectProtocol {
        // Deliberately excludes `.idleDisplaySleepDisabled`: the screen may still turn off normally.
        ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: reason)
    }

    func end(_ token: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }
}

/// Owns Altillo's single Keep Awake assertion.
///
/// It is event-driven: one cancellable task sleeps until the chosen end date, while wake and clock-change
/// notifications recalculate that boundary. An active session is intentionally never written to disk.
@MainActor
@Observable
final class KeepAwakeStore {
    private(set) var duration: KeepAwakeDuration?
    private(set) var endsAt: Date?
    private(set) var clock = Date.now

    var isActive: Bool { token != nil }

    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored var sleep: @Sendable (Duration) async throws -> Void = { duration in
        try await Task.sleep(for: duration)
    }

    @ObservationIgnored private let backend: any KeepAwakeActivityBackend
    @ObservationIgnored private var token: NSObjectProtocol?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var isStarted = false

    init(backend: any KeepAwakeActivityBackend = ProcessInfoKeepAwakeBackend()) {
        self.backend = backend
    }

    /// Starts lifecycle observation, never an assertion. Safe to call more than once.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        let recompute: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            (workspace, workspace.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: recompute
            )),
            (center, center.addObserver(
                forName: .NSSystemClockDidChange, object: nil, queue: .main, using: recompute
            )),
        ]
        clock = now()
    }

    /// Releases everything owned by the store. Called during normal app termination.
    func stop() {
        end()
        guard isStarted else { return }
        isStarted = false
        observers.forEach { center, observer in center.removeObserver(observer) }
        observers.removeAll()
    }

    /// Begins or retimes the one assertion. Retiming an active session never creates a second assertion.
    func begin(_ duration: KeepAwakeDuration) {
        let moment = now()
        clock = moment
        self.duration = duration
        endsAt = duration.interval.map { moment.addingTimeInterval($0) }
        if token == nil {
            token = backend.begin(reason: "Keep Awake is active in Altillo")
        }
        schedule(from: moment)
    }

    /// Called from section settings. Enabling stays inert; disabling is an immediate explicit stop.
    func setModuleEnabled(_ enabled: Bool) {
        if !enabled { end() }
    }

    /// Ends the current session. Idempotent, so every shutdown path can call it safely.
    func end() {
        expiryTask?.cancel()
        expiryTask = nil
        if let token {
            backend.end(token)
            self.token = nil
        }
        duration = nil
        endsAt = nil
    }

    /// Recomputes from the absolute date after sleep or a system clock change.
    func wake() {
        let moment = now()
        clock = moment
        guard isActive else { return }
        guard let endsAt else {
            expiryTask?.cancel()
            expiryTask = nil
            return
        }
        guard endsAt > moment else {
            end()
            return
        }
        schedule(from: moment)
    }

    private func schedule(from moment: Date) {
        expiryTask?.cancel()
        expiryTask = nil
        guard isActive, let endsAt else { return }
        let delay = max(0.05, endsAt.timeIntervalSince(moment))
        expiryTask = Task { [weak self, sleep] in
            try? await sleep(.seconds(delay))
            guard !Task.isCancelled else { return }
            self?.wake()
        }
    }
}
