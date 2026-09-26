import AltilloCore
import AltilloDesign
import SwiftUI

/// The open attic: a header band beside the notch (tabs left, context right) and the active tab below, lit by the
/// bulb hanging under the notch. While a drag hovers (`dropTarget`) the body becomes the box and the paper plane.
/// In edit mode (`model.isEditing`) the band holds the ears as slots and the body the editor (`DesvanEditBody`).
struct DesvanExpandedFace: View {
    let model: NotchModel
    let chrome: NotchChrome
    let flicker: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Which way the body is swapping (not observed: read by the transition as it runs).
    @State private var swap = SectionSwap()
    /// The current edit-mode visit: its undo steps, the selected ear, drags in flight.
    @State private var editSession = NotchEditSession()

    private var isDropTarget: Bool { model.state == .dropTarget }
    private var isEditing: Bool { model.isEditing && !isDropTarget }
    private var bodyKey: String { isDropTarget ? "drop" : (isEditing ? "edit" : model.module.rawValue) }
    private var hoveredZone: DropZone? {
        guard model.scenario == .dropTarget || model.scenario?.isAskDropTarget == true else { return model.dropZone }
        // `-demoMotion flaps`: the pointer comes and goes over the box.
        if DesvanDebug.demoMotion == .flaps { return DesvanDebug.clock.phase ? .shelf : nil }
        return DesvanDebug.forcedZone
    }

    var body: some View {
        VStack(spacing: NotchChrome.expandedContentGap) {
            if chrome.showsDrawer {
                // Keep the camera band clear; the Drawer stays above navigation in every section.
                ZStack {
                    if isEditing {
                        DesvanEditBand(model: model, chrome: chrome, session: editSession)
                            .transition(.opacity)
                    } else {
                        Color.clear
                    }
                }
                .frame(height: chrome.bandHeight)
                DesvanDrawerView(model: model)
                    .padding(.horizontal, chrome.contentInset)
                ZStack {
                    if isEditing {
                        Text("Drag the tabs to reorder them, or onto an ear.")
                            .font(.system(size: 12))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    } else {
                        HStack(spacing: 12) {
                            tabs
                            Spacer(minLength: 8)
                            accessory
                        }
                        .contentShape(Rectangle())
                        .contextMenu { customizeMenu }
                        .transition(.opacity)
                    }
                }
                .frame(height: NotchChrome.drawerNavigationHeight)
                .padding(.horizontal, chrome.contentInset)
            } else {
                ZStack {
                    if isEditing {
                        DesvanEditBand(model: model, chrome: chrome, session: editSession)
                            .transition(.opacity)
                    } else {
                        header
                            .contentShape(Rectangle())
                            .contextMenu { customizeMenu }
                            .transition(.opacity)
                    }
                }
            }
            let direction = swap.direction(for: bodyKey, modules: model.settings.modules,
                                           moduleDirection: model.moduleDirection)
            ZStack(alignment: .top) {
                content
                    .id(bodyKey)
                    .transition(DesvanSectionTransition(swap: swap, reduceMotion: reduceMotion))
            }
            .frame(height: chrome.contentHeight, alignment: .top)
            .padding(.horizontal, chrome.contentInset)
            // Neighbouring sections slide with the tab plaque's spring, so the two read as one motion.
            .animation(Desvan.Motion.pick(direction == 0 ? Desvan.Motion.content : Desvan.Motion.section,
                                          reduceMotion: reduceMotion), value: bodyKey)
            .modifier(DesvanEdgeLean(bump: model.edgeBump, direction: model.edgeBumpDirection))
            .zIndex(1) // A tab dragged up towards an ear floats over the band.
        }
        .frame(width: chrome.size.width, height: chrome.size.height, alignment: .top)
        .coordinateSpace(.named(DesvanEdit.space))
        .overlay { DesvanEditDragGhost(session: editSession) }
        .onChange(of: model.isEditing, initial: true) { _, editing in
            if editing { editSession.begin(with: model.settings) }
        }
        .overlay {
            // The bulb hangs just under the notch; its light warms whatever sits below.
            // The band beside the notch stays pure black so it melts into the hardware notch.
            DesvanBulbGlow(intensity: glow + flicker, radius: 200, originY: chrome.bandHeight)
                .animation(Desvan.Motion.pick(.easeInOut(duration: 0.25), reduceMotion: reduceMotion), value: glow)
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

    /// Right-click on the open notch's band: the way into edit mode from inside (the closed notch has its own).
    @ViewBuilder
    private var customizeMenu: some View {
        Button("Customize the Notch…") { model.actions.beginEditing() }
        Button("Altillo Settings…") { model.actions.openSettings() }
    }

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
        } else if isEditing {
            DesvanEditBody(model: model, session: editSession)
        } else {
            switch model.module {
            case .shelf: DesvanShelfView(model: model)
            case .assistant: DesvanAssistantView(model: model)
            case .usage: DesvanUsageView(model: model)
            case .agents: DesvanAgentsView(model: model)
            case .calendar: DesvanCalendarView(model: model)
            case .mirror: DesvanMirrorView(model: model)
            case .nowPlaying: DesvanNowPlayingView(model: model)
            case .timer: DesvanTimerView(model: model)
            case .note: DesvanNoteView(model: model)
            case .clipboard: DesvanClipboardView(model: model)
            case .shortcuts: DesvanShortcutsView(model: model)
            case .keepAwake: DesvanKeepAwakeView(model: model)
            }
        }
    }
}

// MARK: - Section motion

/// Remembers the body's key so a section change knows which way to slide. Not observed: it is updated while the face
/// is evaluated and read by the transition as it runs, so the leaving section and the arriving one agree on the
/// direction (the leaving one keeps the transition it was last drawn with, which predates the change).
@MainActor
private final class SectionSwap {
    private var key: String?
    private(set) var current = 0

    /// The slide direction for the swap to `newKey`: the model's, when it really came from a neighbour in the tab
    /// strip (tabs, ⌘1–9, ⌃Tab, swipes); 0 (a vertical crossfade) for the drop box, a jump or anything else.
    func direction(for newKey: String, modules: [NotchModule], moduleDirection: Int) -> Int {
        guard newKey != key else { return current }
        defer { key = newKey }
        guard let key else { return current }
        current = Desvan.Motion.sectionDirection(from: key, to: newKey, modules: modules,
                                                 moduleDirection: moduleDirection)
        return current
    }
}

/// The body's swap: sideways with the section (`SlideSwapTransition`), a vertical crossfade otherwise.
private struct DesvanSectionTransition: Transition {
    let swap: SectionSwap
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        SlideSwapTransition(direction: swap.current, reduceMotion: reduceMotion).apply(content: content, phase: phase)
    }
}

/// Rubber band at either end of the tab strip: a swipe past the first or last section tugs the body a few points
/// the way the fingers went (where the next section would have come from) and it springs back. With Reduce Motion
/// it stays still.
private struct DesvanEdgeLean: ViewModifier {
    let bump: Int
    let direction: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let pull = -CGFloat(direction.signum()) * Desvan.Motion.edgeLean
        content.keyframeAnimator(initialValue: CGFloat.zero, trigger: reduceMotion ? 0 : bump) { content, lean in
            content.offset(x: lean)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(pull, duration: 0.09)
                SpringKeyframe(0, duration: 0.45, spring: Spring(duration: 0.4, bounce: 0.3))
            }
        }
    }
}

/// Presses for the notch's small plain buttons (tabs, the gear): they give a touch (94 %) in ≈ 100 ms and come
/// back without a wobble. Hover highlights stay with each button.
private struct DesvanPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

// MARK: - Tabs

/// The open notch's menu: one icon per module and, on the active one only, its name inside a raised plaque that
/// grows and shrinks with a spring as the selection moves (PLAN §4).
///
/// Beside a hardware notch there is very little room (at the narrowest width, ~105 pt a side for up to seven
/// sections), and the targets never shrink below `DesvanHitTarget.minimum`: fewer, larger tabs beat a crammed strip.
/// So `ViewThatFits` tries every section at two densities, then the first few with the active one always among them
/// and the rest behind a "More" menu, and last a single menu named after the active section. Every icon carries the
/// module's name as a tooltip and as its accessibility label.
private struct DesvanTabs: View {
    let model: NotchModel
    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = model.settings.modules.count
        ViewThatFits(in: .horizontal) {
            strip(.roomy, visible: count)
            strip(.snug, visible: count)
            // Fewer tabs with the active one's name, before any tab loses its size or the name disappears; then,
            // in the narrowest band, icons only, still full size. (One `ForEach`: `ViewThatFits` needs unique IDs.)
            ForEach(Self.fallbacks(count: count), id: \.self) { fallback in
                strip(fallback.labelled ? .snug : .iconsOnly, visible: fallback.visible)
            }
            overflowMenu(showTitle: true)
            overflowMenu(showTitle: false)
        }
        .animation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion), value: model.module)
    }

    private struct Fallback: Hashable {
        var labelled: Bool
        var visible: Int
    }

    /// The partial strips, roomiest first: `count - 1` down to 2 named tabs plus "More", then 3 down to 1 icons.
    private static func fallbacks(count: Int) -> [Fallback] {
        let labelled = count > 2 ? (2..<count).reversed().map { Fallback(labelled: true, visible: $0) } : []
        let icons = (1...max(min(count, 3), 1)).reversed().map { Fallback(labelled: false, visible: $0) }
        return labelled + icons
    }

    /// The first `count` sections in order, with the active one swapped in for the last of them when it would be
    /// hidden, so the strip always says where you are.
    private func shown(_ count: Int) -> [NotchModule] {
        let modules = model.settings.modules
        guard count < modules.count, count > 0 else { return modules }
        var shown = Array(modules.prefix(count))
        if !shown.contains(model.module), modules.contains(model.module) { shown[count - 1] = model.module }
        return shown
    }

    /// Seven sections cannot fit beside a hardware notch at narrow widths.
    /// A named menu keeps every section reachable without shrinking the targets further.
    private func overflowMenu(showTitle: Bool) -> some View {
        Menu {
            sectionItems(model.settings.modules)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.module.symbol)
                    .font(.system(size: DesvanTabMetrics.snug.icon - 1, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                if showTitle {
                    Text(model.module.title)
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .fixedSize()
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            .foregroundStyle(Desvan.Palette.paper)
            .padding(.horizontal, 9)
            .frame(minWidth: DesvanHitTarget.minimum, minHeight: DesvanTabMetrics.height)
            .background { DesvanTabPlaque() }
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a section")
        .accessibilityLabel("Sections, \(model.module.title) selected")
    }

    /// The sections that didn't fit, one click away.
    private func moreMenu(_ hidden: [NotchModule]) -> some View {
        Menu {
            sectionItems(hidden)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .frame(width: DesvanTabMetrics.snug.slot, height: DesvanTabMetrics.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More sections")
        .accessibilityLabel("More sections")
    }

    @ViewBuilder
    private func sectionItems(_ modules: [NotchModule]) -> some View {
        ForEach(modules) { tab in
            Button { select(tab) } label: {
                Label(tab.title, systemImage: tab.symbol)
            }
        }
    }

    private func select(_ tab: NotchModule) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.section, reduceMotion: reduceMotion)) {
            model.select(tab)
        }
    }

    private func strip(_ metrics: DesvanTabMetrics, visible: Int) -> some View {
        let tabs = shown(visible)
        let hidden = model.settings.modules.filter { !tabs.contains($0) }
        return HStack(spacing: metrics.spacing) {
            ForEach(tabs) { tab in
                DesvanTabButton(
                    tab: tab,
                    isSelected: model.module == tab,
                    knocks: tab == .agents && model.agentSessions.contains { $0.phase.needsUser },
                    metrics: metrics,
                    namespace: namespace
                ) {
                    select(tab)
                }
            }
            if !hidden.isEmpty { moreMenu(hidden) }
        }
        .fixedSize()
    }
}

/// How tightly the tab strip is packed. Every density keeps the same anatomy and never goes below the minimum
/// target (28 × 28 pt) or a 13 pt icon; when even the snug one doesn't fit, sections move to a menu instead.
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

    static let roomy = DesvanTabMetrics(icon: 15, slot: 32, label: 12.5, padding: 10, gap: 5, spacing: 2)
    static let snug = DesvanTabMetrics(icon: 14, slot: 28, label: 12.5, padding: 8, gap: 4, spacing: 1)
    /// Last strip before the menus: the name lives in the tooltip only.
    static let iconsOnly = DesvanTabMetrics(icon: 14, slot: 28, label: nil, padding: 7, gap: 0, spacing: 1)

    /// Fits the band beside the smallest hardware notch (32 pt) and the Drawer's navigation row.
    static let height: CGFloat = DesvanHitTarget.minimum
    var height: CGFloat { Self.height }
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
            .frame(minWidth: metrics.slot)
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
        .buttonStyle(DesvanPressStyle())
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
/// The Settings window's tab bar uses it too.
struct DesvanTabPlaque: View {
    var cornerRadius: CGFloat = 7

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .frame(width: DesvanHitTarget.minimum, height: DesvanHitTarget.minimum)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Desvan.Palette.paper.opacity(isHovering ? 0.10 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(DesvanPressStyle())
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help("Altillo Settings")
        .accessibilityLabel("Altillo Settings")
    }
}

private struct DesvanHeaderAccessory: View {
    let model: NotchModel
    let isDropTarget: Bool

    var body: some View {
        HStack(spacing: 4) {
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
            } else {
                switch model.module {
                case .shelf: shelf
                case .usage: usage
                case .agents: agents
                case .assistant, .calendar, .mirror, .nowPlaying, .timer, .note, .clipboard, .shortcuts, .keepAwake:
                    EmptyView()
                }
            }
        }
        .lineLimit(1)
    }

    private static let caption = Desvan.Typeface.rounded(11.5, weight: .medium)

    // MARK: Shelf

    @ViewBuilder
    private var shelf: some View {
        if !model.shelf.isEmpty {
            ViewThatFits(in: .horizontal) {
                // "Empty" is the action, so it keeps its word for as long as possible; the status gives way first.
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
                Label(status == .long ? "Putting up…" : "…", systemImage: "arrow.down.circle")
                    .font(Self.caption)
                    .foregroundStyle(Desvan.Palette.bulb)
            } else if model.shelfProblem != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Desvan.Palette.warning)
                    .help(model.shelfProblem ?? "")
                    .accessibilityLabel(model.shelfProblem ?? String(localized: "Shelf problem"))
            } else {
                switch status {
                case .long: shelfStatusLong
                case .short: shelfStatusShort
                case .none: EmptyView()
                }
            }
            switch clear {
            case .word:
                Button("Empty") { model.actions.clearShelf() }
                    .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
            case .glyph:
                Button { model.actions.clearShelf() } label: {
                    Image(systemName: "arrow.down.to.line").font(.system(size: 12.5, weight: .semibold))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
                .accessibilityLabel("Empty the shelf")
                .help("Empty the shelf")
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var shelfStatusLong: some View {
        if model.selection.isEmpty {
            let figure = Text("\(model.shelf.count)")
                .font(Desvan.Typeface.figure(12.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            (model.shelf.count == 1 ? Text("\(figure) thing up there") : Text("\(figure) things up there"))
                .font(Self.caption)
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .contentTransition(.numericText(value: Double(model.shelf.count)))
                .help("Drag it out to take it down")
        } else {
            // With something picked, the keys that act on it.
            HStack(spacing: 10) {
                hint("space", "Look")
                hint("delete.left", "Remove")
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
                .font(Desvan.Typeface.figure(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .contentTransition(.numericText(value: Double(model.shelf.count)))
                .help("\(NotchFormat.things(model.shelf.count)) on the shelf")
        } else {
            HStack(spacing: 8) {
                Image(systemName: "space").font(.system(size: 11, weight: .medium))
                Image(systemName: "delete.left").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Desvan.Palette.paperTertiary)
            .help("Space: look · Delete: remove")
        }
    }

    private func hint(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
            Text(text)
        }
    }

    // MARK: Usage

    /// "Up to date · 2 min ago" (or "Stale · 20 min ago" in mustard) and the refresh button. Design scenarios show
    /// the sample numbers' age and a button that does nothing.
    @ViewBuilder
    private var usage: some View {
        if model.scenario != nil {
            DesvanUsageStatus(freshness: .upToDate(since: model.demo.usageUpdatedAt), isRefreshing: false,
                              refresh: {})
        } else if !model.usage.providers.isEmpty || model.usage.isRefreshing {
            DesvanUsageStatus(freshness: model.usage.freshness(), isRefreshing: model.usage.isRefreshing,
                              refresh: { model.usage.refreshNow() })
        }
    }

    // MARK: Agents

    /// "1 knocking · 2 working" (the sample sessions' in a design review); nothing when nobody is at work.
    @ViewBuilder
    private var agents: some View {
        let counts = AgentsLogic.counts(model.agentSessions)
        if let summary = AgentsLogic.summary(counts) {
            ViewThatFits(in: .horizontal) {
                agentsRow(counts, long: true)
                agentsRow(counts, long: false)
            }
            .help(summary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
        }
    }

    private func agentsRow(_ counts: AgentsLogic.Counts, long: Bool) -> some View {
        HStack(spacing: long ? 10 : 8) {
            if counts.waiting > 0 {
                Group {
                    if long {
                        Text("\(counts.waiting) knocking")
                    } else {
                        Label("\(counts.waiting)", systemImage: "hand.raised")
                    }
                }
                .foregroundStyle(Desvan.Palette.bulb)
            }
            if counts.working > 0 {
                Group {
                    if long {
                        Text("\(counts.working) working")
                    } else {
                        Label("\(counts.working)", systemImage: "gearshape")
                    }
                }
                .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .font(Self.caption)
        .labelStyle(.desvanCompact)
        .monospacedDigit()
        .fixedSize()
        .padding(.trailing, 4)
    }
}

/// How fresh the usage numbers are, and a button to fetch them now. The text gives way before the button does, and
/// the age ticks along (every 30 s) only while it's on screen.
private struct DesvanUsageStatus: View {
    let freshness: UsageStore.Freshness
    let isRefreshing: Bool
    let refresh: () -> Void

    private static let caption = Desvan.Typeface.rounded(11.5, weight: .medium)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    row(long: true, now: context.date)
                    row(long: false, now: context.date)
                    dot
                }
                button
            }
            .help(help(now: context.date))
        }
        .fixedSize()
    }

    private func row(long: Bool, now: Date) -> some View {
        HStack(spacing: 5) {
            dot
            Text(verbatim: text(long: long, now: now))
                .font(Self.caption)
                .foregroundStyle(isStale ? Desvan.Palette.warning : Desvan.Palette.paperTertiary)
                .monospacedDigit()
                .contentTransition(.opacity)
        }
        .fixedSize()
    }

    private var dot: some View {
        Circle()
            .fill(isStale ? Desvan.Palette.warning : Desvan.Palette.done)
            .frame(width: 5, height: 5)
            .opacity(isRefreshing ? 0.4 : 1)
            .accessibilityHidden(true)
    }

    private var button: some View {
        Button(action: refresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: isRefreshing)
                .frame(width: DesvanHitTarget.minimum, height: DesvanHitTarget.minimum)
                .contentShape(Rectangle())
        }
        .buttonStyle(DesvanPressStyle())
        .disabled(isRefreshing)
        .help("Refresh now")
        .accessibilityLabel("Refresh AI usage")
    }

    private var isStale: Bool {
        if case .stale = freshness { return true }
        return false
    }

    private func text(long: Bool, now: Date) -> String {
        if isRefreshing, long { return String(localized: "Refreshing…") }
        switch freshness {
        case let .upToDate(since):
            return long ? String(localized: "Up to date · \(NotchFormat.ago(since, now: now))") : NotchFormat.ago(since, now: now)
        case let .stale(since):
            return long ? String(localized: "Stale · \(NotchFormat.ago(since, now: now))") : String(localized: "Stale")
        case .nothing:
            return isRefreshing ? String(localized: "Refreshing…") : ""
        }
    }

    private func help(now: Date) -> String {
        switch freshness {
        case let .upToDate(since): String(localized: "Up to date · \(NotchFormat.ago(since, now: now))")
        case let .stale(since): String(localized: "These numbers are from \(NotchFormat.ago(since, now: now)). Altillo keeps trying every 5 min.")
        case .nothing: String(localized: "Refresh now")
        }
    }
}

/// A label with its symbol tight against the figure, for the narrow band.
private struct DesvanCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 10.5, weight: .semibold))
            configuration.title
        }
    }
}

private extension LabelStyle where Self == DesvanCompactLabelStyle {
    static var desvanCompact: DesvanCompactLabelStyle { DesvanCompactLabelStyle() }
}
