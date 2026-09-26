# Altillo DMG artwork

The release DMG uses the familiar macOS drag-to-install layout: Altillo on the
left, Applications on the right, and a warm directional cue between them. The
window is 660×400 points with 120-point Finder icons centered at `(165, 215)`
and `(495, 215)`.

`background.tiff` is the production asset. It contains 1x and 2x
representations so Finder stays crisp on Retina displays. The PNG files are
reviewable previews, and `attic-source.png` is the generated source artwork.
A soft band of warm floor light sits behind Finder's black icon labels so both
names remain legible without adding card-like UI to the illustrated scene.

To regenerate the composited assets after changing the source:

```sh
brew install imagemagick
script/render-dmg-background.sh
```

The source artwork was generated with the built-in image generator using the
Altillo master icon as a palette/style reference only. Its prompt asked for a
premium, understated attic interior in warm graphite, espresso, ivory, and
amber; broad quiet space for two Finder icons; subtle rafters and a small lit
door; and explicitly excluded logos, icons, arrows, UI chrome, and text. The
instruction, arrow, label plates, exact dimensions, and Retina packaging are
deterministic layers produced by the render script.
