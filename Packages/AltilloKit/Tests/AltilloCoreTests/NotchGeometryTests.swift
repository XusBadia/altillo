import CoreGraphics
import Testing
@testable import AltilloCore

struct NotchGeometryTests {
    // MacBook Pro 14" at default scaling: 1512×982 points, 32 pt notch, ~185 pt wide.
    let mbpFrame = CGRect(x: 0, y: 0, width: 1512, height: 982)

    @Test func detectsHardwareNotch() {
        let geometry = NotchGeometry(
            screenFrame: mbpFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 0, y: 950, width: 663, height: 32),
            auxiliaryTopRight: CGRect(x: 848, y: 950, width: 664, height: 32)
        )
        #expect(geometry.hasNotch)
        #expect(geometry.notchRect == CGRect(x: 663, y: 950, width: 185, height: 32))
    }

    @Test func fallsBackToVirtualIslandWithoutNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            screenFrame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaTop: 0,
            auxiliaryTopLeft: nil,
            auxiliaryTopRight: nil
        )
        #expect(!geometry.hasNotch)
        #expect(geometry.notchRect.midX == frame.midX)
        #expect(geometry.notchRect.height == 25)
        #expect(geometry.notchRect.maxY == frame.maxY)
    }

    @Test func usesFallbackHeightWhenMenuBarIsHidden() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            screenFrame: frame, visibleFrame: frame, safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        #expect(geometry.notchRect.height == NotchGeometry.fallbackMenuBarHeight)
    }

    @Test func panelHugsTopEdgeOfSecondaryScreen() {
        let external = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        let geometry = NotchGeometry(
            screenFrame: external,
            visibleFrame: CGRect(x: 1512, y: -200, width: 1920, height: 1055),
            safeAreaTop: 0, auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        let panel = geometry.panelFrame(size: CGSize(width: 680, height: 260))
        #expect(panel.maxY == external.maxY)
        #expect(panel.midX == geometry.notchRect.midX)
    }

    @Test func distanceIsZeroInsideAndGrowsOutside() {
        let geometry = NotchGeometry(
            screenFrame: mbpFrame, notchRect: CGRect(x: 663, y: 950, width: 185, height: 32), hasNotch: true
        )
        #expect(geometry.distance(to: CGPoint(x: 700, y: 960)) == 0)
        #expect(geometry.distance(to: CGPoint(x: 700, y: 850)) == 100)
    }
}
