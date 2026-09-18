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
        acceptsMouseMovedEvents = true
    }

    /// Called for ⌘W / ⌘Q while the notch has keyboard focus.
    var onCloseRequest: () -> Void = {}

    /// While the open notch is key, ⌘Q and ⌘W would reach Altillo instead of the app the user sees:
    /// they just close the notch.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased(), key == "q" || key == "w" {
            onCloseRequest()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Only true while the notch is open, so keyboard shortcuts (⌫, space, ⌘A, Esc) reach the shelf.
    /// Being a non-activating panel, becoming key never activates Altillo or hides the user's app.
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    /// Gives keyboard focus back to the app the user was working in.
    func relinquishKey() {
        guard isKeyWindow else { return }
        orderOut(nil)
        orderFrontRegardless()
    }
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
