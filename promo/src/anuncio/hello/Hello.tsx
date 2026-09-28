import {AbsoluteFill, Easing, interpolate, useCurrentFrame, useVideoConfig} from 'remotion';
import {HELLO_GLYPHS, type HelloWord} from './glyphs';

// «hola» escrito a mano, trazo a trazo, en cursiva monolínea.
// El trazo se revela con stroke-dashoffset; la fracción dibujada sale de la
// tabla `timing` (generada offline) para que la mano frene en las curvas.
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const cream = '#F6EFE3';
const amber = '#E9A54A';
const STROKE_WIDTH = 24;
const STROKE_PAUSE_S = 0.14; // pausa entre trazos sueltos (puntos, cruces)
const EXIT_S = 0.7;

// Interpola la tabla de tiempo → fracción de longitud.
const sampleTiming = (timing: readonly number[], t: number) => {
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  const x = t * (timing.length - 1);
  const i = Math.floor(x);
  return timing[i] + (timing[i + 1] - timing[i]) * (x - i);
};

export const Hello = ({
  word = 'hola',
  startFrame = 0,
  drawFrames,
  exitFrame,
  strokeWidth = STROKE_WIDTH,
}: {
  word?: HelloWord;
  startFrame?: number;
  // Por defecto 2,7 s a los fps de la composición.
  drawFrames?: number;
  // Si se pasa, a partir de aquí se desvanece y encoge un poco.
  exitFrame?: number;
  strokeWidth?: number;
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const glyph = HELLO_GLYPHS[word];
  const total = drawFrames ?? Math.round(2.7 * fps);
  const pause = Math.round(STROKE_PAUSE_S * fps);

  // Reparte el tiempo entre trazos según su longitud, dejando pausas entre ellos.
  const strokes = glyph.strokes;
  const lengthSum = strokes.reduce((sum, s) => sum + s.length, 0);
  const drawable = Math.max(1, total - pause * (strokes.length - 1));
  let cursor = startFrame;
  const windows = strokes.map((s) => {
    const from = cursor;
    const frames = (drawable * s.length) / lengthSum;
    cursor += frames + pause;
    return {from, frames};
  });

  // Salida: fundido + ligera reducción.
  const exitFrames = Math.round(EXIT_S * fps);
  const exit = exitFrame === undefined
    ? 0
    : interpolate(frame, [exitFrame, exitFrame + exitFrames], [0, 1], {
      ...clamp,
      easing: Easing.bezier(0.4, 0, 0.2, 1),
    });

  // Degradado que respira despacio a lo largo del trazo.
  const drift = interpolate(frame - startFrame, [0, total + 2 * fps], [-0.12, 0.06], clamp);
  // El halo crece al terminar la palabra y se asienta.
  const settle = interpolate(frame, [startFrame + total - 0.3 * fps, startFrame + total + 0.9 * fps], [0, 1], {
    ...clamp,
    easing: Easing.bezier(0.22, 1, 0.36, 1),
  });
  const glowOpacity = 0.22 + 0.12 * Math.sin(settle * Math.PI) + 0.06 * settle;

  const gradientId = `hello-gradient-${word}`;
  const glowId = `hello-glow-${word}`;
  const {width, height} = glyph;

  const paths = strokes.map((s, i) => {
    const {from, frames} = windows[i];
    const t = interpolate(frame, [from, from + frames], [0, 1], clamp);
    const drawn = sampleTiming(s.timing, t);
    return {s, drawn};
  });

  const renderStrokes = (key: string, stroke: string, widthPx: number) => paths.map(({s, drawn}, i) => (
    <path
      key={`${key}-${i}`}
      d={s.d}
      pathLength={s.length}
      fill="none"
      stroke={stroke}
      strokeWidth={widthPx}
      strokeLinecap="round"
      strokeLinejoin="round"
      strokeDasharray={`${s.length} ${s.length}`}
      strokeDashoffset={s.length * (1 - drawn)}
      opacity={drawn > 0 ? 1 : 0}
    />
  ));

  return (
    <AbsoluteFill style={{alignItems: 'center', justifyContent: 'center'}}>
      <svg
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        style={{
          overflow: 'visible',
          opacity: 1 - exit,
          transform: `scale(${1 - 0.045 * exit})`,
        }}
      >
        <defs>
          <linearGradient
            id={gradientId}
            gradientUnits="userSpaceOnUse"
            x1={width * (0.05 + drift)}
            y1={height * 0.15}
            x2={width * (0.98 + drift)}
            y2={height * 0.85}
          >
            <stop offset="0" stopColor={cream} />
            <stop offset="0.45" stopColor="#F3DDB9" />
            <stop offset="1" stopColor={amber} />
          </linearGradient>
          <filter id={glowId} x="-20%" y="-30%" width="140%" height="160%">
            <feGaussianBlur stdDeviation={strokeWidth * 0.75} />
          </filter>
        </defs>
        {/* Halo ámbar tenue bajo el trazo */}
        <g filter={`url(#${glowId})`} opacity={glowOpacity} style={{mixBlendMode: 'screen'}}>
          {renderStrokes('glow', amber, strokeWidth * 1.4)}
        </g>
        <g>{renderStrokes('ink', `url(#${gradientId})`, strokeWidth)}</g>
      </svg>
    </AbsoluteFill>
  );
};
