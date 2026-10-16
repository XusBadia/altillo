import type {CSSProperties, ReactNode} from 'react';
import {AbsoluteFill, Audio, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {clamp, Cursor, easeInOut, easeOut, Kinetic, MenuBar, palette, SCREEN, system} from '../anuncio/parts';
import {CASA_BOXES, CASA_THUMB} from './manifest';
import {Porch} from './Porch';

// «Casa / Home»: Home Assistant in the notch (promo/CASA.md). 28 s at 60 fps on the 120 BPM grid of music B
// (scripts/casa-music.py): 1 beat = 30 frames, 1 bar = 120 frames. Every notch frame is the real app rendered by
// HomeExportTests.swift (public/casa/ui); motion between them is the app's own: the opening spring, the light-up
// stagger (one plate per 1/16), 1:1 drags through stills taken every 2 %, and crossfades for state changes.
// The camera never cuts: fixed framings joined by quintic moves. Only the hook→screen fade and the end card change scene.
export const CASA_FPS = 60;
export const CASA_FRAMES = 28 * CASA_FPS;

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
    tourSub: 'Anything in Home Assistant.',
    door: ['Ding-dong.', 'See who it is.'],
    found: ['Finds your', 'Home Assistant.'],
    foundSub: 'On your network. No addresses to type.',
    signIn: ['Sign in.', 'No tokens.'],
    signInSub: 'Everything stays between your Mac and your home.',
    line: 'Home Assistant, in your notch.',
    meta: 'Free · Open source · altillo.app',
    window: 'Altillo Settings',
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
    tourSub: 'Todo lo que tengas en Home Assistant.',
    door: ['Ding-dong.', 'Mira quién es.'],
    found: ['Encuentra', 'tu Home Assistant.'],
    foundSub: 'En tu red. Sin escribir direcciones.',
    signIn: ['Inicia sesión.', 'Sin tokens.'],
    signInSub: 'Todo queda entre tu Mac y tu casa.',
    line: 'Tu casa, en el notch.',
    meta: 'Gratis · Código abierto · altillo.app',
    window: 'Ajustes de Altillo',
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
const SETTINGS_IN = bar(10) + 54; // 18.9 s
const RING_CLOSE = SETTINGS_IN - 12;
const SIGN_IN = bar(11, 3); // 21.0 s
const END = bar(13); // 24.0 s: the final hit

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
const SETTINGS_WIN = {x: C - 330, y: 96, width: 660, title: 28};
const SIGN_IN_BUTTON = {x: SETTINGS_WIN.x + 10 + 507, y: SETTINGS_WIN.y + SETTINGS_WIN.title + 251};
const SETTINGS_CROP = 300; // points of the card shown
// The camera card's picture in ring-grid (DesvanHomeCameraCard: 136×76 pt, radius 9), in panel points.
const SNAPSHOT = {x: 145, y: 80, w: 136, h: 76};
const PEEK_CLICK = {x: C + 40, y: 40};

// ─── Camera: [frame, framing]; equal neighbours hold, others move with a quintic ease ───
type Framing = {scale: number; top: number; fx: number};
const smoother = (t: number) => t * t * t * (t * (6 * t - 15) + 10);
const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const shots = (f: Format) => {
  const v = f === 'vertical';
  return {
    WIDE: v ? {scale: 0.72, top: 520, fx: C} : {scale: 1.27, top: 0, fx: C},
    CLOSE: v ? {scale: 2.0, top: 560, fx: C} : {scale: 2.7, top: 34, fx: C},
    CLOSE_B: v ? {scale: 2.08, top: 556, fx: C} : {scale: 2.76, top: 30, fx: C},
    // The peek centred and close; the black above the screen reads as the bezel the notch hangs from.
    PEEK: v ? {scale: 2.3, top: 760, fx: C} : {scale: 4.0, top: 300, fx: C},
    // The camera card filling the frame: the porch picture and «Someone rang».
    CARD: v ? {scale: 2.05, top: 518, fx: C} : {scale: 3.6, top: -25, fx: C},
    SETTINGS: v ? {scale: 1.55, top: 490, fx: C} : {scale: 2.3, top: -177, fx: C},
  };
};
const cameraKeys = (f: Format): Array<[number, Framing]> => {
  const s = shots(f);
  return [
    [SCREEN_IN, s.WIDE],
    [SCREEN_IN + 6, s.WIDE],
    [OPEN + 20, s.CLOSE],
    [CLOSE - 30, s.CLOSE_B],
    [PEEK + 24, s.PEEK],
    [RING_OPEN - 4, s.PEEK],
    [RING_OPEN + 46, s.CARD],
    [RING_CLOSE - 8, s.CARD],
    [SETTINGS_IN + 70, s.SETTINGS],
    [END, s.SETTINGS],
  ];
};
const shotAt = (frame: number, keys: Array<[number, Framing]>): Framing => {
  if (frame <= keys[0][0]) return keys[0][1];
  for (let i = 0; i < keys.length - 1; i++) {
    const [f0, a] = keys[i];
    const [f1, b] = keys[i + 1];
    if (frame > f1) continue;
    if (a === b) return a;
    const t = smoother(Math.min(1, Math.max(0, (frame - f0) / (f1 - f0))));
    const scale = Math.exp(lerp(Math.log(a.scale), Math.log(b.scale), t));
    const k = a.scale === b.scale ? t : (scale - a.scale) / (b.scale - a.scale);
    return {scale, top: lerp(a.top, b.top, k), fx: lerp(a.fx, b.fx, k)};
  }
  return keys[keys.length - 1][1];
};

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
  [BACK1 - 5, BACK.x, BACK.y, 0],
  [BACK1, BACK.x, BACK.y, 1],
  [BACK1 + 6, BACK.x, BACK.y, 0],
  [LAMP_PRESS - 4, HALLWAY_TILE.x, HALLWAY_TILE.y, 0],
  [LAMP_PRESS, HALLWAY_TILE.x, HALLWAY_TILE.y, 1],
  [LAMP_OPEN + 4, HALLWAY_TILE.x, HALLWAY_TILE.y, 1],
  [LAMP_OPEN + 8, HALLWAY_TILE.x, HALLWAY_TILE.y, 0],
  [FLIP - 6, LEVER.x, LEVER.y, 0],
  [FLIP, LEVER.x, LEVER.y, 1],
  [FLIP + 6, LEVER.x, LEVER.y - 4, 0],
  [BACK2 - 6, BACK.x, BACK.y, 0],
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
  [SIGN_IN - 8, SIGN_IN_BUTTON.x, SIGN_IN_BUTTON.y, 0],
  [SIGN_IN, SIGN_IN_BUTTON.x, SIGN_IN_BUTTON.y, 1],
  [SIGN_IN + 6, SIGN_IN_BUTTON.x, SIGN_IN_BUTTON.y, 0],
  [SIGN_IN + 50, SIGN_IN_BUTTON.x + 90, SIGN_IN_BUTTON.y + 120, 0],
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
  [RING_CLOSE, 'idle'],
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

/** Two stills of a 1:1 drag, crossfaded at the fractional step. */
const Steps = ({lang, prefix, index}: {lang: Lang; prefix: string; index: number}) => {
  const i = Math.floor(index);
  const f = index - i;
  const name = (n: number) => `${prefix}-${String(n).padStart(2, '0')}`;
  return (
    <>
      <Img src={ui(lang, name(i))} style={full} />
      {f > 0.01 ? <Img src={ui(lang, name(i + 1))} style={{...full, opacity: f}} /> : null}
    </>
  );
};

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
      // The scene lands: the lights take the movie mood with the plates' 0.3 s easeOut.
      const t = interpolate(frame, [MOVIE + 2, MOVIE + 22], [0, 1], {...clamp, easing: easeOut});
      return (
        <>
          <Img src={ui(lang, 'dim-27')} style={full} />
          <Img src={ui(lang, 'movie-final')} style={{...full, opacity: t}} />
        </>
      );
    }
    case 'blind':
      return <Steps lang={lang} prefix="blind" index={Math.min(28, (0.6 - blindPosition(frame)) / 0.02)} />;
    case 'afterBlind':
      return <Img src={ui(lang, 'after-blind')} style={full} />;
    case 'lamp': {
      // The bat lever throws in ~0.1 s; the plate's pilot light warms over 0.3 s.
      const t = interpolate(frame, [FLIP + 1, FLIP + 8], [0, 1], {...clamp, easing: easeOut});
      return (
        <>
          <Img src={ui(lang, 'lamp-off')} style={full} />
          <Img src={ui(lang, 'lamp-on')} style={{...full, opacity: t}} />
        </>
      );
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

// ─── Settings window (the real card, exported) ───────────────────────────────
const SettingsWindow = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const t = interpolate(frame, [SETTINGS_IN, SETTINGS_IN + 20], [0, 1], {...clamp, easing: easeOut});
  const done = interpolate(frame, [SIGN_IN + 6, SIGN_IN + 26], [0, 1], {...clamp, easing: easeInOut});
  if (t <= 0) return null;
  const card = (name: string, opacity: number) => (
    <div style={{position: 'absolute', left: 10, top: SETTINGS_WIN.title, width: 640, height: SETTINGS_CROP, overflow: 'hidden', opacity}}>
      <Img src={ui(lang, name)} style={{width: 640, height: 640}} />
    </div>
  );
  return (
    <div
      style={{
        position: 'absolute',
        left: SETTINGS_WIN.x,
        top: SETTINGS_WIN.y,
        width: SETTINGS_WIN.width,
        height: SETTINGS_WIN.title + SETTINGS_CROP + 8,
        borderRadius: 16,
        overflow: 'hidden',
        background: '#2A211B',
        boxShadow: '0 24px 70px rgba(0,0,0,.55), 0 0 0 .5px rgba(255,255,255,.14)',
        opacity: t,
        transform: `translateY(${(1 - t) * 14}px) scale(${0.96 + 0.04 * t})`,
        transformOrigin: '50% 30%',
      }}
    >
      <div style={{position: 'absolute', left: 0, top: 0, right: 0, height: SETTINGS_WIN.title, display: 'flex', alignItems: 'center', gap: 8, padding: '0 12px'}}>
        {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
          <div key={c} style={{width: 12, height: 12, borderRadius: 6, background: c}} />
        ))}
        <div style={{position: 'absolute', left: 0, right: 0, textAlign: 'center', fontFamily: system, fontSize: 13, fontWeight: 600, color: 'rgba(246,239,227,.82)'}}>
          {COPY[lang].window}
        </div>
      </div>
      {card('settings', 1 - done)}
      {done > 0 ? card('settings-connected', done) : null}
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

const Desktop = ({lang}: {lang: Lang}) => (
  <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
    <Img src={staticFile('anuncio/product/wallpaper.png')} style={{position: 'absolute', left: -40, top: -20, width: SCREEN.width + 80, height: SCREEN.height + 60, objectFit: 'cover'}} />
    <MenuBar lang={lang} />
    <SettingsWindow lang={lang} />
    <NotchPanel lang={lang} />
    <Pointer />
  </div>
);

const Screen = ({lang, format}: {lang: Lang; format: Format}) => {
  const frame = useCurrentFrame();
  const {width} = useVideoConfig();
  const keys = cameraKeys(format);
  const shot = shotAt(frame, keys);
  const appear = interpolate(frame, [SCREEN_IN - 2, SCREEN_IN + 12], [0, 1], {...clamp, easing: easeOut});
  const v = format === 'vertical';
  return (
    <AbsoluteFill style={{backgroundColor: '#050404', overflow: 'hidden', opacity: appear, filter: appear < 0.99 ? `blur(${(1 - appear) * 14}px)` : undefined}}>
      <div style={{position: 'absolute', left: width / 2 - shot.fx * shot.scale, top: shot.top, transform: `scale(${shot.scale})`, transformOrigin: '0 0'}}>
        <Desktop lang={lang} />
      </div>
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
      {line(PEEK, RING_CLOSE - 4, 'Door', (d) => <Kinetic parts={beats(c.door, 30)} duration={d} size={v ? 96 : 104} style={typeStyle} />)}
      {line(SETTINGS_IN + 20, SIGN_IN - 4, 'Found', (d) => <Kinetic parts={beats(c.found, 24)} sub={c.foundSub} subAt={60} duration={d} size={size} style={typeStyle} />)}
      {line(SIGN_IN + 4, END, 'Sign in', (d) => <Kinetic parts={beats(c.signIn, 30)} sub={c.signInSub} subAt={60} duration={d} size={size} style={typeStyle} />)}
      <Sequence from={END} name="End card">
        <Signature lang={lang} format={format} />
      </Sequence>
      <Audio src={staticFile('casa/audio/casa.wav')} />
    </AbsoluteFill>
  );
};

/** For scripts/casa-camera-check.mjs: the camera and the pointer at a frame (no rendering). */
export const casaCamera = (frame: number, format: Format = 'wide') => shotAt(frame, cameraKeys(format));
export const casaPointer = (frame: number) => ({x: track(frame, 1), y: track(frame, 2)});
