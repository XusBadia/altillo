import CoreGraphics
import Testing
@testable import Altillo

struct MenuBarAccessibilityTests {
    @Test func anonymousBooleanControlRequiresAnUnambiguousNamedMenuHeader() {
        #expect(MenuBarAccessibility.anonymousToggleTitle(parentTitle: "Tailscale", booleanButtonCount: 1) == "Tailscale")
        #expect(MenuBarAccessibility.anonymousToggleTitle(parentTitle: "Tailscale", booleanButtonCount: 2) == nil)
        #expect(MenuBarAccessibility.anonymousToggleTitle(parentTitle: "Tailscale", booleanButtonCount: 0) == nil)
        #expect(MenuBarAccessibility.anonymousToggleTitle(parentTitle: nil, booleanButtonCount: 1) == nil)
        #expect(MenuBarAccessibility.anonymousToggleTitle(parentTitle: " ", booleanButtonCount: 1) == nil)
    }

    @Test func staticMenuTextUsesItsDisplayedValueBeforeItsAccessibilityDescription() {
        #expect(MenuBarAccessibility.menuTitle(role: "AXStaticText", title: nil, description: "Connected", value: "Tailscale") == "Tailscale")
        #expect(MenuBarAccessibility.menuTitle(role: "AXButton", title: nil, description: "More Info", value: nil) == "More Info")
        #expect(MenuBarAccessibility.menuTitle(role: "AXButton", title: nil, description: nil, value: nil).isEmpty)
    }

    @Test func menuToggleStateUsesOnlyKnownControlRoles() {
        #expect(MenuBarAccessibility.controlMark(role: "AXCheckBox", value: 1) == "✓")
        #expect(MenuBarAccessibility.controlMark(role: "AXSwitch", value: 2) == "−")
        #expect(MenuBarAccessibility.controlMark(role: "AXCheckBox", value: 0) == nil)
        #expect(MenuBarAccessibility.controlMark(role: "AXButton", value: 1) == nil)
    }

    @Test func unknownMenuTokensCannotTriggerAnAccessibilityAction() async {
        let accessibility = MenuBarAccessibility()
        let snapshot = await accessibility.menuSnapshot(id: "not-an-item")
        #expect(snapshot?.nodes.count == nil)
        let result = await accessibility.performMenuAction(id: "not-an-action")
        if case .unavailable = result {} else { Issue.record("Unknown action tokens must not invoke an AX target") }
    }

    @Test func identifierKeepsIdentityWhenTheVisibleTitleChanges() {
        let first = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: "sync-item",
            title: "Syncing",
            ordinal: 1
        )
        let second = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: "sync-item",
            title: "Up to date",
            ordinal: 4
        )

        #expect(first == second)
    }

    @Test func changingStatusDoesNotRemoveAnItemWithoutAnIdentifierFromTheDrawer() {
        let first = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: nil,
            title: "Syncing 25%",
            ordinal: 0
        )
        let second = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: "  ",
            title: "Up to date",
            ordinal: 0
        )

        #expect(first == second)
    }

    @Test func ordinalDistinguishesItemsWithoutMetadata() {
        let first = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: nil,
            title: nil,
            ordinal: 0
        )
        let second = MenuBarAccessibility.stableID(
            bundleID: "com.example.status",
            identifier: nil,
            title: nil,
            ordinal: 1
        )

        #expect(first != second)
    }

    @Test func bundleAndMetadataCannotCollideAtSeparatorBoundaries() {
        let first = MenuBarAccessibility.stableID(
            bundleID: "a|identifier:b",
            identifier: "c",
            title: nil,
            ordinal: 0
        )
        let second = MenuBarAccessibility.stableID(
            bundleID: "a",
            identifier: "b|identifier:c",
            title: nil,
            ordinal: 0
        )

        #expect(first != second)
    }

    @Test func publicValuesAreSendable() {
        func acceptSendable<T: Sendable>(_: T) {}

        let application = MenuBarApplication(pid: 42, bundleID: "com.example.status", name: "Status")
        let entry = MenuBarEntry(id: "entry", application: application, title: "Status", frame: .zero)
        acceptSendable(application)
        acceptSendable(entry)
    }
}
