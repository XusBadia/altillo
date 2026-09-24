import AltilloCore
import Foundation

/// Reads one provider's usage on this Mac (PLAN §5.2). Implementations never throw: every failure becomes a
/// `ProviderUsage.problem` the notch can explain, and they never refresh or rewrite another tool's credentials.
public protocol UsageCollector: Sendable {
    var providerID: UsageProviderID { get }
    var displayName: String { get }
    /// Cheap check (files/binaries exist), no network: is there anything to read at all?
    func isAvailable() async -> Bool
    /// One read. `previous` holds the last good numbers so a failure can keep them (stale-while-revalidate).
    func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage
}

/// Collectors Altillo ships with, in display order. Providers it doesn't read natively can come from
/// `OpenUsageCompatibleSource` (a separate, optional source).
public enum UsageCollectors {
    public static func all() -> [any UsageCollector] {
        [ClaudeCollector(), CodexCollector()]
    }
}
