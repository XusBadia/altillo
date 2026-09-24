import Foundation
import Testing
@testable import AltilloCore

struct UsagePaceTests {
    let now = Date(timeIntervalSince1970: 1_790_157_600)
    let week: TimeInterval = 7 * 86400

    /// A weekly window `elapsed` of the way through, with `used` spent.
    func window(used: Double, elapsed: Double, duration: TimeInterval? = 7 * 86400, reset: Bool = true) -> UsageWindow {
        let length = duration ?? week
        return UsageWindow(id: "weekly", kind: .weekly, label: "Week", used: used,
                           resetsAt: reset ? now.addingTimeInterval(length * (1 - elapsed)) : nil, duration: duration)
    }

    @Test func unknownWithoutResetOrDuration() {
        #expect(UsagePace.evaluate(window(used: 0.5, elapsed: 0.5, reset: false), now: now) == .unknown)
        #expect(UsagePace.evaluate(window(used: 0.5, elapsed: 0.5, duration: nil), now: now) == .unknown)
    }

    @Test func unknownRightAfterTheStartAndAfterTheReset() {
        #expect(UsagePace.evaluate(window(used: 0.2, elapsed: 0.0001), now: now) == .unknown)
        #expect(UsagePace.evaluate(window(used: 0.2, elapsed: 1.2), now: now) == .unknown)
    }

    @Test func aheadWhenBarelyUsed() {
        #expect(UsagePace.evaluate(window(used: 0.02, elapsed: 0.5), now: now) == .ahead)
        #expect(UsagePace.evaluate(window(used: 0.3, elapsed: 0.5), now: now) == .ahead)
    }

    @Test func onTrackNearTheLimit() {
        guard case .onTrack(let spare) = UsagePace.evaluate(window(used: 0.47, elapsed: 0.5), now: now) else {
            Issue.record("expected onTrack")
            return
        }
        #expect(abs(spare - 0.06) < 1e-9)
    }

    @Test func behindProjectsWhenItRunsOut() throws {
        // 80 % used halfway through a week: the last 20 % lasts a quarter of the elapsed time.
        guard case .behind(let runsOutAt) = UsagePace.evaluate(window(used: 0.8, elapsed: 0.5), now: now) else {
            Issue.record("expected behind")
            return
        }
        let date = try #require(runsOutAt)
        #expect(abs(date.timeIntervalSince(now) - week * 0.5 / 4) < 1)
    }

    @Test func spentWindowIsBehindWithoutDate() {
        #expect(UsagePace.evaluate(window(used: 1, elapsed: 0.5), now: now) == .behind(runsOutAt: nil))
    }
}

struct UsageHeadlineTests {
    let now = Date(timeIntervalSince1970: 1_790_157_600)

    func window(_ id: String, _ kind: UsageWindow.Kind, used: Double) -> UsageWindow {
        UsageWindow(id: id, kind: kind, label: id, used: used, resetsAt: now.addingTimeInterval(3600), duration: nil)
    }

    func usage(_ windows: [UsageWindow]) -> ProviderUsage {
        ProviderUsage(id: UsageProviderID(rawValue: "p"), displayName: "P", plan: nil, windows: windows, fetchedAt: now)
    }

    @Test func theFullestOfSessionAndWeekWins() {
        let windows = [window("session", .session, used: 0.3), window("weekly", .weekly, used: 0.6),
                       window("monthly", .monthly, used: 0.9)]
        #expect(usage(windows).headline?.id == "weekly", "session and week come before longer windows")
    }

    @Test func withoutSessionOrWeekTheMainLimitWins() {
        // Cursor: the month's total is the plan; "Grok Bot" is a side pool, even when it's fuller.
        let windows = [window("total", .monthly, used: 0.2), window("grok-bot", .other, used: 0.7)]
        #expect(usage(windows).headline?.id == "total")
        let sidePoolsOnly = [window("requests", .other, used: 0.3), window("auto", .other, used: 0.7)]
        #expect(usage(sidePoolsOnly).headline?.id == "requests", "without a main limit, the first one listed")
        #expect(usage([]).headline == nil, "balances alone have no headline")
    }
}
