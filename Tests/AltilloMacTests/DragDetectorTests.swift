import AppKit
import Testing
@testable import Altillo

/// Replays mouse event types against a private pasteboard standing in for the drag pasteboard.
@MainActor
@Suite(.serialized)
final class DragDetectorTests {
    private let pasteboard = NSPasteboard(name: .init("altillo-tests-\(UUID().uuidString)"))
    private var began = 0
    private var moved = 0
    private var ended = 0
    private lazy var detector = DragDetector(callbacks: .init(
        began: { [unowned self] in began += 1 },
        moved: { [unowned self] _ in moved += 1 },
        ended: { [unowned self] in ended += 1 }
    ), pasteboard: pasteboard)

    private func startDrag(writing objects: [any NSPasteboardWriting]) {
        detector.handle(.leftMouseDown)
        detector.handle(.leftMouseDragged) // the source has not written the pasteboard yet
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
    }

    @Test func reportsADroppableDragOnce() {
        defer { pasteboard.releaseGlobally() }
        startDrag(writing: [URL(filePath: "/Users/tester/a.txt") as NSURL])
        #expect(began == 0)
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseDragged)
        #expect(began == 1)
        #expect(moved == 3)
        detector.handle(.leftMouseUp)
        #expect(ended == 1)
    }

    @Test func ignoresClicksAndDragsWithoutPasteboardChanges() {
        defer { pasteboard.releaseGlobally() }
        detector.handle(.leftMouseDown)
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseUp)
        #expect(began == 0 && moved == 0 && ended == 0)
    }

    @Test func ignoresUndroppableContent() {
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("x", forType: .init("com.example.private-type"))
        startDrag(writing: [item])
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseUp)
        #expect(began == 0 && ended == 0)
    }

    @Test func ignoresOwnDrags() {
        defer { pasteboard.releaseGlobally() }
        DragDetector.isOwnDragInProgress = true
        defer { DragDetector.isOwnDragInProgress = false }
        startDrag(writing: ["texto" as NSString])
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseUp)
        #expect(began == 0 && ended == 0)
    }

    @Test func aNewPressEndsAStuckDrag() {
        defer { pasteboard.releaseGlobally() }
        startDrag(writing: ["texto" as NSString])
        detector.handle(.leftMouseDragged)
        detector.handle(.leftMouseDown) // mouse-up was never seen
        #expect(began == 1 && ended == 1)
    }
}
