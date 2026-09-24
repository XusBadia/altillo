import AltilloDesign
import SwiftUI

/// What the panel beside the month lists for the chosen day.
struct DesvanDayAgenda {
    enum Kind { case today, tomorrow, other }

    let day: Date
    let kind: Kind
    /// Today: what is left of it. Any other day: all of it.
    let events: [CalendarStore.Event]
    /// Today is done: the first thing tomorrow, so the panel still says what comes next.
    let tomorrowFirst: CalendarStore.Event?
    let isLoaded: Bool

    /// What Return opens in Calendar.
    var primary: CalendarStore.Event? { events.first ?? tomorrowFirst }

    /// "Today", "Tomorrow" or "Friday".
    var title: String {
        switch kind {
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .other: day.formatted(.dateTime.weekday(.wide))
        }
    }

    /// "24 September".
    var subtitle: String {
        day.formatted(.dateTime.day().month(.wide))
    }

    /// "Thu 24", for the month-only header.
    var shortDay: String {
        switch kind {
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .other: day.formatted(.dateTime.weekday(.abbreviated).day())
        }
    }
}

// MARK: - Panel

/// The chosen day's agenda: a header with the day and the options, then one row per event (time, calendar colour,
/// title and, for calls, Join). Rows open the event in Calendar.
struct DesvanCalendarDayPanel: View {
    let agenda: DesvanDayAgenda
    let options: NotchModel?
    let metrics: DesvanCalendarMetrics
    /// The month's name, when the panel is a second state of the month-only layout and needs a way back.
    var back: String?
    var onBack: (() -> Void)?

    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
            header
                .frame(height: metrics.panelHeader)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
    }

    private var header: some View {
        HStack(spacing: 6) {
            if let back, let onBack {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(back)
                    }
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 24))
                .help("Back to the month (Esc)")
                .desvanHitTarget()
            }
            Text(agenda.title)
                .font(Desvan.Typeface.rounded(metrics.panelTitle, weight: .semibold))
                .foregroundStyle(agenda.kind == .today ? Desvan.Palette.bulb : Desvan.Palette.paper)
                .lineLimit(1)
                .fixedSize()
            Text(agenda.subtitle)
                .font(.system(size: metrics.panelSubtitle))
                .foregroundStyle(Desvan.Palette.paperTertiary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let options {
                DesvanCalendarOptionsButton(model: options)
            }
        }
        .padding(.leading, back == nil ? 2 : 0)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var content: some View {
        if !agenda.events.isEmpty {
            ScrollView(.vertical) {
                VStack(spacing: metrics.rowSpacing) {
                    ForEach(Array(agenda.events.enumerated()), id: \.element.id) { index, event in
                        DesvanDayEventRow(
                            event: event,
                            isNext: agenda.kind == .today && index == 0,
                            isTomorrow: false,
                            width: width,
                            metrics: metrics
                        )
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
        } else if agenda.kind == .today {
            VStack(alignment: .leading, spacing: 6) {
                quiet(agenda.isLoaded ? "Nothing left today." : "Checking your calendar…",
                      symbol: agenda.isLoaded ? "checkmark.circle" : "calendar")
                if let first = agenda.tomorrowFirst {
                    DesvanDayEventRow(event: first, isNext: false, isTomorrow: true, width: width, metrics: metrics)
                }
            }
        } else if agenda.isLoaded {
            quiet("Nothing on this day.", symbol: "sun.max")
        }
    }

    private func quiet(_ text: LocalizedStringKey, symbol: String) -> some View {
        Label {
            Text(text)
                .font(.system(size: metrics.rowTitle))
        } icon: {
            Image(systemName: symbol)
                .font(.system(size: max(13, metrics.rowTitle), weight: .medium))
                .symbolRenderingMode(.hierarchical)
        }
        .foregroundStyle(Desvan.Palette.paperTertiary)
        .padding(.leading, 4)
        .padding(.top, 2)
    }
}

// MARK: - Row

/// One event of the day on a slim wood row. The next one of today carries its countdown, a running one is lit, and
/// a call has its Join button (filled when it's about to start). Clicking the row opens the event in Calendar.
struct DesvanDayEventRow: View {
    let event: CalendarStore.Event
    let isNext: Bool
    let isTomorrow: Bool
    /// The panel's width: narrow panels drop the countdown and shorten Join to a camera.
    let width: CGFloat
    let metrics: DesvanCalendarMetrics

    @State private var isHovering = false
    @Environment(\.openURL) private var openURL

    private var isRunning: Bool { !event.isAllDay && event.isRunning() }
    /// About to start (or running): Join is lit.
    private var isImminent: Bool {
        guard !event.isAllDay, !isTomorrow else { return false }
        return isRunning || event.start.timeIntervalSinceNow <= 15 * 60 && event.start > .now
    }

    /// With room to spare, today's next event gets two lines (title, then time and countdown) so its title isn't
    /// squeezed by the countdown and Join.
    private var isTwoLine: Bool { isNext && metrics.roominess >= 0.5 }
    private var showsCountdown: Bool { isNext && width >= 250 && !event.isAllDay }
    private var joinIsWord: Bool { width >= 230 }
    private var height: CGFloat { isTwoLine ? metrics.rowHeight + 12 : metrics.rowHeight }

    var body: some View {
        HStack(spacing: 8) {
            DesvanCalendarSpine(colorHex: event.calendarColorHex, height: height - 14)
            if isTwoLine {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    // Whatever fits beside Join: range and countdown, the range, or just the start.
                    ViewThatFits(in: .horizontal) {
                        when(DesvanEventFormat.time(event), countdown: true)
                        when(DesvanEventFormat.time(event), countdown: false)
                        when(DesvanEventFormat.shortTime(event), countdown: false)
                    }
                }
            } else {
                Text(DesvanEventFormat.shortTime(event))
                    .font(Desvan.Typeface.figure(metrics.rowTime, weight: .medium))
                    .foregroundStyle(isRunning ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
                    .lineLimit(1)
                    .fixedSize()
                title
            }
            Spacer(minLength: 4)
            if isTomorrow {
                DesvanKraftChip(text: "tomorrow")
            }
            if showsCountdown, !isTwoLine {
                DesvanCountdownBadge(event: event, isTomorrow: false)
            }
            if let url = event.conferenceURL {
                join(url)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, event.conferenceURL == nil ? 9 : 4)
        .frame(height: height)
        .desvanCard(
            radius: 9,
            fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood,
            glow: isRunning ? Desvan.Palette.bulb.opacity(0.5) : nil
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onTapGesture { CalendarAppLink.open(event) }
        .help("Open in Calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanEventFormat.spoken(event, isTomorrow: isTomorrow, isNext: isNext))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { CalendarAppLink.open(event) }
        .accessibilityActions {
            if let url = event.conferenceURL {
                Button("Join") { openURL(url) }
            }
        }
    }

    private func when(_ time: String, countdown: Bool) -> some View {
        HStack(spacing: 5) {
            Text(time)
                .font(Desvan.Typeface.figure(metrics.rowTime, weight: .medium))
                .foregroundStyle(isRunning ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
            if countdown, !event.isAllDay {
                Text(verbatim: "·")
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                Text(DesvanEventFormat.countdown(event, isTomorrow: false))
                    .font(Desvan.Typeface.rounded(metrics.rowTime, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isImminent ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var title: some View {
        Text(event.title)
            .font(.system(size: metrics.rowTitle, weight: isNext ? .medium : .regular))
            .foregroundStyle(Desvan.Palette.paper)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func join(_ url: URL) -> some View {
        let help = MeetingLink.provider(for: url).map { String(localized: "Join with \($0.rawValue)") }
            ?? String(localized: "Join the call")
        if joinIsWord {
            Button("Join") { openURL(url) }
                .buttonStyle(DesvanButtonStyle(kind: isImminent ? .primary : .ghost, height: min(height - 8, 30)))
                .help(help)
        } else {
            Button {
                openURL(url)
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(DesvanButtonStyle(kind: isImminent ? .primary : .quiet, height: min(height - 8, 30)))
            .help(help)
            .desvanHitTarget()
        }
    }
}

// MARK: - Summary

/// The month-only layout's header: the chosen day in one line ("Thu 24 · 10:30 Design review +2"). Clicking it
/// shows the day's list.
struct DesvanCalendarDaySummary: View {
    let agenda: DesvanDayAgenda
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // The first event with its title when it fits (the title truncated past a point), else how many.
                ViewThatFits(in: .horizontal) {
                    line(showsEvent: true)
                    line(showsEvent: false)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background {
                Capsule().fill(Desvan.Palette.paper.opacity(isHovering ? 0.09 : 0.04))
                    .overlay { Capsule().strokeBorder(Desvan.Palette.hairline, lineWidth: 0.75) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .desvanHitTarget()
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .help("Show the day (Space)")
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows the day's events")
    }

    private func line(showsEvent: Bool) -> some View {
        HStack(spacing: 6) {
            Text(agenda.shortDay)
                .font(Desvan.Typeface.rounded(12.5, weight: .semibold))
                .foregroundStyle(agenda.kind == .today ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
            if showsEvent, let first = agenda.primary {
                DesvanCalendarSpine(colorHex: first.calendarColorHex, height: 12)
                Text(DesvanEventFormat.shortTime(first))
                    .font(Desvan.Typeface.figure(12, weight: .medium))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
                Text(first.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paper)
                    .frame(maxWidth: 150, alignment: .leading)
                if agenda.tomorrowFirst != nil {
                    DesvanKraftChip(text: "tomorrow")
                } else if agenda.events.count > 1 {
                    Text(verbatim: "+\(agenda.events.count - 1)")
                        .font(Desvan.Typeface.rounded(12, weight: .semibold))
                        .foregroundStyle(Desvan.Palette.paperTertiary)
                }
            } else if !agenda.events.isEmpty {
                Text(DesvanCalendarWords.events(agenda.events.count))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            } else if agenda.tomorrowFirst != nil {
                DesvanKraftChip(text: "tomorrow")
            } else if agenda.isLoaded {
                Text(agenda.kind == .today ? "Nothing left" : "Free")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var accessibilityText: String {
        var parts = [agenda.title, agenda.subtitle, DesvanCalendarWords.events(agenda.events.count)]
        if let first = agenda.tomorrowFirst {
            parts.append(DesvanEventFormat.spoken(first, isTomorrow: true, isNext: true))
        }
        return parts.joined(separator: ", ")
    }
}
