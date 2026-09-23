import AltilloDesign
import SwiftUI

/// The agents tab: whoever knocks first (glowing with the bulb, Permitir / Denegar), then the rest as slim wood rows.
/// Finished sessions get a rubber stamp.
struct DesvanAgentsView: View {
    let model: NotchModel

    private var ordered: [AgentSession] {
        model.demo.agents.sorted { lhs, rhs in
            if lhs.phase.needsUser != rhs.phase.needsUser { return lhs.phase.needsUser }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    /// The notch can be as narrow as 440 pt: below this the rows drop their optional controls.
    @State private var width: CGFloat = 0
    private var isCompact: Bool { width > 0 && width < 470 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 4) {
                ForEach(ordered) { session in
                    if session.phase.needsUser {
                        DesvanWaitingCard(session: session, isCompact: isCompact)
                    } else {
                        DesvanAgentRow(session: session, isReview: model.scenario != nil, isCompact: isCompact)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }
}

/// An agent knocking on the door: who and where on top, the command below, Denegar / Permitir to the right.
/// Buttons are no-ops until phase 4 wires the hook socket.
private struct DesvanWaitingCard: View {
    let session: AgentSession
    var isCompact = false

    /// The whole sentence when there is room, then without the elapsed time, then just who and where.
    @ViewBuilder
    private func sentence(long: Bool, showsAgo: Bool) -> some View {
        let project = Text(session.project)
            .font(Desvan.Typeface.figure(12.5, weight: .medium).italic())
            .foregroundStyle(Desvan.Palette.paper)
        HStack(spacing: 6) {
            Group {
                if long {
                    Text("\(session.agent.name) wants to do something in \(project)")
                } else {
                    Text("\(session.agent.name) · \(project)")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .fixedSize()
            if showsAgo {
                Text(NotchFormat.ago(session.lastActivity))
                    .font(Desvan.Typeface.rounded(10, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, size: 16)
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    sentence(long: true, showsAgo: true)
                    sentence(long: true, showsAgo: false)
                    sentence(long: false, showsAgo: true)
                    sentence(long: false, showsAgo: false)
                }
                .help("\(session.agent.name) wants to do something in \(session.project) · \(NotchFormat.ago(session.lastActivity))")
                if let request = session.request {
                    HStack(spacing: 6) {
                        Text(request.tool)
                            .font(Desvan.Typeface.rounded(9.5, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                        Text(request.command)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Desvan.Palette.paper)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
            }
            .lineLimit(1)
            Spacer(minLength: 6)
            if !isCompact {
                DesvanKnockingHand(size: 11)
                    .help("Knock, knock: waiting for your OK")
                Button {} label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
                .help("Go to the terminal")
            }
            Button("Deny") {}
                .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 24))
            Button("Allow") {}
                .buttonStyle(DesvanButtonStyle(kind: .primary, height: 24))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 44)
        .background {
            // The bulb's light on the card.
            RadialGradient(colors: [Desvan.Palette.bulb.opacity(0.10), .clear], center: .trailing, startRadius: 0, endRadius: 240)
                .blendMode(.plusLighter)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .desvanCard(radius: 11, glow: Desvan.Palette.bulb.opacity(0.75))
    }
}

private struct DesvanAgentRow: View {
    let session: AgentSession
    let isReview: Bool
    var isCompact = false

    @State private var isHovering = false
    /// A freshly finished session wears the big stamp for 4 s, then a plain label.
    @State private var freshStamp = false
    /// Bumped to stamp again (`-demoMotion stamp`).
    @State private var stampTake = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            AgentGlyph(agent: session.agent, size: 15)
            Text(session.project)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            Text(verbatim: activity)
                .font(.system(size: 11.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(NotchFormat.ago(session.lastActivity))
                .font(Desvan.Typeface.rounded(10, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .monospacedDigit()
            status
                .frame(minWidth: isCompact ? 0 : 84, alignment: .trailing)
            Button {} label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10.5, weight: .medium))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
            .help("Go to the terminal")
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 10)
        .padding(.trailing, 2)
        .frame(height: 26)
        .desvanCard(radius: 9, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onAppear {
            guard session.phase == .finished else { return }
            let recent = Date.now.timeIntervalSince(session.lastActivity) < 4
            guard recent || isReview else { return }
            freshStamp = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                guard DesvanDebug.demoMotion != .stamp else { return }
                withAnimation(Desvan.Motion.pick(.spring(duration: 0.35, bounce: 0), reduceMotion: reduceMotion)) {
                    freshStamp = false
                }
            }
        }
        .onChange(of: DesvanDebug.clock.tick) {
            guard DesvanDebug.demoMotion == .stamp, session.phase == .finished else { return }
            freshStamp = true
            stampTake += 1
        }
    }

    private var activity: String {
        switch session.phase {
        case .finished: String(localized: "All done. \(session.activity)")
        default: session.activity
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .finished:
            DesvanRubberStamp(isFresh: freshStamp)
                .id(stampTake)
        case .working:
            HStack(spacing: 6) {
                DesvanWorkingDots()
                if !isCompact {
                    Text("Working")
                        .font(Desvan.Typeface.rounded(11, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize()
                }
            }
            .help("Working")
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(Desvan.Typeface.rounded(11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.critical)
        case .waitingAnswer, .waitingPermission:
            DesvanKnockingHand(size: 11)
        }
    }
}

/// Three small dots that take turns, like someone busy upstairs. Still with Reduce Motion.
private struct DesvanWorkingDots: View {
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
        HStack(spacing: 2.5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Desvan.Palette.bulb.opacity(index == phase ? 1 : 0.35))
                    .frame(width: 4, height: 4)
                    .animation(Desvan.Motion.pick(.easeOut(duration: 0.2), reduceMotion: reduceMotion), value: phase)
            }
        }
        .accessibilityHidden(true)
    }
}
