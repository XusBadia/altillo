import AppKit

/// Force Touch trackpad feedback. Quiet by design: one tap when something snaps into place (a section change by
/// swiping, a thing landing on the shelf, the notch opening under the finger). Does nothing on a mouse, or when the
/// user turned haptics off in Settings.
@MainActor
enum Haptics {
    enum Pattern: Sendable {
        /// Something snapped into place: a swipe changed section, an alert appeared.
        case snap
        /// A level was crossed: a thing landed on the shelf, the notch opened.
        case land

        var feedback: NSHapticFeedbackManager.FeedbackPattern {
            switch self {
            case .snap: .alignment
            case .land: .levelChange
            }
        }
    }

    static func perform(_ pattern: Pattern, enabled: Bool = AltilloSettings.shared.hapticsEnabled) {
        guard enabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern.feedback, performanceTime: .now)
    }
}
