import AltilloCore
import AltilloUsage
import Foundation

/// Production catalog: Claude and Codex use only sessions explicitly connected to Altillo.
enum UsageAccountCollectors {
    static func all(session: UsageAccountSession = .shared) -> [any UsageCollector] {
        [
            ClaudeCollector(credentials: UsageAccountClaudeReader(session: session),
                            availability: { await session.hasAccount(.claude) }, usesOwnAccount: true,
                            refreshAfterUnauthorized: {
                                _ = try await session.claudeCredentials(now: .now, forceRefresh: true)
                            }),
            CodexCollector(accountAuth: { try await session.codexAuth(now: $0) },
                           availability: { await session.hasAccount(.codex) },
                           refreshAfterUnauthorized: {
                               _ = try await session.codexAuth(now: .now, forceRefresh: true)
                           }),
            CursorCollector(), CopilotCollector(), GeminiCollector(), GrokCollector(), ZAICollector(),
            DevinCollector(), OpenCodeCollector(),
        ]
    }
}

private struct UsageAccountClaudeReader: ClaudeCredentialReading {
    let session: UsageAccountSession
    func read(now: Date) async -> ClaudeCredentialLookup {
        do {
            guard let value = try await session.claudeCredentials(now: now) else { return .notFound }
            return .found(value)
        } catch UsageAuthorizationError.sessionExpired { return .sessionExpired }
        catch UsageAuthorizationError.accessDenied { return .accessDenied }
        catch { return .temporarilyUnavailable }
    }
}
