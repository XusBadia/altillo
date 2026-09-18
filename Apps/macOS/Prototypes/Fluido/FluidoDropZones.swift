import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Two glass zones (shelf and AirDrop) in one `GlassEffectContainer`. Both stay dim glass until the pointer is over
/// one (`model.dropZone`); only that one fills with its light, with a 120 pt radial focus that follows the pointer.
/// Moving from one zone to the other, the light *flows* across (one matched highlight that changes container).
/// Each zone reports its frame so the AppKit drop target can hit-test it.
struct FluidoDropZones: View {
    let model: NotchModel
    let pointer: CGPoint?

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lit: DropZone? { model.dropZone ?? FluidoFlags.hoverZone }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                zone(.shelf, light: .shelf)
                    .reportingFluidoDropZone(.shelf, to: model)
                zone(.airDrop, light: .airDrop)
                    .frame(width: 176)
                    .reportingFluidoDropZone(.airDrop, to: model)
            }
        }
        .animation(reduceMotion ? Fluido.Motion.reduced : .spring(duration: 0.34, bounce: 0.18), value: lit)
        .onChange(of: model.dropZone) { _, zone in
            // A tick on the trackpad when entering a zone.
            if zone != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        }
    }

    private func zone(_ zone: DropZone, light: Fluido.Light) -> some View {
        let isLit = lit == zone
        let shape = RoundedRectangle(cornerRadius: Fluido.Radius.card, style: .continuous)
        return GeometryReader { proxy in
            ZStack {
                if isLit {
                    LitZoneLight(light: light, focus: focus(in: proxy, zone: zone), size: proxy.size)
                        .matchedGeometryEffect(id: "flowingLight", in: namespace)
                        .transition(.opacity)
                }
                label(zone, light: light, isLit: isLit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipShape(shape)
        .fluidoGlass(shape, light: isLit ? light : nil, tint: 0, interactive: false, clear: true)
        .overlay {
            if isLit {
                // Lit edge: crisp stroke plus the same edge bloomed inwards, like the notch's own rim.
                ZStack {
                    shape.strokeBorder(light.linear(.topLeading, .bottomTrailing), lineWidth: 1.5)
                    shape.strokeBorder(light.linear(.topLeading, .bottomTrailing), lineWidth: 6)
                        .blur(radius: 7)
                        .blendMode(.plusLighter)
                        .opacity(0.8)
                }
                .clipShape(shape)
                .transition(.opacity)
            }
        }
        .scaleEffect(isLit && !reduceMotion ? 1.012 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isLit ? .isSelected : [])
    }

    /// Where the radial focus sits inside a zone: under the pointer, kept inside the zone.
    private func focus(in proxy: GeometryProxy, zone: DropZone) -> UnitPoint {
        let frame = proxy.frame(in: .global)
        guard let pointer, frame.width > 0, frame.height > 0 else { return UnitPoint(x: 0.5, y: 0.55) }
        return UnitPoint(
            x: min(max((pointer.x - frame.minX) / frame.width, 0.08), 0.92),
            y: min(max((pointer.y - frame.minY) / frame.height, 0.1), 0.9)
        )
    }

    @ViewBuilder
    private func label(_ zone: DropZone, light: Fluido.Light, isLit: Bool) -> some View {
        VStack(spacing: 11) {
            ZStack {
                if zone == .shelf {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 26, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(isLit ? AnyShapeStyle(light.linear(.top, .bottom)) : AnyShapeStyle(Fluido.Palette.textSecondary))
                        .symbolEffect(.bounce.down, value: isLit)
                } else {
                    AirDropMark()
                        .fill(isLit ? AnyShapeStyle(light.linear(.top, .bottom)) : AnyShapeStyle(Fluido.Palette.textSecondary))
                        .frame(width: 32, height: 32)
                }
            }
            .frame(height: 34)
            .shadow(color: light.mid.opacity(isLit ? 0.9 : 0), radius: 12)
            .scaleEffect(isLit && !reduceMotion ? 1.08 : 1)

            Text(zone == .shelf ? "Guardar" : "AirDrop")
                .font(Fluido.Typography.display)
                .foregroundStyle(isLit ? Fluido.Palette.text : Fluido.Palette.textSecondary)

            if zone == .shelf, !model.shelf.isEmpty {
                ThumbnailStack(items: Array(model.shelf.suffix(4)), side: 20)
                    .opacity(isLit ? 1 : 0.55)
            }
        }
    }
}

/// The light inside a lit zone: a wash of the module's light and a 120 pt focus under the pointer.
private struct LitZoneLight: View {
    let light: Fluido.Light
    let focus: UnitPoint
    let size: CGSize

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Light pooling at the floor of the zone, as if poured in from the rim.
            LinearGradient(colors: [.clear, light.to.opacity(0.16)], startPoint: .center, endPoint: .bottom)
            RadialGradient(
                stops: [
                    .init(color: light.from.opacity(reduceTransparency ? 0.35 : 0.62), location: 0),
                    .init(color: light.to.opacity(0.24), location: 0.45),
                    .init(color: .clear, location: 1),
                ],
                center: focus,
                startRadius: 0,
                endRadius: 120
            )
            .blendMode(.plusLighter)
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}

private extension View {
    /// Publishes this zone's frame (hosting-view coordinates) so the AppKit drop target can hit-test it.
    func reportingFluidoDropZone(_ zone: DropZone, to model: NotchModel) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.dropZoneFrames[zone] = $0 }
            .onDisappear { model.dropZoneFrames[zone] = nil }
    }
}
