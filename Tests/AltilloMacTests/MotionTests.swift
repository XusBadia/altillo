import SwiftUI
import Testing
@testable import Altillo

/// Desván's motion choices: which spring each axis of the silhouette gets, and which way sections slide.
@MainActor
struct MotionTests {
    private typealias Motion = Desvan.Motion

    @Test func openingOvershootsAndClosingNeverBounces() {
        let open = Motion.silhouette(.horizontal, from: (.rest, 197), to: (.expanded, 560), reduceMotion: false)
        #expect(open == Motion.open)
        let close = Motion.silhouette(.vertical, from: (.expanded, 150), to: (.rest, 32), reduceMotion: false)
        #expect(close == Motion.close)
    }

    @Test func eachAxisPicksItsOwnSpring() {
        // Opening a peek into a narrower notch: the height grows (overshoot), the width shrinks (none).
        let height = Motion.silhouette(.vertical, from: (.peek(.shelf), 60), to: (.expanded, 150), reduceMotion: false)
        let width = Motion.silhouette(.horizontal, from: (.peek(.shelf), 500), to: (.expanded, 460), reduceMotion: false)
        #expect(height == Motion.open)
        #expect(width == Motion.close)
    }

    @Test func overshootNeverLeavesThePanel() {
        let wide = Motion.silhouette(.horizontal, from: (.rest, 197), to: (.expanded, 750), limit: 760,
                                     reduceMotion: false)
        #expect(wide == Motion.openFlat)
    }

    @Test func peeksGrowSidewaysFirstAndLeaveTheOtherWay() {
        let height = Motion.silhouette(.vertical, from: (.rest, 32), to: (.peek(.alert), 60), reduceMotion: false)
        let width = Motion.silhouette(.horizontal, from: (.rest, 197), to: (.peek(.alert), 488), reduceMotion: false)
        #expect(height == Motion.open.delay(0.05))
        #expect(width == Motion.open)
        let leaving = Motion.silhouette(.horizontal, from: (.peek(.alert), 488), to: (.rest, 197), reduceMotion: false)
        #expect(leaving == Motion.close.delay(0.04))
    }

    @Test func sectionResizesMoveWithTheTabs() {
        let taller = Motion.silhouette(.vertical, from: (.expanded, 143), to: (.expanded, 194), reduceMotion: false)
        let shorter = Motion.silhouette(.vertical, from: (.expanded, 194), to: (.expanded, 143), reduceMotion: false)
        #expect(taller == Motion.section)
        #expect(shorter == Motion.sectionShrink)
    }

    @Test func reduceMotionIsAFade() {
        let open = Motion.silhouette(.horizontal, from: (.rest, 197), to: (.expanded, 560), reduceMotion: true)
        #expect(open == Motion.fade)
        #expect(Motion.pick(Motion.section, reduceMotion: true) == Motion.fade)
    }

    @Test func sectionsSlideOnlyBetweenNeighboursInTheStrip() {
        let modules: [NotchModule] = [.shelf, .usage, .agents]
        #expect(Motion.sectionDirection(from: "shelf", to: "agents", modules: modules, moduleDirection: 1) == 1)
        #expect(Motion.sectionDirection(from: "agents", to: "usage", modules: modules, moduleDirection: -1) == -1)
        // A jump (direction 0), a stale direction and the drop box all crossfade.
        #expect(Motion.sectionDirection(from: "shelf", to: "usage", modules: modules, moduleDirection: 0) == 0)
        #expect(Motion.sectionDirection(from: "agents", to: "shelf", modules: modules, moduleDirection: 1) == 0)
        #expect(Motion.sectionDirection(from: "shelf", to: "drop", modules: modules, moduleDirection: 1) == 0)
    }

    @Test func facesComeIntoFocusFromTheNotch() {
        #expect(Motion.focusDepth(.expanded).blur >= 8)
        #expect(Motion.focusDepth(.expanded).scale >= 0.94)
        // Peeks get a lighter version, and they wait for their sideways growth.
        #expect(Motion.focusDepth(.peek(.alert)).blur < Motion.focusDepth(.expanded).blur)
        #expect(Motion.focusDelay(.peek(.alert)) > Motion.focusDelay(.expanded))
    }
}
