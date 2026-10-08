import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Testing
@testable import Altillo

/// Records what the store asks of the menu bar. The real assertion is never touched by tests.
@MainActor
private final class FakeConcealer: MenuBarConcealing {
    var isAvailable = true
    var isActive: Bool { active != nil }
    var succeeds = true
    private(set) var active: MenuBarAllowList?
    private(set) var concealCount = 0
    private(set) var releaseCount = 0

    func conceal(allowing list: MenuBarAllowList) async -> Bool {
        concealCount += 1
        guard succeeds else { return false }
        active = list
        return true
    }

    func release() {
        if active != nil { releaseCount += 1 }
        active = nil
    }
}

/// Holds each activation until the test lets it finish, to exercise changes made while macOS answers.
@MainActor
private final class ParkedConcealer: MenuBarConcealing {
    var isAvailable: Bool { true }
    var isActive: Bool { active != nil }
    private(set) var active: MenuBarAllowList?
    private var pending: CheckedContinuation<Void, Never>?
    var isParked: Bool { pending != nil }

    func conceal(allowing list: MenuBarAllowList) async -> Bool {
        await withCheckedContinuation { pending = $0 }
        active = list
        return true
    }

    func release() { active = nil }

    func finish() {
        pending?.resume()
        pending = nil
    }
}

/// Drawer membership, hiding policy and catalog plumbing. These tests never call `start()`, scan the real
/// menu bar or activate the system assertion.
@MainActor
struct DrawerTests {
    private static func makeDefaults() -> (defaults: UserDefaults, suite: String) {
        TestDefaultsJanitor.purgeStale()
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

    private static func item(_ bundleID: String, _ ordinal: Int = 0, pid: Int32 = 10) -> MenuBarEntry {
        MenuBarEntry(
            id: MenuBarAccessibility.stableID(bundleID: bundleID, identifier: nil, title: nil, ordinal: ordinal),
            application: MenuBarApplication(pid: pid, bundleID: bundleID, name: bundleID),
            title: bundleID,
            frame: CGRect(x: 100, y: 3, width: 24, height: 24)
        )
    }

    /// Tests never read or write the real glyph cache, nor ask for Screen Recording.
    private static func noGlyphs() -> MenuBarGlyphCapture { MenuBarGlyphCapture(directory: nil, preflight: { false }) }

    private static func makeStore(_ defaults: UserDefaults, concealer: FakeConcealer,
                                  running: Set<String> = ["com.a", "com.b", "com.c"]) -> MenuBarDrawerStore {
        MenuBarDrawerStore(defaults: defaults, majorVersion: 27, concealer: concealer, glyphs: Self.noGlyphs(),
                           runningBundleIDs: { running })
    }

    @Test func appKitFrameConvertsToAccessibilityCoordinates() {
        let appKit = CGRect(x: 1_240, y: 956, width: 20, height: 24)
        #expect(DrawerGeometry.accessibilityFrame(appKit, primaryScreenHeight: 1_000)
            == CGRect(x: 1_240, y: 20, width: 20, height: 24))
    }

    @Test func coordinateConversionUsesThePrimaryScreensGlobalTopEdge() {
        let appKit = CGRect(x: -1_280, y: 1_176, width: 22, height: 24)
        #expect(DrawerGeometry.accessibilityFrame(appKit, primaryScreenHeight: 1_200)
            == CGRect(x: -1_280, y: 0, width: 22, height: 24))
    }

    // MARK: - Capabilities per macOS version

    @Test func macOS26ListsAndOpensIconsWithoutHiding() {
        #expect(DrawerSupport.decide(majorVersion: 26, canHide: true) == DrawerSupport(catalog: true, hiding: false))
    }

    @Test func macOS27HidesOnlyWhenTheSystemAllowListExists() {
        #expect(DrawerSupport.decide(majorVersion: 27, canHide: true) == DrawerSupport(catalog: true, hiding: true))
        #expect(DrawerSupport.decide(majorVersion: 27, canHide: false) == DrawerSupport(catalog: true, hiding: false))
        #expect(DrawerSupport.decide(majorVersion: 28, canHide: true).hiding)
    }

    @Test func olderVersionsHaveNoDrawer() {
        #expect(DrawerSupport.decide(majorVersion: 25, canHide: true) == .unavailable)
    }

    @Test func stripShowsOnlyForAnEnabledDrawerThatWorksHere() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        #expect(!Self.makeStore(storage.defaults, concealer: FakeConcealer()).showsStrip)
        storage.defaults.set(true, forKey: "drawer.enabled")
        #expect(MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 26, concealer: FakeConcealer(), glyphs: Self.noGlyphs()).showsStrip)
        #expect(Self.makeStore(storage.defaults, concealer: FakeConcealer()).showsStrip)
        let unsupported = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 25, concealer: FakeConcealer(), glyphs: Self.noGlyphs())
        #expect(unsupported.enabled)
        #expect(!unsupported.showsStrip)
        #expect(unsupported.drawerEntries.isEmpty)
    }

    @Test func unsupportedDrawerCannotBeTurnedOn() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        let store = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 25, concealer: FakeConcealer(), glyphs: Self.noGlyphs())
        store.setEnabled(true)
        #expect(!store.enabled)
        #expect(!storage.defaults.bool(forKey: "drawer.enabled"))
    }

    @Test func disabledIsTheDefaultAndHidingDefaultsOn() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())
        #expect(!store.enabled)
        #expect(store.hidesDrawerIcons)
        #expect(!store.newIconsGoToDrawer)
        #expect(!store.isConcealing)
        #expect(store.entries.isEmpty)
    }

    @Test func iconStyleDefaultsToTheMenuBarAndIsRemembered() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }

        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())
        #expect(store.iconStyle == .menuBar)
        store.setIconStyle(.application)
        #expect(Self.makeStore(storage.defaults, concealer: FakeConcealer()).iconStyle == .application)
    }

    @Test func appStyleShowsTheAppsIconEvenWithACapturedGlyph() throws {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // A running app (this test host) so the owner's icon exists.
        let entry = Self.item("com.a", pid: ProcessInfo.processInfo.processIdentifier)
        let key = SHA256.hash(data: Data(entry.id.utf8)).map { String(format: "%02x", $0) }.joined()
        let png = try #require(NSBitmapImageRep(cgImage: Self.opaqueArtwork(colored: true))
            .representation(using: .png, properties: [:]))
        try png.write(to: directory.appendingPathComponent("\(key).2.c.png"))
        let glyphs = MenuBarGlyphCapture(directory: directory, preflight: { true })
        let store = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 27, concealer: FakeConcealer(),
                                       glyphs: glyphs, runningBundleIDs: { ["com.a"] })
        let glyph = try #require(glyphs.image(for: entry))

        #expect(store.stripIcon(for: entry) === glyph)
        store.setIconStyle(.application)
        #expect(store.stripIcon(for: entry) !== glyph)
        #expect(store.settingsIcon(for: entry) !== glyph)
    }

    // MARK: - Membership

    @Test func entryIDsNameTheirOwner() {
        #expect(DrawerMembership.bundleID(fromEntryID: "16:com.openai.codex|ordinal:0") == "com.openai.codex")
        #expect(DrawerMembership.bundleID(
            fromEntryID: "21:com.apple.SSMenuAgent|identifier:33:com.apple.screensharing.menuextra"
        ) == "com.apple.SSMenuAgent")
        #expect(DrawerMembership.bundleID(fromEntryID: "4:día|ordinal:0") == "día")
        #expect(DrawerMembership.bundleID(fromEntryID: "garbage") == nil)
        #expect(DrawerMembership.bundleID(fromEntryID: "99:short") == nil)
    }

    @Test func thePreviousDrawersIconsBecomeTheirApps() {
        let migrated = DrawerMembership.migrating(chosenIDs: [
            "16:com.openai.codex|ordinal:0", "18:com.google.drivefs|ordinal:0", "18:com.google.drivefs|ordinal:1",
            "22:com.apple.MenuBarAgent|identifier:5:clock"
        ])
        #expect(migrated.bundleIDs == ["com.openai.codex", "com.google.drivefs"])
    }

    @Test func theMenuBarKeepsEverythingButTheDrawer() {
        let membership = DrawerMembership(bundleIDs: ["com.b"])
        let list = membership.allowList(running: ["com.a", "com.b", "com.apple.MenuBarAgent"],
                                        alwaysAllowed: ["me.badia.altillo"], known: [], newAppsJoinDrawer: false)
        #expect(list.bundleIDs == ["com.a", "com.apple.MenuBarAgent", "me.badia.altillo"])
        #expect(list.systemItems == Set(0...31))
    }

    @Test func aQuittingAppStaysListedSoTheBarNeverFlickers() {
        let membership = DrawerMembership(bundleIDs: ["com.b"])
        let list = membership.allowList(running: ["com.a"], shownThisSession: ["com.a", "com.gone"],
                                        alwaysAllowed: [], known: [], newAppsJoinDrawer: false)
        #expect(list.bundleIDs == ["com.a", "com.gone"])
    }

    @Test func newAppsStayOutOfTheMenuBarWhenTheyJoinTheDrawer() {
        let membership = DrawerMembership()
        let list = membership.allowList(running: ["com.known", "com.new"], alwaysAllowed: [],
                                        known: ["com.known"], newAppsJoinDrawer: true)
        #expect(list.bundleIDs == ["com.known"])
    }

    @Test func systemHostedItemsAlwaysStay() {
        let membership = DrawerMembership(bundleIDs: ["com.apple.controlcenter"])
        let list = membership.allowList(running: ["com.apple.controlcenter"], alwaysAllowed: [],
                                        known: [], newAppsJoinDrawer: true)
        #expect(list.bundleIDs.contains("com.apple.controlcenter"))
    }

    @Test func onlyAGrowingListCanReuseTheAssertion() {
        let small = MenuBarAllowList(bundleIDs: ["a"], systemItems: [2])
        let large = MenuBarAllowList(bundleIDs: ["a", "b"], systemItems: [2, 6])
        #expect(large.extends(small))
        #expect(!small.extends(large))
    }

    // MARK: - Store

    @Test func movingAnIconMovesItsWholeAppAndHidesIt() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = FakeConcealer()
        let store = Self.makeStore(storage.defaults, concealer: concealer)
        let first = Self.item("com.b", 0)
        let second = Self.item("com.b", 1)
        store.setCatalogForTesting([Self.item("com.a"), first, second], hasAccess: true)

        #expect(store.move(first, toDrawer: true))
        await store.settleForTesting()

        #expect(store.drawerEntries.map(\.id) == [first.id, second.id])
        #expect(store.menuBarEntries.map(\.application.bundleID) == ["com.a"])
        #expect(store.isConcealing)
        #expect(concealer.active?.bundleIDs.contains("com.b") == false)
        #expect(concealer.active?.bundleIDs.contains("com.a") == true)
        #expect(storage.defaults.stringArray(forKey: "drawer.bundleIDs") == ["com.b"])
    }

    @Test func systemItemsAndAltilloCannotMove() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())
        let clock = Self.item(MenuBarAccessibility.menuBarAgentBundleID)
        #expect(!store.canMove(clock))
        #expect(!store.move(clock, toDrawer: true))
        #expect(store.canMove(Self.item("com.a")))
    }

    @Test func nothingIsHiddenWithoutAccessibility() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        storage.defaults.set(["com.b"], forKey: "drawer.bundleIDs")
        let concealer = FakeConcealer()
        let store = Self.makeStore(storage.defaults, concealer: concealer)

        store.setCatalogForTesting([Self.item("com.b")], hasAccess: false)
        store.setPeeking(false)
        await store.settleForTesting()

        #expect(!store.isConcealing)
        #expect(concealer.concealCount == 0)
    }

    @Test func peekingShowsEverythingUntilHiddenAgain() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = FakeConcealer()
        let store = Self.makeStore(storage.defaults, concealer: concealer)
        let app = Self.item("com.b")
        store.setCatalogForTesting([app], hasAccess: true)
        store.move(app, toDrawer: true)
        await store.settleForTesting()

        store.setPeeking(true)
        #expect(!concealer.isActive)
        #expect(!store.isConcealing)

        store.setPeeking(false)
        await store.settleForTesting()
        #expect(concealer.isActive)
        #expect(store.isConcealing)
    }

    @Test func turningHidingOffOrTheDrawerOffShowsEverything() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = FakeConcealer()
        let store = Self.makeStore(storage.defaults, concealer: concealer)
        let app = Self.item("com.b")
        store.setCatalogForTesting([app], hasAccess: true)
        store.move(app, toDrawer: true)
        await store.settleForTesting()

        store.setHidesDrawerIcons(false)
        #expect(!concealer.isActive)
        store.setHidesDrawerIcons(true)
        await store.settleForTesting()
        #expect(concealer.isActive)

        store.setEnabled(false)
        #expect(!concealer.isActive)
        #expect(!store.isConcealing)
    }

    @Test func emptyingTheDrawerShowsEverything() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = FakeConcealer()
        let store = Self.makeStore(storage.defaults, concealer: concealer)
        let app = Self.item("com.b")
        store.setCatalogForTesting([app], hasAccess: true)
        store.move(app, toDrawer: true)
        await store.settleForTesting()

        store.move(app, toDrawer: false)
        await store.settleForTesting()
        #expect(!concealer.isActive)
        #expect(store.drawerEntries.isEmpty)
    }

    @Test func aRefusedAssertionLeavesIconsVisibleAndSaysSo() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = FakeConcealer()
        concealer.succeeds = false
        let store = Self.makeStore(storage.defaults, concealer: concealer)
        let app = Self.item("com.b")
        store.setCatalogForTesting([app], hasAccess: true)
        store.move(app, toDrawer: true)
        await store.settleForTesting()

        #expect(!store.isConcealing)
        #expect(store.problem != nil)
    }

    @Test func newIconsFollowThePolicyButTheFirstCatalogIsTheStartingPoint() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        storage.defaults.set(true, forKey: "drawer.newIconsGoToDrawer")
        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())

        store.setCatalogForTesting([Self.item("com.a")], hasAccess: false)
        #expect(store.drawerEntries.isEmpty)

        store.setCatalogForTesting([Self.item("com.a"), Self.item("com.new")], hasAccess: false)
        #expect(store.drawerEntries.map(\.application.bundleID) == ["com.new"])
    }

    @Test func newIconsStayInTheMenuBarByDefault() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())

        store.setCatalogForTesting([Self.item("com.a")], hasAccess: false)
        store.setCatalogForTesting([Self.item("com.a"), Self.item("com.new")], hasAccess: false)
        #expect(store.drawerEntries.isEmpty)
    }

    @Test func thePreviousDrawerMigratesAndItsChromeIsForgotten() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(["16:com.openai.codex|ordinal:0"], forKey: "drawer.chosenIDs")
        storage.defaults.set(638, forKey: "NSStatusItem Preferred Position Altillo.Drawer.Separator.v27")
        storage.defaults.set(1, forKey: "drawer.v27.chromeGeneration")

        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())

        #expect(store.membership.bundleIDs == ["com.openai.codex"])
        #expect(storage.defaults.stringArray(forKey: "drawer.bundleIDs") == ["com.openai.codex"])
        #expect(storage.defaults.object(forKey: "drawer.chosenIDs") == nil)
        #expect(storage.defaults.object(forKey: "NSStatusItem Preferred Position Altillo.Drawer.Separator.v27") == nil)
        #expect(storage.defaults.object(forKey: "drawer.v27.chromeGeneration") == nil)
    }


    @Test func withoutACatalogYetNothingCountsAsNew() {
        let list = DrawerMembership().allowList(running: ["com.a", "com.b"], alwaysAllowed: [],
                                                known: [], newAppsJoinDrawer: true)
        #expect(list.bundleIDs == ["com.a", "com.b"])
    }

    @Test func peekingWhileMacOSIsStillAnsweringLeavesEverythingShown() async {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        storage.defaults.set(true, forKey: "drawer.enabled")
        let concealer = ParkedConcealer()
        let store = MenuBarDrawerStore(defaults: storage.defaults, majorVersion: 27, concealer: concealer,
                                       glyphs: Self.noGlyphs(), runningBundleIDs: { ["com.a", "com.b"] })
        let app = Self.item("com.b")
        store.setCatalogForTesting([app], hasAccess: true)
        store.move(app, toDrawer: true)
        while !concealer.isParked { await Task.yield() }

        store.setPeeking(true)
        concealer.finish()
        await store.settleForTesting()
        for _ in 0..<10 { await Task.yield() }

        #expect(!store.isConcealing)
    }


    // MARK: - Real glyphs

    /// A 40×30 transparent bar at 2x with a white 6×8 pt glyph at (10, 5) pt and a red 4×4 pt icon at (30, 10) pt.
    private static func bar() -> CGImage {
        let context = CGContext(data: nil, width: 80, height: 60, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CGContext has a bottom-left origin; the glyph rectangles below are in top-left pixels.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 60 - 10 - 16, width: 12, height: 16))
        // Give the glyph an actual alpha silhouette, not a featureless white tile.
        context.clear(CGRect(x: 24, y: 60 - 14 - 8, width: 4, height: 8))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 60, y: 60 - 20 - 8, width: 8, height: 8))
        return context.makeImage()!
    }

    @Test func aGlyphIsCroppedTrimmedAndKeptAtItsPixelSize() throws {
        let glyph = try #require(MenuBarGlyphCapture.glyph(from: Self.bar(), crop: CGRect(x: 6, y: 2, width: 14, height: 14), scale: 2))
        #expect(glyph.size == CGSize(width: 6, height: 8))
        #expect(glyph.isTemplate)
    }

    @Test func colourIconsStayInColour() throws {
        let glyph = try #require(MenuBarGlyphCapture.glyph(from: Self.bar(), crop: CGRect(x: 27, y: 7, width: 10, height: 10), scale: 2))
        #expect(glyph.size == CGSize(width: 4, height: 4))
        #expect(!glyph.isTemplate)
    }

    @Test func anEmptySpotHasNoGlyph() {
        #expect(MenuBarGlyphCapture.glyph(from: Self.bar(), crop: CGRect(x: 0, y: 20, width: 5, height: 5), scale: 2) == nil)
    }

    private static func opaqueArtwork(detailed: Bool = false, colored: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: colored ? 0 : 1, blue: colored ? 0 : 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        if detailed {
            // These two greys are close enough to pass the old monochrome heuristic.
            context.setFillColor(CGColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1))
            context.fill(CGRect(x: 4, y: 4, width: 8, height: 8))
        }
        return context.makeImage()!
    }

    @Test func blankWhiteCapturesUseTheFallback() {
        #expect(MenuBarGlyphCapture.glyph(from: Self.opaqueArtwork(),
            crop: CGRect(x: 0, y: 0, width: 16, height: 16), scale: 1) == nil)
    }

    @Test func opaqueGrayscaleArtworkKeepsItsDetailsInsteadOfBecomingAWhiteSquare() throws {
        let glyph = try #require(MenuBarGlyphCapture.glyph(from: Self.opaqueArtwork(detailed: true),
            crop: CGRect(x: 0, y: 0, width: 16, height: 16), scale: 1))
        #expect(!glyph.isTemplate)
        #expect(glyph.size == CGSize(width: 16, height: 16))
    }

    @Test func oldCachedTemplatesAreRevalidatedWithoutDiscardingColoredSquares() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtures = [Self.item("blank"), Self.item("grayscale"), Self.item("colored")]
        let artwork = [Self.opaqueArtwork(), Self.opaqueArtwork(detailed: true), Self.opaqueArtwork(colored: true)]
        for (entry, pixels) in zip(fixtures, artwork) {
            let key = SHA256.hash(data: Data(entry.id.utf8)).map { String(format: "%02x", $0) }.joined()
            let file = directory.appendingPathComponent("\(key).2.t.png")
            let png = try #require(NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:]))
            try png.write(to: file)
        }
        let capture = MenuBarGlyphCapture(directory: directory, preflight: { true })
        #expect(capture.image(for: fixtures[0]) == nil)
        for entry in fixtures.dropFirst() {
            let glyph = try #require(capture.image(for: entry))
            #expect(!glyph.isTemplate)
            #expect(glyph.size == CGSize(width: 8, height: 8))
        }
    }

    @Test func foldedIconsAreNeverCaptured() {
        let icon = CGRect(x: 100, y: 3, width: 24, height: 24)
        #expect(MenuBarGlyphCapture.overlapsAnother(icon, among: [CGRect(x: 104, y: 3, width: 24, height: 24)]))
        #expect(!MenuBarGlyphCapture.overlapsAnother(icon, among: [CGRect(x: 123, y: 3, width: 24, height: 24)]))
    }

    @Test func withoutScreenRecordingTheDrawerUsesAppIcons() {
        let storage = Self.makeDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: storage.suite) }
        let store = Self.makeStore(storage.defaults, concealer: FakeConcealer())
        #expect(!store.hasIconAccess)
        #expect(store.glyphs.image(for: Self.item("com.a")) == nil)
    }

    // MARK: - Order and refresh

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
