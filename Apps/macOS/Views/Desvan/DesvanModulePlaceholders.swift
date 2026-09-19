import SwiftUI

// STUBS for the new modules (calendar, mirror, now playing). Replaced by the modules work; keep these names.

struct DesvanCalendarView: View {
    let model: NotchModel
    var body: some View { DesvanModulePlaceholder(module: .calendar) }
}

struct DesvanMirrorView: View {
    let model: NotchModel
    var body: some View { DesvanModulePlaceholder(module: .mirror) }
}

struct DesvanNowPlayingView: View {
    let model: NotchModel
    var body: some View { DesvanModulePlaceholder(module: .nowPlaying) }
}

private struct DesvanModulePlaceholder: View {
    let module: NotchModule

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: module.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperTertiary)
            Text(module.explanation)
                .font(Desvan.Typeface.rounded(11.5, weight: .medium))
                .foregroundStyle(Desvan.Palette.paperSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
