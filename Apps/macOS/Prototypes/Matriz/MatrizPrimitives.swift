import AltilloDesign
import AppKit
import SwiftUI

// The building blocks of Matriz: a tiled dot grid, 7×7 dot glyphs, LEDs with bloom, segmented dials and bars,
// viewfinder corners, marching-dot borders and the scanline reveal. Everything is a tile or a `Canvas`: never one view
// per dot.

// MARK: - Dot grid

/// The switched-off matrix: dots on a 6-pt pitch, drawn once as a tile per display scale.
/// On 1× displays the dot snaps to whole pixels so the grid never shimmers into moiré.
struct DotGrid: View {
    var color: Color = Matriz.Palette.dotOff
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        DotGridTile.image(scale: displayScale)
            .renderingMode(.template)
            .resizable(resizingMode: .tile)
            .foregroundStyle(color)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

@MainActor
enum DotGridTile {
    static let pitch: CGFloat = 6
    private static var cache: [Int: Image] = [:]

    static func image(scale: CGFloat) -> Image {
        let key = Int((scale * 100).rounded())
        if let image = cache[key] { return image }
        let pixels = Int((pitch * scale).rounded())
        // 1.5 pt dots; on 1× a crisp 2-px square reads better than a blurred 1.5-px disc.
        let dot = max(2, (1.5 * scale).rounded())
        let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(gray: 1, alpha: 1))
        let origin = ((CGFloat(pixels) - dot) / 2).rounded(.down)
        let rect = CGRect(x: origin, y: origin, width: dot, height: dot)
        if scale >= 2 { context?.fillEllipse(in: rect) } else { context?.fill(rect) }
        let image = context?.makeImage().map { Image(decorative: $0, scale: scale) } ?? Image(systemName: "circle.fill")
        cache[key] = image
        return image
    }
}

// MARK: - Dot glyphs

/// A glyph drawn from a bitmap string: `#` lit, `o` accent, `.` off (drawn only when `offColor` is set).
struct DotGlyph: View {
    let rows: [String]
    var pitch: CGFloat = 2
    var dot: CGFloat = 1.6
    var color: Color = Matriz.Palette.phosphor
    var accent: Color = Matriz.Palette.signal
    var offColor: Color?

    init(_ rows: [String], pitch: CGFloat = 2, dot: CGFloat = 1.6, color: Color = Matriz.Palette.phosphor,
         accent: Color = Matriz.Palette.signal, offColor: Color? = nil) {
        self.rows = rows
        self.pitch = pitch
        self.dot = dot
        self.color = color
        self.accent = accent
        self.offColor = offColor
    }

    private var columns: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        Canvas { context, _ in
            let inset = (pitch - dot) / 2
            for (y, row) in rows.enumerated() {
                for (x, char) in row.enumerated() {
                    let fill: Color? = switch char {
                    case "#": color
                    case "o": accent
                    default: offColor
                    }
                    guard let fill else { continue }
                    let rect = CGRect(x: CGFloat(x) * pitch + inset, y: CGFloat(y) * pitch + inset, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(fill))
                }
            }
        }
        .frame(width: CGFloat(columns) * pitch, height: CGFloat(rows.count) * pitch)
        .accessibilityHidden(true)
    }
}

/// The 7×7 glyph set of the tabs and ears, plus the brand.
enum Glyph7 {
    static let box = [
        ".#####.",
        "#.....#",
        "#######",
        "#.....#",
        "#.###.#",
        "#.....#",
        "#######",
    ]
    static let dial = [
        "..###..",
        ".#...#.",
        "#....##",
        "#..##.#",
        "#.....#",
        ".#...#.",
        "..###..",
    ]
    static let agent = [
        ".......",
        "#......",
        ".#.....",
        "..#....",
        ".#.....",
        "#..###.",
        ".......",
    ]
    /// The brand: a roof of dots with a red LED inside, "what you left upstairs".
    static let roof = [
        "...#...",
        "..#.#..",
        ".#.o.#.",
        "#.....#",
    ]
    static let arrowRight = [
        "..#..",
        "...#.",
        "#####",
        "...#.",
        "..#..",
    ]
    static let arrowDown = [
        "..#..",
        "..#..",
        "#.#.#",
        ".###.",
        "..#..",
    ]
    static let chevronDown = [
        "#...#",
        ".#.#.",
        "..#..",
    ]
}

// MARK: - LEDs

extension View {
    /// LED bloom: a blurred copy added on top with `plusLighter`. The only "light" of the system.
    /// Only for leaf views (it duplicates the content). Skipped with Reduce Transparency.
    func ledGlow(_ radius: CGFloat = 3, opacity: Double = 0.5, isOn: Bool = true) -> some View {
        modifier(LEDGlow(radius: radius, opacity: opacity, isOn: isOn))
    }
}

private struct LEDGlow: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    let isOn: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.overlay {
            if isOn, !reduceTransparency {
                content
                    .blur(radius: radius)
                    .opacity(opacity)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A single round LED.
struct LED: View {
    var color: Color = Matriz.Palette.phosphor
    var size: CGFloat = 4
    var glows = true

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .ledGlow(size * 0.9, opacity: 0.7, isOn: glows)
            .accessibilityHidden(true)
    }
}

/// The recording light: a single LED that breathes (0.35 ↔ 1, 1.6 s cycle). Steady with Reduce Motion.
struct BreathingLED: View {
    var color: Color = Matriz.Palette.signal
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            // easeInOut breathing: cosine between 0.35 and 1.
            let level = reduceMotion ? 1 : 0.675 - 0.325 * cos(phase * 2 * .pi)
            LED(color: color, size: size)
                .opacity(level)
        }
    }
}

/// Working: three LEDs chasing each other around a 3×3 square, one step every 120 ms.
struct LEDSpinner: View {
    var color: Color = Matriz.Palette.phosphor
    var pitch: CGFloat = 3
    var dot: CGFloat = 2.2
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let ring: [(Int, Int)] = [(0, 0), (1, 0), (2, 0), (2, 1), (2, 2), (1, 2), (0, 2), (0, 1)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { timeline in
            let step = reduceMotion ? 0 : Int(timeline.date.timeIntervalSinceReferenceDate / 0.12)
            Canvas { context, _ in
                let inset = (pitch - dot) / 2
                for (index, cell) in Self.ring.enumerated() {
                    let age = (step - index) % Self.ring.count
                    let normalized = (age + Self.ring.count) % Self.ring.count
                    let level: Double = switch normalized {
                    case 0: 1
                    case 1: 0.55
                    case 2: 0.25
                    default: 0
                    }
                    let rect = CGRect(x: CGFloat(cell.0) * pitch + inset, y: CGFloat(cell.1) * pitch + inset, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(Matriz.Palette.dotOff))
                    if level > 0 { context.fill(Path(ellipseIn: rect), with: .color(color.opacity(level))) }
                }
            }
            .frame(width: pitch * 3, height: pitch * 3)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Power-on

/// Brightness of each dot during the power-on sequence (a value type, so canvases can capture it).
struct PowerLevels {
    var elapsed: Double
    var done: Bool

    func callAsFunction(_ index: Int) -> Double {
        if done { return 1 }
        let t = (elapsed - Double(index) * Matriz.Motion.dotStagger) / Matriz.Motion.dotRise
        let clamped = min(max(t, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }
}

/// Drives the staggered power-on of a segmented indicator: 6 ms per dot, each rising in 90 ms (ease-out).
/// Instant with Reduce Motion. The timeline pauses once every dot is lit, so it costs nothing at rest.
struct PowerOn<Content: View>: View {
    let dots: Int
    @ViewBuilder let content: (PowerLevels) -> Content

    @State private var start = Date.now
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var duration: Double { Double(dots) * Matriz.Motion.dotStagger + Matriz.Motion.dotRise }

    var body: some View {
        TimelineView(.animation(paused: finished || reduceMotion)) { timeline in
            content(PowerLevels(elapsed: timeline.date.timeIntervalSince(start), done: finished || reduceMotion))
        }
        .task {
            start = .now
            try? await Task.sleep(for: .seconds(duration + 0.05))
            finished = true
        }
    }
}

// MARK: - Dial

/// Session usage as a dial of 48 LEDs. Lit in order up to the value; the last lit LED glows brighter.
/// Past 80 % the LEDs light in amber, past 95 % in critical, and only the last one blinks (1 Hz).
/// The pace marker is a hollow LED. With Increase Contrast it becomes a continuous ring.
struct DotRing: View {
    var value: Double
    var pace: Double?
    var segments = 48
    var dot: CGFloat = 3.2

    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lit: Int { Int((min(max(value, 0), 1) * Double(segments)).rounded()) }
    private var isCritical: Bool { value >= 0.95 }

    var body: some View {
        PowerOn(dots: lit) { level in
            // Only a critical dial needs a clock (its last LED blinks at 1 Hz); otherwise it's static at rest.
            TimelineView(.animation(minimumInterval: 0.5, paused: !isCritical || reduceMotion)) { timeline in
                let blinkOff = isCritical && !reduceMotion && Int(timeline.date.timeIntervalSinceReferenceDate * 2) % 2 == 1
                Canvas { context, size in
                    draw(in: &context, size: size, level: level, blinkOff: blinkOff)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(min(max(value, 0), 1), format: .percent.precision(.fractionLength(0))))
    }

    private func color(at index: Int) -> Color {
        let fraction = (Double(index) + 0.5) / Double(segments)
        if fraction >= 0.95, value >= 0.95 { return Matriz.Palette.critical }
        if fraction >= 0.8, value >= 0.8 { return Matriz.Palette.amber }
        return Matriz.Palette.phosphor
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, level: PowerLevels, blinkOff: Bool) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = min(size.width, size.height) / 2 - dot / 2 - 1

        if contrast == .increased {
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
            context.stroke(track, with: .color(Matriz.Palette.dotDim), lineWidth: dot)
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                       endAngle: .degrees(-90 + 360 * min(max(value, 0), 1)), clockwise: false)
            context.stroke(arc, with: .color(color(at: max(lit - 1, 0))), style: StrokeStyle(lineWidth: dot, lineCap: .round))
            return
        }

        func rect(_ index: Int, scale: CGFloat = 1) -> CGRect {
            let angle = (Double(index) / Double(segments)) * 2 * .pi - .pi / 2
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let side = dot * scale
            return CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
        }

        let paceIndex = pace.map { min(Int(($0 * Double(segments)).rounded()), segments - 1) }

        // Bloom layer.
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 2.5))
            layer.blendMode = .plusLighter
            for index in 0..<lit {
                let isLast = index == lit - 1
                if isLast, blinkOff { continue }
                layer.opacity = 1
                layer.fill(Path(ellipseIn: rect(index, scale: isLast ? 2.2 : 1.3)),
                           with: .color(color(at: index).opacity((isLast ? 0.8 : 0.35) * level(index))))
            }
        }

        for index in 0..<segments {
            let base = Path(ellipseIn: rect(index))
            if index == paceIndex {
                let ring = Path(ellipseIn: rect(index, scale: 1.25).insetBy(dx: 0.5, dy: 0.5))
                context.fill(Path(ellipseIn: rect(index)), with: .color(.black))
                context.stroke(ring, with: .color(Matriz.Palette.phosphor.opacity(0.9)), lineWidth: 1)
                continue
            }
            context.fill(base, with: .color(Matriz.Palette.dotOff))
            if index < lit {
                let isLast = index == lit - 1
                if isLast, blinkOff { continue }
                context.fill(base, with: .color(color(at: index).opacity(level(index) * (isLast ? 1 : 0.92))))
            }
        }
    }
}

// MARK: - Segment bar

/// Weekly usage as 40 cells of 5×8 pt with 2-pt gaps. The pace marker is a hollow cell.
struct SegmentBar: View {
    var value: Double
    var pace: Double?
    var cells = 40
    var cell = CGSize(width: 5, height: 8)
    var gap: CGFloat = 2

    @Environment(\.colorSchemeContrast) private var contrast

    static func width(cells: Int = 40, cell: CGFloat = 5, gap: CGFloat = 2) -> CGFloat {
        CGFloat(cells) * cell + CGFloat(cells - 1) * gap
    }

    private var lit: Int { Int((min(max(value, 0), 1) * Double(cells)).rounded()) }

    var body: some View {
        PowerOn(dots: lit) { level in
            Canvas { context, _ in
                let paceIndex = pace.map { min(Int(($0 * Double(cells)).rounded(.down)), cells - 1) }
                if contrast == .increased {
                    let full = CGRect(x: 0, y: 0, width: Self.width(cells: cells, cell: cell.width, gap: gap), height: cell.height)
                    context.fill(Path(full), with: .color(Matriz.Palette.dotDim))
                    context.fill(Path(CGRect(x: 0, y: 0, width: full.width * min(max(value, 0), 1), height: cell.height)),
                                 with: .color(color(at: max(lit - 1, 0))))
                    return
                }
                for index in 0..<cells {
                    let rect = CGRect(x: CGFloat(index) * (cell.width + gap), y: 0, width: cell.width, height: cell.height)
                    if index == paceIndex, index >= lit {
                        context.stroke(Path(rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(Matriz.Palette.phosphor), lineWidth: 1)
                        continue
                    }
                    context.fill(Path(rect), with: .color(Matriz.Palette.dotOff))
                    if index < lit {
                        context.fill(Path(rect), with: .color(color(at: index).opacity(level(index) * 0.92)))
                    }
                    if index == paceIndex, index < lit {
                        // Pace inside the lit run: a notch of darkness keeps it readable.
                        context.fill(Path(rect.insetBy(dx: 1, dy: 1)), with: .color(.black))
                    }
                }
            }
            .frame(width: Self.width(cells: cells, cell: cell.width, gap: gap), height: cell.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(Text(min(max(value, 0), 1), format: .percent.precision(.fractionLength(0))))
    }

    private func color(at index: Int) -> Color {
        let fraction = (Double(index) + 0.5) / Double(cells)
        if fraction >= 0.95, value >= 0.95 { return Matriz.Palette.critical }
        if fraction >= 0.8, value >= 0.8 { return Matriz.Palette.amber }
        return Matriz.Palette.phosphor
    }
}

// MARK: - Rules and corners

/// A dotted hairline: the separator of the system.
struct DotRule: View {
    enum Axis { case horizontal, vertical }
    var axis: Axis = .horizontal
    var color: Color = Matriz.Palette.dotDim

    var body: some View {
        Canvas { context, size in
            var path = Path()
            if axis == .horizontal {
                path.move(to: CGPoint(x: 1, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            } else {
                path.move(to: CGPoint(x: size.width / 2, y: 1))
                path.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            }
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [0, 4]))
        }
        .frame(width: axis == .vertical ? 2 : nil, height: axis == .horizontal ? 2 : nil)
        .accessibilityHidden(true)
    }
}

/// Selection as a viewfinder: four 6-pt corners instead of a fill.
struct ViewfinderCorners: Shape {
    var arm: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let a = min(arm, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + a))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + a, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - a, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + a))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - a))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - a, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + a, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - a))
        return path
    }
}

/// A border of dots that march one step every 80 ms (static with Reduce Motion).
struct MarchingDots: View {
    var color: Color
    var cornerRadius: CGFloat = 8
    var isMarching = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08, paused: !isMarching || reduceMotion)) { timeline in
            let step = (isMarching && !reduceMotion) ? Int(timeline.date.timeIntervalSinceReferenceDate / 0.08) % 3 : 0
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0, 6], dashPhase: -CGFloat(step) * 2))
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Scanline

/// New content is "written" by a scanline: a mask that sweeps top → bottom (or left → right for signs).
/// It leaves with a plain fade. With Reduce Motion it is a 150 ms fade both ways.
struct ScanlineModifier: ViewModifier {
    let progress: CGFloat
    let horizontal: Bool

    func body(content: Content) -> some View {
        content.mask(alignment: horizontal ? .leading : .top) {
            Rectangle()
                .scaleEffect(x: horizontal ? max(progress, 0.0001) : 1, y: horizontal ? 1 : max(progress, 0.0001),
                             anchor: horizontal ? .leading : .top)
        }
    }
}

extension AnyTransition {
    static func scanline(horizontal: Bool = false, reduceMotion: Bool) -> AnyTransition {
        if reduceMotion { return AnyTransition.opacity.animation(Matriz.Motion.reduced) }
        let insertion = AnyTransition.modifier(
            active: ScanlineModifier(progress: 0, horizontal: horizontal),
            identity: ScanlineModifier(progress: 1, horizontal: horizontal)
        )
        .animation(horizontal ? Matriz.Motion.marquee : Matriz.Motion.scanline)
        return .asymmetric(insertion: insertion, removal: AnyTransition.opacity.animation(.easeOut(duration: 0.08)))
    }
}

/// Reveals its content once, on appear, with the scanline (a letter sign turning on, for peeks).
struct ScanReveal: ViewModifier {
    var horizontal = true
    var delay: Double = 0
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .modifier(ScanlineModifier(progress: reduceMotion ? 1 : progress, horizontal: horizontal))
            .opacity(reduceMotion ? (progress > 0 ? 1 : 0) : 1)
            .onAppear {
                withAnimation((reduceMotion ? Matriz.Motion.reduced : (horizontal ? Matriz.Motion.marquee : Matriz.Motion.scanline)).delay(delay)) {
                    progress = 1
                }
            }
    }
}

// MARK: - Flip counter

/// A number that changes like a departures board: the old figure switches off row by row while the new one lights
/// up behind the sweep. Two layers and a sweeping mask (a numeric content transition isn't enough).
struct FlipCounter: View {
    let value: Int
    var font: Font
    var color: Color = Matriz.Palette.phosphor
    var glows = true

    @State private var shown: Int?
    @State private var previous: Int?
    @State private var progress: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let current = shown ?? value
        ZStack {
            if let previous, progress < 1 {
                digits(previous)
                    .mask(alignment: .bottom) {
                        Rectangle().scaleEffect(y: max(1 - progress, 0.0001), anchor: .bottom)
                    }
            }
            digits(current)
                .mask(alignment: .top) {
                    Rectangle().scaleEffect(y: max(progress, 0.0001), anchor: .top)
                }
        }
        .onChange(of: value) { old, new in
            guard !reduceMotion else {
                shown = new
                return
            }
            previous = old
            shown = new
            progress = 0
            withAnimation(.easeInOut(duration: 0.26)) { progress = 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(value)"))
    }

    private func digits(_ number: Int) -> some View {
        Text("\(number)")
            .font(font)
            .foregroundStyle(color)
            .ledGlow(2, opacity: 0.45, isOn: glows)
    }
}

// MARK: - Buttons

/// Press at 0.97 on press (not release), 100 ms.
struct MatrizPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Matriz.Motion.press, value: configuration.isPressed)
    }
}

/// Capsule instrument button: Departure Mono label. `.primary` is signal with black text.
struct MatrizButton: View {
    enum Kind { case primary, secondary, quiet }
    let title: String
    var shortcut: String?
    var kind: Kind = .secondary
    var action: () -> Void = {}

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).matrizLabel()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10.5, weight: .semibold))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background {
                Capsule().fill(background)
            }
            .overlay {
                if kind == .quiet {
                    Capsule().strokeBorder(Matriz.Palette.dotDim, lineWidth: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(MatrizPressStyle())
        .onHover { isHovering = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary: .black
        case .secondary: Matriz.Palette.phosphor
        case .quiet: isHovering ? Matriz.Palette.phosphor : Matriz.Palette.phosphor2
        }
    }

    private var background: Color {
        switch kind {
        case .primary: isHovering ? Matriz.Palette.signal.mix(with: .white, by: 0.12) : Matriz.Palette.signal
        case .secondary: isHovering ? Matriz.Palette.dotOff : Matriz.Palette.panelRaised
        case .quiet: isHovering ? Matriz.Palette.panelRaised : .clear
        }
    }
}

// MARK: - Pointer probe

/// Reads the pointer position inside a view, also during a drag (AppKit's `mouseLocationOutsideOfEventStream`).
/// Used for the "flashlight on the matrix" under the cursor.
@MainActor
final class PointerProbe {
    fileprivate weak var view: NSView?

    /// Pointer in the view's coordinates (top-left origin), or nil when unknown.
    func location() -> CGPoint? {
        guard let view, let window = view.window else { return nil }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return CGPoint(x: point.x, y: view.isFlipped ? point.y : view.bounds.height - point.y)
    }
}

struct PointerProbeView: NSViewRepresentable {
    let probe: PointerProbe

    func makeNSView(context: Context) -> NSView {
        let view = PassthroughView()
        probe.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        probe.view = nsView
    }

    private final class PassthroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
