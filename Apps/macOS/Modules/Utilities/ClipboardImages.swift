import AppKit
import CryptoKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers
import Vision

/// A copied image, as a slip keeps it: its PNG lives in `ClipboardImages`, named by its hash; the history (and its
/// JSON) only holds this.
struct ClipboardImage: Codable, Hashable, Sendable {
    /// SHA-256 of the PNG, in hex: the blob's name and what tells two copies of the same image apart.
    var hash: String
    var width: Int
    var height: Int
    var byteCount: Int
    /// The words Vision read in it, on this Mac, so search finds it: nil until it's been read, empty when there
    /// were none.
    var recognizedText: String?
}

/// The PNGs behind the image slips. In memory while the history is only in memory; also on disk, next to the
/// history's JSON (same privacy: 0600 files in a 0700 folder, out of backups), only while the user keeps the history
/// after quitting. What the history no longer points to is dropped from both at once (`retain`), so an image thrown
/// away, trimmed or cleared never stays behind. The disk work (writing a 16 MB PNG, deleting) runs on a serial
/// queue of its own, in order, never on the main thread.
@MainActor
@Observable
final class ClipboardImages {
    /// Largest image kept, as PNG: a copied 6K screenshot fits, a poster-sized render doesn't.
    nonisolated static let maxBytes = 16 * 1024 * 1024
    /// Longest side of a slip's thumbnail, in pixels.
    nonisolated static let thumbnailPixels = 176

    let folder: URL

    /// Thumbnails made so far, by hash (made off the main thread the first time a slip asks).
    private(set) var thumbnails: [String: NSImage] = [:]

    @ObservationIgnored private var blobs: [String: Data] = [:]
    /// PNGs queued to be written, readable until they're on disk (the section may stop and start again first).
    @ObservationIgnored private var pendingWrites: [String: Data] = [:]
    @ObservationIgnored private var making: Set<String> = []
    /// The PNGs on disk (or queued to be), so nothing on the main thread has to look.
    @ObservationIgnored private var onDisk: Set<String>?
    /// The folder was deleted (or queued to be) and nothing has been written since.
    @ObservationIgnored private var folderIsGone = false
    @ObservationIgnored private var usedScratch = false
    @ObservationIgnored private let disk = DispatchQueue(label: "me.badia.altillo.clipboard-images", qos: .utility)

    init(folder: URL) {
        self.folder = folder
    }

    // MARK: - Reading a copy

    /// The image bytes on a pasteboard, as they are (cheap: no decoding), and whether they're PNG already.
    static func rawImage(from pasteboard: NSPasteboard) -> (data: Data, isPNG: Bool)? {
        if let png = pasteboard.data(forType: .png) { return (png, true) }
        for type in otherImageTypes {
            if let data = pasteboard.data(forType: type) { return (data, false) }
        }
        return nil
    }

    /// The image as PNG with its hash and size, or nil when this history doesn't keep it (unreadable, or bigger
    /// than `maxBytes`). PNG is taken as is; anything else is converted once. Decodes and hashes: call it off the
    /// main thread.
    nonisolated static func prepare(_ raw: Data, isPNG: Bool) -> (ClipboardImage, Data)? {
        let png: Data
        if isPNG {
            png = raw
        } else {
            guard raw.count <= maxBytes * 3, let rep = NSBitmapImageRep(data: raw),
                  let converted = rep.representation(using: .png, properties: [:]) else { return nil }
            png = converted
        }
        return describe(png).map { ($0, png) }
    }

    private static let otherImageTypes: [NSPasteboard.PasteboardType] = [
        .tiff, .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .init(UTType.gif.identifier),
        .init(UTType.webP.identifier), .init(UTType.bmp.identifier),
    ]

    /// Hash and pixel size of a PNG; nil when it's too big or not an image.
    nonisolated static func describe(_ png: Data) -> ClipboardImage? {
        guard !png.isEmpty, png.count <= maxBytes,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        return ClipboardImage(hash: hash(of: png), width: width, height: height, byteCount: png.count)
    }

    // MARK: - Keeping them

    func add(_ png: Data, for image: ClipboardImage) {
        blobs[image.hash] = png
    }

    /// The PNG, from memory or (a history kept after quitting) from disk; nil once it's gone.
    func data(for image: ClipboardImage) -> Data? {
        if let data = blobs[image.hash] ?? pendingWrites[image.hash] { return data }
        guard diskIndex().contains(image.hash),
              let data = try? Data(contentsOf: url(for: image.hash)),
              Self.hash(of: data) == image.hash else { return nil }
        blobs[image.hash] = data
        return data
    }

    /// In memory or on disk, without touching the disk (safe in a view's body).
    func has(_ image: ClipboardImage) -> Bool {
        blobs[image.hash] != nil || diskIndex().contains(image.hash)
    }

    /// Keeps in memory only the images in `memory` (the history plus whatever Undo can still put back) and, when
    /// `disk` is given, writes those to disk and deletes every other file there; `disk` nil deletes the folder.
    func retain(memory: Set<String>, disk wanted: Set<String>?) {
        guard let wanted else {
            retainInMemory(memory)
            deleteFolder()
            return
        }
        let present = diskIndex()
        let writes = wanted.subtracting(present).compactMap { hash in blobs[hash].map { (hash, $0) } }
        let deletes = present.subtracting(wanted)
        onDisk = present.subtracting(deletes).union(writes.map(\.0))
        retainInMemory(memory)
        guard !writes.isEmpty || !deletes.isEmpty else { return }
        folderIsGone = false
        for (hash, data) in writes { pendingWrites[hash] = data }
        for hash in deletes { pendingWrites[hash] = nil }
        let folder = folder
        let written = writes.map(\.0)
        disk.async {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                for hash in deletes { try? FileManager.default.removeItem(at: Self.url(for: hash, in: folder)) }
                for (hash, data) in writes { try Self.write(data, to: Self.url(for: hash, in: folder)) }
            } catch {
                DiagnosticLog.post("clipboard", "couldn't save an image: \(error.localizedDescription)")
            }
            Task { @MainActor [weak self] in
                for hash in written { self?.pendingWrites[hash] = nil }
            }
        }
    }

    /// Memory only (the disk is left as it is).
    func retainInMemory(_ memory: Set<String>) {
        blobs = blobs.filter { memory.contains($0.key) }
        if thumbnails.keys.contains(where: { !memory.contains($0) }) {
            thumbnails = thumbnails.filter { memory.contains($0.key) }
        }
        guard usedScratch else { return }
        let prefixes = Set(memory.map { String($0.prefix(Self.scratchPrefix)) })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scratchFolder.path)) ?? []
        for name in names where !prefixes.contains(where: name.contains) {
            try? FileManager.default.removeItem(at: scratchFolder.appending(path: name))
        }
    }

    /// Deletes the saved PNGs (the history is no longer kept after quitting).
    func deleteFolder() {
        guard !folderIsGone else { return }
        folderIsGone = true
        onDisk = []
        pendingWrites = [:]
        let folder = folder
        disk.async { try? FileManager.default.removeItem(at: folder) }
    }

    /// Waits for the disk work queued so far (tests, and before reading the folder from outside).
    func flush() {
        disk.sync {}
    }

    /// What's on disk, listed once (names that are hashes only); kept up to date by `retain` afterwards.
    private func diskIndex() -> Set<String> {
        if let onDisk { return onDisk }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let index = Set(names.filter { $0.hasSuffix(".png") }.map { ($0 as NSString).deletingPathExtension })
        onDisk = index
        return index
    }

    private func url(for hash: String) -> URL {
        Self.url(for: hash, in: folder)
    }

    nonisolated private static func url(for hash: String, in folder: URL) -> URL {
        folder.appending(path: "\(hash).png")
    }

    nonisolated private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try data.write(to: url, options: [.atomic])
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var target = url
        try? target.setResourceValues(values)
    }

    nonisolated static func hash(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - A file to hand out

    /// Where Quick Look and a drag out get the image as a file: one PNG per image in a private temporary folder,
    /// each removed once its slip is gone, all of them when the section stops.
    var scratchFolder: URL {
        let tag = Self.hash(of: Data(folder.path.utf8)).prefix(8)
        return FileManager.default.temporaryDirectory.appending(path: "Altillo Clipboard \(tag)", directoryHint: .isDirectory)
    }

    private static let scratchPrefix = 10

    func scratchFile(for image: ClipboardImage) -> URL? {
        let url = scratchFolder.appending(path: "\(String(localized: "Image")) \(image.hash.prefix(Self.scratchPrefix)).png")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        guard let data = data(for: image) else { return nil }
        do {
            try FileManager.default.createDirectory(at: scratchFolder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try Self.write(data, to: url)
            usedScratch = true
            return url
        } catch {
            return nil
        }
    }

    func dropScratch() {
        try? FileManager.default.removeItem(at: scratchFolder)
    }

    // MARK: - Reading the words in it

    /// Most text kept from one image: enough to find it again, not a transcript of a scanned book.
    nonisolated static let maxRecognizedText = 4_000

    /// The lines of text in an image, top to bottom, read by Vision on this Mac (no network).
    nonisolated static func recognizeText(in png: Data) async -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        let lines = (try? await request.perform(on: png))?
            .compactMap { $0.topCandidates(1).first?.string } ?? []
        let text = lines.joined(separator: "\n")
        return text.count > maxRecognizedText ? String(text.prefix(maxRecognizedText)) : text
    }

    // MARK: - Thumbnails

    /// The slip's thumbnail, or nil while it's being made (the view updates when it's ready).
    func thumbnail(for image: ClipboardImage) -> NSImage? {
        if let thumbnail = thumbnails[image.hash] { return thumbnail }
        guard !making.contains(image.hash), let data = data(for: image) else { return nil }
        making.insert(image.hash)
        let hash = image.hash
        Task.detached(priority: .userInitiated) {
            let made = Self.makeThumbnail(data)
            await MainActor.run {
                self.making.remove(hash)
                guard let made, self.blobs[hash] != nil else { return }
                self.thumbnails[hash] = NSImage(cgImage: made, size: .zero)
            }
        }
        return nil
    }

    nonisolated private static func makeThumbnail(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
