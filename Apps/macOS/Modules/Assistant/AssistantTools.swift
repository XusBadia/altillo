import AltilloCore
import AppKit
import EventKit
import Foundation
import FoundationModels

/// What the assistant is looking at right now, shown under the question ("Looking at your calendar…") and kept
/// with the answer as its sources.
enum AssistantActivity: String, Sendable, CaseIterable, Identifiable {
    case shelf, calendar, nowPlaying, clipboard, usage, agents, calculator, web

    var id: Self { self }

    var symbol: String {
        switch self {
        case .shelf: "tray"
        case .calendar: "calendar"
        case .nowPlaying: "music.note"
        case .clipboard: "doc.on.clipboard"
        case .usage: "gauge.with.needle"
        case .agents: "hand.raised"
        case .calculator: "plus.forwardslash.minus"
        case .web: "globe"
        }
    }

    /// While the tool runs.
    var progress: String {
        switch self {
        case .shelf: String(localized: "Looking at your shelf…")
        case .calendar: String(localized: "Looking at your calendar…")
        case .nowPlaying: String(localized: "Listening to what's playing…")
        case .clipboard: String(localized: "Looking at what you copied…")
        case .usage: String(localized: "Looking at your AI usage…")
        case .agents: String(localized: "Looking at your agents…")
        case .calculator: String(localized: "Working it out…")
        case .web: String(localized: "Searching the web…")
        }
    }

    /// Once the answer is there: what it drew on (tooltip and VoiceOver).
    var source: String {
        switch self {
        case .shelf: String(localized: "Used your shelf")
        case .calendar: String(localized: "Used your calendar")
        case .nowPlaying: String(localized: "Used what's playing")
        case .clipboard: String(localized: "Used your clipboard")
        case .usage: String(localized: "Used your AI usage")
        case .agents: String(localized: "Used your agents")
        case .calculator: String(localized: "Worked out exactly")
        case .web: String(localized: "Searched the web")
        }
    }

    /// Marks for the user's own things (the web and exact sums aren't tools the model calls; the store notes them).
    var isLocalContext: Bool {
        switch self {
        case .shelf, .calendar, .nowPlaying, .clipboard, .usage, .agents: true
        case .calculator, .web: false
        }
    }
}

/// Tells the store a tool started, so the view can say so. Hops to the main actor.
typealias AssistantActivityReport = @MainActor @Sendable (AssistantActivity) -> Void

/// The assistant's tools: Altillo's own context, read on demand and only on this Mac. Only questions about the
/// user's things get them (`AssistantRoute.context`): handed tools, the small model calls them for anything, a haiku
/// included, and then apologises for what it didn't find. Descriptions are short on purpose: every word of them is
/// paid for in the context window.
enum AssistantTools {
    static func all(
        for route: AssistantRoute = .context,
        shelfItems: @escaping @MainActor @Sendable () -> [ShelfItem],
        usage: @escaping @MainActor @Sendable () -> AssistantUsage.Reading = { AssistantUsage.liveReading() },
        agents: @escaping @MainActor @Sendable () -> AssistantAgents.Reading = { AssistantAgents.liveReading() },
        report: @escaping AssistantActivityReport
    ) -> [any Tool] {
        guard route == .context else { return [] }
        return [
            ShelfTool(items: shelfItems, report: report),
            CalendarTool(report: report),
            NowPlayingTool(report: report),
            ClipboardTool(report: report),
            UsageTool(reading: usage, report: report),
            AgentsTool(reading: agents, report: report),
        ]
    }
}

// MARK: - Shelf

struct ShelfTool: Tool {
    let name = "shelf"
    let description = "The user's shelf: saved files, documents, notes and links, with the text of the newest. Pass a name to read one."

    @Generable
    struct Arguments {
        @Guide(description: "Name of one item to read. Omit to list the shelf.")
        var name: String?
    }

    let items: @MainActor @Sendable () -> [ShelfItem]
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.shelf)
        let items = await items()
        let answer = AssistantContent.shelfAnswer(name: arguments.name, items: items)
        await SpikeLog.shared.record(
            SpikeLog.Category.assistant, "tool shelf read=\(arguments.name != nil) → \(answer.count) chars"
        )
        return answer
    }
}

// MARK: - Calendar

struct CalendarTool: Tool {
    let name = "calendar"
    let description = "Gets the user's calendar events for one day."

    @Generable
    struct Arguments {
        @Guide(description: "Days from today: 0 today, 1 tomorrow, -1 yesterday.", .range(-30...60))
        var dayOffset: Int
    }

    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.calendar)
        // Never ask from here: a permission dialog popping up in the middle of an answer would be a surprise,
        // and the Calendar section already asks properly.
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return AssistantContent.calendarNotGranted
        }
        let calendar = Calendar.current
        let now = Date.now
        let day = calendar.date(byAdding: .day, value: arguments.dayOffset, to: calendar.startOfDay(for: now)) ?? now
        let hidden = await MainActor.run { AltilloSettings.shared.calendarHiddenIDs }
        let events = await AssistantCalendar.shared.events(on: day, calendar: calendar, hiding: hidden)
        let answer = AssistantContent.agenda(events, day: day, now: now, calendar: calendar)
        await SpikeLog.shared.record(
            SpikeLog.Category.assistant, "tool calendar offset=\(arguments.dayOffset) → \(events.count) events"
        )
        return answer
    }
}

/// The assistant's own `EKEventStore`, created only once access is known to be granted (creating one never asks,
/// but there's no reason to have it otherwise). `EKEventStore` isn't `Sendable`, so it stays inside this actor.
actor AssistantCalendar {
    static let shared = AssistantCalendar()

    private var store: EKEventStore?

    /// The day's events, cancelled and declined ones left out.
    func events(on day: Date, calendar: Calendar, hiding hidden: Set<String> = []) -> [CalendarStore.Event] {
        let store = self.store ?? EKEventStore()
        self.store = store
        store.reset()
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return [] }
        return CalendarVisibility.events(in: store, from: day, to: end, hiding: hidden)
            .filter { event in
                event.status != .canceled
                    && !(event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
            }
            .map { event in
                let start = event.startDate ?? day
                let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarStore.Event(
                    id: "\(event.eventIdentifier ?? title)@\(start.timeIntervalSinceReferenceDate)",
                    title: title.isEmpty ? "Untitled" : title,
                    start: start,
                    end: event.endDate ?? start,
                    calendarColorHex: 0,
                    location: location?.isEmpty == false ? location : nil,
                    conferenceURL: MeetingLink.find(url: event.url, location: event.location, notes: event.notes),
                    isAllDay: event.isAllDay
                )
            }
    }
}

// MARK: - Now playing

struct NowPlayingTool: Tool {
    let name = "nowPlaying"
    let description = "Gets the song playing in Music or Spotify."

    @Generable
    struct Arguments {}

    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.nowPlaying)
        let answer = await AssistantNowPlaying.read()
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool nowPlaying → \(answer.count) chars")
        return answer
    }
}

/// Asks Music and Spotify what they're doing, read-only, with the same scripts as the Now Playing section.
///
/// Never launches a player (only running ones are asked) and never shows the Automation dialog: the permission is
/// checked first without asking, and a player we aren't allowed to talk to is simply reported as such.
enum AssistantNowPlaying {
    enum Permission: Equatable, Sendable { case granted, denied, notAsked, notRunning }

    static func read() async -> String {
        let running = await MainActor.run {
            let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            return MusicPlayer.allCases.filter { open.contains($0.bundleID) }
        }
        guard !running.isEmpty else {
            return "Neither Music nor Spotify is open, so nothing is playing that Altillo can see."
        }

        var paused: String?
        var blocked: [MusicPlayer] = []
        for player in running {
            guard permission(for: player) == .granted else {
                blocked.append(player)
                continue
            }
            guard let output = try? await AppleScriptRunner.run(MusicPlayerScripts.status(for: player)),
                  let snapshot = MusicPlayerScripts.parse(output)
            else { continue }
            let sentence = AssistantContent.nowPlaying(snapshot, app: player.appName)
            if snapshot.isPlaying { return sentence }
            if paused == nil { paused = sentence }
        }
        if let paused { return paused }
        if !blocked.isEmpty {
            let names = blocked.map(\.appName).joined(separator: " and ")
            return "Altillo isn't allowed to ask \(names) what's playing. Tell the user they can allow it from the Now Playing section."
        }
        let names = running.map(\.appName).joined(separator: " and ")
        return "\(names) \(running.count == 1 ? "is" : "are") open, but nothing is playing."
    }

    /// Asks the system whether Altillo may send Apple Events to the player, without ever showing the dialog.
    /// Blocks for a moment, so it's only called off the main actor.
    static func permission(for player: MusicPlayer) -> Permission {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.bundleID)
        guard let address = target.aeDesc else { return .notAsked }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, false)
        return permission(status: status)
    }

    static func permission(status: OSStatus) -> Permission {
        switch Int(status) {
        case Int(noErr): .granted
        case -1743: .denied // errAEEventNotPermitted
        case -1744: .notAsked // errAEEventWouldRequireUserConsent
        case -600: .notRunning // procNotFound
        default: .denied
        }
    }
}

// MARK: - Clipboard

struct ClipboardTool: Tool {
    let name = "clipboard"
    let description = "Gets the text the user last copied. Only when the user asks about what they copied."

    @Generable
    struct Arguments {}

    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.clipboard)
        let answer = await MainActor.run { AssistantContent.readClipboard() }
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool clipboard → \(answer.count) chars")
        return answer
    }
}

// MARK: - AI usage

struct UsageTool: Tool {
    let name = "usage"
    let description = "The user's AI limits (Claude, Codex…): how much is used, when each refills and the pace."

    @Generable
    struct Arguments {
        @Guide(description: "One provider, like Claude or Codex. Omit for all.")
        var provider: String?
    }

    let reading: @MainActor @Sendable () -> AssistantUsage.Reading
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.usage)
        // Never the network: the numbers Altillo already has (refreshed every 5 min by `UsageStore`).
        let reading = await reading()
        let answer = AssistantUsage.answer(reading, provider: arguments.provider, now: .now)
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool usage → \(answer.count) chars")
        return answer
    }
}

/// What Ask's `usage` tool says, in plain English for the model: one line per limit with its figure, when it
/// refills and the pace, and how old the numbers are.
enum AssistantUsage {
    struct Reading: Sendable {
        /// The usage section is on (with it off, nothing is read).
        var isEnabled: Bool
        var providers: [ProviderUsage]
    }

    /// The running app's latest numbers, as `UsageStore` has them.
    @MainActor
    static func liveReading() -> Reading {
        guard let store = UsageStore.live else { return Reading(isEnabled: false, providers: []) }
        return Reading(isEnabled: store.settings.isEnabled(.usage), providers: store.providers)
    }

    static func answer(_ reading: Reading, provider: String?, now: Date,
                       calendar: Calendar = .current) -> String {
        guard reading.isEnabled else {
            return "The Usage section is turned off in Altillo, so it isn't reading any AI limits. Tell the user they can turn it on in Settings › Sections."
        }
        guard !reading.providers.isEmpty else {
            return "Altillo isn't reading any AI limits yet: neither Claude Code nor Codex is signed in on this Mac."
        }
        var providers = reading.providers
        if let wanted = provider.map(AssistantHTML.fold), !wanted.isEmpty {
            let matches = providers.filter {
                AssistantHTML.fold($0.displayName).contains(wanted) || wanted.contains(AssistantHTML.fold($0.displayName))
                    || $0.id.rawValue == wanted
            }
            if matches.isEmpty {
                let names = providers.map(\.displayName).joined(separator: ", ")
                return "Altillo doesn't read \(provider ?? "that provider"). It reads: \(names)."
            }
            providers = matches
        }
        return providers.map { describe($0, now: now, calendar: calendar) }.joined(separator: "\n\n")
    }

    private static func describe(_ usage: ProviderUsage, now: Date, calendar: Calendar) -> String {
        var lines: [String] = []
        let plan = usage.plan.map { " (\($0) plan)" } ?? ""
        lines.append("\(usage.displayName)\(plan):")
        if usage.windows.isEmpty && usage.balances.isEmpty {
            if let problem = usage.problem {
                lines.append("- No numbers: \(UsageText.sentence(for: problem, provider: usage.id, displayName: usage.displayName, now: now))")
            } else {
                lines.append("- No limits reported.")
            }
            return lines.joined(separator: "\n")
        }
        for window in usage.windows {
            let used = Int((window.used * 100).rounded())
            var line = "- \(UsageText.name(for: window)): \(used)% used, \(max(0, 100 - used))% left"
            if let resetsAt = window.resetsAt, resetsAt > now {
                line += ", refills in \(NotchFormat.countdown(to: resetsAt, now: now)) (\(time(resetsAt, now: now, calendar: calendar)))"
            } else if window.resetsAt == nil, window.kind == .session {
                line += ", starts with the next message"
            }
            switch UsagePace.evaluate(window, now: now) {
            case let .behind(runsOutAt?):
                line += ". At this pace it runs out at \(time(runsOutAt, now: now, calendar: calendar)), before it refills"
            case .behind(nil) where window.used >= 1:
                line += ". The limit is reached"
            case .ahead:
                line += ". Plenty left at this pace"
            case .onTrack:
                line += ". On track to last until it refills"
            default:
                break
            }
            lines.append(line + ".")
        }
        for balance in usage.balances where UsageText.figure(for: balance) != nil {
            lines.append("- \(balance.label): \(UsageText.summary(of: balance)).")
        }
        let age = NotchFormat.ago(usage.fetchedAt, now: now)
        if let problem = usage.problem {
            lines.append("- These numbers are from \(age): \(UsageText.sentence(for: problem, provider: usage.id, displayName: usage.displayName, now: now))")
        } else {
            lines.append("- Read \(age).")
        }
        return lines.joined(separator: "\n")
    }

    /// "16:10" today, "Friday 09:00" another day.
    private static func time(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.weekday(.wide).hour().minute())
    }
}

// MARK: - Agents

struct AgentsTool: Tool {
    let name = "agents"
    let description = "The user's coding agents (Claude Code, Codex): what each is doing and what it waits for."

    @Generable
    struct Arguments {
        @Guide(description: "One agent or project, like Codex or altillo. Omit for all.")
        var agent: String?
    }

    let reading: @MainActor @Sendable () -> AssistantAgents.Reading
    let report: AssistantActivityReport

    func call(arguments: Arguments) async throws -> String {
        await report(.agents)
        // Never the network: the sessions Altillo already follows (`AgentHub`).
        let reading = await reading()
        let answer = AssistantAgents.answer(reading, agent: arguments.agent, now: .now)
        await SpikeLog.shared.record(SpikeLog.Category.assistant, "tool agents → \(answer.count) chars")
        return answer
    }
}

/// What Ask's `agents` tool says, in plain English for the model: one line per session with where it runs, what
/// it's doing or waiting for, and since when. It only reads; answering a permission is the notch's job.
enum AssistantAgents {
    struct Reading: Sendable {
        /// The agents section is on (with it off, nothing is read).
        var isEnabled: Bool
        var sessions: [AgentSession]
    }

    /// The running app's model, set when it's created.
    @MainActor static weak var live: NotchModel?

    /// The sessions `AgentHub` follows right now.
    @MainActor
    static func liveReading() -> Reading {
        guard let model = live else { return Reading(isEnabled: false, sessions: []) }
        return Reading(isEnabled: model.settings.isEnabled(.agents), sessions: model.agentHub.sessions)
    }

    static func answer(_ reading: Reading, agent: String?, now: Date) -> String {
        guard reading.isEnabled else {
            return "The Agents section is turned off in Altillo, so it isn't following any coding agents. Tell the user they can turn it on in Settings › Sections."
        }
        guard !reading.sessions.isEmpty else {
            return "No coding agent sessions right now. Altillo follows Claude Code and Codex on this Mac; when one works, asks for permission or finishes, it shows up in the notch."
        }
        var sessions = AgentsLogic.ordered(reading.sessions)
        if let wanted = agent.map(AssistantHTML.fold)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty {
            let matches = sessions.filter { session in
                let names = [session.agent.name, session.agent.rawValue, session.project].map(AssistantHTML.fold)
                    .filter { !$0.isEmpty }
                return names.contains { $0 == wanted || $0.contains(wanted) || wanted.contains($0) }
            }
            if matches.isEmpty {
                let names = Set(sessions.map(\.agent.name)).sorted().joined(separator: ", ")
                return "No \(agent ?? "such") session right now. Sessions Altillo follows: \(names)."
            }
            sessions = matches
        }
        var lines = sessions.map { describe($0, now: now) }
        let waiting = sessions.count { $0.phase.needsUser }
        if waiting > 0 {
            lines.append("The user can answer from the Agents section of the notch or in the terminal.")
        }
        return lines.joined(separator: "\n")
    }

    static func describe(_ session: AgentSession, now: Date) -> String {
        var line = "- \(session.agent.name) in \(session.project): "
        switch session.phase {
        case .waitingPermission:
            if let request = session.pendingRequest {
                line += "waiting for permission to use \(request.toolName) (\(request.summary))"
                if request.isDangerous { line += ", a dangerous one" }
                line += ", asked \(NotchFormat.ago(request.requestedAt, now: now))"
                if AgentsLogic.isExpired(request, now: now) { line += " (it's asking in the terminal now)" }
            } else {
                line += "waiting for permission, since \(NotchFormat.ago(session.lastActivity, now: now))"
            }
        case .waitingAnswer:
            line += "waiting for the user's answer, since \(NotchFormat.ago(session.lastActivity, now: now))"
            if let message = AgentsLogic.excerpt(session.lastMessage, limit: 160) { line += ". It said: \"\(message)\"" }
        case .working:
            line += "working"
            if let activity = session.activity, !activity.isEmpty { line += " (\(activity))" }
            line += ", started \(NotchFormat.ago(session.startedAt, now: now))"
        case .idle:
            line += "idle, last active \(NotchFormat.ago(session.lastActivity, now: now))"
        case .finished:
            line += "finished \(NotchFormat.ago(session.lastActivity, now: now))"
            if let message = AgentsLogic.excerpt(session.lastMessage, limit: 160) { line += ". Its last words: \"\(message)\"" }
        case .failed:
            line += "failed \(NotchFormat.ago(session.lastActivity, now: now))"
            if let message = AgentsLogic.excerpt(session.lastMessage, limit: 160) { line += ": \"\(message)\"" }
        }
        if session.source == .sessionFile { line += " (read from its session file, so approximate)" }
        return line + "."
    }
}
