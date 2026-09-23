# Contributing to Altillo

Altillo is early-stage (phase 0) — see [PLAN.md](PLAN.md) for the full plan,
principles, and roadmap before diving in. If you're unsure whether something
fits, open an issue first.

## Setup

Requirements: macOS 26+, [Xcode 26+](https://developer.apple.com/xcode/),
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
git clone https://github.com/<org>/altillo.git
cd altillo
xcodegen generate
open Altillo.xcodeproj
```

No Apple Developer account is required: without `Config/Local.xcconfig`, the
project builds with ad-hoc signing and bundle prefix `dev.altillo` (see
[Config/Local.xcconfig.example](Config/Local.xcconfig.example) if you do have
a team and want iCloud sync / push notifications / a physical device).

Day-to-day development notes (running the app, design review scenarios, logs)
are in [docs/desarrollo.md](docs/desarrollo.md) (Spanish).

## Conventions

- **Swift 6, strict concurrency.** `project.yml` sets
  `SWIFT_STRICT_CONCURRENCY: complete` for every target — new code must build
  cleanly under strict concurrency, not opt out of it.
- **XcodeGen owns the project file.** `Altillo.xcodeproj` is generated from
  `project.yml` and is git-ignored. **Never commit it.** If you add, remove,
  or move source files or targets, edit `project.yml` (and `Config/*.xcconfig`
  if it's a build setting) and run `xcodegen generate` — don't hand-edit
  project settings in Xcode's UI, since those changes won't survive
  regeneration.
- **Commit style: [Conventional Commits](https://www.conventionalcommits.org/).**
  e.g. `feat(shelf): support multi-item drag out`,
  `fix(notch): don't reopen during the grace period`,
  `docs: add CI workflow`. Keep commits scoped and the subject line under
  ~72 characters.
- **UX checklist.** Any change to user-facing behavior should pass the
  checklist in [PLAN.md §4](PLAN.md#4-ux-y-personalización) before it's
  considered done:
  - Discoverable without reading anything.
  - Responds in < 100 ms to the intention.
  - Has empty, loading, error, and stale states.
  - Undoable where relevant (⌘Z).
  - Works with keyboard.
  - Works with VoiceOver.
  - Respects Reduce Motion and Reduce Transparency.
  New visual states should start as a SwiftUI Preview with fake data (see
  `DesignScenario` in `Apps/macOS/Notch/DesignScenario.swift`) before they're
  wired to real logic.
- **Reusing third-party code.** Only MIT/Apache/BSD-licensed code may be
  reused, always with attribution in
  [ThirdPartyNotices/README.md](ThirdPartyNotices/README.md). GPL projects
  (boring.notch, Ice, Thaw, MewNotch, Atoll) are reference-only — read them
  for ideas, never copy code from them. See that file for the full policy.

## Localization

Altillo ships in **English** (source language) and **Spanish**. Translations live
in String Catalogs, not in the code:

- `Apps/macOS/Resources/Localizable.xcstrings` — the Mac app
- `Apps/iOS/Localizable.xcstrings` — the iOS app
- `Packages/AltilloKit/Sources/AltilloDesign/Resources/Localizable.xcstrings` — AltilloDesign

Write every user-facing string in English, at the call site:

- SwiftUI APIs that take a `LocalizedStringKey` (`Text`, `Button`, `Label`,
  `Toggle`, `.help`, `.accessibilityLabel`, …) localize a string literal on their
  own — leave the literal alone, don't wrap it.
- Anything that produces a `String` for the UI (a computed `title`, a formatter, an
  AppKit window title, an undo action name) needs `String(localized: "…")`. Inside
  AltilloKit, pass the bundle: `String(localized: "…", bundle: .module)`.
- A custom view that renders a `String` with `Text(…)` does **not** localize.
  Give the parameter type `LocalizedStringKey`, or keep `String` and render it
  with `Text(verbatim:)` when the value is already localized upstream.
- Don't invent plural branches in code. Write one interpolated key
  (`String(localized: "\(count) things")`) and add the plural variations to the
  catalog.
- Never localize logs (`SpikeLog`, `os_log`), file paths, keys, bundle IDs,
  AppleScript, SF Symbol names, or the product name "Altillo" on its own.

Building updates the catalogs with newly discovered keys; open them in Xcode to
fill in the Spanish column. To see the app in Spanish without changing your Mac's
language, run it with `-AppleLanguages "(es)"`. The test action is pinned to
English (`project.yml`), so tests assert English output on any machine; to check a
suite in Spanish, run `xcodebuild … -testLanguage es -testRegion ES`.

## Running tests

```sh
# AltilloKit package (models, state machine, geometry)
cd Packages/AltilloKit && swift test

# macOS app (build + unit/UI tests, ad-hoc signed)
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme Altillo \
  -derivedDataPath build/dd test

# iOS app + widget (build for the simulator, no signing required)
xcodegen generate
xcodebuild -project Altillo.xcodeproj -scheme AltilloiOS \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/dd-ios CODE_SIGNING_ALLOWED=NO build
```

CI (`.github/workflows/ci.yml`) runs all three on every push to `main` and on
every pull request.

## Pull requests

- Keep PRs focused; unrelated cleanups belong in a separate PR.
- Fill in the PR template, including the UX checklist if applicable.
- Make sure `xcodegen generate` produces no unexpected diff after your change
  to `project.yml`.
- Don't commit `Config/Local.xcconfig`, `Altillo.xcodeproj`, `build/`, or
  other generated/local files — they're git-ignored on purpose.

## Secrets

Altillo never needs an API key to run, and the repository must never contain one.

- `Config/Local.xcconfig` (team ID, bundle prefix, signing identity, and — only for a maintainer cutting
  a release — the Sparkle public key) is git-ignored. Copy `Config/Local.xcconfig.example` and fill in
  your own values.
- Signing material (`.p8`, `.p12`, `.pem`, `.cer`, `.mobileprovision`, `.provisionprofile`) and `.env` files are git-ignored too.
- The Sparkle EdDSA **private** signing key lives in the login keychain (`generate_keys --account altillo`),
  never on disk or in git; notarization credentials live in a notarytool keychain profile
  (`altillo-notary`). Neither is needed to build or contribute — only to cut a release. See
  [docs/release.md](docs/release.md) (Spanish) for the full release setup and CI secret names.
- The APNs key used for Live Activities (phase 6) is read from the user's Keychain at runtime. It is never bundled, printed or committed.
- Provider credentials (Claude, Codex…) are read from the user's own Keychain/config files and never leave the Mac.
- Run `script/install-git-hooks.sh` once (needs `brew install gitleaks`): it installs a pre-commit hook that refuses to commit a secret. CI runs the same scan over the full history on every push and pull request.

If a secret ever does land in the history, treat it as leaked: rotate it first, then rewrite the history.
