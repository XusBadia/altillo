import CoreGraphics
import Foundation
import SwiftUI

// Procedural materials for Desván: wood grain, kraft fibre and cardboard. Each texture is generated once per process
// (deterministically, so every launch looks the same), cached as a CGImage and drawn as a plain image afterwards:
// no per-frame cost. They are grey + alpha "light and shade" maps (black or white with a little alpha), so the same
// texture works over any base colour with a normal blend.
//
// Generation is prewarmed off the main thread at launch (`DesvanTexture.prewarm()`); the images are only needed
// once the notch opens.

nonisolated enum DesvanTexture {
    /// Pixels per point: sharp on Retina, gently downsampled on 1× displays.
    static let scale: CGFloat = 2

    /// Horizontal wood grain, 720×220 pt, seamless horizontally (tile it).
    static var wood: Image { Image(decorative: woodImage.cg, scale: scale) }
    /// Kraft paper fibres, 128×128 pt, seamless.
    static var kraft: Image { Image(decorative: kraftImage.cg, scale: scale) }
    /// Cardboard liner: coarse fibres over faint flute ridges, 128×128 pt, seamless.
    static var cardboard: Image { Image(decorative: cardboardImage.cg, scale: scale) }

    /// Generates every texture now (call from a background task at launch).
    static func prewarm() {
        _ = woodImage
        _ = kraftImage
        _ = cardboardImage
    }

    // MARK: Cache

    /// CGImage is immutable once created; the box only exists to cross isolation domains.
    final class Box: @unchecked Sendable {
        let cg: CGImage
        init(_ cg: CGImage) { self.cg = cg }
    }

    private static let woodImage = Box(makeWood(widthPt: 720, heightPt: 220))
    private static let kraftImage = Box(makeFibres(sidePt: 128, seed: 0xC0FF_EE11, flutes: false))
    private static let cardboardImage = Box(makeFibres(sidePt: 128, seed: 0x0B0C_5EED, flutes: true))

    // MARK: Wood

    /// Long, gently wavy grain lines, fine fibre streaks and a little pore noise.
    private static func makeWood(widthPt: Int, heightPt: Int) -> CGImage {
        let width = Int(CGFloat(widthPt) * scale), height = Int(CGFloat(heightPt) * scale)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let s = Double(scale)
        let w = Double(widthPt)
        var rng = Rng(seed: 0x57A1_7B0A_4D21_9E3F)
        for py in 0..<height {
            let v = Double(py) / s
            for px in 0..<width {
                let u = Double(px) / s
                // Slow warp: the grain lines meander along the board.
                let warp = (Noise.value(u / 180, v / 38, periodX: w / 180, seed: 1) - 0.5) * 16
                    + (Noise.value(u / 60, v / 12, periodX: w / 60, seed: 2) - 0.5) * 4
                // Growth rings seen edge-on: thin dark latewood lines ~5 pt apart (spacing drifts along the board),
                // each with a paler band of earlywood beside it.
                let ring = (v + warp) / (4.6 + 1.6 * Noise.value(u / 200, v / 60, periodX: w / 200, seed: 6))
                let late = pow(0.5 + 0.5 * cos(2 * .pi * ring), 9)
                let early = pow(0.5 + 0.5 * cos(2 * .pi * (ring - 0.2)), 14)
                let lineStrength = 0.35 + 0.65 * Noise.value(u / 120, v / 18, periodX: w / 120, seed: 3)
                // Fibre streaks: noise stretched hard along the grain.
                let streak = Noise.value(u / 24, v / 0.9, periodX: w / 24, seed: 4) - 0.5
                let broad = Noise.value(u / 90, v / 7, periodX: w / 90, seed: 5) - 0.5
                let pore = rng.unit() - 0.5
                let value = -1.15 * late * lineStrength + 0.45 * early * lineStrength
                    + 0.30 * streak + 0.40 * broad + 0.08 * pore
                write(value, gain: 0.85, into: &pixels, at: (py * width + px) * 4)
            }
        }
        return image(pixels, width: width, height: height)!
    }

    // MARK: Kraft and cardboard

    /// Mottled paper with short fibres (light and dark). With `flutes`, faint vertical ridges show through, like the
    /// corrugation under a cardboard liner.
    private static func makeFibres(sidePt: Int, seed: UInt64, flutes: Bool) -> CGImage {
        let side = Int(CGFloat(sidePt) * scale)
        let s = Double(scale)
        let period = Double(sidePt)
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { fatalError("Desván: couldn't allocate a texture context") }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var pixels = UnsafeMutableBufferPointer(start: bytes, count: side * side * 4)
        for py in 0..<side {
            let v = Double(py) / s
            for px in 0..<side {
                let u = Double(px) / s
                var value = (Noise.value(u / 32, v / 32, periodX: period / 32, periodY: period / 32, seed: 11) - 0.5) * 0.9
                value += (Noise.value(u / 8, v / 8, periodX: period / 8, periodY: period / 8, seed: 12) - 0.5) * 0.5
                if flutes {
                    // ~4 pt flutes (32 per tile keeps it seamless).
                    value += 0.09 * sin(2 * .pi * u * 32 / period)
                }
                write(value, gain: 0.35, into: &pixels, at: (py * side + px) * 4)
            }
        }
        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        var rng = Rng(seed: seed)
        let count = flutes ? 300 : 380
        for _ in 0..<count {
            let x = rng.unit() * period, y = rng.unit() * period
            let angle = rng.unit() * .pi
            let length = 1 + rng.unit() * (flutes ? 4 : 5)
            let bend = (rng.unit() - 0.5) * 2
            let light = rng.unit() < 0.55
            let alpha = light ? 0.10 + rng.unit() * 0.18 : 0.08 + rng.unit() * 0.14
            if light { context.setStrokeColor(red: 1, green: 0.95, blue: 0.84, alpha: alpha) } else { context.setStrokeColor(gray: 0, alpha: alpha) }
            context.setLineWidth(0.25 + rng.unit() * 0.4)
            // Draw each fibre at its wrapped positions too, so the tile stays seamless.
            for ox in [-period, 0, period] {
                for oy in [-period, 0, period] {
                    let cx = x + ox, cy = y + oy
                    guard cx > -10, cx < period + 10, cy > -10, cy < period + 10 else { continue }
                    let dx = cos(angle) * length / 2, dy = sin(angle) * length / 2
                    context.move(to: CGPoint(x: cx - dx, y: cy - dy))
                    context.addQuadCurve(
                        to: CGPoint(x: cx + dx, y: cy + dy),
                        control: CGPoint(x: cx - dy * bend * 0.4, y: cy + dx * bend * 0.4)
                    )
                    context.strokePath()
                }
            }
        }
        // A few darker flecks.
        for _ in 0..<(flutes ? 40 : 50) {
            let x = rng.unit() * period, y = rng.unit() * period, r = 0.25 + rng.unit() * 0.45
            context.setFillColor(gray: 0, alpha: 0.18 + rng.unit() * 0.22)
            context.fillEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        return context.makeImage()!
    }

    // MARK: Pixels

    /// Encodes a signed value as premultiplied grey + alpha: negative → black, positive → white.
    /// Light is warm (pale wood/kraft), not white, so highlights never turn the material grey.
    private static func write<P: MutableCollection<UInt8>>(
        _ value: Double, gain: Double, light: (Double, Double, Double) = (1, 0.86, 0.66),
        into pixels: inout P, at index: P.Index
    ) where P.Index == Int {
        let alpha = min(abs(value) * gain, 1)
        let a = UInt8(alpha * 255)
        let isLight = value > 0
        // Premultiplied.
        pixels[index] = isLight ? UInt8(alpha * light.0 * 255) : 0
        pixels[index + 1] = isLight ? UInt8(alpha * light.1 * 255) : 0
        pixels[index + 2] = isLight ? UInt8(alpha * light.2 * 255) : 0
        pixels[index + 3] = a
    }

    private static func image(_ pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// xorshift64*: fixed seeds, identical textures on every launch.
    private struct Rng {
        var state: UInt64
        init(seed: UInt64) { state = seed | 1 }
        mutating func unit() -> Double {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return Double((state &* 0x2545_F491_4F6C_DD1D) >> 11) / Double(1 << 53)
        }
    }
}

/// Smooth value noise on an integer lattice, optionally periodic (for seamless tiles).
nonisolated enum Noise {
    static func value(_ x: Double, _ y: Double, periodX: Double = 0, periodY: Double = 0, seed: UInt32) -> Double {
        let x0 = x.rounded(.down), y0 = y.rounded(.down)
        let fx = x - x0, fy = y - y0
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let px = Int(periodX.rounded()), py = Int(periodY.rounded())
        func wrap(_ i: Int, _ p: Int) -> Int { p > 0 ? ((i % p) + p) % p : i }
        let ix = Int(x0), iy = Int(y0)
        let a = hash(wrap(ix, px), wrap(iy, py), seed)
        let b = hash(wrap(ix + 1, px), wrap(iy, py), seed)
        let c = hash(wrap(ix, px), wrap(iy + 1, py), seed)
        let d = hash(wrap(ix + 1, px), wrap(iy + 1, py), seed)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    private static func hash(_ x: Int, _ y: Int, _ seed: UInt32) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 374_761_393
        h = h &+ UInt32(truncatingIfNeeded: y) &* 668_265_263
        h = h &+ seed &* 2_246_822_519
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h & 0xFF_FFFF) / Double(0xFF_FFFF)
    }
}

// MARK: - Overlays

extension View {
    /// Lays a cached procedural texture over the view, clipped to `shape`, at `opacity`.
    func desvanTexture<S: Shape>(_ image: Image, opacity: Double, in shape: S) -> some View {
        overlay {
            image
                .resizable(resizingMode: .tile)
                .opacity(opacity)
                .clipShape(shape)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
