import CoreGraphics

/// Where the notch (or the virtual island on displays without one) sits on a screen.
///
/// All rects use AppKit screen coordinates: origin at the bottom-left of the main display, y grows upwards.
public struct NotchGeometry: Equatable, Sendable {
    /// Width of the virtual island drawn on displays without a hardware notch.
    public static let virtualIslandWidth: CGFloat = 196
    /// Fallback height when the screen reports no menu bar (e.g. auto-hidden menu bar).
    public static let fallbackMenuBarHeight: CGFloat = 24

    public let screenFrame: CGRect
    /// The hardware notch, or the virtual island when `hasNotch` is false.
    public let notchRect: CGRect
    public let hasNotch: Bool

    public init(screenFrame: CGRect, notchRect: CGRect, hasNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
    }

    /// Builds the geometry from the values `NSScreen` exposes.
    ///
    /// - Parameters:
    ///   - screenFrame: `NSScreen.frame`.
    ///   - visibleFrame: `NSScreen.visibleFrame`, used to infer the menu bar height on displays without a notch.
    ///   - safeAreaTop: `NSScreen.safeAreaInsets.top` (0 without a notch).
    ///   - auxiliaryTopLeft: `NSScreen.auxiliaryTopLeftArea` (nil without a notch).
    ///   - auxiliaryTopRight: `NSScreen.auxiliaryTopRightArea` (nil without a notch).
    public init(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryTopLeft: CGRect?,
        auxiliaryTopRight: CGRect?
    ) {
        self.screenFrame = screenFrame
        if safeAreaTop > 0, let left = auxiliaryTopLeft, let right = auxiliaryTopRight, right.minX > left.maxX {
            hasNotch = true
            notchRect = CGRect(
                x: left.maxX,
                y: screenFrame.maxY - safeAreaTop,
                width: right.minX - left.maxX,
                height: safeAreaTop
            )
        } else {
            hasNotch = false
            let menuBarHeight = screenFrame.maxY - visibleFrame.maxY
            let height = menuBarHeight > 0 ? menuBarHeight : Self.fallbackMenuBarHeight
            notchRect = CGRect(
                x: screenFrame.midX - Self.virtualIslandWidth / 2,
                y: screenFrame.maxY - height,
                width: Self.virtualIslandWidth,
                height: height
            )
        }
    }

    /// The fixed-size transparent panel that hosts every notch state, centred on the notch and hugging the top edge.
    /// The window never resizes; SwiftUI animates the content inside it.
    public func panelFrame(size: CGSize) -> CGRect {
        CGRect(
            x: (notchRect.midX - size.width / 2).rounded(),
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Area that counts as "hovering the notch": the notch itself, widened a little so it is easy to hit.
    public func hoverRect(horizontalSlop: CGFloat = 12, verticalSlop: CGFloat = 6) -> CGRect {
        notchRect.insetBy(dx: -horizontalSlop, dy: 0)
            .union(notchRect.offsetBy(dx: 0, dy: -verticalSlop))
    }

    /// Pointer hit-testing includes the boundary: AppKit can report the cursor exactly at the screen's
    /// top edge (`screenFrame.maxY`), which `CGRect.contains` excludes even though the notch touches it.
    public static func containsPointer(_ point: CGPoint, in rect: CGRect) -> Bool {
        guard !rect.isEmpty, !rect.isInfinite else { return false }
        return point.x >= rect.minX && point.x <= rect.maxX
            && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// Distance from a point to the notch, used to open the drop target as a drag approaches.
    public func distance(to point: CGPoint) -> CGFloat {
        let dx = max(notchRect.minX - point.x, 0, point.x - notchRect.maxX)
        let dy = max(notchRect.minY - point.y, 0, point.y - notchRect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
