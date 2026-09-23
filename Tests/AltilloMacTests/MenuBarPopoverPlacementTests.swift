import CoreGraphics
import Testing
@testable import Altillo

struct MenuBarPopoverPlacementTests {
    @Test func preservesDrawerAnchorWhenPanelFits() {
        #expect(MenuBarPopoverPlacement.clampedOrigin(CGPoint(x: 800, y: 100),
            windowSize: CGSize(width: 300, height: 400),
            screens: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]) == CGPoint(x: 800, y: 100))
    }

    @Test func clampsVisibleCardToDisplay() {
        #expect(MenuBarPopoverPlacement.clampedOrigin(CGPoint(x: 1800, y: 100),
            windowSize: CGSize(width: 308, height: 272),
            screens: [CGRect(x: 0, y: 0, width: 1920, height: 1080)]) == CGPoint(x: 1612, y: 100))
    }

    @Test func extractsVisibleControlCenterCardFromTransparentBacking() {
        let window = CGRect(x: 900, y: 100, width: 458, height: 1027)
        let card = MenuBarPopoverPlacement.visibleContentFrame(windowFrame: window, descendants: [
            window, CGRect(x: 1050, y: 179, width: 308, height: 184),
            CGRect(x: 1290, y: 140, width: 54, height: 24),
            CGRect(x: 1064, y: 374, width: 280, height: 22)
        ])
        #expect(card == CGRect(x: 1050, y: 132, width: 308, height: 272))
    }

    @Test func keepsCompactNativePanelBounds() {
        let window = CGRect(x: 900, y: 100, width: 300, height: 280)
        #expect(MenuBarPopoverPlacement.visibleContentFrame(windowFrame: window,
            descendants: [window.insetBy(dx: 10, dy: 10)]) == window)
    }

    @Test func respectsNegativeDisplayCoordinates() {
        #expect(MenuBarPopoverPlacement.clampedOrigin(CGPoint(x: -100, y: -800),
            windowSize: CGSize(width: 300, height: 400),
            screens: [CGRect(x: -1440, y: -900, width: 1440, height: 900)]) == CGPoint(x: -300, y: -800))
    }
}
