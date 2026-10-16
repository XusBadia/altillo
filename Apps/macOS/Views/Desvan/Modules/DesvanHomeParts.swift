import AltilloHome
import AppKit
import SwiftUI

// The Home section's pieces: a tile (a switch plate), a scene's luggage tag, the sensors' line, the doorbell's camera
// card and the ear beside the resting notch.

extension HomeRGB {
    var color: Color { Color(red: red, green: green, blue: blue) }
}

// MARK: - A tile

/// One tile as a switch plate (docs/casa-v2.md §1): a raised wood plate with a black bakelite disc holding the
/// glyph, the name and one quiet line (the room, or a value worth saying). A light that's on lights the plate from
/// its disc with the bulb's real colour, as bright as the bulb is; a plug or fan warms it a little. The state reads
/// on the lamp, never as "Off".
///
/// Press: it gives under the pointer at once. Click toggles; a sideways drag sets a light's brightness or a blind's
/// position 1:1 (a tap of the trackpad at 0 and 100 %); holding 0.6 s (or the chevron on hover) opens its controls.
/// Right-click edits it.
struct DesvanHomeTile: View {
    let tile: HomeResolvedTile
    let store: HomeStore
    /// The second line when there's no value to say; nil while browsing that room.
    var room: String?
    /// Drawn wide: a light shows its dimmer track, a blind its big slats.
    var isWide: Bool
    var height: CGFloat
    /// False until the opening stagger reaches this tile: its light stays off till then.
    var isRevealed: Bool = true
    /// The keyboard is on this tile (drawn only once the keyboard is in use).
    var showsFocus: Bool = false
    let haptic: (Haptics.Pattern) -> Void
    let openDetail: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false
    @State private var dragStart: Double?
    @State private var dragValue: Double?
    @State private var isDragging = false
    @State private var longPress: Task<Void, Never>?
    @State private var didLongPress = false
    @State private var width: CGFloat = 140
    @State private var breathe = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let radius: CGFloat = 12
    private static let longPressDuration: Duration = .milliseconds(600)

    private var entity: HomeEntity { tile.entity }
    private var state: HomeEntityState { store.state(of: entity) }
    private var isPending: Bool { store.isPending(entity.id) }
    private var isAvailable: Bool { state.isAvailable }
    private var isFavourite: Bool { store.isFavourite(entity.id) }
    /// Short plates lay the disc beside the name instead of above it.
    private var isCompact: Bool { height < 76 }
    /// A plate with the whole height to itself (one row): a bigger disc and name.
    private var isLarge: Bool { height >= 112 }
    private var nameSize: CGFloat { isLarge ? 15 : 13 }

    /// Whether a sideways drag (and ←/→) sets a level here.
    var hasLevel: Bool { Self.hasLevel(entity) }

    static func hasLevel(_ entity: HomeEntity) -> Bool {
        guard entity.state.isAvailable else { return false }
        return (entity.kind == .light && entity.capabilities.contains(.brightness))
            || (entity.kind == .cover && entity.capabilities.contains(.position))
    }

    /// 0…1: the light's brightness (0 off) or the blind's position.
    private var level: Double {
        if let dragValue { return dragValue }
        return Self.level(of: entity, state: state)
    }

    static func level(of entity: HomeEntity, state: HomeEntityState) -> Double {
        switch entity.kind {
        case .light: state.isOn == true ? state.brightness ?? 1 : 0
        case .cover: state.position ?? (HomeStore.coverIsOpen(state) ? 1 : 0)
        default: state.isOn == true ? 1 : 0
        }
    }

    /// How much the plate glows: a lit bulb by its brightness (0.35…1), a plug or fan a little, nothing else.
    private var glow: Double {
        guard isRevealed, isAvailable else { return 0 }
        switch entity.kind {
        case .light:
            if let dragValue { return dragValue > 0 ? 0.35 + 0.65 * dragValue : 0 }
            return state.isOn == true ? 0.35 + 0.65 * (state.brightness ?? 1) : 0
        case .switchable, .fan: return state.isOn == true ? 0.3 : 0
        case .script: return state.isOn == true ? 0.3 : 0
        default: return 0
        }
    }

    private var tint: Color {
        entity.kind == .light ? store.glowColor(for: entity).color : Desvan.Palette.bulb
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        content
            .padding(.horizontal, isWide ? 12 : 10)
            .padding(.vertical, isCompact ? 7 : 9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(height: height)
            .background { plate(shape) }
            .overlay(alignment: .topTrailing) { chevron }
            .overlay {
                if !isAvailable { DesvanDashedBevel(radius: Self.radius) }
            }
            .overlay {
                if showsFocus {
                    shape.strokeBorder(Desvan.Palette.bulb.opacity(0.8), lineWidth: 1.5)
                        .shadow(color: Desvan.Palette.bulb.opacity(0.45), radius: 6)
                        .padding(-2)
                        .allowsHitTesting(false)
                }
            }
            .opacity(isAvailable ? (isRevealed ? 1 : 0.55) : 0.4)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.97 : (isHovering && isAvailable ? 1.015 : 1)))
            .contentShape(shape)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max(1, $0) }
            .onHover { hovering in
                withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { isHovering = hovering }
            }
            .gesture(press, including: isRenaming ? .subviews : .all)
            .contextMenu { menu }
            .animation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion),
                       value: isPressed)
            .animation(Desvan.Motion.pick(.easeOut(duration: 0.3), reduceMotion: reduceMotion), value: glow)
            .animation(Desvan.Motion.pick(.spring(response: 0.35, dampingFraction: 1), reduceMotion: reduceMotion),
                       value: dragValue == nil ? level : nil)
            .task(id: isPending) { await breatheWhilePending() }
            .help(store.problems[entity.id] ?? tile.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tile.name)
            .accessibilityValue(accessibilityValue)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.activate(entity) }
            .accessibilityAction(named: Text("Show Controls")) { openDetail() }
            .accessibilityAdjustableAction { direction in
                guard hasLevel else { return }
                store.drag(entity, to: level + (direction == .increment ? 0.1 : -0.1), final: true)
            }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        if isWide, entity.kind == .light, hasLevel || entity.capabilities.contains(.brightness) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    disc(size: isLarge ? 46 : (isCompact ? 32 : 36), glyph: isLarge ? 30 : (isCompact ? 20 : 24))
                    titles
                    Spacer(minLength: 24)
                }
                Spacer(minLength: 4)
                DesvanDimmerTrack(level: level, tint: tint, isActive: glow > 0, isDragging: isDragging)
                    .frame(height: 16)
            }
        } else if isWide, entity.kind == .cover, tile.symbol == nil {
            HStack(spacing: 12) {
                DesvanBlindGlyph(position: level, size: min(height - 26, 84),
                                 isActive: isAvailable && level > 0, isDimmed: !isAvailable)
                    .opacity(breatheOpacity)
                titles
                Spacer(minLength: 24)
            }
            .frame(maxHeight: .infinity)
        } else if isCompact || isWide {
            HStack(spacing: 9) {
                disc(size: 32, glyph: isWide ? 24 : 20)
                titles
                Spacer(minLength: 0)
            }
            .frame(maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                disc(size: isLarge ? 46 : 32, glyph: isLarge ? 30 : 20)
                Spacer(minLength: 2)
                titles
            }
        }
    }

    private func disc(size: CGFloat, glyph: CGFloat) -> some View {
        DesvanBakeliteDisc(size: size, glow: glow, tint: tint) {
            DesvanHomeGlyph(entity: entity, state: state, symbol: tile.symbol, size: glyph, tint: tint, glow: glow,
                            level: dragValue)
                .opacity(breatheOpacity)
        }
    }

    private var breatheOpacity: Double {
        guard isPending else { return 1 }
        return reduceMotion ? 0.75 : (breathe ? 0.6 : 1)
    }

    @ViewBuilder
    private var titles: some View {
        VStack(alignment: .leading, spacing: 1) {
            if isRenaming {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(Desvan.Typeface.rounded(nameSize, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .focused($nameFieldFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .onChange(of: nameFieldFocused) { if !nameFieldFocused, isRenaming { commitRename() } }
            } else {
                Text(verbatim: tile.name)
                    .font(Desvan.Typeface.rounded(nameSize, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(secondLine == nil && isCompact ? 2 : 1)
                    .truncationMode(.tail)
            }
            secondLineView
        }
    }

    private var secondLine: String? {
        if let problem = store.problems[entity.id] { return problem }
        if let dragValue { return HomeText.percent(dragValue) }
        return HomeText.tileLine(for: entity, state: state, room: room)
    }

    @ViewBuilder
    private var secondLineView: some View {
        if let problem = store.problems[entity.id] {
            Label(problem, systemImage: "exclamationmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(Desvan.Palette.critical)
                .lineLimit(1)
                .transition(.opacity)
        } else if let line = secondLine {
            Text(verbatim: line)
                .font(.system(size: isLarge ? 12 : 11, weight: .medium))
                .foregroundStyle(glow > 0 ? Desvan.Palette.paper.opacity(0.78) : Desvan.Palette.paperTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }

    // MARK: The plate

    private func plate(_ shape: RoundedRectangle) -> some View {
        let discRadius: CGFloat = isLarge ? 23 : 16
        let discCenter = UnitPoint(x: min(0.5, ((isWide ? 12 : 10) + discRadius) / max(width, 1)),
                                   y: isCompact || (isWide && entity.kind != .light) ? 0.5
                                       : min(0.5, (9 + discRadius) / max(height, 1)))
        return ZStack {
            Color.clear.desvanCard(radius: Self.radius, fill: Desvan.Palette.woodRaised, grain: 0.6)
            // Off: dark glass over the wood, a little sheen on top.
            shape.fill(LinearGradient(colors: [Desvan.Palette.paper.opacity(0.035), .black.opacity(0.22)],
                                      startPoint: .top, endPoint: .bottom))
                .opacity(1 - glow)
            // On: the bulb's light spreading over the plate from the disc. Light, not paint.
            shape.fill(RadialGradient(
                stops: [
                    .init(color: tint.opacity(0.62 * glow), location: 0),
                    .init(color: tint.opacity(0.26 * glow), location: 0.35),
                    .init(color: tint.opacity(0.06 * glow), location: 1),
                ],
                center: discCenter, startRadius: 0, endRadius: max(width, height) * (isWide ? 0.75 : 1.0)
            ))
            .blendMode(.plusLighter)
            .opacity(glow > 0 ? 1 : 0)
            // A dimmed light: a tinted fill along the bottom edge, as far as it's bright.
            if !isWide, entity.kind == .light, hasLevel, glow > 0 || dragValue != nil {
                GeometryReader { proxy in
                    Capsule()
                        .fill(tint.opacity(dragValue != nil ? 1 : 0.85))
                        .shadow(color: tint.opacity(0.8), radius: 3)
                        .frame(width: max(3, (proxy.size.width - 20) * level), height: 2.5)
                        .position(x: 10 + max(3, (proxy.size.width - 20) * level) / 2, y: proxy.size.height - 3.5)
                }
            }
        }
        .clipShape(shape)
        .overlay {
            // The bevel, tinted by the light it catches.
            shape.strokeBorder(tint.opacity(0.2 + 0.45 * glow), lineWidth: 0.9).opacity(glow > 0 ? 1 : 0)
        }
        .overlay {
            if isHovering, isAvailable {
                shape.strokeBorder(Desvan.Palette.paper.opacity(0.2), lineWidth: 1).allowsHitTesting(false)
            }
        }
        .shadow(color: tint.opacity(0.45 * glow), radius: 4 + 8 * glow)
        .shadow(color: .black.opacity(isPressed ? 0.25 : 0.45), radius: isPressed ? 1 : 2.5, y: isPressed ? 0.5 : 1.5)
    }

    /// On hover, a chevron to the tile's controls.
    @ViewBuilder
    private var chevron: some View {
        if isHovering, isAvailable, !isRenaming, DesvanHomeDetail.hasControls(entity) {
            Button(action: openDetail) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Desvan.Palette.paper.opacity(0.85))
                    .frame(width: 20, height: 20)
                    .background { Circle().fill(Color.black.opacity(0.45)) }
                    .overlay { Circle().strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.6) }
                    .desvanHitTarget()
            }
            .buttonStyle(DesvanPressStyle())
            .padding(5)
            .transition(.opacity)
            .help(String(localized: "Show Controls"))
            .accessibilityLabel("Show Controls")
        }
    }

    // MARK: Press, drag, hold

    /// One gesture for the three: feedback on press-down, a drag past 6 pt sideways sets the level 1:1, holding still
    /// for 0.6 s opens the controls, and a release that did neither is a click.
    private var press: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard isAvailable || entity.kind.isAction else { return }
                if !isPressed, !isDragging, !didLongPress, longPress == nil {
                    isPressed = true
                    armLongPress()
                }
                let dx = value.translation.width, dy = value.translation.height
                let moved = hypot(dx, dy)
                if !isDragging, moved > 6 {
                    longPress?.cancel()
                    longPress = nil
                    if hasLevel, abs(dx) > abs(dy) {
                        isDragging = true
                        dragStart = Self.level(of: entity, state: state)
                    }
                }
                guard isDragging, let start = dragStart else { return }
                // The dimmer's track (wide) or the plate (small) is the whole range: the level follows the pointer.
                let span = isWide && entity.kind == .light ? max(width - 40, 1) : max(width, 1)
                let next = min(max(start + dx / span, 0), 1)
                if (next == 0 || next == 1), dragValue != next { haptic(.snap) }
                dragValue = next
                store.drag(entity, to: next, final: false)
            }
            .onEnded { value in
                longPress?.cancel()
                longPress = nil
                defer {
                    isPressed = false
                    isDragging = false
                    didLongPress = false
                    dragStart = nil
                    dragValue = nil
                }
                if didLongPress { return }
                if isDragging {
                    if let dragValue { store.drag(entity, to: dragValue, final: true) }
                    return
                }
                if hypot(value.translation.width, value.translation.height) < 6, isAvailable || entity.kind.isAction {
                    store.activate(entity)
                }
            }
    }

    private func armLongPress() {
        guard DesvanHomeDetail.hasControls(entity) else { return }
        longPress = Task { @MainActor in
            try? await Task.sleep(for: Self.longPressDuration)
            guard !Task.isCancelled, isPressed, !isDragging else { return }
            didLongPress = true
            isPressed = false
            haptic(.land)
            openDetail()
        }
    }

    private func breatheWhilePending() async {
        guard isPending, !reduceMotion else {
            breathe = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathe = true }
    }

    private var accessibilityValue: String {
        if let problem = store.problems[entity.id] { return problem }
        var parts = [HomeText.stateLine(for: entity, state: state)]
        if let room { parts.append(room) }
        return parts.joined(separator: ", ")
    }

    // MARK: Editing

    @ViewBuilder
    private var menu: some View {
        if isFavourite {
            Button("Rename…") {
                draftName = tile.name
                isRenaming = true
                Task { @MainActor in nameFieldFocused = true }
            }
            Menu("Icon") {
                Button {
                    store.setSymbol(entity.id, nil)
                } label: {
                    Label("Default", systemImage: tile.symbol == nil ? "checkmark" : "arrow.uturn.backward")
                }
                Divider()
                ForEach(HomeText.curatedSymbols(for: entity.kind), id: \.self) { symbol in
                    Button {
                        store.setSymbol(entity.id, symbol)
                    } label: {
                        Image(systemName: symbol)
                    }
                    .accessibilityLabel(Text(verbatim: symbol))
                }
            }
            Menu("Size") {
                ForEach(HomeTileSize.allCases, id: \.self) { size in
                    Toggle(isOn: Binding(get: { tile.size == size }, set: { if $0 { store.setSize(entity.id, size) } })) {
                        Text(verbatim: size == .small
                             ? String(localized: "home.tileSize.small", defaultValue: "Small")
                             : String(localized: "home.tileSize.wide", defaultValue: "Wide"))
                    }
                }
            }
            Button("Hide") { store.setHidden(entity.id, true) }
            Divider()
            Button("Remove from Favourites") { store.removeFavourite(entity.id) }
        } else {
            Button("Add to Favourites") { store.addFavourite(entity.id) }
        }
        if DesvanHomeDetail.hasControls(entity) {
            Divider()
            Button("Show Controls", action: openDetail)
        }
        if let url = store.homeAssistantURL(for: entity.id) {
            Divider()
            Button("Open in Home Assistant") { NSWorkspace.shared.open(url) }
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        store.rename(entity.id, to: draftName)
    }
}

// MARK: - Scenes

/// A scene or script as a kraft luggage tag (the same paper as Shortcuts' tags): its glyph and name in ink, an
/// eyelet at the cut end. A tick when Home Assistant has run it.
struct DesvanHomeSceneTag: View {
    let tile: HomeResolvedTile
    let store: HomeStore

    @State private var isHovering = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 34

    var body: some View {
        let entity = tile.entity
        let firing = store.firing.contains(entity.id)
        let fired = store.fired.contains(entity.id)
        let problem = store.problems[entity.id]
        let shape = DesvanLuggageTagShape(cut: 9, radius: 4)
        HStack(spacing: 7) {
            // The eyelet: a brass ring punched through the tag.
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: 5, height: 5)
                .overlay { Circle().strokeBorder(Color(hex: 0xB89458), lineWidth: 1.6).padding(-2) }
                .padding(.leading, 9)
            ZStack {
                if firing {
                    ProgressView().controlSize(.mini).tint(Desvan.Palette.ink)
                } else if fired {
                    Image(systemName: "checkmark").foregroundStyle(Color(hex: 0x3F6B35))
                        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
                } else if problem != nil {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: 0xA3341F))
                } else {
                    Image(systemName: tile.symbol ?? HomeText.filledSymbol(for: entity, state: entity.state))
                        .foregroundStyle(Desvan.Palette.ink.opacity(0.85))
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .frame(width: 15)
            Text(verbatim: tile.name)
                .font(Desvan.Typeface.rounded(13, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink)
                .lineLimit(1)
        }
        .padding(.trailing, 13)
        .frame(height: Self.height)
        .background {
            shape.fill(LinearGradient(colors: [Color(hex: 0xD9BB92), Desvan.Palette.kraft],
                                      startPoint: .top, endPoint: .bottom))
                .desvanTexture(DesvanTexture.kraft, opacity: 0.28, in: shape)
                .overlay { shape.stroke(Color.white.opacity(0.22), lineWidth: 0.75) }
                .shadow(color: .black.opacity(isHovering ? 0.55 : 0.4), radius: isHovering ? 5 : 2, y: isHovering ? 2.5 : 1.5)
        }
        .overlay {
            if isHovering || firing {
                shape.stroke(Desvan.Palette.bulb.opacity(0.8), lineWidth: 1)
                    .shadow(color: Desvan.Palette.bulb.opacity(0.45), radius: 6)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.96 : (isHovering ? 1.02 : 1)))
        .contentShape(shape)
        .opacity(entity.state.isAvailable ? 1 : 0.4)
        .onHover { hovering in
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { isHovering = hovering }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isPressed { isPressed = true } }
                .onEnded { value in
                    isPressed = false
                    if hypot(value.translation.width, value.translation.height) < 6 { store.activate(entity) }
                }
        )
        .contextMenu {
            if store.isFavourite(entity.id) {
                Button("Hide") { store.setHidden(entity.id, true) }
                Button("Remove from Favourites") { store.removeFavourite(entity.id) }
            } else {
                Button("Add to Favourites") { store.addFavourite(entity.id) }
            }
            if let url = store.homeAssistantURL(for: entity.id) {
                Divider()
                Button("Open in Home Assistant") { NSWorkspace.shared.open(url) }
            }
        }
        .animation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion), value: isPressed)
        .animation(Desvan.Motion.content, value: fired)
        .help(problem ?? String(localized: "Run “\(tile.name)”"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { store.activate(entity) }
        .accessibilityHint(entity.kind == .scene ? "Activates the scene." : "Runs the script.")
    }
}

// MARK: - Sensors

/// Temperature, humidity, doors: compact readings, the figure in bold beside its glyph. The name is in the tooltip
/// and for VoiceOver.
struct DesvanHomeSensors: View {
    let tiles: [HomeResolvedTile]
    let store: HomeStore

    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 12) {
            ForEach(tiles) { tile in
                let entity = tile.entity
                let state = store.state(of: entity)
                let alert = entity.kind == .binarySensor && state.isOn == true
                    && ["door", "window", "garage_door", "opening"].contains(entity.deviceClass ?? "")
                HStack(spacing: 4) {
                    Image(systemName: tile.symbol ?? HomeText.symbol(for: entity, state: state))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(alert ? Desvan.Palette.warning : Desvan.Palette.paperTertiary)
                    Text(verbatim: HomeText.stateLine(for: entity, state: state))
                        .font(Desvan.Typeface.figure(13))
                        .foregroundStyle(alert ? Desvan.Palette.warning : Desvan.Palette.paper)
                }
                .lineLimit(1)
                .fixedSize()
                .frame(height: Self.height)
                .opacity(state.isAvailable ? 1 : 0.4)
                .help(tile.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tile.name)
                .accessibilityValue(HomeText.stateLine(for: entity, state: state))
            }
        }
    }
}

// MARK: - Camera card

/// After a ring, for two minutes: the camera's picture, who rang and when, a refresh and a way to put it away.
struct DesvanHomeCameraCard: View {
    let ring: HomeRing
    let name: String?
    let now: Date
    let hasCamera: Bool
    let refresh: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if hasCamera {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.5))
                    if let snapshot = ring.snapshot {
                        Image(nsImage: snapshot)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity)
                    } else if ring.isLoadingSnapshot {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "video.slash").foregroundStyle(Desvan.Palette.paperTertiary)
                    }
                }
                .frame(width: 136, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.75)
                }
                .accessibilityLabel("The door camera's picture")
            }
            VStack(alignment: .leading, spacing: 3) {
                Label("Someone rang", systemImage: "bell.fill")
                    .font(Desvan.Typeface.rounded(14, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                Text(verbatim: [name, NotchFormat.ago(ring.at)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    if hasCamera {
                        Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 26))
                    }
                    Button("Dismiss", action: dismiss)
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 26))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(height: 92)
        .desvanCard(radius: 12, glow: Desvan.Palette.bulb)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Ear

/// The house in the ear: the door's symbol, how long it's been open and (in a fixed ear) its name; or a bulb and
/// how many lights were left on.
struct DesvanHomeEar: View {
    let signal: HomeSignal
    let now: Date
    var showsName: Bool

    var body: some View {
        HStack(spacing: EarMetrics.spacing) {
            Image(systemName: signal.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Desvan.Palette.bulb)
                .frame(width: EarMetrics.Glyph.home)
            switch signal {
            case let .leftOpen(name, _, since):
                Text(verbatim: EarMetrics.homeMinutesText("\(HomeEarLogic.minutes(since: since, now: now))"))
                    .font(Desvan.Typeface.figure(EarMetrics.TextSize.figure, weight: .medium))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .lineLimit(1)
                    .fixedSize()
                if showsName, !name.isEmpty {
                    Text(verbatim: name)
                        .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: EarMetrics.measuredTitleWidth(name), alignment: .leading)
                }
            case let .lightsOnWhileAway(count):
                Text(verbatim: HomeEarLogic.lightsOnText(count))
                    .font(Desvan.Typeface.rounded(EarMetrics.TextSize.title, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize()
    }
}

// MARK: - Previews

#Preview("Home") {
    let model = NotchModel()
    model.scenario = .openHome
    return DesvanHomeView(model: model)
        .padding(26)
        .frame(width: 640, height: 238 + 52)
        .background(Color.black)
}

#Preview("Tiles") {
    let store = HomeStore.demo()
    return HStack(spacing: 8) {
        ForEach(store.tiles(onPage: nil).prefix(4)) { tile in
            DesvanHomeTile(tile: tile, store: store, room: store.area(tile.entity.areaID)?.name, isWide: false,
                           height: 79, haptic: { _ in }, openDetail: {})
        }
    }
    .padding(20)
    .frame(width: 620)
    .background(Color.black)
}
