import AppKit
import CoreGraphics
import Observation
import ScreenCaptureKit

/// Reads only status-item pixels, never a whole application or display. macOS 26 gives every status item its
/// own window, captured individually. macOS 27 draws the whole bar in one MenuBarAgent window; there the
/// capture is cropped to the item's frame. The path is chosen per item at run time, not by OS version.
/// Images stay in memory and are retained while a status item is temporarily offscreen.
@MainActor @Observable
final class MenuBarIconCapture {
    private(set) var hasAccess: Bool
    private(set) var images: [String: NSImage] = [:]
    /// Items a capture pass tried and couldn't read (no window, hidden, blank). They get a fallback glyph
    /// instead of a placeholder; a later successful capture removes them.
    private(set) var failedIDs: Set<String> = []
    /// A capture pass is reading pixels (the strip shows its progress rather than an empty shelf).
    private(set) var isCapturing = false

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
        if !failedIDs.isEmpty { failedIDs.removeAll() }
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
        if !failedIDs.isSubset(of: liveIDs) { failedIDs.formIntersection(liveIDs) }
        cache.retain(liveIDs)
        let pending = cache.entriesNeedingCapture(entries, appearance: appearance, now: .now,
                                                  maxAge: maxAge, force: force)
        MenuBarDrawerStore.log.debug("glyphs pending=\(pending.count) of \(entries.count) appearance=\(appearance, privacy: .public)")
        // Nothing changed: no window enumeration, no capture, no pixel scan.
        guard !pending.isEmpty else { return }
        refreshing = true
        isCapturing = true
        defer {
            refreshing = false
            isCapturing = false
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
        // macOS 27: one window per display draws the whole menu bar, owned by MenuBarAgent.
        let barHosts = content.windows.filter {
            Self.isMenuBarHost(frame: $0.frame, ownerBundleID: $0.owningApplication?.bundleIdentifier,
                               layer: $0.windowLayer)
        }
        var failed = failedIDs
        defer {
            let settled = hasAccess ? failed : []
            if failedIDs != settled { failedIDs = settled }
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
            let others = entries.lazy.filter { $0.id != entry.id }.map(\.frame)
            let host = window == nil
                ? barHosts.first { Self.hostCrop(hostFrame: $0.frame, item: entry.frame, others: Array(others)) != nil }
                : nil
            guard let source = window ?? host else {
                failed.insert(entry.id)
                continue
            }

            let filter = SCContentFilter(desktopIndependentWindow: source)
            let configuration = SCStreamConfiguration()
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = false
            configuration.captureResolution = .best
            // Accessibility exposes the button inside the padded status window. Read only this region,
            // snapped to the window's backing pixels and at exactly that pixel size: a half-pixel
            // origin or a larger output size would make ScreenCaptureKit resample (blur) the glyph.
            // The backing store holds no more detail than `pointPixelScale`, so asking for more only upscales.
            let scale = CGFloat(max(filter.pointPixelScale, 1))
            let crop = window != nil
                ? Self.sourceRect(windowFrame: source.frame, itemFrame: entry.frame, scale: scale)
                : Self.hostSourceRect(hostFrame: source.frame, itemFrame: entry.frame, scale: scale)
            configuration.sourceRect = crop
            configuration.width = max(1, Int((crop.width * scale).rounded()))
            configuration.height = max(1, Int((crop.height * scale).rounded()))
            let captured: CGImage
            do {
                captured = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                handleCaptureError(error)
                failed.insert(entry.id)
                continue
            }
            guard !Task.isCancelled, hasAccess else { continue }
            let actualScale = CGFloat(captured.height) / crop.height
            guard let image = Self.normalizedGlyph(
                from: captured,
                scale: actualScale,
                removesOpaqueBackground: window == nil
            ) else {
                // Blank pixels: the item is covered, folded into the system overflow, or not drawn yet.
                failed.insert(entry.id)
                continue
            }
            MenuBarDrawerStore.log.debug("glyph \(entry.title, privacy: .public) crop=\(crop.debugDescription, privacy: .public) px=\(captured.width)x\(captured.height) scale=\(actualScale) pt=\(image.size.debugDescription, privacy: .public) template=\(image.isTemplate)")
            // These are the actual colored/template pixels provided by the owner, not its bundle icon.
            images[entry.id] = image
            failed.remove(entry.id)
            if window != nil { windowIDs[entry.id] = source.windowID }
            cache.record(entry, appearance: appearance, at: .now)
        }
        MenuBarDrawerStore.log.debug("glyphs captured, cached=\(self.cache.count)")
    }

    /// Remove transparent padding and almost invisible status-window shadows. Keep the original pixel data, colors, and Retina
    /// resolution: the image's point size is its pixel size divided by the capture scale, so drawing it at `size` maps
    /// one source pixel to one screen pixel (`MenuBarGlyph` never enlarges it). Single-colour glyphs (template symbols the
    /// menu bar drew white or black) are marked as templates so the Drawer can tint them for its own background.
    static func normalizedGlyph(from image: CGImage, scale: CGFloat,
                                removesOpaqueBackground: Bool = false) -> NSImage? {
        guard scale.isFinite, scale > 0 else { return nil }
        let source = removesOpaqueBackground ? image.removingUniformOpaqueBorder() ?? image : image
        guard let bounds = inkBounds(of: source), let cropped = source.cropping(to: bounds) else { return nil }
        let glyph = NSImage(cgImage: cropped, size: CGSize(width: bounds.width / scale, height: bounds.height / scale))
        glyph.isTemplate = isMonochrome(cropped)
        return glyph
    }

    /// True when every clearly visible pixel has (nearly) the same neutral colour, i.e. only alpha carries the shape.
    /// Coloured logos and glyphs mixing light and dark parts (a battery with text inside) stay as captured.
    nonisolated static func isMonochrome(_ image: CGImage) -> Bool {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return false }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var minLuma = 255, maxLuma = 0, opaque = 0
        for offset in stride(from: 0, to: height * context.bytesPerRow, by: 4) {
            let alpha = Int(pixels[offset + 3])
            // Antialiased edges blend with transparency; judge colour on well-covered pixels only.
            guard alpha >= 160 else { continue }
            let r = Int(pixels[offset]) * 255 / alpha
            let g = Int(pixels[offset + 1]) * 255 / alpha
            let b = Int(pixels[offset + 2]) * 255 / alpha
            guard max(r, g, b) - min(r, g, b) <= 28 else { return false }
            let luma = (r * 3 + g * 6 + b) / 10
            minLuma = min(minLuma, luma)
            maxLuma = max(maxLuma, luma)
            opaque += 1
        }
        return opaque > 0 && maxLuma - minLuma <= 48
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

    /// The macOS 27 menu-bar window: MenuBarAgent's main-menu-level window along a display's top edge.
    nonisolated static func isMenuBarHost(frame: CGRect, ownerBundleID: String?, layer: Int) -> Bool {
        ownerBundleID == MenuBarAccessibility.menuBarAgentBundleID
            && layer == Int(CGWindowLevelForKey(.mainMenuWindow))
            && frame.width > 64 && frame.height > 0 && frame.height <= 64
    }

    /// The item's rectangle inside a shared menu-bar window, or nil when that window can't show exactly this
    /// item: it lies outside the window (another display, pushed offscreen) or overlaps another item. macOS 27
    /// stacks the frames of items folded into its overflow menu at the overflow control, so an overlap means
    /// the pixels there belong to something else.
    nonisolated static func hostCrop(hostFrame: CGRect, item: CGRect, others: [CGRect]) -> CGRect? {
        guard item.width > 0, item.height > 0, hostFrame.contains(item) else { return nil }
        guard !others.contains(where: { other in
            let overlap = other.intersection(item)
            // Neighbours' AX frames can touch by a point or two; stacked items overlap by half or more.
            return !overlap.isNull && overlap.height > 2 && overlap.width >= min(item.width, other.width) / 2
        }) else { return nil }
        return item.offsetBy(dx: -hostFrame.minX, dy: -hostFrame.minY)
    }

    /// `hostCrop`, grown outwards to whole backing pixels and clamped to the window.
    nonisolated static func hostSourceRect(hostFrame: CGRect, itemFrame: CGRect, scale: CGFloat = 1) -> CGRect {
        let local = itemFrame.offsetBy(dx: -hostFrame.minX, dy: -hostFrame.minY)
        guard scale.isFinite, scale > 0 else { return local }
        let minX = max(0, (local.minX * scale).rounded(.down) / scale)
        let minY = max(0, (local.minY * scale).rounded(.down) / scale)
        let maxX = min((local.maxX * scale).rounded(.up) / scale, hostFrame.width)
        let maxY = min((local.maxY * scale).rounded(.up) / scale, hostFrame.height)
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    nonisolated static func matchesPosition(windowFrame: CGRect, itemFrame: CGRect) -> Bool {
        abs(windowFrame.midX - itemFrame.midX) <= 2 && abs(windowFrame.midY - itemFrame.midY) <= 2
    }

    nonisolated static func sourceRect(windowFrame: CGRect, itemFrame: CGRect, scale: CGFloat = 1) -> CGRect {
        // Center-relative coordinates also work when the backing window retains its previous
        // screen origin after an icon has moved offscreen.
        let width = min(windowFrame.width, itemFrame.width)
        let height = min(windowFrame.height, itemFrame.height)
        let centered = CGRect(x: (windowFrame.width - width) / 2, y: (windowFrame.height - height) / 2,
                              width: width, height: height)
        // Grow outwards to whole backing pixels (e.g. a 1 pt size difference centres on a half pixel at 1x).
        guard scale.isFinite, scale > 0 else { return centered }
        let minX = (centered.minX * scale).rounded(.down) / scale
        let minY = (centered.minY * scale).rounded(.down) / scale
        let maxX = min((centered.maxX * scale).rounded(.up) / scale, windowFrame.width)
        let maxY = min((centered.maxY * scale).rounded(.up) / scale, windowFrame.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private extension CGImage {
    /// A shared MenuBarAgent window is opaque even when ScreenCaptureKit is asked for transparency. Recover the
    /// glyph instead of preserving the menu bar as a black/white rectangle. A neutral capture becomes a clean
    /// alpha mask; a coloured capture only loses background pixels connected to its outside edge, preserving dark
    /// detail inside the icon.
    nonisolated func removingUniformOpaqueBorder() -> CGImage? {
        let width = width, height = height
        guard width > 2, height > 2,
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ), let data = context.data else { return nil }
        context.setBlendMode(.copy)
        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        let row = context.bytesPerRow

        var border: [Int] = []
        border.reserveCapacity(2 * width + 2 * height)
        for x in 0..<width {
            border.append(x)
            border.append((height - 1) * width + x)
        }
        for y in 1..<(height - 1) {
            border.append(y * width)
            border.append(y * width + width - 1)
        }
        let opaque = border.filter { pixels[($0 / width) * row + ($0 % width) * 4 + 3] >= 240 }
        guard opaque.count >= border.count * 3 / 4 else { return nil }
        func average(_ channel: Int) -> Int {
            opaque.reduce(0) { result, index in
                result + Int(pixels[(index / width) * row + (index % width) * 4 + channel])
            } / max(opaque.count, 1)
        }
        let background = [average(0), average(1), average(2)]
        func distance(_ index: Int) -> Int {
            let offset = (index / width) * row + (index % width) * 4
            return max(
                abs(Int(pixels[offset]) - background[0]),
                abs(Int(pixels[offset + 1]) - background[1]),
                abs(Int(pixels[offset + 2]) - background[2])
            )
        }
        guard opaque.filter({ distance($0) <= 20 }).count >= opaque.count * 4 / 5 else { return nil }

        let allNeutral = (0..<(width * height)).allSatisfy { index in
            let offset = (index / width) * row + (index % width) * 4
            guard pixels[offset + 3] >= 32 else { return true }
            let r = Int(pixels[offset]), g = Int(pixels[offset + 1]), b = Int(pixels[offset + 2])
            return max(r, g, b) - min(r, g, b) <= 28
        }

        var removed = 0
        if allNeutral {
            let backgroundLuma = (background[0] * 3 + background[1] * 6 + background[2]) / 10
            var contrasts = [Int](repeating: 0, count: width * height)
            var strongest = 0
            for index in contrasts.indices {
                let offset = (index / width) * row + (index % width) * 4
                let luma = (Int(pixels[offset]) * 3 + Int(pixels[offset + 1]) * 6
                    + Int(pixels[offset + 2])) / 10
                contrasts[index] = abs(luma - backgroundLuma)
                strongest = max(strongest, contrasts[index])
            }
            guard strongest >= 24 else { return nil }
            for index in contrasts.indices {
                let offset = (index / width) * row + (index % width) * 4
                let alpha = UInt8(clamping: max(0, contrasts[index] - 3) * 255 / max(strongest - 3, 1))
                if alpha == 0 { removed += 1 }
                // A neutral status item is a template. White premultiplied pixels make its alpha unambiguous.
                pixels[offset] = alpha
                pixels[offset + 1] = alpha
                pixels[offset + 2] = alpha
                pixels[offset + 3] = alpha
            }
        } else {
            var queue: [Int] = []
            queue.reserveCapacity(width * height)
            var visited = [Bool](repeating: false, count: width * height)
            for index in border where !visited[index] && distance(index) <= 28 {
                visited[index] = true
                queue.append(index)
            }
            var cursor = 0
            while cursor < queue.count {
                let index = queue[cursor]
                cursor += 1
                let x = index % width, y = index / width
                let offset = y * row + x * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
                removed += 1
                let neighbours = [index - 1, index + 1, index - width, index + width]
                for neighbour in neighbours {
                    guard neighbour >= 0, neighbour < width * height,
                          !visited[neighbour],
                          abs(neighbour % width - x) + abs(neighbour / width - y) == 1,
                          distance(neighbour) <= 28
                    else { continue }
                    visited[neighbour] = true
                    queue.append(neighbour)
                }
            }
        }
        guard removed >= width * height / 5 else { return nil }
        return context.makeImage()
    }
}

/// Identifies a captured glyph. Position is deliberately excluded: hiding the section or another item
/// appearing moves every icon without changing its pixels. Size, owner, identity and the menu-bar
/// appearance (light/dark, scale) are what change the rendered glyph.
struct MenuBarGlyphKey: Hashable, Sendable {
    /// Bump when capture or normalization changes, so glyphs taken the old way are replaced.
    /// 3: common optical sizing and opaque shared-menu-bar background removal.
    static let version = 3

    let version = MenuBarGlyphKey.version
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
