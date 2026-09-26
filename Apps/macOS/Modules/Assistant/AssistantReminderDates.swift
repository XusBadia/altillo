import Foundation

/// When a reminder is due, as parsed from what the user said ("tomorrow at 10", «mañana a las 7», «divendres»).
struct ReminderDue: Equatable, Sendable {
    /// The exact moment when `hasTime`; otherwise the start of the due day (in the parser's calendar).
    var date: Date
    var hasTime: Bool
    /// A time the user said is today ("today at 9", «hoy a las 9») that has already gone by: nothing is made, and
    /// the same time tomorrow is offered instead.
    var hasPassed = false
}

/// Turns what someone actually said into a due date, in English, Spanish and Catalan. No NLP model, no
/// `DataDetector` (it wants a full sentence and guesses wrong on short reminder titles) — just a short list of
/// the phrases people use for "when", read from the most specific ("pasado mañana") to the most generic ("hoy"),
/// so a longer phrase never gets shadowed by a shorter one it contains.
///
/// Everything is matched on a folded copy of the text (lower-cased, accents stripped), so "MAÑANA" and "manana"
/// read the same; the original casing is only touched by `strippingDatePhrases`, and only by deleting words.
enum ReminderDateParser {
    private enum Meridiem { case am, pm }

    /// A time as read off the sentence, before it's turned into a 24-hour hour. `fixed` means it's already a
    /// final 24-hour value (noon, "tonight", "por la tarde"…) and just needs the "already passed" check;
    /// otherwise, with no `meridiem`, it still has to go through the ambiguous-hour rule below.
    private struct TimeCandidate {
        var hour: Int
        var minute: Int
        var meridiem: Meridiem?
        var fixed: Bool
        /// «12 de la noche», «les 12 de la nit»: midnight, not noon.
        var isNight = false
    }

    private struct DayResult {
        var date: Date?
        var isTonight = false
        /// "Next week" names no time of day, so none should be read from the rest of the sentence either.
        var forceNoTime = false
    }

    // MARK: - Word lists

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6,
        "siete": 7, "ocho": 8, "nueve": 9, "diez": 10, "once": 11, "doce": 12,
        "quatre": 4, "cinc": 5, "sis": 6, "set": 7, "vuit": 8, "nou": 9, "deu": 10, "onze": 11, "dotze": 12,
    ]

    private static let months: [String: Int] = [
        "january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6,
        "july": 7, "august": 8, "september": 9, "october": 10, "november": 11, "december": 12,
        "enero": 1, "febrero": 2, "marzo": 3, "abril": 4, "mayo": 5, "junio": 6, "julio": 7, "agosto": 8,
        "septiembre": 9, "setiembre": 9, "octubre": 10, "noviembre": 11, "diciembre": 12,
        "gener": 1, "febrer": 2, "marc": 3, "maig": 5, "juny": 6, "juliol": 7, "agost": 8,
        "setembre": 9, "novembre": 11, "desembre": 12,
    ]

    private static let weekdays: [String: Int] = [
        "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
        "domingo": 1, "lunes": 2, "martes": 3, "miercoles": 4, "jueves": 5, "viernes": 6, "sabado": 7,
        "diumenge": 1, "dilluns": 2, "dimarts": 3, "dimecres": 4, "dijous": 5, "divendres": 6, "dissabte": 7,
    ]

    private static let amMarkers: Set<String> = ["am", "a.m.", "de la manana", "de la madrugada", "del mati"]
    private static let pmMarkers: Set<String> = [
        "pm", "p.m.", "de la tarde", "de la noche", "de la tarda", "del vespre", "de la nit",
    ]

    // MARK: - Patterns

    private static let numberWordPattern =
        #"one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|un|uno|una|dos|tres|cuatro|cinco|seis|"# +
        #"siete|ocho|nueve|diez|once|doce|quatre|cinc|sis|set|vuit|nou|deu|onze|dotze"#
    private static let monthNamePattern =
        #"january|february|march|april|may|june|july|august|september|october|november|december|enero|febrero|"# +
        #"marzo|abril|mayo|junio|julio|agosto|septiembre|setiembre|octubre|noviembre|diciembre|gener|febrer|marc|"# +
        #"maig|juny|juliol|agost|setembre|novembre|desembre"#
    private static let weekdayNamePattern =
        #"sunday|monday|tuesday|wednesday|thursday|friday|saturday|domingo|lunes|martes|miercoles|jueves|"# +
        #"viernes|sabado|diumenge|dilluns|dimarts|dimecres|dijous|divendres|dissabte"#
    /// Words that put a bare hour in the afternoon or evening ("tonight at 8", «esta tarde a las 5»).
    private static let laterInTheDayPattern =
        #"\btonight\b|\bevening\b|\bafternoon\b|\bnoche\b|\btarde\b|\bvespre\b|\btarda\b|\bnit\b"#
    /// Morning phrases that contain «mañana» but don't mean tomorrow: blanked out before the day is read.
    private static let morningNotTomorrowPattern = #"\bde la manana\b|\bpor la manana\b|\bdel mati\b"#
    /// Durations may also start with "an"/"a" ("in an hour").
    private static let durationNumberPattern = numberWordPattern + "|an|a"
    private static let amMarkerPattern = #"am|a\.m\.|de la manana|de la madrugada|del mati"#
    private static let pmMarkerPattern = #"pm|p\.m\.|de la tarde|de la noche|de la tarda|del vespre|de la nit"#
    private static let leadIn = #"(?:\bin\b|\ben\b|\bdentro de\b|\bd'aqui a\b)"#

    private static let dayAfterTomorrowPattern = #"\bpasado manana\b|\bdema passat\b|\bday after tomorrow\b"#
    private static let nextWeekPattern =
        #"\bnext week\b|\bla semana que viene\b|\bla proxima semana\b|\bla setmana que ve\b"#
    private static let monthDeformPattern = #"\b(\d{1,2})\s+de\s+(\#(monthNamePattern))\b"#
    private static let monthFirstPattern = #"\b(\#(monthNamePattern))\s+(\d{1,2})\b"#
    private static let dayMonthPattern = #"\b(\d{1,2})\s+(\#(monthNamePattern))\b"#
    private static let weekdayPattern = #"(?:on |el |this |next |aquest |aquesta )?\b(\#(weekdayNamePattern))\b"#
    private static let inDaysPattern = #"\#(leadIn)\s+(\d{1,3}|\#(numberWordPattern))\s+(days|dias|dies)\b"#
    private static let tonightPattern = #"\btonight\b|\besta noche\b|\baquesta nit\b"#
    private static let tomorrowPattern = #"\btomorrow\b|\bmanana\b|\bdema\b"#
    private static let todayPattern = #"\btoday\b|\bhoy\b|\bavui\b"#

    private static let durationPattern = #"\#(leadIn)\s+(\d{1,3}|\#(durationNumberPattern))\s+(minutos?|minuts?|"# +
        #"minutes|horas?|hores?|hours?)\b"#
    private static let halfHourPattern = #"\#(leadIn)\s+(?:half an hour|media hora|mitja hora)\b"#

    private static let timeBranchAPattern =
        #"(?:\bat\b|\ba las\b|\ba la\b|\ba les\b)\s+(\d{1,2}|\#(numberWordPattern))(?![\p{L}\d])(?:[:.](\d{2}))?"# +
        #"\s*(y media|y cuarto|menos cuarto|i mitja|i quart|menys quart)?"# +
        #"\s*(\#(amMarkerPattern)|\#(pmMarkerPattern))?"#
    private static let timeBranchBPattern = #"\b(\d{1,2}):(\d{2})\b\s*(\#(amMarkerPattern)|\#(pmMarkerPattern))?"#
    private static let timeBranchCPattern = #"\b(\d{1,2})\s*(\#(amMarkerPattern)|\#(pmMarkerPattern))\b"#

    private static let noonPattern = #"\bnoon\b|\bmediodia\b|\bmigdia\b"#
    private static let midnightPattern = #"\bmidnight\b|\bmedianoche\b|\bmitjanit\b"#
    private static let morningPattern = #"\bpor la manana\b|\bal mati\b|\bmorning\b"#
    private static let afternoonPattern = #"\bpor la tarde\b|\ba la tarda\b|\bafternoon\b"#
    private static let eveningPattern = #"\bpor la noche\b|\bal vespre\b|\bevening\b|\bnight\b"#

    private static let leadPhrasePattern =
        #"^(?:remind me to|reminder to|recuerdame|recorda'm|crea un recordatorio para)\s+"#

    /// Every pattern that names a day or a time, used to blank the words out of a reminder's title. Order
    /// doesn't matter here — every match gets removed regardless of what it means.
    private static let strippablePatterns: [String] = [
        dayAfterTomorrowPattern, nextWeekPattern, monthDeformPattern, monthFirstPattern, dayMonthPattern,
        weekdayPattern, inDaysPattern, durationPattern, halfHourPattern, tonightPattern, tomorrowPattern,
        todayPattern, noonPattern, midnightPattern, timeBranchAPattern, timeBranchBPattern, timeBranchCPattern,
        morningPattern, afternoonPattern, eveningPattern,
    ]

    // MARK: - Public API

    /// nil when the text names no day and no time.
    ///
    /// `dayHint`: where to read the day from when `text` names none (the model's "at 10" for the user's "mañana a
    /// las 10").
    static func parse(_ text: String, now: Date, calendar: Calendar = .current, dayHint: String? = nil) -> ReminderDue? {
        let folded = fold(text)
        if let seconds = matchDuration(folded) {
            return ReminderDue(date: now.addingTimeInterval(seconds), hasTime: true)
        }

        let today = calendar.startOfDay(for: now)
        var day = matchDay(dayWords(folded), today: today, calendar: calendar)
        if day.date == nil, let dayHint {
            day = matchDay(dayWords(fold(dayHint)), today: today, calendar: calendar)
        }
        let dayFound = day.date != nil
        let dayBase = day.date ?? today
        let isDayToday = calendar.isDate(dayBase, inSameDayAs: today)

        if matches(midnightPattern, in: folded) {
            let next = calendar.date(byAdding: .day, value: 1, to: dayBase) ?? dayBase
            return ReminderDue(date: calendar.startOfDay(for: next), hasTime: true)
        }

        if day.forceNoTime {
            return ReminderDue(date: dayBase, hasTime: false)
        }

        var candidate = matchTime(folded)
        if candidate == nil { candidate = matchNoon(folded) }
        if candidate == nil { candidate = matchPartOfDay(folded) }
        if candidate == nil, day.isTonight {
            candidate = TimeCandidate(hour: 21, minute: 0, meridiem: nil, fixed: true)
        }

        guard let candidate else {
            guard dayFound else { return nil }
            return ReminderDue(date: dayBase, hasTime: false)
        }

        var adjusted = candidate
        if adjusted.meridiem == nil, !adjusted.fixed, (1...11).contains(adjusted.hour),
           matches(laterInTheDayPattern, in: folded) {
            adjusted.meridiem = .pm
        }
        let resolved = resolve(adjusted, isDayToday: isDayToday, now: now, dayBase: dayBase, calendar: calendar)
        let base = resolved.nextDay ? (calendar.date(byAdding: .day, value: 1, to: dayBase) ?? dayBase) : dayBase
        guard var date = calendar.date(
            bySettingHour: resolved.hour, minute: resolved.minute, second: 0, of: base
        ) else {
            return ReminderDue(date: dayBase, hasTime: false)
        }
        if date <= now {
            // Said without a day: the next time it comes round. Said for today: too late, and the caller says so.
            guard dayFound else {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
                return ReminderDue(date: date, hasTime: true)
            }
            return ReminderDue(date: date, hasTime: true, hasPassed: true)
        }
        return ReminderDue(date: date, hasTime: true)
    }

    /// The title without the date/time words the parser understands, and without asking words
    /// ("remind me to", "recuérdame", "recorda'm", "reminder to", "crea un recordatorio para"…), trimmed, first
    /// letter kept as typed.
    /// "call Ana tomorrow at 10" → "call Ana"; "comprar pan a las 7" → "comprar pan"; "Remind me to water the
    /// plants on Friday" → "water the plants".
    static func strippingDatePhrases(from title: String) -> String {
        var workingOriginal = title
        var workingFolded = fold(title)

        if let m = firstMatch(leadPhrasePattern, in: workingFolded) {
            let range = characterRange(of: m.range, foldedText: workingFolded, originalText: workingOriginal)
            workingOriginal.removeSubrange(range)
            workingFolded.removeSubrange(m.range)
        }

        var removalRanges: [Range<String.Index>] = []
        for pattern in strippablePatterns {
            guard let regex = try? Regex(pattern) else { continue }
            for match in workingFolded.matches(of: regex) {
                removalRanges.append(
                    characterRange(of: match.range, foldedText: workingFolded, originalText: workingOriginal)
                )
            }
        }

        var result = workingOriginal
        for range in merged(removalRanges).sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }

        let words = result.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        return words.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Folding

    /// Lower-cased, accents stripped, curly apostrophes straightened — so every phrase list above only has to
    /// spell each word one way.
    ///
    /// Folded one character at a time, so the folded copy always has exactly as many characters as the original
    /// (positions found in it map back to the typed title): a character that would fold into several ("ß" → "ss",
    /// "ﬁ" → "fi") is kept as it was.
    static func fold(_ text: String) -> String {
        String(text.map { character -> Character in
            if character == "\u{2019}" { return "'" }
            let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return folded.count == 1 ? Character(folded) : character
        })
    }

    // MARK: - Regex helpers

    private static func matches(_ pattern: String, in text: String) -> Bool {
        firstMatch(pattern, in: text) != nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> Regex<AnyRegexOutput>.Match? {
        guard let regex = try? Regex(pattern) else { return nil }
        return text.firstMatch(of: regex)
    }

    private static func numberValue(from match: Regex<AnyRegexOutput>.Match, group: Int) -> Int? {
        guard let raw = match.output[group].substring.map(String.init) else { return nil }
        if let n = Int(raw) { return n }
        return numberWords[raw]
    }

    /// Maps a range found in the folded copy back to the same character offsets in the original string. Folding
    /// only ever turns one character into another (never merges or splits one), so counting characters is enough
    /// — no need to reconcile UTF-8 byte lengths, which do change when an accent is stripped.
    private static func characterRange(
        of range: Range<String.Index>, foldedText: String, originalText: String
    ) -> Range<String.Index> {
        let startOffset = foldedText.distance(from: foldedText.startIndex, to: range.lowerBound)
        let endOffset = foldedText.distance(from: foldedText.startIndex, to: range.upperBound)
        let count = originalText.count
        let start = originalText.index(originalText.startIndex, offsetBy: min(startOffset, count))
        let end = originalText.index(originalText.startIndex, offsetBy: min(endOffset, count))
        return start..<end
    }

    private static func merged(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, range.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                result.append(range)
            }
        }
        return result
    }

    /// True when `text` names a day ("tomorrow", «el viernes», "3 de octubre"), not just a time.
    static func namesDay(_ text: String, now: Date = .now, calendar: Calendar = .current) -> Bool {
        matchDay(dayWords(fold(text)), today: calendar.startOfDay(for: now), calendar: calendar).date != nil
    }

    /// The folded text with the morning phrases that contain «mañana» blanked out (same length), so «hoy a las 9
    /// de la mañana» isn't read as tomorrow.
    private static func dayWords(_ folded: String) -> String {
        guard let regex = try? Regex(morningNotTomorrowPattern) else { return folded }
        var text = folded
        for match in folded.matches(of: regex).reversed() {
            let range = characterRange(of: match.range, foldedText: folded, originalText: text)
            text.replaceSubrange(range, with: String(repeating: " ", count: folded[match.range].count))
        }
        return text
    }

    // MARK: - Relative moments ("in 2 hours", "en media hora")

    private static func matchDuration(_ folded: String) -> TimeInterval? {
        if matches(halfHourPattern, in: folded) { return 30 * 60 }
        guard let m = firstMatch(durationPattern, in: folded) else { return nil }
        let raw = m.output[1].substring.map(String.init) ?? ""
        guard let n = raw == "an" || raw == "a" ? 1 : numberValue(from: m, group: 1) else { return nil }
        let unit = m.output[2].substring.map(String.init) ?? ""
        return unit.hasPrefix("min") ? TimeInterval(n * 60) : TimeInterval(n * 3600)
    }

    // MARK: - Day words

    private static func matchDay(_ folded: String, today: Date, calendar: Calendar) -> DayResult {
        if matches(dayAfterTomorrowPattern, in: folded) {
            return DayResult(date: calendar.date(byAdding: .day, value: 2, to: today))
        }
        if matches(nextWeekPattern, in: folded) {
            return DayResult(date: calendar.date(byAdding: .day, value: 7, to: today), forceNoTime: true)
        }
        if let date = matchMonthDay(folded, today: today, calendar: calendar) {
            return DayResult(date: date)
        }
        if let m = firstMatch(weekdayPattern, in: folded),
           let name = m.output[1].substring.map(String.init), let target = weekdays[name] {
            let todayWeekday = calendar.component(.weekday, from: today)
            var diff = (target - todayWeekday + 7) % 7
            if diff == 0 { diff = 7 }
            return DayResult(date: calendar.date(byAdding: .day, value: diff, to: today))
        }
        if let m = firstMatch(inDaysPattern, in: folded), let n = numberValue(from: m, group: 1) {
            return DayResult(date: calendar.date(byAdding: .day, value: n, to: today))
        }
        if matches(tonightPattern, in: folded) {
            return DayResult(date: today, isTonight: true)
        }
        if matches(tomorrowPattern, in: folded) {
            return DayResult(date: calendar.date(byAdding: .day, value: 1, to: today))
        }
        if matches(todayPattern, in: folded) {
            return DayResult(date: today)
        }
        return DayResult(date: nil)
    }

    /// "3 de octubre", "october 3", "3 october" — this year, or next year if that date already went by.
    private static func matchMonthDay(_ folded: String, today: Date, calendar: Calendar) -> Date? {
        var day: Int?
        var monthName: String?
        if let m = firstMatch(monthDeformPattern, in: folded) {
            day = m.output[1].substring.flatMap { Int($0) }
            monthName = m.output[2].substring.map(String.init)
        } else if let m = firstMatch(monthFirstPattern, in: folded) {
            monthName = m.output[1].substring.map(String.init)
            day = m.output[2].substring.flatMap { Int($0) }
        } else if let m = firstMatch(dayMonthPattern, in: folded) {
            day = m.output[1].substring.flatMap { Int($0) }
            monthName = m.output[2].substring.map(String.init)
        }
        guard let day, let monthName, let month = months[monthName] else { return nil }

        let year = calendar.component(.year, from: today)
        var comps = DateComponents(year: year, month: month, day: day)
        guard let thisYear = calendar.date(from: comps) else { return nil }
        let startThisYear = calendar.startOfDay(for: thisYear)
        if startThisYear < today {
            comps.year = year + 1
            guard let nextYear = calendar.date(from: comps) else { return startThisYear }
            return calendar.startOfDay(for: nextYear)
        }
        return startThisYear
    }

    // MARK: - Times

    private static func meridiem(for marker: String?) -> Meridiem? {
        guard let marker else { return nil }
        if amMarkers.contains(marker) { return .am }
        if pmMarkers.contains(marker) { return .pm }
        return nil
    }

    private static func matchTime(_ folded: String) -> TimeCandidate? {
        matchTimeBranchA(folded) ?? matchTimeBranchB(folded) ?? matchTimeBranchC(folded)
    }

    /// "at 10", "a las 7", "a la 1", "a les 7 y mitja"… — the only branch with the "y media"/"menos cuarto" bits.
    private static func matchTimeBranchA(_ folded: String) -> TimeCandidate? {
        guard let m = firstMatch(timeBranchAPattern, in: folded),
              var hour = numberValue(from: m, group: 1), (0...23).contains(hour) else { return nil }
        var minute = m.output[2].substring.flatMap { Int($0) } ?? 0
        guard minute < 60 else { return nil }
        switch m.output[3].substring.map(String.init) {
        case "y media", "i mitja": minute = 30
        case "y cuarto", "i quart": minute = 15
        case "menos cuarto", "menys quart":
            // «la 1 menos cuarto» is 12:45.
            hour = hour == 1 ? 12 : hour - 1
            minute = 45
        default: break
        }
        let marker = m.output[4].substring.map(String.init)
        return TimeCandidate(hour: hour, minute: minute, meridiem: meridiem(for: marker), fixed: false,
                             isNight: marker == "de la noche" || marker == "de la nit")
    }

    /// "19:30", "10:30pm" — a colon is a strong enough signal that no leading "at" is needed.
    private static func matchTimeBranchB(_ folded: String) -> TimeCandidate? {
        guard let m = firstMatch(timeBranchBPattern, in: folded),
              let hour = m.output[1].substring.flatMap({ Int($0) }) else { return nil }
        let minute = m.output[2].substring.flatMap { Int($0) } ?? 0
        let marker = m.output[3].substring.map(String.init)
        return TimeCandidate(hour: hour, minute: minute, meridiem: meridiem(for: marker), fixed: false)
    }

    /// "10pm", "9am", "7 de la tarde" — a bare hour is only a time when an am/pm word rides right along with it.
    private static func matchTimeBranchC(_ folded: String) -> TimeCandidate? {
        guard let m = firstMatch(timeBranchCPattern, in: folded),
              let hour = m.output[1].substring.flatMap({ Int($0) }) else { return nil }
        let marker = m.output[2].substring.map(String.init)
        return TimeCandidate(hour: hour, minute: 0, meridiem: meridiem(for: marker), fixed: false)
    }

    private static func matchNoon(_ folded: String) -> TimeCandidate? {
        guard matches(noonPattern, in: folded) else { return nil }
        return TimeCandidate(hour: 12, minute: 0, meridiem: .pm, fixed: false)
    }

    /// Bare part-of-day words, only read when nothing more specific was said.
    private static func matchPartOfDay(_ folded: String) -> TimeCandidate? {
        if matches(morningPattern, in: folded) { return TimeCandidate(hour: 9, minute: 0, meridiem: nil, fixed: true) }
        if matches(afternoonPattern, in: folded) {
            return TimeCandidate(hour: 16, minute: 0, meridiem: nil, fixed: true)
        }
        if matches(eveningPattern, in: folded) {
            return TimeCandidate(hour: 20, minute: 0, meridiem: nil, fixed: true)
        }
        return nil
    }

    /// A final 24-hour hour, and whether "already passed today → tomorrow" may still apply (always, now: a
    /// reminder is never set in the past). A bare hour with no marker: 1…6 become afternoon; 7…11 stay morning
    /// unless today's morning slot already passed while the evening one hasn't; 12…23 are used as given.
    private static func resolve(
        _ candidate: TimeCandidate, isDayToday: Bool, now: Date, dayBase: Date, calendar: Calendar
    ) -> (hour: Int, minute: Int, nextDay: Bool) {
        if candidate.fixed {
            return (candidate.hour, candidate.minute, false)
        }
        if let meridiem = candidate.meridiem {
            // «12 de la noche»: midnight at the end of that day.
            if candidate.hour == 12, candidate.isNight { return (0, candidate.minute, true) }
            let hour24: Int
            switch meridiem {
            case .am: hour24 = candidate.hour == 12 ? 0 : candidate.hour
            case .pm: hour24 = candidate.hour >= 12 ? candidate.hour : candidate.hour + 12
            }
            return (hour24, candidate.minute, false)
        }
        if candidate.hour >= 12 || candidate.hour <= 0 {
            return (candidate.hour, candidate.minute, false)
        }
        if (1...6).contains(candidate.hour) {
            return (candidate.hour + 12, candidate.minute, false)
        }
        // 7...11: keep as morning unless today's version of it already passed and the evening one hasn't.
        let eveningHour = candidate.hour + 12
        if isDayToday,
           let morningDate = calendar.date(bySettingHour: candidate.hour, minute: candidate.minute, second: 0, of: dayBase),
           let eveningDate = calendar.date(bySettingHour: eveningHour, minute: candidate.minute, second: 0, of: dayBase),
           now > morningDate, now <= eveningDate {
            return (eveningHour, candidate.minute, false)
        }
        return (candidate.hour, candidate.minute, false)
    }
}
