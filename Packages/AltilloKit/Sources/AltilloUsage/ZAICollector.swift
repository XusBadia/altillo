import AltilloCore
import Foundation

// Z.ai (GLM Coding Plan) quotas from Z.ai's own subscription API, with the API key the user keeps for Z.ai.
//
// Endpoints, the "no coding plan" signal and the quota mapping (CREDIT_LIMIT/TOKENS_LIMIT windows by unit/number,
// TIME_LIMIT web searches) adapted from openusage (MIT),
// Sources/OpenUsage/Providers/ZAI/{ZAIAuthStore,ZAIUsageClient,ZAIUsageMapper,ZAIProvider}.swift
// @87c3d2db465a5eb6c6dd2c2453c55cd82141a76e.

extension UsageProviderID {
    public static let zai = UsageProviderID(rawValue: "zai")
}

/// Reads the GLM Coding Plan's session and weekly prompt quotas and the monthly web-search allowance.
///
/// Windows: `session` (the 5-hour window), `weekly`, `monthly` (whichever the plan has; other lengths → `other`
/// with id `quota-<hours>h`), `web-search` (monthly count of web searches/reader calls).
public struct ZAICollector: UsageCollector {
    public static let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!
    public static let subscriptionURL = URL(string: "https://api.z.ai/api/biz/subscription/list")!

    public let providerID: UsageProviderID = .zai
    public let displayName = "Z.ai"
    public var setupHint: String { "Add a Z.ai API key to ~/.config/zai/key.json" }

    /// `~/.config/zai/key.json`, then `ZAI_API_KEY` / `GLM_API_KEY`.
    public static func defaultKeySource(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> LocalAPIKeySource {
        LocalAPIKeySource(files: [LocalAPIKeySource.configFile("zai", environment: environment)],
                          environmentNames: ["ZAI_API_KEY", "GLM_API_KEY"], environment: environment)
    }

    private let keySource: LocalAPIKeySource
    private let transport: any HTTPTransport

    public init(keySource: LocalAPIKeySource = ZAICollector.defaultKeySource(),
                transport: any HTTPTransport = URLSessionTransport()) {
        self.keySource = keySource
        self.transport = transport
    }

    public func isAvailable() async -> Bool { keySource.key() != nil }

    public func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage {
        if Group1Support.isBackingOff(previous, now: now) { return previous! }
        guard let key = keySource.key() else {
            return failure(.notSignedIn, detail: "Add a Z.ai API key to ~/.config/zai/key.json, or set ZAI_API_KEY.",
                           previous: previous, plan: nil, now: now)
        }

        let headers = ["Authorization": "Bearer \(key)", "Accept": "application/json"]
        async let quotaCall = Group1Support.send(Group1Support.request(Self.quotaURL, headers: headers),
                                                 transport: transport, now: now)
        async let subscriptionCall = Group1Support.send(Group1Support.request(Self.subscriptionURL, headers: headers),
                                                        transport: transport, now: now)
        let (quota, subscription) = await (quotaCall, subscriptionCall)
        // The subscription list only names the plan; its failure never hides the meters.
        let plan = subscription.data.flatMap(ZAIUsageMapper.planName)

        switch quota {
        case .ok(let data):
            if ZAIUsageMapper.isNoCodingPlan(data) {
                return failure(.notSignedIn, detail: "This Z.ai account has no GLM Coding Plan.", previous: previous,
                               plan: plan, now: now)
            }
            guard let mapped = ZAIUsageMapper.map(data) else {
                return failure(.unexpectedResponse("Z.ai quota response changed shape"), detail: nil,
                               previous: previous, plan: plan, now: now)
            }
            return ProviderUsage(id: providerID, displayName: displayName, plan: plan ?? mapped.level,
                                 windows: mapped.windows, fetchedAt: now)
        case .unauthorized:
            return failure(.sessionExpired, detail: "Z.ai rejected the API key. Check it at z.ai/manage-apikey.",
                           previous: previous, plan: plan, now: now)
        case .rateLimited(let until):
            return failure(.rateLimited(retryAfter: until), detail: nil, previous: previous, plan: plan, now: now)
        case .failed(let reason):
            return failure(.unreachable(reason), detail: nil, previous: previous, plan: plan, now: now)
        case .status(let code, _):
            return failure(.unreachable("HTTP \(code)"), detail: nil, previous: previous, plan: plan, now: now)
        }
    }

    private func failure(_ problem: UsageProblem, detail: String?, previous: ProviderUsage?, plan: String?,
                         now: Date) -> ProviderUsage {
        Group1Support.failure(problem, detail: detail, previous: previous, id: providerID, displayName: displayName,
                              plan: plan, now: now)
    }
}

/// Pure mapping of Z.ai's quota and subscription responses.
enum ZAIUsageMapper {
    struct Mapped: Equatable {
        var windows: [UsageWindow]
        /// `data.level` ("pro", "lite") as a plan fallback: "Pro".
        var level: String?
    }

    static let hour: TimeInterval = 3600
    static let day: TimeInterval = 86400

    /// A 2xx `{"success":false,…"msg":"…coding plan…"}`: the key is fine but there's no GLM Coding Plan to meter.
    static func isNoCodingPlan(_ data: Data) -> Bool {
        guard let root = UsageParsing.object(data), root["success"] as? Bool == false else { return false }
        return (root["msg"] as? String ?? "").lowercased().contains("coding plan")
    }

    /// Nil when the shape is unknown. An empty `limits` array maps to no windows (nothing to meter yet).
    static func map(_ data: Data) -> Mapped? {
        guard let root = UsageParsing.object(data) else { return nil }
        let container: [String: Any]
        if let wrapped = root["data"] {
            guard let wrapped = wrapped as? [String: Any] else { return nil }
            container = wrapped
        } else {
            container = root
        }
        guard let limits = container["limits"] as? [[String: Any]] else { return nil }
        let level = UsageParsing.string(container["level"]).map(UsageParsing.titleCased)

        var windows: [UsageWindow] = []
        for entry in limits {
            let type = UsageParsing.string(entry["type"]) ?? UsageParsing.string(entry["name"])
            switch type {
            case "CREDIT_LIMIT", "TOKENS_LIMIT":
                guard let duration = duration(entry), let percent = UsageParsing.number(entry["percentage"]) else {
                    continue
                }
                let (id, kind, label) = classify(duration)
                guard !windows.contains(where: { $0.id == id }) else { continue }
                windows.append(UsageWindow(id: id, kind: kind, label: label,
                                           used: Group1Support.fraction(percent: percent),
                                           resetsAt: UsageParsing.date(entry["nextResetTime"]), duration: duration))
            case "TIME_LIMIT":
                guard !windows.contains(where: { $0.id == "web-search" }),
                      let used = UsageParsing.number(entry["currentValue"]),
                      let limit = UsageParsing.number(entry["usage"]), limit > 0 else { continue }
                windows.append(UsageWindow(id: "web-search", kind: .monthly, label: "Web searches",
                                           used: max(0, used) / limit,
                                           resetsAt: UsageParsing.date(entry["nextResetTime"]),
                                           duration: duration(entry) ?? 30 * day))
            default:
                continue
            }
        }
        if windows.isEmpty, !limits.isEmpty,
           limits.contains(where: { ["CREDIT_LIMIT", "TOKENS_LIMIT", "TIME_LIMIT"].contains(($0["type"] ?? $0["name"]) as? String ?? "") }) {
            return nil // recognised entries without their numbers: the shape changed
        }
        return Mapped(windows: windows.sortedForDisplay(), level: level)
    }

    /// Window length from `unit` (3 hours, 4 days, 5 months, 6 weeks) × `number`.
    static func duration(_ entry: [String: Any]) -> TimeInterval? {
        guard let unit = UsageParsing.number(entry["unit"]), let number = UsageParsing.number(entry["number"]),
              number > 0 else { return nil }
        let unitLength: TimeInterval
        switch unit {
        case 3: unitLength = hour
        case 4: unitLength = day
        case 5: unitLength = 30 * day
        case 6: unitLength = 7 * day
        default: return nil
        }
        return unitLength * number
    }

    private static func classify(_ duration: TimeInterval) -> (String, UsageWindow.Kind, String) {
        if duration < day { return ("session", .session, "Session") }
        if duration == 7 * day { return ("weekly", .weekly, "Week") }
        if duration >= 28 * day && duration <= 31 * day { return ("monthly", .monthly, "Month") }
        let hours = Int(duration / hour)
        return ("quota-\(hours)h", .other, duration.truncatingRemainder(dividingBy: day) == 0
            ? "\(Int(duration / day))-day" : "\(hours)-hour")
    }

    /// `productName` of the first subscription ("GLM Coding Pro").
    static func planName(_ data: Data) -> String? {
        guard let root = UsageParsing.object(data), let list = root["data"] as? [[String: Any]] else { return nil }
        return list.lazy.compactMap { UsageParsing.string($0["productName"]) }.first
    }
}
