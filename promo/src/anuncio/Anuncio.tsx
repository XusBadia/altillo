import type {ReactNode} from 'react';
import {
  AbsoluteFill,
  Audio,
  Img,
  interpolate,
  Sequence,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';
import {Hello} from './hello/Hello';
import {UI_BOXES} from './ui-manifest';
import {clamp, Cursor, easeInOut, easeOut, Kinetic, MenuBar, palette, SCREEN, system} from './parts';
import {DragImage, DropHighlight, FinderWindow, finderFile, finderItemCenter, MailWindow, mailDropRect} from './windows';

// Anuncio estilo Apple: «hola» escrito a mano y Altillo funcionando.
// La interfaz del notch no es una réplica: son los estados de diseño reales de la app (DesignScenario),
// renderizados a 3× desde NotchRootView (ver ANUNCIO.md). Finder y Mail son recreaciones (windows.tsx).
// Rejilla de la música: 120 BPM, 1 tiempo = 30 fotogramas, 1 compás = 120 fotogramas a 60 fps; 16 compases = 32 s.
// Cámara sobria: planos fijos y cortes; solo se mueve al entrar en la pantalla y al salir al final.
export const ANUNCIO_FPS = 60;
export const ANUNCIO_FRAMES = 32 * ANUNCIO_FPS;

type Lang = 'es' | 'en';
type Scenario = keyof typeof UI_BOXES;
export type Score = 'a' | 'b' | 'c';

const B = 30; // un tiempo
const bar = (n: number, beat = 1) => (n - 1) * 4 * B + (beat - 1) * B;

const COPY = {
  es: {
    hero: ['Tu Mac', 'ya tenía', 'un altillo.'],
    heroSub: 'Solo le faltaba una puerta.',
    shelfIn: ['Súbelo', 'al notch.'],
    shelfOut: ['Bájalo', 'donde lo necesites.'],
    usage: ['Claude y Codex,', 'de un vistazo.'],
    usageSub: 'Cuánto te queda y cuándo se recarga.',
    ask: ['Pregunta', 'lo que quieras.'],
    askSub: 'Un asistente que funciona en tu propio Mac.',
    knock: 'Toc, toc.',
    agents: ['Tus agentes', 'piden permiso.'],
    agentsSub: 'Tú decides.',
    montage: ['Música.', 'Agenda.', 'Avisos.', 'Cajón.', 'Límites.', 'Suelta y pregunta.', 'Vistazos.', 'Y más.'],
    line: 'Un sitio arriba para lo importante.',
    meta: 'Gratis para siempre · Código abierto · altillo.app',
  },
  en: {
    hero: ['Your Mac', 'already had', 'an attic.'],
    heroSub: 'It just needed a door.',
    shelfIn: ['Put it up', 'in the notch.'],
    shelfOut: ['Bring it down', 'wherever you need it.'],
    usage: ['Claude and Codex,', 'at a glance.'],
    usageSub: 'What you have left and when it refills.',
    ask: ['Ask', 'anything.'],
    askSub: 'An assistant that runs on your own Mac.',
    knock: 'Knock, knock.',
    agents: ['Your agents', 'ask first.'],
    agentsSub: 'You decide.',
    montage: ['Music.', 'Calendar.', 'Alerts.', 'Drawer.', 'Limits.', 'Drop & ask.', 'Glances.', 'And more.'],
    line: 'A place up top for what matters.',
    meta: 'Free forever · Open source · altillo.app',
  },
};

// ─── Encuadres ───────────────────────────────────────────────────────────────
// Escala en px por punto, borde superior de la pantalla en el fotograma y punto x centrado.
const C = 756; // centro del notch en puntos
const WIDE = {scale: 1.18, top: 36, fx: C}; // pantalla entera (entrada desde el MacBook)
const FINDER_SHOT = {scale: 1.55, top: 64, fx: 668}; // Finder + notch
const MAIL_SHOT = {scale: 1.55, top: 64, fx: 858}; // notch + Mail
const CLOSE = {scale: 2.3, top: 118, fx: C};
type Framing = typeof WIDE;

// Planos con corte seco: [fotograma, encuadre].

const T = {
  heroIn: bar(2),
  zoomIn: [bar(3, 3) + 6, bar(4)] as const,
  // Sin alejamiento final: del montaje se corta directamente a la firma.
  zoomOut: [bar(15), bar(15) + 1] as const,
  signature: bar(15),
};

// ─── Ventanas del escritorio (puntos) ────────────────────────────────────────
const FINDER = {x: 190, y: 236, width: 520, height: 360};
const MAIL = {x: 850, y: 250, width: 520, height: 380};
const PANEL = {width: 780, height: 440, left: (SCREEN.width - 780) / 2};
const fileStart = finderItemCenter(0, FINDER);
const drop = mailDropRect(MAIL);
const dropCenter = {x: drop.x + drop.width / 2, y: drop.y + drop.height / 2};
// La caja de cartón del estado dropTarget: posición medida sobre el panel real (public/anuncio/box/position.json).
const BOX_FRAME = {es: {x: 140, y: 63}, en: {x: 150, y: 63}, scale: 0.795, canvas: {w: 196, h: 146}};
const BOX = {x: PANEL.left + 140 + 78, y: 63 + 62}; // centro de la boca de la caja, donde se suelta
const SHELF_ITEM = {x: PANEL.left + 310, y: 100}; // «Propuesta Altillo v2» en el estante
const TAB_USAGE = {x: PANEL.left + 246, y: 16};
const TAB_ASK = {x: PANEL.left + 172, y: 16};
const ALLOW = {x: PANEL.left + 595, y: 124};

// Momentos clave.
const GRAB_IN = bar(4) + 14;
const HOVER_BOX = bar(4, 4) + 6; // el archivo llega sobre la caja y se abren las solapas
const DROP_IN = bar(5, 2) + 6; // se suelta
const LANDED = DROP_IN + 16;
const GRAB_OUT = bar(6) + 24;
const DROP_OUT = bar(6, 4) + 4;
const CLICK_USAGE = bar(8) + 6;
const CLICK_ASK = bar(10) + 4;
const CLICK_ALLOW = bar(13);

// Estados del notch: [fotograma, escenario]. Se abre una vez y cambia de sección con las pestañas.
const STATES: Array<[number, Scenario]> = [
  [0, 'idle'],
  [bar(2, 3), 'idleWithEars'],
  [GRAB_IN + 26, 'dragArmed'],
  [GRAB_IN + 56, 'dropTarget'],
  [LANDED, 'openShelf'],
  [GRAB_OUT + 22, 'idleWithEars'],
  [bar(7, 3) + 10, 'openShelf'],
  [CLICK_USAGE + 2, 'openUsage'],
  [CLICK_ASK + 2, 'openAssistant'],
  [bar(11) + 12, 'idleWithEars'],
  [bar(11, 2), 'peekAgentWaiting'],
  [bar(12), 'openAgents'],
];

// Montaje final a toda velocidad: el resto de funciones, un corte seco cada medio tiempo durante el compás 14.
const HALF = B / 2;
const MONTAGE: Scenario[] = [
  'openNowPlaying', 'openCalendar', 'peekAlert', 'openDrawer', 'peekUsageAlert', 'dropTargetAsk', 'peekShelf', 'idleWithEars',
];
const MONTAGE_START = bar(14);
const montageAt = (frame: number): Scenario | undefined => {
  const i = Math.floor((frame - MONTAGE_START) / HALF);
  return i >= 0 && i < MONTAGE.length ? MONTAGE[i] : undefined;
};

// Recorrido del cursor en puntos: [fotograma, x, y, pulsado].
const CURSOR: Array<[number, number, number, number]> = [
  [bar(4) - 4, fileStart.x + 90, fileStart.y + 110, 0],
  [GRAB_IN - 6, fileStart.x, fileStart.y, 0],
  [GRAB_IN, fileStart.x, fileStart.y, 1],
  [HOVER_BOX, BOX.x, BOX.y, 1],
  [DROP_IN - 4, BOX.x + 3, BOX.y + 2, 1],
  [DROP_IN, BOX.x + 3, BOX.y + 2, 0],
  [bar(5, 4), BOX.x + 40, BOX.y + 70, 0],
  [bar(6) - 2, SHELF_ITEM.x + 60, SHELF_ITEM.y + 60, 0],
  [GRAB_OUT - 6, SHELF_ITEM.x, SHELF_ITEM.y, 0],
  [GRAB_OUT, SHELF_ITEM.x, SHELF_ITEM.y, 1],
  [DROP_OUT - 6, dropCenter.x, dropCenter.y, 1],
  [DROP_OUT, dropCenter.x, dropCenter.y, 0],
  [bar(7, 2), dropCenter.x - 60, dropCenter.y + 40, 0],
  [bar(7, 3) + 6, C + 20, 26, 0],
  [bar(8) - 2, TAB_USAGE.x + 30, TAB_USAGE.y + 60, 0],
  [CLICK_USAGE - 4, TAB_USAGE.x, TAB_USAGE.y, 0],
  [CLICK_USAGE, TAB_USAGE.x, TAB_USAGE.y, 1],
  [CLICK_USAGE + 6, TAB_USAGE.x, TAB_USAGE.y, 0],
  [bar(9, 3), 900, 180, 0],
  [CLICK_ASK - 4, TAB_ASK.x, TAB_ASK.y, 0],
  [CLICK_ASK, TAB_ASK.x, TAB_ASK.y, 1],
  [CLICK_ASK + 6, TAB_ASK.x, TAB_ASK.y, 0],
  [bar(10, 4), 700, 200, 0],
  [bar(11) + 10, 860, 420, 0],
  [bar(11, 4), 820, 300, 0],
  [bar(12) - 4, C, 40, 0],
  [bar(12, 3), 900, 200, 0],
  [CLICK_ALLOW - 4, ALLOW.x, ALLOW.y, 0],
  [CLICK_ALLOW, ALLOW.x, ALLOW.y, 1],
  [CLICK_ALLOW + 6, ALLOW.x, ALLOW.y + 2, 0],
  [bar(13, 4), 1040, 300, 0],
  [bar(14), 1500, 900, 0], // fuera de cuadro durante el montaje
];

// Punto del notch en la foto del MacBook (1536×1024 mostrada a 1920 de ancho, recortada 100 px arriba).
const HERO = {imageScale: 1.25, cropTop: 100, screen: {x: 311, y: 128, w: 915, h: 552}};
const heroScreen = {
  x: HERO.screen.x * HERO.imageScale,
  y: HERO.screen.y * HERO.imageScale - HERO.cropTop,
  w: HERO.screen.w * HERO.imageScale,
  h: HERO.screen.h * HERO.imageScale,
};
const heroStageScale = heroScreen.w / SCREEN.width;

const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
const track = <K extends number[]>(frame: number, keys: K[], i: number, easing = easeInOut) =>
  interpolate(frame, keys.map((k) => k[0]), keys.map((k) => k[i]), {...clamp, easing});

// Zoom a la caja mientras se abre y se suelta el archivo, y vuelta al plano medio.
const BOX_SHOT = {scale: 3.3, top: 430 - BOX.y * 3.3, fx: BOX.x + 70};
// Cámara: sin cortes; entre encuadres siempre un movimiento continuo con aceleración y frenado suaves.
// [fotograma, encuadre]: dos claves iguales seguidas mantienen el plano.
const CAMERA: Array<[number, Framing]> = [
  [bar(4), FINDER_SHOT],
  [HOVER_BOX - 30, FINDER_SHOT],
  [HOVER_BOX + 10, BOX_SHOT], // zoom a la caja mientras se abren las solapas
  [LANDED + 8, BOX_SHOT],
  [bar(6) + 16, MAIL_SHOT], // se aleja directamente hacia Mail, sin pasar por otro plano
  [bar(7, 2) + 6, MAIL_SHOT],
  [bar(7, 3) + 26, CLOSE], // se acerca al notch mientras el cursor sube a abrirlo
  [T.signature, CLOSE],
];

// Suavizado quíntico: velocidad y aceleración nulas en los extremos, sin tirones al arrancar ni al parar.
const smoother = (t: number) => t * t * t * (t * (6 * t - 15) + 10);

const shotAt = (frame: number): Framing => {
  if (frame <= CAMERA[0][0]) return CAMERA[0][1];
  for (let i = 0; i < CAMERA.length - 1; i++) {
    const [f0, a] = CAMERA[i];
    const [f1, b] = CAMERA[i + 1];
    if (frame > f1) continue;
    if (a === b) return a;
    const t = smoother(Math.min(1, Math.max(0, (frame - f0) / (f1 - f0))));
    // El zoom avanza en escala logarítmica (ritmo uniforme) y el encuadre sigue el mismo avance.
    const scale = Math.exp(lerp(Math.log(a.scale), Math.log(b.scale), t));
    const k = a.scale === b.scale ? t : (scale - a.scale) / (b.scale - a.scale);
    return {scale, top: lerp(a.top, b.top, k), fx: lerp(a.fx, b.fx, k)};
  }
  return CAMERA[CAMERA.length - 1][1];
};

// ─── Notch: transición entre estados reales ──────────────────────────────────
const boxSize = (s: Scenario, lang: Lang) => {
  const [x0, , x1, y1] = UI_BOXES[s][lang];
  return {w: Math.max(1, x1 - x0 - 36), h: Math.max(1, y1 - 18)};
};
const isOpen = (s: Scenario) => s.startsWith('open');

const NotchPanel = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const cut = montageAt(frame);
  if (cut) {
    return (
      <div style={{position: 'absolute', left: PANEL.left, top: 0, width: PANEL.width, height: PANEL.height}}>
        <Img src={staticFile(`anuncio/ui/${lang}/${cut}.png`)} style={{position: 'absolute', left: 0, top: 0, width: PANEL.width, height: PANEL.height}} />
      </div>
    );
  }
  let index = 0;
  STATES.forEach(([f], i) => {
    if (frame >= f) index = i;
  });
  const [start, current] = STATES[index];
  const previous = index > 0 ? STATES[index - 1][1] : current;
  const a = boxSize(previous, lang);
  const b = boxSize(current, lang);
  const opening = b.h * b.w > a.h * a.w;
  // Cambio de pestaña con el notch abierto: la forma se ajusta y el contenido cruza rápido, sin rebote.
  const tabSwitch = isOpen(previous) && isOpen(current);
  const p = index === 0 ? 1 : spring({
    frame: frame - start,
    fps,
    config: tabSwitch
      ? {damping: 40, mass: 0.4, stiffness: 520}
      : opening ? {damping: 17, mass: 0.45, stiffness: 430} : {damping: 30, mass: 0.4, stiffness: 520},
  });
  const fadeIn = Math.min(1, p * (tabSwitch ? 1.6 : 3));
  const layer = (s: Scenario, sx: number, sy: number, opacity: number, blur: number) => (
    <Img
      key={s}
      // Después de pasar sobre la caja, la zona de soltar sigue con las solapas abiertas hasta desaparecer.
      src={staticFile(`anuncio/ui/${lang}/${s === 'dropTarget' && frame >= HOVER_BOX ? 'dropTargetHover' : s}.png`)}
      style={{
        position: 'absolute',
        left: 0,
        top: 0,
        width: PANEL.width,
        height: PANEL.height,
        transform: `scale(${sx}, ${sy})`,
        transformOrigin: '390px 0px',
        opacity,
        filter: blur > 0.05 ? `blur(${blur}px)` : undefined,
      }}
    />
  );
  // Arrastre sobre la caja: el panel real con el puntero encima entra en fundido y las solapas se abren
  // fotograma a fotograma con el muelle de la app (Desvan.Motion.flaps: 0,26 s con rebote).
  const hovering = current === 'dropTarget' && frame >= HOVER_BOX;
  const flaps = hovering ? spring({frame: frame - HOVER_BOX, fps, config: {damping: 11, mass: 0.5, stiffness: 260}}) : 0;
  const boxStep = Math.max(0, Math.min(28, Math.round(flaps / 0.04)));
  const boxAt = BOX_FRAME[lang];
  return (
    <div style={{position: 'absolute', left: PANEL.left, top: 0, width: PANEL.width, height: PANEL.height, isolation: 'isolate'}}>
      {hovering ? (
        <>
          <Img
            src={staticFile(`anuncio/ui/${lang}/dropTargetHover.png`)}
            style={{position: 'absolute', zIndex: 2, left: 0, top: 0, width: PANEL.width, height: PANEL.height, opacity: interpolate(frame, [HOVER_BOX, HOVER_BOX + 12], [0, 1], clamp)}}
          />
          <Img
            src={staticFile(`anuncio/box/box-${String(boxStep).padStart(2, '0')}.png`)}
            style={{
              position: 'absolute',
              zIndex: 3,
              left: boxAt.x,
              top: boxAt.y,
              width: BOX_FRAME.canvas.w * BOX_FRAME.scale,
              height: BOX_FRAME.canvas.h * BOX_FRAME.scale,
            }}
          />
        </>
      ) : null}
      {p < 1 && previous !== current
        ? layer(previous, lerp(1, b.w / a.w, p), lerp(1, b.h / a.h, p), 1 - fadeIn, 0)
        : null}
      {/* Al cerrar solo encoge lo que se va; el estado pequeño aparece a su tamaño. */}
      {opening || tabSwitch
        ? layer(current, lerp(a.w / b.w, 1, p), lerp(a.h / b.h, 1, p), fadeIn, tabSwitch ? 0 : (1 - Math.min(1, p)) * 3)
        : layer(current, 1, 1, Math.min(1, p * 1.4), 0)}
    </div>
  );
};

// ─── Escritorio en puntos: fondo, ventanas, barra de menús, notch, arrastre y cursor ───
const Pointer = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  // Cada tramo arranca y frena suave; el arrastre hacia el notch describe una ligera curva, como una mano.
  const arc = frame > GRAB_IN && frame < HOVER_BOX ? Math.sin(((frame - GRAB_IN) / (HOVER_BOX - GRAB_IN)) * Math.PI) : 0;
  const x = track(frame, CURSOR, 1, smoother) - arc * 60;
  const y = track(frame, CURSOR, 2, smoother) - arc * 20;
  const press = track(frame, CURSOR, 3, smoother);
  const draggingIn = frame >= GRAB_IN && frame < DROP_IN;
  const draggingOut = frame >= GRAB_OUT && frame < DROP_OUT;
  const overMail = draggingOut && x > drop.x && x < drop.x + drop.width && y > drop.y && y < drop.y + drop.height;
  const ring = interpolate(frame, [CLICK_ALLOW, CLICK_ALLOW + 22], [0, 1], {...clamp, easing: easeOut});
  const {label} = finderFile(0, lang);
  return (
    <>
      <DropHighlight {...drop} progress={interpolate(frame, [DROP_OUT - 22, DROP_OUT - 12, DROP_OUT, DROP_OUT + 8], [0, 1, 1, 0], clamp)} />
      {draggingIn || draggingOut ? <DragImage x={x} y={y} label={label} kind="pdf" copyBadge={overMail} /> : null}
      {/* Al soltarlo, el documento cae dentro de la caja. */}
      {frame >= DROP_IN && frame < LANDED ? (
        <div
          style={{
            position: 'absolute',
            left: 0,
            top: 0,
            transformOrigin: `${BOX.x}px ${BOX.y + 10}px`,
            transform: `translateY(${interpolate(frame, [DROP_IN, LANDED], [0, 18], {...clamp, easing: easeInOut})}px) scale(${interpolate(frame, [DROP_IN, LANDED], [1, 0.35], {...clamp, easing: easeInOut})})`,
            opacity: interpolate(frame, [DROP_IN, DROP_IN + 6, LANDED], [1, 1, 0], clamp),
          }}
        >
          <DragImage x={BOX.x - 14} y={BOX.y - 22} label={label} kind="pdf" />
        </div>
      ) : null}
      {ring > 0 && ring < 1 ? (
        <div
          style={{
            position: 'absolute',
            left: ALLOW.x - 70 * ring,
            top: ALLOW.y - 70 * ring,
            width: 140 * ring,
            height: 140 * ring,
            borderRadius: '50%',
            border: `3px solid ${palette.amber}`,
            opacity: 1 - ring,
          }}
        />
      ) : null}
      <Cursor x={x} y={y} press={press} scale={0.62} />
    </>
  );
};

const Desktop = ({lang, pointer = false}: {lang: Lang; pointer?: boolean}) => {
  const frame = useCurrentFrame();
  const attached = interpolate(frame, [DROP_OUT, DROP_OUT + 16], [0, 1], {...clamp, easing: easeOut});
  const selected = frame >= GRAB_IN - 6 ? 0 : undefined;
  return (
    <div style={{position: 'absolute', left: 0, top: 0, width: SCREEN.width, height: SCREEN.height, overflow: 'hidden'}}>
      <Img
        src={staticFile('anuncio/product/wallpaper.png')}
        style={{position: 'absolute', left: -40, top: -20, width: SCREEN.width + 80, height: SCREEN.height + 60, objectFit: 'cover'}}
      />
      <FinderWindow {...FINDER} lang={lang} selectedIndex={selected} draggingIndex={frame >= GRAB_IN && frame < DROP_IN ? 0 : undefined} />
      <MailWindow {...MAIL} lang={lang} attached={attached} />
      <MenuBar lang={lang} />
      <NotchPanel lang={lang} />
      {pointer ? <Pointer lang={lang} /> : null}
    </div>
  );
};

// ─── Plano general: el MacBook con la pantalla real dentro ───
const Hero = ({lang, zoom, lift, shift = 0}: {lang: Lang; zoom: number; lift: number; shift?: number}) => (
  <AbsoluteFill style={{transform: `translate(${shift}px, ${lift}px) scale(${zoom})`, transformOrigin: `960px ${heroScreen.y}px`}}>
    <Img
      src={staticFile('anuncio/product/macbook-front.png')}
      style={{position: 'absolute', left: 0, top: -HERO.cropTop, width: 1920, height: 1280}}
    />
    <div
      style={{
        position: 'absolute',
        left: heroScreen.x,
        top: heroScreen.y,
        width: heroScreen.w,
        height: heroScreen.h,
        overflow: 'hidden',
        borderRadius: 8,
      }}
    >
      <div style={{transform: `scale(${heroStageScale})`, transformOrigin: '0 0'}}>
        <Desktop lang={lang} />
      </div>
    </div>
  </AbsoluteFill>
);

const Screen = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const shot = shotAt(frame);
  // El velo inferior se hace más denso cuanto más cerca está la cámara.
  const near = Math.min(1, Math.max(0, (shot.scale - FINDER_SHOT.scale) / (CLOSE.scale - FINDER_SHOT.scale)));
  return (
    <AbsoluteFill style={{backgroundColor: '#050404', overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          left: 960 - shot.fx * shot.scale,
          top: shot.top,
          transform: `scale(${shot.scale})`,
          transformOrigin: '0 0',
        }}
      >
        <Desktop lang={lang} pointer />
      </div>
      {/* Velo inferior para los titulares */}
      <AbsoluteFill
        style={{
          opacity: interpolate(frame, [bar(4), bar(4) + 30], [0, 1], {...clamp, easing: smoother}),
          background: `linear-gradient(180deg, transparent ${lerp(66, 50, near)}%, rgba(16,14,12,${lerp(0.7, 0.74, near)}) ${lerp(82, 70, near)}%, rgba(16,14,12,${lerp(0.92, 0.95, near)}) 100%)`,
        }}
      />
    </AbsoluteFill>
  );
};

const Signature = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const pop = (at: number) => spring({frame: frame - at, fps, config: {damping: 16, mass: 0.5, stiffness: 260}});
  const icon = pop(0);
  const name = pop(8);
  const line = pop(16);
  const meta = pop(26);
  return (
    <AbsoluteFill
      style={{
        backgroundColor: palette.ink,
        backgroundImage: 'radial-gradient(ellipse at 50% 40%, rgba(233,165,74,.14), transparent 50%)',
        fontFamily: system,
        color: palette.paper,
        alignItems: 'center',
      }}
    >
      <Img
        src={staticFile('icon/AltilloIconMaster-11A.png')}
        style={{
          position: 'absolute',
          top: 170,
          width: 360,
          height: 360,
          borderRadius: 80,
          boxShadow: '0 30px 80px rgba(0,0,0,.5)',
          opacity: Math.min(1, icon * 2),
          transform: `translateY(${(1 - icon) * 50}px) scale(${0.7 + icon * 0.3})`,
        }}
      />
      <div style={{position: 'absolute', top: 580, fontSize: 108, fontWeight: 650, letterSpacing: '-4px', opacity: Math.min(1, name * 2), transform: `translateY(${(1 - name) * 30}px)`}}>
        Altillo
      </div>
      <div style={{position: 'absolute', top: 720, fontSize: 40, fontWeight: 500, letterSpacing: '-.5px', color: '#D8CBB6', opacity: Math.min(1, line * 2), transform: `translateY(${(1 - line) * 24}px)`}}>
        {COPY[lang].line}
      </div>
      <div style={{position: 'absolute', top: 880, fontSize: 26, fontWeight: 600, color: palette.amber, opacity: Math.min(1, meta * 2), transform: `translateY(${(1 - meta) * 18}px)`}}>
        {COPY[lang].meta}
      </div>
    </AbsoluteFill>
  );
};

const HelloScene = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const exit = interpolate(frame, [T.heroIn - 12, T.heroIn + 2], [0, 1], {...clamp, easing: easeInOut});
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink, opacity: 1 - exit, filter: exit > 0.01 ? `blur(${exit * 12}px)` : undefined}}>
      <Hello word={lang === 'es' ? 'hola' : 'hello'} startFrame={4} drawFrames={72} />
    </AbsoluteFill>
  );
};

const Stage = ({lang}: {lang: Lang}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const zoomIn = interpolate(frame, [...T.zoomIn], [0, 1], {...clamp, easing: smoother});
  const zoomOut = interpolate(frame, [...T.zoomOut], [1, 0], {...clamp, easing: easeInOut});
  const entering = frame < T.zoomOut[0];
  // La entrada acaba en el plano amplio del escritorio; la salida parte del primer plano del notch.
  const target = entering ? FINDER_SHOT : CLOSE;
  const amount = entering ? zoomIn : zoomOut;
  const heroZoom = lerp(1, target.scale / heroStageScale, amount);
  // Desplazamiento lateral para que el encuadre de llegada centre su punto x.
  const heroShift = (C - target.fx) * target.scale * amount;
  const heroLift = (target.top - heroScreen.y) * amount + 64 * (1 - amount);
  const inScreen = frame >= T.zoomIn[1] && frame < T.zoomOut[0];
  const settle = interpolate(frame, [T.heroIn, T.heroIn + 54], [0, 1], {...clamp, easing: smoother});
  const base = entering ? lerp(0.9, 0.8, settle) : 0.8;
  const push = entering
    ? frame < T.zoomIn[0] ? base : lerp(0.8, 1, zoomIn)
    : lerp(0.8, 1, zoomOut);
  const heroOpacity = interpolate(frame, [T.heroIn - 2, T.heroIn + 6], [0, 1], clamp);
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink}}>
      {inScreen ? (
        <Screen lang={lang} />
      ) : (
        // Bordes de la foto fundidos con el negro; la máscara no escala y se abre al entrar en la pantalla.
        <AbsoluteFill style={{opacity: heroOpacity, WebkitMaskImage: `radial-gradient(ellipse ${58 + 160 * amount}% ${62 + 160 * amount}% at 50% 42%, #000 72%, transparent 100%)`}}>
          <AbsoluteFill style={{transform: `scale(${push})`, transformOrigin: `960px ${heroScreen.y}px`}}>
            <Hero lang={lang} zoom={heroZoom} lift={heroLift} shift={heroShift} />
          </AbsoluteFill>
        </AbsoluteFill>
      )}
    </AbsoluteFill>
  );
};

export const AltilloAnuncio = ({lang = 'es', score = 'b'}: {lang?: Lang; score?: Score}) => {
  const c = COPY[lang];
  const beats = (from: number, words: string[], step = B): Array<[number, string]> => words.map((w, i) => [from + i * step, w]);
  const line = (from: number, to: number, name: string, node: (d: number) => ReactNode) => (
    <Sequence from={from} durationInFrames={to - from} name={name}>
      {node(to - from)}
    </Sequence>
  );
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink}}>
      <Sequence from={0} name="MacBook y escritorio">
        <Stage lang={lang} />
      </Sequence>
      <Sequence from={0} durationInFrames={T.heroIn + 4} name="hola">
        <HelloScene lang={lang} />
      </Sequence>

      {line(T.heroIn, bar(3, 3) + 8, 'Titular · altillo', (d) => <Kinetic parts={beats(0, c.hero)} sub={c.heroSub} subAt={B * 4} duration={d} />)}
      {line(bar(4) + 20, bar(6) - 4, 'Titular · súbelo', (d) => <Kinetic parts={beats(0, c.shelfIn)} duration={d} />)}
      {line(bar(6) + 20, bar(7, 4), 'Titular · bájalo', (d) => <Kinetic parts={beats(0, c.shelfOut)} duration={d} />)}
      {line(bar(8) + 10, bar(10) - 4, 'Titular · uso', (d) => <Kinetic parts={beats(0, c.usage)} sub={c.usageSub} subAt={B * 2} duration={d} />)}
      {line(bar(10) + 10, bar(11), 'Titular · pregunta', (d) => <Kinetic parts={beats(0, c.ask)} sub={c.askSub} subAt={B * 2} duration={d} />)}
      {line(bar(11, 2), bar(12), 'Titular · toc toc', (d) => <Kinetic parts={[[0, c.knock]]} duration={d} size={120} />)}
      {line(bar(12) + 6, bar(14) - 2, 'Titular · agentes', (d) => <Kinetic parts={beats(0, c.agents)} sub={c.agentsSub} subAt={bar(13) - bar(12) - 6} duration={d} />)}
      {c.montage.map((word, i) => (
        <Sequence key={word} from={MONTAGE_START + i * HALF} durationInFrames={HALF} name={`Montaje · ${word}`}>
          <Kinetic parts={[[0, word]]} duration={HALF * 8} size={104} />
        </Sequence>
      ))}

      <Sequence from={T.signature} name="Firma">
        <Signature lang={lang} />
      </Sequence>

      <Audio src={staticFile(`anuncio/audio/score-${score}.wav`)} />
    </AbsoluteFill>
  );
};
