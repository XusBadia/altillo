# Altillo product ad assets

Generated with `chatgpt-imagegen` (`--backend codex --quiet --timeout 500 --size 1536x1024`).
All files in this directory; nothing else in the repo was touched.

## Files

- `macbook-front.png` — front-on MacBook Pro shot, pure-black screen, for screen-replacement compositing.
- `macbook-angle.png` — 3/4 hero angle MacBook Pro shot, pure-black screen.
- `wallpaper.png` — dark Desván-palette abstract wallpaper (dark top for menu bar legibility).
- `wallpaper-light.png` — light daytime variant of the wallpaper.
- `geometry.json` — measured pixel geometry (screen rect/corners, notch rect) for the two MacBook shots, derived with Python + PIL/NumPy/SciPy by isolating the pure-black screen as the largest non-border-touching near-black connected component, then detecting the notch outline via a local Sobel-style edge pass inside the screen's top ~100px band.

## Prompts used

### macbook-front.png

> Photoreal Apple-keynote-style product photograph of a modern MacBook Pro 14-inch laptop in space black, perfectly front-on and centered in frame, lid open at approximately 100 degrees, camera positioned at screen height with minimal perspective distortion so the screen forms an almost perfect flat rectangle facing the camera. The screen is a PURE FLAT SOLID BLACK rectangle (completely black, no reflections, no UI, it will be digitally replaced), with a thin black bezel around it and the small black camera notch cutout clearly visible centered at the top edge of the screen. No Apple logo anywhere, no text, no stickers, no watermark. Seamless studio backdrop in a warm very dark brown-black color (deep espresso, near #100E0C to #1C1611), with soft warm amber rim lighting on the laptop edges, subtle soft reflection of the laptop on a dark glossy studio surface below. Wide empty negative space around the laptop; the laptop occupies about 60 percent of the frame width, centered horizontally. Professional product photography, sharp focus, high detail on the aluminum body and hinge, cinematic warm lighting.

(Codex backend silently rewrote "MacBook Pro" to "laptop resembling a MacBook Pro" in its revised prompt — see `logs/macbook-front.log`.)

### macbook-angle.png

> Photoreal Apple-keynote-style product photograph of a modern MacBook Pro 14-inch laptop in space black, shown from an elegant three-quarter hero angle from the front-left side, camera slightly above eye level, lid open naturally. The screen is a PURE FLAT SOLID BLACK rectangle (completely black, no reflections, no UI, it will be digitally replaced) with a thin black bezel and the small black camera notch cutout visible at the top edge of the screen. No Apple logo anywhere, no text, no stickers, no watermark. Seamless studio backdrop in warm very dark brown-black color (deep espresso, near #100E0C to #1C1611), dramatic soft warm amber rim lighting tracing the aluminum edges and hinge, subtle soft reflection on a dark glossy studio surface below. Wide empty negative space around the laptop. Professional product photography, sharp focus, cinematic warm lighting, high detail on aluminum chassis.

### wallpaper.png

> Abstract macOS-style desktop wallpaper, smooth flowing organic gradient shapes and soft blurred blobs in a warm color palette: deep espresso near-black, glowing amber orange, warm cream, and a subtle hint of dusty rose. Soft luminous diffuse lighting, silky smooth gradients, no hard edges, no objects, no icons, no text, no logos. Composition darker and denser toward the top of the frame so white text and a black notch panel would remain readable there, gradually opening into warmer glowing amber and cream tones toward the bottom. Wide 16:9-friendly horizontal composition, high resolution, elegant and calm, Apple-wallpaper aesthetic.

### wallpaper-light.png

> Abstract macOS-style desktop wallpaper, lighter daytime variant, smooth flowing organic gradient shapes and soft blurred blobs in a warm bright color palette: cream, soft peach, warm amber gold, and a touch of dusty rose, all light and airy tones. Soft luminous diffuse lighting, silky smooth gradients, no hard edges, no objects, no icons, no text, no logos. Slightly deeper warm tone toward the top of the frame so dark text could still read there, opening into brighter warm cream and peach glow toward the bottom. Wide 16:9-friendly horizontal composition, high resolution, elegant, calm, Apple-wallpaper aesthetic, daylight feel.

## Quality notes

- Both MacBook shots: no Apple logo anywhere, screen reads as flat near-black (max channel value <15 across almost the whole rect, small anti-aliased edge halo at the bezel line), notch clearly present and centered. No obvious warping of keyboard/trackpad/hinge. Kept on first generation for both — no second iteration was needed.
- `macbook-front.png` is not perfectly orthographic — there is a few-pixel perspective skew (top edge y: 131 left vs 133 right corner, screen left edge x 311 vs 324 at top vs bottom) but it reads as front-on at normal viewing size; if pixel-perfect rectilinearity is needed for compositing, treat `screenCorners` as the authoritative quad rather than assuming an axis-aligned rectangle.
- `macbook-angle.png` notch bbox in `geometry.json` is an approximate rectangle around the perspective-skewed trapezoid notch outline (edge-detected in fragments due to the angle); it is close but not pixel-exact — fine for rough placement, not for a tight mask.
- Both wallpapers: no text/objects/logos as requested, correct light/dark relationship (dark-to-warm for `wallpaper.png`, warm-to-cream for `wallpaper-light.png`). Codex backend generated `wallpaper.png` at `quality=low` per its own log line (the others were `medium`) — visually it still looks smooth and artifact-free at this size, but flag it if it needs to be upscaled or used larger than 1536x1024.
- Per-job generation logs (prompt-revision text, timing) are kept in `logs/` in this same directory for reference.
