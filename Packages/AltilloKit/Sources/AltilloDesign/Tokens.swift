import SwiftUI

/// Design tokens shared by macOS and iOS. See PLAN.md §3 ("Lenguaje visual").
///
/// Everything visual in Altillo is derived from these values: never hard-code a colour, radius or duration in a view.
public enum Tokens {}

// MARK: - Colour

extension Tokens {
    /// Warm, near-black palette inspired by Seam. The silhouette itself is always pure black (`notch`).
    public enum Palette {
        /// The notch silhouette. Pure opaque black so it melts into the hardware notch.
        public static let notch = Color.black
        /// Cards and wells inside the open notch (≈ `#1C1917`).
        public static let surface = Color(hex: 0x1C1917)
        /// Raised elements on top of a surface: selected tiles, code blocks, pressed controls (≈ `#292524`).
        public static let elevated = Color(hex: 0x292524)
        /// Even lighter warm grey, for tracks and dividers that need to read on `elevated`.
        public static let raised = Color(hex: 0x3A3532)

        /// Primary text (warm white, ≈ `#FFFFFB`).
        public static let text = Color(hex: 0xFFFFFB)
        /// Secondary text: labels, metadata.
        public static let textSecondary = Color(hex: 0xFFFFFB).opacity(0.62)
        /// Tertiary text: hints, disabled, placeholders.
        public static let textTertiary = Color(hex: 0xFFFFFB).opacity(0.38)

        /// Hairline separators and card outlines.
        public static let hairline = Color(hex: 0xFFFFFB).opacity(0.08)
        /// A slightly stronger hairline, for hovered outlines.
        public static let hairlineStrong = Color(hex: 0xFFFFFB).opacity(0.16)
        /// Top highlight used on cards and glass (a light "lip" on the upper edge).
        public static let highlight = Color.white.opacity(0.10)
        /// Tracks behind rings and bars.
        public static let track = Color(hex: 0xFFFFFB).opacity(0.10)

        /// Default accent: Seam's amber (`oklch(73% .23 74)`).
        public static let amber = Color(hex: 0xF5A524)
        /// Something needs attention soon (≥ 80 % usage, an agent waiting).
        public static let warning = Color(hex: 0xFF9F43)
        /// Something is about to break (≥ 95 % usage, errors).
        public static let critical = Color(hex: 0xFF5F57)
        /// Success / finished.
        public static let success = Color(hex: 0x5BD08A)
        /// Seam's navy, used sparingly as a secondary tint (AirDrop, links).
        public static let navy = Color(hex: 0x1E3A5F)
        /// A calm blue for AirDrop and other system-ish affordances.
        public static let info = Color(hex: 0x5AB0FF)
    }

    /// Accent colour presets the user can pick from (Settings › Apariencia). Amber is the default.
    public enum AccentPreset: String, CaseIterable, Identifiable, Sendable {
        case amber, coral, lime, mint, sky, violet, rose

        public var id: Self { self }

        public var color: Color {
            switch self {
            case .amber: Palette.amber
            case .coral: Color(hex: 0xFF7A59)
            case .lime: Color(hex: 0xB5E550)
            case .mint: Color(hex: 0x4FD1B5)
            case .sky: Color(hex: 0x5AB0FF)
            case .violet: Color(hex: 0xA78BFA)
            case .rose: Color(hex: 0xF472B6)
            }
        }

        /// Spanish display name for Settings.
        public var title: String {
            switch self {
            case .amber: "Ámbar"
            case .coral: "Coral"
            case .lime: "Lima"
            case .mint: "Menta"
            case .sky: "Cielo"
            case .violet: "Violeta"
            case .rose: "Rosa"
            }
        }
    }
}

// MARK: - Shape & space

extension Tokens {
    /// Corner radii. 12 pt is the base; outer containers add their padding so nested corners stay concentric.
    public enum Radius {
        /// Small elements: badges, code snippets, thumbnails' inner image.
        public static let small: CGFloat = 8
        /// Base radius: cards, tiles, drop zones.
        public static let base: CGFloat = 12
        /// Large containers (a card holding cards).
        public static let large: CGFloat = 18
        /// Squircle thumbnails use a continuous corner at ~22 % of their side, like app icons.
        public static func squircle(side: CGFloat) -> CGFloat { side * 0.22 }
    }

    /// 4-pt spacing scale.
    public enum Space {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 6
        public static let m: CGFloat = 8
        public static let l: CGFloat = 12
        public static let xl: CGFloat = 16
        public static let xxl: CGFloat = 24
    }
}

// MARK: - Typography

extension Tokens {
    /// SF Pro sizes tuned for the notch (compact, macOS-dense). Numbers always use `monospacedDigit()`.
    public enum Typography {
        /// Section titles inside the open notch ("Claude", "altillo").
        public static let title = Font.system(size: 13, weight: .semibold)
        /// Default reading text.
        public static let body = Font.system(size: 12, weight: .regular)
        /// Emphasised body.
        public static let bodyEmphasis = Font.system(size: 12, weight: .medium)
        /// Control labels (tabs, buttons).
        public static let label = Font.system(size: 11.5, weight: .medium)
        /// Metadata and captions.
        public static let caption = Font.system(size: 10.5, weight: .regular)
        /// Tiny uppercase-ish labels over bars ("SESIÓN · 5 H").
        public static let micro = Font.system(size: 9.5, weight: .semibold)
        /// Code / commands.
        public static let code = Font.system(size: 11, weight: .regular, design: .monospaced)

        /// Tabular numbers that don't jiggle while they change.
        public static func numeric(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .system(size: size, weight: weight).monospacedDigit()
        }

        /// Rounded numerals for big figures (ring centres, percentages).
        public static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded).monospacedDigit()
        }
    }
}

// MARK: - Motion

extension Tokens {
    /// Springs of 250–420 ms. Opening may overshoot a hair; closing never bounces.
    /// With Reduce Motion every movement becomes a short fade.
    public enum Motion {
        /// The notch opening (peek → open, drag → drop target).
        public static let open = Animation.spring(duration: 0.42, bounce: 0.14)
        /// The notch closing. Critically damped: no bounce.
        public static let close = Animation.spring(duration: 0.34, bounce: 0)
        /// Content swaps inside a stable container (tabs, list changes).
        public static let content = Animation.spring(duration: 0.30, bounce: 0)
        /// Small, immediate reactions (hover, press, selection).
        public static let snappy = Animation.spring(duration: 0.25, bounce: 0)
        /// Hover highlights.
        public static let hover = Animation.easeOut(duration: 0.15)
        /// Everything, when Reduce Motion is on.
        public static let reducedFade = Animation.easeInOut(duration: 0.2)

        /// Content transitions move by 2 % of the container, never more.
        public static let contentShift: CGFloat = 0.02

        public static func open(reduceMotion: Bool) -> Animation { reduceMotion ? reducedFade : open }
        public static func close(reduceMotion: Bool) -> Animation { reduceMotion ? reducedFade : close }
        public static func content(reduceMotion: Bool) -> Animation { reduceMotion ? reducedFade : content }
        public static func snappy(reduceMotion: Bool) -> Animation { reduceMotion ? reducedFade : snappy }
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The user's accent colour. Amber unless changed in Settings.
    @Entry public var altilloAccent: Color = Tokens.Palette.amber
}

// MARK: - Helpers

extension Color {
    /// `Color(hex: 0x1C1917)`, sRGB.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// How worried the user should be about a usage figure.
public enum UsageLevel: Sendable, Equatable {
    case normal, warning, critical

    /// ≥ 80 % warns, ≥ 95 % is critical (defaults; per-provider thresholds arrive in phase 3).
    public init(fraction: Double, warning: Double = 0.8, critical: Double = 0.95) {
        if fraction >= critical { self = .critical }
        else if fraction >= warning { self = .warning }
        else { self = .normal }
    }

    /// Tint for rings and bars. Normal usage stays neutral so alerts are the only thing that pops.
    public var tint: Color {
        switch self {
        case .normal: Tokens.Palette.text.opacity(0.92)
        case .warning: Tokens.Palette.warning
        case .critical: Tokens.Palette.critical
        }
    }
}
