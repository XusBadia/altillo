import Foundation
import Testing
@testable import AltilloCore

struct UsageAlertTests {
    let start = Date(timeIntervalSince1970: 1_790_157_600)
    let reset = Date(timeIntervalSince1970: 1_790_157_600 + 4 * 3600)
    /// Pace alerts off unless a test wants them, so threshold tests stay about thresholds.
    let noPace = UsageAlertConfiguration(runningOutEarly: false)

    func provider(_ used: Double, resetsAt: Date?, problem: UsageProblem? = nil, duration: TimeInterval? = 5 * 3600)
        -> ProviderUsage {
        ProviderUsage(id: .claude, displayName: "Claude", plan: nil,
                      windows: [UsageWindow(id: "session", kind: .session, label: "Session", used: used,
                                            resetsAt: resetsAt, duration: duration)],
                      fetchedAt: start, problem: problem)
    }

    /// Feeds readings in order and returns the events of each step.
    func run(_ readings: [ProviderUsage], configuration: UsageAlertConfiguration? = nil,
             at times: [Date]? = nil) -> [[UsageAlertEvent.Kind]] {
        var state = UsageAlertState()
        var result: [[UsageAlertEvent.Kind]] = []
        for (index, reading) in readings.enumerated() {
            let now = times?[index] ?? start.addingTimeInterval(TimeInterval(index) * 60)
            let step = UsageAlertEvaluator.evaluate([reading], previous: state, configuration: configuration ?? noPace,
                                                    now: now)
            state = step.state
            result.append(step.events.map(\.kind))
        }
        return result
    }

    @Test func firstObservationIsABaseline() {
        #expect(run([provider(0.97, resetsAt: reset)]) == [[]])
        #expect(run([provider(1, resetsAt: reset)]) == [[]])
    }

    @Test func thresholdFiresOncePerWindow() {
        let steps = run([provider(0.5, resetsAt: reset), provider(0.82, resetsAt: reset),
                         provider(0.85, resetsAt: reset), provider(0.79, resetsAt: reset),
                         provider(0.83, resetsAt: reset)])
        #expect(steps == [[], [.threshold(80)], [], [], []])
    }

    @Test func onlyTheHighestCrossedThresholdFires() {
        let steps = run([provider(0.5, resetsAt: reset), provider(0.97, resetsAt: reset),
                         provider(0.98, resetsAt: reset)])
        #expect(steps == [[], [.threshold(95)], []])
    }

    @Test func limitReachedReplacesThresholds() {
        let steps = run([provider(0.5, resetsAt: reset), provider(1, resetsAt: reset), provider(1, resetsAt: reset)])
        #expect(steps == [[], [.limitReached], []])
        let afterThreshold = run([provider(0.5, resetsAt: reset), provider(0.9, resetsAt: reset),
                                  provider(1.02, resetsAt: reset)])
        #expect(afterThreshold == [[], [.threshold(80)], [.limitReached]])
    }

    @Test func newWindowRefillsAndReArms() {
        let next = reset.addingTimeInterval(5 * 3600)
        let steps = run([provider(0.5, resetsAt: reset), provider(0.85, resetsAt: reset),
                         provider(0.05, resetsAt: next), provider(0.81, resetsAt: next)])
        #expect(steps == [[], [.threshold(80)], [.refilled], [.threshold(80)]])
    }

    @Test func resetJitterIsTheSameWindow() {
        let steps = run([provider(0.5, resetsAt: reset), provider(0.85, resetsAt: reset.addingTimeInterval(0.6)),
                         provider(0.86, resetsAt: reset.addingTimeInterval(0.9))])
        #expect(steps == [[], [.threshold(80)], []])
    }

    @Test func largeDropWithoutResetTimesIsANewWindow() {
        let steps = run([provider(0.5, resetsAt: nil), provider(0.9, resetsAt: nil), provider(0.1, resetsAt: nil),
                         provider(0.3, resetsAt: nil)])
        #expect(steps == [[], [.threshold(80)], [.refilled], []])
        // A small correction is not a reset.
        #expect(run([provider(0.9, resetsAt: nil), provider(0.6, resetsAt: nil)]) == [[], []])
    }

    @Test func sessionThatEndedAndHasNotRestartedRefills() {
        // Claude reports no reset time (and 0 %) once the five hours are over and before the next message.
        let times = [start, start.addingTimeInterval(60), reset.addingTimeInterval(60)]
        let steps = run([provider(0.5, resetsAt: reset), provider(0.96, resetsAt: reset), provider(0, resetsAt: nil)],
                        at: times)
        #expect(steps == [[], [.threshold(95)], [.refilled]])
    }

    @Test func refillIsQuietWhenNothingWasAlerted() {
        let next = reset.addingTimeInterval(5 * 3600)
        #expect(run([provider(0.3, resetsAt: reset), provider(0.02, resetsAt: next)]) == [[], []])
        let off = UsageAlertConfiguration(refilled: false, runningOutEarly: false)
        #expect(run([provider(0.9, resetsAt: reset), provider(0.02, resetsAt: next)], configuration: off) == [[], []])
    }

    @Test func problemsFreezeState() {
        var state = UsageAlertEvaluator.evaluate([provider(0.5, resetsAt: reset)], previous: UsageAlertState(),
                                                 configuration: noPace, now: start).state
        let stale = UsageAlertEvaluator.evaluate([provider(0.99, resetsAt: reset, problem: .sessionExpired)],
                                                 previous: state, configuration: noPace, now: start)
        #expect(stale.events.isEmpty)
        #expect(stale.state == state)
        state = stale.state
        let fresh = UsageAlertEvaluator.evaluate([provider(0.9, resetsAt: reset)], previous: state,
                                                 configuration: noPace, now: start)
        #expect(fresh.events.map(\.kind) == [.threshold(80)])
        #expect(fresh.events.first?.windowID == "session")
        #expect(fresh.events.first?.provider == .claude)
    }

    @Test func newlyEnabledThresholdsAlreadyPassedStayQuiet() {
        var state = UsageAlertEvaluator.evaluate([provider(0.6, resetsAt: reset)], previous: UsageAlertState(),
                                                 configuration: UsageAlertConfiguration(thresholds: [80],
                                                                                        runningOutEarly: false),
                                                 now: start).state
        let enabled = UsageAlertConfiguration(thresholds: [50, 80], runningOutEarly: false)
        let step = UsageAlertEvaluator.evaluate([provider(0.65, resetsAt: reset)], previous: state,
                                                configuration: enabled, now: start)
        #expect(step.events.isEmpty)
        state = step.state
        let later = UsageAlertEvaluator.evaluate([provider(0.8, resetsAt: reset)], previous: state,
                                                 configuration: enabled, now: start)
        #expect(later.events.map(\.kind) == [.threshold(80)])
    }

    @Test func runningOutEarlyFiresOnceBeforeTheReset() {
        // A 5 h window with 4 h left: 10 % after 1 h is fine, 50 % after 1 h 5 min runs out early.
        let calm = provider(0.1, resetsAt: reset)
        let hot = provider(0.5, resetsAt: reset)
        let hotter = provider(0.6, resetsAt: reset)
        let times = [start, start.addingTimeInterval(300), start.addingTimeInterval(600)]
        let steps = run([calm, hot, hotter], configuration: UsageAlertConfiguration(), at: times)
        #expect(steps.count == 3)
        #expect(steps[0].isEmpty)
        guard steps[1].count == 1, case .runningOutEarly(let runsOutAt) = steps[1][0] else {
            Issue.record("expected runningOutEarly, got \(steps[1])")
            return
        }
        #expect(runsOutAt < reset)
        #expect(steps[2].isEmpty)
    }

    @Test func ignoresInvalidThresholds() {
        let odd = UsageAlertConfiguration(thresholds: [0, 100, 150, 90], runningOutEarly: false)
        #expect(run([provider(0.5, resetsAt: reset), provider(0.95, resetsAt: reset)], configuration: odd)
            == [[], [.threshold(90)]])
    }

    @Test func stateRoundTripsThroughCodable() throws {
        let state = UsageAlertEvaluator.evaluate([provider(0.85, resetsAt: reset)], previous: UsageAlertState(),
                                                 now: start).state
        let decoded = try JSONDecoder().decode(UsageAlertState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
