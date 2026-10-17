import AltilloHome
import SwiftUI

// The Home section's drawn pieces (docs/casa-v2.md §1): the bakelite disc a tile's glyph sits in, the blind whose
// slats are its position, the brass of a dimmer, and the glyph a tile shows for each kind of thing.

// MARK: - Bakelite disc

/// A black bakelite disc set into the switch plate, the way an old rotary switch sits in its plate: a domed face
/// catching the bulb on its top edge, a thin `hairlineStrong` ring and, when the thing is on, its light inside.
struct DesvanBakeliteDisc<Content: View>: View {
    var size: CGFloat = 32
    /// 0…1: how much of the light is inside the disc.
    var glow: Double = 0
    var tint: Color = Desvan.Palette.bulb
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0x2A2521), Color(hex: 0x0E0C0A)],
                    center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: size * 0.7
                ))
            // The light inside the disc: added, not painted.
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.42 * glow), tint.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: size * 0.55))
                .blendMode(.plusLighter)
            // The dome: a soft highlight on the upper half, a dark lower rim.
            Circle()
                .strokeBorder(
                    LinearGradient(stops: [
                        .init(color: Desvan.Palette.paper.opacity(0.30), location: 0),
                        .init(color: Desvan.Palette.paper.opacity(0.06), location: 0.45),
                        .init(color: .black.opacity(0.6), location: 1),
                    ], startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.9
                )
            Circle()
                .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.6)
                .padding(-1.2)
            content
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - Blind

/// A slatted *persiana* or a fabric roller shade.
enum DesvanBlindStyle: Equatable {
    case slats, fabric
}

/// The window's parts, shared by the drawing and the gesture: the oak frame, the roller box over it, the glass, the
/// bottom rail and how far its edge travels (`travelTop` is the edge fully open, `travelTop + travel` closed).
struct DesvanBlindMetrics {
    let size: CGSize
    let detail: Bool

    var sill: CGFloat { detail ? 8 : 0 }
    var sillOverhang: CGFloat { detail ? 6 : 0 }
    var frameWidth: CGFloat { detail ? 9 : max(1.4, size.width * 0.09) }
    var boxHeight: CGFloat { detail ? 17 : size.height * 0.15 }
    var frame: CGRect {
        CGRect(x: sillOverhang, y: 0, width: size.width - 2 * sillOverhang, height: size.height - sill + (detail ? 2 : 0))
    }
    var box: CGRect { CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frameWidth + boxHeight) }
    var glass: CGRect {
        CGRect(x: frame.minX + frameWidth, y: box.maxY, width: frame.width - 2 * frameWidth,
               height: frame.maxY - frameWidth - box.maxY)
    }
    var rail: CGFloat { detail ? 8 : max(1.4, glass.height * 0.1) }
    var travelTop: CGFloat { glass.minY + rail }
    var travel: CGFloat { glass.height - rail }
}

/// A window in an oak frame with a cream roller box over it and a warm late-afternoon view through the glass (sky,
/// sun, two hills); the blind comes down from the box and covers `1 − position` of the glass. A *persiana* is
/// slats with lit tops and slits of light between them, a shade is linen; both end in a bronze rail with a brass
/// pull and cast a soft shadow on the glass. `detail` draws the big window (sill, mullion, guides, screws).
struct DesvanBlindArt: View, Animatable {
    var position: Double
    var style: DesvanBlindStyle = .slats
    var detail = false
    var isActive = true

    nonisolated var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, metrics: DesvanBlindMetrics(size: size, detail: detail),
                      position: min(max(position, 0), 1), style: style, isActive: isActive)
        }
        .accessibilityHidden(true)
    }

    private static func linear(_ hexes: [UInt32], _ from: CGPoint, _ to: CGPoint, opacity: Double = 1) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: hexes.map { Color(hex: $0, opacity: opacity) }), startPoint: from, endPoint: to)
    }

    static func draw(in context: inout GraphicsContext, metrics m: DesvanBlindMetrics, position: Double,
                     style: DesvanBlindStyle, isActive: Bool) {
        let detail = m.detail
        let frame = m.frame, glass = m.glass, box = m.box
        let radius = detail ? 5 : max(1.5, m.size.width * 0.1)

        // Sill: the ledge the window stands on.
        if detail {
            let sill = CGRect(x: 0, y: m.size.height - m.sill, width: m.size.width, height: m.sill)
            context.fill(Path(roundedRect: sill, cornerRadius: 2),
                         with: linear([0xA87C55, 0x6E4A2D, 0x4A3020], CGPoint(x: 0, y: sill.minY), CGPoint(x: 0, y: sill.maxY)))
            context.fill(Path(CGRect(x: sill.minX + 1, y: sill.minY, width: sill.width - 2, height: 0.8)),
                         with: .color(Color(hex: 0xF0D3A8).opacity(0.55)))
        }

        // The oak frame.
        let framePath = Path(roundedRect: frame, cornerRadius: radius, style: .continuous)
        context.fill(framePath, with: linear(detail ? [0xA9784C, 0x7D5432, 0x5C3B22] : [0xD3A56B, 0x9A6B40, 0x6E4A2B],
                                              CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.maxY)))
        if detail {
            // Grain along the stiles.
            for index in 0..<6 {
                let x = frame.minX + 1.5 + CGFloat(index) * 1.3
                context.fill(Path(CGRect(x: x, y: box.maxY, width: 0.5, height: frame.maxY - box.maxY)),
                             with: .color(.black.opacity(index.isMultiple(of: 2) ? 0.10 : 0.05)))
                context.fill(Path(CGRect(x: frame.maxX - 2 - CGFloat(index) * 1.3, y: box.maxY, width: 0.5,
                                         height: frame.maxY - box.maxY)),
                             with: .color(.black.opacity(index.isMultiple(of: 2) ? 0.08 : 0.04)))
            }
        }
        context.stroke(Path(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius, style: .continuous),
                       with: linear([0xFFE6BE, 0x3A2414], CGPoint(x: 0, y: frame.minY), CGPoint(x: 0, y: frame.maxY),
                                    opacity: 0.55),
                       lineWidth: detail ? 1 : 0.5)

        // The view through the glass.
        let dim: Double = isActive ? 1 : 0.55
        var view = context
        view.clip(to: Path(roundedRect: glass, cornerRadius: detail ? 2 : 0.6))
        view.fill(Path(glass), with: linear([0x78A9D2, 0xA9CBE0, 0xE9DDBE, 0xF4C98F],
                                            CGPoint(x: 0, y: glass.minY), CGPoint(x: 0, y: glass.maxY), opacity: dim))
        let sun = CGPoint(x: glass.minX + glass.width * 0.7, y: glass.minY + glass.height * 0.6)
        view.fill(Path(ellipseIn: CGRect(x: sun.x - glass.width * 0.5, y: sun.y - glass.width * 0.5,
                                         width: glass.width, height: glass.width)),
                  with: .radialGradient(Gradient(colors: [Color(hex: 0xFFF6DA).opacity(0.95 * dim),
                                                          Color(hex: 0xFFE1A0).opacity(0.35 * dim), .clear]),
                                        center: sun, startRadius: 0, endRadius: glass.width * 0.5))
        if detail {
            view.fill(Path(ellipseIn: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)),
                      with: .color(Color(hex: 0xFFF8E6).opacity(dim)))
        }
        func hill(_ base: CGFloat, _ peaks: [(CGFloat, CGFloat)]) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: glass.minX - 2, y: glass.maxY + 2))
            path.addLine(to: CGPoint(x: glass.minX - 2, y: glass.minY + glass.height * base))
            var x = glass.minX - 2
            for (width, rise) in peaks {
                let next = x + glass.width * width
                path.addQuadCurve(to: CGPoint(x: next, y: glass.minY + glass.height * base),
                                  control: CGPoint(x: (x + next) / 2, y: glass.minY + glass.height * (base - rise)))
                x = next
            }
            path.addLine(to: CGPoint(x: glass.maxX + 2, y: glass.maxY + 2))
            path.closeSubpath()
            return path
        }
        view.fill(hill(0.8, [(0.55, 0.16), (0.6, 0.1)]), with: .color(Color(hex: 0xA3AE8A).opacity(0.9 * dim)))
        view.fill(hill(0.9, [(0.4, 0.08), (0.45, 0.14), (0.4, 0.05)]),
                  with: linear([0x6F8A5A, 0x4F6640], CGPoint(x: 0, y: glass.minY + glass.height * 0.75),
                               CGPoint(x: 0, y: glass.maxY), opacity: dim))
        // A reflection across the pane.
        var glare = Path()
        glare.move(to: CGPoint(x: glass.minX + glass.width * 0.1, y: glass.maxY))
        glare.addLine(to: CGPoint(x: glass.minX + glass.width * 0.32, y: glass.maxY))
        glare.addLine(to: CGPoint(x: glass.minX + glass.width * 0.78, y: glass.minY))
        glare.addLine(to: CGPoint(x: glass.minX + glass.width * 0.6, y: glass.minY))
        glare.closeSubpath()
        view.fill(glare, with: .color(.white.opacity(0.09)))

        // The blind.
        let edge = HomeDetailLogic.edgeY(position: position, top: m.travelTop, travel: m.travel)
        let railTop = edge - m.rail
        if railTop > glass.minY {
            let cloth = CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: railTop - glass.minY)
            switch style {
            case .slats:
                let pitch: CGFloat = detail ? 8 : max(2.2, glass.height / 5)
                let slit: CGFloat = detail ? 1.1 : 0.55
                // Light through the slits, then the slats from the rail up (they ride with it into the box).
                view.fill(Path(cloth), with: .color(Color(hex: 0xFFE3A6).opacity(0.75 * dim)))
                var top = railTop - pitch
                while top + pitch > glass.minY {
                    let slat = CGRect(x: glass.minX, y: top + slit, width: glass.width, height: pitch - slit)
                    view.fill(Path(slat), with: linear([0xF6EEDF, 0xE4D7BF, 0xC5B497],
                                                       CGPoint(x: 0, y: slat.minY), CGPoint(x: 0, y: slat.maxY)))
                    if detail {
                        view.fill(Path(CGRect(x: slat.minX, y: slat.minY, width: slat.width, height: 0.7)),
                                  with: .color(.white.opacity(0.75)))
                        view.fill(Path(CGRect(x: slat.minX, y: slat.maxY - 0.6, width: slat.width, height: 0.6)),
                                  with: .color(Color(hex: 0x6B5639).opacity(0.45)))
                    }
                    top -= pitch
                }
            case .fabric:
                view.fill(Path(cloth), with: linear([0xD6C6A8, 0xF2E8D6, 0xF6EEDF, 0xF2E8D6, 0xD3C3A4],
                                                    CGPoint(x: cloth.minX, y: 0), CGPoint(x: cloth.maxX, y: 0)))
                if detail {
                    var x = cloth.minX + 2
                    while x < cloth.maxX {
                        view.fill(Path(CGRect(x: x, y: cloth.minY, width: 0.5, height: cloth.height)),
                                  with: .color(Color(hex: 0x8A7552).opacity(0.10)))
                        x += 3
                    }
                }
                // The sun glowing through the linen.
                view.fill(Path(cloth), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0xFFD98F).opacity(0.25 * dim), .clear]),
                    center: sun, startRadius: 0, endRadius: glass.width * 0.6))
            }
            // The blind's shadow on the glass below it.
            let shadow = CGRect(x: glass.minX, y: edge, width: glass.width, height: detail ? 14 : 2.5)
            view.fill(Path(shadow), with: .linearGradient(Gradient(colors: [.black.opacity(0.38), .clear]),
                                                          startPoint: CGPoint(x: 0, y: shadow.minY),
                                                          endPoint: CGPoint(x: 0, y: shadow.maxY)))
        }
        // The bottom rail.
        let rail = CGRect(x: glass.minX, y: max(railTop, glass.minY - m.rail), width: glass.width, height: m.rail)
        view.fill(Path(roundedRect: rail, cornerRadius: min(2, m.rail / 3)),
                  with: linear(style == .fabric ? [0xB98F60, 0x7A5634] : [0xC29A68, 0x8C6942, 0x5E4428],
                               CGPoint(x: 0, y: rail.minY), CGPoint(x: 0, y: rail.maxY)))
        if detail {
            view.fill(Path(CGRect(x: rail.minX, y: rail.minY, width: rail.width, height: 0.8)),
                      with: .color(Color(hex: 0xFFE7BF).opacity(0.6)))
        }

        if detail {
            // A centre mullion and the guides the blind runs in.
            for x in [glass.minX, glass.maxX - 3] {
                context.fill(Path(CGRect(x: x, y: glass.minY, width: 3, height: glass.height)),
                             with: linear([0x2F2116, 0x5A3E28], CGPoint(x: x, y: 0), CGPoint(x: x + 3, y: 0), opacity: 0.85))
            }
            let mullion = CGRect(x: glass.midX - 2.5, y: max(edge, glass.minY), width: 5, height: glass.maxY - max(edge, glass.minY))
            if mullion.height > 0 {
                context.fill(Path(mullion), with: linear([0x6E4A2D, 0xB8875A, 0x6E4A2D],
                                                         CGPoint(x: mullion.minX, y: 0), CGPoint(x: mullion.maxX, y: 0)))
            }
            // Inner shadow of the opening.
            context.stroke(Path(glass.insetBy(dx: 0.75, dy: 0.75)),
                           with: linear([0x000000, 0x000000], CGPoint(x: glass.minX, y: glass.minY),
                                        CGPoint(x: glass.maxX, y: glass.maxY), opacity: 0.35),
                           lineWidth: 1.5)
        }

        // The pull: a brass handle hanging from the rail's middle.
        let pullY = rail.maxY
        if detail {
            let handle = CGRect(x: glass.midX - 11, y: pullY - 2, width: 22, height: 7)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 1.5, x: 0, y: 1))
                layer.fill(Path(roundedRect: handle, cornerRadius: 3.5),
                           with: linear([0xFBE7B5, 0xD6AE68, 0x8E6B37], CGPoint(x: 0, y: handle.minY),
                                        CGPoint(x: 0, y: handle.maxY)))
            }
            context.fill(Path(roundedRect: handle.insetBy(dx: 6, dy: 2.4), cornerRadius: 1.2),
                         with: .color(Color(hex: 0x4A3518).opacity(0.75)))
        } else if m.size.width >= 14 {
            let nub = CGRect(x: glass.midX - glass.width * 0.13, y: pullY - 0.3, width: glass.width * 0.26,
                             height: max(1, m.rail * 0.6))
            context.fill(Path(roundedRect: nub, cornerRadius: nub.height / 2), with: .color(Color(hex: 0xF0CF8A)))
        }

        // The roller box over the window.
        let boxPath = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: detail ? 1.5 : 0.5,
                                             bottomTrailingRadius: detail ? 1.5 : 0.5, topTrailingRadius: radius,
                                             style: .continuous).path(in: box)
        context.drawLayer { layer in
            layer.addFilter(.shadow(color: .black.opacity(0.45), radius: detail ? 3 : 0.8, x: 0, y: detail ? 2 : 0.6))
            layer.fill(boxPath, with: linear([0xF4ECDC, 0xE2D5BC, 0xC2B08E], CGPoint(x: 0, y: box.minY),
                                             CGPoint(x: 0, y: box.maxY)))
        }
        context.stroke(Path(CGRect(x: box.minX, y: box.minY + 0.4, width: box.width, height: 0.1)),
                       with: .color(.white.opacity(0.7)), lineWidth: detail ? 0.8 : 0.4)
        // The slot the blind rolls into.
        let slot = CGRect(x: glass.minX - 1, y: box.maxY - (detail ? 3 : 0.8), width: glass.width + 2, height: detail ? 2 : 0.6)
        context.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2), with: .color(Color(hex: 0x3A2A1A).opacity(0.7)))
        if detail {
            for x in [box.minX + 8, box.maxX - 8] {
                let screw = CGRect(x: x - 2.5, y: box.minY + box.height * 0.42 - 2.5, width: 5, height: 5)
                context.fill(Path(ellipseIn: screw),
                             with: .radialGradient(Gradient(colors: [Color(hex: 0xF4E3B8), Color(hex: 0x9C7A43)]),
                                                   center: CGPoint(x: screw.minX + 1.8, y: screw.minY + 1.6),
                                                   startRadius: 0, endRadius: 3.5))
                context.fill(Path(CGRect(x: screw.minX + 1, y: screw.midY - 0.35, width: 3, height: 0.7)),
                             with: .color(Color(hex: 0x4A3518).opacity(0.8)))
            }
        }
    }
}

/// A tile's blind: the big window's drawing at glyph size (frame, roller box, slats, rail and pull), so the glyph
/// *is* the position. Animates between positions.
struct DesvanBlindGlyph: View {
    /// 0 closed … 1 open.
    var position: Double
    var size: CGFloat = 20
    /// On a lit plate (open, or a daylight scene) the view through the window is bright.
    var isActive: Bool = true
    /// Dims the drawing for unavailable blinds.
    var isDimmed: Bool = false
    var style: DesvanBlindStyle = .slats

    var body: some View {
        DesvanBlindArt(position: position, style: style, detail: false, isActive: isActive)
            .frame(width: size, height: size * 1.05)
            .opacity(isDimmed ? 0.55 : 1)
            .accessibilityHidden(true)
    }
}

// MARK: - Brass

/// The brass thumb of a dimmer: a small polished disc, lit on top.
struct DesvanBrassThumb: View {
    var size: CGFloat = 14
    var isPressed = false

    var body: some View {
        Circle()
            .fill(RadialGradient(
                colors: [Color(hex: 0xFFF0C8), Color(hex: 0xE2BD78), Color(hex: 0x9C7A43)],
                center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: size * 0.7
            ))
            .overlay { Circle().strokeBorder(Color(hex: 0x5E4522).opacity(0.8), lineWidth: 0.6) }
            .shadow(color: .black.opacity(0.55), radius: isPressed ? 3 : 1.5, y: isPressed ? 2 : 1)
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 1.12 : 1)
            .accessibilityHidden(true)
    }
}

/// A dimmer's groove cut into the plate, filled with the light's colour as far as it's bright, with the brass thumb
/// at the level.
struct DesvanDimmerTrack: View {
    var level: Double
    var tint: Color
    var isActive: Bool
    var isDragging = false
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let thumb: CGFloat = 16
            let x = (width - thumb) * min(max(level, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .overlay {
                        Capsule().strokeBorder(
                            LinearGradient(colors: [.black.opacity(0.6), Desvan.Palette.paper.opacity(0.12)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.75
                        )
                    }
                    .frame(height: height)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, x + thumb / 2), height: height - 2)
                    .padding(.leading, 1)
                    .shadow(color: tint.opacity(0.6), radius: 4)
                    .opacity(isActive ? 1 : 0)
                DesvanBrassThumb(size: thumb, isPressed: isDragging)
                    .offset(x: x)
            }
            .frame(height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - A tile's glyph

/// What sits in a tile's disc: the user's own SF Symbol if they picked one; otherwise a light's bulb (lit as bright as
/// it is, in its real colour), a blind's slats at its position, and filled SF Symbols for the rest (brass when on).
struct DesvanHomeGlyph: View {
    let entity: HomeEntity
    let state: HomeEntityState
    /// The user's symbol, nil for the kind's own glyph.
    var symbol: String?
    var size: CGFloat = 20
    var tint: Color
    /// 0…1, how lit the thing is.
    var glow: Double
    /// The level a drag is showing (brightness or position), ahead of the state.
    var level: Double?

    var body: some View {
        if let symbol {
            sfSymbol(symbol)
        } else {
            switch entity.kind {
            case .light:
                DesvanBulbGlyph(size: size, lit: glow, tint: tint)
                    .offset(y: size * 0.06)
            case .cover where entity.deviceClass != "garage" && entity.deviceClass != "gate":
                DesvanBlindGlyph(position: level ?? coverPosition, size: size * 0.92,
                                 isActive: state.isAvailable && coverPosition > 0, isDimmed: !state.isAvailable)
            default:
                sfSymbol(HomeText.filledSymbol(for: entity, state: state))
            }
        }
    }

    private var coverPosition: Double {
        state.position ?? (HomeStore.coverIsOpen(state) ? 1 : 0)
    }

    private func sfSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(glow > 0 ? AnyShapeStyle(tint) : AnyShapeStyle(Desvan.Palette.paperSecondary))
            .shadow(color: tint.opacity(0.7 * glow), radius: 5)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
    }
}

// MARK: - Luggage tag

/// A luggage tag: a card with its left end cut at both corners, where the eyelet goes.
struct DesvanLuggageTagShape: Shape {
    var cut: CGFloat = 9
    var radius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        let cut = min(cut, rect.height / 2.5)
        return Path.rounded([
            CGPoint(x: rect.minX + cut, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX + cut, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY - cut),
            CGPoint(x: rect.minX, y: rect.minY + cut),
        ], radius: radius)
    }
}

/// A dashed bevel for things that can't be reached right now.
struct DesvanDashedBevel: View {
    var radius: CGFloat = 12

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Desvan.Palette.paper.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
