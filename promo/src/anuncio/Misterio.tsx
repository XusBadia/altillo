import type {ReactNode} from 'react';
import {AbsoluteFill, Audio, Img, interpolate, Sequence, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';
import {UI_BOXES} from './ui-manifest';
import {clamp, easeInOut, easeOut, Kinetic, MenuBar, palette, SCREEN, system} from './parts';

// Teaser «Mira arriba» (16 s, 120 BPM, 60 fps): el notch visto en la oscuridad y, en un plano fijo, la interfaz
// real (DesignScenario) cambiando de pestaña cada vez más deprisa, hasta el silencio y el nombre. Sin web.
// Música: public/anuncio/audio/teaser-misterio.wav (scripts/teaser-music.py), la B del anuncio «a través del techo».
export const MISTERIO_FPS = 60;
export const MISTERIO_FRAMES = 16 * MISTERIO_FPS;

type Lang = 'es' | 'en';
type Scenario = keyof typeof UI_BOXES;

const B = 30; // un tiempo
const BAR = 4 * B;

const COPY = {
  es: {
    intro: [['Llevas años', 'mirándolo.'], ['Pero nunca', 'has mirado', 'dentro.']],
    look: 'Mira arriba.',
    soon: 'Muy pronto.',
  },
  en: {
    intro: [["You've looked at it", 'for years.'], ['But you never', 'looked', 'inside.']],
    look: 'Look up.',
    soon: 'Coming soon.',
  },
};

// El escritorio en puntos, como en el anuncio: el panel del notch (780×440) centrado arriba.
const PANEL = {width: 780, height: 440, left: (SCREEN.width - 780) / 2};
const NOTCH = {x: SCREEN.width / 2, w: 195.6, h: 32};

// Plano fijo del notch abierto cambiando de pestaña, cada vez más deprisa: [fotograma desde TABS_START, estado].
const TABS: Array<[number, Scenario]> = [
  [0, 'idle'],
  // compases 3–4: una pestaña cada dos tiempos
  [8, 'openShelf'],
  [2 * B, 'openUsage'],
  [4 * B, 'openAgents'],
  [6 * B, 'openDrawer'],
  // compás 5: una por tiempo
  [8 * B, 'openNowPlaying'],
  [9 * B, 'openAssistant'],
  [10 * B, 'openCalendar'],
  [11 * B, 'openUsage'],
  // compás 6: una por medio tiempo, con la subida; al final se cierra antes del silencio
  ...(['openAgents', 'openDrawer', 'openShelf', 'openNowPlaying', 'openCalendar', 'openAssistant', 'openUsage'] as Scenario[])
    .map((state, i): [number, Scenario] => [12 * B + i * (B / 2), state]),
  [15 * B + B / 2, 'idle'],
];
const TABS_START = 2 * BAR;
const LOOK = 6 * BAR; // compás 7, tiempo 1: silencio
const NAME = 6 * BAR + 2 * B; // compás 7, tiempo 3: golpe final

const smoother = (t: number) => t * t * t * (t * (6 * t - 15) + 10);

// Escritorio en penumbra con el notch en el estado dado.
const Desk = ({state, lang, open = 1}: {state: Scenario; lang: Lang; open?: number}) => {
  const [x0, , x1, y1] = UI_BOXES[state][lang];
  // Apertura: el panel crece desde el tamaño del notch cerrado, como en la app.
  const sx = interpolate(open, [0, 1], [NOTCH.w / Math.max(1, x1 - x0), 1]);
  const sy = interpolate(open, [0, 1], [NOTCH.h / Math.max(1, y1), 1]);
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
      <Img
        src={staticFile('anuncio/product/wallpaper.png')}
        style={{position: 'absolute', left: -40, top: -20, width: SCREEN.width + 80, height: SCREEN.height + 60, objectFit: 'cover', filter: 'brightness(.55)'}}
      />
      <MenuBar lang={lang} />
      <Img
        src={staticFile(`anuncio/ui/${lang}/${state}.png`)}
        style={{
          position: 'absolute',
          left: PANEL.left,
          top: 0,
          width: PANEL.width,
          height: PANEL.height,
          transform: `scale(${sx}, ${sy})`,
          transformOrigin: '390px 0px',
        }}
      />
    </div>
  );
};

// Cámara en puntos: el foco (x, y) queda en el centro del fotograma.
const Camera = ({x, y, scale, children}: {x: number; y: number; scale: number; children: ReactNode}) => (
  <div style={{position: 'absolute', left: 960 - x * scale, top: 540 - y * scale, transform: `scale(${scale})`, transformOrigin: '0 0'}}>
    {children}
  </div>
);

// Viñeta: solo se ve un círculo de luz alrededor del foco.
const Vignette = ({radius = 34, dark = 0.96}: {radius?: number; dark?: number}) => (
  <AbsoluteFill style={{background: `radial-gradient(ellipse ${radius}% ${radius * 1.5}% at 50% 50%, transparent 0%, rgba(8,7,6,${dark * 0.7}) 60%, rgba(8,7,6,${dark}) 100%)`}} />
);

const boxSize = (state: Scenario, lang: Lang) => {
  const [x0, , x1, y1] = UI_BOXES[state][lang];
  return {w: Math.max(1, x1 - x0), h: Math.max(1, y1)};
};

// Panel del notch con la transición real entre estados: la forma se ajusta y el contenido cruza
// (mismos muelles que el anuncio: apertura con rebote, cambio de pestaña sin rebote).
const TabPanel = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  let index = 0;
  TABS.forEach(([f], i) => {
    if (frame >= f) index = i;
  });
  const [start, current] = TABS[index];
  const previous = index > 0 ? TABS[index - 1][1] : current;
  const a = boxSize(previous, lang);
  const b = boxSize(current, lang);
  const isOpen = (x: Scenario) => x.startsWith('open');
  const tabSwitch = isOpen(previous) && isOpen(current);
  const opening = !tabSwitch && isOpen(current);
  const p = index === 0 ? 1 : spring({
    frame: frame - start,
    fps,
    config: tabSwitch ? {damping: 40, mass: 0.4, stiffness: 520} : opening ? {damping: 17, mass: 0.45, stiffness: 430} : {damping: 30, mass: 0.4, stiffness: 520},
  });
  const fadeIn = Math.min(1, p * (tabSwitch ? 1.6 : 3));
  const layer = (state: Scenario, sx: number, sy: number, opacity: number) => (
    <Img
      key={state}
      src={staticFile(`anuncio/ui/${lang}/${state}.png`)}
      style={{position: 'absolute', left: 0, top: 0, width: PANEL.width, height: PANEL.height, transform: `scale(${sx}, ${sy})`, transformOrigin: '390px 0px', opacity}}
    />
  );
  return (
    <div style={{position: 'absolute', left: PANEL.left, top: 0, width: PANEL.width, height: PANEL.height}}>
      {p < 1 && previous !== current ? layer(previous, interpolate(p, [0, 1], [1, b.w / a.w]), interpolate(p, [0, 1], [1, b.h / a.h]), 1 - fadeIn) : null}
      {opening || tabSwitch
        ? layer(current, interpolate(p, [0, 1], [a.w / b.w, 1]), interpolate(p, [0, 1], [a.h / b.h, 1]), fadeIn)
        : layer(current, 1, 1, Math.min(1, p * 1.4))}
    </div>
  );
};

// Cámara fija sobre el notch: el borde superior de la pantalla arriba del todo, empuje lento y un paneo mínimo.
const TabsShot = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const length = LOOK - TABS_START;
  const t = smoother(Math.min(1, frame / length));
  const scale = interpolate(t, [0, 1], [2.05, 2.4]);
  const x = NOTCH.x + interpolate(t, [0, 1], [-10, 10]);
  const top = interpolate(t, [0, 1], [150, 120]); // píxel donde queda el borde superior de la pantalla
  const focus = interpolate(frame, [0, 24], [0, 1], {...clamp, easing: easeOut});
  return (
    <AbsoluteFill style={{backgroundColor: '#080706', overflow: 'hidden'}}>
      <AbsoluteFill style={{filter: `blur(${(1 - focus) * 12}px) brightness(${0.5 + 0.5 * focus})`}}>
        <div style={{position: 'absolute', left: 960 - x * scale, top, transform: `scale(${scale})`, transformOrigin: '0 0'}}>
          <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
            <Img
              src={staticFile('anuncio/product/wallpaper.png')}
              style={{position: 'absolute', left: -40, top: -20, width: SCREEN.width + 80, height: SCREEN.height + 60, objectFit: 'cover', filter: 'brightness(.55)'}}
            />
            <MenuBar lang={lang} />
            <TabPanel lang={lang} />
          </div>
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{background: 'radial-gradient(ellipse 58% 80% at 50% 28%, transparent 0%, rgba(8,7,6,.55) 62%, rgba(8,7,6,.94) 100%)'}} />
    </AbsoluteFill>
  );
};

// Compases 1–2: el notch cerrado en la oscuridad; se escapa luz cálida por debajo.
const Intro = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const t = smoother(Math.min(1, frame / (2 * BAR)));
  const scale = interpolate(t, [0, 1], [2.1, 3.4]);
  // La luz crece despacio y sin parpadeos, como una trampilla que se entreabre.
  const light = smoother(Math.min(1, frame / (2 * BAR - 20)));
  const fade = interpolate(frame, [0, 40], [0, 1], {...clamp, easing: easeOut});
  return (
    <AbsoluteFill style={{backgroundColor: '#080706', overflow: 'hidden'}}>
      <AbsoluteFill style={{opacity: fade, filter: 'brightness(.9)'}}>
        <Camera x={NOTCH.x} y={60} scale={scale}>
          <Desk state="idle" lang={lang} />
        </Camera>
      </AbsoluteFill>
      {/* Luz que se escapa por el borde inferior del notch */}
      <div
        style={{
          position: 'absolute',
          left: 960 - NOTCH.w * scale * 0.62,
          top: 540 + (NOTCH.h - 60) * scale - 12 * scale,
          width: NOTCH.w * scale * 1.24,
          height: 30 * scale,
          borderRadius: '50%',
          background: `radial-gradient(ellipse at 50% 30%, rgba(255,190,100,${0.9 * light}), rgba(233,165,74,${0.25 * light}) 45%, transparent 70%)`,
          filter: 'blur(6px)',
          mixBlendMode: 'screen',
        }}
      />
      {/* Silueta del notch con luz de contorno, como una trampilla mal cerrada */}
      <div
        style={{
          position: 'absolute',
          left: 960 - (NOTCH.w / 2) * scale,
          top: 540 - 60 * scale - 20,
          width: NOTCH.w * scale,
          height: NOTCH.h * scale + 20,
          borderRadius: `0 0 ${11 * scale}px ${11 * scale}px`,
          backgroundColor: '#000',
          boxShadow: `0 ${3 * scale}px ${14 * scale}px rgba(233,165,74,${0.55 * light}), 0 ${scale}px ${2 * scale}px rgba(255,200,120,${0.5 * light})`,
        }}
      />
      <Vignette radius={46} dark={0.92} />
    </AbsoluteFill>
  );
};

// Final: el notch arriba, con luz saliendo, y el nombre.
const Name = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = (at: number) => spring({frame: frame - at, fps, config: {damping: 18, mass: 0.6, stiffness: 180}});
  const name = pop(0);
  const soon = pop(2 * B);
  const glow = interpolate(frame, [0, 8, 90], [1.6, 1, 0.8], clamp);
  const end = interpolate(frame, [MISTERIO_FRAMES - NAME - 24, MISTERIO_FRAMES - NAME], [1, 0], {...clamp, easing: easeInOut});
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink, fontFamily: system, color: palette.paper, alignItems: 'center', opacity: end}}>
      {/* Luz del altillo: sale del notch y baña la parte de arriba */}
      <div
        style={{
          position: 'absolute',
          top: -260,
          width: 1500,
          height: 700,
          borderRadius: '50%',
          background: `radial-gradient(ellipse at 50% 40%, rgba(233,165,74,${0.34 * glow}), rgba(233,165,74,${0.08 * glow}) 45%, transparent 70%)`,
        }}
      />
      <div style={{position: 'absolute', top: 0, width: 520, height: 86, borderRadius: '0 0 42px 42px', backgroundColor: '#000', boxShadow: `0 10px ${60 * glow}px rgba(233,165,74,${0.5 * glow})`}} />
      <div
        style={{
          position: 'absolute',
          top: 400,
          fontSize: 190,
          fontWeight: 650,
          letterSpacing: '-7px',
          opacity: Math.min(1, name * 1.6),
          filter: name < 0.98 ? `blur(${(1 - Math.min(1, name)) * 16}px)` : undefined,
          transform: `translateY(${(1 - name) * 40}px) scale(${1.08 - 0.08 * name})`,
        }}
      >
        Altillo
      </div>
      <div style={{position: 'absolute', top: 650, fontSize: 44, fontWeight: 500, color: palette.amber, opacity: Math.min(1, soon * 1.6), transform: `translateY(${(1 - soon) * 20}px)`}}>
        {COPY[lang].soon}
      </div>
    </AbsoluteFill>
  );
};

export const AltilloMisterio = ({lang = 'es'}: {lang?: Lang}) => {
  const c = COPY[lang];
  return (
    <AbsoluteFill style={{backgroundColor: '#080706'}}>
      <Sequence from={0} durationInFrames={TABS_START} name="El notch en la oscuridad">
        <Intro lang={lang} />
      </Sequence>
      {c.intro.map((parts, i) => (
        <Sequence key={i} from={i * BAR + 10} durationInFrames={BAR - 14} name={`Texto · ${parts.join(' ')}`}>
          <Kinetic parts={parts.map((p, j) => [j * B, p])} duration={BAR - 14} size={84} />
        </Sequence>
      ))}
      <Sequence from={TABS_START} durationInFrames={LOOK - TABS_START} name="Pestañas">
        <TabsShot lang={lang} />
      </Sequence>
      <Sequence from={LOOK} durationInFrames={NAME - LOOK} name="Mira arriba">
        <AbsoluteFill style={{backgroundColor: '#080706'}}>
          <Kinetic parts={[[4, c.look]]} duration={NAME - LOOK + 6} size={120} style={{bottom: 470}} />
        </AbsoluteFill>
      </Sequence>
      <Sequence from={NAME} name="Nombre">
        <Name lang={lang} />
      </Sequence>
      <Audio src={staticFile('anuncio/audio/teaser-misterio.wav')} />
    </AbsoluteFill>
  );
};
