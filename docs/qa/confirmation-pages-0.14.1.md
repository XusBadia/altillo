# Altillo 0.14.1 publication verification

Verified on 11 November 2026.

- Source and release tag: `129237d635aed6e253778183dfcf8f798ae48520`.
- Version/build: **0.14.1 (223)**; universal `arm64` and `x86_64`.
- [Exact-source CI](https://github.com/XusBadia/altillo/actions/runs/43014446660): all six jobs passed (AltilloKit, macOS and Spanish localization, iOS simulator, website/Playwright, secret scan, publication guards).
- Local validation: complete AltilloKit suite passed, with optional live-account/lab suites skipped; 49 UsageAccount/UsageStore tests passed. The browser harness passed 64 combinations of state, language, appearance and viewport plus two polling transitions.
- The exported app bundles the exact official icon from `website/public/altillo-icon.png`; its Sparkle feed is `https://altillo.app/appcast.xml`.
- Developer ID signing, Apple notarization and stapling succeeded for the app and DMG. The release script mounted the DMG, verified signatures and embedded code, passed Gatekeeper, and confirmed the mounted app stayed alive.
- [Public release](https://github.com/XusBadia/altillo/releases/tag/v0.14.1): published, stable, with `Altillo-0.14.1.dmg` (18,348,009 bytes).
- The public download checksum matches the tested local DMG: `a206a173f4078e12961a1e9137eaa7c2746d8f40fefece6f617ab4ed374c9524`. The repository Homebrew cask records this version and checksum.
- The public feed at both altillo.app and GitHub Pages offers 0.14.1 (223), retains older entries and names the correct GitHub download. Sparkle's `sign_update --verify` accepted the enclosure signature; the signing account's public key matches the key embedded in the app.

No installed-app Sparkle upgrade was exercised during this publication. The tested DMG, public transport checksum, signed enclosure and live feed were verified; this does not claim an interactive upgrade was performed.
