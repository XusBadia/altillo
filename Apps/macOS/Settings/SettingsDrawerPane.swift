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
    @FocusState private var focusedEntryID: String?

    private var canMove: Bool {
        store.enabled && store.hasAccess && store.support.arranging
            && store.movingEntryID == nil && !store.isPerformingMenuBarInteraction
    }

    private var movingEntry: MenuBarEntry? {
        guard let id = store.movingEntryID else { return nil }
        return findEntry(withID: id)
    }

    var body: some View {
        SettingsPane(
            title: "Drawer",
            subtitle: "Drag menu bar icons between Altillo and the menu bar."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    enableCard
                    if store.enabled, store.isSupported { visibilityCard }
                    stateContent

                    if let problem = store.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Desvan.Palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                            .accessibilityLabel("Drawer error: \(problem)")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 18)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { store.setVisible(true, for: .settings) }
        .onDisappear { store.setVisible(false, for: .settings) }
        .onChange(of: store.movingEntryID) { previous, current in
            // A native Command-drag necessarily activates the menu bar. Once macOS has
            // finished it, return the window the user was arranging to the foreground.
            guard previous != nil, current == nil else { return }
            SettingsWindowController.shared.show(tab: .drawer)
        }
    }

    private var visibilityCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: store.hidesDrawerIcons ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(store.hidesDrawerIcons ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide Drawer icons from the menu bar")
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    if store.support.hidingStyle == .overflow {
                        Text("Keeps them in Altillo and moves them into macOS's hidden area. macOS 27 may hide every icon from the same app together.")
                            .settingsHint()
                    } else {
                        Text("Keeps them in Altillo without leaving a second copy visible in the menu bar.")
                            .settingsHint()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

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
                VStack(alignment: .leading, spacing: 3) {
                    Text("Use Drawer")
                        .font(Desvan.Typeface.rounded(13, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Keep selected icons within reach in Altillo.")
                        .settingsHint()
                }

                Spacer(minLength: 8)

                if store.hasAccess, store.isSupported {
                    Button {
                        store.refresh(forceIcons: true)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .disabled(store.isLoading || store.movingEntryID != nil)
                    .help("Refresh menu bar icons")
                    .accessibilityLabel("Refresh menu bar icons")
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
            unsupportedCard
        } else if !store.enabled {
            inactiveCard
        } else if !store.hasAccess {
            permissionCard
        } else if store.requiresIconAccess && !store.hasIconAccess {
            iconPermissionCard
        } else {
            if store.support.isPartial { partialSupportCard }
            arrangementContent
        }
    }

    /// What this version of macOS doesn't allow, so the missing part isn't mistaken for a fault.
    private var partialSupportCard: some View {
        SettingsCard {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Some Drawer features aren't available on this version of macOS")
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    if !store.support.hiding {
                        Text("Altillo can't hide menu bar icons here, so icons you keep in Altillo also stay in the menu bar. You can still open their menus from the Drawer.")
                            .settingsHint()
                    }
                    if !store.support.arranging {
                        Text("Icons can't be moved from here. Hold Command and drag them in the menu bar instead.")
                            .settingsHint()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
    }

    private var iconPermissionCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow Screen Recording access")
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Allow Screen Recording so Altillo can display each icon as it appears in your menu bar.")
                        .settingsHint()
                }
                Spacer(minLength: 8)
                Button("Allow access") { store.requestIconAccess() }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
            }
        }
    }

    private var permissionCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "accessibility")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Allow Accessibility access")
                        .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                    Text("Altillo uses it to find and move your menu bar icons.")
                        .settingsHint()
                }

                Spacer(minLength: 8)

                Button("Allow access") { store.requestAccess() }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
            }
        }
    }

    private var unsupportedCard: some View {
        SettingsCard {
            Label {
                Text("Drawer is not available on this version of macOS.")
                    .settingsHint()
            } icon: {
                Image(systemName: "macwindow.badge.exclamationmark")
                    .foregroundStyle(Desvan.Palette.warning)
            }
        }
    }

    private var inactiveCard: some View {
        SettingsCard {
            Label {
                Text("Turn on Drawer to choose which icons appear in Altillo.")
                    .settingsHint()
            } icon: {
                Image(systemName: "archivebox")
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
    }

    private var arrangementContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if let movingEntry {
                    ProgressView()
                        .controlSize(.small)
                    Text("Moving \(displayName(for: movingEntry))…")
                        .settingsHint()
                } else if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Finding menu bar icons…")
                        .settingsHint()
                } else {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .accessibilityHidden(true)
                    Text("Drag icons between areas, or within Altillo to reorder them.")
                        .settingsHint()
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 16)
            .padding(.horizontal, 2)
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
    }

    private func dropZone(
        title: String,
        symbol: String,
        entries: [MenuBarEntry],
        destination: Destination,
        isTargeted: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                Spacer(minLength: 4)
                Text(entries.count, format: .number)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .accessibilityLabel("\(entries.count) icons")
            }

            if entries.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "square.dashed")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.bulb : Desvan.Palette.paperTertiary)
                        .accessibilityHidden(true)
                    Text(isTargeted.wrappedValue ? "Drop here" : "Drag icons here")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isTargeted.wrappedValue ? Desvan.Palette.paper : Desvan.Palette.paperTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .dropDestination(for: String.self) { identifiers, _ in
            guard canMove,
                  let identifier = identifiers.first,
                  let entry = findEntry(withID: identifier)
            else { return false }

            return handleDrop(entry, in: destination, before: nil)
        } isTargeted: { targeted in
            isTargeted.wrappedValue = targeted && canMove
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title), \(entries.count) icons")
    }

    private func iconCell(_ entry: MenuBarEntry, destination: Destination) -> some View {
        MenuBarPopupAnchorReader { anchor in
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
        }
        .buttonStyle(.plain)
        .disabled(store.movingEntryID != nil)
        .opacity(store.movingEntryID == nil || isMoving ? 1 : 0.55)
        .draggable(entry.id) { dragPreview(for: entry) }
        .dropDestination(for: String.self) { identifiers, _ in
            guard canMove,
                  let identifier = identifiers.first,
                  let dragged = findEntry(withID: identifier)
            else { return false }
            return handleDrop(dragged, in: destination, before: entry)
        } isTargeted: { targeted in
            if targeted { dropTargetEntryID = entry.id }
            else if dropTargetEntryID == entry.id { dropTargetEntryID = nil }
        }

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
        .help("\(displayName(for: entry)) · \(entry.application.name)")
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

    private enum Destination: Equatable {
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
