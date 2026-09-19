import AppKit
import AltilloDesign
import SwiftUI

/// The agenda tab: what is left of today. The next thing sits on a lit wood card with its countdown and, when the
/// organiser left a link, a "Unirse" button; everything after it goes on slim rows below.
///
/// The store only runs while this view is on screen (`start()` / `stop()`), so a hidden agenda costs nothing.
struct DesvanCalendarView: View {
    let model: NotchModel

    private var store: CalendarStore { model.calendar }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { store.start() }
            .onDisappear { store.stop() }
    }

    /// Real events whenever there are any. A design scenario with an empty (or locked) agenda falls back to samples
    /// so the look can still be reviewed.
    private var events: [CalendarStore.Event] {
        if !store.events.isEmpty { return store.events }
        if model.scenario == .openCalendar { return CalendarStore.Event.samples() }
        return []
    }

    @ViewBuilder
    private var content: some View {
        if let next = events.first {
            agenda(next: next, rest: Array(events.dropFirst()))
        } else {
            notice
        }
    }

    private func agenda(next: CalendarStore.Event, rest: [CalendarStore.Event]) -> some View {
        VStack(spacing: 5) {
            DesvanNextEventCard(event: next, isTomorrow: store.isTomorrow)
            if rest.isEmpty {
                Text(store.isTomorrow ? "Y nada más mañana." : "Y ya está por hoy.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Desvan.Palette.paperTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(rest) { event in
                            DesvanEventRow(event: event)
                        }
                    }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    @ViewBuilder
    private var notice: some View {
        switch store.access {
        case .denied:
            DesvanModuleNotice(
                symbol: "calendar.badge.exclamationmark",
                title: "La agenda está cerrada",
                message: "Altillo no puede ver tu calendario. Dale acceso en Ajustes del Sistema y vuelve a abrir el notch.",
                actionTitle: "Abrir Ajustes"
            ) {
                PrivacySettings.calendars.open()
            }
        case .unknown:
            DesvanModuleNotice(
                symbol: "calendar",
                title: "¿Miramos tu agenda?",
                message: "Altillo enseña aquí tu próximo evento. Los eventos no salen de tu Mac.",
                actionTitle: "Dar acceso"
            ) {
                Task { await store.requestAccess() }
            }
        case .granted:
            if store.hasLoaded {
                DesvanModuleNotice(
                    symbol: "checkmark.circle",
                    title: "Nada más por hoy",
                    message: "Tu agenda está limpia. Baja la persiana cuando quieras."
                )
            } else {
                DesvanModuleNotice(symbol: "calendar", title: "Mirando la agenda…")
            }
        }
    }
}

// MARK: - The next thing

/// The soonest event: a lit card with its countdown and, when there is a meeting link, the button to join.
private struct DesvanNextEventCard: View {
    let event: CalendarStore.Event
    let isTomorrow: Bool

    @Environment(\.openURL) private var openURL

    /// Close enough that the card lights up: the same "I need you" signal the agents tab uses.
    private var isImminent: Bool {
        let minutes = event.start.timeIntervalSinceNow / 60
        return minutes <= 15
    }

    var body: some View {
        HStack(spacing: 10) {
            DesvanCalendarSpine(colorHex: event.calendarColorHex, height: 28)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(event.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Desvan.Palette.paper)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(DesvanEventFormat.time(event))
                        .font(Desvan.Typeface.figure(11.5, weight: .medium))
                        .foregroundStyle(Desvan.Palette.paperSecondary)
                    if isTomorrow {
                        DesvanKraftChip(text: "mañana")
                    }
                    if let location = event.location {
                        Text("·")
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                        Text(location)
                            .font(.system(size: 11))
                            .foregroundStyle(Desvan.Palette.paperTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer(minLength: 8)
            DesvanCountdownBadge(event: event, isTomorrow: isTomorrow)
            if let url = event.conferenceURL {
                Button("Unirse") { openURL(url) }
                    .buttonStyle(DesvanButtonStyle(kind: .primary, height: 24))
                    .help(joinHelp(for: url))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 46)
        .background {
            if isImminent {
                RadialGradient(colors: [Desvan.Palette.bulb.opacity(0.10), .clear],
                               center: .trailing, startRadius: 0, endRadius: 240)
                    .blendMode(.plusLighter)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .desvanCard(radius: 12, glow: isImminent ? Desvan.Palette.bulb.opacity(0.75) : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanEventFormat.spoken(event, isTomorrow: isTomorrow, isNext: true))
    }

    private func joinHelp(for url: URL) -> String {
        guard let provider = MeetingLink.provider(for: url) else { return "Unirse a la llamada" }
        return "Unirse por \(provider.rawValue)"
    }
}

/// Everything after the next one: one slim wood row each.
private struct DesvanEventRow: View {
    let event: CalendarStore.Event

    @State private var isHovering = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: event.calendarColorHex))
                .frame(width: 6, height: 6)
                .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
            Text(DesvanEventFormat.shortTime(event))
                .font(Desvan.Typeface.figure(11, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
            Text(event.title)
                .font(.system(size: 11.5))
                .foregroundStyle(Desvan.Palette.paper)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let location = event.location {
                Text(location)
                    .font(.system(size: 10.5))
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
                        .font(.system(size: 10.5, weight: .medium))
                }
                .buttonStyle(DesvanButtonStyle(kind: .quiet, height: 20))
                .help("Unirse a la llamada")
                .opacity(isHovering ? 1 : 0.55)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, event.conferenceURL == nil ? 9 : 2)
        .frame(height: 24)
        .desvanCard(radius: 8, fill: isHovering ? Desvan.Palette.woodRaised : Desvan.Palette.wood)
        .onHover { hovering in withAnimation(Desvan.Motion.hover) { isHovering = hovering } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DesvanEventFormat.spoken(event, isTomorrow: false, isNext: false))
    }
}

// MARK: - Pieces

/// The calendar's colour, as a painted edge down the side of the card. Never the only signal: the title and the
/// time say everything the colour does.
private struct DesvanCalendarSpine: View {
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
private struct DesvanCountdownBadge: View {
    let event: CalendarStore.Event
    let isTomorrow: Bool

    var body: some View {
        let text = DesvanEventFormat.countdown(event, isTomorrow: isTomorrow)
        let urgent = !event.isAllDay && event.start.timeIntervalSinceNow <= 15 * 60
        HStack(spacing: 4) {
            Image(systemName: event.isRunning() ? "dot.radiowaves.left.and.right" : "clock")
                .font(.system(size: 9.5, weight: .semibold))
            Text(text)
                .font(Desvan.Typeface.rounded(11.5, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(urgent ? Desvan.Palette.bulb : Desvan.Palette.paperSecondary)
        .shadow(color: Desvan.Palette.bulb.opacity(urgent ? 0.45 : 0), radius: 5)
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// A small kraft label, for "mañana".
struct DesvanKraftChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Desvan.Typeface.rounded(9.5, weight: .semibold))
            .foregroundStyle(Desvan.Palette.ink)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(Capsule().fill(Desvan.Palette.kraft))
            .fixedSize()
    }
}

// MARK: - Words

/// Spanish, compact, and the same wording VoiceOver reads.
enum DesvanEventFormat {
    /// "10:30 – 11:15", or "todo el día".
    static func time(_ event: CalendarStore.Event) -> String {
        guard !event.isAllDay else { return "todo el día" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }

    /// Just the start, for the slim rows.
    static func shortTime(_ event: CalendarStore.Event) -> String {
        event.isAllDay ? "todo el día" : event.start.formatted(date: .omitted, time: .shortened)
    }

    /// "ahora", "en 12 min", "mañana".
    static func countdown(_ event: CalendarStore.Event, isTomorrow: Bool, now: Date = .now) -> String {
        if event.isAllDay { return isTomorrow ? "mañana" : "hoy" }
        if event.isRunning(at: now) { return "ahora" }
        if isTomorrow { return "mañana" }
        return "en \(NotchFormat.countdown(to: event.start, now: now))"
    }

    /// One sentence for VoiceOver: no colour, no layout, just what is happening and when.
    static func spoken(_ event: CalendarStore.Event, isTomorrow: Bool, isNext: Bool, now: Date = .now) -> String {
        var parts: [String] = []
        if isNext { parts.append("Lo siguiente:") }
        parts.append(event.title)
        parts.append(time(event))
        parts.append(countdown(event, isTomorrow: isTomorrow, now: now))
        if let location = event.location { parts.append("en \(location)") }
        if event.conferenceURL != nil { parts.append("con enlace para unirse") }
        return parts.joined(separator: ", ")
    }
}
