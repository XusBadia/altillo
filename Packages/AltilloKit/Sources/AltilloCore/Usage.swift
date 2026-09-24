import Foundation

// Shared AI-usage model (PLAN §5.2). Collectors (AltilloUsage, macOS) produce it, the notch and Ask read it, and
// later CloudKit carries it to iOS, so everything here is plain Codable/Sendable data with no platform code.

/// A provider Altillo knows how to read. Raw values are stable (persisted, synced, used in settings).
public struct UsageProviderID: RawRepresentable, Hashable, Codable, Sendable, Comparable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let claude = UsageProviderID(rawValue: "claude")
    public static let codex = UsageProviderID(rawValue: "codex")

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One limit that fills up and resets: the 5-hour session, the week, a per-model week, a monthly quota.
public struct UsageWindow: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case session, weekly, modelWeekly, monthly, other
    }

    /// Stable id within its provider ("session", "weekly", "weekly-sonnet").
    public var id: String
    public var kind: Kind
    /// Short human label ("Session", "Week", "Sonnet week"), already localized by the collector's caller if needed.
    public var label: String
    /// 0…1 (can exceed 1 when over the limit).
    public var used: Double
    /// When it refills. Nil when the window hasn't started (Claude's session before the first message).
    public var resetsAt: Date?
    /// Length of the window, when known (5 h, 7 d…). Needed for pace.
    public var duration: TimeInterval?

    public init(id: String, kind: Kind, label: String, used: Double, resetsAt: Date?, duration: TimeInterval?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.used = used
        self.resetsAt = resetsAt
        self.duration = duration
    }

    /// Fraction of the window already elapsed: what an even pace would have used by now. Nil without both
    /// `resetsAt` and `duration`.
    public func elapsedFraction(now: Date = .now) -> Double? {
        guard let resetsAt, let duration, duration > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        return min(max(1 - remaining / duration, 0), 1)
    }
}

/// A balance that doesn't reset on a timer: prepaid credits, extra usage, dollars left.
public struct UsageBalance: Hashable, Codable, Sendable {
    public var id: String
    public var label: String
    /// Remaining amount in `unit`.
    public var remaining: Double?
    /// Spent amount in `unit`.
    public var used: Double?
    public var limit: Double?
    /// "USD", "credits"…
    public var unit: String

    public init(id: String, label: String, remaining: Double?, used: Double?, limit: Double?, unit: String) {
        self.id = id
        self.label = label
        self.remaining = remaining
        self.used = used
        self.limit = limit
        self.unit = unit
    }
}

/// Why a provider has no fresh numbers. Every case must be explainable to the user in one sentence.
public enum UsageProblem: Hashable, Codable, Sendable {
    /// The CLI isn't installed or never signed in.
    case notSignedIn
    /// The token expired and Altillo never refreshes it: using the CLI once refreshes it.
    case sessionExpired
    /// The provider asked us to slow down; the last numbers are kept until `retryAfter`.
    case rateLimited(retryAfter: Date?)
    /// Network or server trouble; the last numbers are kept.
    case unreachable(String)
    /// The response changed shape (the endpoints are private).
    case unexpectedResponse(String)
    /// Access to the credential was refused (e.g. keychain prompt denied).
    case accessDenied
}

/// Everything known about one provider at one moment.
public struct ProviderUsage: Identifiable, Hashable, Codable, Sendable {
    public var id: UsageProviderID
    /// "Claude", "Codex".
    public var displayName: String
    /// "Max 20x", "Pro", "Plus" — nil when unknown.
    public var plan: String?
    /// Session first, then weekly, then the rest.
    public var windows: [UsageWindow]
    public var balances: [UsageBalance]
    /// When these numbers were read from the provider.
    public var fetchedAt: Date
    /// Set when the latest attempt failed; `windows` then hold the last good numbers (if any).
    public var problem: UsageProblem?
    /// Optional one-sentence English explanation of `problem` from the collector (e.g. why a sign-in can't read
    /// usage). Views may show it as secondary text; they should not parse it.
    public var problemDetail: String?

    public init(id: UsageProviderID, displayName: String, plan: String?, windows: [UsageWindow],
                balances: [UsageBalance] = [], fetchedAt: Date, problem: UsageProblem? = nil,
                problemDetail: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.plan = plan
        self.windows = windows
        self.balances = balances
        self.fetchedAt = fetchedAt
        self.problem = problem
        self.problemDetail = problemDetail
    }

    public var session: UsageWindow? { windows.first { $0.kind == .session } }
    public var weekly: UsageWindow? { windows.first { $0.kind == .weekly } }

    /// The window that matters most right now: the fullest of session and week.
    public var headline: UsageWindow? {
        [session, weekly].compactMap { $0 }.max { $0.used < $1.used } ?? windows.first
    }

    /// Older than `limit` (default 15 min: three missed refreshes) means the view should say "stale".
    public func isStale(now: Date = .now, limit: TimeInterval = 15 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) > limit
    }
}

/// One Mac's view of all its providers. The unit synced to other devices (phase 5).
public struct UsageSnapshot: Hashable, Codable, Sendable {
    public static let schema = "altillo.usage.v1"

    public var schema: String
    public var deviceID: String
    public var deviceName: String
    public var updatedAt: Date
    public var providers: [ProviderUsage]

    public init(deviceID: String, deviceName: String, updatedAt: Date, providers: [ProviderUsage]) {
        schema = Self.schema
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.providers = providers
    }
}

// MARK: - Pace

/// How a window is being spent relative to an even pace (adapted from openusage's Pace, MIT).
public enum UsagePace: Hashable, Sendable {
    /// Plenty left at this rate.
    case ahead
    /// On track to finish close to the limit; `spare` is the projected unused fraction.
    case onTrack(spare: Double)
    /// Will run out before the reset, at `runsOutAt`.
    case behind(runsOutAt: Date?)
    /// Not enough elapsed (or used) to say anything.
    case unknown

    /// Projects the current rate to the end of the window.
    public static func evaluate(_ window: UsageWindow, now: Date = .now) -> UsagePace {
        guard let resetsAt = window.resetsAt, let duration = window.duration, duration > 0, now < resetsAt else {
            return .unknown
        }
        let elapsed = duration - resetsAt.timeIntervalSince(now)
        guard elapsed >= max(60, duration * 0.01) else { return .unknown }
        if window.used >= 1 { return .behind(runsOutAt: nil) }
        guard window.used >= 0.05 else { return .ahead }
        let projected = window.used / elapsed * duration
        if projected <= 0.9 { return .ahead }
        if projected <= 1 { return .onTrack(spare: 1 - projected) }
        let rate = window.used / elapsed
        let runsOut = now.addingTimeInterval((1 - window.used) / rate)
        return .behind(runsOutAt: runsOut < resetsAt ? runsOut : nil)
    }
}
