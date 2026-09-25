import AltilloCore
import AppKit
import Foundation
import Observation

/// The Shortcuts section («Atajos»): the user's Shortcuts, favourites pinned as big tiles, one click to run.
///
/// The list comes from `/usr/bin/shortcuts list` off the main thread, is cached, and is refreshed each time the
/// section appears (never polled). Nothing runs without an explicit click (or an explicit request in Ask, which
/// goes through `run(_:input:)` too). Pins are the store's own defaults key.
@MainActor
@Observable
final class ShortcutsStore {
    enum Phase: Equatable {
        /// Nothing listed yet.
        case loading
        case ready
        /// `/usr/bin/shortcuts` isn't on this Mac.
        case missing
        /// Listing failed; the message says why.
        case failed(String)
    }

    enum RunState: Equatable, Sendable {
        case running
        case succeeded(output: String?)
        case failed(String)

        var isRunning: Bool { self == .running }
    }

    /// What a shortcut gets as its input, when the user picks "Run with …".
    enum Input: Equatable, Sendable {
        case text(String, label: String)
        case file(URL)

        /// "Clipboard text", "“Report.pdf”".
        var label: String {
            switch self {
            case let .text(_, label): label
            case let .file(url): "“\(url.lastPathComponent)”"
            }
        }
    }

    /// The last run the section talks about under the list.
    struct Outcome: Equatable {
        let shortcut: ShortcutInfo
        let state: RunState
        let at: Date
    }

    private(set) var shortcuts: [ShortcutInfo] = []
    private(set) var phase: Phase = .loading
    private(set) var isRefreshing = false
    /// Per shortcut: running, or how its last run went (cleared after a few seconds).
    private(set) var runs: [ShortcutInfo.ID: RunState] = [:]
    private(set) var lastOutcome: Outcome?
    /// Pinned shortcuts' ids (identifier, or name when there's none), in the order they were pinned.
    private(set) var pinnedIDs: [ShortcutInfo.ID]

    var query = ""
    var isSearchFocused = false

    /// Typing in the search field, or a search on screen: don't close under the user.
    var holdsOpen: Bool { isSearchFocused || !query.isEmpty }

    var pinned: [ShortcutInfo] {
        pinnedIDs.compactMap { id in shortcuts.first { $0.id == id } }
    }

    /// The list beside the tiles: every shortcut that isn't pinned, or every match of a search (pins included).
    var listed: [ShortcutInfo] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return shortcuts.filter { !pinnedIDs.contains($0.id) } }
        return shortcuts.filter { shortcut in
            let haystack = shortcut.name + " " + (shortcut.folder ?? "")
            return words.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }

    static let pinnedKey = "shortcutsPinned"
    static let maxPinned = 12

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let lister: @Sendable () async throws -> [ShortcutInfo]
    @ObservationIgnored private let runner: @Sendable ([String]) async throws -> ShortcutsCLI.Output
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var clearTasks: [ShortcutInfo.ID: Task<Void, Never>] = [:]

    /// Tests pass their own defaults, list and runner: nothing real is listed or run.
    init(
        defaults: UserDefaults = .standard,
        lister: @escaping @Sendable () async throws -> [ShortcutInfo] = { try await ShortcutsStore.listFromCLI() },
        runner: @escaping @Sendable ([String]) async throws -> ShortcutsCLI.Output = { try await ShortcutsCLI.execute($0) }
    ) {
        self.defaults = defaults
        self.lister = lister
        self.runner = runner
        pinnedIDs = (defaults.array(forKey: Self.pinnedKey) as? [String]) ?? []
    }

    // MARK: - Lifecycle

    /// Called when the section appears: shows the cached list at once and refreshes it in the background.
    func start() {
        refresh()
    }

    func stop() {
        query = ""
        isSearchFocused = false
    }

    /// Lists the shortcuts again (off the main thread). A refresh already on its way is reused.
    func refresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshTask = Task { [weak self] in
            await self?.load()
        }
    }

    /// Waits for the list (Ask uses it when the section hasn't been opened yet).
    func loadIfNeeded() async {
        if phase == .ready, !shortcuts.isEmpty { return }
        if let refreshTask { await refreshTask.value; return }
        await load()
    }

    private func load() async {
        defer {
            isRefreshing = false
            refreshTask = nil
        }
        do {
            let list = try await lister()
            shortcuts = list
            phase = .ready
            if Self.showsDemo, pinnedIDs.isEmpty { pinnedIDs = list.prefix(3).map(\.id) }
            SpikeLog.shared.record("shortcuts", "listed \(list.count) shortcuts")
        } catch ShortcutsCLI.Failure.missing {
            shortcuts = []
            phase = .missing
        } catch is CancellationError {
            return
        } catch {
            // Keep what was listed before: a hiccup shouldn't empty the section.
            if shortcuts.isEmpty { phase = .failed(Self.message(for: error)) }
            SpikeLog.shared.record("shortcuts", "list failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pins

    func isPinned(_ shortcut: ShortcutInfo) -> Bool { pinnedIDs.contains(shortcut.id) }

    var canPinMore: Bool { pinned.count < Self.maxPinned }

    @discardableResult
    func togglePin(_ shortcut: ShortcutInfo) -> Bool {
        if let index = pinnedIDs.firstIndex(of: shortcut.id) {
            pinnedIDs.remove(at: index)
        } else {
            guard canPinMore else { return false }
            pinnedIDs.append(shortcut.id)
        }
        if !Self.showsDemo { defaults.set(pinnedIDs, forKey: Self.pinnedKey) }
        return true
    }

    /// Moves a pin to another place among the pins.
    func movePin(_ shortcut: ShortcutInfo, before target: ShortcutInfo) {
        guard shortcut.id != target.id, let from = pinnedIDs.firstIndex(of: shortcut.id) else { return }
        pinnedIDs.remove(at: from)
        let to = pinnedIDs.firstIndex(of: target.id) ?? pinnedIDs.endIndex
        pinnedIDs.insert(shortcut.id, at: to)
        if !Self.showsDemo { defaults.set(pinnedIDs, forKey: Self.pinnedKey) }
    }

    // MARK: - Running

    /// Runs a shortcut the user clicked. A shortcut already running isn't started twice.
    func trigger(_ shortcut: ShortcutInfo, input: Input? = nil) {
        guard runs[shortcut.id] != .running else { return }
        Task { await run(shortcut, input: input) }
    }

    /// "Run with …" found nothing to hand over any more: say so instead of running without it.
    func reportMissingInput(for shortcut: ShortcutInfo) {
        lastOutcome = Outcome(shortcut: shortcut,
                              state: .failed(String(localized: "There's nothing to hand over any more, so it didn't run.")),
                              at: .now)
    }

    /// Runs it and waits for the result. Only ever called for an explicit click or an explicit request in Ask.
    @discardableResult
    func run(_ shortcut: ShortcutInfo, input: Input? = nil) async -> RunState {
        guard runs[shortcut.id] != .running else { return .running }
        clearTasks[shortcut.id]?.cancel()
        runs[shortcut.id] = .running
        lastOutcome = Outcome(shortcut: shortcut, state: .running, at: .now)

        var scratch: URL?
        var inputPath: URL?
        switch input {
        case let .text(text, _):
            do {
                let folder = FileManager.default.temporaryDirectory
                    .appendingPathComponent("altillo-shortcut-input-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let file = folder.appendingPathComponent("Input.txt")
                try Data(text.utf8).write(to: file, options: .atomic)
                scratch = folder
                inputPath = file
            } catch {
                return finish(shortcut, .failed(String(localized: "Couldn't prepare the input.")))
            }
        case let .file(url):
            inputPath = url
        case nil:
            break
        }
        defer { if let scratch { try? FileManager.default.removeItem(at: scratch) } }

        let arguments = ShortcutsCLI.runArguments(for: shortcut, inputPath: inputPath)
        SpikeLog.shared.record("shortcuts", "run: \(ShortcutsCLI.displayCommand(arguments))")
        let state: RunState
        do {
            let output = try await runner(arguments)
            if output.succeeded {
                let text = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                state = .succeeded(output: text.isEmpty ? nil : text)
            } else {
                state = .failed(ShortcutsCLI.failureMessage(output))
            }
        } catch ShortcutsCLI.Failure.missing {
            state = .failed(String(localized: "The Shortcuts command isn't on this Mac."))
        } catch ShortcutsCLI.Failure.timedOut {
            state = .failed(String(localized: "It took too long and was stopped."))
        } catch {
            state = .failed(error.localizedDescription)
        }
        return finish(shortcut, state)
    }

    private func finish(_ shortcut: ShortcutInfo, _ state: RunState) -> RunState {
        runs[shortcut.id] = state
        lastOutcome = Outcome(shortcut: shortcut, state: state, at: .now)
        let word = switch state {
        case .running: "running"
        case .succeeded: "done"
        case .failed: "failed"
        }
        SpikeLog.shared.record("shortcuts", "\(shortcut.name): \(word)")
        clearTasks[shortcut.id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.runs[shortcut.id] == state else { return }
            self.runs[shortcut.id] = nil
        }
        return state
    }

    // MARK: - Inputs on offer

    /// "Run with …" choices: the clipboard's text (judged from its types only, so nothing is read until the user
    /// picks it) and the shelf's selected item.
    static func inputOffers(shelfSelection: [ShelfItem], pasteboard: NSPasteboard = .general) -> [InputOffer] {
        var offers: [InputOffer] = []
        let types = pasteboard.types?.map(\.rawValue) ?? []
        if ClipboardPrivacy.decide(types: types, frontmostBundleID: nil) == .record,
           pasteboard.accessBehavior != .alwaysDeny {
            offers.append(.clipboard)
        }
        if shelfSelection.count == 1, let item = shelfSelection.first {
            offers.append(.shelf(item))
        }
        return offers
    }

    enum InputOffer: Equatable, Identifiable {
        case clipboard
        case shelf(ShelfItem)

        var id: String {
            switch self {
            case .clipboard: "clipboard"
            case let .shelf(item): item.id.uuidString
            }
        }

        var title: String {
            switch self {
            case .clipboard: String(localized: "Run with the Clipboard’s Text")
            case let .shelf(item): String(localized: "Run with “\(item.displayName)”")
            }
        }

        /// The input itself, read only now that the user picked it. Nil when there's nothing usable any more.
        @MainActor
        func resolve(pasteboard: NSPasteboard = .general) -> Input? {
            switch self {
            case .clipboard:
                let types = pasteboard.types?.map(\.rawValue) ?? []
                guard ClipboardPrivacy.decide(types: types, frontmostBundleID: nil) == .record,
                      let text = ClipboardPrivacy.keepable(pasteboard.string(forType: .string)) else { return nil }
                return .text(text, label: String(localized: "the clipboard’s text"))
            case let .shelf(item):
                switch item.kind {
                case let .file(url, _): return .file(url)
                case let .text(text): return .text(text, label: "“\(item.displayName)”")
                case let .link(url): return .text(url.absoluteString, label: "“\(item.displayName)”")
                }
            }
        }
    }

    // MARK: - Listing

    /// Every shortcut, each with its folder, straight from the CLI.
    nonisolated static func listFromCLI() async throws -> [ShortcutInfo] {
        let all = try await ShortcutsCLI.execute(ShortcutsCLI.listArguments(), timeout: .seconds(15))
        guard all.succeeded else { throw ListFailure(message: ShortcutsCLI.failureMessage(all)) }
        var shortcuts = ShortcutsCLI.parseList(all.standardOutput)
        // Folders are a nicety: a failure here just leaves them out.
        if let folders = try? await ShortcutsCLI.execute(ShortcutsCLI.listArguments(folders: true), timeout: .seconds(10)),
           folders.succeeded {
            for folder in ShortcutsCLI.parseList(folders.standardOutput) {
                guard let inside = try? await ShortcutsCLI.execute(
                    ShortcutsCLI.listArguments(folder: folder.identifier ?? folder.name), timeout: .seconds(10)
                ), inside.succeeded else { continue }
                let ids = Set(ShortcutsCLI.parseList(inside.standardOutput).map(\.id))
                for index in shortcuts.indices where ids.contains(shortcuts[index].id) {
                    shortcuts[index].folder = folder.name
                }
            }
        }
        return shortcuts
    }

    struct ListFailure: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static func message(for error: Error) -> String {
        (error as? ListFailure)?.message ?? error.localizedDescription
    }

    /// `-demoShortcuts YES`: pins the first three shortcuts in memory, for design reviews (nothing is saved).
    static let showsDemo = UserDefaults.standard.bool(forKey: "demoShortcuts")
}
