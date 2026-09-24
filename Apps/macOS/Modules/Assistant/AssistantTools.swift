import AltilloCore
import AppKit
import EventKit
import Foundation
import FoundationModels

/// What the assistant is looking at right now, shown under the question ("Looking at your calendar…") and kept
/// with the answer as its sources.
enum AssistantActivity: String, Sendable, CaseIterable, Identifiable {
    case shelf, calendar, nowPlaying, clipboard, calculator, web

    var id: Self { self }

    var symbol: String {
        switch self {
        case .shelf: "tray"
        case .calendar: "calendar"
        case .nowPlaying: "music.note"
        case .clipboard: "doc.on.clipboard"
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
        case .calculator: String(localized: "Worked out exactly")
        case .web: String(localized: "Searched the web")
        }
    }

    /// Marks for the user's own things (the web and exact sums aren't tools the model calls; the store notes them).
    var isLocalContext: Bool {
        switch self {
        case .shelf, .calendar, .nowPlaying, .clipboard: true
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
        report: @escaping AssistantActivityReport
    ) -> [any Tool] {
        guard route == .context else { return [] }
        return [
            ShelfTool(items: shelfItems, report: report),
            CalendarTool(report: report),
            NowPlayingTool(report: report),
            ClipboardTool(report: report),
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
