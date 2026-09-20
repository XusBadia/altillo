import AppKit
import SwiftUI

/// Who made this, which version you have, and where to find the code.
struct SettingsAboutPane: View {
    private static let repository = URL(string: "https://github.com/XusBadia/altillo")!

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
                    Text("Altillo")
                        .font(Desvan.Typeface.display(26, weight: 700))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Versión \(version) (\(build))")
                        .font(Desvan.Typeface.figure(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                }

                Text("Un sitio arriba donde dejar cosas y ver lo importante.")
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .multilineTextAlignment(.center)

                Link(destination: Self.repository) {
                    Label("Ver el código en GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulbInk)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Desvan.Palette.bulb))
                }
                .buttonStyle(.plain)
                .pointerStyle(.link)
                .padding(.top, 4)
                .accessibilityLabel("Ver el código de Altillo en GitHub")
            }

            Spacer(minLength: 0)

            VStack(spacing: 3) {
                Text("Licencia MIT. Puedes usarlo, copiarlo y modificarlo libremente.")
                Text("© 2026 Xus Badia")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .multilineTextAlignment(.center)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }
}
