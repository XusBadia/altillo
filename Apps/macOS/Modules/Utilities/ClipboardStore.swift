import AltilloCore
import AppKit
import Foundation
import Observation

/// The clipboard section («Portapapeles»): the last things the user copied (texts, and files by reference) while
/// the section is on.
///
/// macOS has no pasteboard-changed notification, so it looks at `NSPasteboard.changeCount` (one integer, no
/// contents, never the privacy alert) every 0.75 s with a generous timer tolerance, **only while the Clipboard
/// section is enabled**; turning it off stops the timer and forgets everything. Contents are read only after the
/// types say it's text or file references that aren't marked private and don't come from a password manager
/// (`ClipboardPrivacy`); a copied file's contents are never read, only where it is. Everything lives in memory; surviving a relaunch is an opt-in (`keepsHistory`), saved by
/// `ClipboardArchive`. Nothing ever leaves the Mac.
@MainActor
@Observable
final class ClipboardStore {
    /// How often the pasteboard's change count is looked at, and how late the system may run the check to batch
    /// it with other wake-ups.
    static let interval: TimeInterval = 0.75
    static let tolerance: TimeInterval = 0.3

    private(set) var history = ClipboardHistory()
    /// The section is on and the pasteboard is being watched.
    private(set) var isWatching = false
    /// The user told macOS never to let Altillo read the clipboard (System Settings › Privacy & Security ›
    /// Paste from Other Apps).
    private(set) var isAccessDenied = false
    /// The slip just copied back, for the "Copied" moment. Cleared after a beat.
    private(set) var justCopied: ClipboardItem.ID?
    /// The last clear or deletion, which "Undo" puts back (while it's offered).
    private(set) var undoable: Undoable?

    struct Undoable: Equatable {
        enum Kind: Equatable { case clear, delete }
        let kind: Kind
        let snapshot: ClipboardHistory
    }

    // The section's own UI state, kept here so the notch knows when it must stay open.
    var query = ""
    var isSearchFocused = false
    /// The slip picked with ↑↓ (Return copies it).
    var selection: ClipboardItem.ID?

    /// Typing in the search field, or a search on screen: don't close under the user.
    var holdsOpen: Bool { isSearchFocused || !query.isEmpty }

    /// Slips for the current search, in the order the section shows them.
    var visibleItems: [ClipboardItem] { history.matching(query) }

    /// Keep the history after quitting (off by default). Stored in the store's own defaults key.
    var keepsHistory: Bool {
        didSet {
            guard keepsHistory != oldValue else { return }
            defaults.set(keepsHistory, forKey: Self.keepsHistoryKey)
            if keepsHistory { persist() } else { archive.delete() }
        }
    }

    static let keepsHistoryKey = "clipboardKeepsHistory"

    @ObservationIgnored private let pasteboard: NSPasteboard
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let archive: ClipboardArchive
    @ObservationIgnored private let frontmostBundleID: @MainActor () -> String?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastChangeCount = 0
    @ObservationIgnored private var ownChangeCount: Int?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private weak var settings: AltilloSettings?

    /// Tests pass a private pasteboard, their own defaults and a scratch archive: the user's are never touched.
    init(
        pasteboard: NSPasteboard = .general,
        defaults: UserDefaults = .standard,
        archive: ClipboardArchive = .standard,
        frontmostBundleID: @escaping @MainActor () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
    ) {
        self.pasteboard = pasteboard
        self.defaults = defaults
        self.archive = archive
        self.frontmostBundleID = frontmostBundleID
        keepsHistory = defaults.bool(forKey: Self.keepsHistoryKey)
        if Self.showsDemo { history = ClipboardHistory(items: ClipboardItem.samples()) }
    }

    // MARK: - Lifecycle

    /// Follows the Clipboard section: watching while it's enabled, nothing at all while it's off.
    func follow(_ settings: AltilloSettings) {
        self.settings = settings
        observeSettings()
    }

    private func observeSettings() {
        guard let settings else { return }
        let enabled = withObservationTracking {
            settings.isEnabled(.clipboard)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSettings() }
        }
        enabled ? start() : stop()
    }

    /// Starts watching. What's on the pasteboard already isn't read: only what's copied from now on.
    func start() {
        guard !isWatching else { return }
        isWatching = true
        if keepsHistory, history.isEmpty, let saved = archive.load() { history = saved }
        lastChangeCount = pasteboard.changeCount
        refreshAccess()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = Self.tolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DiagnosticLog.shared.record("clipboard", "watching (every \(Self.interval) s)")
    }

    /// Stops watching and forgets what's in memory (a saved history stays on disk if the user keeps one).
    func stop() {
        guard isWatching else { return }
        isWatching = false
        timer?.invalidate()
        timer = nil
        if keepsHistory { saveNow() }
        if !Self.showsDemo { history = ClipboardHistory() }
        undoable = nil
        query = ""
        selection = nil
        DiagnosticLog.shared.record("clipboard", "stopped watching")
    }

    // MARK: - Watching

    /// One tick: compares the change count and, only when it moved, looks at what arrived.
    func check() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        // Our own copy-back: already in the history, already on top.
        if count == ownChangeCount { return }
        let types = pasteboard.types?.map(\.rawValue) ?? []
        let frontmost = frontmostBundleID()
        let decision = ClipboardPrivacy.decide(types: types, frontmostBundleID: frontmost)
        switch decision {
        case .skipPrivate:
            DiagnosticLog.shared.record("clipboard", "skipped: private (marked, or from a password manager)")
            return
        case .skipNotText:
            return
        case .record, .recordFiles:
            break
        }
        refreshAccess()
        guard !isAccessDenied else { return }
        let source = types.contains(ClipboardPrivacy.sourceType)
            ? pasteboard.string(forType: .init(ClipboardPrivacy.sourceType)) : nil
        // An app may copy on a password manager's behalf and say so.
        guard !ClipboardPrivacy.isPasswordManager(source), let content = read(decision) else { return }
        let bundleID = source ?? frontmost
        history.record(content, at: .now, sourceBundleID: bundleID, sourceName: Self.appName(for: bundleID))
        changed()
    }

    /// What's on the pasteboard, as a slip: the text, or where the copied files are (never what's in them).
    private func read(_ decision: ClipboardPrivacy.Decision) -> ClipboardContent? {
        switch decision {
        case .record:
            let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: .URL)
            return ClipboardPrivacy.keepable(text).map(ClipboardContent.text)
        case .recordFiles:
            let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                               options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard !urls.isEmpty, urls.count <= ClipboardPrivacy.maxFiles else { return nil }
            // Copied again: the bookmarks the slip has are reused, so a repeat copy costs no disk work.
            let key = ClipboardContent.files(urls.map { ClipboardFile(url: $0, bookmarked: false) }).dedupeKey
            if let existing = history.items.first(where: { $0.content.dedupeKey == key }) { return existing.content }
            return .files(urls.enumerated().map { index, url in
                ClipboardFile(url: url, bookmarked: index < ClipboardPrivacy.maxBookmarkedFiles)
            })
        case .skipPrivate, .skipNotText:
            return nil
        }
    }

    private func refreshAccess() {
        let denied = pasteboard.accessBehavior == .alwaysDeny
        if denied != isAccessDenied { isAccessDenied = denied }
    }

    // MARK: - Actions

    /// Puts a slip back on the clipboard, with a short "Copied" moment. Says it came from Altillo. False when
    /// there's nothing left to copy (every file it points to is gone).
    @discardableResult
    func copy(_ item: ClipboardItem) -> Bool {
        switch item.content {
        case let .text(text):
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case let .files(files):
            let urls = files.compactMap { $0.resolvedURL() }
            guard !urls.isEmpty else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(urls as [NSURL])
            // Like Finder: the names as text too, so pasting into a text field gives them.
            pasteboard.setString(urls.map(\.lastPathComponent).joined(separator: "\n"), forType: .string)
        }
        if let id = Bundle.main.bundleIdentifier {
            pasteboard.setString(id, forType: .init(ClipboardPrivacy.sourceType))
        }
        ownChangeCount = pasteboard.changeCount
        lastChangeCount = pasteboard.changeCount
        history.touch(item.id)
        selection = item.id
        justCopied = item.id
        copiedReset?.cancel()
        copiedReset = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.justCopied = nil
        }
        changed()
        return true
    }

    func delete(_ item: ClipboardItem) {
        let before = history
        guard history.remove(item.id) != nil else { return }
        if selection == item.id { selection = nil }
        offerUndo(.delete, snapshot: before)
        changed()
    }

    @discardableResult
    func togglePin(_ item: ClipboardItem) -> Bool {
        let done = history.togglePin(item.id)
        if done { changed() }
        return done
    }

    func clear() {
        guard !history.recent.isEmpty else { return }
        let before = history
        history.clear()
        selection = nil
        offerUndo(.clear, snapshot: before)
        changed()
    }

    func undo() {
        guard let undoable else { return }
        history = undoable.snapshot
        self.undoable = nil
        undoExpiry?.cancel()
        changed()
    }

    private func offerUndo(_ kind: Undoable.Kind, snapshot: ClipboardHistory) {
        undoable = Undoable(kind: kind, snapshot: snapshot)
        undoExpiry?.cancel()
        undoExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.undoable = nil
        }
    }

    // MARK: - Keyboard

    /// ↑ / ↓ through the slips on screen (`offset` -1 / +1), starting from the top.
    func moveSelection(_ offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { selection = nil; return }
        guard let current = selection, let index = items.firstIndex(where: { $0.id == current }) else {
            selection = offset > 0 ? items.first?.id : items.last?.id
            return
        }
        selection = items[min(max(index + offset, 0), items.count - 1)].id
    }

    /// Return: copies the picked slip, or the first match of a search.
    @discardableResult
    func copySelection() -> ClipboardItem? {
        let items = visibleItems
        guard let item = items.first(where: { $0.id == selection }) ?? items.first, copy(item) else { return nil }
        return item
    }

    // MARK: - Saving

    private func changed() {
        guard keepsHistory else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func persist() {
        saveNow()
    }

    private func saveNow() {
        saveTask?.cancel()
        guard keepsHistory, !Self.showsDemo else { return }
        do {
            try archive.save(history)
        } catch {
            DiagnosticLog.shared.record("clipboard", "couldn't save the history: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    static func appName(for bundleID: String?) -> String? {
        guard let bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// `-demoClipboard YES`: sample slips for design reviews and screenshots, so the user's clipboard never
    /// has to be read (or written) to review the look.
    static let showsDemo = UserDefaults.standard.bool(forKey: "demoClipboard")
}

extension ClipboardItem {
    /// Design-review slips (`-demoClipboard YES`).
    static func samples(now: Date = .now) -> [ClipboardItem] {
        [
            ClipboardItem(text: "Meet at the café on Carrer de Verdi at 6, table by the window.",
                          copiedAt: now.addingTimeInterval(-40), sourceBundleID: "com.apple.MobileSMS",
                          sourceName: "Messages"),
            ClipboardItem(text: "https://github.com/xusbadia/altillo/pull/128",
                          copiedAt: now.addingTimeInterval(-4 * 60), sourceBundleID: "com.apple.Safari",
                          sourceName: "Safari"),
            ClipboardItem(text: "xcodebuild -project Altillo.xcodeproj -scheme Altillo \\\n  -derivedDataPath build/dd test",
                          copiedAt: now.addingTimeInterval(-22 * 60), sourceBundleID: "com.apple.Terminal",
                          sourceName: "Terminal"),
            ClipboardItem(text: "Tracking number 1Z 999 AA1 01 2345 6784 — arriving Thursday",
                          copiedAt: now.addingTimeInterval(-3 * 3_600), sourceBundleID: "com.apple.mail",
                          sourceName: "Mail", isPinned: true),
            ClipboardItem(text: "The attic keeps what you need close, and out of the way until you do.\nSecond draft.",
                          copiedAt: now.addingTimeInterval(-26 * 3_600), sourceBundleID: "com.apple.Notes",
                          sourceName: "Notes"),
        ]
    }
}
