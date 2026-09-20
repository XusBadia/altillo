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
            .frame(height: chrome.contentHeight, alignment: .top)
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
            let sideZone = max(0, (chrome.size.width - chrome.notchWidth) / 2 - chrome.topRadius - Self.bandInset)
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
            .padding(.horizontal, chrome.topRadius + Self.bandInset)
        } else {
            // No camera to dodge: one plain row.
            HStack(spacing: 12) {
                tabs
                Spacer(minLength: 8)
                accessory
            }
            .frame(height: chrome.bandHeight)
            .padding(.horizontal, chrome.topRadius + Self.bandInset)
        }
    }

    /// Room kept between the silhouette's fillet and the band's content. Every point counts: beside the camera
    /// the narrowest notch only leaves ~105 pt a side.
    private static let bandInset: CGFloat = 6

    private var tabs: some View {
        DesvanTabs(model: model)
            .opacity(isDropTarget ? 0.4 : 1)
            .allowsHitTesting(!isDropTarget)
    }

    private var accessory: some View {
        DesvanHeaderAccessory(model: model, isDropTarget: isDropTarget)
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
            case .drawer: DesvanDrawerView(model: model)
            }
        }
    }
}

// MARK: - Tabs

/// The open notch's menu: one icon per module and, on the active one only, its name inside a raised plaque that
/// grows and shrinks with a spring as the selection moves (PLAN §4).
///
/// Beside a hardware notch there is very little room (at the narrowest width, ~105 pt for up to six modules), so the
/// strip has four densities and `ViewThatFits` picks the roomiest one that still fits. The last one drops the name;
/// every icon always carries the module's name as a tooltip and as its accessibility label.
private struct DesvanTabs: View {
    let model: NotchModel
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ViewThatFits(in: .horizontal) {
            strip(.roomy)
            strip(.snug)
            strip(.tight)
            strip(.cramped)
            strip(.iconsOnly)
            overflowMenu(showTitle: true)
            overflowMenu(showTitle: false)
        }
        .animation(Desvan.Motion.pick(.spring(duration: 0.3, bounce: 0.18), reduceMotion: reduceMotion),
                   value: model.module)
    }

    /// Seven sections cannot fit beside a hardware notch at narrow widths.
    /// A named menu keeps every section reachable without shrinking the targets further.
    private func overflowMenu(showTitle: Bool) -> some View {
        Menu {
            ForEach(model.settings.modules) { tab in
                Button { model.module = tab } label: {
                    Label(tab.title, systemImage: tab.symbol)
                }
            }
        } label: {
            Group {
                if showTitle { Label(model.module.title, systemImage: model.module.symbol) }
                else { Image(systemName: model.module.symbol) }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Choose a section")
        .accessibilityLabel("Sections, \(model.module.title) selected")
    }

    private func strip(_ metrics: DesvanTabMetrics) -> some View {
        HStack(spacing: metrics.spacing) {
            ForEach(model.settings.modules) { tab in
                DesvanTabButton(
                    tab: tab,
                    isSelected: model.module == tab,
                    knocks: tab == .agents && model.scenario != nil && model.demo.waitingAgent != nil,
                    metrics: metrics,
                    namespace: namespace
                ) {
                    withAnimation(Desvan.Motion.pick(.spring(duration: 0.3, bounce: 0.18), reduceMotion: reduceMotion)) {
                        model.module = tab
                    }
                }
            }
        }
        .fixedSize()
    }
}

/// How tightly the tab strip is packed. Every density keeps the same anatomy; only the numbers shrink.
private struct DesvanTabMetrics: Hashable {
    /// Point size of the module's symbol.
    var icon: CGFloat
    /// Width of an inactive tab (the icon's tap target).
    var slot: CGFloat
    /// Point size of the active tab's name, or `nil` when there is no room for it.
    var label: CGFloat?
    /// Horizontal padding inside the active plaque.
    var padding: CGFloat
    /// Icon-to-name gap.
    var gap: CGFloat
    var spacing: CGFloat

    static let roomy = DesvanTabMetrics(icon: 12.5, slot: 26, label: 12, padding: 9, gap: 5, spacing: 2)
    static let snug = DesvanTabMetrics(icon: 12, slot: 22, label: 11.5, padding: 8, gap: 4, spacing: 1)
    static let tight = DesvanTabMetrics(icon: 11, slot: 19, label: 11, padding: 7, gap: 3.5, spacing: 0)
    static let cramped = DesvanTabMetrics(icon: 10.5, slot: 17, label: 10.5, padding: 6, gap: 3, spacing: 0)
    /// Last resort (six modules at the narrowest width): the name lives in the tooltip only.
    static let iconsOnly = DesvanTabMetrics(icon: 11, slot: 17, label: nil, padding: 6, gap: 0, spacing: 0)

    var height: CGFloat { 22 }
}

private struct DesvanTabButton: View {
    let tab: NotchModule
    let isSelected: Bool
    let knocks: Bool
    let metrics: DesvanTabMetrics
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: metrics.gap) {
                icon
                    .frame(width: metrics.icon + 4, height: metrics.icon + 4)
                if isSelected, let size = metrics.label {
                    Text(tab.title)
                        .font(Desvan.Typeface.rounded(size, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .foregroundStyle(foreground)
            // On the plaque the label is pressed into the wood: a hairline of shade above, of light below.
            .shadow(color: .black.opacity(isSelected ? 0.7 : 0), radius: 0, y: -0.5)
            .padding(.horizontal, isSelected ? metrics.padding : 0)
            .frame(width: isSelected ? nil : metrics.slot, height: metrics.height)
            .background {
                if isSelected {
                    DesvanTabPlaque()
                        .matchedGeometryEffect(id: "tab", in: namespace)
                } else if isHovering {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Desvan.Palette.paper.opacity(0.08))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return Desvan.Palette.paper }
        return isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary
    }

    @ViewBuilder
    private var icon: some View {
        switch tab {
        case .shelf:
            DesvanHouseMark(size: metrics.icon, lit: isSelected ? 1 : (isHovering ? 0.5 : 0.25),
                            outline: foreground)
        case .agents where knocks:
            // The knock only happens with a live (or scripted) agent waiting; it stays on the icon.
            DesvanKnockingHand(size: metrics.icon - 1.5)
        default:
            Image(systemName: tab.symbol)
                .font(.system(size: metrics.icon - 1, weight: .medium))
                .symbolRenderingMode(.hierarchical)
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

/// The right-hand side of the band: what the active module has to say, and its one action. Like the tabs it has
/// several lengths and keeps the longest one that fits the room left beside the notch.
/// Opens the Settings window from the notch itself: there is no Dock icon and no menu bar to discover.
private struct DesvanSettingsButton: View {
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape")
                .font(.system(size: 11, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .frame(width: 20, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Desvan.Palette.paper.opacity(isHovering ? 0.10 : 0))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Ajustes de Altillo")
        .accessibilityLabel("Ajustes de Altillo")
    }
}

private struct DesvanHeaderAccessory: View {
    let model: NotchModel
    let isDropTarget: Bool

    var body: some View {
        HStack(spacing: 6) {
            summary
            if !isDropTarget {
                DesvanSettingsButton { model.actions.openSettings() }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var summary: some View {
        Group {
            if isDropTarget {
                EmptyView()
            } else if model.module == .usage || model.module == .agents, model.scenario == nil {
                // Only usage and agents still show sample data, until their modules exist (phases 3 and 4).
                ViewThatFits(in: .horizontal) {
                    sampleCaption("Datos de ejemplo")
                    sampleCaption("Ejemplo")
                }
            } else {
                switch model.module {
                case .shelf: shelf
                case .usage: usage
                case .agents: agents
                case .calendar, .mirror, .nowPlaying, .drawer: EmptyView()
                }
            }
        }
        .lineLimit(1)
    }

    private static let caption = Desvan.Typeface.rounded(11, weight: .medium)

    private func sampleCaption(_ text: String) -> some View {
        Text(text)
            .font(Self.caption)
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .fixedSize()
    }

    // MARK: Shelf

    @ViewBuilder
    private var shelf: some View {
        if !model.shelf.isEmpty {
            ViewThatFits(in: .horizontal) {
                // "Vaciar" is the action, so it keeps its word for as long as possible; the status gives way first.
                shelfRow(status: .long, clear: .word)
                shelfRow(status: .short, clear: .word)
                shelfRow(status: .none, clear: .word)
                shelfRow(status: .short, clear: .glyph)
                shelfRow(status: .none, clear: .glyph)
            }
            .animation(Desvan.Motion.hover, value: model.selection.isEmpty)
        }
    }

    private enum ShelfStatus { case long, short, none }
    private enum ClearButton { case word, glyph }

    @ViewBuilder
    private func shelfRow(status: ShelfStatus, clear: ClearButton) -> some View {
        HStack(spacing: 6) {
            if model.isReceivingDrop {
                Label(status == .long ? "Guardando…" : "…", systemImage: "arrow.down.circle")
                    .font(Self.caption)
                    .foregroundStyle(Desvan.Palette.bulb)
            } else if model.shelfProblem != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Desvan.Palette.warning)
                    .help(model.shelfProblem ?? "")
                    .accessibilityLabel(model.shelfProblem ?? "Problema con el altillo")
            } else {
                switch status {
                case .long: shelfStatusLong
                case .short: shelfStatusShort
                case .none: EmptyView()
                }
            }
            switch clear {
            case .word:
                Button("Vaciar") { model.actions.clearShelf() }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
            case .glyph:
                Button { model.actions.clearShelf() } label: {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
                .help("Vaciar el altillo")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var shelfStatusLong: some View {
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
    }

    @ViewBuilder
    private var shelfStatusShort: some View {
        if model.selection.isEmpty {
            Text("\(model.shelf.count)")
                .font(Desvan.Typeface.figure(12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .contentTransition(.numericText(value: Double(model.shelf.count)))
                .help("\(NotchFormat.things(model.shelf.count)) en el altillo")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "space").font(.system(size: 9.5, weight: .medium))
                Image(systemName: "delete.left").font(.system(size: 9.5, weight: .medium))
            }
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .help("Espacio: mirar · Retroceso: quitar")
        }
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .medium))
            Text(text)
        }
    }

    // MARK: Usage

    private var usage: some View {
        let ago = NotchFormat.ago(model.demo.usageUpdatedAt)
        return ViewThatFits(in: .horizontal) {
            usageRow(Text("Al día · \(ago)"))
            usageRow(Text(ago))
            usageRow(nil)
        }
    }

    private func usageRow(_ text: Text?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Desvan.Palette.done).frame(width: 5, height: 5)
            if let text {
                text
                    .font(Self.caption)
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .monospacedDigit()
            }
        }
        .fixedSize()
        .help("Al día · \(NotchFormat.ago(model.demo.usageUpdatedAt))")
    }

    // MARK: Agents

    private var agents: some View {
        let waiting = model.demo.agents.count { $0.phase.needsUser }
        let working = model.demo.workingAgentsCount
        return ViewThatFits(in: .horizontal) {
            agentsRow(waiting: waiting, working: working, long: true)
            agentsRow(waiting: waiting, working: working, long: false)
        }
        .help(agentsSummary(waiting: waiting, working: working))
    }

    private func agentsRow(waiting: Int, working: Int, long: Bool) -> some View {
        HStack(spacing: long ? 10 : 8) {
            if waiting > 0 {
                Group {
                    if long {
                        Text("\(waiting) llama a la puerta")
                    } else {
                        Label("\(waiting)", systemImage: "hand.raised")
                    }
                }
                .foregroundStyle(Desvan.Palette.bulb)
            }
            if working > 0 {
                Group {
                    if long {
                        Text("\(working) trabajando")
                    } else {
                        Label("\(working)", systemImage: "gearshape")
                    }
                }
                .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .font(Self.caption)
        .labelStyle(.desvanCompact)
        .monospacedDigit()
        .fixedSize()
    }

    private func agentsSummary(waiting: Int, working: Int) -> String {
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) llama a la puerta") }
        if working > 0 { parts.append("\(working) trabajando") }
        return parts.joined(separator: " · ")
    }
}

/// A label with its symbol tight against the figure, for the narrow band.
private struct DesvanCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9.5, weight: .semibold))
            configuration.title
        }
    }
}

private extension LabelStyle where Self == DesvanCompactLabelStyle {
    static var desvanCompact: DesvanCompactLabelStyle { DesvanCompactLabelStyle() }
}
