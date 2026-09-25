import SwiftUI

/// The last page: ready, and the one thing worth trying first, shown as a small loop: a file carried up into the
/// notch, the bulb lighting as it arrives. "Start" closes the window.
struct OnboardingDonePage: View {
    let flow: OnboardingFlow

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)

            OnboardingDropDemo(hasNotch: flow.model.hasNotch)
                .frame(width: 340, height: 170)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Text("Your altillo is ready")
                        .font(Desvan.Typeface.display(28, weight: 700))
                        .foregroundStyle(Desvan.Palette.paper)
                        .accessibilityAddTraits(.isHeader)
                    DesvanRubberStamp(text: "Done", isFresh: true)
                }
                Text(tryLine)
                    .font(Desvan.Typeface.rounded(15, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .multilineTextAlignment(.center)
                Text("It stays up there until you drag it out, wherever you want it. You'll find this welcome again in Altillo's menu and in Settings › About.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430)
                    .padding(.top, 2)
            }
            .padding(.top, 18)

            Spacer(minLength: 18)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tryLine: String {
        flow.model.hasNotch
            ? String(localized: "Try it: drag any file up to the notch.")
            : String(localized: "Try it: drag any file up to the top of the screen.")
    }
}

/// The demo loop: the top of a screen with the notch, and a file with the pointer on it rising into it. The notch
/// widens a touch as it takes it (the landing) and the bulb glows. With Reduce Motion, a still picture.
struct OnboardingDropDemo: View {
    let hasNotch: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Pose {
        var x: CGFloat = -110
        var y: CGFloat = 36
        var scale: CGFloat = 1
        var opacity: Double = 0
        var width: CGFloat = 1
        var glow: Double = 0.08
    }

    var body: some View {
        ZStack(alignment: .top) {
            screen
            if reduceMotion {
                scene(Pose(x: -40, y: 6, opacity: 1, glow: 0.16))
            } else {
                KeyframeAnimator(initialValue: Pose(), repeating: true) { pose in
                    scene(pose)
                } keyframes: { _ in
                    // 2.6 s: in from the lower left, up along a curve, into the notch, a beat of rest.
                    KeyframeTrack(\.opacity) {
                        LinearKeyframe(0, duration: 0.15)
                        LinearKeyframe(1, duration: 0.25)
                        LinearKeyframe(1, duration: 1.05)
                        LinearKeyframe(0, duration: 0.25)
                        LinearKeyframe(0, duration: 0.9)
                    }
                    KeyframeTrack(\.x) {
                        LinearKeyframe(-110, duration: 0.35)
                        CubicKeyframe(0, duration: 1.15)
                        LinearKeyframe(0, duration: 1.1)
                    }
                    KeyframeTrack(\.y) {
                        LinearKeyframe(36, duration: 0.35)
                        CubicKeyframe(-50, duration: 1.15)
                        LinearKeyframe(-50, duration: 1.1)
                    }
                    KeyframeTrack(\.scale) {
                        LinearKeyframe(1, duration: 1.15)
                        CubicKeyframe(0.5, duration: 0.35)
                        LinearKeyframe(0.5, duration: 1.1)
                    }
                    KeyframeTrack(\.glow) {
                        LinearKeyframe(0.08, duration: 0.5)
                        CubicKeyframe(0.2, duration: 0.9)
                        CubicKeyframe(0.34, duration: 0.15)
                        CubicKeyframe(0.08, duration: 1.05)
                    }
                    KeyframeTrack(\.width) {
                        LinearKeyframe(1, duration: 1.45)
                        SpringKeyframe(1.24, duration: 0.2, spring: .snappy)
                        SpringKeyframe(1, duration: 0.55, spring: Spring(duration: 0.5, bounce: 0.35))
                        LinearKeyframe(1, duration: 0.4)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("A file being dragged up into the notch")
    }

    private var screen: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x3A2E24), Color(hex: 0x1F1914)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .top) {
                Rectangle().fill(Desvan.Palette.paper.opacity(0.07)).frame(height: 16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
            }
    }

    private func scene(_ pose: Pose) -> some View {
        ZStack(alignment: .top) {
            DesvanBulbGlow(intensity: pose.glow, radius: 110, originY: 18)
            // The file, with the pointer holding it.
            ZStack(alignment: .bottomTrailing) {
                DemoDocument()
                Image(systemName: "cursorarrow")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 1)
                    .offset(x: 10, y: 10)
            }
            .scaleEffect(pose.scale)
            .opacity(pose.opacity)
            .offset(x: pose.x, y: 60 + pose.y)
            // The notch (or the island), widening as it takes the file, which goes in behind it.
            UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                .fill(Color.black)
                .frame(width: 92 * pose.width, height: 22)
                .overlay {
                    DesvanHouseMark(size: 10, lit: min(1, pose.glow * 4))
                        .opacity(pose.width > 1.05 ? 1 : 0)
                }
                .offset(y: hasNotch ? 0 : 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A paper document with a folded corner and a few lines of text.
    private struct DemoDocument: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Desvan.Palette.paper)
                    .shadow(color: .black.opacity(0.45), radius: 5, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<4, id: \.self) { line in
                        Capsule()
                            .fill(Desvan.Palette.ink.opacity(0.25))
                            .frame(width: line == 3 ? 16 : 26, height: 2.5)
                    }
                }
                .padding(.top, 12)
                .padding(.leading, 7)
                Text(verbatim: "PDF")
                    .font(.system(size: 6.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 2).fill(Desvan.Palette.tomato))
                    .offset(x: 7, y: 34)
            }
            .frame(width: 40, height: 50)
        }
    }
}
