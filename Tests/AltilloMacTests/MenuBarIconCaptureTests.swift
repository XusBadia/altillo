import CoreGraphics
import Foundation
import ScreenCaptureKit
import Testing
@testable import Altillo

struct MenuBarIconCaptureTests {
    @Test @MainActor func transparentPaddingIsRemovedWithoutDownsamplingRetinaPixels() throws {
        let source = try glyphFixture(width: 48, height: 48, ink: CGRect(x: 13, y: 9, width: 16, height: 28))
        #expect(MenuBarIconCapture.inkBounds(of: source) == CGRect(x: 13, y: 9, width: 16, height: 28))
        let normalized = try #require(MenuBarIconCapture.normalizedGlyph(from: source, scale: 2))
        #expect(normalized.size == CGSize(width: 8, height: 14))
        let pixels = try #require(normalized.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width == 16)
        #expect(pixels.height == 28)
        let data = try #require(pixels.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(Array(UnsafeBufferPointer(start: bytes, count: 4)) == [128, 0, 0, 128])
    }

    @Test @MainActor func aBlankCaptureDoesNotReplaceAnExistingGlyph() throws {
        let blank = try glyphFixture(width: 48, height: 48, ink: .zero)
        #expect(MenuBarIconCapture.inkBounds(of: blank) == nil)
        #expect(MenuBarIconCapture.normalizedGlyph(from: blank, scale: 2) == nil)
    }

    @Test @MainActor func wideStatusTextKeepsEveryPixelAndItsAspectRatio() throws {
        let source = try glyphFixture(width: 240, height: 48, ink: CGRect(x: 10, y: 8, width: 220, height: 28))
        let normalized = try #require(MenuBarIconCapture.normalizedGlyph(from: source, scale: 2))
        #expect(normalized.size == CGSize(width: 110, height: 14))
        let pixels = try #require(normalized.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(pixels.width == 220)
        #expect(pixels.height == 28)
    }

    @Test func faintStatusWindowShadowDoesNotSetTheGlyphSize() throws {
        let source = try glyphFixture(width: 48, height: 48, ink: CGRect(x: 16, y: 10, width: 12, height: 16), backgroundAlpha: 2)
        #expect(MenuBarIconCapture.inkBounds(of: source) == CGRect(x: 15, y: 9, width: 14, height: 18))
    }

    @Test func genuinelyDimGlyphRemainsVisible() throws {
        let source = try glyphFixture(width: 24, height: 24, ink: CGRect(x: 5, y: 4, width: 12, height: 13), inkAlpha: 16)
        #expect(MenuBarIconCapture.inkBounds(of: source) == CGRect(x: 5, y: 4, width: 12, height: 13))
    }

    private func glyphFixture(width: Int, height: Int, ink: CGRect, backgroundAlpha: UInt8 = 0, inkAlpha: UInt8 = 128) throws -> CGImage {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = ink.contains(CGPoint(x: x, y: y)) ? inkAlpha : backgroundAlpha
                pixels[offset] = alpha
                pixels[offset + 3] = alpha
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        return try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    @Test @MainActor func screenCaptureSuccessOverridesStalePreflightDenial() async {
        var probes = 0
        let capture = MenuBarIconCapture(
            preflightAccess: { false }, requestSystemAccess: { false },
            probeSystemAccess: { probes += 1 }, openPermissionSettings: {}
        )
        #expect(!capture.hasAccess)
        capture.requestAccess()
        await capture.reconcileAccess()
        #expect(capture.hasAccess)
        capture.checkAccess()
        #expect(capture.hasAccess)
        #expect(probes == 1)
    }

    @Test @MainActor func deniedRequestCannotEnableCaptureOrPopulateImages() async {
        let capture = MenuBarIconCapture(
            preflightAccess: { false }, requestSystemAccess: { false },
            probeSystemAccess: { throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue) },
            openPermissionSettings: {}
        )
        capture.requestAccess()
        await capture.reconcileAccess()
        #expect(!capture.hasAccess)
        #expect(capture.images.isEmpty)
    }

    @Test @MainActor func laterSettingsGrantOverridesPreviousVerifiedDenial() async {
        var preflightGranted = false
        let capture = MenuBarIconCapture(
            preflightAccess: { preflightGranted }, requestSystemAccess: { false },
            probeSystemAccess: { throw NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue) },
            openPermissionSettings: {}
        )
        capture.requestAccess()
        await capture.reconcileAccess()
        #expect(!capture.hasAccess)
        preflightGranted = true
        capture.checkAccess()
        #expect(capture.hasAccess)
    }

    @Test @MainActor func checkingWithoutUserRequestNeverInvokesPromptingAPI() async {
        var probes = 0
        var requests = 0
        let capture = MenuBarIconCapture(
            preflightAccess: { false }, requestSystemAccess: { requests += 1; return false },
            probeSystemAccess: { probes += 1 }, openPermissionSettings: {}
        )
        await capture.reconcileAccess()
        #expect(probes == 0)
        #expect(requests == 0)
        #expect(!capture.hasAccess)
    }

    private var item: MenuBarEntry {
        MenuBarEntry(id: "status", application: MenuBarApplication(pid: 42, bundleID: "example", name: "Example"),
                     title: "Status", frame: CGRect(x: 500, y: 0, width: 24, height: 24))
    }

    @Test func onlyTheStatusItemWindowCanBeCaptured() {
        #expect(MenuBarIconCapture.isStatusWindow(frame: item.frame, ownerPID: 42, entry: item))
        #expect(!MenuBarIconCapture.isStatusWindow(frame: item.frame, ownerPID: 43, entry: item))
        #expect(!MenuBarIconCapture.isStatusWindow(frame: CGRect(x: 0, y: 0, width: 1600, height: 24), ownerPID: 42, entry: item))
        #expect(!MenuBarIconCapture.isStatusWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 400), ownerPID: 42, entry: item))
    }

    @Test func offscreenStatusWindowsRemainEligible() {
        let hiddenFrame = CGRect(x: -3000, y: 0, width: 24, height: 24)
        #expect(MenuBarIconCapture.isStatusWindow(frame: hiddenFrame, ownerPID: 42, entry: item))
        #expect(!MenuBarIconCapture.matchesPosition(windowFrame: hiddenFrame, itemFrame: item.frame))
    }

    @Test func adjacentItemsFromTheSameProcessDoNotMatch() {
        #expect(MenuBarIconCapture.matchesPosition(windowFrame: item.frame, itemFrame: item.frame))
        #expect(!MenuBarIconCapture.matchesPosition(windowFrame: item.frame.offsetBy(dx: 24, dy: 0), itemFrame: item.frame))
    }

    @Test func macOSTahoeStatusProxyRequiresExplicitValidationAndMatchingGeometry() {
        let padded = CGRect(x: 493, y: -3, width: 38, height: 30)
        #expect(!MenuBarIconCapture.isStatusWindow(frame: padded, ownerPID: 418, entry: item))
        #expect(MenuBarIconCapture.isStatusWindow(frame: padded, ownerPID: 418, entry: item, isSystemStatusProxy: true))
        #expect(MenuBarIconCapture.matchesPosition(windowFrame: padded, itemFrame: item.frame))
        #expect(MenuBarIconCapture.sourceRect(windowFrame: padded, itemFrame: item.frame) == CGRect(x: 7, y: 3, width: 24, height: 24))
        #expect(!MenuBarIconCapture.isStatusWindow(frame: CGRect(x: 0, y: 0, width: 1000, height: 30), ownerPID: 418, entry: item, isSystemStatusProxy: true))
    }

    // MARK: - Glyph cache

    private func cacheEntry(_ id: String = "status", width: CGFloat = 24, x: CGFloat = 500) -> MenuBarEntry {
        MenuBarEntry(id: id, application: MenuBarApplication(pid: 42, bundleID: "example", name: "Example"),
                     title: "Status", frame: CGRect(x: x, y: 0, width: width, height: 24))
    }

    @Test func uncachedGlyphsNeedCaptureAndCachedOnesDoNot() {
        var cache = MenuBarGlyphCache()
        let now = ContinuousClock.now
        let entry = cacheEntry()
        #expect(cache.entriesNeedingCapture([entry], appearance: "dark", now: now) == [entry])
        cache.record(entry, appearance: "dark", at: now)
        #expect(cache.entriesNeedingCapture([entry], appearance: "dark", now: now + .seconds(3_600)).isEmpty)
    }

    @Test func movingAnItemDoesNotInvalidateItsGlyph() {
        var cache = MenuBarGlyphCache()
        let now = ContinuousClock.now
        cache.record(cacheEntry(x: 500), appearance: "dark", at: now)
        // Collapsing the section pushes items offscreen; their pixels are unchanged.
        #expect(cache.entriesNeedingCapture([cacheEntry(x: -3_000)], appearance: "dark", now: now).isEmpty)
    }

    @Test func sizeAppearanceOrIdentityChangesRequireRecapture() {
        var cache = MenuBarGlyphCache()
        let now = ContinuousClock.now
        cache.record(cacheEntry(), appearance: "dark", at: now)
        #expect(cache.entriesNeedingCapture([cacheEntry(width: 40)], appearance: "dark", now: now).count == 1)
        #expect(cache.entriesNeedingCapture([cacheEntry()], appearance: "light", now: now).count == 1)
        #expect(cache.entriesNeedingCapture([cacheEntry("other")], appearance: "dark", now: now).count == 1)
        // Sub-pixel AX noise is not a size change.
        #expect(cache.entriesNeedingCapture([cacheEntry(width: 24.1)], appearance: "dark", now: now).isEmpty)
    }

    @Test func maxAgeRenewsOnlyOldGlyphsAndForceRenewsAll() {
        var cache = MenuBarGlyphCache()
        let now = ContinuousClock.now
        let fresh = cacheEntry("fresh"), old = cacheEntry("old")
        cache.record(old, appearance: "a", at: now)
        cache.record(fresh, appearance: "a", at: now + .seconds(50))
        let later = now + .seconds(61)
        #expect(cache.entriesNeedingCapture([fresh, old], appearance: "a", now: later, maxAge: .seconds(60)) == [old])
        #expect(cache.entriesNeedingCapture([fresh, old], appearance: "a", now: later).isEmpty)
        #expect(cache.entriesNeedingCapture([fresh, old], appearance: "a", now: later, force: true) == [fresh, old])
    }

    @Test func zeroSizedItemsAreNeverCapturedAndDeadItemsAreForgotten() {
        var cache = MenuBarGlyphCache()
        let now = ContinuousClock.now
        #expect(cache.entriesNeedingCapture([cacheEntry(width: 0)], appearance: "a", now: now).isEmpty)
        cache.record(cacheEntry("gone"), appearance: "a", at: now)
        cache.record(cacheEntry("kept"), appearance: "a", at: now)
        cache.retain(["kept"])
        #expect(cache.count == 1)
        #expect(cache.entriesNeedingCapture([cacheEntry("gone")], appearance: "a", now: now).count == 1)
    }

    @Test @MainActor func unchangedCatalogNeverTouchesScreenCapture() async {
        // Without access nothing is enumerated; with an empty pending set the capture returns
        // before enumerating windows. Both paths leave the image cache untouched.
        let capture = MenuBarIconCapture(preflightAccess: { false }, requestSystemAccess: { false },
                                         probeSystemAccess: {}, openPermissionSettings: {})
        await capture.refresh(entries: [cacheEntry()])
        #expect(capture.images.isEmpty)
    }
}
