import SwiftUI
import Testing
@testable import AltilloDesign

/// The notch's springs, sampled: how far and when opening overshoots, and that closing never does.
struct MotionTokensTests {
    /// Samples a spring from 0 to 1 every millisecond and returns its peak and when it happens.
    private func peak(of spring: Spring, over duration: Double = 1.2) -> (value: Double, time: Double) {
        var best = (value: 0.0, time: 0.0)
        for step in 0...Int(duration * 1000) {
            let time = Double(step) / 1000
            let value = spring.value(target: 1.0, time: time)
            if value > best.value { best = (value, time) }
        }
        return best
    }

    @Test func openingOvershootsALittleAndPeaksLikeALiquid() {
        let peak = peak(of: Tokens.Motion.openSpring)
        // A few percent past its size (visible, not jelly), peaking ≈ 280 ms in.
        #expect(peak.value > 1.03 && peak.value < 1.06)
        #expect(peak.time > 0.24 && peak.time < 0.32)
        // …and has found its level (within half a percent) ≈ 250 ms after that.
        let settled = (550...1200).allSatisfy {
            abs(Tokens.Motion.openSpring.value(target: 1.0, time: Double($0) / 1000) - 1) < 0.005
        }
        #expect(settled)
    }

    @Test func closingNeverBouncesAndIsQuickerThanOpening() {
        let peak = peak(of: Tokens.Motion.closeSpring)
        #expect(peak.value <= 1.0001)
        let ninety = (0...1000).first { Tokens.Motion.closeSpring.value(target: 1.0, time: Double($0) / 1000) >= 0.9 }
        #expect((ninety ?? 1000) < 230)
        #expect(Tokens.Motion.closeSpring.settlingDuration < Tokens.Motion.openSpring.settlingDuration)
    }

    @Test func slideSwapMovesLikePages() {
        // Forward: arrives from the trailing side, leaves by the leading side; at rest it doesn't move.
        #expect(SlideSwapTransition.offset(direction: 1, phase: -1, distance: 24) == 24)
        #expect(SlideSwapTransition.offset(direction: 1, phase: 1, distance: 24) == -24)
        #expect(SlideSwapTransition.offset(direction: -1, phase: -1, distance: 24) == -24)
        #expect(SlideSwapTransition.offset(direction: -1, phase: 0, distance: 24) == 0)
        #expect(SlideSwapTransition.offset(direction: 3, phase: -1, distance: 10) == 10)
    }

    @Test func focusStaysSubtle() {
        #expect(Tokens.Motion.focusScale >= 0.94 && Tokens.Motion.focusScale < 1)
        #expect(Tokens.Motion.focusBlur > 0 && Tokens.Motion.focusBlur <= 10)
    }
}
