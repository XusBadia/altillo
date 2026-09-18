import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Shown while a drag is near the notch: the cardboard box (≈ 75 %) and the paper plane for AirDrop (≈ 25 %).
/// Both lie flat, text at 40 %, until the pointer is over one of them (`hovered`): only that one reacts.
/// Each zone reports its frame so the AppKit drop target knows where the pointer is.
struct DesvanDropZones: View {
    let model: NotchModel
    let hovered: DropZone?

    var body: some View {
        HStack(spacing: 10) {
            DesvanBoxZone(model: model, isHovering: hovered == .shelf)
                .desvanDropZoneFrame(.shelf, model: model)
            DesvanAirDropZone(isHovering: hovered == .airDrop)
                .frame(width: 154)
                .desvanDropZoneFrame(.airDrop, model: model)
        }
    }
}

private extension View {
    /// Publishes this zone's frame (hosting-view coordinates) so the AppKit drop target can hit-test it.
    func desvanDropZoneFrame(_ zone: DropZone, model: NotchModel) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.dropZoneFrames[zone] = $0 }
            .onDisappear { model.dropZoneFrames[zone] = nil }
    }
}

// MARK: - The box

private struct DesvanBoxZone: View {
    let model: NotchModel
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            DesvanCardboardBox(openness: isHovering ? 1 : 0, warmth: isHovering ? 1 : 0)
                .animation(
                    reduceMotion ? Desvan.Motion.fade : (isHovering ? Desvan.Motion.flaps : Desvan.Motion.flapsClose),
                    value: isHovering
                )
                .frame(width: 184, height: 150)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text(isHovering ? "Suéltalo, ya lo guardo arriba" : "Guárdalo en el altillo")
                    .font(Desvan.Typeface.fraunces(17.5, weight: 600))
                    .foregroundStyle(Desvan.Palette.paper)
                    .contentTransition(.opacity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                if !model.shelf.isEmpty {
                    DesvanThumbStack(items: Array(model.shelf.suffix(5)), side: 20)
                        .padding(.top, 4)
                }
            }
            .opacity(isHovering ? 1 : 0.4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // The inside of the zone warms up under the pointer.
            RadialGradient(
                colors: [Desvan.Palette.bulb.opacity(isHovering ? 0.16 : 0), .clear],
                center: UnitPoint(x: 0.22, y: 0.5),
                startRadius: 0,
                endRadius: 220
            )
            .blendMode(.plusLighter)
        }
        .desvanCard(glow: isHovering ? Desvan.Palette.bulb : nil)
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: isHovering)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        model.shelf.isEmpty
            ? "Se queda arriba hasta que lo bajes a otro sitio."
            : "Ya hay \(NotchFormat.things(model.shelf.count)) esperando."
    }
}

// MARK: - AirDrop

/// The paper plane: it rises 3 pt and leans towards the pointer when hovered, in sky.
private struct DesvanAirDropZone: View {
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGRect = .zero

    var body: some View {
        VStack(spacing: 10) {
            plane
                .frame(width: 60, height: 52)
            VStack(spacing: 3) {
                Text("AirDrop")
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("mandarlo a otro dispositivo")
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isHovering ? 1 : 0.4)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(
                colors: [Desvan.Palette.sky.opacity(isHovering ? 0.16 : 0), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 110
            )
            .blendMode(.plusLighter)
        }
        .desvanCard(glow: isHovering ? Desvan.Palette.sky : nil)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frame = $0 }
        .animation(Desvan.Motion.pick(.spring(duration: 0.3, bounce: 0.3), reduceMotion: reduceMotion), value: isHovering)
    }

    @ViewBuilder
    private var plane: some View {
        if isHovering && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { _ in
                planeGlyph(lean: lean)
            }
        } else {
            planeGlyph(lean: 0)
        }
    }

    private func planeGlyph(lean: Double) -> some View {
        Image(systemName: "paperplane.fill")
            .font(.system(size: 30, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isHovering ? Desvan.Palette.sky : Desvan.Palette.paperTertiary)
            .shadow(color: isHovering ? Desvan.Palette.sky.opacity(0.5) : .clear, radius: 8)
            .rotationEffect(.degrees(lean))
            .offset(y: isHovering ? -3 : 0)
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(.black.opacity(isHovering ? 0.35 : 0.2))
                    .frame(width: 30, height: 5)
                    .blur(radius: 2)
                    .offset(y: 8)
            }
            .animation(.spring(duration: 0.35, bounce: 0.2), value: lean)
            .accessibilityHidden(true)
    }

    /// Leans up to 10° towards the pointer (the panel's hosting view is top-left, the screen is bottom-left).
    private var lean: Double {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.contains(NSEvent.mouseLocation) }),
              frame != .zero else { return -6 }
        let mouse = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        let x = mouse.x - frame.midX
        return min(max(x / 12, -10), 10)
    }
}

/// A few thumbnails overlapping, newest on top, each cut out with a wood-coloured ring.
struct DesvanThumbStack: View {
    let items: [ShelfItem]
    var side: CGFloat = 20
    var ring: Color = Desvan.Palette.wood

    var body: some View {
        HStack(spacing: -side * 0.36) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                ShelfThumbnail(item: item, side: side, compact: true)
                    .padding(1.5)
                    .background {
                        RoundedRectangle(cornerRadius: side * 0.24 + 1.5, style: .continuous).fill(ring)
                    }
                    .rotationEffect(.degrees(Desvan.jitter(item.id) * 4))
                    .zIndex(Double(index))
            }
        }
        .accessibilityHidden(true)
    }
}
