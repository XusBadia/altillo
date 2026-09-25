import SwiftUI

/// Page 5: the few gestures and keys that bring Altillo to you, and "Open Altillo at login" (on by default here,
/// written only when the user leaves the page or finishes).
struct OnboardingTricksPage: View {
    @Bindable var flow: OnboardingFlow
    let eyebrow: String

    private struct Trick: Identifiable {
        let id: String
        let keys: [String]
        let symbol: String?
        let title: String
        let detail: String
    }

    private var tricks: [Trick] {
        var tricks: [Trick] = []
        let settings = flow.settings
        if settings.modules.contains(.assistant), settings.assistantHotKey != .off {
            tricks.append(Trick(id: "ask", keys: [settings.assistantHotKey.title], symbol: nil,
                                title: String(localized: "Ask anything"),
                                detail: String(localized: "Opens Ask from any app, ready to type.")))
        }
        tricks.append(Trick(id: "keep", keys: [], symbol: "arrow.up.doc",
                            title: String(localized: "Keep a file up there"),
                            detail: String(localized: "Drag it to the notch and let go. Drag it out when you need it.")))
        if settings.modules.count > 1 {
            tricks.append(Trick(id: "swipe", keys: [], symbol: "hand.draw",
                                title: String(localized: "Swipe between sections"),
                                detail: String(localized: "Two fingers sideways on the open notch.")))
            tricks.append(Trick(id: "jump", keys: ["⌘1", "…", "⌘9"], symbol: nil,
                                title: String(localized: "Jump to a section"),
                                detail: String(localized: "With the notch open, in the order of its tabs.")))
        }
        tricks.append(Trick(id: "customize", keys: [], symbol: "cursorarrow.click.2",
                            title: String(localized: "Make it yours"),
                            detail: String(localized: "Right-click the notch to rearrange sections and ears.")))
        return tricks
    }

    var body: some View {
        // Scrolls only if a translation runs longer than the page.
        ScrollView(.vertical) {
            content
                .padding(.horizontal, 30)
                .padding(.top, 18)
                .padding(.bottom, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            OnboardingHeader(
                eyebrow: eyebrow,
                title: "A few tricks",
                subtitle: "Altillo stays out of the way until you want it. These bring it to you."
            )

            VStack(spacing: 0) {
                ForEach(Array(tricks.enumerated()), id: \.element.id) { index, trick in
                    if index > 0 {
                        Rectangle().fill(Desvan.Palette.hairline).frame(height: 0.75)
                            .padding(.leading, 120)
                    }
                    trickRow(trick)
                }
            }
            .desvanCard(radius: 14)

            loginCard
        }
    }

    private func trickRow(_ trick: Trick) -> some View {
        HStack(spacing: 14) {
            Group {
                if let symbol = trick.symbol {
                    OnboardingSymbolTile(symbol: symbol, size: 28)
                } else {
                    HStack(spacing: 3) {
                        ForEach(trick.keys, id: \.self) { key in
                            if key == "…" {
                                Text(verbatim: key)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Desvan.Palette.paperTertiary)
                            } else {
                                OnboardingKeycap(label: key)
                            }
                        }
                    }
                }
            }
            .frame(width: 92, alignment: .leading)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(trick.title)
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(trick.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(trick.keys.filter { $0 != "…" }.joined(separator: " ")))
    }

    private var loginCard: some View {
        HStack(spacing: 14) {
            OnboardingSymbolTile(symbol: "power", tint: Desvan.Palette.bulb, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text("Open Altillo at login")
                    .font(Desvan.Typeface.rounded(13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(flow.settings.launchAtLoginProblem
                     ?? String(localized: "A notch app is best when it's always there. It uses next to nothing while you don't need it."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(flow.settings.launchAtLoginProblem == nil
                                     ? Desvan.Palette.paperSecondary : Desvan.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("Open Altillo at login", isOn: $flow.launchAtLogin)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(14)
        .desvanCard(radius: 14)
    }
}
