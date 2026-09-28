import type {PropsWithChildren} from 'react';
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  staticFile,
  useCurrentFrame,
} from 'remotion';

// «Miniatura»: película stop motion de un set en miniatura dentro del notch.
// Fotogramas clave: imagen generada (gpt-image, public/stopmotion/keys).
// Animación: Grok Imagine image_to_video a 720p (public/stopmotion/grok720).
// Tratamiento stop motion con ffmpeg (public/stopmotion/process.sh):
// 12 fps a doses, vibración del set, parpadeo y grano. Texto e icono a 1080p.
export const MINIATURA_FPS = 24;
export const MINIATURA_FRAMES = 32 * MINIATURA_FPS;

type Lang = 'es' | 'en';

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);
const paper = '#F6EFE3';
const charcoal = '#100E0C';
const amber = '#E9A54A';
const fontFamily = '"Helvetica Neue", Helvetica, Arial, sans-serif';

// El movimiento del texto también se anima «a doses» para convivir con el set.
const onTwos = (frame: number) => Math.floor(frame / 2) * 2;
const boil = (frame: number, seed: number) => {
  const step = Math.floor(frame / 2);
  return Math.sin(step * 78.233 + seed) * 0.7;
};

const COPY = {
  es: {
    attic: 'Tu Mac ya tenía un altillo.',
    door: 'Solo le faltaba una puerta.',
    shelf: 'Deja arriba lo que quieras a mano.',
    agents: 'Tus agentes llaman antes de entrar.',
    line: 'Un sitio arriba para lo importante.',
    meta: 'Código abierto · macOS · altillo.app',
  },
  en: {
    attic: 'Your Mac already had an attic.',
    door: 'It just needed a door.',
    shelf: 'Keep what you need up top.',
    agents: 'Your agents knock before they come in.',
    line: 'A place up top for what matters.',
    meta: 'Open source · macOS · altillo.app',
  },
} satisfies Record<Lang, Record<string, string>>;

// Planos: [inicio, duración, fundido de entrada, recorte inicial, velocidad]
const SHOTS = [
  {file: 's1-establish', from: 0, duration: 102, fadeIn: 0, trim: 0, rate: 1},
  {file: 's2-ladder', from: 96, duration: 138, fadeIn: 6, trim: 4, rate: 1},
  {file: 's3-door', from: 228, duration: 102, fadeIn: 6, trim: 0, rate: 1.4},
  {file: 's4-attic', from: 322, duration: 116, fadeIn: 8, trim: 14, rate: 1},
  {file: 's5-robot', from: 432, duration: 138, fadeIn: 6, trim: 0, rate: 1},
  {file: 's6-close', from: 564, duration: 96, fadeIn: 6, trim: 34, rate: 1},
] as const;
const SIGNATURE_START = 648;

const Shot = ({file, fadeIn, trim, rate}: {
  file: string;
  fadeIn: number;
  trim: number;
  rate: number;
}) => {
  const frame = useCurrentFrame();
  const opacity = fadeIn === 0 ? 1 : interpolate(frame, [0, fadeIn], [0, 1], clamp);
  return (
    <AbsoluteFill style={{opacity}}>
      <OffthreadVideo
        src={staticFile(`stopmotion/shots/${file}.mp4`)}
        muted
        trimBefore={trim}
        playbackRate={rate}
        style={{width: '100%', height: '100%', objectFit: 'cover'}}
      />
      {/* Destello cálido al atravesar la puerta hacia el desván */}
      {fadeIn >= 8 ? (
        <AbsoluteFill
          style={{
            background: 'radial-gradient(ellipse at 50% 45%, rgba(255,196,110,.55), rgba(233,165,74,0) 62%)',
            opacity: interpolate(frame, [0, 4, 18], [0.8, 1, 0], clamp),
            mixBlendMode: 'screen',
          }}
        />
      ) : null}
    </AbsoluteFill>
  );
};

const Caption = ({children, duration}: PropsWithChildren<{duration: number}>) => {
  const raw = useCurrentFrame();
  const frame = onTwos(raw);
  const reveal = interpolate(frame, [0, 14], [0, 1], {...clamp, easing: ease});
  const opacity = interpolate(frame, [0, 10, duration - 12, duration - 1], [0, 1, 1, 0], clamp);
  return (
    <AbsoluteFill style={{justifyContent: 'flex-end', alignItems: 'center', opacity}}>
      <AbsoluteFill
        style={{background: 'linear-gradient(180deg, transparent 60%, rgba(10,8,6,.18) 74%, rgba(10,8,6,.66) 100%)'}}
      />
      <div
        style={{
          position: 'relative',
          marginBottom: 96,
          fontFamily,
          fontSize: 56,
          lineHeight: 1.2,
          fontWeight: 400,
          letterSpacing: '-1.4px',
          color: paper,
          textAlign: 'center',
          transform: `translate(${boil(raw, 1.7)}px, ${(1 - reveal) * 12 + boil(raw, 4.1)}px)`,
          textShadow: '0 2px 18px rgba(0,0,0,.3)',
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};

const Signature = ({lang}: {lang: Lang}) => {
  const raw = useCurrentFrame();
  const frame = onTwos(raw);
  const bg = interpolate(raw, [0, 14], [0, 1], clamp);
  const icon = interpolate(frame, [6, 30], [0, 1], {...clamp, easing: ease});
  const name = interpolate(frame, [16, 34], [0, 1], clamp);
  const line = interpolate(frame, [30, 50], [0, 1], clamp);
  const meta = interpolate(frame, [46, 64], [0, 1], clamp);
  const glow = 0.1 + 0.03 * Math.sin(Math.floor(raw / 2) * 0.9);

  return (
    <AbsoluteFill
      style={{
        opacity: bg,
        backgroundColor: charcoal,
        backgroundImage: `radial-gradient(ellipse at 50% 38%, rgba(233,165,74,${glow}), transparent 46%)`,
        color: paper,
        fontFamily,
        alignItems: 'center',
      }}
    >
      <Img
        src={staticFile('icon/AltilloIconMaster-11A.png')}
        style={{
          position: 'absolute',
          width: 420,
          height: 420,
          top: 150,
          // El máster es opaco y cuadrado: se aplica la máscara de icono de macOS.
          borderRadius: 94,
          boxShadow: '0 24px 60px rgba(0,0,0,.45)',
          opacity: icon,
          transform: `translate(${boil(raw, 2.2) * 0.6}px, ${(1 - icon) * 16}px) rotate(${boil(raw, 7.3) * 0.25}deg)`,
        }}
      />
      <div style={{position: 'absolute', top: 592, fontSize: 100, fontWeight: 500, lineHeight: 1, letterSpacing: '-5px', opacity: name}}>
        Altillo
      </div>
      <div style={{position: 'absolute', top: 728, fontSize: 34, lineHeight: 1.4, letterSpacing: '-.3px', color: '#D8CBB6', opacity: line}}>
        {COPY[lang].line}
      </div>
      <div style={{position: 'absolute', top: 902, fontSize: 22, letterSpacing: '.2px', color: amber, opacity: meta * 0.9}}>
        {COPY[lang].meta}
      </div>
    </AbsoluteFill>
  );
};

const Sfx = ({src, from, volume = 0.6}: {src: string; from: number; volume?: number}) => (
  <Sequence from={from} name={`SFX · ${src}`}>
    <Audio src={staticFile(`stopmotion/audio/${src}`)} volume={volume} />
  </Sequence>
);

export const AltilloMiniatura = ({lang = 'es'}: {lang?: Lang}) => {
  const copy = COPY[lang];
  return (
    <AbsoluteFill style={{backgroundColor: charcoal}}>
      {SHOTS.map((shot) => (
        <Sequence key={shot.file} from={shot.from} durationInFrames={shot.duration} name={shot.file}>
          <Shot {...shot} />
        </Sequence>
      ))}

      <Sequence from={10} durationInFrames={84} name="Texto · altillo">
        <Caption duration={84}>{copy.attic}</Caption>
      </Sequence>
      <Sequence from={110} durationInFrames={110} name="Texto · puerta">
        <Caption duration={110}>{copy.door}</Caption>
      </Sequence>
      <Sequence from={338} durationInFrames={90} name="Texto · estante">
        <Caption duration={90}>{copy.shelf}</Caption>
      </Sequence>
      <Sequence from={446} durationInFrames={108} name="Texto · agentes">
        <Caption duration={108}>{copy.agents}</Caption>
      </Sequence>

      <Sequence from={SIGNATURE_START} name="Firma">
        <Signature lang={lang} />
      </Sequence>

      <Audio src={staticFile('stopmotion/audio/score.wav')} />
      {/* Efectos sintetizados en local: solo los de acción física clara y a volumen bajo. */}
      <Sfx src="paper-rustle.wav" from={118} volume={0.45} />
      <Sfx src="paper-rustle.wav" from={336} volume={0.35} />
      <Sfx src="tick.wav" from={396} volume={0.35} />
      <Sfx src="knock.wav" from={482} volume={0.7} />
      <Sfx src="latch-click.wav" from={632} volume={0.5} />
    </AbsoluteFill>
  );
};
