import AppKit

/// Detects drags carrying files, URLs or text anywhere on screen (not only over Altillo).
///
/// How: on `leftMouseDown` remember the drag pasteboard's `changeCount`. A drag session writes to that pasteboard
/// when it starts, so on `leftMouseDragged` a changed count with droppable types means a drag is in flight.
/// Global monitors see events sent to other apps and local monitors our own; mouse monitors need no Accessibility.
@MainActor
final class DragDetector {
    struct Callbacks {
        /// A drag with droppable content started outside Altillo.
        var began: () -> Void
        /// The pointer moved during that drag (AppKit screen coordinates).
        var moved: (CGPoint) -> Void
        /// The mouse button was released.
        var ended: () -> Void
    }

    /// Set by `shelfDraggable` while a drag started from the shelf is in flight, so it is not mistaken for an incoming drag.
    static var isOwnDragInProgress = false

    private enum Phase {
        /// No button down.
        case idle
        /// Button down; waiting for the drag pasteboard to change.
        case pressed(changeCount: Int)
        /// A droppable drag is in flight; `began` fired.
        case dragging
        /// The pasteboard changed but the drag is ours or carries nothing droppable; ignore until mouse up.
        case ignored
    }

    private let callbacks: Callbacks
    private let pasteboard: NSPasteboard
    private var monitors: [Any] = []
    private var phase = Phase.idle

    /// `pasteboard` is injectable for tests; the app always uses the system drag pasteboard.
    init(callbacks: Callbacks, pasteboard: NSPasteboard = NSPasteboard(name: .drag)) {
        self.callbacks = callbacks
        self.pasteboard = pasteboard
    }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if case .dragging = phase { callbacks.ended() }
        phase = .idle
    }

    /// Hot path: runs for every drag event, so it only compares integers until a drag is confirmed.
    func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            if case .dragging = phase { callbacks.ended() }
            phase = .pressed(changeCount: pasteboard.changeCount)
        case .leftMouseDragged:
            switch phase {
            case .dragging:
                callbacks.moved(NSEvent.mouseLocation)
            case let .pressed(changeCount):
                guard pasteboard.changeCount != changeCount else { return }
                evaluateNewDrag()
            case .idle, .ignored:
                return
            }
        case .leftMouseUp:
            if case .dragging = phase {
                SpikeLog.shared.record(SpikeLog.Category.dragEnd, "soltado en \(Self.describe(NSEvent.mouseLocation))")
                phase = .idle
                callbacks.ended()
            } else {
                phase = .idle
            }
        default:
            return
        }
    }

    private func evaluateNewDrag() {
        let types = pasteboard.types ?? []
        guard !Self.isOwnDragInProgress else {
            phase = .ignored
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let items = pasteboard.pasteboardItems?.count ?? 0
        guard DragPasteboard.isDroppable(types) else {
            phase = .ignored
            SpikeLog.shared.record(SpikeLog.Category.dragStart,
                                   "ignorado (sin tipos aceptables) · app: \(app) · tipos: \(Self.describe(types))")
            return
        }
        phase = .dragging
        SpikeLog.shared.record(SpikeLog.Category.dragStart,
                               "app: \(app) · \(items) ítem(s) · tipos: \(Self.describe(types))")
        callbacks.began()
        callbacks.moved(NSEvent.mouseLocation)
    }

    private static func describe(_ types: [NSPasteboard.PasteboardType]) -> String {
        types.isEmpty ? "—" : types.map(\.rawValue).joined(separator: ", ")
    }

    private static func describe(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }
}
