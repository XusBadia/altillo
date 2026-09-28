# Altillo easter eggs — shared engine

A vanilla ES module with no dependencies, shared by every marketing-site prototype. Each egg announces itself as a **notch peek**: a small black pill with concave fillets that drops from the top centre of the viewport, shows an icon and one line, plus `n/total` found. Found eggs are remembered in `localStorage` (`altillo.eggs.v1`) and listed in the **secret drawer**. Press `?`, or click the tiny keyhole in the footer.

Test page: `/lab/shared/eggs/` (`?theme=black`, `?lang=es`, `?eggs-hour=2`, `?idle=5000`).

## Mount

```html
<link rel="stylesheet" href="../shared/eggs/eggs.css">
<script type="module">
  import { mountEggs } from "../shared/eggs/eggs.js";
  const eggs = mountEggs({
    locale: "en",                       // "en" | "es" (anything not es → en)
    demoRoot: "#demo",                  // element or selector; listens for `altillo-demo`
    selectors: {                        // element or selector; missing → those eggs skip
      logo: ".brand",
      heroNotch: ".hero .an-notch",
      footer: "footer",
    },
  });
</script>
```

Options (all optional): `locale`, `demoRoot`, `selectors`, `storageKey`, `idleMs` (60 000), `now()` (clock override), `console` (true), `keyhole` (`"auto"` = in the footer if one is given, otherwise fixed bottom-left; `"fixed"`; `false`), `veil` (true: the default night dim and lamp), `aurioImage` (`/media/aurio-mascot-wink.webp`), `aurioHref` (`https://www.aurioapp.com`; an in-page `"#anchor"` scrolls there instead of opening a new tab), `builtins` (true), `eggs` (array of custom eggs).

Eggs whose requirements are missing are not registered, so the "3 of 12" count only includes eggs a visitor can actually find on that page.

## Returned API

| | |
|---|---|
| `register({ id, title, hint, message?, icon?, requires?, trigger?(ctx), reveal?(ctx, detail) })` | Adds a page-specific egg. `trigger` wires listeners and calls `ctx.found()`. It may return a cleanup function. `requires`: selector keys or `"demoRoot"`. The default reveal is a peek with `message`. |
| `trigger(id, detail?)` | Discovers an egg (for tests and custom wiring). |
| `peek(text, { icon, mood, counter, duration })` | Shows a notch peek. Peeks queue, a burst keeps only the newest three, and clicking one dismisses it. |
| `note({ title, body, figure, variant: "kraft" \| "paper" \| "blueprint", eyebrow })` / `closeNote()` | Opens a modal note taped to the page: focus trapped, closes on Esc or a click outside, and focus goes back to where it was. |
| `openDrawer()` / `closeDrawer()` | Opens or closes the secret drawer. |
| `setNight(bool)`, `lamp(ms)` | Sets or clears `html.is-night`. `lamp` shows a lamp cone that follows the cursor. |
| `reset()`, `count`, `total`, `list()`, `destroy()` | |

`ctx` (passed to `trigger`/`reveal`): `found`, `peek`, `note`, `openDrawer`, `setNight`, `lamp`, `onKeys(sequence, fn)`, `onTaps(el, n, fn, { windowMs })`, `onDemo(type, fn)`, `listen`, `later`, `emit`, `reduced()`, `t(en, es)`, `el`, `demoRoot`.

The module also exports these helpers: `normalize` (accent- and case-insensitive), `keyToken`, `onKeySequence(word | tokens[], fn)` (ignores form fields and ⌘/Ctrl/Alt chords; arrow keys become `up`/`down`/`left`/`right`), `tapCounter(el, n, fn, { windowMs })` and `ICONS`.

### Events

- **In:** `altillo-demo` CustomEvents on `demoRoot`, with `detail.type` set to `notch-knocked`, `shelf-full`, `agent-denied` (with `detail.command`), `all-tracks-played` or `mirror-flipped`.
- **Out:** `altillo-eggs` on `document` and on `demoRoot`, with `detail.type` set to:
  - `found`, with `{ id, first, count, total }`
  - `night`, with `{ on }`
  - `reset`
  - `hidden-track`, with `{ title, artist, number }`. The demo can show the fourth track from this.

## Catalogue

| id | Trigger | What happens | Needs |
|---|---|---|---|
| `knock` | 3 quick clicks on the hero notch, or the demo's `notch-knocked` | The notch jolts. Peek: "Someone heard the knock." | `heroNotch` or `demoRoot` |
| `lights-out` | Type `altillo` (or `desván`, accents optional) | `html.is-night`, and a lamp cone follows the cursor for 7 s. Typing it again turns the lights back on. | — |
| `blueprint` | Konami code ↑↑↓↓←→←→BA | Blueprint note: a hand-drawn attic plan with a room "not on the tour" | — |
| `creak` | demo `shelf-full` | The demo root sways slightly. Peek: "The attic creaks." | `demoRoot` |
| `good-call` | demo `agent-denied` whose command contains `rm -rf` (any flag order) | Peek: "Good call." | `demoRoot` |
| `fourth-track` | demo `all-tracks-played` | Peek: Bonus track "Dust on the Rafters", and the `hidden-track` event fires | `demoRoot` |
| `still-you` | demo `mirror-flipped` ×5 | Peek: "Still you." | `demoRoot` |
| `window-light` | Logo clicked 5 times | The logo's window lights up and flickers (`.egg-flicker`; also targets `.an-house::after`). Peek: "Someone's home." | `logo` |
| `light-on` | The tab is hidden, then shown again | While away, the title reads "Someone left the light on…" and the favicon becomes a lit house. Both are restored on return. Peek: "Welcome back…" | — |
| `night-owl` | A visit between 00:00 and 05:00 local time | Night mode, plus "The house looks better while the rest sleeps." | — |
| `console` | Calling `altillo.knock()` from the console | The console shows a styled ASCII door with the GitHub link. Peek: "Side door's open. Hi, builder." | — |
| `aurio` | Type `aurio` | Aurio (the wink image) peeks up from the bottom-right with a "Psst. I live next door." bubble, linked to aurioapp.com (or `aurioHref`). It is skipped if the image is missing. | — |
| `yawn` | No input for 60 s (visible tab, nothing open) | The peek yawns: it stretches its jaw once | — |
| `hint` | Press `?` | Opens the drawer (found eggs, plus hints for the missing ones) | — |

## Theming

Everything reads `--egg-*` custom properties, declared on `:where(:root)` so any page rule overrides them.

| Variable | Default | Used for |
|---|---|---|
| `--egg-accent` / `--egg-accent-ink` | `#ffb547` / `#2b1a05` | Icons, lit dots, the lamp, flicker glow |
| `--egg-pill` / `--egg-pill-ink` / `--egg-pill-ink-2` | `#000` / paper / 50% paper | The peek and the fixed keyhole |
| `--egg-font`, `--egg-rounded`, `--egg-display`, `--egg-hand`, `--egg-mono` | SF stack / SF Rounded / rounded / Bradley Hand… / SF Mono | Body, peek, titles, blueprint labels, eyebrows |
| `--egg-kraft`, `--egg-paper`, `--egg-ink`, `--egg-tape` | `#c9a77c`, `#f6efe3`, `#2b241d`, tape | Notes |
| `--egg-blueprint`, `--egg-blueprint-ink` | `#1d4a7a`, `#e9f1fb` | Blueprint note |
| `--egg-drawer`, `--egg-drawer-raised`, `--egg-drawer-ink`, `--egg-drawer-ink-2`, `--egg-brass`, `--egg-hairline` | Dark wood, brass | Drawer |
| `--egg-drawer-grain` | `0.17` | Wood grain opacity (`../wood.webp`). Set it to `0` on flat or Apple-like pages. |
| `--egg-scrim` | `rgb(12 9 6 / .52)` | Behind notes and the drawer |
| `--egg-night-dim` | `0.42` | Default night veil. Set it to `0` if the page styles `html.is-night` itself. |
| `--egg-peek-top` | `0px` | Pushes the peek below a fixed bar |
| `--egg-z` | `9000` | Base z-index |

A pure-black, Apple-like page (see the `black` theme in `index.html`):

```css
:root {
  --egg-drawer: #161617; --egg-drawer-raised: #1d1d1f; --egg-drawer-grain: 0;
  --egg-brass: #6e6e73; --egg-drawer-ink-2: #98989d;
  --egg-kraft: #f5f5f7; --egg-ink: #1d1d1f;
  --egg-display: -apple-system, "SF Pro Display", sans-serif;
}
```

## Hooks for page styling

- `html.is-night`: night mode.
- `html[data-last-egg="id"]`: the most recent discovery.
- `html.egg-has-note` / `html.egg-has-drawer`: a note or the drawer is open.
- `.egg-knocked` on the hero notch, `.egg-creaking` on the demo root, `.egg-flicker` on the logo: short reactions you can restyle.

## Guarantees

- Everything can be dismissed: click a peek, press Esc or click outside a note or the drawer, and the dragon leaves by itself.
- Nothing ever covers the main CTA uninvited. Only deliberate actions open a modal (the Konami code, `?`, the keyhole).
- Keyboard: `?` toggles the drawer, which is a focus-trapped dialog. The keyhole is a real `<button>` with `aria-expanded`. Discoveries are announced through a polite live region. Typing in form fields never triggers anything.
- `prefers-reduced-motion`: things fade in place, with no drop, sway, flicker or yawn. The lamp still follows the cursor, because that motion is driven by the user.
