import AltilloCore
import CoreGraphics
import Foundation
import FoundationModels
import Testing
@testable import Altillo

/// Phase 12's timer and note: timers scheduled from absolute dates (sleep, relaunch, several at once, pause),
/// the dial's snapping, reading "10 min" or "1h 30", the note saving as you type, Ask's `timer` and `note` tools
/// and their routing, and the notch staying open while typing.
@MainActor
struct TimerNoteTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// "Now", moved by hand.
    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
        func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
    }

    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("altillo-timer-note-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        TestDefaultsJanitor.purgeStale()
        let suite = "me.badia.altillo.tests.timernote.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    /// A store on a hand-moved clock that records its alerts and rings instead of playing them.
    private func makeTimers(_ clock: Clock, url: URL? = nil) -> (TimerStore, Box) {
        let store = TimerStore(storeURL: url)
        let box = Box()
        store.now = { clock.now }
        store.soundEnabled = { true }
        store.playSound = { box.sounds += 1 }
        store.postAlert = { box.alerts.append($0) }
        return (store, box)
    }

    private final class Box {
        var alerts: [NotchAlert] = []
        var sounds = 0
    }

    // MARK: - Scheduling from absolute dates

    @Test func aTimerRingsAtItsEndDateOnce() {
        let clock = Clock(start)
        let (store, box) = makeTimers(clock)
        let timer = store.start(seconds: 600, label: "Pasta")
        #expect(timer.endsAt == start.addingTimeInterval(600))
        // It sleeps until its last minute, then until it rings: never polling.
        #expect(TimerLogic.nextBoundary(store.timers, now: start) == start.addingTimeInterval(540))
        #expect(TimerLogic.nextBoundary(store.timers, now: start.addingTimeInterval(540)) == start.addingTimeInterval(600))

        clock.advance(599)
        store.wake()
        #expect(box.alerts.isEmpty && store.timers[0].isRunning)

        clock.advance(1)
        store.wake()
        #expect(store.timers[0].rangAt == start.addingTimeInterval(600))
        #expect(box.alerts.count == 1 && box.sounds == 1 && store.ringCount == 1)
        let alert = box.alerts.first
        #expect(alert?.title == "Pasta: time's up")
        #expect(alert?.isUrgent == true && alert?.module == .timer && alert?.source == .timer)
        #expect(alert?.detail == nil, "on time: no 'at …'")

        store.wake()
        #expect(box.alerts.count == 1, "a timer rings once")
        // Once rung, it only has one more boundary: leaving the contextual ear.
        #expect(TimerLogic.nextBoundary(store.timers, now: clock.now) == start.addingTimeInterval(600 + 300))
    }

    @Test func soundFollowsTheSetting() {
        let clock = Clock(start)
        let (store, box) = makeTimers(clock)
        store.soundEnabled = { false }
        store.start(seconds: 60)
        clock.advance(60)
        store.wake()
        #expect(box.alerts.count == 1 && box.sounds == 0)
    }

    @Test func wakingFromSleepRecomputesFromTheEndDate() {
        let clock = Clock(start)
        let (store, box) = makeTimers(clock)
        store.start(seconds: 600, label: "Tea")
        store.start(seconds: 600, label: "Bread")
        store.pause(store.timers[1].id)
        // The Mac slept 3 minutes past the end: it still peeks, saying when it rang.
        clock.advance(780)
        store.wake()
        #expect(store.timers[0].rangAt == start.addingTimeInterval(600))
        #expect(box.alerts.count == 1)
        #expect(box.alerts.first?.detail?.hasPrefix("at ") == true)
        #expect(store.timers[1].isPaused, "a paused timer doesn't run while the Mac sleeps")
        #expect(store.timers[1].remaining(at: clock.now) == 600)
    }

    @Test func aLongSleepRingsQuietly() {
        let clock = Clock(start)
        let (store, box) = makeTimers(clock)
        store.start(seconds: 60)
        clock.advance(60 + TimerLogic.lateRingWindow + 1)
        store.wake()
        #expect(store.timers[0].hasRung)
        #expect(box.alerts.isEmpty && box.sounds == 0, "news from long ago isn't worth a peek")
    }

    @Test func runningTimersSurviveARelaunch() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "timers.json")
        let clock = Clock(start)
        let (first, _) = makeTimers(clock, url: url)
        let pasta = first.start(seconds: 600, label: "Pasta")
        let pomodoro = first.start(seconds: 1_500, label: "Pomodoro")
        first.pause(pomodoro.id)

        // Relaunched four minutes later.
        clock.advance(240)
        let (second, box) = makeTimers(clock, url: url)
        second.restore()
        #expect(second.timers.map(\.id) == [pasta.id, pomodoro.id])
        #expect(second.timer(pasta.id)?.remaining(at: clock.now) == 360)
        #expect(second.timer(pomodoro.id)?.isPaused == true)

        // Relaunched after the pasta was done: it rings on the first wake.
        clock.advance(400)
        let (third, thirdBox) = makeTimers(clock, url: url)
        third.restore()
        third.wake()
        #expect(third.timer(pasta.id)?.hasRung == true)
        #expect(thirdBox.alerts.count == 1)
        #expect(box.alerts.isEmpty)
    }

    @Test func oldRungTimersAreClearedOnLaunch() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "timers.json")
        let clock = Clock(start)
        let (first, _) = makeTimers(clock, url: url)
        first.start(seconds: 60)
        clock.advance(60)
        first.wake()
        clock.advance(TimerLogic.staleRungAge + 1)
        let (second, _) = makeTimers(clock, url: url)
        second.restore()
        #expect(second.timers.isEmpty)
    }

    @Test func severalTimersRingInTurn() {
        let clock = Clock(start)
        let (store, box) = makeTimers(clock)
        store.start(seconds: 1_500, label: "Pomodoro")
        store.start(seconds: 600, label: "Pasta")
        #expect(store.ordered.map(\.label) == ["Pasta", "Pomodoro"], "the soonest to ring first")
        clock.advance(600)
        store.wake()
        #expect(box.alerts.map(\.title) == ["Pasta: time's up"])
        #expect(store.ordered.map(\.label) == ["Pasta", "Pomodoro"], "the one ringing leads")
        clock.advance(900)
        store.wake()
        #expect(box.alerts.map(\.title) == ["Pasta: time's up", "Pomodoro: time's up"])
    }

    @Test func pauseResumeResetAndRestart() {
        let clock = Clock(start)
        let (store, _) = makeTimers(clock)
        let id = store.start(seconds: 600).id
        clock.advance(120)
        store.pause(id)
        #expect(store.timer(id)?.state == .paused(remaining: 480))
        clock.advance(300)
        #expect(store.timer(id)?.remaining(at: clock.now) == 480, "paused time doesn't pass")
        store.resume(id)
        #expect(store.timer(id)?.endsAt == clock.now.addingTimeInterval(480))
        store.reset(id)
        #expect(store.timer(id)?.state == .paused(remaining: 600))
        store.toggle(id)
        #expect(store.timer(id)?.endsAt == clock.now.addingTimeInterval(600))
        clock.advance(600)
        store.wake()
        store.restart(id)
        #expect(store.timer(id)?.endsAt == clock.now.addingTimeInterval(600))
        store.remove(id)
        #expect(store.timers.isEmpty)
    }

    @Test func askCallingItsToolTwiceSetsOneTimer() {
        let clock = Clock(start)
        let (store, _) = makeTimers(clock)
        let first = store.start(seconds: 600, label: "Pasta", origin: .ask)
        clock.advance(1)
        let second = store.start(seconds: 600, label: "Pasta", origin: .ask)
        #expect(first.id == second.id && store.timers.count == 1)
        #expect(store.lastAskTimer?.id == first.id)
        store.undoAsk(first.id)
        #expect(store.timers.isEmpty)
    }

    @Test func theContextualEarSignal() {
        let clock = Clock(start)
        let (store, _) = makeTimers(clock)
        #expect(TimerLogic.signal(store.timers, now: start) == nil)
        let paused = store.start(seconds: 60, label: "Paused")
        store.pause(paused.id)
        #expect(TimerLogic.signal(store.timers, now: start) == nil, "paused timers never take the ear")
        store.start(seconds: 300, label: "Tea")
        let running = TimerLogic.signal(store.timers, now: start)
        #expect(running?.label == "Tea" && running?.isImminent == false && running?.isRinging == false)
        #expect(TimerLogic.signal(store.timers, now: start.addingTimeInterval(241))?.isImminent == true)
        clock.advance(300)
        store.wake()
        let ringing = store.contextualSignal
        #expect(ringing?.isRinging == true && ringing?.label == "Tea")
        #expect(TimerLogic.signal(store.timers, now: clock.now.addingTimeInterval(301)) == nil,
                "after five minutes it leaves the ear")
    }

    @Test func aTimerAboutToRingOutranksTheMusic() {
        let song = PlaybackSignal(title: "Teardrop", artist: "Massive Attack", appName: "Spotify")
        let usage = UsageSignal(providerName: "Claude", fraction: 0.9)
        let running = TimerSignal(label: "Tea", endsAt: start.addingTimeInterval(600), isRinging: false,
                                  isImminent: false, runningCount: 1)
        var imminent = running
        imminent.isImminent = true
        let all = Set(NotchModule.allCases)
        let agent = AgentRequestSignal(agentName: "Claude", project: "altillo")

        #expect(NotchActivityLogic.resolve(.init(playback: song, usage: usage, timer: running), enabled: all, now: start)
            == .playback(song))
        #expect(NotchActivityLogic.resolve(.init(playback: song, usage: usage, timer: imminent), enabled: all, now: start)
            == .timer(imminent))
        #expect(NotchActivityLogic.resolve(.init(usage: usage, timer: running), enabled: all, now: start)
            == .timer(running), "a running timer beats AI usage")
        #expect(NotchActivityLogic.resolve(.init(agentRequest: agent, timer: imminent), enabled: all, now: start)
            == .agentRequest(agent), "an agent knocking still comes first")
        #expect(NotchActivityLogic.resolve(.init(timer: imminent), enabled: all.subtracting([.timer]), now: start)
            == .rest, "only with the section on")
        #expect(NotchActivity.timer(running).module == .timer)
        #expect(NotchActivityLogic.accessibilityLabel(for: .timer(TimerSignal(
            label: "Tea", endsAt: start, isRinging: true, isImminent: true, runningCount: 0)), now: start)
            == "Tea: time's up")
    }

    @Test func theEarCountdownOnlyRedrawsWhenItsTextChanges() {
        let end = start.addingTimeInterval(125)
        let entries = Array(DesvanTimerCountdownSchedule(end: end).entries(from: start, mode: .normal).prefix(100))
        #expect(entries.first == start)
        #expect(entries[1] == end.addingTimeInterval(-120))
        #expect(entries[2] == end.addingTimeInterval(-60))
        #expect(entries[3] == end.addingTimeInterval(-59))
        #expect(entries.last == end)
        #expect(entries.count == 3 + 60, "minutes, then seconds, then nothing")
        #expect(TimerFormat.ear(125) == "3m" && TimerFormat.ear(42) == "0:42" && TimerFormat.ear(5_400) == "1h30")
    }

    // MARK: - The dial

    @Test func theDialSnapsToMinutesClockwiseFromTwelve() {
        let center = CGPoint(x: 50, y: 50)
        #expect(TimerDial.angle(of: CGPoint(x: 50, y: 0), around: center) == 0)
        #expect(abs(TimerDial.angle(of: CGPoint(x: 100, y: 50), around: center) - 90) < 0.001)
        #expect(abs(TimerDial.angle(of: CGPoint(x: 50, y: 100), around: center) - 180) < 0.001)
        #expect(abs(TimerDial.angle(of: CGPoint(x: 0, y: 50), around: center) - 270) < 0.001)

        #expect(TimerDial.minutes(forAngle: 90, previous: 10) == 15)
        #expect(TimerDial.minutes(forAngle: 62.9, previous: 10) == 10)
        #expect(TimerDial.minutes(forAngle: 63.1, previous: 10) == 11)
        #expect(TimerDial.sweep(forSeconds: 900) == 90)
        #expect(TimerDial.sweep(forSeconds: 7_200) == 360, "more than an hour fills the face")
    }

    @Test func theDialStopsAtItsEndsInsteadOfWrapping() {
        // Winding up past 12 o'clock sticks at 60…
        #expect(TimerDial.minutes(forAngle: 3, previous: 58) == 60)
        #expect(TimerDial.minutes(forAngle: 20, previous: 60) == 60)
        // …and coming back from 60 works.
        #expect(TimerDial.minutes(forAngle: 330, previous: 60) == 55)
        // Winding down past zero sticks at 0.
        #expect(TimerDial.minutes(forAngle: 354, previous: 2) == 0)
        #expect(TimerDial.minutes(forAngle: 340, previous: 0) == 0)
    }

    @Test func hapticTicksEveryFiveMinutesAndArrowSteps() {
        #expect(TimerDial.crossesFiveMinuteMark(from: 4, to: 5))
        #expect(TimerDial.crossesFiveMinuteMark(from: 6, to: 5))
        #expect(TimerDial.crossesFiveMinuteMark(from: 9, to: 11))
        #expect(!TimerDial.crossesFiveMinuteMark(from: 6, to: 7))
        #expect(!TimerDial.crossesFiveMinuteMark(from: 5, to: 5))
        #expect(TimerDial.step(59, by: 1) == 60 && TimerDial.step(60, by: 1) == 60)
        #expect(TimerDial.step(0, by: -1) == 0 && TimerDial.step(10, by: -1) == 9)
    }

    // MARK: - Reading durations

    @Test func readsDurationsTheWayPeopleSayThem() {
        let cases: [(String, TimeInterval)] = [
            ("10", 600), ("10 min", 600), ("10min", 600), ("25 minutes", 1_500), ("25-minute", 1_500),
            ("1h 30", 5_400), ("1h30", 5_400), ("1 h 30 min", 5_400), ("1 hour 30 minutes", 5_400),
            ("90 s", 90), ("30 seconds", 30), ("1:30", 90), ("2.5 min", 150), ("1,5 horas", 5_400),
            ("an hour", 3_600), ("an hour and a half", 5_400), ("half an hour", 1_800),
            ("media hora", 1_800), ("una hora y media", 5_400), ("hora y media", 5_400), ("diez minutos", 600),
            ("cinco minutos", 300), ("un quart d'hora", 900), ("mitja hora", 1_800), ("vint minuts", 1_200),
        ]
        for (text, seconds) in cases {
            #expect(TimerDurationParser.seconds(in: text) == seconds, "\(text)")
        }
        #expect(TimerDurationParser.seconds(in: "hello") == nil)
        #expect(TimerDurationParser.seconds(in: "0 min") == nil)
        #expect(TimerDurationParser.seconds(in: "30 hours") == nil, "longer than a day")
    }

    @Test func keepsTheRestAsTheLabel() {
        #expect(TimerDurationParser.parse("10 pasta") == .init(seconds: 600, label: "Pasta"))
        #expect(TimerDurationParser.parse("Pomodoro 25") == .init(seconds: 1_500, label: "Pomodoro"))
        #expect(TimerDurationParser.parse("pon un temporizador de 10 min para la pasta")
            == .init(seconds: 600, label: "Pasta"))
        #expect(TimerDurationParser.parse("set a 25 minute timer") == .init(seconds: 1_500, label: nil))
        #expect(TimerDurationParser.parse("1h 30 Café")?.label == "Café", "as typed")
    }

    @Test func aBareNumberNeedsItsUnitWhenAsked() {
        #expect(TimerDurationParser.seconds(in: "pon 3 ejemplos", bareNumbersAreMinutes: false) == nil)
        #expect(TimerDurationParser.seconds(in: "pon 10 min", bareNumbersAreMinutes: false) == 600)
        #expect(TimerDurationParser.seconds(in: "1h 30", bareNumbersAreMinutes: false) == 5_400)
    }

    // MARK: - The note

    @Test func theNoteSavesAfterTypingPauses() async throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folder: folder, saveDelay: .milliseconds(300))
        store.load()
        for text in ["B", "Bu", "Buy", "Buy m", "Buy milk"] {
            store.text = text
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(store.saveCount == 0, "nothing written while typing")
        try await Task.sleep(for: .milliseconds(800))
        #expect(store.saveCount == 1, "one write once typing pauses")
        #expect(try String(contentsOf: folder.appending(path: "note.txt"), encoding: .utf8) == "Buy milk")

        // A fresh store (the next launch) reads it back without writing.
        let reopened = NoteStore(folder: folder, saveDelay: .milliseconds(80))
        reopened.load()
        #expect(reopened.text == "Buy milk" && reopened.saveCount == 0)
    }

    @Test func leavingTheSectionWritesAtOnce() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folder: folder, saveDelay: .seconds(60))
        store.start()
        store.text = "Call Ana"
        store.stop()
        #expect(try String(contentsOf: folder.appending(path: "note.txt"), encoding: .utf8) == "Call Ana")
    }

    @Test func clearUndoNewNoteAndHistory() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folder: folder, saveDelay: .seconds(60))
        store.load()
        store.text = "Shopping"
        store.clear()
        #expect(store.text.isEmpty && store.clearedText == "Shopping")
        store.undoClear()
        #expect(store.text == "Shopping" && store.clearedText == nil)
        store.clear()
        store.text = "x"
        #expect(store.clearedText == nil, "typing again drops the undo")

        for index in 1...7 {
            store.text = "Note \(index)"
            store.newNote()
        }
        #expect(store.text.isEmpty)
        #expect(store.history.map(\.text) == ["Note 7", "Note 6", "Note 5", "Note 4", "Note 3"])
        store.text = "Current"
        store.restore(store.history[2].id)
        #expect(store.text == "Note 5")
        #expect(store.history.first?.text == "Current" && store.history.count == 5)

        let reopened = NoteStore(folder: folder)
        reopened.load()
        #expect(reopened.history.map(\.text) == store.history.map(\.text))
    }

    // MARK: - Ask

    @Test func askRoutesTimersAndNotesToTheTools() {
        for question in [
            "pon un temporizador de 10 min", "Set a 25 minute timer", "pon 10 min", "avísame en media hora",
            "apunta comprar leche", "Add to my note: call Ana", "write this down: the wifi is attic42",
            "¿qué temporizadores tengo?", "what's in my note?",
        ] {
            #expect(AssistantRouter.route(question) == .context, "\(question)")
        }
        #expect(AssistantRouter.route("Pon 3 ejemplos de haiku") == .chat)
        #expect(AssistantRouter.route("Write a haiku about autumn") == .chat)
    }

    @Test func askGetsTimerAndNoteTools() {
        let names = AssistantTools.all(for: .context, shelfItems: { [] }, report: { _ in }).map(\.name)
        #expect(names.contains("timer") && names.contains("note"))
        #expect(AssistantTools.all(for: .chat, shelfItems: { [] }, report: { _ in }).isEmpty)
        #expect(AssistantInstructions.text(route: .context).contains("call timer"))
        #expect(AssistantActivity.timer.isLocalContext && AssistantActivity.note.isLocalContext)
    }

    @Test func askSetsListsAndCancelsTimers() {
        let clock = Clock(start)
        let (store, _) = makeTimers(clock)
        let set = TimerAssistant.perform(.start(duration: "10 min", label: "Pasta"), store: store, isEnabled: true,
                                         now: start)
        #expect(set.hasPrefix("Timer set: Pasta, 10 min. It rings at"))
        #expect(store.timers.count == 1 && store.timers[0].origin == .ask && store.timers[0].label == "Pasta")

        let unnamed = TimerAssistant.perform(.start(duration: "1h 30", label: "timer"), store: store, isEnabled: true,
                                             now: start)
        #expect(unnamed.hasPrefix("Timer set, 1 h 30 min."), "a label that only says 'timer' leaves it unnamed")

        let list = TimerAssistant.perform(.list, store: store, isEnabled: true, now: start)
        #expect(list.contains("Pasta (10 min): 10 min left"))
        #expect(list.contains("Timer (1 h 30 min)"))

        let vague = TimerAssistant.perform(.cancel(label: nil), store: store, isEnabled: true, now: start)
        #expect(vague.hasPrefix("Nothing was cancelled: which timer?") && store.timers.count == 2)
        let cancelled = TimerAssistant.perform(.cancel(label: "pasta"), store: store, isEnabled: true, now: start)
        #expect(cancelled == "Cancelled the timer Pasta (10 min).")
        #expect(store.timers.count == 1)

        let unclear = TimerAssistant.perform(.start(duration: "a while", label: nil), store: store, isEnabled: true,
                                             now: start)
        #expect(unclear.hasPrefix("No timer was set") && store.timers.count == 1)
        let off = TimerAssistant.perform(.start(duration: "5 min", label: nil), store: store, isEnabled: false,
                                         now: start)
        #expect(off.hasPrefix("The Timer section is turned off") && store.timers.count == 1)
    }

    @Test func askAddsToTheNoteAndTheNotchCanUndoIt() throws {
        let folder = try scratch()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = NoteStore(folder: folder, saveDelay: .seconds(60))
        store.text = "Shopping"
        let added = NoteAssistant.perform(.add("apunta: comprar leche"), store: store, isEnabled: true)
        #expect(added == "Added to the note: \"comprar leche\". The note now has 2 lines. Tell the user exactly that; they can undo it from the Note section of the notch.")
        #expect(store.text == "Shopping\ncomprar leche")
        #expect(try String(contentsOf: folder.appending(path: "note.txt"), encoding: .utf8) == store.text,
                "saved at once")
        #expect(NoteAssistant.perform(.read, store: store, isEnabled: true).contains("comprar leche"))

        store.undoAskAppend()
        #expect(store.text == "Shopping" && store.askAppend == nil)

        _ = NoteAssistant.perform(.add("Call Ana"), store: store, isEnabled: true)
        store.text += "!"
        #expect(store.askAppend == nil, "once the user edits, Ask's undo is gone")

        #expect(NoteAssistant.perform(.add("  "), store: store, isEnabled: true).hasPrefix("Nothing was added"))
        #expect(NoteAssistant.perform(.add("x"), store: store, isEnabled: false).hasPrefix("The Note section is turned off"))
        #expect(NoteAssistant.cleaned("Add to my note: buy bread") == "buy bread")
        #expect(NoteAssistant.cleaned("«llamar a Marta»") == "llamar a Marta")
    }

    // MARK: - Staying open while typing

    @Test func typingInTheNoteOrATimerNameHoldsTheNotchOpen() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.modules = [.shelf, .timer, .note]
        let model = NotchModel(settings: settings)
        model.state = .open
        model.jump(to: .note)
        #expect(!model.holdsOpen)
        model.note.isEditing = true
        #expect(model.holdsOpen)
        model.jump(to: .shelf)
        #expect(!model.holdsOpen, "only while the note is the section on screen")
        model.jump(to: .timer)
        model.timers.isEditingName = true
        #expect(model.holdsOpen)
        model.state = .idle
        #expect(!model.holdsOpen)
    }

    @Test func timerSoundIsOnByDefaultAndRemembered() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        #expect(settings.timerSound)
        settings.timerSound = false
        #expect(!AltilloSettings(defaults: defaults).timerSound)
    }
}
