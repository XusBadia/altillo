import type {CSSProperties, ReactNode} from 'react';
import {AbsoluteFill, Audio, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {clamp, Cursor, easeOut, Kinetic, MenuBar, palette, SCREEN, system} from '../anuncio/parts';
import {CASA_BOXES, CASA_THUMB} from './manifest';
import {Porch} from './Porch';

// «Casa / Home»: Home Assistant in the notch (promo/CASA.md). 24 s at 60 fps on the 120 BPM grid of music B
// (scripts/casa-music.py): 1 beat = 30 frames, 1 bar = 120 frames. Every notch frame is the real app rendered by
// HomeExportTests.swift (public/casa/ui); motion between them is the app's own: the opening spring, the light-up
// stagger (one plate per 1/16), 1:1 drags through stills taken every 2 %, and crossfades for state changes.
// The camera never cuts: it punches in on each action and pulls back to the grid with quintic moves (zoom in log
// scale), each channel on its own keys, plus a small eased push on some beats. A depth-of-field pass keeps the subject
// sharp and blurs and dims the rest, and racks between subjects. Only the hook→screen fade and the end card change scene.
export const CASA_FPS = 60;
export const CASA_FRAMES = 24 * CASA_FPS;

export type Lang = 'es' | 'en';
type Format = 'wide' | 'vertical';

const B = 30;
const bar = (n: number, beat = 1) => (n - 1) * 4 * B + (beat - 1) * B;

const COPY = {
  en: {
    hook: ['Your notch', 'can now run', 'your home.'],
    lights: ['Your lights.', 'In their real colours.'],
    dim: ['Drag', 'to dim.'],
    movie: ['Movie night.', 'One click.'],
    blind: ['Pull up', 'the blind.'],
    blindSub: 'Hold any tile for its controls.',
    lamp: ['Flip', 'the switch.'],
    tour: ['Lights.', 'Plugs.', 'Blinds.', 'Scenes.'],
    tourSub: 'Straight from your Home Assistant.',
    door: ['Ding-dong.', 'See who it is.'],
    line: 'Home Assistant, in your notch.',
    meta: 'Free · Open source · altillo.app',
  },
  es: {
    hook: ['Tu casa,', 'ahora', 'en el notch.'],
    lights: ['Tus luces.', 'Con su color real.'],
    dim: ['Arrastra', 'para atenuar.'],
    movie: ['Noche de peli.', 'Un clic.'],
    blind: ['Sube', 'la persiana.'],
    blindSub: 'Mantén pulsada una baldosa para ver sus controles.',
    lamp: ['Dale', 'al interruptor.'],
    tour: ['Luces.', 'Enchufes.', 'Persianas.', 'Escenas.'],
    tourSub: 'Desde tu Home Assistant.',
    door: ['Ding-dong.', 'Mira quién es.'],
    line: 'Tu casa, en el notch.',
    meta: 'Gratis · Código abierto · altillo.app',
  },
};

// ─── Moments (frames) ────────────────────────────────────────────────────────
const SCREEN_IN = bar(2); // 2.0 s: the drop
const OPEN = bar(2, 3); // 3.0 s: hover opens the notch
const REVEAL = OPEN + 8; // first plate lights up
const STAGGER = 7.5; // one plate per 1/16 note
const REVEAL_LEN = 21; // the app's easeOut(0.35 s)
// Pointer travel is timed so no hop peaks above ~35 px per frame on screen (scripts/casa-camera-check.mjs).
const DIM_PRESS = bar(3, 2) - 6; // 4.4 s
const DIM_FROM = DIM_PRESS + 6;
const DIM_TO = DIM_FROM + 60; // 1 s of 1:1 drag
const MOVIE = bar(4); // 6.0 s, on the downbeat
const BLIND_PRESS = bar(4, 2) + 24; // 6.9 s, held 0.6 s
const BLIND_OPEN = BLIND_PRESS + 36; // 7.5 s
const PULL_FROM = bar(5) + 16; // 8.27 s
const PULL_TO = PULL_FROM + 90; // 1.5 s of 1:1 pull
const BACK1 = bar(6) + 16;
const LAMP_PRESS = bar(6, 3) + 26;
const LAMP_OPEN = LAMP_PRESS + 36;
const FLIP = bar(7, 3) + 6; // 13.1 s
const BACK2 = bar(7, 4) + 10;
const TOUR = BACK2 + 10; // words every beat from 13.8 s
const CLOSE = bar(9); // 16.0 s: the break, the notch closes on the hit
const PEEK = bar(9, 2); // 16.5 s: «ding»
const RING_OPEN = bar(9, 4) - 15; // 17.25 s: a click on the peek opens Home, the camera card on top
const RETURN = bar(10); // 18.0 s: the music comes back
export const CASA_END = bar(11); // 20.0 s: the final hit cuts to the end card
const END = CASA_END;

// ─── Geometry (points on a 14" MacBook Pro screen) ───────────────────────────
const PANEL = {width: 780, height: 480, left: (SCREEN.width - 780) / 2};
const C = SCREEN.width / 2;
const at = (x: number, y: number) => ({x: PANEL.left + x, y});
// Measured on the exported grid (points inside the panel).
const COLS: Array<[number, number]> = [[136.5, 256], [265.6, 385], [394.7, 514], [523.4, 643]];
const ROWS: Array<[number, number]> = [[72, 150], [159, 237]];
const LAMP_BAR = {x0: 146.5, full: 101.6, y: 147}; // the floor lamp's level bar
const LEVEL_FROM = 0.7;
const LEVEL_TO = 0.16;
const PELI = at(177, 261);
const BLIND_TILE = at(454, 198);
const PLUG_TILE = at(325, 198);
const LAMP_TILE = at(200, 112);
const HALLWAY_TILE = at(583, 198);
const BACK = at(178.7, 53.3);
const PULL = {x: 236.7, yClosed: 242, yOpen: 173.3}; // the blind's brass pull: 4 % … 60 %
const LEVER = at(245, 212);
// The camera card's picture in ring-grid (DesvanHomeCameraCard: 136×76 pt, radius 9), in panel points.
const SNAPSHOT = {x: 145, y: 80, w: 136, h: 76};
const PEEK_CLICK = {x: C + 40, y: 40};

// ─── Camera ──────────────────────────────────────────────────────────────────
// A framing is the zoom `s` and the screen point (x, y) held at the frame's anchor (the centre in the wide cut, the
// stage in the vertical one). Each channel has its own keys, so a pan can run through a zoom without stopping; between
// keys it moves with a quintic (zoom in log scale) and holds otherwise. Effective zoom stays ≤ 3.4 on the raster UI
// (exported at 3×); only the peek (as before) and the vector porch go further.
type Framing = {s: number; x: number; y: number};
type Rect = [number, number, number, number];
const smoother = (t: number) => t * t * t * (t * (6 * t - 15) + 10);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const ANCHOR = {wide: 540, vertical: 860};
const shots = (f: Format): Record<string, Framing> => {
  const v = f === 'vertical';
  return {
    WIDE: v ? {s: 0.72, x: C, y: 472} : {s: 1.27, x: C, y: 425},
    GRID0: v ? {s: 1.92, x: C, y: 150} : {s: 2.6, x: C, y: 186},
    GRID: v ? {s: 2.0, x: C, y: 150} : {s: 2.72, x: C, y: 186},
    // Tight on the floor lamp and its level bar.
    DIM: v ? {s: 2.6, x: 640, y: 138} : {s: 3.3, x: 668, y: 150},
    // Back to the whole grid, tilted down to the «Peli» tag: the scene lands on every plate.
    MOVIE: v ? {s: 2.1, x: 730, y: 190} : {s: 2.85, x: 720, y: 205},
    BLIND_TILE: v ? {s: 2.3, x: 800, y: 190} : {s: 3.0, x: 800, y: 190},
    // The blind's window and its readout; a slow creep while the pull goes up.
    BLIND: v ? {s: 2.55, x: 696, y: 178} : {s: 3.25, x: 745, y: 186},
    BLIND_IN: v ? {s: 2.62, x: 700, y: 176} : {s: 3.4, x: 740, y: 184},
    HALL_TILE: v ? {s: 2.3, x: 860, y: 190} : {s: 2.95, x: 840, y: 192},
    // The bakelite plate and «Off / On».
    LAMP: v ? {s: 2.6, x: 735, y: 176} : {s: 3.4, x: 692, y: 178},
    // The pull-back for the tour: the whole panel.
    TOUR: v ? {s: 1.86, x: C, y: 160} : {s: 2.45, x: C, y: 172},
    // The peek centred and close; the black above the screen reads as the bezel the notch hangs from.
    PEEK: v ? {s: 2.3, x: C, y: 43.5} : {s: 4.0, x: C, y: 60},
    // The camera card filling the frame, then a slow push onto the porch picture.
    CARD: v ? {s: 2.05, x: C, y: 167} : {s: 3.4, x: C, y: 160},
    PORCH: v ? {s: 2.6, x: 650, y: 132} : {s: 3.85, x: 645, y: 136},
  };
};
type Move = [number, number, Partial<Framing>];
const cameraMoves = (f: Format): Move[] => {
  const s = shots(f);
  return [
    [SCREEN_IN + 6, OPEN + 25, s.GRID0],
    [OPEN + 25, REVEAL + 52, s.GRID], // a slow push while the plates light up
    [REVEAL + 58, DIM_PRESS + 20, s.DIM], // punch in on the lamp as the pointer reaches it
    [DIM_TO - 14, MOVIE - 4, s.MOVIE], // pull back to the grid, down to «Peli»
    [MOVIE + 32, BLIND_PRESS + 16, s.BLIND_TILE], // lean into the blind while it is held
    [BLIND_OPEN - 4, PULL_FROM - 2, s.BLIND], // punch in on the window as the detail opens
    [PULL_FROM, PULL_TO, s.BLIND_IN],
    [PULL_TO + 2, BACK1 + 24, s.GRID], // back to Favourites
    [BACK1 + 24, LAMP_PRESS + 4, s.HALL_TILE],
    [LAMP_OPEN - 6, FLIP - 10, s.LAMP], // punch in on the switch
    [FLIP + 8, TOUR + 16, s.TOUR], // the whole panel for the tour
    [CLOSE - 30, PEEK + 24, s.PEEK],
    [RING_OPEN + 2, RING_OPEN + 52, s.CARD],
    [RING_OPEN + 54, END, s.PORCH], // still pushing in when the hit cuts to the end card
  ];
};
// An eased push on the beat: a quick quintic rise (8 frames) and a slower settle (34), in log zoom.
const PULSES: Array<[number, number]> = [[MOVIE, 0.022], [FLIP, 0.022], [TOUR, 0.014], [TOUR + B, 0.014], [TOUR + 2 * B, 0.014],
  [TOUR + 3 * B, 0.014], [RETURN, 0.018]];
const pulse = (frame: number) => PULSES.reduce((sum, [at, amp]) => {
  const u = frame - at;
  if (u <= 0 || u >= 42) return sum;
  return sum + amp * (u < 8 ? smoother(u / 8) : 1 - smoother((u - 8) / 34));
}, 0);
type Track = Array<[number, number]>;
const channel = (moves: Move[], k: keyof Framing, initial: number): Track => {
  const keys: Track = [[0, initial]];
  for (const [f0, f1, shot] of moves) {
    const value = shot[k];
    if (value === undefined) continue;
    const last = keys[keys.length - 1];
    if (f0 < last[0]) throw new Error(`camera ${k}: move at ${f0} overlaps the one ending at ${last[0]}`);
    keys.push([f0, last[1]], [f1, value]);
  }
  return keys;
};
const along = (keys: Track, frame: number, log = false) => {
  if (frame <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [f0, a] = keys[i];
    const [f1, b] = keys[i + 1];
    if (frame > f1) continue;
    if (a === b || f1 === f0) return b;
    const t = smoother(Math.min(1, Math.max(0, (frame - f0) / (f1 - f0))));
    return log ? Math.exp(lerp(Math.log(a), Math.log(b), t)) : lerp(a, b, t);
  }
  return keys[keys.length - 1][1];
};
const cameraTracks = (f: Format) => {
  const moves = cameraMoves(f);
  const wide = shots(f).WIDE;
  return {s: channel(moves, 's', wide.s), x: channel(moves, 'x', wide.x), y: channel(moves, 'y', wide.y)};
};
const TRACKS = {wide: cameraTracks('wide'), vertical: cameraTracks('vertical')};
const shotAt = (frame: number, f: Format): Framing => {
  const t = TRACKS[f];
  return {s: along(t.s, frame, true) * Math.exp(pulse(frame)), x: along(t.x, frame), y: along(t.y, frame)};
};

// ─── Focus: the sharp rectangle (screen points) and how strong the rest is blurred/dimmed (0…1) ───
const R = {
  LAMP: [500, 70, 624, 152] as Rect,
  PELI: [500, 243, 590, 281] as Rect,
  GRID: [496, 62, 1016, 284] as Rect,
  BLIND_TILE: [758, 157, 882, 239] as Rect,
  BLIND: [505, 84, 1005, 268] as Rect,
  HALL_TILE: [887, 157, 1011, 239] as Rect,
  LAMP_DETAIL: [548, 88, 935, 262] as Rect,
  PEEK: [530, 0, 982, 62] as Rect,
  CARD: [500, 70, 1012, 166] as Rect,
  PORCH: [507, 76, 651, 160] as Rect,
};
const FEATHER = 30; // points of soft edge around the sharp rectangle (by default)
type FocusMove = [number, number, {r?: Rect; a?: number; e?: number}];
const FOCUS: FocusMove[] = [
  [DIM_PRESS - 6, DIM_PRESS + 14, {r: R.LAMP, a: 1}],
  // Rack to the tag, with a short soft edge so the bedside label just above (which changes) stays out of focus.
  [DIM_TO + 4, MOVIE - 8, {r: R.PELI, e: 8}],
  [MOVIE + 20, MOVIE + 44, {r: R.GRID, a: 0, e: FEATHER}], // the scene has landed everywhere: all sharp
  [BLIND_PRESS - 6, BLIND_PRESS + 18, {r: R.BLIND_TILE, a: 1}],
  [BLIND_OPEN - 2, BLIND_OPEN + 26, {r: R.BLIND}],
  [PULL_TO + 6, BACK1 - 4, {a: 0}],
  [LAMP_PRESS - 10, LAMP_PRESS + 14, {r: R.HALL_TILE, a: 1}],
  [LAMP_OPEN - 2, LAMP_OPEN + 26, {r: R.LAMP_DETAIL}],
  [BACK2 - 22, BACK2 - 2, {a: 0}],
  [PEEK + 2, PEEK + 30, {r: R.PEEK, a: 1}],
  [RING_OPEN + 4, RING_OPEN + 40, {r: R.CARD}],
  [RETURN + 45, RETURN + 85, {r: R.PORCH}], // «See who it is»: rack focus to the porch picture
];
const focusTracks = () => {
  const r = [0, 1, 2, 3].map((i) => {
    const keys: Track = [[0, R.LAMP[i]]];
    for (const [f0, f1, m] of FOCUS) {
      if (!m.r) continue;
      keys.push([f0, keys[keys.length - 1][1]], [f1, m.r[i]]);
    }
    return keys;
  });
  const scalar = (k: 'a' | 'e', initial: number) => {
    const keys: Track = [[0, initial]];
    for (const [f0, f1, m] of FOCUS) {
      const value = m[k];
      if (value === undefined) continue;
      keys.push([f0, keys[keys.length - 1][1]], [f1, value]);
    }
    return keys;
  };
  return {r, a: scalar('a', 0), e: scalar('e', FEATHER)};
};
const FOCUS_TRACKS = focusTracks();
const focusAt = (frame: number) => ({
  rect: FOCUS_TRACKS.r.map((k) => along(k, frame)) as Rect,
  amount: along(FOCUS_TRACKS.a, frame),
  feather: along(FOCUS_TRACKS.e, frame),
});

// ─── Cursor: [frame, x, y, pressed] in screen points ─────────────────────────
const lampX = (level: number) => PANEL.left + LAMP_BAR.x0 + LAMP_BAR.full * level;
const CURSOR: Array<[number, number, number, number]> = [
  [SCREEN_IN, 1180, 620, 0],
  [OPEN - 16, 800, 70, 0],
  [OPEN - 2, C + 6, 14, 0],
  [OPEN + 50, PANEL.left + 118, 200, 0], // parked beside the plates while they light up
  [DIM_PRESS - 10, lampX(LEVEL_FROM), LAMP_BAR.y, 0],
  [DIM_PRESS, lampX(LEVEL_FROM), LAMP_BAR.y, 1],
  [DIM_FROM, lampX(LEVEL_FROM), LAMP_BAR.y, 1],
  [DIM_TO, lampX(LEVEL_TO), LAMP_BAR.y, 1],
  [DIM_TO + 6, lampX(LEVEL_TO), LAMP_BAR.y, 0],
  [MOVIE - 6, PELI.x, PELI.y, 0],
  [MOVIE, PELI.x, PELI.y, 1],
  [MOVIE + 6, PELI.x, PELI.y, 0],
  [BLIND_PRESS - 4, BLIND_TILE.x, BLIND_TILE.y, 0],
  [BLIND_PRESS, BLIND_TILE.x, BLIND_TILE.y, 1],
  [BLIND_OPEN + 4, BLIND_TILE.x, BLIND_TILE.y, 1],
  [BLIND_OPEN + 8, BLIND_TILE.x, BLIND_TILE.y, 0],
  [PULL_FROM - 8, PANEL.left + PULL.x, PULL.yClosed, 0],
  [PULL_FROM - 3, PANEL.left + PULL.x, PULL.yClosed, 1],
  [PULL_FROM, PANEL.left + PULL.x, PULL.yClosed, 1],
  [PULL_TO, PANEL.left + PULL.x, PULL.yOpen, 1],
  [PULL_TO + 5, PANEL.left + PULL.x, PULL.yOpen, 0],
  [BACK1 - 3, BACK.x, BACK.y, 0],
  [BACK1, BACK.x, BACK.y, 1],
  [BACK1 + 6, BACK.x, BACK.y, 0],
  [LAMP_PRESS - 4, HALLWAY_TILE.x, HALLWAY_TILE.y, 0],
  [LAMP_PRESS, HALLWAY_TILE.x, HALLWAY_TILE.y, 1],
  [LAMP_OPEN + 4, HALLWAY_TILE.x, HALLWAY_TILE.y, 1],
  [LAMP_OPEN + 8, HALLWAY_TILE.x, HALLWAY_TILE.y, 0],
  [FLIP - 6, LEVER.x, LEVER.y, 0],
  [FLIP, LEVER.x, LEVER.y, 1],
  [FLIP + 4, LEVER.x, LEVER.y - 4, 0],
  [BACK2 - 3, BACK.x, BACK.y, 0],
  [BACK2, BACK.x, BACK.y, 1],
  [BACK2 + 6, BACK.x, BACK.y, 0],
  [TOUR + 14, LAMP_TILE.x, LAMP_TILE.y, 0],
  [TOUR + 18, LAMP_TILE.x, LAMP_TILE.y, 0],
  [TOUR + 38, PLUG_TILE.x, PLUG_TILE.y, 0],
  [TOUR + 42, PLUG_TILE.x, PLUG_TILE.y, 0],
  [TOUR + 64, BLIND_TILE.x, BLIND_TILE.y, 0],
  [TOUR + 70, BLIND_TILE.x, BLIND_TILE.y, 0],
  [TOUR + 108, PELI.x, PELI.y, 0],
  [RING_OPEN - 6, PEEK_CLICK.x, PEEK_CLICK.y, 0],
  [RING_OPEN, PEEK_CLICK.x, PEEK_CLICK.y, 1],
  [RING_OPEN + 6, PEEK_CLICK.x, PEEK_CLICK.y, 0],
  [RING_OPEN + 80, PANEL.left + 560, 330, 0], // off the card, out of the way of the picture
];
const track = (frame: number, i: number) =>
  interpolate(frame, CURSOR.map((k) => k[0]), CURSOR.map((k) => k[i]), {...clamp, easing: smoother});

// The drags follow the cursor 1:1: level/position from where the pointer is.
const dimLevel = (frame: number) => {
  if (frame < DIM_FROM) return LEVEL_FROM;
  const x = track(frame, 1) - PANEL.left;
  return Math.min(LEVEL_FROM, Math.max(LEVEL_TO, (x - LAMP_BAR.x0) / LAMP_BAR.full));
};
const blindPosition = (frame: number) => {
  if (frame < PULL_FROM) return 0.04;
  const y = track(frame, 2);
  return Math.min(0.6, Math.max(0.04, 0.04 + ((PULL.yClosed - y) / (PULL.yClosed - PULL.yOpen)) * 0.56));
};

// ─── Notch faces ─────────────────────────────────────────────────────────────
type Face = 'idle' | 'reveal' | 'dim' | 'movie' | 'blind' | 'afterBlind' | 'lamp' | 'afterLamp' | 'peek' | 'ring';
const STATES: Array<[number, Face]> = [
  [0, 'idle'],
  [OPEN, 'reveal'],
  [DIM_FROM - 4, 'dim'],
  [MOVIE + 2, 'movie'],
  [BLIND_OPEN, 'blind'],
  [BACK1 + 2, 'afterBlind'],
  [LAMP_OPEN, 'lamp'],
  [BACK2 + 2, 'afterLamp'],
  [CLOSE, 'idle'],
  [PEEK, 'peek'],
  [RING_OPEN + 2, 'ring'],
];
const shapeOf: Record<Face, string> = {
  idle: 'idle', reveal: 'grid', dim: 'grid', movie: 'grid', afterBlind: 'grid', afterLamp: 'grid',
  blind: 'blind-00', lamp: 'lamp-off', peek: 'peekDoorbell', ring: 'grid',
};
const isOpen = (f: Face) => f !== 'idle' && f !== 'peek';
const box = (f: Face, lang: Lang) => {
  const [x0, , x1, y1] = CASA_BOXES[shapeOf[f]][lang];
  return {x: x0, w: Math.max(1, x1 - x0), h: Math.max(1, y1)};
};
const ui = (lang: Lang, name: string) => staticFile(`casa/ui/${lang}/${name}.webp`);
const full: CSSProperties = {position: 'absolute', left: 0, top: 0, width: PANEL.width, height: PANEL.height};

/** A 1:1 drag: the nearest real still (every 2 %), never a blend, so the readout digits stay crisp under the zoom. */
const Steps = ({lang, prefix, index}: {lang: Lang; prefix: string; index: number}) => (
  <Img src={ui(lang, `${prefix}-${String(Math.round(index)).padStart(2, '0')}`)} style={full} />
);

/**
 * A state change between two real stills: the lights, the lever and the colours crossfade, but inside `hard` (panel
 * points, where the text changes) the still switches at the half-way point, so no text is ever a blend of two.
 */
const Swap = ({lang, from, to, t, hard}: {lang: Lang; from: string; to: string; t: number; hard: Rect[]}) => (
  <>
    <Img src={ui(lang, from)} style={full} />
    {t > 0 ? <Img src={ui(lang, to)} style={{...full, opacity: t}} /> : null}
    {t > 0 && t < 1 ? hard.map(([x0, y0, x1, y1]) => (
      <Img key={`${x0},${y0}`} src={ui(lang, t < 0.5 ? from : to)}
        style={{...full, clipPath: `inset(${y0}px ${PANEL.width - x1}px ${PANEL.height - y1}px ${x0}px)`}} />
    )) : null}
  </>
);
// Where the text changes, in panel points: the scene tag (its tick) and the switch's status block.
const MOVIE_TEXT: Rect[] = [[130, 240, 280, 284]];
const SWITCH_TEXT: Rect[] = [[325, 98, 636, 166]];

/** The cell of plate `i` (row-major), split at the gaps so the cells tile the grid area with no seams. */
const cell = (i: number) => {
  const c = i % 4;
  const r = Math.floor(i / 4);
  const left = c === 0 ? 100 : (COLS[c - 1][1] + COLS[c][0]) / 2;
  const right = c === 3 ? 690 : (COLS[c][1] + COLS[c + 1][0]) / 2;
  const top = r === 0 ? 62 : (ROWS[0][1] + ROWS[1][0]) / 2;
  const bottom = r === 1 ? 242 : (ROWS[0][1] + ROWS[1][0]) / 2;
  return `polygon(${left}px ${top}px, ${right}px ${top}px, ${right}px ${bottom}px, ${left}px ${bottom}px)`;
};

const FaceView = ({face, lang, frame}: {face: Face; lang: Lang; frame: number}) => {
  switch (face) {
    case 'idle':
      return <Img src={ui(lang, 'idle')} style={full} />;
    case 'reveal': {
      // Every plate dark first, then each one takes its light (the app's own stagger and easeOut).
      const done = frame > REVEAL + 7 * STAGGER + REVEAL_LEN;
      return (
        <>
          <Img src={ui(lang, done ? 'grid' : 'unrevealed')} style={full} />
          {done ? null : Array.from({length: 8}, (_, i) => {
            const t = interpolate(frame, [REVEAL + i * STAGGER, REVEAL + i * STAGGER + REVEAL_LEN], [0, 1], {...clamp, easing: easeOut});
            return t > 0 ? <Img key={i} src={ui(lang, 'grid')} style={{...full, opacity: t, clipPath: cell(i)}} /> : null;
          })}
        </>
      );
    }
    case 'dim':
      return <Steps lang={lang} prefix="dim" index={Math.min(27, (LEVEL_FROM - dimLevel(frame)) / 0.02)} />;
    case 'movie': {
      // The scene lands: the lights take the movie mood with the plates' 0.3 s easeOut. The plates change while they
      // are still out of focus (FOCUS opens to the grid only after), so their changing labels never read as a blend.
      const t = interpolate(frame, [MOVIE + 2, MOVIE + 22], [0, 1], {...clamp, easing: easeOut});
      return <Swap lang={lang} from="dim-27" to="movie-final" t={t} hard={MOVIE_TEXT} />;
    }
    case 'blind':
      return <Steps lang={lang} prefix="blind" index={Math.min(28, (0.6 - blindPosition(frame)) / 0.02)} />;
    case 'afterBlind':
      return <Img src={ui(lang, 'after-blind')} style={full} />;
    case 'lamp': {
      // The bat lever throws in ~0.1 s; the plate's pilot light warms over 0.3 s.
      const t = interpolate(frame, [FLIP + 1, FLIP + 8], [0, 1], {...clamp, easing: easeOut});
      return <Swap lang={lang} from="lamp-off" to="lamp-on" t={t} hard={SWITCH_TEXT} />;
    }
    case 'afterLamp':
      return <Img src={ui(lang, 'after-lamp')} style={full} />;
    case 'peek': {
      const [x0, y0, x1, y1] = CASA_THUMB[lang];
      return (
        <>
          <Img src={ui(lang, 'peekDoorbell')} style={full} />
          <div style={{position: 'absolute', left: x0, top: y0, width: x1 - x0, height: y1 - y0, borderRadius: 2.5, overflow: 'hidden'}}>
            <Porch width={x1 - x0} height={y1 - y0} t={interpolate(frame, [PEEK, PEEK + 40], [0.6, 1], clamp)} />
          </div>
        </>
      );
    }
    case 'ring':
      // The Home section after a ring: the camera card stays on top for two minutes, with the door camera's picture.
      return (
        <>
          <Img src={ui(lang, 'ring-grid')} style={full} />
          <div style={{position: 'absolute', left: SNAPSHOT.x, top: SNAPSHOT.y, width: SNAPSHOT.w, height: SNAPSHOT.h, borderRadius: 9, overflow: 'hidden', boxShadow: 'inset 0 0 0 .75px rgba(255,255,255,.16)'}}>
            <Porch width={SNAPSHOT.w} height={SNAPSHOT.h} />
          </div>
        </>
      );
  }
};

const NotchPanel = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  let index = 0;
  STATES.forEach(([f], i) => {
    if (frame >= f) index = i;
  });
  const [start, current] = STATES[index];
  const previous = index > 0 ? STATES[index - 1][1] : current;
  const a = box(previous, lang);
  const b = box(current, lang);
  const opening = b.h * b.w > a.h * a.w && !(isOpen(previous) && isOpen(current));
  const tabSwitch = isOpen(previous) && isOpen(current);
  const p = index === 0 ? 1 : spring({
    frame: frame - start,
    fps,
    config: tabSwitch ? {damping: 40, mass: 0.4, stiffness: 520}
      : opening ? {damping: 17, mass: 0.45, stiffness: 430} : {damping: 30, mass: 0.4, stiffness: 520},
  });
  const fadeIn = Math.min(1, p * (tabSwitch ? 1.6 : 3));
  const left = lerp(a.x, b.x, p);
  const sameShape = shapeOf[previous] === shapeOf[current];
  const layer = (face: Face, f: number, sx: number, sy: number, opacity: number, blur: number, x0?: number) => (
    <div
      key={face}
      style={{
        ...full,
        transform: `translateX(${x0 === undefined ? 0 : left - x0 * sx}px) scale(${sx}, ${sy})`,
        transformOrigin: '0px 0px',
        opacity,
        filter: blur > 0.05 ? `blur(${blur}px)` : undefined,
      }}
    >
      <FaceView face={face} lang={lang} frame={f} />
    </div>
  );
  return (
    <div style={{position: 'absolute', left: PANEL.left, top: 0, width: PANEL.width, height: PANEL.height, isolation: 'isolate'}}>
      {p < 1 && previous !== current && !sameShape
        ? layer(previous, Math.min(frame, start), lerp(1, b.w / a.w, p), lerp(1, b.h / a.h, p), 1 - fadeIn, 0, a.x)
        : null}
      {/* Same shape (a scene, a drag): the content changes in place, no crossfade of the frame. */}
      {sameShape || opening || tabSwitch
        ? layer(current, frame, sameShape ? 1 : lerp(a.w / b.w, 1, p), sameShape ? 1 : lerp(a.h / b.h, 1, p), sameShape ? 1 : fadeIn,
          sameShape || tabSwitch ? 0 : (1 - Math.min(1, p)) * 3, sameShape ? undefined : b.x)
        : layer(current, frame, 1, 1, Math.min(1, p * 1.4), 0)}
    </div>
  );
};

// ─── Desktop and camera ──────────────────────────────────────────────────────
const Pointer = () => {
  const frame = useCurrentFrame();
  const x = track(frame, 1);
  const y = track(frame, 2);
  const press = track(frame, 3);
  // A short ring while a tile is held for its controls (the app opens them after 0.6 s).
  const holds: Array<[number, number, {x: number; y: number}]> = [[BLIND_PRESS, BLIND_OPEN, BLIND_TILE], [LAMP_PRESS, LAMP_OPEN, HALLWAY_TILE]];
  const ring = holds.find(([s, e]) => frame >= s && frame < e + 6);
  const hold = ring ? interpolate(frame, [ring[0], ring[1]], [0, 1], clamp) : 0;
  return (
    <>
      {ring ? (
        <svg style={{position: 'absolute', left: ring[2].x - 14, top: ring[2].y - 14, overflow: 'visible', opacity: interpolate(frame, [ring[1], ring[1] + 6], [1, 0], clamp)}} width={28} height={28}>
          <circle cx={14} cy={14} r={11} fill="none" stroke="rgba(233,165,74,.25)" strokeWidth={3} />
          <circle cx={14} cy={14} r={11} fill="none" stroke={palette.amber} strokeWidth={3} strokeLinecap="round"
            strokeDasharray={`${2 * Math.PI * 11 * hold} 999`} transform="rotate(-90 14 14)" />
        </svg>
      ) : null}
      <Cursor x={x} y={y} press={press} scale={0.62} />
    </>
  );
};

// The desktop (wallpaper, menu bar, notch) and the pointer are separate layers: the pointer stays sharp over the
// depth-of-field pass.
const Desktop = ({lang}: {lang: Lang}) => (
  <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
    <Img src={staticFile('anuncio/product/wallpaper.png')} style={{position: 'absolute', left: -40, top: -20, width: SCREEN.width + 80, height: SCREEN.height + 60, objectFit: 'cover'}} />
    <MenuBar lang={lang} />
    <NotchPanel lang={lang} />
  </div>
);
const PointerLayer = () => (
  <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
    <Pointer />
  </div>
);

const Screen = ({lang, format}: {lang: Lang; format: Format}) => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const shot = shotAt(frame, format);
  const appear = interpolate(frame, [SCREEN_IN - 2, SCREEN_IN + 12], [0, 1], {...clamp, easing: easeOut});
  const v = format === 'vertical';
  const left = width / 2 - shot.x * shot.s;
  const top = ANCHOR[format] - shot.y * shot.s;
  const stage = (node: ReactNode) => (
    <div style={{position: 'absolute', left, top, transform: `scale(${shot.s})`, transformOrigin: '0 0'}}>{node}</div>
  );
  // Depth of field: a blurred, dimmed copy underneath and the sharp one masked to the focus rectangle (feathered),
  // all in frame pixels so the blur is the same at any zoom.
  const {rect, amount, feather} = focusAt(frame);
  const [x0, y0, x1, y1] = rect.map((c, i) => (i % 2 === 0 ? left + c * shot.s : top + c * shot.s));
  const e = feather * shot.s;
  const mask = `linear-gradient(90deg, transparent ${x0 - e}px, #000 ${x0}px, #000 ${x1}px, transparent ${x1 + e}px), `
    + `linear-gradient(180deg, transparent ${y0 - e}px, #000 ${y0}px, #000 ${y1}px, transparent ${y1 + e}px)`;
  const dof = amount > 0.002;
  return (
    <AbsoluteFill style={{backgroundColor: '#050404', overflow: 'hidden', opacity: appear, filter: appear < 0.99 ? `blur(${(1 - appear) * 14}px)` : undefined}}>
      {dof ? (
        <AbsoluteFill style={{filter: `blur(${amount * (v ? 7 : 9)}px) brightness(${1 - amount * 0.4}) saturate(${1 - amount * 0.2})`}}>
          {stage(<Desktop lang={lang} />)}
        </AbsoluteFill>
      ) : null}
      <AbsoluteFill style={dof ? {maskImage: mask, WebkitMaskImage: mask, maskComposite: 'intersect', WebkitMaskComposite: 'source-in'} : undefined}>
        {stage(<Desktop lang={lang} />)}
      </AbsoluteFill>
      {stage(<PointerLayer />)}
      {/* Veil for the type: under the stage in the vertical cut, along the bottom in the wide one. */}
      <AbsoluteFill
        style={{
          background: v
            ? 'linear-gradient(180deg, rgba(16,14,12,.96) 0%, rgba(16,14,12,.9) 22%, transparent 30%, transparent 70%, rgba(16,14,12,.85) 80%, rgba(16,14,12,.96) 100%)'
            : 'linear-gradient(180deg, transparent 60%, rgba(16,14,12,.72) 76%, rgba(16,14,12,.94) 100%)',
        }}
      />
    </AbsoluteFill>
  );
};

const Signature = ({lang, format}: {lang: Lang; format: Format}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = (at: number) => spring({frame: frame - at, fps, config: {damping: 16, mass: 0.5, stiffness: 260}});
  const v = format === 'vertical';
  const icon = pop(0);
  const name = pop(8);
  const line = pop(16);
  const meta = pop(26);
  const y = v ? 520 : 0;
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink, backgroundImage: 'radial-gradient(ellipse at 50% 40%, rgba(233,165,74,.16), transparent 55%)', fontFamily: system, color: palette.paper, alignItems: 'center'}}>
      <Img src={staticFile('icon/AltilloIconMaster-11A.png')} style={{position: 'absolute', top: 170 + y, width: 340, height: 340, borderRadius: 76, boxShadow: '0 30px 80px rgba(0,0,0,.5)', opacity: Math.min(1, icon * 2), transform: `translateY(${(1 - icon) * 50}px) scale(${0.7 + icon * 0.3})`}} />
      <div style={{position: 'absolute', top: 560 + y, fontSize: 108, fontWeight: 650, letterSpacing: '-4px', opacity: Math.min(1, name * 2), transform: `translateY(${(1 - name) * 30}px)`}}>Altillo</div>
      <div style={{position: 'absolute', top: 700 + y, fontSize: v ? 50 : 46, fontWeight: 600, letterSpacing: '-.8px', color: '#F3E6D0', textAlign: 'center', opacity: Math.min(1, line * 2), transform: `translateY(${(1 - line) * 24}px)`}}>
        {COPY[lang].line}
      </div>
      <div style={{position: 'absolute', top: 860 + y, fontSize: v ? 30 : 26, fontWeight: 600, color: palette.amber, opacity: Math.min(1, meta * 2), transform: `translateY(${(1 - meta) * 18}px)`}}>
        {COPY[lang].meta}
      </div>
    </AbsoluteFill>
  );
};

export const AltilloCasa = ({lang = 'es', format = 'wide'}: {lang?: Lang; format?: Format}) => {
  const c = COPY[lang];
  const v = format === 'vertical';
  const beats = (words: string[], step = B): Array<[number, string]> => words.map((w, i) => [i * step, w]);
  // Type sits under the stage: along the bottom (wide) or in the lower third (vertical).
  const typeStyle: CSSProperties = v ? {bottom: 250} : {bottom: 84};
  const size = v ? 74 : 88;
  const line = (from: number, to: number, name: string, node: (d: number) => ReactNode) => (
    <Sequence from={from} durationInFrames={to - from} name={name}>{node(to - from)}</Sequence>
  );
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink}}>
      <Sequence from={0} durationInFrames={END} name="Screen">
        <Screen lang={lang} format={format} />
      </Sequence>
      {line(0, SCREEN_IN + 4, 'Hook', (d) => (
        <Kinetic parts={beats(c.hook, 24).map(([f, w]) => [f + 6, w])} duration={d} size={v ? 110 : 120}
          style={{bottom: v ? 820 : 400, ...(v ? {padding: '0 60px'} : {})}} />
      ))}
      {line(REVEAL + 4, DIM_PRESS - 4, 'Lights', (d) => <Kinetic parts={beats(c.lights, 24)} duration={d} size={size} style={typeStyle} />)}
      {line(DIM_PRESS, MOVIE - 4, 'Dim', (d) => <Kinetic parts={beats(c.dim, 18)} duration={d} size={size} style={typeStyle} />)}
      {line(MOVIE, BLIND_PRESS + 10, 'Movie', (d) => <Kinetic parts={beats(c.movie, 24)} duration={d} size={size} style={typeStyle} />)}
      {line(BLIND_PRESS + 14, BACK1 - 2, 'Blind', (d) => <Kinetic parts={beats(c.blind, 18)} sub={c.blindSub} subAt={30} duration={d} size={size} style={typeStyle} />)}
      {line(LAMP_PRESS + 10, BACK2 - 4, 'Switch', (d) => <Kinetic parts={beats(c.lamp, 18)} duration={d} size={size} style={typeStyle} />)}
      {line(TOUR, CLOSE - 6, 'Tour', (d) => <Kinetic parts={beats(c.tour, 30)} sub={c.tourSub} subAt={100} duration={d} size={v ? 64 : 84} style={typeStyle} />)}
      {line(PEEK, END, 'Door', (d) => <Kinetic parts={beats(c.door, 30)} duration={d} size={v ? 96 : 104} style={typeStyle} />)}
      <Sequence from={END} name="End card">
        <Signature lang={lang} format={format} />
      </Sequence>
      <Audio src={staticFile('casa/audio/casa.wav')} />
    </AbsoluteFill>
  );
};

/** For scripts/casa-camera-check.mjs: the camera and the pointer at a frame (no rendering). */
export const casaCamera = (frame: number, format: Format = 'wide') => {
  const c = shotAt(frame, format);
  return {scale: c.s, fx: c.x, top: ANCHOR[format] - c.y * c.s};
};
export const casaFocus = focusAt;
export const casaPointer = (frame: number) => ({x: track(frame, 1), y: track(frame, 2)});
