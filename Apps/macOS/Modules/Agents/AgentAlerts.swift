import AltilloCore
import Foundation

/// Which peek a session's change deserves (PLAN §5.8): a permission asked ("Knock, knock"), a question, a
/// finished turn. Pure, so the hub calls it on every transition and tests pin the wording. STUB: the agents UI
/// work fills it in; until then nothing peeks.
enum AgentAlerts {
    /// `previous` is nil for a session seen for the first time.
    static func alert(from previous: AltilloCore.AgentSession?, to current: AltilloCore.AgentSession) -> NotchAlert? {
        nil
    }
}
