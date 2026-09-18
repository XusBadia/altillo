import AltilloDesign
import SwiftUI

/// Live agents as a departures board: PROYECTO · AGENTE · ESTADO · HACE. The row that waits for you expands with the
/// command on a well and DENEGAR / PERMITIR. Rows are written in one after another by the scanline.
struct MatrizAgents: View {
    let demo: DemoContent

    private var ordered: [AgentSession] {
        demo.agents.sorted { lhs, rhs in
            if lhs.phase.needsUser != rhs.phase.needsUser { return lhs.phase.needsUser }
            return lhs.lastActivity > rhs.lastActivity
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardRow {
                Text("PROYECTO")
            } agent: {
                Text("AGENTE")
            } state: {
                Text("ESTADO")
            } ago: {
                Text("HACE")
            }
            .matrizLabelStyle(Matriz.Palette.phosphor3)
            .frame(height: 18)

            DotRule().padding(.vertical, 5)

            ForEach(Array(ordered.enumerated()), id: \.element.id) { index, session in
                VStack(spacing: 0) {
                    AgentBoardRow(session: session)
                    if index < ordered.count - 1 {
                        DotRule(color: Matriz.Palette.dotOff).padding(.vertical, 4)
                    }
                }
                .modifier(ScanReveal(horizontal: false, delay: Double(index) * 0.05))
            }
            Spacer(minLength: 0)
        }
    }
}

/// Column layout shared by the header and the rows.
private struct BoardRow<Project: View, Agent: View, State: View, Ago: View>: View {
    @ViewBuilder var project: Project
    @ViewBuilder var agent: Agent
    @ViewBuilder var state: State
    @ViewBuilder var ago: Ago

    var body: some View {
        HStack(spacing: 0) {
            project.frame(maxWidth: .infinity, alignment: .leading)
            agent.frame(width: 84, alignment: .leading)
            state.frame(width: 128, alignment: .leading)
            ago.frame(width: 64, alignment: .trailing)
        }
    }
}

private extension View {
    func matrizLabelStyle(_ color: Color) -> some View {
        font(Matriz.Fonts.departure()).tracking(0.66).foregroundStyle(color).lineLimit(1)
    }
}

private struct AgentBoardRow: View {
    let session: AgentSession
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BoardRow {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(session.project.uppercased())
                        .font(Matriz.Fonts.departure())
                        .tracking(0.66)
                        .foregroundStyle(Matriz.Palette.phosphor)
                        .fixedSize()
                    Text(activity)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(Matriz.Palette.phosphor2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } agent: {
                Text(session.agent.name.uppercased()).matrizLabelStyle(Matriz.Palette.phosphor2)
            } state: {
                PhaseCell(phase: session.phase)
            } ago: {
                Text(ago).matrizLabelStyle(Matriz.Palette.phosphor2)
            }
            .frame(height: 20)

            if session.phase.needsUser, let request = session.request {
                HStack(spacing: 8) {
                    HStack(spacing: 10) {
                        Text(request.tool.uppercased()).matrizLabelStyle(Matriz.Palette.phosphor3)
                        Text(request.command)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Matriz.Palette.phosphor)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Matriz.Palette.panel)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Matriz.Palette.dotOff, lineWidth: 1))
                    }
                    MatrizButton(title: "TERMINAL", kind: .quiet)
                        .help("Ir a la terminal")
                    MatrizButton(title: "DENEGAR", kind: .secondary)
                    MatrizButton(title: "PERMITIR", shortcut: "⌘↩", kind: .primary)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.bottom, 2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background {
            if isHovering { RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Matriz.Palette.panelRaised.opacity(0.7)) }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.project), \(session.agent.name), \(session.phase.title)")
    }

    /// The activity without the redundant state words ("Terminado en 6 min 12 s" → "6 min 12 s").
    private var activity: String {
        switch session.phase {
        case .waitingPermission, .waitingAnswer: session.activity
        case .finished: session.activity.replacingOccurrences(of: "Terminado en ", with: "en ")
        default: session.activity
        }
    }

    private var ago: String {
        NotchFormat.ago(session.lastActivity).replacingOccurrences(of: "hace ", with: "").uppercased()
    }
}

/// LED + word: the state never depends on colour alone.
private struct PhaseCell: View {
    let phase: AgentPhase

    var body: some View {
        HStack(spacing: 7) {
            switch phase {
            case .waitingPermission, .waitingAnswer:
                BreathingLED(size: 6).frame(width: 9)
                Text("ESPERA").matrizLabelStyle(Matriz.Palette.signal)
            case .working:
                LEDSpinner(pitch: 3, dot: 2.2)
                Text("EN MARCHA").matrizLabelStyle(Matriz.Palette.phosphor)
            case .finished:
                LED(color: Matriz.Palette.phosphor, size: 6).frame(width: 9)
                Text("HECHO").matrizLabelStyle(Matriz.Palette.phosphor2)
            case .error:
                LED(color: Matriz.Palette.critical, size: 6).frame(width: 9)
                Text("ERROR").matrizLabelStyle(Matriz.Palette.critical)
            }
        }
    }
}
