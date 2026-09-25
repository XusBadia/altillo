import Foundation
import FoundationModels

// Ask learns the kitchen timer (phase 12): «pon 10 min», "set a 25 minute timer for the pasta", "what timers are
// running?". The first thing Ask *does* rather than reads, so every answer says exactly what was done, and the timer
// section offers "Undo" on a timer Ask set.

struct TimerTool: Tool {
    let name = "timer"
    let description = "Starts a kitchen timer, lists the running ones or cancels one."

    @Generable
    enum Action {
        case start, list, cancel
    }

    @Generable
    struct Arguments {
        @Guide(description: "start, list or cancel.")
        var action: Action
        @Guide(description: "How long, as the user said it: \"10 min\", \"1h 30\", \"25 minutes\". Only to start.")
        var duration: String?
        @Guide(description: "What it's for, like Pasta. Optional.")
        var label: String?
    }

    let perform: @MainActor @Sendable (TimerAssistant.Request) -> String
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.timer)
        let request: TimerAssistant.Request = switch arguments.action {
        case .start: .start(duration: arguments.duration ?? "", label: arguments.label)
        case .list: .list
        case .cancel: .cancel(label: arguments.label)
        }
        let answer = await perform(request)
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool timer \(arguments.action) → \(answer.count) chars")
        return answer
    }
}

/// What Ask's `timer` tool does and says, in plain English for the model.
enum TimerAssistant {
    enum Request: Equatable, Sendable {
        case start(duration: String, label: String?)
        case list
        case cancel(label: String?)
    }

    /// Acts on the running app's timers (`NotchModel.timers`).
    @MainActor
    static func live(_ request: Request) -> String {
        guard let model = AssistantAgents.live else {
            return "The timer isn't available right now."
        }
        return perform(request, store: model.timers, isEnabled: model.settings.isEnabled(.timer), now: .now)
    }

    @MainActor
    static func perform(_ request: Request, store: TimerStore, isEnabled: Bool, now: Date,
                        calendar: Calendar = .current) -> String {
        guard isEnabled else {
            return "The Timer section is turned off in Altillo, so no timer was set. Tell the user they can turn it on in Settings › Sections, or from the notch's Customize mode."
        }
        switch request {
        case let .start(duration, label):
            guard let parsed = TimerDurationParser.parse(duration), parsed.seconds >= 1 else {
                return "No timer was set: couldn't tell how long from \"\(duration)\". Ask the user how many minutes."
            }
            let name = [label, parsed.label].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty && !genericLabels.contains(AssistantHTML.fold($0)) } ?? ""
            let timer = store.start(seconds: parsed.seconds, label: name, origin: .ask)
            let ends = timer.endsAt.map { clock($0, now: now, calendar: calendar) } ?? ""
            let what = name.isEmpty ? "Timer set" : "Timer set: \(name)"
            return "\(what), \(TimerFormat.duration(timer.duration)). It rings at \(ends). Tell the user exactly that; they can undo it from the Timer section of the notch."
        case .list:
            let timers = store.ordered
            guard !timers.isEmpty else { return "No timers are set." }
            return timers.map { describe($0, now: now, calendar: calendar) }.joined(separator: "\n")
        case let .cancel(label):
            let candidates = store.ordered.filter { !$0.hasRung }
            guard !candidates.isEmpty else { return "There's no timer to cancel." }
            let wanted = label.map(AssistantHTML.fold)?.trimmingCharacters(in: .whitespaces) ?? ""
            let target: KitchenTimer?
            if wanted.isEmpty || genericLabels.contains(wanted) {
                target = candidates.count == 1 ? candidates.first : nil
            } else {
                target = candidates.first { timer in
                    let name = AssistantHTML.fold(timer.label)
                    return !name.isEmpty && (name == wanted || name.contains(wanted) || wanted.contains(name))
                }
            }
            guard let target else {
                let names = candidates.map { "\($0.displayName) (\(TimerFormat.duration($0.duration)))" }
                    .joined(separator: ", ")
                return "Nothing was cancelled: which timer? Running: \(names)."
            }
            store.remove(target.id)
            return "Cancelled the timer \(target.displayName) (\(TimerFormat.duration(target.duration)))."
        }
    }

    /// Labels that only say "timer": the timer stays unnamed.
    private static let genericLabels: Set<String> = [
        "timer", "temporizador", "temporitzador", "a timer", "un temporizador", "countdown", "alarm", "alarma",
    ]

    static func describe(_ timer: KitchenTimer, now: Date, calendar: Calendar) -> String {
        let set = TimerFormat.duration(timer.duration)
        switch timer.state {
        case let .running(endsAt):
            return "- \(timer.displayName) (\(set)): \(TimerFormat.duration(max(1, endsAt.timeIntervalSince(now)))) left, rings at \(clock(endsAt, now: now, calendar: calendar))."
        case let .paused(remaining):
            return "- \(timer.displayName) (\(set)): paused with \(TimerFormat.duration(remaining)) left."
        case let .rang(at):
            return "- \(timer.displayName) (\(set)): rang at \(clock(at, now: now, calendar: calendar))."
        }
    }

    /// "14:32" today, "Friday 09:00" another day.
    private static func clock(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}
