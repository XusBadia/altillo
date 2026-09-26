import AltilloCore
import Foundation
import FoundationModels
import Testing
@testable import Altillo

/// Phase 13: files dropped on Ask, saved answers, the reminders action, dictation and the routing that leads there.
/// None of it needs the model, the microphone or the real Reminders.
@MainActor
struct AssistantPhase13Tests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("altillo-ask13-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Attachments

    @Test func droppedTextIsAttachedAsADocument() async {
        let item = ShelfItem(kind: .text("Buy milk\nCall Ana"), displayName: "Buy milk")
        let attachment = await AssistantAttachments.read([item])
        #expect(attachment?.kind == .document)
        #expect(attachment?.name == "Buy milk")
        #expect(attachment?.text.contains("Call Ana") == true)
    }

    @Test func aLongFileIsCutToTheAttachmentBudget() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("long.md")
        try Data(String(repeating: "palabra ", count: 5_000).utf8).write(to: url)
        let item = ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "long.md")
        let attachment = await AssistantAttachments.read([item])
        #expect(attachment?.kind == .document)
        #expect((attachment?.text.count ?? .max) <= AssistantAttachments.textLimit)
        #expect(attachment?.text.hasSuffix("[…cut: the rest isn't shown]") == true)
        #expect(FileManager.default.fileExists(atPath: url.path), "a file the user owns is never touched")
    }

    @Test func altillosOwnCopyIsRemovedOnceRead() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let slot = folder.appendingPathComponent("slot", isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        let url = slot.appendingPathComponent("promised.txt")
        try Data("Promised text".utf8).write(to: url)
        let item = ShelfItem(kind: .file(url, isOwnedCopy: true), displayName: "promised.txt")
        let attachment = await AssistantAttachments.read(item, inboxRoot: folder)
        #expect(attachment.text.contains("Promised text"))
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(!FileManager.default.fileExists(atPath: slot.path), "its empty slot goes too")
        #expect(FileManager.default.fileExists(atPath: folder.path), "never the Inbox itself")
    }

    @Test func onlyCopiesInsideTheInboxAreEverDeleted() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = folder.appendingPathComponent("Inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let outside = folder.appendingPathComponent("mine.txt")
        try Data("mine".utf8).write(to: outside)
        // Marked as a copy by mistake: still outside the Inbox, so it stays.
        _ = await AssistantAttachments.read(ShelfItem(kind: .file(outside, isOwnedCopy: true), displayName: "mine.txt"),
                                            inboxRoot: inbox)
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(!AssistantAttachments.discardCopy(at: inbox, inboxRoot: inbox))
    }

    @Test func copiesBeyondTheFirstThreeAreDeletedToo() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        var items: [ShelfItem] = []
        var urls: [URL] = []
        for index in 1...5 {
            let slot = folder.appendingPathComponent("slot\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let url = slot.appendingPathComponent("n\(index).txt")
            try Data("note \(index)".utf8).write(to: url)
            urls.append(url)
            items.append(ShelfItem(kind: .file(url, isOwnedCopy: true), displayName: "n\(index).txt"))
        }
        let read = await AssistantAttachments.read(items, inboxRoot: folder)
        #expect(read?.text.contains("note 3") == true)
        #expect(read?.text.contains("note 4") == false)
        #expect(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test func imagesAreDescribedFromWhatVisionFound() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("receipt.png")
        try Data([0x89, 0x50]).write(to: url)
        let item = ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "receipt.png")
        let read = await AssistantAttachments.read(item) { _ in
            AssistantAttachments.ImageReading(lines: ["Total 12,50 €"], labels: ["document"])
        }
        #expect(read.kind == .image)
        #expect(read.text.contains("Total 12,50 €"))
        #expect(read.text.contains("It seems to show: document"))

        let blind = await AssistantAttachments.read(item) { _ in nil }
        #expect(blind.text.contains("can't see images"))
    }

    @Test func unreadableFilesGoAlongByName() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("clip.mov")
        try Data([0, 1, 2]).write(to: url)
        let read = await AssistantAttachments.read(ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: "clip.mov"))
        #expect(read.kind == .unreadable)
        #expect(read.text.contains("can't be read"))
    }

    @Test func severalDropsShareTheBudget() async {
        let items = (1...3).map { ShelfItem(kind: .text(String(repeating: "note\($0) ", count: 800)), displayName: "Note \($0)") }
        let read = await AssistantAttachments.read(items)
        #expect(read?.name.contains("Note 1") == true)
        #expect((read?.text.count ?? .max) <= AssistantAttachments.textLimit)
        #expect(read?.text.contains("\"Note 3\"") == true)
    }

    @Test func thePromptCarriesTheAttachmentBeforeTheQuestion() {
        let attachment = AssistantAttachment(name: "informe.pdf", kind: .document, text: "Ventas: 120", description: "PDF file")
        let prompt = AssistantAttachments.prompt(for: "What's in this PDF?", attachment: attachment)
        #expect(prompt.contains("\"informe.pdf\" (PDF file)"))
        #expect(prompt.contains("Ventas: 120"))
        #expect(prompt.range(of: "Ventas")!.lowerBound < prompt.range(of: "What's in this PDF?")!.lowerBound)
        #expect(AssistantAttachments.defaultQuestion(for: attachment).contains("informe.pdf"))
    }

    @Test func theChipFollowsTheStore() async throws {
        let store = AssistantStore(saved: AssistantSavedStore(fileURL: try scratch().appendingPathComponent("s.json")))
        #expect(store.attachment == nil)
        store.attach([ShelfItem(kind: .text("Hello"), displayName: "Hello")])
        #expect(store.isAttaching)
        #expect(store.holdsOpen, "the notch stays while it reads")
        for _ in 0..<200 where store.isAttaching { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!store.isAttaching)
        #expect(store.attachment?.name == "Hello")
        store.removeAttachment()
        #expect(store.attachment == nil)
        store.setAttachment(AssistantAttachment(name: "a.txt", kind: .document, text: "a", description: "text"))
        store.newConversation()
        #expect(store.attachment == nil, "a new conversation forgets what was attached")
    }

    // MARK: - Saved answers

    @Test func savedAnswersPersistPrivately() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Ask/Saved answers.json")
        let exchange = UUID()
        let store = AssistantSavedStore(fileURL: url)
        let saved = store.save(question: "¿Qué es un altillo?", answer: "Un **desván** pequeño.", exchangeID: exchange,
                               attachmentName: "nota.txt")
        #expect(saved != nil)
        #expect(store.save(question: "again", answer: "again", exchangeID: exchange) == nil, "saved once")
        #expect(store.save(question: "empty", answer: "  ", exchangeID: UUID()) == nil)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let reloaded = AssistantSavedStore(fileURL: url)
        reloaded.load()
        #expect(reloaded.answers.count == 1)
        #expect(reloaded.answers.first?.answer == "Un **desván** pequeño.")
        #expect(reloaded.answers.first?.attachmentName == "nota.txt")
        #expect(reloaded.isSaved(exchange))

        reloaded.remove(exchangeID: exchange)
        #expect(reloaded.answers.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path), "nothing saved, no file")
    }

    @Test func savedAnswersAreThereRightAfterARelaunch() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("s.json")
        AssistantSavedStore(fileURL: url).save(question: "q", answer: "a", exchangeID: UUID())
        #expect(AssistantSavedStore(fileURL: url).answers.count == 1, "loaded in init")
    }

    @Test func anUnreadableFileIsMovedAsideNotOverwritten() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Saved answers.json")
        try Data("{ not json".utf8).write(to: url)
        let store = AssistantSavedStore(fileURL: url)
        #expect(store.answers.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.contains { $0.hasPrefix("Saved answers (unreadable ") && $0.hasSuffix(").json") })
        store.save(question: "q", answer: "a", exchangeID: UUID())
        let aside = try #require(names.first { $0.hasPrefix("Saved answers (unreadable ") })
        #expect(try String(contentsOf: folder.appendingPathComponent(aside), encoding: .utf8) == "{ not json")
    }

    @Test func newestSavedAnswersComeFirstAndTheListIsCapped() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = AssistantSavedStore(fileURL: folder.appendingPathComponent("s.json"))
        for index in 0..<(AssistantSavedStore.limit + 5) {
            store.save(question: "q\(index)", answer: "a\(index)", exchangeID: UUID())
        }
        #expect(store.answers.count == AssistantSavedStore.limit)
        #expect(store.answers.first?.question == "q\(AssistantSavedStore.limit + 4)")
        let first = try #require(store.answers.first)
        store.remove(first.id)
        #expect(!store.answers.contains(first))
    }

    // MARK: - Reminders

    private actor FakeReminders: ReminderStoring {
        var status: ReminderAccess
        var grants: Bool
        var created: [(title: String, due: ReminderDue?)] = []
        var removed: [String] = []
        var asked = 0
        var fails = false

        init(_ status: ReminderAccess, grants: Bool = true) {
            self.status = status
            self.grants = grants
        }

        func access() -> ReminderAccess { status }
        func requestAccess() -> Bool {
            asked += 1
            status = grants ? .granted : .denied
            return grants
        }
        func create(title: String, due: ReminderDue?, calendar: Calendar) throws -> CreatedReminder {
            if fails { throw CocoaError(.fileWriteUnknown) }
            created.append((title, due))
            return CreatedReminder(identifier: "r\(created.count)", listName: "Reminders")
        }
        var removes = true
        func remove(identifier: String) -> Bool {
            removed.append(identifier)
            return removes
        }
        func setFails() { fails = true }
        func setRemoves(_ value: Bool) { removes = value }
    }

    private var madrid: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return calendar
    }

    /// Friday 25 September 2026, 17:00 in Madrid.
    private var friday: Date {
        madrid.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 17))!
    }

    @Test func aReminderIsMadeWithItsDateAndAnUndo() async throws {
        let store = FakeReminders(.granted)
        let result = await AssistantReminders.create(
            title: "call Ana tomorrow at 10", when: "tomorrow at 10", question: "remind me to call Ana tomorrow at 10",
            store: store, now: friday, calendar: madrid
        )
        let created = await store.created
        #expect(created.count == 1)
        #expect(created.first?.title == "Call Ana")
        let due = try #require(created.first?.due)
        #expect(due.hasTime)
        #expect(due.date == madrid.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10)))
        #expect(result.answer.contains("Reminder created"))
        #expect(result.answer.contains("\"Call Ana\""))
        #expect(result.answer.contains("tomorrow (Saturday 26 September) at 10:00"))
        #expect(result.receipt?.undo == .reminder("r1"))
        #expect(result.receipt?.isAgentReply == false, "a reminder's answer is the model's own words, still shown")
        #expect(result.receipt?.title == "Call Ana")

        #expect(await AssistantReminders.undo(identifier: "r1", store: store))
        #expect(await store.removed == ["r1"])
    }

    @Test func namesKeepTheCasingTheUserTyped() {
        #expect(AssistantReminders.cleanTitle("call ana", question: "remind me to call Ana tomorrow at 10") == "Call Ana")
        #expect(AssistantReminders.cleanTitle("trucar a l'Ana demà a les 9", question: "") == "Trucar a l'Ana")
    }

    @Test func aSecondCallForTheSameQuestionMakesNothingNew() async {
        let store = FakeReminders(.granted)
        let once = AssistantActionOnce()
        let work: @Sendable () async -> AssistantReminders.Result = { [friday, madrid] in
            await AssistantReminders.create(title: "Call Ana", when: "tomorrow at 10", question: "", store: store,
                                            now: friday, calendar: madrid)
        }
        let (first, firstIsNew) = await once.run(work)
        let (second, secondIsNew) = await once.run(work)
        #expect(firstIsNew && !secondIsNew)
        #expect(first == second)
        #expect(await store.created.count == 1)
    }

    @Test func aTimeThatPassedTodayMakesNothingAndOffersTomorrow() async throws {
        let store = FakeReminders(.granted)
        let result = await AssistantReminders.create(title: "Call Ana", when: "today at 9am", question: "", store: store,
                                                     now: friday, calendar: madrid)
        #expect(await store.created.isEmpty)
        #expect(result.answer.contains("has already passed"))
        let receipt = try #require(result.receipt)
        #expect(receipt.undo == nil)
        let tomorrowAtNine = madrid.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 9))!
        #expect(receipt.offer == .reminder(title: "Call Ana", due: tomorrowAtNine))

        let accepted = await AssistantReminders.accept(try #require(receipt.offer), store: store, now: friday,
                                                       calendar: madrid)
        #expect(accepted?.undo == .reminder("r1"))
        #expect(await store.created.first?.due == ReminderDue(date: tomorrowAtNine, hasTime: true))
    }

    @Test func theModelsTimeGetsTheQuestionsDay() async {
        let store = FakeReminders(.granted)
        _ = await AssistantReminders.create(title: "llamar a Ana", when: "a las 10",
                                            question: "recuérdame mañana llamar a Ana a las 10", store: store,
                                            now: friday, calendar: madrid)
        #expect(await store.created.first?.due?.date
            == madrid.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10)))
    }

    @Test func undoReportsWhetherItWorked() async {
        let store = FakeReminders(.granted)
        await store.setRemoves(false)
        #expect(await !AssistantReminders.undo(identifier: "r9", store: store))
    }

    @Test func theDateComesFromTheQuestionWhenTheModelLeavesItOut() async {
        let store = FakeReminders(.granted)
        _ = await AssistantReminders.create(
            title: "comprar pan", when: nil, question: "recuérdame comprar pan a las 7", store: store, now: friday,
            calendar: madrid
        )
        let due = await store.created.first?.due
        #expect(due?.date == madrid.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 19)))
    }

    @Test func accessIsAskedOnlyTheFirstTime() async {
        let fresh = FakeReminders(.notDetermined, grants: true)
        let allowed = await AssistantReminders.create(title: "Water the plants", when: nil, question: "", store: fresh,
                                                      now: friday, calendar: madrid)
        #expect(await fresh.asked == 1)
        #expect(allowed.answer.contains("just allowed"))
        #expect(allowed.answer.contains("with no date"))

        let refused = FakeReminders(.notDetermined, grants: false)
        let no = await AssistantReminders.create(title: "Water the plants", when: nil, question: "", store: refused,
                                                 now: friday, calendar: madrid)
        #expect(await refused.created.isEmpty)
        #expect(no.receipt == nil)
        #expect(no.answer.contains("No reminder was made"))

        let denied = FakeReminders(.denied)
        let never = await AssistantReminders.create(title: "Water the plants", when: nil, question: "", store: denied,
                                                    now: friday, calendar: madrid)
        #expect(await denied.asked == 0, "a refusal is never asked again")
        #expect(never.answer.contains("Privacy & Security › Reminders"))
    }

    @Test func nothingIsMadeWithoutATitleOrWhenSavingFails() async {
        let store = FakeReminders(.granted)
        let empty = await AssistantReminders.create(title: "  ", when: "tomorrow", question: "", store: store, now: friday,
                                                    calendar: madrid)
        #expect(empty.answer.contains("nothing to be reminded of"))
        await store.setFails()
        let failed = await AssistantReminders.create(title: "Pay rent", when: nil, question: "", store: store, now: friday,
                                                     calendar: madrid)
        #expect(failed.receipt == nil)
        #expect(failed.answer.contains("couldn't save it"))
    }

    @Test func remindersToolIsTheOnlyToolOnItsRoute() {
        let tools = AssistantTools.all(for: .reminder, shelfItems: { [] }, question: "remind me to call Ana",
                                       reminders: FakeReminders(.granted), report: { _ in })
        #expect(tools.map(\.name) == ["reminders"])
        #expect(!AssistantTools.all(for: .context, shelfItems: { [] }, report: { _ in }).map(\.name).contains("reminders"))
        #expect(AssistantInstructions.text(route: .reminder).contains("Call reminders once"))
    }

    // MARK: - Routing

    @Test func explicitReminderRequestsGoToTheReminderRoute() {
        for question in [
            "Remind me to call Ana tomorrow at 10",
            "recuérdame comprar pan a las 7",
            "Recuerdame llamar al dentista el lunes",
            "recorda'm trucar a l'Ana demà",
            "Create a reminder to pay the rent",
            "pon un recordatorio para regar las plantas",
            "crea un recordatori per comprar llet",
            "recuérdame en 10 minutos que saque la pasta",
        ] {
            #expect(AssistantRouter.route(question) == .reminder, "\(question)")
        }
    }

    @Test func questionsAndMemoriesAreNotReminders() {
        for question in [
            "Remind me about the French revolution",
            "remind me of the capital of France",
            "recuérdame qué es un monad",
            "how do I set a reminder on iPhone?",
            "What's a good app to make reminders?",
            "What's new in Reminders?",
            "¿Cómo creo un recordatorio?",
            "què és un recordatori?",
        ] {
            #expect(AssistantRouter.route(question) != .reminder, "\(question)")
        }
        #expect(AssistantRouter.route("remind me about the dentist tomorrow at 9") == .reminder)
        #expect(AssistantRouter.route("Please remind me to water the plants") == .reminder)
        #expect(AssistantRouter.route("Set a reminder for tomorrow at 8: gym") == .reminder)
    }

    @Test func attachmentsDontSwallowTimersAndNotes() {
        #expect(AssistantRouter.asksForTimer("pon 10 minutos"))
        #expect(AssistantRouter.asksForNote("apunta comprar leche"))
        #expect(AssistantRouter.asksForNote("write down the wifi password"))
        #expect(!AssistantRouter.asksForNote("summarize this"))
    }

    @Test func dictationNeverSendsActionsOnItsOwn() {
        #expect(AssistantStore.autoSends("What's the capital of France?", enabled: true))
        #expect(!AssistantStore.autoSends("What's the capital of France?", enabled: false))
        #expect(!AssistantStore.autoSends("tell Claude to delete the branch", enabled: true))
        #expect(!AssistantStore.autoSends("recuérdame llamar a Ana mañana", enabled: true))
        #expect(!AssistantStore.autoSends("  ", enabled: true))
    }

    @Test func timersAndQuestionsAboutRemindersStayWhereTheyWere() {
        #expect(AssistantRouter.route("remind me in 10 minutes") == .context, "a duration is a timer")
        #expect(AssistantRouter.route("avísame en media hora") == .context)
        #expect(AssistantRouter.route("what are my reminders?") != .reminder)
        #expect(AssistantRouter.route("what is a reminder in music theory?") != .reminder)
        #expect(AssistantRouter.route("run my reminder shortcut") == .shortcut)
    }

    // MARK: - Dictation

    private final class FakeRecognizer: DictationRecognizer {
        var permissionResult: DictationPermission = .granted
        var localeResult: Locale? = Locale(identifier: "es-ES")
        var started: Locale?
        var finished = 0
        var cancelled = 0
        var askedForPermission = false

        func permission(ask: Bool) async -> DictationPermission {
            askedForPermission = ask
            return permissionResult
        }
        func locale() -> Locale? { localeResult }
        func start(locale: Locale, events: @escaping @Sendable (DictationEvent) -> Void) throws { started = locale }
        func finish() { finished += 1 }
        func cancel() { cancelled += 1 }
    }

    private final class ManualScheduler: DictationScheduling {
        final class Entry: DictationScheduled {
            let delay: Duration
            let work: @MainActor () -> Void
            var isCancelled = false
            init(delay: Duration, work: @escaping @MainActor () -> Void) {
                self.delay = delay
                self.work = work
            }
            func cancel() { isCancelled = true }
        }

        var entries: [Entry] = []

        func after(_ delay: Duration, _ work: @escaping @MainActor () -> Void) -> any DictationScheduled {
            let entry = Entry(delay: delay, work: work)
            entries.append(entry)
            return entry
        }

        /// Fires the newest live entry with this delay.
        func fire(_ delay: Duration) {
            guard let entry = entries.last(where: { $0.delay == delay && !$0.isCancelled }) else { return }
            entry.isCancelled = true
            entry.work()
        }
    }

    private func dictation() -> (AssistantDictation, FakeRecognizer, ManualScheduler, Box) {
        let recognizer = FakeRecognizer()
        let scheduler = ManualScheduler()
        let dictation = AssistantDictation(recognizer: recognizer, scheduler: scheduler)
        let box = Box()
        dictation.onTranscript = { box.transcripts.append($0) }
        dictation.onEnded = { box.endings.append($0) }
        return (dictation, recognizer, scheduler, box)
    }

    private final class Box {
        var transcripts: [String] = []
        var endings: [AssistantDictation.Ending] = []
    }

    @Test func dictationListensWritesAndStopsOnSilence() async {
        let (dictation, recognizer, scheduler, box) = dictation()
        await dictation.start()
        #expect(recognizer.askedForPermission)
        #expect(recognizer.started?.identifier == "es-ES")
        #expect(dictation.state == .listening)

        dictation.handle(.level(0.7))
        #expect(dictation.level == 0.7)
        dictation.handle(.level(3))
        #expect(dictation.level == 1, "clamped")
        dictation.handle(.partial("recuérdame"))
        dictation.handle(.partial("recuérdame comprar pan"))
        #expect(box.transcripts == ["recuérdame", "recuérdame comprar pan"])

        scheduler.fire(dictation.silenceAfterSpeech)
        #expect(dictation.state == .finishing)
        #expect(recognizer.finished == 1)
        dictation.handle(.final("Recuérdame comprar pan."))
        #expect(dictation.state == .idle)
        #expect(box.endings == [.init(text: "Recuérdame comprar pan.", bySilence: true)])
    }

    @Test func aClickStopsAndKeepsTheWords() async {
        let (dictation, recognizer, scheduler, box) = dictation()
        await dictation.toggle()
        dictation.handle(.partial("hello there"))
        await dictation.toggle()
        #expect(dictation.state == .finishing)
        #expect(recognizer.finished == 1)
        // The final words never come: it ends anyway with what it heard.
        scheduler.fire(dictation.finalWait)
        #expect(dictation.state == .idle)
        #expect(box.endings == [.init(text: "hello there", bySilence: false)])
    }

    @Test func nothingHeardEndsWithAProblem() async {
        let (dictation, recognizer, scheduler, box) = dictation()
        await dictation.start()
        scheduler.fire(dictation.silenceBeforeSpeech)
        #expect(dictation.state == .idle)
        #expect(dictation.problem == .noSpeech)
        #expect(recognizer.cancelled >= 1)
        #expect(box.endings.isEmpty)
    }

    @Test func permissionsAndLanguageProblemsAreExplained() async {
        let (dictation, recognizer, _, _) = dictation()
        recognizer.permissionResult = .microphoneDenied
        await dictation.start()
        #expect(dictation.problem == .microphoneDenied)
        #expect(dictation.state == .idle)
        #expect(recognizer.started == nil)

        recognizer.permissionResult = .speechDenied
        await dictation.start()
        #expect(dictation.problem == .speechDenied)

        recognizer.permissionResult = .granted
        recognizer.localeResult = nil
        await dictation.start()
        #expect(dictation.problem == .unavailable)
        #expect(!(dictation.problem?.message.isEmpty ?? true))
    }

    @Test func aRecognizerErrorKeepsWhatWasHeard() async {
        let (dictation, _, _, box) = dictation()
        await dictation.start()
        dictation.handle(.partial("half a"))
        dictation.handle(.failed(noSpeech: false))
        #expect(box.endings.map(\.text) == ["half a"])

        await dictation.start()
        dictation.handle(.failed(noSpeech: true))
        #expect(dictation.problem == .noSpeech)
    }

    @Test func cancellingSendsNothing() async {
        let (dictation, recognizer, _, box) = dictation()
        await dictation.start()
        dictation.handle(.partial("never mind"))
        dictation.cancel()
        #expect(dictation.state == .idle)
        #expect(recognizer.cancelled >= 1)
        #expect(box.endings.isEmpty)
        dictation.handle(.final("late words"))
        #expect(box.endings.isEmpty, "late events after a cancel are ignored")
    }

    @Test func dictatedWordsFollowWhatWasTyped() async throws {
        let recognizer = FakeRecognizer()
        let scheduler = ManualScheduler()
        let dictation = AssistantDictation(recognizer: recognizer, scheduler: scheduler)
        let store = AssistantStore(dictation: dictation,
                                   saved: AssistantSavedStore(fileURL: try scratch().appendingPathComponent("s.json")))
        store.draft = "Translate:"
        store.toggleDictation()
        for _ in 0..<100 where dictation.state != .listening { await Task.yield() }
        #expect(store.holdsOpen, "the notch stays while listening")
        dictation.handle(.partial("buenos días"))
        #expect(store.draft == "Translate: buenos días")
        dictation.cancel()
        #expect(store.draft == "Translate: buenos días", "what was heard stays in the field")
    }
}

/// "Tell Claude to …": parsed from the user's own words and sent as typed, only to a session waiting for a reply.
@MainActor
struct AssistantAgentReplyTests {
    private func session(_ agent: AgentKind, _ project: String, waiting: Bool) -> AgentSession {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        return AgentSession(
            agent: agent, sessionID: UUID().uuidString, cwd: "/Users/me/\(project)",
            phase: waiting ? .waitingAnswer : .working, startedAt: now, lastActivity: now, source: .hooks,
            reply: waiting ? AgentReplyChannel(kind: .stopHook, id: "req-\(project)", openedAt: now) : nil
        )
    }

    @Test func explicitPhrasesAreParsedWithTheMessageAsTyped() {
        #expect(AgentReplyIntent.parse("Tell Codex to run the linter")
            == .init(agent: "Codex", project: nil, message: "run the linter"))
        #expect(AgentReplyIntent.parse("dile a Claude que siga con los tests")
            == .init(agent: "Claude", project: nil, message: "siga con los tests"))
        #expect(AgentReplyIntent.parse("Dígale a Claude: Sí, adelante")
            == .init(agent: "Claude", project: nil, message: "Sí, adelante"))
        #expect(AgentReplyIntent.parse("reply to Claude: yes, go ahead")?.message == "yes, go ahead")
        #expect(AgentReplyIntent.parse("tell Claude in altillo to commit it")
            == .init(agent: "Claude", project: "altillo", message: "commit it"))
        #expect(AgentReplyIntent.parse("digues a Codex que continuï")?.message == "continuï")
        #expect(AgentReplyIntent.parse("tell Claude Code that the build is green")?.agent == "Claude Code")
    }

    @Test func theMessageKeepsItsQuotes() {
        #expect(AgentReplyIntent.parse(#"tell Claude: commit with message "fix bug""#)?.message
            == #"commit with message "fix bug""#)
        #expect(AgentReplyIntent.parse(#"tell Claude: "yes, go ahead""#)?.message == "yes, go ahead")
        #expect(AgentReplyIntent.parse("dile a Codex que «sí»")?.message == "sí")
        #expect(AgentReplyIntent.unwrapped(#""a" and "b""#) == #""a" and "b""#)
        #expect(AgentReplyIntent.unwrapped(#""unbalanced"#) == #""unbalanced"#)
        #expect(AgentReplyIntent.unwrapped(#""""x"""#) == #""""x"""#)
    }

    @Test func everythingElseIsNotAReply() {
        for text in ["Tell Claude a joke", "Tell Claude about Paris", "Please tell Claude how to cook rice",
                     "Answer Claude's question", "Answer Claude’s question", "tell claude code's story",
                     "tell Claude yes"] {
            #expect(AgentReplyIntent.parse(text) == nil, "\(text)")
        }
        #expect(AgentReplyIntent.parse("tell me about Claude") == nil)
        #expect(AgentReplyIntent.parse("what is Claude doing?") == nil)
        #expect(AgentReplyIntent.parse("ask Claude what it's doing") == nil)
        #expect(AgentReplyIntent.parse("tell Claudette to call me") == nil)
        #expect(AssistantRouter.route("tell Codex to run the tests") == .agentReply)
        #expect(AssistantRouter.route("¿qué está haciendo Codex?") == .context)
        #expect(AssistantRouter.route("tell me a joke about Claude") != .agentReply)
    }

    @Test func itSendsOnlyToTheOneWaitingSession() {
        var sent: [(String, String)] = []
        let sessions = [session(.claude, "altillo", waiting: true), session(.codex, "api", waiting: false)]
        let request = AgentReplyIntent.Request(agent: "Claude", project: nil, message: "go ahead")
        let result = AssistantAgentReply.perform(request, isEnabled: true, sessions: sessions) { text, session in
            sent.append((text, session.project))
            return true
        }
        #expect(sent.count == 1 && sent[0] == ("go ahead", "altillo"))
        #expect(result.answer.contains("altillo"))
        #expect(result.receipt?.title == "go ahead")
        #expect(result.receipt?.undo == nil, "a message can't be unsent")
        #expect(result.receipt?.isAgentReply == true, "its card stands for the answer, which isn't drawn above it")
    }

    @Test func nothingIsSentWhenItCantBeClear() {
        var sends = 0
        let send: (String, AgentSession) -> Bool = { _, _ in sends += 1; return true }
        let codex = AgentReplyIntent.Request(agent: "Codex", project: nil, message: "hi")
        let notWaiting = AssistantAgentReply.perform(codex, isEnabled: true,
                                                     sessions: [session(.codex, "api", waiting: false)], send: send)
        #expect(notWaiting.receipt == nil)
        let twoWaiting = AssistantAgentReply.perform(codex, isEnabled: true,
                                                     sessions: [session(.codex, "api", waiting: true),
                                                                session(.codex, "web", waiting: true)], send: send)
        #expect(twoWaiting.answer.contains("api, web"))
        #expect(twoWaiting.receipt == nil)
        let picked = AssistantAgentReply.perform(.init(agent: "Codex", project: "web", message: "hi"), isEnabled: true,
                                                 sessions: [session(.codex, "api", waiting: true),
                                                            session(.codex, "web", waiting: true)], send: send)
        #expect(picked.receipt != nil)
        let twoClaudes = AssistantAgentReply.perform(.init(agent: "Claude", project: nil, message: "hi"), isEnabled: true,
                                                     sessions: [session(.claude, "altillo", waiting: true),
                                                                session(.claude, "web", waiting: false)], send: send)
        #expect(twoClaudes.receipt == nil, "which one isn't clear, even if only one is waiting")
        #expect(twoClaudes.answer.contains("altillo, web"))
        let exact = AssistantAgentReply.perform(.init(agent: "Codex", project: "api", message: "hi"), isEnabled: true,
                                                sessions: [session(.codex, "api", waiting: true),
                                                           session(.codex, "api-v2", waiting: true)], send: send)
        #expect(exact.receipt != nil, "an exact project name beats a longer one that starts the same")
        let fuzzy = AssistantAgentReply.perform(.init(agent: "Codex", project: "ap", message: "hi"), isEnabled: true,
                                                sessions: [session(.codex, "api", waiting: true),
                                                           session(.codex, "app", waiting: true)], send: send)
        #expect(fuzzy.receipt == nil)
        let off = AssistantAgentReply.perform(codex, isEnabled: false, sessions: [session(.codex, "api", waiting: true)],
                                              send: send)
        #expect(off.receipt == nil)
        let empty = AssistantAgentReply.perform(.init(agent: "Codex", project: nil, message: ""), isEnabled: true,
                                                sessions: [session(.codex, "api", waiting: true)], send: send)
        #expect(empty.receipt == nil)
        let gone = AssistantAgentReply.perform(codex, isEnabled: true, sessions: [session(.codex, "api", waiting: true)]) { _, _ in false }
        #expect(gone.receipt == nil)
        #expect(sends == 2, "only the ones it could tell apart")
    }
}

/// Ask's music tool reads Altillo's Now Playing first (any app), only while it's listening anyway.
@MainActor
struct AssistantNowPlayingTests {
    private func track(_ title: String, app: String = "Safari", playing: Bool = true) -> NowPlayingStore.Track {
        NowPlayingStore.Track(title: title, artist: "Rosalía", album: "Motomami", duration: 185, elapsed: 62,
                              isPlaying: playing, appBundleID: "com.apple.Safari", appName: app)
    }

    @Test func theStoreAnswersForAnyApp() {
        let reading = AssistantNowPlaying.StoreReading(isListening: true, track: track("Saoko"))
        let answer = AssistantNowPlaying.answer(from: reading)
        #expect(answer == "Playing in Safari: \"Saoko\" by Rosalía, from \"Motomami\" (1:02 of 3:05).")
    }

    @Test func aStoreThatIsntListeningOrHasNothingFallsBack() {
        #expect(AssistantNowPlaying.answer(from: .init(isListening: false, track: track("Saoko"))) == nil,
                "a track heard earlier may be stale")
        #expect(AssistantNowPlaying.answer(from: .init(isListening: true, track: nil)) == nil)
        #expect(AssistantNowPlaying.answer(from: .init(isListening: true, track: track("  "))) == nil)
    }

    @Test func theToolUsesTheStoreBeforeThePlayers() async {
        let answer = await AssistantNowPlaying.read { .init(isListening: true, track: track("Episode 12", app: "Podcasts")) }
        #expect(answer.hasPrefix("Playing in Podcasts: \"Episode 12\""))
    }

    @Test func theChipNamesTheAppThatsPlaying() {
        let listening = AssistantNowPlaying.StoreReading(isListening: true, track: track("Saoko", app: "Chrome"))
        #expect(AssistantSuggestion.playingApp(store: listening, runningPlayer: "Music") == "Chrome")
        let paused = AssistantNowPlaying.StoreReading(isListening: true, track: track("Saoko", playing: false))
        #expect(AssistantSuggestion.playingApp(store: paused, runningPlayer: "Spotify") == "Spotify")
        #expect(AssistantSuggestion.playingApp(store: .none, runningPlayer: nil) == nil)
    }
}
