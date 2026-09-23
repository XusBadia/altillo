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

/// Content coming into focus as its container grows around it: it sharpens from a blur while growing from just under
/// full size, anchored where the container grows from (the notch, at the top). Leaving is the same in reverse.
/// Blur and scale only exist while the transition runs; at rest the content is untouched. With Reduce Motion it is
/// a plain fade.
public struct FocusTransition: Transition {
    public var blur: CGFloat
    public var scale: CGFloat
    public var anchor: UnitPoint
    public var reduceMotion: Bool

    public init(blur: CGFloat = Tokens.Motion.focusBlur, scale: CGFloat = Tokens.Motion.focusScale,
                anchor: UnitPoint = .top, reduceMotion: Bool = false) {
        self.blur = blur
        self.scale = scale
        self.anchor = anchor
        self.reduceMotion = reduceMotion
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            content.opacity(phase.isIdentity ? 1 : 0)
        } else {
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .blur(radius: phase.isIdentity ? 0 : blur)
                .scaleEffect(phase.isIdentity ? 1 : scale, anchor: anchor)
        }
    }
}

extension Transition where Self == FocusTransition {
    public static func focus(blur: CGFloat = Tokens.Motion.focusBlur, scale: CGFloat = Tokens.Motion.focusScale,
                             anchor: UnitPoint = .top, reduceMotion: Bool = false) -> FocusTransition {
        FocusTransition(blur: blur, scale: scale, anchor: anchor, reduceMotion: reduceMotion)
    }
}

/// Sideways swap between neighbouring sections, like pages: moving forward (`direction` +1) the new content comes in
/// from the trailing side while the old one leaves by the leading side, with a fade and a whisper of blur. The shift
/// is short (a hint of travel, not a full page). With `direction` 0 it falls back to `ContentSwapTransition`, and
/// with Reduce Motion it is a plain fade.
public struct SlideSwapTransition: Transition {
    /// +1 forward (towards the trailing side of a tab strip), -1 back, 0 no direction.
    public var direction: Int
    public var distance: CGFloat
    public var reduceMotion: Bool

    public init(direction: Int, distance: CGFloat = Tokens.Motion.slideDistance, reduceMotion: Bool = false) {
        self.direction = direction
        self.distance = distance
        self.reduceMotion = reduceMotion
    }

    public func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion || direction == 0 {
            ContentSwapTransition(reduceMotion: reduceMotion).apply(content: content, phase: phase)
        } else {
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .blur(radius: phase.isIdentity ? 0 : 2.5)
                .offset(x: Self.offset(direction: direction, phase: phase.value, distance: distance))
        }
    }

    /// Horizontal offset for a phase value (-1 appearing, 0 identity, +1 disappearing): moving forward, content
    /// appears on the trailing side (+x) and disappears on the leading side (-x).
    public static func offset(direction: Int, phase: Double, distance: CGFloat) -> CGFloat {
        -CGFloat(phase) * CGFloat(direction.signum()) * distance
    }
}

extension Transition where Self == SlideSwapTransition {
    public static func slideSwap(direction: Int, distance: CGFloat = Tokens.Motion.slideDistance,
                                 reduceMotion: Bool = false) -> SlideSwapTransition {
        SlideSwapTransition(direction: direction, distance: distance, reduceMotion: reduceMotion)
    }
}
