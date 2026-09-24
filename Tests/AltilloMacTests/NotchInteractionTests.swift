import AppKit
import Testing
@testable import Altillo
import AltilloCore

/// Phase 11: sections that arrive with an update, moving between sections (keys, swipes), alerts and the shortcut.
@MainActor
struct NotchInteractionTests {
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "me.badia.altillo.tests.interaction.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    // MARK: New sections after an update

    @Test func aSectionAddedByAnUpdateArrivesSwitchedOnInItsPlace() {
        let defaults = Self.makeDefaults()
        // Stored by a version that didn't know about Ask (no `knownModules`).
        defaults.set(["shelf", "calendar", "usage"], forKey: "modules")
        let settings = AltilloSettings(defaults: defaults)
        #expect(settings.modules == [.shelf, .assistant, .calendar, .usage])
        #expect(AltilloSettings(defaults: defaults).modules == settings.modules, "the migration is saved")
    }

    @Test func aSectionTheUserPutAwayStaysAway() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        settings.setEnabled(.assistant, false)
        #expect(!AltilloSettings(defaults: defaults).isEnabled(.assistant))
    }

    @Test func aFreshInstallGetsEverySectionInTheDefaultOrder() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        #expect(settings.modules == NotchModule.allCases)
        #expect(settings.modules.prefix(2) == [.shelf, .assistant])
    }

    @Test func newSettingsHaveQuietDefaultsAndSurviveARelaunch() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        #expect(settings.hapticsEnabled)
        #expect(settings.assistantHotKey == .controlOptionA)
        #expect(settings.alertsForCalendar)
        #expect(!settings.alertsForNowPlaying, "a new song is not worth interrupting by default")

        settings.hapticsEnabled = false
        settings.assistantHotKey = .optionSpace
        settings.alertsForCalendar = false
        settings.alertsForNowPlaying = true
        let relaunched = AltilloSettings(defaults: defaults)
        #expect(!relaunched.hapticsEnabled)
        #expect(relaunched.assistantHotKey == .optionSpace)
        #expect(!relaunched.alertsForCalendar)
        #expect(relaunched.alertsForNowPlaying)
    }

    // MARK: Moving between sections

    @Test func selectingRemembersWhichWayTheContentSlides() {
        let model = NotchModel(settings: AltilloSettings(defaults: Self.makeDefaults()))
        model.settings.modules = [.shelf, .assistant, .calendar]
        model.jump(to: .shelf)
        #expect(model.moduleDirection == 0)
        model.select(.calendar)
        #expect(model.moduleDirection == 1)
        model.select(.assistant)
        #expect(model.moduleDirection == -1)
        model.jump(to: .calendar)
        #expect(model.moduleDirection == 0, "alerts and the shortcut don't slide")
    }

    @Test func neighboursStopAtTheEnds() {
        let model = NotchModel(settings: AltilloSettings(defaults: Self.makeDefaults()))
        model.settings.modules = [.shelf, .assistant, .calendar]
        model.jump(to: .shelf)
        #expect(model.neighbour(-1) == nil)
        #expect(model.neighbour(1) == .assistant)
        model.jump(to: .calendar)
        #expect(model.neighbour(1) == nil)
        model.bumpEdge(1)
        #expect(model.edgeBump == 1 && model.edgeBumpDirection == 1)
    }

    @Test func aHorizontalSwipeMovesOneSectionPerGesture() {
        var swipe = SwipeTracker()
        swipe.begin(ignored: false)
        #expect(swipe.track(dx: -4, dy: 0, phase: .began, momentum: []) == .pass, "not decided yet")
        #expect(swipe.track(dx: -10, dy: 1, phase: .changed, momentum: []) == .swallow)
        #expect(swipe.track(dx: -30, dy: 0, phase: .changed, momentum: []) == .step(1), "fingers left: next")
        #expect(swipe.track(dx: -80, dy: 0, phase: .changed, momentum: []) == .swallow, "only one step")
        #expect(swipe.track(dx: 0, dy: 0, phase: .ended, momentum: []) == .swallow)
        #expect(swipe.track(dx: -20, dy: 0, phase: [], momentum: .changed) == .swallow, "its momentum too")

        swipe.begin(ignored: false)
        _ = swipe.track(dx: 20, dy: 0, phase: .began, momentum: [])
        #expect(swipe.track(dx: 20, dy: 0, phase: .changed, momentum: []) == .step(-1), "fingers right: previous")
    }

    @Test func verticalAndIgnoredGesturesPassThrough() {
        var swipe = SwipeTracker()
        swipe.begin(ignored: false)
        _ = swipe.track(dx: 1, dy: 8, phase: .began, momentum: [])
        #expect(swipe.track(dx: -60, dy: 10, phase: .changed, momentum: []) == .pass, "a list scrolling stays a scroll")
        #expect(swipe.track(dx: 0, dy: 0, phase: [], momentum: .changed) == .pass)

        swipe.begin(ignored: true)
        #expect(swipe.track(dx: -60, dy: 0, phase: .changed, momentum: []) == .pass, "the shelf's row scrolls itself")
    }

    @Test func aGestureOverSidewaysContentIsTheContentsFromStartToEnd() {
        var swipe = SwipeTracker()
        swipe.begin(ignored: true)
        #expect(swipe.track(dx: -4, dy: 0, phase: .began, momentum: []) == .pass)
        #expect(swipe.track(dx: -200, dy: 0, phase: .changed, momentum: []) == .pass, "never a section change")
        #expect(swipe.track(dx: 300, dy: 0, phase: .changed, momentum: []) == .pass, "not even back at its edge")
        #expect(swipe.track(dx: 0, dy: 0, phase: .ended, momentum: []) == .pass)
        #expect(swipe.track(dx: -40, dy: 0, phase: [], momentum: .began) == .pass, "its momentum scrolls too")
        #expect(swipe.track(dx: -20, dy: 0, phase: [], momentum: .changed) == .pass)

        // The next gesture, elsewhere, is a swipe again.
        swipe.begin(ignored: false)
        _ = swipe.track(dx: -10, dy: 0, phase: .began, momentum: [])
        #expect(swipe.track(dx: -40, dy: 0, phase: .changed, momentum: []) == .step(1))
    }

    @Test func onlyAGestureStartingInsideAScrollingRegionIsIgnored() {
        let cards = CGRect(x: 20, y: 90, width: 600, height: 160)
        let drawer = CGRect(x: 20, y: 60, width: 300, height: 30)
        let regions = [cards, drawer]
        #expect(SwipeTracker.contentScrolls(at: CGPoint(x: 300, y: 170), in: regions), "over the cards")
        #expect(SwipeTracker.contentScrolls(at: CGPoint(x: 100, y: 70), in: regions), "over the drawer's icons")
        #expect(!SwipeTracker.contentScrolls(at: CGPoint(x: 300, y: 20), in: regions), "the tabs, above")
        #expect(!SwipeTracker.contentScrolls(at: CGPoint(x: 700, y: 170), in: regions), "beside the cards")
        #expect(!SwipeTracker.contentScrolls(at: CGPoint(x: 300, y: 170), in: [CGRect]()), "nothing scrolls")
        #expect(!SwipeTracker.contentScrolls(at: .zero, in: [CGRect.null, .zero]), "empty frames never count")
    }

    @Test func contentScrollsSidewaysOnlyWhenWiderThanItsViewport() {
        #expect(SwipeTracker.overflows(content: 700, viewport: 600))
        #expect(!SwipeTracker.overflows(content: 600, viewport: 600), "fits exactly")
        #expect(!SwipeTracker.overflows(content: 600.3, viewport: 600), "rounding")
        #expect(!SwipeTracker.overflows(content: 400, viewport: 600))
        #expect(!SwipeTracker.overflows(content: 400, viewport: 0), "not laid out yet")
    }

    @Test func theModelKeepsOneRegionPerScrollingView() {
        let model = NotchModel(settings: AltilloSettings(defaults: Self.makeDefaults()))
        #expect(model.horizontalScrollRegions.isEmpty)
        model.horizontalScrollRegions["usage.cards"] = CGRect(x: 0, y: 100, width: 500, height: 160)
        model.horizontalScrollRegions["usage.cards"] = CGRect(x: 0, y: 110, width: 500, height: 160)
        #expect(model.horizontalScrollRegions.count == 1)
        #expect(SwipeTracker.contentScrolls(at: CGPoint(x: 10, y: 260), in: model.horizontalScrollRegions.values))
        model.horizontalScrollRegions["usage.cards"] = nil
        #expect(!SwipeTracker.contentScrolls(at: CGPoint(x: 10, y: 260), in: model.horizontalScrollRegions.values))
    }

    // MARK: Alerts

    @Test func anAlertPeeksAndGoesBackOnItsOwn() {
        var machine = NotchStateMachine()
        let peeked = machine.handle(.alert)
        #expect(peeked && machine.state == .peek)
        let expired = machine.handle(.alertExpired)
        #expect(expired && machine.state == .idle)
    }

    @Test func anAlertUnderThePointerWaitsForItToLeave() {
        var machine = NotchStateMachine()
        machine.handle(.alert)
        machine.handle(.hoverIntent)
        machine.handle(.alertExpired)
        #expect(machine.state == .peek)
        machine.handle(.pointerLeft)
        #expect(machine.state == .idle)
    }

    @Test func theAlertFaceOnlyShowsARealAlert() {
        let model = NotchModel(settings: AltilloSettings(defaults: Self.makeDefaults()))
        model.state = .peek
        model.alert = .demoMeeting
        #expect(NotchChrome.face(for: model) == .peek(.alert))
        model.alert = nil
        #expect(NotchChrome.face(for: model) != .peek(.alert))
    }

    // MARK: Shortcut

    @Test func everyShortcutHasAKeyAndNoneIsTakenByMacOS() {
        for key in AssistantHotKey.allCases where key != .off {
            let combo = key.combo
            #expect(combo != nil)
            #expect(!key.title.isEmpty)
        }
        #expect(AssistantHotKey.off.combo == nil)
    }
}
