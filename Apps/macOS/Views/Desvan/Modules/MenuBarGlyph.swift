import AppKit
import SwiftUI

/// The capture is already trimmed to its visible pixels. Give symbols a common
/// optical box, but preserve the width of status items that contain text.
struct MenuBarGlyph: View {
    let image: NSImage

    static func size(for imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: 18, height: 18)
        }
        let isWide = imageSize.width / imageSize.height > 2
        let scale = isWide
            ? min(14 / imageSize.height, 178 / imageSize.width)
            : 18 / max(imageSize.width, imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func cellWidth(for imageSize: CGSize) -> CGFloat {
        let width = size(for: imageSize).width + 16
        // Wide indicators occupy whole grid slots so subsequent symbols align.
        return max(34, ceil((width + 6) / 40) * 40 - 6)
    }

    var body: some View {
        let size = Self.size(for: image.size)
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size.width, height: size.height)
            .frame(height: 18)
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
