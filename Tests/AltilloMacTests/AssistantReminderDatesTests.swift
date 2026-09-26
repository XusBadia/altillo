import Foundation
import Testing
@testable import Altillo

/// One rule per test, in English, Spanish and Catalan: what "tomorrow at 10" / «mañana a las 7» / «demà» mean,
/// worked out against a fixed "now" so the answers don't drift with the calendar.
struct AssistantReminderDatesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Madrid")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Friday 25 September 2026, 17:00 in Madrid.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 17, minute: 0))!
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func parse(_ text: String) -> ReminderDue? {
        ReminderDateParser.parse(text, now: now, calendar: calendar)
    }

    // MARK: - Tomorrow

    @Test func tomorrowAtTen() {
        #expect(parse("tomorrow at 10") == ReminderDue(date: date(2026, 9, 26, 10, 0), hasTime: true))
    }

    @Test func mananaALas7() {
        #expect(parse("mañana a las 7") == ReminderDue(date: date(2026, 9, 26, 7, 0), hasTime: true))
    }

    @Test func demaAlMati() {
        #expect(parse("demà al matí") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
    }

    // MARK: - Today, implied and explicit

    @Test func aLas7NoDayIsToday() {
        // now is 17:00, so bare "a las 7" reads as evening, not the morning that already went by.
        #expect(parse("a las 7") == ReminderDue(date: date(2026, 9, 25, 19, 0), hasTime: true))
    }

    @Test func recuerdameComprarPanALas7() {
        #expect(parse("recuérdame comprar pan a las 7") == ReminderDue(date: date(2026, 9, 25, 19, 0), hasTime: true))
    }

    @Test func at3IsAfternoonAndNeverInThePast() {
        // Hours 1...6 always become afternoon and are never bumped to tomorrow, even past "now".
        // 15:00 already went by at 17:00, and a reminder is never set in the past.
        #expect(parse("at 3") == ReminderDue(date: date(2026, 9, 26, 15, 0), hasTime: true))
        #expect(parse("at 6") == ReminderDue(date: date(2026, 9, 25, 18, 0), hasTime: true))
    }

    @Test func at9amAlreadyPassedMovesToTomorrow() {
        #expect(parse("at 9am") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
    }

    @Test func today() {
        // "today" makes the ambiguous-hour check today's, same as an implied day: 10am already went by, so
        // this reads as 22:00, not 10:00.
        #expect(parse("hoy a las 10") == ReminderDue(date: date(2026, 9, 25, 22, 0), hasTime: true))
    }

    // MARK: - Weekdays

    @Test func onMonday() {
        #expect(parse("on monday") == ReminderDue(date: date(2026, 9, 28), hasTime: false))
    }

    @Test func elViernesALas10() {
        // Today already is a Friday, so "el viernes" means next week's, not today.
        #expect(parse("el viernes a las 10") == ReminderDue(date: date(2026, 10, 2, 10, 0), hasTime: true))
    }

    @Test func divendresBareCatalan() {
        #expect(parse("divendres") == ReminderDue(date: date(2026, 10, 2), hasTime: false))
    }

    // MARK: - Day after tomorrow, next week, in N days

    @Test func pasadoManana() {
        #expect(parse("pasado mañana") == ReminderDue(date: date(2026, 9, 27), hasTime: false))
    }

    @Test func demaPassat() {
        #expect(parse("demà passat") == ReminderDue(date: date(2026, 9, 27), hasTime: false))
    }

    @Test func nextWeekHasNoTime() {
        #expect(parse("next week") == ReminderDue(date: date(2026, 10, 2), hasTime: false))
    }

    @Test func laSetmanaQueVe() {
        #expect(parse("la setmana que ve") == ReminderDue(date: date(2026, 10, 2), hasTime: false))
    }

    @Test func inThreeDays() {
        #expect(parse("in 3 days") == ReminderDue(date: date(2026, 9, 28), hasTime: false))
    }

    @Test func dAquiATresDies() {
        #expect(parse("d'aquí a tres dies") == ReminderDue(date: date(2026, 9, 28), hasTime: false))
    }

    // MARK: - Morning/afternoon/evening combos

    @Test func mananaPorLaManana() {
        #expect(parse("mañana por la mañana") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
    }

    @Test func demaALes8DelVespre() {
        #expect(parse("demà a les 8 del vespre") == ReminderDue(date: date(2026, 9, 26, 20, 0), hasTime: true))
    }

    @Test func bareAfternoonBumpsWhenPassed() {
        #expect(parse("afternoon") == ReminderDue(date: date(2026, 9, 26, 16, 0), hasTime: true))
    }

    @Test func tonightIsNineOClock() {
        #expect(parse("tonight") == ReminderDue(date: date(2026, 9, 25, 21, 0), hasTime: true))
    }

    // MARK: - Relative moments

    @Test func inTwoHours() {
        #expect(parse("in 2 hours") == ReminderDue(date: date(2026, 9, 25, 19, 0), hasTime: true))
    }

    @Test func enMediaHora() {
        #expect(parse("en media hora") == ReminderDue(date: date(2026, 9, 25, 17, 30), hasTime: true))
    }

    @Test func dinsDeMitjaHora() {
        #expect(parse("d'aquí a mitja hora") == ReminderDue(date: date(2026, 9, 25, 17, 30), hasTime: true))
    }

    // MARK: - Noon, midnight, quarters

    @Test func noonAlreadyPassedMovesToTomorrow() {
        #expect(parse("at noon") == ReminderDue(date: date(2026, 9, 26, 12, 0), hasTime: true))
    }

    @Test func migdia() {
        #expect(parse("migdia") == ReminderDue(date: date(2026, 9, 26, 12, 0), hasTime: true))
    }

    @Test func midnightIsAlwaysTheNextOne() {
        #expect(parse("midnight") == ReminderDue(date: date(2026, 9, 26, 0, 0), hasTime: true))
    }

    @Test func yCuarto() {
        #expect(parse("a las 7 y cuarto") == ReminderDue(date: date(2026, 9, 25, 19, 15), hasTime: true))
    }

    @Test func menosCuarto() {
        #expect(parse("a las 8 menos cuarto") == ReminderDue(date: date(2026, 9, 25, 19, 45), hasTime: true))
    }

    // MARK: - Month and day

    @Test func threeDeOctubreHasNoTime() {
        #expect(parse("3 de octubre") == ReminderDue(date: date(2026, 10, 3), hasTime: false))
    }

    @Test func monthNameFirst() {
        #expect(parse("october 3") == ReminderDue(date: date(2026, 10, 3), hasTime: false))
    }

    // MARK: - No date at all

    @Test func callAnaIsNil() {
        #expect(parse("call Ana") == nil)
    }

    @Test func bareNumberIsNotATime() {
        #expect(parse("buy 2 loaves of bread") == nil)
    }

    // MARK: - Stripping date phrases

    @Test func stripTrailingDayAndTime() {
        #expect(ReminderDateParser.strippingDatePhrases(from: "call Ana tomorrow at 10") == "call Ana")
    }

    @Test func stripTrailingTimeOnly() {
        #expect(ReminderDateParser.strippingDatePhrases(from: "comprar pan a las 7") == "comprar pan")
    }

    @Test func stripLeadingAskAndTrailingWeekday() {
        #expect(
            ReminderDateParser.strippingDatePhrases(from: "Remind me to water the plants on Friday")
                == "water the plants"
        )
    }

    @Test func stripSpanishAskAndDayAndTime() {
        #expect(
            ReminderDateParser.strippingDatePhrases(from: "Recuérdame llamar a Ana mañana a las 10")
                == "llamar a Ana"
        )
    }

    // MARK: - Review fixes

    private func at(_ hour: Int, _ minute: Int = 0) -> Date { date(2026, 9, 25, hour, minute) }

    @Test func morningPhrasesDontMeanTomorrow() {
        let eight = at(8)
        #expect(ReminderDateParser.parse("hoy a las 9 de la mañana", now: eight, calendar: calendar)
            == ReminderDue(date: at(9), hasTime: true))
        #expect(ReminderDateParser.parse("a las 9 de la mañana", now: eight, calendar: calendar)
            == ReminderDue(date: at(9), hasTime: true))
        #expect(ReminderDateParser.parse("por la mañana", now: eight, calendar: calendar)
            == ReminderDue(date: at(9), hasTime: true))
        #expect(parse("mañana por la mañana") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
        #expect(ReminderDateParser.parse("avui a les 10 del matí", now: eight, calendar: calendar)
            == ReminderDue(date: at(10), hasTime: true))
    }

    @Test func laterInTheDayWordsMeanPM() {
        #expect(parse("tonight at 8") == ReminderDue(date: at(20), hasTime: true))
        #expect(parse("tonight at 11") == ReminderDue(date: at(23), hasTime: true))
        #expect(parse("this evening at 7") == ReminderDue(date: at(19), hasTime: true))
        #expect(parse("esta tarde a las 6") == ReminderDue(date: at(18), hasTime: true))
        #expect(parse("esta noche a las 10") == ReminderDue(date: at(22), hasTime: true))
        #expect(parse("aquest vespre a les 9") == ReminderDue(date: at(21), hasTime: true))
        #expect(parse("demà a la tarda a les 4") == ReminderDue(date: date(2026, 9, 26, 16, 0), hasTime: true))
    }

    @Test func midnightAndQuarterTo() {
        #expect(parse("a las 12 de la noche") == ReminderDue(date: date(2026, 9, 26, 0, 0), hasTime: true))
        #expect(parse("mañana a la 1 menos cuarto") == ReminderDue(date: date(2026, 9, 26, 12, 45), hasTime: true))
        #expect(parse("mañana a la una menos cuarto") == ReminderDue(date: date(2026, 9, 26, 12, 45), hasTime: true))
    }

    @Test func dotsHalvesQuartersAndWords() {
        #expect(parse("a las 7.30") == ReminderDue(date: at(19, 30), hasTime: true))
        #expect(parse("a les 7 i mitja") == ReminderDue(date: at(19, 30), hasTime: true))
        #expect(parse("a les 8 i quart") == ReminderDue(date: at(20, 15), hasTime: true))
        #expect(parse("a las siete") == ReminderDue(date: at(19), hasTime: true))
        #expect(parse("at seven") == ReminderDue(date: at(19), hasTime: true))
        #expect(parse("tomorrow at nine") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
        #expect(parse("a les set del vespre") == ReminderDue(date: at(19), hasTime: true))
        #expect(parse("a las doce") == ReminderDue(date: date(2026, 9, 26, 12, 0), hasTime: true))
    }

    @Test func anHour() {
        #expect(parse("in an hour") == ReminderDue(date: at(18), hasTime: true))
        #expect(parse("en una hora") == ReminderDue(date: at(18), hasTime: true))
        #expect(parse("d'aquí a una hora") == ReminderDue(date: at(18), hasTime: true))
    }

    @Test func aTimeSaidForTodayThatAlreadyWentByIsFlagged() {
        #expect(parse("today at 9am") == ReminderDue(date: at(9), hasTime: true, hasPassed: true))
        #expect(parse("hoy a las 3") == ReminderDue(date: at(15), hasTime: true, hasPassed: true))
        #expect(parse("avui a les 4 de la tarda") == ReminderDue(date: at(16), hasTime: true, hasPassed: true))
        // Said without a day, it's the next time it comes round.
        #expect(parse("at 9am") == ReminderDue(date: date(2026, 9, 26, 9, 0), hasTime: true))
    }

    @Test func theDayCanComeFromTheQuestion() {
        #expect(ReminderDateParser.parse("at 10", now: now, calendar: calendar, dayHint: "recuérdame mañana a las 10")
            == ReminderDue(date: date(2026, 9, 26, 10, 0), hasTime: true))
        #expect(ReminderDateParser.parse("tomorrow at 10", now: now, calendar: calendar, dayHint: "el lunes")
            == ReminderDue(date: date(2026, 9, 26, 10, 0), hasTime: true), "its own day wins")
        #expect(ReminderDateParser.namesDay("el viernes", now: now, calendar: calendar))
        #expect(!ReminderDateParser.namesDay("a las 9 de la mañana", now: now, calendar: calendar))
    }

    @Test func titlesWithLettersThatFoldLongerStayIntact() {
        #expect(ReminderDateParser.strippingDatePhrases(from: "Fußball tomorrow at 10 with Ana") == "Fußball with Ana")
        #expect(ReminderDateParser.strippingDatePhrases(from: "ﬁle the taxes mañana a las 9") == "ﬁle the taxes")
        #expect(ReminderDateParser.parse("Fußball tomorrow at 10", now: now, calendar: calendar)
            == ReminderDue(date: date(2026, 9, 26, 10, 0), hasTime: true))
    }
}
