import AltilloDesign
import SwiftUI

// MARK: - Rim light (the signature)

/// How the notch's edge is lit right now.
struct RimStyle: Equatable {
    var light: Fluido.Light
    /// 0…1.
    var intensity: Double
    /// The gradient turns around the silhouette (one turn every 3 s) while an event is happening.
    var rotates = false
    /// Opacity breathes 0.35 ↔ 0.9 over 2.4 s (an agent waiting for you).
    var breathes = false
    /// How much light escapes outside the silhouette onto the desktop (0…1).
    var halo: Double = 0
    /// Points from the top edge where the light fades in, so it never draws a line along the menu bar.
    var fadeTop: CGFloat = 10
}

/// Draws a shape inset inside a larger canvas, so glows, bulges and halos have room to spill without clipping.
struct CanvasInset<S: Shape>: Shape {
    var base: S
    var pad: CGFloat

    var animatableData: S.AnimatableData {
        get { base.animatableData }
        set { base.animatableData = newValue }
    }

    func path(in rect: CGRect) -> Path {
        base.path(in: CGRect(x: rect.minX + pad, y: rect.minY, width: rect.width - 2 * pad, height: rect.height - pad))
    }
}

/// The rim light: a 1.5 pt stroke with an angular gradient of the module's light, clipped inside the silhouette, plus a
/// copy blurred 6 pt in `.plusLighter`. The gradient only turns (and breathes) while there is an event; at rest it is a
/// still image, so it costs nothing. With Reduce Motion the light is fixed.
struct RimLight<S: Shape>: View {
    var shape: S
    var size: CGSize
    var style: RimStyle
    /// Draw the inner rim (true) or the outer halo (false).
    var inner = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private static var pad: CGFloat { 40 }

    var body: some View {
        let animated = (style.rotates || style.breathes) && !reduceMotion
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1 / 60)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    layer(
                        angle: style.rotates ? (t / 3).truncatingRemainder(dividingBy: 1) * 360 : 200,
                        breath: style.breathes ? 0.625 + 0.275 * sin(t * 2 * .pi / 2.4) : 1
                    )
                }
            } else {
                layer(angle: 200, breath: style.breathes ? 0.8 : 1)
            }
        }
        .frame(width: size.width + 2 * Self.pad, height: size.height + Self.pad)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func layer(angle: Double, breath: Double) -> some View {
        let canvas = CanvasInset(base: shape, pad: Self.pad)
        let light = style.light
        // A bright head and a dim tail, so the turn reads as light travelling around the edge.
        let gradient = AngularGradient(
            stops: [
                .init(color: light.from, location: 0),
                .init(color: light.to, location: 0.28),
                .init(color: light.to.opacity(0.55), location: 0.5),
                .init(color: light.from.opacity(0.4), location: 0.72),
                .init(color: light.from, location: 1),
            ],
            center: .center,
            angle: .degrees(angle)
        )
        let intensity = style.intensity * breath
        if inner {
            ZStack {
                canvas.stroke(gradient, lineWidth: 3)
                if !reduceTransparency {
                    canvas.stroke(gradient, lineWidth: 10)
                        .blur(radius: 6)
                        .blendMode(.plusLighter)
                    // A wider, dimmer bloom: the light soaking into the ink.
                    canvas.stroke(gradient, lineWidth: 26)
                        .blur(radius: 14)
                        .blendMode(.plusLighter)
                        .opacity(0.45)
                }
            }
            .clipShape(canvas)
            .mask(fade)
            .opacity(intensity)
        } else if style.halo > 0, !reduceTransparency {
            canvas.stroke(gradient, lineWidth: 8)
                .blur(radius: 14)
                .mask(fade)
                .opacity(intensity * style.halo)
        }
    }

    /// Transparent along the top edge (the menu bar), fully lit below.
    private var fade: some View {
        let height = size.height + Self.pad
        let start = min(style.fadeTop / height, 0.9)
        let end = min((style.fadeTop + max(10, size.height * 0.35)) / height, 0.97)
        return LinearGradient(
            stops: [.init(color: .clear, location: 0), .init(color: .clear, location: start), .init(color: .white, location: end)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Glass

/// Liquid Glass for controls on the ink. On pure black the glass has nothing to refract, so it always sits on a 7 %
/// white base, and the module's light is painted by us (a gradient wash plus a lit edge) instead of `Glass.tint`: the
/// notch panel is rarely key, and tinted glass in an inactive window renders grey. Opaque with Reduce Transparency.
struct FluidoGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    var light: Fluido.Light?
    /// 0…1: how strongly the light washes the glass.
    var tint: Double = 1
    var interactive = true
    /// `.clear` glass for large surfaces (drop zones): regular glass on black reads as flat grey.
    var clear = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background {
                    shape.fill(Fluido.Palette.ink2)
                        .overlay { if let light { shape.fill(light.linear(.topLeading, .bottomTrailing)).opacity(0.35 * tint) } }
                }
                .overlay { shape.strokeBorder(light?.from.opacity(0.9 * tint) ?? Fluido.Palette.hairlineStrong, lineWidth: 1) }
        } else {
            content
                .background {
                    ZStack {
                        if clear {
                            // Dark glass: ink over the glass, so large surfaces stay ink and only the edges catch light.
                            shape.fill(Fluido.Palette.ink1.opacity(0.82))
                        } else {
                            shape.fill(Color.white.opacity(0.07))
                        }
                        if let light {
                            shape.fill(light.linear(.topLeading, .bottomTrailing)).opacity(0.3 * tint)
                        }
                    }
                }
                .overlay {
                    // Specular lip on top, the module's light on the lower edge.
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.34),
                                .white.opacity(0.05),
                                (light?.to ?? .white).opacity(light == nil ? 0.10 : 0.55 * tint),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
                }
                .glassEffect((clear ? Glass.clear : Glass.regular).interactive(interactive), in: shape)
        }
    }
}

extension View {
    func fluidoGlass<S: InsettableShape>(
        _ shape: S, light: Fluido.Light? = nil, tint: Double = 1, interactive: Bool = true, clear: Bool = false
    ) -> some View {
        modifier(FluidoGlass(shape: shape, light: light, tint: tint, interactive: interactive, clear: clear))
    }
}

/// Capsule button on glass. `light` makes it the primary action (washed in the module's light).
struct FluidoButtonStyle: ButtonStyle {
    var light: Fluido.Light?
    var height: CGFloat = 26

    func makeBody(configuration: Configuration) -> some View {
        FluidoButtonBody(configuration: configuration, light: light, height: height)
    }
}

private struct FluidoButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let light: Fluido.Light?
    let height: CGFloat

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold).width(light == nil ? .standard : .expanded))
            .foregroundStyle(light == nil ? Fluido.Palette.text : Color.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 13)
            .frame(height: height)
            .background {
                if let light {
                    // The primary action is the one place a light fills a (tiny) surface: a lit capsule.
                    Capsule()
                        .fill(light.linear(.topLeading, .bottomTrailing))
                        .brightness(isHovering ? 0.06 : 0)
                        .overlay {
                            Capsule().fill(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0)], startPoint: .top, endPoint: .center))
                        }
                        .overlay { Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.75) }
                }
            }
            .fluidoGlass(Capsule(), light: nil, tint: 0)
            .shadow(color: (light?.mid ?? .clear).opacity(isHovering ? 0.6 : 0.4), radius: 10, y: 1)
            // Press at 0.97 on press, not on release.
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(Fluido.Motion.snappy(reduceMotion), value: configuration.isPressed)
            .animation(Fluido.Motion.hover(reduceMotion), value: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(Capsule())
    }
}

// MARK: - Small pieces

/// A dot of light with a soft glow. Breathes while `breathes` (static with Reduce Motion).
struct LightDot: View {
    var light: Fluido.Light
    var size: CGFloat = 6
    var breathes = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if breathes && !reduceMotion {
                PhaseAnimator([0.45, 1.0]) { phase in
                    dot.opacity(phase)
                } animation: { _ in .easeInOut(duration: 1.2) }
            } else {
                dot
            }
        }
        .accessibilityHidden(true)
    }

    private var dot: some View {
        Circle()
            .fill(light.linear(.topLeading, .bottomTrailing))
            .frame(width: size, height: size)
            .shadow(color: light.mid.opacity(0.9), radius: size * 0.8)
    }
}

/// Ink wells: the only "surfaces" in Fluido. Near-black, a hairline with a faint top lip.
struct InkWell: ViewModifier {
    var radius: CGFloat = Fluido.Radius.card
    var fill: Color = Fluido.Palette.ink1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.11), .white.opacity(0.04), .white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.75
                        )
                    }
            }
    }
}

extension View {
    func inkWell(radius: CGFloat = Fluido.Radius.card, fill: Color = Fluido.Palette.ink1) -> some View {
        modifier(InkWell(radius: radius, fill: fill))
    }
}
