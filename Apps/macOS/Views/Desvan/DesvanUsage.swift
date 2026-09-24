import AltilloCore
import AltilloDesign
import SwiftUI

/// The usage tab: one wood card per provider. The limit that matters most as a ring with its figure (the session, or
/// for providers without one the fullest limit they have: a month, a request quota), the plan, when it refills and
/// the pace in italics ("Runs out at 16:40"), and the next limit's bar underneath with a notch where an even pace
/// would be, or a balance ("$7.50 left") when there's no other limit. A provider with only balances (prepaid credits)
/// shows the balance as the figure. A provider in trouble says so in one sentence, with a way out when there is one.
///
/// Real numbers come from `UsageStore`; design scenarios show `DemoContent`'s. Countdowns move with a `TimelineView`
/// that only exists while the tab is on screen: nothing ticks when the notch is closed.
struct DesvanUsageView: View {
    let model: NotchModel

    var body: some View {
        if model.scenario != nil {
            DesvanUsageBoard(model: model, providers: model.demo.usage, retry: nil)
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
            DesvanUsageBoard(model: model, providers: providers, retry: { store.refreshNow() })
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

/// The cards side by side; with three or more providers they scroll sideways, two and a bit at a time, settling on
/// a card's edge.
private struct DesvanUsageBoard: View {
    let model: NotchModel
    let providers: [ProviderUsage]
    let retry: (() -> Void)?

    @State private var width: CGFloat = 0
    private static let spacing: CGFloat = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if providers.count <= 2 {
                HStack(spacing: Self.spacing) {
                    ForEach(providers) { usage in
                        DesvanUsageCard(usage: usage, now: context.date, retry: retry)
                    }
                }
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: Self.spacing) {
                        ForEach(providers) { usage in
                            DesvanUsageCard(usage: usage, now: context.date, retry: retry)
                                .frame(width: cardWidth)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.never)
                .scrollClipDisabled()
                // A swipe over the cards scrolls them; it never changes section.
                .reportsHorizontalScroll(id: "usage.cards", model: model)
            }
        }
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    /// Two cards and the edge of the next, so it's clear there are more.
    private var cardWidth: CGFloat {
        guard width > 0 else { return 220 }
        return max(200, ((width - 2 * Self.spacing) / 2.25).rounded())
    }
}

private struct DesvanUsageCard: View {
    let usage: ProviderUsage
    let now: Date
    let retry: (() -> Void)?

    /// The card measures itself: its ring shrinks with it, and each line drops what it can't hold (the window's
    /// length first, then the plan chip, "refills", the week's name). The notch can be as narrow as 440 pt, which
    /// leaves ~190 pt per provider.
    @State private var width: CGFloat = 0
    private var isRoomy: Bool { width <= 0 || width >= 300 }

    private static let inset: CGFloat = 14

    /// The ring: 100 pt when the card has room, down to 64 pt in the narrowest notch. With the week's row under it,
    /// 100 + 10 + 17 fits the card's 132 pt inside (usage content 160 minus the insets).
    private var ringSide: CGFloat {
        guard width > 0 else { return 100 }
        return min(100, max(64, ((width - 2 * Self.inset) * 0.36).rounded()))
    }

    /// The limit the ring shows: the session when there is one, otherwise the headline (the week, or for a
    /// provider without either the fullest limit it has).
    private var main: UsageWindow? { usage.session ?? usage.headline }
    /// The row underneath: the week, or the fullest other limit there is.
    private var secondary: UsageWindow? {
        guard let main else { return nil }
        if main.kind != .weekly, let weekly = usage.weekly { return weekly }
        return usage.windows.filter { $0.id != main.id }.max { $0.used < $1.used }
    }

    private var isStale: Bool { usage.isStale(now: now, limit: UsageStore.staleAfter) }

    var body: some View {
        Group {
            if let main {
                VStack(alignment: .leading, spacing: 0) {
                    ring(main)
                    Spacer(minLength: 10)
                    if let secondary {
                        bar(secondary)
                    } else if let balance = usage.balances.first {
                        balanceRow(balance)
                    }
                }
            } else if let balance = usage.balances.first(where: { UsageText.figure(for: $0) != nil }) {
                balanceOnly(balance)
            } else {
                problemOnly
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .desvanCard()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    // MARK: Header (glyph, name, plan)

    /// The name, then the plan chip and the window's length while they fit.
    private func title(showsLength window: UsageWindow?) -> some View {
        ViewThatFits(in: .horizontal) {
            titleRow(plan: true, length: window)
            titleRow(plan: true, length: nil)
            titleRow(plan: false, length: nil)
        }
    }

    private func titleRow(plan showsPlan: Bool, length window: UsageWindow?) -> some View {
        HStack(spacing: 6) {
            AgentGlyph(provider: usage.id, name: usage.displayName, size: 18)
            Text(usage.displayName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
                .fixedSize()
            if showsPlan, let plan = usage.plan, !plan.isEmpty {
                Text(plan)
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 19)
                    .background(Capsule().fill(Desvan.Palette.woodRaised))
                    .overlay(Capsule().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5))
                    .fixedSize()
            }
            if let window, let length = UsageText.length(of: window) {
                Spacer(minLength: 4)
                Text(verbatim: length)
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .fixedSize()
                    .help(String(localized: "\(UsageText.name(for: window)): \(length)"))
            }
        }
    }

    // MARK: Ring

    private func ring(_ window: UsageWindow) -> some View {
        let used = window.used
        let side = ringSide
        return HStack(spacing: 14) {
            DesvanRing(value: used, lineWidth: max(4, (side * 0.06).rounded()), pace: window.elapsedFraction(now: now)) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((min(max(used, 0), 1) * 100).rounded()))")
                        .font(Desvan.Typeface.figure((side * 0.28).rounded(), weight: .semibold))
                        .contentTransition(.numericText(value: used))
                    Text("%")
                        .font(Desvan.Typeface.figure(max(10.5, (side * 0.14).rounded()), weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }
                .foregroundStyle(Desvan.Palette.paper)
                .offset(x: 1)
            }
            .frame(width: side, height: side)
            .opacity(isStale ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 4) {
                title(showsLength: window)
                ViewThatFits(in: .horizontal) {
                    refill(UsageText.refillsIn(window, now: now))
                    refill(compactRefill(window))
                }
                .help(UsageText.refillsIn(window, now: now))
                status(pace: window)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func refill(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Desvan.Typeface.rounded(13.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.paper.opacity(0.85))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }

    private func compactRefill(_ window: UsageWindow) -> String {
        guard let resetsAt = window.resetsAt else {
            return window.kind == .session ? String(localized: "not started") : String(localized: "no date")
        }
        return String(localized: "in \(NotchFormat.countdown(to: resetsAt, now: now))")
    }

    /// The pace in italics (for a limit), or, when the numbers aren't fresh, why ("Unreachable · 20 min ago").
    @ViewBuilder
    private func status(pace window: UsageWindow?) -> some View {
        if let problem = usage.problem {
            let sentence = UsageText.sentence(for: problem, provider: usage.id, displayName: usage.displayName, now: now)
            DesvanUsageNote(
                text: isRoomy
                    ? "\(UsageText.shortStatus(for: problem)) · \(NotchFormat.ago(usage.fetchedAt, now: now))"
                    : UsageText.shortStatus(for: problem),
                tone: .warning, symbol: "exclamationmark.triangle.fill"
            )
            .help(usage.problemDetail.map { "\(sentence) \($0)" } ?? sentence)
        } else if isStale {
            DesvanUsageNote(text: String(localized: "Stale · \(NotchFormat.ago(usage.fetchedAt, now: now))"),
                            tone: .warning, symbol: "clock")
                .help("These numbers are from \(NotchFormat.ago(usage.fetchedAt, now: now)).")
        } else if let window, let pace = UsageText.pace(for: window, now: now) {
            DesvanUsageNote(text: pace.text, tone: pace.tone, symbol: nil)
        }
    }

    // MARK: Bar

    /// One line: the week's bar, its figure and when it refills; the name and the countdown give way first.
    private func bar(_ window: UsageWindow) -> some View {
        ViewThatFits(in: .horizontal) {
            barRow(window, label: true, countdown: true)
            barRow(window, label: true, countdown: false)
            barRow(window, label: false, countdown: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isStale ? 0.6 : 1)
        .help(barHelp(window))
        .accessibilityElement(children: .combine)
    }

    private func barRow(_ window: UsageWindow, label: Bool, countdown: Bool) -> some View {
        HStack(spacing: 8) {
            if label {
                Text(UsageText.name(for: window))
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            DesvanBar(value: window.used, pace: window.elapsedFraction(now: now))
                .frame(minWidth: 96)
            Text(NotchFormat.percent(window.used))
                .font(Desvan.Typeface.figure(14, weight: .medium))
                .foregroundStyle(Desvan.usageTint(window.used))
                .monospacedDigit()
                .fixedSize()
            if countdown, let resetsAt = window.resetsAt {
                Text(NotchFormat.countdown(to: resetsAt, now: now))
                    .font(Desvan.Typeface.rounded(12.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .lineLimit(1)
    }

    private func barHelp(_ window: UsageWindow) -> String {
        var parts = ["\(UsageText.name(for: window)): \(UsageText.refillsIn(window, now: now))"]
        if let pace = UsageText.pace(for: window, now: now) { parts.append(pace.text) }
        return parts.joined(separator: " · ")
    }

    // MARK: Balances

    /// A balance on one line, under the ring when there's no second limit: "Credits  $7.50 left".
    private func balanceRow(_ balance: UsageBalance) -> some View {
        ViewThatFits(in: .horizontal) {
            balanceLine(balance, label: true)
            balanceLine(balance, label: false)
        }
        .fixedSize(horizontal: false, vertical: true)
        .opacity(isStale ? 0.6 : 1)
        .help("\(balance.label): \(UsageText.summary(of: balance))")
        .accessibilityElement(children: .combine)
    }

    private func balanceLine(_ balance: UsageBalance, label: Bool) -> some View {
        HStack(spacing: 8) {
            if label {
                Text(verbatim: balance.label)
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let spent = UsageText.spentFraction(of: balance) {
                DesvanBar(value: spent, pace: nil)
                    .frame(minWidth: 60)
            } else {
                Spacer(minLength: 0)
            }
            Text(verbatim: UsageText.summary(of: balance))
                .font(Desvan.Typeface.figure(14, weight: .medium))
                .foregroundStyle(Desvan.Palette.paper)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .lineLimit(1)
    }

    /// No limit to draw a ring with, only balances (prepaid credits, dollars left): the first one as the figure,
    /// its bar when it has a limit, and the next balance underneath.
    private func balanceOnly(_ balance: UsageBalance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title(showsLength: nil)
            Text(verbatim: balance.label)
                .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .lineLimit(1)
                .padding(.top, 4)
            if let figure = UsageText.figure(for: balance) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: figure.value)
                        .font(Desvan.Typeface.figure(30, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .contentTransition(.numericText())
                    Text(verbatim: figure.caption)
                        .font(Desvan.Typeface.rounded(13.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(1)
                }
                .opacity(isStale ? 0.6 : 1)
            }
            status(pace: nil)
            Spacer(minLength: 0)
            if let next = usage.balances.first(where: { $0.id != balance.id }) {
                balanceRow(next)
            } else if let spent = UsageText.spentFraction(of: balance) {
                DesvanBar(value: spent, pace: nil)
                    .opacity(isStale ? 0.6 : 1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: No numbers at all

    /// Nothing to draw a ring with: what's wrong, in one sentence, and "Try again" when it can help.
    private var problemOnly: some View {
        VStack(alignment: .leading, spacing: 8) {
            title(showsLength: nil)
            if let problem = usage.problem {
                Text(UsageText.sentence(for: problem, provider: usage.id, displayName: usage.displayName, now: now))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(usage.problemDetail ?? "")
                Spacer(minLength: 0)
                if let retry, UsageText.canRetry(problem) {
                    Button("Try again", action: retry)
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                }
            } else {
                Text("No limits to show for this plan.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// The line under the countdown, in SF Pro Rounded italic: the pace, or what's off with the numbers.
private struct DesvanUsageNote: View {
    let text: String
    let tone: UsageText.Tone
    let symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
            }
            Text(verbatim: text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded).italic())
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .lineLimit(1)
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
                    .frame(width: max(8, width * clamped))
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
