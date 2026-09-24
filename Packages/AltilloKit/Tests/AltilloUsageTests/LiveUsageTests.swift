import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

/// Opt-in check against this Mac's real providers (read-only; never prints tokens):
/// `ALTILLO_LIVE_USAGE=1 swift test --filter LiveUsageTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_LIVE_USAGE"] != nil))
struct LiveUsageTests {
    @Test func printLiveUsage() async {
        let now = Date()
        var lines: [String] = []
        for collector in UsageCollectors.all() {
            let started = Date()
            let usage = await collector.fetch(previous: nil, now: now)
            lines.append(describe(usage, elapsed: Date().timeIntervalSince(started)))
        }
        let started = Date()
        let compatible = await OpenUsageCompatibleSource(excluding: []).fetch(now: now)
        lines.append("== compatible source (all providers, \(String(format: "%.2f", Date().timeIntervalSince(started))) s)")
        for usage in compatible { lines.append(describe(usage, elapsed: nil)) }
        print(lines.joined(separator: "\n"))
    }

    private func describe(_ usage: ProviderUsage, elapsed: TimeInterval?) -> String {
        let formatter = ISO8601DateFormatter()
        var text = "== \(usage.displayName) [\(usage.id.rawValue)] plan=\(usage.plan ?? "-")"
        if let elapsed { text += " (\(String(format: "%.2f", elapsed)) s)" }
        if let problem = usage.problem { text += " problem=\(problem) \(usage.problemDetail ?? "")" }
        for window in usage.windows {
            let percent = String(format: "%.1f", window.used * 100)
            let reset = window.resetsAt.map { formatter.string(from: $0) } ?? "not started"
            text += "\n   \(window.id) (\(window.kind.rawValue), \(window.label)): \(percent)% resets \(reset)"
        }
        for balance in usage.balances {
            text += "\n   balance \(balance.id): remaining=\(balance.remaining.map { "\($0)" } ?? "-") "
                + "used=\(balance.used.map { "\($0)" } ?? "-") limit=\(balance.limit.map { "\($0)" } ?? "-") \(balance.unit)"
        }
        return text
    }
}
