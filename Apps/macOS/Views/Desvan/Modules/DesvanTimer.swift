import AltilloDesign
import SwiftUI

/// The «Temporizador» section: a kitchen timer you turn to set, quick times, a name, and every timer running as a
/// row of tags underneath. Several can run at once ("Pasta" and "Pomodoro").
///
/// The dial shows either the next timer being set (nothing selected) or the selected timer counting down. Only
/// while this view is on screen does anything tick (one `TimelineView`, paused when nothing runs); the timers
/// themselves ring from `TimerStore`, with the notch closed too.
struct DesvanTimerView: View {
    let model: NotchModel

    /// The timer on the dial; nil while setting a new one.
    @State private var selectedID: UUID?
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var store: TimerStore { model.timers }
    private static let quickMinutes = [1, 5, 10, 25]

    private var selected: KitchenTimer? { selectedID.flatMap(store.timer) }

    var body: some View {
        let running = store.timers.filter(\.isRunning)
        TimelineView(DesvanTimerSecondsSchedule(anchor: running.compactMap(\.endsAt).min(), paused: running.isEmpty)) {
            context in
            content(now: context.date)
        }
        .padding(.leading, 16)
        .padding(.trailing, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 16)
        // Opening on the section shows the timer that rings next (or the one ringing); with none, a new one.
        .onAppear { selectedID = selectedID ?? store.ordered.first { $0.isRunning || $0.hasRung }?.id }
        .onDisappear {
            store.isEditingName = false
        }
        .onChange(of: isNameFocused) { _, focused in
            store.isEditingName = focused
            if focused { model.actions.takeKeyboardFocus() }
        }
        // A timer rang while the section is open: it comes onto the dial, which shakes.
        .onChange(of: store.ringCount) {
            if let id = store.lastRungID { select(id) }
        }
        // The selected timer went away (removed, undone, Ask cancelled it): back to setting a new one.
        .onChange(of: store.timers.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    private func content(now: Date) -> some View {
        HStack(alignment: .center, spacing: 18) {
            DesvanTimerDial(
                reading: reading(now: now),
                ringCount: store.ringCount,
                setMinutes: { minutes in
                    if selectedID != nil { select(nil) }
                    store.draftMinutes = minutes
                },
                pressKnob: { pressKnob() },
                haptic: { model.actions.haptic(.snap) }
            )
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 8)
                if let selected {
                    DesvanTimerControls(timer: selected, now: now, store: store)
                } else {
                    composer
                }
                Spacer(minLength: 10)
                tags(now: now)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private func reading(now: Date) -> DesvanTimerDial.Reading {
        guard let selected else { return .draft(minutes: store.draftMinutes) }
        switch selected.state {
        case .running: return .running(remaining: selected.remaining(at: now), label: selected.label)
        case let .paused(remaining): return .paused(remaining: remaining, label: selected.label)
        case .rang: return .rang(label: selected.label)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Text(selected?.displayName ?? String(localized: "New timer"))
                .font(Desvan.Typeface.display(16, weight: 600))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            if selected?.origin == .ask {
                Label("Set by Ask", systemImage: "sparkle")
                    .font(Desvan.Typeface.rounded(11, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.bulb)
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            soundToggle
        }
        .frame(height: 22)
    }

    private var soundToggle: some View {
        let on = model.settings.timerSound
        return Button {
            model.settings.timerSound.toggle()
        } label: {
            Image(systemName: on ? "bell" : "bell.slash")
                .font(.system(size: 12, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 14)
        }
        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 28))
        .help(on ? "Rings with a sound. Click to ring silently." : "Rings silently. Click to ring with a sound.")
        .accessibilityLabel("Sound")
        .accessibilityValue(on ? "On" : "Off")
    }

    // MARK: - Setting a new one

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            // As much as fits the notch's width: "1 min … Other…", then without "Other…", then bare figures.
            ViewThatFits(in: .horizontal) {
                quickTimes(unit: true, other: true)
                quickTimes(unit: true, other: false)
                quickTimes(unit: false, other: false)
            }
            HStack(spacing: 8) {
                DesvanTimerNameField(text: $name, isFocused: $isNameFocused, onSubmit: startFromField) {
                    model.actions.takeKeyboardFocus()
                }
                Button(action: startFromField) {
                    Label("Start", systemImage: "play.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(DesvanButtonStyle(kind: .primary, height: 32))
                .help(startTitle)
                .accessibilityLabel(startTitle)
                .disabled(fieldDuration == nil && store.draftMinutes == 0)
            }
        }
    }

    private func quickTimes(unit: Bool, other: Bool) -> some View {
        HStack(spacing: 5) {
            ForEach(Self.quickMinutes, id: \.self) { minutes in
                DesvanTimerChip(title: unit ? "\(minutes) min" : "\(minutes)′", isOn: store.draftMinutes == minutes) {
                    store.draftMinutes = minutes
                    model.actions.haptic(.snap)
                }
                .accessibilityLabel("\(minutes) minutes")
            }
            if other {
                DesvanTimerChip(title: String(localized: "Other…"), isOn: false) {
                    model.actions.takeKeyboardFocus()
                    isNameFocused = true
                }
                .help("Type a time and a name, like “1h 30 bread”")
            }
        }
    }

    /// "Start 5 min", or the time typed in the field.
    private var startTitle: String {
        let seconds = fieldDuration ?? TimeInterval(store.draftMinutes * 60)
        return String(localized: "Start \(TimerFormat.duration(seconds))")
    }

    /// A time typed in the name field ("10", "1h 30 bread"), which wins over the dial.
    private var fieldDuration: TimeInterval? {
        TimerDurationParser.parse(name)?.seconds
    }

    private func startFromField() {
        let timer: KitchenTimer?
        if let parsed = TimerDurationParser.parse(name) {
            timer = store.start(seconds: parsed.seconds, label: parsed.label ?? "")
        } else {
            timer = store.startDraft(label: name)
        }
        guard let timer else { return }
        name = ""
        isNameFocused = false
        model.actions.haptic(.land)
        select(timer.id)
    }

    private func pressKnob() {
        guard let selected else {
            startFromField()
            return
        }
        if selected.hasRung { store.restart(selected.id) } else { store.toggle(selected.id) }
    }

    private func select(_ id: UUID?) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { selectedID = id }
    }

    // MARK: - Every timer

    @ViewBuilder
    private func tags(now: Date) -> some View {
        let timers = store.ordered
        if timers.isEmpty {
            Text("Turn the dial or pick a time. Several can run at once.")
                .font(.system(size: 12))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 30, alignment: .leading)
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    if selectedID != nil {
                        DesvanTimerNewTag { select(nil) }
                    }
                    ForEach(timers) { timer in
                        DesvanTimerTag(timer: timer, now: now, isSelected: timer.id == selectedID) {
                            select(timer.id)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.never)
            .reportsHorizontalScroll(id: "timers", model: model)
            .frame(height: 34)
        }
    }
}

// MARK: - The selected timer's controls

private struct DesvanTimerControls: View {
    let timer: KitchenTimer
    let now: Date
    let store: TimerStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status)
                .font(.system(size: 13))
                .foregroundStyle(timer.hasRung ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                .lineLimit(1)
                .frame(height: 28, alignment: .leading)
                .accessibilityAddTraits(.updatesFrequently)
            HStack(spacing: 6) {
                if timer.hasRung {
                    Button { store.restart(timer.id) } label: {
                        Label("Again", systemImage: "arrow.clockwise").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 32))
                    Button("Done") { store.remove(timer.id) }
                        .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 32))
                } else {
                    Button { store.toggle(timer.id) } label: {
                        Label(timer.isRunning ? "Pause" : "Resume",
                              systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                            .labelStyle(.titleAndIcon)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 32))
                    Button { store.reset(timer.id) } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(DesvanButtonStyle(kind: .ghost, height: 32))
                    .disabled(timer.isPaused && timer.remaining(at: now) >= timer.duration)
                    if timer.origin == .ask {
                        Button { store.undoAsk(timer.id) } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward").labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 32))
                        .help("Take back the timer Ask set")
                    } else {
                        Button { store.remove(timer.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        }
                        .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 32))
                        .help("Remove this timer")
                        .accessibilityLabel("Remove this timer")
                    }
                }
            }
        }
    }

    private var status: String {
        let set = TimerFormat.duration(timer.duration)
        switch timer.state {
        case let .running(endsAt):
            return String(localized: "\(set) · rings at \(endsAt.formatted(date: .omitted, time: .shortened))")
        case .paused:
            return String(localized: "\(set) · paused")
        case let .rang(at):
            return String(localized: "Time's up · \(at.formatted(date: .omitted, time: .shortened))")
        }
    }
}

// MARK: - Pieces

/// A quick time: a small capsule, lit by the bulb when it's the one set.
private struct DesvanTimerChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isOn ? Desvan.Palette.bulb : Desvan.Palette.paper.opacity(isHovering ? 1 : 0.85))
                .padding(.horizontal, 9)
                .frame(minWidth: 28, minHeight: 28)
                .background {
                    Capsule()
                        .fill(Desvan.Palette.paper.opacity(isOn ? 0.1 : isHovering ? 0.08 : 0.03))
                        .overlay {
                            Capsule().strokeBorder(
                                isOn ? Desvan.Palette.bulb.opacity(0.7) : Desvan.Palette.paper.opacity(0.2), lineWidth: 1
                            )
                        }
                }
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Desvan.Motion.hover, value: isHovering)
        .animation(Desvan.Motion.hover, value: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "+" back to setting a new timer, at the head of the tags.
private struct DesvanTimerNewTag: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .foregroundStyle(Desvan.Palette.paper)
                .background {
                    Circle().strokeBorder(Desvan.Palette.paper.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("New timer")
        .accessibilityLabel("New timer")
    }
}

/// One timer as a kraft tag: what it is and what's left. Click to put it on the dial.
private struct DesvanTimerTag: View {
    let timer: KitchenTimer
    let now: Date
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(timer.hasRung ? Color(hex: 0xA2560B) : Desvan.Palette.ink.opacity(0.7))
                Text(timer.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .leading)
                Text(timer.hasRung ? String(localized: "Time's up") : TimerFormat.clock(timer.remaining(at: now)))
                    .font(Desvan.Typeface.figure(12, weight: .medium))
                    .foregroundStyle(Desvan.Palette.ink.opacity(0.7))
                    .fixedSize()
            }
            .foregroundStyle(Desvan.Palette.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background {
                let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
                shape.fill(timer.hasRung ? Desvan.Palette.bulb : Desvan.Palette.kraft)
                    .desvanTexture(DesvanTexture.kraft, opacity: 0.5, in: shape)
                    .overlay {
                        shape.strokeBorder(isSelected ? Desvan.Palette.paper.opacity(0.9) : .black.opacity(0.25),
                                           lineWidth: isSelected ? 1.5 : 0.5)
                    }
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            }
            .opacity(timer.isPaused && !isSelected ? 0.75 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var symbol: String {
        switch timer.state {
        case .running: "timer"
        case .paused: "pause.fill"
        case .rang: "bell.fill"
        }
    }

    private var accessibilityLabel: String {
        switch timer.state {
        case .running: String(localized: "\(timer.displayName), \(TimerFormat.duration(timer.remaining(at: now))) left")
        case .paused: String(localized: "\(timer.displayName), paused")
        case .rang: String(localized: "\(timer.displayName), time's up")
        }
    }
}

/// The name field, set into the wood like Ask's prompt. Typing a time here ("10", "1h 30 bread") and Return starts
/// it; a plain name starts the dial's time under that name.
private struct DesvanTimerNameField: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    /// The notch panel doesn't become key on hover; a click in the field has to ask for it.
    let onClick: () -> Void

    var body: some View {
        let focused = isFocused.wrappedValue
        TextField(
            "Timer name",
            text: $text,
            prompt: Text("Name, or “10 pasta”").foregroundStyle(Desvan.Palette.paperTertiary)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(Desvan.Palette.paper)
        .tint(Desvan.Palette.bulb)
        .focused(isFocused)
        .onSubmit(onSubmit)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 32)
        .background {
            Capsule()
                .fill(Color.black.opacity(0.4))
                .overlay {
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.black.opacity(0.6), Desvan.Palette.lip],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.75
                    )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(Desvan.Palette.bulb.opacity(focused ? 0.55 : 0), lineWidth: 1)
                        .shadow(color: Desvan.Palette.bulb.opacity(focused ? 0.35 : 0), radius: 6)
                }
        }
        .animation(Desvan.Motion.hover, value: focused)
        .contentShape(Capsule())
        .simultaneousGesture(TapGesture().onEnded {
            onClick()
            isFocused.wrappedValue = true
        })
        .accessibilityLabel("Timer name, or a time to start")
    }
}

/// Once a second, on the second of the soonest timer to ring (so its countdown changes exactly when it should);
/// nothing at all when no timer runs.
struct DesvanTimerSecondsSchedule: TimelineSchedule {
    let anchor: Date?
    let paused: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(anchor: paused ? nil : anchor, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let anchor: Date?
        var upcoming: Date?

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            guard let anchor else {
                upcoming = nil
                return current
            }
            // The next moment the soonest countdown's whole seconds change; past it, plain seconds.
            let remaining = anchor.timeIntervalSince(current)
            let step = remaining > 0 ? remaining - (remaining.rounded(.up) - 1) : 1
            upcoming = current.addingTimeInterval(Swift.max(0.05, step))
            return current
        }
    }
}
