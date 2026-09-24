import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

/// Opt-in, read-only check of the Cursor, Copilot, OpenRouter and Z.ai collectors on this Mac (never prints tokens):
/// `ALTILLO_LIVE_USAGE=1 swift test --filter CursorCopilotOpenRouterZAILiveTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_LIVE_USAGE"] != nil))
struct CursorCopilotOpenRouterZAILiveTests {
    @Test func printLiveUsage() async {
        let collectors: [any UsageCollector] = [CursorCollector(), CopilotCollector(), OpenRouterCollector(),
                                                ZAICollector()]
        var lines: [String] = []
        let formatter = ISO8601DateFormatter()
        for collector in collectors {
            let available = await collector.isAvailable()
            let started = Date()
            let usage = await collector.fetch(previous: nil, now: Date())
            var text = "== \(usage.displayName) [\(usage.id.rawValue)] available=\(available) "
                + "plan=\(usage.plan ?? "-") (\(String(format: "%.2f", Date().timeIntervalSince(started))) s)"
            if let problem = usage.problem { text += "\n   problem=\(problem) \(usage.problemDetail ?? "")" }
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
