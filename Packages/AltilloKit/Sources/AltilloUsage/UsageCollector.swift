import AltilloCore
import Foundation

/// Reads one provider's usage on this Mac (PLAN §5.2). Implementations never throw: every failure becomes a
/// `ProviderUsage.problem` the notch can explain, and they never refresh or rewrite another tool's credentials.
///
/// Altillo reads every provider itself, from what that provider's own tools already keep on this Mac (a CLI's
/// sign-in, an editor's session, an API key the user adds). It never depends on another usage app being installed.
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
            GrokCollector(), OpenRouterCollector(), ZAICollector(), DevinCollector(), OpenCodeCollector(),
        ]
    }
}

// The CLIs whose sign-in Altillo reads for the two built-in providers.
public extension ClaudeCollector {
    var setupHint: String { "Sign in to Claude Code on this Mac" }
}

public extension CodexCollector {
    var setupHint: String { "Sign in to the Codex CLI on this Mac" }
}
