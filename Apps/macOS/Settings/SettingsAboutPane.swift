import AppKit
import SwiftUI

/// Who made this, which version you have, and where to find the code.
struct SettingsAboutPane: View {
    private static let repository = URL(string: "https://github.com/XusBadia/altillo")!
    private static let privacy = URL(string: "https://altillo.app/privacy/")!
    private static let reportProblem = URL(string: "https://github.com/XusBadia/altillo/issues/new?template=bug_report.yml")!

    private let updater = Updater.shared
    @State private var copiedDiagnostics = false

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Everything fits in the window without scrolling, so Aurio is seen on arrival: a compact hero, the invitation
    /// right under it, then the practical cards. The scroll view only matters at larger text sizes.
    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                hero

                VStack(alignment: .leading, spacing: 12) {
                    SettingsSupportCard()
                    updatesCard
                    helpCard
                }
                .padding(.top, 16)

                HStack(spacing: 6) {
                    Text("MIT licence. Use it, copy it and change it freely.")
                    Text(verbatim: "·")
                    Text("© 2026 Xus Badia")
                }
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 60, height: 60)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "Altillo")
                        .font(Desvan.Typeface.display(22, weight: 700))
                        .foregroundStyle(Desvan.Palette.paper)
                        .accessibilityAddTraits(.isHeader)
                    Text("Version \(version) (\(build))")
                        .font(Desvan.Typeface.figure(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .textSelection(.enabled)
                }
                Text("A place up top to leave things and see what matters.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Link(destination: Self.repository) {
                Label("View the code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulbInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Desvan.Palette.bulb))
                    .contentShape(Capsule())
                    .fixedSize()
            }
            .buttonStyle(SettingsPressStyle(scale: 0.96))
            .pointerStyle(.link)
            .accessibilityLabel("View Altillo's code on GitHub")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var updatesCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    SettingsGroupHeading(title: "Updates")
                    Spacer(minLength: 8)
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .controlSize(.small)
                        .disabled(!updater.canCheckForUpdates)
                }

                SettingsCardDivider()

                if updater.isConfigured {
                    SettingsToggleRow("Automatically check for updates", isOn: automaticallyChecksForUpdates)
                } else {
                    Text("This build has no update feed configured, so it can't check for updates.")
                        .settingsHint()
                }

                SettingsCardDivider()

                HStack(alignment: .center, spacing: 12) {
                    Text("The first-run tour: starting points, AI tools, permissions and tricks.")
                        .settingsHint()
                    Spacer(minLength: 12)
                    Button("Show the Welcome Again") { OnboardingWindowController.shared.show() }
                        .controlSize(.small)
                        .help("The first-run tour: starting points, AI tools, permissions and tricks.")
                }
            }
        }
    }

    private var helpCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                SettingsGroupHeading(title: "Help")
                SettingsCardDivider()

                HStack(spacing: 14) {
                    Link("Report a Problem", destination: Self.reportProblem)
                        .pointerStyle(.link)
                    Link("Privacy", destination: Self.privacy)
                        .pointerStyle(.link)
                    Spacer(minLength: 8)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SupportDiagnostics.current(), forType: .string)
                        withAnimation(SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion)) {
                            copiedDiagnostics = true
                        }
                    } label: {
                        Label {
                            copiedDiagnostics ? Text("Diagnostics Copied") : Text("Copy Safe Diagnostics")
                        } icon: {
                            Image(systemName: copiedDiagnostics ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .controlSize(.small)
                    .help("The diagnostic copy includes the version, macOS, architecture and hook status. It never includes paths, credentials, session content or logs.")
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
    }
}

/// "Help us keep building Altillo": the same invitation as the website's, to try our other app, Aurio. Altillo is
/// free and open source; trying Aurio is how people can support it.
private struct SettingsSupportCard: View {
    private static let aurio = URL(string: "https://www.aurioapp.com")!

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Link(destination: Self.aurio) {
            HStack(spacing: 14) {
                // Aurio, the dragon, winks when you come close (like on the website).
                ZStack {
                    Image("AurioMascot")
                        .resizable()
                        .scaledToFit()
                        .opacity(isHovering ? 0 : 1)
                    Image("AurioMascotWink")
                        .resizable()
                        .scaledToFit()
                        .opacity(isHovering ? 1 : 0)
                }
                .frame(width: 120, height: 90)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    SettingsGroupHeading(
                        title: "Help us keep building Altillo",
                        detail: "Altillo is free. Support it by trying our other app, Aurio: track expenses, share accounts and follow your net worth."
                    )
                    Label("Meet Aurio", systemImage: "arrow.up.right")
                        .labelStyle(.titleAndIcon)
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulb)
                        .padding(.top, 2)
                        .offset(x: isHovering ? 2 : 0)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Desvan.Palette.woodRaised)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Desvan.Palette.paper.opacity(isHovering ? 0.05 : 0))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                    }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SettingsPressStyle())
        .pointerStyle(.link)
        .onHover { hovering in
            withAnimation(Desvan.Motion.pick(.easeInOut(duration: 0.18), reduceMotion: reduceMotion)) {
                isHovering = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Help us keep building Altillo: meet Aurio, our personal finance app")
        .accessibilityAddTraits(.isLink)
    }
}
