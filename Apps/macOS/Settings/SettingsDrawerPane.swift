import AppKit
import SwiftUI

/// Lets people move real menu bar items between Altillo and the visible menu bar.
@MainActor
struct SettingsDrawerPane: View {
    @Bindable private var store = MenuBarDrawerStore.shared
    @State private var drawerIsTargeted = false
    @State private var menuBarIsTargeted = false
    @State private var dropTargetEntryID: String?
    @State private var selectedEntryID: String?
    @State private var draggedEntryID: String?
    @State private var dragLocation = CGPoint.zero
    @State private var zoneFrames: [Destination: CGRect] = [:]
    @State private var viewportFrames: [Destination: CGRect] = [:]
    @State private var cellFrames: [String: CGRect] = [:]
    @GestureState private var localDragIsActive = false
    @FocusState private var focusedEntryID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    nonisolated private static let arrangementSpace = "drawer-arrangement"

    private var canMove: Bool {
        store.enabled && store.hasAccess && store.support.arranging
            && store.movingEntryID == nil && !store.isPerformingMenuBarInteraction
    }

    private var movingEntry: MenuBarEntry? {
        guard let id = store.movingEntryID else { return nil }
        return findEntry(withID: id)
    }

    private var revealAnimation: Animation {
        SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion)
    }

    var body: some View {
        SettingsPane(
            title: "Drawer",
            subtitle: "Drag menu bar icons between areas, or use each icon's menu."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    enableCard
                    if store.enabled, store.isSupported {
                        visibilityCard
                            .transition(.settingsReveal)
                    }
                    if let problem = store.problem {
                        problemNotice(problem)
                            .transition(.settingsReveal)
                    }

                    stateContent
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
                .animation(revealAnimation, value: store.enabled)
                .animation(revealAnimation, value: store.isSupported)
                .animation(revealAnimation, value: store.hasAccess)
                .animation(revealAnimation, value: store.hasIconAccess)
                .animation(revealAnimation, value: store.problem)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { store.setVisible(true, for: .settings) }
        .onDisappear {
            resetLocalDrag()
            store.setVisible(false, for: .settings)
            SettingsWindowController.shared.endMenuBarArrangement(restoreFocus: false)
        }
        .onChange(of: localDragIsActive) { _, active in
            if !active { resetLocalDrag() }
        }
        .onChange(of: store.movingEntryID) { previous, current in
            if current != nil {
                SettingsWindowController.shared.beginMenuBarArrangement()
            } else if previous != nil {
                SettingsWindowController.shared.endMenuBarArrangement()
            }
        }
    }

    /// The last thing that went wrong, on a warning wash so it reads as a state, not as a setting.
    private func problemNotice(_ problem: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(SettingsTone.warning.color)
                .accessibilityHidden(true)
            Text(verbatim: problem)
                .settingsHint()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            shape.fill(SettingsTone.warning.color.opacity(0.08))
                .overlay { shape.strokeBorder(SettingsTone.warning.color.opacity(0.22), lineWidth: 0.75) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drawer error: \(problem)")
    }

    private var visibilityCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: store.hidesDrawerIcons ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(store.hidesDrawerIcons ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 30, height: 30)
                    .background {
                        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                        shape.fill(Desvan.Palette.plank.opacity(0.85))
                            .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                    }
                    .animation(revealAnimation, value: store.hidesDrawerIcons)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Drawer icons from the menu bar")
                        .settingsRowTitle()
                    if store.support.hidingStyle == .overflow {
                        Text("On macOS 27, icons stay in the menu bar’s overflow area; they aren’t removed. Use Altillo’s arrow in the menu bar to reveal them. Icons from the same app may hide together.")
                            .settingsHint()
                    } else {
                        Text("Keeps them in Altillo without leaving a second copy visible in the menu bar.")
                            .settingsHint()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Toggle("Hide Drawer icons from the menu bar", isOn: Binding(
                    get: { store.hidesDrawerIcons },
                    set: { store.setHidesDrawerIcons($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!store.support.hiding || store.movingEntryID != nil)
                .help(store.hidesDrawerIcons
                    ? "Drawer icons are hidden from the visible menu bar"
                    : "Drawer icons also remain visible in the menu bar")
            }
        }
    }

    private var enableCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                SettingsGroupHeading(title: "Use Drawer", detail: "Keep selected icons within reach in Altillo.")

                Spacer(minLength: 12)

                if store.hasAccess, store.isSupported {
                    RefreshIconsButton(isLoading: store.isLoading) {
                        store.refresh(forceIcons: true, clearProblem: true)
                    }
                    .disabled(store.isLoading || store.movingEntryID != nil)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                Toggle("Use Drawer", isOn: Binding(
                    get: { store.enabled },
                    set: { store.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!store.isSupported || store.movingEntryID != nil)
            }
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if !store.isSupported {
            unsupportedNotice
                .transition(.settingsReveal)
        } else if !store.enabled {
            inactiveNotice
                .transition(.settingsReveal)
        } else if !store.hasAccess {
            permissionCard
                .transition(.settingsReveal)
        } else if store.requiresIconAccess && !store.hasIconAccess {
            iconPermissionCard
                .transition(.settingsReveal)
        } else {
            if store.support.isPartial {
                partialSupportCard
                    .transition(.settingsReveal)
            }
            arrangementContent
                .transition(.settingsReveal)
        }
    }

    /// What this version of macOS doesn't allow, so the missing part isn't mistaken for a fault.
    private var partialSupportCard: some View {
        SettingsCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Some Drawer features aren't available on this version of macOS")
                        .settingsRowTitle()
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if !store.support.hiding {
                        Text("Altillo can't hide menu bar icons here, so icons you keep in Altillo also stay in the menu bar. You can still open their menus from the Drawer.")
                            .settingsHint()
                    }
                    if !store.support.arranging {
                        Text("Icons can't be moved from here. Hold Command and drag them in the menu bar instead.")
                            .settingsHint()
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var iconPermissionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsGroupHeading(title: "Allow Screen Recording access")
                SettingsNotice(
                    symbol: "rectangle.dashed.badge.record",
                    message: "Allow Screen Recording so Altillo can display each icon as it appears in your menu bar."
                ) {
                    Button("Allow access") { store.requestIconAccess() }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
                }
            }
        }
    }

    private var permissionCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 10) {
                SettingsGroupHeading(title: "Allow Accessibility access")
                SettingsNotice(
                    symbol: "accessibility",
                    message: "Altillo uses it to find and move your menu bar icons."
                ) {
                    Button("Allow access") { store.requestAccess() }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
                }
            }
        }
    }

    private var unsupportedNotice: some View {
        SettingsNotice(
            symbol: "macwindow.badge.exclamationmark",
            message: "Drawer is not available on this version of macOS.",
            tone: .warning
        )
    }

    private var inactiveNotice: some View {
        SettingsNotice(
            symbol: "archivebox",
            message: "Turn on Drawer to choose which icons appear in Altillo.",
            tone: .neutral
        )
    }

    private var arrangementContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Group {
                    if let movingEntry {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Moving \(displayName(for: movingEntry))…")
                                .settingsHint()
                        }
                        .transition(.settingsReveal)
                    } else if store.isLoading {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Finding menu bar icons…")
                                .settingsHint()
                        }
                        .transition(.settingsReveal)
                    } else {
                        HStack(spacing: 7) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Desvan.Palette.paperTertiary)
                                .accessibilityHidden(true)
                            Text("Drag icons between areas, or open an icon's menu to move it.")
                                .settingsHint()
                        }
                        .transition(.settingsReveal)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18)
            .padding(.horizontal, 2)
            .animation(revealAnimation, value: store.movingEntryID)
            .animation(revealAnimation, value: store.isLoading)
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 10) {
                dropZone(
                    title: "Altillo",
                    symbol: "archivebox.fill",
                    entries: store.drawerEntries,
                    destination: .drawer,
                    isTargeted: $drawerIsTargeted
                )

                dropZone(
                    title: "Menu Bar",
                    symbol: "menubar.rectangle",
                    entries: store.menuBarEntries,
                    destination: .menuBar,
                    isTargeted: $menuBarIsTargeted
                )
            }
        }
        .overlay(alignment: .topLeading) {
            if let id = draggedEntryID, let entry = findEntry(withID: id) {
                dragPreview(for: entry)
                    .fixedSize()
                    .shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    .offset(x: dragLocation.x + 12, y: dragLocation.y + 12)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: Self.arrangementSpace)
    }

    private func dropZone(
        title: String,
        symbol: String,
        entries: [MenuBarEntry],
        destination: Destination,
        isTargeted: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Desvan.Typeface.rounded(13.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 4)
                if !store.isLoading || !entries.isEmpty {
                    SettingsBadge(
                        text: entries.count.formatted(),
                        tone: isTargeted.wrappedValue ? .accent : .neutral
                    )
                    .contentTransition(.numericText())
                    .animation(revealAnimation, value: entries.count)
                    .transition(.opacity)
                    .accessibilityLabel("\(entries.count) icons")
                }
            }
            .animation(Desvan.Motion.hover, value: isTargeted.wrappedValue)

            if entries.isEmpty {
                VStack(spacing: 7) {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityHidden(true)
                        Text("Finding menu bar icons…")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Desvan.Palette.paperSecondary)
                    } else {
                        Image(systemName: "square.dashed")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                            .symbolEffect(.bounce, value: isTargeted.wrappedValue)
                            .accessibilityHidden(true)
                        Text(isTargeted.wrappedValue ? "Drop here" : "Drag icons here")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.paper : Desvan.Palette.paperTertiary)
                            .contentTransition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(Desvan.Motion.hover, value: isTargeted.wrappedValue)
            } else {
                ScrollView(.vertical) {
                    MenuBarGlyphGrid() {
                        ForEach(entries, id: \.id) { entry in
                            iconCell(entry, destination: destination)
                        }
                    }
                    .padding(.trailing, 3)
                    .padding(.bottom, 2)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.arrangementSpace)) }) {
                    viewportFrames[destination] = $0
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230, alignment: .topLeading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape
                .fill(isTargeted.wrappedValue ? Desvan.Palette.bulb.opacity(0.10) : Desvan.Palette.woodRaised)
                .overlay {
                    shape.strokeBorder(
                        isTargeted.wrappedValue ? Desvan.Palette.bulb : Desvan.Palette.hairlineStrong,
                        lineWidth: isTargeted.wrappedValue ? 1.5 : 0.75
                    )
                }
                .animation(Desvan.Motion.hover, value: isTargeted.wrappedValue)
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.arrangementSpace)) }) {
            zoneFrames[destination] = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(store.isLoading && entries.isEmpty
            ? String(localized: "\(title), finding menu bar icons")
            : String(localized: "\(title), \(entries.count) icons"))
    }

    private func iconCell(_ entry: MenuBarEntry, destination: Destination) -> some View {
        MenuBarPopupAnchorReader(toolTip: entry.hoverName) { anchor in
            anchoredIconCell(entry, destination: destination, anchor: anchor)
        }
    }

    private func anchoredIconCell(_ entry: MenuBarEntry, destination: Destination,
                                  anchor: MenuBarPopupAnchor) -> some View {
        let isMoving = store.movingEntryID == entry.id
        let moveToDrawer = destination == .menuBar
        let actionTitle = moveToDrawer ? "Move to Altillo" : "Move to Menu Bar"

        let draggableCell = Button {
            selectedEntryID = entry.id
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(cellBackground(entry))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(cellBorder(entry), lineWidth: cellBorderWidth(entry))
                    }

                MenuBarGlyph(image: icon(for: entry))
                    .foregroundStyle(Desvan.Palette.paper)
                    .accessibilityHidden(true)

                if isMoving {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Desvan.Palette.wood.opacity(0.72))
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .frame(width: MenuBarGlyph.cellWidth(for: icon(for: entry).size), height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(Desvan.Motion.hover, value: cellBackground(entry))
            .animation(Desvan.Motion.hover, value: isMoving)
        }
        .buttonStyle(SettingsPressStyle(scale: 0.94))
        .disabled(store.movingEntryID != nil)
        .opacity(store.movingEntryID == nil || isMoving ? 1 : 0.55)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .named(Self.arrangementSpace)) }) {
            cellFrames[entry.id] = $0
        }
        .onDisappear { cellFrames[entry.id] = nil }
        .highPriorityGesture(localDrag(for: entry))

        return draggableCell
        .contextMenu { entryMenu(for: entry, destination: destination, anchor: anchor) }
        .focusable()
        .focusEffectDisabled()
        .focused($focusedEntryID, equals: entry.id)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(selectedEntryID == entry.id ? .isSelected : [])
        .accessibilityLabel("\(displayName(for: entry)), \(entry.application.name), in \(destination.title)")
        .accessibilityHint(destination == .drawer
            ? "Selects this icon. Drag to reorder or move it. Open its menu from the shortcut menu."
            : "Selects this icon. Drag to move it. Open its menu from the shortcut menu.")
        .help(entry.hoverName)
        .accessibilityAction {
            guard store.movingEntryID == nil else { return }
            selectedEntryID = entry.id
        }
        .accessibilityAction(named: Text(actionTitle)) {
            guard canMove else { return }
            store.move(entry, toDrawer: moveToDrawer)
        }
    }

    @ViewBuilder
    private func entryMenu(for entry: MenuBarEntry, destination: Destination,
                           anchor: MenuBarPopupAnchor) -> some View {
        Button("Open menu") { store.activate(entry, anchor: anchor) }
            .disabled(store.movingEntryID != nil)
        Divider()
        if destination == .drawer {
            Button("Move earlier", systemImage: "arrow.left") { reorder(entry, offset: -1) }
                .disabled(!canReorder(entry, offset: -1))
            Button("Move later", systemImage: "arrow.right") { reorder(entry, offset: 1) }
                .disabled(!canReorder(entry, offset: 1))
            Divider()
        }
        let toDrawer = destination == .menuBar
        Button(toDrawer ? "Move to Altillo" : "Move to Menu Bar",
               systemImage: toDrawer ? "archivebox" : "menubar.rectangle") {
            store.move(entry, toDrawer: toDrawer)
        }
        .disabled(!canMove)
    }

    private func dragPreview(for entry: MenuBarEntry) -> some View {
        HStack(spacing: 7) {
            MenuBarGlyph(image: icon(for: entry))
            Text(displayName(for: entry))
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    /// These tiles only move inside Settings. Keeping the gesture local avoids an
    /// NSDraggingSession competing with the subsequent native menu-bar gesture.
    private func localDrag(for entry: MenuBarEntry) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.arrangementSpace))
            .updating($localDragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                guard canMove else { resetLocalDrag(); return }
                draggedEntryID = entry.id
                selectedEntryID = entry.id
                dragLocation = value.location
                let target = localDropTarget(at: value.location)
                drawerIsTargeted = target?.destination == .drawer
                menuBarIsTargeted = target?.destination == .menuBar
                dropTargetEntryID = target?.entry?.id
            }
            .onEnded { value in
                defer { resetLocalDrag() }
                guard canMove, draggedEntryID == entry.id,
                      let current = findEntry(withID: entry.id),
                      let target = localDropTarget(at: value.location) else { return }
                _ = handleDrop(current, in: target.destination, before: target.entry)
            }
    }

    private func localDropTarget(at point: CGPoint) -> (destination: Destination, entry: MenuBarEntry?)? {
        guard let destination = [Destination.drawer, .menuBar].first(where: {
            zoneFrames[$0]?.contains(point) == true
        }) else { return nil }
        let entries = destination == .drawer ? store.drawerEntries : store.menuBarEntries
        // Cells outside a scrolled viewport must not become invisible drop targets.
        let entry = viewportFrames[destination]?.contains(point) == true
            ? entries.first(where: { cellFrames[$0.id]?.contains(point) == true }) : nil
        return (destination, entry)
    }

    private func resetLocalDrag() {
        draggedEntryID = nil
        drawerIsTargeted = false
        menuBarIsTargeted = false
        dropTargetEntryID = nil
    }

    private func cellBackground(_ entry: MenuBarEntry) -> Color {
        if dropTargetEntryID == entry.id { return Desvan.Palette.bulb.opacity(0.24) }
        if selectedEntryID == entry.id { return Desvan.Palette.bulb.opacity(0.30) }
        if focusedEntryID == entry.id { return Desvan.Palette.paper.opacity(0.10) }
        return Desvan.Palette.plank.opacity(0.72)
    }

    private func cellBorder(_ entry: MenuBarEntry) -> Color {
        if dropTargetEntryID == entry.id {
            return Desvan.Palette.bulb.opacity(0.85)
        }
        return Desvan.Palette.hairlineStrong
    }

    private func cellBorderWidth(_ entry: MenuBarEntry) -> CGFloat {
        dropTargetEntryID == entry.id ? 1 : 0.75
    }

    private func handleDrop(_ entry: MenuBarEntry, in destination: Destination,
                            before target: MenuBarEntry?) -> Bool {
        let toDrawer = destination == .drawer
        if store.isInDrawer(entry) == toDrawer {
            if toDrawer { store.reorderDrawerEntry(entry, before: target) }
            return true
        }
        return store.move(entry, toDrawer: toDrawer, before: toDrawer ? target : nil)
    }

    private func canReorder(_ entry: MenuBarEntry, offset: Int) -> Bool {
        guard canMove, let index = store.drawerEntries.firstIndex(where: { $0.id == entry.id }) else { return false }
        return store.drawerEntries.indices.contains(index + offset)
    }

    private func reorder(_ entry: MenuBarEntry, offset: Int) {
        let entries = store.drawerEntries
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let destination = index + offset
        guard entries.indices.contains(destination) else { return }
        if offset < 0 {
            store.reorderDrawerEntry(entry, before: entries[destination])
        } else {
            let afterDestination = destination + 1
            store.reorderDrawerEntry(entry, before: entries.indices.contains(afterDestination)
                ? entries[afterDestination] : nil)
        }
    }

    private func findEntry(withID id: String) -> MenuBarEntry? {
        (store.drawerEntries + store.menuBarEntries).first { $0.id == id }
    }

    private func displayName(for entry: MenuBarEntry) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if [MenuBarAccessibility.controlCenterBundleID, MenuBarAccessibility.menuBarAgentBundleID]
            .contains(entry.application.bundleID) {
            return title.components(separatedBy: ",").first ?? title
        }
        return title.isEmpty ? entry.application.name : title
    }

    private func icon(for entry: MenuBarEntry) -> NSImage {
        store.settingsIcon(for: entry)
    }

    private enum Destination: Hashable {
        case drawer
        case menuBar

        var title: String {
            switch self {
            case .drawer: "Altillo"
            case .menuBar: "Menu Bar"
            }
        }
    }
}

/// The enable card's refresh: it lightens under the pointer and its arrow turns while the icons are being found.
private struct RefreshIconsButton: View {
    let isLoading: Bool
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .semibold))
                .symbolEffect(.rotate, isActive: isLoading)
                .foregroundStyle(isHovering && isEnabled ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Desvan.Palette.paper.opacity(isHovering && isEnabled ? 0.08 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(SettingsPressStyle(scale: 0.92))
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help("Refresh menu bar icons")
        .accessibilityLabel("Refresh menu bar icons")
    }
}
