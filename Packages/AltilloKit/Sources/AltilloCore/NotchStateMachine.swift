/// Visual states of the notch. See PLAN.md §4 ("Máquina de estados del notch").
public enum NotchState: String, Sendable, CaseIterable {
    /// Only the hardware notch (or nothing) is visible; mouse events pass through.
    case idle
    /// Slightly grown, showing a one-line summary or an alert.
    case peek
    /// A drag with droppable content is in progress somewhere on screen.
    case dragArmed
    /// The drag is close to the notch: the shelf is open and highlighted as a drop zone.
    case dropTarget
    /// Fully open, showing the active tab.
    case open

    /// Whether the panel must receive mouse events in this state.
    public var isInteractive: Bool { self != .idle }
}

/// Inputs to the state machine. Timing (dwell, grace periods) lives in the caller, which reports elapsed timers as events.
public enum NotchEvent: Sendable, Equatable {
    /// The pointer has rested on the notch for the short dwell (~80 ms).
    case hoverIntent
    /// The pointer has rested on the notch (or the peek) for the long dwell (~300 ms).
    case hoverSustained
    case click
    /// The pointer left the notch area.
    case pointerLeft
    /// The pointer was outside for the whole close grace period (~400 ms).
    case closeGraceElapsed
    /// A drag carrying files, URLs or text started outside Altillo.
    case dragBegan
    /// The drag moved; `near` is true when it is within the activation distance of the notch.
    case dragMoved(near: Bool)
    /// The drag finished; `dropped` is true when it was dropped on Altillo.
    case dragEnded(dropped: Bool)
    /// Something worth a glance happened (usage threshold, agent waiting…).
    case alert
    /// The alert peek has been on screen long enough.
    case alertExpired
    case escape
}

public struct NotchStateMachine: Sendable {
    public private(set) var state: NotchState
    /// Open the notch on a sustained hover instead of requiring a click.
    public var opensOnHover: Bool
    /// True while the pointer is over the notch area, so alerts and grace periods don't close it under the cursor.
    public private(set) var isPointerInside = false

    public init(state: NotchState = .idle, opensOnHover: Bool = true) {
        self.state = state
        self.opensOnHover = opensOnHover
    }

    /// Applies an event and returns whether the state changed.
    @discardableResult
    public mutating func handle(_ event: NotchEvent) -> Bool {
        let previous = state
        state = next(for: event)
        return state != previous
    }

    private mutating func next(for event: NotchEvent) -> NotchState {
        switch (state, event) {
        case (_, .escape):
            return .idle

        case (.idle, .hoverIntent):
            isPointerInside = true
            return .peek
        case (.peek, .hoverIntent), (.open, .hoverIntent):
            isPointerInside = true
            return state
        case (.peek, .hoverSustained):
            return opensOnHover ? .open : .peek
        case (.idle, .click), (.peek, .click):
            isPointerInside = true
            return .open

        case (_, .pointerLeft):
            isPointerInside = false
            return state == .peek ? .idle : state
        case (.open, .closeGraceElapsed):
            return isPointerInside ? .open : .idle

        case (.idle, .dragBegan), (.peek, .dragBegan):
            return .dragArmed
        case (.open, .dragBegan):
            return .dropTarget
        case (.dragArmed, .dragMoved(near: true)):
            return .dropTarget
        case (.dropTarget, .dragMoved(near: false)):
            return .dragArmed
        case (.dropTarget, .dragEnded(dropped: true)):
            return .open
        case (.dragArmed, .dragEnded), (.dropTarget, .dragEnded(dropped: false)):
            return .idle

        case (.idle, .alert):
            return .peek
        case (.peek, .alertExpired):
            return isPointerInside ? .peek : .idle

        default:
            return state
        }
    }
}
