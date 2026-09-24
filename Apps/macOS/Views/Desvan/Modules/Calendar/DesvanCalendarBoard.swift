import AltilloDesign
import SwiftUI

/// The calendar tab's month layouts.
///
/// - `.monthAndAgenda`: a compact month on the left and the chosen day's agenda beside it.
/// - `.month`: the month across the whole body with the chosen day summed up in its header; the summary (or Space)
///   turns the card over to that day's list.
///
/// Keyboard: ← → move a day, ↑ ↓ a week (walking off the month turns the page), ⌘← / ⌘→ turn the page, T goes
/// back to today, Return opens the day's first event in Calendar, Space shows or hides the day's list (month only)
/// and Esc hides it.
struct DesvanCalendarBoard: View {
    let model: NotchModel
    let style: CalendarStyle

    @State private var browser: CalendarBrowser
    /// `.month`: the chosen day's list is showing instead of the grid.
    @State private var showsDay = false
    /// Which way the pages turn. Not observed: the leaving page and the arriving one read it as they move.
    @State private var turn = CalendarPageTurn()
    @State private var size: CGSize = .zero
    @FocusState private var isFocused: Bool
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: NotchModel, style: CalendarStyle) {
        self.model = model
        self.style = style
        _browser = State(initialValue: CalendarBrowser(today: model.calendar.today, calendar: model.calendar.calendar))
        // `-designScenario openCalendar -calendarDemoDay YES` opens the month-only layout on the day's list.
        _showsDay = State(initialValue: model.scenario == .openCalendar
            && UserDefaults.standard.bool(forKey: "calendarDemoDay"))
    }

    private var store: CalendarStore { model.calendar }
    private var calendar: Calendar { store.calendar }
    private var grid: CalendarGrid {
        CalendarGrid(month: browser.month, calendar: calendar, minimumRows: DesvanMonthCard.minimumRows)
    }

    private var metrics: DesvanCalendarMetrics { DesvanCalendarMetrics(height: size.height) }

    /// The month beside the agenda: wide enough for its name and arrows, leaving the agenda the rest.
    private var compactMonthWidth: CGFloat {
        let roomy = metrics.roominess
        return min(max(size.width * (0.42 + 0.04 * roomy), 196 + 12 * roomy), 252 + 36 * roomy)
    }

    var body: some View {
        ZStack(alignment: .top) {
            if style == .monthAndAgenda {
                HStack(spacing: 8) {
                    monthCard(accessory: nil)
                        .frame(width: compactMonthWidth)
                    ZStack(alignment: .top) {
                        DesvanCalendarDayPanel(
                            agenda: agenda(for: browser.selected),
                            options: model,
                            metrics: metrics
                        )
                        .id(browser.selected)
                        .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else if showsDay {
                DesvanCalendarDayPanel(
                    agenda: agenda(for: browser.selected),
                    options: model,
                    metrics: metrics,
                    back: backTitle
                ) {
                    setShowsDay(false)
                }
                .padding(.horizontal, metrics.cardInset + 3)
                .padding(.vertical, metrics.cardInset)
                .desvanCard(radius: 12)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            } else {
                monthCard(accessory: summary)
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            store.display(browser.month)
            isFocused = true
        }
        .onChange(of: browser.month) { _, month in store.display(month) }
        // Midnight while open: if the lit day was chosen, the choice follows it into the new day.
        .onChange(of: store.today) { old, new in
            if calendar.isDate(browser.selected, inSameDayAs: old) { change { $0.select(new, calendar: calendar) } }
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in arrow(press) }
        .onKeyPress(.return) {
            open(agenda(for: browser.selected).primary)
            return .handled
        }
        .onKeyPress(.space) {
            guard style == .month else { return .ignored }
            setShowsDay(!showsDay)
            return .handled
        }
        .onKeyPress(.escape) {
            guard showsDay else { return .ignored }
            setShowsDay(false)
            return .handled
        }
        .onKeyPress(characters: ["t"], phases: .down) { press in
            guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
            change { $0.goToToday(store.today, calendar: calendar) }
            return .handled
        }
    }

    // MARK: Month

    private func monthCard(accessory: AnyView?) -> some View {
        DesvanMonthCard(
            grid: grid,
            selected: browser.selected,
            today: store.today,
            days: store.days,
            calendar: calendar,
            isLoaded: store.loadedMonths.contains(browser.month) || store.showsSamples,
            isShowingToday: browser.isShowingToday(store.today, calendar: calendar),
            turn: turn,
            accessory: accessory,
            options: style == .month ? model : nil,
            metrics: metrics,
            onSelect: { day in
                isFocused = true
                change { $0.select(day, calendar: calendar) }
            },
            onTurnPage: { months in change { $0.turnPage(by: months, calendar: calendar) } },
            onToday: { change { $0.goToToday(store.today, calendar: calendar) } }
        )
    }

    /// `.month`: the chosen day in one line at the top right; a click shows its list.
    private var summary: AnyView {
        AnyView(DesvanCalendarDaySummary(agenda: agenda(for: browser.selected)) { setShowsDay(true) })
    }

    /// "September", for the way back from a day's list to its month.
    private var backTitle: String {
        browser.selected.formatted(.dateTime.month(.wide))
    }

    // MARK: Agenda

    /// What the panel lists for a day. Today: what is left of it (or, when it's done, tomorrow's first thing). Any
    /// other day: all of it.
    private func agenda(for day: Date) -> DesvanDayAgenda {
        if calendar.isDate(day, inSameDayAs: store.today) {
            var events = store.events
            var isTomorrow = store.isTomorrow
            if events.isEmpty, store.showsSamples {
                events = CalendarStore.Event.samples()
                isTomorrow = false
            }
            return DesvanDayAgenda(
                day: day,
                kind: .today,
                events: isTomorrow ? [] : events,
                tomorrowFirst: isTomorrow ? events.first : nil,
                isLoaded: store.hasLoaded || store.showsSamples
            )
        }
        let kind: DesvanDayAgenda.Kind = if let tomorrow = calendar.date(byAdding: .day, value: 1, to: store.today),
                                             calendar.isDate(day, inSameDayAs: tomorrow) { .tomorrow } else { .other }
        return DesvanDayAgenda(
            day: day,
            kind: kind,
            events: store.events(on: day),
            tomorrowFirst: nil,
            isLoaded: store.loadedMonths.contains(browser.month) || store.showsSamples
        )
    }

    private func open(_ event: CalendarStore.Event?) {
        CalendarAppLink.open(event)
    }

    // MARK: Moving

    private func arrow(_ press: KeyPress) -> KeyPress.Result {
        var key = press.key
        // Right-to-left layouts draw the week the other way round: ← still points at the day drawn on the left.
        if layoutDirection == .rightToLeft {
            if key == .leftArrow { key = .rightArrow } else if key == .rightArrow { key = .leftArrow }
        }
        if press.modifiers.contains(.command) {
            switch key {
            case .leftArrow: change { $0.turnPage(by: -1, calendar: calendar) }
            case .rightArrow: change { $0.turnPage(by: 1, calendar: calendar) }
            default: return .ignored
            }
            return .handled
        }
        guard press.modifiers.isDisjoint(with: [.option, .control]) else { return .ignored }
        let step: CalendarBrowser.Step = switch key {
        case .leftArrow: .previousDay
        case .rightArrow: .nextDay
        case .upArrow: .previousWeek
        default: .nextWeek
        }
        change { $0.move(step, calendar: calendar) }
        return .handled
    }

    /// Applies a move; a page turn slides the grid the way it went.
    private func change(_ update: (inout CalendarBrowser) -> Void) {
        var next = browser
        update(&next)
        guard next != browser else { return }
        if next.month != browser.month {
            turn.direction = next.month > browser.month ? 1 : -1
            withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { browser = next }
        } else {
            withAnimation(Desvan.Motion.pick(Desvan.Motion.lift, reduceMotion: reduceMotion)) { browser = next }
        }
    }

    private func setShowsDay(_ shows: Bool) {
        withAnimation(Desvan.Motion.pick(Desvan.Motion.content, reduceMotion: reduceMotion)) { showsDay = shows }
    }
}

/// Which way the month pages turn: +1 forwards (the new month comes in from the trailing edge), -1 backwards.
@MainActor
final class CalendarPageTurn {
    var direction = 1
}

/// A page turn: the old month slides out one way and fades while the new one comes in from the other side.
struct CalendarPageTransition: Transition {
    let turn: CalendarPageTurn
    let reduceMotion: Bool

    func body(content: Content, phase: TransitionPhase) -> some View {
        let direction = CGFloat(turn.direction)
        let shift: CGFloat = reduceMotion ? 0 : 28
        let offset: CGFloat = switch phase {
        case .willAppear: direction * shift
        case .didDisappear: -direction * shift
        case .identity: 0
        }
        content
            .offset(x: offset)
            .opacity(phase.isIdentity ? 1 : 0)
    }
}
