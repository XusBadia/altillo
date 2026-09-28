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
    /// The all-agents preview shown before the user deletes Altillo.
    var uninstallPreparation: AgentHooksUninstallPreparation?
    private(set) var uninstallSummary: String?
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

    func prepareToUninstall(wait: Int) {
        uninstallSummary = nil
        let preparation = installer(wait: wait).prepareToUninstall()
        if preparation.isEmpty {
            uninstallSummary = String(localized: "No Altillo hooks are installed. You can delete the app safely.")
        } else {
            uninstallPreparation = preparation
        }
    }

    func confirmUninstall(_ plans: [AgentHookPlan], wait: Int) {
        let preparation = uninstallPreparation
        let manualSteps = preparation?.manualSteps ?? []
        let selectedTargets = Set(plans.map(\.target))
        let unselected = preparation?.plans.filter { !selectedTargets.contains($0.target) } ?? []
        uninstallPreparation = nil
        let results = installer(wait: wait).applyUninstall(plans)
        for result in results {
            if let error = result.errorDescription {
                feedback[result.target] = Feedback(text: error, isError: true)
            } else {
                feedback[result.target] = Feedback(
                    text: String(localized: "Hooks removed. This agent is ready for Altillo to be deleted."),
                    isError: false, backup: result.backup
                )
            }
        }
        for step in manualSteps {
            feedback[step.target] = Feedback(
                text: String(localized: "Not changed automatically. Open the file and remove only Altillo's hook entries."),
                isError: true
            )
        }
        for plan in unselected {
            feedback[plan.target] = Feedback(
                text: String(localized: "Still installed. Remove these hooks before deleting Altillo."),
                isError: true
            )
        }
        let removed = results.filter(\.succeeded).count
        let failed = results.count - removed
        if failed == 0, manualSteps.isEmpty, unselected.isEmpty {
            uninstallSummary = String(localized: "All selected Altillo hooks were removed. You can now delete the app.")
        } else {
            uninstallSummary = String(localized: "Removed \(removed); \(failed + manualSteps.count + unselected.count) still need attention before deleting Altillo.")
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hooksSection
            SettingsCardDivider()
            permissionsSection
            SettingsCardDivider()
            uninstallSection
        }
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: showsReplySwitch)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: model.uninstallSummary)
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
        .sheet(item: $model.uninstallPreparation) { preparation in
            AgentHooksUninstallSheet(
                preparation: preparation,
                path: model.displayPath,
                backups: model.backupsPath,
                cancel: { model.uninstallPreparation = nil },
                confirm: { model.confirmUninstall($0, wait: settings.agentPermissionWait) }
            )
        }
    }

    /// Every CLI in one well, OpenCode last; what hooks are for under it.
    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Hooks")
            SettingsWell {
                ForEach(model.reports, id: \.target) { report in
                    if report.target != model.reports.first?.target {
                        SettingsRowDivider(leading: SettingsAgentHookRow.textInset)
                    }
                    SettingsAgentHookRow(report: report, feedback: model.feedback[report.target],
                                         path: model.displayPath(report.configFile),
                                         replies: Binding(
                                            get: { model.replyTargets.contains(report.target) },
                                            set: { model.setReply($0, for: report.target, wait: settings.agentPermissionWait) })) { action in
                        model.prepare(action, for: report.target, wait: settings.agentPermissionWait)
                    }
                }
                if !model.reports.isEmpty {
                    SettingsRowDivider(leading: SettingsAgentHookRow.textInset)
                }
                SettingsOpenCodeRow()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Hooks are optional and installed separately for each CLI. They give Altillo precise live events, permission requests and replies. Without hooks, Claude Code, Codex and Gemini still appear from local session files with less detail; Copilot and Cursor need hooks. OpenCode uses its local API and needs nothing installed.")
                    .settingsHint()
                if showsReplySwitch {
                    replyFootnote
                        .transition(.settingsReveal)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// How long a permission request waits in the notch before the agent asks in the terminal.
    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Permissions")
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Wait for my answer up to")
                        .settingsRowTitle()
                        .accessibilityHidden(true)
                    Spacer(minLength: 12)
                    Picker(selection: $settings.agentPermissionWait) {
                        ForEach(AgentHookCommand.waitChoices, id: \.self) { seconds in
                            Text(Self.waitTitle(seconds)).tag(seconds)
                        }
                    } label: {
                        Text("Wait for my answer up to")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .fixedSize()
                }
                Text("Altillo never approves anything on its own. If Altillo is closed or you don't answer in time, the agent asks in the terminal as usual.")
                    .settingsHint()
            }
            .padding(.horizontal, 2)
        }
    }

    /// Removing every hook before Altillo is deleted, and how that went.
    private var uninstallSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Uninstall")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    Text("Before deleting Altillo, remove its hooks so no CLI keeps a command pointing to a missing app. You'll review every file first; backups are made and other hooks stay untouched.")
                        .settingsHint()
                    Spacer(minLength: 12)
                    Button("Prepare to Uninstall…") {
                        model.prepareToUninstall(wait: settings.agentPermissionWait)
                    }
                    .controlSize(.small)
                    .fixedSize()
                }
                if let summary = model.uninstallSummary {
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(summary)
                        .transition(.settingsReveal)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Some agent row has "Let me reply from the notch".
    private var showsReplySwitch: Bool {
        model.reports.contains { SettingsAgentHookRow.showsReplySwitch(for: $0) }
    }

    /// What "Let me reply from the notch" does, said once for every agent that has the switch.
    private var replyFootnote: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Let me reply from the notch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            Text("When it finishes a turn and you're not looking at its terminal, the agent waits up to \(Self.waitTitle(settings.agentPermissionWait)) for your reply before it stops. Switching to the terminal lets it stop at once, so you can type there. On by default for new Claude Code and Codex installs.")
                .settingsHint()
        }
        .accessibilityElement(children: .combine)
    }

    static func waitTitle(_ seconds: Int) -> String {
        switch seconds {
        case 120: String(localized: "2 min (default)")
        case let seconds where seconds % 60 == 0: String(localized: "\(seconds / 60) min")
        default: String(localized: "\(seconds) s")
        }
    }
}

/// One review for every CLI before Altillo is removed. Each safe target is selected explicitly; ambiguous files
/// are never edited and instead show the exact manual action.
private struct AgentHooksUninstallSheet: View {
    let preparation: AgentHooksUninstallPreparation
    let path: (URL) -> String
    let backups: String
    let cancel: () -> Void
    let confirm: ([AgentHookPlan]) -> Void

    @State private var selected: Set<AgentHookTarget>

    init(preparation: AgentHooksUninstallPreparation, path: @escaping (URL) -> String, backups: String,
         cancel: @escaping () -> Void, confirm: @escaping ([AgentHookPlan]) -> Void) {
        self.preparation = preparation
        self.path = path
        self.backups = backups
        self.cancel = cancel
        self.confirm = confirm
        _selected = State(initialValue: Set(preparation.plans.map(\.target)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Prepare to Uninstall Altillo")
                    .font(Desvan.Typeface.display(17, weight: 650))
                    .foregroundStyle(Desvan.Palette.paper)
                Text("Choose each agent to clean up. Altillo removes only commands it owns, saves the current file in \(backups), and then confirms the result for every agent.")
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(preparation.plans) { plan in
                        VStack(alignment: .leading, spacing: 7) {
                            Toggle(isOn: selection(for: plan.target)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(plan.target.displayName)
                                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                                    Text(verbatim: path(plan.fileURL))
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundStyle(Desvan.Palette.paperTertiary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            AgentHookDiffView(diff: plan.diff)
                                .frame(height: 150)
                                .opacity(selected.contains(plan.target) ? 1 : 0.45)
                        }
                    }

                    ForEach(preparation.manualSteps) { step in
                        VStack(alignment: .leading, spacing: 5) {
                            Label("\(step.target.displayName) needs manual cleanup", systemImage: "exclamationmark.triangle.fill")
                                .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                                .foregroundStyle(Desvan.Palette.warning)
                            Text(verbatim: path(step.fileURL))
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                            Text("Altillo left this file untouched because \(step.reason) Open it and remove only complete hook entries whose command, bash or exec value runs `altillo-hook`. Leave every other setting and hook unchanged.")
                                .settingsHint()
                            Button("Open File") { NSWorkspace.shared.open(step.fileURL) }
                                .controlSize(.small)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Desvan.Palette.warning.opacity(0.08)))
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(removeTitle) {
                    confirm(preparation.plans.filter { selected.contains($0.target) })
                }
                .disabled(selected.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 680, height: 680)
        .background(Desvan.Palette.wood)
        .environment(\.colorScheme, .dark)
    }

    private func selection(for target: AgentHookTarget) -> Binding<Bool> {
        Binding(
            get: { selected.contains(target) },
            set: { on in
                if on { selected.insert(target) } else { selected.remove(target) }
            }
        )
    }

    private var removeTitle: String {
        String(localized: "Remove Hooks (\(selected.count))")
    }
}

/// OpenCode needs nothing installed: Altillo follows `opencode serve` while it runs.
private struct SettingsOpenCodeRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: SettingsAgentHookRow.glyphSpacing) {
            AgentGlyph(agent: .opencode, size: SettingsAgentHookRow.glyphSize)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "OpenCode")
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .frame(minHeight: SettingsAgentHookRow.glyphSize)
                Text("Nothing to install. While `opencode serve` runs, Altillo follows its sessions, and you can answer its permissions and reply from the notch.")
                    .settingsHint()
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// One agent: its mark, name, how its hooks stand, the file they live in, and what can be done.
private struct SettingsAgentHookRow: View {
    let report: AgentHookReport
    let feedback: AgentHooksModel.Feedback?
    let path: String
    /// "Let me reply from the notch" for this agent (what it does is the group's footnote, said once).
    @Binding var replies: Bool
    let perform: (AgentHookPlan.Action) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let glyphSize: CGFloat = 20
    static let glyphSpacing: CGFloat = 11
    /// Where the text column starts: past the glyph. Row dividers and the lines under the name line up here.
    static let textInset: CGFloat = glyphSize + glyphSpacing

    static func showsReplySwitch(for report: AgentHookReport) -> Bool {
        report.status != .agentNotFound && report.target.replyEvent != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: Self.glyphSpacing) {
                AgentGlyph(agent: AgentKind(rawValue: report.target.rawValue), size: Self.glyphSize)
                    .opacity(report.status == .agentNotFound ? 0.5 : 1)
                HStack(alignment: .center, spacing: 7) {
                    Text(report.target.displayName)
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(report.status == .agentNotFound
                                         ? Desvan.Palette.paperSecondary : Desvan.Palette.paper)
                    SettingsBadge(text: badgeText, symbol: badgeSymbol, tone: badgeTone)
                        .id(badgeText)
                        .transition(.opacity)
                        .accessibilityLabel(Text(verbatim: statusText))
                }
                Spacer(minLength: 8)
                buttons
                    .controlSize(.small)
                    .transition(.opacity)
            }
            .accessibilityElement(children: .contain)

            if hasDetails {
                VStack(alignment: .leading, spacing: 4) {
                    if let statusDetail {
                        Text(statusDetail)
                            .settingsHint()
                            .accessibilityHidden(true) // already the badge's label
                            .transition(.settingsReveal)
                    }
                    if report.status != .agentNotFound {
                        Text(verbatim: path).settingsCode()
                    }
                    ForEach(notes, id: \.self) { note in
                        Text(note).settingsHint()
                    }
                    if Self.showsReplySwitch(for: report) {
                        replySwitch
                            .padding(.top, 2)
                    }
                    if let feedback {
                        feedbackLine(feedback)
                            .id(feedback.text)
                            .transition(.settingsReveal)
                    }
                }
                .padding(.leading, Self.textInset)
            }
        }
        .padding(.vertical, 8)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: report.status)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: feedback)
        .animation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion), value: notes)
    }

    /// "Let me reply from the notch": the label on the left, its switch on the trailing edge.
    private var replySwitch: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Let me reply from the notch")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paper)
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Toggle(isOn: $replies) {
                Text("Let me reply from the notch")
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .contentShape(Rectangle())
    }

    private func feedbackLine(_ feedback: AgentHooksModel.Feedback) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(feedback.isError ? Desvan.Palette.warning : Desvan.Palette.sage)
                .accessibilityHidden(true)
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

    private var hasDetails: Bool {
        statusDetail != nil || report.status != .agentNotFound || !notes.isEmpty
            || Self.showsReplySwitch(for: report) || feedback != nil
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

    /// The whole state in a sentence: the badge's accessibility label, and the hint under the name when the badge
    /// alone can't say it.
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

    /// The long sentence under the name, for the states that need explaining.
    private var statusDetail: String? {
        switch report.status {
        case .needsRepair, .unreadable: statusText
        case .notInstalled, .installed, .agentNotFound: nil
        }
    }

    private var badgeText: String {
        switch report.status {
        case .notInstalled: String(localized: "Not installed")
        case .installed: String(localized: "Installed")
        case .needsRepair(.hookMissing): String(localized: "Needs repair")
        case .needsRepair(.outdated): String(localized: "Needs update")
        case .agentNotFound: String(localized: "Not set up on this Mac")
        case .unreadable: String(localized: "Left alone")
        }
    }

    private var badgeSymbol: String? {
        switch report.status {
        case .installed: "checkmark"
        case .needsRepair, .unreadable: "exclamationmark"
        case .notInstalled, .agentNotFound: nil
        }
    }

    private var badgeTone: SettingsTone {
        switch report.status {
        case .installed: .good
        case .needsRepair, .unreadable: .warning
        case .notInstalled, .agentNotFound: .neutral
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
