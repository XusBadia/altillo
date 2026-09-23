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

    @Test func notchOnASecondaryScreenUsesGlobalCoordinates() {
        // The MacBook to the right of (and lower than) an external display: every rect AppKit reports is global.
        let frame = CGRect(x: 1920, y: -120, width: 1512, height: 982)
        let geometry = NotchGeometry(
            screenFrame: frame,
            visibleFrame: CGRect(x: 1920, y: -120, width: 1512, height: 950),
            safeAreaTop: 32,
            auxiliaryTopLeft: CGRect(x: 1920, y: 830, width: 663, height: 32),
            auxiliaryTopRight: CGRect(x: 2768, y: 830, width: 664, height: 32)
        )
        #expect(geometry.hasNotch)
        #expect(geometry.notchRect == CGRect(x: 2583, y: 830, width: 185, height: 32))
        let panel = geometry.panelFrame(size: CGSize(width: 760, height: 320))
        #expect(panel.maxY == frame.maxY)
        #expect(panel.minX >= frame.minX && panel.maxX <= frame.maxX)
        #expect(geometry.distance(to: CGPoint(x: 2675, y: 862)) == 0)
    }

    @Test func safeAreaWithoutCameraHousingFallsBackToTheIsland() {
        // A safe-area inset with no auxiliary areas (seen while a notched display mirrors another) isn't a notch.
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let geometry = NotchGeometry(
            screenFrame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950), safeAreaTop: 32,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        #expect(!geometry.hasNotch)
        #expect(geometry.notchRect.width == NotchGeometry.virtualIslandWidth)
        #expect(geometry.notchRect.maxY == frame.maxY)
    }

    @Test func distanceIsZeroInsideAndGrowsOutside() {
        let geometry = NotchGeometry(
            screenFrame: mbpFrame, notchRect: CGRect(x: 663, y: 950, width: 185, height: 32), hasNotch: true
        )
        #expect(geometry.distance(to: CGPoint(x: 700, y: 960)) == 0)
        #expect(geometry.distance(to: CGPoint(x: 700, y: 850)) == 100)
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -1920, y: -200, width: 1920, height: 1080),
    ])
    func hoverIncludesExactScreenEdgeBeforeAndAfterOpening(screen: CGRect) {
        let geometry = NotchGeometry(
            screenFrame: screen, visibleFrame: screen, safeAreaTop: 0,
            auxiliaryTopLeft: nil, auxiliaryTopRight: nil
        )
        let pointer = CGPoint(x: screen.midX, y: screen.maxY)
        let openRect = geometry.panelFrame(size: CGSize(width: 560, height: 180))
        for area in [geometry.hoverRect(), openRect] {
            #expect(NotchGeometry.containsPointer(pointer, in: area))
            #expect(NotchGeometry.containsPointer(CGPoint(x: area.minX, y: area.maxY), in: area))
            #expect(NotchGeometry.containsPointer(CGPoint(x: area.maxX, y: area.maxY), in: area))
            #expect(!NotchGeometry.containsPointer(CGPoint(x: pointer.x, y: screen.maxY + 0.1), in: area))
            #expect(!NotchGeometry.containsPointer(CGPoint(x: area.maxX + 0.1, y: area.midY), in: area))
            #expect(!NotchGeometry.containsPointer(CGPoint(x: pointer.x, y: area.minY - 0.1), in: area))
        }
    }

    @Test func emptyShapeDoesNotAcceptPointer() {
        #expect(!NotchGeometry.containsPointer(.zero, in: .zero))
        #expect(!NotchGeometry.containsPointer(.zero, in: .null))
    }
}
