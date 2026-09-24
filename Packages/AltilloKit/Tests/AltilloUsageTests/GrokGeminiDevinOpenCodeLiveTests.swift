import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

/// Opt-in, read-only check of the Grok, Gemini, Devin and OpenCode collectors against this Mac (never prints tokens):
/// `ALTILLO_LIVE_USAGE=1 swift test --filter Group2LiveUsageTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_LIVE_USAGE"] != nil))
struct Group2LiveUsageTests {
    @Test func printLiveUsage() async {
        let collectors: [any UsageCollector] = [GrokCollector(), GeminiCollector(), DevinCollector(),
                                                OpenCodeCollector()]
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        for collector in collectors {
            let available = await collector.isAvailable()
            let started = Date()
            let usage = await collector.fetch(previous: nil, now: Date())
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(started))
            var text = "== \(usage.displayName) [\(usage.id.rawValue)] available=\(available) "
                + "plan=\(usage.plan ?? "-") (\(elapsed) s)"
            if let problem = usage.problem { text += " problem=\(problem) \(usage.problemDetail ?? "")" }
            if !available { text += "\n   setup hint: \(collector.setupHint)" }
            for window in usage.windows {
                let reset = window.resetsAt.map { formatter.string(from: $0) } ?? "not started"
                text += "\n   \(window.id) (\(window.kind.rawValue), \(window.label)): "
                    + "\(String(format: "%.1f", window.used * 100))% resets \(reset)"
            }
            for balance in usage.balances {
                text += "\n   balance \(balance.id): remaining=\(balance.remaining.map { "\($0)" } ?? "-") "
                    + "used=\(balance.used.map { "\($0)" } ?? "-") limit=\(balance.limit.map { "\($0)" } ?? "-") "
                    + balance.unit
            }
            lines.append(text)
        }
        print(lines.joined(separator: "\n"))
    }
}
