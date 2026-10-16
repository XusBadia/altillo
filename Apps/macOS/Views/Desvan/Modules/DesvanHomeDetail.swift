import AltilloHome
import SwiftUI

/// A tile's controls (docs/casa-v2.md §3), in place of the grid: a light's big brass dimmer dial with its warmth and
/// colours, a blind's window to pull up and down with Stop, a plug's big switch. Back (or Esc) returns to the tiles.
///
/// Everything answers at once: the dial and the swatches show the new value while the command travels, and the
/// tile follows Home Assistant's push.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Group {
                switch entity.kind {
                case .light: light
                case .cover: blind
                default: power
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    // MARK: Light

    private var tint: Color { store.glowColor(for: entity).color }
    private var isOn: Bool { dragLevel.map { $0 > 0 } ?? (state.isOn == true) }

    private var light: some View {
        HStack(alignment: .center, spacing: 22) {
            DesvanHomeDimmerDial(
                level: entity.capabilities.contains(.brightness) ? level : (isOn ? 1 : 0),
                tint: tint,
                isOn: isOn,
                isAdjustable: entity.capabilities.contains(.brightness) && state.isAvailable,
                change: { value, final in
                    dragLevel = final ? nil : value
                    store.drag(entity, to: value, final: final)
                },
                pressKnob: { store.activate(entity) },
                haptic: { haptic(.snap) }
            )
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(verbatim: HomeText.stateLine(for: entity, state: dragLevel.map { value in
                        var preview = state
                        preview.isOn = value > 0
                        preview.brightness = value > 0 ? value : nil
                        return preview
                    } ?? state))
                        .font(Desvan.Typeface.figure(17))
                        .foregroundStyle(isOn ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    if store.isPending(entity.id) {
                        ProgressView().controlSize(.small).tint(Desvan.Palette.bulb)
                    }
                    Spacer(minLength: 8)
                    Button(isOn ? "Turn Off" : "Turn On") { store.activate(entity) }
                        .buttonStyle(DesvanButtonStyle(kind: isOn ? .ghost : .primary, height: 28))
                        .disabled(!state.isAvailable)
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
            }
            .modifier(DesvanHomeControlsCard())
        }
        .padding(.horizontal, 4)
    }

    // MARK: Blind

    private var blind: some View {
        HStack(alignment: .center, spacing: 22) {
            DesvanHomeBlindControl(
                position: level,
                isAdjustable: entity.capabilities.contains(.position) && state.isAvailable,
                change: { value, final in
                    dragLevel = final ? nil : value
                    store.drag(entity, to: value, final: final)
                },
                haptic: { haptic(.snap) }
            )
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: HomeText.stateLine(for: entity, state: dragLevel.map { position in
                    var preview = state
                    preview.position = position
                    preview.raw = position > 0 ? "open" : "closed"
                    return preview
                } ?? state))
                    .font(Desvan.Typeface.figure(24))
                    .foregroundStyle(Desvan.Palette.paper)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Button("Open", systemImage: "arrow.up") { store.drag(entity, to: 1, final: true) }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                    Button("Stop", systemImage: "stop.fill") { store.stopCover(entity) }
                        .buttonStyle(DesvanButtonStyle(kind: .primary, height: 28))
                    Button("Close", systemImage: "arrow.down") { store.drag(entity, to: 0, final: true) }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 28))
                }
                .disabled(!state.isAvailable)
            }
            .modifier(DesvanHomeControlsCard())
        }
        .padding(.horizontal, 4)
    }

    // MARK: Plug, switch, fan

    private var power: some View {
        let on = state.isOn == true
        return HStack(spacing: 22) {
            Button { store.activate(entity) } label: {
                DesvanBakeliteDisc(size: 110, glow: on ? 0.9 : 0, tint: Desvan.Palette.bulb) {
                    DesvanHomeGlyph(entity: entity, state: state, symbol: tile.symbol, size: 50,
                                    tint: Desvan.Palette.bulb, glow: on ? 1 : 0, level: nil)
                }
            }
            .buttonStyle(DesvanPressStyle())
            .accessibilityLabel(tile.name)
            .accessibilityValue(HomeText.stateLine(for: entity, state: state))
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: HomeText.stateLine(for: entity, state: state))
                    .font(Desvan.Typeface.figure(24))
                    .foregroundStyle(on ? Desvan.Palette.bulb : Desvan.Palette.paper)
                Button(on ? "Turn Off" : "Turn On") { store.activate(entity) }
                    .buttonStyle(DesvanButtonStyle(kind: on ? .ghost : .primary, height: 28))
                    .disabled(!state.isAvailable)
            }
            .modifier(DesvanHomeControlsCard())
        }
        .padding(.horizontal, 4)
    }

    private func step(_ delta: Double) -> KeyPress.Result {
        guard DesvanHomeTile.hasLevel(entity) else { return .ignored }
        let next = min(max(DesvanHomeTile.level(of: entity, state: state) + delta, 0), 1)
        store.drag(entity, to: next, final: true)
        return .handled
    }
}

/// The controls beside the dial: a wood card, so they sit on something instead of floating in the notch.
private struct DesvanHomeControlsCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .desvanCard(radius: 14, fill: Desvan.Palette.wood, grain: 0.6)
    }
}

// MARK: - Dimmer dial

/// A light's dimmer as a rotary dial, kin of the kitchen timer's: a dark wood rim, a cream enamel face with ticks
/// from 0 to 100 % over three quarters of a turn, the light's own colour filling the arc as far as it's bright, and
/// a bakelite knob with a brass pointer. Turn it by dragging round the face (1:1, no jumps across the gap); click the
/// knob to switch the light.
struct DesvanHomeDimmerDial: View {
    let level: Double
    let tint: Color
    let isOn: Bool
    let isAdjustable: Bool
    let change: (Double, Bool) -> Void
    let pressKnob: () -> Void
    let haptic: () -> Void

    static let size: CGFloat = 160
    private static let rim: CGFloat = 7
    private static let knob: CGFloat = 78
    /// Where 0 % is, in SwiftUI degrees (0 = 3 o'clock, clockwise): 7:30.
    static let startAngle = 135.0
    static let sweep = 270.0

    @State private var dragLevel: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: Double { dragLevel ?? level }

    var body: some View {
        ZStack {
            face
            DesvanDialArc(from: Self.startAngle, sweep: Self.sweep * (isOn ? shown : 0))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center,
                                    startAngle: .degrees(Self.startAngle), endAngle: .degrees(Self.startAngle + Self.sweep)),
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .shadow(color: tint.opacity(0.7), radius: 5)
                .padding(Self.rim + 16)
                .animation(dragLevel == nil ? Desvan.Motion.pick(.spring(response: 0.35, dampingFraction: 1),
                                                                 reduceMotion: reduceMotion) : nil, value: shown)
            DesvanDialTicks(start: Self.startAngle, sweep: Self.sweep)
                .padding(Self.rim + 2)
            knob
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(turn, including: isAdjustable ? .all : .subviews)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Brightness")
        .accessibilityValue(isOn ? HomeText.percent(shown) : String(localized: "home.state.off", defaultValue: "Off"))
        .accessibilityAdjustableAction { direction in
            change(min(max(shown + (direction == .increment ? 0.1 : -0.1), 0), 1), true)
        }
        .accessibilityAction(named: Text(isOn ? "Turn Off" : "Turn On")) { pressKnob() }
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
                .fill(RadialGradient(colors: [tint.opacity(isOn ? 0.35 * (0.35 + 0.65 * shown) : 0), .clear],
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
        let angle = Angle.degrees(Self.startAngle + Self.sweep * (isOn ? shown : 0))
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0x2E2824), Color(hex: 0x0B0908)],
                                     center: UnitPoint(x: 0.4, y: 0.28), startRadius: 0, endRadius: Self.knob * 0.7))
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [Desvan.Palette.paper.opacity(0.32), .black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.55), radius: 4, y: 3)
            // The brass pointer turning with the level.
            Capsule()
                .fill(LinearGradient(colors: [Color(hex: 0xF3DDA6), Color(hex: 0x9C7A43)], startPoint: .top, endPoint: .bottom))
                .frame(width: 11, height: 3.5)
                .offset(x: Self.knob / 2 - 10)
                .rotationEffect(angle)
                .shadow(color: .black.opacity(0.5), radius: 1)
                .animation(dragLevel == nil ? Desvan.Motion.pick(.spring(response: 0.35, dampingFraction: 1),
                                                                 reduceMotion: reduceMotion) : nil, value: shown)
            VStack(spacing: 0) {
                DesvanBulbGlyph(size: 18, lit: isOn ? 0.35 + 0.65 * shown : 0, tint: tint)
                Text(verbatim: isOn ? HomeText.percent(shown) : String(localized: "home.state.off", defaultValue: "Off"))
                    .font(Desvan.Typeface.figure(15))
                    .foregroundStyle(Desvan.Palette.paper)
                    .contentTransition(.numericText())
                    .lineLimit(1)
            }
        }
        .frame(width: Self.knob, height: Self.knob)
    }

    /// Drag round the face; a click on the knob switches the light.
    private var turn: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                guard hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) > Self.knob / 2 else { return }
                let previous = dragLevel ?? (isOn ? level : 0)
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
                } else if fromKnob, hypot(value.translation.width, value.translation.height) < 4 {
                    pressKnob()
                }
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
            .frame(height: 28)
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

// MARK: - Blind

/// A blind's big window: drag it up or down 1:1 (or its brass track beside it) to set the position.
struct DesvanHomeBlindControl: View {
    let position: Double
    let isAdjustable: Bool
    let change: (Double, Bool) -> Void
    let haptic: () -> Void

    static let height: CGFloat = 150
    @State private var start: Double?
    @State private var dragged: Double?

    private var shown: Double { dragged ?? position }

    var body: some View {
        HStack(spacing: 12) {
            DesvanBlindGlyph(position: shown, size: Self.height / 1.05)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
            // The cord's track: top is open.
            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.black.opacity(0.5))
                    .overlay { Capsule().strokeBorder(Desvan.Palette.paper.opacity(0.12), lineWidth: 0.75) }
                    .frame(width: 6)
                DesvanBrassThumb(size: 18, isPressed: dragged != nil)
                    .offset(y: (Self.height - 18) * (1 - shown))
            }
            .frame(width: 18, height: Self.height)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let from = start ?? position
                    start = from
                    let next = min(max(from - value.translation.height / Self.height, 0), 1)
                    if next != dragged, next == 0 || next == 1 { haptic() }
                    dragged = next
                    change(next, false)
                }
                .onEnded { _ in
                    if let dragged { change(dragged, true) }
                    start = nil
                    dragged = nil
                },
            including: isAdjustable ? .all : .none
        )
        .animation(dragged == nil ? .spring(response: 0.35, dampingFraction: 1) : nil, value: shown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(HomeText.percent(shown))
        .accessibilityAdjustableAction { direction in
            change(min(max(position + (direction == .increment ? 0.1 : -0.1), 0), 1), true)
        }
    }
}
