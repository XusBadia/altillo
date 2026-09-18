import AppKit

/// Detects drags carrying files, URLs or text anywhere on screen (not only over Altillo).
/// STUB: implemented by the drag & drop spike. Keep this API.
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

    private let callbacks: Callbacks

    init(callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    func start() {}
    func stop() {}
}
