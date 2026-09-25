import AltilloCore
import AppKit
import Testing
@testable import Altillo

/// Phase 2: which screens show the notch, which one hosts the live notch, and when a full-screen app keeps it quiet.
struct ScreensTests {
    // MARK: Arrangements

    /// External 1920×1080 display with the menu bar (no notch).
    static let external = screen(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), menuBar: 25)
    /// MacBook Pro 14" to the right of the external display, bottoms aligned, with its notch.
    static let macBook = notched(id: 2, frame: CGRect(x: 1920, y: 0, width: 1512, height: 982))
    /// A second external display above the first one (negative-free, but stacked vertically).
    static let above = screen(id: 3, frame: CGRect(x: 0, y: 1080, width: 2560, height: 1440), menuBar: 25)
    /// A display to the left of the menu-bar screen (negative x).
    static let left = screen(id: 4, frame: CGRect(x: -1440, y: 180, width: 1440, height: 900), menuBar: 25)

    static let primaryHeight: CGFloat = 1080

    static func screen(id: CGDirectDisplayID, frame: CGRect, menuBar: CGFloat, primaryHeight: CGFloat = primaryHeight)
        -> ScreenDescriptor {
        var visible = frame
        visible.size.height -= menuBar
        let geometry = NotchGeometry(
            screenFrame: frame, visibleFrame: visible, safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        return ScreenDescriptor(id: id, geometry: geometry, primaryHeight: primaryHeight)
    }

    static func notched(id: CGDirectDisplayID, frame: CGRect, primaryHeight: CGFloat = primaryHeight) -> ScreenDescriptor {
        let top: CGFloat = 32
        let notchWidth: CGFloat = 185
        let sideWidth = (frame.width - notchWidth) / 2
        let geometry = NotchGeometry(
            screenFrame: frame,
            visibleFrame: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - top),
            safeAreaTop: top,
            auxiliaryTopLeft: CGRect(x: frame.minX, y: frame.maxY - top, width: sideWidth, height: top),
            auxiliaryTopRight: CGRect(x: frame.maxX - sideWidth, y: frame.maxY - top, width: sideWidth, height: top)
        )
        return ScreenDescriptor(id: id, geometry: geometry, primaryHeight: primaryHeight)
    }

    // MARK: Which screen

    @Test func notchModePrefersTheHardwareNotchEvenOffTheMenuBarScreen() throws {
        let plan = try #require(ScreenService.plan(
            for: .notch, screens: [Self.external, Self.macBook], pointer: nil, currentLive: nil, canMove: true
        ))
        #expect(plan.live == Self.macBook)
        #expect(plan.screens == [Self.macBook])
        #expect(plan.resting.isEmpty)
    }

    @Test func notchModeWithoutANotchUsesTheMenuBarScreen() throws {
        let plan = try #require(ScreenService.plan(
            for: .notch, screens: [Self.external, Self.above], pointer: nil, currentLive: nil, canMove: true
        ))
        #expect(plan.live == Self.external)
    }

    @Test func lidClosedFallsBackToTheExternalIsland() throws {
        // The MacBook's panel was live; closing the lid removes its screen.
        let plan = try #require(ScreenService.plan(
            for: .notch, screens: [Self.external], pointer: nil, currentLive: Self.macBook.id, canMove: false
        ))
        #expect(plan.live == Self.external)
        #expect(!plan.live.hasNotch)
    }

    @Test func noScreensMeansNoPlan() {
        #expect(ScreenService.plan(for: .all, screens: [], pointer: nil, currentLive: nil, canMove: true) == nil)
    }

    @Test func mainModeIgnoresTheNotch() throws {
        let plan = try #require(ScreenService.plan(
            for: .main, screens: [Self.external, Self.macBook], pointer: CGPoint(x: 2500, y: 500),
            currentLive: nil, canMove: true
        ))
        #expect(plan.live == Self.external)
        #expect(plan.screens.count == 1)
    }

    @Test func cursorModeFollowsThePointer() throws {
        let screens = [Self.external, Self.macBook, Self.left]
        let onMacBook = try #require(ScreenService.plan(
            for: .cursor, screens: screens, pointer: CGPoint(x: 2600, y: 400), currentLive: Self.external.id, canMove: true
        ))
        #expect(onMacBook.live == Self.macBook)
        #expect(onMacBook.screens == [Self.macBook])

        let onLeft = try #require(ScreenService.plan(
            for: .cursor, screens: screens, pointer: CGPoint(x: -700, y: 600), currentLive: Self.macBook.id, canMove: true
        ))
        #expect(onLeft.live == Self.left)
    }

    @Test func cursorModeNeverMovesANotchInUse() throws {
        let plan = try #require(ScreenService.plan(
            for: .cursor, screens: [Self.external, Self.macBook], pointer: CGPoint(x: 2600, y: 400),
            currentLive: Self.external.id, canMove: false
        ))
        #expect(plan.live == Self.external)
        #expect(plan.screens == [Self.external])
    }

    @Test func cursorModeKeepsItsScreenWhenThePointerIsNowhere() throws {
        let plan = try #require(ScreenService.plan(
            for: .cursor, screens: [Self.external, Self.macBook], pointer: CGPoint(x: 99_999, y: 0),
            currentLive: Self.macBook.id, canMove: true
        ))
        #expect(plan.live == Self.macBook)
    }

    @Test func theTopEdgeBelongsToTheScreen() {
        // AppKit reports the pointer exactly at maxY when it's pushed against the top of the screen.
        let top = CGPoint(x: 2600, y: Self.macBook.frame.maxY)
        #expect(ScreenService.screen(at: top, in: [Self.external, Self.macBook]) == Self.macBook)
    }

    @Test func allModeGivesEveryScreenANotchAndOpensTheOneInUse() throws {
        let screens = [Self.external, Self.macBook, Self.above]
        let plan = try #require(ScreenService.plan(
            for: .all, screens: screens, pointer: CGPoint(x: 900, y: 2000), currentLive: nil, canMove: true
        ))
        #expect(plan.screens == screens)
        #expect(plan.live == Self.above)
        #expect(plan.resting == [Self.external, Self.macBook])
        // Each screen keeps its own geometry: a notch on the MacBook, islands elsewhere.
        #expect(plan.resting.map(\.hasNotch) == [false, true])
    }

    @Test func allModeKeepsAnOpenNotchWhereItIs() throws {
        let plan = try #require(ScreenService.plan(
            for: .all, screens: [Self.external, Self.macBook], pointer: CGPoint(x: 2600, y: 400),
            currentLive: Self.external.id, canMove: false
        ))
        #expect(plan.live == Self.external)
        #expect(plan.screens.count == 2)
    }

    @Test func alertsAndTheShortcutGoHomeOrToThePointer() {
        let screens = [Self.external, Self.macBook]
        let pointer = CGPoint(x: 500, y: 500)
        #expect(ScreenService.attentionScreen(for: .all, screens: screens, pointer: pointer) == Self.macBook)
        #expect(ScreenService.attentionScreen(for: .notch, screens: screens, pointer: pointer) == Self.macBook)
        #expect(ScreenService.attentionScreen(for: .main, screens: screens, pointer: pointer) == Self.external)
        #expect(ScreenService.attentionScreen(for: .cursor, screens: screens, pointer: pointer) == Self.external)
    }

    // MARK: Geometry per screen

    @Test func windowServerFramesFlipAroundTheMenuBarScreen() {
        #expect(Self.external.windowServerFrame == CGRect(x: 0, y: 0, width: 1920, height: 1080))
        // Bottoms aligned, 98 pt shorter: its top is 98 pt below the menu-bar screen's top.
        #expect(Self.macBook.windowServerFrame == CGRect(x: 1920, y: 98, width: 1512, height: 982))
        #expect(Self.above.windowServerFrame == CGRect(x: 0, y: -1440, width: 2560, height: 1440))
        #expect(Self.left.windowServerFrame == CGRect(x: -1440, y: 0, width: 1440, height: 900))
    }

    @Test func eachScreensPanelHugsItsOwnTopEdge() {
        for screen in [Self.external, Self.macBook, Self.above, Self.left] {
            let panel = screen.geometry.panelFrame(size: NotchLayout.panelSize)
            #expect(panel.maxY == screen.frame.maxY)
            #expect(abs(panel.midX - screen.geometry.notchRect.midX) <= 0.5)
            #expect(screen.frame.contains(screen.geometry.notchRect))
        }
    }

    @MainActor
    @Test func restingShapesMatchTheirScreen() {
        let notch = NotchChrome.restShape(notch: Self.macBook.geometry.notchRect.size, hasNotch: true)
        #expect(notch.size == CGSize(width: 185 + 12, height: 32))
        let island = NotchChrome.restShape(notch: Self.external.geometry.notchRect.size, hasNotch: false)
        #expect(island.size == CGSize(width: 76, height: 5))
    }

    // MARK: Full screen

    static let ownPID: pid_t = 42
    static let menuBar = WindowSnapshot(
        ownerPID: 1, layer: FullScreenDetector.menuBarLayer, bounds: CGRect(x: 0, y: 0, width: 1920, height: 30), alpha: 1
    )

    static func window(_ bounds: CGRect, pid: pid_t = 500, alpha: Double = 1, layer: Int = 0) -> WindowSnapshot {
        WindowSnapshot(ownerPID: pid, layer: layer, bounds: bounds, alpha: alpha)
    }

    @Test func aWindowCoveringTheScreenWithoutAMenuBarIsFullScreen() {
        let video = Self.window(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(FullScreenDetector.isFullScreen(Self.external, windows: [video], ownPID: Self.ownPID))
    }

    @Test func theMenuBarOnScreenMeansItIsNotFullScreen() {
        let big = Self.window(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [Self.menuBar, big], ownPID: Self.ownPID))
    }

    @Test func aZoomedWindowIsNotFullScreen() {
        // Below the menu bar (auto-hidden here, so no menu bar window either).
        let zoomed = Self.window(CGRect(x: 0, y: 30, width: 1920, height: 1050))
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [zoomed], ownPID: Self.ownPID))
    }

    @Test func invisibleAndOwnWindowsDontCount() {
        let covering = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        // RocketSim-style transparent overlays, and Altillo's own panels.
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [Self.window(covering, alpha: 0)], ownPID: Self.ownPID))
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [Self.window(covering, pid: Self.ownPID)], ownPID: Self.ownPID))
        // Only layer 0 (normal windows): the Dock and the wallpaper cover the screen too.
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [Self.window(covering, layer: 20)], ownPID: Self.ownPID))
    }

    @Test func fullScreenBesideTheNotchStartsBelowTheCamera() {
        // The MacBook in Quartz coordinates starts at y = 98; the app fills everything below the notch.
        let below = Self.window(CGRect(x: 1920, y: 98 + 32, width: 1512, height: 982 - 32))
        #expect(FullScreenDetector.isFullScreen(Self.macBook, windows: [below], ownPID: Self.ownPID))
        // Without the notch allowance, the same offset is just a window below the menu bar.
        let external = Self.window(CGRect(x: 0, y: 32, width: 1920, height: 1048))
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: [external], ownPID: Self.ownPID))
    }

    @Test func fullScreenIsPerScreen() {
        // A full-screen app on the MacBook; the external display still shows its menu bar and desktop.
        let onMacBook = Self.window(CGRect(x: 1920, y: 98, width: 1512, height: 982))
        let windows = [Self.menuBar, onMacBook]
        #expect(FullScreenDetector.isFullScreen(Self.macBook, windows: windows, ownPID: Self.ownPID))
        #expect(!FullScreenDetector.isFullScreen(Self.external, windows: windows, ownPID: Self.ownPID))
    }

    @Test func aMenuBarOnAnotherScreenDoesntCount() {
        let aboveMenuBar = Self.window(CGRect(x: 0, y: -1440, width: 2560, height: 30), pid: 1,
                                       layer: FullScreenDetector.menuBarLayer)
        let video = Self.window(CGRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(FullScreenDetector.isFullScreen(Self.external, windows: [aboveMenuBar, video], ownPID: Self.ownPID))
    }

    // MARK: Full-screen behaviour

    @Test func stayAsUsualNeverHides() {
        for state in NotchState.allCases {
            #expect(!FullScreenBehaviour.show.hidesNotch(in: state, dragIsClose: false))
        }
        #expect(!FullScreenBehaviour.show.quietensOverFullScreen)
    }

    @Test func onlyWhenDraggingShowsUpForACloseDrag() {
        let behaviour = FullScreenBehaviour.dragOnly
        #expect(behaviour.quietensOverFullScreen)
        #expect(behaviour.takesDropsOverFullScreen)
        #expect(behaviour.hidesNotch(in: .idle, dragIsClose: false))
        #expect(behaviour.hidesNotch(in: .peek, dragIsClose: false))
        #expect(behaviour.hidesNotch(in: .dragArmed, dragIsClose: false), "a drag across the video stays invisible")
        #expect(!behaviour.hidesNotch(in: .dragArmed, dragIsClose: true))
        #expect(!behaviour.hidesNotch(in: .dropTarget, dragIsClose: true))
        #expect(!behaviour.hidesNotch(in: .open, dragIsClose: false), "the drop's result stays in sight")
    }

    @Test func hideOnlyComesBackWhenAskedFor() {
        let behaviour = FullScreenBehaviour.hide
        #expect(!behaviour.takesDropsOverFullScreen)
        #expect(behaviour.hidesNotch(in: .dragArmed, dragIsClose: true))
        #expect(behaviour.hidesNotch(in: .dropTarget, dragIsClose: true))
        #expect(!behaviour.hidesNotch(in: .open, dragIsClose: false), "the Ask shortcut and the menu still open it")
    }

    @MainActor
    @Test func screenSettingsDefaultToTheNotchAndOnlyWhenDragging() {
        TestDefaultsJanitor.purgeStale()
        let suite = "me.badia.altillo.tests.screens-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AltilloSettings(defaults: defaults)
        #expect(settings.displayMode == .notch)
        #expect(settings.fullScreenBehaviour == .dragOnly)
        settings.displayMode = .all
        settings.fullScreenBehaviour = .hide
        let relaunched = AltilloSettings(defaults: defaults)
        #expect(relaunched.displayMode == .all)
        #expect(relaunched.fullScreenBehaviour == .hide)
    }

    // MARK: Panels

    @MainActor
    @Test func theNotchPanelIsNamedForVoiceOverAndStaysOnEverySpace() {
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(panel.title == "Altillo")
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.ignoresMouseEvents, "click-through until the notch is in use")
        #expect(!panel.canBecomeKey, "only the open notch takes the keyboard")
        let host = NotchHostView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        #expect(host.isAccessibilityElement())
        #expect(host.accessibilityLabel() == "Altillo")
        #expect(host.accessibilityRole() == .group)
    }

    @MainActor
    @Test func escapeClosesTheNotchEvenWithoutAFocusedControl() {
        let panel = NotchPanel(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        var closed = 0
        panel.onCloseRequest = { closed += 1 }
        panel.cancelOperation(nil)
        #expect(closed == 1)
    }

    @MainActor
    @Test func movingTheLivePanelFollowsTheNewScreen() {
        let model = NotchModel(settings: AltilloSettings(defaults: UserDefaults(suiteName: "screens-\(UUID())")!))
        let controller = NotchWindowController(screen: Self.external, model: model)
        #expect(controller.screenID == Self.external.id)
        #expect(controller.update(screen: Self.macBook))
        #expect(controller.screenID == Self.macBook.id)
        #expect(controller.panel.frame == Self.macBook.geometry.panelFrame(size: NotchLayout.panelSize))
        #expect(!controller.update(screen: Self.macBook), "the same screen again changes nothing")
        controller.close()
    }
}
