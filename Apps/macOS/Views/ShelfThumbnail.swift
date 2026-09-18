import AltilloCore
import AltilloDesign
import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Quick Look thumbnails, generated once per file and size and kept in memory.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private struct Key: Hashable {
        let url: URL
        let pixels: Int
    }

    private var images: [Key: NSImage] = [:]
    private var inFlight: [Key: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL, side: CGFloat, scale: CGFloat) -> NSImage? {
        images[Key(url: url, pixels: Int(side * scale))]
    }

    func thumbnail(for url: URL, side: CGFloat, scale: CGFloat) async -> NSImage? {
        let key = Key(url: url, pixels: Int(side * scale))
        if let image = images[key] { return image }
        if let task = inFlight[key] { return await task.value }

        let task = Task<NSImage?, Never> {
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: side, height: side),
                scale: scale,
                representationTypes: .all
            )
            if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                return representation.nsImage
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        images[key] = image
        return image
    }
}

/// The visual of a shelf item: a Quick Look thumbnail for files, a tiny note for text, a squircle for links.
struct ShelfThumbnail: View {
    let item: ShelfItem
    let side: CGFloat
    /// Compact thumbnails (peek stacks) drop the inner details and use a filled squircle for everything.
    var compact = false

    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?

    var body: some View {
        Group {
            switch item.kind {
            case let .file(url, _):
                fileThumbnail(url)
            case let .text(text):
                TextNoteThumbnail(text: text, side: side, compact: compact)
            case let .link(url):
                LinkThumbnail(url: url, side: side, compact: compact)
            }
        }
        .frame(width: side, height: side)
    }

    @ViewBuilder
    private func fileThumbnail(_ url: URL) -> some View {
        let shape = RoundedRectangle(cornerRadius: compact ? side * 0.24 : 4, style: .continuous)
        Group {
            if let image = image ?? ThumbnailCache.shared.cached(url, side: side, scale: displayScale) {
                if compact {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: side, height: side)
                        .background(Tokens.Palette.elevated)
                        .clipShape(shape)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1.5)
                }
            } else {
                shape.fill(Tokens.Palette.elevated)
                    .frame(width: side * 0.72, height: side * 0.86)
            }
        }
        .task(id: url) {
            image = await ThumbnailCache.shared.thumbnail(for: url, side: side, scale: displayScale)
        }
    }
}

private struct TextNoteThumbnail: View {
    let text: String
    let side: CGFloat
    let compact: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? side * 0.24 : 6, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(Color(hex: 0xF7F3EA))
            if compact {
                Image(systemName: "text.quote")
                    .font(.system(size: side * 0.45, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x57534E))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Rectangle().fill(Tokens.Palette.amber).frame(width: 14, height: 2)
                    Text(text)
                        .font(.system(size: 7.5, weight: .medium))
                        .foregroundStyle(Color(hex: 0x292524))
                        .lineSpacing(0.5)
                        .lineLimit(5)
                }
                .padding(7)
            }
        }
        .frame(width: compact ? side : side * 0.8, height: compact ? side : side * 0.9)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1.5)
    }
}

private struct LinkThumbnail: View {
    let url: URL
    let side: CGFloat
    let compact: Bool

    var body: some View {
        let inner = compact ? side : side * 0.78
        ZStack {
            RoundedRectangle(cornerRadius: Tokens.Radius.squircle(side: inner), style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(hex: 0x2F5A8C), Tokens.Palette.navy],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay {
                    RoundedRectangle(cornerRadius: Tokens.Radius.squircle(side: inner), style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            Image(systemName: "link")
                .font(.system(size: inner * 0.42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .accessibilityLabel(url.host(percentEncoded: false) ?? url.absoluteString)
        }
        .frame(width: inner, height: inner)
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1.5)
    }
}
