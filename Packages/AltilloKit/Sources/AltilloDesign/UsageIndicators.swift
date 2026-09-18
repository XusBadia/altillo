import SwiftUI

/// Circular usage gauge. The arc starts at 12 o'clock and fills clockwise.
/// Tint defaults to the `UsageLevel` colour, so it turns orange at 80 % and red at 95 %.
public struct UsageRing<Label: View>: View {
    public var value: Double
    public var lineWidth: CGFloat
    public var tint: Color?
    /// Optional pace marker (fraction of the window elapsed), drawn as a small tick across the ring.
    public var pace: Double?
    private let label: Label

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        value: Double,
        lineWidth: CGFloat = 3,
        tint: Color? = nil,
        pace: Double? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.value = value
        self.lineWidth = lineWidth
        self.tint = tint
        self.pace = pace
        self.label = label()
    }

    private var clamped: Double { min(max(value, 0), 1) }
    private var resolvedTint: Color { tint ?? UsageLevel(fraction: clamped).tint }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.Palette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(clamped, 0.001))
                .stroke(resolvedTint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let pace {
                GeometryReader { proxy in
                    let radius = min(proxy.size.width, proxy.size.height) / 2
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Tokens.Palette.text)
                        .frame(width: 1.5, height: lineWidth + 1)
                        .shadow(color: .black.opacity(0.7), radius: 0.75)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(360 * min(max(pace, 0), 1)))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            }
            label
        }
        .padding(lineWidth / 2)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

extension UsageRing where Label == EmptyView {
    public init(value: Double, lineWidth: CGFloat = 3, tint: Color? = nil, pace: Double? = nil) {
        self.init(value: value, lineWidth: lineWidth, tint: tint, pace: pace) { EmptyView() }
    }
}

/// Linear usage gauge with an optional pace marker: a tick at the fraction you'd expect to have used by now
/// if you spread the window evenly. Fill past the tick means you're burning faster than the window allows.
public struct UsageBar: View {
    public var value: Double
    public var pace: Double?
    public var tint: Color?
    public var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(value: Double, pace: Double? = nil, tint: Color? = nil, height: CGFloat = 5) {
        self.value = value
        self.pace = pace
        self.tint = tint
        self.height = height
    }

    private var clamped: Double { min(max(value, 0), 1) }

    public var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Palette.track)
                Capsule()
                    .fill(tint ?? UsageLevel(fraction: clamped).tint)
                    .frame(width: max(height, width * clamped))
                    .opacity(clamped > 0 ? 1 : 0)
                if let pace {
                    let x = width * min(max(pace, 0), 1)
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Tokens.Palette.text)
                        .frame(width: 2, height: height + 6)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .offset(x: min(max(x - 1, 0), width - 2))
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: height)
        .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }
}

/// A small dot that emits a slow ripple while something is working. Static with Reduce Motion.
///
/// The ripple is a self-contained repeating keyframe animation, so it can never leak into surrounding transitions
/// (a `withAnimation(.repeatForever)` in `onAppear` would make the parent's insertion transition loop too).
public struct PulseDot: View {
    public var color: Color
    public var size: CGFloat
    public var isPulsing: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color = Tokens.Palette.amber, size: CGFloat = 6, isPulsing: Bool = true) {
        self.color = color
        self.size = size
        self.isPulsing = isPulsing
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .background {
                if isPulsing && !reduceMotion {
                    KeyframeAnimator(initialValue: 0.0, repeating: true) { progress in
                        Circle()
                            .fill(color)
                            .scaleEffect(1 + progress * 1.8)
                            .opacity(0.55 * (1 - progress))
                    } keyframes: { _ in
                        CubicKeyframe(1.0, duration: 1.6)
                        CubicKeyframe(1.0, duration: 0.5)
                    }
                }
            }
            .shadow(color: color.opacity(0.6), radius: size * 0.6)
            .accessibilityHidden(true)
    }
}

#Preview("Usage indicators") {
    VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 16) {
            UsageRing(value: 0.42).frame(width: 18, height: 18)
            UsageRing(value: 0.85).frame(width: 18, height: 18)
            UsageRing(value: 0.97).frame(width: 18, height: 18)
            UsageRing(value: 0.62, lineWidth: 5, pace: 0.5) {
                Text("62").font(Tokens.Typography.figure(14)).foregroundStyle(Tokens.Palette.text)
            }
            .frame(width: 54, height: 54)
        }
        UsageBar(value: 0.62, pace: 0.48).frame(width: 240)
        UsageBar(value: 0.86, pace: 0.9).frame(width: 240)
        UsageBar(value: 0.97).frame(width: 240)
        HStack(spacing: 16) {
            PulseDot()
            PulseDot(color: Tokens.Palette.warning)
            PulseDot(color: Tokens.Palette.success, isPulsing: false)
        }
    }
    .padding(32)
    .background(.black)
}
