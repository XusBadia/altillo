import SwiftUI

/// The welcome window: the progress bars in the title bar, the page, and Skip / Back / Continue along the bottom.
/// Return continues, Esc skips (no confirmation: skipping only closes the window, it can come back from the menu).
struct OnboardingRootView: View {
    @Bindable var flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(steps: flow.steps, current: flow.step)
                .frame(height: 28)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomBar
        }
        .ignoresSafeArea()
        .onChange(of: flow.step) { _, step in
            // VoiceOver hears where it is now; the page's own title follows.
            AccessibilityNotification.Announcement(
                "\(OnboardingText.position(of: step, in: flow.steps)): \(step.title)"
            ).post()
        }
        .tint(Desvan.Palette.bulb)
        .background(SettingsBackdrop())
        .environment(\.colorScheme, .dark)
    }

    private var page: some View {
        ZStack {
            pageContent
                .id(flow.step)
                .transition(OnboardingPageTransition(direction: flow.direction, reduceMotion: reduceMotion))
        }
        .animation(Desvan.Motion.pick(.spring(duration: 0.38, bounce: 0.1), reduceMotion: reduceMotion),
                   value: flow.step)
    }

    @ViewBuilder
    private var pageContent: some View {
        let eyebrow = OnboardingText.position(of: flow.step, in: flow.steps)
        switch flow.step {
        case .hello: OnboardingHelloPage(flow: flow)
        case .preset: OnboardingPresetPage(flow: flow, eyebrow: eyebrow)
        case .aiTools: OnboardingAIToolsPage(flow: flow, eyebrow: eyebrow)
        case .permissions: OnboardingPermissionsPage(flow: flow, eyebrow: eyebrow)
        case .tricks: OnboardingTricksPage(flow: flow, eyebrow: eyebrow)
        case .done: OnboardingDonePage(flow: flow)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if flow.isLast {
                // Esc on the last page closes too, as Start would.
                Button("Close") { flow.finish() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            } else {
                Button("Skip") { flow.finish() }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 30))
                    .keyboardShortcut(.cancelAction)
                    .help("Close the welcome. You can open it again from Altillo's menu or Settings › About.")
                    .accessibilityHint("Closes the welcome. Open it again from Altillo's menu.")
            }
            Spacer(minLength: 0)
            if !flow.isFirst {
                Button("Back") { flow.back() }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 30))
                    .keyboardShortcut("[", modifiers: .command)
            }
            Button(flow.isLast ? "Start" : "Continue") { flow.next() }
                .buttonStyle(DesvanButtonStyle(kind: .primary, height: 30))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background {
            Rectangle()
                .fill(Color.black.opacity(0.16))
                .overlay(alignment: .top) {
                    Rectangle().fill(Desvan.Palette.hairline).frame(height: 0.75)
                }
        }
    }
}

/// Pages slide a little towards where you're going and fade; with Reduce Motion they only fade.
struct OnboardingPageTransition: Transition {
    let direction: Int
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let distance: CGFloat = reduceMotion ? 0 : 36
        let offset: CGFloat = switch phase {
        case .willAppear: CGFloat(direction) * distance
        case .didDisappear: CGFloat(-direction) * distance
        case .identity: 0
        }
        content
            .offset(x: offset)
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity || reduceMotion ? 0 : 3)
    }
}
