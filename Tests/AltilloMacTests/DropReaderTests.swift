import AltilloCore
import AppKit
import Testing
@testable import Altillo

/// Feeds private named pasteboards (never the general or drag pasteboard) into the drop-reading code.
@MainActor
struct DropReaderTests {
    private let pasteboard = NSPasteboard(name: .init("altillo-tests-\(UUID().uuidString)"))

    private func item(_ values: [NSPasteboard.PasteboardType: String]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        for (type, value) in values { item.setString(value, forType: type) }
        return item
    }

    @Test func readsSeveralFinderFilesInOrder() {
        defer { pasteboard.releaseGlobally() }
        let a = URL(filePath: "/Users/tester/Documents/a.pdf")
        let b = URL(filePath: "/Users/tester/Documents/b.pdf")
        pasteboard.clearContents()
        pasteboard.writeObjects([a as NSURL, b as NSURL])

        let payload = DropReader.read(from: pasteboard)
        #expect(payload.items == [.file(a), .file(b)])
        #expect(payload.promises.isEmpty)
        #expect(payload.summary == "2 files")
    }

    @Test func resolvesFileReferenceURLs() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "altillo-ref-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        // Swift's URL bridging turns reference URLs back into path URLs, so build the string through CoreFoundation.
        let cfReference = try #require(CFURLCreateFileReferenceURL(nil, file as CFURL, nil)?.takeRetainedValue())
        let reference = try #require(CFURLGetString(cfReference) as String?)
        #expect(reference.contains(".file/id="))

        let resolved = try #require(DropReader.fileURL(from: reference))
        #expect(resolved.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
    }

    @Test func readsWebURLWithTitleAsLink() {
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([item([
            .URL: "https://example.com/article",
            DragPasteboard.urlName: "An article",
            .string: "https://example.com/article",
        ])])

        let payload = DropReader.read(from: pasteboard)
        #expect(payload.items == [.link(URL(string: "https://example.com/article")!, title: "An article")])
    }

    @Test func readsPlainTextAndURLLikeText() {
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.writeObjects([
            "Hello, this is selected text" as NSString,
            item([.string: "https://apple.com/en/"]),
            item([.string: "not a url: https://apple.com"]),
        ])

        let payload = DropReader.read(from: pasteboard)
        #expect(payload.items == [
            .text("Hello, this is selected text"),
            .link(URL(string: "https://apple.com/en/")!, title: nil),
            .text("not a url: https://apple.com"),
        ])
    }

    @Test func readsRTFOnlyText() throws {
        defer { pasteboard.releaseGlobally() }
        let attributed = NSAttributedString(string: "Rich text")
        let rtf = try attributed.data(from: NSRange(location: 0, length: attributed.length),
                                      documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let item = NSPasteboardItem()
        item.setData(rtf, forType: .rtf)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        #expect(DropReader.read(from: pasteboard).items == [.text("Rich text")])
    }

    @Test func imageDataWinsOverItsWebURL() throws {
        defer { pasteboard.releaseGlobally() }
        let png = try #require(Self.samplePNG())
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setString("https://example.com/fotos/gato.jpg", forType: .URL)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let payload = DropReader.read(from: pasteboard)
        #expect(payload.items == [.image(png, type: NSPasteboard.PasteboardType.png.rawValue, suggestedName: "gato.png")])
    }

    @Test func tiffWithoutSourceIsNamedAsPNG() throws {
        defer { pasteboard.releaseGlobally() }
        let tiff = try #require(NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.orange.setFill()
            rect.fill()
            return true
        }.tiffRepresentation)
        let item = NSPasteboardItem()
        item.setData(tiff, forType: .tiff)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        guard case let .image(_, type, name) = DropReader.read(from: pasteboard).items.first else {
            Issue.record("expected an image")
            return
        }
        #expect(type == NSPasteboard.PasteboardType.tiff.rawValue)
        #expect(name.hasPrefix("Image "))
        #expect(name.hasSuffix(".png"))
    }

    @Test func keepsMixedOrder() {
        defer { pasteboard.releaseGlobally() }
        let file = URL(filePath: "/Users/tester/Desktop/x.txt")
        pasteboard.clearContents()
        pasteboard.writeObjects([
            "first" as NSString,
            file as NSURL,
            item([.URL: "https://example.com"]),
        ])

        #expect(DropReader.read(from: pasteboard).items == [
            .text("first"), .file(file), .link(URL(string: "https://example.com")!, title: nil),
        ])
    }

    @Test func detectsFilePromises() {
        defer { pasteboard.releaseGlobally() }
        let delegate = PromiseDelegate()
        let provider = NSFilePromiseProvider(fileType: "public.plain-text", delegate: delegate)
        pasteboard.clearContents()
        pasteboard.writeObjects([provider, "and some text" as NSString])

        let types = pasteboard.types ?? []
        #expect(DragPasteboard.isDroppable(types))
        let payload = DropReader.read(from: pasteboard)
        #expect(payload.promiseItemCount == 1)
        #expect(payload.promises.count == 1)
        #expect(payload.promiseInsertionIndex == 0)
        #expect(payload.items == [.text("and some text")])
    }

    @Test func droppableTypes() {
        #expect(DragPasteboard.isDroppable([.fileURL]))
        #expect(DragPasteboard.isDroppable([.init("com.apple.pasteboard.promised-file-url")]))
        #expect(DragPasteboard.isDroppable([.init("com.apple.NSFilePromiseItemMetaData")]))
        #expect(DragPasteboard.isDroppable([.string]))
        #expect(DragPasteboard.isDroppable([.png]))
        #expect(!DragPasteboard.isDroppable([.init("com.example.private-type")]))
        #expect(!DragPasteboard.isDroppable([]))
        #expect(!DragPasteboard.isDroppable(nil))
    }

    static func samplePNG() -> Data? {
        let image = NSImage(size: NSSize(width: 2, height: 2), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        guard let tiff = image.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "prometido.txt"
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL) async throws {
        try Data("promise".utf8).write(to: url)
    }
}
