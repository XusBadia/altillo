import AppKit
import ApplicationServices

/// Clicks a status item the way a person does, so its app opens its own menu or panel under the icon. Many
/// apps ignore Accessibility's press (or open a window instead); a real click is what they're written for.
@MainActor
enum MenuBarItemClicker {
    /// Whether `frame` (Accessibility coordinates) is drawn where a click can reach it: on a display's menu bar,
    /// and beside the camera housing rather than behind it.
    static func isClickable(_ frame: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0, let primary = NSScreen.screens.first else { return false }
        let top = primary.frame.maxY
        return NSScreen.screens.contains { screen in
            let bounds = DrawerGeometry.accessibilityFrame(screen.frame, primaryScreenHeight: top)
            guard bounds.contains(frame) else { return false }
            let sides = [screen.auxiliaryTopLeftArea, screen.auxiliaryTopRightArea].compactMap { $0 }
            guard !sides.isEmpty else { return true }
            return sides.contains { area in
                let visible = DrawerGeometry.accessibilityFrame(area, primaryScreenHeight: top)
                return frame.minX >= visible.minX - 1 && frame.maxX <= visible.maxX + 1
            }
        }
    }

    /// Posts a left click at the icon's centre and puts the pointer back where it was.
    @discardableResult
    static func click(_ frame: CGRect) async -> Bool {
        guard AXIsProcessTrusted(), isClickable(frame),
              let source = CGEventSource(stateID: .privateState) else { return false }
        for _ in 0..<10 where mouseIsDown {
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !mouseIsDown else { return false }
        let point = CGPoint(x: frame.midX, y: frame.midY)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: .left) else { return false }
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        let pointer = CGEvent(source: nil)?.location
        // Altillo's own panels above the menu bar must let this click through to the icon. That includes the open
        // notch, which steps down to the status bar's level while an app's panel opens from the Drawer.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let overlays = NSApplication.shared.windows.filter { window in
            window.level.rawValue >= NSWindow.Level.statusBar.rawValue && !window.ignoresMouseEvents
                && DrawerGeometry.accessibilityFrame(window.frame, primaryScreenHeight: primaryTop).contains(point)
        }
        overlays.forEach { $0.ignoresMouseEvents = true }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(50))
        up.post(tap: .cghidEventTap)
        if let pointer { CGWarpMouseCursorPosition(pointer) }
        try? await Task.sleep(for: .milliseconds(50))
        overlays.forEach { $0.ignoresMouseEvents = false }
        return true
    }

    private static var mouseIsDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }
}
