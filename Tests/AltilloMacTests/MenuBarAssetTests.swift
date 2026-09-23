import AppKit
import Testing
@testable import Altillo

@MainActor
struct MenuBarAssetTests {
    @Test func menuBarAssetHasStatusItemDimensions() throws {
        let icon = try #require(NSImage(named: "MenuBarIcon"))
        // A 1024-point SVG silently creates a huge status item and pushes all
        // neighbouring menu extras off-screen, breaking Drawer movement.
        #expect(icon.size.width > 0 && icon.size.width <= 24)
        #expect(icon.size.height > 0 && icon.size.height <= 24)
    }
}
