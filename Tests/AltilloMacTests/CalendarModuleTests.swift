import CoreGraphics
import EventKit
import Foundation
import Testing
@testable import Altillo

/// The agenda's plain logic: ordering, colours, permission states and the words the notch (and VoiceOver) use.
@MainActor
struct CalendarModuleTests {
    private func event(
        _ title: String,
        start: Date,
        minutes: Double = 30,
        allDay: Bool = false,
        location: String? = nil,
        link: String? = nil
    ) -> CalendarStore.Event {
        CalendarStore.Event(
            id: title,
            title: title,
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            calendarColorHex: 0xFF00_00,
            location: location,
            conferenceURL: link.flatMap(URL.init(string:)),
            isAllDay: allDay
        )
    }

    @Test func allDayEventsComeFirstAndTheRestBySoonest() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let sorted = CalendarMapping.sorted([
            event("Tarde", start: now.addingTimeInterval(3_600)),
            event("Cumpleaños", start: now, allDay: true),
            event("Pronto", start: now.addingTimeInterval(600)),
        ])
        #expect(sorted.map(\.title) == ["Cumpleaños", "Pronto", "Tarde"])
    }

    @Test func sameStartFallsBackToTheTitleSoTheOrderNeverWobbles() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = CalendarMapping.sorted([event("Zanahoria", start: now), event("Abeja", start: now)])
        let second = CalendarMapping.sorted([event("Abeja", start: now), event("Zanahoria", start: now)])
        #expect(first.map(\.title) == second.map(\.title))
    }

    @Test func calendarColoursSurviveTheTripToHex() {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let orange = CGColor(colorSpace: sRGB, components: [1, 0.5, 0, 1])!
        #expect(CalendarMapping.hex(of: orange) == 0xFF80_00)
    }

    @Test func aCalendarWithoutAColourFallsBackToKraft() {
        #expect(CalendarMapping.hex(of: nil) == 0xC9A7_7C)
    }

    @Test func onlyFullAccessCounts() {
        #expect(CalendarStore.access(for: .fullAccess) == .granted)
        #expect(CalendarStore.access(for: .notDetermined) == .unknown)
        #expect(CalendarStore.access(for: .denied) == .denied)
        #expect(CalendarStore.access(for: .restricted) == .denied)
        // Write-only can add events but can't read them: useless for the agenda.
        #expect(CalendarStore.access(for: .writeOnly) == .denied)
    }

    @Test func aRunningEventIsHappeningNow() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let running = event("Reunión", start: now.addingTimeInterval(-300))
        let later = event("Después", start: now.addingTimeInterval(300))
        #expect(running.isRunning(at: now))
        #expect(!later.isRunning(at: now))
    }

    @Test func theCountdownSaysWhatIsGoingOn() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        #expect(DesvanEventFormat.countdown(event("A", start: now.addingTimeInterval(720)), isTomorrow: false, now: now) == "en 12 min")
        #expect(DesvanEventFormat.countdown(event("B", start: now.addingTimeInterval(-60)), isTomorrow: false, now: now) == "ahora")
        #expect(DesvanEventFormat.countdown(event("C", start: now, allDay: true), isTomorrow: false, now: now) == "hoy")
        #expect(DesvanEventFormat.countdown(event("D", start: now.addingTimeInterval(50_000)), isTomorrow: true, now: now) == "mañana")
    }

    @Test func voiceOverGetsAWholeSentence() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let spoken = DesvanEventFormat.spoken(
            event("Diseño", start: now.addingTimeInterval(720), location: "Meet", link: "https://meet.google.com/a-b-c"),
            isTomorrow: false,
            isNext: true,
            now: now
        )
        #expect(spoken.hasPrefix("Lo siguiente:, Diseño"))
        #expect(spoken.contains("en 12 min"))
        #expect(spoken.contains("en Meet"))
        #expect(spoken.contains("enlace"))
    }

    @Test func samplesAreOrderedAndCarryAJoinLink() {
        let samples = CalendarStore.Event.samples()
        #expect(samples.count == 3)
        #expect(samples[0].conferenceURL != nil)
    }
}
