import AltilloCore
import AltilloDesign
import AppKit
import SwiftUI

/// Shown while a drag is near the notch: the cardboard box (≈ 70 %) and the paper plane for AirDrop (≈ 30 %).
/// Both lie flat, text at 60 % (still readable at a glance), until the pointer is over one of them (`hovered`):
/// only that one reacts.
/// Each zone reports its frame so the AppKit drop target knows where the pointer is.
struct DesvanDropZones: View {
    let model: NotchModel
    let hovered: DropZone?

    @State private var width: CGFloat = 0

    private static let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: Self.spacing) {
            DesvanBoxZone(model: model, isHovering: hovered == .shelf)
                .desvanDropZoneFrame(.shelf, model: model)
            DesvanAirDropZone(isHovering: hovered == .airDrop)
                // The plane keeps a comfortable corner (≈ 30 %, 116–168 pt) whatever the notch is set to, so a
                // narrow notch still leaves the box room for its words; the box takes the rest.
                .frame(width: planeWidth)
                .desvanDropZoneFrame(.airDrop, model: model)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private var planeWidth: CGFloat {
        guard width > 0 else { return 150 }
        return min(max((width - Self.spacing) * 0.3, 116), 168)
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
    @State private var width: CGFloat = 0

    /// The box grows with the room it has: nearly full size on a roomy notch, smaller on a narrow one so the words
    /// beside it (≈ 170 pt) still fit. At most 0.9, 176 × 131 pt, well inside the 160 pt tall zone.
    private var boxScale: CGFloat {
        guard width > 0 else { return 0.8 }
        let room = width - 24 - 170 // leading and trailing padding, the gap, and the words
        return min(max(room / DesvanCardboardBox.canvasSize.width, 0.5), 0.9)
    }

    var body: some View {
        HStack(spacing: 8) {
            DesvanCardboardBox(openness: isHovering ? 1 : 0, warmth: isHovering ? 1 : 0, scale: boxScale)
                .animation(
                    reduceMotion ? Desvan.Motion.fade : (isHovering ? Desvan.Motion.flaps : Desvan.Motion.flapsClose),
                    value: isHovering
                )
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                // Narrow notches get the short sentences instead of a truncated long one.
                ViewThatFits(in: .horizontal) {
                    title(isHovering ? "Drop it, I'll put it up" : "Put it on the shelf")
                    title(isHovering ? "Drop it, I've got it" : "Put it up there")
                }
                ViewThatFits(in: .horizontal) {
                    subtitle(long, showsStack: true)
                    subtitle(short, showsStack: true)
                    subtitle(short, showsStack: false)
                }
            }
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(.leading, 2)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background {
            // The inside of the zone warms up under the pointer.
            RadialGradient(
                colors: [Desvan.Palette.bulb.opacity(isHovering ? 0.16 : 0), .clear],
                center: UnitPoint(x: 0.2, y: 0.5),
                startRadius: 0,
                endRadius: 220
            )
            .blendMode(.plusLighter)
        }
        .desvanCard(glow: isHovering ? Desvan.Palette.bulb : nil)
        .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: isHovering)
        .accessibilityElement(children: .combine)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Desvan.Typeface.display(17, weight: 600))
            .foregroundStyle(Desvan.Palette.paper)
            .contentTransition(.opacity)
            .lineLimit(1)
            .fixedSize()
    }

    private func subtitle(_ text: LocalizedStringKey, showsStack: Bool) -> some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .lineLimit(1)
                .fixedSize()
            if showsStack, !model.shelf.isEmpty {
                DesvanThumbStack(items: Array(model.shelf.suffix(5)), side: 18)
            }
        }
    }

    private var long: LocalizedStringKey {
        model.shelf.isEmpty
            ? "It stays up there until you take it down somewhere else."
            : "\(NotchFormat.things(model.shelf.count)) already waiting."
    }

    private var short: LocalizedStringKey {
        model.shelf.isEmpty ? "Until you take it down." : "\(model.shelf.count) already waiting."
    }
}

// MARK: - AirDrop

/// The paper plane: it rises 4 pt and leans towards the pointer when hovered, in sky.
private struct DesvanAirDropZone: View {
    let isHovering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame: CGRect = .zero

    var body: some View {
        VStack(spacing: 10) {
            plane
                .frame(width: 60, height: 52)
            VStack(spacing: 2) {
                Text("AirDrop")
                    .font(Desvan.Typeface.rounded(15, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("to another device")
                    .font(.system(size: 13))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
            }
            .opacity(isHovering ? 1 : 0.6)
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
        DesvanPaperPlane(tint: isHovering ? Desvan.Palette.sky : nil)
            .frame(width: 46, height: 38)
            .opacity(isHovering ? 1 : 0.5)
            .shadow(color: isHovering ? Desvan.Palette.sky.opacity(0.45) : .clear, radius: 6)
            .rotationEffect(.degrees(lean))
            .offset(y: isHovering ? -4 : 0)
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(.black.opacity(isHovering ? 0.4 : 0.25))
                    .frame(width: isHovering ? 30 : 36, height: 5)
                    .blur(radius: isHovering ? 3 : 2)
                    .offset(y: 9)
            }
            .animation(Desvan.Motion.pick(.spring(duration: 0.35, bounce: 0.2), reduceMotion: reduceMotion), value: lean)
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

/// A folded paper plane (AirDrop): two facets of paper with a crease, lit from above. `tint` washes it in a colour.
struct DesvanPaperPlane: View {
    var tint: Color?

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let nose = CGPoint(x: w * 0.98, y: h * 0.06)
            let wing = CGPoint(x: w * 0.02, y: h * 0.46)
            let keel = CGPoint(x: w * 0.40, y: h * 0.60)
            let tail = CGPoint(x: w * 0.52, y: h * 0.98)
            let paper = tint.map { Desvan.Palette.paper.mix(with: $0, by: 0.35) } ?? Desvan.Palette.paper
            // Lower facet (in shade).
            var lower = Path()
            lower.addLines([nose, keel, tail])
            lower.closeSubpath()
            context.fill(lower, with: .color(paper.mix(with: Color(hex: 0x6B5A48), by: 0.45)))
            // Upper wing (facing the light).
            var upper = Path()
            upper.addLines([nose, wing, keel])
            upper.closeSubpath()
            context.fill(upper, with: .linearGradient(
                Gradient(colors: [paper, paper.mix(with: Color(hex: 0xB9A98F), by: 0.35)]),
                startPoint: nose, endPoint: wing
            ))
            context.fill(upper, with: .tiledImage(DesvanTexture.kraft, origin: .zero,
                                                  sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: 1))
            // The crease.
            var crease = Path()
            crease.move(to: nose)
            crease.addLine(to: keel)
            context.stroke(crease, with: .color(Color(hex: 0x6B5A48).opacity(0.55)), lineWidth: 0.75)
            context.stroke(upper, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
            context.stroke(lower, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}
