import AltilloCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Makes a shelf tile draggable out of Altillo. `items` is evaluated when the drag starts
    /// (the whole selection when the tile is selected). About 0.5 s after the drop, `onEnded` reports the operation
    /// and the items that actually left the shelf (moved away or trashed), judged by what happened to the files.
    ///
    /// Clicks, selection and context menus keep working: the AppKit drag source is an overlay that never takes part
    /// in hit-testing. A local event monitor watches left-button presses on the tile and only starts an AppKit dragging
    /// session once the pointer moves more than `ShelfDragRouter.threshold` points, swallowing that one drag event.
    func shelfDraggable(
        items: @escaping () -> [ShelfItem],
        onEnded: @escaping (NSDragOperation, [ShelfItem]) -> Void
    ) -> some View {
        overlay(ShelfDragSourceRepresentable(items: items, onEnded: onEnded).allowsHitTesting(false))
    }
}

private struct ShelfDragSourceRepresentable: NSViewRepresentable {
    let items: () -> [ShelfItem]
    let onEnded: (NSDragOperation, [ShelfItem]) -> Void

    func makeNSView(context: Context) -> ShelfDragSourceView {
        let view = ShelfDragSourceView()
        view.items = items
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: ShelfDragSourceView, context: Context) {
        view.items = items
        view.onEnded = onEnded
    }

    static func dismantleNSView(_ view: ShelfDragSourceView, coordinator: ()) {
        ShelfDragRouter.shared.unregister(view)
    }
}

/// Watches left-button presses for every registered tile with one local monitor (not one per tile).
@MainActor
final class ShelfDragRouter {
    static let shared = ShelfDragRouter()
    /// Points the pointer must travel with the button down before a drag starts.
    static let threshold: CGFloat = 3

    private let views = NSHashTable<ShelfDragSourceView>.weakObjects()
    private var monitor: Any?
    private weak var armedView: ShelfDragSourceView?
    private var armedPoint: NSPoint = .zero

    func register(_ view: ShelfDragSourceView) {
        views.add(view)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    func unregister(_ view: ShelfDragSourceView) {
        views.remove(view)
        if armedView === view { armedView = nil }
        if views.allObjects.isEmpty, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Returns true to swallow the event (only the drag event that starts a session).
    private func handle(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown:
            armedView = nil
            // Control-click opens the context menu; never turn it into a drag.
            guard !event.modifierFlags.contains(.control), let window = event.window else { return false }
            armedView = views.allObjects.first { $0.window === window && $0.contains(windowPoint: event.locationInWindow) }
            armedPoint = event.locationInWindow
            return false
        case .leftMouseDragged:
            guard let view = armedView, view.window === event.window else { return false }
            let dx = event.locationInWindow.x - armedPoint.x
            let dy = event.locationInWindow.y - armedPoint.y
            guard dx * dx + dy * dy >= Self.threshold * Self.threshold else { return false }
            armedView = nil
            return view.beginShelfDrag(with: event)
        default:
            armedView = nil
            return false
        }
    }
}

/// Invisible overlay that owns the AppKit dragging session for one tile.
final class ShelfDragSourceView: NSView, NSDraggingSource {
    var items: () -> [ShelfItem] = { [] }
    var onEnded: (NSDragOperation, [ShelfItem]) -> Void = { _, _ in }

    private var draggedItems: [ShelfItem] = []
    private var initiallyExistingFileIDs: Set<ShelfItem.ID> = []

    /// Never the target of clicks: SwiftUI keeps handling taps, selection and context menus on the tile.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            ShelfDragRouter.shared.unregister(self)
        } else {
            ShelfDragRouter.shared.register(self)
        }
    }

    /// True when the point is on the visible (unclipped) part of this tile.
    func contains(windowPoint: NSPoint) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, alphaValue > 0 else { return false }
        return visibleRect.contains(convert(windowPoint, from: nil))
    }

    func beginShelfDrag(with event: NSEvent) -> Bool {
        let items = items()
        let draggingItems = Self.draggingItems(for: items, at: convert(event.locationInWindow, from: nil))
        guard !draggingItems.isEmpty else { return false }
        draggedItems = items
        initiallyExistingFileIDs = Set(items.compactMap { item in
            guard let url = item.fileURL, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return item.id
        })
        // Before the session writes the drag pasteboard, so DragDetector never reports our own drag as incoming.
        DragDetector.isOwnDragInProgress = true
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .default
        let mask = draggingSession(session, sourceOperationMaskFor: .outsideApplication)
        SpikeLog.shared.record(SpikeLog.Category.dragOut,
                               "inicio: \(items.count) ítem(s) [\(Self.kinds(items))] · máscara fuera de la app: \(mask.logDescription)")
        return true
    }

    // MARK: - NSDraggingSource

    /// Outside Altillo we offer the same operations Finder offers for its own files (copy, move, link, generic, delete),
    /// so every destination applies its native rules: Finder moves on the same volume and copies across volumes
    /// (⌥ forces copy, ⌘⌥ makes an alias), the Dock's Trash picks delete, and Mail, Slack or browsers pick copy.
    /// Text and links only offer copy/generic/link: "moving" them makes no sense and would remove them from the shelf.
    /// Inside Altillo nothing is accepted (dropping a tile back on the notch would duplicate it).
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        switch context {
        case .outsideApplication:
            draggedItems.contains(where: { $0.fileURL != nil })
                ? [.copy, .move, .link, .generic, .delete]
                : [.copy, .link, .generic]
        default:
            []
        }
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        DragDetector.isOwnDragInProgress = true
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DragDetector.isOwnDragInProgress = false
        let items = draggedItems
        let initiallyExisting = initiallyExistingFileIDs
        draggedItems = []
        initiallyExistingFileIDs = []
        SpikeLog.shared.record(SpikeLog.Category.dragOut,
                               "fin: operación \(operation.logDescription) en (\(Int(screenPoint.x)), \(Int(screenPoint.y))) · \(items.count) ítem(s)")
        releaseSwiftUIPress()
        Self.resolveDeparted(items, initiallyExistingFileIDs: initiallyExisting, after: operation, then: onEnded)
    }

    // MARK: - Helpers

    /// The dragging session swallows the mouse-up, so SwiftUI would think the button is still pressed on the tile.
    /// Send it a mouse-up far outside any view: gestures end without registering a tap.
    private func releaseSwiftUIPress() {
        guard let window, let up = NSEvent.mouseEvent(
            with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 1, pressure: 0
        ) else { return }
        window.sendEvent(up)
    }

    /// Decides which items actually left the shelf, from what happened to the files rather than from the reported
    /// operation: some destinations return every bit of the source mask, so `.move`/`.delete` bits can't be trusted.
    ///
    /// - A file that no longer exists at its URL 0.5 s later was moved (Finder, same volume) or deleted → it left.
    /// - Only an exact `.delete` (the Dock's Trash) may send a still-present file to the Trash; Altillo does it itself
    ///   because the Dock doesn't delete files for third-party drag sources.
    /// - Text and links never leave: dragging them out always copies.
    static func resolveDeparted(
        _ items: [ShelfItem],
        initiallyExistingFileIDs: Set<ShelfItem.ID>? = nil,
        after operation: NSDragOperation,
        then onEnded: @escaping (NSDragOperation, [ShelfItem]) -> Void
    ) {
        guard operation != [], items.contains(where: { $0.fileURL != nil }) else {
            onEnded(operation, [])
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            var departed: [ShelfItem] = []
            var toRecycle: [URL] = []
            let initiallyExisting = initiallyExistingFileIDs ?? Set(items.compactMap { $0.fileURL == nil ? nil : $0.id })
            for item in items {
                guard let url = item.fileURL, initiallyExisting.contains(item.id) else { continue }
                let exists = FileManager.default.fileExists(atPath: url.path)
                SpikeLog.shared.record(SpikeLog.Category.dragOut, "\(url.lastPathComponent): existe después: \(exists ? "sí" : "no") · \(url.path)")
                if !exists, operation == .move || operation == .delete {
                    departed.append(item)
                } else if operation == .delete {
                    toRecycle.append(url)
                    departed.append(item)
                }
            }
            if !toRecycle.isEmpty {
                do {
                    let moved = try await NSWorkspace.shared.recycle(toRecycle)
                    SpikeLog.shared.record(SpikeLog.Category.dragOut, "papelera: Altillo movió \(moved.count) archivo(s) a la Papelera")
                } catch {
                    departed.removeAll { item in toRecycle.contains { $0 == item.fileURL } }
                    SpikeLog.shared.record(SpikeLog.Category.dragOut, "FALLO moviendo a la Papelera: \(error.localizedDescription)")
                }
            }
            onEnded(operation, departed)
        }
    }

    private static func kinds(_ items: [ShelfItem]) -> String {
        items.map { item in
            switch item.kind {
            case let .file(_, isOwnedCopy): isOwnedCopy ? "copia" : "referencia"
            case .link: "enlace"
            case .text: "texto"
            }
        }.joined(separator: ", ")
    }

    /// One dragging item per shelf item, fanned out a little under the pointer (the first few visible, the rest piled).
    private static func draggingItems(for items: [ShelfItem], at point: NSPoint) -> [NSDraggingItem] {
        let side: CGFloat = 56
        return items.enumerated().compactMap { index, item in
            let writer: any NSPasteboardWriting
            let icon: NSImage
            switch item.kind {
            case let .file(url, _):
                writer = url as NSURL
                icon = NSWorkspace.shared.icon(forFile: url.path)
            case let .link(url):
                writer = url as NSURL
                icon = NSWorkspace.shared.icon(for: .internetLocation)
            case let .text(text):
                writer = text as NSString
                icon = NSWorkspace.shared.icon(for: .plainText)
            }
            let draggingItem = NSDraggingItem(pasteboardWriter: writer)
            let step = CGFloat(min(index, 3))
            let frame = NSRect(x: point.x - side / 2 + step * 6, y: point.y - side / 2 - step * 6, width: side, height: side)
            draggingItem.setDraggingFrame(frame, contents: icon)
            return draggingItem
        }
    }
}
