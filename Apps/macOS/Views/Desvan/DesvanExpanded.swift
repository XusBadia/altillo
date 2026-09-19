import AltilloCore
import AltilloDesign
import SwiftUI

/// The open attic: a header band beside the notch (tabs left, context right) and the active tab below, lit by the
/// bulb hanging under the notch. While a drag hovers (`dropTarget`) the body becomes the box and the paper plane.
struct DesvanExpandedFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    let flicker: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDropTarget: Bool { model.state == .dropTarget }
    private var bodyKey: String { isDropTarget ? "drop" : model.module.rawValue }
    private var hoveredZone: DropZone? {
        guard model.scenario == .dropTarget else { return model.dropZone }
        // `-demoMotion flaps`: the pointer comes and goes over the box.
        if DesvanDebug.demoMotion == .flaps { return DesvanDebug.clock.phase ? .shelf : nil }
        return DesvanDebug.forcedZone
    }

    var body: some View {
        VStack(spacing: NotchChrome.expandedContentGap) {
            header
            ZStack(alignment: .top) {
                content
                    .id(bodyKey)
                    .transition(.contentSwap(shift: 4, reduceMotion: reduceMotion))
            }
            .frame(height: NotchChrome.expandedContentHeight, alignment: .top)
            .padding(.horizontal, chrome.contentInset)
            .animation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion), value: bodyKey)
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
        .overlay {
            // The bulb hangs just under the notch; its light warms whatever sits below.
            // The band beside the notch stays pure black so it melts into the hardware notch.
            DesvanBulbGlow(intensity: glow + flicker, radius: 160, originY: chrome.bandHeight)
                .animation(.easeInOut(duration: 0.25), value: glow)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: chrome.bandHeight - 2)
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                        Color.black
                    }
                }
        }
    }

    /// 6 % at rest, warmer while something hovers the box.
    private var glow: Double {
        guard isDropTarget else { return 0.06 }
        return hoveredZone == .shelf ? 0.14 : 0.09
    }

    @ViewBuilder
    private var header: some View {
        if chrome.hasNotch {
            // Tabs and context sit either side of the camera; the notch body stays clear.
            let sideZone = (chrome.size.width - chrome.notchWidth) / 2 - chrome.topRadius - 8
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: sideZone)
                    .overlay(alignment: .leading) { tabs }
                Color.clear.frame(width: chrome.notchWidth)
                Color.clear
                    .frame(width: sideZone)
                    .overlay(alignment: .trailing) { accessory }
            }
            .frame(height: chrome.bandHeight)
            .padding(.horizontal, chrome.topRadius + 8)
        } else {
            // No camera to dodge: one plain row.
            HStack(spacing: 12) {
                tabs
                Spacer(minLength: 0)
                accessory
            }
            .frame(height: chrome.bandHeight)
            .padding(.horizontal, chrome.topRadius + 8)
        }
    }

    private var tabs: some View {
        DesvanTabs(model: model)
            .fixedSize()
            .opacity(isDropTarget ? 0.4 : 1)
            .allowsHitTesting(!isDropTarget)
    }

    private var accessory: some View {
        DesvanHeaderAccessory(model: model, isDropTarget: isDropTarget)
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        if isDropTarget {
            DesvanDropZones(model: model, hovered: hoveredZone)
        } else {
            switch model.module {
            case .shelf: DesvanShelfView(model: model)
            case .usage: DesvanUsageView(demo: model.demo)
            case .agents: DesvanAgentsView(model: model)
            case .calendar: DesvanCalendarView(model: model)
            case .mirror: DesvanMirrorView(model: model)
            case .nowPlaying: DesvanNowPlayingView(model: model)
            }
        }
    }
}

// MARK: - Tabs

private extension NotchModule {
    var desvanTitle: String { title }
}

/// SF Pro Rounded 12 semibold, lowercase-friendly. The active tab sits on a `woodRaised` capsule with a top lip.
/// Switching tabs is frequent, so the capsule moves with a short, bounce-free spring.
private struct DesvanTabs: View {
    let model: NotchModel
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(model.settings.modules) { tab in
                DesvanTabButton(
                    tab: tab,
                    isSelected: model.module == tab,
                    knocks: tab == .agents && model.scenario != nil && model.demo.waitingAgent != nil,
                    namespace: namespace
                ) {
                    withAnimation(Desvan.Motion.pick(.spring(duration: 0.24, bounce: 0), reduceMotion: reduceMotion)) {
                        model.module = tab
                    }
                }
            }
        }
    }
}

private struct DesvanTabButton: View {
    let tab: NotchModule
    let isSelected: Bool
    let knocks: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon
                Text(tab.desvanTitle)
                    .font(Desvan.Typeface.rounded(12, weight: .semibold))
            }
            .foregroundStyle(isSelected || isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
            // On the plaque the label is pressed into the wood: a hairline of shade above, of light below.
            .shadow(color: .black.opacity(isSelected ? 0.7 : 0), radius: 0, y: -0.5)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background {
                if isSelected {
                    DesvanTabPlaque()
                        .matchedGeometryEffect(id: "tab", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Desvan.Palette.paper.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var icon: some View {
        switch tab {
        case .shelf:
            DesvanHouseMark(size: 12, lit: isSelected ? 1 : 0.25,
                            outline: isSelected ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
        case .calendar, .mirror, .nowPlaying:
            Image(systemName: tab.symbol)
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
        case .usage:
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
        case .agents:
            if knocks {
                DesvanKnockingHand(size: 10.5)
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 10.5, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }
}

/// The active tab: a small plaque of lighter wood in a thin brass frame, like the label holder on an attic drawer.
private struct DesvanTabPlaque: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)], startPoint: .top, endPoint: .bottom))
            .desvanTexture(DesvanTexture.wood, opacity: 0.7, in: shape)
            .overlay {
                // Brass rim: bright where it faces the bulb, dark underneath.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: 0xE8C987), Color(hex: 0xA9824A), Color(hex: 0x5E4522)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                shape.inset(by: 1).strokeBorder(.black.opacity(0.45), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
    }
}

// MARK: - Header accessory

private struct DesvanHeaderAccessory: View {
    let model: NotchModel
    let isDropTarget: Bool

    var body: some View {
        Group {
            if isDropTarget {
                EmptyView()
            } else if model.module != .shelf, model.scenario == nil {
                // Usage and agents still show sample data until their modules exist (phases 3 and 4).
                Text("Datos de ejemplo")
                    .font(Self.caption)
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            } else {
                switch model.module {
                case .shelf: shelf
                case .usage: usage
                case .agents: agents
                case .calendar, .mirror, .nowPlaying: EmptyView()
                }
            }
        }
        .lineLimit(1)
    }

    private static let caption = Desvan.Typeface.rounded(11, weight: .medium)

    @ViewBuilder
    private var shelf: some View {
        if !model.shelf.isEmpty {
            HStack(spacing: 6) {
                if model.selection.isEmpty {
                    Text("\(Text("\(model.shelf.count)").font(Desvan.Typeface.figure(12, weight: .semibold)).foregroundStyle(Desvan.Palette.paper)) \(model.shelf.count == 1 ? "cosa" : "cosas") arriba")
                        .font(Self.caption)
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .contentTransition(.numericText(value: Double(model.shelf.count)))
                        .help("Arrástralo fuera para bajarlo")
                } else {
                    // With something picked, the keys that act on it.
                    HStack(spacing: 10) {
                        hint("space", "Mirar")
                        hint("delete.left", "Quitar")
                    }
                    .font(Self.caption)
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .transition(.opacity)
                }
                Button("Vaciar") { model.actions.clearShelf() }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
            }
            .animation(Desvan.Motion.hover, value: model.selection.isEmpty)
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text)
        }
    }

    private var usage: some View {
        HStack(spacing: 5) {
            Circle().fill(Desvan.Palette.done).frame(width: 5, height: 5)
            Text("Al día · \(NotchFormat.ago(model.demo.usageUpdatedAt))")
                .font(Self.caption)
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .monospacedDigit()
        }
    }

    private var agents: some View {
        let waiting = model.demo.agents.count { $0.phase.needsUser }
        let working = model.demo.workingAgentsCount
        return HStack(spacing: 10) {
            if waiting > 0 {
                Text("\(waiting) llama a la puerta")
                    .foregroundStyle(Desvan.Palette.bulb)
            }
            if working > 0 {
                Text("\(working) trabajando")
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .font(Self.caption)
        .monospacedDigit()
    }
}
