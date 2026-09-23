import CoreGraphics
import Testing
@testable import Altillo

@MainActor
struct MenuBarItemMoverTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let divider = CGRect(x: 1100, y: 0, width: 20, height: 30)

    @Test func nativeClicksUseStatusItemCenterAndRejectHiddenAnchors() {
        #expect(MenuBarItemMover.clickPoint(frame: CGRect(x: 1200, y: 3, width: 24, height: 24),
                                           screens: [screen]) == CGPoint(x: 1212, y: 15))
        for frame in [CGRect(x: -3, y: 3, width: 24, height: 24),
                      CGRect(x: -3000, y: 3, width: 24, height: 24),
                      CGRect.zero,
                      CGRect(x: CGFloat.infinity, y: 3, width: 24, height: 24)] {
            #expect(MenuBarItemMover.clickPoint(frame: frame, screens: [screen]) == nil)
        }
    }

    @Test func placementUsesOppositeSidesOfDividerWithoutLeavingMenuBarRow() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let left = MenuBarItemMover.dragPoints(item: item, divider: divider, toLeft: true, screens: [screen])
        let right = MenuBarItemMover.dragPoints(item: item, divider: divider, toLeft: false, screens: [screen])
        #expect(left?.start == CGPoint(x: 1212, y: 15))
        #expect(left?.end == CGPoint(x: 1102, y: 15))
        #expect(right?.end == CGPoint(x: 1118, y: 15))
    }

    @Test func rejectsOffscreenAndPartiallyClippedSources() {
        for x: CGFloat in [-100, -10, 1430] {
            #expect(MenuBarItemMover.dragPoints(
                item: CGRect(x: x, y: 3, width: 24, height: 24),
                divider: divider, toLeft: true, screens: [screen]
            ) == nil)
        }
    }

    @Test func acceptsAClippedDividerWhenItsInsertionPointIsVisible() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let clippedDivider = CGRect(x: -1, y: 3, width: 22, height: 24)

        let left = MenuBarItemMover.dragPoints(
            item: item, divider: clippedDivider, toLeft: true, screens: [screen]
        )
        let right = MenuBarItemMover.dragPoints(
            item: item, divider: clippedDivider, toLeft: false, screens: [screen]
        )

        #expect(left?.end == CGPoint(x: 1, y: 15))
        #expect(right?.end == CGPoint(x: 19, y: 15))
    }

    @Test func rejectsAClippedDividerWhenItsInsertionPointIsOffscreen() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let offscreenDivider = CGRect(x: -30, y: 3, width: 22, height: 24)

        #expect(MenuBarItemMover.dragPoints(
            item: item, divider: offscreenDivider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func rejectsOtherScreensAndDifferentMenuBarRows() {
        let upperDisplay = CGRect(x: 0, y: -900, width: 1440, height: 900)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: 1200, y: -897, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen, upperDisplay]
        ) == nil)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: 1200, y: 50, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func rejectsInvalidFramesBeforePostingEvents() {
        #expect(MenuBarItemMover.dragPoints(item: .zero, divider: divider, toLeft: true, screens: [screen]) == nil)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: CGFloat.infinity, y: 3, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func systemIconsAreDistinctWithoutScreenCapture() {
        let owner = MenuBarApplication(pid: 0, bundleID: "com.apple.controlcenter", name: "Control Center")
        let wifi = MenuBarEntry(id: "com.apple.controlcenter.WiFi", application: owner, title: "Wi-Fi", frame: .zero)
        let sound = MenuBarEntry(id: "com.apple.controlcenter.Sound", application: owner, title: "Sound", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: wifi) == "wifi")
        #expect(MenuBarAccessibility.systemSymbol(for: sound) == "speaker.wave.2.fill")
        let thirdParty = MenuBarEntry(id: "wifi", application: .init(pid: 0, bundleID: "test.app", name: "Wi-Fi"),
                                     title: "Wi-Fi", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: thirdParty) == nil)
    }
}
