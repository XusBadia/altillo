# Altillo brand assets

`AltilloIconMaster-11A.png` is the canonical app-icon artwork selected for Altillo.

`../AppIcon.icon` is the adaptive Icon Composer source used by current versions of macOS and iOS. It keeps the selected 11A geometry in three flat 1024×1024 layers from `../IconLayers`: the dark background, the ivory structure, and the orange attic. Icon Composer supplies the platform mask, depth, lighting, dark appearance, and monochrome appearance.

The PNGs in `../Assets.xcassets/AppIcon.appiconset` are direct Lanczos downscales of the canonical master and remain as the fallback for older toolchains and OS releases. Do not regenerate them from the SVG.

`AltilloMark.svg` is a simplified vector companion used only where a monochrome or resolution-independent mark is required, such as the menu-bar template icon.
