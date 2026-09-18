import AltilloDesign
import SwiftUI

/// The live agents tab: the session that needs you first (with Permitir / Denegar), then the rest as compact rows.
struct AgentsView: View {
    let demo: DemoContent

    private var ordered: [AgentSession] {
        demo.agents.sorted { lhs, rhs in
            if lhs.phase.needsUser != rhs.phase.needsUser { return lhs.phase.needsUser }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ordered) { session in
                if session.phase.needsUser {
                    WaitingAgentCard(session: session)
                } else {
                    AgentRow(session: session)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// An agent blocked on you. Buttons are no-ops until phase 4 wires the hook socket.
private struct WaitingAgentCard: View {
    let session: AgentSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                AgentGlyph(agent: session.agent, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(Tokens.Typography.title)
                        .foregroundStyle(Tokens.Palette.text)
                    Text("\(session.agent.name) · \(NotchFormat.ago(session.lastActivity))")
                        .font(Tokens.Typography.caption)
                        .foregroundStyle(Tokens.Palette.textTertiary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                PhaseBadge(phase: session.phase)
            }

            if let request = session.request {
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        Text(request.tool.uppercased())
                            .font(Tokens.Typography.micro)
                            .tracking(0.5)
                            .foregroundStyle(Tokens.Palette.textTertiary)
                        Text(request.command)
                            .font(Tokens.Typography.code)
                            .foregroundStyle(Tokens.Palette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                            .overlay {
                                RoundedRectangle(cornerRadius: Tokens.Radius.small, style: .continuous)
                                    .strokeBorder(Tokens.Palette.hairline, lineWidth: 0.5)
                            }
                    }

                    Button {} label: {
                        Label("Ir a la terminal", systemImage: "arrow.up.forward.app")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(GlassButtonStyle(.plain, height: 28))
                    .help("Ir a la terminal")
                    Button("Denegar") {}
                        .buttonStyle(GlassButtonStyle(.regular, height: 28))
                    Button("Permitir") {}
                        .buttonStyle(GlassButtonStyle(.prominent, height: 28))
                }
            }
        }
        .padding(12)
        .altilloCard(radius: Tokens.Radius.large)
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.large, style: .continuous)
                .strokeBorder(Tokens.Palette.warning.opacity(0.35), lineWidth: 1)
        }
    }
}

private struct AgentRow: View {
    let session: AgentSession
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, size: 18)
            Text(session.project)
                .font(Tokens.Typography.bodyEmphasis)
                .foregroundStyle(Tokens.Palette.text)
            Text(session.activity)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(NotchFormat.ago(session.lastActivity))
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Palette.textTertiary)
                .monospacedDigit()
            PhaseBadge(phase: session.phase)
            Button {} label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(GlassButtonStyle(.plain, height: 24))
            .help("Ir a la terminal")
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 38)
        .altilloCard(radius: Tokens.Radius.base, fill: isHovering ? Tokens.Palette.elevated : Tokens.Palette.surface)
        .onHover { hovering in withAnimation(Tokens.Motion.hover) { isHovering = hovering } }
    }
}

/// State of a session as a small dot + label.
private struct PhaseBadge: View {
    let phase: AgentPhase
    @Environment(\.altilloAccent) private var accent

    var body: some View {
        HStack(spacing: 6) {
            switch phase {
            case .working:
                PulseDot(color: accent, size: 6)
            case .waitingPermission, .waitingAnswer:
                PulseDot(color: Tokens.Palette.warning, size: 6)
            case .finished:
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(Tokens.Palette.success)
            case .error:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Tokens.Palette.critical)
            }
            Text(phase.title)
                .font(Tokens.Typography.label)
                .foregroundStyle(textColor)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Capsule().fill(tint.opacity(0.12)))
    }

    private var tint: Color {
        switch phase {
        case .working: accent
        case .waitingPermission, .waitingAnswer: Tokens.Palette.warning
        case .finished: Tokens.Palette.success
        case .error: Tokens.Palette.critical
        }
    }

    private var textColor: Color {
        switch phase {
        case .finished: Tokens.Palette.textSecondary
        default: tint
        }
    }
}
