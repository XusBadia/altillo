import Foundation
import Observation
import ServiceManagement

/// User settings, stored in `UserDefaults` and shared by the notch and the Settings window.
@MainActor
@Observable
final class AltilloSettings {
    static let shared = AltilloSettings(loginItem: .system)

    /// Width of the open notch. Narrow by default: it should take as little room as possible.
    var openWidth: Double {
        didSet {
            let clamped = openWidth.clamped(to: Self.widthRange)
            guard clamped == openWidth else { openWidth = clamped; return }
            defaults.set(clamped, forKey: Key.openWidth)
        }
    }

    /// Modules shown in the notch, in order. The shelf is always first (`NotchModule.isAlwaysOn`).
    var modules: [NotchModule] {
        didSet { defaults.set(modules.map(\.rawValue), forKey: Key.modules) }
    }

    /// Open the notch on a sustained hover instead of requiring a click.
    var opensOnHover: Bool {
        didSet { defaults.set(opensOnHover, forKey: Key.opensOnHover) }
    }

    /// Start Altillo when the user logs in. Mirrors the real `SMAppService` status.
    var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
            guard !isSyncingLoginItem else { return }
            do {
                try loginItem.setRegistered(launchAtLogin)
                launchAtLoginProblem = nil
            } catch {
                launchAtLoginProblem = launchAtLogin
                    ? String(localized: "Couldn't turn this on. Try moving Altillo to the Applications folder.")
                    : String(localized: "Couldn't turn this off. Remove it in System Settings › General › Login Items.")
                revertLaunchAtLogin(to: oldValue)
            }
        }
    }

    /// Set when registering or unregistering the login item failed; shown next to the toggle.
    private(set) var launchAtLoginProblem: String?

    /// Show the "drop something up here" hint while the shelf is empty.
    var showHintOnEmptyShelf: Bool {
        didSet { defaults.set(showHintOnEmptyShelf, forKey: Key.showHintOnEmptyShelf) }
    }

    /// How long items stay in the shelf before Altillo clears them.
    var shelfExpiry: ShelfExpiry {
        didSet { defaults.set(shelfExpiry.rawValue, forKey: Key.shelfExpiry) }
    }

    /// A light tap on Force Touch trackpads when something snaps into place.
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Global shortcut that opens the notch on the assistant, ready to type.
    var assistantHotKey: AssistantHotKey {
        didSet { defaults.set(assistantHotKey.rawValue, forKey: Key.assistantHotKey) }
    }

    /// Which screen (or screens) the notch lives on.
    var displayMode: DisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Key.displayMode) }
    }

    /// What the notch does while an app is full screen on its screen.
    var fullScreenBehaviour: FullScreenBehaviour {
        didSet { defaults.set(fullScreenBehaviour.rawValue, forKey: Key.fullScreenBehaviour) }
    }

    /// What sits in the left and right ears beside the resting notch.
    var leftEar: EarContent {
        didSet { defaults.set(leftEar.rawValue, forKey: Key.leftEar) }
    }

    var rightEar: EarContent {
        didSet { defaults.set(rightEar.rawValue, forKey: Key.rightEar) }
    }

    /// Ears only while they have something to say (a thing on the shelf, a song playing), or always.
    var earsVisibility: EarsVisibility {
        didSet { defaults.set(earsVisibility.rawValue, forKey: Key.earsVisibility) }
    }

    /// Set when macOS refused the shortcut (another app already uses it); shown next to the picker.
    var assistantHotKeyProblem: String?

    /// Peek five minutes before an event starts (only with the calendar section on and access granted).
    var alertsForCalendar: Bool {
        didSet { defaults.set(alertsForCalendar, forKey: Key.alertsForCalendar) }
    }

    /// Peek when a new song starts in Music or Spotify. Off by default: the notch stays invisible until it matters.
    var alertsForNowPlaying: Bool {
        didSet { defaults.set(alertsForNowPlaying, forKey: Key.alertsForNowPlaying) }
    }

    static let widthRange: ClosedRange<Double> = 440...760
    static let widthPresets: [(name: String, value: Double)] = [
        (String(localized: "Narrow"), 480),
        (String(localized: "Medium"), 560),
        (String(localized: "Wide"), 680),
    ]
    /// Everything on by default: sections are easier to discover in the notch than in Settings.
    static let defaultModules: [NotchModule] = NotchModule.allCases

    private let defaults: UserDefaults
    private let loginItem: LoginItem
    /// Guards `launchAtLogin` writes that only mirror the system, so they never register anything back.
    private var isSyncingLoginItem = false

    private enum Key {
        static let openWidth = "openWidth"
        static let modules = "modules"
        static let opensOnHover = "opensOnHover"
        static let launchAtLogin = "launchAtLogin"
        static let showHintOnEmptyShelf = "showHintOnEmptyShelf"
        static let shelfExpiry = "shelfExpiry"
        static let knownModules = "knownModules"
        static let hapticsEnabled = "hapticsEnabled"
        static let assistantHotKey = "assistantHotKey"
        static let alertsForCalendar = "alertsForCalendar"
        static let alertsForNowPlaying = "alertsForNowPlaying"
        static let displayMode = "displayMode"
        static let fullScreenBehaviour = "fullScreenBehaviour"
        static let leftEar = "leftEar"
        static let rightEar = "rightEar"
        static let earsVisibility = "earsVisibility"
    }

    /// Modules every version before the assistant knew about. A stored list without `knownModules` comes from
    /// one of those versions, so anything newer is a module the user has never seen, not one they put away.
    static let legacyModules: [NotchModule] = [.shelf, .usage, .agents, .calendar, .mirror, .nowPlaying]

    init(defaults: UserDefaults = .standard, loginItem: LoginItem = .unmanaged) {
        self.defaults = defaults
        self.loginItem = loginItem
        let width = defaults.double(forKey: Key.openWidth)
        openWidth = width > 0 ? width.clamped(to: Self.widthRange) : 560
        let stored = (defaults.array(forKey: Key.modules) as? [String])?.compactMap(NotchModule.init)
        var modules = Self.normalise(stored ?? Self.defaultModules)
        // Sections added by an update arrive switched on (they're easier to discover in the notch than in
        // Settings), placed where they belong in the default order. Ones the user already knew keep their choice.
        let known = (defaults.array(forKey: Key.knownModules) as? [String])?.compactMap(NotchModule.init)
            ?? (stored == nil ? NotchModule.allCases : Self.legacyModules)
        let arrivals = NotchModule.allCases.filter { !known.contains($0) && !modules.contains($0) }
        for module in arrivals {
            let defaultIndex = NotchModule.allCases.firstIndex(of: module) ?? modules.endIndex
            modules.insert(module, at: min(defaultIndex, modules.endIndex))
        }
        let resolved = Self.normalise(modules)
        self.modules = resolved
        if !arrivals.isEmpty { defaults.set(resolved.map(\.rawValue), forKey: Key.modules) }
        defaults.set(NotchModule.allCases.map(\.rawValue), forKey: Key.knownModules)
        opensOnHover = defaults.object(forKey: Key.opensOnHover) as? Bool ?? true
        let rememberedLogin = defaults.object(forKey: Key.launchAtLogin) as? Bool ?? false
        // The system is the source of truth: the user may have changed it in System Settings.
        launchAtLogin = loginItem.isManaged ? loginItem.isRegistered() : rememberedLogin
        showHintOnEmptyShelf = defaults.object(forKey: Key.showHintOnEmptyShelf) as? Bool ?? true
        shelfExpiry = (defaults.string(forKey: Key.shelfExpiry).flatMap(ShelfExpiry.init)) ?? .never
        hapticsEnabled = defaults.object(forKey: Key.hapticsEnabled) as? Bool ?? true
        assistantHotKey = defaults.string(forKey: Key.assistantHotKey).flatMap(AssistantHotKey.init) ?? .controlOptionA
        alertsForCalendar = defaults.object(forKey: Key.alertsForCalendar) as? Bool ?? true
        alertsForNowPlaying = defaults.object(forKey: Key.alertsForNowPlaying) as? Bool ?? false
        displayMode = defaults.string(forKey: Key.displayMode).flatMap(DisplayMode.init) ?? .notch
        fullScreenBehaviour = defaults.string(forKey: Key.fullScreenBehaviour).flatMap(FullScreenBehaviour.init)
            ?? .dragOnly
        leftEar = defaults.string(forKey: Key.leftEar).flatMap(EarContent.init) ?? .none
        rightEar = defaults.string(forKey: Key.rightEar).flatMap(EarContent.init) ?? .shelf
        earsVisibility = defaults.string(forKey: Key.earsVisibility).flatMap(EarsVisibility.init) ?? .withActivity
    }

    /// Applies a starting point (PLAN §4): which sections, in which order, and what the ears show. Everything
    /// else (width, behaviour, alerts) is left as the user had it.
    func apply(_ preset: NotchPreset) {
        modules = Self.normalise(preset.modules)
        leftEar = preset.leftEar
        rightEar = preset.rightEar
    }

    /// The preset the current sections and ears match exactly, if any.
    var matchingPreset: NotchPreset? {
        NotchPreset.allCases.first { preset in
            Self.normalise(preset.modules) == modules && preset.leftEar == leftEar && preset.rightEar == rightEar
        }
    }

    func isEnabled(_ module: NotchModule) -> Bool { modules.contains(module) }

    func setEnabled(_ module: NotchModule, _ enabled: Bool) {
        guard !module.isAlwaysOn else { return }
        if enabled {
            guard !modules.contains(module) else { return }
            modules.append(module)
        } else {
            modules.removeAll { $0 == module }
        }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var updated = modules
        updated.move(fromOffsets: source, toOffset: destination)
        modules = Self.normalise(updated)
    }

    /// Re-reads the login item status (it can change in System Settings while Altillo runs).
    func refreshLaunchAtLogin() {
        guard loginItem.isManaged else { return }
        let registered = loginItem.isRegistered()
        guard registered != launchAtLogin else { return }
        isSyncingLoginItem = true
        launchAtLogin = registered
        isSyncingLoginItem = false
    }

    private func revertLaunchAtLogin(to value: Bool) {
        isSyncingLoginItem = true
        launchAtLogin = value
        isSyncingLoginItem = false
    }

    /// Always-on modules first, no duplicates, nothing unknown.
    private static func normalise(_ modules: [NotchModule]) -> [NotchModule] {
        var seen = Set<NotchModule>()
        let unique = modules.filter { seen.insert($0).inserted }
        let alwaysOn = NotchModule.allCases.filter(\.isAlwaysOn)
        return alwaysOn + unique.filter { !$0.isAlwaysOn }
    }
}

// MARK: - Shelf expiry

/// How long the shelf keeps what you leave up there. Used by the shelf module.
enum ShelfExpiry: String, CaseIterable, Identifiable, Codable, Sendable {
    case never, day, week

    var id: Self { self }

    /// Label in Settings.
    var title: String {
        switch self {
        case .never: String(localized: "Never")
        case .day: String(localized: "After a day")
        case .week: String(localized: "After a week")
        }
    }

    /// How long an item survives, or `nil` if it stays forever.
    var duration: TimeInterval? {
        switch self {
        case .never: nil
        case .day: 24 * 60 * 60
        case .week: 7 * 24 * 60 * 60
        }
    }
}

// MARK: - Screens

/// Where the notch appears (PLAN §4, "Pantallas").
enum DisplayMode: String, CaseIterable, Identifiable, Codable, Sendable {
    /// The screen with a hardware notch; without one, the screen with the menu bar.
    case notch
    /// Always the screen with the menu bar.
    case main
    /// Every screen, each with its own island (or notch).
    case all
    /// Whichever screen the pointer is on.
    case cursor

    var id: Self { self }

    var title: String {
        switch self {
        case .notch: String(localized: "The one with the notch")
        case .main: String(localized: "The one with the menu bar")
        case .all: String(localized: "All of them")
        case .cursor: String(localized: "The one with the pointer")
        }
    }
}

/// What the notch does over a full-screen app.
enum FullScreenBehaviour: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Behaves as usual.
    case show
    /// Stays out of the way, but still takes files you drag up to it.
    case dragOnly
    /// Out of the way entirely.
    case hide

    var id: Self { self }

    var title: String {
        switch self {
        case .show: String(localized: "Stay as usual")
        case .dragOnly: String(localized: "Only when you drag something")
        case .hide: String(localized: "Hide")
        }
    }
}

// MARK: - Ears

/// What an ear beside the resting notch shows.
enum EarContent: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    /// How many things wait on the shelf.
    case shelf
    /// The next event and how long until it starts.
    case nextEvent
    /// A small equaliser while music plays.
    case nowPlaying
    /// The main AI provider's session ring (phase 3).
    case usage
    /// Agents working or knocking (phase 4).
    case agents

    var id: Self { self }

    var title: String {
        switch self {
        case .none: String(localized: "Nothing")
        case .shelf: String(localized: "Things on the shelf")
        case .nextEvent: String(localized: "Next event")
        case .nowPlaying: String(localized: "Music playing")
        case .usage: String(localized: "AI usage")
        case .agents: String(localized: "Agents")
        }
    }

    var symbol: String {
        switch self {
        case .none: "circle.dashed"
        case .shelf: "house"
        case .nextEvent: "calendar"
        case .nowPlaying: "waveform"
        case .usage: "gauge.with.needle"
        case .agents: "hand.raised"
        }
    }

    /// Usage and agents only have sample data until phases 3 and 4: offered, but marked as coming.
    var isAvailable: Bool { self != .usage && self != .agents }
}

enum EarsVisibility: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Only while an ear has something to say.
    case withActivity
    /// Always, even with nothing to report (empty ears stay dark).
    case always

    var id: Self { self }

    var title: String {
        switch self {
        case .withActivity: String(localized: "Only when there's something")
        case .always: String(localized: "Always")
        }
    }
}

// MARK: - Presets

/// Starting points for the notch (PLAN §4): the user picks one and then adjusts.
enum NotchPreset: String, CaseIterable, Identifiable, Sendable {
    /// Just the shelf.
    case minimal
    /// Shelf, Ask, AI usage and agents.
    case developer
    /// Every section.
    case everything

    var id: Self { self }

    var title: String {
        switch self {
        case .minimal: String(localized: "Minimal")
        case .developer: String(localized: "Developer")
        case .everything: String(localized: "Everything")
        }
    }

    var explanation: String {
        switch self {
        case .minimal: String(localized: "Just the shelf. The notch stays out of sight.")
        case .developer: String(localized: "Shelf, Ask, AI usage and your agents.")
        case .everything: String(localized: "Every section, with the next event beside the notch.")
        }
    }

    var modules: [NotchModule] {
        switch self {
        case .minimal: [.shelf]
        case .developer: [.shelf, .assistant, .usage, .agents]
        case .everything: NotchModule.allCases
        }
    }

    var leftEar: EarContent {
        switch self {
        case .minimal: .none
        case .developer: .usage
        case .everything: .nextEvent
        }
    }

    var rightEar: EarContent {
        switch self {
        case .minimal, .everything: .shelf
        case .developer: .agents
        }
    }
}

// MARK: - Assistant shortcut

/// The global shortcut that summons the assistant. A short list of combinations that don't clash with macOS's own
/// (⌘Space is Spotlight, ⌃Space switches input source, ⌥⌘Space opens a Finder search).
enum AssistantHotKey: String, CaseIterable, Identifiable, Codable, Sendable {
    case off, controlOptionA, optionSpace, controlOptionSpace

    var id: Self { self }

    /// Label in Settings, with the symbols a Mac user reads.
    var title: String {
        switch self {
        case .off: String(localized: "None")
        case .controlOptionA: "⌃⌥A"
        case .optionSpace: "⌥Space"
        case .controlOptionSpace: "⌃⌥Space"
        }
    }
}

// MARK: - Login item

/// The "open at login" registration, injected so tests never touch the real `SMAppService`.
struct LoginItem: Sendable {
    /// False for the test/preview double: then the stored preference is the source of truth.
    var isManaged: Bool
    var isRegistered: @Sendable () -> Bool
    var setRegistered: @Sendable (Bool) throws -> Void

    /// The real login item of Altillo.app.
    @MainActor static let system = LoginItem(
        isManaged: true,
        isRegistered: { SMAppService.mainApp.status == .enabled },
        setRegistered: { enabled in
            if enabled {
                guard SMAppService.mainApp.status != .enabled else { return }
                try SMAppService.mainApp.register()
            } else {
                guard SMAppService.mainApp.status == .enabled else { return }
                try SMAppService.mainApp.unregister()
            }
        }
    )

    /// Remembers the preference without touching the system. Default for injected instances.
    static let unmanaged = LoginItem(isManaged: false, isRegistered: { false }, setRegistered: { _ in })
}

extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double { min(max(self, range.lowerBound), range.upperBound) }
}
