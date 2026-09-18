import CoreGraphics
import SwiftUI

/// Very subtle film grain, like Seam's SVG `fractalNoise` in `soft-light`.
///
/// The noise tile is generated once (deterministically) and cached; drawing it is a single tiled image, so it costs
/// nothing at rest. Use it on cards and glass, never on the black silhouette (it must stay pure black).
public struct GrainOverlay: View {
    public var opacity: Double

    public init(opacity: Double = 0.06) {
        self.opacity = opacity
    }

    public var body: some View {
        GrainTexture.image
            .resizable(resizingMode: .tile)
            .interpolation(.none)
            .blendMode(.overlay)
            .opacity(opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Overlays `GrainOverlay` clipped to `shape`.
    public func grain<S: Shape>(_ opacity: Double = 0.06, in shape: S) -> some View {
        overlay {
            GrainOverlay(opacity: opacity).clipShape(shape)
        }
    }
}

@MainActor
enum GrainTexture {
    static let side = 128

    /// Generated on first use and kept for the lifetime of the process.
    static let image: Image = {
        guard let cgImage = makeNoise(side: side) else { return Image(systemName: "circle.fill") }
        return Image(decorative: cgImage, scale: 1)
    }()

    /// Uniform grey noise from a fixed-seed xorshift generator, so every launch looks identical.
    static func makeNoise(side: Int, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) -> CGImage? {
        var state = seed
        var bytes = [UInt8](repeating: 0, count: side * side)
        for index in bytes.indices {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            bytes[index] = UInt8(truncatingIfNeeded: state >> 56)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: side,
            height: side,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

#Preview("Grain") {
    HStack(spacing: 16) {
        RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous)
            .fill(Tokens.Palette.surface)
            .frame(width: 160, height: 100)
        RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous)
            .fill(Tokens.Palette.surface)
            .grain(0.08, in: RoundedRectangle(cornerRadius: Tokens.Radius.base, style: .continuous))
            .frame(width: 160, height: 100)
    }
    .padding(24)
    .background(.black)
}
