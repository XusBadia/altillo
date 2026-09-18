import AltilloCore
import AppKit
import Testing
@testable import Altillo

/// Drives `DropTargetView` through `NSDraggingDestination` with a fake dragging info backed by a private pasteboard.
@MainActor
@Suite(.serialized)
struct DropTargetTests {
    private let pasteboard = NSPasteboard(name: .init("altillo-tests-\(UUID().uuidString)"))
    private let root = URL.applicationSupportDirectory.appending(path: "AltilloTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func makeView() -> DropTargetView {
        let view = DropTargetView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.ingest = FileIngest(inboxRoot: root.appending(path: "Inbox", directoryHint: .isDirectory))
        return view
    }

    private func drop(_ info: FakeDraggingInfo, on view: DropTargetView) async -> [ShelfItem]? {
        await withCheckedContinuation { continuation in
            view.onDrop = { continuation.resume(returning: $0) }
            if !view.performDragOperation(info) { continuation.resume(returning: nil) }
        }
    }

    @Test func registersPromiseAndFileTypes() {
        let types = Set(makeView().registeredDraggedTypes)
        #expect(types.contains(.fileURL))
        #expect(types.contains(.URL))
        #expect(types.contains(.string))
        #expect(types.contains(.tiff))
        for promise in NSFilePromiseReceiver.readableDraggedTypes {
            #expect(types.contains(.init(promise)))
        }
    }

    @Test func choosesOperationPerContent() {
        let view = makeView()
        var entered = 0
        view.onDragEntered = { entered += 1 }

        pasteboard.clearContents()
        pasteboard.writeObjects([URL(filePath: "/Users/tester/a.txt") as NSURL])
        #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard, mask: .every)) == .generic)
        #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard, mask: .copy)) == .copy)
        #expect(entered == 1, "entered fires once per hover")

        pasteboard.clearContents()
        pasteboard.writeObjects(["texto" as NSString])
        #expect(view.draggingUpdated(FakeDraggingInfo(pasteboard: pasteboard, mask: .every)) == .copy)

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("x", forType: .init("com.example.private-type"))
        pasteboard.writeObjects([item])
        #expect(view.draggingUpdated(FakeDraggingInfo(pasteboard: pasteboard, mask: .every)) == [])
        pasteboard.releaseGlobally()
    }

    @Test func rejectsOwnDrags() {
        let view = makeView()
        pasteboard.clearContents()
        pasteboard.writeObjects(["texto" as NSString])
        let own = FakeDraggingInfo(pasteboard: pasteboard, mask: .every, source: view)
        #expect(view.draggingEntered(own) == [])
        #expect(!view.performDragOperation(own))

        DragDetector.isOwnDragInProgress = true
        defer { DragDetector.isOwnDragInProgress = false }
        #expect(view.draggingEntered(FakeDraggingInfo(pasteboard: pasteboard, mask: .every)) == [])
        pasteboard.releaseGlobally()
    }

    @Test func deliversFilesLinksImagesAndTextInOrder() async throws {
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stable = root.appending(path: "estable.txt")
        try Data("a".utf8).write(to: stable)
        let temporary = FileManager.default.temporaryDirectory.appending(path: "altillo-drop-\(UUID().uuidString).txt")
        try Data("b".utf8).write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let png = try #require(DropReaderTests.samplePNG())
        let image = NSPasteboardItem()
        image.setData(png, forType: .png)
        let link = NSPasteboardItem()
        link.setString("https://example.com/pagina", forType: .URL)

        pasteboard.clearContents()
        pasteboard.writeObjects([stable as NSURL, temporary as NSURL, link, image, "nota rápida" as NSString])

        let view = makeView()
        var accepted = false
        view.onDropAccepted = { accepted = true }
        let items = try #require(await drop(FakeDraggingInfo(pasteboard: pasteboard, mask: .every), on: view))

        #expect(accepted)
        try #require(items.count == 5)
        #expect(items[0].kind == .file(stable.standardizedFileURL, isOwnedCopy: false))
        guard case let .file(copy, true) = items[1].kind else {
            Issue.record("temporary file should be an owned copy")
            return
        }
        #expect(copy.path.hasPrefix(root.path))
        #expect(items[2].kind == .link(URL(string: "https://example.com/pagina")!))
        #expect(items[2].displayName == "example.com/pagina")
        guard case let .file(imageFile, true) = items[3].kind else {
            Issue.record("image data should be written to the inbox")
            return
        }
        #expect(try Data(contentsOf: imageFile) == png)
        #expect(items[4].kind == .text("nota rápida"))
        #expect(items[4].displayName == "nota rápida")
    }

    @Test func partialFailureStillDeliversTheRest() async throws {
        defer {
            pasteboard.releaseGlobally()
            try? FileManager.default.removeItem(at: root)
        }
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(filePath: "/no/existe/\(UUID().uuidString).txt") as NSURL, "sobrevive" as NSString])

        let items = try #require(await drop(FakeDraggingInfo(pasteboard: pasteboard, mask: .every), on: makeView()))
        #expect(items.map(\.kind) == [.text("sobrevive")])
    }
}

final class FakeDraggingInfo: NSObject, NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSourceOperationMask: NSDragOperation
    let draggingSource: Any?

    @MainActor init(pasteboard: NSPasteboard, mask: NSDragOperation, source: Any? = nil) {
        draggingPasteboard = pasteboard
        draggingSourceOperationMask = mask
        draggingSource = source
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingLocation: NSPoint { .zero }
    var draggedImageLocation: NSPoint { .zero }
    var draggedImage: NSImage? { nil }
    var draggingSequenceNumber: Int { 1 }
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 0
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions = [],
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
    func resetSpringLoading() {}
}
