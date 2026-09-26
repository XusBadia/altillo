import AltilloCore
import SwiftUI

/// Page 1: what Altillo is in one sentence, then the first real moment with it: an arrow pointing up at the notch.
/// When the user opens the notch for real, the card celebrates quietly and the welcome moves on by itself.
struct OnboardingHelloPage: View {
    let flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var greetingProgress: CGFloat = 0

    private var model: NotchModel { flow.model }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            AltilloGreeting(progress: greetingProgress)
                .frame(width: 300, height: 110)
                .background {
                    DesvanBulbGlow(intensity: flow.sawNotchOpen ? 0.12 : 0.07, radius: 120, originY: 150)
                        .frame(width: 420, height: 240)
                }
                .animation(Desvan.Motion.pick(.easeInOut(duration: 0.3), reduceMotion: reduceMotion),
                           value: flow.sawNotchOpen)

            VStack(spacing: 8) {
                Text("Welcome to your altillo")
                    .font(Desvan.Typeface.display(28, weight: 700))
                    .foregroundStyle(Desvan.Palette.paper)
                    .accessibilityAddTraits(.isHeader)
                Text("Altillo turns the notch into a place up top: leave things there for a moment, and see what matters without leaving what you're doing.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 440)
            }
            .padding(.top, 6)

            Spacer(minLength: 18)

            tryItCard
                .frame(maxWidth: 460)

            Spacer(minLength: 22)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { flow.notchStateChanged(model.state) }
        .onChange(of: model.state) { _, state in flow.notchStateChanged(state) }
        .task {
            let shouldPlay = flow.claimGreetingAnimation()
            guard !reduceMotion, shouldPlay else {
                greetingProgress = 1
                return
            }
            withAnimation(.linear(duration: 2)) { greetingProgress = 1 }
        }
        .onChange(of: reduceMotion) { _, reduced in
            guard reduced else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { greetingProgress = 1 }
        }
        .task(id: flow.sawNotchOpen) {
            // Leave the two-second handwritten welcome fully visible before moving on.
            guard flow.sawNotchOpen, flow.step == .hello else { return }
            try? await Task.sleep(for: .milliseconds(2200))
            guard !Task.isCancelled, flow.step == .hello else { return }
            flow.next()
        }
    }

    private var tryItCard: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Desvan.Palette.bulb.opacity(flow.sawNotchOpen ? 0.2 : 0.1))
                    .overlay { Circle().strokeBorder(Desvan.Palette.bulb.opacity(0.35), lineWidth: 1) }
                if flow.sawNotchOpen {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Desvan.Palette.done)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    OnboardingBobbingArrow()
                        .transition(.opacity)
                }
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                if flow.sawNotchOpen {
                    HStack(spacing: 10) {
                        Text("There it is.")
                            .font(Desvan.Typeface.display(17, weight: 650))
                            .foregroundStyle(Desvan.Palette.paper)
                        DesvanRubberStamp(text: "Found", isFresh: true)
                    }
                    Text("That's your altillo. It's always up there, one move away.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(tryTitle)
                        .font(Desvan.Typeface.display(17, weight: 650))
                        .foregroundStyle(Desvan.Palette.paper)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tryDetail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .desvanCard(radius: 16, glow: flow.sawNotchOpen ? Desvan.Palette.bulb : nil)
        .animation(Desvan.Motion.pick(Desvan.Motion.settle, reduceMotion: reduceMotion), value: flow.sawNotchOpen)
        .accessibilityElement(children: .combine)
    }

    private var tryTitle: String {
        model.hasNotch
            ? String(localized: "Move the pointer up to the notch")
            : String(localized: "Move the pointer to the top of the screen")
    }

    private var tryDetail: String {
        switch (model.hasNotch, model.settings.opensOnHover) {
        case (true, true): String(localized: "Rest it there for a moment and Altillo opens. Try it now.")
        case (true, false): String(localized: "Click the notch and Altillo opens. Try it now.")
        case (false, true):
            String(localized: "Without a notch, Altillo lives in a small island at the top centre. Rest the pointer on it to open it. Try it now.")
        case (false, false):
            String(localized: "Without a notch, Altillo lives in a small island at the top centre. Click it to open it. Try it now.")
        }
    }
}

/// An arrow nudging upwards, towards the notch: a few bobs, then one every few seconds. Still with Reduce Motion.
struct OnboardingBobbingArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bobs = 0

    var body: some View {
        let arrow = Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(Desvan.Palette.bulb)
        if reduceMotion {
            arrow
        } else {
            arrow.keyframeAnimator(initialValue: 0.0, trigger: bobs) { content, lift in
                content.offset(y: -lift)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(6, duration: 0.45)
                    CubicKeyframe(0, duration: 0.55)
                }
            }
            .task {
                await PeriodicNudge.run(
                    eager: [.milliseconds(300), .seconds(1.6), .seconds(1.6), .seconds(1.6)],
                    every: .seconds(5)
                ) { bobs += 1 }
            }
        }
    }
}
