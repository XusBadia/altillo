import Foundation

// The welcome's rules (PLAN phase 15), kept pure so tests can walk every path: which steps apply to a setup, which
// permissions it needs, when the window shows itself at launch. The views and `OnboardingFlow` only read from here.

/// The welcome's pages, in order. Some only apply to some setups (`OnboardingLogic.steps(for:)`).
enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    /// What Altillo is, and the notch opening for the first time.
    case hello
    /// Minimal, Developer or Everything.
    case preset
    /// AI providers and coding agents found on this Mac, and the offer to install the hooks.
    case aiTools
    /// The system permissions the chosen sections need, one at a time.
    case permissions
    /// Shortcuts and gestures, and "Open at login".
    case tricks
    /// "Try it: drag a file up".
    case done

    var id: Self { self }

    /// Short name for the progress row and VoiceOver.
    var title: String {
        switch self {
        case .hello: String(localized: "Hello")
        case .preset: String(localized: "Starting point")
        case .aiTools: String(localized: "AI tools")
        case .permissions: String(localized: "Permissions")
        case .tricks: String(localized: "Tricks")
        case .done: String(localized: "Ready")
        }
    }
}

/// A permission the welcome may explain and ask for.
enum OnboardingPermission: String, CaseIterable, Identifiable, Sendable {
    /// EventKit, for the calendar section, the next-event ear and the meeting peek.
    case calendar
    /// Apple Events to Music and Spotify, for Now playing.
    case automation
    /// The camera, for the mirror.
    case camera
    /// Accessibility, for the Drawer (menu bar icons).
    case accessibility

    var id: Self { self }
}

/// Where a permission stands, as the welcome shows it.
enum OnboardingPermissionStatus: Equatable, Sendable {
    /// Never asked: the row offers "Allow".
    case notAsked
    case granted
    /// Refused (or restricted): the row leads to System Settings.
    case denied
    /// Nothing to ask right now (no camera connected, neither Music nor Spotify open): the row explains when it'll ask.
    case notNow
}

/// What the welcome needs to know about the setup to decide its pages.
struct OnboardingContext: Equatable, Sendable {
    var modules: Set<NotchModule>
    var leftEar: EarContent
    var rightEar: EarContent
    /// The Drawer (menu bar icons) is switched on: it needs Accessibility.
    var drawerEnabled: Bool
    /// What was found on this Mac, if the search is over.
    var detection: OnboardingDetection

    @MainActor
    init(settings: AltilloSettings, drawerEnabled: Bool, detection: OnboardingDetection) {
        modules = Set(settings.modules)
        leftEar = settings.leftEar
        rightEar = settings.rightEar
        self.drawerEnabled = drawerEnabled
        self.detection = detection
    }

    init(modules: Set<NotchModule>, leftEar: EarContent = .none, rightEar: EarContent = .shelf,
         drawerEnabled: Bool = false, detection: OnboardingDetection = .pending) {
        self.modules = modules
        self.leftEar = leftEar
        self.rightEar = rightEar
        self.drawerEnabled = drawerEnabled
        self.detection = detection
    }
}

/// The AI tools found on this Mac.
struct OnboardingDetection: Equatable, Sendable {
    /// False until both the usage providers and the agents have been looked for.
    var hasChecked: Bool
    /// Providers set up on this Mac (their tool signed in, their key added).
    var providersFound: Int
    /// Coding agents set up on this Mac (Claude Code, Codex).
    var agentsFound: Int

    static let pending = OnboardingDetection(hasChecked: false, providersFound: 0, agentsFound: 0)

    var foundNothing: Bool { hasChecked && providersFound == 0 && agentsFound == 0 }
}

enum OnboardingLogic {
    /// The pages for this setup, in order. Hello, the starting point, the tricks and the end are always there; the
    /// AI tools only with Usage or Agents on (and not once the search came back empty); permissions only when a
    /// section that's on needs one.
    static func steps(for context: OnboardingContext) -> [OnboardingStep] {
        OnboardingStep.allCases.filter { applies($0, to: context) }
    }

    static func applies(_ step: OnboardingStep, to context: OnboardingContext) -> Bool {
        switch step {
        case .hello, .preset, .tricks, .done:
            true
        case .aiTools:
            wantsAITools(context.modules) && !context.detection.foundNothing
        case .permissions:
            !permissions(for: context).isEmpty
        }
    }

    /// Usage or Agents is among the sections.
    static func wantsAITools(_ modules: Set<NotchModule>) -> Bool {
        modules.contains(.usage) || modules.contains(.agents)
    }

    /// The permissions the setup needs, in the order they're explained. Never one the setup doesn't use.
    static func permissions(for context: OnboardingContext) -> [OnboardingPermission] {
        var needed: [OnboardingPermission] = []
        let ears = [context.leftEar, context.rightEar]
        if context.modules.contains(.calendar) || ears.contains(.nextEvent) { needed.append(.calendar) }
        if context.modules.contains(.nowPlaying) { needed.append(.automation) }
        if context.modules.contains(.mirror) { needed.append(.camera) }
        if context.drawerEnabled { needed.append(.accessibility) }
        return needed
    }

    /// The page after `step` for this setup (nil after the last). Works even if `step` no longer applies (the search
    /// came back empty while the AI tools were on screen).
    static func step(after step: OnboardingStep, in steps: [OnboardingStep]) -> OnboardingStep? {
        steps.first { $0.rawValue > step.rawValue }
    }

    static func step(before step: OnboardingStep, in steps: [OnboardingStep]) -> OnboardingStep? {
        steps.last { $0.rawValue < step.rawValue }
    }

    /// "Open at login" as the tricks page first shows it: on for a first run (a notch app is meant to be there),
    /// otherwise however the user left it.
    static func initialLaunchAtLogin(current: Bool, hasCompletedOnboarding: Bool) -> Bool {
        current || !hasCompletedOnboarding
    }
}

// MARK: - Launch

/// Whether the welcome opens on its own when Altillo starts, and on which page.
struct OnboardingLaunch: Equatable, Sendable {
    /// `-showWelcome YES`: open it even if it was completed (reviews).
    var forceShow: Bool
    /// `-welcomeStep <n>`: the page to open on, 1-based over every page (reviews).
    var requestedStep: Int?
    /// Launched with review arguments (a design scenario, `-openSettings`, `-openModule`, `-modules`…): a review or
    /// a test is driving the app. People never start Altillo with arguments.
    var isReviewing: Bool
    /// Running as the unit-test host.
    var isTestHost: Bool

    /// Launch arguments that don't make a launch a review: the welcome's own, the language, and what Xcode adds.
    static let ordinaryArguments: Set<String> = [
        "showWelcome", "welcomeStep", "AppleLanguages", "AppleLocale", "NSDocumentRevisionsDebugMode",
        "ApplePersistenceIgnoreState", "NSTreatUnknownArgumentsAsOpen",
    ]

    static func current(defaults: UserDefaults = .standard,
                        arguments: [String: Any] = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain),
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> OnboardingLaunch {
        let step = defaults.integer(forKey: "welcomeStep")
        return OnboardingLaunch(
            forceShow: defaults.bool(forKey: "showWelcome"),
            requestedStep: step > 0 ? step : nil,
            isReviewing: isReview(arguments: Set(arguments.keys)),
            isTestHost: isTestHost(environment)
        )
    }

    static func isReview(arguments: Set<String>) -> Bool {
        !arguments.subtracting(ordinaryArguments).isEmpty
    }

    /// XCTest and Swift Testing both run inside the app when it hosts the unit tests.
    static func isTestHost(_ environment: [String: String]) -> Bool {
        ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
            .contains { environment[$0] != nil }
    }

    /// Never in the test host; always when forced; never while a review drives the app; otherwise once.
    func shouldShow(hasCompletedOnboarding: Bool) -> Bool {
        if isTestHost { return false }
        if forceShow { return true }
        if isReviewing { return false }
        return !hasCompletedOnboarding
    }

    /// The page asked for with `-welcomeStep`, if it exists.
    var step: OnboardingStep? {
        requestedStep.flatMap { OnboardingStep(rawValue: $0 - 1) }
    }
}
