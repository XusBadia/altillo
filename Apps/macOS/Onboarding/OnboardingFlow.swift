import AltilloCore
import AppKit
import ApplicationServices
import AVFoundation
import EventKit
import Observation

/// One run of the welcome: the page on screen, the choices not written yet, and what the system says about each
/// permission. Made fresh every time the window opens.
@MainActor
@Observable
final class OnboardingFlow {
    /// The notch's own model: its settings, the usage store, the calendar and mirror stores, the Drawer.
    let model: NotchModel
    var settings: AltilloSettings { model.settings }

    private(set) var step: OnboardingStep
    /// +1 going forward, -1 going back: which way the pages slide.
    private(set) var direction = 1

    /// The hooks installer, as Settings › Sections › Agents uses it (the same review sheet before anything is written).
    let hooks = AgentHooksModel()
    private(set) var hooksChecked = false

    /// "Open Altillo at login" on the tricks page. Written only when the user leaves that page or finishes.
    var launchAtLogin: Bool
    private var sawTricks = false

    private(set) var permissionStatus: [OnboardingPermission: OnboardingPermissionStatus] = [:]
    /// Rows the user put off with "Later".
    private(set) var deferred: Set<OnboardingPermission> = []
    /// Rows whose system prompt has been shown in this run (Accessibility has no "denied": it waits in System
    /// Settings, so the row explains where to go).
    private(set) var requested: Set<OnboardingPermission> = []
    private(set) var inFlight: Set<OnboardingPermission> = []

    /// The notch opened while the hello page was on screen.
    private(set) var sawNotchOpen = false

    /// Closes the window (wired by the window controller).
    @ObservationIgnored var close: () -> Void = {}

    /// Whether the Drawer is on (it needs Accessibility). Injected by tests: the real one reads the user's defaults.
    @ObservationIgnored private let drawerEnabled: () -> Bool

    init(model: NotchModel, step: OnboardingStep = .hello, drawerEnabled: (() -> Bool)? = nil) {
        self.model = model
        self.drawerEnabled = drawerEnabled ?? { [drawer = model.drawer] in drawer.enabled }
        self.step = step
        launchAtLogin = OnboardingLogic.initialLaunchAtLogin(
            current: model.settings.launchAtLogin, hasCompletedOnboarding: model.settings.hasCompletedOnboarding
        )
        if step == .tricks { sawTricks = true }
    }

    // MARK: Pages

    var detection: OnboardingDetection {
        let modules = Set(settings.modules)
        let usageOn = modules.contains(.usage)
        let agentsOn = modules.contains(.agents)
        return OnboardingDetection(
            hasChecked: (!usageOn || model.usage.hasChecked) && (!agentsOn || hooksChecked),
            providersFound: usageOn ? model.usage.setUpEntries.count : 0,
            agentsFound: agentsOn ? agentReports.count : 0
        )
    }

    var context: OnboardingContext {
        OnboardingContext(settings: settings, drawerEnabled: drawerEnabled(), detection: detection)
    }

    var steps: [OnboardingStep] { OnboardingLogic.steps(for: context) }

    var permissions: [OnboardingPermission] { OnboardingLogic.permissions(for: context) }

    var isLast: Bool { OnboardingLogic.step(after: step, in: steps) == nil }
    var isFirst: Bool { OnboardingLogic.step(before: step, in: steps) == nil }

    func next() {
        guard let target = OnboardingLogic.step(after: step, in: steps) else { return finish() }
        go(to: target, direction: 1)
    }

    func back() {
        guard let target = OnboardingLogic.step(before: step, in: steps) else { return }
        go(to: target, direction: -1)
    }

    private func go(to target: OnboardingStep, direction: Int) {
        leave(step)
        self.direction = direction
        step = target
        if target == .tricks { sawTricks = true }
    }

    /// The last page's "Start", Skip, Esc or the close button: whatever the user saw is kept, and the welcome
    /// doesn't come back on its own.
    func finish() {
        leave(step)
        settings.hasCompletedOnboarding = true
        close()
    }

    /// Called by the window when it closes by any route (the close button too).
    func windowClosed() {
        if step == .tricks { writeLaunchAtLogin() }
        settings.hasCompletedOnboarding = true
    }

    private func leave(_ step: OnboardingStep) {
        if step == .tricks, sawTricks { writeLaunchAtLogin() }
    }

    private func writeLaunchAtLogin() {
        guard settings.launchAtLogin != launchAtLogin else { return }
        settings.launchAtLogin = launchAtLogin
    }

    // MARK: Hello

    func notchStateChanged(_ state: NotchState) {
        guard step == .hello, state == .open, !sawNotchOpen else { return }
        sawNotchOpen = true
    }

    // MARK: AI tools

    /// Claude Code and Codex, when they're set up on this Mac.
    var agentReports: [AgentHookReport] {
        hooks.reports.filter { $0.status != .agentNotFound }
    }

    func refreshHooks() {
        hooks.refresh(wait: settings.agentPermissionWait)
        hooksChecked = true
    }

    /// Looks for providers again if the last look is more than a minute old (the usage store ignores it while its
    /// section is off).
    func refreshUsage() {
        model.usage.refreshIfOlder(than: 60)
    }

    // MARK: Permissions

    func status(of permission: OnboardingPermission) -> OnboardingPermissionStatus {
        permissionStatus[permission] ?? .notAsked
    }

    /// Reads every permission the setup needs, silently (no prompt ever comes from here).
    func refreshPermissions() async {
        for permission in permissions {
            permissionStatus[permission] = await Self.currentStatus(of: permission)
        }
    }

    func putOff(_ permission: OnboardingPermission) {
        deferred.insert(permission)
    }

    /// The real system prompt, now, because the user pressed "Allow".
    func request(_ permission: OnboardingPermission) async {
        guard !inFlight.contains(permission) else { return }
        inFlight.insert(permission)
        defer { inFlight.remove(permission) }
        deferred.remove(permission)
        requested.insert(permission)
        switch permission {
        case .calendar:
            await model.calendar.requestAccess()
        case .camera:
            await model.mirror.requestAccess()
        case .automation:
            // Scripting a running player once is what shows the dialog, exactly as the Now playing section does.
            for player in Self.runningPlayers() {
                _ = try? await AppleScriptRunner.run(MusicPlayerScripts.status(for: player))
            }
        case .accessibility:
            // Shows the system prompt, opens System Settings if needed and keeps checking for two minutes.
            model.drawer.requestAccess()
        }
        permissionStatus[permission] = await Self.currentStatus(of: permission)
    }

    func openSystemSettings(for permission: OnboardingPermission) {
        let anchor = switch permission {
        case .calendar: "Privacy_Calendars"
        case .automation: "Privacy_Automation"
        case .camera: "Privacy_Camera"
        case .accessibility: "Privacy_Accessibility"
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    static func currentStatus(of permission: OnboardingPermission) async -> OnboardingPermissionStatus {
        switch permission {
        case .calendar:
            return calendarStatus(EKEventStore.authorizationStatus(for: .event))
        case .camera:
            return cameraStatus(AVCaptureDevice.authorizationStatus(for: .video), hasCamera: hasCamera())
        case .automation:
            var statuses: [AutomationPermission.Status] = []
            for player in runningPlayers() {
                statuses.append(await AutomationPermission.status(for: player.bundleID))
            }
            return automationStatus(statuses)
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notAsked
        }
    }

    static func calendarStatus(_ status: EKAuthorizationStatus) -> OnboardingPermissionStatus {
        switch CalendarStore.access(for: status) {
        case .granted: .granted
        case .unknown: .notAsked
        case .denied: .denied
        }
    }

    static func cameraStatus(_ status: AVAuthorizationStatus, hasCamera: Bool) -> OnboardingPermissionStatus {
        switch MirrorStore.access(for: status) {
        case .granted: .granted
        case .denied: .denied
        case .unknown: hasCamera ? .notAsked : .notNow
        }
    }

    /// One answer for Music and Spotify together: allowed for either is enough to show what's playing.
    static func automationStatus(_ statuses: [AutomationPermission.Status]) -> OnboardingPermissionStatus {
        if statuses.isEmpty { return .notNow }
        if statuses.contains(.granted) { return .granted }
        if statuses.contains(.denied) { return .denied }
        return .notAsked
    }

    static func runningPlayers() -> [MusicPlayer] {
        let open = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return MusicPlayer.allCases.filter { open.contains($0.bundleID) }
    }

    private static func hasCamera() -> Bool {
        !AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.isEmpty
    }
}
