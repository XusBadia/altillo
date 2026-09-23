import AltilloCore
import AppKit
import Foundation
import FoundationModels
import Testing
@testable import Altillo

/// The assistant's plain logic, none of it needing the model: what the tools read and say, the chips, the words
/// for failures, and when the notch must stay open.
@MainActor
struct AssistantTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A scratch folder per test, removed afterwards by the caller.
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("altillo-assistant-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func file(_ name: String, in folder: URL, _ contents: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func item(_ url: URL, addedAt: Date? = nil) -> ShelfItem {
        ShelfItem(kind: .file(url, isOwnedCopy: false), displayName: url.lastPathComponent, addedAt: addedAt ?? now)
    }

    // MARK: - Truncation

    @Test func shortTextIsLeftAlone() {
        #expect(AssistantContent.truncate("Hola", to: 100) == "Hola")
    }

    @Test func longTextIsCutOnAWordAndSaysSo() {
        let text = String(repeating: "palabra ", count: 1_000)
        let cut = AssistantContent.truncate(text, to: 300)
        #expect(cut.count <= 300)
        #expect(cut.hasSuffix("[…cut: the rest isn't shown]"))
        #expect(!cut.contains("palab\n"), "words aren't sliced in half")
    }

    @Test func everyToolOutputFitsTheBudget() throws {
        let huge = String(repeating: "x", count: 50_000)
        let note = ShelfItem(kind: .text(huge), displayName: "Huge note", addedAt: now)
        #expect(AssistantContent.text(of: note).count <= AssistantContent.toolOutputLimit)
        #expect(AssistantContent.clipboard(types: ["public.utf8-plain-text"], text: huge, fileNames: []).count
            <= AssistantContent.toolOutputLimit)
    }

    // MARK: - Reading each kind

    @Test func readsPlainTextMarkdownAndSource() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let notes = try file("notes.txt", in: folder, "Buy milk\nCall Ana")
        let readme = try file("README.md", in: folder, "# Altillo\nA place up there.")
        let code = try file("main.swift", in: folder, "print(\"hola\")")

        #expect(AssistantContent.text(of: item(notes)).contains("Call Ana"))
        #expect(AssistantContent.text(of: item(readme)).contains("A place up there."))
        #expect(AssistantContent.text(of: item(code)).contains("print(\"hola\")"))
        #expect(AssistantContent.readable(of: code) == .plainText)
    }

    @Test func readsRichText() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("letter.rtf")
        let rich = NSAttributedString(string: "Dear Marta, the shelf is ready.")
        let data = try rich.data(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        try data.write(to: url)
        #expect(AssistantContent.readable(of: url) == .richText)
        let text = AssistantContent.text(of: item(url))
        #expect(text.contains("Dear Marta, the shelf is ready."))
        #expect(!text.contains("rtf1"), "the RTF markup is gone")
    }

    @Test func readsAPDF() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("invoice.pdf")
        // A one-page PDF drawn with Core Text, so it has a real text layer.
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 300, height: 200)
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: "Invoice 42 total 120 EUR",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        ))
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        try (data as Data).write(to: url)

        #expect(AssistantContent.readable(of: url) == .pdf)
        #expect(AssistantContent.text(of: item(url)).contains("Invoice 42"))
    }

    @Test func textNotesAndLinksNeedNoDisk() {
        let note = ShelfItem(kind: .text("Wi-Fi: altillo-5G"), displayName: "Wi-Fi", addedAt: now)
        #expect(AssistantContent.text(of: note).contains("altillo-5G"))

        let link = ShelfItem(kind: .link(URL(string: "https://example.com/a")!), displayName: "Example", addedAt: now)
        let text = AssistantContent.text(of: link)
        #expect(text.contains("https://example.com/a"))
        #expect(text.contains("aren't opened"), "links are never fetched")
    }

    @Test func binariesMissingFilesAndFoldersAreExplainedNotRead() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try file("photo.png", in: folder, "not really a png")
        _ = try file("a.txt", in: folder, "a")
        _ = try file("b.txt", in: folder, "b")

        #expect(AssistantContent.readable(of: image) == nil)
        #expect(AssistantContent.text(of: item(image)).contains("can't be read"))
        #expect(AssistantContent.text(of: item(folder.appendingPathComponent("gone.txt"))).contains("isn't where it was"))
        let listing = AssistantContent.readFile(at: folder)
        #expect(listing.contains("a.txt") && listing.contains("b.txt"))
    }

    // MARK: - Shelf listing and finding

    @Test func listingIsNewestFirstWithKindsSizesAndAges() {
        let items = [
            ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/Report.pdf"), isOwnedCopy: false),
                      displayName: "Report.pdf", addedAt: now.addingTimeInterval(-3 * 86_400)),
            ShelfItem(kind: .text("hello"), displayName: "hello", addedAt: now.addingTimeInterval(-300)),
            ShelfItem(kind: .link(URL(string: "https://apple.com")!), displayName: "Apple", addedAt: now),
        ]
        let listing = AssistantContent.listing(items, now: now) { _ in 1_500_000 }
        let lines = listing.split(separator: "\n").map(String.init)
        #expect(lines.first == "3 things on the shelf, newest first:")
        #expect(lines[1].hasPrefix("- \"Apple\", link, https://apple.com, added just now"))
        #expect(lines[2] == "- \"hello\", text note, 5 characters, added 5 min ago")
        #expect(lines[3].contains("\"Report.pdf\", PDF file, "))
        #expect(lines[3].contains("MB"))
        #expect(lines[3].hasSuffix("added 3 days ago"))
    }

    @Test func anEmptyShelfSaysSo() {
        #expect(AssistantContent.listing([], now: now) { _ in nil } == "The shelf is empty.")
        #expect(AssistantContent.shelfAnswer(name: nil, items: [], now: now) == "The shelf is empty.")
    }

    @Test func longShelvesAreSummarised() {
        let items = (0..<30).map { ShelfItem(kind: .text("\($0)"), displayName: "note \($0)", addedAt: now) }
        let listing = AssistantContent.listing(items, now: now) { _ in nil }
        #expect(listing.contains("…and 10 older ones."))
    }

    @Test func findsTheItemTheModelMeans() {
        let older = ShelfItem(kind: .text("a"), displayName: "Presupuesto cocina.pdf", addedAt: now.addingTimeInterval(-60))
        let newer = ShelfItem(kind: .text("b"), displayName: "Notas reunión.md", addedAt: now)
        let items = [older, newer]
        #expect(AssistantContent.find("Presupuesto cocina.pdf", in: items) == older)
        #expect(AssistantContent.find("presupuesto cocina", in: items) == older, "without the extension")
        #expect(AssistantContent.find("“notas reunion”", in: items) == newer, "quotes, case and accents don't matter")
        #expect(AssistantContent.find("cocina", in: items) == older, "part of the name")
        #expect(AssistantContent.find("the file Notas reunión please", in: items) == newer, "the name inside a phrase")
        #expect(AssistantContent.find("taxes", in: items) == nil)
        #expect(AssistantContent.find("  ", in: items) == nil)
    }

    @Test func askingForAMissingItemListsWhatThereIs() {
        let items = [ShelfItem(kind: .text("x"), displayName: "Groceries", addedAt: now)]
        let answer = AssistantContent.shelfAnswer(name: "Taxes 2025", items: items, now: now)
        #expect(answer.hasPrefix("Nothing on the shelf is called \"Taxes 2025\"."))
        #expect(answer.contains("Groceries"))
    }

    @Test func aBareListingAlsoCarriesTheNewestText() {
        let items = [
            ShelfItem(kind: .text("Launch on 3 October"), displayName: "Kickoff", addedAt: now),
            ShelfItem(kind: .link(URL(string: "https://apple.com")!), displayName: "Apple", addedAt: now),
        ]
        let answer = AssistantContent.shelfAnswer(name: nil, items: items, now: now)
        #expect(answer.contains("Text of \"Kickoff\":\nLaunch on 3 October"))
        #expect(!answer.contains("Text of \"Apple\""), "links have no text to preview")
        #expect(AssistantContent.shelfAnswer(name: "the kickoff note", items: items, now: now).contains("Launch on 3 October"),
                "a description instead of a name still reaches the text")
    }

    // MARK: - Calendar, music, clipboard words

    @Test func agendaMarksWhatIsOverAndWhatIsHappening() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Madrid"))
        let day = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0) -> Date { day.addingTimeInterval(Double(hour * 3_600 + minute * 60)) }
        let clock = at(10, 15)
        let events = [
            CalendarStore.Event(id: "1", title: "Stand-up", start: at(9), end: at(9, 15), calendarColorHex: 0,
                                location: nil, conferenceURL: nil, isAllDay: false),
            CalendarStore.Event(id: "2", title: "Design review", start: at(10), end: at(11), calendarColorHex: 0,
                                location: "Room B", conferenceURL: URL(string: "https://meet.google.com/x"), isAllDay: false),
            CalendarStore.Event(id: "3", title: "Holiday", start: day, end: at(24), calendarColorHex: 0,
                                location: nil, conferenceURL: nil, isAllDay: true),
        ]
        let agenda = AssistantContent.agenda(events, day: day, now: clock, calendar: calendar)
        let lines = agenda.split(separator: "\n").map(String.init)
        #expect(lines[0].hasSuffix("(today): 3 events."))
        #expect(lines[1] == "- all day: Holiday")
        #expect(lines[2] == "- 09:00–09:15 Stand-up (over)")
        #expect(lines[3] == "- 10:00–11:00 Design review · at Room B · video call (happening now)")

        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        #expect(AssistantContent.agenda([], day: tomorrow, now: clock, calendar: calendar).hasSuffix("(tomorrow): no events."))
    }

    @Test func nowPlayingReadsLikeASentence() {
        let snapshot = PlayerSnapshot(isPlaying: true, title: "Teardrop", artist: "Massive Attack", album: "Mezzanine",
                                      duration: 330, elapsed: 65, trackID: "t", artworkURL: nil)
        #expect(AssistantContent.nowPlaying(snapshot, app: "Spotify")
            == "Playing in Spotify: \"Teardrop\" by Massive Attack, from the album \"Mezzanine\" (1:05 of 5:30).")
        var paused = snapshot
        paused.isPlaying = false
        paused.album = nil
        paused.duration = nil
        #expect(AssistantContent.nowPlaying(paused, app: "Music") == "Paused in Music: \"Teardrop\" by Massive Attack.")
        #expect(AssistantContent.clock(3_729) == "1:02:09")
    }

    @Test func automationPermissionIsReadWithoutAsking() {
        #expect(AssistantNowPlaying.permission(status: 0) == .granted)
        #expect(AssistantNowPlaying.permission(status: -1743) == .denied)
        #expect(AssistantNowPlaying.permission(status: -1744) == .notAsked)
        #expect(AssistantNowPlaying.permission(status: -600) == .notRunning)
    }

    @Test func clipboardKeepsSecretsSecret() {
        let text = "public.utf8-plain-text"
        #expect(AssistantContent.clipboard(types: [text, "org.nspasteboard.ConcealedType"], text: "hunter2", fileNames: [])
            .contains("marked private"))
        #expect(!AssistantContent.clipboard(types: [text, "org.nspasteboard.TransientType"], text: "hunter2", fileNames: [])
            .contains("hunter2"))
        #expect(AssistantContent.clipboard(types: [text], text: "hunter2", fileNames: [], isDenied: true)
            .contains("isn't allowed"))
        #expect(AssistantContent.clipboard(types: [text], text: "Tracking: 1Z999", fileNames: []).contains("Tracking: 1Z999"))
        #expect(AssistantContent.clipboard(types: ["public.file-url"], text: nil, fileNames: ["a.pdf"]).contains("\"a.pdf\""))
        #expect(AssistantContent.clipboard(types: [], text: nil, fileNames: []) == "The clipboard is empty.")
    }

    @Test func clipboardDetectionOnlyLooksAtTypes() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("altillo-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("hola", forType: .string)
        #expect(AssistantContent.clipboardHasText(pasteboard))
        #expect(AssistantContent.readClipboard(pasteboard).contains("hola"))

        pasteboard.clearContents()
        pasteboard.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil)
        pasteboard.setString("secret", forType: .string)
        #expect(!AssistantContent.clipboardHasText(pasteboard))
        #expect(!AssistantContent.readClipboard(pasteboard).contains("secret"))
    }

    // MARK: - Suggestions

    @Test func chipsFollowWhatIsThere() {
        let all = AssistantSuggestion.make(.init(
            calendarGranted: true, readableShelfItem: "Informe.pdf", runningPlayer: "Spotify", clipboardHasText: true
        ))
        #expect(all.map(\.kind) == [.today, .summarize, .playing])
        #expect(all[1].title == "Summarize “Informe.pdf”")
        #expect(all[1].prompt.contains("Informe.pdf"))
        #expect(all[2].prompt.contains("Spotify"))

        let clipboardOnly = AssistantSuggestion.make(.init(clipboardHasText: true))
        #expect(clipboardOnly.map(\.kind) == [.clipboard, .capabilities])

        let nothing = AssistantSuggestion.make(.init())
        #expect(nothing.map(\.kind) == [.capabilities, .reply])
    }

    @Test func theNewestReadableShelfItemIsTheOneToSummarise() {
        let items = [
            ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/old.pdf"), isOwnedCopy: false), displayName: "old.pdf",
                      addedAt: now.addingTimeInterval(-600)),
            ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/new.md"), isOwnedCopy: false), displayName: "new.md",
                      addedAt: now.addingTimeInterval(-60)),
            ShelfItem(kind: .file(URL(fileURLWithPath: "/tmp/photo.jpg"), isOwnedCopy: false), displayName: "photo.jpg",
                      addedAt: now),
            ShelfItem(kind: .link(URL(string: "https://apple.com")!), displayName: "Apple", addedAt: now),
        ]
        #expect(AssistantSuggestion.readableItem(in: items)?.displayName == "new.md")
        #expect(AssistantSuggestion.readableItem(in: [items[2], items[3]]) == nil)
    }

    @Test func longNamesAreShortenedKeepingTheExtension() {
        let short = AssistantFormat.shortName("Presupuesto reforma cocina definitivo.pdf")
        #expect(short.count <= 22)
        #expect(short.hasSuffix("ivo.pdf"))
        #expect(AssistantFormat.shortName("a.pdf") == "a.pdf")
    }

    // MARK: - Failures

    @Test func failuresBecomeFriendlyWords() {
        let context = LanguageModelSession.GenerationError.Context(debugDescription: "test")
        typealias GenerationError = LanguageModelSession.GenerationError
        #expect(AssistantFailure(GenerationError.exceededContextWindowSize(context)) == .contextFull)
        #expect(AssistantFailure(GenerationError.guardrailViolation(context)) == .guardrail)
        #expect(AssistantFailure(GenerationError.unsupportedLanguageOrLocale(context)) == .language)
        #expect(AssistantFailure(GenerationError.assetsUnavailable(context)) == .notReady)
        #expect(AssistantFailure(GenerationError.rateLimited(context)) == .busy)
        #expect(AssistantFailure(GenerationError.concurrentRequests(context)) == .busy)
        #expect(AssistantFailure(GenerationError.refusal(.init(transcriptEntries: []), context)) == .refused)
        #expect(AssistantFailure(GenerationError.decodingFailure(context)) == .other)
        #expect(AssistantFailure(CocoaError(.fileReadUnknown)) == .other)

        let messages: [AssistantFailure] = [.contextFull, .guardrail, .language, .notReady, .busy, .refused, .other, .tool("calendar")]
        for failure in messages {
            #expect(!failure.message.isEmpty)
            #expect(!failure.message.localizedCaseInsensitiveContains("error"), "no jargon: \(failure.message)")
        }
        #expect(AssistantFailure.tool("calendar").message.contains("calendar"))
    }

    // MARK: - Words

    @Test func thePeekShowsTheOpeningWordsWithoutMarkdown() {
        #expect(AssistantFormat.peekTitle("**You're free** after 17:00. Enjoy!") == "You're free after 17:00.")
        let long = AssistantFormat.peekTitle(String(repeating: "word ", count: 40))
        #expect(long.count <= 48)
        #expect(long.hasSuffix("…"))
        #expect(AssistantFormat.peekTitle("   ") == "Your answer is ready")
    }

    @Test func markdownIsRenderedInlineAndStrippedForCopies() {
        let answer = "## Today\n- **10:30** Design\n- `17:00` Review"
        #expect(AssistantFormat.plainText(answer) == "Today\n- 10:30 Design\n- 17:00 Review")
        let rendered = AssistantFormat.rendered("A *little* [link](https://apple.com)")
        #expect(String(rendered.characters) == "A little link")
        #expect(rendered.runs.contains { $0.link == URL(string: "https://apple.com") })
    }

    @Test func instructionsCarryTheDateAndStayShort() throws {
        let madrid = try #require(TimeZone(identifier: "Europe/Madrid"))
        let text = AssistantInstructions.text(now: now, locale: Locale(identifier: "es_ES"), timeZone: madrid)
        #expect(text.contains("Europe/Madrid"))
        #expect(text.contains("2026"))
        #expect(text.contains("region: ES"))
        #expect(text.count < 1_000, "instructions are paid for on every turn")

        let recap = AssistantInstructions.recap([
            (question: "One", answer: "First"),
            (question: "Two", answer: String(repeating: "long ", count: 200)),
            (question: "Three", answer: "Third"),
        ])
        #expect(!recap.contains("One"), "only the last two exchanges are carried")
        #expect(recap.contains("User: Two") && recap.contains("You: Third"))
        #expect(recap.count < 700)
    }

    @Test func questionsInAnotherLanguageAskForAnAnswerInIt() {
        #expect(AssistantInstructions.prompt(for: "¿Qué tengo hoy en el calendario y qué he copiado?")
            .hasSuffix("(Reply in Spanish.)"))
        #expect(AssistantInstructions.prompt(for: "What do I have on my calendar today?")
            == "What do I have on my calendar today?")
    }

    @Test func answersPutUpAreNamedAfterTheirQuestion() {
        #expect(AssistantFormat.shelfName(question: "What do I have today?") == "What do I have today?")
        let long = AssistantFormat.shelfName(question: String(repeating: "a", count: 80))
        #expect(long.count == 48 && long.hasSuffix("…"))
    }

    // MARK: - Holding the notch open

    @Test func theNotchStaysOpenWhileTypingOrAnswering() {
        #expect(!AssistantStore.holdsOpen(isFieldFocused: false, draft: "", isResponding: false))
        #expect(!AssistantStore.holdsOpen(isFieldFocused: false, draft: "  \n", isResponding: false))
        #expect(AssistantStore.holdsOpen(isFieldFocused: true, draft: "", isResponding: false))
        #expect(AssistantStore.holdsOpen(isFieldFocused: false, draft: "¿Qué", isResponding: false))
        #expect(AssistantStore.holdsOpen(isFieldFocused: false, draft: "", isResponding: true))

        let store = AssistantStore()
        #expect(!store.holdsOpen)
        store.draft = "Hola"
        #expect(store.holdsOpen)
        store.draft = ""
        store.isFieldFocused = true
        #expect(store.holdsOpen)
    }

    @Test func aFocusRequestIsTakenOnce() {
        let store = AssistantStore()
        #expect(!store.takeFocusRequest())
        store.requestFocus()
        #expect(store.takeFocusRequest())
        #expect(!store.takeFocusRequest(), "a request made before the view appeared is honoured once, not forever")
    }

    @Test func puttingAnAnswerUpMakesATextItem() {
        let store = AssistantStore()
        var added: [ShelfItem] = []
        store.context.addToShelf = { added += $0 }
        store.putUp(AssistantStore.Exchange(question: "Plan?", answer: "**Rest** and read.", status: .done))
        #expect(added.count == 1)
        #expect(added.first?.displayName == "Plan?")
        if case let .text(text) = added.first?.kind {
            #expect(text == "Rest and read.")
        } else {
            Issue.record("expected a text item")
        }
    }

    @Test func headingsNeverShowTheirHashes() {
        #expect(AssistantFormat.boldHeadings("## Summary\n- one") == "**Summary**\n- one")
        #expect(AssistantFormat.boldHeadings("#hashtag stays") == "#hashtag stays")
        #expect(!String(AssistantFormat.rendered("### Plan").characters).contains("#"))
    }
}
