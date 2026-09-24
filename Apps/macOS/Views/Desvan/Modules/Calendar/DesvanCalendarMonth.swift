import AltilloDesign
import SwiftUI

/// The month on a wood card: its name with the page arrows and a way back to today, the weekday initials (from the
/// user's first weekday, in their language) and five or six rows of days. Today is lit by the bulb; the chosen day is
/// raised on a small plaque, like the active tab; days with events carry up to three dots in their calendars'
/// colours.
struct DesvanMonthCard: View {
    let grid: CalendarGrid
    let selected: Date
    let today: Date
    let days: [Date: [CalendarStore.Event]]
    let calendar: Calendar
    /// The month's events arrived: until then a day without dots means "not yet", not "free".
    let isLoaded: Bool
    let isShowingToday: Bool
    let turn: CalendarPageTurn
    /// Something for the header's right side (the chosen day's summary, in the month-only layout).
    let accessory: AnyView?
    /// The options menu goes in the header when there's no agenda beside the month to hold it.
    let options: NotchModel?
    let metrics: DesvanCalendarMetrics
    let onSelect: (Date) -> Void
    let onTurnPage: (Int) -> Void
    let onToday: () -> Void

    @Namespace private var plaque
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Five rows for most months (roomier), six when the month needs them.
    static let minimumRows = 5

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: metrics.header)
            weekdays
                .frame(height: metrics.weekdays)
            ZStack {
                rows
                    .id(grid.month)
                    .transition(CalendarPageTransition(turn: turn, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.horizontal, metrics.cardInset)
        .padding(.top, metrics.cardInset / 2)
        .padding(.bottom, metrics.cardInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .desvanCard(radius: 12)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 2) {
            title
                .padding(.leading, 5)
                .layoutPriority(1)
            if accessory != nil {
                navigation
                    .padding(.leading, 4)
            }
            Spacer(minLength: 4)
            if let accessory {
                accessory
            } else {
                navigation
            }
            if let options {
                DesvanCalendarOptionsButton(model: options)
            }
        }
    }

    /// "September 2026", "Sep 2026" or "Sep", whichever fits.
    private var title: some View {
        ViewThatFits(in: .horizontal) {
            titleText(month: monthName(short: false), year: true)
            titleText(month: monthName(short: true), year: true)
            titleText(month: monthName(short: true), year: false)
        }
        .contentTransition(.opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(monthName(short: false)) \(String(grid.month.year))")
        .accessibilityAddTraits(.isHeader)
    }

    private func titleText(month: String, year: Bool) -> some View {
        HStack(spacing: 4) {
            Text(month)
                .foregroundStyle(Desvan.Palette.paper)
            if year {
                Text(verbatim: String(grid.month.year))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .font(Desvan.Typeface.rounded(metrics.title, weight: .semibold))
        .lineLimit(1)
        .fixedSize()
    }

    private func monthName(short: Bool) -> String {
        let symbols = short ? calendar.shortStandaloneMonthSymbols : calendar.standaloneMonthSymbols
        let index = grid.month.month - 1
        return symbols.indices.contains(index) ? symbols[index].capitalized(with: calendar.locale) : ""
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            DesvanCalendarNavButton(symbol: "chevron.left", help: "Previous month") { onTurnPage(-1) }
            Button("Today", action: onToday)
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
                .opacity(isShowingToday ? 0.45 : 1)
                .help("Go back to today (T)")
                .desvanHitTarget()
            DesvanCalendarNavButton(symbol: "chevron.right", help: "Next month") { onTurnPage(1) }
        }
        .fixedSize()
    }

    // MARK: Grid

    private var weekdays: some View {
        let symbols = CalendarGrid.weekdaySymbols(calendar: calendar)
        return HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { index in
                Text(symbols[index])
                    .font(Desvan.Typeface.rounded(metrics.weekdayFont, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(0..<grid.rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        cell(row * 7 + column)
                    }
                }
            }
        }
    }

    private func cell(_ index: Int) -> some View {
        let day = grid.days[index]
        let events = days[day] ?? []
        let isToday = calendar.isDate(day, inSameDayAs: today)
        let isSelected = calendar.isDate(day, inSameDayAs: selected)
        return DesvanDayCell(
            number: String(calendar.component(.day, from: day)),
            isInMonth: grid.isInMonth(index),
            isToday: isToday,
            isSelected: isSelected,
            isPast: day < today,
            dots: CalendarBuckets.dots(for: events),
            label: DesvanCalendarWords.dayLabel(day, count: isLoaded ? events.count : nil, isToday: isToday),
            plaque: plaque,
            plaqueID: grid.month,
            metrics: metrics
        ) {
            onSelect(day)
        }
    }
}

// MARK: - Day

/// One day of the grid: its number, its dots, and the plaque when it is the chosen one.
private struct DesvanDayCell: View {
    let number: String
    let isInMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let isPast: Bool
    let dots: [UInt32]
    let label: String
    let plaque: Namespace.ID
    let plaqueID: CalendarMonth
    let metrics: DesvanCalendarMetrics
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                backdrop
                if isToday { bulbLight }
                // The number and its dots as one little stack, always in the same place so a row's numbers line
                // up whether or not their days have events.
                VStack(spacing: metrics.dotGap) {
                    Text(number)
                        .font(Desvan.Typeface.figure(metrics.number, weight: isToday || isSelected ? .semibold : .medium))
                        .foregroundStyle(numberColor)
                        .shadow(color: Desvan.Palette.bulb.opacity(isToday ? 0.55 : 0), radius: 4)
                        .frame(height: metrics.numberLine)
                    HStack(spacing: metrics.dot * 0.6) {
                        ForEach(dots.indices, id: \.self) { index in
                            Circle()
                                .fill(Color(hex: dots[index]))
                                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                                .frame(width: metrics.dot, height: metrics.dot)
                        }
                    }
                    .frame(height: metrics.dot)
                    .opacity(isInMonth ? 1 : 0.45)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private var backdrop: some View {
        if isSelected {
            DesvanCalendarPlaque()
                .matchedGeometryEffect(id: plaqueID, in: plaque)
                .frame(maxWidth: metrics.plaqueWidth, maxHeight: metrics.plaqueHeight)
                .padding(.horizontal, 1.5)
                .padding(.vertical, 1)
        } else if isHovering {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Desvan.Palette.paper.opacity(0.07))
                .frame(maxWidth: metrics.plaqueWidth, maxHeight: metrics.plaqueHeight)
                .padding(.horizontal, 1.5)
                .padding(.vertical, 1)
        }
    }

    /// Today, lit from above: light added to whatever is under it, never paint.
    private var bulbLight: some View {
        RadialGradient(
            colors: [Desvan.Palette.bulb.opacity(isSelected ? 0.22 : 0.3), Desvan.Palette.bulb.opacity(0)],
            center: .center,
            startRadius: 0,
            endRadius: metrics.plaqueWidth * 0.42
        )
        .frame(width: metrics.plaqueWidth, height: metrics.plaqueHeight)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var numberColor: Color {
        if isToday { return Desvan.Palette.bulb }
        if !isInMonth { return Desvan.Palette.paper.opacity(0.26) }
        if isSelected { return Desvan.Palette.paper }
        return isPast ? Desvan.Palette.paperSecondary : Desvan.Palette.paper
    }
}

/// The chosen day: a small plaque of lighter wood in a thin brass frame, the same as the active tab's.
struct DesvanCalendarPlaque: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Color(hex: 0x3B3026), Color(hex: 0x2B231B)], startPoint: .top, endPoint: .bottom))
            .desvanTexture(DesvanTexture.wood, opacity: 0.7, in: shape)
            .overlay {
                // Brass rim: bright where it faces the bulb, dark underneath.
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: 0xE8C987), Color(hex: 0xA9824A), Color(hex: 0x5E4522)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .overlay {
                shape.inset(by: 1).strokeBorder(.black.opacity(0.45), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.7), radius: 1.5, y: 1)
    }
}

// MARK: - Controls

/// A chevron in the month's header: a small visual with a full-size target.
struct DesvanCalendarNavButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .frame(width: 24, height: 24)
                .background {
                    Circle().fill(Desvan.Palette.paper.opacity(isHovering ? 0.08 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .desvanHitTarget()
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// The calendar's options (layout, all-day events, which calendars) behind a small slider icon.
struct DesvanCalendarOptionsButton: View {
    let model: NotchModel

    @State private var isHovering = false

    var body: some View {
        Menu {
            DesvanCalendarOptions(model: model)
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isHovering ? Desvan.Palette.paper : Desvan.Palette.paperSecondary)
                .frame(width: 26, height: 24)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Desvan.Palette.paper.opacity(isHovering ? 0.08 : 0))
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .desvanHitTarget()
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help("Calendar options")
        .accessibilityLabel("Calendar options")
    }
}

// MARK: - Sizes

/// Sizes for the calendar's month layouts, from the body height they're given: compact at a 150 pt body, roomy from
/// 200 pt, and in between for anything else, so the layouts look right whatever height the notch settles on.
struct DesvanCalendarMetrics: Equatable {
    /// 0 at 150 pt, 1 from 200 pt.
    let roominess: CGFloat

    /// - Parameters: `compact` and `roomy` are the body heights the two ends were designed for (the agenda alone
    ///   goes from 104 to 180 pt).
    init(height: CGFloat, compact: CGFloat = 150, roomy: CGFloat = 200) {
        roominess = height > 0 ? min(max((height - compact) / (roomy - compact), 0), 1) : 1
    }

    private func lerp(_ compact: CGFloat, _ roomy: CGFloat) -> CGFloat {
        compact + (roomy - compact) * roominess
    }

    // Month card
    var cardInset: CGFloat { lerp(5, 8) }
    var header: CGFloat { lerp(26, 32) }
    var title: CGFloat { lerp(13, 15) }
    var weekdays: CGFloat { lerp(14, 18) }
    var weekdayFont: CGFloat { 12 }
    var number: CGFloat { lerp(12, 14) }
    var numberLine: CGFloat { lerp(13, 16) }
    var dot: CGFloat { lerp(4, 5) }
    var dotGap: CGFloat { lerp(1, 3) }
    /// The plaque and the hover wash never grow past this, however wide or tall the cell.
    var plaqueWidth: CGFloat { lerp(34, 44) }
    var plaqueHeight: CGFloat { lerp(22, 30) }

    // Day panel
    var panelHeader: CGFloat { lerp(26, 32) }
    var panelTitle: CGFloat { lerp(13, 15) }
    var panelSubtitle: CGFloat { lerp(12, 12.5) }
    var rowHeight: CGFloat { lerp(30, 36) }
    var rowSpacing: CGFloat { lerp(4, 6) }
    var rowTitle: CGFloat { lerp(12, 13.5) }
    var rowTime: CGFloat { lerp(12, 12.5) }

    // Agenda (today's list alone)
    var nextCardHeight: CGFloat { lerp(46, 60) }
    var nextTitle: CGFloat { lerp(13, 15) }
    var nextTime: CGFloat { lerp(12, 13) }
    var agendaRowHeight: CGFloat { lerp(24, 34) }
}

// MARK: - Words

enum DesvanCalendarWords {
    /// "Thursday 24 September, today, 3 events", for VoiceOver. `count` is nil while the month is loading.
    static func dayLabel(_ day: Date, count: Int?, isToday: Bool) -> String {
        var parts = [day.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if isToday { parts.append(String(localized: "today")) }
        if let count { parts.append(events(count)) }
        return parts.joined(separator: ", ")
    }

    static func events(_ count: Int) -> String {
        switch count {
        case 0: String(localized: "no events")
        case 1: String(localized: "1 event")
        default: String(localized: "\(count) events")
        }
    }
}
