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
    /// Soft, with weight: things fall, squash a little and settle. Closing never bounces. With Reduce Motion, fades.
    ///
    /// The open notch is liquid rather than bouncy: the silhouette grows out of the notch, runs a little past its
    /// size and settles, while its content comes into focus a hair behind it (blurred and slightly small → sharp).
    /// Closing is quicker: the content blurs away first and the shape slips back into the notch without a bounce.
    enum Motion {
        /// The silhouette opening: peaks ≈ 280 ms in, ≈ 4–5 % past its size, settles over the next ≈ 250 ms.
        static let openSpring = Tokens.Motion.openSpring
        /// The silhouette closing: ≈ 200 ms to 90 %, critically damped.
        static let closeSpring = Tokens.Motion.closeSpring
        static let open = Animation.spring(openSpring)
        static let close = Animation.spring(closeSpring)
        /// Opening near the edge of the panel, where an overshoot would be cut off: the same pace, no overshoot.
        static let openFlat = Animation.spring(duration: 0.36, bounce: 0)

        /// Changing section: the tab plaque, the body's slide and the silhouette's new height, as one motion.
        static let sectionSpring = Spring(duration: 0.32, bounce: 0.15)
        static let section = Animation.spring(sectionSpring)
        /// The silhouette getting shorter for a section: an overshoot inwards would clip the content, so none.
        static let sectionShrink = Animation.spring(duration: 0.3, bounce: 0)

        /// A face coming into focus, a hair behind the silhouette that grows around it.
        static let focusIn = Animation.spring(duration: 0.3, bounce: 0)
        /// A face leaving: gone in ≈ 120 ms, before the shape has collapsed onto it.
        static let focusOut = Animation.easeOut(duration: 0.12)

        static let content = Animation.spring(duration: 0.30, bounce: 0)
        static let settle = Animation.spring(duration: 0.5, bounce: 0.35)
        static let flaps = Animation.spring(duration: 0.26, bounce: 0.28)
        static let flapsClose = Animation.spring(duration: 0.22, bounce: 0)
        /// Hover highlights: reads in ≈ 100 ms.
        static let hover = Animation.easeOut(duration: 0.12)
        /// Pressing something: it gives in ≈ 100 ms and comes back without a wobble.
        static let press = Animation.spring(duration: 0.16, bounce: 0)
        /// A thing lifting under the pointer: quick, with a touch of spring.
        static let lift = Animation.spring(duration: 0.2, bounce: 0.2)
        static let fade = Animation.easeInOut(duration: 0.18)

        /// How far the open notch's body leans when a swipe runs past the first or last section.
        static let edgeLean: CGFloat = 8

        static func pick(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? fade : animation
        }

        /// The animation for one axis of the silhouette as it goes from one face (or size) to another.
        ///
        /// Each axis picks its own spring: whatever grows gets the liquid overshoot, whatever shrinks never
        /// bounces (an overshoot inwards would cut into content laid out at its final size). A peek grows sideways
        /// first and then drops its line (its height waits 50 ms); leaving a peek it does the reverse.
        static func silhouette(
            _ axis: Axis,
            from: (face: NotchFace, length: CGFloat),
            to: (face: NotchFace, length: CGFloat),
            limit: CGFloat = .infinity,
            reduceMotion: Bool
        ) -> Animation {
            if reduceMotion { return fade }
            let grows = to.length > from.length
            if from.face == to.face {
                // Same face, new size: a section of a different height, the drop box, the Drawer.
                return grows ? section : sectionShrink
            }
            // The overshoot must stay inside the panel, or its edge would be cut off mid-flight.
            let overshoot = (to.length - from.length) * 0.06
            var animation = grows ? (to.length + overshoot > limit ? openFlat : open) : close
            switch (from.face, to.face, axis) {
            case (_, .peek, .vertical) where grows:
                animation = animation.delay(0.05)
            case (.peek, .rest, .horizontal), (.peek, .ears, .horizontal):
                animation = animation.delay(0.04)
            default:
                break
            }
            return animation
        }

        /// Which way the open notch's body slides when it swaps from the section keyed `old` to `new` (module raw
        /// values, or "drop" for the box): the model's direction when it really came from a neighbour in the tab
        /// strip, 0 (a vertical crossfade) for the drop box, a jump or a stale direction.
        static func sectionDirection(from old: String, to new: String, modules: [NotchModule],
                                     moduleDirection: Int) -> Int {
            guard moduleDirection != 0,
                  let from = modules.firstIndex(where: { $0.rawValue == old }),
                  let to = modules.firstIndex(where: { $0.rawValue == new }) else { return 0 }
            return (to - from).signum() == moduleDirection.signum() ? moduleDirection.signum() : 0
        }

        /// How much a face is out of focus before it arrives: the open notch the most, the small faces a touch.
        static func focusDepth(_ face: NotchFace) -> (blur: CGFloat, scale: CGFloat) {
            switch face {
            case .expanded: (Tokens.Motion.focusBlur, Tokens.Motion.focusScale)
            case .peek(.hint), .ears: (3, 0.98)
            case .peek, .dragArmed: (6, 0.97)
            case .rest: (0, 1)
            }
        }

        /// How long a face waits for the silhouette before it starts to come into focus. A peek waits for its
        /// sideways growth, so its line sharpens as the shape drops.
        static func focusDelay(_ face: NotchFace) -> Double {
            switch face {
            case .expanded: 0.05
            case .peek(.hint): 0.03
            case .peek: 0.08
            case .ears, .dragArmed, .rest: 0.03
            }
        }

        /// Faces come into focus as the silhouette grows around them and blur away quickly when it leaves.
        @MainActor
        static func face(_ face: NotchFace, reduceMotion: Bool) -> some Transition {
            let depth = focusDepth(face)
            return AsymmetricTransition(
                insertion: FocusTransition(blur: depth.blur, scale: depth.scale, reduceMotion: reduceMotion)
                    .animation(reduceMotion ? fade : focusIn.delay(focusDelay(face))),
                removal: FocusTransition(blur: depth.blur * 0.6, scale: 1 - (1 - depth.scale) / 2,
                                         reduceMotion: reduceMotion)
                    .animation(reduceMotion ? fade : focusOut)
            )
        }
    }
}

// MARK: - Typography

extension Desvan {
    /// SF Pro Rounded for titles, empty states, the "Done" stamp and figures;
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
/// - `-demoShelfCount <n>` repeats the sample files until the shelf holds `n` things, to review how the row
///   scrolls when the altillo is full.
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

    /// How many things the design scenarios put on the shelf (nil: the six real samples).
    static let demoShelfCount: Int? = {
        let value = UserDefaults.standard.integer(forKey: "demoShelfCount")
        return value > 0 ? min(value, 60) : nil
    }()

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
