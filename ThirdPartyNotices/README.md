# Third-party notices

Altillo is [MIT licensed](../LICENSE) and is written from scratch. To keep it
that way, this file states the policy for reusing other people's code, and
tracks every case where Altillo actually does.

## Policy

- **Only MIT, Apache-2.0, or BSD-licensed code may be reused**, and only with
  a clear, per-file attribution added below (and normally a comment at the
  top of the file that reused the code, pointing back to the source).
- **GPL-licensed projects are reference-only.** We read them to understand
  how a problem was solved, and to avoid known bugs, but we do not copy code
  from them, even in modified form. This currently applies to
  [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3),
  [Ice](https://github.com/jordanbaird/Ice) (GPL-3),
  [Thaw](https://github.com/thaw-menu-bar/thaw) (GPL-3),
  [MewNotch](https://github.com/mewnotch/MewNotch) (GPL-3), and
  [Atoll](https://github.com/MrPenguin4/Atoll) (GPL-3, fork of boring.notch).
  See [docs/investigacion.md](../docs/investigacion.md) for what was learned
  from each.
- Before reusing anything, double-check the upstream project's current
  license and any trademark/branding restrictions (e.g. OpenUsage's
  `TRADEMARK.md`, which reserves the name "OpenUsage" for the upstream
  project — Altillo may say it is "compatible with OpenUsage" but must not use
  the name as its own product name or imply affiliation).
- When reused code is later rewritten enough that nothing recognizable
  remains, its row here can be marked accordingly, but the entry stays for
  history rather than being deleted.

## Reused code

Fill in a row whenever a PR reuses or adapts MIT/Apache/BSD code, and keep
it accurate as code changes. Adapted files carry a header comment pointing
back to the source.

| Source project | License | What was reused | Where in Altillo | PR / commit |
|---|---|---|---|---|
| [OpenUsage](https://github.com/robinebers/openusage) (© 2026 Robin Ebers) | MIT | Claude usage mapping (windows, `limits[]` weekly_scoped entries, extra usage in cents, plan formatting, `Retry-After` parsing), keychain lookup order / `CLAUDE_CONFIG_DIR` service suffix / hex-encoded value fallback | `Packages/AltilloKit/Sources/AltilloUsage/ClaudeCollector.swift`, `ClaudeCredentials.swift` | phase 3 (usage collectors) |
| [OpenUsage](https://github.com/robinebers/openusage) (© 2026 Robin Ebers) | MIT | Codex window classification by duration, plan naming, `wham/usage` mapping | `Packages/AltilloKit/Sources/AltilloUsage/CodexCollector.swift` | phase 3 |
| [OpenUsage](https://github.com/robinebers/openusage) (© 2026 Robin Ebers) | MIT | Alert rules from `MobileQuotaNotificationEvaluator` and `PaceNotificationLogic` (baseline, once per window, highest crossed threshold, reset jitter tolerance, inferred reset) | `Packages/AltilloKit/Sources/AltilloCore/UsageAlerts.swift` | phase 3 |
| [OpenUsage](https://github.com/robinebers/openusage) (© 2026 Robin Ebers) | MIT | Pace projection (`UsagePace`) | `Packages/AltilloKit/Sources/AltilloCore/Usage.swift` | 2c906af |
| [ai-limits](https://github.com/XusBadia/ai-limits) (© 2026 Xus Badia) | MIT | `codex app-server` JSON-RPC handshake and rate-limit result mapping | `Packages/AltilloKit/Sources/AltilloUsage/CodexAppServer.swift`, `CodexCollector.swift` | phase 3 |

| [OpenUsage](https://github.com/robinebers/openusage) (© 2026 Robin Ebers) | MIT | Provider knowledge for Cursor (SQLite/keychain credentials, Connect RPC + REST usage mapping), GitHub Copilot (token sources, `copilot_internal/user` quota mapping), OpenRouter and Z.ai (key locations, credits/quota mapping), Grok (billing/settings mapping), Gemini/Antigravity (language-server discovery, quota summary mapping), Devin (credentials, `GetUserStatus` mapping) and OpenCode (Go usage mapping); shared key-file and parsing helpers | `Packages/AltilloKit/Sources/AltilloUsage/{Cursor*,Copilot*,OpenRouter*,ZAI*,Grok*,Gemini*,Devin*,OpenCode*}.swift`, `ProviderSupport+Group1.swift`, `ProviderSupport+Group2.swift` | independence round (24-09-2026), fork commit 87c3d2d |

Altillo reads every provider itself, with the credentials the providers' own
tools already keep on the Mac; it never reads another app's data or API.
OpenUsage is used only as a reference for how each provider works, and its
upstream changes are tracked in `script/openusage-upstream.json`
(`docs/proveedores.md`).

Planned reuse (per [PLAN.md](../PLAN.md)), to be filled in as it lands:

- [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT) — shelf drag/drop
  and window techniques.
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) — notch
  window/shape reference.
- [OpenUsage](https://github.com/robinebers/openusage) (MIT) — provider
  mappers, pacing calculation, alert thresholds.
