import AppKit

/// Turns a two-finger trackpad gesture into at most one section change.
///
/// The first few points decide the axis: a vertical gesture is left alone (lists scroll), a horizontal one is taken
/// over for its whole life, momentum included, so nothing underneath scrolls sideways while the section changes.
/// One gesture moves one section, however long the swipe.
///
/// Content that scrolls sideways (the usage cards, the shelf's row, the drawer's icons) owns every gesture that starts
/// over it, edges included: the views report those regions (`NotchModel.horizontalScrollRegions`) and a gesture that
/// begins inside one is `ignored` from start to end, momentum too. Swipes anywhere else change section.
struct SwipeTracker {
    /// True when a gesture starting at `point` belongs to content that scrolls sideways itself. `point` and
    /// `regions` share one space: the hosting view's, top-left origin.
    static func contentScrolls(at point: CGPoint, in regions: some Sequence<CGRect>) -> Bool {
        regions.contains { !$0.isNull && !$0.isEmpty && $0.contains(point) }
    }

    /// True when content is wider than its viewport, so it really scrolls sideways (half a point of slack for
    /// rounding: content that fits exactly doesn't scroll).
    static func overflows(content: CGFloat, viewport: CGFloat) -> Bool {
        viewport > 0 && content - viewport > 0.5
    }

    enum Outcome: Equatable {
        /// Not ours: let the event reach the views.
        case pass
        /// Ours, but nothing to do yet (or anymore).
        case swallow
        /// Move one section: +1 to the next (fingers moved left), -1 to the previous.
        case step(Int)
    }

    /// Points of horizontal travel that make a swipe. Short enough to feel instant, long enough to not fire on a
    /// resting finger.
    static let threshold: CGFloat = 36
    /// Travel needed before the axis is decided.
    static let decisionDistance: CGFloat = 6

    private enum Axis { case horizontal, vertical }

    private var isActive = false
    private var isIgnored = false
    private var axis: Axis?
    private var travelX: CGFloat = 0
    private var travelY: CGFloat = 0
    private var hasStepped = false

    /// A new gesture starts. `ignored` gestures (over content that scrolls sideways itself) are never taken.
    mutating func begin(ignored: Bool) {
        isActive = true
        isIgnored = ignored
        axis = nil
        travelX = 0
        travelY = 0
        hasStepped = false
    }

    /// `dx` follows the fingers: negative when they move left.
    mutating func track(dx: CGFloat, dy: CGFloat, phase: NSEvent.Phase, momentum: NSEvent.Phase) -> Outcome {
        let ours = !isIgnored && axis == .horizontal
        // The flick's momentum arrives after the fingers lift: swallow it if the gesture was ours.
        if !momentum.isEmpty { return ours ? .swallow : .pass }
        guard isActive, !isIgnored else { return .pass }
        if phase.contains(.ended) || phase.contains(.cancelled) {
            isActive = false
            return ours ? .swallow : .pass
        }
        guard phase.contains(.changed) || phase.contains(.began) else { return .pass }
        travelX += dx
        travelY += dy
        if axis == nil {
            guard abs(travelX) + abs(travelY) >= Self.decisionDistance else { return .pass }
            axis = abs(travelX) > abs(travelY) * 1.2 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { return .pass }
        if !hasStepped, abs(travelX) >= Self.threshold {
            hasStepped = true
            return .step(travelX < 0 ? 1 : -1)
        }
        return .swallow
    }
}
