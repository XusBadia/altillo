import type {CSSProperties, PropsWithChildren} from 'react';
import {Easing, interpolate, spring, useCurrentFrame, useVideoConfig} from 'remotion';

// Piezas compartidas del anuncio: tipografía, barra de menús, cursor y aperturas del notch.
export const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
export const easeOut = Easing.bezier(0.22, 1, 0.36, 1);
export const easeInOut = Easing.bezier(0.65, 0, 0.35, 1);
export const system = 'system-ui, -apple-system, "SF Pro Display", "Helvetica Neue", sans-serif';
export const palette = {
  ink: '#100E0C',
  paper: '#F6EFE3',
  muted: '#A99C88',
  amber: '#E9A54A',
};

// Pantalla de un MacBook Pro 14" en puntos: el escenario donde vive el notch.
export const SCREEN = {width: 1512, height: 982, menuBar: 32};

/** Titular estilo Apple: entra con desenfoque y sube; sale con un fundido corto. */
export const Headline = ({children, sub, duration, style}: PropsWithChildren<{
  sub?: string;
  duration: number;
  style?: CSSProperties;
}>) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const inT = interpolate(frame, [0, 0.7 * fps], [0, 1], {...clamp, easing: easeOut});
  const subT = interpolate(frame, [0.25 * fps, 0.95 * fps], [0, 1], {...clamp, easing: easeOut});
  const out = interpolate(frame, [duration - 0.35 * fps, duration], [1, 0], clamp);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 112,
        textAlign: 'center',
        fontFamily: system,
        color: palette.paper,
        opacity: out,
        ...style,
      }}
    >
      <div
        style={{
          fontSize: 76,
          fontWeight: 600,
          letterSpacing: '-2.2px',
          lineHeight: 1.06,
          opacity: inT,
          filter: `blur(${(1 - inT) * 12}px)`,
          transform: `translateY(${(1 - inT) * 26}px)`,
        }}
      >
        {children}
      </div>
      {sub ? (
        <div
          style={{
            marginTop: 18,
            fontSize: 34,
            fontWeight: 500,
            letterSpacing: '-.4px',
            color: palette.muted,
            opacity: subT,
            filter: `blur(${(1 - subT) * 8}px)`,
            transform: `translateY(${(1 - subT) * 16}px)`,
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};

/** Barra de menús de macOS Tahoe, translúcida sobre el fondo de pantalla. */
export const MenuBar = ({lang}: {lang: 'es' | 'en'}) => {
  const items = lang === 'es' ? ['Finder', 'Archivo', 'Edición', 'Visualización', 'Ir', 'Ventana', 'Ayuda'] : ['Finder', 'File', 'Edit', 'View', 'Go', 'Window', 'Help'];
  return (
    <div
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: SCREEN.width,
        height: SCREEN.menuBar,
        display: 'flex',
        alignItems: 'center',
        gap: 20,
        padding: '0 16px',
        fontFamily: system,
        fontSize: 13.5,
        fontWeight: 500,
        color: 'rgba(255,255,255,.94)',
        background: 'rgba(0,0,0,.10)',
        textShadow: '0 1px 2px rgba(0,0,0,.25)',
      }}
    >
      <svg width="14" height="16" viewBox="0 0 14 17" fill="white" style={{marginRight: 2}}>
        <path d="M11.6 9c0-2 1.6-3 1.7-3-1-1.4-2.4-1.6-2.9-1.6-1.2-.1-2.4.7-3 .7s-1.6-.7-2.6-.7C3.4 4.4 1.2 5.9 1.2 9c0 1 .2 2 .5 3 .5 1.4 2 4.6 3.5 4.6.8 0 1.4-.6 2.5-.6s1.6.6 2.5.6c1.5 0 2.8-2.9 3.3-4.3-2-.9-1.9-2.7-1.9-3.3zM9.7 3.2C10.5 2.2 10.4 1 10.4.6c-.8 0-1.8.5-2.3 1.2-.6.7-.9 1.5-.8 2.4.9.1 1.8-.4 2.4-1z" />
      </svg>
      {items.map((item, i) => (
        <span key={item} style={{fontWeight: i === 0 ? 700 : 500}}>{item}</span>
      ))}
      <div style={{flex: 1}} />
      <svg width="18" height="13" viewBox="0 0 18 13" fill="none" stroke="white" strokeWidth="1.6" strokeLinecap="round">
        <path d="M1.5 4.5a11 11 0 0 1 15 0M4 7.3a7.3 7.3 0 0 1 10 0M6.6 10a3.4 3.4 0 0 1 4.8 0" />
      </svg>
      <svg width="26" height="12" viewBox="0 0 26 12">
        <rect x=".75" y=".75" width="21.5" height="10.5" rx="3" fill="none" stroke="white" strokeOpacity=".5" strokeWidth="1.2" />
        <rect x="2.4" y="2.4" width="14" height="7.2" rx="1.6" fill="white" />
        <rect x="23.4" y="4" width="1.8" height="4" rx=".9" fill="white" fillOpacity=".5" />
      </svg>
      <span>{lang === 'es' ? 'jue 1 oct  10:24' : 'Thu Oct 1  10:24'}</span>
    </div>
  );
};

/** Cursor de flecha de macOS (con sombra); `press` lo encoge un poco al hacer clic. */
export const Cursor = ({x, y, press = 0, scale = 1}: {x: number; y: number; press?: number; scale?: number}) => (
  <svg
    width={28 * scale}
    height={40 * scale}
    viewBox="0 0 28 40"
    style={{
      position: 'absolute',
      left: x - 3 * scale,
      top: y - 2 * scale,
      transform: `scale(${1 - press * 0.12})`,
      transformOrigin: '3px 2px',
      filter: 'drop-shadow(0 2px 3px rgba(0,0,0,.35))',
      overflow: 'visible',
    }}
  >
    <path d="M3 2 L3 31 L10 24.5 L14.6 35.3 L19.2 33.4 L14.7 22.8 L24 22.8 Z" fill="black" stroke="white" strokeWidth="2.2" strokeLinejoin="round" />
  </svg>
);

/** Muelle de apertura del notch (≈270 ms con un pequeño rebote, como la app). */
export const useOpenSpring = (from: number, damping = 16) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  return spring({frame: frame - from, fps, config: {damping, mass: 0.7, stiffness: 190}});
};

/** Titular cinético: cada trozo entra con muelle en su golpe; sale rápido hacia arriba. */
export const Kinetic = ({parts, sub, subAt = 0, duration, size = 92, style}: {
  parts: Array<[number, string]>;
  sub?: string;
  subAt?: number;
  duration: number;
  size?: number;
  style?: CSSProperties;
}) => {
  const frame = useCurrentFrame();
  const {fps} = useVideoConfig();
  const out = interpolate(frame, [duration - 9, duration], [0, 1], {...clamp, easing: easeInOut});
  const pop = (at: number) => spring({frame: frame - at, fps, config: {damping: 14, mass: 0.5, stiffness: 320}});
  const s = pop(subAt);
  return (
    <div
      style={{
        position: 'absolute',
        left: 0,
        right: 0,
        bottom: 104,
        textAlign: 'center',
        fontFamily: system,
        color: palette.paper,
        opacity: 1 - out,
        filter: out > 0.01 ? `blur(${out * 14}px)` : undefined,
        transform: `translateY(${-out * 40}px)`,
        ...style,
      }}
    >
      <div style={{fontSize: size, fontWeight: 650, letterSpacing: `${-size * 0.03}px`, lineHeight: 1.04}}>
        {parts.map(([at, text], i) => {
          const p = pop(at);
          return (
            <span
              key={i}
              style={{
                display: 'inline-block',
                marginRight: i < parts.length - 1 ? '0.26em' : 0,
                opacity: Math.min(1, p * 1.6),
                filter: p < 0.98 ? `blur(${(1 - Math.min(1, p)) * 10}px)` : undefined,
                transform: `translateY(${(1 - p) * 36}px) scale(${1.14 - 0.14 * p})`,
              }}
            >
              {text}
            </span>
          );
        })}
      </div>
      {sub ? (
        <div
          style={{
            marginTop: 16,
            fontSize: size * 0.4,
            fontWeight: 500,
            letterSpacing: '-.4px',
            color: palette.muted,
            opacity: Math.min(1, s * 1.5),
            transform: `translateY(${(1 - s) * 18}px)`,
          }}
        >
          {sub}
        </div>
      ) : null}
    </div>
  );
};
