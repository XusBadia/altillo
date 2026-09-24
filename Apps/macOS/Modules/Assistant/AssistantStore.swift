import AltilloCore
import AppKit
import EventKit
import Foundation
import FoundationModels
import Observation

/// What the assistant can reach in the rest of Altillo. Wired by `NotchCoordinator`.
@MainActor
struct AssistantContext {
    /// Everything on the shelf right now, oldest first.
    var shelfItems: () -> [ShelfItem] = { [] }
    /// Puts an answer (or anything else) on the shelf, with the landing.
    var addToShelf: ([ShelfItem]) -> Void = { _ in }
    /// Shows a peek while the notch is closed ("the answer is ready").
    var postAlert: (NotchAlert) -> Void = { _ in }
    /// True while the open notch is showing the assistant (so a finished answer doesn't need an alert).
    var isVisible: () -> Bool = { false }
    /// Whether the user lets Ask search the web on its own (Settings ▸ Behaviour ▸ Ask). Off by default.
    var webSearchAllowed: () -> Bool = { AltilloSettings.shared.assistantWebSearch }
    /// "Always allow" under an answer: turns web lookups on for good.
    var allowWebSearch: () -> Void = { AltilloSettings.shared.assistantWebSearch = true }
    /// Opens a web page in the default browser (a source, or the question as a search).
    var openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }
}

/// The «Ask» section: a small on-device assistant (Apple Intelligence, Foundation Models) that can look at
/// Altillo's own context through tools — the shelf, today's calendar, what's playing, the clipboard.
///
/// Private by construction: the model runs on this Mac, the conversation lives only in memory (a new conversation,
/// or quitting, forgets it) and nothing is ever written to disk. The web is only reached when the user allows it:
/// for good in Settings, or for one question at a time from the offer under an answer that needed it. Nothing runs
/// at idle either: a session is made and prewarmed the first time the section appears, and availability is
/// re-checked on every appearance and when the system says it changed, never on a timer.
///
/// `start()` / `stop()` are reference counted like the other stores, because SwiftUI inserts the new view before it
/// removes the old one. An answer on its way keeps going when the notch closes; if it finishes unseen, a peek says so.
@MainActor
@Observable
final class AssistantStore {
    enum Availability: Equatable, Sendable {
        /// Not checked yet (the section hasn't been opened).
        case unknown
        case available
        case deviceNotEligible
        case appleIntelligenceOff
        /// Downloading or otherwise getting ready.
        case modelNotReady

        init(_ availability: SystemLanguageModel.Availability) {
            switch availability {
            case .available: self = .available
            case .unavailable(.deviceNotEligible): self = .deviceNotEligible
            case .unavailable(.appleIntelligenceNotEnabled): self = .appleIntelligenceOff
            case .unavailable(.modelNotReady): self = .modelNotReady
            case .unavailable: self = .modelNotReady
            }
        }
    }

    /// One question and its answer.
    struct Exchange: Identifiable, Equatable, Sendable {
        enum Status: Equatable, Sendable {
            /// Asked; nothing written back yet (a tool may be running).
            case thinking
            /// Words are arriving.
            case answering
            case done
            /// The user pressed stop; whatever arrived stays.
            case stopped
            case failed(AssistantFailure)
        }

        let id: UUID
        var question: String
        var answer = ""
        var status: Status = .thinking
        /// Tools it used, in order, for the little "from your calendar" marks.
        var sources: [AssistantActivity] = []
        /// Pages the answer drew on when it searched the web, for the globe mark.
        var webSources: [AssistantWebSource] = []
        /// The answer needed something live and web lookups are off: offer to search for this one question.
        var offersWeb = false

        init(id: UUID = UUID(), question: String, answer: String = "", status: Status = .thinking,
             sources: [AssistantActivity] = [], webSources: [AssistantWebSource] = [], offersWeb: Bool = false) {
            self.id = id
            self.question = question
            self.answer = answer
            self.status = status
            self.sources = sources
            self.webSources = webSources
            self.offersWeb = offersWeb
        }

        var usedWeb: Bool { sources.contains(.web) }

        var isFinished: Bool {
            switch status {
            case .thinking, .answering: false
            case .done, .stopped, .failed: true
            }
        }

        /// There's an answer worth copying or putting on the shelf.
        var hasAnswer: Bool {
            isFinished && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var context = AssistantContext()
    private(set) var availability: Availability = .unknown
    /// The current conversation only. Memory, never disk.
    private(set) var exchanges: [Exchange] = []
    /// The tool running right now, if any.
    private(set) var activity: AssistantActivity?
    /// Chips for the empty state, rebuilt each time the section appears.
    private(set) var suggestions: [AssistantSuggestion] = AssistantSuggestion.make(.init())
    /// An answer is being written (or a tool is running for it).
    private(set) var isResponding = false
    /// What's typed in the prompt field.
    var draft = ""
    /// Set by the view from its `@FocusState`.
    var isFieldFocused = false

    /// Typing, a draft, or an answer on its way: the notch must not close under the user.
    var holdsOpen: Bool { Self.holdsOpen(isFieldFocused: isFieldFocused, draft: draft, isResponding: isResponding) }

    nonisolated static func holdsOpen(isFieldFocused: Bool, draft: String, isResponding: Bool) -> Bool {
        isFieldFocused || isResponding || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Bumped to move keyboard focus to the prompt field (the shortcut summoned the assistant).
    private(set) var focusRequest = 0
    /// The last request the view acted on, so one made while the view wasn't there is honoured on appear.
    @ObservationIgnored private var handledFocusRequest = 0

    /// A chat session made and prewarmed ahead of the first question. Every question gets a session of its own
    /// (with the tools its route needs and a recap of the last exchanges), so this only speeds up the first one.
    @ObservationIgnored private var prewarmed: LanguageModelSession?
    @ObservationIgnored private var prewarmedAt: Date?
    @ObservationIgnored private var responseTask: Task<Void, Never>?
    @ObservationIgnored private var respondingTo: UUID?
    @ObservationIgnored private var viewers = 0

    // MARK: - Lifecycle

    /// Called by the view when the section appears.
    func start() {
        viewers += 1
        guard viewers == 1 else { return }
        refreshAvailability()
        observeAvailability()
        refreshSuggestions()
    }

    /// Called by the view when the section goes away. An answer on its way is not cancelled: it finishes and
    /// announces itself with a peek.
    func stop() {
        viewers = max(0, viewers - 1)
    }

    func requestFocus() { focusRequest += 1 }

    /// True once per focus request; the view moves focus to the field when it gets one.
    func takeFocusRequest() -> Bool {
        guard focusRequest != handledFocusRequest else { return false }
        handledFocusRequest = focusRequest
        return true
    }

    private func refreshAvailability() {
        let now = Availability(SystemLanguageModel.default.availability)
        if now != availability {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "availability \(availability) → \(now)")
            availability = now
        }
        prepareSession()
    }

    /// Makes (and prewarms) a chat session ahead of the first question, remade when it has aged so the date and
    /// time in its instructions stay right.
    private func prepareSession() {
        guard availability == .available, !isResponding, exchanges.isEmpty else { return }
        let isStale = prewarmedAt.map { Date.now.timeIntervalSince($0) > 10 * 60 } ?? true
        guard prewarmed == nil || isStale else { return }
        let fresh = makeSession(route: .chat, recap: nil)
        fresh.prewarm()
        prewarmed = fresh
        prewarmedAt = .now
    }

    /// `SystemLanguageModel` is observable: when Apple Intelligence is switched on or finishes downloading, this
    /// fires and the section comes alive without polling. Re-armed after every change while visible.
    private func observeAvailability() {
        withObservationTracking {
            _ = SystemLanguageModel.default.availability
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.viewers > 0 else { return }
                self.refreshAvailability()
                self.observeAvailability()
            }
        }
    }

    /// Rebuilds the chips from what's there right now: cheap checks only (authorization status, running apps,
    /// pasteboard types, shelf names), nothing read.
    func refreshSuggestions() {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let signals = AssistantSuggestion.Signals(
            calendarGranted: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
            readableShelfItem: AssistantSuggestion.readableItem(in: context.shelfItems())?.displayName,
            runningPlayer: MusicPlayer.allCases.first { open.contains($0.bundleID) }?.appName,
            clipboardHasText: AssistantContent.clipboardHasText()
        )
        suggestions = AssistantSuggestion.make(signals)
    }

    // MARK: - Asking

    /// Sends `text`, or the draft when nil.
    func send(_ text: String? = nil) {
        let question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isResponding else { return }
        availability = Availability(SystemLanguageModel.default.availability)
        guard availability == .available else { return }
        if text == nil { draft = "" }

        let exchange = Exchange(question: question)
        exchanges.append(exchange)
        isResponding = true
        respondingTo = exchange.id
        activity = nil
        SpikeLog.shared.record(SpikeLog.Category.assistant, "ask (\(question.count) chars)")
        responseTask = Task { [weak self] in
            await self?.respond(to: question, exchange: exchange.id)
        }
    }

    /// Stops the answer being written. What already arrived stays.
    func cancel() {
        guard isResponding else { return }
        responseTask?.cancel()
        SpikeLog.shared.record(SpikeLog.Category.assistant, "stop")
    }

    /// Forgets the conversation and starts over.
    func newConversation() {
        responseTask?.cancel()
        responseTask = nil
        respondingTo = nil
        isResponding = false
        activity = nil
        exchanges = []
        prewarmed = nil
        refreshAvailability()
        refreshSuggestions()
        SpikeLog.shared.record(SpikeLog.Category.assistant, "new conversation")
    }

    /// Copies an answer as plain text.
    func copy(_ exchange: Exchange) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AssistantFormat.plainText(exchange.answer), forType: .string)
    }

    /// "Search the web" under an answer that needed it: the user's consent for this one question. Looks it up and
    /// answers again in place.
    func searchWeb(for exchange: Exchange) {
        guard !isResponding, exchanges.last?.id == exchange.id else { return }
        availability = Availability(SystemLanguageModel.default.availability)
        guard availability == .available else { return }
        isResponding = true
        respondingTo = exchange.id
        activity = nil
        update(exchange.id) {
            $0.offersWeb = false
            $0.sources = []
            $0.webSources = []
        }
        SpikeLog.shared.record(SpikeLog.Category.assistant, "web search allowed for one question")
        let question = exchange.question
        responseTask = Task { [weak self] in
            await self?.respondFromWeb(to: question, exchange: exchange.id)
        }
    }

    /// "Always allow": web lookups on for good (the Settings toggle), and this question searched right away.
    func alwaysAllowWeb(for exchange: Exchange) {
        context.allowWebSearch()
        SpikeLog.shared.record(SpikeLog.Category.assistant, "web search always allowed")
        searchWeb(for: exchange)
    }

    /// "Open in browser": the question as a DuckDuckGo search in the default browser. Nothing is sent from here.
    func openInBrowser(_ exchange: Exchange) {
        guard let url = AssistantWeb.browserSearchURL(exchange.question) else { return }
        update(exchange.id) { $0.offersWeb = false }
        context.openURL(url)
    }

    func open(_ source: AssistantWebSource) {
        context.openURL(source.url)
    }

    /// Puts an answer on the shelf as a note, so it can be dragged out anywhere.
    func putUp(_ exchange: Exchange) {
        let text = AssistantFormat.plainText(exchange.answer)
        guard !text.isEmpty else { return }
        context.addToShelf([ShelfItem(kind: .text(text), displayName: AssistantFormat.shelfName(question: exchange.question))])
        SpikeLog.shared.record(SpikeLog.Category.assistant, "answer put up on the shelf")
    }

    // MARK: - Answering

    /// Routes the question (`AssistantRouter`), then answers it: from the model alone, with the local tools, or
    /// from web results when it's about something live and the user allows the web.
    private func respond(to question: String, exchange id: UUID) async {
        let followsContext = exchanges.last(where: { $0.id != id && $0.isFinished })?.sources
            .contains(where: \.isLocalContext) ?? false
        let route = AssistantRouter.route(question, followsContext: followsContext)
        let webAllowed = context.webSearchAllowed()
        SpikeLog.shared.record(SpikeLog.Category.assistant, "route \(route.rawValue)")
        if route == .live && webAllowed {
            await respondFromWeb(to: question, exchange: id)
            return
        }

        var prompt = route == .live
            ? AssistantInstructions.prompt(forOfflineLive: question)
            : AssistantInstructions.prompt(for: question)
        if let hint = AssistantCalculator.hint(for: question) {
            prompt += "\n\n(Exact result: \(hint))"
            noteActivity(.calculator)
        }
        // Without the web, a live question is a chat one that knows it can't check.
        let sessionRoute: AssistantRoute = route == .live ? .chat : route
        do {
            try await answer(prompt, route: sessionRoute, into: id)
        } catch {
            finish(id, error: Task.isCancelled ? CancellationError() : error)
            return
        }
        // Web lookups are allowed and the model says it can't know: look it up for it.
        if !Task.isCancelled, webAllowed,
           let exchange = exchanges.first(where: { $0.id == id }), !exchange.usedWeb,
           AssistantLiveness.answerAdmitsNotKnowing(AssistantFormat.plainText(exchange.answer)) {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "the model can't know: looking it up")
            await respondFromWeb(to: question, exchange: id)
            return
        }
        finish(id, error: Task.isCancelled ? CancellationError() : nil)
    }

    /// Searches the web for the question itself and answers from the results. The search is Altillo's, not the
    /// model's: handed a `web` tool, the small model searched for translations and haikus, and searched the same
    /// words again and again until its context overflowed.
    private func respondFromWeb(to question: String, exchange id: UUID) async {
        update(id) {
            $0.answer = ""
            $0.status = .thinking
        }
        noteActivity(.web)
        let lookup = await AssistantWeb.lookUp(question)
        guard !Task.isCancelled else {
            finish(id, error: CancellationError())
            return
        }
        noteWebSources(lookup.sources)
        SpikeLog.shared.record(
            SpikeLog.Category.assistant, "web lookup → \(lookup.backend.rawValue), \(lookup.text.count) chars"
        )
        do {
            try await answer(AssistantInstructions.prompt(for: question, webResults: lookup.text), route: .live, into: id)
        } catch {
            finish(id, error: Task.isCancelled ? CancellationError() : error)
            return
        }
        finish(id, error: Task.isCancelled ? CancellationError() : nil)
    }

    /// One answer in a session of its own. When the small window overflows, or the model trips over itself (it
    /// sometimes fails right after a tool call), it tries once more in a fresh session without the recap.
    private func answer(_ prompt: String, route: AssistantRoute, into id: UUID) async throws {
        let session = takePrewarmed(for: route, excluding: id) ?? makeSession(route: route, recap: recap(excluding: id))
        do {
            try await stream(prompt, in: session, into: id)
        } catch let error where [.contextFull, .other].contains(AssistantFailure(error)) && !Task.isCancelled {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "\(AssistantFailure(error)): retrying in a fresh session")
            update(id) {
                $0.answer = ""
                $0.status = .thinking
            }
            try await stream(prompt, in: makeSession(route: route, recap: nil), into: id)
        }
    }

    private func stream(_ prompt: String, in session: LanguageModelSession, into id: UUID) async throws {
        for try await snapshot in session.streamResponse(to: prompt) {
            try Task.checkCancellation()
            activity = nil
            update(id) {
                $0.answer = snapshot.content
                $0.status = .answering
            }
        }
    }

    private func finish(_ id: UUID, error: (any Error)?) {
        // A conversation thrown away mid-answer: its late ending must not touch the new one.
        guard respondingTo == id else { return }
        responseTask = nil
        respondingTo = nil
        isResponding = false
        activity = nil
        guard let index = exchanges.firstIndex(where: { $0.id == id }) else { return }

        switch error {
        case nil:
            exchanges[index].status = .done
            let exchange = exchanges[index]
            exchanges[index].offersWeb = !context.webSearchAllowed() && !exchange.usedWeb
                && AssistantLiveness.shouldOffer(
                    question: exchange.question,
                    answer: AssistantFormat.plainText(exchange.answer),
                    usedLocalTools: exchange.sources.contains(where: \.isLocalContext)
                )
            SpikeLog.shared.record(SpikeLog.Category.assistant, "answered (\(exchanges[index].answer.count) chars)")
        case is CancellationError:
            exchanges[index].status = .stopped
            return
        case let error?:
            let failure = AssistantFailure(error)
            exchanges[index].status = .failed(failure)
            SpikeLog.shared.record(SpikeLog.Category.assistant, "failed: \(failure) — \(error)")
        }

        guard !context.isVisible() else { return }
        let exchange = exchanges[index]
        let title = exchange.hasAnswer && error == nil
            ? AssistantFormat.peekTitle(exchange.answer)
            : String(localized: "I couldn't answer")
        context.postAlert(NotchAlert(source: .assistant, symbol: "sparkle", title: title, module: .assistant))
    }

    private func update(_ id: UUID, _ change: (inout Exchange) -> Void) {
        guard let index = exchanges.firstIndex(where: { $0.id == id }) else { return }
        change(&exchanges[index])
    }

    // MARK: - Sessions

    /// The prewarmed chat session, for the first question of a conversation when it's a chat one.
    private func takePrewarmed(for route: AssistantRoute, excluding id: UUID) -> LanguageModelSession? {
        guard route == .chat, let session = prewarmed, !session.isResponding,
              !exchanges.contains(where: { $0.id != id })
        else { return nil }
        prewarmed = nil
        return session
    }

    private func recap(excluding id: UUID) -> String {
        let earlier = exchanges
            .filter { $0.id != id && $0.hasAnswer }
            .map { (question: $0.question, answer: AssistantFormat.plainText($0.answer)) }
        return AssistantInstructions.recap(earlier)
    }

    private func makeSession(route: AssistantRoute, recap: String?) -> LanguageModelSession {
        let tools = AssistantTools.all(
            for: route,
            shelfItems: { [weak self] in self?.context.shelfItems() ?? [] },
            report: { [weak self] activity in self?.noteActivity(activity) }
        )
        return LanguageModelSession(
            model: .default,
            tools: tools,
            instructions: AssistantInstructions.text(recap: recap, route: route)
        )
    }

    private func noteActivity(_ activity: AssistantActivity) {
        self.activity = activity
        guard let id = respondingTo else { return }
        update(id) { exchange in
            if !exchange.sources.contains(activity) { exchange.sources.append(activity) }
        }
    }

    private func noteWebSources(_ sources: [AssistantWebSource]) {
        guard let id = respondingTo else { return }
        update(id) { exchange in
            for source in sources where !exchange.webSources.contains(source) && exchange.webSources.count < 5 {
                exchange.webSources.append(source)
            }
        }
    }
}

// MARK: - Sample data

extension AssistantStore.Exchange {
    /// Shown in the `openAssistant` design scenario when there's no real conversation to draw.
    static let sample = AssistantStore.Exchange(
        question: String(localized: "What do I have today, and what did I copy last?"),
        answer: String(localized: """
        You have **Notch design with Marta** at 10:30 and the **weekly review** at 17:00; the evening is free.
        You copied a tracking number for a parcel arriving on Thursday.
        """),
        status: .done,
        sources: [.calendar, .clipboard]
    )
}
