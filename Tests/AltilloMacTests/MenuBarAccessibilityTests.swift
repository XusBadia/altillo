import CoreGraphics
import Testing
@testable import Altillo

struct MenuBarAccessibilityTests {
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
