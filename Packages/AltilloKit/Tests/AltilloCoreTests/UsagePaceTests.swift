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
