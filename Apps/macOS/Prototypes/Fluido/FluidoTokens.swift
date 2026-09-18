import AltilloDesign
import SwiftUI

// Direction C · «Fluido» (docs/design/direcciones.md): the notch is living black ink; nothing appears out of nowhere,
// everything transforms from where it was, and light escapes through the edges.

/// The tokens of the Fluido direction. Prototype-local on purpose: nothing here leaks into `AltilloDesign`.
enum Fluido {}

// MARK: - Palette

extension Fluido {
    enum Palette {
        /// Silhouette and background. No warm cards in this direction: ink, not paper.
        static let notch = Color.black
        /// Wells.
        static let ink1 = Color(hex: 0x111113)
        /// Raised elements, tracks.
        static let ink2 = Color(hex: 0x1C1C1F)
        /// A notch lighter than ink2, for hover on wells.
        static let ink3 = Color(hex: 0x26262A)

        static let text = Color.white
        static let textSecondary = Color.white.opacity(0.64)
        static let textTertiary = Color.white.opacity(0.40)
        static let hairline = Color.white.opacity(0.08)
        static let hairlineStrong = Color.white.opacity(0.14)

        static let warning = Color(hex: 0xFFB224)
        static let critical = Color(hex: 0xFF453A)
    }
}

// MARK: - Lights

extension Fluido {
    /// Every module has its own light: a two-colour gradient that only ever shows up as (1) the rim light of the
    /// notch while that module speaks and (2) the stroke of its ring or its active chip. It never fills large surfaces.
    struct Light: Hashable {
        var from: Color
        var to: Color

        static let shelf = Light(from: Color(hex: 0xFFB224), to: Color(hex: 0xFF6A3D))
        static let ai = Light(from: Color(hex: 0x8B7CFF), to: Color(hex: 0x4CC9F0))
        static let agents = Light(from: Color(hex: 0xC6F432), to: Color(hex: 0x2EE6A6))
        static let calendar = Light(from: Color(hex: 0xFF5E7E), to: Color(hex: 0xFFA24C))
        static let airDrop = Light(from: Color(hex: 0x3FA9FF), to: Color(hex: 0x7AE1FF))
        static let warning = Light(from: Color(hex: 0xFFB224), to: Color(hex: 0xFF8A3D))
        static let critical = Light(from: Color(hex: 0xFF6A3D), to: Color(hex: 0xFF453A))
        /// The brand line: all three module lights in a row ("la luz que se escapa del altillo").
        static let brand = Light(from: Color(hex: 0xFFB224), to: Color(hex: 0x8B7CFF))

        var colors: [Color] { [from, to] }
        /// Midpoint, for places that need a single colour (glows, shadows).
        var mid: Color { from.mix(with: to, by: 0.5) }

        var linear: LinearGradient {
            LinearGradient(colors: [from, to], startPoint: .leading, endPoint: .trailing)
        }

        func linear(_ start: UnitPoint, _ end: UnitPoint) -> LinearGradient {
            LinearGradient(colors: [from, to], startPoint: start, endPoint: end)
        }

        func opacity(_ value: Double) -> Light {
            Light(from: from.opacity(value), to: to.opacity(value))
        }
    }
}

extension NotchTab {
    var fluidoLight: Fluido.Light {
        switch self {
        case .shelf: .shelf
        case .usage: .ai
        case .agents: .agents
        }
    }

    var fluidoSymbol: String {
        switch self {
        case .shelf: "tray.full.fill"
        case .usage: "gauge.with.needle.fill"
        case .agents: "terminal.fill"
        }
    }
}

// MARK: - Typography

extension Fluido {
    /// System fonts only, but with SF Pro's widths (Expanded, Condensed, Compressed), like Fitness or Weather.
    enum Typography {
        /// Tabs: SF Pro 12 semibold Expanded.
        static let tab = Font.system(size: 12, weight: .semibold).width(.expanded)
        /// Item names: SF Pro Text 11 medium, normal width.
        static let itemName = Font.system(size: 11, weight: .medium)
        /// Big figures inside rings: SF Pro 28 bold Expanded.
        static let ringFigure = Font.system(size: 28, weight: .bold).width(.expanded).monospacedDigit()
        /// Figures in the ears: SF Pro Compressed 14 semibold (more digits fit beside the notch).
        static let earFigure = Font.system(size: 14, weight: .semibold).width(.compressed).monospacedDigit()
        /// Countdowns: SF Pro 11 medium Condensed.
        static let countdown = Font.system(size: 11, weight: .medium).width(.condensed).monospacedDigit()
        /// Peek line: SF Pro 12.5 medium; the key fact in Expanded semibold.
        static let peek = Font.system(size: 12.5, weight: .medium)
        static let peekKey = Font.system(size: 12.5, weight: .semibold).width(.expanded).monospacedDigit()
        /// Titles inside the open notch.
        static let title = Font.system(size: 13, weight: .semibold).width(.expanded)
        static let display = Font.system(size: 17, weight: .semibold).width(.expanded)
        static let body = Font.system(size: 12, weight: .regular)
        static let bodyEmphasis = Font.system(size: 12, weight: .medium)
        static let caption = Font.system(size: 10.5, weight: .regular)
        /// Tiny labels over metrics, set wide instead of uppercase.
        static let micro = Font.system(size: 9.5, weight: .semibold).width(.expanded)
        static let code = Font.system(size: 11, weight: .medium, design: .monospaced)
    }
}

// MARK: - Shape & motion

extension Fluido {
    enum Radius {
        static let panel: CGFloat = 22
        static let card: CGFloat = 18
        static let thumbnail: CGFloat = 14
    }

    /// Elastic and continuous: things open with a heartbeat and close without one.
    enum Motion {
        /// NotchNook's heartbeat.
        static let open = Animation.spring(duration: 0.45, bounce: 0.28)
        static let close = Animation.spring(duration: 0.30, bounce: 0)
        /// "Materialise": blur 6 → 0, fade, scale 0.98 → 1.
        static let materialize = Animation.spring(duration: 0.26, bounce: 0)
        /// The swallow's bulge springing back.
        static let swallow = Animation.spring(duration: 0.4, bounce: 0.4)
        static let snappy = Animation.spring(duration: 0.25, bounce: 0.12)
        static let hover = Animation.spring(duration: 0.22, bounce: 0.2)
        static let reduced = Animation.easeInOut(duration: 0.18)

        static func open(_ reduce: Bool) -> Animation { reduce ? reduced : open }
        static func close(_ reduce: Bool) -> Animation { reduce ? reduced : close }
        static func snappy(_ reduce: Bool) -> Animation { reduce ? reduced : snappy }
        static func hover(_ reduce: Bool) -> Animation { reduce ? reduced : hover }
        static func materialize(_ reduce: Bool) -> Animation { reduce ? reduced : materialize }
    }
}

// MARK: - Transitions

/// "Materialise": content condenses out of the ink (blur 6 → 0, opacity, scale 0.98 → 1). A plain fade with
/// Reduce Motion.
struct MaterializeTransition: Transition {
    var reduceMotion = false
    var anchor: UnitPoint = .top

    func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            content.opacity(phase.isIdentity ? 1 : 0)
        } else {
            content
                .opacity(phase.isIdentity ? 1 : 0)
                .blur(radius: phase.isIdentity ? 0 : 6)
                .scaleEffect(phase.isIdentity ? 1 : 0.98, anchor: anchor)
        }
    }
}

extension Transition where Self == MaterializeTransition {
    static func materialize(reduceMotion: Bool = false, anchor: UnitPoint = .top) -> MaterializeTransition {
        MaterializeTransition(reduceMotion: reduceMotion, anchor: anchor)
    }
}

// MARK: - Prototype launch flags

/// Launch arguments read only by this prototype, to freeze looks that normally need a live pointer.
enum FluidoFlags {
    /// `-prototypeHoverZone shelf|airDrop`: light a drop zone as if the pointer were over it (screenshots only).
    static let hoverZone: DropZone? = switch UserDefaults.standard.string(forKey: "prototypeHoverZone") {
    case "shelf": .shelf
    case "airDrop", "airdrop": .airDrop
    default: nil
    }
}
