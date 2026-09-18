import AltilloDesign
import SwiftUI

/// The agents tab: whoever knocks first (glowing with the bulb, Permitir / Denegar), then the rest as wood rows.
/// Finished sessions get a rubber stamp.
struct DesvanAgentsView: View {
    let model: NotchModel

    private var ordered: [AgentSession] {
        model.demo.agents.sorted { lhs, rhs in
            if lhs.phase.needsUser != rhs.phase.needsUser { return lhs.phase.needsUser }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ordered) { session in
                if session.phase.needsUser {
                    DesvanWaitingCard(session: session)
                } else {
                    DesvanAgentRow(session: session, isReview: model.scenario != nil)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// An agent knocking on the door. Buttons are no-ops until phase 4 wires the hook socket.
private struct DesvanWaitingCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                AgentGlyph(agent: session.agent, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(session.agent.name) quiere hacer algo en \(Text(session.project).font(Desvan.Typeface.figure(13.5, weight: .medium).italic()).foregroundStyle(Desvan.Palette.paper))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    Text("espera tu permiso · \(NotchFormat.ago(session.lastActivity))")
                        .font(Desvan.Typeface.rounded(10.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    DesvanKnockingHand(size: 11)
                    Text("Toc, toc")
                        .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulb)
                }
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(Capsule().fill(Desvan.Palette.bulb.opacity(0.12)))
            }

            if let request = session.request {
                HStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text(request.tool)
                            .font(Desvan.Typeface.rounded(10, weight: .semibold))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                        Text(request.command)
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Desvan.Palette.paper)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Desvan.Palette.woodRaised)
                            .overlay {
                                // A shallow well: shadow at the top edge.
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(colors: [.black.opacity(0.5), Desvan.Palette.hairline],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: 1
                                    )
                            }
                    }

                    Button {} label: {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
                    .help("Ir a la terminal")
                    Button("Denegar") {}
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                    Button("Permitir") {}
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
                }
            }
        }
        .padding(12)
        .background {
            // The bulb's light on the card.
            RadialGradient(colors: [Desvan.Palette.bulb.opacity(0.10), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                .blendMode(.plusLighter)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .desvanCard(glow: Desvan.Palette.bulb.opacity(0.75))
    }
}

private struct DesvanAgentRow: View {
    let session: AgentSession
    let isReview: Bool

    @State private var isHovering = false
    /// A freshly finished session wears the big stamp for 4 s, then a plain label.
    @State private var freshStamp = false

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, size: 18)
            Text(session.project)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            Text(activity)
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(NotchFormat.ago(session.lastActivity))
                .font(Desvan.Typeface.rounded(10.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .monospacedDigit()
            status
                .frame(minWidth: 84, alignment: .trailing)
            Button {} label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
            .help("Ir a la terminal")
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 38)
        .desvanCard(radius: 12, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onAppear {
            guard session.phase == .finished else { return }
            let recent = Date.now.timeIntervalSince(session.lastActivity) < 4
            guard recent || isReview else { return }
            freshStamp = true
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.spring(duration: 0.35, bounce: 0)) { freshStamp = false }
            }
        }
    }

    private var activity: String {
        switch session.phase {
        case .finished: "Listo. " + session.activity.replacingOccurrences(of: "Terminado", with: "Terminó")
        default: session.activity
        }
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .finished:
            DesvanRubberStamp(isFresh: freshStamp)
        case .working:
            HStack(spacing: 6) {
                DesvanWorkingDots()
                Text("Trabajando")
                    .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
        case .error:
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
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
                    .animation(.easeOut(duration: 0.2), value: phase)
            }
        }
        .accessibilityHidden(true)
    }
}
