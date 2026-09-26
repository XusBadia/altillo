import AltilloAgents
import AltilloCore
import AppKit
import Foundation

/// Finds the app hosting an agent (from the hook's parent chain and environment) and brings the right window and
/// tab forward. Tab selection uses AppleScript for Terminal and iTerm2, only when macOS already allows Altillo to
/// automate them, or after asking once; it never blocks the main thread.
enum AgentTerminalFocus {
    static let terminalBundleID = "com.apple.Terminal"
    static let iTermBundleID = "com.googlecode.iterm2"

    /// `TERM_PROGRAM` values → bundle ids, for when the parent chain doesn't reach a running app.
    static let termProgramBundles: [String: String] = [
        "Apple_Terminal": terminalBundleID, "iTerm.app": iTermBundleID, "ghostty": "com.mitchellh.ghostty",
        "WezTerm": "com.github.wez.wezterm", "vscode": "com.microsoft.VSCode", "WarpTerminal": "dev.warp.Warp-Stable",
        "Hyper": "co.zeit.hyper", "Tabby": "org.tabby", "zed": "dev.zed.Zed", "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
    ]

    /// Where the hook says the agent runs. Main actor: `NSRunningApplication` lookups.
    @MainActor
    static func host(for envelope: HookEnvelope) -> AgentHost {
        var app: NSRunningApplication?
        for pid in envelope.ppids {
            if let candidate = NSRunningApplication(processIdentifier: pid), candidate.activationPolicy == .regular {
                app = candidate
                break
            }
        }
        let env = envelope.env
        if app == nil, let bundleID = env["__CFBundleIdentifier"] ?? env["TERM_PROGRAM"].flatMap({ termProgramBundles[$0] }) {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        let sessionID = env["ITERM_SESSION_ID"] ?? env["TERM_SESSION_ID"] ?? env["KITTY_WINDOW_ID"]
            ?? env["WEZTERM_PANE"] ?? env["TMUX_PANE"]
        return AgentHost(
            appBundleID: app?.bundleIdentifier ?? env["__CFBundleIdentifier"],
            appName: app?.localizedName, terminalProgram: env["TERM_PROGRAM"], terminalSessionID: sessionID,
            tty: envelope.tty, pid: envelope.agentPID ?? env["CLAUDE_PID"].flatMap { Int32($0) })
    }

    /// Activates the host app, then selects the tab when the host supports it.
    /// The running app hosting the session: its bundle id, else the first GUI app walking up from the agent.
    @MainActor
    static func application(for host: AgentHost) -> NSRunningApplication? {
        var app: NSRunningApplication?
        if let bundleID = host.appBundleID {
            app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        }
        if app == nil, let pid = host.pid {
            // Walk up from the agent to the first GUI app.
            for entry in [ProcessTree.entry(pid)].compactMap({ $0 }) + ProcessTree.ancestors(of: pid) {
                if let candidate = NSRunningApplication(processIdentifier: entry.pid),
                   candidate.activationPolicy == .regular {
                    app = candidate
                    break
                }
            }
        }
        return app
    }

    @MainActor
    static func focus(_ host: AgentHost) {
        guard let app = application(for: host) else { return }
        app.activate()

        guard let bundleID = app.bundleIdentifier, let script = tabScript(bundleID: bundleID, host: host) else { return }
        Task.detached(priority: .userInitiated) {
            guard await mayAutomate(bundleID: bundleID) else { return }
            _ = try? await AppleScriptRunner.run(script)
        }
    }

    /// The AppleScript that selects the session's tab, when the host supports it and we know which tab.
    static func tabScript(bundleID: String, host: AgentHost) -> String? {
        switch bundleID {
        case terminalBundleID:
            guard let tty = host.tty, isSafe(tty) else { return nil }
            return """
            tell application id "\(terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected of t to true
                            set index of w to 1
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            """
        case iTermBundleID:
            // ITERM_SESSION_ID is "w0t1p0:<unique id>".
            let uniqueID = host.terminalSessionID?.split(separator: ":").last.map(String.init)
            let tty = host.tty
            guard uniqueID != nil || tty != nil, isSafe(uniqueID ?? ""), isSafe(tty ?? "") else { return nil }
            return """
            tell application id "\(iTermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (unique id of s is "\(uniqueID ?? "-")") or (tty of s is "\(tty ?? "-")") then
                                select w
                                tell t to select
                                tell s to select
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        default:
            return nil
        }
    }

    /// Identifiers pasted into a script: letters, digits and `/-_.:` only.
    static func isSafe(_ text: String) -> Bool {
        text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "/-_.:".contains($0)) }
    }

    /// Whether to script `bundleID`: yes when already allowed; when macOS has never asked, run it once so macOS
    /// asks (the script's first Apple Event shows the system prompt); never again after that.
    static func mayAutomate(bundleID: String) async -> Bool {
        switch await AutomationPermission.status(for: bundleID) {
        case .granted:
            return true
        case .undetermined:
            let key = "agents.automationAsked." + bundleID
            guard !UserDefaults.standard.bool(forKey: key) else { return false }
            UserDefaults.standard.set(true, forKey: key)
            return true
        case .denied, .unavailable:
            return false
        }
    }
}
