import AltilloCore
import AppKit
import Testing
@testable import Altillo

/// Drops only land where the pointer is: the shelf zone, the AirDrop zone, or nowhere.
@MainActor
@Suite(.serialized)
struct DropZoneTests {
    private let pasteboard = NSPasteboard(name: .init("altillo-zone-tests-\(UUID().uuidString)"))

    private func makeView(zone: DropZone?) -> DropTargetView {
        let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.zoneAt = { _ in zone }
        return view
    }

    private func textDrag() -> FakeDraggingInfo {
        pasteboard.clearContents()
        pasteboard.writeObjects(["hola" as NSString])
        return FakeDraggingInfo(pasteboard: pasteboard, mask: .every)
    }

    @Test func outsideEveryZoneRefusesTheDrop() {
        defer { pasteboard.releaseGlobally() }
        let view = makeView(zone: nil)
        var entered = false
        view.onDragEntered = { entered = true }
        let info = textDrag()

        #expect(view.draggingEntered(info) == [])
        #expect(!view.prepareForDragOperation(info))
        #expect(!view.performDragOperation(info))
        #expect(!entered, "nothing lights up outside the zones")
    }

    @Test func reportsZoneChangesOnlyWhenTheyChange() {
        defer { pasteboard.releaseGlobally() }
        var zone: DropZone? = .shelf
        let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.zoneAt = { _ in zone }
        var reported: [DropZone?] = []
        view.onZoneChanged = { reported.append($0) }
        let info = textDrag()

        _ = view.draggingEntered(info)
        _ = view.draggingUpdated(info)
        zone = .airDrop
        _ = view.draggingUpdated(info)
        view.draggingExited(info)

        #expect(reported == [.shelf, .airDrop, nil])
    }

    @Test func airDropZoneDeliversToAirDropNotTheShelf() async {
        defer { pasteboard.releaseGlobally() }
        let view = makeView(zone: .airDrop)
        var shelf: [ShelfItem] = []
        view.onDrop = { shelf = $0 }
        let items: [ShelfItem] = await withCheckedContinuation { continuation in
            view.onAirDrop = { continuation.resume(returning: $0) }
            #expect(view.performDragOperation(textDrag()))
        }
        #expect(items.map(\.kind) == [.text("hola")])
        #expect(shelf.isEmpty)
    }
}
