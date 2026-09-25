import AltilloDesign
import SwiftUI

/// The kitchen timer's face: cream enamel in a dark wood rim, sixty minute marks, and the bulb's amber wedge for
/// the time set (or what's left). Turn it by dragging round the face, like an egg timer: it snaps to minutes and
/// taps the trackpad every five. The knob in the middle starts, pauses and resumes.
///
/// Keyboard and VoiceOver: it takes focus; arrows (or VoiceOver's adjust) move it a minute, typing digits sets the
/// minutes, Return or Space presses the knob.
struct DesvanTimerDial: View {
    /// What the face shows: the time set on the dial, or a timer's remaining time.
    enum Reading: Equatable {
        case draft(minutes: Int)
        case running(remaining: TimeInterval, label: String)
        case paused(remaining: TimeInterval, label: String)
        case rang(label: String)
    }

    let reading: Reading
    /// Bumped when a timer rings with the section open: the dial shakes (a flash with Reduce Motion).
    let ringCount: Int
    /// The user turned the dial: the minutes under the pointer (or the arrow key's step).
    let setMinutes: (Int) -> Void
    /// The knob was pressed (click, Return, Space).
    let pressKnob: () -> Void
    let haptic: () -> Void

    static let size: CGFloat = 148
    private static let rim: CGFloat = 7
    private static let knob: CGFloat = 70

    @State private var dragMinutes: Int?
    @State private var typed = ""
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var draftMinutes: Int? {
        if case let .draft(minutes) = reading { return minutes }
        return nil
    }

    /// Degrees of amber from 12 o'clock.
    private var sweep: Double {
        switch reading {
        case let .draft(minutes): TimerDial.sweep(forSeconds: TimeInterval(minutes * 60))
        case let .running(remaining, _), let .paused(remaining, _): TimerDial.sweep(forSeconds: remaining)
        case .rang: 0
        }
    }

    var body: some View {
        ZStack {
            rimAndFace
            DesvanTimerWedge(sweep: sweep)
                .fill(wedgeFill)
                .padding(Self.rim + 3)
                .animation(wedgeAnimation, value: sweep)
            DesvanTimerMarks()
                .padding(Self.rim + 2)
            handle
            knob
            indexMark
        }
        .frame(width: Self.size, height: Self.size)
        .contentShape(Circle())
        .gesture(turn)
        .modifier(DesvanTimerShake(trigger: ringCount, reduceMotion: reduceMotion))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .overlay {
            Circle()
                .strokeBorder(Desvan.Palette.bulb.opacity(isFocused ? 0.7 : 0), lineWidth: 1.5)
                .shadow(color: Desvan.Palette.bulb.opacity(isFocused ? 0.45 : 0), radius: 6)
                .padding(-3)
                .allowsHitTesting(false)
                .animation(Desvan.Motion.hover, value: isFocused)
        }
        .onKeyPress(keys: [.upArrow, .rightArrow]) { _ in step(1) }
        .onKeyPress(keys: [.downArrow, .leftArrow]) { _ in step(-1) }
        .onKeyPress(keys: [.return, .space]) { _ in
            typed = ""
            pressKnob()
            return .handled
        }
        .onKeyPress(characters: .decimalDigits, phases: .down) { press in
            typed = String((typed + press.characters).suffix(3))
            if let minutes = Int(typed), minutes > 0 { setMinutes(min(minutes, Int(TimerLogic.maximumDuration / 60))) }
            return .handled
        }
        .onChange(of: isFocused) { if !isFocused { typed = "" } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer dial")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Drag round the dial, or type the minutes, then press the knob to start.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = step(1)
            case .decrement: _ = step(-1)
            @unknown default: break
            }
        }
        .accessibilityAction(named: knobTitle) { pressKnob() }
    }

    // MARK: - Pieces

    private var rimAndFace: some View {
        ZStack {
            // The rim: dark wood, lit on top by the bulb.
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
            // The face: cream enamel, a little darker towards its edge, with paper grain.
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xF8F1E4), Color(hex: 0xE9DDC6)],
                    center: UnitPoint(x: 0.45, y: 0.35), startRadius: 4, endRadius: Self.size * 0.55
                ))
                .grain(0.09, in: Circle())
                .overlay {
                    // Set into the rim: a thin shadow along its top edge.
                    Circle().strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center),
                        lineWidth: 2
                    )
                }
                .padding(Self.rim)
        }
    }

    /// Settles when set by a chip or Ask; follows the pointer exactly while dragging.
    private var wedgeAnimation: Animation? {
        dragMinutes == nil ? Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion) : nil
    }

    private var wedgeFill: some ShapeStyle {
        RadialGradient(
            colors: [Desvan.Palette.bulb.opacity(0.95), Color(hex: 0xE8952C).opacity(0.92)],
            center: .center, startRadius: Self.knob / 2, endRadius: Self.size / 2
        )
    }

    /// A kraft nub on the wedge's edge: something to grab.
    @ViewBuilder
    private var handle: some View {
        if draftMinutes != nil {
            // On the rim, like the tab of a real dial, clear of the numbers.
            let radius = Self.size / 2 - Self.rim / 2 - 0.5
            let angle = Angle.degrees(sweep - 90)
            Circle()
                .fill(Desvan.Palette.kraft)
                .overlay { Circle().strokeBorder(Desvan.Palette.ink.opacity(0.35), lineWidth: 0.75) }
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .frame(width: 12, height: 12)
                .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
                .allowsHitTesting(false)
                .animation(wedgeAnimation, value: sweep)
        }
    }

    /// The bulb-lit index at 12 o'clock, where the time runs out.
    private var indexMark: some View {
        Triangle()
            .fill(Desvan.Palette.bulb)
            .shadow(color: Desvan.Palette.bulb.opacity(0.6), radius: 3)
            .frame(width: 9, height: 6)
            .offset(y: -Self.size / 2 + 3)
            .allowsHitTesting(false)
    }

    /// The raised wooden knob with the figure on it.
    private var knob: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0x3A3027), Desvan.Palette.wood],
                                     startPoint: .top, endPoint: .bottom))
                .desvanTexture(DesvanTexture.wood, opacity: 0.3, in: Circle())
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(colors: [Desvan.Palette.paper.opacity(0.25), .black.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1
                    )
                }
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
            VStack(spacing: 1) {
                Text(figure)
                    .font(Desvan.Typeface.figure(figure.count > 5 ? 15 : 19))
                    .foregroundStyle(isRang ? Desvan.Palette.bulb : Desvan.Palette.paper)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(caption)
                    .font(Desvan.Typeface.rounded(11, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 6)
        }
        .frame(width: Self.knob, height: Self.knob)
    }

    private var isRang: Bool {
        if case .rang = reading { return true }
        return false
    }

    private var figure: String {
        switch reading {
        case let .draft(minutes): TimerFormat.clock(TimeInterval(minutes * 60))
        case let .running(remaining, _), let .paused(remaining, _): TimerFormat.clock(remaining)
        case .rang: "0:00"
        }
    }

    private var caption: String {
        switch reading {
        case .draft: String(localized: "Start")
        case .running: String(localized: "left")
        case .paused: String(localized: "Paused")
        case .rang: String(localized: "Time's up")
        }
    }

    private var knobTitle: LocalizedStringKey {
        switch reading {
        case .draft: "Start"
        case .running: "Pause"
        case .paused: "Resume"
        case .rang: "Start again"
        }
    }

    private var accessibilityValue: String {
        switch reading {
        case let .draft(minutes): String(localized: "\(minutes) minutes")
        case let .running(remaining, label):
            [label, String(localized: "\(TimerFormat.duration(remaining)) left")].filter { !$0.isEmpty }
                .joined(separator: ", ")
        case let .paused(remaining, label):
            [label, String(localized: "paused, \(TimerFormat.duration(remaining)) left")].filter { !$0.isEmpty }
                .joined(separator: ", ")
        case let .rang(label):
            [label, String(localized: "time's up")].filter { !$0.isEmpty }.joined(separator: ", ")
        }
    }

    // MARK: - Turning

    /// Drag round the face to set the minutes; a click on the knob presses it.
    private var turn: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                let startDistance = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                // Pressing the knob isn't turning the dial.
                guard startDistance > Self.knob / 2 else { return }
                let previous = dragMinutes ?? min(draftMinutes ?? 0, TimerDial.maximumMinutes)
                let angle = TimerDial.angle(of: value.location, around: center)
                let minutes = TimerDial.minutes(forAngle: angle, previous: previous)
                if dragMinutes == nil || minutes != previous {
                    if TimerDial.crossesFiveMinuteMark(from: previous, to: minutes) { haptic() }
                    dragMinutes = minutes
                    typed = ""
                    setMinutes(minutes)
                }
            }
            .onEnded { value in
                defer { dragMinutes = nil }
                let center = CGPoint(x: Self.size / 2, y: Self.size / 2)
                let startDistance = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                let moved = hypot(value.translation.width, value.translation.height)
                if startDistance <= Self.knob / 2, moved < 4 { pressKnob() }
            }
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        typed = ""
        let current = min(draftMinutes ?? 0, TimerDial.maximumMinutes)
        let next = TimerDial.step(current, by: delta)
        guard next != current || draftMinutes == nil else { return .handled }
        if next % 5 == 0 { haptic() }
        setMinutes(next)
        return .handled
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path.rounded([
                CGPoint(x: rect.minX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.midX, y: rect.maxY),
            ], radius: 1.2)
        }
    }
}

/// The amber sector from 12 o'clock, clockwise.
struct DesvanTimerWedge: Shape {
    var sweep: Double

    var animatableData: Double {
        get { sweep }
        set { sweep = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sweep > 0.01 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        if sweep >= 359.99 {
            path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                       width: radius * 2, height: radius * 2))
            return path
        }
        path.move(to: center)
        path.addArc(center: center, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(sweep - 90),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Sixty minute marks and the numbers every five, printed in ink on the face. Drawn once into a canvas.
struct DesvanTimerMarks: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for minute in 0..<60 {
                let angle = Angle.degrees(Double(minute) * 6 - 90).radians
                let major = minute % 5 == 0
                let outer = radius - 1
                let inner = radius - (major ? 8 : 4)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + outer * cos(angle), y: center.y + outer * sin(angle)))
                tick.addLine(to: CGPoint(x: center.x + inner * cos(angle), y: center.y + inner * sin(angle)))
                context.stroke(tick, with: .color(Desvan.Palette.ink.opacity(major ? 0.75 : 0.4)),
                               style: StrokeStyle(lineWidth: major ? 1.4 : 0.8, lineCap: .round))
                guard major else { continue }
                let numberRadius = radius - 17
                let text = context.resolve(
                    Text("\(minute)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Desvan.Palette.ink.opacity(0.85))
                )
                context.draw(text, at: CGPoint(x: center.x + numberRadius * cos(angle),
                                               y: center.y + numberRadius * sin(angle)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The dial shaking like a kitchen timer going off: a few quick turns either way that die down. With Reduce Motion,
/// the bulb's light flashes over it instead.
private struct DesvanTimerShake: ViewModifier {
    let trigger: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content.overlay {
                Circle()
                    .fill(Desvan.Palette.bulb)
                    .blendMode(.plusLighter)
                    .keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, value in
                        view.opacity(value)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0.35, duration: 0.2)
                            LinearKeyframe(0, duration: 0.4)
                            LinearKeyframe(0.35, duration: 0.2)
                            LinearKeyframe(0, duration: 0.5)
                        }
                    }
                    .allowsHitTesting(false)
            }
        } else {
            content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, angle in
                view.rotationEffect(.degrees(angle))
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(7, duration: 0.05)
                    CubicKeyframe(-7, duration: 0.07)
                    CubicKeyframe(6, duration: 0.07)
                    CubicKeyframe(-6, duration: 0.07)
                    CubicKeyframe(4.5, duration: 0.07)
                    CubicKeyframe(-4.5, duration: 0.07)
                    CubicKeyframe(3, duration: 0.07)
                    CubicKeyframe(-3, duration: 0.07)
                    CubicKeyframe(1.5, duration: 0.07)
                    CubicKeyframe(-1.5, duration: 0.07)
                    SpringKeyframe(0, duration: 0.3, spring: Spring(duration: 0.3, bounce: 0))
                }
            }
        }
    }
}
