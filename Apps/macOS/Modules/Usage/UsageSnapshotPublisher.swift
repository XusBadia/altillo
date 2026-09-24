import AltilloCore
import Foundation

/// Something that sends each fresh usage snapshot elsewhere: the legacy `openusage.mobile.v1` file for the old
/// iPhone app today, CloudKit for Altillo on iOS later (phase 5). Called on the main actor after every refresh
/// batch; implementations debounce and do their I/O off the main actor.
@MainActor
protocol UsageSnapshotPublisher: AnyObject {
    /// Whether it can publish at all on this build/Mac (entitlements, settings).
    var isEnabled: Bool { get }
    func publish(_ snapshot: UsageSnapshot)
}
