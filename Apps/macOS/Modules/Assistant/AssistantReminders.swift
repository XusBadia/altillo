import EventKit
import Foundation
import FoundationModels

// Phase 13: «recuérdame comprar pan a las 7», "remind me to call Ana tomorrow at 10". Ask adds it to the Reminders
// app, says exactly what it made, and the answer carries an Undo. Access to Reminders is asked for only the first
// time the user asks for one, never before and never for anything else.

/// What an action did, shown under the answer whatever the model says about it, with an Undo when it can be undone.
struct AssistantActionReceipt: Identifiable, Equatable, Sendable {
    enum Undo: Equatable, Sendable {
        /// The reminder's `calendarItemIdentifier`.
        case reminder(String)
    }

    /// A one-click follow-up when nothing was made ("today at 9" had already gone by).
    enum Offer: Equatable, Sendable {
        /// The same reminder at this moment (tomorrow, same time).
        case reminder(title: String, due: Date)
    }

    let id: UUID
    var symbol: String
    /// "Call Ana" (localised framing is the view's).
    var title: String
    /// "Tomorrow at 10:00", "Sent to Claude in altillo"…
    var detail: String?
    var undo: Undo?
    var isUndone = false
    /// Undo was tried and the reminder couldn't be removed.
    var undoFailed = false
    var offer: Offer?

    init(id: UUID = UUID(), symbol: String, title: String, detail: String? = nil, undo: Undo? = nil,
         offer: Offer? = nil) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.undo = undo
        self.offer = offer
    }
}

/// Hands a receipt to the store, which pins it to the answer being written. Hops to the main actor.
typealias AssistantReceiptReport = @MainActor @Sendable (AssistantActionReceipt) -> Void

struct RemindersTool: Tool {
    let name = "reminders"
    let description = "Adds a reminder to the user's Reminders app."

    @Generable
    struct Arguments {
        @Guide(description: "What to be reminded of, in the user's words, without the date or time.")
        var title: String
        @Guide(description: "When, as the user said it: \"tomorrow at 10\", \"a las 7\". Omit if they didn't say.")
        var when: String?
    }

    /// The question it answers: the date is read from it too when the model leaves `when` out.
    let question: String
    let store: any ReminderStoring
    /// Shared by every session of one question: a retry never makes a second reminder.
    var once = AssistantActionOnce()
    let report: AssistantActivityReport
    let receipt: AssistantReceiptReport

    func call(arguments: Arguments) async throws -> String {
        await report(.reminders)
        let (result, isNew) = await once.run {
            await AssistantReminders.create(
                title: arguments.title, when: arguments.when, question: question, store: store, now: .now
            )
        }
        if isNew, let made = result.receipt { await receipt(made) }
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool reminders → \(result.answer.count) chars")
        return result.answer
    }
}

/// One action per question. The model may call a tool twice, and a failed answer is retried in a fresh session:
/// after the first reminder is made, every later call for the same question gets that first result back.
actor AssistantActionOnce {
    private var done: AssistantReminders.Result?
    private var running = false

    /// The first call's result, run once; `isNew` is false for the calls that just got it back.
    func run(_ work: @Sendable () async -> AssistantReminders.Result) async -> (AssistantReminders.Result, isNew: Bool) {
        if let done { return (done, false) }
        guard !running else {
            return (AssistantReminders.Result(answer: "The reminder is already being made. Don't call reminders again."), false)
        }
        running = true
        let result = await work()
        running = false
        // Only something made counts; a refusal or a question back can be tried again.
        if result.receipt?.undo != nil { done = result }
        return (result, true)
    }
}

// MARK: - The store behind it

enum ReminderAccess: Equatable, Sendable {
    case granted, notDetermined, denied
}

struct CreatedReminder: Equatable, Sendable {
    var identifier: String
    /// The list it went into ("Reminders", «Recordatorios»).
    var listName: String
}

/// Reminders, reachable without EventKit in tests.
protocol ReminderStoring: Sendable {
    func access() async -> ReminderAccess
    /// Shows the system's permission dialog. Only called when the user asked for a reminder.
    func requestAccess() async -> Bool
    func create(title: String, due: ReminderDue?, calendar: Calendar) async throws -> CreatedReminder
    /// Removes a reminder Ask made (Undo). False when it's gone already.
    func remove(identifier: String) async -> Bool
}

/// The real Reminders, through one `EKEventStore` kept inside this actor (`EKEventStore` isn't `Sendable`).
actor LiveReminderStore: ReminderStoring {
    static let shared = LiveReminderStore()

    private var store: EKEventStore?

    private var eventStore: EKEventStore {
        if let store { return store }
        let made = EKEventStore()
        store = made
        return made
    }

    func access() -> ReminderAccess {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func requestAccess() async -> Bool {
        let store = eventStore
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        return granted
    }

    func create(title: String, due: ReminderDue?, calendar: Calendar) throws -> CreatedReminder {
        let store = eventStore
        guard let list = store.defaultCalendarForNewReminders() else {
            throw CocoaError(.featureUnsupported)
        }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = list
        if let due {
            let units: Set<Calendar.Component> = due.hasTime
                ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            var components = calendar.dateComponents(units, from: due.date)
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            reminder.dueDateComponents = components
            // A due time alone doesn't ring on the Mac: the alarm is what notifies.
            if due.hasTime { reminder.addAlarm(EKAlarm(absoluteDate: due.date)) }
        }
        try store.save(reminder, commit: true)
        return CreatedReminder(identifier: reminder.calendarItemIdentifier, listName: list.title)
    }

    func remove(identifier: String) -> Bool {
        let store = eventStore
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return false }
        return (try? store.remove(reminder, commit: true)) != nil
    }
}

// MARK: - What the tool does and says

enum AssistantReminders {
    struct Result: Equatable, Sendable {
        /// For the model, plain English.
        var answer: String
        var receipt: AssistantActionReceipt?
    }

    /// Makes the reminder. Asks for access only if it was never asked; says plainly when it can't.
    static func create(title: String, when: String?, question: String, store: any ReminderStoring, now: Date,
                       calendar: Calendar = .current) async -> Result {
        let clean = cleanTitle(title, question: question)
        guard !clean.isEmpty else {
            return Result(answer: "No reminder was made: there was nothing to be reminded of. Ask the user what the reminder should say.")
        }
        var justAllowed = false
        switch await store.access() {
        case .granted:
            break
        case .denied:
            return Result(answer: "No reminder was made: Altillo isn't allowed to use Reminders. Tell the user they can allow it in System Settings › Privacy & Security › Reminders.")
        case .notDetermined:
            guard await store.requestAccess() else {
                return Result(answer: "No reminder was made: the user didn't allow Altillo to use Reminders. Tell them they can change it in System Settings › Privacy & Security › Reminders.")
            }
            justAllowed = true
        }

        let due = due(when: when, question: question, now: now, calendar: calendar)
        if let due, due.hasPassed {
            // "Today at 9" at 17:00: nothing is made in the past; the same time tomorrow is one click away.
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: due.date) ?? due.date
            let time = clock(due.date, calendar: calendar)
            return Result(
                answer: "No reminder was made: \(time) today has already passed. Tell the user so in one sentence; they can set it for tomorrow at \(time) with one click in the notch.",
                receipt: AssistantActionReceipt(
                    symbol: "clock.badge.exclamationmark",
                    title: clean,
                    detail: String(localized: "\(userTime(due.date, calendar: calendar)) has already passed today"),
                    offer: .reminder(title: clean, due: tomorrow)
                )
            )
        }
        let made: CreatedReminder
        do {
            made = try await store.create(title: clean, due: due, calendar: calendar)
        } catch {
            return Result(answer: "No reminder was made: Reminders couldn't save it (\(error.localizedDescription)). Tell the user to try again.")
        }
        let when = due.map { " " + describe($0, now: now, calendar: calendar) } ?? ", with no date"
        var answer = "Reminder created in the \"\(made.listName)\" list: \"\(clean)\"\(when)."
        if justAllowed { answer += " The user has just allowed Altillo to use Reminders; thank them in a few words." }
        answer += " Tell the user exactly that in one sentence; they can undo it from the notch."
        let receipt = AssistantActionReceipt(
            symbol: "checklist",
            title: clean,
            detail: due.map { String(localized: "In Reminders · \(userFacing($0, now: now, calendar: calendar))") }
                ?? String(localized: "In Reminders"),
            undo: .reminder(made.identifier)
        )
        return Result(answer: answer, receipt: receipt)
    }

    /// The model's `when` first (with the day from the question when it only kept the time: "at 10" for
    /// «mañana a las 10»); the question itself when the model left it out or it says nothing readable.
    static func due(when: String?, question: String, now: Date, calendar: Calendar) -> ReminderDue? {
        if let when, !when.trimmingCharacters(in: .whitespaces).isEmpty,
           let due = ReminderDateParser.parse(when, now: now, calendar: calendar, dayHint: question) {
            return due
        }
        return ReminderDateParser.parse(question, now: now, calendar: calendar)
    }

    /// Makes the reminder the receipt offered (the same time tomorrow).
    static func accept(_ offer: AssistantActionReceipt.Offer, store: any ReminderStoring, now: Date,
                       calendar: Calendar = .current) async -> AssistantActionReceipt? {
        guard case let .reminder(title, date) = offer, date > now, await store.access() == .granted,
              let made = try? await store.create(title: title, due: ReminderDue(date: date, hasTime: true),
                                                 calendar: calendar)
        else { return nil }
        let due = ReminderDue(date: date, hasTime: true)
        return AssistantActionReceipt(
            symbol: "checklist", title: title,
            detail: String(localized: "In Reminders · \(userFacing(due, now: now, calendar: calendar))"),
            undo: .reminder(made.identifier)
        )
    }

    /// "09:00", in English for the model.
    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "HH:mm"
        return format.string(from: date)
    }

    /// "9:00", in the user's language.
    static func userTime(_ date: Date, calendar: Calendar) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current, calendar: calendar,
                                        timeZone: calendar.timeZone))
    }

    /// The model sometimes keeps the date or the asking words in the title, and lowercases names ("call ana"):
    /// words the user typed get their casing back from the question.
    static func cleanTitle(_ title: String, question: String = "") -> String {
        let stripped = ReminderDateParser.strippingDatePhrases(from: title)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”«».,")))
        let typed = Dictionary(
            question.split(whereSeparator: \.isWhitespace).map { (String($0).lowercased(), String($0)) },
            uniquingKeysWith: { first, _ in first }
        )
        let restored = stripped.split(separator: " ", omittingEmptySubsequences: false)
            .map { word in typed[word.lowercased()] ?? String(word) }
            .joined(separator: " ")
        guard let first = restored.first else { return "" }
        return first.uppercased() + restored.dropFirst()
    }

    /// "tomorrow (Saturday 26 September) at 10:00", in English for the model.
    static func describe(_ due: ReminderDue, now: Date, calendar: Calendar) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = "EEEE d MMMM"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateFormat = "HH:mm"
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: due.date)).day ?? 99
        let name = switch offset {
        case 0: "today"
        case 1: "tomorrow (\(day.string(from: due.date)))"
        default: "on \(day.string(from: due.date))"
        }
        return "due " + name + (due.hasTime ? " at \(time.string(from: due.date))" : "")
    }

    /// "Tomorrow, 10:00" for the receipt, in the user's language.
    static func userFacing(_ due: ReminderDue, now: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: .current, calendar: calendar,
                                     timeZone: calendar.timeZone)
        let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                             to: calendar.startOfDay(for: due.date)).day ?? 99
        let dayText: String
        switch offset {
        case 0: dayText = String(localized: "Today")
        case 1: dayText = String(localized: "Tomorrow")
        default:
            style = style.weekday(.wide).day().month(.wide)
            dayText = due.date.formatted(style)
        }
        guard due.hasTime else { return dayText }
        let time = due.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current,
                                                       calendar: calendar, timeZone: calendar.timeZone))
        return String(localized: "\(dayText), \(time)")
    }

    /// The Undo under the answer.
    static func undo(identifier: String, store: any ReminderStoring) async -> Bool {
        await store.remove(identifier: identifier)
    }
}
