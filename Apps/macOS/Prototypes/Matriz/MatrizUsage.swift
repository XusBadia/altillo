import AltilloDesign
import SwiftUI

/// The usage tab as an instrument panel: per provider, an unfilled block with a 48-LED dial, the session countdown,
/// the pace line and a 40-cell weekly bar. Blocks are separated by a dotted rule, never by cards.
struct MatrizUsage: View {
    let demo: DemoContent

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(demo.usage.enumerated()), id: \.element.id) { index, usage in
                if index > 0 {
                    DotRule(axis: .vertical)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                }
                ProviderPanel(usage: usage)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
    }
}

private struct ProviderPanel: View {
    let usage: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 10)
            session
            DotRule()
                .padding(.vertical, 11)
            weekly
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(usage.agent.name.uppercased())
                .matrizLabel()
                .foregroundStyle(Matriz.Palette.phosphor)
            Text(usage.plan.uppercased())
                .matrizLabel()
                .foregroundStyle(Matriz.Palette.phosphor3)
            Spacer(minLength: 0)
        }
    }

    private var session: some View {
        let window = usage.session
        let color = Matriz.Palette.usage(window.used)
        return HStack(spacing: 16) {
            ZStack {
                DotRing(value: window.used, pace: window.expectedPace(), dot: 3)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text("\(Int((window.used * 100).rounded()))")
                        .font(Matriz.Fonts.doto(26, weight: 800))
                        .foregroundStyle(color)
                        .ledGlow(2.5, opacity: 0.5)
                    Text("%")
                        .matrizLabel()
                        .foregroundStyle(color.opacity(0.8))
                }
                .offset(x: 2, y: 1)
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 5) {
                Text("SESIÓN · 5 H")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.phosphor3)
                Text(NotchFormat.countdown(to: window.resetsAt).uppercased())
                    .font(Matriz.Fonts.departure(22))
                    .foregroundStyle(Matriz.Palette.phosphor)
                    .fixedSize()
                PaceLine(delta: window.paceDelta())
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(usage.agent.name), \(Int((window.used * 100).rounded())) por ciento de la sesión")
        .accessibilityValue("Reinicia en \(NotchFormat.countdown(to: window.resetsAt))")
    }

    private var weekly: some View {
        let window = usage.weekly
        let color = Matriz.Palette.usage(window.used)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .lastTextBaseline) {
                Text("SEMANA")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.phosphor3)
                Spacer()
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("\(Int((window.used * 100).rounded()))")
                        .font(Matriz.Fonts.doto(15, weight: 800))
                        .foregroundStyle(color)
                    Text("%").matrizLabel().foregroundStyle(color.opacity(0.8))
                }
            }
            SegmentBar(value: window.used, pace: window.expectedPace())
            HStack {
                Text("REINICIA EN \(NotchFormat.countdown(to: window.resetsAt).uppercased())")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.phosphor3)
                Spacer()
                PaceLine(delta: window.paceDelta(), compact: true)
            }
        }
        .frame(width: SegmentBar.width())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Semana, \(Int((window.used * 100).rounded())) por ciento")
    }
}

/// "↗ +9 PTS SOBRE EL RITMO" in amber; margin and on-pace stay quiet.
private struct PaceLine: View {
    let delta: Double
    var compact = false

    var body: some View {
        let points = Int((abs(delta) * 100).rounded())
        Text(text(points))
            .matrizLabel()
            .foregroundStyle(delta > 0.05 ? Matriz.Palette.amber : Matriz.Palette.phosphor2)
            .fixedSize()
    }

    private func text(_ points: Int) -> String {
        if delta > 0.05 { return compact ? "↗ +\(points) PTS" : "↗ +\(points) PTS SOBRE EL RITMO" }
        if delta < -0.05 { return compact ? "↘ CON MARGEN" : "↘ \(points) PTS DE MARGEN" }
        return "= AL RITMO"
    }
}
