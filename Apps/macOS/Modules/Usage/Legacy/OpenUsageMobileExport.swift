import AltilloCore
import Foundation

/// Pure mapping from Altillo's `UsageSnapshot` to the legacy `openusage.mobile.v1` document. No I/O, no iCloud:
/// testable on its own. Metric ids and labels copy what the OpenUsage Mobile Bridge wrote ("claude.session",
/// "claude.weekly", "claude.fable", "codex.credits"…) so the iPhone keeps its per-metric settings (visibility,
/// headline, alerts are keyed by metric id) and renders the same cards.
enum OpenUsageMobileExport {
    typealias Document = OpenUsageMobileDocument

    static func document(from snapshot: UsageSnapshot, deviceID: String) -> Document {
        var order: [String] = []
        var providers: [String: Document.Provider] = [:]
        for usage in snapshot.providers {
            guard let provider = provider(from: usage, now: snapshot.updatedAt),
                  providers[provider.providerID] == nil else { continue }
            order.append(provider.providerID)
            providers[provider.providerID] = provider
        }
        return Document(
            deviceID: deviceID,
            deviceName: text(snapshot.deviceName, max: Document.maxDeviceNameLength) ?? "Mac",
            updatedAt: wholeSeconds(snapshot.updatedAt),
            providerOrder: order,
            providers: providers
        )
    }

    /// Nil when the provider has nothing worth a card on the phone (never signed in, or an id the phone rejects).
    static func provider(from usage: ProviderUsage, now: Date) -> Document.Provider? {
        let providerID = usage.id.rawValue.lowercased()
        guard Document.isValidProviderID(providerID) else { return nil }

        var metrics: [Document.Metric] = []
        var usedIDs = Set<String>()
        func add(_ metric: Document.Metric) {
            var metric = metric
            var candidate = metric.id
            var attempt = 2
            while usedIDs.contains(candidate) {
                candidate = "\(metric.id)-\(attempt)"
                attempt += 1
            }
            metric.id = candidate
            usedIDs.insert(candidate)
            if metric.isValid { metrics.append(metric) }
        }
        for window in usage.windows { add(metric(from: window, providerID: providerID)) }
        for balance in usage.balances {
            if let metric = metric(from: balance, providerID: providerID) { add(metric) }
        }

        let status = status(for: usage, hasMetrics: !metrics.isEmpty, now: now)
        if metrics.isEmpty {
            // A provider the user never set up would only add an empty card; a broken one explains itself.
            guard let problem = usage.problem, problem != .notSignedIn else { return nil }
        }
        return Document.Provider(
            providerID: providerID,
            displayName: text(usage.displayName, max: Document.maxTextLength) ?? providerID.capitalized,
            plan: usage.plan.flatMap { text($0, max: Document.maxTextLength) },
            refreshedAt: wholeSeconds(usage.fetchedAt),
            status: status,
            metrics: metrics
        )
    }

    /// Problems that need the user (sign in again, allow the keychain) make the card "unavailable"; transient ones
    /// keep the last numbers flagged as "attention", like stale data did with the bridge.
    static func status(for usage: ProviderUsage, hasMetrics: Bool, now: Date) -> Document.Provider.Status {
        switch usage.problem {
        case .none:
            return usage.isStale(now: now) ? .attention : .available
        case .notSignedIn, .sessionExpired, .accessDenied:
            return .unavailable
        case .rateLimited, .unreachable, .unexpectedResponse:
            return hasMetrics ? .attention : .unavailable
        }
    }

    // MARK: - Windows → progress metrics (percent)

    static func metric(from window: UsageWindow, providerID: String) -> Document.Metric {
        let (slug, label) = identity(of: window)
        return Document.Metric(
            id: "\(providerID).\(slug)",
            label: label,
            presentation: .progress,
            used: window.used.isFinite ? max(0, (window.used * 1_000).rounded() / 10) : 0,
            limit: 100,
            unit: Document.Unit(kind: .percent),
            resetsAt: window.resetsAt.map(wholeSeconds),
            periodDurationMilliseconds: window.duration.flatMap { $0.isFinite && $0 > 0 ? Int(($0 * 1_000).rounded()) : nil }
        )
    }

    /// Slug and label the bridge used: "session"/"Session", "weekly"/"Weekly", the model's name for a per-model
    /// week ("fable"/"Fable"), "monthly"/"Monthly", and the window's own id and label otherwise.
    static func identity(of window: UsageWindow) -> (slug: String, label: String) {
        switch window.kind {
        case .session: return ("session", "Session")
        case .weekly: return ("weekly", "Weekly")
        case .monthly: return ("monthly", "Monthly")
        case .modelWeekly:
            let model = modelName(of: window)
            return (slug(model).nonEmpty ?? slug(window.id).nonEmpty ?? "model", model)
        case .other:
            let label = text(window.label, max: Document.maxTextLength) ?? "Usage"
            return (slug(window.id).nonEmpty ?? slug(label).nonEmpty ?? "usage", label)
        }
    }

    /// "Fable week" → "Fable"; falls back to the id ("weekly-sonnet" → "Sonnet").
    static func modelName(of window: UsageWindow) -> String {
        var name = window.label.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in [" week", " weekly"] where name.lowercased().hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        if let name = text(name, max: Document.maxTextLength) { return name }
        let fromID = window.id.replacingOccurrences(of: "weekly-", with: "")
            .split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return text(fromID, max: Document.maxTextLength) ?? "Model"
    }

    // MARK: - Balances → value metrics (dollars / count)

    /// Bridge ids for the balances it knew; everything else keeps Altillo's id and label.
    private static let knownBalances: [String: (slug: String, label: String)] = [
        "limit-resets": ("rate-limit-resets", "Rate Limit Resets"),
        "credits": ("credits", "Credits"),
        "creditvalue": ("credit-value", "Credit Value"),
        "credit-value": ("credit-value", "Credit Value"),
    ]

    static func metric(from balance: UsageBalance, providerID: String) -> Document.Metric? {
        guard let number = balance.remaining ?? balance.used, number.isFinite, number >= 0 else { return nil }
        let known = knownBalances[balance.id.lowercased()]
        let label = known?.label ?? text(balance.label, max: Document.maxTextLength) ?? "Balance"
        let slug = known?.slug ?? slug(balance.id).nonEmpty ?? slug(label).nonEmpty ?? "balance"
        return Document.Metric(
            id: "\(providerID).\(slug)",
            label: label,
            presentation: .values,
            values: [Document.Value(number: number, unit: unit(for: balance.unit))]
        )
    }

    static func unit(for raw: String) -> Document.Unit {
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "usd", "dollars", "dollar", "$": Document.Unit(kind: .dollars)
        case "percent", "%": Document.Unit(kind: .percent)
        default: Document.Unit(kind: .count, suffix: text(raw, max: Document.maxSuffixLength))
        }
    }

    // MARK: - Helpers

    static func slug(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1-$2", options: .regularExpression)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Trimmed, control characters removed, cut to `max` characters; nil when nothing is left.
    static func text(_ value: String, max: Int) -> String? {
        let cleaned = String(value.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(max)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The phone decodes plain ISO 8601; dropping sub-seconds also keeps a decoded file equal to what was mapped.
    static func wholeSeconds(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
