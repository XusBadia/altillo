import AppKit
import Testing
@testable import Altillo

@MainActor
struct MenuBarGlyphTests {
    @Test func compactSymbolsShareOpticalSizeOnlyWhenTheyCanScaleCleanly() {
        // Vector sources are fitted to the 18 pt box.
        #expect(MenuBarGlyph.size(for: CGSize(width: 12, height: 12), allowsEnlarging: true) == CGSize(width: 18, height: 18))
        // Captured bitmaps keep their native size up to a full 24 pt status item; larger ones shrink to fit.
        #expect(MenuBarGlyph.size(for: CGSize(width: 12, height: 12)) == CGSize(width: 12, height: 12))
        #expect(MenuBarGlyph.size(for: CGSize(width: 20, height: 20)) == CGSize(width: 20, height: 20))
        #expect(MenuBarGlyph.size(for: CGSize(width: 24, height: 18)) == CGSize(width: 24, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 36, height: 36)) == CGSize(width: 24, height: 24))
        #expect(MenuBarGlyph.size(for: CGSize(width: 18, height: 12)) == CGSize(width: 18, height: 12))
    }

    @Test func textStatusItemsKeepTheirNativePixelsAndOccupyWholeSlots() {
        let source = CGSize(width: 96, height: 12)
        #expect(MenuBarGlyph.size(for: source) == source)
        #expect(MenuBarGlyph.cellWidth(for: source) == 114)
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

    @Test func capturedGlyphsAreNeverEnlargedBeyondTheirPixels() {
        // A 1x capture of a 14 pt symbol keeps 14 px instead of being stretched to 18 (the blur).
        let oneX = bitmap(pixels: 14, scale: 1)
        #expect(!MenuBarGlyph.allowsEnlarging(oneX))
        #expect(MenuBarGlyph.size(of: oneX) == CGSize(width: 14, height: 14))
        #expect(MenuBarGlyph.pixelScale(of: oneX) == 1)
        let twoX = bitmap(pixels: 30, scale: 2)
        #expect(MenuBarGlyph.size(of: twoX) == CGSize(width: 15, height: 15))
        #expect(MenuBarGlyph.pixelScale(of: twoX) == 2)
        // Oversized captures still shrink to a status item's height.
        #expect(MenuBarGlyph.size(of: bitmap(pixels: 40, scale: 1)) == CGSize(width: 24, height: 24))
    }

    @Test func vectorSymbolsMayGrowToTheOpticalBox() throws {
        let symbol = try #require(NSImage(systemSymbolName: "icloud", accessibilityDescription: nil))
        #expect(MenuBarGlyph.allowsEnlarging(symbol))
        #expect(max(MenuBarGlyph.size(of: symbol).width, MenuBarGlyph.size(of: symbol).height) == 18)
    }
}
