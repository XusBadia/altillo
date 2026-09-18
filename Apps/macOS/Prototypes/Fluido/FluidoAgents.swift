import AltilloDesign
import SwiftUI

/// The agents tab: the session that needs you, edged in breathing lime light, then the rest as quiet rows.
struct FluidoAgentsView: View {
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
                    FluidoWaitingCard(session: session)
                        .padding(.bottom, 2)
                } else {
                    FluidoAgentRow(session: session)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// An agent blocked on you. "Permitir" and "Denegar" grow out of the status chip (one glass container); allowing
/// melts the buttons back into the chip, which turns into "Hecho".
private struct FluidoWaitingCard: View {
    let session: AgentSession

    @State private var resolved: Resolution?
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Resolution { case allowed, denied }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluido.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                AgentGlyph(agent: session.agent, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(Fluido.Typography.title)
                        .foregroundStyle(Fluido.Palette.text)
                    Text("\(session.agent.name) te necesita")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Fluido.Palette.textSecondary)
                }
                Spacer(minLength: 8)
                Text(NotchFormat.ago(session.lastActivity))
                    .font(Fluido.Typography.countdown)
                    .foregroundStyle(Fluido.Palette.textTertiary)
            }
            if let request = session.request {
                command(request)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .inkWell()
        .overlay {
            FluidoEdgeLight(shape: shape, light: resolved == .denied ? .critical : .agents, breathes: resolved == nil)
        }
    }

    private func command(_ request: PermissionRequest) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(request.tool)
                    .font(Fluido.Typography.micro)
                    .foregroundStyle(Fluido.Palette.textTertiary)
                Text(request.command)
                    .font(Fluido.Typography.code)
                    .foregroundStyle(Fluido.Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black)
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Fluido.Palette.hairline, lineWidth: 0.75))
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 6) {
                    if let resolved {
                        Label(resolved == .allowed ? "Hecho" : "Denegado",
                              systemImage: resolved == .allowed ? "checkmark" : "xmark")
                            .labelStyle(DoneLabelStyle(drawsOn: !reduceMotion))
                            .font(.system(size: 11.5, weight: .semibold).width(.expanded))
                            .foregroundStyle(Fluido.Palette.text)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .fluidoGlass(Capsule(), light: resolved == .allowed ? .agents : .critical, tint: 0.8, interactive: false)
                            .glassEffectID("status", in: glass)
                    } else {
                        Button("Denegar") { resolve(.denied) }
                            .buttonStyle(FluidoButtonStyle(height: 28))
                            .glassEffectID("deny", in: glass)
                        Button("Permitir") { resolve(.allowed) }
                            .buttonStyle(FluidoButtonStyle(light: .agents, height: 28))
                            .glassEffectID("status", in: glass)
                    }
                }
            }
        }
    }

    private func resolve(_ resolution: Resolution) {
        withAnimation(reduceMotion ? Fluido.Motion.reduced : .spring(duration: 0.5, bounce: 0.3)) { resolved = resolution }
    }
}

/// A checkmark that draws itself on (SF Symbols 7 `.drawOn`).
private struct DoneLabelStyle: LabelStyle {
    var drawsOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Fluido.Light.agents.linear(.top, .bottom))
                .transition(.symbolEffect(.drawOn))
            configuration.title
        }
    }
}

/// A card's edge lit from inside with a module's light, breathing 0.35 ↔ 0.9 over 2.4 s while it waits.
struct FluidoEdgeLight<S: InsettableShape>: View {
    var shape: S
    var light: Fluido.Light
    var breathes: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if breathes && !reduceMotion {
                PhaseAnimator([0.35, 0.9]) { phase in
                    edge.opacity(phase)
                } animation: { _ in .easeInOut(duration: 1.2) }
            } else {
                edge.opacity(breathes ? 0.8 : 0.6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var edge: some View {
        let gradient = light.linear(.topLeading, .bottomTrailing)
        return ZStack {
            shape.strokeBorder(gradient, lineWidth: 1.5)
            shape.strokeBorder(gradient, lineWidth: 5)
                .blur(radius: 6)
                .blendMode(.plusLighter)
                .clipShape(shape)
        }
    }
}

// MARK: - Rows

private struct FluidoAgentRow: View {
    let session: AgentSession
    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            AgentGlyph(agent: session.agent, size: 18)
            Text(session.project)
                .font(.system(size: 12, weight: .semibold).width(.expanded))
                .foregroundStyle(Fluido.Palette.text)
            Text(activity)
                .font(.system(size: 12, weight: .regular).width(.condensed))
                .foregroundStyle(Fluido.Palette.textSecondary)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(NotchFormat.ago(session.lastActivity))
                .font(Fluido.Typography.countdown)
                .foregroundStyle(Fluido.Palette.textTertiary)
            status
                .frame(width: 22)
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 40)
        .background(alignment: .bottomLeading) {
            if let progress {
                // Data as decoration: the run's progress, a thread of light along the row's floor.
                GeometryReader { proxy in
                    Capsule()
                        .fill(Fluido.Light.agents.linear(.leading, .trailing))
                        .frame(width: proxy.size.width * progress, height: 1.5)
                        .shadow(color: Fluido.Light.agents.to.opacity(0.8), radius: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 0.5)
            }
        }
        .inkWell(radius: 14, fill: isHovering ? Fluido.Palette.ink2 : Fluido.Palette.ink1)
        .onHover { hovering in withAnimation(Fluido.Motion.hover(reduceMotion)) { isHovering = hovering } }
        .accessibilityElement(children: .combine)
    }

    /// "Hecho en 6 min." for finished runs, the live activity otherwise.
    private var activity: String {
        if session.phase == .finished {
            let minutes = session.activity.split(separator: " ").dropFirst(2).first.map(String.init) ?? ""
            return minutes.isEmpty ? "Hecho." : "Hecho en \(minutes) min."
        }
        return session.activity
    }

    /// "42 de 118" → 0.36.
    private var progress: Double? {
        guard session.phase == .working else { return nil }
        let numbers = session.activity.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        guard numbers.count >= 2, numbers[1] > 0 else { return nil }
        return min(numbers[0] / numbers[1], 1)
    }

    @ViewBuilder
    private var status: some View {
        switch session.phase {
        case .working:
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(Fluido.Light.agents.linear(.leading, .trailing))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous), isActive: !reduceMotion)
        case .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Fluido.Light.agents.linear(.top, .bottom))
        case .error:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Fluido.Light.critical.linear(.top, .bottom))
        case .waitingPermission, .waitingAnswer:
            LightDot(light: .agents, size: 6, breathes: true)
        }
    }
}
