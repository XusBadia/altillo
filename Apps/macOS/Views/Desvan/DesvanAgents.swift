import AltilloCore
import AltilloDesign
import SwiftUI

/// The agents tab (PLAN §5.3): whoever knocks first as a big card glowing with the bulb (what it wants, how long it
/// has waited, how long until it gives up and asks in the terminal, Allow / Deny / Go to terminal), then everyone
/// else as slim wood rows. Finished sessions get the rubber stamp and can be cleared.
///
/// Real sessions come from `AgentHub`; design scenarios show `DemoContent`'s, with buttons that do nothing. Clocks
/// only tick (`TimelineView`) while the tab is on screen.
struct DesvanAgentsView: View {
    let model: NotchModel

    /// The notch can be as narrow as 440 pt: below this the rows drop their optional words.
    @State private var width: CGFloat = 0
    /// A waiting session the user brought up from the rows ("Answer"); otherwise the card is the first waiting.
    @State private var pickedID: AgentSession.ID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isCompact: Bool { width > 0 && width < 470 }
    private var isReview: Bool { model.scenario != nil }

    var body: some View {
        let sessions = AgentsLogic.ordered(model.agentSessions)
        Group {
            if sessions.isEmpty {
                DesvanModuleNotice(
                    symbol: "hand.raised",
                    title: "Nobody's working upstairs",
                    message: "Altillo follows Claude Code, Codex, Gemini CLI, Copilot CLI, Cursor and OpenCode: when one works, asks for your OK or finishes, it shows up here.",
                    actionTitle: "Agents Settings…",
                    action: { SettingsWindowController.shared.show(tab: .modules) }
                )
            } else {
                list(sessions)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private func list(_ sessions: [AgentSession]) -> some View {
        let featured = AgentsLogic.featured(in: sessions, preferring: pickedID)
        let others = sessions.filter { $0.id != featured?.id }
        let actions = self.actions
        return ScrollView(.vertical) {
            VStack(spacing: 8) {
                if let featured {
                    DesvanAgentCard(session: featured, actions: actions, isCompact: isCompact)
                        .id(featured.id)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)),
                            removal: .opacity
                        ))
                }
                ForEach(others) { session in
                    DesvanAgentRow(session: session, actions: actions, isReview: isReview, isCompact: isCompact) {
                        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                            pickedID = session.id
                        }
                    }
                    .transition(.opacity)
                }
                if others.contains(where: { $0.source == .sessionFile }) {
                    DesvanHooksHint(action: actions.installHooks)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion),
                       value: sessions.map { "\($0.id)|\($0.phase.rawValue)|\($0.pendingRequest?.id ?? "")" })
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }

    /// What the buttons do: the hub's calls, or nothing in a design review.
    private var actions: DesvanAgentActions {
        guard !isReview else { return DesvanAgentActions() }
        let hub = model.agentHub
        return DesvanAgentActions(
            decide: { hub.decide($0, $1) },
            reply: { hub.sendReply($1, to: $0) },
            letStop: { hub.letStop($0) },
            focus: { hub.focus($0) },
            dismiss: { hub.dismiss($0) },
            installHooks: { SettingsWindowController.shared.show(tab: .modules) }
        )
    }
}

/// The tab's calls into the hub, no-ops by default (design scenarios).
@MainActor
struct DesvanAgentActions {
    var decide: (String, AgentDecision) -> Void = { _, _ in }
    /// Sends a reply typed in the notch, and says whether it went.
    var reply: (AgentSession, String) -> AgentHub.ReplyOutcome = { _, _ in .unavailable }
    /// "No, stop": lets the held stop hook go, so the agent stops now.
    var letStop: (AgentSession) -> Void = { _ in }
    var focus: (AgentSession) -> Void = { _ in }
    var dismiss: (AgentSession) -> Void = { _ in }
    var installHooks: () -> Void = {}
}

// MARK: - The card

/// An agent knocking on the door. A permission: who and where, how long it has waited and a ring counting down to
/// when the agent gives up and asks in the terminal; the tool and its command on a slip of raised wood ("Show more"
/// unfolds the rest); Deny / Allow for this session / Allow and Go to terminal. A dangerous command says so in
/// tomato and Allow has to be held for a second. A question: the start of what it asked, and Go to terminal.
private struct DesvanAgentCard: View {
    let session: AgentSession
    let actions: DesvanAgentActions
    var isCompact = false

    @State private var showsMore = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var request: AgentPermissionRequest? {
        session.phase == .waitingPermission ? session.pendingRequest : nil
    }

    /// Only hooks (or OpenCode's server) can carry an answer back; a session seen through its file is answered in
    /// the terminal.
    private var canAnswer: Bool { session.source != .sessionFile && request != nil }

    /// A reply typed here can reach the agent (a stop hook holding the turn open, or OpenCode's server).
    private func replyChannel(now: Date) -> AgentReplyChannel? {
        guard session.phase == .waitingAnswer, let channel = session.reply else { return nil }
        if !channel.isClosed, let expiry = channel.expiresAt, expiry <= now { return nil }
        return channel
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            let expired = request.map { AgentsLogic.isExpired($0, now: now) } ?? false
            HStack(alignment: .top, spacing: 10) {
                AgentGlyph(agent: session.agent, size: isCompact ? 22 : 26)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 8) {
                    header(now: now)
                    if let request {
                        slip(request)
                        if request.isDangerous, canAnswer, !expired { dangerLine }
                        if let failure = request.failure {
                            Label(failure, systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Desvan.Palette.warning)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if let message = AgentsLogic.excerpt(session.lastMessage, limit: 140) {
                        Text(verbatim: "“\(message)”")
                            .font(.system(size: 12.5).italic())
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    if let channel = replyChannel(now: now) {
                        // Go to terminal shares the quick answers' row: a row of its own pushed the card past
                        // the section's height.
                        DesvanReplyField(agentName: session.agent.name, channel: channel, now: now,
                                         send: { actions.reply(session, $0) },
                                         letStop: { actions.letStop(session) }) {
                            terminalButton(prominent: true)
                        }
                    } else {
                        buttons(expired: expired)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // The bulb's light on the card.
                RadialGradient(colors: [Desvan.Palette.bulb.opacity(0.10), .clear], center: .topTrailing,
                               startRadius: 0, endRadius: 320)
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .desvanCard(radius: 14, glow: Desvan.Palette.bulb.opacity(0.75))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel(now: now))
            .accessibilityActions { accessibilityActions(expired: expired) }
        }
    }

    // MARK: Header

    /// "Claude wants to run a command in altillo", then how long it has waited and the countdown.
    private func header(now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                sentence(long: true)
                sentence(long: false)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            HStack(spacing: 8) {
                if !isCompact || request?.expiresAt == nil {
                    DesvanKnockingHand(size: 12)
                        .help("Knock, knock: waiting for you")
                }
                Text(NotchFormat.ago(request?.requestedAt ?? session.lastActivity, now: now))
                    .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
                    .fixedSize()
                if let request, canAnswer, let left = AgentsLogic.secondsLeft(request, now: now), left > 0 {
                    DesvanCountdown(fraction: AgentsLogic.remainingFraction(request, now: now) ?? 0, seconds: left)
                }
            }
        }
    }

    private func sentence(long: Bool) -> some View {
        let project = Text(session.project)
            .font(Desvan.Typeface.figure(13.5, weight: .medium).italic())
            .foregroundStyle(Desvan.Palette.paper)
        let ask = long ? AgentsLogic.ask(for: session) : session.agent.name
        return Text("\(ask) in \(project)")
            .font(.system(size: 13.5))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Slip

    /// The tool, then what it wants to do in monospace; "Show more" unfolds the full command or the diff.
    private func slip(_ request: AgentPermissionRequest) -> some View {
        let extra = Self.more(for: request)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(request.toolName)
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                    .foregroundStyle(request.isDangerous ? Desvan.Palette.critical : Desvan.Palette.paperSecondary)
                    .fixedSize()
                Text(verbatim: request.summary)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if extra != nil {
                    Button {
                        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) {
                            showsMore.toggle()
                        }
                    } label: {
                        Text(showsMore ? "Show less" : "Show more")
                            .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
                    .accessibilityHint("Shows the whole request")
                }
            }
            if showsMore, let extra {
                ScrollView(.vertical) {
                    Text(verbatim: extra)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 96)
                .scrollIndicators(.automatic)
                .transition(.opacity)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, extra == nil ? 8 : 2)
        .padding(.vertical, 2)
        .frame(minHeight: 26)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Desvan.Palette.woodRaised))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(request.isDangerous ? Desvan.Palette.critical.opacity(0.55) : Desvan.Palette.hairlineStrong,
                              lineWidth: request.isDangerous ? 1 : 0.5)
        }
        .accessibilityElement(children: .contain)
    }

    /// What "Show more" reveals: the detail when it says more than the summary, or the summary itself when it's too
    /// long for one line.
    static func more(for request: AgentPermissionRequest) -> String? {
        let summary = request.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail = request.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty,
           detail != summary {
            return detail
        }
        return summary.count > 48 || summary.contains("\n") ? summary : nil
    }

    private var dangerLine: some View {
        Label("This one could be hard to undo. Hold Allow for a second to confirm.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Desvan.Palette.critical)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Buttons

    @ViewBuilder
    private func buttons(expired: Bool) -> some View {
        HStack(spacing: 6) {
            if canAnswer, !expired, let request {
                terminalButton(prominent: false)
                Spacer(minLength: 4)
                Button { actions.decide(request.id, .deny) } label: {
                    Text("Deny").font(Desvan.Typeface.rounded(13, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                .keyboardShortcut(".", modifiers: .command)
                .help("Deny (⌘.)")
                if request.canAllowForSession, !request.isDangerous {
                    Button { actions.decide(request.id, .allowForSession) } label: {
                        ViewThatFits(in: .horizontal) {
                            Text("Allow for this session")
                            Text("For this session")
                            Text("Session")
                        }
                        .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                    .keyboardShortcut(.return, modifiers: .option)
                    .help("Allow, and don't ask again for this in this session (⌥Return)")
                    .accessibilityLabel("Allow for this session")
                }
                if request.isDangerous {
                    DesvanHoldToAllow { actions.decide(request.id, .allow) }
                } else {
                    Button { actions.decide(request.id, .allow) } label: {
                        Text("Allow").font(Desvan.Typeface.rounded(13, weight: .semibold))
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
                    .keyboardShortcut(.defaultAction)
                    .help("Allow (Return)")
                }
            } else {
                note(expired: expired)
                Spacer(minLength: 4)
                terminalButton(prominent: true)
            }
        }
    }

    /// Why there's nothing to press here: the wait ran out, the session is only read from its file, or it asked
    /// something the terminal has to answer.
    @ViewBuilder
    private func note(expired: Bool) -> some View {
        if session.phase == .waitingPermission, session.source == .sessionFile {
            Button(action: actions.installHooks) {
                Label("Install hooks to answer from here", systemImage: "link")
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
            .help("Opens Settings › Sections, where Altillo can add its hooks to your agents")
        } else if expired {
            Text("It's asking in the terminal now")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperTertiary)
        } else if session.phase == .waitingAnswer, session.reply == nil {
            Text("Answer it in the terminal")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperTertiary)
        } else if session.phase == .waitingPermission, request == nil {
            Text("Answer it in the terminal")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperTertiary)
        }
    }

    private func terminalButton(prominent: Bool) -> some View {
        Button { actions.focus(session) } label: {
            if prominent {
                Label("Go to terminal", systemImage: "arrow.up.forward.app")
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
            } else {
                ViewThatFits(in: .horizontal) {
                    Label("Terminal", systemImage: "arrow.up.forward.app")
                    Image(systemName: "arrow.up.forward.app")
                }
                .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
            }
        }
        .buttonStyle(DesvanButtonStyle(kind: prominent ? .primary : .quiet, height: 28))
        .keyboardShortcut("t", modifiers: .command)
        .help("Go to the terminal (⌘T)")
        .accessibilityLabel("Go to terminal")
    }

    // MARK: Accessibility

    private func accessibilityLabel(now: Date) -> String {
        var parts = [String(localized: "\(AgentsLogic.ask(for: session)) in \(session.project)")]
        if let request {
            parts.append("\(request.toolName): \(request.summary)")
            if request.isDangerous { parts.append(String(localized: "Dangerous")) }
            if let left = AgentsLogic.secondsLeft(request, now: now), left > 0 {
                parts.append(String(localized: "\(Int(left.rounded(.up))) seconds left to answer here"))
            }
        } else if let message = AgentsLogic.excerpt(session.lastMessage, limit: 140) {
            parts.append(message)
        }
        parts.append(NotchFormat.ago(request?.requestedAt ?? session.lastActivity, now: now))
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func accessibilityActions(expired: Bool) -> some View {
        if canAnswer, !expired, let request {
            // A dangerous request is allowed from its own button, which asks for a second activation.
            if !request.isDangerous {
                Button("Allow") { actions.decide(request.id, .allow) }
                if request.canAllowForSession {
                    Button("Allow for this session") { actions.decide(request.id, .allowForSession) }
                }
            }
            Button("Deny") { actions.decide(request.id, .deny) }
        }
        Button("Go to terminal") { actions.focus(session) }
    }
}

/// "Reply to Claude…": a line of paper to write on, and quick answers. Return sends. While a stop hook holds the
/// turn open, the ring shows how long the agent still waits before it stops as usual, and "No, stop" lets it stop
/// now. A reply that didn't get through keeps its text here, saying so, until the session moves on.
private struct DesvanReplyField<Trailing: View>: View {
    let agentName: String
    let channel: AgentReplyChannel
    let now: Date
    let send: (String) -> AgentHub.ReplyOutcome
    let letStop: () -> Void
    /// At the end of the quick answers' row (Go to terminal).
    @ViewBuilder let trailing: () -> Trailing

    @State private var text = ""
    @State private var outcome: AgentHub.ReplyOutcome?
    @FocusState private var focused: Bool

    private static var chips: [LocalizedStringResource] { ["Continue", "Yes"] }

    private var closed: Bool { channel.isClosed || outcome == .unavailable }
    private var tooLong: Bool { text.utf8.count > AgentHub.maxReplyBytes }
    private var canSend: Bool {
        !closed && !tooLong && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField(text: $text, prompt: Text("Reply to \(agentName)…")) {
                    Text("Reply to \(agentName)")
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundStyle(closed ? Desvan.Palette.paperSecondary : Desvan.Palette.paper)
                .focused($focused)
                .onSubmit { submit(text) }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Desvan.Palette.woodRaised))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(focused ? Desvan.Palette.bulb.opacity(0.7) : Desvan.Palette.hairlineStrong,
                                      lineWidth: focused ? 1 : 0.5)
                }
                if !closed, let expiry = channel.expiresAt {
                    let total = max(expiry.timeIntervalSince(channel.openedAt), 1)
                    let left = max(expiry.timeIntervalSince(now), 0)
                    DesvanCountdown(fraction: min(max(left / total, 0), 1), seconds: left,
                                    help: "After this, it stops and you answer in the terminal")
                }
                Button { submit(text) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
                // The style doesn't dim a disabled button: without this an empty reply looks ready to send.
                .opacity(canSend ? 1 : 0.4)
                .disabled(!canSend)
                .help("Send (Return)")
                .accessibilityLabel("Send reply")
            }
            HStack(spacing: 6) {
                if !closed {
                    ForEach(Self.chips.indices, id: \.self) { index in
                        let chip = String(localized: Self.chips[index])
                        Button { submit(chip) } label: {
                            Text(verbatim: chip).font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                        }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                        .help("Reply “\(chip)”")
                    }
                    if channel.kind == .stopHook {
                        Button(action: letStop) {
                            Text("No, stop").font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                        }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                        .help("Let it stop now, without a reply")
                    }
                }
                if closed {
                    Text("It stopped waiting. Answer in the terminal.")
                        .font(.system(size: 12))
                        .foregroundStyle(Desvan.Palette.warning)
                        .lineLimit(1)
                } else if tooLong || outcome == .tooLong {
                    Text("Too long to send from here (16 KB at most).")
                        .font(.system(size: 12))
                        .foregroundStyle(Desvan.Palette.warning)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                trailing()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func submit(_ reply: String) {
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !closed else { return }
        let result = send(trimmed)
        outcome = result
        // Sent: the session moves on and the field goes. Otherwise the typed text stays.
        if result == .sent { text = "" }
    }
}

/// How long until the hook gives up: a ring that empties, and the time left. Turns tomato for the last 15 s.
private struct DesvanCountdown: View {
    let fraction: Double
    let seconds: TimeInterval
    var help: LocalizedStringKey = "After this, it asks in the terminal instead"

    var body: some View {
        let urgent = seconds <= 15
        let tint = urgent ? Desvan.Palette.critical : Desvan.Palette.bulb
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Desvan.Palette.paper.opacity(0.12), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: max(fraction, 0.001))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: fraction)
            }
            .frame(width: 13, height: 13)
            Text(verbatim: AgentsLogic.clock(seconds))
                .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                .foregroundStyle(urgent ? Desvan.Palette.critical : Desvan.Palette.paperSecondary)
                .monospacedDigit()
                .fixedSize()
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(seconds.rounded(.up))) seconds left to answer here")
    }
}

/// Allow for a dangerous request: press and hold for a second while the capsule fills with tomato (a fade with
/// Reduce Motion). A click alone only reminds how. VoiceOver activates it twice: the first arms it, the second
/// allows. Return never allows a dangerous request.
private struct DesvanHoldToAllow: View {
    let action: () -> Void

    static let hold: Double = 1

    @State private var progress: CGFloat = 0
    @State private var armed = false
    @State private var reminds = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let capsule = Capsule()
        HStack(spacing: 5) {
            Image(systemName: "hand.tap.fill").font(.system(size: 11.5, weight: .semibold))
            Text(reminds ? "Keep holding" : "Hold to allow")
        }
        .font(Desvan.Typeface.rounded(13, weight: .semibold))
        .foregroundStyle(progress > 0.5 ? Desvan.Palette.paper : Desvan.Palette.critical)
        .padding(.horizontal, 13)
        .frame(height: 28)
        .background {
            ZStack(alignment: .leading) {
                capsule.fill(Desvan.Palette.critical.opacity(0.14))
                if reduceMotion {
                    capsule.fill(Desvan.Palette.critical).opacity(progress)
                } else {
                    GeometryReader { proxy in
                        capsule.fill(Desvan.Palette.critical).frame(width: proxy.size.width * progress)
                    }
                    .clipShape(capsule)
                }
            }
        }
        .overlay { capsule.strokeBorder(Desvan.Palette.critical.opacity(0.75), lineWidth: 1) }
        .fixedSize()
        .desvanHitTarget()
        .onLongPressGesture(minimumDuration: Self.hold, maximumDistance: 24) {
            progress = 0
            action()
        } onPressingChanged: { pressing in
            if pressing {
                reminds = true
                withAnimation(.linear(duration: Self.hold)) { progress = 1 }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    reminds = false
                }
            }
        }
        .help("Dangerous: press and hold for a second to allow")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(armed ? "Allow: activate again to confirm" : "Allow, dangerous")
        .accessibilityHint("Needs two activations")
        .accessibilityAction {
            if armed {
                armed = false
                action()
            } else {
                armed = true
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    armed = false
                }
            }
        }
    }
}

// MARK: - Rows

private struct DesvanAgentRow: View {
    let session: AgentSession
    let actions: DesvanAgentActions
    let isReview: Bool
    var isCompact = false
    /// Brings a waiting session up into the card.
    let answer: () -> Void

    @State private var isHovering = false
    /// A freshly finished session wears the big stamp for 4 s, then a plain label.
    @State private var freshStamp = false
    /// Bumped to stamp again (`-demoMotion stamp`).
    @State private var stampTake = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOver: Bool { session.phase == .finished || session.phase == .failed }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                AgentGlyph(agent: session.agent, size: 22)
                Text(session.project)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: isCompact ? 92 : 150, alignment: .leading)
                if session.source == .sessionFile {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .help("Read from its session file: install hooks to answer from here")
                        .accessibilityLabel("Read from its session file")
                }
                Text(verbatim: activity)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if !isCompact || !isHovering {
                    Text(NotchFormat.ago(session.lastActivity, now: context.date))
                        .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                status
                    .frame(minWidth: isCompact ? 0 : 60, alignment: .trailing)
                trailingButtons
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 40)
            .desvanCard(radius: 12, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood)
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
            .help("\(session.agent.name) in \(session.project): \(activity)")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel(now: context.date))
            .accessibilityActions {
                if session.phase.needsUser { Button("Answer", action: answer) }
                Button("Go to terminal") { actions.focus(session) }
                if isOver { Button("Clear") { actions.dismiss(session) } }
            }
        }
        .task(id: session.phase) { await stampIfFresh() }
        .onChange(of: DesvanDebug.clock.tick) {
            guard DesvanDebug.demoMotion == .stamp, session.phase == .finished else { return }
            freshStamp = true
            stampTake += 1
        }
    }

    /// The stamp comes down when a session finishes in front of the user (or in the design review), then settles.
    private func stampIfFresh() async {
        guard session.phase == .finished else { return }
        let recent = Date.now.timeIntervalSince(session.lastActivity) < 4
        guard recent || isReview else { return }
        freshStamp = true
        try? await Task.sleep(for: .seconds(4))
        guard !Task.isCancelled, DesvanDebug.demoMotion != .stamp else { return }
        withAnimation(Desvan.Motion.pick(.spring(duration: 0.35, bounce: 0), reduceMotion: reduceMotion)) {
            freshStamp = false
        }
    }

    private var activity: String {
        let words = session.activity ?? AgentsLogic.excerpt(session.lastMessage) ?? ""
        switch session.phase {
        case .finished: return words.isEmpty ? String(localized: "All done.") : String(localized: "All done. \(words)")
        case .failed: return AgentsLogic.excerpt(session.lastMessage) ?? words
        case .waitingPermission where words.isEmpty: return AgentsLogic.ask(for: session)
        default: return words
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .finished:
            DesvanRubberStamp(isFresh: freshStamp)
                .fixedSize()
                .id(stampTake)
        case .working:
            HStack(spacing: 6) {
                DesvanWorkingDots()
                if !isCompact {
                    Text("Working")
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize()
                }
            }
            .help("Working")
        case .idle:
            Text("Idle")
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .fixedSize()
        case .failed:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.critical)
                .labelStyle(.titleAndIcon)
                .fixedSize()
        case .waitingAnswer, .waitingPermission:
            Button(action: answer) {
                HStack(spacing: 5) {
                    DesvanKnockingHand(size: 12)
                    Text("Answer")
                }
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
            }
            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
            .help("Show what it's asking")
        }
    }

    /// Go to terminal on hover (at narrow widths it takes the time's place); a finished or failed session can also
    /// be cleared.
    @ViewBuilder
    private var trailingButtons: some View {
        if !isCompact || isHovering {
            Button { actions.focus(session) } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 13.5, weight: .medium))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
            .help("Go to the terminal")
            .accessibilityLabel("Go to terminal")
            .opacity(isHovering ? 1 : 0)
            .allowsHitTesting(isHovering)
        }
        if isOver {
            Button { actions.dismiss(session) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
            .help("Clear")
            .accessibilityLabel("Clear")
            .opacity(isHovering ? 1 : 0.55)
        }
    }

    private func accessibilityLabel(now: Date) -> String {
        [
            String(localized: "\(session.agent.name) in \(session.project)"),
            session.phase.title,
            activity,
            NotchFormat.ago(session.lastActivity, now: now),
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }
}

/// Some sessions are only read from their files: a quiet way to the hooks that let Altillo answer for them.
private struct DesvanHooksHint: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text.magnifyingglass")
                Text("Install hooks to answer from here")
                Image(systemName: "chevron.forward").font(.system(size: 10, weight: .semibold))
            }
            .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
        }
        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
        .help("Sessions marked with a magnifying glass are only read from their files. Settings › Sections can add Altillo's hooks to your agents.")
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

/// Three small dots that take turns, like someone busy upstairs. Still with Reduce Motion.
struct DesvanWorkingDots: View {
    var dot: CGFloat = 5
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            dots(phase: -1)
        } else {
            TimelineView(.periodic(from: .now, by: 0.35)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
                dots(phase: phase)
            }
        }
    }

    private func dots(phase: Int) -> some View {
        HStack(spacing: dot * 0.6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Desvan.Palette.bulb.opacity(index == phase ? 1 : 0.35))
                    .frame(width: dot, height: dot)
                    .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: phase)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The agents ear: how many are working, a subtle pulse while they do, and the knocking hand when one waits.
struct DesvanAgentsEar: View {
    let counts: AgentsLogic.Counts

    var body: some View {
        HStack(spacing: 4) {
            if counts.waiting > 0 {
                DesvanKnockingHand(size: 12.5)
            } else {
                DesvanWorkingDots(dot: 3.5)
            }
            Text("\(counts.active)")
                .font(Desvan.Typeface.figure(13, weight: .medium))
                .foregroundStyle(counts.waiting > 0 ? Desvan.Palette.bulb : Desvan.Palette.paper)
                .contentTransition(.numericText(value: Double(counts.active)))
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AgentsLogic.earAccessibilityLabel(counts))
    }
}

// MARK: - Peek

/// An agent alert's left ear: the knocking hand while it waits for the user, its mark once it's done, a tomato
/// triangle when it failed.
struct DesvanAgentAlertSymbol: View {
    let alert: NotchAlert

    var body: some View {
        Group {
            if let context = alert.agent {
                switch context.kind {
                case .permission, .question:
                    DesvanKnockingHand(size: 14)
                case .finished:
                    AgentGlyph(agent: context.agent, size: 15)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.critical)
                }
            } else {
                DesvanAlertSymbol(alert: alert)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An agent alert's right ear: who's knocking, or the "Done" stamp coming down.
struct DesvanAgentAlertFigure: View {
    let context: AgentAlertContext

    var body: some View {
        Group {
            switch context.kind {
            case .finished: DesvanRubberStamp(isFresh: true)
            case .permission, .question, .failed: AgentGlyph(agent: context.agent, size: 15)
            }
        }
        .accessibilityHidden(true)
    }
}

/// An agent alert's sentence: "Knock, knock: Claude wants to run [git push] in altillo", with the command on a
/// slip and the project in italics; "Careful:" in tomato for a dangerous one. Questions and finished turns follow
/// with the first words the agent said, dimmer.
struct DesvanAgentAlertLine: View {
    let alert: NotchAlert
    /// The island has no right ear: the agent's mark goes before the sentence.
    var showsAgent = false

    private static let sentence = Font.system(size: 12.5, weight: .regular)
    private static let datum = Desvan.Typeface.figure(13.5, weight: .medium)

    var body: some View {
        HStack(spacing: 5) {
            if let context = alert.agent {
                if showsAgent { AgentGlyph(agent: context.agent, size: 14) }
                line(context)
            } else {
                Text(alert.title).font(Self.sentence)
            }
            Spacer(minLength: 8)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([alert.title, alert.detail].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private func line(_ context: AgentAlertContext) -> some View {
        let name = context.agent.name
        let project = Text(context.project).font(Self.datum.italic())
        switch context.kind {
        case let .permission(dangerous):
            Text(dangerous ? "Careful:" : "Knock, knock:")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(dangerous ? Desvan.Palette.critical : Desvan.Palette.bulb)
                .fixedSize()
            if let verb = context.verb, let object = context.object {
                Text("\(name) wants to \(verb)")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
                    .fixedSize()
                slip(object, dangerous: dangerous)
                Text("in \(project)")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
            } else {
                Text("\(name) wants your OK in \(project)")
                    .font(Self.sentence)
                    .foregroundStyle(Desvan.Palette.paper)
            }
        case .question:
            Text("\(name) is asking you something in \(project)")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paper)
                .layoutPriority(1)
            excerpt(context)
        case .finished:
            Text("\(name) finished in \(project)")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paper)
                .layoutPriority(1)
            excerpt(context)
        case .failed:
            Text("\(name) failed in \(project)")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paper)
                .layoutPriority(1)
            excerpt(context)
        }
    }

    @ViewBuilder
    private func excerpt(_ context: AgentAlertContext) -> some View {
        if let excerpt = context.excerpt {
            Text(verbatim: "· \(excerpt)")
                .font(Self.sentence)
                .foregroundStyle(Desvan.Palette.paperSecondary)
        }
    }

    private func slip(_ text: String, dangerous: Bool) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Desvan.Palette.paper)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 19)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Desvan.Palette.woodRaised))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(dangerous ? Desvan.Palette.critical.opacity(0.6) : Desvan.Palette.hairlineStrong,
                                  lineWidth: dangerous ? 1 : 0.5)
            }
    }
}

#Preview("Agents") {
    let model = NotchModel()
    model.scenario = .openAgents
    return DesvanAgentsView(model: model)
        .frame(width: 600, height: 180)
        .padding(16)
        .background(Desvan.Palette.notch)
}
