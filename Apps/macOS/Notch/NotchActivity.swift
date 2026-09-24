import CoreGraphics
import Foundation

/// What the contextual left ear (`EarContent.automatic`) is about right now: the one thing most worth a glance.
///
/// One place decides the order (PLAN §4, "Orejas"): an agent asking for something beats an event about to start,
/// which beats music playing, which beats AI usage; with none of them the ear rests. Only sections the user has on
/// and real data take part: design scenarios and sample content never reach here, and the mirror never does (the
/// camera only ever runs while its section is on screen).
enum NotchActivity: Equatable, Sendable {
    /// An agent is waiting for the user's answer (phase 4 feeds it; nothing real exists yet).
    case agentRequest(AgentRequestSignal)
    /// A timed event starting within `NotchActivityLogic.imminentWindow`, or that has just started.
    case imminentEvent(EarEvent)
    /// Music or Spotify is playing (paused doesn't count: the ear goes back to what it showed before).
    case playback(PlaybackSignal)
    /// The main AI provider's session (phase 3 feeds it; nothing real exists yet).
    case usage(UsageSignal)
    case rest

    /// The section tapping the indicator opens.
    var module: NotchModule? {
        switch self {
        case .agentRequest: .agents
        case .imminentEvent: .calendar
        case .playback: .nowPlaying
        case .usage: .usage
        case .rest: nil
        }
    }
}

/// An agent waiting on the user, free of whatever source reports it.
struct AgentRequestSignal: Equatable, Sendable {
    var agentName: String
    var project: String?
}

/// What's playing, as far as the indicator needs it.
struct PlaybackSignal: Equatable, Sendable {
    var title: String
    var artist: String
    var appName: String
}

/// The session used so far, 0…1.
struct UsageSignal: Equatable, Sendable {
    var providerName: String
    var fraction: Double
}

/// Everything the contextual ear could talk about, each `nil` when its source has nothing real to say.
struct NotchActivityInputs: Equatable, Sendable {
    var agentRequest: AgentRequestSignal?
    var nextEvent: EarEvent?
    var playback: PlaybackSignal?
    var usage: UsageSignal?
}

// MARK: - Logic (pure, testable)

enum NotchActivityLogic {
    /// An event this close (or one that started under `EarsLogic.nowGrace` ago) outranks the music.
    static let imminentWindow: TimeInterval = 15 * 60

    /// The single activity the contextual ear shows, in priority order, among the sections that are on.
    static func resolve(_ inputs: NotchActivityInputs, enabled modules: Set<NotchModule>, now: Date) -> NotchActivity {
        if modules.contains(.agents), let request = inputs.agentRequest {
            return .agentRequest(request)
        }
        if modules.contains(.calendar), let event = inputs.nextEvent, isImminent(event, now: now) {
            return .imminentEvent(event)
        }
        if modules.contains(.nowPlaying), let playback = inputs.playback {
            return .playback(playback)
        }
        if modules.contains(.usage), let usage = inputs.usage {
            return .usage(usage)
        }
        return .rest
    }

    static func isImminent(_ event: EarEvent, now: Date) -> Bool {
        guard !event.isAllDay, event.end > now else { return false }
        let remaining = event.start.timeIntervalSince(now)
        return remaining <= imminentWindow && remaining > -EarsLogic.nowGrace
    }

    /// Whether a click (screen coordinates) lands on the left ear of a shape centred on the notch: left of the
    /// camera's clear band, inside the shape.
    static func isOnLeftEar(_ point: CGPoint, shape: CGRect, clearWidth: CGFloat) -> Bool {
        shape.contains(point) && point.x < shape.midX - clearWidth / 2
    }

    /// What VoiceOver reads for the indicator.
    static func accessibilityLabel(for activity: NotchActivity, now: Date) -> String {
        switch activity {
        case let .agentRequest(request):
            if let project = request.project, !project.isEmpty {
                return String(localized: "\(request.agentName) is waiting for you in \(project)")
            }
            return String(localized: "\(request.agentName) is waiting for you")
        case let .imminentEvent(event):
            let name = event.title.isEmpty ? String(localized: "Next event") : event.title
            switch EarsLogic.label(for: event, now: now) {
            case .now: return String(localized: "\(name) is starting now")
            case let .countdown(minutes): return String(localized: "\(name) in \(minutes) minutes")
            case let .at(date): return String(localized: "\(name) at \(date.formatted(date: .omitted, time: .shortened))")
            }
        case let .playback(playback):
            let title = playback.title.isEmpty ? playback.appName : playback.title
            if playback.artist.isEmpty { return String(localized: "Now playing: \(title)") }
            return String(localized: "Now playing: \(title) by \(playback.artist)")
        case let .usage(usage):
            return String(localized: "\(usage.providerName): \(NotchFormat.percent(usage.fraction)) of the session")
        case .rest:
            return String(localized: "Nothing going on")
        }
    }

    /// What the indicator does when activated, for VoiceOver's hint.
    static func accessibilityHint(for activity: NotchActivity) -> String? {
        guard let module = activity.module else { return nil }
        return String(localized: "Opens \(module.title)")
    }
}
