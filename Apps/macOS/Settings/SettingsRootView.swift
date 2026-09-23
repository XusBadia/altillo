import SwiftUI

/// Sections of the Settings window. A plain macOS tabbed settings window, dressed in Desván's warmth:
/// dark wood surfaces, rounded type and the bulb as the accent.
enum SettingsTab: String, CaseIterable, Identifiable {
    case modules, drawer, size, behaviour, about

    var id: Self { self }

    var title: String {
        switch self {
        case .modules: String(localized: "Sections")
        case .drawer: String(localized: "Drawer")
        case .size: String(localized: "Size")
        case .behaviour: String(localized: "Behaviour")
        case .about: String(localized: "About")
        }
    }

    /// `open Altillo.app --args -openSettings YES -settingsTab size` opens the window on a section (design reviews).
    static var launchOverride: SettingsTab? {
        UserDefaults.standard.string(forKey: "settingsTab").flatMap(SettingsTab.init)
    }

    var symbol: String {
        switch self {
        case .modules: "square.stack.3d.up"
        case .drawer: "archivebox"
        case .size: "arrow.left.and.right"
        case .behaviour: "hand.tap"
        case .about: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    @Bindable var navigation: SettingsNavigation
    @Bindable private var settings = AltilloSettings.shared

    var body: some View {
        TabView(selection: $navigation.tab) {
            SettingsModulesPane(settings: settings)
                .settingsTab(.modules)
            SettingsDrawerPane()
                .settingsTab(.drawer)
            SettingsSizePane(settings: settings)
                .settingsTab(.size)
            SettingsBehaviourPane(settings: settings)
                .settingsTab(.behaviour)
            SettingsAboutPane()
                .settingsTab(.about)
        }
        .tint(Desvan.Palette.bulb)
        .frame(
            width: SettingsWindowController.contentSize.width,
            height: SettingsWindowController.contentSize.height
        )
        .background(SettingsBackdrop())
    }
}

private extension View {
    func settingsTab(_ tab: SettingsTab) -> some View {
        self
            .background(SettingsBackdrop())
            .tabItem { Label(tab.title, systemImage: tab.symbol) }
            .tag(tab)
    }
}

// MARK: - Warmth

/// Dark wood with the bulb hanging above: the same light that fills the notch, much dimmer.
struct SettingsBackdrop: View {
    var body: some View {
        Desvan.Palette.wood
            .overlay(alignment: .top) {
                RadialGradient(
                    stops: [
                        .init(color: Desvan.Palette.bulb.opacity(0.10), location: 0),
                        .init(color: Desvan.Palette.bulb.opacity(0.04), location: 0.45),
                        .init(color: Desvan.Palette.bulb.opacity(0), location: 1),
                    ],
                    center: .top,
                    startRadius: 0,
                    endRadius: 320
                )
                .frame(height: 320)
                .blendMode(.plusLighter)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Every pane shares the same padding, the same warm form background and the same title voice.
struct SettingsPane<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Desvan.Typeface.display(17, weight: 650))
                    .foregroundStyle(Desvan.Palette.paper)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 10)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A wood card used as the background of a group of controls.
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                shape.fill(Desvan.Palette.woodRaised)
                    .overlay {
                        shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75)
                    }
            }
    }
}

extension Text {
    /// Explanatory line under a control: small, paper, never shouting.
    func settingsHint() -> some View {
        self
            .font(.system(size: 11))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
