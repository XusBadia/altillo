import SwiftUI

/// The notch silhouette as living ink: the same slab as `NotchShape` (concave top fillets, convex bottom corners),
/// plus a **bulge** — a smooth belly of `bulgeDepth` points that swells below the bottom edge around `bulgeX`.
///
/// The bulge is what makes the notch feel liquid: it swallows drops ("el trago") and leans towards the pointer during
/// a drag (magnetism). With `bulgeDepth == 0` the path is exactly the notch shape, so over a hardware notch the
/// silhouette always settles back to the exact form. Everything is animatable.
struct FluidoNotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Horizontal centre of the bulge, as a fraction of the width (0…1).
    var bulgeX: CGFloat = 0.5
    /// How far the belly swells below the bottom edge, in points. May be negative (sucked in).
    var bulgeDepth: CGFloat = 0
    /// Width of the belly, in points.
    var bulgeWidth: CGFloat = 120

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>>> {
        get { AnimatablePair(AnimatablePair(topRadius, bottomRadius), AnimatablePair(bulgeDepth, AnimatablePair(bulgeX, bulgeWidth))) }
        set {
            topRadius = newValue.first.first
            bottomRadius = newValue.first.second
            bulgeDepth = newValue.second.first
            bulgeX = newValue.second.second.first
            bulgeWidth = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        guard w > 0, h > 0 else { return Path() }

        let top = max(0, min(topRadius, w / 4, h / 2))
        let bottom = max(0, min(bottomRadius, (w - 2 * top) / 2, h - top))
        let k: CGFloat = 0.5523
        let x0 = rect.minX, y0 = rect.minY

        var path = Path()
        path.move(to: CGPoint(x: x0, y: y0))
        path.addCurve(
            to: CGPoint(x: x0 + top, y: y0 + top),
            control1: CGPoint(x: x0 + top * k, y: y0),
            control2: CGPoint(x: x0 + top, y: y0 + top * (1 - k))
        )
        path.addLine(to: CGPoint(x: x0 + top, y: y0 + h - bottom))
        path.addCurve(
            to: CGPoint(x: x0 + top + bottom, y: y0 + h),
            control1: CGPoint(x: x0 + top, y: y0 + h - bottom * (1 - k)),
            control2: CGPoint(x: x0 + top + bottom * (1 - k), y: y0 + h)
        )

        // Bottom edge, with the belly.
        let left = x0 + top + bottom
        let right = x0 + w - top - bottom
        let halfWidth = min(bulgeWidth / 2, (right - left) / 2)
        if abs(bulgeDepth) > 0.01, halfWidth > 4 {
            let cx = min(max(x0 + w * bulgeX, left + halfWidth), right - halfWidth)
            let by = y0 + h
            path.addLine(to: CGPoint(x: cx - halfWidth, y: by))
            // Two cubic halves: a bell that leaves the edge tangentially and is flat at its lowest point.
            path.addCurve(
                to: CGPoint(x: cx, y: by + bulgeDepth),
                control1: CGPoint(x: cx - halfWidth * 0.52, y: by),
                control2: CGPoint(x: cx - halfWidth * 0.48, y: by + bulgeDepth)
            )
            path.addCurve(
                to: CGPoint(x: cx + halfWidth, y: by),
                control1: CGPoint(x: cx + halfWidth * 0.48, y: by + bulgeDepth),
                control2: CGPoint(x: cx + halfWidth * 0.52, y: by)
            )
        }
        path.addLine(to: CGPoint(x: x0 + w - top - bottom, y: y0 + h))

        path.addCurve(
            to: CGPoint(x: x0 + w - top, y: y0 + h - bottom),
            control1: CGPoint(x: x0 + w - top - bottom * (1 - k), y: y0 + h),
            control2: CGPoint(x: x0 + w - top, y: y0 + h - bottom * (1 - k))
        )
        path.addLine(to: CGPoint(x: x0 + w - top, y: y0 + top))
        path.addCurve(
            to: CGPoint(x: x0 + w, y: y0),
            control1: CGPoint(x: x0 + w - top, y: y0 + top * (1 - k)),
            control2: CGPoint(x: x0 + w - top * k, y: y0)
        )
        path.closeSubpath()
        return path
    }
}
