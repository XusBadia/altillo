import AltilloCore
import AltilloDesign
import SwiftUI

/// The open notch: tabs beside the notch on the left, context on the right, the active tab below. While a drag hovers
/// (`dropTarget`) the body becomes the two drop zones, keeping the header so the morph into the shelf is seamless.
struct FluidoExpandedFace: View {
    let model: NotchModel
    let chrome: FluidoChrome
    let pointer: CGPoint?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDropTarget: Bool { model.state == .dropTarget }
    private var bodyKey: String { isDropTarget ? "drop" : model.tab.rawValue }

    var body: some View {
        VStack(spacing: 8) {
            header
            ZStack(alignment: .top) {
                content
                    .id(bodyKey)
                    .transition(.materialize(reduceMotion: reduceMotion))
            }
            .frame(height: FluidoChrome.expandedContentHeight, alignment: .top)
            .padding(.horizontal, chrome.contentInset)
            .animation(Fluido.Motion.materialize(reduceMotion), value: bodyKey)
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
    }

    private var header: some View {
        let sideZone = (chrome.size.width - chrome.notchWidth) / 2 - chrome.topRadius - 10
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .leading) {
                    FluidoTabs(model: model)
                        .fixedSize()
                        .opacity(isDropTarget ? 0.4 : 1)
                        .allowsHitTesting(!isDropTarget)
                }
            Color.clear.frame(width: chrome.hasNotch ? chrome.notchWidth : 20)
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .trailing) {
                    FluidoHeaderAccessory(model: model, isDropTarget: isDropTarget)
                        .fixedSize()
                }
        }
        .frame(height: chrome.bandHeight)
        .padding(.horizontal, chrome.topRadius + 10)
    }

    @ViewBuilder
    private var content: some View {
        if isDropTarget {
            FluidoDropZones(model: model, pointer: pointer)
        } else {
            switch model.tab {
            case .shelf: FluidoShelfView(model: model)
            case .usage: FluidoUsageView(demo: model.demo)
            case .agents: FluidoAgentsView(demo: model.demo)
            }
        }
    }
}

// MARK: - Tabs

/// The selected tab is a glass chip washed in its module's light, with its name in SF Expanded; the others collapse
/// to their symbol. Switching tabs, the chip flows to the new tab and the label unfolds out of it.
struct FluidoTabs: View {
    let model: NotchModel

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(NotchTab.allCases) { tab in
                FluidoTabButton(
                    tab: tab,
                    isSelected: model.tab == tab,
                    badge: tab == .agents && model.demo.waitingAgent != nil,
                    namespace: namespace
                ) {
                    withAnimation(reduceMotion ? Fluido.Motion.reduced : .spring(duration: 0.38, bounce: 0.22)) { model.tab = tab }
                }
            }
        }
    }
}

private struct FluidoTabButton: View {
    let tab: NotchTab
    let isSelected: Bool
    let badge: Bool
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.fluidoSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected || isHovering
                        ? AnyShapeStyle(tab.fluidoLight.linear(.topLeading, .bottomTrailing))
                        : AnyShapeStyle(Fluido.Palette.textSecondary))
                    .overlay(alignment: .topTrailing) {
                        if badge && !isSelected {
                            LightDot(light: .agents, size: 5)
                                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                                .offset(x: 3.5, y: -2.5)
                        }
                    }
                if isSelected {
                    Text(tab.title)
                        .font(Fluido.Typography.tab)
                        .foregroundStyle(Fluido.Palette.text)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.9, anchor: .leading)),
                            removal: .opacity
                        ))
                }
            }
            .padding(.horizontal, isSelected ? 11 : 8)
            .frame(height: 26)
            .background {
                if isSelected {
                    Color.clear
                        .fluidoGlass(Capsule(), light: tab.fluidoLight, tint: 0.7)
                        .matchedGeometryEffect(id: "fluidoTab", in: namespace)
                } else if isHovering {
                    Capsule().fill(Color.white.opacity(0.07))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Fluido.Motion.hover) { isHovering = hovering } }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Header accessory

private struct FluidoHeaderAccessory: View {
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
            HStack(spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(model.shelf.count)")
                        .font(Fluido.Typography.earFigure)
                        .foregroundStyle(Fluido.Palette.text)
                        .contentTransition(.numericText(value: Double(model.shelf.count)))
                    Text(model.shelf.count == 1 ? "cosa" : "cosas")
                        .font(Fluido.Typography.caption)
                        .foregroundStyle(Fluido.Palette.textTertiary)
                }
                Button("Vaciar") { model.actions.clearShelf() }
                    .buttonStyle(FluidoButtonStyle(height: 24))
            }
        }
    }

    private var usage: some View {
        HStack(spacing: 6) {
            LightDot(light: .agents, size: 5)
            Text("hace \(NotchFormat.ago(model.demo.usageUpdatedAt).replacingOccurrences(of: "hace ", with: ""))")
                .font(Fluido.Typography.countdown)
                .foregroundStyle(Fluido.Palette.textTertiary)
        }
    }

    private var agents: some View {
        let waiting = model.demo.agents.count { $0.phase.needsUser }
        let working = model.demo.workingAgentsCount
        return HStack(spacing: 10) {
            if waiting > 0 {
                HStack(spacing: 5) {
                    LightDot(light: .agents, size: 5)
                    Text("\(waiting) te necesita")
                        .foregroundStyle(Fluido.Palette.text)
                }
            }
            if working > 0 {
                Text("\(working) trabajando")
                    .foregroundStyle(Fluido.Palette.textTertiary)
            }
        }
        .font(Fluido.Typography.countdown)
    }
}
