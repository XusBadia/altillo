import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit

/// Reads only the individual status-item windows, never a whole application or display.
/// Images stay in memory and are retained while a status item is temporarily offscreen.
@MainActor @Observable
final class MenuBarIconCapture {
    private(set) var hasAccess: Bool
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private var windowIDs: [String: CGWindowID] = [:]
    @ObservationIgnored private var cache = MenuBarGlyphCache()
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var verifiedCaptureAccess: Bool?
    @ObservationIgnored private var permissionRequestDeadline: Date?
    @ObservationIgnored private var permissionProbe: Task<Void, Never>?
    @ObservationIgnored private let preflightAccess: () -> Bool
    @ObservationIgnored private let requestSystemAccess: () -> Bool
    @ObservationIgnored private let probeSystemAccess: () async throws -> Void
    @ObservationIgnored private let openPermissionSettings: () -> Void

    init(
        preflightAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestSystemAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        probeSystemAccess: @escaping () async throws -> Void = {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        },
        openPermissionSettings: @escaping () -> Void = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    ) {
        self.preflightAccess = preflightAccess
        self.requestSystemAccess = requestSystemAccess
        self.probeSystemAccess = probeSystemAccess
        self.openPermissionSettings = openPermissionSettings
        hasAccess = preflightAccess()
    }

    func checkAccess() {
        // Core Graphics can retain the process's original denial after a Settings grant.
        // An actual ScreenCaptureKit result is stronger evidence than that cached preflight.
        let granted = preflightAccess() || verifiedCaptureAccess == true
        if hasAccess != granted { hasAccess = granted }
        if !hasAccess { forgetImages() }
        if !hasAccess, let deadline = permissionRequestDeadline, deadline > Date() {
            reconcileRequestedAccess()
        }
    }

    /// Call only in response to the user's permission button.
    func requestAccess() {
        permissionRequestDeadline = Date().addingTimeInterval(120)
        verifiedCaptureAccess = nil
        _ = requestSystemAccess()
        checkAccess()
        if !hasAccess {
            openPermissionSettings()
        }
    }

    /// Useful when a caller needs the reconciled permission before loading icons.
    func reconcileAccess() async {
        checkAccess()
        await permissionProbe?.value
    }

    private func reconcileRequestedAccess() {
        guard permissionProbe == nil else { return }
        permissionProbe = Task { [weak self] in
            guard let self else { return }
            defer { permissionProbe = nil }
            do {
                // This potentially prompting API is reached only after the user's explicit
                // permission action. It also picks up grants made while Settings was open.
                try await probeSystemAccess()
                verifiedCaptureAccess = true
                hasAccess = true
                permissionRequestDeadline = nil
            } catch {
                handleCaptureError(error)
            }
        }
    }

    private func handleCaptureError(_ error: Error) {
        let error = error as NSError
        guard error.domain == SCStreamErrorDomain, error.code == SCStreamError.Code.userDeclined.rawValue else { return }
        verifiedCaptureAccess = false
        hasAccess = false
        forgetImages()
    }

    private func forgetImages() {
        if !images.isEmpty { images.removeAll() }
        windowIDs.removeAll()
        cache.removeAll()
    }

    /// Captures only items whose glyph is missing or whose cache key changed (owner, identity, size,
    /// menu-bar appearance). `maxAge` additionally renews glyphs older than that age, for moments when
    /// the Drawer becomes visible; `force` recaptures everything after an explicit Refresh.
    /// Desktop-independent window capture can also refresh a hidden item's backing window.
    func refresh(entries: [MenuBarEntry], appearance: String = "", maxAge: Duration? = nil, force: Bool = false) async {
        // A pre-collapse caller must really await its snapshot, even if another
        // refresh is already capturing an older layout.
        while refreshing {
            await withCheckedContinuation { refreshWaiters.append($0) }
            guard !Task.isCancelled else { return }
        }
        checkAccess()
        guard hasAccess, !Task.isCancelled else { return }
        let liveIDs = Set(entries.map(\.id))
        if images.keys.contains(where: { !liveIDs.contains($0) }) {
            images = images.filter { liveIDs.contains($0.key) }
        }
        windowIDs = windowIDs.filter { liveIDs.contains($0.key) }
        cache.retain(liveIDs)
        let pending = cache.entriesNeedingCapture(entries, appearance: appearance, now: .now,
                                                  maxAge: maxAge, force: force)
        MenuBarDrawerStore.log.debug("glyphs pending=\(pending.count) of \(entries.count) appearance=\(appearance, privacy: .public)")
        // Nothing changed: no window enumeration, no capture, no pixel scan.
        guard !pending.isEmpty else { return }
        refreshing = true
        defer {
            refreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        // Existing preflight or a verified user-initiated request authorizes discovery.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            verifiedCaptureAccess = true
        } catch {
            handleCaptureError(error)
            return
        }
        let statusWindowIDs = Set((CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { info -> CGWindowID? in
            guard info[kCGWindowLayer as String] as? Int == Int(CGWindowLevelForKey(.statusWindow)) else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        })
        // Read each window's owner once instead of once per entry.
        let windows = content.windows.map { window in
            (window: window, pid: window.owningApplication?.processID,
             isSystemStatusProxy: window.owningApplication?.bundleIdentifier == "com.apple.controlcenter"
                && statusWindowIDs.contains(window.windowID))
        }
        for entry in pending {
            guard !Task.isCancelled, hasAccess else { return }
            let candidates = windows.filter {
                Self.isStatusWindow(frame: $0.window.frame, ownerPID: $0.pid, entry: entry,
                                    isSystemStatusProxy: $0.isSystemStatusProxy)
            }.map(\.window)
            let window = candidates.first {
                Self.matchesPosition(windowFrame: $0.frame, itemFrame: entry.frame)
            } ?? candidates.first { $0.windowID == windowIDs[entry.id] }
            guard let window else { continue }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = false
            configuration.captureResolution = .best
            // Accessibility exposes the button inside the padded status window. Read only this region.
            let crop = Self.sourceRect(windowFrame: window.frame, itemFrame: entry.frame)
            configuration.sourceRect = crop
            let scale = CGFloat(max(filter.pointPixelScale, 1))
            configuration.width = max(1, Int((crop.width * scale).rounded(.up)))
            configuration.height = max(1, Int((crop.height * scale).rounded(.up)))
            let captured: CGImage
            do {
                captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                handleCaptureError(error)
                continue
            }
            guard !Task.isCancelled, hasAccess else { continue }
            let actualScale = CGFloat(captured.height) / crop.height
            guard let image = Self.normalizedGlyph(from: captured, scale: actualScale) else { continue }
            // These are the actual colored/template pixels provided by the owner, not its bundle icon.
            images[entry.id] = image
            windowIDs[entry.id] = window.windowID
            cache.record(entry, appearance: appearance, at: .now)
        }
        MenuBarDrawerStore.log.debug("glyphs captured, cached=\(self.cache.count)")
    }

    /// Remove transparent padding and almost invisible status-window shadows. Keep the original pixel data, colors, and Retina
    /// resolution; callers choose the displayed size independently of these native points.
    static func normalizedGlyph(from image: CGImage, scale: CGFloat) -> NSImage? {
        guard scale.isFinite, scale > 0, let bounds = inkBounds(of: image),
              let cropped = image.cropping(to: bounds) else { return nil }
        return NSImage(cgImage: cropped, size: CGSize(width: bounds.width / scale, height: bounds.height / scale))
    }

    nonisolated static func inkBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        // Convert into a predictable RGBA layout only to inspect alpha. The returned
        // image is cropped from the original CGImage, so this conversion never replaces its pixels.
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minX = width, minY = height, maxX = -1, maxY = -1
        var inkMinX = width, inkMinY = height, inkMaxX = -1, inkMaxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * context.bytesPerRow + x * 4 + 3] > 0 {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                // macOS status windows include a very low-alpha glow even without their
                // outer shadow. It must not determine the apparent size of the actual symbol.
                if pixels[y * context.bytesPerRow + x * 4 + 3] >= 32 {
                    inkMinX = min(inkMinX, x)
                    inkMinY = min(inkMinY, y)
                    inkMaxX = max(inkMaxX, x)
                    inkMaxY = max(inkMaxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let nonzeroBounds = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        // Keep genuinely dim items instead of treating them as empty. For normal items,
        // one source pixel around the visible ink preserves its antialiased edge.
        guard inkMaxX >= inkMinX, inkMaxY >= inkMinY else { return nonzeroBounds }
        let visibleBounds = CGRect(x: inkMinX, y: inkMinY, width: inkMaxX - inkMinX + 1, height: inkMaxY - inkMinY + 1)
        return visibleBounds.insetBy(dx: -1, dy: -1).intersection(nonzeroBounds)
    }

    /// Tight bounds prevent matching the owner's application windows or a full menu-bar window.
    nonisolated static func isStatusWindow(frame: CGRect, ownerPID: pid_t?, entry: MenuBarEntry, isSystemStatusProxy: Bool = false) -> Bool {
        guard ownerPID == entry.application.pid || isSystemStatusProxy,
              frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0,
              entry.frame.width > 0, entry.frame.height > 0,
              frame.width <= 512, frame.height <= 64,
              frame.width >= entry.frame.width - 4, frame.width <= entry.frame.width + 20,
              frame.height >= entry.frame.height - 4, frame.height <= entry.frame.height + 12 else { return false }
        return true
    }

    nonisolated static func matchesPosition(windowFrame: CGRect, itemFrame: CGRect) -> Bool {
        abs(windowFrame.midX - itemFrame.midX) <= 2 && abs(windowFrame.midY - itemFrame.midY) <= 2
    }

    nonisolated static func sourceRect(windowFrame: CGRect, itemFrame: CGRect) -> CGRect {
        // Center-relative coordinates also work when the backing window retains its previous
        // screen origin after an icon has moved offscreen.
        let width = min(windowFrame.width, itemFrame.width)
        let height = min(windowFrame.height, itemFrame.height)
        return CGRect(x: (windowFrame.width - width) / 2, y: (windowFrame.height - height) / 2,
                      width: width, height: height)
    }
}

/// Identifies a captured glyph. Position is deliberately excluded: hiding the section or another item
/// appearing moves every icon without changing its pixels. Size, owner, identity and the menu-bar
/// appearance (light/dark, scale) are what change the rendered glyph.
struct MenuBarGlyphKey: Hashable, Sendable {
    let bundleID: String
    let itemID: String
    let width: Int
    let height: Int
    let appearance: String

    init(entry: MenuBarEntry, appearance: String) {
        bundleID = entry.application.bundleID
        itemID = entry.id
        // Half-point resolution: AX frames can carry sub-pixel noise.
        width = Int((entry.frame.width * 2).rounded())
        height = Int((entry.frame.height * 2).rounded())
        self.appearance = appearance
    }
}

/// Pure bookkeeping for `MenuBarIconCapture`: which entries need new pixels.
struct MenuBarGlyphCache {
    private var keys: [String: MenuBarGlyphKey] = [:]
    private var capturedAt: [String: ContinuousClock.Instant] = [:]

    var count: Int { keys.count }

    func entriesNeedingCapture(_ entries: [MenuBarEntry], appearance: String, now: ContinuousClock.Instant,
                               maxAge: Duration? = nil, force: Bool = false) -> [MenuBarEntry] {
        guard !force else { return entries }
        return entries.filter { entry in
            guard entry.frame.width > 0, entry.frame.height > 0 else { return false }
            guard keys[entry.id] == MenuBarGlyphKey(entry: entry, appearance: appearance),
                  let captured = capturedAt[entry.id] else { return true }
            if let maxAge { return now - captured >= maxAge }
            return false
        }
    }

    mutating func record(_ entry: MenuBarEntry, appearance: String, at instant: ContinuousClock.Instant) {
        keys[entry.id] = MenuBarGlyphKey(entry: entry, appearance: appearance)
        capturedAt[entry.id] = instant
    }

    mutating func retain(_ ids: Set<String>) {
        guard keys.keys.contains(where: { !ids.contains($0) }) else { return }
        keys = keys.filter { ids.contains($0.key) }
        capturedAt = capturedAt.filter { ids.contains($0.key) }
    }

    mutating func removeAll() {
        keys.removeAll()
        capturedAt.removeAll()
    }
}
