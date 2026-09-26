import AltilloCore
import AppKit
import SwiftUI

/// What Settings › Sections › Agents does with the installer: reads each agent's status, computes a plan for the
/// user to review, and applies it only after they confirm. File work is small (a few KB), so it runs in place.
@MainActor
@Observable
final class AgentHooksModel {
    struct Feedback: Equatable {
        let text: String
        let isError: Bool
        /// The backup taken before writing, to reveal in Finder.
        var backup: URL?
    }

    private(set) var reports: [AgentHookReport] = []
    /// The plan being reviewed in the diff sheet.
    var review: AgentHookPlan?
    private(set) var feedback: [AgentHookTarget: Feedback] = [:]
    /// Agents whose stop hook waits for a reply from the notch (opt-in, off by default; phase 14).
    private(set) var replyTargets: Set<AgentHookTarget>
    /// A reply toggle waiting on the review sheet: undone if the user cancels it.
    private var pendingReplyChange: (target: AgentHookTarget, wasOn: Bool)?

    private let environment: AgentHookEnvironment
    private let defaults: UserDefaults

    static func replyKey(_ target: AgentHookTarget) -> String { "agentReplyFromNotch.\(target.rawValue)" }

    /// Replying from the notch is on by default for Claude Code and Codex, for new installs only: the first install
    /// includes it (and its review shows it). An install made before this default keeps what it has; the switch
    /// stays there. Gemini, Copilot and Cursor start off.
    static let repliesByDefault: Set<AgentHookTarget> = [.claude, .codex]

    init(environment: AgentHookEnvironment = .live, defaults: UserDefaults = .standard) {
        self.environment = environment
        self.defaults = defaults
        replyTargets = Set(AgentHookTarget.allCases.filter { defaults.bool(forKey: Self.replyKey($0)) })
    }

    /// Settles the default for agents the user never chose for: on for a new install, off (remembered) for one that
    /// already has Altillo's hooks.
    private func resolveReplyDefaults(wait: Int) {
        let plain = AgentHookInstaller(environment: environment, wait: wait)
        for target in Self.repliesByDefault where defaults.object(forKey: Self.replyKey(target)) == nil {
            switch plain.status(for: target) {
            case .installed, .needsRepair:
                replyTargets.remove(target)
                defaults.set(false, forKey: Self.replyKey(target))
            case .notInstalled, .agentNotFound, .unreadable:
                replyTargets.insert(target) // remembered once the install is confirmed
            }
        }
    }

    func installer(wait: Int) -> AgentHookInstaller {
        AgentHookInstaller(environment: environment, wait: wait, replyTargets: replyTargets)
    }

    /// "Let me reply from the notch": remembered per agent; when its hooks are in, the change goes through the same
    /// review as any other edit of the agent's file (cancelling it turns the switch back).
    func setReply(_ on: Bool, for target: AgentHookTarget, wait: Int) {
        let wasOn = replyTargets.contains(target)
        guard on != wasOn else { return }
        if on { replyTargets.insert(target) } else { replyTargets.remove(target) }
        defaults.set(on, forKey: Self.replyKey(target))
        let status = reports.first { $0.target == target }?.status
        switch status {
        case .installed?, .needsRepair?:
            pendingReplyChange = (target, wasOn)
            prepare(.install, for: target, wait: wait)
            if review == nil { pendingReplyChange = nil }
        default:
            refresh(wait: wait)
        }
    }

    /// The review sheet was dismissed without writing.
    func cancelReview(wait: Int) {
        review = nil
        if let change = pendingReplyChange {
            if change.wasOn { replyTargets.insert(change.target) } else { replyTargets.remove(change.target) }
            defaults.set(change.wasOn, forKey: Self.replyKey(change.target))
            pendingReplyChange = nil
        }
        refresh(wait: wait)
    }

    func displayPath(_ url: URL) -> String { environment.displayPath(url) }
    var backupsPath: String { environment.displayPath(environment.backupsDirectory) }

    func refresh(wait: Int) {
        resolveReplyDefaults(wait: wait)
        let installer = installer(wait: wait)
        reports = AgentHookTarget.allCases.map(installer.report(for:))
    }

    /// Install, Update (also relinks the hook first) or Remove: computes the change and opens the review sheet.
    func prepare(_ action: AgentHookPlan.Action, for target: AgentHookTarget, wait: Int) {
        feedback[target] = nil
        resolveReplyDefaults(wait: wait)
        let installer = installer(wait: wait)
        do {
            if action == .install, !FileManager.default.isExecutableFile(atPath: environment.hookLink.path) {
                if case .unavailable(let reason) = AgentHookInstaller.refreshStableHookPath(environment: environment) {
                    throw AgentHookError.hookUnavailable(reason)
                }
            }
            let plan = action == .install ? try installer.planInstall(target) : try installer.planUninstall(target)
            if plan.changesNothing {
                // Only the hook link needed fixing (or nothing at all): there's nothing to review.
                try installer.apply(plan)
                if action == .install { defaults.set(replyTargets.contains(target), forKey: Self.replyKey(target)) }
                feedback[target] = Feedback(text: String(localized: "Up to date. Nothing in the file had to change."),
                                            isError: false)
            } else {
                review = plan
            }
        } catch {
            feedback[target] = Feedback(text: error.localizedDescription, isError: true)
        }
        refresh(wait: wait)
    }

    func confirm(_ plan: AgentHookPlan, wait: Int) {
        review = nil
        pendingReplyChange = nil
        if plan.action == .install {
            defaults.set(replyTargets.contains(plan.target), forKey: Self.replyKey(plan.target))
        }
        do {
            let outcome = try installer(wait: wait).apply(plan)
            let text = switch plan.action {
            case .install: String(localized: "Hooks installed.")
            case .uninstall: String(localized: "Hooks removed. Everything else is as it was.")
            }
            feedback[plan.target] = Feedback(text: text, isError: false, backup: outcome.backup)
        } catch {
            feedback[plan.target] = Feedback(text: error.localizedDescription, isError: true)
        }
        refresh(wait: wait)
    }
}

/// Settings › Sections › Agents: per agent, whether Altillo's hooks are in, and the buttons to install, update or
/// remove them (each through a diff the user confirms); how long a permission waits for an answer; and what
/// Altillo does and never does with them.
struct SettingsAgentsGroup: View {
    @Bindable var settings: AltilloSettings
    @State private var model = AgentHooksModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hooks")
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                ForEach(model.reports, id: \.target) { report in
                    SettingsAgentHookRow(report: report, feedback: model.feedback[report.target],
                                         path: model.displayPath(report.configFile),
                                         replies: Binding(
                                            get: { model.replyTargets.contains(report.target) },
                                            set: { model.setReply($0, for: report.target, wait: settings.agentPermissionWait) }),
                                         wait: Self.waitTitle(settings.agentPermissionWait)) { action in
                        model.prepare(action, for: report.target, wait: settings.agentPermissionWait)
                    }
                }
                SettingsOpenCodeRow()
                Text("Hooks let an agent tell Altillo what it's doing and ask you for permission in the notch. Without them Altillo still shows your sessions from the agents' own session files, but can't approve anything.")
                    .settingsHint()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text("Wait for my answer up to")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paper)
                    Picker(selection: $settings.agentPermissionWait) {
                        ForEach(AgentHookCommand.waitChoices, id: \.self) { seconds in
                            Text(Self.waitTitle(seconds)).tag(seconds)
                        }
                    } label: {
                        Text("Wait for my answer up to")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                Text("Altillo never approves anything on its own. If Altillo is closed or you don't answer in time, the agent asks in the terminal as usual.")
                    .settingsHint()
            }
        }
        .padding(.vertical, 6)
        .onAppear { model.refresh(wait: settings.agentPermissionWait) }
        .onChange(of: settings.agentPermissionWait) { _, wait in model.refresh(wait: wait) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh(wait: settings.agentPermissionWait)
        }
        .sheet(item: $model.review) { plan in
            AgentHookReviewSheet(plan: plan, path: model.displayPath(plan.fileURL),
                                 backups: model.backupsPath,
                                 cancel: { model.cancelReview(wait: settings.agentPermissionWait) },
                                 confirm: { model.confirm(plan, wait: settings.agentPermissionWait) })
        }
    }

    static func waitTitle(_ seconds: Int) -> String {
        switch seconds {
        case 120: String(localized: "2 min (default)")
        case let seconds where seconds % 60 == 0: String(localized: "\(seconds / 60) min")
        default: String(localized: "\(seconds) s")
        }
    }
}

/// OpenCode needs nothing installed: Altillo follows `opencode serve` while it runs.
private struct SettingsOpenCodeRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            AgentGlyph(agent: .opencode, size: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "OpenCode")
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("Nothing to install. While `opencode serve` runs, Altillo follows its sessions, and you can answer its permissions and reply from the notch.")
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// One agent: its mark, name, how its hooks stand, the file they live in, and what can be done.
private struct SettingsAgentHookRow: View {
    let report: AgentHookReport
    let feedback: AgentHooksModel.Feedback?
    let path: String
    /// "Let me reply from the notch" for this agent.
    @Binding var replies: Bool
    /// "2 min (default)": how long the agent waits.
    let wait: String
    let perform: (AgentHookPlan.Action) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 9) {
                AgentGlyph(agent: AgentKind(rawValue: report.target.rawValue), size: 20)
                    .opacity(report.status == .agentNotFound ? 0.5 : 1)
                VStack(alignment: .leading, spacing: 0) {
                    Text(report.target.displayName)
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    HStack(spacing: 4) {
                        if let symbol = statusSymbol {
                            Image(systemName: symbol)
                                .font(.system(size: 10.5, weight: .semibold))
                                .accessibilityHidden(true)
                        }
                        Text(statusText)
                            .font(.system(size: 11))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(statusColor)
                }
                Spacer(minLength: 8)
                buttons
                    .controlSize(.small)
            }
            .accessibilityElement(children: .contain)

            VStack(alignment: .leading, spacing: 3) {
                if report.status != .agentNotFound {
                    Text(verbatim: path)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .textSelection(.enabled)
                }
                ForEach(notes, id: \.self) { note in
                    Text(note).settingsHint()
                }
                if report.status != .agentNotFound, report.target.replyEvent != nil {
                    Toggle(isOn: $replies) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Let me reply from the notch")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Desvan.Palette.paper)
                            Text("When it finishes a turn and you're not looking at its terminal, the agent waits up to \(wait) for your reply before it stops. Switching to the terminal lets it stop at once, so you can type there. On by default for new Claude Code and Codex installs.")
                                .settingsHint()
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .padding(.top, 2)
                }
                if let feedback {
                    HStack(spacing: 8) {
                        Text(feedback.text)
                            .font(.system(size: 11))
                            .foregroundStyle(feedback.isError ? Desvan.Palette.warning : Desvan.Palette.paperSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let backup = feedback.backup {
                            Button("Show Backup") { NSWorkspace.shared.activateFileViewerSelecting([backup]) }
                                .buttonStyle(.link)
                                .font(.system(size: 11))
                        }
                    }
                }
            }
            .padding(.leading, 29)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var buttons: some View {
        switch report.status {
        case .notInstalled:
            Button("Install…") { perform(.install) }
        case .installed:
            Button("Remove…") { perform(.uninstall) }
        case .needsRepair:
            HStack(spacing: 6) {
                Button("Remove…") { perform(.uninstall) }
                Button("Update…") { perform(.install) }
                    .keyboardShortcut(.defaultAction)
            }
        case .unreadable:
            Button("Open File") { NSWorkspace.shared.open(report.configFile) }
        case .agentNotFound:
            EmptyView()
        }
    }

    private var notes: [String] {
        var notes = report.notes
        let isIn = report.status == .installed || report.status == .needsRepair(.outdated)
            || report.status == .needsRepair(.hookMissing)
        if report.target == .codex, isIn {
            notes.append(String(localized: "Codex runs new or changed hooks only once you trust them: in Codex, type /hooks and trust Altillo's."))
        }
        if !report.target.answersPermissions, report.status != .agentNotFound {
            notes.append(String(localized: "Altillo shows when it asks for permission, but you answer in the terminal: its hooks can't answer for you."))
        }
        return notes
    }

    private var statusText: String {
        switch report.status {
        case .notInstalled: String(localized: "Not installed")
        case .installed: String(localized: "Installed")
        case .needsRepair(.hookMissing): String(localized: "Needs repair: the hooks can't find Altillo")
        case .needsRepair(.outdated):
            String(localized: "Needs an update: written by another version, or with another wait")
        case .agentNotFound: String(localized: "Not set up on this Mac")
        case .unreadable(let reason): String(localized: "Left alone: \(reason)")
        }
    }

    private var statusSymbol: String? {
        switch report.status {
        case .installed: "checkmark.circle.fill"
        case .needsRepair, .unreadable: "exclamationmark.triangle.fill"
        case .notInstalled, .agentNotFound: nil
        }
    }

    private var statusColor: Color {
        switch report.status {
        case .installed: Desvan.Palette.sage
        case .needsRepair, .unreadable: Desvan.Palette.warning
        case .notInstalled, .agentNotFound: Desvan.Palette.paperSecondary
        }
    }
}

/// The review before any write: what will change, as a unified diff, and the promise of what won't.
struct AgentHookReviewSheet: View {
    let plan: AgentHookPlan
    let path: String
    let backups: String
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Desvan.Typeface.display(16, weight: 650))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Text(verbatim: path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 8)
                Text(verbatim: "+\(plan.diff.addedCount)")
                    .foregroundStyle(Desvan.Palette.sage)
                Text(verbatim: "−\(plan.diff.removedCount)")
                    .foregroundStyle(Desvan.Palette.tomato)
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))

            AgentHookDiffView(diff: plan.diff)

            if plan.target == .codex, plan.action == .install {
                Text("Codex runs new or changed hooks only once you trust them: in Codex, type /hooks and trust Altillo's.")
                    .settingsHint()
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(plan.action == .install ? "Install" : "Remove", action: confirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 520)
        .background(Desvan.Palette.wood)
        .environment(\.colorScheme, .dark)
    }

    private var title: String {
        switch plan.action {
        case .install: String(localized: "Install Altillo's hooks for \(plan.target.displayName)?")
        case .uninstall: String(localized: "Remove Altillo's hooks from \(plan.target.displayName)?")
        }
    }

    private var explanation: String {
        let backup = plan.originalData == nil ? ""
            : " " + String(localized: "A copy of the file goes to \(backups) first.")
        switch plan.action {
        case .install:
            return String(localized: "Altillo will change this file exactly as shown. Your other settings and hooks stay as they are.") + backup
        case .uninstall where plan.newText == nil:
            return String(localized: "Altillo created this file for its hooks and nothing else is in it, so it will be deleted.") + backup
        case .uninstall:
            return String(localized: "Only Altillo's hooks come out. Your other settings and hooks stay as they are.") + backup
        }
    }
}

/// A unified diff in monospace: removed lines on red, added lines on green, context dimmed.
private struct AgentHookDiffView: View {
    let diff: UnifiedDiff

    private struct Row: Identifiable {
        let id: Int
        let text: String
        let kind: Kind
        enum Kind { case header, hunk, context, removed, added }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        func add(_ text: String, _ kind: Row.Kind) { rows.append(Row(id: rows.count, text: text, kind: kind)) }
        add("--- \(diff.oldName)", .header)
        add("+++ \(diff.newName)", .header)
        for hunk in diff.hunks {
            add(hunk.header, .hunk)
            for line in hunk.lines {
                switch line {
                case .context(let text): add(" " + text, .context)
                case .removed(let text): add("-" + text, .removed)
                case .added(let text): add("+" + text, .added)
                }
            }
        }
        return rows
    }

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Text(verbatim: row.text.isEmpty ? " " : row.text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(color(row.kind))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(background(row.kind))
                }
            }
            .padding(.vertical, 6)
            .textSelection(.enabled)
        }
        // Short diffs start at the left edge like any code listing, rather than centred in the scroll view.
        .defaultScrollAnchor(.topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
            shape.fill(Color.black.opacity(0.35))
                .overlay { shape.strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(Text("Changes to the file"))
        .accessibilityValue(Text(diff.text))
    }

    private func color(_ kind: Row.Kind) -> Color {
        switch kind {
        case .header: Desvan.Palette.paperTertiary
        case .hunk: Desvan.Palette.sky
        case .context: Desvan.Palette.paperSecondary
        case .removed: Desvan.Palette.tomato
        case .added: Desvan.Palette.sage
        }
    }

    private func background(_ kind: Row.Kind) -> Color {
        switch kind {
        case .removed: Desvan.Palette.tomato.opacity(0.12)
        case .added: Desvan.Palette.sage.opacity(0.12)
        default: .clear
        }
    }
}
