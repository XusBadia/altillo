import AltilloHome
import SwiftUI

/// Favourites as the notch lays them out (docs/casa-v2.md §2): the same columns, small and wide tiles, hidden ones
/// dimmed. Drag a tile onto another to move it; click one for its inspector. Under it, "Add from a room".
struct SettingsHomeTiles: View {
    @Bindable var settings: AltilloSettings
    let store: HomeStore

    @State private var inspected: HomeEntityID?
    @State private var dropTarget: HomeEntityID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Favourites") {
                Button("Suggest Favourites") {
                    withAnimation(motion) { _ = store.applySuggestions() }
                }
                .controlSize(.small)
                .help("Adds lights, plugs, blinds and scenes from your rooms, up to eight")
            }
            grid
            Text("In this order in Altillo. Drag a tile onto another to move it, click it to rename it, change its icon or size, or hide it.")
                .settingsHint()
            SettingsCardDivider()
            SettingsHomeCatalogue(store: store)
        }
    }

    private var motion: Animation { SettingsMotion.pick(SettingsMotion.reorder, reduceMotion: reduceMotion) }

    @ViewBuilder
    private var grid: some View {
        let tiles = store.settingsTiles
        if tiles.isEmpty {
            Text("No favourites yet. Add them from a room below, or let Altillo suggest some.")
                .settingsHint()
                .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                .background { well }
        } else {
            let metrics = HomeStore.layoutMetrics(sizes: tiles.map(\.size), availableHeight: Double(Self.tileHeight))
            SettingsHomeTileGridLayout(columns: max(metrics.columns, 1), placements: metrics.placements,
                                       tileHeight: Self.tileHeight, spacing: Self.spacing) {
                ForEach(tiles) { tile in
                    SettingsHomeTileView(tile: tile, room: store.area(tile.entity?.areaID)?.name,
                                         isDropTarget: dropTarget == tile.id) {
                        inspected = tile.id
                    }
                    .popover(isPresented: inspecting(tile.id), arrowEdge: .bottom) {
                        SettingsHomeTileInspector(store: store, entityID: tile.id) {
                            inspected = nil
                        }
                    }
                    .draggable(tile.id.rawValue)
                    .dropDestination(for: String.self) { identifiers, _ in
                        guard let raw = identifiers.first, let dragged = HomeEntityID(rawValue: raw) else { return false }
                        withAnimation(motion) { store.dropTile(dragged, onto: tile.id) }
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
        guard let entity = tile.entity else { return String(localized: "Not in Home Assistant") }
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
            .opacity(tile.isHidden || tile.entity == nil ? 0.45 : 1)
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
                                                      dash: tile.entity == nil ? [3, 3] : []))
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }
}

/// What a tile can change: name, icon (a curated set for its kind), size, hidden; and removing it.
private struct SettingsHomeTileInspector: View {
    let store: HomeStore
    let entityID: HomeEntityID
    let close: () -> Void

    @State private var name = ""

    private var tile: HomeTile? { store.tile(for: entityID) }
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
                    Picker(selection: Binding(get: { tile.size }, set: { store.setSize(entityID, $0) })) {
                        Text("Small").tag(HomeTileSize.small)
                        Text("Wide").tag(HomeTileSize.wide)
                    } label: {
                        Text("Size")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Toggle(isOn: Binding(get: { !tile.isHidden }, set: { store.setHidden(entityID, !$0) })) {
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
                        store.removeFavourite(entityID)
                    }
                    .controlSize(.small)
                    .help("Takes it off your favourites")
                }
            }
            .padding(14)
            .frame(width: 300)
            .onAppear { name = tile.name ?? "" }
            .onDisappear(perform: commitName)
        }
    }

    private func commitName() {
        guard store.tile(for: entityID) != nil else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.rename(entityID, to: trimmed.isEmpty ? nil : trimmed)
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
            store.setSymbol(entityID, symbol)
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

/// "Add from a room": areas, with search, each entity with its + button.
private struct SettingsHomeCatalogue: View {
    let store: HomeStore

    @State private var query = ""
    @State private var expandedAreas: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSubheading("Add from a room")
            search
            catalogue
            Text("Locks, alarms and garage doors can't be favourites yet.")
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
            Text(searching ? "Nothing called “\(query)”." : "Home Assistant hasn't shared any lights, plugs or blinds yet.")
                .settingsHint()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(groups) { group in
                    SettingsInlineDisclosure(title: LocalizedStringKey(group.name), count: group.entities.count,
                                             isExpanded: expanded(group.id)) {
                        SettingsWell {
                            ForEach(group.entities) { entity in
                                row(entity)
                                if entity.id != group.entities.last?.id { SettingsRowDivider(leading: 24) }
                            }
                        }
                        .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private func row(_ entity: HomeEntity) -> some View {
        let added = store.isFavourite(entity.id)
        return HStack(spacing: 8) {
            Image(systemName: HomeText.symbol(for: entity, state: entity.state))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(verbatim: entity.name)
                .font(.system(size: 12.5))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            Text(verbatim: HomeText.kindName(entity))
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.paperTertiary)
            Spacer(minLength: 8)
            Button {
                withAnimation(SettingsMotion.pick(SettingsMotion.reorder, reduceMotion: reduceMotion)) {
                    if added { store.removeFavourite(entity.id) } else { store.addFavourite(entity.id) }
                }
            } label: {
                Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(added ? Desvan.Palette.sage : Desvan.Palette.bulb)
            }
            .buttonStyle(SettingsPressStyle(scale: 0.85))
            .help(added ? "In your favourites. Click to take it off." : "Add to your favourites")
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
