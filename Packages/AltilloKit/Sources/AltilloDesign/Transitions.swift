import SwiftUI

/// Content swap used everywhere in the notch: a fade with a 2 % shift and a whisper of blur.
/// With Reduce Motion it is a plain fade.
public struct ContentSwapTransition: Transition {
    /// Vertical shift in points (≈ 2 % of the container). Positive moves down.
    public var shift: CGFloat
    public var reduceMotion: Bool

    public init(shift: CGFloat = 4, reduceMotion: Bool = false) {
        self.shift = shift
        self.reduceMotion = reduceMotion
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            content.opacity(phase.isIdentity ? 1 : 0)
        } else {
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .blur(radius: phase.isIdentity ? 0 : 4)
                .scaleEffect(phase.isIdentity ? 1 : 1 - Tokens.Motion.contentShift, anchor: .top)
                .offset(y: phase.isIdentity ? 0 : -shift)
        }
    }
}

extension Transition where Self == ContentSwapTransition {
    public static func contentSwap(shift: CGFloat = 4, reduceMotion: Bool = false) -> ContentSwapTransition {
        ContentSwapTransition(shift: shift, reduceMotion: reduceMotion)
    }
}
