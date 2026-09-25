import AppKit
import Foundation
import Observation

/// The «Nota» section (phase 12): one paper note that saves as you type, plus the last few notes put away with
/// "New note".
///
/// Plain text in Application Support (`Altillo/note.txt`, the history beside it in `notes-history.json`), written
/// a moment after the last keystroke (debounced) and at once when the section goes away or Altillo quits. Nothing
/// runs at rest: the only task is the pending save, and only while there's something to save.
@MainActor
@Observable
final class NoteStore {
    /// A note put away with "New note".
    struct Archived: Identifiable, Codable, Equatable, Sendable {
        var id = UUID()
        var text: String
        var archivedAt: Date
    }

    /// What Ask added last, so the notch can take it back.
    struct AskAppend: Equatable, Sendable {
        var previousText: String
        var added: String
    }

    /// Notes kept in the history.
    static let historyLimit = 5
    /// How long typing has to pause before the note is written.
    static let defaultSaveDelay: Duration = .milliseconds(600)

    /// The note. Setting it (typing) schedules a save.
    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            // Typing after a clear or after Ask's line makes those undo buttons stale.
            if !text.isEmpty { clearedText = nil }
            if let askAppend, text != askAppend.resultingText {
                self.askAppend = nil
            }
            scheduleSave()
        }
    }
    /// Newest first, at most `historyLimit`.
    private(set) var history: [Archived] = []
    /// What "Clear" took away, until the user types again: "Undo" puts it back.
    private(set) var clearedText: String?
    private(set) var askAppend: AskAppend?
    /// Set by the view from its `@FocusState`: typing keeps the notch open.
    var isEditing = false

    /// While the user types in the note, the notch doesn't close when the pointer wanders off.
    var holdsOpen: Bool { isEditing }

    @ObservationIgnored let noteURL: URL?
    @ObservationIgnored let historyURL: URL?
    @ObservationIgnored var saveDelay: Duration
    @ObservationIgnored var now: () -> Date = { .now }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var didLoad = false
    @ObservationIgnored private var users = 0
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    /// Writes that reached the disk (tests read it to check the debounce).
    @ObservationIgnored private(set) var saveCount = 0

    init(
        folder: URL? = URL.applicationSupportDirectory.appending(path: "Altillo", directoryHint: .isDirectory),
        saveDelay: Duration = NoteStore.defaultSaveDelay
    ) {
        noteURL = folder?.appending(path: "note.txt")
        historyURL = folder?.appending(path: "notes-history.json")
        self.saveDelay = saveDelay
    }

    // MARK: - Lifecycle

    /// Reference counted like the other stores (SwiftUI inserts the new view before removing the old one).
    func start() {
        users += 1
        load()
        guard terminationObserver == nil else { return }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.flush() } }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        isEditing = false
        flush()
    }

    /// Reads the note and its history once (Ask may need them before the section is ever opened).
    func load() {
        guard !didLoad else { return }
        didLoad = true
        if let noteURL, let stored = try? String(contentsOf: noteURL, encoding: .utf8) {
            // Straight into storage: loading isn't typing, nothing to save.
            withoutSaving { text = stored }
        }
        if let historyURL, let data = try? Data(contentsOf: historyURL),
           let stored = try? JSONDecoder().decode([Archived].self, from: data) {
            history = Array(stored.prefix(Self.historyLimit))
        }
    }

    // MARK: - Acting

    /// Empties the note; "Undo" brings it back until the user types again.
    func clear() {
        guard !text.isEmpty else { return }
        let old = text
        text = ""
        clearedText = old
        askAppend = nil
    }

    func undoClear() {
        guard let clearedText, text.isEmpty else { return }
        text = clearedText
        self.clearedText = nil
    }

    /// Puts the current note away in the history and starts a blank one.
    func newNote() {
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty else { return }
        archive(text)
        text = ""
        clearedText = nil
        askAppend = nil
        saveNow()
    }

    /// Brings a note back from the history; the current one (if any) takes its place there.
    func restore(_ id: Archived.ID) {
        guard let index = history.firstIndex(where: { $0.id == id }) else { return }
        let item = history.remove(at: index)
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { archive(text) }
        text = item.text
        clearedText = nil
        askAppend = nil
        saveNow()
    }

    func deleteFromHistory(_ id: Archived.ID) {
        history.removeAll { $0.id == id }
        saveNow()
    }

    /// Adds a line at the end (Ask's "apunta …"), saved at once. Returns the line as written.
    @discardableResult
    func append(_ line: String, fromAsk: Bool = false) -> String {
        load()
        let clean = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let previous = text
        let append = AskAppend(previousText: previous, added: clean)
        text = append.resultingText
        askAppend = fromAsk ? append : nil
        clearedText = nil
        saveNow()
        return clean
    }

    /// Takes Ask's last line back out, if the note hasn't changed since.
    func undoAskAppend() {
        guard let askAppend else { return }
        text = askAppend.previousText
        self.askAppend = nil
        saveNow()
    }

    /// Ask's line stays: no more "Undo".
    func keepAskAppend() {
        askAppend = nil
    }

    // MARK: - Saving

    @ObservationIgnored private var suppressesSave = false

    private func withoutSaving(_ change: () -> Void) {
        suppressesSave = true
        change()
        suppressesSave = false
    }

    private func scheduleSave() {
        guard !suppressesSave else { return }
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes a pending save now (the section went away, Altillo quits).
    func flush() {
        guard saveTask != nil else { return }
        saveNow()
    }

    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        guard let noteURL else { return }
        do {
            try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: noteURL, options: .atomic)
            if let historyURL {
                try JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
            }
            saveCount += 1
        } catch {
            SpikeLog.shared.record("utilities", "note: couldn't save (\(error.localizedDescription))")
        }
    }

    private func archive(_ note: String) {
        history.insert(Archived(text: note, archivedAt: now()), at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
    }
}

extension NoteStore.AskAppend {
    /// A new line goes on a line of its own.
    func addedSeparator(for previous: String) -> String {
        previous.isEmpty || previous.hasSuffix("\n") ? "" : "\n"
    }

    /// The note right after the line went in.
    var resultingText: String { previousText + addedSeparator(for: previousText) + added }
}

extension NoteStore.Archived {
    /// The first line, for the history menu.
    var title: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 40 ? String(trimmed.prefix(39)) + "…" : trimmed
    }
}
