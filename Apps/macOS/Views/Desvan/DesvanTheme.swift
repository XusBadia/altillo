import AltilloCore
import AltilloDesign
import CoreText
import SwiftUI

// Direction B · «Desván» (docs/design/direcciones.md): the attic at home. A warm bulb, cardboard boxes, paper tags.
// Tokens live here so every Desván view reads from one place.

enum Desvan {}

// MARK: - Palette

extension Desvan {
    enum Palette {
        /// The silhouette. Always pure opaque black.
        static let notch = Color.black
        /// Cards: dark wood.
        static let wood = Color(hex: 0x1E1914)
        /// Raised elements and wells on a card.
        static let woodRaised = Color(hex: 0x2A231C)
        /// The shelf plank, tracks.
        static let plank = Color(hex: 0x3A3027)
        /// Text: warm paper white.
        static let paper = Color(hex: 0xF6EFE3)
        static let paperSecondary = Color(hex: 0xF6EFE3).opacity(0.62)
        static let paperTertiary = Color(hex: 0xF6EFE3).opacity(0.38)
        /// Ink for text written on kraft or on the bulb.
        static let ink = Color(hex: 0x2B241D)
        /// Text on the bulb-filled primary button.
        static let bulbInk = Color(hex: 0x2B1A05)
        /// The bulb: light, not paint. Focus, drop, "I need you".
        static let bulb = Color(hex: 0xFFB547)
        /// Luggage tags.
        static let kraft = Color(hex: 0xC9A77C)
        /// Cardboard of the box (a touch more saturated than the tags).
        static let cardboard = Color(hex: 0xB08858)
        static let cardboardDark = Color(hex: 0x8A6843)
        /// Masking tape.
        static let tape = Color(hex: 0xE9DCBC)

        /// Hairlines on wood.
        static let hairline = Color(hex: 0xF6EFE3).opacity(0.08)
        static let hairlineStrong = Color(hex: 0xF6EFE3).opacity(0.14)
        static let lip = Color(hex: 0xF6EFE3).opacity(0.12)

        // The seven label colours (à la Tot). Identity only, never state.
        static let tomato = Color(hex: 0xF2674A)
        static let mustard = Color(hex: 0xE8B33A)
        static let sage = Color(hex: 0x9DB88A)
        static let sky = Color(hex: 0x86B6D9)
        static let lavender = Color(hex: 0xB7A3E0)
        static let rose = Color(hex: 0xEE9FB5)
        static let sand = Color(hex: 0xD8C3A0)

        // State: warning = mustard, critical = tomato, done = sage. Never colour alone: always with a word or icon.
        static let warning = mustard
        static let critical = tomato
        static let done = sage
    }


    /// Usage tint: paper while calm, mustard from 80 %, tomato from 95 %.
    static func usageTint(_ fraction: Double) -> Color {
        switch UsageLevel(fraction: fraction) {
        case .normal: Palette.paper
        case .warning: Palette.warning
        case .critical: Palette.critical
        }
    }

    /// A stable pseudo-random value in -1…1 derived from an id (the same across launches, unlike `hashValue`).
    static func jitter(_ id: UUID, salt: UInt8 = 0) -> Double {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        var hash: UInt32 = 2_166_136_261
        for byte in bytes + [salt] {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return Double(hash % 2001) / 1000 - 1
    }
}

// MARK: - Motion

extension Desvan {
    /// Soft, with weight: things fall, bounce a little and settle. Closing never bounces.
    enum Motion {
        static let open = Animation.spring(duration: 0.44, bounce: 0.2)
        static let close = Animation.spring(duration: 0.32, bounce: 0)
        static let content = Animation.spring(duration: 0.30, bounce: 0)
        static let settle = Animation.spring(duration: 0.5, bounce: 0.35)
        static let flaps = Animation.spring(duration: 0.26, bounce: 0.28)
        static let flapsClose = Animation.spring(duration: 0.22, bounce: 0)
        static let hover = Animation.easeOut(duration: 0.15)
        static let fade = Animation.easeInOut(duration: 0.18)

        static func pick(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? fade : animation
        }
    }
}

// MARK: - Typography

extension Desvan {
    /// SF Pro Rounded for titles, empty states, the "Hecho" stamp and figures;
    /// SF Pro Rounded for tabs, buttons and chips; SF Pro / SF Mono for names, sentences and commands.
    enum Typeface {
        /// Big numbers: SF Pro Rounded, one step bolder than asked, with tabular digits.
        static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight == .semibold ? .bold : weight, design: .rounded).monospacedDigit()
        }

        static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        /// Titles, empty states and the stamp: SF Pro Rounded (chosen by the user over bundled display fonts).
        /// `weight` keeps the old variable-font scale (100–900).
        static func display(_ size: CGFloat, weight: CGFloat = 600, italic: Bool = false) -> Font {
            let font = Font.system(size: size, weight: Self.weight(weight), design: .rounded)
            return italic ? font.italic() : font
        }

        private static func weight(_ value: CGFloat) -> Font.Weight {
            switch value {
            case ..<350: .regular
            case ..<550: .medium
            case ..<650: .semibold
            case ..<750: .bold
            default: .heavy
            }
        }
    }
}

// MARK: - Chrome

extension Desvan {
    /// The shared silhouette geometry, with a little more room for Desván's peek sentences.
    @MainActor
    static func chrome(for model: NotchModel) -> NotchChrome {
        var chrome = NotchChrome(model: model)
        if case let .peek(kind) = chrome.face, kind != .hint {
            let width: CGFloat = kind == .agentWaiting ? 452 : 436
            chrome.size.width = width + 2 * chrome.topRadius
        }
        return chrome
    }
}

/// Launch flags for design reviews only.
///
/// - `-prototypeHoverZone shelf|airDrop` lights that zone in the frozen dropTarget scenario, as if the pointer were
///   over it.
/// - `-demoMotion landing|flaps|knock|stamp|approach` loops a signature moment in its design scenario so it can be
///   watched (and recorded) live: `landing` in openShelf, `flaps` in dropTarget, `knock` in peekAgentWaiting or
///   openAgents (the knock already repeats every 3 s), `stamp` in openAgents, `approach` in dragArmed. Nothing runs
///   without the flag, and nothing runs outside a design scenario.
enum DesvanDebug {
    static let forcedZone: DropZone? = switch UserDefaults.standard.string(forKey: "prototypeHoverZone") {
    case "shelf": .shelf
    case "airDrop", "airdrop": .airDrop
    default: nil
    }

    enum Moment: String {
        case landing, flaps, knock, stamp, approach
    }

    static let demoMotion: Moment? = UserDefaults.standard.string(forKey: "demoMotion").flatMap(Moment.init(rawValue:))

    /// Ticks while a `-demoMotion` loop runs; views replay their moment on each tick.
    @MainActor static let clock = MotionClock()

    @MainActor
    @Observable
    final class MotionClock {
        /// Increments every `period`; `phase` alternates on each tick (open/closed, near/far).
        private(set) var tick = 0
        var phase: Bool { tick % 2 == 1 }

        /// Runs until cancelled (tie it to the scenario's `.task`). Does nothing without `-demoMotion`.
        func run(for scenario: DesignScenario?) async {
            guard let moment = DesvanDebug.demoMotion, scenario != nil else { return }
            let period: Duration = switch moment {
            case .flaps, .approach: .milliseconds(1400)
            case .landing, .knock, .stamp: .milliseconds(2500)
            }
            try? await Task.sleep(for: .milliseconds(700))
            while !Task.isCancelled {
                tick += 1
                try? await Task.sleep(for: period)
            }
        }
    }
}
