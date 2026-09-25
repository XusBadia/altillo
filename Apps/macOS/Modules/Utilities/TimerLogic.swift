import CoreGraphics
import Foundation

// The kitchen timer's plain logic (phase 12): what a timer is, when the store has to wake up next, what the dial
// reads under the pointer and how "10 min", "1h 30" or "media hora" become seconds. Nothing here touches the
// clock or the disk, so all of it is tested with fixed dates.

/// One kitchen timer. Several can run at once ("Pasta" and "Pomodoro").
///
/// A running timer only stores its absolute end date, never a countdown: after sleep, a relaunch or a clock change
/// the remaining time is simply recomputed from it.
struct KitchenTimer: Identifiable, Codable, Equatable, Sendable {
    enum State: Codable, Equatable, Sendable {
        /// Counting down; rings at `endsAt`.
        case running(endsAt: Date)
        /// Stopped with this much left (a reset timer is paused at its full duration).
        case paused(remaining: TimeInterval)
        /// Went off at `at`. It stays in the list (with "Again") until the user dismisses it.
        case rang(at: Date)
    }

    /// Who set it: the user, or Ask on the user's behalf (undoable from the notch).
    enum Origin: String, Codable, Sendable {
        case user, ask
    }

    let id: UUID
    /// What it's for ("Pasta"); empty for an unnamed timer.
    var label: String
    /// The time it was set for, in seconds.
    var duration: TimeInterval
    var state: State
    var origin: Origin
    var createdAt: Date

    init(id: UUID = UUID(), label: String = "", duration: TimeInterval, state: State, origin: Origin = .user,
         createdAt: Date) {
        self.id = id
        self.label = label
        self.duration = duration
        self.state = state
        self.origin = origin
        self.createdAt = createdAt
    }

    /// Seconds left at `now` (0 once it has rung).
    func remaining(at now: Date) -> TimeInterval {
        switch state {
        case let .running(endsAt): max(0, endsAt.timeIntervalSince(now))
        case let .paused(remaining): remaining
        case .rang: 0
        }
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    var hasRung: Bool {
        if case .rang = state { return true }
        return false
    }

    var endsAt: Date? {
        if case let .running(endsAt) = state { return endsAt }
        return nil
    }

    var rangAt: Date? {
        if case let .rang(at) = state { return at }
        return nil
    }

    /// "Pasta", or "Timer" for an unnamed one.
    var displayName: String {
        label.isEmpty ? String(localized: "Timer") : label
    }
}

// MARK: - Scheduling

enum TimerLogic {
    /// A timer this close to ringing outranks the music in the contextual ear.
    static let imminentWindow: TimeInterval = 60
    /// A timer that rang this long ago still shows (with its bell) in the contextual ear.
    static let ringingWindow: TimeInterval = 5 * 60
    /// A timer that went off while Altillo wasn't running (or the Mac slept) still peeks if it's this recent.
    static let lateRingWindow: TimeInterval = 10 * 60
    /// Rung timers older than this are cleared away on launch.
    static let staleRungAge: TimeInterval = 12 * 3_600
    /// Longest timer: a day.
    static let maximumDuration: TimeInterval = 24 * 3_600

    /// Running timers whose end has come by `now` (a hair early counts: the wake-up is never exact).
    static func due(_ timers: [KitchenTimer], now: Date, tolerance: TimeInterval = 0.05) -> [KitchenTimer] {
        timers.filter { timer in
            guard let endsAt = timer.endsAt else { return false }
            return endsAt.timeIntervalSince(now) <= tolerance
        }
    }

    /// The next moment anything visible changes on its own: a running timer entering its last minute or ringing, a
    /// rung timer leaving the contextual ear. The store sleeps until then; with nothing running it never wakes.
    static func nextBoundary(_ timers: [KitchenTimer], now: Date) -> Date? {
        var dates: [Date] = []
        for timer in timers {
            switch timer.state {
            case let .running(endsAt):
                let imminent = endsAt.addingTimeInterval(-imminentWindow)
                if imminent > now { dates.append(imminent) }
                dates.append(endsAt)
            case let .rang(at):
                let quiet = at.addingTimeInterval(ringingWindow)
                if quiet > now { dates.append(quiet) }
            case .paused:
                break
            }
        }
        return dates.min()
    }

    /// Running timers first (soonest to ring), then paused ones, then the ones that rang (newest first).
    static func ordered(_ timers: [KitchenTimer], now: Date) -> [KitchenTimer] {
        timers.sorted { a, b in
            let rankA = rank(a), rankB = rank(b)
            if rankA != rankB { return rankA < rankB }
            switch (a.state, b.state) {
            case let (.running(x), .running(y)): return x < y
            case let (.rang(x), .rang(y)): return x > y
            default: return a.createdAt < b.createdAt
            }
        }
    }

    private static func rank(_ timer: KitchenTimer) -> Int {
        switch timer.state {
        case .rang: 0
        case .running: 1
        case .paused: 2
        }
    }

    /// What the contextual ear says about the timers at `now`: one that is ringing (recently rang), else the
    /// soonest running one. Paused timers never take the ear.
    static func signal(_ timers: [KitchenTimer], now: Date) -> TimerSignal? {
        if let ringing = timers
            .filter({ ($0.rangAt.map { now.timeIntervalSince($0) < ringingWindow }) ?? false })
            .max(by: { ($0.rangAt ?? .distantPast) < ($1.rangAt ?? .distantPast) }) {
            return TimerSignal(label: ringing.label, endsAt: ringing.rangAt ?? now, isRinging: true, isImminent: true,
                               runningCount: timers.count(where: \.isRunning))
        }
        let running = timers.filter(\.isRunning)
            .sorted { ($0.endsAt ?? .distantFuture) < ($1.endsAt ?? .distantFuture) }
        guard let soonest = running.first, let endsAt = soonest.endsAt else { return nil }
        return TimerSignal(label: soonest.label, endsAt: endsAt, isRinging: false,
                           isImminent: endsAt.timeIntervalSince(now) <= imminentWindow + 0.05,
                           runningCount: running.count)
    }
}

// MARK: - The dial

/// The kitchen-timer dial: 60 minutes around the face, 12 o'clock is zero, clockwise. Dragging snaps to whole
/// minutes and never jumps across zero (a real egg timer stops at its ends).
enum TimerDial {
    static let maximumMinutes = 60

    /// Degrees clockwise from 12 o'clock of `point` around `center` (0 ..< 360). Screen coordinates, y down.
    static func angle(of point: CGPoint, around center: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// Whole minutes under `angle`, given what the dial read just before (`previous`), so a drag that runs past
    /// 12 o'clock sticks at 60 (winding up) or at 0 (winding down) instead of wrapping round.
    static func minutes(forAngle angle: Double, previous: Int) -> Int {
        let raw = Int((angle / 6).rounded()) % 60
        if previous >= 45, raw <= 15 { return maximumMinutes }
        if previous == maximumMinutes, raw >= 45 { return raw }
        if previous <= 15, raw >= 45 { return 0 }
        return raw
    }

    /// The angle (degrees clockwise from 12) a number of seconds covers on the face (a full turn is an hour).
    static func sweep(forSeconds seconds: TimeInterval) -> Double {
        min(max(seconds, 0), Double(maximumMinutes) * 60) / 60 * 6
    }

    /// Five-minute marks passed going from `old` to `new` minutes: each one gets a haptic tick.
    static func crossesFiveMinuteMark(from old: Int, to new: Int) -> Bool {
        guard old != new else { return false }
        return old / 5 != new / 5 || new % 5 == 0
    }

    /// One step of VoiceOver's adjustable action (or an arrow key): a minute, clamped to the face.
    static func step(_ minutes: Int, by delta: Int) -> Int {
        min(max(minutes + delta, 0), maximumMinutes)
    }
}

// MARK: - Formatting

enum TimerFormat {
    /// "9:41", "1:05:00", "0:07": the countdown on the dial and in the ear.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "10 min", "1 h 30 min", "45 s": how long a timer was set for.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let secs = total % 60
        if hours > 0 {
            return minutes > 0 ? String(localized: "\(hours) h \(minutes) min") : String(localized: "\(hours) h")
        }
        if minutes > 0 {
            return secs > 0 ? String(localized: "\(minutes) min \(secs) s") : String(localized: "\(minutes) min")
        }
        return String(localized: "\(secs) s")
    }

    /// The ear, cheap: "12m" while there's more than a minute left (it changes once a minute), then "0:42".
    static func ear(_ seconds: TimeInterval) -> String {
        if seconds > 60 {
            let minutes = Int((seconds / 60).rounded(.up))
            if minutes >= 60 {
                let hours = minutes / 60
                let rest = minutes % 60
                return rest == 0 ? String(localized: "\(hours)h") : String(localized: "\(hours)h\(rest)")
            }
            return String(localized: "\(minutes)m")
        }
        return clock(seconds)
    }
}

// MARK: - Reading durations

/// Turns what people type or say into seconds: "10", "10 min", "25 minutes", "1h 30", "1:30", "90 s",
/// "media hora", "an hour and a half", "diez minutos", "un quart d'hora". English, Spanish and Catalan.
enum TimerDurationParser {
    struct Result: Equatable, Sendable {
        var seconds: TimeInterval
        /// Whatever words are left once the duration and the filler are gone ("Pasta"), capitalised.
        var label: String?
    }

    /// Just the duration, or nil if there isn't one (or it's zero, or longer than a day). With
    /// `bareNumbersAreMinutes` off, a number needs its unit ("pon 3 ejemplos" isn't three minutes).
    static func seconds(in text: String, bareNumbersAreMinutes: Bool = true) -> TimeInterval? {
        parse(text, bareNumbersAreMinutes: bareNumbersAreMinutes)?.seconds
    }

    /// The duration and a label from the rest ("10 pasta" → 10 min, "Pasta").
    static func parse(_ text: String, bareNumbersAreMinutes: Bool = true) -> Result? {
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return nil }
        var total: TimeInterval = 0
        var found = false
        var used = Set<Int>()
        var index = 0
        /// A number waiting for its unit ("1h 30": the 30 after hours is minutes).
        var lastUnit: TimeInterval?

        while index < tokens.count {
            let token = tokens[index]
            // "1:30" is minutes and seconds, "1:30:00" hours, minutes and seconds.
            if token.contains(":"), let clock = clockSeconds(token) {
                total += clock
                found = true
                used.insert(index)
                index += 1
                continue
            }
            // Fixed phrases: "media hora", "half an hour", "un quart d'hora", "hora y media".
            if let (value, length) = phrase(at: index, in: tokens) {
                total += value
                found = true
                used.formUnion(index..<(index + length))
                index += length
                lastUnit = value >= 3_600 ? 3_600 : 60
                continue
            }
            // "1h30", "10min", "90s" written together.
            if let (value, unit) = glued(token) {
                total += value * unit
                found = true
                used.insert(index)
                lastUnit = unit
                index += 1
                continue
            }
            if let value = number(token) {
                // Its unit is the next word, if it is one ("10 minutes", "diez minutos", "1,5 horas").
                if index + 1 < tokens.count, let unit = unit(tokens[index + 1]) {
                    total += value * unit
                    found = true
                    used.formUnion([index, index + 1])
                    lastUnit = unit
                    index += 2
                    // "una hora y media", "an hour and a half".
                    if unit == 3_600, let extra = andAHalf(at: index, in: tokens) {
                        total += 1_800
                        used.formUnion(index..<(index + extra))
                        index += extra
                    }
                    continue
                }
                // "1h 30": a bare number after hours is minutes; after minutes, seconds.
                if let previous = lastUnit, isDigits(token) {
                    total += value * (previous == 3_600 ? 60 : previous == 60 ? 1 : 1)
                    found = true
                    used.insert(index)
                    lastUnit = nil
                    index += 1
                    continue
                }
                // A bare figure ("10") is minutes; a word ("un", "a") without a unit isn't a duration.
                if bareNumbersAreMinutes, isDigits(token) || token.contains(".") || token.contains(",") {
                    total += value * 60
                    found = true
                    used.insert(index)
                    index += 1
                    continue
                }
            }
            // A unit on its own ("an hour", "una hora", "a minute") counts once.
            if let unit = unit(token), index > 0, ["a", "an", "one", "un", "una", "uno"].contains(tokens[index - 1]) {
                total += unit
                found = true
                used.formUnion([index - 1, index])
                lastUnit = unit
                index += 1
                if unit == 3_600, let extra = andAHalf(at: index, in: tokens) {
                    total += 1_800
                    used.formUnion(index..<(index + extra))
                    index += extra
                }
                continue
            }
            index += 1
        }

        guard found, total >= 1, total <= TimerLogic.maximumDuration else { return nil }
        // The label keeps the user's own spelling ("Café"), when the words line up.
        let typed = tokenize(text, folded: false)
        let leftover = tokens.enumerated()
            .filter { !used.contains($0.offset) && !filler.contains($0.element) }
            .map { typed.count == tokens.count ? typed[$0.offset] : $0.element }
        let label = leftover.isEmpty ? nil : leftover.joined(separator: " ")
        return Result(seconds: total, label: label.map(capitalised))
    }

    // MARK: Pieces

    /// Words, numbers and clock times, folded (lowercase, no accents) or as typed (for the label).
    private static func tokenize(_ text: String, folded: Bool = true) -> [String] {
        let source = folded
            ? text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            : text
        return source
            .split { !($0.isLetter || $0.isNumber || $0 == ":" || $0 == "." || $0 == ",") }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".,")) }
            .filter { !$0.isEmpty }
    }

    private static func isDigits(_ token: String) -> Bool {
        !token.isEmpty && token.allSatisfy(\.isNumber)
    }

    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40, "fortyfive": 45,
        "fifty": 50, "ninety": 90,
        "un": 1, "uno": 1, "una": 1, "dos": 2, "tres": 3, "cuatro": 4, "cinco": 5, "seis": 6, "siete": 7, "ocho": 8,
        "nueve": 9, "diez": 10, "once": 11, "doce": 12, "quince": 15, "veinte": 20, "veinticinco": 25, "treinta": 30,
        "cuarenta": 40, "cincuenta": 50, "noventa": 90,
        "dues": 2, "quatre": 4, "cinc": 5, "sis": 6, "set": 7, "vuit": 8, "nou": 9, "deu": 10, "quinze": 15,
        "vint": 20, "trenta": 30, "quaranta": 40, "cinquanta": 50,
    ]

    private static func number(_ token: String) -> Double? {
        if let value = Double(token.replacingOccurrences(of: ",", with: ".")), value >= 0 { return value }
        return numberWords[token]
    }

    private static func unit(_ token: String) -> TimeInterval? {
        switch token {
        case "h", "hr", "hrs", "hour", "hours", "hora", "horas", "hores": 3_600
        case "m", "min", "mins", "minute", "minutes", "minuto", "minutos", "minut", "minuts": 60
        case "s", "sec", "secs", "second", "seconds", "segundo", "segundos", "seg", "segon", "segons": 1
        default: nil
        }
    }

    /// "1h30", "10min", "90s", "1,5h".
    private static func glued(_ token: String) -> (TimeInterval, TimeInterval)? {
        guard let first = token.first, first.isNumber else { return nil }
        // "1h30": hours then minutes.
        if let h = token.firstIndex(of: "h"), token.last != "h" {
            let hours = String(token[..<h])
            let minutes = String(token[token.index(after: h)...]).replacingOccurrences(of: "min", with: "")
                .replacingOccurrences(of: "m", with: "")
            if let hoursValue = number(hours), let minutesValue = Double(minutes) {
                return (hoursValue * 3_600 + minutesValue * 60, 1)
            }
        }
        let digits = token.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let suffix = String(token.dropFirst(digits.count))
        guard !suffix.isEmpty, let value = number(String(digits)), let unit = unit(suffix) else { return nil }
        return (value, unit)
    }

    /// "1:30" → 90 s; "1:30:00" → 5 400 s.
    private static func clockSeconds(_ token: String) -> TimeInterval? {
        let parts = token.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let values = parts.compactMap { $0 }
        switch values.count {
        case 2 where values[1] < 60: return TimeInterval(values[0] * 60 + values[1])
        case 3 where values[1] < 60 && values[2] < 60:
            return TimeInterval(values[0] * 3_600 + values[1] * 60 + values[2])
        default: return nil
        }
    }

    /// Fixed phrases, with how many tokens they take.
    private static func phrase(at index: Int, in tokens: [String]) -> (TimeInterval, Int)? {
        let phrases: [([String], TimeInterval)] = [
            (["hora", "y", "media"], 5_400), (["hora", "i", "mitja"], 5_400),
            (["media", "hora"], 1_800), (["mitja", "hora"], 1_800), (["half", "an", "hour"], 1_800),
            (["half", "hour"], 1_800), (["un", "quart", "d", "hora"], 900), (["quart", "d", "hora"], 900),
            (["cuarto", "de", "hora"], 900), (["quarter", "of", "an", "hour"], 900), (["quarter", "hour"], 900),
        ]
        for (words, value) in phrases where index + words.count <= tokens.count {
            if Array(tokens[index..<(index + words.count)]) == words { return (value, words.count) }
        }
        return nil
    }

    /// "y media", "and a half", "i mitja" after an hour: tokens taken.
    private static func andAHalf(at index: Int, in tokens: [String]) -> Int? {
        for words in [["y", "media"], ["and", "a", "half"], ["i", "mitja"]] where index + words.count <= tokens.count {
            if Array(tokens[index..<(index + words.count)]) == words { return words.count }
        }
        return nil
    }

    /// Words that are never a label: verbs of asking, articles, "timer" itself.
    private static let filler: Set<String> = [
        "set", "start", "a", "an", "the", "for", "of", "timer", "timers", "me", "please", "in", "and", "my", "on",
        "remind", "countdown", "alarm", "minute", "minutes", "hour", "hours",
        "pon", "ponme", "poner", "pone", "un", "una", "uno", "temporizador", "de", "del", "para", "por", "el", "la",
        "y", "en", "avisame", "avisa", "cuenta", "atras", "minutos", "horas", "favor",
        "posa", "posam", "posa'm", "temporitzador", "per", "i", "d", "avisa'm", "compte", "enrere", "minuts", "hores",
        "que", "suene", "rings", "ring", "timer's", "cronometro",
    ]

    private static func capitalised(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

// MARK: - The contextual ear

/// The timer, as far as the contextual ear needs it (`NotchActivity.timer`).
struct TimerSignal: Equatable, Sendable {
    var label: String
    /// When it rings (or, for one that is ringing, when it rang).
    var endsAt: Date
    var isRinging: Bool
    /// Under a minute left (or ringing): it outranks the music.
    var isImminent: Bool
    var runningCount: Int
}
