import AppKit
import CryptoKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// A copied image, as a slip keeps it: its PNG lives in `ClipboardImages`, named by its hash; the history (and its
/// JSON) only holds this.
struct ClipboardImage: Codable, Hashable, Sendable {
    /// SHA-256 of the PNG, in hex: the blob's name and what tells two copies of the same image apart.
    var hash: String
    var width: Int
    var height: Int
    var byteCount: Int
}

/// The PNGs behind the image slips. In memory while the history is only in memory; also on disk, next to the
/// history's JSON (same privacy: 0600 files in a 0700 folder, out of backups), only while the user keeps the history
/// after quitting. What the history no longer points to is dropped from both at once (`retain`), so an image thrown
/// away, trimmed or cleared never stays behind.
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
    @ObservationIgnored private var making: Set<String> = []

    init(folder: URL) {
        self.folder = folder
    }

    // MARK: - Reading a copy

    /// The image a pasteboard holds, as PNG with its hash and size, or nil when there's none this history keeps
    /// (unreadable, or bigger than `maxBytes`). PNG is taken as is; anything else is converted once.
    static func read(from pasteboard: NSPasteboard) -> (ClipboardImage, Data)? {
        let data: Data
        if let png = pasteboard.data(forType: .png) {
            data = png
        } else if let other = pasteboard.data(forType: .tiff) ?? Self.firstImageData(on: pasteboard),
                  other.count <= maxBytes * 3,
                  let rep = NSBitmapImageRep(data: other),
                  let png = rep.representation(using: .png, properties: [:]) {
            data = png
        } else {
            return nil
        }
        return describe(data).map { ($0, data) }
    }

    private static let otherImageTypes: [NSPasteboard.PasteboardType] = [
        .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .init(UTType.gif.identifier),
        .init(UTType.webP.identifier), .init(UTType.bmp.identifier),
    ]

    private static func firstImageData(on pasteboard: NSPasteboard) -> Data? {
        for type in otherImageTypes {
            if let data = pasteboard.data(forType: type) { return data }
        }
        return nil
    }

    /// Hash and pixel size of a PNG; nil when it's too big or not an image.
    nonisolated static func describe(_ png: Data) -> ClipboardImage? {
        guard !png.isEmpty, png.count <= maxBytes,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0
        else { return nil }
        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
        return ClipboardImage(hash: hash, width: width, height: height, byteCount: png.count)
    }

    // MARK: - Keeping them

    func add(_ png: Data, for image: ClipboardImage) {
        blobs[image.hash] = png
    }

    /// The PNG, from memory or (a history kept after quitting) from disk; nil once it's gone.
    func data(for image: ClipboardImage) -> Data? {
        if let data = blobs[image.hash] { return data }
        guard let data = try? Data(contentsOf: url(for: image.hash)),
              Self.hash(of: data) == image.hash else { return nil }
        blobs[image.hash] = data
        return data
    }

    func has(_ image: ClipboardImage) -> Bool {
        blobs[image.hash] != nil || FileManager.default.fileExists(atPath: url(for: image.hash).path)
    }

    /// Keeps in memory only the images in `memory` (the history plus whatever Undo can still put back) and, when
    /// `disk` is given, writes those to disk and deletes every other file there; `disk` nil deletes the folder.
    func retain(memory: Set<String>, disk: Set<String>?) {
        retainInMemory(memory)
        guard let disk else {
            deleteFolder()
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names where !disk.contains((name as NSString).deletingPathExtension) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
            for hash in disk {
                let target = url(for: hash)
                guard !FileManager.default.fileExists(atPath: target.path), let data = blobs[hash] else { continue }
                try write(data, to: target)
            }
        } catch {
            DiagnosticLog.shared.record("clipboard", "couldn't save an image: \(error.localizedDescription)")
        }
    }

    /// Memory only (the disk is left as it is).
    func retainInMemory(_ memory: Set<String>) {
        blobs = blobs.filter { memory.contains($0.key) }
        if thumbnails.keys.contains(where: { !memory.contains($0) }) {
            thumbnails = thumbnails.filter { memory.contains($0.key) }
        }
        let prefixes = Set(memory.map { String($0.prefix(Self.scratchPrefix)) })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: scratchFolder.path)) ?? []
        for name in names where !prefixes.contains(where: name.contains) {
            try? FileManager.default.removeItem(at: scratchFolder.appending(path: name))
        }
    }

    func deleteFolder() {
        try? FileManager.default.removeItem(at: folder)
        dropScratch()
    }

    private func url(for hash: String) -> URL {
        folder.appending(path: "\(hash).png")
    }

    private func write(_ data: Data, to url: URL) throws {
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
    /// removed when the section stops (or the history is cleared of it).
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
            try write(data, to: url)
            return url
        } catch {
            return nil
        }
    }

    func dropScratch() {
        try? FileManager.default.removeItem(at: scratchFolder)
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
