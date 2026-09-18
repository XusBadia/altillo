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

_Empty for now — Altillo hasn't reused any third-party code yet. Fill in a row
below whenever a PR reuses or adapts MIT/Apache/BSD code, and keep it
accurate as code changes._

| Source project | License | What was reused | Where in Altillo | PR / commit |
|---|---|---|---|---|
| _none yet_ | | | | |

Planned reuse (per [PLAN.md](../PLAN.md)), to be filled in as it lands:

- [NotchDrop](https://github.com/Lakr233/NotchDrop) (MIT) — shelf drag/drop
  and window techniques.
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) (MIT) — notch
  window/shape reference.
- [OpenUsage](https://github.com/robinebers/openusage) (MIT) — provider
  mappers, pacing calculation, alert thresholds.
