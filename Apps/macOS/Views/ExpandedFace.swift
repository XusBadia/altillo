import AltilloCore
import AltilloDesign
import SwiftUI

/// The open notch: a header band beside the notch (tabs on the left, context on the right) and the active tab below.
/// While a drag hovers (`dropTarget`) the body becomes the drop zone, keeping the header so the morph into the open
/// shelf after the drop is seamless.
struct ExpandedFace: View {
    let model: NotchModel
    let chrome: NotchChrome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDropTarget: Bool { model.state == .dropTarget }
    private var bodyKey: String { isDropTarget ? "drop" : model.tab.rawValue }

    var body: some View {
        VStack(spacing: 8) {
            header
            ZStack(alignment: .top) {
                content
                    .id(bodyKey)
                    .transition(.contentSwap(shift: 4, reduceMotion: reduceMotion))
            }
            .frame(height: NotchChrome.expandedContentHeight, alignment: .top)
            .padding(.horizontal, chrome.contentInset)
            .animation(Tokens.Motion.content(reduceMotion: reduceMotion), value: bodyKey)
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
    }

    private var header: some View {
        let sideZone = (chrome.size.width - chrome.notchWidth) / 2 - chrome.topRadius - 10
        return HStack(spacing: 0) {
            // Fixed zones (Color.clear) so an empty accessory can't collapse the layout.
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .leading) {
                    TabSwitcher(model: model)
                        .fixedSize()
                        .opacity(isDropTarget ? 0.45 : 1)
                        .allowsHitTesting(!isDropTarget)
                }
            Color.clear.frame(width: chrome.notchWidth)
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .trailing) {
                    HeaderAccessory(model: model, isDropTarget: isDropTarget)
                        .fixedSize()
                }
        }
        .frame(height: chrome.bandHeight)
        .padding(.horizontal, chrome.topRadius + 10)
    }

    @ViewBuilder
    private var content: some View {
        if isDropTarget {
            DropZoneView(model: model)
        } else {
            switch model.tab {
            case .shelf: ShelfView(model: model)
            case .usage: UsageView(demo: model.demo)
            case .agents: AgentsView(demo: model.demo)
            }
        }
    }
}

// MARK: - Tabs

extension NotchTab {
    var title: String {
        switch self {
        case .shelf: "Altillo"
        case .usage: "IA"
        case .agents: "Agentes"
        }
    }

    var systemImage: String {
        switch self {
        case .shelf: "tray.full.fill"
        case .usage: "gauge.with.dots.needle.67percent"
        case .agents: "terminal.fill"
        }
    }
}

/// Compact tab switcher. The selected tab sits on a glass capsule that slides between tabs.
struct TabSwitcher: View {
    let model: NotchModel

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                TabButton(
                    tab: tab,
                    isSelected: model.tab == tab,
                    badge: tab == .agents && model.demo.waitingAgent != nil,
                    namespace: namespace
                ) {
                    withAnimation(Tokens.Motion.snappy(reduceMotion: reduceMotion)) { model.tab = tab }
                }
            }
        }
    }
}

private struct TabButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let badge: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.altilloAccent) private var accent

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : .primary)
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Circle()
                                .fill(Tokens.Palette.warning)
                                .frame(width: 5, height: 5)
                                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                                .offset(x: 3, y: -2)
                        }
                    }
                Text(tab.title)
                    .font(Tokens.Typography.label)
            }
            .foregroundStyle(isSelected || isHovering ? Tokens.Palette.text : Tokens.Palette.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Tokens.Palette.text.opacity(0.06))
                        .glassCapsule()
                        .matchedGeometryEffect(id: "selectedTab", in: namespace)
                } else if isHovering {
                    Capsule().fill(Tokens.Palette.text.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Tokens.Motion.hover) { isHovering = hovering } }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Header accessory

/// Right side of the header: context for the active tab.
private struct HeaderAccessory: View {
    let model: NotchModel
    let isDropTarget: Bool

    var body: some View {
        Group {
            if isDropTarget {
                EmptyView()
            } else {
                switch model.tab {
                case .shelf: shelf
                case .usage: usage
                case .agents: agents
                }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var shelf: some View {
        if !model.shelf.isEmpty {
            HStack(spacing: 4) {
                Text(NotchFormat.things(model.shelf.count))
                    .font(Tokens.Typography.caption)
                    .foregroundStyle(Tokens.Palette.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(model.shelf.count)))
                Button("Vaciar") { model.actions.clearShelf() }
                    .buttonStyle(GlassButtonStyle(.plain, height: 22))
            }
        }
    }

    private var usage: some View {
        HStack(spacing: 5) {
            PulseDot(color: Tokens.Palette.success, size: 5, isPulsing: false)
            Text("Actualizado \(NotchFormat.ago(model.demo.usageUpdatedAt))")
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Palette.textTertiary)
                .monospacedDigit()
        }
    }

    private var agents: some View {
        let waiting = model.demo.agents.count { $0.phase.needsUser }
        let working = model.demo.workingAgentsCount
        return HStack(spacing: 8) {
            if waiting > 0 {
                Label("\(waiting) espera", systemImage: "hand.raised.fill")
                    .foregroundStyle(Tokens.Palette.warning)
            }
            if working > 0 {
                Label("\(working) trabajando", systemImage: "circle.dotted")
                    .foregroundStyle(Tokens.Palette.textTertiary)
            }
        }
        .labelStyle(CompactLabelStyle())
        .font(Tokens.Typography.caption)
        .monospacedDigit()
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .semibold))
            configuration.title
        }
    }
}
