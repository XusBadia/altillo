import AltilloCore
import Foundation

/// Reads one provider's usage on this Mac (PLAN §5.2). Implementations never throw: every failure becomes a
/// `ProviderUsage.problem` the notch can explain, and they never refresh or rewrite another tool's credentials.
///
/// Altillo reads each provider directly. The macOS catalog supplies app-owned Claude/Codex sessions; legacy
/// adapters remain available for explicit integrations and other providers' local sessions or keys.
/// It never depends on another usage app being installed.
public protocol UsageCollector: Sendable {
    var providerID: UsageProviderID { get }
    var displayName: String { get }
    /// One short English sentence telling someone who hasn't set this provider up how to (Settings shows it under
    /// "Not set up on this Mac"): "Sign in to Cursor", "Install GitHub Copilot in your editor". Has a default.
    var setupHint: String { get }
    /// Cheap check (files/binaries exist), no network: is there anything to read at all?
    func isAvailable() async -> Bool
    /// One read. `previous` holds the last good numbers so a failure can keep them (stale-while-revalidate).
    func fetch(previous: ProviderUsage?, now: Date) async -> ProviderUsage
}

public extension UsageCollector {
    var setupHint: String { "Sign in to \(displayName) on this Mac" }
}

/// Collectors Altillo ships with, in display order.
public enum UsageCollectors {
    public static func all() -> [any UsageCollector] {
        [
            ClaudeCollector(), CodexCollector(), CursorCollector(), CopilotCollector(), GeminiCollector(),
            GrokCollector(), ZAICollector(), DevinCollector(), OpenCodeCollector(),
        ]
    }
}
