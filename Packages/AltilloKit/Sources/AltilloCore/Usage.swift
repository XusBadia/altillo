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
    /// Length of the window, when known (5 h, 7 d…).
    public var duration: TimeInterval?

    public init(id: String, kind: Kind, label: String, used: Double, resetsAt: Date?, duration: TimeInterval?) {
        self.id = id
        self.kind = kind
        self.label = label
        self.used = used
        self.resetsAt = resetsAt
        self.duration = duration
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
    /// When these numbers were read from the provider.
    public var fetchedAt: Date
    /// Set when the latest attempt failed; `windows` then hold the last good numbers (if any).
    public var problem: UsageProblem?
    /// Optional one-sentence English explanation of `problem` from the collector (e.g. why a sign-in can't read
    /// usage). Views may show it as secondary text; they should not parse it.
    public var problemDetail: String?

    public init(id: UsageProviderID, displayName: String, plan: String?, windows: [UsageWindow],
                fetchedAt: Date, problem: UsageProblem? = nil,
                problemDetail: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.plan = plan
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.problem = problem
        self.problemDetail = problemDetail
    }

    public var session: UsageWindow? { windows.first { $0.kind == .session } }
    public var weekly: UsageWindow? { windows.first { $0.kind == .weekly } }

    /// The window that matters most right now: the fullest of session and week; for providers without either
    /// (a monthly quota, request counts…), the fullest window they have. On a tie, the one listed first.
    public var headline: UsageWindow? {
        let short = [session, weekly].compactMap { $0 }
        if !short.isEmpty { return Self.fullest(short) }
        // No session or week (a monthly plan, a request quota): the provider's main limit, which collectors list
        // first, rather than a side pool that happens to be fuller (Cursor's "Grok Bot").
        return windows.first { $0.kind != .other } ?? windows.first
    }

    private static func fullest(_ windows: [UsageWindow]) -> UsageWindow? {
        windows.reduce(nil) { best, window in
            guard let best else { return window }
            return window.used > best.used ? window : best
        }
    }

    /// Older than `limit` (default 15 min: three missed refreshes) means the view should say "stale".
    public func isStale(now: Date = .now, limit: TimeInterval = 15 * 60) -> Bool {
        now.timeIntervalSince(fetchedAt) > limit
    }
}

/// One Mac's view of all its providers. The unit synced to other devices (phase 5).
public struct UsageSnapshot: Hashable, Codable, Sendable {
    public static let schema = "altillo.usage.v2"

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
