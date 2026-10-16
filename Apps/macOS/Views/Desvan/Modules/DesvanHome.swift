import AltilloHome
import AppKit
import SwiftUI

/// The «Home» tab (docs/casa-v2.md §1–3): the house's name with chips for Favourites, the user's pages and every
/// room; the tiles as switch plates filling the notch's height (two rows in view, more scroll); the scenes as kraft
/// luggage tags and the sensors' readings along the bottom. Lights glow with the colour each bulb is really showing;
/// opening the section lights them up one by one.
///
/// Click a tile to toggle it; drag across it to dim a light or move a blind; hold it (or its chevron) for its
/// controls; right-click to rename, change its icon or size, hide it or (un)favourite it. Keyboard: 1…9 toggle the
/// first nine tiles, arrows move between them (←/→ set the level on a light or blind), Space toggles, Esc closes.
/// Everything is optimistic: the tile changes at once and only goes back if Home Assistant says no.
struct DesvanHomeView: View {
    let model: NotchModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The chip picked: Favourites (`.page(nil)`), one of the user's pages or a room.
    @State private var selection: HomeSelection = .page(nil)
    /// The tile whose controls replace the grid.
    @State private var detail: HomeResolvedTile?
    /// How many tiles have lit up so far in the opening stagger.
    @State private var revealed = 0
    /// The grid's room (height, width), measured.
    @State private var gridSize = CGSize(width: 600, height: 166)
    @FocusState private var focus: HomeEntityID?
    /// Focus rings show once the keyboard is used, not on a click.
    @State private var keyboardUsed = false

    private var store: HomeStore { model.shownHome }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var content: some View {
        switch store.connection {
        case .notConfigured where store.settings.homeServer == nil:
            DesvanModuleNotice(
                symbol: NotchModule.home.symbol,
                title: "Your home, up here",
                message: "Connect Home Assistant to switch lights, blinds and scenes from the notch.",
                actionTitle: "Connect Home Assistant"
            ) { model.actions.openHomeSettings() }
        case .unauthorized:
            DesvanModuleNotice(
                symbol: "key.fill",
                title: "Home Assistant didn't accept the token",
                message: "It may have been deleted or mistyped.",
                actionTitle: "Paste a New Token"
            ) { model.actions.openHomeSettings() }
        case .needsTrust:
            DesvanModuleNotice(
                symbol: "lock.shield",
                title: "A certificate to check",
                message: "Your server uses its own certificate. Check it once in Settings and Altillo remembers it.",
                actionTitle: "Check in Settings"
            ) { model.actions.openHomeSettings() }
        case .localNetworkDenied:
            DesvanModuleNotice(
                symbol: "network.slash",
                title: "Altillo can't see your local network",
                message: "Allow Altillo in Privacy & Security › Local Network to reach Home Assistant.",
                actionTitle: "Open Privacy Settings"
            ) { PrivacySettings.localNetwork.open() }
        case let .unreachable(reason):
            DesvanModuleNotice(
                symbol: "wifi.exclamationmark",
                title: "Can't reach your home right now",
                message: "\(reason) Altillo keeps trying on its own.",
                actionTitle: "Try Now"
            ) { store.reconnect() }
        case .connecting, .notConfigured:
            VStack(alignment: .leading, spacing: 10) {
                DesvanHomeHeader(name: store.homeName, chips: [], selection: $selection)
                DesvanHomeSkeleton()
            }
        case .connected:
            if store.tiles(onPage: nil).isEmpty, selection == .page(nil), store.browsableAreas.isEmpty {
                DesvanModuleNotice(
                    symbol: "star",
                    title: "Choose your favourites",
                    message: "Pick the lights, plugs, blinds and scenes you want one click away.",
                    actionTitle: "Choose Favourites"
                ) { model.actions.openHomeSettings() }
            } else {
                house
            }
        }
    }

    // MARK: - The house

    private var shownTiles: [HomeResolvedTile] {
        switch selection {
        case let .page(id): store.tiles(onPage: id)
        case let .area(id): store.tiles(inArea: id)
        }
    }

    private var chips: [HomeChip] {
        var chips = [HomeChip(selection: .page(nil), title: String(localized: "Favourites"))]
        chips += store.layout.customPages.map { HomeChip(selection: .page($0.id), title: $0.customName ?? "") }
        chips += store.browsableAreas.map { HomeChip(selection: .area($0.id), title: $0.name) }
        return chips
    }

    private var backTitle: String {
        chips.first { $0.selection == selection }?.title ?? String(localized: "Favourites")
    }

    @ViewBuilder
    private var house: some View {
        ZStack(alignment: .topLeading) {
            if let detail {
                DesvanHomeDetail(tile: detail, store: store, backTitle: backTitle, haptic: { model.actions.haptic($0) }) {
                    closeDetail()
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .center)))
            } else {
                grid
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02, anchor: .center)))
            }
        }
        .onDisappear {
            store.watchArea(nil)
            if store.didAutoSuggest { store.dismissAutoSuggestHint() }
        }
        .task(id: model.scenario) { applyDemo() }
    }

    private var grid: some View {
        let all = shownTiles
        let actions = all.filter { $0.entity.kind.isAction }
        let sensors = all.filter { $0.entity.kind == .sensor || $0.entity.kind == .binarySensor }
        let tiles = all.filter { !$0.entity.kind.isAction && $0.entity.kind != .sensor && $0.entity.kind != .binarySensor }
        let spacing: CGFloat = 8
        let metrics = HomeGridMetrics(sizes: tiles.map(\.size), availableHeight: gridSize.height, spacing: spacing)
        // One row only: the plates take the whole height rather than leave the notch's black showing below them.
        let height = metrics.rows == 1 ? max(gridSize.height - 4, HomeGridMetrics.minTileHeight) : metrics.tileHeight
        let columnWidth = metrics.columns > 0
            ? (gridSize.width - spacing * CGFloat(metrics.columns - 1)) / CGFloat(metrics.columns) : gridSize.width
        return VStack(alignment: .leading, spacing: 6) {
            DesvanHomeHeader(name: store.homeName, chips: chips, selection: $selection,
                             hint: store.didAutoSuggest ? store.autoSuggestedCount : nil) {
                store.dismissAutoSuggestHint()
                model.actions.openHomeSettings()
            }
            Group {
                if tiles.isEmpty, store.ring == nil {
                    emptyGrid(hasOthers: !actions.isEmpty || !sensors.isEmpty)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: spacing) {
                            camera
                            HomeGridLayout(metrics: metrics, tileHeight: height, spacing: spacing) {
                                ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                                    let span = metrics.placements.indices.contains(index) ? metrics.placements[index].span : 1
                                    let width = columnWidth * CGFloat(span) + spacing * CGFloat(span - 1)
                                    DesvanHomeTile(
                                        tile: tile, store: store,
                                        room: roomLine(for: tile),
                                        isWide: width >= 230,
                                        height: height,
                                        isRevealed: index < revealed,
                                        showsFocus: keyboardUsed && focus == tile.id,
                                        haptic: { model.actions.haptic($0) },
                                        openDetail: { openDetail(tile) }
                                    )
                                    .focusable()
                                    .focused($focus, equals: tile.id)
                                    .focusEffectDisabled()
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollDisabled(!metrics.scrolls && store.ring == nil)
                    .padding(-2)
                    .mask {
                        // More rows below: the last visible one fades into the notch instead of being cut.
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: metrics.scrolls ? 0.86 : 1),
                                               .init(color: .black.opacity(metrics.scrolls ? 0.15 : 1), location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .padding(-12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { gridSize = $0 }
            if !actions.isEmpty || !sensors.isEmpty {
                HStack(spacing: 14) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(actions) { DesvanHomeSceneTag(tile: $0, store: store) }
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.never)
                    .scrollBounceBehavior(.basedOnSize)
                    .padding(.vertical, -3)
                    if !sensors.isEmpty {
                        DesvanHomeSensors(tiles: sensors, store: store)
                            .fixedSize()
                    }
                }
                .frame(height: DesvanHomeSceneTag.height)
            }
        }
        .animation(Desvan.Motion.pick(.spring(response: 0.35, dampingFraction: 1), reduceMotion: reduceMotion),
                   value: tiles.map(\.id))
        .task(id: tiles.count) { await lightUp(count: tiles.count) }
        // Keys work as soon as the section opens; the ring only shows once they're used.
        .onAppear { if focus == nil { focus = tiles.first?.id } }
        .onKeyPress(phases: .down) { press in handleKey(press, tiles: tiles, metrics: metrics) }
        .onChange(of: selection) { _, new in
            if case let .area(id) = new { store.watchArea(id) } else { store.watchArea(nil) }
        }
    }

    /// The tile's second line: its room on Favourites and pages, nothing while browsing that room.
    private func roomLine(for tile: HomeResolvedTile) -> String? {
        if case .area = selection { return nil }
        return store.area(tile.entity.areaID)?.name
    }

    @ViewBuilder
    private var camera: some View {
        // Ticks only while there's a ring to show, so the card leaves on its own two minutes later.
        if store.ring != nil {
            TimelineView(.periodic(from: .now, by: 15)) { context in
                if let ring = store.ring, store.isRingFresh(at: context.date) {
                    DesvanHomeCameraCard(ring: ring, name: store.service.entities[ring.entity]?.name,
                                         now: context.date, hasCamera: store.doorbellCamera != nil,
                                         refresh: store.refreshSnapshot, dismiss: store.dismissRing)
                        .transition(.opacity)
                }
            }
        }
    }

    private func emptyGrid(hasOthers: Bool) -> some View {
        VStack(spacing: 6) {
            DesvanHouseMark(size: 22, lit: 0.4)
            Text(selection == .page(nil) ? "No favourites yet" : "Nothing to switch here")
                .font(Desvan.Typeface.rounded(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
            Text(selection == .page(nil)
                 ? "Pick a room above and right-click a tile to add it, or choose them in Settings."
                 : "This room only has scenes and sensors.")
                .font(.system(size: 11.5))
                .foregroundStyle(Desvan.Palette.paperSecondary)
                .multilineTextAlignment(.center)
            if selection == .page(nil), !hasOthers {
                Button("Choose Favourites") { model.actions.openHomeSettings() }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 26))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail

    private func openDetail(_ tile: HomeResolvedTile) {
        guard DesvanHomeDetail.hasControls(tile.entity) else { return }
        withAnimation(Desvan.Motion.pick(.spring(response: 0.35, dampingFraction: 1), reduceMotion: reduceMotion)) {
            detail = tile
        }
    }

    private func closeDetail() {
        let id = detail?.id
        withAnimation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion)) {
            detail = nil
        }
        focus = id
    }

    // MARK: - Keyboard

    /// 1…9 toggle the tile at that place; arrows walk the grid (←/→ set the level ±10 % on a light or blind with
    /// focus); Space or Return toggles the focused tile; Esc closes the notch. (⌘1…9 already pick the section.)
    private func handleKey(_ press: KeyPress, tiles: [HomeResolvedTile], metrics: HomeGridMetrics) -> KeyPress.Result {
        guard detail == nil, !tiles.isEmpty else { return .ignored }
        let modifiers = press.modifiers.subtracting([.numericPad, .function, .capsLock])
        if press.key == .escape {
            model.actions.send(.escape)
            return .handled
        }
        guard modifiers.isEmpty else { return .ignored }
        if let digit = Int(press.characters), (1...9).contains(digit) {
            guard tiles.indices.contains(digit - 1) else { return .handled }
            keyboardUsed = true
            focus = tiles[digit - 1].id
            store.activate(tiles[digit - 1].entity)
            return .handled
        }
        let index = focus.flatMap { id in tiles.firstIndex { $0.id == id } }
        switch press.key {
        case .space, .return:
            guard let index else { return .ignored }
            keyboardUsed = true
            store.activate(tiles[index].entity)
            return .handled
        case .leftArrow, .rightArrow:
            keyboardUsed = true
            let delta = press.key == .rightArrow ? 1 : -1
            guard let index else {
                focus = tiles.first?.id
                return .handled
            }
            let entity = tiles[index].entity
            if DesvanHomeTile.hasLevel(entity) {
                let level = DesvanHomeTile.level(of: entity, state: store.state(of: entity))
                store.drag(entity, to: min(max(level + 0.1 * Double(delta), 0), 1), final: true)
            } else {
                focus = tiles[min(max(index + delta, 0), tiles.count - 1)].id
            }
            return .handled
        case .upArrow, .downArrow:
            keyboardUsed = true
            guard let index, metrics.placements.indices.contains(index) else {
                focus = tiles.first?.id
                return .handled
            }
            let here = metrics.placements[index]
            let row = here.row + (press.key == .downArrow ? 1 : -1)
            let candidates = metrics.placements.enumerated().filter { $0.element.row == row }
            if let next = candidates.min(by: { abs($0.element.column - here.column) < abs($1.element.column - here.column) }) {
                focus = tiles[next.offset].id
            }
            return .handled
        case .tab:
            keyboardUsed = true
            return .ignored
        default:
            return .ignored
        }
    }

    /// The opening moment: the tiles light up one after another with their bulbs' colours. With Reduce Motion they
    /// all fade in together.
    private func lightUp(count: Int) async {
        guard revealed < count else { return }
        if reduceMotion {
            withAnimation(Desvan.Motion.fade) { revealed = count }
            return
        }
        try? await Task.sleep(for: .milliseconds(120))
        while revealed < count, !Task.isCancelled {
            withAnimation(.easeOut(duration: 0.35)) { revealed += 1 }
            try? await Task.sleep(for: .milliseconds(55))
        }
    }

    // MARK: - Design reviews

    /// `-demoHome area|detail|blind|few|many` in the openHome scenario: a room browsed, a light's controls, a blind's,
    /// two favourites (with the "picked for you" hint) or twelve.
    private func applyDemo() {
        guard model.scenario == .openHome, let demo = DesvanHomeDemo.current else { return }
        store.applyDesignDemo(demo)
        switch demo {
        case .area:
            selection = .area("living_room")
            store.watchArea("living_room")
        case .detail, .blind:
            let local = demo == .detail ? "light.living_room_lamp" : "cover.living_room_blind"
            if let tile = store.tiles(onPage: nil).first(where: { $0.entity.id.localID == local }) { detail = tile }
        case .few, .many:
            break
        }
    }
}

/// What the chips can show.
enum HomeSelection: Hashable {
    /// Favourites (nil) or one of the user's pages.
    case page(HomePage.ID?)
    /// Everything worth a tile in one of Home Assistant's areas.
    case area(String)
}

struct HomeChip: Hashable {
    let selection: HomeSelection
    let title: String
}

/// `-demoHome <state>` for design reviews (only in the openHome scenario).
enum DesvanHomeDemo: String {
    case area, detail, blind, few, many

    static let current: DesvanHomeDemo? = UserDefaults.standard.string(forKey: "demoHome").flatMap(Self.init(rawValue:))
}

// MARK: - Grid

/// Places the tiles where `HomeGridMetrics` says: columns of equal width, wide tiles over two, rows of `tileHeight`.
struct HomeGridLayout: Layout {
    let metrics: HomeGridMetrics
    let tileHeight: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = CGFloat(metrics.rows)
        return CGSize(width: proposal.width ?? 600, height: max(0, rows * tileHeight + max(rows - 1, 0) * spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = CGFloat(max(metrics.columns, 1))
        let columnWidth = (bounds.width - spacing * (columns - 1)) / columns
        for (index, subview) in subviews.enumerated() {
            guard metrics.placements.indices.contains(index) else {
                subview.place(at: bounds.origin, proposal: .zero)
                continue
            }
            let placement = metrics.placements[index]
            let span = CGFloat(placement.span)
            let x = bounds.minX + CGFloat(placement.column) * (columnWidth + spacing)
            let y = bounds.minY + CGFloat(placement.row) * (tileHeight + spacing)
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: columnWidth * span + spacing * (span - 1), height: tileHeight))
        }
    }
}

// MARK: - Header

/// The house's name, then the chips: Favourites, the user's pages and every room. Picking a room browses all of it.
/// The first time Altillo picked the favourites itself, a quiet line says so, with a way to change them.
private struct DesvanHomeHeader: View {
    let name: String
    let chips: [HomeChip]
    @Binding var selection: HomeSelection
    var hint: Int?
    var change: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: name)
                .font(Desvan.Typeface.display(15, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
                .fixedSize()
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(chips, id: \.selection) { chip in
                            self.chip(chip).id(chip.selection)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: selection) { _, new in
                    withAnimation(Desvan.Motion.content) { proxy.scrollTo(new, anchor: .center) }
                }
            }
            .mask {
                // The chips fade out under the hint rather than stopping at a hard edge.
                LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.92),
                                       .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            }
            if let hint {
                HStack(spacing: 4) {
                    Text("Altillo picked \(hint) to start")
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                    Button("Change", action: change)
                        .buttonStyle(.plain)
                        .foregroundStyle(Desvan.Palette.bulb)
                        .desvanHitTarget()
                }
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .transition(.opacity)
            }
        }
        .frame(height: 26)
    }

    private func chip(_ chip: HomeChip) -> some View {
        let isSelected = selection == chip.selection
        return Button {
            withAnimation(Desvan.Motion.content) { selection = chip.selection }
        } label: {
            Text(verbatim: chip.title)
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .foregroundStyle(isSelected ? Desvan.Palette.bulbInk : Desvan.Palette.paperSecondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background {
                    if isSelected {
                        Capsule().fill(Desvan.Palette.bulb.opacity(0.94))
                            .overlay {
                                Capsule().fill(LinearGradient(colors: [.white.opacity(0.3), .clear],
                                                              startPoint: .top, endPoint: .center))
                            }
                            .shadow(color: Desvan.Palette.bulb.opacity(0.35), radius: 6)
                    } else {
                        Capsule().fill(Desvan.Palette.paper.opacity(0.06))
                            .overlay { Capsule().strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
                    }
                }
                .contentShape(Capsule())
                .desvanHitTarget()
        }
        .buttonStyle(DesvanPressStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Loading

/// While connecting: eight blank plates breathing softly where the real ones will be.
private struct DesvanHomeSkeleton: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(0..<8, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DesvanHomeTile.radius, style: .continuous)
                    .fill(Desvan.Palette.paper.opacity(dim ? 0.04 : 0.08))
                    .frame(height: 79)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { dim = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connecting to your home…")
    }
}
