import type {CSSProperties, PropsWithChildren} from 'react';
import {AltilloProductDemo} from './AltilloProductDemo';
import {
  AbsoluteFill,
  Easing,
  Img,
  interpolate,
  OffthreadVideo,
  Sequence,
  staticFile,
  useCurrentFrame,
} from 'remotion';

// The film is deliberately footage-led. No simulated product UI, invented
// features, CSS scenery or regenerated brand artwork is used in this edit.
// Native Grok Imagine clips, generated through the authenticated Grok Build CLI.
// Original 1264x720 / 24fps clips are preserved in film/source; the edit uses
// normalized 8-second / 30fps copies. Typography and brand artwork render at 1080p.
export const LA_PUERTA_DURATION = 28 * 30;
const SHOT_DURATION = 8 * 30;
const CLOSING_START = 24 * 30;
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);
const paper = '#F6EFE3';
const charcoal = '#100E0C';
const fontFamily = '"Helvetica Neue", Helvetica, Arial, sans-serif';

const videoStyle: CSSProperties = {
  width: '100%',
  height: '100%',
  objectFit: 'cover',
};

const Footage = ({file, opening = false, closing = false}: {
  file: string;
  opening?: boolean;
  closing?: boolean;
}) => {
  const frame = useCurrentFrame();
  const opacity = opening
    ? interpolate(frame, [0, 18], [0, 1], clamp)
    : closing
      ? interpolate(frame, [SHOT_DURATION - 22, SHOT_DURATION - 1], [1, 0], clamp)
      : 1;

  return (
    <AbsoluteFill style={{opacity}}>
      <OffthreadVideo
        src={staticFile(`film/${file}`)}
        style={videoStyle}
        trimAfter={SHOT_DURATION}
        volume={(audioFrame) => interpolate(
          audioFrame,
          [0, opening ? 18 : 3, SHOT_DURATION - (closing ? 24 : 4), SHOT_DURATION - 1],
          [0, 1, 1, 0],
          clamp,
        )}
      />
    </AbsoluteFill>
  );
};

const FilmTitle = ({children, duration}: PropsWithChildren<{duration: number}>) => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [0, 22], [0, 1], {...clamp, easing: ease});
  const opacity = interpolate(frame, [0, 16, duration - 18, duration - 1], [0, 1, 1, 0], clamp);

  return (
    <AbsoluteFill style={{opacity, justifyContent: 'flex-end', alignItems: 'center'}}>
      <AbsoluteFill
        style={{
          background: 'linear-gradient(180deg, transparent 58%, rgba(10,8,6,.08) 70%, rgba(10,8,6,.62) 100%)',
        }}
      />
      <div
        style={{
          position: 'relative',
          marginBottom: 94,
          fontFamily,
          fontSize: 55,
          lineHeight: 1.2,
          fontWeight: 400,
          letterSpacing: '-1.35px',
          color: paper,
          textAlign: 'center',
          transform: `translateY(${(1 - reveal) * 10}px)`,
          textShadow: '0 2px 18px rgba(0,0,0,.24)',
        }}
      >
        {children}
      </div>
    </AbsoluteFill>
  );
};

const Signature = () => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [0, 28], [0, 1], {...clamp, easing: ease});
  const nameOpacity = interpolate(frame, [8, 28], [0, 1], clamp);
  const lineOpacity = interpolate(frame, [24, 45], [0, 1], clamp);

  return (
    <AbsoluteFill
      style={{
        backgroundColor: charcoal,
        color: paper,
        fontFamily,
        alignItems: 'center',
        backgroundImage: 'radial-gradient(ellipse at 50% 43%, rgba(94,60,25,.07), transparent 48%)',
      }}
    >
      <Img
        src={staticFile('icon/AltilloIconMaster-11A.png')}
        style={{
          position: 'absolute',
          width: 490,
          height: 490,
          top: 131,
          opacity: reveal,
          transform: `translateY(${(1 - reveal) * 14}px)`,
        }}
      />
      <div
        style={{
          position: 'absolute',
          top: 608,
          fontSize: 103,
          fontWeight: 500,
          lineHeight: 1,
          letterSpacing: '-5.4px',
          opacity: nameOpacity,
        }}
      >
        Altillo
      </div>
      <div
        style={{
          position: 'absolute',
          top: 752,
          fontSize: 31,
          lineHeight: 1.4,
          fontWeight: 400,
          letterSpacing: '-.25px',
          color: '#CABDA9',
          opacity: lineOpacity,
        }}
      >
        Un sitio arriba para lo importante.
      </div>
    </AbsoluteFill>
  );
};

export const AltilloLaPuerta = ({productDemo=false}:{productDemo?:boolean}) => (
  <AbsoluteFill style={{backgroundColor: charcoal}}>
    <Sequence from={0} durationInFrames={SHOT_DURATION} name="01 · La puerta">
      <Footage file="01-door.mp4" opening />
    </Sequence>
    <Sequence from={SHOT_DURATION} durationInFrames={productDemo ? 600 : SHOT_DURATION} name={productDemo ? '02 · Altillo en acción' : '02 · El altillo'}>
      {productDemo ? <AltilloProductDemo/> : <Footage file="02-attic.mp4" />}
    </Sequence>
    <Sequence from={productDemo ? 840 : SHOT_DURATION * 2} durationInFrames={SHOT_DURATION} name="03 · Volver arriba">
      <Footage file="03-return.mp4" closing />
    </Sequence>

    <Sequence from={30} durationInFrames={94} name="Tu Mac ya tenía un altillo.">
      <FilmTitle duration={94}>Tu Mac ya tenía un altillo.</FilmTitle>
    </Sequence>
    <Sequence from={135} durationInFrames={104} name="Solo le faltaba una puerta.">
      <FilmTitle duration={104}>Solo le faltaba una puerta.</FilmTitle>
    </Sequence>

    <Sequence from={productDemo ? 1080 : CLOSING_START} durationInFrames={120} name="Altillo · Firma 11A">
      <Signature />
    </Sequence>
  </AbsoluteFill>
);
