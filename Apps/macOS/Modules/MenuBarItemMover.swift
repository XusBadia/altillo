import AppKit
import ApplicationServices

/// Sends the same Command-drag gesture as a manual menu-bar rearrangement.
/// The caller verifies the resulting AX layout; posting events alone is never success.
@MainActor
enum MenuBarItemMover {
    enum Result { case posted, unavailable, busy }

    /// Click the status item itself. Unlike AXShowMenu this preserves apps' distinct
    /// primary and secondary click handlers, including custom popovers.
    static func click(frame: CGRect, rightButton: Bool) async -> Result {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return .unavailable }
        let screens = NSScreen.screens.map {
            DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: primary.frame.maxY)
        }
        guard let point = clickPoint(frame: frame, screens: screens),
              let source = CGEventSource(stateID: .privateState) else { return .unavailable }
        for _ in 0..<10 {
            if !mouseIsDown { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !Task.isCancelled, !mouseIsDown else { return .busy }
        let button: CGMouseButton = rightButton ? .right : .left
        guard let down = CGEvent(mouseEventSource: source,
                                 mouseType: rightButton ? .rightMouseDown : .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: source,
                               mouseType: rightButton ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: button) else { return .unavailable }
        // A settings shortcut must never leak Command into the target's click.
        down.flags = []
        up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        let overlays = overlayMouseStates(at: [point], primaryTop: primary.frame.maxY)
        defer { overlays.forEach { $0.window.ignoresMouseEvents = $0.ignored } }
        overlays.forEach { $0.window.ignoresMouseEvents = true }
        down.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(50))
        // Release even when cancelled. Leave the pointer at the menu's native anchor
        // so restoring it cannot dismiss or select a menu item under the old pointer.
        overlays.forEach { $0.window.ignoresMouseEvents = true }
        up.post(tap: .cghidEventTap)
        return .posted
    }

    static func clickPoint(frame: CGRect, screens: [CGRect]) -> CGPoint? {
        guard frame.minX.isFinite, frame.minY.isFinite, frame.width.isFinite, frame.height.isFinite,
              frame.width > 0, frame.height > 0,
              screens.contains(where: { $0.contains(frame) }) else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    static func move(frame: CGRect, beside divider: CGRect, toLeft: Bool) async -> Result {
        guard AXIsProcessTrusted(), let primary = NSScreen.screens.first else { return .unavailable }
        let screens = NSScreen.screens.map {
            DrawerGeometry.accessibilityFrame($0.frame, primaryScreenHeight: primary.frame.maxY)
        }
        guard let points = dragPoints(item: frame, divider: divider, toLeft: toLeft, screens: screens),
              let source = CGEventSource(stateID: .hidSystemState) else { return .unavailable }
        source.localEventsSuppressionInterval = 0
        // A gesture's onEnded can arrive just before the real mouse-up reaches WindowServer.
        for _ in 0..<10 {
            if !mouseIsDown { break }
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard !Task.isCancelled, !mouseIsDown else { return .busy }
        guard let down = event(.leftMouseDown, at: points.start, source: source),
              let up = event(.leftMouseUp, at: points.end, source: source),
              let commandDown = commandEvent(keyDown: true, source: source),
              let commandUp = commandEvent(keyDown: false, source: source) else { return .unavailable }
        let cursor = CGEvent(source: nil)?.location
        let overlays = overlayMouseStates(at: [points.start, points.end], primaryTop: primary.frame.maxY)
        defer { overlays.forEach { $0.window.ignoresMouseEvents = $0.ignored } }
        overlays.forEach { $0.window.ignoresMouseEvents = true }
        // MenuBarAgent on macOS 27 checks the global modifier state rather than trusting
        // only the flags attached to mouse events. Post the real Command transition around
        // the gesture; every path below still releases it before returning.
        commandDown.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(50))
        down.post(tap: .cghidEventTap)
        // Always send mouse-up, including cancellation, so no synthetic button remains held.
        // Cross the drag threshold near the source before travelling to the destination.
        // One jump directly to the divider can be interpreted as a click by a status host
        // which has not entered its tracking loop yet.
        try? await Task.sleep(for: .milliseconds(100))
        var releasePoint = points.start
        for point in dragPath(from: points.start, to: points.end) {
            guard !Task.isCancelled else { break }
            overlays.forEach { $0.window.ignoresMouseEvents = true }
            event(.leftMouseDragged, at: point, source: source)?.post(tap: .cghidEventTap)
            releasePoint = point
            try? await Task.sleep(for: .milliseconds(25))
        }
        overlays.forEach { $0.window.ignoresMouseEvents = true }
        up.location = releasePoint
        up.post(tap: .cghidEventTap)
        commandUp.post(tap: .cghidEventTap)
        try? await Task.sleep(for: .milliseconds(100))
        if let cursor, let current = CGEvent(source: nil)?.location,
           hypot(current.x - releasePoint.x, current.y - releasePoint.y) < 3 {
            // Restore position without a second synthetic mouse event. A mouseMoved
            // at the user's original hot corner can open Mission Control, hiding the
            // menu bar and causing every subsequent rearrangement to hit the desktop.
            CGWarpMouseCursorPosition(cursor)
        }
        return .posted
    }

    static func dragPath(from start: CGPoint, to end: CGPoint) -> [CGPoint] {
        let distance = hypot(end.x - start.x, end.y - start.y)
        guard distance > 0 else { return [end] }
        let threshold = min(6 / distance, 0.1)
        return [CGPoint(x: start.x + (end.x - start.x) * threshold,
                        y: start.y + (end.y - start.y) * threshold)] + (1...8).map { step in
            let fraction = CGFloat(step) / 8
            return CGPoint(x: start.x + (end.x - start.x) * fraction,
                           y: start.y + (end.y - start.y) * fraction)
        }
    }

    /// Both ends must be visible on one screen and the same menu-bar row. Never drag a
    /// status item down: macOS treats that as removal for some system controls.
    static func dragPoints(item: CGRect, divider: CGRect, toLeft: Bool,
                           screens: [CGRect]) -> (start: CGPoint, end: CGPoint)? {
        guard item.width > 0, item.height > 0, divider.width > 0, divider.height > 0,
              item.minX.isFinite, item.minY.isFinite, item.width.isFinite, item.height.isFinite,
              divider.minX.isFinite, divider.minY.isFinite, divider.width.isFinite, divider.height.isFinite,
              abs(item.midY - divider.midY) < max(item.height, divider.height) / 2,
              let screen = screens.first(where: { $0.contains(item) }) else { return nil }
        let start = CGPoint(x: item.midX, y: item.midY)
        // Use the divider's left or right insertion edge, keeping the destination
        // inside our own status item rather than another app's clickable icon.
        let end = CGPoint(x: toLeft ? divider.minX + 2 : divider.maxX - 2, y: divider.midY)
        // A saturated menu bar can clip one edge of our divider by a point or two while
        // its insertion point is still usable. Requiring the whole divider to be visible
        // rejected exactly that valid layout. The source and actual destination are the
        // coordinates that must be on-screen.
        guard screen.contains(start), screen.contains(end) else { return nil }
        return (start, end)
    }

    private static var mouseIsDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
            || CGEventSource.buttonState(.combinedSessionState, button: .right)
    }

    /// The notch is a transparent panel above the status bar. Its rectangular native
    /// window can intercept events even where SwiftUI draws no content. Do not let
    /// our own overlay swallow the synthetic gesture intended for another app.
    private static func overlayMouseStates(at points: [CGPoint], primaryTop: CGFloat)
        -> [(window: NSWindow, ignored: Bool)] {
        NSApplication.shared.windows.compactMap { window in
            let frame = DrawerGeometry.accessibilityFrame(window.frame, primaryScreenHeight: primaryTop)
            guard window.level.rawValue > NSWindow.Level.statusBar.rawValue,
                  points.contains(where: { frame.contains($0) }) else { return nil }
            return (window, window.ignoresMouseEvents)
        }
    }

    static func event(_ type: CGEventType, at point: CGPoint, source: CGEventSource) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = .maskCommand
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    static func commandEvent(keyDown: Bool, source: CGEventSource) -> CGEvent? {
        // kVK_Command is stable in the macOS virtual-key table and avoids importing Carbon
        // solely for one constant.
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: keyDown) else {
            return nil
        }
        event.flags = keyDown ? .maskCommand : []
        return event
    }
}
