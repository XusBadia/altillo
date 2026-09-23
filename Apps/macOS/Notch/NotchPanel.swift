import AppKit

/// Borderless, transparent, non-activating panel that sits above the menu bar over the notch.
final class NotchPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        Self.configure(self)
        acceptsMouseMovedEvents = true
        // Tab walks the open notch's controls in reading order, even as sections come and go.
        autorecalculatesKeyViewLoop = true
        // VoiceOver names the window after the app; it's never shown on screen.
        title = "Altillo"
    }

    /// What every notch panel shares, the live one and the resting ones in "All of them": above the menu bar on
    /// every space (full-screen ones included), never in ⌘` or Mission Control, and click-through until it matters.
    static func configure(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .mainMenu + 3
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.ignoresMouseEvents = true
    }

    /// Called for ⌘W / ⌘Q and Esc while the notch has keyboard focus.
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

    /// Esc that no control inside used (a focused button, the tab strip…) closes the notch, like any panel.
    override func cancelOperation(_ sender: Any?) {
        onCloseRequest()
    }

    override func keyDown(with event: NSEvent) {
        // Reached only when nothing in the responder chain handled the key.
        if event.keyCode == 53 { // Esc
            onCloseRequest()
            return
        }
        super.keyDown(with: event)
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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // One named group for VoiceOver ("Altillo"), with the notch's controls inside it.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Altillo")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The drawn shape is centred horizontally and glued to the top edge.
    var visibleShapeRect: NSRect {
        let size = visibleShapeSize()
        return NSRect(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height, width: size.width, height: size.height)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return visibleShapeRect.contains(local) ? super.hitTest(point) : nil
    }

    /// VoiceOver's frame for the group follows the drawn notch, not the transparent panel around it.
    override func accessibilityFrame() -> NSRect {
        guard let window else { return super.accessibilityFrame() }
        return window.convertToScreen(convert(visibleShapeRect, to: nil))
    }
}
