# Altillo interactive demo (`lab/shared/demo`)

A macOS desktop with the real notch UI that you can hover, tap and drag files onto. It is shared by the marketing-site prototypes. Everything runs on sample data. The only real thing is the audio: the three original tracks in `/media/music/`.

- `demo.js`: an ES module with no dependencies. It exports `mountDemo` (default export too).
- `demo.css`: the desktop scene (`.dm-*`) and how the notch moves.
- `../notch.css`: the notch kit (`.an-*`). The demo always uses it and never themes it.
- `index.html`: a standalone test page (`/lab/shared/demo/`) with theme and module buttons and an event log. It also accepts query flags: `?lang=es`, `?theme=t-apple|t-warm` and `?auto=0`.

## Use

```html
<div id="demo"></div>
<script type="module">
  import { mountDemo } from "../shared/demo/demo.js";
  const demo = mountDemo(document.getElementById("demo"), { locale: "en" });
</script>
```

`mountDemo` injects `notch.css` and `demo.css` if the page doesn't already link them. Link them yourself to avoid a flash of unstyled content.

### Options

| option | default | |
| --- | --- | --- |
| `locale` | `<html lang>` or `"en"` | `"en"` or `"es"` |
| `mediaBase` | `"/media/music/"` | Where `azotea.mp3`, `luz-de-tarde.mp3` and `ultimo-tranvia.mp3` live |
| `caption` | `true` | Shows the hint line and the Reset button under the frame |
| `autoAgent` | `true` | Claude asks to run `git push` 2.6 s after the desktop first scrolls into view |
| `initialShelf` | `[]` | File ids (`proposal`, `shot`, `notes`, `assets`, `link`, `idea`, `invoice`, `holiday`) already on the shelf at mount and after `reset()` |

### Returned API

| method | |
| --- | --- |
| `show(moduleId)` | Opens the notch on that module, or switches to it if the notch is already open. Modules: `shelf`, `ask`, `usage`, `agents`, `calendar`, `mirror`, `music` (aliases `nowplaying`, `now-playing`). `drawer` tucks the menu bar icons into the Drawer strip and opens the notch with the strip highlighted. `show("agents")` starts the `git push` request if none is pending. Opens made with `show` stay open ("pinned") until `close()`, Escape or a click on the empty desktop. |
| `open()` / `close()` | Opens the notch on the current module, or closes it. |
| `reset()` | Back to the first state. |
| `on(type, fn)` | Subscribes to one event type, or to `"*"` for all of them. `fn` receives `detail`. Returns an unsubscribe function. |
| `state` | A read-only snapshot: `{ open, module, shelf, delivered, drawerTucked, agent, playing, compact }`. |
| `destroy()` | Stops audio and timers, removes listeners and empties the element. |

Every method except `on` and `destroy` returns the API, so calls can be chained.

## Events

Every meaningful action dispatches a DOM `CustomEvent("altillo-demo", { bubbles: true, detail: { type, … } })` on the root element. These events feed the easter eggs.

| `type` | extra `detail` | when |
| --- | --- | --- |
| `opened` | `module`, `via` (`hover`, `click`, `tap`, `keyboard`, `drag`, `api`) | The notch opens |
| `closed` | `via` | The notch closes |
| `module-shown` | `module` | Any module becomes visible, including `drawer` via `show()` |
| `file-shelved` | `file`, `id`, `count`, `via` (`drag`, `button`, `double-click`) | A file lands on the shelf |
| `shelf-full` | `count`, optional `attempted` | The 8th item lands, and again whenever something is refused because the shelf is full |
| `file-delivered` | `file`, `id`, `delivered` | A shelf item is dropped into Deliveries (drag, or the Deliveries / "To Deliveries" buttons) |
| `agent-requested` | `command`, `danger` | Claude Code asks for permission |
| `agent-allowed` | `command`, `session` | Allow, Allow for this session, or a completed hold-to-allow |
| `agent-denied` | `command` | Deny |
| `joined-call` | `event`, `provider` | The simulated Join finishes ("Joining…" → "Joined") |
| `track-played` | `track`, `title` | Audio starts playing |
| `all-tracks-played` | `tracks` | Each of the 3 tracks has played for at least 5 s (fires once) |
| `mirror-flipped` | `mirrored` | Mirrored ↔ As it is |
| `drawer-toggled` | `tucked` | Menu bar icons tucked into the Drawer, or shown again |
| `ask-asked` | `question`, `topic` (`today`, `clipboard`, `music`, `usage`, `summarize`, `shelf`, `fallback`) | A question is sent to Ask |
| `notch-knocked` | none | 3 clicks within 0.9 s on the notch (its camera area once it's open) |
| `reset` | none | `reset()` or the Reset button |

## Theming

Theme the demo only through custom properties set on the mount element or an ancestor. The notch never changes.

| variable | default | what it styles |
| --- | --- | --- |
| `--demo-bg` | `transparent` | Background behind the frame |
| `--demo-wallpaper` | purple-sunset gradients | The screen wallpaper (any `background` value) |
| `--demo-frame` | `#0b0b0c` | Display bezel |
| `--demo-frame-edge` | `#3a3a3e` | The 1 px rim around the bezel |
| `--demo-radius` | `22px` | Outer corner radius of the frame. The screen radius follows it. |
| `--demo-bezel` | `14px` (`7px` compact) | Bezel thickness |
| `--demo-shadow` | soft drop shadow | Frame shadow |
| `--demo-accent` | `#ffb547` | Focus rings outside the notch, the cue arrow, the Deliveries drop halo and the counter |
| `--demo-font` | system UI | Caption font (hint line and Reset) |
| `--demo-mono` | SF Mono stack | Terminal font |
| `--demo-text` / `--demo-muted` | light / 60 % | Caption colours |
| `--demo-window` / `--demo-window-text` | dark glass / near-white | Finder and Terminal material |

`index.html` includes two example skins: `t-apple` (pure black, rounded) and `t-warm` (a warm #10100f editorial look with a thin square frame and a serif caption).

## Layout and scale

- **Wide (container > 700 px):** the scene is authored at 1152 × 720 design px and scaled with `zoom` to the container width, so it stays crisp. On small scenes the notch grows a bit relative to the desktop (`--an-scale` up to 1.5) so its text stays readable.
- **Compact (container ≤ 700 px):** the desktop turns into a column. The files sit in a row, the terminal is collapsed to its last lines next to Deliveries, and there is no dock. The notch fills the width at about 1:1 scale, so the smallest kit text is ≥ 11 px. The tabs move to their own row, as the app does on narrow panels. Tap to open. Tapping the camera area or the empty desktop closes it.
- The breakpoint is based on the container, not the viewport (ResizeObserver).

## Motion (from the app's SwiftUI)

- **Open:** `spring(duration: 0.4, bounce: 0.3)`, sampled into a CSS `linear()` easing. It peaks around 280 ms with a ~4 % overshoot.
- **Content focus-in:** blur 10 → 0 and scale 0.95 → 1, with `spring(0.3, 0)` and a 50 ms delay.
- **Close:** 200 ms with no bounce. Content focuses out (blur 6, scale 0.975, 120 ms).
- **Section change:** `spring(0.32, 0.15)`. The body slides 24 pt sideways with blur 2.5.
- **Knocking hand:** −12° → 4° → −12° → 0 over 0.7 s. It fires at 0.4 s, 3.4 s and 6.4 s, then every 30 s.
- With `prefers-reduced-motion`, springs, blur, knocking and typing are removed. States still change instantly.

## Accessibility

- The closed notch is a button with `aria-expanded`. Enter opens it and focuses the active tab.
- Tabs follow the ARIA tabs pattern: ←/→/Home/End move between them, and Escape closes and returns focus.
- Every drag has a button alternative:
  - "Put on shelf" in Finder (or double-click a file).
  - "To Deliveries" in the shelf header, or the Deliveries icon itself.
  - Delete or Backspace on a shelf item takes it down.
- Hold-to-allow works with the keyboard: hold Space or Enter.
- Actions are announced through a polite live region. Focus is kept across re-renders.

## Faithfulness notes

- **Mirror, Drawer and Ask** are built from `DesvanMirror.swift`, `DesvanDrawer.swift` / `docs/cajon.md` and `DesvanAssistant.swift`. The markup, kit CSS and screenshots are in `notch.css` under "KIT EXTENSIONS" and in the new sections of `notch.html`.
- **Ask:** the app has no "On this Mac" badge. Privacy is stated in the welcome line ("Privately, on this Mac. …"), and the demo keeps it that way.
- **Drawer:** the app's menu bar jumps with no animation (Hidden Bar technique). The demo animates the tuck lightly for legibility.
- **Mirror:** the camera never turns on. The glass shows an illustrated portrait, labelled as such.
