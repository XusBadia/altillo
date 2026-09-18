import SwiftUI

/// The notch silhouette: a slab hanging from the top edge of the screen, with concave top corners that flare into the
/// menu bar (like the hardware notch's fillets) and convex bottom corners.
///
/// Both radii are animatable, so the shape morphs smoothly between states (idle → peek → open).
/// The body of the notch is inset by `topCornerRadius` on each side: a shape drawn over a hardware notch of width `w`
/// must be `w + 2 × topCornerRadius` wide.
///
/// Approach inspired by DynamicNotchKit (MIT, © MrKai77); written from scratch.
public struct NotchShape: Shape {
    public var topCornerRadius: CGFloat
    public var bottomCornerRadius: CGFloat

    public init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        guard w > 0, h > 0 else { return Path() }

        let top = max(0, min(topCornerRadius, w / 4, h / 2))
        let bottom = max(0, min(bottomCornerRadius, (w - 2 * top) / 2, h - top))
        // Circle approximation with cubic Béziers (k = 0.5523).
        let k: CGFloat = 0.5523

        var path = Path()
        let x0 = rect.minX, y0 = rect.minY
        path.move(to: CGPoint(x: x0, y: y0))

        // Top-left concave fillet.
        path.addCurve(
            to: CGPoint(x: x0 + top, y: y0 + top),
            control1: CGPoint(x: x0 + top * k, y: y0),
            control2: CGPoint(x: x0 + top, y: y0 + top * (1 - k))
        )
        path.addLine(to: CGPoint(x: x0 + top, y: y0 + h - bottom))

        // Bottom-left convex corner.
        path.addCurve(
            to: CGPoint(x: x0 + top + bottom, y: y0 + h),
            control1: CGPoint(x: x0 + top, y: y0 + h - bottom * (1 - k)),
            control2: CGPoint(x: x0 + top + bottom * (1 - k), y: y0 + h)
        )
        path.addLine(to: CGPoint(x: x0 + w - top - bottom, y: y0 + h))

        // Bottom-right convex corner.
        path.addCurve(
            to: CGPoint(x: x0 + w - top, y: y0 + h - bottom),
            control1: CGPoint(x: x0 + w - top - bottom * (1 - k), y: y0 + h),
            control2: CGPoint(x: x0 + w - top, y: y0 + h - bottom * (1 - k))
        )
        path.addLine(to: CGPoint(x: x0 + w - top, y: y0 + top))

        // Top-right concave fillet.
        path.addCurve(
            to: CGPoint(x: x0 + w, y: y0),
            control1: CGPoint(x: x0 + w - top, y: y0 + top * (1 - k)),
            control2: CGPoint(x: x0 + w - top * k, y: y0)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("NotchShape") {
    VStack(spacing: 24) {
        NotchShape(topCornerRadius: 6, bottomCornerRadius: 10)
            .fill(.black)
            .frame(width: 197, height: 32)
        NotchShape(topCornerRadius: 8, bottomCornerRadius: 18)
            .fill(.black)
            .frame(width: 380, height: 66)
        NotchShape(topCornerRadius: 14, bottomCornerRadius: 26)
            .fill(.black)
            .frame(width: 640, height: 240)
    }
    .frame(width: 720, height: 420, alignment: .top)
    .background(LinearGradient(colors: [Color(hex: 0xC9D6E8), Color(hex: 0x8FA7C7)], startPoint: .top, endPoint: .bottom))
}
