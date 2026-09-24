import AltilloCore
import Foundation

/// Turns what `UsageAlertEvaluator` noticed in a refresh into one peek (PLAN §5.8): "Claude is at 95% of the
/// session · refills 16:10". A newer alert replaces the one on screen, so a batch that noticed several things shows
/// only the one that matters most: a limit used up, then the highest level crossed, then running out early, then a
/// refill. Pure, so tests can read every sentence.
enum UsageAlertPresenter {
    static func alert(for events: [UsageAlertEvent], providers: [ProviderUsage], now: Date = .now) -> NotchAlert? {
        let order = Dictionary(providers.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = events.max { lhs, rhs in
            let left = (rank(lhs.kind), -(order[lhs.provider] ?? .max), -windowRank(lhs, in: providers))
            let right = (rank(rhs.kind), -(order[rhs.provider] ?? .max), -windowRank(rhs, in: providers))
            return left < right
        }
        guard let chosen else { return nil }
        let window = providers.first { $0.id == chosen.provider }?.windows.first { $0.id == chosen.windowID }
        return alert(for: chosen, window: window, now: now)
    }

    static func alert(for event: UsageAlertEvent, window: UsageWindow?, now: Date = .now) -> NotchAlert {
        let name = event.providerName
        let phrase = window.map(UsageText.phrase(for:)) ?? event.windowLabel
        let refills = window.flatMap { UsageText.refillsAt($0, now: now) }
        switch event.kind {
        case let .threshold(level):
            let used = window?.used ?? Double(level) / 100
            return NotchAlert(
                source: .usage, symbol: symbol,
                title: String(localized: "\(name) is at \(NotchFormat.percent(used)) of \(phrase)"),
                trailing: refills, isUrgent: used >= 0.95, module: .usage, duration: .seconds(6)
            )
        case .limitReached:
            return NotchAlert(
                source: .usage, symbol: symbol,
                title: String(localized: "\(name) has used all of \(phrase)"),
                trailing: refills, isUrgent: true, module: .usage, duration: .seconds(8)
            )
        case let .runningOutEarly(runsOutAt):
            return NotchAlert(
                source: .usage, symbol: symbol,
                title: String(localized: "At this pace \(name) runs out at \(UsageText.moment(runsOutAt, now: now))"),
                detail: phrase,
                trailing: refills, module: .usage, duration: .seconds(6)
            )
        case .refilled:
            let noun = window.map(UsageText.name(for:)) ?? event.windowLabel
            return NotchAlert(
                source: .usage, symbol: symbol,
                title: String(localized: "\(name) is ready again"),
                detail: String(localized: "\(noun) refilled"),
                module: .usage, duration: .seconds(5)
            )
        }
    }

    static let symbol = "gauge.with.needle"

    private static func rank(_ kind: UsageAlertEvent.Kind) -> Int {
        switch kind {
        case .limitReached: 400
        case let .threshold(level): 200 + level
        case .runningOutEarly: 100
        case .refilled: 0
        }
    }

    /// The session before the week before the rest.
    private static func windowRank(_ event: UsageAlertEvent, in providers: [ProviderUsage]) -> Int {
        let kind = providers.first { $0.id == event.provider }?.windows.first { $0.id == event.windowID }?.kind
        switch kind {
        case .session: return 0
        case .weekly: return 1
        default: return 2
        }
    }
}
