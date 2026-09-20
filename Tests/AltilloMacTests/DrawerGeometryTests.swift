import CoreGraphics
import Foundation
import Testing
@testable import Altillo

/// Pure Drawer policy and geometry. These tests never call `start()` or create a status item.
@MainActor
struct DrawerGeometryTests {
    private static func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "me.badia.altillo.tests.drawer-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func appKitFrameConvertsToAccessibilityCoordinates() {
        let appKit = CGRect(x: 1_240, y: 956, width: 20, height: 24)

        let accessibility = DrawerGeometry.accessibilityFrame(appKit, primaryScreenHeight: 1_000)

        #expect(accessibility == CGRect(x: 1_240, y: 20, width: 20, height: 24))
    }

    @Test func coordinateConversionUsesThePrimaryScreensGlobalTopEdge() {
        let appKit = CGRect(x: -40, y: 1_176, width: 18, height: 24)

        let accessibility = DrawerGeometry.accessibilityFrame(appKit, primaryScreenHeight: 1_200)

        #expect(accessibility == CGRect(x: -40, y: 0, width: 18, height: 24))
    }

    @Test func itemFullyLeftOfDividerOnTheSameRowBelongsToDrawer() {
        let divider = CGRect(x: 300, y: 0, width: 20, height: 24)
        let item = CGRect(x: 260, y: 2, width: 22, height: 20)

        #expect(DrawerGeometry.isBeforeSeparator(item, separator: divider))
    }

    @Test func onePointLayoutToleranceStillCountsAsBeforeDivider() {
        let divider = CGRect(x: 300, y: 0, width: 20, height: 24)
        let item = CGRect(x: 280, y: 0, width: 21, height: 24)

        #expect(DrawerGeometry.isBeforeSeparator(item, separator: divider))
    }

    @Test func overlappingOrRightHandItemsStayOutOfDrawer() {
        let divider = CGRect(x: 300, y: 0, width: 20, height: 24)

        #expect(!DrawerGeometry.isBeforeSeparator(
            CGRect(x: 290, y: 0, width: 20, height: 24),
            separator: divider
        ))
        #expect(!DrawerGeometry.isBeforeSeparator(
            CGRect(x: 330, y: 0, width: 20, height: 24),
            separator: divider
        ))
    }

    @Test func anotherMenuBarRowDoesNotBelongToThisDivider() {
        let divider = CGRect(x: 300, y: 0, width: 20, height: 24)

        #expect(!DrawerGeometry.isBeforeSeparator(
            CGRect(x: 260, y: 40, width: 20, height: 20),
            separator: divider
        ))
    }

    @Test func nonRenderableFramesNeverBelongToDrawer() {
        let divider = CGRect(x: 300, y: 0, width: 20, height: 24)

        #expect(!DrawerGeometry.isBeforeSeparator(
            CGRect(x: 260, y: 0, width: 0, height: 20),
            separator: divider
        ))
        #expect(!DrawerGeometry.isBeforeSeparator(
            CGRect(x: 260, y: 0, width: 20, height: 0),
            separator: divider
        ))
    }

    @Test func legacyHidingIsGatedToMacOS26() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        #expect(!MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 25).isSupported)
        #expect(MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 26).isSupported)
        #expect(!MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 27).isSupported)
    }

    @Test func naturallyOverflowingIconsCannotOpenAnOffscreenMenu() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(!DrawerGeometry.hasVisibleAnchor(CGRect(x: -84, y: 3, width: 45, height: 24), screens: [screen]))
        #expect(!DrawerGeometry.hasVisibleAnchor(CGRect(x: -10, y: 3, width: 45, height: 24), screens: [screen]))
        #expect(DrawerGeometry.hasVisibleAnchor(CGRect(x: 200, y: 3, width: 45, height: 24), screens: [screen]))
        #expect(!DrawerGeometry.hasVisibleAnchor(.zero, screens: [screen]))
        let leftDisplay = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(DrawerGeometry.hasVisibleAnchor(CGRect(x: -84, y: 3, width: 45, height: 24), screens: [screen, leftDisplay]))
    }

    @Test func disabledIsTheDefaultWithoutStartingTheStore() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        let store = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 26)

        #expect(!store.enabled)
        #expect(!store.isHidden)
        #expect(!store.isLoading)
        #expect(store.entries.isEmpty)
    }

    @Test func storedPreferenceLoadsWithoutStartingOrRewritingIt() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")

        let store = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 26)

        #expect(store.enabled)
        #expect(storage.defaults.bool(forKey: "drawer.enabled"))
        #expect(!store.isHidden)
        #expect(store.entries.isEmpty)
    }
}
