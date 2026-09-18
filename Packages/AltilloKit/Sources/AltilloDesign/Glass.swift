import SwiftUI

// Liquid Glass is reserved for controls (PLAN §3). The silhouette is never glass on a hardware notch.
// With Reduce Transparency every glass surface falls back to an opaque warm capsule.

/// Glass capsule behind a control, with a very subtle grain. Falls back to an opaque capsule with Reduce Transparency.
public struct GlassCapsuleBackground: ViewModifier {
    public var tint: Color?
    public var interactive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(tint: Color? = nil, interactive: Bool = true) {
        self.tint = tint
        self.interactive = interactive
    }

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Capsule().fill(tint ?? Tokens.Palette.elevated))
                .overlay(Capsule().strokeBorder(Tokens.Palette.hairlineStrong, lineWidth: 0.5))
        } else {
            // On the pure-black notch, untinted glass has nothing to refract: a faint warm base keeps it legible.
            content
                .background { GrainOverlay(opacity: 0.05).clipShape(Capsule()) }
                .background { Capsule().fill(Tokens.Palette.text.opacity(tint == nil ? 0.07 : 0)) }
                .glassEffect(glass, in: .capsule)
        }
    }

    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        return glass.interactive(interactive)
    }
}

extension View {
    /// Wraps the view in a Liquid Glass capsule (or an opaque one with Reduce Transparency).
    public func glassCapsule(tint: Color? = nil, interactive: Bool = true) -> some View {
        modifier(GlassCapsuleBackground(tint: tint, interactive: interactive))
    }
}

/// A small static glass pill: an icon and/or a label. Use for status and filters, not for primary actions.
public struct GlassChip: View {
    public var title: String?
    public var systemImage: String?
    public var tint: Color?

    public init(_ title: String? = nil, systemImage: String? = nil, tint: Color? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: Tokens.Space.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            if let title {
                Text(title)
                    .font(Tokens.Typography.label)
            }
        }
        .foregroundStyle(Tokens.Palette.text)
        .padding(.horizontal, title == nil ? 7 : 10)
        .frame(height: 24)
        .glassCapsule(tint: tint, interactive: false)
    }
}

/// Capsule glass button. `.prominent` is tinted with the accent (primary action), `.regular` is neutral glass,
/// `.plain` has no background until hovered (tertiary actions like "Vaciar").
public struct GlassButtonStyle: ButtonStyle {
    public enum Prominence: Sendable { case plain, regular, prominent }

    public var prominence: Prominence
    public var height: CGFloat

    public init(_ prominence: Prominence = .regular, height: CGFloat = 26) {
        self.prominence = prominence
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration, prominence: prominence, height: height)
    }
}

private struct GlassButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: GlassButtonStyle.Prominence
    let height: CGFloat

    @Environment(\.altilloAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        styledLabel
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(Tokens.Motion.snappy(reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(Tokens.Motion.hover, value: isHovering)
            .onHover { isHovering = $0 }
            .contentShape(Capsule())
    }

    @ViewBuilder
    private var styledLabel: some View {
        let label = configuration.label
            .font(Tokens.Typography.label)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: height)
        switch prominence {
        case .plain:
            label
                .foregroundStyle(isHovering ? Tokens.Palette.text : Tokens.Palette.textSecondary)
                .background(Capsule().fill(Tokens.Palette.text.opacity(isHovering ? 0.08 : 0)))
        case .regular:
            label
                .foregroundStyle(Tokens.Palette.text)
                .glassCapsule()
        case .prominent:
            // Solid accent with a glassy top lip. (Tinted Liquid Glass renders desaturated in a panel that never
            // becomes key, which made the primary action look disabled.)
            label
                .foregroundStyle(Tokens.Palette.surface)
                .fontWeight(.semibold)
                .background {
                    Capsule()
                        .fill(accent.opacity(isHovering ? 1 : 0.92))
                        .overlay {
                            Capsule().fill(LinearGradient(
                                colors: [.white.opacity(0.32), .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .center
                            ))
                        }
                        .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5) }
                        .grain(0.06, in: Capsule())
                }
                .shadow(color: accent.opacity(isHovering ? 0.45 : 0.25), radius: 8, y: 1)
        }
    }
}

extension ButtonStyle where Self == GlassButtonStyle {
    public static var altilloGlass: GlassButtonStyle { GlassButtonStyle(.regular) }
    public static var altilloProminent: GlassButtonStyle { GlassButtonStyle(.prominent) }
    public static var altilloPlain: GlassButtonStyle { GlassButtonStyle(.plain) }
}

// MARK: - Cards

/// Warm surface card: `#1C1917` fill, hairline outline, a light top lip and a whisper of grain.
public struct CardBackground: ViewModifier {
    public var radius: CGFloat
    public var fill: Color

    public init(radius: CGFloat = Tokens.Radius.base, fill: Color = Tokens.Palette.surface) {
        self.radius = radius
        self.fill = fill
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .grain(0.05, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Tokens.Palette.highlight, Tokens.Palette.hairline, Tokens.Palette.hairline.opacity(0.5)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.5
                        )
                    }
            }
    }
}

extension View {
    /// Places the view on a warm surface card.
    public func altilloCard(radius: CGFloat = Tokens.Radius.base, fill: Color = Tokens.Palette.surface) -> some View {
        modifier(CardBackground(radius: radius, fill: fill))
    }
}

#Preview("Glass controls") {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            GlassChip("Altillo", systemImage: "tray")
            GlassChip(systemImage: "sparkle")
            GlassChip("3", systemImage: "circle.fill", tint: Tokens.Palette.amber.opacity(0.4))
        }
        HStack(spacing: 8) {
            Button("Permitir") {}.buttonStyle(.altilloProminent)
            Button("Denegar") {}.buttonStyle(.altilloGlass)
            Button("Vaciar") {}.buttonStyle(.altilloPlain)
        }
        Text("Tarjeta")
            .foregroundStyle(Tokens.Palette.text)
            .frame(width: 220, height: 80)
            .altilloCard()
    }
    .padding(32)
    .background(.black)
}
