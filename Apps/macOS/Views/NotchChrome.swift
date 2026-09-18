import AltilloCore
import CoreGraphics
import Foundation

/// What the notch is showing. Each face has its own fixed layout; the shape morphs between them.
enum NotchFace: Hashable {
    /// Nothing to show: exactly the hardware notch, or a hairline lip on displays without one.
    case rest
    /// Idle with minimal information beside the notch.
    case ears
    /// Slightly grown with a one-line summary.
    case peek(PeekKind)
    /// A drag is in progress somewhere: a small "Suelta aquí" tab.
    case dragArmed
    /// Fully open (tabs, or the drop zone while a drag hovers).
    case expanded
}

enum PeekKind: Hashable {
    case shelf, usageAlert, agentWaiting
}

/// Size and corner radii of the black silhouette for the current face.
///
/// All sizes include the concave top fillets (`topRadius` on each side), so over a hardware notch of width `w`
/// the rest shape is `w + 2 × topRadius` wide and its body lines up with the notch exactly.
struct NotchChrome: Equatable {
    var face: NotchFace
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Height of the top band that sits beside the hardware notch (ears, tabs). Content below it is free.
    var bandHeight: CGFloat
    /// Width of the notch body (without fillets), i.e. the part to keep clear of content on a hardware notch.
    var notchWidth: CGFloat
    /// Width kept empty between the ears: the notch body on a hardware notch, a small gap on the virtual island.
    var clearWidth: CGFloat
    /// Drawing over a hardware notch (or simulating one). Without a notch, compact faces collapse to a single row.
    var hasNotch: Bool
    var showsShadow: Bool

    /// `-simulateNotch YES` draws every face as if the display had a MacBook Pro 14" notch (185×32 pt), to review the
    /// notch look on a display without one. Views only: the window and hit-testing follow the drawn shape as usual.
    static let simulatedNotch: CGSize? = UserDefaults.standard.bool(forKey: "simulateNotch")
        ? CGSize(width: 185, height: 32)
        : nil

    static let expandedSize = CGSize(width: 680, height: 0)
    static let expandedContentHeight: CGFloat = 188
    static let earWidth: CGFloat = 50
    static let peekEarWidth: CGFloat = 64
    static let peekLineHeight: CGFloat = 34

    /// Horizontal inset of content inside the expanded shape (fillet + breathing room).
    var contentInset: CGFloat { topRadius + 16 }

    @MainActor
    init(model: NotchModel) {
        let notch = Self.simulatedNotch ?? model.notchSize
        let hasNotch = model.hasNotch || Self.simulatedNotch != nil
        let face = Self.face(for: model)
        self.face = face
        self.hasNotch = hasNotch
        notchWidth = notch.width
        clearWidth = hasNotch ? notch.width : 20
        bandHeight = notch.height
        showsShadow = true

        switch face {
        case .rest:
            showsShadow = false
            if hasNotch {
                topRadius = 6
                bottomRadius = 10
                size = CGSize(width: notch.width + 2 * topRadius, height: notch.height)
            } else {
                // Without a notch there is nothing to blend with: a hairline lip that only hints where Altillo lives.
                topRadius = 3
                bottomRadius = 3
                size = CGSize(width: 76, height: 5)
            }
        case .ears:
            showsShadow = !hasNotch
            topRadius = 6
            bottomRadius = hasNotch ? 10 : notch.height / 2
            size = CGSize(width: clearWidth + 2 * Self.earWidth + 2 * topRadius, height: notch.height)
        case .peek:
            topRadius = 8
            let width = max(notch.width + 2 * Self.peekEarWidth, 360) + 2 * topRadius
            if hasNotch {
                bottomRadius = 18
                size = CGSize(width: width, height: notch.height + Self.peekLineHeight)
            } else {
                // The island has no camera to dodge: one centred row.
                let height = max(notch.height, 24) + 14
                bottomRadius = height / 2 - 2
                bandHeight = 0
                size = CGSize(width: width, height: height)
            }
        case .dragArmed:
            topRadius = 8
            if hasNotch {
                bottomRadius = 16
                size = CGSize(width: notch.width + 2 * 36 + 2 * topRadius, height: notch.height + 30)
            } else {
                bottomRadius = 15
                bandHeight = 0
                size = CGSize(width: 150 + 2 * topRadius, height: 34)
            }
        case .expanded:
            topRadius = 14
            bottomRadius = 26
            let band = max(notch.height, 34)
            bandHeight = band
            size = CGSize(width: Self.expandedSize.width, height: band + 8 + Self.expandedContentHeight + 16)
        }
    }

    @MainActor
    static func face(for model: NotchModel) -> NotchFace {
        switch model.state {
        case .idle:
            return showsEars(model) ? .ears : .rest
        case .peek:
            switch model.scenario {
            case .peekUsageAlert: return .peek(.usageAlert)
            case .peekAgentWaiting: return .peek(.agentWaiting)
            default: return .peek(.shelf)
            }
        case .dragArmed:
            return .dragArmed
        case .dropTarget, .open:
            return .expanded
        }
    }

    /// Ears only appear when there is something to show (PLAN §3).
    @MainActor
    static func showsEars(_ model: NotchModel) -> Bool {
        if let scenario = model.scenario { return scenario == .idleWithEars }
        return !model.shelf.isEmpty
    }
}
