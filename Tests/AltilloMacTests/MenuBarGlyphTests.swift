import AppKit
import Testing
@testable import Altillo

@MainActor
struct MenuBarGlyphTests {
    @Test func compactSymbolsShareOneOpticalSize() {
        #expect(MenuBarGlyph.size(for: CGSize(width: 12, height: 12), allowsEnlarging: true) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 12, height: 12)) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 20, height: 20)) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 24, height: 18)) == CGSize(width: 18, height: 13.5))
        #expect(MenuBarGlyph.size(for: CGSize(width: 36, height: 36)) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 18, height: 12)) == CGSize(width: 18, height: 12))
    }

    @Test func textStatusItemsShareAHeightAndOccupyWholeSlots() {
        let source = CGSize(width: 96, height: 12)
        #expect(MenuBarGlyph.size(for: source) == CGSize(width: 144, height: 18))
        #expect(MenuBarGlyph.cellWidth(for: source) == 154)
        #expect(MenuBarGlyph.cellWidth(for: CGSize(width: 18, height: 18)) == 34)
        #expect(MenuBarGlyph.cellWidth(for: CGSize(width: 24, height: 24)) == 34)
    }

    @Test func oversizedStatusItemsFitSettingsWithoutDistortion() {
        let size = MenuBarGlyph.size(for: CGSize(width: 400, height: 20))
        #expect(size.width == 178)
        #expect(abs(size.width / size.height - 20) < 0.001)
        #expect(MenuBarGlyph.cellWidth(for: CGSize(width: 400, height: 20)) == 194)
    }
}

@MainActor
struct MenuBarGlyphSharpnessTests {
    private func bitmap(pixels: Int, scale: CGFloat) -> NSImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(cgImage: rep.cgImage!, size: CGSize(width: CGFloat(pixels) / scale, height: CGFloat(pixels) / scale))
        return image
    }

    @Test func capturedGlyphsUseTheCommonOpticalBox() {
        let oneX = bitmap(pixels: 14, scale: 1)
        #expect(!MenuBarGlyph.allowsEnlarging(oneX))
        #expect(MenuBarGlyph.size(of: oneX) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.pixelScale(of: oneX) == 1)
        let twoX = bitmap(pixels: 30, scale: 2)
        #expect(MenuBarGlyph.size(of: twoX) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.pixelScale(of: twoX) == 2)
        #expect(MenuBarGlyph.size(of: bitmap(pixels: 40, scale: 1)) == CGSize(width: 18, height: 18))
    }

    @Test func vectorSymbolsMayGrowToTheOpticalBox() throws {
        let symbol = try #require(NSImage(systemSymbolName: "icloud", accessibilityDescription: nil))
        #expect(MenuBarGlyph.allowsEnlarging(symbol))
        #expect(max(MenuBarGlyph.size(of: symbol).width, MenuBarGlyph.size(of: symbol).height) == 18)
    }

    // MARK: - Fallbacks instead of placeholders

    private static func entry(owner: String, title: String = "Item") -> MenuBarEntry {
        MenuBarEntry(id: "\(owner)|\(title)", application: MenuBarApplication(pid: 42, bundleID: owner, name: owner),
                     title: title, frame: CGRect(x: 0, y: 3, width: 24, height: 24))
    }

    @Test func aCapturedGlyphAlwaysWins() {
        let entry = Self.entry(owner: "com.apple.MenuBarAgent", title: "Wi-Fi")
        #expect(MenuBarGlyphFallback.source(for: entry, hasCapture: true, captureFailed: true,
                                            hasApplicationIcon: true) == .captured)
    }

    @Test func aPendingCaptureIsSkippedRatherThanShownAsAPlaceholder() {
        let entry = Self.entry(owner: "test.app")
        #expect(MenuBarGlyphFallback.source(for: entry, hasCapture: false, captureFailed: false,
                                            hasApplicationIcon: true) == .none)
    }

    @Test func aFailedCaptureFallsBackToTheOwnersIcon() {
        let entry = Self.entry(owner: "test.app")
        #expect(MenuBarGlyphFallback.source(for: entry, hasCapture: false, captureFailed: true,
                                            hasApplicationIcon: true) == .applicationIcon)
    }

    @Test func systemItemsFallBackToTheirSymbolNotAGenericAgentIcon() {
        let wifi = Self.entry(owner: "com.apple.MenuBarAgent", title: "Wi‑Fi, connected, 3 bars")
        #expect(MenuBarGlyphFallback.source(for: wifi, hasCapture: false, captureFailed: true,
                                            hasApplicationIcon: true) == .systemSymbol("wifi"))
        let clock = Self.entry(owner: "com.apple.MenuBarAgent", title: "Clock")
        #expect(MenuBarGlyphFallback.source(for: clock, hasCapture: false, captureFailed: true,
                                            hasApplicationIcon: false) == .systemSymbol("clock"))
    }

    @Test func anItemWithNothingToDrawIsSkipped() {
        let entry = Self.entry(owner: "test.app")
        #expect(MenuBarGlyphFallback.source(for: entry, hasCapture: false, captureFailed: true,
                                            hasApplicationIcon: false) == .none)
    }

    @Test func applicationIconFallbackIsDrawnAtTheStripsGlyphSize() throws {
        let icon = NSImage(size: CGSize(width: 512, height: 512), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let glyph = MenuBarGlyphFallback.glyph(fromApplicationIcon: icon)
        #expect(glyph.size == CGSize(width: MenuBarGlyph.box, height: MenuBarGlyph.box))
        #expect(!glyph.isTemplate)
        #expect(MenuBarGlyph.size(of: glyph) == CGSize(width: MenuBarGlyph.box, height: MenuBarGlyph.box))
        let pixels = try #require(glyph.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width > 0)
    }

    @Test func genericArtworkIsRecognizedWithoutRejectingRealSquareLogos() {
        let generic = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill(); return true
        }
        let real = NSImage(size: CGSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemBlue.setFill(); rect.fill(); return true
        }
        #expect(MenuBarGlyphFallback.isGenericApplicationIcon(generic, generic: generic))
        #expect(!MenuBarGlyphFallback.isGenericApplicationIcon(real, generic: generic))
    }

    @Test func missingArtworkUsesReadableInitials() throws {
        #expect(MenuBarGlyphFallback.initials(for: "OpenUsage Mobile Bridge") == "OM")
        #expect(MenuBarGlyphFallback.initials(for: "  Ollama  ") == "OL")
        #expect(MenuBarGlyphFallback.initials(for: "") == "?")
        let icon = MenuBarGlyphFallback.monogram(for: "OpenUsage Mobile Bridge")
        #expect(icon.isTemplate)
        #expect(icon.size == CGSize(width: 18, height: 18))
        #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil)
    }

    @Test func hoverStartsWithAppNameAndAvoidsRepeatingIt() {
        let app = MenuBarApplication(pid: 0, bundleID: "test", name: "Example")
        let same = MenuBarEntry(id: "1", application: app, title: "Example", frame: .zero)
        let detail = MenuBarEntry(id: "2", application: app, title: "Syncing", frame: .zero)
        #expect(same.hoverName == "Example")
        #expect(detail.hoverName == "Example — Syncing")
        let keyboard = MenuBarEntry(id: "input", application: .init(pid: 0,
            bundleID: "com.apple.TextInputMenuAgent", name: "TextInputMenuAgent"), title: "", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: keyboard) == "keyboard")
    }
}
