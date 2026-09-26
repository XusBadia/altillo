import CoreGraphics
import Testing
@testable import Altillo

@MainActor
struct MenuBarItemMoverTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let divider = CGRect(x: 1100, y: 0, width: 20, height: 30)

    @Test func nativeClicksUseStatusItemCenterAndRejectHiddenAnchors() {
        #expect(MenuBarItemMover.clickPoint(frame: CGRect(x: 1200, y: 3, width: 24, height: 24),
                                           screens: [screen]) == CGPoint(x: 1212, y: 15))
        for frame in [CGRect(x: -3, y: 3, width: 24, height: 24),
                      CGRect(x: -3000, y: 3, width: 24, height: 24),
                      CGRect.zero,
                      CGRect(x: CGFloat.infinity, y: 3, width: 24, height: 24)] {
            #expect(MenuBarItemMover.clickPoint(frame: frame, screens: [screen]) == nil)
        }
    }

    @Test func placementUsesOppositeSidesOfDividerWithoutLeavingMenuBarRow() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let left = MenuBarItemMover.dragPoints(item: item, divider: divider, toLeft: true, screens: [screen])
        let right = MenuBarItemMover.dragPoints(item: item, divider: divider, toLeft: false, screens: [screen])
        #expect(left?.start == CGPoint(x: 1212, y: 15))
        #expect(left?.end == CGPoint(x: 1102, y: 15))
        #expect(right?.end == CGPoint(x: 1118, y: 15))
    }

    @Test func rejectsOffscreenAndPartiallyClippedSources() {
        for x: CGFloat in [-100, -10, 1430] {
            #expect(MenuBarItemMover.dragPoints(
                item: CGRect(x: x, y: 3, width: 24, height: 24),
                divider: divider, toLeft: true, screens: [screen]
            ) == nil)
        }
    }

    @Test func acceptsAClippedDividerWhenItsInsertionPointIsVisible() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let clippedDivider = CGRect(x: -1, y: 3, width: 22, height: 24)

        let left = MenuBarItemMover.dragPoints(
            item: item, divider: clippedDivider, toLeft: true, screens: [screen]
        )
        let right = MenuBarItemMover.dragPoints(
            item: item, divider: clippedDivider, toLeft: false, screens: [screen]
        )

        #expect(left?.end == CGPoint(x: 1, y: 15))
        #expect(right?.end == CGPoint(x: 19, y: 15))
    }

    @Test func rejectsAClippedDividerWhenItsInsertionPointIsOffscreen() {
        let item = CGRect(x: 1200, y: 3, width: 24, height: 24)
        let offscreenDivider = CGRect(x: -30, y: 3, width: 22, height: 24)

        #expect(MenuBarItemMover.dragPoints(
            item: item, divider: offscreenDivider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func rejectsOtherScreensAndDifferentMenuBarRows() {
        let upperDisplay = CGRect(x: 0, y: -900, width: 1440, height: 900)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: 1200, y: -897, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen, upperDisplay]
        ) == nil)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: 1200, y: 50, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func rejectsInvalidFramesBeforePostingEvents() {
        #expect(MenuBarItemMover.dragPoints(item: .zero, divider: divider, toLeft: true, screens: [screen]) == nil)
        #expect(MenuBarItemMover.dragPoints(
            item: CGRect(x: CGFloat.infinity, y: 3, width: 24, height: 24),
            divider: divider, toLeft: true, screens: [screen]
        ) == nil)
    }

    @Test func systemIconsAreDistinctWithoutScreenCapture() {
        let owner = MenuBarApplication(pid: 0, bundleID: "com.apple.controlcenter", name: "Control Center")
        let wifi = MenuBarEntry(id: "com.apple.controlcenter.WiFi", application: owner, title: "Wi-Fi", frame: .zero)
        let sound = MenuBarEntry(id: "com.apple.controlcenter.Sound", application: owner, title: "Sound", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: wifi) == "wifi")
        #expect(MenuBarAccessibility.systemSymbol(for: sound) == "speaker.wave.2.fill")
        let thirdParty = MenuBarEntry(id: "wifi", application: .init(pid: 0, bundleID: "test.app", name: "Wi-Fi"),
                                     title: "Wi-Fi", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: thirdParty) == nil)
    }
    @Test func macOS27SystemItemsKeepTheirSymbolsAndControlCenterOwnsTheirPanels() {
        let agent = MenuBarApplication(pid: 0, bundleID: "com.apple.MenuBarAgent", name: "Control Center")
        let wifi = MenuBarEntry(id: "22:com.apple.MenuBarAgent|identifier:24:com.apple.menuextra.wifi",
                                application: agent, title: "Wi‑Fi, connected, 3 bars", frame: .zero)
        #expect(MenuBarAccessibility.systemSymbol(for: wifi) == "wifi")
        #expect(MenuBarAccessibility.panelOwnerBundleID(forItemOwner: "com.apple.MenuBarAgent") == "com.apple.controlcenter")
        #expect(MenuBarAccessibility.panelOwnerBundleID(forItemOwner: "io.tailscale.ipn.macsys") == "io.tailscale.ipn.macsys")
    }

    @Test func groupedStatusItemsAreUnwrappedAndDirectOnesKeepTheirOrdinal() {
        struct Node { let role: String; var children: [Node] = [] }
        let item = Node(role: "AXMenuBarItem")
        // macOS 26 and third-party apps: items are direct children.
        let direct = MenuBarAccessibility.statusItemCandidates(in: [item, item], role: { $0.role }, nested: { $0.children })
        #expect(direct.map(\.ordinal) == [0, 1])
        // macOS 27 MenuBarAgent: each system item sits inside an AXGroup.
        let grouped = [Node(role: "AXGroup", children: [item]), Node(role: "AXGroup", children: [item]), item]
        let unwrapped = MenuBarAccessibility.statusItemCandidates(in: grouped, role: { $0.role }, nested: { $0.children })
        #expect(unwrapped.map(\.ordinal) == [0, 1, 2])
        #expect(unwrapped.allSatisfy { $0.element.role == "AXMenuBarItem" })
        #expect(MenuBarAccessibility.statusItemCandidates(in: [Node(role: "AXGroup")], role: { $0.role },
                                                          nested: { $0.children }).isEmpty)
    }
}
