import Foundation

/// A deliberately small support snapshot. It reports product/runtime state only: never file paths, usernames,
/// environment variables, hook notes, session text, clipboard contents, credentials or logs.
enum SupportDiagnostics {
    @MainActor
    static func current(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let reports = AgentHookTarget.allCases.map(AgentHookInstaller().report(for:))
        return make(version: version, build: build,
                    operatingSystem: processInfo.operatingSystemVersionString,
                    architecture: architecture, reports: reports,
                    drawer: MenuBarDrawerStore.shared.supportDiagnostics)
    }

    static func make(version: String, build: String, operatingSystem: String, architecture: String,
                     reports: [AgentHookReport], drawer: DrawerSupportDiagnostics? = nil) -> String {
        let hooks = reports.map { "- \($0.target.displayName): \(statusName($0.status))" }.joined(separator: "\n")
        let drawerState = drawer.map { "\n\($0.summary)" } ?? ""
        return """
        Altillo diagnostics (safe to share)
        Version: \(version) (\(build))
        macOS: \(operatingSystem)
        Architecture: \(architecture)\(drawerState)
        Hook status:
        \(hooks)

        No paths, credentials, session content or logs are included.
        """
    }

    private static func statusName(_ status: AgentHookStatus) -> String {
        switch status {
        case .notInstalled: "not installed"
        case .installed: "installed"
        case .needsRepair(.hookMissing): "needs repair (hook missing)"
        case .needsRepair(.outdated): "needs update"
        case .agentNotFound: "agent not found"
        case .unreadable: "configuration left untouched"
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}

/// Counts and fixed states only: no app identities, menu titles or screen contents.
struct DrawerSupportDiagnostics {
    var enabled: Bool
    var canHide: Bool
    var accessibilityTrusted: Bool
    var hidesIcons: Bool
    var peeking: Bool
    var concealing: Bool
    var assertionActive: Bool
    var selectedApps: Int
    var catalogItems: Int
    var interactionActive: Bool
    var hasProblem: Bool

    var summary: String {
        """
        Drawer:
        - Enabled: \(enabled)
        - Hiding available: \(canHide)
        - Accessibility trusted: \(accessibilityTrusted)
        - Hide icons: \(hidesIcons)
        - Showing hidden icons: \(peeking)
        - Concealing: \(concealing)
        - Assertion active: \(assertionActive)
        - Selected apps: \(selectedApps)
        - Catalog items: \(catalogItems)
        - Interaction active: \(interactionActive)
        - Has error: \(hasProblem)
        """
    }
}
