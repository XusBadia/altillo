import Foundation
import Testing
@testable import Altillo

@MainActor
struct QuickLookPresenterTests {
    @Test func filtersMissingFilesWithoutChangingOrder() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "AltilloQuickLookTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let first = root.appending(path: "first.txt")
        let missing = root.appending(path: "missing.txt")
        let second = root.appending(path: "second.txt")
        try Data().write(to: first)
        try Data().write(to: second)

        #expect(QuickLookPresenter.existingURLs(in: [first, missing, second]) == [first, second])
    }

    @Test func dataSourceHandlesSeveralItemsAndInvalidIndexes() {
        let source = QuickLookPresenter.Source()
        let urls = [URL(filePath: "/tmp/a.txt"), URL(filePath: "/tmp/b.txt")]
        source.urls = urls

        #expect(source.numberOfPreviewItems(in: nil) == 2)
        #expect((source.previewPanel(nil, previewItemAt: 0) as? NSURL) == urls[0] as NSURL)
        #expect(source.previewPanel(nil, previewItemAt: -1) == nil)
        #expect(source.previewPanel(nil, previewItemAt: 2) == nil)
    }
}
