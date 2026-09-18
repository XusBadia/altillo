import AppKit

/// Global + local mouse monitors. Global monitors only see events sent to other apps, local ones only ours,
/// so both are installed. Neither needs the Accessibility permission for mouse events.
@MainActor
final class InputMonitor {
    var mouseMoved: (CGPoint) -> Void = { _ in }
    /// Returns true to swallow a local click.
    var mouseDown: (CGPoint, _ isLocal: Bool) -> Void = { _, _ in }

    private var monitors: [Any] = []

    func start() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved]
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: moveMask) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: moveMask) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseMoved(NSEvent.mouseLocation) }
            return event
        } as Any)
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown(NSEvent.mouseLocation, false) }
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDown(NSEvent.mouseLocation, true) }
            return event
        } as Any)
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}
