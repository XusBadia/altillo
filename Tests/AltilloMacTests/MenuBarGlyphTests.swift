import AppKit
import Testing
@testable import Altillo

@MainActor
struct MenuBarGlyphTests {
    @Test func compactSymbolsShareOpticalSize() {
        #expect(MenuBarGlyph.size(for: CGSize(width: 12, height: 12)) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 36, height: 36)) == CGSize(width: 18, height: 18))
        #expect(MenuBarGlyph.size(for: CGSize(width: 18, height: 12)) == CGSize(width: 18, height: 12))
    }

    @Test func textStatusItemsRemainLegibleAndOccupyWholeSlots() {
        let source = CGSize(width: 96, height: 16)
        #expect(MenuBarGlyph.size(for: source) == CGSize(width: 84, height: 14))
        #expect(MenuBarGlyph.cellWidth(for: source) == 114)
        #expect(MenuBarGlyph.cellWidth(for: CGSize(width: 18, height: 18)) == 34)
    }

    @Test func oversizedStatusItemsFitSettingsWithoutDistortion() {
        let size = MenuBarGlyph.size(for: CGSize(width: 400, height: 20))
        #expect(size.width == 178)
        #expect(abs(size.width / size.height - 20) < 0.001)
        #expect(MenuBarGlyph.cellWidth(for: CGSize(width: 400, height: 20)) == 194)
    }
}
