import AltilloCore
import Foundation
import Testing
@testable import AltilloUsage

/// Opt-in, read-only check of the Cursor, Copilot and Z.ai collectors on this Mac (never prints tokens):
/// `ALTILLO_LIVE_USAGE=1 swift test --filter CursorCopilotZAILiveTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ALTILLO_LIVE_USAGE"] != nil))
struct CursorCopilotZAILiveTests {
    @Test func printLiveUsage() async {
        let collectors: [any UsageCollector] = [CursorCollector(), CopilotCollector(),
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

            lines.append(text)
        }
        print(lines.joined(separator: "\n"))
    }
}
