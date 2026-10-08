import AltilloCore
import AltilloDesign
import SwiftUI

/// The usage tab: full-width provider rows on a shared walnut panel, with readable plans, usage bars,
/// refill dates and status sentences. Balances retain their own units; missing readings never become zeroes.
///
/// Real numbers come from `UsageStore`; design scenarios show `DemoContent`'s. Countdowns move with a `TimelineView`
/// that only exists while the tab is on screen: nothing ticks when the notch is closed.
struct DesvanUsageView: View {
    let model: NotchModel

    var body: some View {
        if model.scenario != nil {
            DesvanUsageBoard(model: model, providers: model.demo.usage, trends: [:], retry: nil)
        } else {
            live
                .onAppear { model.usage.refreshIfOlder(than: 60) }
        }
    }

    @ViewBuilder
    private var live: some View {
        let store = model.usage
        let providers = store.providers
        if !providers.isEmpty {
            DesvanUsageBoard(
                model: model,
                providers: providers,
                trends: Dictionary(uniqueKeysWithValues: providers.map { ($0.id, store.trend(for: $0.id)) }),
                retry: { store.refreshNow() }
            )
        } else if !store.hasChecked {
            DesvanModuleNotice(symbol: "gauge.with.needle", title: "Checking your AI tools…")
        } else {
            DesvanModuleNotice(
                symbol: "gauge.with.needle",
                title: "No AI usage to show yet",
                message: "Set up the AI tools you use on this Mac (Claude Code, Codex, Cursor…) and their limits show up here.",
                actionTitle: "Usage Settings…",
                action: { SettingsWindowController.shared.show(tab: .modules) }
            )
        }
    }
}

/// One shared walnut panel. Providers occupy the full width and scroll vertically when the list is taller
/// than the notch. Text owns its height; a narrower display changes the row's arrangement, never its contents.
private struct DesvanUsageBoard: View {
    let model: NotchModel
    let providers: [ProviderUsage]
    let trends: [UsageProviderID: [UsageTrendPoint]]
    let retry: (() -> Void)?

    var body: some View {
        GeometryReader { geometry in
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        ForEach(providers) { usage in
                            DesvanUsageRow(
                                usage: usage,
                                trend: trends[usage.id] ?? [],
                                now: context.date,
                                retry: retry,
                                width: max(geometry.size.width - 32, 0)
                            )
                            .padding(.vertical, 13)
                            if usage.id != providers.last?.id {
                                Rectangle()
                                    .fill(Desvan.Palette.hairlineStrong)
                                    .frame(height: 0.5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .desvanCard()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DesvanUsageRow: View {
    let usage: ProviderUsage
    let trend: [UsageTrendPoint]
    let now: Date
    let retry: (() -> Void)?
    let width: CGFloat

    /// Keep the same main limit as the former card: session first, then the provider's headline.
    private var main: UsageWindow? { usage.session ?? usage.headline }
    private var secondary: UsageWindow? {
        guard let main else { return nil }
        if main.kind != .weekly, let weekly = usage.weekly { return weekly }
        return usage.windows.filter { $0.id != main.id }.max { $0.used < $1.used }
    }
    private var isStale: Bool { usage.isStale(now: now, limit: UsageStore.staleAfter) }
    private var hasOldNumbers: Bool { isStale || usage.problem != nil }
    private var isWide: Bool { width >= 470 }
    /// Room for the longest refill line on one line, clock included.
    static let detailsMinWidth: CGFloat = 172

    var body: some View {
        Group {
            if isWide {
                HStack(alignment: .center, spacing: 18) {
                    // The name and plan need little; the refill line ("se repone en 1 h 11 min") must never wrap,
                    // so it keeps at least `detailsMinWidth` and the bar takes what's left.
                    identity
                        .frame(width: min(160, width * 0.24), alignment: .leading)
                    measurements
                        .frame(maxWidth: .infinity, alignment: .leading)
                    details
                        .frame(width: min(220, max(Self.detailsMinWidth, width * 0.32)), alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 14) {
                        identity
                            .frame(width: min(155, width * 0.42), alignment: .leading)
                        measurements
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    details
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: usage.displayName))
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentGlyph(provider: usage.id, name: usage.displayName, size: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: usage.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .fixedSize(horizontal: false, vertical: true)
                if let plan = usage.plan, !plan.isEmpty {
                    Text(verbatim: plan)
                        .font(Desvan.Typeface.rounded(11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Desvan.Palette.woodRaised))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
                }
            }
        }
    }

    @ViewBuilder
    private var measurements: some View {
        if let main {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(UsageText.name(for: main))
                        .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(NotchFormat.percent(main.used))
                        .font(Desvan.Typeface.figure(19, weight: .semibold))
                        .foregroundStyle(Desvan.usageTint(main.used))
                        .monospacedDigit()
                        .fixedSize()
                        .contentTransition(.numericText(value: main.used))
                }
                DesvanBar(value: main.used, pace: hasOldNumbers ? nil : main.elapsedFraction(now: now))
                    .accessibilityLabel("\(UsageText.name(for: main)), \(NotchFormat.percent(main.used)) used")
                if let secondary {
                    // One line always: the whole sentence when it fits, otherwise without the refill (still in
                    // the tooltip), rather than breaking "se repone / en 3 d 3 h" over two lines.
                    ViewThatFits(in: .horizontal) {
                        secondaryLine(windowSummary(secondary))
                        secondaryLine(windowSummary(secondary, includesRefill: false))
                    }
                    .help(windowHelp(secondary))
                } else if let balance = usage.balances.first {
                    balanceSummary(balance)
                }
            }
            .opacity(hasOldNumbers ? 0.85 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(UsageText.name(for: main)), \(NotchFormat.percent(main.used)) used")
            .accessibilityValue(measurementAccessibility)
        } else if let balance = usage.balances.first(where: { UsageText.figure(for: $0) != nil }) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: balance.label)
                    .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if UsageText.figure(for: balance) != nil {
                    Text(verbatim: UsageText.summary(of: balance))
                        .font(Desvan.Typeface.figure(17, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                if let spent = UsageText.spentFraction(of: balance) {
                    DesvanBar(value: spent, pace: nil)
                }
                if let next = usage.balances.first(where: { $0.id != balance.id }) {
                    balanceSummary(next)
                }
            }
            .opacity(hasOldNumbers ? 0.85 : 1)
            .accessibilityElement(children: .combine)
        } else if usage.problem == nil {
            Text("No limits to show for this plan.")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func secondaryLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Desvan.Typeface.rounded(11.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private func balanceSummary(_ balance: UsageBalance) -> some View {
        Text(verbatim: "\(balance.label) · \(UsageText.summary(of: balance))")
            .font(Desvan.Typeface.rounded(11.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let problem = usage.problem {
                DesvanUsageNote(text: UsageText.shortStatus(for: problem), tone: .warning,
                                symbol: "exclamationmark.triangle.fill")
                if main == nil, !usage.balances.contains(where: { UsageText.figure(for: $0) != nil }) {
                    Text(UsageText.sentence(for: problem, provider: usage.id,
                                           displayName: usage.displayName, now: now))
                        .font(.system(size: 12))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("These numbers are from \(NotchFormat.ago(usage.fetchedAt, now: now)).")
                        .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let retry, UsageText.canRetry(problem) {
                    Button("Try again", action: retry)
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                }
            } else if isStale {
                DesvanUsageNote(text: String(localized: "Stale · \(NotchFormat.ago(usage.fetchedAt, now: now))"),
                                tone: .warning, symbol: "clock")
            } else if let main {
                Label {
                    Text(verbatim: UsageText.refillsIn(main, now: now))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(Desvan.Typeface.rounded(12, weight: .medium))
                .foregroundStyle(Desvan.Palette.paper)
                .monospacedDigit()
                if let pace = UsageText.pace(for: main, now: now) {
                    DesvanUsageNote(text: pace.text, tone: pace.tone, symbol: nil)
                }
            }
            if trend.count > 1 {
                DesvanUsageTrend(points: trend)
                    .frame(width: 54, height: 13)
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(problemHelp)
    }

    private var problemHelp: String {
        guard let problem = usage.problem else { return "" }
        let sentence = UsageText.sentence(for: problem, provider: usage.id,
                                          displayName: usage.displayName, now: now)
        return usage.problemDetail.map { "\(sentence) \($0)" } ?? sentence
    }

    private func windowSummary(_ window: UsageWindow, includesRefill: Bool = true) -> String {
        let summary = "\(UsageText.name(for: window)) · \(NotchFormat.percent(window.used))"
        // Expired historical limits must not pretend they are currently refilling.
        guard !hasOldNumbers, includesRefill else { return summary }
        return "\(summary) · \(UsageText.refillsIn(window, now: now))"
    }

    private func windowHelp(_ window: UsageWindow) -> String {
        var parts = [windowSummary(window)]
        if !hasOldNumbers, let pace = UsageText.pace(for: window, now: now) { parts.append(pace.text) }
        return parts.joined(separator: " · ")
    }

    private var measurementAccessibility: String {
        var parts: [String] = []
        if let secondary { parts.append(windowSummary(secondary)) }
        else if let balance = usage.balances.first { parts.append("\(balance.label): \(UsageText.summary(of: balance))") }
        if hasOldNumbers {
            parts.append(String(localized: "These numbers are from \(NotchFormat.ago(usage.fetchedAt, now: now))."))
        }
        return parts.joined(separator: ". ")
    }
}

/// Status sentences wrap with the row, including full reset projections and fetch failures.
private struct DesvanUsageNote: View {
    let text: String
    let tone: UsageText.Tone
    let symbol: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(Desvan.Typeface.rounded(12, weight: .medium))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
    }

    private var color: Color {
        switch tone {
        case .calm: Desvan.Palette.paperSecondary
        case .good: Desvan.Palette.done
        case .warning: Desvan.Palette.warning
        case .critical: Desvan.Palette.critical
        }
    }
}

/// A quiet 30-day sparkline. The current reading remains the row's main figure; this only answers “which way has
/// it been moving?” and exposes the same information as a sentence to VoiceOver.
private struct DesvanUsageTrend: View {
    let points: [UsageTrendPoint]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard let first = points.first, let last = points.last else { return }
                let span = max(last.date.timeIntervalSince(first.date), 1)
                let values = points.map(\.used)
                let low = max((values.min() ?? 0) - 0.05, 0)
                let high = min(max((values.max() ?? 1) + 0.05, low + 0.1), 1)
                for (index, point) in points.enumerated() {
                    let x = point.date.timeIntervalSince(first.date) / span * proxy.size.width
                    let normalized = (min(max(point.used, low), high) - low) / max(high - low, 0.01)
                    let y = (1 - normalized) * proxy.size.height
                    if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Desvan.Palette.paperSecondary.opacity(0.75), style: StrokeStyle(lineWidth: 1.25,
                                                                                   lineCap: .round,
                                                                                   lineJoin: .round))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("30-day usage trend")
        .accessibilityValue(accessibilityValue)
        .help(accessibilityValue)
    }

    private var accessibilityValue: String {
        usageTrendSummary(points)
    }
}

private func usageTrendSummary(_ points: [UsageTrendPoint]) -> String {
    guard let first = points.first, let last = points.last else { return String(localized: "No trend yet") }
    let change = Int(((last.used - first.used) * 100).rounded())
    if change == 0 { return String(localized: "Steady over the recorded period") }
    if change > 0 { return String(localized: "Up \(change) percentage points over the recorded period") }
    return String(localized: "Down \(-change) percentage points over the recorded period")
}

/// A limit's bar on a plank-coloured track, with a small notch above it marking an even pace.
private struct DesvanBar: View {
    let value: Double
    let pace: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let clamped = min(max(value, 0), 1)
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Desvan.Palette.plank)
                    .overlay(alignment: .top) {
                        Capsule().fill(.black.opacity(0.35)).frame(height: 2.5).padding(.horizontal, 2)
                    }
                Capsule()
                    .fill(LinearGradient(
                        colors: [Desvan.usageTint(clamped), Desvan.usageTint(clamped).opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .frame(width: clamped > 0 ? min(width, max(2, width * clamped)) : 0)
                // The notch: where an even pace would be.
                if let pace {
                    let x = width * min(max(pace, 0), 1)
                    VStack(spacing: 0) {
                        Triangle()
                            .fill(Desvan.Palette.paper)
                            .frame(width: 7, height: 4)
                        Rectangle()
                            .fill(Desvan.Palette.paper)
                            .frame(width: 1.5, height: 9)
                    }
                    .shadow(color: .black.opacity(0.7), radius: 0.75)
                    .offset(x: x - 3.5, y: -2.5)
                }
            }
        }
        .frame(height: 8)
        .animation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion), value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(clamped, format: .percent.precision(.fractionLength(0))))
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                path.closeSubpath()
            }
        }
    }
}
