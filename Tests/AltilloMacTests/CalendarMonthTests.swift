import Foundation
import Testing
@testable import Altillo

/// The month view's plain logic: the grid (first weekday, 4/5/6-row months, borrowed days), which days each event
/// lands on (multi-day, all-day, across midnight, in other time zones), hidden calendars, and how the selection
/// walks across months.
@MainActor
struct CalendarMonthTests {
    // MARK: Helpers

    private func calendar(_ zone: String = "Europe/Madrid", firstWeekday: Int = 2,
                          locale: String = "es_ES") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: locale)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0,
                      in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func event(_ title: String, from start: Date, to end: Date, allDay: Bool = false,
                       calendarID: String = "work", color: UInt32 = 0xFF00_00) -> CalendarStore.Event {
        CalendarStore.Event(
            id: title, title: title, start: start, end: end, calendarColorHex: color, location: nil,
            conferenceURL: nil, isAllDay: allDay, calendarID: calendarID
        )
    }

    private func days(_ numbers: [Int], _ month: Int, _ year: Int = 2026, in calendar: Calendar) -> [Date] {
        numbers.map { date(year, month, $0, in: calendar) }
    }

    // MARK: Grid

    @Test func theGridStartsOnTheUsersFirstWeekday() {
        // 1 September 2026 is a Tuesday.
        let monday = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: calendar(firstWeekday: 2))
        #expect(monday.leading == 1)
        #expect(monday.days.first == date(2026, 8, 31, in: calendar()))

        let sundayCalendar = calendar("America/New_York", firstWeekday: 1, locale: "en_US")
        let sunday = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: sundayCalendar)
        #expect(sunday.leading == 2)
        #expect(sunday.days.first == date(2026, 8, 30, in: sundayCalendar))
    }

    @Test func weekdayInitialsFollowTheFirstWeekdayAndTheLanguage() {
        let spanish = CalendarGrid.weekdaySymbols(calendar: calendar(firstWeekday: 2, locale: "es_ES"))
        #expect(spanish.count == 7)
        #expect(spanish.first == "L")
        #expect(spanish.last == "D")
        let english = CalendarGrid.weekdaySymbols(calendar: calendar(firstWeekday: 1, locale: "en_US"))
        #expect(english == ["S", "M", "T", "W", "T", "F", "S"])
        let names = CalendarGrid.weekdayNames(calendar: calendar(firstWeekday: 2, locale: "en_GB"))
        #expect(names.first == "Monday")
    }

    @Test func monthsNeedFourFiveOrSixRowsButTheNotchAlwaysDrawsSix() {
        let madrid = calendar()
        // September 2026 from Monday: 1 borrowed + 30 days = 5 rows.
        #expect(CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid, minimumRows: 0).rows == 5)
        // August 2026 starts on a Saturday: 5 borrowed + 31 = 6 rows.
        #expect(CalendarGrid(month: CalendarMonth(year: 2026, month: 8), calendar: madrid, minimumRows: 0).rows == 6)
        // February 2026 starts on a Sunday: from Sunday it fits four rows exactly.
        let sundays = calendar(firstWeekday: 1)
        let february = CalendarGrid(month: CalendarMonth(year: 2026, month: 2), calendar: sundays, minimumRows: 0)
        #expect(february.rows == 4)
        #expect(february.leading == 0)

        let padded = CalendarGrid(month: CalendarMonth(year: 2026, month: 2), calendar: sundays)
        #expect(padded.rows == 6)
        #expect(padded.naturalRows == 4)
        #expect(padded.days.count == 42)
    }

    @Test func borrowedDaysAtBothEndsAreNotPartOfTheMonth() {
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid)
        #expect(!grid.isInMonth(0)) // 31 August
        #expect(grid.isInMonth(1)) // 1 September
        #expect(grid.isInMonth(30)) // 30 September
        #expect(!grid.isInMonth(31)) // 1 October
        #expect(grid.days.last == date(2026, 10, 11, in: madrid))
        #expect(grid.interval.start == date(2026, 8, 31, in: madrid))
        #expect(grid.interval.end == date(2026, 10, 12, in: madrid))
        #expect(grid.index(of: date(2026, 9, 24, 15, 30, in: madrid), calendar: madrid) == 24)
    }

    @Test func everyCellIsAMidnightEvenAcrossDaylightSaving() {
        // Spain goes back an hour on 25 October 2026.
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 10), calendar: madrid)
        #expect(Set(grid.days).count == grid.days.count)
        for day in grid.days {
            #expect(madrid.component(.hour, from: day) == 0)
        }
        #expect(grid.days.contains(date(2026, 10, 26, in: madrid)))
    }

    // MARK: Buckets

    @Test func eventsLandOnEveryDayTheyTouch() {
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid)
        let trip = event("Lisbon", from: date(2026, 9, 7, in: madrid),
                         to: date(2026, 9, 9, 23, 59, in: madrid).addingTimeInterval(59), allDay: true)
        let party = event("Party", from: date(2026, 9, 12, 22, 0, in: madrid), to: date(2026, 9, 13, 1, 0, in: madrid))
        let lunch = event("Lunch", from: date(2026, 9, 15, 13, 0, in: madrid), to: date(2026, 9, 15, 14, 0, in: madrid))
        let buckets = CalendarBuckets.bucket([trip, party, lunch], days: grid.days, calendar: madrid)

        #expect(buckets[date(2026, 9, 6, in: madrid)] == nil)
        for day in days([7, 8, 9], 9, in: madrid) {
            #expect(buckets[day]?.map(\.title) == ["Lisbon"])
        }
        #expect(buckets[date(2026, 9, 10, in: madrid)] == nil)
        #expect(buckets[date(2026, 9, 12, in: madrid)]?.map(\.title) == ["Party"])
        #expect(buckets[date(2026, 9, 13, in: madrid)]?.map(\.title) == ["Party"])
        #expect(buckets[date(2026, 9, 15, in: madrid)]?.map(\.title) == ["Lunch"])
    }

    @Test func anEventEndingAtMidnightStaysOnItsDayAndAMomentStillCounts() {
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid)
        let holiday = event("Holiday", from: date(2026, 9, 11, in: madrid), to: date(2026, 9, 12, in: madrid),
                            allDay: true)
        let reminder = event("Reminder", from: date(2026, 9, 20, 9, 0, in: madrid),
                             to: date(2026, 9, 20, 9, 0, in: madrid))
        let buckets = CalendarBuckets.bucket([holiday, reminder], days: grid.days, calendar: madrid)
        #expect(buckets[date(2026, 9, 11, in: madrid)]?.map(\.title) == ["Holiday"])
        #expect(buckets[date(2026, 9, 12, in: madrid)] == nil)
        #expect(buckets[date(2026, 9, 20, in: madrid)]?.map(\.title) == ["Reminder"])
    }

    @Test func daysAreTheUsersInTheirTimeZone() {
        // 23:30 in London on the 10th is already the 11th in Tokyo, and still the 10th in New York.
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let start = date(2026, 9, 10, 23, 30, in: london)
        let call = event("Call", from: start, to: start.addingTimeInterval(30 * 60))

        let tokyo = calendar("Asia/Tokyo")
        let tokyoGrid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: tokyo)
        let tokyoDays = CalendarBuckets.bucket([call], days: tokyoGrid.days, calendar: tokyo)
        #expect(tokyoDays.keys.sorted() == [date(2026, 9, 11, in: tokyo)])

        let newYork = calendar("America/New_York")
        let newYorkGrid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: newYork)
        let newYorkDays = CalendarBuckets.bucket([call], days: newYorkGrid.days, calendar: newYork)
        #expect(newYorkDays.keys.sorted() == [date(2026, 9, 10, in: newYork)])
    }

    @Test func eachDayIsInAgendaOrderAndShowsAtMostThreeDots() {
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid)
        let day = date(2026, 9, 24, in: madrid)
        let events = [
            event("Late", from: date(2026, 9, 24, 18, 0, in: madrid), to: date(2026, 9, 24, 19, 0, in: madrid), color: 0x3),
            event("Early", from: date(2026, 9, 24, 9, 0, in: madrid), to: date(2026, 9, 24, 10, 0, in: madrid), color: 0x2),
            event("Birthday", from: day, to: date(2026, 9, 25, in: madrid), allDay: true, color: 0x1),
            event("Noon", from: date(2026, 9, 24, 12, 0, in: madrid), to: date(2026, 9, 24, 13, 0, in: madrid), color: 0x4),
        ]
        let bucket = CalendarBuckets.bucket(events, days: grid.days, calendar: madrid)[day] ?? []
        #expect(bucket.map(\.title) == ["Birthday", "Early", "Noon", "Late"])
        #expect(CalendarBuckets.dots(for: bucket) == [0x1, 0x2, 0x4])
    }

    // MARK: Filter

    @Test func hiddenCalendarsAndAllDayEventsCanBeLeftOut() {
        let madrid = calendar()
        let day = date(2026, 9, 24, in: madrid)
        let events = [
            event("Standup", from: date(2026, 9, 24, 9, 30, in: madrid), to: date(2026, 9, 24, 9, 45, in: madrid),
                  calendarID: "work"),
            event("Gym", from: date(2026, 9, 24, 19, 0, in: madrid), to: date(2026, 9, 24, 20, 0, in: madrid),
                  calendarID: "home"),
            event("Holiday", from: day, to: date(2026, 9, 25, in: madrid), allDay: true, calendarID: "holidays"),
        ]
        #expect(CalendarFilter().apply(events).count == 3)
        #expect(CalendarFilter(hiddenCalendarIDs: ["home"]).apply(events).map(\.title) == ["Standup", "Holiday"])
        #expect(CalendarFilter(showsAllDay: false).apply(events).map(\.title) == ["Standup", "Gym"])
        #expect(CalendarFilter(hiddenCalendarIDs: ["work", "home"], showsAllDay: false).apply(events).isEmpty)
    }

    @Test func theAgendaFallsBackToTomorrowWhenWhatIsLeftTodayIsHidden() {
        let madrid = calendar()
        let now = date(2026, 9, 24, 16, 0, in: madrid)
        let events = [
            event("Done", from: date(2026, 9, 24, 9, 0, in: madrid), to: date(2026, 9, 24, 10, 0, in: madrid)),
            event("Gym", from: date(2026, 9, 24, 19, 0, in: madrid), to: date(2026, 9, 24, 20, 0, in: madrid),
                  calendarID: "home"),
            event("Standup", from: date(2026, 9, 25, 9, 30, in: madrid), to: date(2026, 9, 25, 9, 45, in: madrid)),
        ]
        let all = CalendarMapping.agenda(from: events, now: now, calendar: madrid)
        #expect(all.events.map(\.title) == ["Gym"])
        #expect(!all.isTomorrow)

        let filtered = CalendarFilter(hiddenCalendarIDs: ["home"]).apply(events)
        let tomorrow = CalendarMapping.agenda(from: filtered, now: now, calendar: madrid)
        #expect(tomorrow.events.map(\.title) == ["Standup"])
        #expect(tomorrow.isTomorrow)
    }

    // MARK: Selection

    @Test func arrowsWalkAcrossMonthsAndTurnThePage() {
        let madrid = calendar()
        var browser = CalendarBrowser(today: date(2026, 9, 30, 15, 0, in: madrid), calendar: madrid)
        #expect(browser.month == CalendarMonth(year: 2026, month: 9))
        #expect(browser.selected == date(2026, 9, 30, in: madrid))

        browser.move(.nextDay, calendar: madrid)
        #expect(browser.selected == date(2026, 10, 1, in: madrid))
        #expect(browser.month == CalendarMonth(year: 2026, month: 10))

        browser.move(.previousWeek, calendar: madrid)
        #expect(browser.selected == date(2026, 9, 24, in: madrid))
        #expect(browser.month == CalendarMonth(year: 2026, month: 9))

        browser.move(.nextWeek, calendar: madrid)
        browser.move(.previousDay, calendar: madrid)
        #expect(browser.selected == date(2026, 9, 30, in: madrid))
    }

    @Test func theYearTurnsToo() {
        let madrid = calendar()
        var browser = CalendarBrowser(today: date(2026, 12, 31, in: madrid), calendar: madrid)
        browser.move(.nextDay, calendar: madrid)
        #expect(browser.month == CalendarMonth(year: 2027, month: 1))
        browser.move(.previousWeek, calendar: madrid)
        #expect(browser.selected == date(2026, 12, 25, in: madrid))
        #expect(browser.month == CalendarMonth(year: 2026, month: 12))
    }

    @Test func turningThePageKeepsTheDayOrTheMonthsLast() {
        let madrid = calendar()
        var browser = CalendarBrowser(today: date(2026, 1, 31, in: madrid), calendar: madrid)
        browser.turnPage(by: 1, calendar: madrid)
        #expect(browser.selected == date(2026, 2, 28, in: madrid))
        #expect(browser.month == CalendarMonth(year: 2026, month: 2))
        browser.turnPage(by: -2, calendar: madrid)
        #expect(browser.selected == date(2025, 12, 28, in: madrid))

        browser.goToToday(date(2026, 9, 24, 8, 0, in: madrid), calendar: madrid)
        #expect(browser.selected == date(2026, 9, 24, in: madrid))
        #expect(browser.month == CalendarMonth(year: 2026, month: 9))
        #expect(browser.isShowingToday(date(2026, 9, 24, 23, 0, in: madrid), calendar: madrid))
    }

    @Test func clickingABorrowedDayGoesToItsMonth() {
        let madrid = calendar()
        var browser = CalendarBrowser(today: date(2026, 9, 10, in: madrid), calendar: madrid)
        browser.select(date(2026, 8, 31, in: madrid), calendar: madrid)
        #expect(browser.month == CalendarMonth(year: 2026, month: 8))
    }

    @Test func monthsCompareAndAddAcrossYears() {
        let madrid = calendar()
        let december = CalendarMonth(year: 2026, month: 12)
        #expect(december.adding(1, in: madrid) == CalendarMonth(year: 2027, month: 1))
        #expect(december.adding(-12, in: madrid) == CalendarMonth(year: 2025, month: 12))
        #expect(CalendarMonth(year: 2026, month: 12) < CalendarMonth(year: 2027, month: 1))
        #expect(december.contains(date(2026, 12, 31, 23, 59, in: madrid), in: madrid))
    }

    // MARK: Calendar.app

    @Test func eventsOpenInCalendarByTheirIdentifier() {
        var single = event("Design", from: Date(timeIntervalSinceReferenceDate: 800_000_000),
                           to: Date(timeIntervalSinceReferenceDate: 800_001_800))
        single.itemIdentifier = "ABC-123"
        #expect(CalendarAppLink.url(for: single)?.absoluteString == "ical://ekevent/ABC-123?method=show&options=more")

        var repeating = single
        repeating.isRecurring = true
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        repeating.start = date(2026, 9, 24, 8, 30, in: utc)
        #expect(CalendarAppLink.url(for: repeating)?.absoluteString
            == "ical://ekevent/20260924T083000Z/ABC-123?method=show&options=more")

        let unknown = event("Sample", from: .now, to: .now)
        #expect(CalendarAppLink.url(for: unknown) == nil)
    }

    @Test func allDayOccurrencesAreStampedInLocalTime() {
        let madrid = calendar()
        let stamp = CalendarAppLink.occurrenceStamp(date(2026, 9, 24, in: madrid), allDay: true,
                                                    timeZone: madrid.timeZone)
        #expect(stamp == "20260924T000000")
    }

    // MARK: Words

    @Test func voiceOverReadsTheDayAndHowBusyItIs() {
        let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let label = DesvanCalendarWords.dayLabel(day, count: 3, isToday: true)
        #expect(label.contains("today"))
        #expect(label.hasSuffix("3 events"))
        #expect(DesvanCalendarWords.dayLabel(day, count: 1, isToday: false).hasSuffix("1 event"))
        #expect(DesvanCalendarWords.dayLabel(day, count: 0, isToday: false).hasSuffix("no events"))
        // Still loading: no count rather than a wrong "no events".
        #expect(!DesvanCalendarWords.dayLabel(day, count: nil, isToday: false).contains("event"))
    }

    @Test func theSampleMonthHasARhythmATripAndToday() {
        let madrid = calendar()
        let grid = CalendarGrid(month: CalendarMonth(year: 2026, month: 9), calendar: madrid)
        let today = date(2026, 9, 24, in: madrid)
        let samples = CalendarStore.Event.samples(for: grid, today: today, calendar: madrid)
        #expect(samples.contains { $0.isAllDay && $0.title == "Lisbon" })
        let buckets = CalendarBuckets.bucket(samples, days: grid.days, calendar: madrid)
        #expect(buckets[today]?.isEmpty == false)
        #expect(Set(samples.map(\.calendarID)).count >= 3)
    }
}
