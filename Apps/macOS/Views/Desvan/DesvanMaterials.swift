import AltilloDesign
import SwiftUI

// Materials of the attic: the bulb's light, wood cards with paper grain, the plank, luggage tags, the house mark,
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

/// A dark wood card with paper grain, a marked top lip and a soft inner shadow at the bottom.
struct DesvanCard: ViewModifier {
    var radius: CGFloat = 14
    var fill: Color = Desvan.Palette.wood
    var glow: Color? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .overlay {
                        // Inner shadow: the card is a little tray, darker towards its bottom edge.
                        shape.fill(LinearGradient(
                            colors: [.clear, .black.opacity(0.22)],
                            startPoint: UnitPoint(x: 0.5, y: 0.55),
                            endPoint: .bottom
                        ))
                    }
                    .grain(0.045, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Desvan.Palette.lip, Desvan.Palette.hairline, Desvan.Palette.hairline.opacity(0.4)],
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
    func desvanCard(radius: CGFloat = 14, fill: Color = Desvan.Palette.wood, glow: Color? = nil) -> some View {
        modifier(DesvanCard(radius: radius, fill: fill, glow: glow))
    }
}

// MARK: - Plank

/// The shelf's plank: a 3 pt board with a 1 px paper lip on top and a soft shadow underneath.
struct DesvanPlank: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Shadow cast on the wall below.
            LinearGradient(colors: [.black.opacity(0.45), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 8)
                .offset(y: 4)
            // The front edge of the board.
            Rectangle()
                .fill(LinearGradient(
                    colors: [Desvan.Palette.plank, Color(hex: 0x2C241C)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .frame(height: 4)
                .overlay(alignment: .top) {
                    Rectangle().fill(Desvan.Palette.paper.opacity(0.14)).frame(height: 1)
                }
        }
        .frame(height: 4, alignment: .top)
        .accessibilityHidden(true)
    }
}

// MARK: - Luggage tag

/// A hanging kraft tag: a pentagon pointing up (like the house mark) with rounded corners and a punched hole.
struct DesvanTagShape: Shape {
    /// Height of the pointed top.
    var peak: CGFloat = 6
    var radius: CGFloat = 3

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY + peak),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.minY + peak),
        ]
        return Path.rounded(points, radius: radius)
    }
}

/// A small tag pointing left (the right ear's shelf counter).
struct DesvanSideTagShape: Shape {
    var peak: CGFloat = 5
    var radius: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        let points = [
            CGPoint(x: rect.minX, y: rect.midY),
            CGPoint(x: rect.minX + peak, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX + peak, y: rect.maxY),
        ]
        return Path.rounded(points, radius: radius)
    }
}

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

/// The hanging tag with the item's name written on it and a cord up to the plank.
struct DesvanLuggageTag: View {
    let title: String
    let edge: Color
    var isSelected = false
    var width: CGFloat = 88
    var cord: CGFloat = 9

    var body: some View {
        let shape = DesvanTagShape()
        VStack(spacing: 0) {
            Rectangle()
                .fill(Desvan.Palette.paper.opacity(0.4))
                .frame(width: 0.75, height: cord + 5)
                .padding(.bottom, -5)
                .zIndex(1)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.ink)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .padding(.top, 8)
                .padding(.bottom, 3.5)
                .frame(width: width)
                .background {
                    shape.fill(isSelected ? Desvan.Palette.bulb : Desvan.Palette.kraft)
                        .overlay {
                            // Kraft fibre: a darker bottom and a touch of grain.
                            shape.fill(LinearGradient(
                                colors: [.white.opacity(0.10), .black.opacity(0.08)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                        }
                        .grain(0.12, in: shape)
                        .overlay {
                            shape.inset(by: 0.75).stroke(edge, lineWidth: 1.5)
                                .opacity(isSelected ? 0 : 1)
                        }
                        .overlay(alignment: .top) {
                            // The punched hole, with a reinforcement ring in the item's colour.
                            Circle()
                                .fill(Color.black.opacity(0.85))
                                .frame(width: 3.5, height: 3.5)
                                .background(Circle().fill(edge.opacity(isSelected ? 0 : 0.9)).frame(width: 6.5, height: 6.5))
                                .offset(y: 3)
                        }
                        .shadow(color: isSelected ? Desvan.Palette.bulb.opacity(0.45) : .black.opacity(0.4),
                                radius: isSelected ? 7 : 1.5, y: isSelected ? 0 : 1)
                }
        }
    }
}

extension DesvanTagShape {
    func inset(by amount: CGFloat) -> some Shape {
        InsetTag(base: self, amount: amount)
    }
}

private struct InsetTag: Shape {
    let base: DesvanTagShape
    let amount: CGFloat
    func path(in rect: CGRect) -> Path { base.path(in: rect.insetBy(dx: amount, dy: amount)) }
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

/// A hand-drawn light bulb whose glass fills with light (`lit` 0…1).
struct DesvanBulbGlyph: View {
    var size: CGFloat = 14
    var lit: Double = 1

    var body: some View {
        let glass = size * 0.72
        VStack(spacing: size * 0.02) {
            ZStack {
                Circle()
                    .fill(Desvan.Palette.bulb.opacity(0.15 + 0.85 * lit))
                Circle()
                    .strokeBorder(Desvan.Palette.paper.opacity(0.55 + 0.45 * (1 - lit)), lineWidth: 1)
                    .opacity(1 - lit * 0.6)
                // The filament.
                Path { path in
                    path.move(to: CGPoint(x: glass * 0.36, y: glass * 0.62))
                    path.addQuadCurve(to: CGPoint(x: glass * 0.64, y: glass * 0.62),
                                      control: CGPoint(x: glass * 0.5, y: glass * 0.3))
                }
                .stroke(Desvan.Palette.bulbInk.opacity(0.55), lineWidth: 0.9)
            }
            .frame(width: glass, height: glass)
            .shadow(color: Desvan.Palette.bulb.opacity(0.8 * lit), radius: size * 0.45)
            // Screw base.
            VStack(spacing: size * 0.04) {
                Capsule().frame(width: size * 0.36, height: size * 0.07)
                Capsule().frame(width: size * 0.3, height: size * 0.07)
            }
            .foregroundStyle(Desvan.Palette.paper.opacity(0.7))
        }
        .frame(width: size, height: size * 1.12)
        .accessibilityHidden(true)
    }
}

// MARK: - Rubber stamp

/// "Hecho": a sage rubber stamp in Fraunces italic, tilted −8°. It drops from 1.3× with a small shake when fresh,
/// and shrinks to a plain label after 4 s.
struct DesvanRubberStamp: View {
    var text = "Hecho"
    var isFresh: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    var body: some View {
        let big = isFresh
        Text(text)
            .font(Desvan.Typeface.fraunces(big ? 15 : 12, weight: 700, italic: true))
            .foregroundStyle(Desvan.Palette.done)
            .padding(.horizontal, big ? 8 : 6)
            .padding(.vertical, big ? 1.5 : 1)
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
