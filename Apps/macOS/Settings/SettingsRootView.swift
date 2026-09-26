import SwiftUI

/// Sections of the Settings window. A macOS settings window with its sections in the title bar, dressed in Desván's
/// warmth: dark wood surfaces, rounded type and the bulb as the accent.
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
    let model: NotchModel?
    @Bindable private var settings = AltilloSettings.shared

    /// `model` follows the actual live display, including Pointer and All Displays modes. The fallback is only
    /// used if a settings window is constructed outside the running app (for example, a design preview).
    private var hasHardwareNotch: Bool {
        if let model { return model.hasNotch }
        let screens = ScreenService.descriptors
        return ScreenService.plan(
            for: settings.displayMode,
            screens: screens,
            pointer: NSEvent.mouseLocation,
            currentLive: nil,
            canMove: true
        )?.live.hasNotch ?? false
    }

    var body: some View {
        // The window draws its content under the title bar and the tab bar is the title bar, beside the traffic
        // lights. The pane keeps to the safe area below it, so its lists and scroll views start where they should.
        pane
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Desvan.Palette.hairlineStrong)
                    .frame(height: 0.75)
            }
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    SettingsTabBar(selection: $navigation.tab)
                        .frame(height: proxy.safeAreaInsets.top)
                        .offset(y: -proxy.safeAreaInsets.top)
                }
            }
        .tint(Desvan.Palette.bulb)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsBackdrop())
    }

    @ViewBuilder
    private var pane: some View {
        switch navigation.tab {
        case .modules: SettingsModulesPane(settings: settings, hasHardwareNotch: hasHardwareNotch)
        case .drawer: SettingsDrawerPane()
        case .size: SettingsSizePane(settings: settings, hasHardwareNotch: hasHardwareNotch)
        case .behaviour: SettingsBehaviourPane(settings: settings, hasHardwareNotch: hasHardwareNotch)
        case .about: SettingsAboutPane()
        }
    }
}

// MARK: - Tab bar

/// The window's sections, in the title bar: a symbol over its name, the chosen one on the same brass-rimmed plaque as
/// the notch's active tab. ⌘1–⌘5 switch too. If the names ever don't fit beside the traffic lights (a longer
/// translation), they move to the tooltips and only the symbols stay. macOS's "Larger Text" display setting scales
/// the whole window evenly, so the proportions hold; the window's height is chosen to fit it.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsTab
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Room kept free on both sides for the traffic lights, so the centred tabs never slide under them.
    private static let trafficLightsInset: CGFloat = 76

    var body: some View {
        ViewThatFits(in: .horizontal) {
            bar(showsTitles: true)
            bar(showsTitles: false)
        }
        .padding(.horizontal, Self.trafficLightsInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func bar(showsTitles: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(SettingsTab.allCases.enumerated()), id: \.element) { index, tab in
                SettingsTabButton(tab: tab, isSelected: selection == tab, showsTitle: showsTitles,
                                  namespace: namespace) {
                    withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
                        selection = tab
                    }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .fixedSize()
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let showsTitle: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false
    private let symbolSize: CGFloat = 15
    private let titleSize: CGFloat = 11.5

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: symbolSize, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: symbolSize + 5)
                if showsTitle {
                    Text(tab.title)
                        .font(Desvan.Typeface.rounded(titleSize, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(isSelected || isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
            .shadow(color: .black.opacity(isSelected ? 0.7 : 0), radius: 0, y: -0.5)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .frame(minWidth: showsTitle ? 62 : 38, minHeight: 40)
            .background {
                if isSelected {
                    DesvanTabPlaque(cornerRadius: 9)
                        .matchedGeometryEffect(id: "settingsTab", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Desvan.Palette.paper.opacity(0.07))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
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
