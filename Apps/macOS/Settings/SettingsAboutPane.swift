import AppKit
import SwiftUI

/// Who made this, which version you have, and where to find the code.
struct SettingsAboutPane: View {
    private static let repository = URL(string: "https://github.com/XusBadia/altillo")!

    private let updater = Updater.shared

    /// Two-way binding onto `Updater`, which isn't `@Observable` — it just wraps Sparkle's own state
    /// (Sparkle persists this preference itself). The toggle still reflects the current value on every
    /// redraw; it just won't animate if something else flips it from outside this view.
    private var automaticallyChecksForUpdates: Binding<Bool> {
        Binding(
            get: { updater.automaticallyChecksForUpdates },
            set: { updater.automaticallyChecksForUpdates = $0 }
        )
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text(verbatim: "Altillo")
                        .font(Desvan.Typeface.display(26, weight: 700))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Version \(version) (\(build))")
                        .font(Desvan.Typeface.figure(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }

                Text("A place up top to leave things and see what matters.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)

                Link(destination: Self.repository) {
                    Label("View the code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulbInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Desvan.Palette.bulb))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .padding(.top, 4)
                .accessibilityLabel("View Altillo's code on GitHub")

                VStack(spacing: 6) {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)

                    if updater.isConfigured {
                        Toggle("Automatically check for updates", isOn: automaticallyChecksForUpdates)
                            .font(Desvan.Typeface.figure(11.5, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                    } else {
                        Text("This build has no update feed configured, so it can't check for updates.")
                            .font(Desvan.Typeface.figure(11, weight: .regular))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 10)
            }

            Spacer(minLength: 0)

            VStack(spacing: 3) {
                Text("MIT licence. Use it, copy it and change it freely.")
                Text("© 2026 Xus Badia")
            }
            .font(.system(size: 11))
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}
