import AltilloHome
import SwiftUI

/// Favourites and the user's own pages as the notch lays them out (docs/casa-v2.md §2): the same columns, small and
/// wide tiles, hidden ones dimmed. Drag a tile onto another to move it; click one for its inspector. Under it,
/// "Add from a room", where rooms and what each one shows in the notch are chosen too.
struct SettingsHomeTiles: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    /// The page being edited: Favourites (nil) or one of the user's.
    @State private var page: HomePage.ID?
    @State private var pageName = ""
    @FocusState private var pageNameFocused: Bool
    @State private var inspected: HomeEntityID?
    @State private var dropTarget: HomeEntityID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 64

    private var isFavourites: Bool { page == nil }
    private var customPage: HomePage? { page.flatMap { store.layout.page($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Tiles") {
                if isFavourites {
                    let canSuggest = !store.service.entities.isEmpty && !store.suggestedFavourites().isEmpty
                    Button("Suggest Favourites") {
                        withAnimation(motion) { _ = store.applySuggestions() }
                    }
                    .controlSize(.small)
                    .disabled(!canSuggest)
                    .help(canSuggest ? "Adds lights, plugs, blinds and scenes from your rooms, up to eight"
                                     : "Everything Altillo would suggest is already in your favourites")
                }
            }
            pageBar
            if let customPage { pageEditor(customPage) }
            grid
            Text(isFavourites
                 ? "In this order in Altillo. Drag a tile onto another to move it, click it to rename it, change its icon or size, or hide it."
                 : "A page of its own in the notch, after Favourites. Add tiles from a room below.")
                .settingsHint()
            SettingsCardDivider()
            if store.service.entities.isEmpty {
                waiting
            } else {
                SettingsHomeCatalogue(store: store, page: page, pageTitle: pageTitle)
            }
        }
        .onChange(of: store.pages.map(\.id)) { _, ids in
            if let page, !ids.contains(page) { self.page = nil }
        }
        .onChange(of: page) { old, _ in
            if let old { store.renamePage(old, to: pageName) }
            inspected = nil
            pageName = customPage?.customName ?? ""
        }
    }

    private var pageTitle: String { customPage?.customName ?? String(localized: "Favourites") }

    /// Favourites, the user's pages and "New Page".
    private var pageBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                pill(String(localized: "Favourites"), id: nil)
                ForEach(store.layout.customPages) { custom in
                    pill(custom.customName ?? "", id: custom.id)
                }
                Button {
                    let id = store.addPage()
                    withAnimation(motion) { page = id }
                    Task { @MainActor in pageNameFocused = true }
                } label: {
                    Label("New Page", systemImage: "plus")
                        .font(.system(size: 11.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            Capsule().strokeBorder(Desvan.Palette.hairline, style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(SettingsPressStyle(scale: 0.95))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .help("A page of your own in the notch, like Night or Office")
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func pill(_ title: String, id: HomePage.ID?) -> some View {
        let selected = page == id
        return Button {
            withAnimation(motion) { page = id }
        } label: {
            Text(verbatim: title)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Desvan.Palette.bulbInk : Desvan.Palette.paperSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    if selected {
                        Capsule().fill(Desvan.Palette.bulb.opacity(0.94))
                    } else {
                        Capsule().fill(Desvan.Palette.paper.opacity(0.06))
                            .overlay { Capsule().strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(SettingsPressStyle(scale: 0.95))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The page's name and the way to delete it.
    private func pageEditor(_ custom: HomePage) -> some View {
        HStack(spacing: 8) {
            Text("Name").settingsRowTitle()
            TextField(text: $pageName, prompt: Text(verbatim: custom.customName ?? "")) { Text("Name") }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(maxWidth: 220)
                .focused($pageNameFocused)
                .onSubmit { store.renamePage(custom.id, to: pageName) }
                .onChange(of: pageNameFocused) { _, focused in
                    if !focused { store.renamePage(custom.id, to: pageName) }
                }
            Spacer(minLength: 8)
            Button("Delete Page", role: .destructive) {
                pageName = ""
                withAnimation(motion) {
                    page = nil
                    store.removePage(custom.id)
                }
            }
            .controlSize(.small)
            .help("Deletes this page and its tiles. The devices stay in Home Assistant and on your other pages.")
        }
        .onAppear { pageName = custom.customName ?? "" }
    }

    /// While Home Assistant hasn't sent its devices: say why the list isn't here instead of leaving a hole.
    @ViewBuilder
    private var waiting: some View {
        switch store.connection {
        case .connecting, .notConfigured, .connected:
            SettingsNotice(symbol: "arrow.triangle.2.circlepath",
                           message: "Loading your devices from Home Assistant. Your tiles are kept meanwhile.",
                           tone: .neutral)
        default:
            SettingsNotice(symbol: "wifi.exclamationmark",
                           message: "Altillo can't reach Home Assistant, so your devices can't be listed. Your tiles are kept.",
                           tone: .warning) {
                Button("Try Now") { store.reconnect() }
            }
        }
    }

    private var motion: Animation { SettingsMotion.pick(SettingsMotion.reorder, reduceMotion: reduceMotion) }

    @ViewBuilder
    private var grid: some View {
        let tiles = store.settingsTiles(onPage: page)
        if tiles.isEmpty {
            Text(isFavourites ? "No favourites yet. Add them from a room below, or let Altillo suggest some."
                              : "No tiles on this page yet. Add them from a room below.")
                .settingsHint()
                .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                .background { well }
        } else {
            let metrics = HomeStore.layoutMetrics(sizes: tiles.map(\.size), availableHeight: Double(Self.tileHeight))
            SettingsHomeTileGridLayout(columns: max(metrics.columns, 1), placements: metrics.placements,
                                       tileHeight: Self.tileHeight, spacing: Self.spacing) {
                ForEach(tiles) { tile in
                    SettingsHomeTileView(tile: tile, room: store.area(tile.entity?.areaID)?.name,
                                         isLoading: store.service.entities.isEmpty,
                                         isDropTarget: dropTarget == tile.id) {
                        inspected = tile.id
                    }
                    .popover(isPresented: inspecting(tile.id), arrowEdge: .bottom) {
                        SettingsHomeTileInspector(store: store, entityID: tile.id, page: page) {
                            inspected = nil
                        }
                    }
                    .draggable(tile.id.rawValue)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let raw = identifiers.first, let dragged = HomeEntityID(rawValue: raw) else { return false }
                        withAnimation(motion) { store.dropTile(dragged, onto: tile.id, onPage: page) }
                        return true
                    } isTargeted: { targeted in
                        if targeted { dropTarget = tile.id } else if dropTarget == tile.id { dropTarget = nil }
                    }
                }
            }
            .padding(10)
            .background { well }
            .animation(motion, value: tiles.map(\.tile))
        }
    }

    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape.fill(Color.black.opacity(0.22))
            .overlay { shape.strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
    }

    private func inspecting(_ id: HomeEntityID) -> Binding<Bool> {
        Binding(get: { inspected == id }, set: { open in
            if open { inspected = id } else if inspected == id { inspected = nil }
        })
    }
}

/// Places tiles where `HomeGridMetrics` says, the way the notch does: equal columns, wide tiles over two.
struct SettingsHomeTileGridLayout: Layout {
    let columns: Int
    let placements: [HomeGridMetrics.Placement]
    let tileHeight: CGFloat
    let spacing: CGFloat

    private var rows: Int { (placements.map(\.row).max() ?? -1) + 1 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? CGFloat(columns) * 120
        let height = CGFloat(rows) * tileHeight + CGFloat(max(rows - 1, 0)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let unit = (bounds.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        for (index, subview) in subviews.enumerated() {
            guard placements.indices.contains(index) else { break }
            let place = placements[index]
            let width = CGFloat(place.span) * unit + CGFloat(place.span - 1) * spacing
            let origin = CGPoint(x: bounds.minX + CGFloat(place.column) * (unit + spacing),
                                 y: bounds.minY + CGFloat(place.row) * (tileHeight + spacing))
            subview.place(at: origin, proposal: ProposedViewSize(width: width, height: tileHeight))
        }
    }
}

/// A tile in miniature: the switch plate, its bakelite disc with the glyph, the name and the room.
private struct SettingsHomeTileView: View {
    let tile: HomeSettingsTile
    let room: String?
    /// Home Assistant hasn't sent its devices yet: a missing entity isn't gone, just not here yet.
    var isLoading = false
    let isDropTarget: Bool
    let open: () -> Void

    @State private var isHovering = false

    private var symbol: String {
        if let own = tile.tile.symbol { return own }
        guard let entity = tile.entity else { return "questionmark.circle" }
        return HomeText.symbol(for: entity, state: entity.state)
    }

    private var isOn: Bool { tile.entity?.state.isOn == true }

    /// Like the notch: the room, or the kind when it has none.
    private var secondLine: String {
        guard let entity = tile.entity else {
            return isLoading ? String(localized: "Waiting for Home Assistant") : String(localized: "Not in Home Assistant")
        }
        return room ?? HomeText.kindName(entity)
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: tile.size == .wide ? 14 : 12, weight: .semibold))
                    .foregroundStyle(isOn ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .frame(width: 26, height: 26)
                    .background {
                        Circle().fill(Color.black.opacity(0.85))
                            .overlay { Circle().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 1) }
                    }
                VStack(alignment: .leading, spacing: 1) {
                    // Like the notch's compact tiles: a long name takes a second line rather than an ellipsis, the
                    // room stays under it and the tile keeps its height, so the grid stays aligned.
                    Text(verbatim: tile.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paper)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: secondLine)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { plate }
            .overlay(alignment: .topTrailing) {
                if tile.isHidden {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .opacity(tile.isHidden || (tile.entity == nil && !isLoading) ? 0.45 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SettingsPressStyle(scale: 0.97))
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help("Click to edit, drag to move")
        .accessibilityLabel(Text(verbatim: tile.name))
        .accessibilityValue(Text(tile.isHidden ? "Hidden" : (tile.size == .wide ? "Wide" : "Small")))
        .accessibilityHint(Text("Opens its settings"))
    }

    private var plate: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Desvan.Palette.plank, Desvan.Palette.plank.opacity(0.78)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                shape.strokeBorder(isDropTarget ? Desvan.Palette.bulb
                                   : (isHovering ? Desvan.Palette.hairlineStrong : Desvan.Palette.hairline),
                                   style: StrokeStyle(lineWidth: isDropTarget ? 1.5 : 0.75,
                                                      dash: tile.entity == nil && !isLoading ? [3, 3] : []))
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// What a tile can change: name, icon (a curated set for its kind), size, hidden; and removing it.
private struct SettingsHomeTileInspector: View {
    let store: HomeStore
    let entityID: HomeEntityID
    /// Favourites (nil) or one of the user's pages: each page keeps its own name, icon, size and visibility.
    let page: HomePage.ID?
    let close: () -> Void

    @State private var name = ""

    private var tile: HomeTile? { store.tile(for: entityID, onPage: page) }
    private var entity: HomeEntity? { store.service.entities[entityID] }

    var body: some View {
        if let tile {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Name").settingsRowTitle().frame(width: 52, alignment: .leading)
                    TextField(text: $name, prompt: Text(verbatim: entity?.name ?? entityID.localID)) { Text("Name") }
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(commitName)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon").settingsRowTitle()
                    iconGrid(selected: tile.symbol)
                }
                HStack(spacing: 8) {
                    Text("Size").settingsRowTitle().frame(width: 52, alignment: .leading)
                    Picker(selection: Binding(get: { tile.size }, set: { store.setSize(entityID, $0, onPage: page) })) {
                        Text("Small").tag(HomeTileSize.small)
                        Text("Wide").tag(HomeTileSize.wide)
                    } label: {
                        Text("Size")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle(isOn: Binding(get: { !tile.isHidden }, set: { store.setHidden(entityID, !$0, onPage: page) })) {
                    Text("Show in Altillo").settingsRowTitle()
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Divider()
                HStack {
                    if let entity {
                        Text(verbatim: [HomeText.kindName(entity), store.area(entity.areaID)?.name]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    Button("Remove", role: .destructive) {
                        close()
                        store.removeTile(entityID, fromPage: page)
                    }
                    .controlSize(.small)
                    .help(page == nil ? "Takes it off your favourites" : "Takes it off this page")
                }
            }
            .padding(14)
            .frame(width: 300)
            .onAppear { name = tile.name ?? "" }
            .onDisappear(perform: commitName)
        }
    }

    private func commitName() {
        guard store.tile(for: entityID, onPage: page) != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.rename(entityID, to: trimmed.isEmpty ? nil : trimmed, onPage: page)
    }

    private func iconGrid(selected: String?) -> some View {
        let symbols = HomeStore.curatedSymbols(for: entity?.kind ?? .other)
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 8), spacing: 4) {
            iconButton(symbol: nil, selected: selected == nil)
            ForEach(symbols, id: \.self) { symbol in
                iconButton(symbol: symbol, selected: selected == symbol)
            }
        }
    }

    private func iconButton(symbol: String?, selected: Bool) -> some View {
        Button {
            store.setSymbol(entityID, symbol, onPage: page)
        } label: {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text("Auto").font(.system(size: 8.5, weight: .semibold))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .frame(width: 28, height: 28)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(symbol == nil ? Text("Its own icon") : Text(verbatim: symbol ?? ""))
        .accessibilityLabel(symbol == nil ? Text("Its own icon") : Text(verbatim: symbol ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Add from a room": areas, with search, each entity with its + button (for the page being edited) and its eye
/// (whether it shows when that room is explored in the notch); each room's eye says whether its chip shows at all.
private struct SettingsHomeCatalogue: View {
    let store: HomeStore
    let page: HomePage.ID?
    let pageTitle: String

    @State private var query = ""
    @State private var expandedAreas: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Add from a room")
            search
            catalogue
            Text("The eye sets what each room shows in the notch. Locks, alarms and garage doors can't be tiles yet.")
                .settingsHint()
        }
    }

    private var search: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .accessibilityHidden(true)
            TextField(text: $query, prompt: Text("Search lights, plugs, blinds…")) { Text("Search") }
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
            if searching {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Desvan.Palette.paperTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.18))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75)
                }
        }
    }

    @ViewBuilder
    private var catalogue: some View {
        let groups = store.catalogue(matching: query)
        if groups.isEmpty {
            Text(searching ? "Nothing called “\(query)”." : "Home Assistant hasn't shared anything that can be a tile yet.")
                .settingsHint()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    SettingsInlineDisclosure(title: LocalizedStringKey(group.name), count: group.entities.count,
                                             isExpanded: expanded(group.id)) {
                        SettingsWell {
                            ForEach(group.entities) { entity in
                                row(entity, roomHidden: store.isAreaHidden(group.id))
                                if entity.id != group.entities.last?.id { SettingsRowDivider(leading: 24) }
                            }
                        }
                        .padding(.leading, 14)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .topTrailing) {
                        if !group.id.isEmpty { roomEye(group).padding(.trailing, 4) }
                    }
                }
            }
        }
    }

    private var animation: Animation { SettingsMotion.pick(SettingsMotion.reorder, reduceMotion: reduceMotion) }

    /// Whether the room's chip shows in the notch.
    private func roomEye(_ group: HomeCatalogueGroup) -> some View {
        let hidden = store.isAreaHidden(group.id)
        return Button {
            withAnimation(animation) { store.setAreaHidden(group.id, !hidden) }
        } label: {
            Image(systemName: hidden ? "eye.slash" : "eye")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hidden ? Desvan.Palette.paperTertiary : Desvan.Palette.paperSecondary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressStyle(scale: 0.85))
        .help(hidden ? Text("“\(group.name)” is hidden in the notch. Click to show it.")
                     : Text("Shown in the notch. Click to hide “\(group.name)”."))
        .accessibilityLabel(hidden ? Text("Show \(group.name) in the notch") : Text("Hide \(group.name) in the notch"))
    }

    /// Whether the entity shows when its room is explored in the notch.
    @ViewBuilder
    private func entityEye(_ entity: HomeEntity, roomHidden: Bool) -> some View {
        if store.showsInRooms(entity) {
            let hidden = store.isHiddenInRooms(entity.id)
            Button {
                withAnimation(animation) { store.setHiddenInRooms(entity.id, !hidden) }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(hidden ? Desvan.Palette.paperTertiary : Desvan.Palette.paperSecondary)
                    .frame(width: 20, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SettingsPressStyle(scale: 0.85))
            .disabled(roomHidden)
            .help(roomHidden ? Text("Its room is hidden in the notch")
                  : (hidden ? Text("Hidden in its room in the notch. Click to show it.")
                            : Text("Shown in its room in the notch. Click to hide it there.")))
            .accessibilityLabel(hidden ? Text("Show \(entity.name) in its room") : Text("Hide \(entity.name) in its room"))
        } else {
            Color.clear.frame(width: 20, height: 18).accessibilityHidden(true)
        }
    }

    private func row(_ entity: HomeEntity, roomHidden: Bool) -> some View {
        let added = store.isOnPage(entity.id, page: page)
        let dimmed = roomHidden || (store.showsInRooms(entity) && store.isHiddenInRooms(entity.id))
        return HStack(spacing: 8) {
            Image(systemName: HomeText.symbol(for: entity, state: entity.state))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: entity.name)
                .font(.system(size: 12.5))
                .foregroundStyle(dimmed ? Desvan.Palette.paperSecondary : Desvan.Palette.paper)
                .lineLimit(1)
            Text(verbatim: HomeText.kindName(entity))
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.paperTertiary)
            Spacer(minLength: 8)
            entityEye(entity, roomHidden: roomHidden)
            Button {
                withAnimation(animation) {
                    if added { store.removeTile(entity.id, fromPage: page) } else { store.addTile(entity.id, toPage: page) }
                }
            } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(added ? Desvan.Palette.sage : Desvan.Palette.bulb)
            }
            .buttonStyle(SettingsPressStyle(scale: 0.85))
            .help(added ? Text("On “\(pageTitle)”. Click to take it off.") : Text("Add to “\(pageTitle)”"))
            .accessibilityLabel(added ? Text("Remove \(entity.name)") : Text("Add \(entity.name)"))
        }
        .padding(.vertical, 4)
        .help(entity.id.localID)
    }

    private func expanded(_ id: String) -> Binding<Bool> {
        Binding(
            get: { searching || expandedAreas.contains(id) },
            set: { open in
                if open { expandedAreas.insert(id) } else { expandedAreas.remove(id) }
            }
        )
    }
}
