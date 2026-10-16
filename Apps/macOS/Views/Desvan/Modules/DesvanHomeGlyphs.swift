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

/// A window with a blind: slats come down from the top and cover `1 − position` of it (the glyph *is* the
/// position), daylight shows below them, a bottom rail ends the blind. Animates between positions.
struct DesvanBlindGlyph: View {
    /// 0 closed … 1 open.
    var position: Double
    var size: CGFloat = 20
    /// On a lit plate (open, or a daylight scene) the window glows a little.
    var isActive: Bool = true
    /// Dims the drawing for unavailable blinds.
    var isDimmed: Bool = false

    var body: some View {
        let frame = RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
        let inset = size * 0.1
        ZStack {
            // Daylight: the sky at the top, a warm sill at the bottom.
            frame.fill(LinearGradient(
                colors: [Desvan.Palette.sky.opacity(isActive ? 0.95 : 0.55),
                         Color(hex: 0xF2D9A8).opacity(isActive ? 0.9 : 0.45)],
                startPoint: .top, endPoint: .bottom
            ))
            .padding(inset)
            BlindSlats(covered: 1 - min(max(position, 0), 1), slats: size >= 30 ? 9 : 5)
                .fill(LinearGradient(colors: [Color(hex: 0xEDE3D1), Color(hex: 0xB9A88E)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(inset)
            frame.strokeBorder(
                LinearGradient(colors: [Color(hex: 0xE9CD92), Color(hex: 0x8A6A3A)], startPoint: .top, endPoint: .bottom),
                lineWidth: min(max(1, size * 0.08), 3.5)
            )
        }
        .frame(width: size, height: size * 1.05)
        .opacity(isDimmed ? 0.55 : 1)
        .accessibilityHidden(true)
    }

    /// Slats from the top down to `covered` of the height, each a thin bar with a gap, and a heavier rail at the end.
    private struct BlindSlats: Shape {
        var covered: Double
        var slats: Int

        var animatableData: Double {
            get { covered }
            set { covered = newValue }
        }

        func path(in rect: CGRect) -> Path {
            var path = Path()
            let bottom = rect.minY + rect.height * covered
            let pitch = rect.height / CGFloat(slats)
            var y = rect.minY
            while y < bottom - 0.5 {
                let height = min(pitch * 0.68, bottom - y)
                path.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: height))
                y += pitch
            }
            // The bottom rail, always visible (a fully open blind keeps it at the top).
            let rail = max(1.2, pitch * 0.5)
            path.addRoundedRect(in: CGRect(x: rect.minX - 0.5, y: min(max(bottom - rail, rect.minY), rect.maxY - rail),
                                           width: rect.width + 1, height: rail),
                                cornerSize: CGSize(width: rail / 2, height: rail / 2))
            return path
        }
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
