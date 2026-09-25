import AVFoundation
import EventKit
import Foundation
import Testing
@testable import Altillo

/// Phase 15: the welcome. Which pages a setup gets, which permissions it asks for (never one it doesn't need), when
/// it opens by itself, and what it writes.
@MainActor
struct OnboardingTests {
    private static func makeDefaults(_ name: String = #function) -> UserDefaults {
        TestDefaultsJanitor.purgeStale()
        let suite = "me.badia.altillo.tests.onboarding.\(name.replacingOccurrences(of: "()", with: ""))-\(UUID().uuidString)"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    private static func context(_ preset: NotchPreset, drawer: Bool = false,
                                detection: OnboardingDetection = .pending) -> OnboardingContext {
        OnboardingContext(modules: Set(preset.modules), leftEar: preset.leftEar, rightEar: preset.rightEar,
                          drawerEnabled: drawer, detection: detection)
    }

    // MARK: Pages

    @Test func minimalSkipsAIToolsAndPermissions() {
        #expect(OnboardingLogic.steps(for: Self.context(.minimal)) == [.hello, .preset, .tricks, .done])
    }

    @Test func developerGetsAIToolsButNoPermissions() {
        let steps = OnboardingLogic.steps(for: Self.context(.developer))
        #expect(steps == [.hello, .preset, .aiTools, .tricks, .done])
        #expect(OnboardingLogic.permissions(for: Self.context(.developer)).isEmpty)
    }

    @Test func everythingGetsEveryPage() {
        #expect(OnboardingLogic.steps(for: Self.context(.everything)) == OnboardingStep.allCases)
    }

    @Test func aiToolsLeaveOnceTheSearchComesBackEmpty() {
        let empty = OnboardingDetection(hasChecked: true, providersFound: 0, agentsFound: 0)
        #expect(!OnboardingLogic.steps(for: Self.context(.developer, detection: empty)).contains(.aiTools))
        let stillLooking = OnboardingDetection(hasChecked: false, providersFound: 0, agentsFound: 0)
        #expect(OnboardingLogic.steps(for: Self.context(.developer, detection: stillLooking)).contains(.aiTools))
        let oneAgent = OnboardingDetection(hasChecked: true, providersFound: 0, agentsFound: 1)
        #expect(OnboardingLogic.steps(for: Self.context(.developer, detection: oneAgent)).contains(.aiTools))
        let oneProvider = OnboardingDetection(hasChecked: true, providersFound: 2, agentsFound: 0)
        #expect(OnboardingLogic.steps(for: Self.context(.developer, detection: oneProvider)).contains(.aiTools))
    }

    @Test func eitherUsageOrAgentsIsEnoughForAITools() {
        #expect(OnboardingLogic.steps(for: OnboardingContext(modules: [.shelf, .usage])).contains(.aiTools))
        #expect(OnboardingLogic.steps(for: OnboardingContext(modules: [.shelf, .agents])).contains(.aiTools))
        #expect(!OnboardingLogic.steps(for: OnboardingContext(modules: [.shelf, .calendar])).contains(.aiTools))
    }

    // MARK: Permissions

    @Test func permissionsFollowTheSectionsThatAreOn() {
        #expect(OnboardingLogic.permissions(for: Self.context(.everything)) == [.calendar, .automation, .camera])
        #expect(OnboardingLogic.permissions(for: OnboardingContext(modules: [.shelf, .mirror])) == [.camera])
        #expect(OnboardingLogic.permissions(for: OnboardingContext(modules: [.shelf, .nowPlaying])) == [.automation])
        #expect(OnboardingLogic.permissions(for: OnboardingContext(modules: [.shelf, .assistant, .usage])).isEmpty)
    }

    @Test func theNextEventEarAloneNeedsTheCalendar() {
        let context = OnboardingContext(modules: [.shelf], leftEar: .nextEvent, rightEar: .shelf)
        #expect(OnboardingLogic.permissions(for: context) == [.calendar])
        #expect(OnboardingLogic.steps(for: context).contains(.permissions))
    }

    @Test func accessibilityOnlyWithTheDrawerOn() {
        #expect(!OnboardingLogic.permissions(for: Self.context(.everything)).contains(.accessibility))
        let withDrawer = Self.context(.minimal, drawer: true)
        #expect(OnboardingLogic.permissions(for: withDrawer) == [.accessibility])
        #expect(OnboardingLogic.steps(for: withDrawer) == [.hello, .preset, .permissions, .tricks, .done])
    }

    @Test func systemAnswersReadAsRowStates() {
        #expect(OnboardingFlow.calendarStatus(.fullAccess) == .granted)
        #expect(OnboardingFlow.calendarStatus(.notDetermined) == .notAsked)
        #expect(OnboardingFlow.calendarStatus(.denied) == .denied)
        #expect(OnboardingFlow.calendarStatus(.writeOnly) == .denied, "the notch needs to read events")
        #expect(OnboardingFlow.cameraStatus(.authorized, hasCamera: false) == .granted)
        #expect(OnboardingFlow.cameraStatus(.notDetermined, hasCamera: true) == .notAsked)
        #expect(OnboardingFlow.cameraStatus(.notDetermined, hasCamera: false) == .notNow,
                "no camera: nothing to ask, it would only be refused")
        #expect(OnboardingFlow.cameraStatus(.denied, hasCamera: true) == .denied)
    }

    @Test func musicAndSpotifyShareOneRow() {
        #expect(OnboardingFlow.automationStatus([]) == .notNow, "neither is open: it asks when you first play")
        #expect(OnboardingFlow.automationStatus([.undetermined]) == .notAsked)
        #expect(OnboardingFlow.automationStatus([.denied, .granted]) == .granted)
        #expect(OnboardingFlow.automationStatus([.undetermined, .denied]) == .denied)
        #expect(OnboardingFlow.automationStatus([.unavailable]) == .notAsked)
    }

    // MARK: Navigation

    @Test func continueAndBackWalkOnlyThePagesThatApply() {
        let steps: [OnboardingStep] = [.hello, .preset, .tricks, .done]
        #expect(OnboardingLogic.step(after: .preset, in: steps) == .tricks)
        #expect(OnboardingLogic.step(before: .tricks, in: steps) == .preset)
        #expect(OnboardingLogic.step(after: .done, in: steps) == nil)
        #expect(OnboardingLogic.step(before: .hello, in: steps) == nil)
        // A page that stopped applying while on screen still knows its neighbours.
        #expect(OnboardingLogic.step(after: .aiTools, in: steps) == .tricks)
        #expect(OnboardingLogic.step(before: .aiTools, in: steps) == .preset)
        #expect(OnboardingText.position(of: .aiTools, in: steps) == "Step 2 of 4")
    }

    @Test func theFlowAppliesAPresetAndWalksItsPages() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        let model = NotchModel(settings: settings)
        let flow = OnboardingFlow(model: model, drawerEnabled: { false })
        settings.apply(.minimal)
        #expect(flow.steps.first == .hello)
        flow.next()
        #expect(flow.step == .preset)
        flow.next()
        #expect(flow.step == .tricks, "Minimal has no AI tools and needs no permission")
        flow.back()
        #expect(flow.step == .preset)
        #expect(flow.direction == -1)
    }

    // MARK: What it writes

    @Test func skippingCountsAsDone() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        #expect(!settings.hasCompletedOnboarding)
        let flow = OnboardingFlow(model: NotchModel(settings: settings), drawerEnabled: { false })
        var closed = false
        flow.close = { closed = true }
        flow.finish()
        #expect(closed)
        #expect(settings.hasCompletedOnboarding)
    }

    @Test func closingTheWindowCountsAsDone() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        let flow = OnboardingFlow(model: NotchModel(settings: settings), drawerEnabled: { false })
        flow.windowClosed()
        #expect(settings.hasCompletedOnboarding)
    }

    @Test func completionSurvivesARelaunch() {
        let defaults = Self.makeDefaults()
        let settings = AltilloSettings(defaults: defaults)
        settings.hasCompletedOnboarding = true
        #expect(AltilloSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @Test func openAtLoginIsOnlyWrittenWhenLeavingTheTricks() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.apply(.minimal)
        let flow = OnboardingFlow(model: NotchModel(settings: settings), step: .preset, drawerEnabled: { false })
        #expect(flow.launchAtLogin, "on by default the first time")
        #expect(!settings.launchAtLogin)
        flow.next()
        #expect(flow.step == .tricks)
        #expect(!settings.launchAtLogin, "nothing written while the page is on screen")
        flow.next()
        #expect(settings.launchAtLogin)
    }

    @Test func skippingBeforeTheTricksNeverTurnsOnOpenAtLogin() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        let flow = OnboardingFlow(model: NotchModel(settings: settings), drawerEnabled: { false })
        flow.close = {}
        flow.finish()
        #expect(!settings.launchAtLogin)
    }

    @Test func turningItOffOnTheTricksIsRespected() {
        let settings = AltilloSettings(defaults: Self.makeDefaults())
        settings.launchAtLogin = true
        let flow = OnboardingFlow(model: NotchModel(settings: settings), step: .tricks, drawerEnabled: { false })
        flow.launchAtLogin = false
        flow.close = {}
        flow.finish()
        #expect(!settings.launchAtLogin)
    }

    @Test func openAtLoginStartsOnForAFirstRunOnlyOtherwiseAsLeft() {
        #expect(OnboardingLogic.initialLaunchAtLogin(current: false, hasCompletedOnboarding: false))
        #expect(!OnboardingLogic.initialLaunchAtLogin(current: false, hasCompletedOnboarding: true))
        #expect(OnboardingLogic.initialLaunchAtLogin(current: true, hasCompletedOnboarding: true))
    }

    // MARK: Launch

    @Test func showsOnceForEveryoneButNeverInTheTestHost() {
        let normal = OnboardingLaunch(forceShow: false, requestedStep: nil, isReviewing: false, isTestHost: false)
        #expect(normal.shouldShow(hasCompletedOnboarding: false))
        #expect(!normal.shouldShow(hasCompletedOnboarding: true))
        var testHost = normal
        testHost.isTestHost = true
        testHost.forceShow = true
        #expect(!testHost.shouldShow(hasCompletedOnboarding: false))
    }

    @Test func reviewsAndForcedShowing() {
        let reviewing = OnboardingLaunch(forceShow: false, requestedStep: nil, isReviewing: true, isTestHost: false)
        #expect(!reviewing.shouldShow(hasCompletedOnboarding: false), "a design scenario or -openSettings is on")
        let forced = OnboardingLaunch(forceShow: true, requestedStep: 4, isReviewing: false, isTestHost: false)
        #expect(forced.shouldShow(hasCompletedOnboarding: true))
        #expect(forced.step == .permissions)
        #expect(OnboardingLaunch(forceShow: true, requestedStep: 9, isReviewing: false, isTestHost: false).step == nil)
    }

    @Test func launchArgumentsAreRead() {
        let defaults = Self.makeDefaults()
        defaults.set(true, forKey: "showWelcome")
        defaults.set(3, forKey: "welcomeStep")
        let arguments: [String: Any] = ["showWelcome": "YES", "welcomeStep": "3", "AppleLanguages": "(es)"]
        let launch = OnboardingLaunch.current(defaults: defaults, arguments: arguments, environment: [:])
        #expect(launch.forceShow)
        #expect(launch.step == .aiTools)
        #expect(!launch.isTestHost)
        #expect(!launch.isReviewing, "the welcome's own flags and the language aren't a review")
        #expect(OnboardingLaunch.isTestHost(["XCTestConfigurationFilePath": "/tmp/x"]))
        #expect(!OnboardingLaunch.isTestHost(["HOME": "/Users/x"]))
    }

    @Test func anyReviewArgumentKeepsTheWelcomeAway() {
        #expect(OnboardingLaunch.isReview(arguments: ["designScenario"]))
        #expect(OnboardingLaunch.isReview(arguments: ["openSettings", "settingsTab"]))
        #expect(OnboardingLaunch.isReview(arguments: ["modules", "AppleLanguages"]))
        #expect(!OnboardingLaunch.isReview(arguments: []))
        #expect(!OnboardingLaunch.isReview(arguments: ["NSDocumentRevisionsDebugMode"]), "Xcode's Run adds it")
    }

    @Test func thisProcessIsTheTestHost() {
        // The real launch check must see the test host, or running the tests would open the welcome.
        #expect(OnboardingLaunch.current().isTestHost)
    }
}
