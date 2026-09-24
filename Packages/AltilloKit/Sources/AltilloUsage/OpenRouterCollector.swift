import AltilloCore
import Foundation

// OpenRouter credits and key limit from OpenRouter's API, with the API key the user keeps for OpenRouter.
//
// Endpoints and mapping (independent /credits and /key, "both rejected" = invalid key) adapted from openusage (MIT),
// Sources/OpenUsage/Providers/OpenRouter/{OpenRouterAuthStore,OpenRouterUsageClient,OpenRouterUsageMapper,
// OpenRouterProvider}.swift @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

extension UsageProviderID {
    public static let openRouter = UsageProviderID(rawValue: "openrouter")
}

/// Reads OpenRouter's prepaid credits and, when the key has a spending limit, how much of it is used.
///
/// Windows: `key-limit` (daily → other, weekly → weekly, monthly → monthly, no reset → other). Balances: `credits`
/// (USD left of what was bought), `spend-today`, `spend-week`, `spend-month` (USD spent on this key).
public struct OpenRouterCollector: UsageCollector {
    public static let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
    public static let keyURL = URL(string: "https://openrouter.ai/api/v1/key")!

    public let providerID: UsageProviderID = .openRouter
    public let displayName = "OpenRouter"
    public var setupHint: String { "Add an OpenRouter API key to ~/.config/openrouter/key.json" }

    /// `~/.config/openrouter/key.json`, then `OPENROUTER_API_KEY` / `OPENROUTER_KEY`.
    public static func defaultKeySource(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> LocalAPIKeySource {
        LocalAPIKeySource(files: [LocalAPIKeySource.configFile("openrouter", environment: environment)],
                          environmentNames: ["OPENROUTER_API_KEY", "OPENROUTER_KEY"], environment: environment)
    }

    private let keySource: LocalAPIKeySource
    private let transport: any HTTPTransport

    public init(keySource: LocalAPIKeySource = OpenRouterCollector.defaultKeySource(),
                transport: any HTTPTransport = URLSessionTransport()) {
        self.keySource = keySource
        self.transport = transport
    }

    public func isAvailable() async -> Bool { keySource.key() != nil }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if Group1Support.isBackingOff(previous, now: now) { return previous! }
        guard let key = keySource.key() else {
            return failure(.notSignedIn, detail: "Add an OpenRouter API key to ~/.config/openrouter/key.json, "
                               + "or set OPENROUTER_API_KEY.", previous: previous, now: now)
        }

        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]
        async let creditsCall = Group1Support.send(Group1Support.request(Self.creditsURL, headers: headers),
                                                   transport: transport, now: now)
        async let keyCall = Group1Support.send(Group1Support.request(Self.keyURL, headers: headers),
                                               transport: transport, now: now)
        let (credits, keyInfo) = await (creditsCall, keyCall)

        // Each endpoint maps on its own: OpenRouter gates some endpoints by key type, so one 403 mustn't blank
        // out what the other returned.
        let creditsData = credits.object?["data"] as? [String: Any]
        let keyData = keyInfo.object?["data"] as? [String: Any]
        let mapped = OpenRouterUsageMapper.map(credits: creditsData, key: keyData, now: now)
        if !mapped.windows.isEmpty || !mapped.balances.isEmpty {
            return ProviderUsage(id: providerID, displayName: displayName, plan: mapped.plan, windows: mapped.windows,
                                 balances: mapped.balances, fetchedAt: now)
        }

        switch (credits, keyInfo) {
        case (.unauthorized, .unauthorized):
            return failure(.sessionExpired, detail: "OpenRouter rejected the API key. Check it at openrouter.ai/keys.",
                           previous: previous, now: now)
        case (.rateLimited(let until), _), (_, .rateLimited(let until)):
            return failure(.rateLimited(retryAfter: until), detail: nil, previous: previous, now: now)
        case (.failed(let reason), _), (_, .failed(let reason)):
            return failure(.unreachable(reason), detail: nil, previous: previous, now: now)
        case (.status(let code, _), _), (_, .status(let code, _)):
            return failure(.unreachable("HTTP \(code)"), detail: nil, previous: previous, now: now)
        default:
            return failure(.unexpectedResponse("OpenRouter response changed shape"), detail: nil, previous: previous,
                           now: now)
        }
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, now: Date)
        -> ProviderUsage {
        Group1Support.failure(problem, detail: detail, previous: previous, id: providerID, displayName: displayName,
                              plan: nil, now: now)
    }
}

/// Pure mapping of `GET /api/v1/credits` and `GET /api/v1/key` (both wrapped in `{"data": …}`).
enum OpenRouterUsageMapper {
    struct Mapped: Equatable {
        var plan: String?
        var windows: [UsageWindow]
        var balances: [UsageBalance]
    }

    static func map(credits: [String: Any]?, key: [String: Any]?, now: Date) -> Mapped {
        var windows: [UsageWindow] = []
        var balances: [UsageBalance] = []

        if let credits, let totalUsage = UsageParsing.number(credits["total_usage"]) {
            let used = max(0, totalUsage)
            let bought = max(0, UsageParsing.number(credits["total_credits"]) ?? 0)
            balances.append(UsageBalance(id: "credits", label: "Credits", remaining: max(0, bought - used), used: used,
                                         limit: bought > 0 ? bought : nil, unit: "USD"))
        }

        var plan: String?
        if let key {
            if let limit = UsageParsing.number(key["limit"]), limit > 0 {
                let remaining = max(0, UsageParsing.number(key["limit_remaining"]) ?? 0)
                let reset = UsageParsing.string(key["limit_reset"])?.lowercased()
                let (kind, resetsAt, duration) = limitWindow(reset, now: now)
                windows.append(UsageWindow(id: "key-limit", kind: kind, label: "Key limit",
                                           used: max(0, limit - remaining) / limit, resetsAt: resetsAt,
                                           duration: duration))
            }
            for (field, id, label) in [("usage_daily", "spend-today", "Today"), ("usage_weekly", "spend-week", "This week"),
                                       ("usage_monthly", "spend-month", "This month")] {
                if let amount = UsageParsing.number(key[field]) {
                    balances.append(UsageBalance(id: id, label: label, remaining: nil, used: max(0, amount), limit: nil,
                                                 unit: "USD"))
                }
            }
            if let free = key["is_free_tier"] as? Bool { plan = free ? "Free tier" : "Pay as you go" }
        }
        return Mapped(plan: plan, windows: windows, balances: balances)
    }

    /// OpenRouter resets key limits at 00:00 UTC: daily every day, weekly on Mondays, monthly on the 1st.
    static func limitWindow(_ reset: String?, now: Date) -> (UsageWindow.Kind, Date?, TimeInterval?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let startOfToday = calendar.startOfDay(for: now)
        switch reset {
        case "daily":
            return (.other, calendar.date(byAdding: .day, value: 1, to: startOfToday), 86400)
        case "weekly":
            let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0,
                                                                              weekday: 2),
                                         matchingPolicy: .nextTime)
            return (.weekly, next, 7 * 86400)
        case "monthly":
            let next = calendar.nextDate(after: now, matching: DateComponents(day: 1, hour: 0, minute: 0, second: 0),
                                         matchingPolicy: .nextTime)
            return (.monthly, next, Group1Support.monthDuration(endingAt: next))
        default:
            return (.other, nil, nil)
        }
    }
}
