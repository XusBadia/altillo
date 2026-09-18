import AppKit

/// Borderless, transparent, non-activating panel that sits above the menu bar over the notch.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = .mainMenu + 3
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        ignoresMouseEvents = true
    }

    // Never steal focus from the app the user is working in.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Root view of the panel. Only the visible notch shape is hit-testable; the rest of the panel is empty space.
final class NotchHostView: NSView {
    var visibleShapeSize: () -> CGSize = { .zero }

    /// The drawn shape is centred horizontally and glued to the top edge.
    var visibleShapeRect: NSRect {
        let size = visibleShapeSize()
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height, width: size.width, height: size.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return visibleShapeRect.contains(local) ? super.hitTest(point) : nil
    }
}
