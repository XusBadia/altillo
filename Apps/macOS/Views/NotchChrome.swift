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
    /// A drag is in progress somewhere: a small "Drop here" tab.
    case dragArmed
    /// Fully open (tabs, or the drop zone while a drag hovers).
    case expanded
}

enum PeekKind: Hashable {
    /// Hovering with nothing to report: a quiet hint of what opens, no instructions.
    case hint
    case shelf, usageAlert, agentWaiting
    /// A live alert (`NotchModel.alert`): a meeting about to start, a new song, an answer ready.
    case alert
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
    /// Height reserved for the open notch's body (0 unless `face == .expanded`).
    var contentHeight: CGFloat = 0
    var showsDrawer: Bool = false
    static let drawerHeight: CGFloat = 46
    /// The tab row under the Drawer: the tabs' 28 pt targets plus a little air.
    static let drawerNavigationHeight: CGFloat = 32

    /// `-simulateNotch YES` draws every face as if the display had a MacBook Pro 14" notch (185×32 pt), to review the
    /// notch look on a display without one. Views only: the window and hit-testing follow the drawn shape as usual.
    static let simulatedNotch: CGSize? = UserDefaults.standard.bool(forKey: "simulateNotch")
        ? CGSize(width: 185, height: 32)
        : nil

    /// The silhouette at rest, for one screen's notch. Shared with the resting notches of "All of them", which draw
    /// it on the screens the live notch isn't on.
    struct RestShape: Equatable {
        var size: CGSize
        var topRadius: CGFloat
        var bottomRadius: CGFloat
    }

    static func restShape(notch: CGSize, hasNotch: Bool) -> RestShape {
        if hasNotch {
            // Exactly the hardware notch plus its fillets, so it blends in.
            return RestShape(size: CGSize(width: notch.width + 2 * 6, height: notch.height), topRadius: 6, bottomRadius: 10)
        }
        // Without a notch there is nothing to blend with: a hairline lip that only hints where Altillo lives.
        return RestShape(size: CGSize(width: 76, height: 5), topRadius: 3, bottomRadius: 3)
    }

    /// Height of the open tabs' body, between the band and the bottom margin. Each section gets what it needs to
    /// breathe (PLAN §3: roomier since 24-09-2026, like OmniNotch) and no more, so the silhouette is shorter for an
    /// empty shelf than for the agents and morphs between the two.
    enum ExpandedContent {
        /// Things standing on the plank plus their names underneath.
        static let shelf: CGFloat = 150
        /// Just the plank with the house and one sentence above it: nothing below the board.
        static let emptyShelf: CGFloat = 130
        /// Ring, plan, countdown and pace, with the week's bar underneath.
        static let usage: CGFloat = 160
        /// The one knocking on a tall card plus a useful part of the vertical queue.
        static let agents: CGFloat = 220
        /// The cardboard box and the paper plane.
        static let drop: CGFloat = 160
        /// Calendar (next event card plus rows), mirror and now playing.
        static let module: CGFloat = 180
        /// The conversation and the prompt field: the one section that needs room to read.
        static let assistant: CGFloat = 200
        /// Edit mode: the sections to arrange, the ears and the presets.
        static let editing: CGFloat = 200
        /// The calendar with its month grid (alone, or beside the chosen day's agenda).
        static let calendarMonth: CGFloat = 220
    }

    /// Room between the band (or each Drawer row) and what comes below it.
    static let expandedContentGap: CGFloat = 8
    static let expandedBottomInset: CGFloat = 16
    /// Enough room for the widest compact indicator (the usage ring plus "100") to clear the island's curve.
    static let earWidth: CGFloat = 56
    static let peekEarWidth: CGFloat = 64
    static let peekLineHeight: CGFloat = 28

    /// Where the open notch's body starts, from the top of the shape: below the band and, when it shows, the
    /// Drawer and the tab row under it.
    var contentTop: CGFloat {
        bandHeight + Self.expandedContentGap
            + (showsDrawer ? Self.drawerHeight + Self.drawerNavigationHeight + 2 * Self.expandedContentGap : 0)
    }

    /// Horizontal inset of content inside the expanded shape (fillet + breathing room).
    var contentInset: CGFloat { topRadius + 12 }

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
            let rest = Self.restShape(notch: notch, hasNotch: hasNotch)
            topRadius = rest.topRadius
            bottomRadius = rest.bottomRadius
            size = rest.size
        case .ears:
            showsShadow = !hasNotch
            topRadius = 6
            bottomRadius = hasNotch ? 10 : notch.height / 2
            size = CGSize(width: clearWidth + 2 * Self.earWidth + 2 * topRadius, height: notch.height)
        case .peek(.hint):
            topRadius = 6
            if hasNotch {
                bottomRadius = 12
                size = CGSize(width: clearWidth + 2 * Self.earWidth + 2 * topRadius, height: notch.height + 4)
            } else {
                bottomRadius = 13
                bandHeight = 0
                size = CGSize(width: 104 + 2 * topRadius, height: 28)
            }
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
                size = CGSize(width: notch.width + 2 * 36 + 2 * topRadius, height: notch.height + 26)
            } else {
                bottomRadius = 15
                bandHeight = 0
                size = CGSize(width: 150 + 2 * topRadius, height: 34)
            }
        case .expanded:
            topRadius = 14
            bottomRadius = 24
            // Beside a hardware notch the band is exactly the notch; the island keeps room for the tabs.
            let band = hasNotch ? notch.height : max(notch.height, 28)
            bandHeight = band
            // Only a Drawer that works on this macOS; an unsupported one would render an empty or broken strip.
            showsDrawer = model.drawer.showsStrip || model.scenario == .openDrawer
            let content = Self.expandedContentHeight(for: model)
            contentHeight = content
            size = CGSize(
                width: model.settings.openWidth,
                height: band + Self.expandedContentGap + content + Self.expandedBottomInset
                    + (showsDrawer ? Self.drawerHeight + Self.drawerNavigationHeight + 2 * Self.expandedContentGap : 0)
            )
        }
    }

    /// What the open notch needs below the band for whatever it is showing.
    @MainActor
    static func expandedContentHeight(for model: NotchModel) -> CGFloat {
        if model.state == .dropTarget { return ExpandedContent.drop }
        if model.isEditing { return ExpandedContent.editing }
        switch model.module {
        case .shelf: return model.shelf.isEmpty ? ExpandedContent.emptyShelf : ExpandedContent.shelf
        case .usage: return ExpandedContent.usage
        case .agents: return ExpandedContent.agents
        case .assistant: return ExpandedContent.assistant
        case .calendar:
            return model.settings.calendarStyle == .agenda ? ExpandedContent.module : ExpandedContent.calendarMonth
        case .mirror, .nowPlaying, .timer, .note, .clipboard, .shortcuts, .keepAwake:
            return ExpandedContent.module
        }
    }

    @MainActor
    static func face(for model: NotchModel) -> NotchFace {
        switch model.state {
        case .idle:
            return showsEars(model) ? .ears : .rest
        case .peek:
            if model.alert != nil, model.scenario == nil || model.scenario == .peekAlert { return .peek(.alert) }
            switch model.scenario {
            case .peekUsageAlert: return .peek(.usageAlert)
            case .peekAgentWaiting: return .peek(.agentWaiting)
            case .peekShelf: return .peek(.shelf)
            case .peekHint: return .peek(.hint)
            default: return model.shelf.isEmpty ? .peek(.hint) : .peek(.shelf)
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
        if let scenario = model.scenario { return scenario == .idleWithEars || scenario.isAgentWaitingEars }
        return model.ears.showsEars(for: model)
    }
}
