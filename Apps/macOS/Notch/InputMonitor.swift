import AppKit

/// Global + local mouse monitors. Global monitors only see events sent to other apps, local ones only ours,
/// so both are installed. Neither needs the Accessibility permission for mouse events.
@MainActor
final class InputMonitor {
    var mouseMoved: (CGPoint) -> Void = { _ in }
    /// A click anywhere. `isRight` for the secondary button (right-click or control-click).
    var mouseDown: (CGPoint, _ isLocal: Bool, _ isRight: Bool) -> Void = { _, _, _ in }

    private var monitors: [Any] = []

    /// Idempotent: starting twice never doubles the monitors (and every event with them).
    func start() {
        guard monitors.isEmpty else { return }
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved]
        add(NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
        })
        add(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
            return event
        })
        add(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let isRight = Self.isSecondary(event)
            MainActor.assumeIsolated { self?.mouseDown(NSEvent.mouseLocation, false, isRight) }
        })
        add(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            let isRight = Self.isSecondary(event)
            MainActor.assumeIsolated { self?.mouseDown(NSEvent.mouseLocation, true, isRight) }
            return event
        })
    }

    /// AppKit returns nil when it can't install a monitor; keep only real ones so `stop` never removes a nil.
    private func add(_ monitor: Any?) {
        if let monitor { monitors.append(monitor) }
    }

    /// Right button, or a control-click (the Mac's other right-click).
    nonisolated private static func isSecondary(_ event: NSEvent) -> Bool {
        event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
