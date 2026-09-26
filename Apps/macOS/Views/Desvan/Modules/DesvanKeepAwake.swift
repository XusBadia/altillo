import AltilloDesign
import SwiftUI

/// An explicit, temporary switch that prevents idle system sleep. It never prevents display sleep and never
/// resumes by itself after launch.
struct DesvanKeepAwakeView: View {
    let model: NotchModel

    private var store: KeepAwakeStore { model.keepAwake }

    var body: some View {
        VStack(spacing: 14) {
            status
            if store.isActive {
                Button("Stop") { store.end() }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 30))
                    .keyboardShortcut(.cancelAction)
            } else {
                HStack(spacing: 8) {
                    ForEach(KeepAwakeDuration.allCases) { duration in
                        Button(duration.title) { store.begin(duration) }
                            .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 30))
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 16)
    }

    private var status: some View {
        VStack(spacing: 7) {
            Image(systemName: store.isActive ? "cup.and.heat.waves.fill" : "cup.and.heat.waves")
                .font(.system(size: 28, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(store.isActive ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                .contentTransition(.symbolEffect(.replace))
            Text(store.isActive ? "Your Mac will stay awake" : "Keep your Mac awake")
                .font(Desvan.Typeface.display(16, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        if let end = store.endsAt {
            return String(localized: "Until \(end.formatted(date: .omitted, time: .shortened)). The display can still turn off.")
        }
        if store.isActive {
            return String(localized: "Until you stop it. The display can still turn off.")
        }
        return String(localized: "Choose a duration. It won't turn itself on again after you quit Altillo.")
    }
}
