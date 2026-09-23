import AltilloCore
import Foundation
import Testing
@testable import Altillo

struct FileIngestClassificationTests {
    private let ingest = FileIngest(
        inboxRoot: URL(filePath: "/Users/tester/Library/Application Support/Altillo/Inbox", directoryHint: .isDirectory),
        homeDirectory: URL(filePath: "/Users/tester", directoryHint: .isDirectory),
        temporaryDirectory: URL(filePath: "/private/var/folders/ab/cd1234/T/", directoryHint: .isDirectory)
    )

    private func decision(_ path: String) -> FileIngest.Decision {
        ingest.classify(URL(filePath: path))
    }

    @Test(arguments: [
        "/Users/tester/Documents/Report.pdf",
        "/Users/tester/Desktop/screenshot.png",
        "/Users/tester/Downloads/installer.dmg",
        "/Users/tester/Library/Mobile Documents/com~apple~CloudDocs/note.txt",
        "/Users/tester/Library/Containers/com.example.app/Data/Documents/doc.txt",
        "/Volumes/External/Photos/IMG_0001.HEIC",
        "/Applications/Safari.app",
        "/Users/tester/Library/Application Support/Altillo/InboxOld/x.txt",
    ])
    func stableLocationsAreReferenced(path: String) {
        #expect(decision(path) == .reference)
    }

    @Test(arguments: [
        ("/private/var/folders/ab/cd1234/T/TemporaryItems/NSIRD_screencaptureui_x/Screenshot.png", "temporary"),
        ("/var/folders/zz/other/T/foo.txt", "temporary"),
        ("/tmp/foo.txt", "temporary"),
        ("/private/tmp/foo.txt", "temporary"),
        ("/Users/tester/.Trash/old.txt", "trash"),
        ("/Volumes/External/.Trashes/501/old.txt", "trash"),
        ("/Users/tester/Library/Containers/com.apple.mail/Data/Library/Mail Downloads/ABC/attachment.pdf", "Mail"),
        ("/Users/tester/Library/Mail/V10/account/INBOX.mbox/Attachments/1/2/attachment.pdf", "Mail"),
        ("/Users/tester/Library/Containers/com.apple.Safari/Data/Library/Caches/img.jpg", "Safari"),
        ("/Users/tester/Library/Caches/com.google.Chrome/img.webp", "caches"),
        ("/Users/tester/Library/Containers/com.tinyspeck.slackmacgap/Data/tmp/file.zip", "temporary file of com.tinyspeck.slackmacgap"),
        ("/Users/tester/Library/Containers/com.example.app/Data/Library/Caches/x.png", "temporary file of com.example.app"),
        ("/Users/tester/Library/Application Support/Altillo/Inbox/UUID/photo.jpg", "own inbox"),
    ])
    func volatileLocationsAreCopied(path: String, reason: String) {
        #expect(decision(path) == .copy(reason: reason))
    }

    @Test func sanitizesFileNames() {
        #expect(FileIngest.sanitizedFileName("a/b:c.txt") == "a-b-c.txt")
        #expect(FileIngest.sanitizedFileName("  ") == "Untitled")
        #expect(FileIngest.sanitizedFileName(".hidden") == "hidden")
    }
}

/// Uses real files: a temporary source (copied) and one under Application Support (referenced).
struct FileIngestDiskTests {
    private let root: URL
    private let ingest: FileIngest

    init() throws {
        root = URL.applicationSupportDirectory.appending(path: "AltilloTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        ingest = FileIngest(inboxRoot: root.appending(path: "Inbox", directoryHint: .isDirectory))
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func temporaryFileIsClonedIntoInbox() throws {
        defer { cleanUp() }
        let source = FileManager.default.temporaryDirectory.appending(path: "altillo-test-\(UUID().uuidString).txt")
        try Data("hola".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let (item, decision) = try ingest.ingest(fileAt: source)
        #expect(decision == .copy(reason: "temporary"))
        guard case let .file(copy, isOwnedCopy) = item.kind else {
            Issue.record("expected a file item")
            return
        }
        #expect(isOwnedCopy)
        #expect(copy.lastPathComponent == source.lastPathComponent)
        #expect(copy.path.hasPrefix(ingest.inboxRoot.path))
        #expect(try Data(contentsOf: copy) == Data("hola".utf8))
        #expect(FileManager.default.fileExists(atPath: source.path), "the original is left untouched")
    }

    @Test func temporaryFolderIsCopiedRecursively() throws {
        defer { cleanUp() }
        let folder = FileManager.default.temporaryDirectory.appending(path: "altillo-folder-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "sub"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "sub/a.txt"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let (item, _) = try ingest.ingest(fileAt: folder)
        let copy = try #require(item.fileURL)
        #expect(FileManager.default.fileExists(atPath: copy.appending(path: "sub/a.txt").path))
    }

    @Test func stableFileIsReferenced() throws {
        defer { cleanUp() }
        let source = root.appending(path: "Documento estable.txt")
        try Data("estable".utf8).write(to: source)

        let (item, decision) = try ingest.ingest(fileAt: source)
        #expect(decision == .reference)
        #expect(item.kind == .file(source.standardizedFileURL, isOwnedCopy: false))
        #expect(item.displayName.hasPrefix("Documento estable"))
        let inboxExists = FileManager.default.fileExists(atPath: ingest.inboxRoot.path)
        #expect(!inboxExists, "no copy was made")
    }

    @Test func missingFileThrows() {
        defer { cleanUp() }
        #expect(throws: FileIngest.IngestError.self) {
            try ingest.ingest(fileAt: root.appending(path: "does-not-exist.txt"))
        }
    }

    @Test func rawDataGetsUniqueSlots() throws {
        defer { cleanUp() }
        let first = try ingest.ingest(data: Data([1, 2, 3]), suggestedName: "Image.png")
        let second = try ingest.ingest(data: Data([4, 5]), suggestedName: "Image.png")
        let a = try #require(first.fileURL)
        let b = try #require(second.fileURL)
        #expect(a != b)
        #expect(a.lastPathComponent == "Image.png")
        #expect(b.lastPathComponent == "Image.png")
        #expect(try Data(contentsOf: b) == Data([4, 5]))
    }
}
