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

    private let environment: AgentHookEnvironment

    init(environment: AgentHookEnvironment = .live) {
        self.environment = environment
    }

    func installer(wait: Int) -> AgentHookInstaller {
        AgentHookInstaller(environment: environment, wait: wait)
    }

    func displayPath(_ url: URL) -> String { environment.displayPath(url) }
    var backupsPath: String { environment.displayPath(environment.backupsDirectory) }

    func refresh(wait: Int) {
        let installer = installer(wait: wait)
        reports = AgentHookTarget.allCases.map(installer.report(for:))
    }

    /// Install, Update (also relinks the hook first) or Remove: computes the change and opens the review sheet.
    func prepare(_ action: AgentHookPlan.Action, for target: AgentHookTarget, wait: Int) {
        feedback[target] = nil
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
                                         path: model.displayPath(report.configFile)) { action in
                        model.prepare(action, for: report.target, wait: settings.agentPermissionWait)
                    }
                }
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
                                 cancel: { model.review = nil },
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

/// One agent: its mark, name, how its hooks stand, the file they live in, and what can be done.
private struct SettingsAgentHookRow: View {
    let report: AgentHookReport
    let feedback: AgentHooksModel.Feedback?
    let path: String
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
        if report.target == .codex, report.status == .installed || report.status == .needsRepair(.outdated)
            || report.status == .needsRepair(.hookMissing) {
            notes.append(String(localized: "Codex runs new or changed hooks only once you trust them: in Codex, type /hooks and trust Altillo's."))
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
