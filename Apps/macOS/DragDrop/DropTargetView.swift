import AltilloCore
import AppKit

/// Full-size view inside the notch panel that receives drops (files, file promises, URLs, text, images).
/// STUB: implemented by the drag & drop spike. Keep this API.
final class DropTargetView: NSView {
    var onDragEntered: () -> Void = {}
    var onDragExited: () -> Void = {}
    /// Delivered on the main actor once every dropped item is ingested (file promises resolve asynchronously).
    var onDrop: ([ShelfItem]) -> Void = { _ in }
}
