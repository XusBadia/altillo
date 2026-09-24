import AltilloCore
import Foundation

// Optional source "compatible with OpenUsage" (PLAN §5.2): if an app serving the `openusage.limits.v1` local API is
// running (the OpenUsage app does, on 127.0.0.1:6736), Altillo can show the providers it doesn't read natively.
// Branding: never present this source under the name "OpenUsage"; only "compatible with OpenUsage".

/// Reads providers from a local `openusage.limits.v1` API. Cheap when nothing listens: a refused connection fails
/// immediately and the whole request is capped at 1 s.
public struct OpenUsageCompatibleSource: Sendable {
    public static let defaultURL = URL(string: "http://127.0.0.1:6736/v1/limits")!
    public static let schema = "openusage.limits.v1"
    /// User-facing name for settings.
    public static let displayName = "Local usage API (compatible with OpenUsage)"

    public let url: URL
    /// Providers read natively are skipped (their native numbers win).
    public let excluded: Set<UsageProviderID>
    private let transport: any HTTPTransport
    private let timeout: TimeInterval

    public init(url: URL = OpenUsageCompatibleSource.defaultURL,
                excluding excluded: Set<UsageProviderID> = [.claude, .codex],
                transport: any HTTPTransport = URLSessionTransport(),
                timeout: TimeInterval = 1) {
        self.url = url
        self.excluded = excluded
        self.transport = transport
        self.timeout = timeout
    }

    /// Whether something answers with the expected schema right now.
    public func isAvailable() async -> Bool {
        await read(now: .now) != nil
    }

    /// Providers from the local API, minus `excluded`. Empty when nothing listens or the answer isn't the schema.
    public func fetch(now: Date = .now) async -> [ProviderUsage] {
        await read(now: now) ?? []
    }

    /// Nil when unavailable; otherwise the (possibly empty) provider list.
    func read(now: Date) async -> [ProviderUsage]? {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Altillo", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await transport.send(request), (200..<300).contains(response.statusCode)
        else { return nil }
        return OpenUsageLimitsMapper.map(data, excluding: excluded, now: now)
    }
}

/// Pure mapping of `openusage.limits.v1`.
enum OpenUsageLimitsMapper {
    static func map(_ data: Data, excluding excluded: Set<UsageProviderID>, now: Date) -> [ProviderUsage]? {
        guard let body = UsageParsing.object(data), body["schema"] as? String == OpenUsageCompatibleSource.schema,
              let providers = body["providers"] as? [String: Any] else { return nil }

        var errors: [String: String] = [:]
        for entry in (body["errors"] as? [Any]) ?? [] {
            guard let object = entry as? [String: Any],
                  let id = UsageParsing.string(object["provider"]) ?? UsageParsing.string(object["providerId"])
            else { continue }
            errors[id] = UsageParsing.string(object["message"]) ?? UsageParsing.string(object["error"]) ?? "Error"
        }

        var result: [ProviderUsage] = []
        for (rawID, value) in providers.sorted(by: { $0.key < $1.key }) {
            let id = UsageProviderID(rawValue: rawID)
            guard !excluded.contains(id), let provider = value as? [String: Any] else { continue }
            var windows: [UsageWindow] = []
            var balances: [UsageBalance] = []
            let resources = (provider["resources"] as? [String: Any]) ?? [:]
            for (key, raw) in resources.sorted(by: { $0.key < $1.key }) {
                guard let resource = raw as? [String: Any] else { continue }
                switch resource["kind"] as? String {
                case "consumption":
                    if let window = window(key: key, resource) {
                        windows.append(window)
                    } else if let balance = balance(key: key, resource) {
                        balances.append(balance)
                    }
                case "balance":
                    if let balance = balance(key: key, resource) { balances.append(balance) }
                default:
                    continue
                }
            }
            var usage = ProviderUsage(
                id: id,
                displayName: UsageParsing.string(provider["displayName"]) ?? UsageParsing.titleCased(rawID),
                plan: UsageParsing.string(provider["plan"]),
                windows: windows.sortedForDisplay(),
                balances: balances,
                fetchedAt: UsageParsing.date(provider["fetchedAt"]) ?? now
            )
            if let message = errors[rawID] {
                usage.problem = .unreachable(message)
            }
            result.append(usage)
        }
        return result
    }

    /// A consumption resource with a usable fraction becomes a window.
    private static func window(key: String, _ resource: [String: Any]) -> UsageWindow? {
        let used: Double
        if let utilization = UsageParsing.number(resource["utilization"]) {
            used = utilization
        } else if let value = UsageParsing.number(resource["used"]), let limit = UsageParsing.number(resource["limit"]),
                  limit > 0 {
            used = value / limit
        } else {
            return nil
        }
        let seconds = UsageParsing.number(resource["windowSeconds"])
        let resetsAt = UsageParsing.date(resource["resetsAt"])
        let kind: UsageWindow.Kind
        let label: String
        switch key {
        case "session":
            (kind, label) = (.session, "Session")
        case "weekly":
            (kind, label) = (.weekly, "Week")
        case "monthly":
            (kind, label) = (.monthly, "Month")
        default:
            let name = UsageParsing.titleCased(key)
            if let seconds, seconds >= 27 * 86400 {
                (kind, label) = (.monthly, "\(name) month")
            } else if let seconds, seconds >= 6 * 86400 {
                (kind, label) = (.modelWeekly, "\(name) week")
            } else {
                (kind, label) = (.other, name)
            }
        }
        let id = switch kind {
        case .modelWeekly: "weekly-\(UsageParsing.slug(key))"
        default: key
        }
        return UsageWindow(id: id, kind: kind, label: label, used: used, resetsAt: resetsAt, duration: seconds)
    }

    private static let balanceLabels = ["credits": "Credits", "creditValue": "Credit value",
                                        "rateLimitResets": "Limit resets", "spend": "Spend"]
    private static let unitNames = ["usd": "USD", "percent": "%"]

    private static func balance(key: String, _ resource: [String: Any]) -> UsageBalance? {
        let remaining = UsageParsing.number(resource["available"]) ?? UsageParsing.number(resource["remaining"])
        let used = UsageParsing.number(resource["used"])
        let limit = UsageParsing.number(resource["limit"])
        guard remaining != nil || used != nil else { return nil }
        let unit = UsageParsing.string(resource["unit"]) ?? ""
        return UsageBalance(id: key, label: balanceLabels[key] ?? UsageParsing.titleCased(key), remaining: remaining,
                            used: used, limit: limit, unit: unitNames[unit.lowercased()] ?? unit)
    }
}
