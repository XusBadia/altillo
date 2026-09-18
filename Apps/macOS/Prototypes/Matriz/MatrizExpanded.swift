import AltilloCore
import AltilloDesign
import SwiftUI

/// The open notch: a header band beside the notch (brand + tabs on the left, context on the right) and the active tab
/// below, written in by the scanline. While a drag hovers (`dropTarget`) the body becomes the two drop fields.
struct MatrizExpanded: View {
    let model: NotchModel
    let chrome: NotchChrome

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDropTarget: Bool { model.state == .dropTarget }
    private var bodyKey: String { isDropTarget ? "drop" : model.tab.rawValue }
    private var contentHeight: CGFloat { chrome.size.height - chrome.bandHeight - 8 - 14 }

    var body: some View {
        VStack(spacing: 8) {
            header
            ZStack(alignment: .top) {
                content
                    .id(bodyKey)
                    .transition(.scanline(reduceMotion: reduceMotion))
            }
            .frame(height: contentHeight, alignment: .top)
            .padding(.horizontal, chrome.contentInset)
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
        .background {
            // The switched-off display: a faint matrix that fades out towards the edges.
            DotGrid(color: Matriz.Palette.dotOff.opacity(0.6))
                .mask(RadialGradient(colors: [.white, .white.opacity(0)], center: .init(x: 0.5, y: 0.35), startRadius: 60, endRadius: 380))
        }
    }

    private var header: some View {
        let sideZone = (chrome.size.width - chrome.notchWidth) / 2 - chrome.topRadius - 12
        return HStack(spacing: 0) {
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .leading) {
                    HStack(spacing: 14) {
                        DotGlyph(Glyph7.roof, pitch: 3, dot: 2.2, color: Matriz.Palette.phosphor)
                            .accessibilityLabel("Altillo")
                        MatrizTabs(model: model)
                            .opacity(isDropTarget ? 0.4 : 1)
                            .allowsHitTesting(!isDropTarget)
                    }
                    .fixedSize()
                }
            Color.clear.frame(width: chrome.notchWidth)
            Color.clear
                .frame(width: sideZone)
                .overlay(alignment: .trailing) {
                    MatrizHeaderAccessory(model: model, isDropTarget: isDropTarget)
                        .fixedSize()
                }
        }
        .frame(height: chrome.bandHeight)
        .padding(.horizontal, chrome.topRadius + 12)
    }

    @ViewBuilder
    private var content: some View {
        if isDropTarget {
            MatrizDropFields(model: model)
        } else {
            switch model.tab {
            case .shelf: MatrizShelf(model: model)
            case .usage: MatrizUsage(demo: model.demo)
            case .agents: MatrizAgents(demo: model.demo)
            }
        }
    }
}

// MARK: - Tabs

extension NotchTab {
    var matrizTitle: String {
        switch self {
        case .shelf: "ALTILLO"
        case .usage: "USO"
        case .agents: "AGENTES"
        }
    }
}

/// Departure Mono labels. Active: phosphor with a 4-pt signal LED on its left; inactive: phosphor3.
struct MatrizTabs: View {
    let model: NotchModel

    var body: some View {
        HStack(spacing: 12) {
            ForEach(NotchTab.allCases) { tab in
                MatrizTab(
                    tab: tab,
                    isSelected: model.tab == tab,
                    waiting: tab == .agents && model.demo.waitingAgent != nil
                ) {
                    // Switching tabs is very frequent: no animation beyond the scanline of the new content.
                    model.tab = tab
                }
            }
        }
    }
}

private struct MatrizTab: View {
    let tab: NotchTab
    let isSelected: Bool
    let waiting: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                LED(color: Matriz.Palette.signal, size: 4, glows: isSelected)
                    .opacity(isSelected ? 1 : 0)
                Text(tab.matrizTitle)
                    .matrizLabel()
                    .foregroundStyle(isSelected ? Matriz.Palette.phosphor : isHovering ? Matriz.Palette.phosphor2 : Matriz.Palette.phosphor3)
                if waiting, !isSelected {
                    BreathingLED(size: 4)
                }
            }
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(MatrizPressStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.matrizTitle.capitalized)
        .accessibilityValue(waiting ? "Un agente espera" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Header accessory

/// Right side of the header: context for the active tab, in instrument labels.
private struct MatrizHeaderAccessory: View {
    let model: NotchModel
    let isDropTarget: Bool

    var body: some View {
        Group {
            if isDropTarget {
                Text("SUELTA PARA GUARDAR")
                    .matrizLabel()
                    .foregroundStyle(Matriz.Palette.phosphor3)
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
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    FlipCounter(value: model.shelf.count, font: Matriz.Fonts.departure(), color: Matriz.Palette.phosphor2, glows: false)
                    Text(model.shelf.count == 1 ? "COSA" : "COSAS").matrizLabel().foregroundStyle(Matriz.Palette.phosphor2)
                }
                MatrizButton(title: "VACIAR", kind: .quiet) { model.actions.clearShelf() }
            }
        }
    }

    private var usage: some View {
        HStack(spacing: 6) {
            LED(color: Matriz.Palette.phosphor, size: 4)
            Text("ACTUALIZADO \(NotchFormat.ago(model.demo.usageUpdatedAt).uppercased())")
                .matrizLabel()
                .foregroundStyle(Matriz.Palette.phosphor3)
        }
    }

    private var agents: some View {
        let waiting = model.demo.agents.count { $0.phase.needsUser }
        let working = model.demo.workingAgentsCount
        return HStack(spacing: 12) {
            if waiting > 0 {
                HStack(spacing: 6) {
                    BreathingLED(size: 5)
                    Text("\(waiting) ESPERA").matrizLabel().foregroundStyle(Matriz.Palette.signal)
                }
            }
            if working > 0 {
                HStack(spacing: 6) {
                    LEDSpinner(pitch: 2.5, dot: 1.8)
                    Text("\(working) EN MARCHA").matrizLabel().foregroundStyle(Matriz.Palette.phosphor2)
                }
            }
        }
    }
}
