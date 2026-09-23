import AltilloDesign
import SwiftUI

// Materials of the attic: the bulb's light, wood cards with paper grain, the plank, the house mark,
// a rubber stamp. Nothing here ever draws on the silhouette itself: it stays pure black.

// MARK: - Bulb light

/// Warm light from a bulb hanging just under the notch: a radial `bulb` gradient over the interior.
/// Light, not paint: it's added (`plusLighter`) so it warms whatever it falls on.
struct DesvanBulbGlow: View {
    /// Peak opacity of the light (6 % at rest, up to 14 % while a drag comes close).
    var intensity: Double
    var radius: CGFloat = 180
    /// Vertical position of the bulb in the view.
    var originY: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let center = UnitPoint(x: 0.5, y: proxy.size.height > 0 ? originY / proxy.size.height : 0)
            RadialGradient(
                stops: [
                    .init(color: Desvan.Palette.bulb.opacity(intensity), location: 0),
                    .init(color: Desvan.Palette.bulb.opacity(intensity * 0.45), location: 0.45),
                    .init(color: Desvan.Palette.bulb.opacity(0), location: 1),
                ],
                center: center,
                startRadius: 0,
                endRadius: radius
            )
            .scaleEffect(x: 1.7, y: 1, anchor: center)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Wood card

/// A dark wood card: procedural grain running along the board, paper grain on top, a marked top lip (the edge
/// catching the bulb's light) and a soft inner shadow at the bottom, like a shallow tray.
struct DesvanCard: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Desvan.Palette.wood
    var glow: Color? = nil
    /// Strength of the wood grain (0 = plain).
    var grain: Double = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .desvanTexture(DesvanTexture.wood, opacity: 0.17 * grain, in: shape)
                    .overlay {
                        // Inner shadow: the card is a little tray, darker towards its bottom edge and its sides.
                        shape.fill(LinearGradient(
                            colors: [.clear, .black.opacity(0.26)],
                            startPoint: UnitPoint(x: 0.5, y: 0.5),
                            endPoint: .bottom
                        ))
                    }
                    .grain(0.04, in: shape)
                    .overlay {
                        // Bevel: a lit top lip, fading down the sides, and a dark bottom edge.
                        shape.strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Desvan.Palette.paper.opacity(0.16), location: 0),
                                    .init(color: Desvan.Palette.hairline, location: 0.12),
                                    .init(color: Desvan.Palette.hairline.opacity(0.3), location: 0.8),
                                    .init(color: .black.opacity(0.5), location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                    }
            }
            .overlay {
                if let glow {
                    shape.strokeBorder(glow.opacity(0.85), lineWidth: 1)
                        .shadow(color: glow.opacity(0.55), radius: 8)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func desvanCard(radius: CGFloat = 14, fill: Color = Desvan.Palette.wood, glow: Color? = nil, grain: Double = 1) -> some View {
        modifier(DesvanCard(radius: radius, fill: fill, glow: glow, grain: grain))
    }
}

// MARK: - Plank

/// The shelf's board, seen a little from above: a narrow top surface the things stand on, a front edge with the
/// grain running along it, a lit arris between the two and a soft shadow cast on the wall below.
struct DesvanPlank: View {
    static let top: CGFloat = 4
    static let front: CGFloat = 7
    static var height: CGFloat { top + front }

    var body: some View {
        VStack(spacing: 0) {
            // Top surface: lighter, it faces the bulb.
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(hex: 0x3E3329), Color(hex: 0x54463A)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .desvanTexture(DesvanTexture.wood, opacity: 0.55, in: Rectangle())
                .frame(height: Self.top)
            // The arris catches the light.
            Rectangle().fill(Color(hex: 0xE8CFA6).opacity(0.30)).frame(height: 0.5)
            // Front edge.
            Rectangle()
                .fill(LinearGradient(
                    colors: [Color(hex: 0x3F3329), Desvan.Palette.plank, Color(hex: 0x261E17)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .desvanTexture(DesvanTexture.wood, opacity: 0.9, in: Rectangle())
                .frame(height: Self.front - 0.5)
        }
        .background(alignment: .top) {
            // Shadow cast on the wall below: dense at the board, long and soft further down.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.35),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 16)
            .offset(y: Self.height)
        }
        .frame(height: Self.height, alignment: .top)
        .accessibilityHidden(true)
    }
}

// MARK: - Rounded polygons

extension Path {
    /// A closed polygon with every corner rounded by `radius` (tangent arcs).
    static func rounded(_ points: [CGPoint], radius: CGFloat) -> Path {
        var path = Path()
        guard points.count > 2 else { return path }
        let count = points.count
        let first = CGPoint(
            x: (points[count - 1].x + points[0].x) / 2,
            y: (points[count - 1].y + points[0].y) / 2
        )
        path.move(to: first)
        for index in 0..<count {
            let corner = points[index]
            let next = points[(index + 1) % count]
            path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - House mark

/// The brand: a house profile (pentagon) with a small lit window. "There's light in the attic".
struct DesvanHouseMark: View {
    var size: CGFloat = 14
    var lit: Double = 1
    var outline: Color = Desvan.Palette.paper

    var body: some View {
        ZStack {
            HouseOutline()
                .stroke(outline, style: StrokeStyle(lineWidth: max(1.2, size * 0.1), lineCap: .round, lineJoin: .round))
            RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                .fill(Desvan.Palette.bulb.opacity(0.25 + 0.75 * lit))
                .frame(width: size * 0.26, height: size * 0.26)
                .shadow(color: Desvan.Palette.bulb.opacity(0.9 * lit), radius: size * 0.22)
                .offset(y: size * 0.1)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private struct HouseOutline: Shape {
        func path(in rect: CGRect) -> Path {
            let inset = rect.width * 0.08
            let r = rect.insetBy(dx: inset, dy: inset)
            let points = [
                CGPoint(x: r.midX, y: r.minY),
                CGPoint(x: r.maxX, y: r.minY + r.height * 0.42),
                CGPoint(x: r.maxX, y: r.maxY),
                CGPoint(x: r.minX, y: r.maxY),
                CGPoint(x: r.minX, y: r.minY + r.height * 0.42),
            ]
            return Path.rounded(points, radius: rect.width * 0.08)
        }
    }
}

// MARK: - Bulb glyph

/// A hand-drawn light bulb. `lit` 0…1 takes it from a cold, smoky glass with a dark filament to a hot filament
/// glowing inside amber glass, with a halo of light around it.
struct DesvanBulbGlyph: View {
    var size: CGFloat = 14
    var lit: Double = 1

    var body: some View {
        let glass = size * 0.8
        let neck = glass * 0.5
        let shape = BulbGlass()
        ZStack(alignment: .top) {
            // Halo: light, not paint.
            Circle()
                .fill(RadialGradient(
                    colors: [Desvan.Palette.bulb.opacity(0.55 * lit), Desvan.Palette.bulb.opacity(0.12 * lit), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: glass * 1.5
                ))
                .frame(width: glass * 3, height: glass * 3)
                .offset(y: -glass * 1.0)
                .blendMode(.plusLighter)

            VStack(spacing: -0.5) {
                ZStack {
                    // Cold glass.
                    shape.fill(Desvan.Palette.paper.opacity(0.10 * (1 - lit)))
                    // Hot glass: white-hot around the filament, amber towards the rim.
                    shape.fill(RadialGradient(
                        stops: [
                            .init(color: Color(hex: 0xFFF6DE), location: 0),
                            .init(color: Color(hex: 0xFFD27A), location: 0.3),
                            .init(color: Desvan.Palette.bulb, location: 0.62),
                            .init(color: Color(hex: 0xC7761A), location: 1),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 0,
                        endRadius: glass * 0.62
                    ))
                    .opacity(lit)
                    shape.stroke(Desvan.Palette.paper.opacity(0.55 - 0.35 * lit), lineWidth: 0.9)
                    // Filament on its two support wires.
                    Filament()
                        .stroke(
                            lit > 0.35 ? Color(hex: 0xFFFBEF) : Desvan.Palette.paper.opacity(0.55),
                            style: StrokeStyle(lineWidth: max(0.8, glass * 0.06), lineCap: .round, lineJoin: .round)
                        )
                        .shadow(color: Color(hex: 0xFFE3A3).opacity(lit), radius: glass * 0.12)
                    // Specular highlight on the glass.
                    Ellipse()
                        .fill(Color.white.opacity(0.45 - 0.2 * lit))
                        .frame(width: glass * 0.16, height: glass * 0.26)
                        .rotationEffect(.degrees(28))
                        .offset(x: -glass * 0.2, y: -glass * 0.2)
                }
                .frame(width: glass, height: glass * 1.08)
                .shadow(color: Desvan.Palette.bulb.opacity(0.9 * lit), radius: size * 0.35)
                // Brass screw base.
                VStack(spacing: 0.6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color(hex: 0xE9CD92), Color(hex: 0x9C7A43), Color(hex: 0x5E4522)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: neck * (index == 2 ? 0.7 : 1), height: max(1.2, size * 0.075))
                    }
                }
            }
            .frame(width: size, alignment: .top)
        }
        .frame(width: size, height: size * 1.25, alignment: .top)
        .accessibilityHidden(true)
    }

    /// A pear-shaped bulb: a round globe narrowing into the neck.
    private struct BulbGlass: Shape {
        func path(in rect: CGRect) -> Path {
            let r = rect.width / 2
            let globe = Path(ellipseIn: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.width))
            var neck = Path()
            neck.move(to: CGPoint(x: rect.midX - r * 0.86, y: rect.minY + r * 1.4))
            neck.addQuadCurve(to: CGPoint(x: rect.midX - r * 0.5, y: rect.maxY),
                              control: CGPoint(x: rect.midX - r * 0.52, y: rect.minY + r * 1.75))
            neck.addLine(to: CGPoint(x: rect.midX + r * 0.5, y: rect.maxY))
            neck.addQuadCurve(to: CGPoint(x: rect.midX + r * 0.86, y: rect.minY + r * 1.4),
                              control: CGPoint(x: rect.midX + r * 0.52, y: rect.minY + r * 1.75))
            neck.closeSubpath()
            return globe.union(neck)
        }
    }

    /// Two support wires and a small zigzag coil between them.
    private struct Filament: Shape {
        func path(in rect: CGRect) -> Path {
            let w = rect.width, h = rect.height
            var path = Path()
            let left = CGPoint(x: rect.minX + w * 0.34, y: rect.minY + h * 0.42)
            let right = CGPoint(x: rect.minX + w * 0.66, y: rect.minY + h * 0.42)
            path.move(to: CGPoint(x: rect.minX + w * 0.42, y: rect.maxY))
            path.addLine(to: left)
            let steps = 5
            for step in 1...steps {
                let t = CGFloat(step) / CGFloat(steps)
                let x = left.x + (right.x - left.x) * t
                let y = left.y + (step % 2 == 1 ? -h * 0.08 : 0)
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: rect.minX + w * 0.58, y: rect.maxY))
            return path
        }
    }
}

// MARK: - Rubber stamp

/// "Done": a sage rubber stamp in SF Pro Rounded italic, tilted −8°. It drops from 1.3× with a small shake when fresh,
/// and shrinks to a plain label after 4 s.
struct DesvanRubberStamp: View {
    var text: LocalizedStringKey = "Done"
    var isFresh: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        let big = isFresh
        Text(text)
            .font(Desvan.Typeface.display(big ? 13.5 : 11.5, weight: 700, italic: true))
            .foregroundStyle(Desvan.Palette.done)
            .padding(.horizontal, big ? 7 : 5)
            .padding(.vertical, big ? 1 : 0.5)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Desvan.Palette.done, lineWidth: big ? 1.6 : 1)
                    .overlay {
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(Desvan.Palette.done.opacity(big ? 0.5 : 0), lineWidth: 0.6)
                            .padding(2)
                    }
            }
            .opacity(0.94)
            .rotationEffect(.degrees(big ? -8 : -3))
            .keyframeAnimator(initialValue: StampPose(), trigger: landed) { content, pose in
                content
                    .scaleEffect(pose.scale)
                    .offset(x: pose.shake)
                    .opacity(pose.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    CubicKeyframe(1.3, duration: 0.001)
                    CubicKeyframe(1.0, duration: 0.18)
                }
                KeyframeTrack(\.opacity) {
                    LinearKeyframe(0, duration: 0.001)
                    LinearKeyframe(1, duration: 0.08)
                }
                KeyframeTrack(\.shake) {
                    CubicKeyframe(0, duration: 0.18)
                    CubicKeyframe(1.2, duration: 0.04)
                    CubicKeyframe(-1, duration: 0.05)
                    CubicKeyframe(0.5, duration: 0.05)
                    CubicKeyframe(0, duration: 0.06)
                }
            }
            .onAppear { if big && !reduceMotion { landed = true } }
            .accessibilityLabel(text)
    }

    private struct StampPose {
        var scale = 1.0
        var shake = 0.0
        var opacity = 1.0
    }
}

// MARK: - Buttons

/// Capsule buttons for Desván. `.primary` is filled with the bulb and dark ink; `.ghost` is an outline;
/// `.quiet` has no background until hovered. Presses scale to 0.97 on press, not on release.
struct DesvanButtonStyle: ButtonStyle {
    enum Kind { case primary, ghost, quiet }
    var kind: Kind
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        DesvanButtonBody(configuration: configuration, kind: kind, height: height)
    }
}

private struct DesvanButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: DesvanButtonStyle.Kind
    let height: CGFloat
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 13)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background { background }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Desvan.Motion.pick(.spring(duration: 0.2, bounce: 0), reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Desvan.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: Desvan.Palette.bulbInk
        case .ghost: Desvan.Palette.paper.opacity(isHovering ? 1 : 0.85)
        case .quiet: isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch kind {
        case .primary:
            Capsule()
                .fill(Desvan.Palette.bulb.opacity(isHovering ? 1 : 0.94))
                .overlay {
                    Capsule().fill(LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ))
                }
                .overlay { Capsule().strokeBorder(Color(hex: 0xFFE2A8).opacity(0.6), lineWidth: 0.5) }
                .grain(0.08, in: Capsule())
                .shadow(color: Desvan.Palette.bulb.opacity(isHovering ? 0.55 : 0.35), radius: 9, y: 1)
        case .ghost:
            Capsule()
                .fill(Desvan.Palette.paper.opacity(isHovering ? 0.08 : 0.02))
                .overlay { Capsule().strokeBorder(Desvan.Palette.paper.opacity(0.24), lineWidth: 1) }
        case .quiet:
            Capsule().fill(Desvan.Palette.paper.opacity(isHovering ? 0.08 : 0))
        }
    }
}
