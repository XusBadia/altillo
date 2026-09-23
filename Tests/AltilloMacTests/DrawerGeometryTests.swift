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

    private static func entry(_ id: String) -> MenuBarEntry {
        MenuBarEntry(
            id: id,
            application: MenuBarApplication(pid: 1, bundleID: "test.\(id)", name: id),
            title: id,
            frame: .zero
        )
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

    @Test func drawerDisplayUsesSavedOrderAndKeepsNewIconsStableAtTheEnd() {
        let entries = [Self.entry("calendar"), Self.entry("vpn"), Self.entry("cloud"), Self.entry("audio")]

        let ordered = DrawerOrder.sort(entries, preferredIDs: ["cloud", "calendar"])

        #expect(ordered.map(\.id) == ["cloud", "calendar", "vpn", "audio"])
    }

    @Test func drawerDisplayIgnoresSavedIDsThatAreNoLongerAvailable() {
        let entries = [Self.entry("vpn"), Self.entry("cloud")]

        let ordered = DrawerOrder.sort(entries, preferredIDs: ["missing", "cloud", "vpn"])

        #expect(ordered.map(\.id) == ["cloud", "vpn"])
    }

    @Test func reorderingPlacesTheDraggedIconImmediatelyBeforeItsTarget() {
        let reordered = DrawerOrder.moving("audio", before: "vpn", in: ["calendar", "vpn", "cloud", "audio"])

        #expect(reordered == ["calendar", "audio", "vpn", "cloud"])
    }

    @Test func droppingOnDrawerBackgroundMovesIconToEndWithoutDuplicatingIt() {
        let reordered = DrawerOrder.moving("vpn", before: nil, in: ["calendar", "vpn", "cloud"])

        #expect(reordered == ["calendar", "cloud", "vpn"])
        #expect(reordered.count(where: { $0 == "vpn" }) == 1)
    }

    // MARK: - Event-driven refresh

    @Test func appearingReusesARecentCleanCatalog() {
        let now = ContinuousClock.now
        #expect(!DrawerRefreshPolicy.needsScan(isStale: false, hasEntries: true, lastScan: now - .seconds(5),
                                               now: now, maxAge: .seconds(30)))
        #expect(DrawerRefreshPolicy.needsScan(isStale: true, hasEntries: true, lastScan: now,
                                              now: now, maxAge: .seconds(30)))
        #expect(DrawerRefreshPolicy.needsScan(isStale: false, hasEntries: false, lastScan: now,
                                              now: now, maxAge: .seconds(30)))
        #expect(DrawerRefreshPolicy.needsScan(isStale: false, hasEntries: true, lastScan: nil,
                                              now: now, maxAge: .seconds(30)))
        #expect(DrawerRefreshPolicy.needsScan(isStale: false, hasEntries: true, lastScan: now - .seconds(31),
                                              now: now, maxAge: .seconds(30)))
    }

    @Test func debounceIsTrailingButCappedByMaxWait() {
        let start = ContinuousClock.now
        #expect(DrawerRefreshPolicy.debounceDeadline(now: start, delay: .milliseconds(400), firstRequest: nil,
                                                     maxWait: .seconds(2)) == start + .milliseconds(400))
        // Later events push the deadline back…
        let soon = start + .milliseconds(300)
        #expect(DrawerRefreshPolicy.debounceDeadline(now: soon, delay: .milliseconds(400), firstRequest: start,
                                                     maxWait: .seconds(2)) == soon + .milliseconds(400))
        // …but never beyond maxWait after the first request.
        let late = start + .milliseconds(1_900)
        #expect(DrawerRefreshPolicy.debounceDeadline(now: late, delay: .milliseconds(400), firstRequest: start,
                                                     maxWait: .seconds(2)) == start + .seconds(2))
        let overdue = start + .seconds(5)
        #expect(DrawerRefreshPolicy.debounceDeadline(now: overdue, delay: .milliseconds(400), firstRequest: start,
                                                     maxWait: .seconds(2)) == overdue)
    }

    @Test func debouncerCoalescesABurstIntoOneRunAndThenGoesIdle() async throws {
        let debouncer = MenuBarRefreshDebouncer(maxWait: .seconds(5))
        var runs = 0
        for _ in 0..<5 { debouncer.schedule(after: .milliseconds(40)) { runs += 1 } }
        #expect(debouncer.isPending)
        try await Task.sleep(for: .milliseconds(300))
        #expect(runs == 1)
        #expect(!debouncer.isPending)
        debouncer.schedule(after: .milliseconds(40)) { runs += 1 }
        debouncer.cancel()
        try await Task.sleep(for: .milliseconds(150))
        #expect(runs == 1)
    }

    @Test func runningApplicationsAreResolvedOncePerProcess() {
        struct Process { let pid: Int32; let finished: Bool }
        var cache = MenuBarApplicationCache()
        var lookups: [Int32] = []
        func resolve(_ process: Process) -> MenuBarApplicationCache.Resolution {
            lookups.append(process.pid)
            if !process.finished { return .pending }
            if process.pid == 1 { return .ineligible }
            return .application(MenuBarApplication(pid: process.pid, bundleID: "app.\(process.pid)", name: "\(process.pid)"))
        }
        let first = cache.applications(from: [Process(pid: 1, finished: true), Process(pid: 2, finished: true),
                                              Process(pid: 3, finished: false)], pid: \.pid, resolve: resolve)
        #expect(first.map(\.pid) == [2])
        let second = cache.applications(from: [Process(pid: 1, finished: true), Process(pid: 2, finished: true),
                                               Process(pid: 3, finished: true)], pid: \.pid, resolve: resolve)
        #expect(second.map(\.pid) == [2, 3])
        // 1 and 2 were resolved once; 3 again only because it was still launching.
        #expect(lookups == [1, 2, 3, 3])
        // Dead processes are dropped; a reused pid is resolved afresh after `forget`.
        _ = cache.applications(from: [Process(pid: 2, finished: true)], pid: \.pid, resolve: resolve)
        #expect(cache.count == 1)
        cache.forget(pid: 2)
        _ = cache.applications(from: [Process(pid: 2, finished: true)], pid: \.pid, resolve: resolve)
        #expect(lookups == [1, 2, 3, 3, 2])
    }
}
