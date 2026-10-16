import AltilloCore
import SwiftUI

/// Stable destinations: global settings first, then one page per configurable section.
enum SettingsTab: String, CaseIterable, Identifiable {
    case modules, drawer, size, behaviour, about
    case shelf, assistant, calendar, usage, clipboard, home, agents

    var id: Self { self }

    static let global: [Self] = [.behaviour, .size, .modules, .drawer]
    static let sections: [Self] = [.shelf, .assistant, .calendar, .usage, .clipboard, .home, .agents]

    var module: NotchModule? {
        switch self {
        case .shelf: .shelf
        case .assistant: .assistant
        case .calendar: .calendar
        case .usage: .usage
        case .clipboard: .clipboard
        case .home: .home
        case .agents: .agents
        default: nil
        }
    }

    var title: String {
        switch self {
        case .modules: String(localized: "Sections")
        case .drawer: String(localized: "Drawer")
        case .size: String(localized: "Appearance")
        case .behaviour: String(localized: "General")
        case .about: String(localized: "About")
        default: module?.title ?? ""
        }
    }

    static var launchOverride: SettingsTab? {
        UserDefaults.standard.string(forKey: "settingsTab").flatMap(SettingsTab.init)
    }

    var symbol: String {
        switch self {
        case .modules: "square.stack.3d.up"
        case .drawer: "archivebox"
        case .size: "paintbrush"
        case .behaviour: "slider.horizontal.3"
        case .about: "info.circle"
        default: module?.symbol ?? "circle"
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

    private var liveDisplayID: CGDirectDisplayID? {
        if let id = model?.activeDisplayID { return id }
        return ScreenService.plan(
            for: settings.displayMode,
            screens: ScreenService.descriptors,
            pointer: NSEvent.mouseLocation,
            currentLive: nil,
            canMove: true
        )?.live.id
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $navigation.tab, settings: settings)
                .frame(width: 184)
            Rectangle().fill(Desvan.Palette.hairlineStrong).frame(width: 0.75)
            paneContent
                .id(navigation.tab)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .clipped()
        }
        .tint(Desvan.Palette.bulb)
        .background(SettingsBackdrop())
    }

    @ViewBuilder
    private var paneContent: some View {
        switch navigation.tab {
        case .modules: SettingsModulesPane(settings: settings, navigation: navigation)
        case .drawer: SettingsDrawerPane()
        case .size: SettingsSizePane(settings: settings, hasHardwareNotch: hasHardwareNotch,
                                     displayID: liveDisplayID)
        case .behaviour: SettingsBehaviourPane(settings: settings, hasHardwareNotch: hasHardwareNotch)
        case .about: SettingsAboutPane()
        default:
            SettingsSectionPane(tab: navigation.tab, settings: settings, clipboard: model?.clipboard,
                                home: model?.home)

        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTab
    @Bindable var settings: AltilloSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "Altillo")
                .font(Desvan.Typeface.display(20, weight: 650))
                .foregroundStyle(Desvan.Palette.paper)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 20)
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(SettingsTab.global) { tab in row(tab) }
                    Text("Configure sections")
                        .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 22)
                        .padding(.bottom, 6)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(SettingsTab.sections) { tab in row(tab) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            row(.about).padding(.top, 12)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func row(_ tab: SettingsTab) -> some View {
        Button { selection = tab } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 19)
                    .foregroundStyle(selection == tab ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                Text(tab.title)
                    .font(Desvan.Typeface.rounded(12.5, weight: selection == tab ? .semibold : .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let module = tab.module, !settings.isEnabled(module) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .accessibilityLabel("Off")
                }
            }
            .foregroundStyle(Desvan.Palette.paper)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if selection == tab { DesvanTabPlaque(cornerRadius: 8) }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .settingsHoverHighlight()
        .accessibilityAddTraits(selection == tab ? [.isSelected] : [])
        .background {
            // Preserve the original five keyboard shortcuts even as navigation grows.
            if let index = [SettingsTab.modules, .drawer, .size, .behaviour, .about].firstIndex(of: tab) {
                Button(tab.title) { selection = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
                    .frame(width: 0, height: 0)
            }
        }
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
            VStack(alignment: .leading, spacing: 3) {
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
