# Altillo brand assets

`AltilloIconMaster-11A.png` is the canonical flattened app-icon artwork for Altillo. The filename stays stable for release and promo consumers; its artwork is the Golden Gate house-glyph redesign generated in September 2026.

`../AppIcon.icon` is the adaptive Icon Composer source used by current versions of macOS and iOS. It uses the generated 1024×1024 Liquid Glass artwork as one optically composed layer so the warm gradient, refraction, highlights, and house proportions survive compilation unchanged; Icon Composer supplies the platform mask and outer system treatment. `../IconLayers` keeps compatibility copies for the promo renderer.

The PNGs in `../Assets.xcassets/AppIcon.appiconset` are direct Lanczos downscales of the canonical master and remain as the fallback for older toolchains and OS releases. Do not regenerate them from the SVG.

`AltilloMark.svg` is a simplified vector companion used only where a monochrome or resolution-independent mark is required, such as the menu-bar template icon.

`AltilloGreeting.svg` is the original connected lettering drawn in the welcome tour. Its cubic paths are the geometry source for `Apps/macOS/Onboarding/AltilloGreeting.swift`; after editing the SVG, run `python3 Apps/Shared/Brand/AltilloGreetingGenerate.py` from the repository root to update the SwiftUI paths. The renderer animates the main stroke, the `t` crossbar and the `i` dot in that order.
