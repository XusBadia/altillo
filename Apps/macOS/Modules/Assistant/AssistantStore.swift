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
    /// "Tell Claude to …" (phase 13): hands the words to a waiting agent (`AgentHub.reply`).
    var replyToAgent: (AgentReplyIntent.Request) -> AssistantAgentReply.Result = { AssistantAgentReply.live($0) }
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
        /// What was attached when it was asked (phase 13), for the mark on the question slip.
        var attachmentName: String?
        /// What its actions did (a reminder made), shown under the answer with an Undo (phase 13).
        var receipts: [AssistantActionReceipt] = []
        /// How it was routed, once known.
        var route: AssistantRoute?

        init(id: UUID = UUID(), question: String, answer: String = "", status: Status = .thinking,
             sources: [AssistantActivity] = [], webSources: [AssistantWebSource] = [], offersWeb: Bool = false,
             attachmentName: String? = nil, receipts: [AssistantActionReceipt] = []) {
            self.id = id
            self.question = question
            self.answer = answer
            self.status = status
            self.sources = sources
            self.webSources = webSources
            self.offersWeb = offersWeb
            self.attachmentName = attachmentName
            self.receipts = receipts
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

    // Phase 13
    /// Something dropped on Ask, read and going along with the questions until it's removed.
    private(set) var attachment: AssistantAttachment?
    /// A drop being read (a PDF, an image through Vision).
    private(set) var isAttaching = false
    /// The saved answers list is showing instead of the conversation.
    var showsSaved = false
    /// Answers the user chose to keep (the only thing Ask writes to disk).
    let saved: AssistantSavedStore
    /// The mic in the prompt field.
    let dictation: AssistantDictation
    /// Send the question as soon as dictation ends (a choice in the mic's menu). Off by default: the words stay in
    /// the field to be checked first.
    var sendsWhenDictationEnds: Bool = UserDefaults.standard.bool(forKey: AssistantStore.autoSendKey) {
        didSet { UserDefaults.standard.set(sendsWhenDictationEnds, forKey: Self.autoSendKey) }
    }
    nonisolated static let autoSendKey = "assistantDictationAutoSend"
    @ObservationIgnored private let reminders: any ReminderStoring
    /// What was in the field when dictation started: the words heard go after it.
    @ObservationIgnored private var dictationPrefix = ""
    @ObservationIgnored private var attachTask: Task<Void, Never>?
    /// One action per question, shared by its retries (`AssistantActionOnce`).
    @ObservationIgnored private var actionOnce: [UUID: AssistantActionOnce] = [:]

    init(dictation: AssistantDictation? = nil, saved: AssistantSavedStore? = nil,
         reminders: any ReminderStoring = LiveReminderStore.shared) {
        self.dictation = dictation ?? AssistantDictation(recognizer: LiveDictationRecognizer())
        self.saved = saved ?? AssistantSavedStore()
        self.reminders = reminders
        self.dictation.onTranscript = { [weak self] words in self?.dictated(words) }
        self.dictation.onEnded = { [weak self] ending in self?.dictationEnded(ending) }
    }

    /// Typing, a draft, dictating, or an answer on its way: the notch must not close under the user.
    var holdsOpen: Bool {
        Self.holdsOpen(isFieldFocused: isFieldFocused, draft: draft, isResponding: isResponding)
            || dictation.isActive || isAttaching
    }

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
    /// announces itself with a peek. The mic never listens unseen.
    func stop() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { dictation.cancel() }
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
            runningPlayer: AssistantSuggestion.playingApp(
                store: AssistantNowPlaying.liveReading(),
                runningPlayer: MusicPlayer.allCases.first { open.contains($0.bundleID) }?.appName
            ),
            clipboardHasText: AssistantContent.clipboardHasText()
        )
        suggestions = AssistantSuggestion.make(signals)
    }

    // MARK: - Asking

    /// Sends `text`, or the draft when nil.
    func send(_ text: String? = nil) {
        var question = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        // Something attached and nothing typed: the obvious question about it.
        if question.isEmpty, text == nil, let attachment { question = AssistantAttachments.defaultQuestion(for: attachment) }
        guard !question.isEmpty, !isResponding, !isAttaching else { return }
        availability = Availability(SystemLanguageModel.default.availability)
        guard availability == .available else { return }
        if text == nil { draft = "" }
        dictation.cancel()
        showsSaved = false

        let exchange = Exchange(question: question, attachmentName: attachment?.name)
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

    /// Forgets the conversation (and what was attached) and starts over.
    func newConversation() {
        dictation.cancel()
        removeAttachment()
        actionOnce = [:]
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

    // MARK: - Attachments (phase 13)

    /// Something dropped on Ask: read it (off the main actor) and keep it for the next questions. Replaces what
    /// was attached before.
    func attach(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        attachTask?.cancel()
        isAttaching = true
        showsSaved = false
        SpikeLog.shared.record(SpikeLog.Category.assistant, "attaching \(items.count) dropped item(s)")
        attachTask = Task { [weak self] in
            let read = await Task.detached(priority: .userInitiated) { await AssistantAttachments.read(items) }.value
            guard let self, !Task.isCancelled else { return }
            self.attachment = read
            self.isAttaching = false
            self.attachTask = nil
            let kind = read.map { String(describing: $0.kind) } ?? "nothing"
            SpikeLog.shared.record(SpikeLog.Category.assistant, "attached \(kind) (\(read?.text.count ?? 0) chars)")
        }
    }

    /// Sets an attachment already read (tests, previews).
    func setAttachment(_ attachment: AssistantAttachment?) {
        attachTask?.cancel()
        attachTask = nil
        isAttaching = false
        self.attachment = attachment
    }

    /// The × on the chip. Following questions go back to being about anything.
    func removeAttachment() {
        setAttachment(nil)
    }

    // MARK: - Saved answers (phase 13)

    func isSaved(_ exchange: Exchange) -> Bool { saved.isSaved(exchange.id) }

    /// The bookmark under an answer: saves it, or unsaves it when it's saved already.
    func toggleSave(_ exchange: Exchange) {
        guard exchange.hasAnswer else { return }
        if saved.isSaved(exchange.id) {
            saved.remove(exchangeID: exchange.id)
        } else {
            saved.save(question: exchange.question, answer: exchange.answer, exchangeID: exchange.id,
                       attachmentName: exchange.attachmentName)
            SpikeLog.shared.record(SpikeLog.Category.assistant, "answer saved")
        }
    }

    func copy(_ answer: AssistantSavedAnswer) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(AssistantFormat.plainText(answer.answer), forType: .string)
    }

    func putUp(_ answer: AssistantSavedAnswer) {
        let text = AssistantFormat.plainText(answer.answer)
        guard !text.isEmpty else { return }
        context.addToShelf([ShelfItem(kind: .text(text), displayName: AssistantFormat.shelfName(question: answer.question))])
    }

    func delete(_ answer: AssistantSavedAnswer) {
        saved.remove(answer.id)
    }

    // MARK: - Actions (phase 13)

    /// Undo under an answer: removes the reminder it made.
    func undo(_ receipt: AssistantActionReceipt, in exchange: Exchange) {
        guard case let .reminder(identifier)? = receipt.undo, !receipt.isUndone else { return }
        let reminders = self.reminders
        Task { [weak self] in
            let removed = await AssistantReminders.undo(identifier: identifier, store: reminders)
            SpikeLog.shared.record(SpikeLog.Category.assistant, "reminder undo → \(removed)")
            self?.update(exchange.id) { exchange in
                guard let index = exchange.receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
                // Undone only when it really went; otherwise the card says so.
                exchange.receipts[index].isUndone = removed
                exchange.receipts[index].undoFailed = !removed
            }
        }
    }

    /// "Tomorrow at 9:00" on a card whose time had passed: makes that reminder, and the card becomes its receipt.
    func accept(_ receipt: AssistantActionReceipt, in exchange: Exchange) {
        guard let offer = receipt.offer else { return }
        let reminders = self.reminders
        update(exchange.id) { exchange in
            guard let index = exchange.receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
            exchange.receipts[index].offer = nil
        }
        Task { [weak self] in
            let made = await AssistantReminders.accept(offer, store: reminders, now: .now)
            SpikeLog.shared.record(SpikeLog.Category.assistant, "reminder offer accepted → \(made != nil)")
            self?.update(exchange.id) { exchange in
                guard let index = exchange.receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
                if let made {
                    exchange.receipts[index] = made
                } else {
                    exchange.receipts[index].offer = offer
                    exchange.receipts[index].undoFailed = true
                }
            }
        }
    }

    /// "Tell Claude to …": sent as typed, answered by Altillo itself, no model involved.
    private func replyToAgent(_ request: AgentReplyIntent.Request, exchange id: UUID) {
        noteActivity(.agents)
        let result = context.replyToAgent(request)
        SpikeLog.shared.record(SpikeLog.Category.assistant, "agent reply → \(result.receipt == nil ? "not sent" : "sent")")
        update(id) {
            $0.answer = result.answer
            if let receipt = result.receipt { $0.receipts.append(receipt) }
        }
        finish(id, error: nil)
    }

    private func noteReceipt(_ receipt: AssistantActionReceipt) {
        guard let id = respondingTo else { return }
        update(id) { $0.receipts.append(receipt) }
    }

    // MARK: - Dictation (phase 13)

    /// The mic button.
    func toggleDictation() {
        if !dictation.isActive {
            dictationPrefix = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        Task { await dictation.toggle() }
    }

    private func dictated(_ words: String) {
        draft = dictationPrefix.isEmpty ? words : dictationPrefix + " " + words
    }

    private func dictationEnded(_ ending: AssistantDictation.Ending) {
        guard Self.autoSends(draft, enabled: sendsWhenDictationEnds), !isResponding else { return }
        send()
    }

    /// Whether dictation may send on its own. Never for actions (a message to an agent, a reminder): the words the
    /// recogniser heard stay in the field for the user to check first.
    static func autoSends(_ draft: String, enabled: Bool) -> Bool {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !text.isEmpty else { return false }
        return AgentReplyIntent.parse(text) == nil && AssistantRouter.route(text) != .reminder
            && !ShortcutsAskIntent.isExplicitRun(text)
    }

    // MARK: - Answering

    /// Routes the question (`AssistantRouter`), then answers it: from the model alone, with the local tools, or
    /// from web results when it's about something live and the user allows the web.
    private func respond(to question: String, exchange id: UUID) async {
        let followsContext = exchanges.last(where: { $0.id != id && $0.isFinished })?.sources
            .contains(where: \.isLocalContext) ?? false
        let route = AssistantRouter.route(question, followsContext: followsContext)
        let webAllowed = context.webSearchAllowed()
        update(id) { $0.route = route }
        if route == .agentReply, let request = AgentReplyIntent.parse(question) {
            replyToAgent(request, exchange: id)
            return
        }
        // With something attached, questions are about it, unless they explicitly ask for an action.
        let attached = exchanges.first(where: { $0.id == id })?.attachmentName != nil ? attachment : nil
        if let attached, !route.acts, !AssistantRouter.asksForTimer(question), !AssistantRouter.asksForNote(question) {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "route attachment (\(attached.text.count) chars)")
            do {
                try await answer(AssistantAttachments.prompt(for: question, attachment: attached), route: .chat, into: id)
            } catch {
                finish(id, error: Task.isCancelled ? CancellationError() : error)
                return
            }
            finish(id, error: Task.isCancelled ? CancellationError() : nil)
            return
        }
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
            try await answer(prompt, route: sessionRoute, question: question, into: id)
        } catch {
            finish(id, error: Task.isCancelled ? CancellationError() : error)
            return
        }
        // Web lookups are allowed and the model says it can't know: look it up for it.
        if !Task.isCancelled, webAllowed, !route.acts,
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
    private func answer(_ prompt: String, route: AssistantRoute, question: String = "", into id: UUID) async throws {
        let session = takePrewarmed(for: route, excluding: id)
            ?? makeSession(route: route, recap: recap(excluding: id), question: question, exchange: id)
        do {
            try await stream(prompt, in: session, into: id)
        } catch let error where [.contextFull, .other].contains(AssistantFailure(error)) && !Task.isCancelled
            && !hasActed(id, route: route) {
            SpikeLog.shared.record(SpikeLog.Category.assistant, "\(AssistantFailure(error)): retrying in a fresh session")
            update(id) {
                $0.answer = ""
                $0.status = .thinking
            }
            try await stream(prompt, in: makeSession(route: route, recap: nil, question: question, exchange: id), into: id)
        }
    }

    /// An action route whose tool already did something: never tried again (the reminder exists, the shortcut ran).
    private func hasActed(_ id: UUID, route: AssistantRoute) -> Bool {
        guard route == .reminder || route == .shortcut,
              let exchange = exchanges.first(where: { $0.id == id })
        else { return false }
        return !exchange.receipts.isEmpty || exchange.sources.contains(.shortcuts)
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
                && !(exchange.route?.acts ?? false)
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

    private func makeSession(route: AssistantRoute, recap: String?, question: String = "",
                             exchange: UUID? = nil) -> LanguageModelSession {
        let once: AssistantActionOnce
        if let exchange {
            once = actionOnce[exchange] ?? AssistantActionOnce()
            actionOnce[exchange] = once
        } else {
            once = AssistantActionOnce()
        }
        let tools = AssistantTools.all(
            for: route,
            shelfItems: { [weak self] in self?.context.shelfItems() ?? [] },
            question: question,
            reminders: reminders,
            once: once,
            receipt: { [weak self] receipt in self?.noteReceipt(receipt) },
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
