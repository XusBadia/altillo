import AppKit
import SwiftUI

/// Chooses which apps' menu bar icons live in Altillo (the Drawer) and which stay in the menu bar. Membership is per
/// app: every icon of an app moves, and hides, together. System items (clock, Wi‑Fi, Control Center…) always stay.
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

    /// Whether moves can happen at all right now. Each tile also asks `store.canMove(_:)` (system items can't).
    private var canArrange: Bool {
        store.enabled && store.hasAccess && !store.isPerformingMenuBarInteraction
    }

    private func canMove(_ entry: MenuBarEntry) -> Bool {
        canArrange && store.canMove(entry)
    }

    /// The icons that travel with the one being dragged or selected, lit softly so the rule shows itself.
    private var travellingCompanionIDs: Set<String> {
        guard let id = draggedEntryID ?? selectedEntryID, let entry = findEntry(withID: id) else { return [] }
        return Set(store.companions(of: entry).map(\.id))
    }

    private var revealAnimation: Animation {
        SettingsMotion.pick(SettingsMotion.reveal, reduceMotion: reduceMotion)
    }

    var body: some View {
        SettingsPane(
            title: "Drawer",
            subtitle: "Keep the menu bar icons you rarely need in Altillo, one click away in the notch."
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    enableCard
                    if store.enabled, store.isSupported, store.hasAccess {
                        optionsCard
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
                .animation(revealAnimation, value: store.problem)
                .animation(revealAnimation, value: store.hidesDrawerIcons)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { store.setVisible(true, for: .settings) }
        .onDisappear {
            resetLocalDrag()
            store.setVisible(false, for: .settings)
        }
        .onChange(of: localDragIsActive) { _, active in
            if !active { resetLocalDrag() }
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

    private var enableCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 12) {
                SettingsGroupHeading(title: "Use Drawer", detail: "Keep selected icons within reach in Altillo.")

                Spacer(minLength: 12)

                if store.hasAccess, store.isSupported, store.enabled {
                    RefreshIconsButton(isLoading: store.isLoading) {
                        store.refresh(clearProblem: true)
                    }
                    .disabled(store.isLoading)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }

                Toggle("Use Drawer", isOn: Binding(
                    get: { store.enabled },
                    set: { store.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!store.isSupported)
            }
        }
    }

    // MARK: - Options

    /// How Drawer icons behave in the menu bar, and where icons of apps Altillo hasn't seen before go.
    private var optionsCard: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 0) {
                if store.support.hiding {
                    hidingRow
                    if store.hidesDrawerIcons {
                        peekRow
                            .padding(.top, 12)
                            .transition(.settingsReveal)
                    }
                } else {
                    hidingUnavailableRow
                }
                SettingsCardDivider()
                newIconsRow
            }
        }
    }

    private var hidingRow: some View {
        HStack(alignment: .center, spacing: 12) {
            optionTile(symbol: store.hidesDrawerIcons ? "eye.slash.fill" : "eye.fill",
                       isLit: store.hidesDrawerIcons)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hide Drawer icons from the menu bar")
                    .settingsRowTitle()
                Text("They leave the menu bar and live in Altillo. Icons from the same app hide together, and macOS also hides Live Activity pills meanwhile. Quitting Altillo brings them all back.")
                    .settingsHint()
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
            .help(store.hidesDrawerIcons
                ? "Drawer icons are hidden from the menu bar"
                : "Drawer icons also stay in the menu bar")
        }
    }

    /// A moment's look at the hidden icons in the real menu bar, and the way back.
    private var peekRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Color.clear.frame(width: 30, height: 1)
                .accessibilityHidden(true)

            Text(store.isPeeking
                ? "Your Drawer icons are back in the menu bar for now."
                : "Need one in the menu bar for a moment? Show them there until you hide them again.")
                .settingsHint()
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)

            Spacer(minLength: 12)

            Button {
                store.setPeeking(!store.isPeeking)
            } label: {
                Label(store.isPeeking ? "Hide them again" : "Show hidden icons",
                      systemImage: store.isPeeking ? "eye.slash" : "eye")
            }
            .buttonStyle(DesvanButtonStyle(kind: store.isPeeking ? .primary : .ghost, height: 26))
            .disabled(!store.isPeeking && !store.isConcealing)
            .help(store.isPeeking
                ? "Hide the Drawer icons from the menu bar again"
                : "Show the hidden Drawer icons in the menu bar")
        }
        .animation(revealAnimation, value: store.isPeeking)
    }

    /// macOS 26: nothing is broken, the system just can't hide icons for Altillo yet.
    private var hidingUnavailableRow: some View {
        HStack(alignment: .top, spacing: 12) {
            optionTile(symbol: "info.circle", isLit: false)

            VStack(alignment: .leading, spacing: 2) {
                Text("Hiding icons needs macOS 27")
                    .settingsRowTitle()
                Text("On this version of macOS, icons you keep in Altillo also stay in the menu bar. The Drawer still opens their menus from the notch.")
                    .settingsHint()
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var newIconsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            optionTile(symbol: "sparkles", isLit: store.newIconsGoToDrawer)

            VStack(alignment: .leading, spacing: 2) {
                Text("New menu bar icons")
                    .settingsRowTitle()
                Text("From apps Altillo hasn't seen before.")
                    .settingsHint()
            }
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Picker(selection: Binding(
                get: { store.newIconsGoToDrawer },
                set: { store.setNewIconsGoToDrawer($0) }
            )) {
                Text("Stay in the menu bar").tag(false)
                Text("Go to the Drawer").tag(true)
            } label: {
                Text("New menu bar icons")
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .fixedSize()
        }
    }

    private func optionTile(symbol: String, isLit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(isLit ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 30, height: 30)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                shape.fill(Desvan.Palette.plank.opacity(0.85))
                    .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .animation(revealAnimation, value: isLit)
            .accessibilityHidden(true)
    }

    // MARK: - States

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
        } else {
            arrangementContent
                .transition(.settingsReveal)
        }
    }

    /// Accessibility is the Drawer's only permission. Two ways to give it: the system prompt, or dragging Altillo's
    /// icon straight into the list in System Settings.
    private var permissionCard: some View {
        SettingsCard {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsGroupHeading(
                        title: "Allow Accessibility access",
                        detail: "Altillo reads your menu bar icons and opens their menus. It's the only permission the Drawer needs."
                    )
                    Button("Grant Access") { store.requestAccess() }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26))
                    Text("Or drag the icon into the Accessibility list in System Settings.")
                        .settingsHint()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                AppIconDragSource(size: 58)
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

    // MARK: - Arrangement

    private var arrangementContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Group {
                    if store.isLoading && store.entries.isEmpty {
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
                            Text("Drag icons between areas. Icons from the same app move together.")
                                .settingsHint()
                        }
                        .transition(.settingsReveal)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 18)
            .padding(.horizontal, 2)
            .animation(revealAnimation, value: store.isLoading && store.entries.isEmpty)
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
                    .animation(revealAnimation, value: entries.map(\.id))
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
        MenuBarPopupAnchorReader(toolTip: toolTip(for: entry)) { anchor in
            anchoredIconCell(entry, destination: destination, anchor: anchor)
        }
    }

    private func anchoredIconCell(_ entry: MenuBarEntry, destination: Destination,
                                  anchor: MenuBarPopupAnchor) -> some View {
        let isLocked = !store.canMove(entry)
        let moveToDrawer = destination == .menuBar

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
                    .opacity(isLocked ? 0.78 : 1)
                    .accessibilityHidden(true)
            }
            .frame(width: MenuBarGlyph.cellWidth(for: icon(for: entry).size), height: 34)
            .overlay(alignment: .bottomTrailing) {
                if isLocked { lockBadge }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(Desvan.Motion.hover, value: cellBackground(entry))
        }
        .buttonStyle(SettingsPressStyle(scale: 0.94))
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
        .accessibilityHint(accessibilityHint(for: entry, in: destination))
        .accessibilityAction {
            selectedEntryID = entry.id
        }
        .accessibilityActions {
            if canMove(entry) {
                Button(moveTitle(for: entry, toDrawer: moveToDrawer)) {
                    store.move(entry, toDrawer: moveToDrawer)
                }
            }
        }
    }

    /// A small padlock on the tile's corner: macOS hosts this item and keeps it in the menu bar.
    private var lockBadge: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 6.5, weight: .bold))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .frame(width: 13, height: 13)
            .background {
                Circle().fill(Desvan.Palette.wood)
                    .overlay { Circle().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75) }
            }
            .offset(x: 3, y: 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func entryMenu(for entry: MenuBarEntry, destination: Destination,
                           anchor: MenuBarPopupAnchor) -> some View {
        Button("Open menu") { store.activate(entry, anchor: anchor) }
        Divider()
        if destination == .drawer {
            Button("Move earlier", systemImage: "arrow.left") { reorder(entry, offset: -1) }
                .disabled(!canReorder(entry, offset: -1))
            Button("Move later", systemImage: "arrow.right") { reorder(entry, offset: 1) }
                .disabled(!canReorder(entry, offset: 1))
            Divider()
        }
        if store.canMove(entry) {
            let toDrawer = destination == .menuBar
            Button(moveTitle(for: entry, toDrawer: toDrawer),
                   systemImage: toDrawer ? "archivebox" : "menubar.rectangle") {
                store.move(entry, toDrawer: toDrawer)
            }
            .disabled(!canArrange)
        } else {
            Button(lockReason(for: entry), systemImage: "lock") {}
                .disabled(true)
        }
    }

    /// "Move to Altillo", or, when the app has more icons, the whole app's move spelled out.
    private func moveTitle(for entry: MenuBarEntry, toDrawer: Bool) -> String {
        let count = store.companions(of: entry).count + 1
        let app = entry.application.name
        if count == 1 {
            return toDrawer ? String(localized: "Move to Altillo") : String(localized: "Move to Menu Bar")
        }
        return toDrawer
            ? String(localized: "Move the \(count) icons from \(app) to Altillo")
            : String(localized: "Move the \(count) icons from \(app) to Menu Bar")
    }

    private func accessibilityHint(for entry: MenuBarEntry, in destination: Destination) -> String {
        if !store.canMove(entry) {
            return String(localized: "\(lockReason(for: entry)). Open its menu from the shortcut menu.")
        }
        return destination == .drawer
            ? String(localized: "Selects this icon. Drag to reorder or move it. Open its menu from the shortcut menu.")
            : String(localized: "Selects this icon. Drag to move it. Open its menu from the shortcut menu.")
    }

    private func toolTip(for entry: MenuBarEntry) -> String {
        store.canMove(entry) ? entry.hoverName : "\(entry.hoverName) — \(lockReason(for: entry))"
    }

    /// Why a tile can't move: macOS hosts it, or it's Altillo's own icon (the way back to Altillo stays in sight).
    private func lockReason(for entry: MenuBarEntry) -> String {
        entry.application.bundleID == Bundle.main.bundleIdentifier
            ? String(localized: "Altillo's own icon stays in the menu bar")
            : String(localized: "macOS keeps this in the menu bar")
    }

    private func dragPreview(for entry: MenuBarEntry) -> some View {
        let companions = store.companions(of: entry).count
        return HStack(spacing: 7) {
            MenuBarGlyph(image: icon(for: entry))
            Text(companions > 0 ? entry.application.name : displayName(for: entry))
                .font(.system(size: 11, weight: .medium))
            if companions > 0 {
                Text(verbatim: "+\(companions.formatted())")
                    .font(Desvan.Typeface.rounded(10.5, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Capsule().fill(Desvan.Palette.bulb.opacity(0.16)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
    }

    /// These tiles only move inside Settings; moves are logical and instant, nothing touches the real menu bar.
    private func localDrag(for entry: MenuBarEntry) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.arrangementSpace))
            .updating($localDragIsActive) { _, active, _ in active = true }
            .onChanged { value in
                guard canMove(entry) else { resetLocalDrag(); return }
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
                guard canMove(entry), draggedEntryID == entry.id,
                      let current = findEntry(withID: entry.id),
                      let target = localDropTarget(at: value.location) else { return }
                withAnimation(revealAnimation) {
                    _ = handleDrop(current, in: target.destination, before: target.entry)
                }
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
        if travellingCompanionIDs.contains(entry.id) { return Desvan.Palette.bulb.opacity(0.14) }
        if focusedEntryID == entry.id { return Desvan.Palette.paper.opacity(0.10) }
        return Desvan.Palette.plank.opacity(0.72)
    }

    private func cellBorder(_ entry: MenuBarEntry) -> Color {
        if dropTargetEntryID == entry.id { return Desvan.Palette.bulb.opacity(0.85) }
        if travellingCompanionIDs.contains(entry.id) { return Desvan.Palette.bulb.opacity(0.45) }
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
        guard canArrange, let index = store.drawerEntries.firstIndex(where: { $0.id == entry.id }) else { return false }
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
        store.entries.first { $0.id == id }
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
