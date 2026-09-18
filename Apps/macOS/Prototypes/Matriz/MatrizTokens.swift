import AltilloDesign
import AppKit
import CoreText
import SwiftUI

/// Design tokens of the "Matriz" direction (docs/design/direcciones.md § Dirección A): the notch is a switched-off
/// hardware display that Altillo lights up dot by dot.
enum Matriz {}

// MARK: - Palette

extension Matriz {
    enum Palette {
        /// Silhouette and the open notch background. No filled cards: dot grids and hairlines give the structure.
        static let notch = Color.black
        /// Wells (an agent's command, drop fields).
        static let panel = Color(hex: 0x0D0D0C)
        /// Secondary button, selected row.
        static let panelRaised = Color(hex: 0x161614)
        /// A switched-off LED: grids, empty ring and bar segments.
        static let dotOff = Color(hex: 0x262522)
        /// A slightly brighter off-LED, for glyphs that must read while unlit.
        static let dotDim = Color(hex: 0x3A3833)
        /// Text and lit LEDs: warm phosphor white.
        static let phosphor = Color(hex: 0xF4F1EA)
        /// Secondary text (≈ 6:1 on black).
        static let phosphor2 = Color(hex: 0xF4F1EA).opacity(0.58)
        /// Decoration and disabled only (not AA for text).
        static let phosphor3 = Color(hex: 0xF4F1EA).opacity(0.34)
        /// "I need you": waiting agent, armed drop zone, brand dot. Replaced by the user's accent.
        static let signal = Color(hex: 0xFF4D1F)
        /// Warning (≥ 80 %, above pace).
        static let amber = Color(hex: 0xFFB000)
        /// ≥ 95 %, errors. Never follows the accent.
        static let critical = Color(hex: 0xFF3B2F)
        /// Only while the pointer is over the AirDrop field.
        static let airdrop = Color(hex: 0x3FA9FF)
        /// 1-px hairlines around thumbnails.
        static let hairline = Color(hex: 0xF4F1EA).opacity(0.14)

        static func usage(_ fraction: Double) -> Color {
            switch UsageLevel(fraction: fraction) {
            case .normal: phosphor
            case .warning: amber
            case .critical: critical
            }
        }
    }
}

// MARK: - Motion

extension Matriz {
    /// Mechanical and precise: springs without bounce; the life comes from the LEDs, not from movement.
    enum Motion {
        static let open = Animation.spring(duration: 0.36, bounce: 0.08)
        static let close = Animation.spring(duration: 0.28, bounce: 0)
        /// The scanline that "writes" new content from top to bottom.
        static let scanline = Animation.easeOut(duration: 0.12)
        /// Peek text enters like a sign, left to right.
        static let marquee = Animation.easeOut(duration: 0.18)
        /// Per-dot stagger of the power-on sequence and each dot's rise time.
        static let dotStagger: Double = 0.006
        static let dotRise: Double = 0.09
        static let press = Animation.easeOut(duration: 0.1)
        /// The only bounce of the direction: something landing in the shelf has real momentum.
        static let landing = Animation.spring(duration: 0.3, bounce: 0.2)
        /// Reduce Motion: every movement becomes a 150 ms fade.
        static let reduced = Animation.easeInOut(duration: 0.15)

        static func open(_ reduce: Bool) -> Animation { reduce ? reduced : open }
        static func close(_ reduce: Bool) -> Animation { reduce ? reduced : close }
        static func snappy(_ reduce: Bool) -> Animation { reduce ? reduced : .spring(duration: 0.22, bounce: 0) }
    }
}

// MARK: - Fonts

extension Matriz {
    /// Doto (numbers) and Departure Mono (labels), bundled under Prototypes/Matriz/Fonts and registered at runtime for
    /// this process only, so the prototype needs no Info.plist change.
    enum Fonts {
        static let registered: Bool = {
            var ok = true
            for (name, ext) in [("Doto-Variable", "ttf"), ("DepartureMono-Regular", "otf")] {
                guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
                    ok = false
                    continue
                }
                var error: Unmanaged<CFError>?
                if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                    // Already registered (e.g. a second panel) is fine.
                    let code = (error?.takeRetainedValue()).map { CFErrorGetCode($0) } ?? 0
                    if code != CTFontManagerError.alreadyRegistered.rawValue { ok = false }
                }
            }
            return ok
        }()

        private static let wghtTag = 0x7767_6874 // 'wght'
        private static let rondTag = 0x524F_4E44 // 'ROND'

        /// Doto at an explicit weight and dot roundness (0 = square dots, 100 = round LEDs).
        static func doto(_ size: CGFloat, weight: CGFloat = 800, roundness: CGFloat = 100) -> Font {
            _ = registered
            let variation: [NSNumber: NSNumber] = [
                NSNumber(value: wghtTag): NSNumber(value: Double(weight)),
                NSNumber(value: rondTag): NSNumber(value: Double(roundness)),
            ]
            let attributes: [CFString: Any] = [
                kCTFontFamilyNameAttribute: "Doto",
                kCTFontVariationAttribute: variation,
            ]
            let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
            return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        }

        /// Departure Mono: designed on an 11-px grid, so 11 pt (22 px on Retina) or multiples.
        static func departure(_ size: CGFloat = 11) -> Font {
            _ = registered
            return .custom("DepartureMono-Regular", fixedSize: size)
        }
    }
}

extension Text {
    /// Uppercase instrument label: Departure Mono, tracking +0.06 em.
    func matrizLabel(_ size: CGFloat = 11) -> Text {
        font(Matriz.Fonts.departure(size)).tracking(size * 0.06)
    }
}
