import AppKit
import AltilloDesign
import SwiftUI

/// The calendar tab, in the layout the user picked (Settings › Sections › Calendar, or the options in the tab
/// itself): today's agenda, the month, or the month beside the chosen day's agenda.
///
/// The store only runs while this view is on screen (`start()` / `stop()`), so a hidden calendar costs nothing.
struct DesvanCalendarView: View {
    let model: NotchModel

    private var store: CalendarStore { model.calendar }
    private var settings: AltilloSettings { model.settings }
    private var isDesignScenario: Bool { model.scenario == .openCalendar }

    private var filter: CalendarFilter {
        CalendarFilter(hiddenCalendarIDs: settings.calendarHiddenIDs, showsAllDay: settings.calendarShowsAllDay)
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contextMenu { DesvanCalendarOptions(model: model) }
            .onAppear {
                store.filter = filter
                store.showsSamples = isDesignScenario
                store.start()
            }
            .onDisappear { store.stop() }
            .onChange(of: filter) { _, filter in store.filter = filter }
    }

    @ViewBuilder
    private var content: some View {
        switch settings.calendarStyle {
        case .agenda:
            DesvanCalendarAgenda(model: model)
        case .month, .monthAndAgenda:
            if store.access == .granted || isDesignScenario {
                DesvanCalendarBoard(model: model, style: settings.calendarStyle)
            } else {
                DesvanCalendarAccessNotice(store: store)
            }
        }
    }
}

/// Today's agenda: the next thing on a lit wood card with its countdown and, when the organiser left a link, a
/// "Join" button; everything after it on slim rows below.
private struct DesvanCalendarAgenda: View {
    let model: NotchModel

    @State private var height: CGFloat = 0
    private var metrics: DesvanCalendarMetrics { DesvanCalendarMetrics(height: height, compact: 104, roomy: 180) }

    private var store: CalendarStore { model.calendar }

    /// Real events whenever there are any. A design scenario with an empty (or locked) agenda falls back to samples
    /// so the look can still be reviewed.
    private var events: [CalendarStore.Event] {
        if !store.events.isEmpty { return store.events }
        if model.scenario == .openCalendar { return CalendarStore.Event.samples() }
        return []
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { height = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if let next = events.first {
            agenda(next: next, rest: Array(events.dropFirst()))
        } else if store.access == .granted {
            if store.hasLoaded {
                DesvanModuleNotice(
                    symbol: "checkmark.circle",
                    title: "Nothing else today",
                    message: "Your day is clear. Pull the shutter down whenever you like."
                )
            } else {
                DesvanModuleNotice(symbol: "calendar", title: "Checking your calendar…")
            }
        } else {
            DesvanCalendarAccessNotice(store: store)
        }
    }

    private func agenda(next: CalendarStore.Event, rest: [CalendarStore.Event]) -> some View {
        VStack(spacing: metrics.rowSpacing + 1) {
            DesvanNextEventCard(event: next, isTomorrow: store.isTomorrow, metrics: metrics)
            if rest.isEmpty {
                Text(store.isTomorrow ? "And nothing else tomorrow." : "And that's it for today.")
                    .font(.system(size: metrics.rowTitle))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: metrics.rowSpacing) {
                        ForEach(rest) { event in
                            DesvanEventRow(event: event, metrics: metrics)
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }
}

/// No access yet, or access refused: one invitation, or the way to System Settings.
struct DesvanCalendarAccessNotice: View {
    let store: CalendarStore

    var body: some View {
        switch store.access {
        case .denied:
            DesvanModuleNotice(
                symbol: "calendar.badge.exclamationmark",
                title: "The calendar is closed",
                message: "Altillo can't see your calendar. Give it access in System Settings and open the notch again.",
                actionTitle: "Open Settings"
            ) {
                PrivacySettings.calendars.open()
            }
        case .unknown:
            DesvanModuleNotice(
                symbol: "calendar",
                title: "Shall we look at your calendar?",
                message: "Altillo shows your next event up here. Events never leave your Mac.",
                actionTitle: "Give access"
            ) {
                Task { await store.requestAccess() }
            }
        case .granted:
            DesvanModuleNotice(symbol: "calendar", title: "Checking your calendar…")
        }
    }
}

/// The calendar's options, from its right-click menu and its slider button: layout, all-day events, which
/// calendars. Everything here is also in Settings › Sections.
struct DesvanCalendarOptions: View {
    let model: NotchModel

    var body: some View {
        @Bindable var settings = model.settings
        Picker("Layout", selection: $settings.calendarStyle) {
            ForEach(CalendarStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }
        .pickerStyle(.inline)
        Divider()
        Toggle("Show All-Day Events", isOn: $settings.calendarShowsAllDay)
        Button("Choose Calendars…") { SettingsWindowController.shared.show(tab: .modules) }
        Divider()
        Button("Open Calendar") { CalendarAppLink.openApp() }
    }
}

// MARK: - The next thing

/// The soonest event: a lit card with its countdown and, when there is a meeting link, the button to join.
private struct DesvanNextEventCard: View {
    let event: CalendarStore.Event
    let isTomorrow: Bool
    let metrics: DesvanCalendarMetrics

    @Environment(\.openURL) private var openURL

    /// Close enough that the card lights up: the same "I need you" signal the agents tab uses.
    private var isImminent: Bool {
        let minutes = event.start.timeIntervalSinceNow / 60
        return minutes <= 15
    }

    var body: some View {
        HStack(spacing: 10) {
            DesvanCalendarSpine(colorHex: event.calendarColorHex, height: metrics.nextCardHeight - 18)
            VStack(alignment: .leading, spacing: 2.5 + metrics.roominess) {
                Text(event.title)
                    .font(.system(size: metrics.nextTitle, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(DesvanEventFormat.time(event))
                        .font(Desvan.Typeface.figure(metrics.nextTime, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    if isTomorrow {
                        DesvanKraftChip(text: "tomorrow")
                    }
                    if let location = event.location {
                        Text("·")
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                        Text(location)
                            .font(.system(size: metrics.nextTime))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
            DesvanCountdownBadge(event: event, isTomorrow: isTomorrow)
            if let url = event.conferenceURL {
                Button("Join") { openURL(url) }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 26 + 2 * metrics.roominess))
                    .help(joinHelp(for: url))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: metrics.nextCardHeight)
        .background {
            if isImminent {
                RadialGradient(colors: [Desvan.Palette.bulb.opacity(0.10), .clear],
                               center: .trailing, startRadius: 0, endRadius: 240)
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .desvanCard(radius: 12, glow: isImminent ? Desvan.Palette.bulb.opacity(0.75) : nil)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { CalendarAppLink.open(event) }
        .help("Open in Calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanEventFormat.spoken(event, isTomorrow: isTomorrow, isNext: true))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { CalendarAppLink.open(event) }
        .accessibilityActions {
            if let url = event.conferenceURL {
                Button("Join") { openURL(url) }
            }
        }
    }

    private func joinHelp(for url: URL) -> String {
        guard let provider = MeetingLink.provider(for: url) else { return String(localized: "Join the call") }
        return String(localized: "Join with \(provider.rawValue)")
    }
}

/// Everything after the next one: one slim wood row each.
private struct DesvanEventRow: View {
    let event: CalendarStore.Event
    let metrics: DesvanCalendarMetrics

    @State private var isHovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
            Text(DesvanEventFormat.shortTime(event))
                .font(Desvan.Typeface.figure(metrics.rowTime, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            Text(event.title)
                .font(.system(size: metrics.rowTitle))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let location = event.location {
                Text(location)
                    .font(.system(size: 12))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
            if let url = event.conferenceURL {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "video")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 22))
                .desvanHitTarget()
                .help("Join the call")
                .opacity(isHovering ? 1 : 0.55)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, event.conferenceURL == nil ? 9 : 2)
        .frame(height: metrics.agendaRowHeight)
        .desvanCard(radius: 8, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .onTapGesture { CalendarAppLink.open(event) }
        .help("Open in Calendar")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanEventFormat.spoken(event, isTomorrow: false, isNext: false))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { CalendarAppLink.open(event) }
        .accessibilityActions {
            if let url = event.conferenceURL {
                Button("Join") { openURL(url) }
            }
        }
    }
}

// MARK: - Pieces

/// The calendar's colour, as a painted edge down the side of the card. Never the only signal: the title and the
/// time say everything the colour does.
struct DesvanCalendarSpine: View {
    let colorHex: UInt32
    var height: CGFloat

    var body: some View {
        let tint = Color(hex: colorHex)
        Capsule()
            .fill(LinearGradient(colors: [tint, tint.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .frame(width: 3.5, height: height)
            .overlay(Capsule().strokeBorder(.black.opacity(0.3), lineWidth: 0.5))
            .shadow(color: tint.opacity(0.4), radius: 3)
            .accessibilityHidden(true)
    }
}

/// "en 12 min", refreshed by the store every half minute. Amber when it is about to start, paper otherwise; the
/// words carry the meaning on their own.
struct DesvanCountdownBadge: View {
    let event: CalendarStore.Event
    let isTomorrow: Bool

    var body: some View {
        let text = DesvanEventFormat.countdown(event, isTomorrow: isTomorrow)
        let urgent = !event.isAllDay && event.start.timeIntervalSinceNow <= 15 * 60
        HStack(spacing: 4) {
            Image(systemName: event.isRunning() ? "dot.radiowaves.left.and.right" : "clock")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(Desvan.Typeface.rounded(12, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(urgent ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
        .shadow(color: Desvan.Palette.bulb.opacity(urgent ? 0.45 : 0), radius: 5)
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// A small kraft label, for "tomorrow".
struct DesvanKraftChip: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(Desvan.Palette.ink)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(Desvan.Palette.kraft))
            .fixedSize()
    }
}

// MARK: - Words

/// Compact, and the same wording VoiceOver reads.
enum DesvanEventFormat {
    /// "10:30 – 11:15", or "all day".
    static func time(_ event: CalendarStore.Event) -> String {
        guard !event.isAllDay else { return String(localized: "all day") }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return String(localized: "\(start) – \(end)")
    }

    /// Just the start, for the slim rows.
    static func shortTime(_ event: CalendarStore.Event) -> String {
        event.isAllDay ? String(localized: "all day") : event.start.formatted(date: .omitted, time: .shortened)
    }

    /// "now", "in 12 min", "tomorrow".
    static func countdown(_ event: CalendarStore.Event, isTomorrow: Bool, now: Date = .now) -> String {
        if event.isAllDay { return isTomorrow ? String(localized: "tomorrow") : String(localized: "today") }
        if event.isRunning(at: now) { return String(localized: "now") }
        if isTomorrow { return String(localized: "tomorrow") }
        return String(localized: "in \(NotchFormat.countdown(to: event.start, now: now))")
    }

    /// One sentence for VoiceOver: no colour, no layout, just what is happening and when.
    static func spoken(_ event: CalendarStore.Event, isTomorrow: Bool, isNext: Bool, now: Date = .now) -> String {
        var parts: [String] = []
        if isNext { parts.append(String(localized: "Up next:")) }
        parts.append(event.title)
        parts.append(time(event))
        parts.append(countdown(event, isTomorrow: isTomorrow, now: now))
        if let location = event.location { parts.append(String(localized: "at \(location)")) }
        if event.conferenceURL != nil { parts.append(String(localized: "with a link to join")) }
        return parts.joined(separator: ", ")
    }
}
