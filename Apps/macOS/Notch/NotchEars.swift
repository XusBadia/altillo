import AppKit
import CoreGraphics
import Foundation

/// What one ear beside the resting notch shows, with the data it needs. One value decides both the view and how wide
/// the ear grows (`EarMetrics`), so the silhouette always fits what it says: nothing to say, no ear.
enum EarItem: Equatable, Sendable {
    /// An agent waiting for the user: the knocking hand and its name.
    case agentRequest(AgentRequestSignal)
    /// The agents ear: who is working and who is knocking ("1 knocking · 2 working").
    case agents(AgentsLogic.Counts)
    /// An event: when ("in 12 min", "13:30", "now") and what.
    case event(EarEvent, EarsLogic.EventLabel)
    /// What's playing: the sleeve, the title and the equaliser.
    case playback(PlaybackSignal)
    /// An AI provider's fullest limit: the ring, the figure and the provider.
    case usage(UsageSignal, isStale: Bool)
    /// A kitchen timer: the countdown and its name.
    case timer(TimerSignal)
    /// How many things wait on the shelf.
    case shelf(count: Int)
    /// A chosen ear with nothing to say while ears always show: its glyph, unlit.
    case quiet(EarContent)

    /// The section a click on this ear opens.
    var module: NotchModule? {
        switch self {
        case .agentRequest, .agents: .agents
        case .event: .calendar
        case .playback: .nowPlaying
        case .usage: .usage
        case .timer: .timer
        case .shelf: .shelf
        case let .quiet(content): content.module
        }
    }

    /// The ear for one of "What matters now"'s activities (`nil` for `.rest`).
    init?(_ activity: NotchActivity, now: Date) {
        switch activity {
        case let .agentRequest(request): self = .agentRequest(request)
        case let .imminentEvent(event): self = .event(event, EarsLogic.label(for: event, now: now))
        case let .playback(playback): self = .playback(playback)
        case let .usage(usage): self = .usage(usage, isStale: false)
        case let .timer(timer): self = .timer(timer)
        case .rest: return nil
        }
    }
}

/// What the two ears show right now. Either can be empty, and then it takes no room at all.
struct EarsArrangement: Equatable, Sendable {
    var left: EarItem?
    var right: EarItem?

    var isEmpty: Bool { left == nil && right == nil }

    func item(on side: EarSide) -> EarItem? { side == .left ? left : right }
}

// MARK: - Logic (pure, testable)

enum EarsArrangementLogic {
    /// Decides what each ear shows.
    ///
    /// - A fixed ear (Shelf, Next event…) shows its own thing while it has something to say; while ears always show,
    ///   a quiet one keeps its glyph; otherwise it's empty.
    /// - "What matters now" takes the most important activity no fixed ear is already showing. Both ears on it show
    ///   the first and the second.
    /// - With "What matters now" on either side, an ear left empty shows the next activity instead of a black gap
    ///   (the event on the left, the music on the right). With nothing left to say it stays empty: no room taken.
    static func arrange(
        left: EarContent,
        right: EarContent,
        visibility: EarsVisibility,
        activities: [NotchActivity],
        now: Date,
        fixedItem: (EarContent) -> EarItem?
    ) -> EarsArrangement {
        let contents = [left, right]
        var items: [EarItem?] = contents.map { content in
            guard content != .none, content != .automatic, content.isAvailable else { return nil }
            if let item = fixedItem(content) { return item }
            return visibility == .always ? .quiet(content) : nil
        }

        // Whatever a fixed ear already says isn't repeated by the contextual one.
        let shownModules = Set(items.compactMap { item -> NotchModule? in
            if case .quiet = item { return nil }
            return item?.module
        })
        var pool = activities
            .compactMap { EarItem($0, now: now) }
            .filter { item in item.module.map { !shownModules.contains($0) } ?? true }

        for index in contents.indices where contents[index] == .automatic {
            if !pool.isEmpty {
                items[index] = pool.removeFirst()
            } else if visibility == .always {
                items[index] = .quiet(.automatic)
            }
        }

        if contents.contains(.automatic) {
            for index in contents.indices where items[index] == nil && contents[index] != .none && !pool.isEmpty {
                items[index] = pool.removeFirst()
            }
        }
        return EarsArrangement(left: items[0], right: items[1])
    }
}

// MARK: - Metrics

/// How wide each ear grows for what it shows. The views (`DesvanEarItemView`) are built from the same numbers: the
/// fixed parts (glyphs, sleeves, rings) at these sizes, titles cut at `titleWidth`, so the shape fits the content.
enum EarMetrics {
    /// Air between an ear's content and the camera on one side, and the shape's edge on the other.
    static let padding: CGFloat = 9
    /// No ear grows past this, so the notch stays a notch and leaves the menu bar alone.
    static let maxWidth: CGFloat = 150
    /// Titles (events, songs, agents) are cut beyond this.
    static let titleWidth: CGFloat = 64
    /// Secondary names (provider, timer name) are cut beyond this.
    static let nameWidth: CGFloat = 52
    static let spacing: CGFloat = 5

    enum Glyph {
        static let calendar: CGFloat = 13
        static let hand: CGFloat = 14
        static let sleeve: CGFloat = 18
        static let equaliser: CGFloat = 15
        static let ring: CGFloat = 14
        static let house: CGFloat = 14
        static let timer: CGFloat = 14
        static let dots: CGFloat = 16
        static let quiet: CGFloat = 16
    }

    enum TextSize {
        static let figure: CGFloat = 12.5
        static let title: CGFloat = 12
        static let name: CGFloat = 11
    }

    /// The ear's width: its content plus air on both sides, 0 for no ear.
    static func width(for item: EarItem?) -> CGFloat {
        guard let item else { return 0 }
        return min(maxWidth, ceil(contentWidth(for: item)) + 2 * padding)
    }

    static func contentWidth(for item: EarItem) -> CGFloat {
        switch item {
        case let .agentRequest(request):
            return Glyph.hand + spacing + title(request.agentName)
        case let .agents(counts):
            return Glyph.dots + spacing + text(agentsText(counts), size: TextSize.title, weight: .medium) + 1
        case let .event(event, label):
            let when = eventText(for: label, hasTitle: !event.title.isEmpty)
            var width = Glyph.calendar + spacing + figure(when)
            if !event.title.isEmpty { width += spacing + title(event.title) }
            return width
        case let .playback(playback):
            let name = playback.title.isEmpty ? playback.appName : playback.title
            return Glyph.sleeve + spacing + (name.isEmpty ? 0 : title(name) + spacing) + Glyph.equaliser
        case let .usage(usage, _):
            var width = Glyph.ring + spacing + figure(percentText(usage.fraction))
            if !usage.providerName.isEmpty { width += spacing + name(usage.providerName) }
            return width
        case let .timer(timer):
            var width = Glyph.timer
            if !timer.isRinging {
                // The countdown's digits change every second; its width only with the number of digits.
                let countdown = TimerFormat.ear(max(0, timer.endsAt.timeIntervalSinceNow))
                width += spacing + figure(String(countdown.map { $0.isNumber ? "0" : $0 }))
            }
            if !timer.label.isEmpty { width += spacing + name(timer.label) }
            return width
        case let .shelf(count):
            return Glyph.house + spacing + figure("\(count)")
        case .quiet:
            return Glyph.quiet
        }
    }

    /// What the event ear says for when: "in 12 min" alone, the shorter "12 min" beside a title.
    static func eventText(for label: EarsLogic.EventLabel, hasTitle: Bool) -> String {
        hasTitle ? EarsLogic.compactText(for: label) : EarsLogic.text(for: label)
    }

    /// The agents ear in words: who's knocking, or else who's working ("2 knocking", "3 working").
    static func agentsText(_ counts: AgentsLogic.Counts) -> String {
        if counts.waiting > 0 { return String(localized: "\(counts.waiting) knocking") }
        if counts.working > 0 { return String(localized: "\(counts.working) working") }
        return "\(counts.active)"
    }

    static func percentText(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))"
    }

    private static func figure(_ string: String) -> CGFloat {
        text(string, size: TextSize.figure, weight: .medium) + 1
    }

    private static func title(_ string: String) -> CGFloat {
        min(text(string, size: TextSize.title, weight: .medium) + 1, titleWidth)
    }

    private static func name(_ string: String) -> CGFloat {
        min(text(string, size: TextSize.name, weight: .regular) + 1, nameWidth)
    }

    /// The width of `string` in SF Pro Rounded with monospaced digits, like `Desvan.Typeface.figure`.
    static func text(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        let base = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        return ceil((string as NSString).size(withAttributes: [.font: font]).width)
    }
}
