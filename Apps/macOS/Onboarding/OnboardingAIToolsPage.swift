import AltilloCore
import AppKit
import SwiftUI

/// Page 3 (with Usage or Agents on): the AI providers set up on this Mac and the coding agents installed, and an
/// honest offer: Altillo's hooks, so agents can ask for permission in the notch. Nothing is installed from here
/// without the same diff review and confirmation as Settings.
struct OnboardingAIToolsPage: View {
    let flow: OnboardingFlow
    let eyebrow: String

    private var modules: [NotchModule] { flow.settings.modules }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                OnboardingHeader(
                    eyebrow: eyebrow,
                    title: "Your AI tools",
                    subtitle: "Altillo finds them by itself, right here on your Mac. Nothing leaves it."
                )
                if !OnboardingLogic.wantsAITools(Set(modules)) {
                    Text("Usage and Agents are off in this setup. Turn them on any time: right-click the notch.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                if modules.contains(.usage) { usageCard }
                if modules.contains(.agents) { agentsCard }
            }
            .padding(.horizontal, 30)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear {
            flow.refreshHooks()
            flow.refreshUsage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            flow.refreshHooks()
        }
        .sheet(item: Bindable(flow.hooks).review) { plan in
            AgentHookReviewSheet(plan: plan, path: flow.hooks.displayPath(plan.fileURL),
                                 backups: flow.hooks.backupsPath,
                                 cancel: { flow.hooks.review = nil },
                                 confirm: { flow.hooks.confirm(plan, wait: flow.settings.agentPermissionWait) })
        }
    }

    // MARK: Usage

    private var usageCard: some View {
        let usage = flow.model.usage
        let found = usage.setUpEntries
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                cardTitle("How much you have left", symbol: "gauge.with.needle")
                Spacer(minLength: 8)
                if usage.hasChecked, !found.isEmpty {
                    Text(foundCount(found.count))
                        .font(Desvan.Typeface.figure(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                }
            }
            if !usage.hasChecked {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking around your Mac…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                .frame(minHeight: 30)
            } else if found.isEmpty {
                Text("No AI accounts on this Mac yet. Sign in to Claude Code, Codex, Cursor or another one and it shows up in the notch by itself.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                OnboardingFlowLayout(spacing: 6) {
                    ForEach(found) { entry in
                        HStack(spacing: 6) {
                            AgentGlyph(provider: entry.id, name: entry.displayName, size: 18)
                            Text(entry.displayName)
                                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                                .foregroundStyle(Desvan.Palette.paper)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Desvan.Palette.paper.opacity(0.06)))
                        .overlay(Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75))
                        .accessibilityElement(children: .combine)
                    }
                }
                Text("Their limits show in Usage, and beside the notch when they run high. Sign in to others and they join in.")
                    .settingsHint()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desvanCard(radius: 14)
    }

    private func foundCount(_ count: Int) -> String {
        count == 1 ? String(localized: "1 found") : String(localized: "\(count) found")
    }

    private func agentsFootnote(hasCodex: Bool) -> String {
        let review = String(localized: "You'll see exactly what changes before anything is written, and Settings takes it out in one click.")
        guard hasCodex else { return review }
        return review + " " + String(localized: "Codex also asks you to trust them: type /hooks in Codex.")
    }

    // MARK: Agents

    private var agentsCard: some View {
        let reports = flow.agentReports
        return VStack(alignment: .leading, spacing: 10) {
            cardTitle("Answer your agents from the notch", symbol: "hand.raised")
            if reports.isEmpty {
                Text("No Claude Code or Codex on this Mac yet. Once you have one, Settings › Sections › Agents sets it up.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Altillo already shows what your agents are doing. With its hooks they can also ask for your permission right in the notch. It never approves anything on its own.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    ForEach(reports, id: \.target) { report in
                        OnboardingAgentRow(report: report, feedback: flow.hooks.feedback[report.target]) {
                            flow.hooks.prepare(.install, for: report.target, wait: flow.settings.agentPermissionWait)
                        }
                    }
                }
                Text(agentsFootnote(hasCodex: reports.contains { $0.target == .codex }))
                    .settingsHint()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .desvanCard(radius: 14)
    }

    private func cardTitle(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.kraft)
                .accessibilityHidden(true)
            Text(title)
                .font(Desvan.Typeface.display(15, weight: 650))
                .foregroundStyle(Desvan.Palette.paper)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// One coding agent: its mark, whether its hooks are in, and "Set up…" (which opens the review first).
private struct OnboardingAgentRow: View {
    let report: AgentHookReport
    let feedback: AgentHooksModel.Feedback?
    let install: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                AgentGlyph(agent: AgentKind(rawValue: report.target.rawValue), size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.target.displayName)
                        .font(Desvan.Typeface.rounded(13, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text(statusText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(statusColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                trailing
            }
            if let feedback, feedback.isError {
                Text(feedback.text)
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 36)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Desvan.Palette.paper.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75)
                }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var trailing: some View {
        switch report.status {
        case .installed:
            OnboardingDoneLabel(text: "Ready")
        case .notInstalled:
            Button("Set Up…", action: install)
                .buttonStyle(DesvanButtonStyle(kind: .primary))
                .accessibilityLabel("Set up hooks for \(report.target.displayName)")
        case .needsRepair:
            Button("Update…", action: install)
                .buttonStyle(DesvanButtonStyle(kind: .ghost))
                .accessibilityLabel("Update hooks for \(report.target.displayName)")
        case .unreadable:
            Button("Open File") { NSWorkspace.shared.open(report.configFile) }
                .buttonStyle(DesvanButtonStyle(kind: .ghost))
        case .agentNotFound:
            EmptyView()
        }
    }

    private var statusText: String {
        switch report.status {
        case .installed: String(localized: "Hooks in. It can ask you from the notch.")
        case .notInstalled: String(localized: "Found on this Mac. Sessions already show up.")
        case .needsRepair: String(localized: "Hooks from another version: worth an update.")
        case .unreadable(let reason): String(localized: "Left alone: \(reason)")
        case .agentNotFound: ""
        }
    }

    private var statusColor: Color {
        switch report.status {
        case .installed: Desvan.Palette.done
        case .needsRepair, .unreadable: Desvan.Palette.warning
        case .notInstalled, .agentNotFound: Desvan.Palette.paperSecondary
        }
    }
}

/// Chips that wrap onto the next line when they run out of room.
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width, !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}
