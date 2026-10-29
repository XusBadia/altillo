import Foundation
import Testing
@testable import Altillo

struct SupportDiagnosticsTests {
    @Test func safeSnapshotContainsUsefulStateButNeverPathsNotesOrCredentials() {
        let secretPath = URL(filePath: "/Users/alice/private/.claude/settings.json")
        let reports = [
            AgentHookReport(target: .claude, status: .installed, configFile: secretPath,
                            notes: ["token=secret-123"]),
            AgentHookReport(target: .codex, status: .unreadable("at /Users/alice/.codex/hooks.json"),
                            configFile: secretPath, notes: ["Bearer private"]),
        ]

        let text = SupportDiagnostics.make(version: "1.2.3", build: "45", operatingSystem: "macOS 26.1",
                                           architecture: "arm64", reports: reports,
                                           drawer: DrawerSupportDiagnostics(enabled: true, canHide: true,
                                               accessibilityTrusted: true, hidesIcons: true, peeking: false,
                                               concealing: false, assertionActive: false, selectedApps: 2,
                                               catalogItems: 10, interactionActive: false, hasProblem: true))

        #expect(text.contains("Version: 1.2.3 (45)"))
        #expect(text.contains("Claude Code: installed"))
        #expect(text.contains("Codex: configuration left untouched"))
        #expect(text.contains("Hiding available: true"))
        #expect(text.contains("Concealing: false"))
        #expect(text.contains("Selected apps: 2"))
        #expect(text.contains("Has error: true"))
        #expect(!text.contains("/Users/"))
        #expect(!text.contains("secret-123"))
        #expect(!text.contains("Bearer"))
    }
}
