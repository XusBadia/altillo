import Foundation

// Usage alerts: pure edge detection over successive `ProviderUsage` readings. The app turns the returned events into
// notch alerts; this file knows nothing about UI or notifications.
//
// Adapted from openusage (https://github.com/robinebers/openusage, MIT, © 2026 Robin Ebers):
// `MobileQuotaNotificationEvaluator` (thresholds, limit reached, baseline, once per window, highest crossed only)
// and `PaceNotificationLogic` (reset-jitter tolerance, "will run out" edge). See ThirdPartyNotices/README.md.

/// Which alerts to raise. Plain data so the app can persist it with the user's settings.
public struct UsageAlertConfiguration: Hashable, Codable, Sendable {
    /// Percent-used thresholds (1…99). Default 80 and 95.
    public var thresholds: [Int]
    /// Alert when a window hits 100 %.
    public var limitReached: Bool
    /// Alert when a window that had reached a threshold refills.
    public var refilled: Bool
    /// Alert when the current pace runs out before the reset.
    public var runningOutEarly: Bool

    public init(thresholds: [Int] = [80, 95], limitReached: Bool = true, refilled: Bool = true,
                runningOutEarly: Bool = true) {
        self.thresholds = thresholds
        self.limitReached = limitReached
        self.refilled = refilled
        self.runningOutEarly = runningOutEarly
    }

    public static let `default` = UsageAlertConfiguration()

    fileprivate var validThresholds: Set<Int> { Set(thresholds.filter { (1...99).contains($0) }) }
}

/// One thing worth telling the user about.
public struct UsageAlertEvent: Hashable, Codable, Sendable {
    public enum Kind: Hashable, Codable, Sendable {
        /// Usage crossed this percent (the highest crossed threshold when several were crossed at once).
        case threshold(Int)
        /// The window is used up.
        case limitReached
        /// A window that had reached an alert threshold (or its limit) started over.
        case refilled
        /// At the current rate the window runs out at `runsOutAt`, before it resets.
        case runningOutEarly(runsOutAt: Date)
    }

    public var provider: UsageProviderID
    public var providerName: String
    /// `UsageWindow.id`.
    public var windowID: String
    public var windowLabel: String
    public var kind: Kind

    public init(provider: UsageProviderID, providerName: String, windowID: String, windowLabel: String, kind: Kind) {
        self.provider = provider
        self.providerName = providerName
        self.windowID = windowID
        self.windowLabel = windowLabel
        self.kind = kind
    }
}

/// What the evaluator remembers between readings. Persist it (it's Codable) so a relaunch doesn't re-alert.
public struct UsageAlertState: Hashable, Codable, Sendable {
    public struct Observation: Hashable, Codable, Sendable {
        public var resetsAt: Date?
        public var used: Double
        /// Thresholds already alerted (or already passed at baseline) in this window.
        public var deliveredThresholds: Set<Int>
        /// Thresholds that were configured last time, so newly enabled ones already passed don't fire late.
        public var configuredThresholds: Set<Int>
        public var limitReachedDelivered: Bool
        public var runningOutDelivered: Bool
    }

    /// Keyed by "provider|window".
    public var observations: [String: Observation]

    public init(observations: [String: Observation] = [:]) {
        self.observations = observations
    }
}

/// Pure alert logic. Rules:
/// - The first observation of a window is a baseline: recorded, never fired (no alert storm at launch).
/// - Each threshold, "limit reached" and "running out early" fire at most once per window.
/// - A new window is detected when `resetsAt` moves later by more than 1 s (providers jitter by milliseconds), when
///   usage drops by at least 0.5, or when the previous reset time has passed and the provider reports none yet
///   (Claude's session before the next first message). It re-arms everything and may fire `refilled`.
/// - A reading that jumps across several thresholds fires only the highest; reaching 100 % fires `limitReached`
///   instead of any threshold.
/// - Providers with a `problem` keep their previous observations untouched: their numbers aren't fresh.
public enum UsageAlertEvaluator {
    public static let resetJitterTolerance: TimeInterval = 1
    public static let inferredResetDrop: Double = 0.5

    public struct Result: Hashable, Sendable {
        public var events: [UsageAlertEvent]
        public var state: UsageAlertState
    }

    public static func evaluate(_ providers: [ProviderUsage], previous: UsageAlertState,
                                configuration: UsageAlertConfiguration = .default, now: Date = .now) -> Result {
        var events: [UsageAlertEvent] = []
        var next = UsageAlertState()
        let thresholds = configuration.validThresholds

        for provider in providers {
            if provider.problem != nil {
                // Stale numbers: carry this provider's memory forward unchanged.
                let prefix = "\(provider.id.rawValue)|"
                for (key, value) in previous.observations where key.hasPrefix(prefix) {
                    next.observations[key] = value
                }
                continue
            }
            for window in provider.windows {
                let key = "\(provider.id.rawValue)|\(window.id)"
                let pace = UsagePace.evaluate(window, now: now)
                func event(_ kind: UsageAlertEvent.Kind) -> UsageAlertEvent {
                    UsageAlertEvent(provider: provider.id, providerName: provider.displayName, windowID: window.id,
                                    windowLabel: window.label, kind: kind)
                }

                guard var observation = previous.observations[key] else {
                    next.observations[key] = baseline(window, pace: pace, thresholds: thresholds)
                    continue
                }

                if isNewWindow(window, previous: observation, now: now) {
                    let hadAlerted = observation.limitReachedDelivered
                        || thresholds.contains { observation.used >= Double($0) / 100 }
                    if configuration.refilled, hadAlerted, window.used < observation.used {
                        events.append(event(.refilled))
                    }
                    // Like the first reading, the first reading of a new window is a baseline.
                    next.observations[key] = baseline(window, pace: pace, thresholds: thresholds)
                    continue
                }

                // Thresholds switched on while already above them count as delivered.
                let newlyConfigured = thresholds.subtracting(observation.configuredThresholds)
                observation.deliveredThresholds.formUnion(newlyConfigured.filter { window.used >= Double($0) / 100 })

                let crossed = thresholds.filter {
                    !observation.deliveredThresholds.contains($0) && window.used >= Double($0) / 100
                }
                if window.used >= 1, !observation.limitReachedDelivered {
                    if configuration.limitReached { events.append(event(.limitReached)) }
                    observation.limitReachedDelivered = true
                    observation.deliveredThresholds.formUnion(crossed)
                } else if let highest = crossed.max() {
                    events.append(event(.threshold(highest)))
                    observation.deliveredThresholds.formUnion(crossed)
                }

                if case .behind(let runsOutAt?) = pace, window.used < 1, !observation.runningOutDelivered {
                    if configuration.runningOutEarly { events.append(event(.runningOutEarly(runsOutAt: runsOutAt))) }
                    observation.runningOutDelivered = true
                }

                observation.configuredThresholds = thresholds
                observation.resetsAt = window.resetsAt ?? observation.resetsAt
                observation.used = window.used
                next.observations[key] = observation
            }
        }
        return Result(events: events, state: next)
    }

    static func isNewWindow(_ window: UsageWindow, previous: UsageAlertState.Observation, now: Date) -> Bool {
        if let current = window.resetsAt, let old = previous.resetsAt,
           current.timeIntervalSince(old) > resetJitterTolerance {
            return true
        }
        if previous.used - window.used >= inferredResetDrop { return true }
        if window.resetsAt == nil, let old = previous.resetsAt, old <= now, window.used < previous.used {
            return true
        }
        return false
    }

    private static func baseline(_ window: UsageWindow, pace: UsagePace, thresholds: Set<Int>)
        -> UsageAlertState.Observation {
        var runningOut = false
        if case .behind = pace { runningOut = true }
        return UsageAlertState.Observation(
            resetsAt: window.resetsAt,
            used: window.used,
            deliveredThresholds: thresholds.filter { window.used >= Double($0) / 100 },
            configuredThresholds: thresholds,
            limitReachedDelivered: window.used >= 1,
            runningOutDelivered: runningOut
        )
    }
}
