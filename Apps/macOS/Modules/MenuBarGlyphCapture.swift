import AppKit
import CryptoKit
import Observation
import ScreenCaptureKit

/// The real menu-bar glyphs, with Screen Recording (optional: without it the Drawer shows app icons).
///
/// macOS 27's MenuBarAgent keeps an offscreen, transparent copy of each display's menu bar (a main-menu-level
/// window). One capture per display is cropped at every icon's Accessibility frame. Hidden icons aren't drawn,
/// so glyphs are only read from icons on screen and kept on disk: a hidden icon shows its last capture.
@MainActor @Observable
final class MenuBarGlyphCapture {
    private(set) var hasAccess: Bool
    /// Glyphs loaded in this session, by entry id.
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private let directory: URL?
    @ObservationIgnored private var onDisk: [String: URL] = [:]
    @ObservationIgnored private var capturing = false
    @ObservationIgnored private var lastCapture: [String: ContinuousClock.Instant] = [:]
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private let preflight: () -> Bool

    /// A visible glyph is recaptured at most this often (clock and battery-style icons change).
    static let maxAge: Duration = .seconds(60)

    init(directory: URL? = MenuBarGlyphCapture.defaultDirectory,
         preflight: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.directory = directory
        self.preflight = preflight
        hasAccess = preflight()
        if let directory, let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "png" {
                let key = String(file.deletingPathExtension().lastPathComponent.prefix(64))
                onDisk[key] = file
            }
        }
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Altillo/MenuBarGlyphs", isDirectory: true)
    }

    func checkAccess() {
        let granted = preflight()
        if granted != hasAccess { hasAccess = granted }
    }

    /// Only in response to the user's button: prompts once, then System Settings; rechecks for two minutes.
    func requestAccess() {
        if !CGRequestScreenCaptureAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        checkAccess()
        permissionTask?.cancel()
        permissionTask = Task { [weak self] in
            for _ in 0..<60 where !(self?.hasAccess ?? true) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self?.checkAccess()
            }
        }
    }

    /// The captured glyph for `entry`, from this session or from disk.
    func image(for entry: MenuBarEntry) -> NSImage? {
        guard hasAccess else { return nil }
        if let image = images[entry.id] { return image }
        guard let file = onDisk[Self.key(for: entry.id)], let image = Self.load(file) else { return nil }
        images[entry.id] = image
        return image
    }

    /// Captures `drawn`: icons that are on screen right now (never hidden ones: their frames are stale and
    /// their pixels absent). `force` ignores `maxAge`.
    func capture(_ drawn: [MenuBarEntry], force: Bool = false) async {
        // One capture at a time; a forced one (icons about to hide) waits rather than being dropped.
        while capturing {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
        }
        checkAccess()
        guard hasAccess else { return }
        let now = ContinuousClock.now
        let pending = drawn.filter { entry in
            force || lastCapture[entry.id].map { now - $0 >= Self.maxAge } ?? true
        }
        guard !pending.isEmpty else { return }
        capturing = true
        defer { capturing = false }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            checkAccess()
            return
        }
        let hosts = content.windows.filter {
            $0.owningApplication?.bundleIdentifier == MenuBarAccessibility.menuBarAgentBundleID
                && $0.windowLayer == Int(CGWindowLevelForKey(.mainMenuWindow))
                && $0.frame.width > 64 && $0.frame.height > 0 && $0.frame.height <= 64
        }
        for host in hosts {
            let inside = pending.filter { entry in
                host.frame.contains(entry.frame)
                    && !Self.overlapsAnother(entry.frame, among: drawn.filter { $0.id != entry.id }.map(\.frame))
            }
            guard !inside.isEmpty else { continue }
            let filter = SCContentFilter(desktopIndependentWindow: host)
            let scale = CGFloat(max(filter.pointPixelScale, 1))
            let configuration = SCStreamConfiguration()
            configuration.width = Int((host.frame.width * scale).rounded())
            configuration.height = Int((host.frame.height * scale).rounded())
            configuration.showsCursor = false
            configuration.shouldBeOpaque = false
            configuration.captureResolution = .best
            guard let bar = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                         configuration: configuration) else { continue }
            for entry in inside {
                let local = entry.frame.offsetBy(dx: -host.frame.minX, dy: -host.frame.minY)
                guard let pixels = Self.trimmedGlyph(from: bar, crop: local, scale: scale) else { continue }
                images[entry.id] = Self.image(pixels.image, scale: scale, isTemplate: pixels.isTemplate)
                lastCapture[entry.id] = now
                save(pixels.image, scale: scale, isTemplate: pixels.isTemplate, for: entry.id)
            }
        }
    }

    // MARK: - Pixels

    /// Items folded into macOS's overflow share one frame; the pixels there belong to something else.
    nonisolated static func overlapsAnother(_ item: CGRect, among others: [CGRect]) -> Bool {
        others.contains { other in
            let overlap = other.intersection(item)
            return !overlap.isNull && overlap.height > 2 && overlap.width >= min(item.width, other.width) / 2
        }
    }

    /// Crops `crop` (points, top-left origin) out of the bar, trims transparent padding and keeps one source pixel
    /// per screen pixel. Single-colour glyphs (the menu bar drew a template white or black) become templates so
    /// the Drawer can tint them; colour icons stay as drawn. Nil when nothing is drawn there.
    nonisolated static func glyph(from bar: CGImage, crop: CGRect, scale: CGFloat) -> NSImage? {
        trimmedGlyph(from: bar, crop: crop, scale: scale).map { image($0.image, scale: scale, isTemplate: $0.isTemplate) }
    }

    nonisolated static func image(_ pixels: CGImage, scale: CGFloat, isTemplate: Bool) -> NSImage {
        let image = NSImage(cgImage: pixels, size: CGSize(width: CGFloat(pixels.width) / scale,
                                                         height: CGFloat(pixels.height) / scale))
        image.isTemplate = isTemplate
        return image
    }

    nonisolated static func trimmedGlyph(from bar: CGImage, crop: CGRect, scale: CGFloat)
        -> (image: CGImage, isTemplate: Bool)? {
        let pixels = CGRect(x: (crop.minX * scale).rounded(.down), y: (crop.minY * scale).rounded(.down),
                            width: (crop.width * scale).rounded(.up), height: (crop.height * scale).rounded(.up))
            .intersection(CGRect(x: 0, y: 0, width: bar.width, height: bar.height))
        guard !pixels.isEmpty, let cropped = bar.cropping(to: pixels),
              let bitmap = RGBA(cropped), let ink = bitmap.inkBounds(),
              let trimmed = cropped.cropping(to: ink) else { return nil }
        guard !bitmap.isBlankRectangle(in: ink) else { return nil }
        return (trimmed, bitmap.hasAlphaMask(in: ink) && bitmap.isMonochrome(in: ink))
    }

    /// Premultiplied RGBA8 pixels of a small image, for trimming and colour checks.
    struct RGBA {
        let width: Int
        let height: Int
        let data: [UInt8]

        init?(_ image: CGImage) {
            let width = image.width, height = image.height
            self.width = width
            self.height = height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
                guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            data = buffer
        }

        func alpha(_ x: Int, _ y: Int) -> UInt8 { data[(y * width + x) * 4 + 3] }

        /// A template uses only alpha: opaque artwork would otherwise become a solid tinted tile.
        func hasAlphaMask(in rect: CGRect) -> Bool {
            var minimum = 255, maximum = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let value = Int(alpha(x, y))
                    minimum = min(minimum, value)
                    maximum = max(maximum, value)
                }
            }
            return maximum - minimum > 32 && minimum < maximum / 2
        }

        /// A featureless grey rectangle is a failed capture, not useful menu-bar artwork.
        /// Keep opaque artwork with detail, as well as genuinely coloured square logos.
        func isBlankRectangle(in rect: CGRect) -> Bool {
            var minimumAlpha = 255, maximumAlpha = 0
            var minimumGrey = 255, maximumGrey = 0
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let index = (y * width + x) * 4
                    let a = Int(data[index + 3])
                    guard a > 24 else { return false }
                    let channels = (0..<3).map { Int(data[index + $0]) * 255 / a }
                    guard channels.max()! - channels.min()! <= 8 else { return false }
                    minimumAlpha = min(minimumAlpha, a)
                    maximumAlpha = max(maximumAlpha, a)
                    minimumGrey = min(minimumGrey, channels.min()!)
                    maximumGrey = max(maximumGrey, channels.max()!)
                }
            }
            return maximumAlpha - minimumAlpha <= 8 && maximumGrey - minimumGrey <= 8
        }

        /// Bounds of pixels a person can see (top-left origin, like `CGImage.cropping`).
        func inkBounds(threshold: UInt8 = 24) -> CGRect? {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height {
                for x in 0..<width where alpha(x, y) > threshold {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
            guard maxX >= minX, maxY >= minY else { return nil }
            return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        }

        /// Every visible pixel is the same grey (white or black glyph ink), within a small tolerance.
        func isMonochrome(in rect: CGRect) -> Bool {
            var reference: Int?
            for y in Int(rect.minY)..<Int(rect.maxY) {
                for x in Int(rect.minX)..<Int(rect.maxX) {
                    let index = (y * width + x) * 4
                    let a = Int(data[index + 3])
                    guard a > 96 else { continue }
                    // Un-premultiply before comparing channels.
                    let r = Int(data[index]) * 255 / a, g = Int(data[index + 1]) * 255 / a, b = Int(data[index + 2]) * 255 / a
                    guard max(r, g, b) - min(r, g, b) <= 24 else { return false }
                    if let reference {
                        if abs(reference - r) > 48 { return false }
                    } else {
                        reference = r
                    }
                }
            }
            return reference != nil
        }
    }

    // MARK: - Disk

    private static func key(for id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// `<key>.<scale>.<t|c>.png`: the scale gives the glyph its point size, t/c whether it's a template.
    /// Writes the captured pixels themselves, never a re-rendered NSImage (which could drop to 1x).
    private func save(_ pixels: CGImage, scale: CGFloat, isTemplate: Bool, for id: String) {
        guard let directory else { return }
        let key = Self.key(for: id)
        let file = directory.appendingPathComponent("\(key).\(Int(scale.rounded())).\(isTemplate ? "t" : "c").png")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let old = onDisk[key], old != file { try? FileManager.default.removeItem(at: old) }
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, pixels, nil)
        if CGImageDestinationFinalize(destination) { onDisk[key] = file }
    }

    private static func load(_ file: URL) -> NSImage? {
        let parts = file.deletingPathExtension().lastPathComponent.split(separator: ".")
        guard parts.count == 3, let scale = Double(parts[1]), scale > 0,
              let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        // Old cache metadata may call opaque grayscale artwork a template. Recheck its pixels
        // with the same rules as a fresh capture so existing installs recover without deleting files.
        return glyph(from: cgImage,
                     crop: CGRect(x: 0, y: 0, width: Double(cgImage.width) / scale,
                                  height: Double(cgImage.height) / scale), scale: scale)
    }
}
