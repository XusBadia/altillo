import Foundation
import Testing
@testable import Altillo

/// What each resting ear shows and how wide it grows: no ear padded with black, nothing said twice, the next most
/// important thing filling an ear that would otherwise be empty.
struct EarsArrangementTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let agent = AgentRequestSignal(agentName: "Claude", project: "altillo")
    private let song = PlaybackSignal(title: "Teardrop", artist: "Massive Attack", appName: "Spotify")
    private let usage = UsageSignal(providerName: "Claude", fraction: 0.82)

    private var standup: EarEvent {
        EarEvent(title: "Standup", start: now.addingTimeInterval(12 * 60), end: now.addingTimeInterval(42 * 60),
                 isAllDay: false)
    }

    private func arrange(
        _ left: EarContent, _ right: EarContent,
        visibility: EarsVisibility = .withActivity,
        activities: [NotchActivity],
        fixed: [EarContent: EarItem] = [:]
    ) -> EarsArrangement {
        EarsArrangementLogic.arrange(left: left, right: right, visibility: visibility, activities: activities,
                                     now: now) { fixed[$0] }
    }

    // MARK: - Arrangement

    @Test func aQuietFixedEarIsFilledWithTheNextActivity() {
        let ears = arrange(.automatic, .agents, activities: [.imminentEvent(standup), .playback(song)])
        #expect(ears.left == .event(standup, .countdown(minutes: 12)))
        #expect(ears.right == .playback(song))
    }

    @Test func withNothingElseGoingOnTheQuietEarTakesNoRoom() {
        let ears = arrange(.automatic, .agents, activities: [.imminentEvent(standup)])
        #expect(ears.left != nil)
        #expect(ears.right == nil)
        #expect(EarMetrics.width(for: ears.right) == 0)
    }

    @Test func twoContextualEarsShowTheFirstAndTheSecond() {
        let ears = arrange(.automatic, .automatic, activities: [.agentRequest(agent), .playback(song), .usage(usage)])
        #expect(ears.left == .agentRequest(agent))
        #expect(ears.right == .playback(song))
    }

    @Test func aFixedEarWithSomethingToSayKeepsIt() {
        let ears = arrange(.automatic, .shelf, activities: [.playback(song)], fixed: [.shelf: .shelf(count: 3)])
        #expect(ears.left == .playback(song))
        #expect(ears.right == .shelf(count: 3))
    }

    @Test func theContextualEarNeverRepeatsAFixedOne() {
        let ears = arrange(.automatic, .nowPlaying, activities: [.playback(song), .usage(usage)],
                           fixed: [.nowPlaying: .playback(song)])
        #expect(ears.left == .usage(usage, isStale: false))
        #expect(ears.right == .playback(song))
    }

    @Test func withoutTheContextualEarAQuietOneStaysEmpty() {
        let ears = arrange(.nextEvent, .shelf, activities: [.playback(song)], fixed: [.nextEvent: .event(standup, .at(standup.start))])
        #expect(ears.left == .event(standup, .at(standup.start)))
        #expect(ears.right == nil)
    }

    @Test func alwaysVisibleEarsKeepAQuietGlyph() {
        let ears = arrange(.automatic, .shelf, visibility: .always, activities: [])
        #expect(ears.left == .quiet(.automatic))
        #expect(ears.right == .quiet(.shelf))
    }

    @Test func anEarSetToNothingStaysEmpty() {
        let ears = arrange(.automatic, .none, activities: [.imminentEvent(standup), .playback(song)])
        #expect(ears.right == nil)
    }

    // MARK: - Priority list

    @Test func everyActivityComesInPriorityOrder() {
        let inputs = NotchActivityInputs(agentRequest: agent, nextEvent: standup, playback: song, usage: usage)
        let all = NotchActivityLogic.resolveAll(inputs, enabled: Set(NotchModule.allCases), now: now)
        #expect(all == [.agentRequest(agent), .imminentEvent(standup), .playback(song), .usage(usage)])
        #expect(NotchActivityLogic.resolve(inputs, enabled: Set(NotchModule.allCases), now: now) == all.first)
        #expect(NotchActivityLogic.resolveAll(.init(), enabled: Set(NotchModule.allCases), now: now).isEmpty)
    }

    // MARK: - Metrics

    @Test func earsGrowWithWhatTheySayUpToACap() {
        let short = EarItem.event(EarEvent(title: "", start: standup.start, end: standup.end, isAllDay: false),
                                  .countdown(minutes: 12))
        let titled = EarItem.event(standup, .countdown(minutes: 12))
        let long = EarItem.event(EarEvent(title: String(repeating: "Quarterly planning ", count: 6),
                                          start: standup.start, end: standup.end, isAllDay: false),
                                 .countdown(minutes: 12))
        #expect(EarMetrics.width(for: titled) > EarMetrics.width(for: short))
        #expect(EarMetrics.width(for: long) <= EarMetrics.maxWidth)
        #expect(EarMetrics.width(for: .quiet(.shelf)) < EarMetrics.width(for: titled))
        #expect(EarMetrics.width(for: nil) == 0)
    }

    @Test func eachEarOpensWhatItShows() {
        #expect(EarItem.playback(song).module == .nowPlaying)
        #expect(EarItem.event(standup, .now).module == .calendar)
        #expect(EarItem.agentRequest(agent).module == .agents)
        #expect(EarItem.quiet(.automatic).module == nil)
    }
}
