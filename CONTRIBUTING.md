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
