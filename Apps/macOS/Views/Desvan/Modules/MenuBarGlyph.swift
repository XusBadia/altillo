import AppKit
import SwiftUI

/// The capture is already trimmed to its visible pixels and sized in native points (pixels / capture scale).
/// Captured glyphs are shown at that native size and never resampled when they fit the menu bar's own
/// 24 pt item height: a status item captured at 1x holds only 1x pixels, and fitting every glyph to a common
/// 18 pt box (14 → 18 px up, 20 or 24 → 18 px down) is what made the Drawer blurry. Only glyphs taller than a
/// status item shrink. Vector images (SF Symbols, the demo) still fill the 18 pt optical box.
/// Monochrome captures arrive as templates and take the surrounding foreground style.
struct MenuBarGlyph: View {
    let image: NSImage

    /// Optical box for vector symbols.
    static let box: CGFloat = 18
    /// Tallest native capture shown unscaled: a full menu-bar status item.
    static let nativeLimit: CGFloat = 24

    static func size(for imageSize: CGSize, allowsEnlarging: Bool = false) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: box, height: box)
        }
        let isWide = imageSize.width / imageSize.height > 2
        let limit = allowsEnlarging ? box : nativeLimit
        var scale = isWide
            ? min(limit / imageSize.height, 178 / imageSize.width)
            : limit / max(imageSize.width, imageSize.height)
        if !allowsEnlarging { scale = min(scale, 1) }
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Bitmap-backed images (every capture) carry a fixed number of pixels; only vector images scale cleanly.
    static func allowsEnlarging(_ image: NSImage) -> Bool {
        !image.representations.contains { $0 is NSBitmapImageRep || $0.pixelsWide > 0 }
    }

    static func size(of image: NSImage) -> CGSize {
        size(for: image.size, allowsEnlarging: allowsEnlarging(image))
    }

    static func cellWidth(for imageSize: CGSize) -> CGFloat {
        // 5 pt either side: a full 24 pt native status item still fits one 34 pt slot.
        let width = size(for: imageSize).width + 10
        // Wide indicators occupy whole grid slots so subsequent symbols align.
        return max(34, ceil((width + 6) / 40) * 40 - 6)
    }

    @Environment(\.displayScale) private var displayScale

    /// Pixels per point of the captured bitmap (nil for vector images).
    static func pixelScale(of image: NSImage) -> CGFloat? {
        // A CGImage-backed rep reports its point size as `pixelsWide`; ask for the backing CGImage instead.
        guard image.size.width > 0, !allowsEnlarging(image),
              let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width else { return nil }
        return CGFloat(pixels) / image.size.width
    }

    var body: some View {
        let size = Self.size(of: image)
        // One source pixel per screen pixel: sample exactly, so a half-point position cannot soften it.
        let isNative = size == image.size && Self.pixelScale(of: image) == displayScale
        Image(nsImage: image)
            .renderingMode(image.isTemplate ? .template : .original)
            .resizable()
            // At native size no resampling happens; otherwise (downscaling, vector) use the best filter.
            .interpolation(isNative ? .none : .high)
            .antialiased(!isNative)
            .frame(width: size.width, height: size.height)
            .frame(height: max(Self.box, size.height))
            .accessibilityHidden(true)
    }
}

/// Compact rows retain source order and allow text status items to span slots.
struct MenuBarGlyphGrid: Layout {
    private let spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 194
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        return subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width + 0.5 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            let frame = CGRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            return frame
        }
    }
}

/// What stands in for an item's captured glyph. The Drawer never shows a placeholder shape: an item whose
/// pixels can't be read is drawn with a symbol (macOS's own items) or its app's icon, or left out.
enum MenuBarGlyphFallback {
    enum Source: Equatable {
        case captured
        case systemSymbol(String)
        case applicationIcon
        /// Nothing to show yet (capture pending) or at all: skip the item.
        case none
    }

    /// `captureFailed` is true once a capture pass tried this item and couldn't read it; until then a missing
    /// capture is only pending, and the strip waits rather than flashing a fallback that is replaced a moment later.
    static func source(for entry: MenuBarEntry, hasCapture: Bool, captureFailed: Bool,
                       hasApplicationIcon: Bool) -> Source {
        if hasCapture { return .captured }
        guard captureFailed else { return .none }
        if let symbol = MenuBarAccessibility.systemSymbol(for: entry) { return .systemSymbol(symbol) }
        return hasApplicationIcon ? .applicationIcon : .none
    }

    /// An app icon redrawn at the strip's optical box. The drawing handler keeps it resolution independent,
    /// so `MenuBarGlyph` sizes it like a vector symbol (the 18 pt box) instead of a native capture.
    static func glyph(fromApplicationIcon icon: NSImage) -> NSImage {
        let side = MenuBarGlyph.box
        let glyph = NSImage(size: CGSize(width: side, height: side), flipped: false) { rect in
            icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        glyph.isTemplate = false
        return glyph
    }
}
