import {AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {UI_BOXES} from './ui-manifest';
import {palette, system} from './parts';

// Piezas para Product Hunt que no salen del anuncio: resumen de funciones, cierre «gratis y abierto» y miniatura.
// La galería de Product Hunt es de 1270×760; la miniatura, de 240×240 (GIF de menos de 3 MB).
type Scenario = keyof typeof UI_BOXES;

const background = {
  backgroundColor: palette.ink,
  backgroundImage: 'radial-gradient(ellipse at 50% 0%, rgba(233,165,74,.16), transparent 60%)',
  fontFamily: system,
  color: palette.paper,
};

// Un estado real del notch recortado a su forma, escalado a `width`.
const Notch = ({state, width, maxHeight}: {state: Scenario; width: number; maxHeight?: number}) => {
  const [x0, y0, x1, y1] = UI_BOXES[state].en;
  const k = width / (x1 - x0);
  const height = Math.min((y1 - y0) * k, maxHeight ?? Infinity);
  return (
    <div style={{width, height, overflow: 'hidden', position: 'relative', borderRadius: maxHeight ? '0 0 22px 22px' : undefined}}>
      <Img
        src={staticFile(`anuncio/ui/en/${state}.png`)}
        style={{position: 'absolute', left: -x0 * k, top: -y0 * k, width: 780 * k, height: 440 * k}}
      />
    </div>
  );
};

const FEATURES: Array<{state: Scenario; title: string; line: string}> = [
  {state: 'openNowPlaying', title: 'Now Playing', line: 'Control whatever is playing.'},
  {state: 'openCalendar', title: 'Calendar', line: 'Your day, and a Join button.'},
  {state: 'openDrawer', title: 'Drawer', line: 'Tuck menu bar icons away.'},
  {state: 'peekAlert', title: 'Glances', line: 'A meeting in 5 minutes? It tells you.'},
  {state: 'peekUsageAlert', title: 'Limits', line: 'Before Claude runs out, not after.'},
  {state: 'peekShelf', title: 'Shelf', line: 'Six things waiting up there.'},
];

export const PHFeatures = () => (
  <AbsoluteFill style={{...background, padding: '0 70px', justifyContent: 'center'}}>
    <div style={{fontSize: 54, fontWeight: 650, letterSpacing: '-1.6px', textAlign: 'center'}}>All of it, right up there.</div>
    <div style={{fontSize: 24, color: palette.muted, textAlign: 'center', marginTop: 10}}>
      And the shelf, AI usage, live agents and Ask.
    </div>
    <div style={{display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: '30px 30px', marginTop: 40}}>
      {FEATURES.map(({state, title, line}) => (
        <div key={state} style={{display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
          <div style={{height: state.startsWith('peek') ? 58 : 196, display: 'flex', alignItems: 'flex-start', justifyContent: 'center'}}>
            <Notch state={state} width={state.startsWith('peek') ? 340 : 350} maxHeight={state === 'openDrawer' ? 86 : undefined} />
          </div>
          <div style={{fontSize: 22, fontWeight: 650, marginTop: 6}}>{title}</div>
          <div style={{fontSize: 17, color: palette.muted, marginTop: 4}}>{line}</div>
        </div>
      ))}
    </div>
  </AbsoluteFill>
);

const PROMISES = [
  ['Native', 'Swift 6, made for macOS 26.'],
  ['Private', 'Your files and credentials stay on your Mac.'],
  ['In control', 'Altillo never approves anything for you.'],
];

export const PHOpen = () => (
  <AbsoluteFill style={{...background, alignItems: 'center', justifyContent: 'center'}}>
    <Img
      src={staticFile('icon/AltilloIconMaster-11A.png')}
      style={{width: 200, height: 200, borderRadius: 45, boxShadow: '0 24px 60px rgba(0,0,0,.5)'}}
    />
    <div style={{fontSize: 66, fontWeight: 650, letterSpacing: '-2px', marginTop: 36}}>Free forever. Open source.</div>
    <div style={{display: 'flex', gap: 56, marginTop: 44}}>
      {PROMISES.map(([title, line]) => (
        <div key={title} style={{width: 280, textAlign: 'center'}}>
          <div style={{fontSize: 24, fontWeight: 650, color: palette.amber}}>{title}</div>
          <div style={{fontSize: 19, color: '#D8CBB6', marginTop: 8, lineHeight: 1.35}}>{line}</div>
        </div>
      ))}
    </div>
    <div style={{fontSize: 22, color: palette.muted, marginTop: 52}}>altillo.app · github.com/XusBadia/altillo · MIT</div>
  </AbsoluteFill>
);

// Miniatura: el icono con la luz del altillo respirando despacio (sin destellos; bucle de 3 s).
export const PH_THUMB_FRAMES = 90;
export const PHThumb = () => {
  const frame = useCurrentFrame();
  const glow = 0.5 - 0.5 * Math.cos((frame / PH_THUMB_FRAMES) * Math.PI * 2);
  const lift = interpolate(glow, [0, 1], [0, -3]);
  return (
    <AbsoluteFill style={{backgroundColor: palette.ink, alignItems: 'center', justifyContent: 'center'}}>
      <div
        style={{
          position: 'absolute',
          width: 220,
          height: 220,
          borderRadius: '50%',
          background: `radial-gradient(circle, rgba(233,165,74,${0.18 + glow * 0.22}), transparent 65%)`,
        }}
      />
      <Img
        src={staticFile('icon/AltilloIconMaster-11A.png')}
        style={{width: 176, height: 176, borderRadius: 40, transform: `translateY(${lift}px)`, filter: `brightness(${1 + glow * 0.08})`}}
      />
    </AbsoluteFill>
  );
};
