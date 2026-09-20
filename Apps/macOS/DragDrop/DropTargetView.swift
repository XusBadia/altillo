import AltilloCore
import AppKit

/// Full-size view inside the notch panel that receives drops (files, file promises, URLs, text, images).
/// It wraps the SwiftUI hosting view, so the SwiftUI content must not register its own drop destinations.
final class DropTargetView: NSView {
    var onDragEntered: () -> Void = {}
    var onDragExited: () -> Void = {}
    /// Which drop zone is under a point (view coordinates). Nil means "not a drop target": the drag is refused there.
    var zoneAt: (NSPoint) -> DropZone? = { _ in .shelf }
    /// The zone under the dragged pointer changed (nil when it left every zone).
    var onZoneChanged: (DropZone?) -> Void = { _ in }
    /// Delivered on the main actor once every dropped item is ingested (file promises resolve asynchronously).
    var onDrop: ([ShelfItem]) -> Void = { _ in }
    /// Items dropped on the AirDrop zone, ingested the same way (promises become real files to send).
    var onAirDrop: ([ShelfItem]) -> Void = { _ in }
    /// Fired synchronously when a drop is accepted, before `onDrop` (which can take seconds with file promises).
    var onDropAccepted: () -> Void = {}

    var ingest = FileIngest.standard
    /// How long to wait for file promises before delivering whatever arrived.
    var promiseTimeout: Duration = .seconds(120)

    private var isTargeted = false
    private var currentZone: DropZone?

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "altillo.file-promises"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(DragPasteboard.droppableTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: - NSDraggingDestination

    override func wantsPeriodicDraggingUpdates() -> Bool { false }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        track(sender)
    }

    /// Follows the pointer across zones: only a zone under the pointer accepts (and lights up).
    private func track(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let zone = zone(for: sender)
        if zone != currentZone {
            currentZone = zone
            onZoneChanged(zone)
        }
        let operation = zone == nil ? [] : operation(for: sender)
        if operation != [], !isTargeted {
            isTargeted = true
            onDragEntered()
        }
        return operation
    }

    private func zone(for sender: any NSDraggingInfo) -> DropZone? {
        guard !isOwnDrag(sender) else { return nil }
        return zoneAt(convert(sender.draggingLocation, from: nil))
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        endTargeting()
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        endTargeting()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        zone(for: sender) != nil && operation(for: sender) != []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard !isOwnDrag(sender), let zone = zone(for: sender) else { return false }
        return receive(sender.draggingPasteboard, sourceMask: sender.draggingSourceOperationMask, zone: zone)
    }

    // MARK: - Receiving

    /// Reads the pasteboard, starts receiving promises (must happen during the drop) and ingests the rest off the main thread.
    @discardableResult
    func receive(_ pasteboard: NSPasteboard, sourceMask: NSDragOperation, zone: DropZone = .shelf) -> Bool {
        let start = ContinuousClock.now
        let payload = DropReader.read(from: pasteboard)
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        let types = pasteboard.types?.map(\.rawValue).joined(separator: ", ") ?? "—"
        SpikeLog.shared.record(SpikeLog.Category.drop,
                               "app activa: \(app) · máscara: \(sourceMask.logDescription) · leído: \(payload.summary) · tipos: \(types)")
        guard !payload.isEmpty else { return false }
        onDropAccepted()

        let promised = payload.promises.map { startReceiving($0) }
        let ingest = ingest
        let timeout = promiseTimeout
        Task { @MainActor [weak self] in
            var items = await Self.ingest(payload.items, with: ingest)
            if !promised.isEmpty {
                let promiseStart = ContinuousClock.now
                var files: [ShelfItem] = []
                for stream in promised {
                    files += await Self.collect(stream, timeout: timeout, ingest: ingest)
                }
                SpikeLog.shared.record(SpikeLog.Category.promise,
                                       "\(files.count) archivos de \(promised.count) promesas en \(Self.milliseconds(since: promiseStart))")
                items.insert(contentsOf: files, at: min(payload.promiseInsertionIndex, items.count))
            }
            SpikeLog.shared.record(SpikeLog.Category.drop,
                                   "entregados \(items.count) ítems en \(Self.milliseconds(since: start)) desde que se soltó")
            switch zone {
            case .shelf: self?.onDrop(items)
            case .airDrop: self?.onAirDrop(items)
            }
        }
        return true
    }

    private func endTargeting() {
        if currentZone != nil {
            currentZone = nil
            onZoneChanged(nil)
        }
        guard isTargeted else { return }
        isTargeted = false
        onDragExited()
    }

    private func isOwnDrag(_ sender: any NSDraggingInfo) -> Bool {
        sender.draggingSource != nil || DragDetector.isOwnDragInProgress
    }

    /// References show the plain arrow (generic); promises and data are copies, so they get the "+" badge.
    private func operation(for sender: any NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender), DragPasteboard.isDroppable(sender.draggingPasteboard.types) else { return [] }
        let types = sender.draggingPasteboard.types ?? []
        let isFileReference = types.contains(.fileURL) && !types.contains(where: DragPasteboard.promiseTypes.contains)
        let preferred: [NSDragOperation] = isFileReference ? [.generic, .copy, .link, .move] : [.copy, .generic, .link, .move]
        let mask = sender.draggingSourceOperationMask
        return preferred.first(where: mask.contains) ?? []
    }

    // MARK: - Ingest

    private struct PromiseOutcome: Sendable {
        let url: URL
        let error: String?
        let elapsed: Duration
    }

    private struct PromiseStream {
        let outcomes: AsyncStream<PromiseOutcome>
        let expected: Int
        let finish: @Sendable () -> Void
    }

    private func startReceiving(_ receiver: NSFilePromiseReceiver) -> PromiseStream {
        let names = receiver.fileNames
        let expected = max(names.count, 1)
        let (outcomes, continuation) = AsyncStream<PromiseOutcome>.makeStream()
        SpikeLog.shared.record(SpikeLog.Category.promise,
                               "recibiendo \(expected) archivo(s): \(names.joined(separator: ", ")) · tipos: \(receiver.fileTypes.joined(separator: ", "))")
        do {
            let directory = try ingest.makeSlotDirectory()
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: Self.promiseQueue,
                                          reader: Self.reader(
                                              continuation,
                                              start: .now,
                                              recoveryRoot: ingest.inboxRoot.deletingLastPathComponent()
                                                  .appending(path: "Recovery", directoryHint: .isDirectory)
                                          ))
        } catch {
            SpikeLog.shared.record(SpikeLog.Category.promise, "FALLO creando la carpeta del inbox: \(error.localizedDescription)")
            continuation.finish()
        }
        return PromiseStream(outcomes: outcomes, expected: expected, finish: { continuation.finish() })
    }

    /// Built outside the main actor: AppKit calls it on `promiseQueue`.
    private nonisolated static func reader(
        _ continuation: AsyncStream<PromiseOutcome>.Continuation,
        start: ContinuousClock.Instant,
        recoveryRoot: URL
    ) -> @Sendable (URL, (any Error)?) -> Void {
        { url, error in
            let elapsed = ContinuousClock.now - start
            let result = continuation.yield(PromiseOutcome(url: url, error: error?.localizedDescription, elapsed: elapsed))
            if case .terminated = result, error == nil {
                recoverLatePromise(at: url, under: recoveryRoot)
            }
            let logResult = error.map { "FALLO \($0.localizedDescription)" } ?? "ok"
            SpikeLog.post(SpikeLog.Category.promise, "\(url.lastPathComponent): \(logResult) en \(milliseconds(elapsed))")
        }
    }

    /// A provider may finish after the 120 s timeout. Keep that copy recoverable instead of leaking it in Inbox or
    /// deleting what might be the only exported representation.
    nonisolated static func recoverLatePromise(at url: URL, under recoveryRoot: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let slot = recoveryRoot.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: url, to: slot.appending(path: url.lastPathComponent))
            SpikeLog.post(SpikeLog.Category.promise, "promesa tardía apartada en Recuperación: \(url.lastPathComponent)")
        } catch {
            SpikeLog.post(SpikeLog.Category.promise, "FALLO apartando promesa tardía: \(error.localizedDescription)")
        }
    }

    private static func collect(_ stream: PromiseStream, timeout: Duration, ingest: FileIngest) async -> [ShelfItem] {
        let timer = Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            stream.finish()
        }
        defer {
            timer.cancel()
            stream.finish()
        }

        var items: [ShelfItem] = []
        var received = 0
        for await outcome in stream.outcomes {
            received += 1
            if outcome.error == nil, FileManager.default.fileExists(atPath: outcome.url.path) {
                items.append(ingest.item(forReceivedFile: outcome.url))
                SpikeLog.shared.record(SpikeLog.Category.ingest, "copia (promesa) → \(outcome.url.path)")
            }
            if received >= stream.expected { break }
        }
        if received < stream.expected {
            SpikeLog.shared.record(SpikeLog.Category.promise,
                                   "FALLO: timeout de \(timeout) con \(received)/\(stream.expected) archivos; se entrega lo recibido")
        }
        return items
    }

    /// Files, links, images and text, in order. File copies and image encoding run off the main thread.
    private static func ingest(_ incoming: [IncomingDrop], with ingest: FileIngest) async -> [ShelfItem] {
        guard !incoming.isEmpty else { return [] }
        let results = await Task.detached(priority: .userInitiated) {
            incoming.map { entry in Self.ingestOne(entry, with: ingest) }
        }.value
        var items: [ShelfItem] = []
        for (item, message) in results {
            SpikeLog.shared.record(SpikeLog.Category.ingest, message)
            if let item { items.append(item) }
        }
        return items
    }

    private nonisolated static func ingestOne(_ entry: IncomingDrop, with ingest: FileIngest) -> (ShelfItem?, String) {
        do {
            switch entry {
            case let .file(url):
                let start = ContinuousClock.now
                let (item, decision) = try ingest.ingest(fileAt: url)
                switch decision {
                case .reference:
                    return (item, "referencia → \(url.path)")
                case let .copy(reason):
                    return (item, "copia (\(reason)) en \(milliseconds(since: start)) → \(item.fileURL?.path ?? "?") · original: \(url.path)")
                }
            case let .link(url, title):
                let item = ShelfItem(kind: .link(url), displayName: title ?? linkName(url))
                return (item, "enlace → \(url.absoluteString)")
            case let .image(data, type, suggestedName):
                let bytes = try pngIfNeeded(data, type: type)
                let item = try ingest.ingest(data: bytes, suggestedName: suggestedName)
                return (item, "copia (imagen sin archivo, \(type), \(bytes.count) bytes) → \(item.fileURL?.path ?? "?")")
            case let .text(text):
                let item = ShelfItem(kind: .text(text), displayName: textName(text))
                return (item, "texto (\(text.count) caracteres)")
            }
        } catch {
            return (nil, "FALLO \(entry.logLabel): \(error.localizedDescription)")
        }
    }

    private nonisolated static func pngIfNeeded(_ data: Data, type: String) throws -> Data {
        guard type == NSPasteboard.PasteboardType.tiff.rawValue else { return data }
        guard let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return png
    }

    nonisolated static func linkName(_ url: URL) -> String {
        let host = url.host() ?? url.absoluteString
        let path = url.path()
        return path.isEmpty || path == "/" ? host : host + path
    }

    nonisolated static func textName(_ text: String) -> String {
        let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 60 ? String(trimmed.prefix(59)) + "…" : trimmed
    }

    nonisolated static func milliseconds(since start: ContinuousClock.Instant) -> String {
        milliseconds(ContinuousClock.now - start)
    }

    nonisolated static func milliseconds(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
        return "\(Int(ms.rounded())) ms"
    }
}

private extension IncomingDrop {
    var logLabel: String {
        switch self {
        case let .file(url): "archivo \(url.path)"
        case let .link(url, _): "enlace \(url.absoluteString)"
        case let .image(_, type, _): "imagen \(type)"
        case .text: "texto"
        }
    }
}

extension NSDragOperation {
    /// "copy+move+generic" for the log.
    var logDescription: String {
        if self == [] { return "none" }
        let names: [(NSDragOperation, String)] = [
            (.copy, "copy"), (.link, "link"), (.generic, "generic"), (.private, "private"), (.move, "move"), (.delete, "delete"),
        ]
        let parts = names.filter { contains($0.0) }.map(\.1)
        return parts.isEmpty ? "raw(\(rawValue))" : parts.joined(separator: "+")
    }
}
