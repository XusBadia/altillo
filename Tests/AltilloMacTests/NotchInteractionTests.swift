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
