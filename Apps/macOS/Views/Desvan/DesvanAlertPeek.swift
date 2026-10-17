import AppKit
import SwiftUI

// The live alert peek (`NotchAlert`): one sentence under the notch, the source's symbol in the left ear and a figure
// in the right one. Sober on purpose: the bulb only lights the symbol when something needs you.

/// Left ear: the alert's symbol, lit by the bulb when it's urgent.
struct DesvanAlertSymbol: View {
    let alert: NotchAlert
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: alert.symbol)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(alert.isUrgent ? Desvan.Palette.bulb : Desvan.Palette.paper)
            .shadow(color: Desvan.Palette.bulb.opacity(alert.isUrgent ? 0.55 : 0), radius: 4)
            .symbolEffect(.bounce.down, options: .nonRepeating, value: reduceMotion ? nil : alert.id)
            .accessibilityHidden(true)
    }
}

/// Right ear: a short figure ("in 5 min", "3:41").
struct DesvanAlertFigure: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Desvan.Typeface.rounded(12, weight: .semibold))
            .foregroundStyle(Desvan.Palette.paperSecondary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// The sentence: the title in paper, the detail dimmer, and (on the island, which has no right ear) the figure.
/// A doorbell's ring leads with the camera's picture once it has arrived.
struct DesvanAlertLine: View {
    let alert: NotchAlert
    var showsTrailing: Bool
    var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 6) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Desvan.Palette.hairlineStrong, lineWidth: 0.5)
                    }
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
            Text(alert.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Desvan.Palette.paper)
                .layoutPriority(1)
            if let detail = alert.detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Desvan.Palette.paperSecondary)
            }
            Spacer(minLength: 8)
            if showsTrailing, let trailing = alert.trailing {
                DesvanAlertFigure(text: trailing)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .animation(.easeOut(duration: 0.25), value: thumbnail != nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([alert.title, alert.detail, alert.trailing].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

extension NotchAlert {
    /// The peek shown by the "Peek: meeting about to start" design scenario.
    static let demoMeeting = NotchAlert(
        source: .calendar,
        symbol: "calendar",
        title: String(localized: "Product sync"),
        detail: String(localized: "with Ana and Luis"),
        trailing: String(localized: "in 5 min"),
        isUrgent: true,
        module: .calendar
    )
}
