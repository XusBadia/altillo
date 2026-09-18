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

    /// The identity colour of a shelf item, by kind (tag edge, never state).
    static func labelColor(for item: ShelfItem) -> Color {
        switch item.kind {
        case .text: return Palette.mustard
        case .link: return Palette.lavender
        case let .file(url, _):
            let ext = url.pathExtension.lowercased()
            if ["png", "jpg", "jpeg", "heic", "gif", "tiff", "webp"].contains(ext) { return Palette.sky }
            if ext == "pdf" { return Palette.tomato }
            if ["txt", "md", "rtf", "doc", "docx", "pages"].contains(ext) { return Palette.sage }
            if ["zip", "dmg", "tar", "gz", "rar", "7z"].contains(ext) { return Palette.sand }
            if ["mov", "mp4", "m4v", "mp3", "wav", "m4a"].contains(ext) { return Palette.rose }
            return Palette.kraft
        }
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
        static let pendulum = Animation.interpolatingSpring(stiffness: 120, damping: 6)
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
    /// Fraunces for the logotype, empty-state titles and the "Hecho" stamp; New York for figures;
    /// SF Pro Rounded for tabs, buttons and chips; SF Pro / SF Mono for names, sentences and commands.
    enum Typeface {
        /// New York with tabular digits.
        static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .serif).monospacedDigit()
        }

        static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
            .system(size: size, weight: weight, design: .rounded)
        }

        /// Fraunces with its soft, slightly wonky personality (`SOFT 100`, `WONK 1`), optical size following the
        /// point size. Falls back to New York if the bundled font can't be loaded.
        @MainActor
        static func fraunces(_ size: CGFloat, weight: CGFloat = 600, italic: Bool = false) -> Font {
            FrauncesLoader.font(size: size, weight: weight, italic: italic)
                ?? (italic
                    ? .system(size: size, weight: .semibold, design: .serif).italic()
                    : .system(size: size, weight: .semibold, design: .serif))
        }
    }
}

/// Registers the bundled Fraunces variable fonts (OFL, see Fonts/Fraunces-OFL.txt) for this process and builds
/// instances with explicit variation axes.
@MainActor
enum FrauncesLoader {
    private static var cache: [String: Font] = [:]

    private static let descriptors: (roman: CTFontDescriptor?, italic: CTFontDescriptor?) = {
        func load(_ name: String) -> CTFontDescriptor? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { return nil }
            var error: Unmanaged<CFError>?
            // Process scope: nothing is installed system-wide. Already-registered is fine.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let all = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
            return all?.first
        }
        return (load("Fraunces-Variable"), load("Fraunces-Italic-Variable"))
    }()

    private static func tag(_ string: String) -> NSNumber {
        NSNumber(value: string.unicodeScalars.reduce(UInt32(0)) { ($0 << 8) | $1.value })
    }

    static func font(size: CGFloat, weight: CGFloat, italic: Bool) -> Font? {
        let key = "\(size)-\(weight)-\(italic)"
        if let font = cache[key] { return font }
        guard let base = italic ? descriptors.italic : descriptors.roman else { return nil }
        let variation: [NSNumber: NSNumber] = [
            tag("wght"): NSNumber(value: Double(weight)),
            tag("opsz"): NSNumber(value: Double(min(max(size, 9), 144))),
            tag("SOFT"): 100,
            tag("WONK"): 1,
        ]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(
            base,
            [kCTFontVariationAttribute: variation] as CFDictionary
        )
        let font = Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        cache[key] = font
        return font
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

/// Launch flag for design screenshots only: `-prototypeHoverZone shelf|airDrop` lights that zone in the frozen
/// dropTarget scenario, as if the pointer were over it.
enum DesvanDebug {
    static let forcedZone: DropZone? = switch UserDefaults.standard.string(forKey: "prototypeHoverZone") {
    case "shelf": .shelf
    case "airDrop", "airdrop": .airDrop
    default: nil
    }
}
