import SwiftUI

/// The contextual ear while a timer runs: a small timer glyph and what's left ("12m", then "0:42" in the last
/// minute), or a ringing bell once it has gone off.
///
/// Cheap on purpose (PLAN §1.5): the text only redraws when it changes, once a minute while there's more than a
/// minute left and once a second in the last one (`DesvanTimerCountdownSchedule`). Nothing ticks unseen.
struct DesvanTimerEar: View {
    let signal: TimerSignal

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: signal.isRinging ? "bell.fill" : "timer")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(signal.isImminent || signal.isRinging ? Desvan.Palette.bulb : Desvan.Palette.paper)
                .shadow(color: Desvan.Palette.bulb.opacity(signal.isRinging ? 0.6 : 0), radius: 4)
                .symbolEffect(.wiggle, options: .repeat(3), value: reduceMotion ? false : signal.isRinging)
            if !signal.isRinging {
                TimelineView(DesvanTimerCountdownSchedule(end: signal.endsAt)) { context in
                    Text(TimerFormat.ear(max(0, signal.endsAt.timeIntervalSince(context.date))))
                        .font(Desvan.Typeface.figure(12.5, weight: .medium))
                        .foregroundStyle(signal.isImminent ? Desvan.Palette.bulb : Desvan.Palette.paper)
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        }
        .fixedSize()
    }
}

/// Redraws a countdown only when its text changes: at every whole minute before `end` while more than a minute is
/// left, then every second, then never again.
struct DesvanTimerCountdownSchedule: TimelineSchedule {
    let end: Date

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(end: end, upcoming: startDate)
    }

    struct Entries: Sequence, IteratorProtocol {
        let end: Date
        var upcoming: Date?

        mutating func next() -> Date? {
            guard let current = upcoming else { return nil }
            let remaining = end.timeIntervalSince(current)
            if remaining <= 0 {
                upcoming = nil
            } else if remaining > 60 {
                // The next whole minute before the end (the text reads minutes rounded up).
                let minutes = (remaining / 60).rounded(.up) - 1
                upcoming = end.addingTimeInterval(-minutes * 60)
            } else {
                let seconds = remaining.rounded(.up) - 1
                upcoming = end.addingTimeInterval(-seconds)
            }
            return current
        }
    }
}
