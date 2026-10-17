import AltilloHome
import SwiftUI

/// A tile's controls (docs/casa-v2.md §3), in place of the grid, all on one wooden wall: a dimmable light's brass
/// dial (turn the ring, click the knob), a plug's or plain light's bakelite wall switch, a blind's window to pull
/// down by its handle. Back (or Esc) returns to the tiles.
///
/// Everything answers on press-down and follows the pointer 1:1; the value is sent when let go, and the face
/// follows Home Assistant's push.
struct DesvanHomeDetail: View {
    let tile: HomeResolvedTile
    let store: HomeStore
    /// "Favourites", a page's or a room's name: where Back goes.
    let backTitle: String
    let haptic: (Haptics.Pattern) -> Void
    let back: () -> Void

    @FocusState private var isFocused: Bool
    @State private var dragLevel: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Kinds with more to them than a click.
    static func hasControls(_ entity: HomeEntity) -> Bool {
        switch entity.kind {
        case .light, .cover, .switchable, .fan: true
        default: false
        }
    }

    private var entity: HomeEntity { store.service.entities[tile.entity.id] ?? tile.entity }
    private var state: HomeEntityState { store.state(of: entity) }
    private var level: Double { dragLevel ?? DesvanHomeTile.level(of: entity, state: state) }
    private var room: String? { store.area(entity.areaID)?.name }
    /// When the state last changed, from the server (a prediction has no date).
    private var since: Date? { (store.service.entities[entity.id] ?? entity).state.lastChanged }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Group {
                switch HomeDetailLogic.face(for: entity) {
                case .dimmer: light
                case .blind: blind
                case .toggle: power
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .desvanCard(radius: 14, fill: Desvan.Palette.wood, grain: 0.6)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear { isFocused = true }
        .onKeyPress(.escape) {
            back()
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .downArrow]) { _ in step(-0.1) }
        .onKeyPress(keys: [.rightArrow, .upArrow]) { _ in step(0.1) }
        .onKeyPress(.space) {
            store.activate(entity)
            return .handled
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Label(backTitle, systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 24))
            .help(String(localized: "Back (Esc)"))
            Text(verbatim: tile.name)
                .font(Desvan.Typeface.display(15, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            if let room {
                Text(verbatim: room)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = store.homeAssistantURL(for: entity.id) {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                        .frame(width: 24, height: 24)
                        .desvanHitTarget()
                }
                .buttonStyle(DesvanPressStyle())
                .help(String(localized: "Open in Home Assistant"))
                .accessibilityLabel("Open in Home Assistant")
            }
        }
        .frame(height: 26)
    }

    /// "Since 14:32" under a state, kept current by the minute.
    private var sinceLine: some View {
        TimelineView(.everyMinute) { context in
            if let text = HomeDetailLogic.since(since, now: context.date) {
                Label {
                    Text(verbatim: text)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .lineLimit(1)
            }
        }
    }

    // MARK: Light

    private var tint: Color { store.glowColor(for: entity).color }
    private var isOn: Bool { dragLevel.map { $0 > 0 } ?? (state.isOn == true) }

    private var light: some View {
        HStack(alignment: .center, spacing: 24) {
            DesvanHomeDimmerDial(
                level: level,
                tint: tint,
                isOn: isOn,
                isAdjustable: state.isAvailable,
                change: { value, final in
                    dragLevel = final ? nil : value
                    store.drag(entity, to: value, final: final)
                },
                pressKnob: {
                    haptic(.snap)
                    store.activate(entity)
                },
                haptic: { haptic(.snap) }
            )
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(verbatim: HomeText.stateLine(for: entity, state: dragLevel.map { value in
                            var preview = state
                            preview.isOn = value > 0
                            preview.brightness = value > 0 ? value : nil
                            return preview
                        } ?? state))
                            .font(Desvan.Typeface.figure(22))
                            .foregroundStyle(isOn ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                            .contentTransition(.numericText())
                            .lineLimit(1)
                        if store.isPending(entity.id) {
                            ProgressView().controlSize(.small).tint(Desvan.Palette.bulb)
                        }
                    }
                    sinceLine
                }
                if entity.capabilities.contains(.colorTemperature) {
                    DesvanHomeWarmth(color: store.glowColor(for: entity)) { kelvin in
                        store.setColorTemperature(entity, kelvin: kelvin)
                    }
                }
                if entity.capabilities.contains(.color) {
                    DesvanHomeSwatches(current: isOn ? store.glowColor(for: entity) : nil) { color in
                        haptic(.snap)
                        store.setColor(entity, color)
                    }
                }
                if !entity.capabilities.contains(.color), !entity.capabilities.contains(.colorTemperature) {
                    brightnessPresets
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!state.isAvailable)
        }
    }

    /// For a light that only dims: four quick levels as kraft keys, so the face is never an empty card.
    private var brightnessPresets: some View {
        HStack(spacing: 8) {
            ForEach([0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                Button {
                    haptic(.snap)
                    store.drag(entity, to: value, final: true)
                } label: {
                    VStack(spacing: 3) {
                        DesvanBulbGlyph(size: 13, lit: 0.25 + 0.75 * value, tint: tint)
                        Text(verbatim: HomeText.percent(value))
                            .font(Desvan.Typeface.rounded(11, weight: .bold))
                    }
                }
                .buttonStyle(DesvanKraftKeyStyle(isSelected: isOn && abs(level - value) < 0.03))
                .accessibilityLabel(Text(verbatim: HomeText.percent(value)))
            }
        }
    }

    // MARK: Blind

    private var blind: some View {
        let travel = store.coverTravel(entity)
        let canPosition = entity.capabilities.contains(.position)
        let shownPosition = travel.isMoving ? travel.position : (dragLevel ?? DesvanHomeTile.level(of: entity, state: state))
        let readout: HomeEntityState = {
            var preview = state
            if let dragLevel {
                preview.position = dragLevel
                preview.raw = dragLevel > 0 ? "open" : "closed"
            } else if travel.isMoving {
                preview.position = travel.position
            }
            return preview
        }()
        return HStack(alignment: .center, spacing: 26) {
            DesvanHomeBlindWindow(
                position: shownPosition,
                target: travel.target,
                isMoving: travel.isMoving,
                style: HomeDetailLogic.blindStyle(for: entity),
                canPosition: canPosition && state.isAvailable,
                isAvailable: state.isAvailable,
                change: { value, final in
                    dragLevel = final ? nil : value
                    if final { store.drag(entity, to: value, final: true) }
                },
                toggle: { store.activate(entity) },
                stop: { store.stopCover(entity) },
                haptic: { haptic(.snap) }
            )
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: HomeText.stateLine(for: entity, state: travel.isMoving && dragLevel == nil ? {
                        var settled = readout
                        settled.raw = travel.position > 0 ? "open" : "closed"
                        return settled
                    }() : readout))
                        .font(Desvan.Typeface.figure(26))
                        .foregroundStyle(Desvan.Palette.paper)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if travel.isMoving {
                        HStack(spacing: 5) {
                            Image(systemName: travel.direction < 0 ? "arrow.down" : "arrow.up")
                            Text(verbatim: HomeDetailLogic.travelLine(travel))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.bulb)
                        .lineLimit(1)
                    } else {
                        sinceLine
                    }
                }
                HStack(spacing: 8) {
                    if canPosition {
                        blindPreset(1, title: Text("Open"))
                        blindPreset(0.5, title: Text(verbatim: "½"), label: Text("Half open"))
                        blindPreset(0, title: Text("Close"))
                    } else {
                        blindPreset(1, title: Text("Open"), command: .open)
                        blindPreset(0, title: Text("Close"), command: .close)
                    }
                    Button {
                        haptic(.snap)
                        store.stopCover(entity)
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "stop.fill").font(.system(size: 12, weight: .bold))
                            Text("Stop").font(Desvan.Typeface.rounded(11, weight: .bold))
                        }
                    }
                    .buttonStyle(DesvanKraftKeyStyle(isSelected: false, isBrass: travel.isMoving))
                    .help(String(localized: "Stop"))
                }
                .disabled(!state.isAvailable)
            }
            .frame(width: 280, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private enum PresetCommand { case position, open, close }

    private func blindPreset(_ value: Double, title: Text, label: Text? = nil, command: PresetCommand = .position) -> some View {
        let current = dragLevel ?? DesvanHomeTile.level(of: entity, state: state)
        return Button {
            haptic(.snap)
            switch command {
            case .position: store.drag(entity, to: value, final: true)
            case .open: if !HomeStore.coverIsOpen(state) { store.activate(entity) }
            case .close: if HomeStore.coverIsOpen(state) { store.activate(entity) }
            }
        } label: {
            VStack(spacing: 3) {
                DesvanBlindGlyph(position: value, size: 16)
                title.font(Desvan.Typeface.rounded(11, weight: .bold))
            }
        }
        .buttonStyle(DesvanKraftKeyStyle(isSelected: abs(current - value) < 0.03 && !store.coverTravel(entity).isMoving))
        .accessibilityLabel(label ?? title)
    }

    // MARK: Plug, switch, fan, plain light

    private var power: some View {
        let on = state.isOn == true
        return HStack(alignment: .center, spacing: 28) {
            DesvanHomeWallSwitch(
                isOn: on,
                isAvailable: state.isAvailable,
                name: tile.name,
                stateText: HomeText.stateLine(for: entity, state: state),
                glyph: {
                    DesvanHomeGlyph(entity: entity, state: state, symbol: tile.symbol, size: 17,
                                    tint: entity.kind == .light ? tint : Desvan.Palette.bulb, glow: on ? 1 : 0, level: nil)
                },
                toggle: {
                    haptic(.snap)
                    store.activate(entity)
                }
            )
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(verbatim: HomeText.stateLine(for: entity, state: state))
                        .font(Desvan.Typeface.figure(30))
                        .foregroundStyle(on ? Desvan.Palette.bulb : Desvan.Palette.paper)
                        .shadow(color: Desvan.Palette.bulb.opacity(on ? 0.45 : 0), radius: 8)
                        .contentTransition(.interpolate)
                        .lineLimit(1)
                    if store.isPending(entity.id) {
                        ProgressView().controlSize(.small).tint(Desvan.Palette.bulb)
                    }
                }
                sinceLine
                if let room {
                    Label {
                        Text(verbatim: room)
                    } icon: {
                        Image(systemName: "house")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                }
                Spacer().frame(height: 6)
                Text("Click the switch or flip its lever")
                    .font(.system(size: 11))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                if let url = store.homeAssistantURL(for: entity.id) {
                    Button("Open in Home Assistant", systemImage: "arrow.up.forward.square") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 26))
                }
            }
            .frame(width: 260, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func step(_ delta: Double) -> KeyPress.Result {
        guard DesvanHomeTile.hasLevel(entity) else { return .ignored }
        let next = min(max(DesvanHomeTile.level(of: entity, state: state) + delta, 0), 1)
        store.drag(entity, to: next, final: true)
        return .handled
    }
}

// MARK: - Logic

/// Which face a thing gets.
enum HomeDetailFace: Equatable {
    /// A light that dims: the dial.
    case dimmer
    /// Anything that only switches (plug, switch, fan, input_boolean, a plain light): the wall switch.
    case toggle
    /// A cover: the window.
    case blind
}

/// A blind on its way: where Home Assistant says it is and, when this Mac sent it, where it's going.
struct HomeCoverTravel: Equatable {
    var isMoving: Bool
    /// 0 closed … 1 open: the server's position (the predicted one if the server never said).
    var position: Double
    /// Where it was sent; nil when the trip wasn't ours or it's standing.
    var target: Double?
    /// -1 closing, +1 opening, 0 standing.
    var direction: Int
}

/// The detail face's decisions, apart from the drawing so tests can hold them.
enum HomeDetailLogic {
    static func face(for entity: HomeEntity) -> HomeDetailFace {
        switch entity.kind {
        case .cover: .blind
        case .light where entity.capabilities.contains(.brightness): .dimmer
        default: .toggle
        }
    }

    /// Fabric for shades and curtains, slats for everything else (a Spanish *persiana*).
    static func blindStyle(for entity: HomeEntity) -> DesvanBlindStyle {
        switch entity.deviceClass {
        case "shade", "curtain", "awning": .fabric
        default: .slats
        }
    }

    // Blind geometry: the bottom edge travels over `travel` points of glass, from `top` (open) down (closed). Home
    // Assistant's 0 is closed and 100 open, so the blind covers `1 − position` of the travel from the top.

    static func edgeY(position: Double, top: CGFloat, travel: CGFloat) -> CGFloat {
        top + CGFloat(1 - clamp(position)) * travel
    }

    /// The position whose edge sits at `y`: clamped, snapped to fully open or closed within 2 %, in whole percent.
    static func position(atY y: CGFloat, top: CGFloat, travel: CGFloat) -> Double {
        guard travel > 0 else { return 0 }
        var value = clamp(1 - Double((y - top) / travel))
        if value < 0.02 { value = 0 }
        if value > 0.98 { value = 1 }
        return (value * 100).rounded() / 100
    }

    /// A press this close to the edge grabs it (and keeps the offset, so the blind doesn't jump to the pointer).
    static func grabOffset(startY: CGFloat, edgeY: CGFloat, slop: CGFloat = 16) -> CGFloat? {
        abs(startY - edgeY) <= slop ? startY - edgeY : nil
    }

    /// A press that barely moved is a click.
    static func isClick(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < 4
    }

    /// The wall switch on release: a click flips it; a drag of the lever flips it if it went the other way (up is on).
    static func switchFlips(isOn: Bool, translation: CGSize) -> Bool {
        if isClick(translation) { return true }
        guard abs(translation.height) >= 8 else { return false }
        return (translation.height < 0) != isOn
    }

    /// Where the lever points while dragged, -1 (down, off) … 1 (up, on), 1:1 with the pointer.
    static func leverFlip(isOn: Bool, dragHeight: CGFloat, throwLength: CGFloat = 30) -> Double {
        clamp((isOn ? 1 : -1) - Double(dragHeight / throwLength), lower: -1)
    }

    static func coverTravel(server: HomeEntityState, pending: HomeEntityState?) -> HomeCoverTravel {
        let direction = server.raw == "closing" ? -1 : server.raw == "opening" ? 1 : 0
        let position = server.position ?? pending?.position ?? (HomeStore.coverIsOpen(server) ? 1 : 0)
        guard direction != 0 else { return HomeCoverTravel(isMoving: false, position: position, target: nil, direction: 0) }
        var target: Double?
        if let sent = pending?.position, abs(sent - position) > 0.01, (sent - position) * Double(direction) > 0 {
            target = sent
        }
        return HomeCoverTravel(isMoving: true, position: position, target: target, direction: direction)
    }

    /// "Closing to 15 %", or just "Closing…" when the trip isn't ours.
    static func travelLine(_ travel: HomeCoverTravel) -> String {
        if let target = travel.target {
            let percent = HomeText.percent(target)
            return travel.direction < 0
                ? String(localized: "home.cover.closingTo", defaultValue: "Closing to \(percent)")
                : String(localized: "home.cover.openingTo", defaultValue: "Opening to \(percent)")
        }
        return travel.direction < 0
            ? String(localized: "home.state.closing", defaultValue: "Closing…")
            : String(localized: "home.state.opening", defaultValue: "Opening…")
    }

    /// "Since 14:32", "Since yesterday at 22:10", "Since Monday at 9:05", "Since 3 Oct"; nil without a date.
    static func since(_ date: Date?, now: Date, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        if now.timeIntervalSince(date) < 60 { return String(localized: "home.since.now", defaultValue: "Since just now") }
        let time = atTime(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) {
            return String(localized: "home.since.today", defaultValue: "Since \(time)")
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: "home.since.yesterday", defaultValue: "Since yesterday at \(time)")
        }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 99
        if days < 7 {
            let weekday = date.formatted(Date.FormatStyle(calendar: calendar).weekday(.wide))
            return String(localized: "home.since.weekday", defaultValue: "Since \(weekday) at \(time)")
        }
        let day = date.formatted(Date.FormatStyle(calendar: calendar).day().month(.abbreviated))
        return String(localized: "home.since.date", defaultValue: "Since \(day)")
    }

    /// The clock time with its article where the language has one ("las 14:32", "la 1:05").
    private static func atTime(_ date: Date, calendar: Calendar) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, calendar: calendar))
        return calendar.component(.hour, from: date) == 1
            ? String(localized: "home.at.timeOne", defaultValue: "\(time)")
            : String(localized: "home.at.time", defaultValue: "\(time)")
    }

    private static func clamp(_ value: Double, lower: Double = 0) -> Double { min(max(value, lower), 1) }
}

// MARK: - Kraft key

/// A small kraft-paper key, pressed into the wall: the blind's and the dimmer's presets, Stop. The current one wears
/// a brass ring; `isBrass` makes the key itself brass (Stop while the blind travels).
struct DesvanKraftKeyStyle: ButtonStyle {
    var isSelected: Bool
    var isBrass = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return configuration.label
            .foregroundStyle(Desvan.Palette.ink.opacity(isEnabled ? 0.88 : 0.45))
            .frame(width: 56, height: 50)
            .background {
                shape
                    .fill(LinearGradient(
                        colors: isBrass ? [Color(hex: 0xF7DFA4), Color(hex: 0xD9A955)]
                            : [Color(hex: 0xE2CBA5), Color(hex: 0xC09C6E)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .grain(0.12, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [.white.opacity(pressed ? 0.15 : 0.55), .black.opacity(0.35)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: .black.opacity(pressed ? 0.3 : 0.55), radius: pressed ? 1 : 2.5, y: pressed ? 0.5 : 2)
            }
            .overlay {
                shape
                    .strokeBorder(LinearGradient(colors: [Color(hex: 0xF3DDA6), Color(hex: 0x9C7A43)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    .padding(-3)
                    .opacity(isSelected ? 1 : 0)
            }
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .offset(y: pressed && !reduceMotion ? 1 : 0)
            .opacity(isEnabled ? 1 : 0.55)
            .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: pressed)
            .animation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion),
                       value: isSelected)
            .contentShape(shape)
    }
}

// MARK: - Dimmer dial

/// A light's dimmer as a rotary dial, kin of the kitchen timer's: a dark wood rim, a cream enamel face with ticks
/// from 0 to 100 % over three quarters of a turn, the light's own colour filling the arc as far as it's bright, and
/// a bakelite knob with a brass pointer. Turn it by dragging round the face (1:1, no jumps across the gap; up from
/// off turns the light on); press the knob to switch the light — it sinks on press-down and switches on release.
struct DesvanHomeDimmerDial: View {
    let level: Double
    let tint: Color
    let isOn: Bool
    let isAdjustable: Bool
    let change: (Double, Bool) -> Void
    let pressKnob: () -> Void
    let haptic: () -> Void

    static let size: CGFloat = 164
    private static let rim: CGFloat = 7
    private static let knob: CGFloat = 80
    /// Where 0 % is, in SwiftUI degrees (0 = 3 o'clock, clockwise): 7:30.
    static let startAngle = 135.0
    static let sweep = 270.0

    @State private var dragLevel: Double?
    @State private var isKnobPressed = false
    @State private var isKnobHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Double { dragLevel ?? level }
    private var lit: Bool { dragLevel.map { $0 > 0 } ?? isOn }

    var body: some View {
        ZStack {
            face
            DesvanDialArc(from: Self.startAngle, sweep: Self.sweep * (lit ? shown : 0))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                    startAngle: .degrees(Self.startAngle), endAngle: .degrees(Self.startAngle + Self.sweep)),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .shadow(color: tint.opacity(0.7), radius: 5)
                .padding(Self.rim + 16)
                .animation(dragLevel == nil ? Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1),
                                                                 reduceMotion: reduceMotion) : nil, value: shown)
                .animation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion),
                           value: lit)
            DesvanDialTicks(start: Self.startAngle, sweep: Self.sweep)
                .padding(Self.rim + 2)
            knob
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(turn, including: isAdjustable ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness")
        .accessibilityValue(lit ? HomeText.percent(shown) : String(localized: "home.state.off", defaultValue: "Off"))
        .accessibilityAdjustableAction { direction in
            change(min(max((lit ? shown : 0) + (direction == .increment ? 0.1 : -0.1), 0), 1), true)
        }
        .accessibilityAction(named: Text(lit ? "Turn Off" : "Turn On")) { pressKnob() }
    }

    private var face: some View {
        ZStack {
            Circle()
                .fill(Desvan.Palette.woodRaised)
                .desvanTexture(DesvanTexture.wood, opacity: 0.35, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [Desvan.Palette.paper.opacity(0.22), .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF8F1E4), Color(hex: 0xE4D6BC)],
                                     center: UnitPoint(x: 0.45, y: 0.35), startRadius: 4, endRadius: Self.size * 0.55))
                .grain(0.09, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 2
                    )
                }
                .padding(Self.rim)
            // The light falling on the enamel.
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(lit ? 0.35 * (0.35 + 0.65 * shown) : 0), .clear],
                                     center: .center, startRadius: Self.knob / 2, endRadius: Self.size / 2))
                .blendMode(.multiply)
                .padding(Self.rim)
            // Low and high marks at the two ends of the scale.
            Image(systemName: "sun.min.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink.opacity(0.6))
                .offset(x: -Self.size * 0.2, y: Self.size * 0.36)
            Image(systemName: "sun.max.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.ink.opacity(0.75))
                .offset(x: Self.size * 0.2, y: Self.size * 0.36)
        }
    }

    private var knob: some View {
        let angle = Angle.degrees(Self.startAngle + Self.sweep * (lit ? shown : 0))
        let label = isKnobHovered && dragLevel == nil
            ? String(localized: lit ? "Turn Off" : "Turn On")
            : lit ? HomeText.percent(shown) : String(localized: "home.state.off", defaultValue: "Off")
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: isKnobPressed ? 0x231E1B : 0x2E2824), Color(hex: 0x0B0908)],
                                     center: UnitPoint(x: 0.4, y: isKnobPressed ? 0.34 : 0.28), startRadius: 0,
                                     endRadius: Self.knob * 0.7))
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [Desvan.Palette.paper.opacity(isKnobHovered ? 0.45 : 0.32), .black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                // The bulb's light caught in the bakelite when on.
                .overlay {
                    Circle()
                        .fill(RadialGradient(colors: [tint.opacity(lit ? 0.28 : 0), .clear], center: .center,
                                             startRadius: 0, endRadius: Self.knob * 0.5))
                        .blendMode(.plusLighter)
                }
                .shadow(color: .black.opacity(0.55), radius: isKnobPressed ? 1.5 : 4, y: isKnobPressed ? 1 : 3)
            // The brass pointer turning with the level.
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0xF3DDA6), Color(hex: 0x9C7A43)], startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 3.5)
                .offset(x: Self.knob / 2 - 10)
                .rotationEffect(angle)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .animation(dragLevel == nil ? Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1),
                                                                 reduceMotion: reduceMotion) : nil, value: shown)
            VStack(spacing: 1) {
                DesvanBulbGlyph(size: 18, lit: lit ? 0.35 + 0.65 * shown : 0, tint: tint)
                Text(verbatim: label)
                    .font(Desvan.Typeface.figure(isKnobHovered && dragLevel == nil ? 11 : 15))
                    .foregroundStyle(Desvan.Palette.paper)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: Self.knob - 16)
            }
        }
        .frame(width: Self.knob, height: Self.knob)
        .scaleEffect(isKnobPressed && !reduceMotion ? 0.96 : 1)
        .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: isKnobPressed)
        .animation(Desvan.Motion.fade, value: isKnobHovered)
        .contentShape(Circle())
        .onHover { isKnobHovered = isAdjustable && $0 }
        .pointerStyle(isAdjustable ? .link : nil)
        .help(String(localized: lit ? "Turn Off" : "Turn On"))
    }

    /// Drag round the face; press the knob to switch the light.
    private var turn: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                let fromKnob = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) <= Self.knob / 2
                if fromKnob {
                    // Press-down: the knob sinks; it stays down only while the pointer is still on it.
                    isKnobPressed = HomeDetailLogic.isClick(value.translation)
                    return
                }
                let previous = dragLevel ?? (lit ? level : 0)
                let next = Self.level(at: value.location, around: center, previous: previous)
                if next != previous, next == 0 || next == 1 { haptic() }
                dragLevel = next
                change(next, false)
            }
            .onEnded { value in
                let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                let fromKnob = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) <= Self.knob / 2
                if let dragLevel {
                    change(dragLevel, true)
                } else if fromKnob, HomeDetailLogic.isClick(value.translation) {
                    pressKnob()
                }
                isKnobPressed = false
                dragLevel = nil
            }
    }

    /// The level under the pointer: its angle on the 270° scale. In the gap at the bottom it stays at whichever end
    /// it was nearest to, and it never jumps from one end to the other.
    static func level(at point: CGPoint, around center: CGPoint, previous: Double) -> Double {
        var degrees = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        var relative = degrees - startAngle
        if relative < 0 { relative += 360 }
        var next: Double
        if relative > sweep {
            next = relative < sweep + (360 - sweep) / 2 ? 1 : 0
        } else {
            next = relative / sweep
        }
        if abs(next - previous) > 0.5 { next = previous > 0.5 ? 1 : 0 }
        return (next * 100).rounded() / 100
    }
}

/// An arc of the dial's scale, from `from` degrees clockwise for `sweep` degrees.
struct DesvanDialArc: Shape {
    var from: Double
    var sweep: Double

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sweep > 0.5 else { return path }
        let radius = min(rect.width, rect.height) / 2
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: .degrees(from),
                    endAngle: .degrees(from + sweep), clockwise: false)
        return path
    }
}

/// Ticks every 5 % along the scale, longer every 25 %, printed in ink on the enamel.
private struct DesvanDialTicks: View {
    let start: Double
    let sweep: Double

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for step in 0...20 {
                let angle = Angle.degrees(start + sweep * Double(step) / 20).radians
                let major = step % 5 == 0
                let outer = radius - 1
                let inner = radius - (major ? 7 : 3.5)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                tick.addLine(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                context.stroke(tick, with: .color(Desvan.Palette.ink.opacity(major ? 0.7 : 0.35)),
                               style: StrokeStyle(lineWidth: major ? 1.3 : 0.8, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Wall switch

/// A plug's, a switch's or a plain light's control: a cream bakelite wall plate with two brass screws, a pilot
/// jewel with the thing's glyph (lit when on) and a bat toggle — a brass shaft with a bakelite ball — that throws up
/// for on and down for off with a critically damped spring, passing through pointing at you. Click anywhere on the
/// plate, or drag the lever, to switch.
struct DesvanHomeWallSwitch<Glyph: View>: View {
    let isOn: Bool
    let isAvailable: Bool
    let name: String
    let stateText: String
    @ViewBuilder var glyph: Glyph
    let toggle: () -> Void

    static var size: CGSize { CGSize(width: 112, height: 164) }

    @State private var dragFlip: Double?
    @State private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var flip: Double { dragFlip ?? (isOn ? 1 : -1) }

    var body: some View {
        let plate = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            plate
                .fill(LinearGradient(colors: [Color(hex: 0xF5EEDF), Color(hex: 0xE6DAC2), Color(hex: 0xD3C3A4)],
                                     startPoint: .top, endPoint: .bottom))
                .grain(0.07, in: plate)
                .overlay {
                    plate.strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.1), .black.opacity(0.28)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.2
                    )
                }
                .overlay {
                    // The plate's lit lip, a few points in.
                    plate.inset(by: 5).strokeBorder(.black.opacity(0.06), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 7, y: 4)
                .shadow(color: Desvan.Palette.bulb.opacity(isOn ? 0.18 : 0), radius: 18)
            VStack(spacing: 0) {
                DesvanScrewHead(angle: 28).padding(.top, 9)
                DesvanBakeliteDisc(size: 30, glow: isOn ? 1 : 0, tint: Desvan.Palette.bulb) { glyph }
                    .shadow(color: Desvan.Palette.bulb.opacity(isOn ? 0.55 : 0), radius: 8)
                    .padding(.top, 7)
                Spacer(minLength: 0)
                toggleWell
                Spacer(minLength: 0)
                DesvanScrewHead(angle: -52).padding(.bottom, 9)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(isPressed && !reduceMotion ? 0.985 : 1)
        .animation(Desvan.Motion.pick(Desvan.Motion.press, reduceMotion: reduceMotion), value: isPressed)
        .opacity(isAvailable ? 1 : 0.5)
        .contentShape(plate)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isPressed = true
                    if !HomeDetailLogic.isClick(value.translation) {
                        dragFlip = HomeDetailLogic.leverFlip(isOn: isOn, dragHeight: value.translation.height)
                    }
                }
                .onEnded { value in
                    let flips = HomeDetailLogic.switchFlips(isOn: isOn, translation: value.translation)
                    isPressed = false
                    withAnimation(Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1), reduceMotion: reduceMotion)) {
                        dragFlip = nil
                    }
                    if flips { toggle() }
                },
            including: isAvailable ? .all : .none
        )
        .pointerStyle(isAvailable ? .link : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: stateText))
        .accessibilityAddTraits([.isButton, .isToggle])
        .accessibilityAction { toggle() }
    }

    /// The recessed oval the lever stands in, with I and O engraved above and below.
    private var toggleWell: some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0xCDBD9E), Color(hex: 0xEDE4D2)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.3), .white.opacity(0.7)], startPoint: .top,
                                       endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .frame(width: 34, height: 64)
            // I and O engraved beside the well.
            Text(verbatim: "I")
                .offset(x: -28, y: -22)
                .foregroundStyle(Desvan.Palette.ink.opacity(isOn ? 0.8 : 0.3))
            Text(verbatim: "O")
                .offset(x: -28, y: 22)
                .foregroundStyle(Desvan.Palette.ink.opacity(isOn ? 0.3 : 0.8))
            Group {
                if reduceMotion {
                    DesvanToggleLever(flip: isOn ? 1 : -1)
                        .id(isOn)
                        .transition(.opacity)
                } else {
                    DesvanToggleLever(flip: flip)
                }
            }
            .animation(dragFlip == nil ? Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1),
                                                            reduceMotion: reduceMotion) : nil, value: isOn)
        }
        .font(.system(size: 9, weight: .heavy, design: .rounded))
        .frame(width: 60, height: 70)
    }
}

/// The bat toggle seen from the front: a brass nut, a brass shaft whose visible length is the lever's tilt, and a
/// black bakelite ball at its end that grows a little as it swings towards you. -1 down (off) … 1 up (on).
struct DesvanToggleLever: View, Animatable {
    var flip: Double

    nonisolated var animatableData: Double {
        get { flip }
        set { flip = newValue }
    }

    var body: some View {
        let reach: CGFloat = 26
        let tip = CGFloat(-flip) * reach
        let near = 1 - abs(flip)
        let ball = 15 * (1 + 0.28 * near)
        let shaft = abs(tip)
        ZStack {
            // The lever's shadow on the plate (light from above: it falls below).
            Capsule()
                .fill(.black.opacity(0.28))
                .frame(width: 8, height: shaft + 8)
                .offset(y: tip / 2 + 5 + 3 * near)
                .blur(radius: 2.5)
            Circle()
                .fill(.black.opacity(0.3))
                .frame(width: ball, height: ball)
                .offset(y: tip + 6 + 4 * near)
                .blur(radius: 3)
            // The nut.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFFF0C8), Color(hex: 0xC9A15E), Color(hex: 0x7E5F33)],
                                     center: UnitPoint(x: 0.38, y: 0.3), startRadius: 0, endRadius: 12))
                .overlay { Circle().strokeBorder(Color(hex: 0x5E4522).opacity(0.8), lineWidth: 0.6) }
                .frame(width: 18, height: 18)
            // The shaft.
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0x8E6E3C), Color(hex: 0xF6E2B0), Color(hex: 0xB8914F),
                                              Color(hex: 0x7A5C30)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 6, height: shaft + 6)
                .offset(y: tip / 2)
            // The ball.
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x4A423C), Color(hex: 0x16120F), Color(hex: 0x050404)],
                                     center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: ball * 0.7))
                .overlay {
                    Circle()
                        .fill(RadialGradient(colors: [.white.opacity(0.55), .clear], center: UnitPoint(x: 0.34, y: 0.28),
                                             startRadius: 0, endRadius: ball * 0.22))
                }
                .frame(width: ball, height: ball)
                .offset(y: tip)
        }
        .frame(width: 60, height: 66)
        .accessibilityHidden(true)
    }
}

/// A slotted brass screw head.
private struct DesvanScrewHead: View {
    var angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xF4E3B8), Color(hex: 0xB8945A), Color(hex: 0x7A5C30)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
                .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5) }
            Capsule()
                .fill(Color(hex: 0x4A3518).opacity(0.85))
                .frame(width: 6.5, height: 1.3)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 8, height: 8)
        .shadow(color: .white.opacity(0.6), radius: 0, y: 0.5)
        .accessibilityHidden(true)
    }
}

// MARK: - Warmth

/// The white's warmth: a track from candle to daylight with a brass thumb, dragged 1:1 (or clicked) and sent when let go.
struct DesvanHomeWarmth: View {
    /// The colour the light shows now: the thumb starts where that white sits on the track.
    let color: HomeRGB
    let set: (Double) -> Void

    static let range = 2200.0...6500.0
    @State private var dragged: Double?
    @State private var width: CGFloat = 200

    /// 0…1 along the track, estimated from how blue the white is.
    private var position: Double {
        if let dragged { return dragged }
        let ratio = color.blue / max(color.red, 0.01)
        return min(max((ratio - 0.3) / 0.7, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Warmth")
                .font(Desvan.Typeface.rounded(11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xFF9A3C), Color(hex: 0xFFC77E), Color(hex: 0xFFE9C9),
                                                  Color(hex: 0xF5F1EA), Color(hex: 0xD3E2FF)],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay { Capsule().strokeBorder(.black.opacity(0.35), lineWidth: 0.75) }
                    .frame(height: 8)
                DesvanBrassThumb(size: 16, isPressed: dragged != nil)
                    .offset(x: (width - 16) * position)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = max($0, 1) }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in dragged = min(max((value.location.x - 8) / max(width - 16, 1), 0), 1) }
                    .onEnded { _ in
                        if let dragged {
                            let range = Self.range
                            set(range.lowerBound + (range.upperBound - range.lowerBound) * dragged)
                        }
                        dragged = nil
                    }
            )
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Warmth")
        .accessibilityValue(HomeText.percent(position))
        .accessibilityAdjustableAction { direction in
            let next = min(max(position + (direction == .increment ? 0.1 : -0.1), 0), 1)
            set(Self.range.lowerBound + (Self.range.upperBound - Self.range.lowerBound) * next)
        }
    }
}

// MARK: - Colours

/// Eight colours for a colour bulb, as enamel buttons; the one the bulb shows has a brass ring.
struct DesvanHomeSwatches: View {
    let current: HomeRGB?
    let set: (HomeRGB) -> Void

    @State private var picked: HomeRGB?

    static let colors: [(HomeRGB, LocalizedStringResource)] = [
        (HomeRGB(red: 1, green: 0.32, blue: 0.22), "Red"),
        (HomeRGB(red: 1, green: 0.58, blue: 0.18), "Orange"),
        (HomeRGB(red: 1, green: 0.84, blue: 0.32), "Yellow"),
        (HomeRGB(red: 0.47, green: 0.88, blue: 0.4), "Green"),
        (HomeRGB(red: 0.3, green: 0.84, blue: 0.9), "Cyan"),
        (HomeRGB(red: 0.32, green: 0.5, blue: 1), "Blue"),
        (HomeRGB(red: 0.62, green: 0.38, blue: 1), "Violet"),
        (HomeRGB(red: 1, green: 0.42, blue: 0.7), "Pink"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Colour")
                .font(Desvan.Typeface.rounded(11, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            HStack(spacing: 0) {
                ForEach(Self.colors.indices, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 4) }
                    let (rgb, name) = Self.colors[index]
                    let selected = isSelected(rgb)
                    Button {
                        picked = rgb
                        set(rgb)
                    } label: {
                        Circle()
                            .fill(RadialGradient(colors: [rgb.color.mix(with: .white, by: 0.35), rgb.color],
                                                 center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                            .overlay { Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.75) }
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay {
                                Circle()
                                    .strokeBorder(LinearGradient(colors: [Color(hex: 0xF3DDA6), Color(hex: 0x9C7A43)],
                                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
                                    .opacity(selected ? 1 : 0)
                            }
                            .shadow(color: rgb.color.opacity(selected ? 0.6 : 0), radius: 5)
                            .contentShape(Circle())
                    }
                    .buttonStyle(DesvanPressStyle())
                    .help(String(localized: name))
                    .accessibilityLabel(Text(name))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .onChange(of: current) { picked = nil }
    }

    private func isSelected(_ rgb: HomeRGB) -> Bool {
        guard let shown = picked ?? current else { return false }
        return abs(shown.red - rgb.red) + abs(shown.green - rgb.green) + abs(shown.blue - rgb.blue) < 0.2
    }
}

// MARK: - Blind window

/// A blind's big window set in the wall: drag the blind's bottom edge (its brass pull) 1:1, or click anywhere on the
/// glass to send it to that height; it's sent when let go. While Home Assistant reports it travelling, the blind
/// shows where it really is and a dashed brass line where it's going. A blind without positions opens or closes on
/// a click.
struct DesvanHomeBlindWindow: View {
    let position: Double
    let target: Double?
    let isMoving: Bool
    let style: DesvanBlindStyle
    let canPosition: Bool
    let isAvailable: Bool
    let change: (Double, Bool) -> Void
    let toggle: () -> Void
    let stop: () -> Void
    let haptic: () -> Void

    static let size = CGSize(width: 178, height: 172)

    @State private var dragged: Double?
    @State private var grab: CGFloat?
    @State private var hoverY: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Double { dragged ?? position }
    private var metrics: DesvanBlindMetrics { DesvanBlindMetrics(size: Self.size, detail: true) }

    var body: some View {
        let m = metrics
        let edge = HomeDetailLogic.edgeY(position: shown, top: m.travelTop, travel: m.travel)
        let nearHandle = hoverY.map { abs($0 - edge) <= 16 } ?? false
        let showsTag = dragged != nil || isMoving || hoverY != nil
        ZStack(alignment: .topLeading) {
            DesvanBlindArt(position: shown, style: style, detail: true, isActive: isAvailable)
                .frame(width: Self.size.width, height: Self.size.height)
                .animation(dragged == nil ? Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1),
                                                               reduceMotion: reduceMotion) : nil, value: shown)
            if let target, isMoving {
                targetMarker(y: HomeDetailLogic.edgeY(position: target, top: m.travelTop, travel: m.travel), m: m)
            }
            if canPosition {
                percentTag(edge: edge, m: m)
                    .opacity(showsTag ? 1 : 0)
                    .animation(Desvan.Motion.fade, value: showsTag)
                    .animation(dragged == nil ? Desvan.Motion.pick(.spring(response: 0.3, dampingFraction: 1),
                                                                   reduceMotion: reduceMotion) : nil, value: shown)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .compositingGroup()
        .shadow(color: .black.opacity(0.55), radius: 8, y: 5)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case let .active(point): hoverY = point.y
            case .ended: hoverY = nil
            }
        }
        .pointerStyle(!isAvailable ? nil : dragged != nil ? .grabActive : canPosition && nearHandle ? .grabIdle : .link)
        .gesture(pull, including: isAvailable ? .all : .none)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(HomeText.percent(shown))
        .accessibilityAdjustableAction { direction in
            guard canPosition else { return toggle() }
            change(min(max(position + (direction == .increment ? 0.1 : -0.1), 0), 1), true)
        }
        .accessibilityAction(named: Text("Stop")) { stop() }
    }

    private var pull: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard canPosition else { return }
                let m = metrics
                if grab == nil {
                    let edge = HomeDetailLogic.edgeY(position: position, top: m.travelTop, travel: m.travel)
                    // Grabbed by the edge: keep the offset. Pressed elsewhere: the edge comes to the pointer once it moves.
                    grab = HomeDetailLogic.grabOffset(startY: value.startLocation.y, edgeY: edge) ?? 0
                    if HomeDetailLogic.grabOffset(startY: value.startLocation.y, edgeY: edge) != nil { dragged = position }
                }
                guard dragged != nil || !HomeDetailLogic.isClick(value.translation) else { return }
                let next = HomeDetailLogic.position(atY: value.location.y - (grab ?? 0), top: m.travelTop, travel: m.travel)
                if next != shown, next == 0 || next == 1 { haptic() }
                dragged = next
                change(next, false)
            }
            .onEnded { value in
                defer {
                    grab = nil
                    dragged = nil
                }
                guard canPosition else {
                    if HomeDetailLogic.isClick(value.translation) {
                        haptic()
                        toggle()
                    }
                    return
                }
                // A click on the pull itself changes nothing.
                if dragged == position, HomeDetailLogic.isClick(value.translation) { return }
                let m = metrics
                let final = dragged ?? HomeDetailLogic.position(atY: value.location.y, top: m.travelTop, travel: m.travel)
                haptic()
                change(final, true)
            }
    }

    /// A kraft tag with the percentage, hanging under the pull (or above it when the blind is nearly closed).
    private func percentTag(edge: CGFloat, m: DesvanBlindMetrics) -> some View {
        let below = edge + 30 < m.glass.maxY
        return Text(verbatim: HomeText.percent(shown))
            .font(Desvan.Typeface.rounded(10.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Desvan.Palette.ink)
            .padding(.horizontal, 6)
            .frame(height: 17)
            .background {
                Capsule()
                    .fill(LinearGradient(colors: [Color(hex: 0xEAD6B3), Color(hex: 0xC9A77C)], startPoint: .top,
                                         endPoint: .bottom))
                    .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
            }
            .fixedSize()
            .position(x: m.glass.midX + 30, y: below ? edge + 15 : edge - m.rail - 12)
            .allowsHitTesting(false)
    }

    /// Where a travelling blind is going: a dashed brass line across the glass, with notches on the frame.
    private func targetMarker(y: CGFloat, m: DesvanBlindMetrics) -> some View {
        let brass = LinearGradient(colors: [Color(hex: 0xF7DFA4), Color(hex: 0xC9974A)], startPoint: .top, endPoint: .bottom)
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: m.glass.minX + 2, y: y))
                path.addLine(to: CGPoint(x: m.glass.maxX - 2, y: y))
            }
            .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [6, 4]))
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: m.glass.minX + 2, y: y))
                    path.addLine(to: CGPoint(x: m.glass.maxX - 2, y: y))
                }
                .stroke(brass, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
            }
            .shadow(color: Color(hex: 0xFFB547).opacity(0.7), radius: 3)
            ForEach([true, false], id: \.self) { leading in
                Path { path in
                    let x = leading ? m.frame.minX + 1 : m.frame.maxX - 1
                    let dir: CGFloat = leading ? 1 : -1
                    path.move(to: CGPoint(x: x, y: y - 5))
                    path.addLine(to: CGPoint(x: x + 6 * dir, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + 5))
                    path.closeSubpath()
                }
                .fill(brass)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
