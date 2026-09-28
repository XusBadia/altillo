import Foundation

/// Which apps keep their menu-bar icons in the Drawer. Membership is per app, not per icon: macOS's
/// allow-list shows or hides every icon of an app together, so the Drawer never promises a split it can't keep.
struct DrawerMembership: Equatable, Sendable {
    /// Bundle ids in the order they joined.
    private(set) var bundleIDs: [String]

    init(bundleIDs: [String] = []) {
        var seen: Set<String> = []
        self.bundleIDs = bundleIDs.filter { seen.insert($0).inserted }
    }

    var isEmpty: Bool { bundleIDs.isEmpty }

    func contains(_ bundleID: String) -> Bool { bundleIDs.contains(bundleID) }

    mutating func insert(_ bundleID: String) {
        guard !contains(bundleID) else { return }
        bundleIDs.append(bundleID)
    }

    mutating func remove(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
    }

    /// Items macOS itself hosts (clock, Wi‑Fi, Control Center and its modules) belong to MenuBarAgent or
    /// Control Center. Allow-listing those processes can't tell one item from another, so they always stay.
    static func isSystemHosted(_ bundleID: String) -> Bool {
        bundleID == MenuBarAccessibility.menuBarAgentBundleID || bundleID == MenuBarAccessibility.controlCenterBundleID
    }

    /// Every system item number is always allowed until each one is verified to map to a known item.
    /// 0…31 activates without error on 27.0 and covers the items macOS draws today.
    static let systemItems: Set<Int> = Set(0...31)

    /// What stays in the menu bar: everything running (and already shown this session) that isn't in the
    /// Drawer, plus Altillo itself and the system-hosted items. With `newAppsJoinDrawer`, apps Altillo has
    /// never seen with an icon stay out of the list, so their icons appear in the Drawer instead.
    func allowList(running: Set<String>, shownThisSession: Set<String> = [], alwaysAllowed: Set<String>,
                   known: Set<String>, newAppsJoinDrawer: Bool) -> MenuBarAllowList {
        // Without a baseline yet (no catalog read so far), nothing counts as new: hiding everything would be worse.
        let filtersNew = newAppsJoinDrawer && !known.isEmpty
        let candidates = running.filter { !filtersNew || known.contains($0) }
            .union(shownThisSession)
        let bundles = candidates.subtracting(bundleIDs)
            .union(alwaysAllowed)
            .union(running.filter(Self.isSystemHosted))
        return MenuBarAllowList(bundleIDs: bundles, systemItems: Self.systemItems)
    }

    /// Entry ids begin with the owner's length-prefixed bundle id (`16:com.openai.codex|ordinal:0`).
    static func bundleID(fromEntryID id: String) -> String? {
        guard let colon = id.firstIndex(of: ":"), let length = Int(id[..<colon]), length > 0 else { return nil }
        let start = id.index(after: colon)
        guard let end = id.utf8.index(start, offsetBy: length, limitedBy: id.utf8.endIndex) else { return nil }
        return String(id[start..<end])
    }

    /// The previous Drawer stored individual icon ids. Their owners become the apps in the Drawer.
    static func migrating(chosenIDs: [String]) -> DrawerMembership {
        DrawerMembership(bundleIDs: chosenIDs.compactMap(bundleID(fromEntryID:)).filter { !isSystemHosted($0) })
    }
}
