import React from 'react';
import {
  AbsoluteFill,
  Html5Audio,
  Img,
  interpolate,
  random,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from 'remotion';

const C = {
  ink: '#0a0806',
  wood: '#1e1914',
  wood2: '#2a231c',
  paper: '#f6efe3',
  kraft: '#c9a77c',
  bulb: '#ffb547',
  tomato: '#f2674a',
  sage: '#9db88a',
  sky: '#86b6d9',
};

const serif = 'New York, Iowan Old Style, Georgia, serif';
const sans = '-apple-system, BlinkMacSystemFont, SF Pro Rounded, Helvetica Neue, sans-serif';

const snap = (frame: number) => Math.floor(frame / 2.5) * 2.5;
const clamp = {extrapolateLeft: 'clamp' as const, extrapolateRight: 'clamp' as const};

const jitter = (frame: number, seed: string, amount = 2) => {
  const f = Math.floor(snap(frame));
  return (random(`${seed}-${f}`) - 0.5) * amount * 2;
};

const sceneOpacity = (frame: number, start: number, end: number) =>
  interpolate(frame, [start, start + 14, end - 14, end], [0, 1, 1, 0], clamp);

const paperEdge: React.CSSProperties = {
  clipPath: 'polygon(0.4% 1.5%, 11% 0.3%, 23% 1.2%, 38% 0.2%, 52% 1.4%, 69% 0.4%, 83% 1.2%, 99.4% 0.3%, 98.8% 17%, 99.7% 34%, 98.9% 52%, 99.5% 71%, 98.7% 99.1%, 84% 98.5%, 67% 99.7%, 49% 98.8%, 31% 99.5%, 14% 98.6%, 0.4% 99.4%, 1.2% 81%, 0.3% 62%, 1.1% 43%, 0.2% 22%)',
};

const Texture = () => (
  <AbsoluteFill
    style={{
      pointerEvents: 'none',
      opacity: 0.16,
      mixBlendMode: 'soft-light',
      backgroundImage:
        'repeating-linear-gradient(7deg, rgba(255,255,255,.11) 0 1px, transparent 1px 5px), repeating-linear-gradient(91deg, rgba(0,0,0,.12) 0 1px, transparent 1px 7px)',
    }}
  />
);

const Desk = ({light = 0.15}: {light?: number}) => {
  const frame = useCurrentFrame();
  const shift = jitter(frame, 'desk', 1.5);
  return (
    <AbsoluteFill
      style={{
        background:
          `radial-gradient(circle at 50% 8%, rgba(255,181,71,${light}), transparent 37%), ` +
          'radial-gradient(circle at 8% 85%, rgba(242,103,74,.11), transparent 32%), ' +
          'radial-gradient(circle at 92% 82%, rgba(134,182,217,.10), transparent 30%), ' +
          'linear-gradient(145deg, #291c13, #100c08 48%, #070504)',
        transform: `scale(1.01) translate(${shift}px, ${-shift}px)`,
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          opacity: 0.12,
          backgroundImage:
            'repeating-linear-gradient(3deg, transparent 0 31px, rgba(255,255,255,.11) 32px, transparent 34px), repeating-linear-gradient(178deg, transparent 0 73px, rgba(0,0,0,.4) 74px, transparent 77px)',
        }}
      />
      <Texture />
    </AbsoluteFill>
  );
};

const ShadowPaper = ({
  children,
  style,
  tone = C.paper,
}: React.PropsWithChildren<{style?: React.CSSProperties; tone?: string}>) => (
  <div
    style={{
      ...paperEdge,
      position: 'absolute',
      background: tone,
      color: C.ink,
      boxShadow: '12px 18px 0 rgba(0,0,0,.20), 0 28px 55px rgba(0,0,0,.28)',
      ...style,
    }}
  >
    {children}
  </div>
);

const Tape = ({style}: {style?: React.CSSProperties}) => (
  <div
    style={{
      position: 'absolute',
      width: 150,
      height: 44,
      background: 'rgba(230,205,151,.72)',
      boxShadow: '0 3px 9px rgba(0,0,0,.2)',
      opacity: 0.9,
      ...paperEdge,
      ...style,
    }}
  />
);

const PrintedScreen = ({
  src,
  style,
  rotate = -1,
}: {
  src: string;
  style?: React.CSSProperties;
  rotate?: number;
}) => {
  const frame = useCurrentFrame();
  const x = jitter(frame, `screen-${src}`, 1.4);
  const y = jitter(frame + 13, `screen-y-${src}`, 1.2);
  const r = rotate + jitter(frame + 7, `screen-r-${src}`, 0.16);
  return (
    <div
      style={{
        ...paperEdge,
        position: 'absolute',
        padding: '18px 18px 42px',
        background: '#e9dfcf',
        boxShadow: '18px 24px 0 rgba(0,0,0,.20), 0 35px 80px rgba(0,0,0,.35)',
        transform: `translate(${x}px, ${y}px) rotate(${r}deg)`,
        ...style,
      }}
    >
      <Img src={staticFile(src)} style={{display: 'block', width: '100%', borderRadius: 8}} />
      <Tape style={{left: '50%', top: -20, transform: 'translateX(-50%) rotate(1.5deg)'}} />
    </div>
  );
};

const IntroScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame);
  const {fps} = useVideoConfig();
  const laptop = spring({fps, frame: local - 8, config: {damping: 13, mass: 0.9, stiffness: 110}});
  const notchDrop = spring({fps, frame: local - 34, config: {damping: 10, stiffness: 150, mass: 0.7}});
  const titleIn = spring({fps, frame: local - 62, config: {damping: 14, stiffness: 120}});
  const zoom = interpolate(local, [0, 165], [1, 1.07], clamp);

  return (
    <AbsoluteFill style={{opacity: sceneOpacity(frame, 0, 190), transform: `scale(${zoom})`}}>
      <Desk light={0.12} />
      <div
        style={{
          position: 'absolute',
          left: 350,
          top: 185 + (1 - laptop) * 520,
          width: 1220,
          height: 720,
          transform: `rotate(${jitter(frame, 'laptop', 0.25)}deg)`,
        }}
      >
        <div
          style={{
            ...paperEdge,
            position: 'absolute',
            left: 90,
            right: 90,
            top: 0,
            height: 640,
            background: '#d8d0c6',
            boxShadow: '24px 32px 0 rgba(0,0,0,.22), 0 50px 90px rgba(0,0,0,.42)',
            padding: 24,
          }}
        >
          <div
            style={{
              position: 'relative',
              width: '100%',
              height: '100%',
              overflow: 'hidden',
              borderRadius: 18,
              background:
                'radial-gradient(circle at 15% 88%, #bd4158, transparent 32%), radial-gradient(circle at 83% 70%, #4759ba, transparent 38%), #211a31',
            }}
          >
            <div
              style={{
                position: 'absolute',
                left: '50%',
                top: -2 + (1 - notchDrop) * -150,
                width: 250,
                height: 72,
                transform: 'translateX(-50%)',
                background: '#000',
                borderRadius: '0 0 34px 34px',
                boxShadow: `0 20px 70px rgba(255,181,71,${0.08 + notchDrop * 0.15})`,
              }}
            />
          </div>
        </div>
        <div
          style={{
            ...paperEdge,
            position: 'absolute',
            bottom: 6,
            left: 0,
            width: '100%',
            height: 95,
            background: '#c8c0b6',
            transform: 'perspective(500px) rotateX(56deg)',
            boxShadow: '0 28px 40px rgba(0,0,0,.34)',
          }}
        />
      </div>

      <ShadowPaper
        style={{
          left: 126,
          top: 122,
          padding: '22px 30px',
          transform: `translateY(${(1 - titleIn) * -90}px) rotate(-2.2deg)`,
          opacity: titleIn,
          fontFamily: serif,
          fontSize: 61,
          fontWeight: 700,
          lineHeight: 1.03,
        }}
      >
        Tu Mac ya tenía<br />un altillo.
      </ShadowPaper>
    </AbsoluteFill>
  );
};

const DoorScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame - 145);
  const {fps} = useVideoConfig();
  const arrive = spring({fps, frame: local, config: {damping: 12, stiffness: 130}});
  const open = spring({fps, frame: local - 34, config: {damping: 11, stiffness: 90}});
  const words = spring({fps, frame: local - 50, config: {damping: 15, stiffness: 130}});

  return (
    <AbsoluteFill style={{opacity: sceneOpacity(frame, 145, 300)}}>
      <Desk light={0.22 + open * 0.11} />
      <div
        style={{
          position: 'absolute',
          left: 960,
          top: 485,
          width: 530,
          height: 310,
          transform: `translate(-50%, -50%) scale(${0.8 + arrive * 0.2}) rotate(${jitter(frame, 'door-set', 0.3)}deg)`,
        }}
      >
        <div
          style={{
            position: 'absolute',
            inset: 0,
            clipPath: 'polygon(50% 0, 100% 42%, 90% 42%, 90% 100%, 10% 100%, 10% 42%, 0 42%)',
            background: C.paper,
            filter: 'drop-shadow(20px 28px 0 rgba(0,0,0,.24))',
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: 155,
            top: 125,
            width: 220,
            height: 150,
            background: C.bulb,
            boxShadow: `0 0 ${50 + open * 110}px rgba(255,181,71,.85)`,
            clipPath: 'polygon(50% 0, 100% 38%, 100% 100%, 0 100%, 0 38%)',
          }}
        />
        <div
          style={{
            position: 'absolute',
            left: 155,
            top: 125,
            width: 220,
            height: 150,
            transformOrigin: 'left center',
            transform: `perspective(700px) rotateY(${-112 * open}deg)`,
            background: C.wood2,
            clipPath: 'polygon(50% 0, 100% 38%, 100% 100%, 0 100%, 0 38%)',
            boxShadow: '12px 10px 18px rgba(0,0,0,.35)',
          }}
        />
      </div>
      <ShadowPaper
        tone={C.kraft}
        style={{
          left: 530,
          bottom: 95,
          padding: '24px 42px',
          transform: `translateY(${(1 - words) * 130}px) rotate(1.2deg)`,
          opacity: words,
          fontFamily: serif,
          fontSize: 58,
          fontWeight: 700,
        }}
      >
        Solo le faltaba una puerta.
      </ShadowPaper>
    </AbsoluteFill>
  );
};

const fileCards = [
  {label: 'PDF', color: C.tomato, left: 160, delay: 0, rotate: -5},
  {label: 'IMG', color: C.sky, left: 360, delay: 16, rotate: 4},
  {label: 'ZIP', color: C.kraft, left: 565, delay: 30, rotate: -2},
];

const ShelfScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame - 270);
  const {fps} = useVideoConfig();
  const photoIn = spring({fps, frame: local - 10, config: {damping: 14, stiffness: 120}});
  const saved = interpolate(local, [105, 120], [0, 1], clamp);

  return (
    <AbsoluteFill style={{opacity: sceneOpacity(frame, 270, 490)}}>
      <Desk light={0.18} />
      <PrintedScreen
        src={saved < 0.5 ? '/ui/drop.png' : '/ui/shelf.png'}
        style={{
          right: 95,
          top: 136 + (1 - photoIn) * 300,
          width: 1030,
          opacity: photoIn,
        }}
      />
      <div style={{position: 'absolute', left: 115, top: 105, width: 675, height: 820}}>
        <ShadowPaper
          tone={C.bulb}
          style={{
            left: 10,
            top: 15,
            padding: '22px 34px',
            transform: 'rotate(-3deg)',
            fontFamily: serif,
            fontWeight: 800,
            fontSize: 76,
          }}
        >
          Súbelo ↑
        </ShadowPaper>
        <div style={{position: 'absolute', left: 45, top: 150, color: C.paper, fontFamily: sans, fontSize: 28, lineHeight: 1.28, width: 570}}>
          Deja archivos un rato.<br />Bájalos donde los necesites.
        </div>
        {fileCards.map((card, i) => {
          const p = spring({fps, frame: local - 40 - card.delay, config: {damping: 9, stiffness: 120, mass: 0.65}});
          const y = interpolate(p, [0, 1], [690, 330 - i * 24]);
          const x = card.left + Math.sin((local + i * 10) / 12) * 8;
          return (
            <div
              key={card.label}
              style={{
                ...paperEdge,
                position: 'absolute',
                left: x,
                top: y,
                width: 135,
                height: 175,
                background: C.paper,
                borderTop: `18px solid ${card.color}`,
                boxShadow: '10px 14px 0 rgba(0,0,0,.22)',
                transform: `rotate(${card.rotate + jitter(frame, `file-${i}`, 0.5)}deg)`,
                display: 'grid',
                placeItems: 'center',
                color: C.wood,
                fontFamily: sans,
                fontSize: 27,
                fontWeight: 800,
              }}
            >
              {card.label}
            </div>
          );
        })}
      </div>
    </AbsoluteFill>
  );
};

const UsageScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame - 455);
  const {fps} = useVideoConfig();
  const enter = spring({fps, frame: local - 8, config: {damping: 13, stiffness: 120}});
  const count = Math.round(interpolate(local, [30, 92], [0, 85], clamp));

  return (
    <AbsoluteFill style={{opacity: sceneOpacity(frame, 455, 645)}}>
      <Desk light={0.14} />
      <PrintedScreen
        src="/ui/usage.png"
        rotate={1.3}
        style={{left: 120 + (1 - enter) * -500, top: 145, width: 1080, opacity: enter}}
      />
      <ShadowPaper
        tone={C.sky}
        style={{
          right: 115,
          top: 145,
          width: 610,
          padding: '34px 38px',
          transform: `translateX(${(1 - enter) * 500}px) rotate(-2deg)`,
          opacity: enter,
        }}
      >
        <div style={{fontFamily: serif, fontSize: 62, fontWeight: 800, lineHeight: 1.02}}>Lo importante,<br />de un vistazo.</div>
        <div style={{fontFamily: sans, fontSize: 25, lineHeight: 1.35, marginTop: 22}}>Claude y Codex, sin abrir otra app.</div>
      </ShadowPaper>
      <div
        style={{
          position: 'absolute',
          right: 240,
          bottom: 100,
          width: 300,
          height: 300,
          borderRadius: '50%',
          background: `conic-gradient(${C.bulb} ${count * 3.6}deg, ${C.wood2} 0)`,
          boxShadow: '17px 22px 0 rgba(0,0,0,.23)',
          transform: `rotate(${jitter(frame, 'dial', 0.45)}deg)`,
          display: 'grid',
          placeItems: 'center',
        }}
      >
        <div style={{width: 222, height: 222, borderRadius: '50%', background: C.paper, display: 'grid', placeItems: 'center', color: C.wood}}>
          <div style={{fontFamily: serif, fontWeight: 800, fontSize: 72}}>{count}%</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const AgentsScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame - 610);
  const {fps} = useVideoConfig();
  const enter = spring({fps, frame: local - 10, config: {damping: 13, stiffness: 125}});
  const knockWindow = (offset: number) => spring({fps, frame: local - offset, durationInFrames: 15, config: {damping: 7, stiffness: 170}});
  const knock = knockWindow(47) - knockWindow(63) + knockWindow(76) - knockWindow(92);
  const action = spring({fps, frame: local - 102, config: {damping: 12, stiffness: 140}});

  return (
    <AbsoluteFill style={{opacity: sceneOpacity(frame, 610, 805)}}>
      <Desk light={0.21} />
      <PrintedScreen
        src="/ui/agents.png"
        rotate={-1.8}
        style={{right: 90, top: 165, width: 1120, opacity: enter, transform: `translateY(${(1 - enter) * 370}px)`}}
      />
      <ShadowPaper
        tone={C.kraft}
        style={{left: 100, top: 115, width: 650, padding: '34px 40px', transform: `rotate(${1 + jitter(frame, 'agents-title', 0.3)}deg)`}}
      >
        <div style={{fontFamily: serif, fontSize: 63, fontWeight: 800, lineHeight: 1.02}}>Llaman a<br />la puerta.</div>
        <div style={{fontFamily: sans, fontSize: 24, marginTop: 22}}>Permite o deniega desde el notch.</div>
      </ShadowPaper>
      <div
        style={{
          position: 'absolute',
          left: 255,
          bottom: 125,
          fontSize: 150,
          transformOrigin: 'bottom center',
          transform: `rotate(${-18 + knock * 22}deg) translateY(${-Math.abs(knock) * 18}px)`,
          filter: 'drop-shadow(12px 18px 0 rgba(0,0,0,.22))',
        }}
      >
        ✋
      </div>
      <div style={{position: 'absolute', right: 245, bottom: 95, display: 'flex', gap: 24, opacity: action, transform: `translateY(${(1 - action) * 80}px)`}}>
        <ShadowPaper tone={C.paper} style={{position: 'relative', padding: '20px 30px', fontFamily: sans, fontWeight: 750, fontSize: 26}}>Denegar</ShadowPaper>
        <ShadowPaper tone={C.bulb} style={{position: 'relative', padding: '20px 34px', fontFamily: sans, fontWeight: 800, fontSize: 26}}>Permitir</ShadowPaper>
      </div>
    </AbsoluteFill>
  );
};

const FinaleScene = () => {
  const frame = useCurrentFrame();
  const local = snap(frame - 760);
  const {fps} = useVideoConfig();
  const bg = spring({fps, frame: local - 2, config: {damping: 11, stiffness: 120}});
  const attic = spring({fps, frame: local - 22, config: {damping: 10, stiffness: 145}});
  const structure = spring({fps, frame: local - 42, config: {damping: 12, stiffness: 130}});
  const copy = spring({fps, frame: local - 72, config: {damping: 15, stiffness: 115}});
  const master = spring({fps, frame: local - 92, config: {damping: 15, stiffness: 105}});

  const layer = (src: string, progress: number, fromX: number, fromY: number, rotate: number): React.CSSProperties => ({
    position: 'absolute',
    inset: 0,
    width: '100%',
    height: '100%',
    objectFit: 'contain',
    opacity: progress,
    transform: `translate(${(1 - progress) * fromX}px, ${(1 - progress) * fromY}px) rotate(${(1 - progress) * rotate + jitter(frame, src, 0.2)}deg) scale(${0.88 + progress * 0.12})`,
    filter: 'drop-shadow(18px 25px 0 rgba(0,0,0,.22))',
  });

  return (
    <AbsoluteFill style={{opacity: interpolate(frame, [760, 780], [0, 1], clamp)}}>
      <Desk light={0.26} />
      <div style={{position: 'absolute', left: 185, top: 145, width: 700, height: 700}}>
        <Img src={staticFile('/icon/Background.png')} style={{...layer('bg', bg, -420, 0, -13), opacity: bg * (1 - master)}} />
        <Img src={staticFile('/icon/Attic.png')} style={{...layer('attic', attic, 0, -480, 8), opacity: attic * (1 - master)}} />
        <Img src={staticFile('/icon/Structure.png')} style={{...layer('structure', structure, 430, 120, 14), opacity: structure * (1 - master)}} />
        <Img
          src={staticFile('/icon/AltilloIconMaster-11A.png')}
          style={{
            position: 'absolute',
            inset: 0,
            width: '100%',
            height: '100%',
            objectFit: 'contain',
            opacity: master,
            transform: `scale(${0.94 + master * 0.06}) rotate(${jitter(frame, 'master-icon', 0.16)}deg)`,
          }}
        />
      </div>
      <div style={{position: 'absolute', left: 970, top: 235, opacity: copy, transform: `translateY(${(1 - copy) * 90}px)`}}>
        <div style={{fontFamily: serif, fontSize: 118, lineHeight: 0.9, fontWeight: 800, color: C.paper}}>Altillo</div>
        <div style={{marginTop: 38, fontFamily: serif, fontSize: 48, lineHeight: 1.1, color: C.paper, width: 650}}>Un sitio arriba<br />para lo importante.</div>
        <div style={{marginTop: 42, display: 'inline-block', padding: '15px 22px', borderRadius: 999, border: `2px solid ${C.bulb}`, color: C.bulb, fontFamily: sans, fontWeight: 750, fontSize: 19, letterSpacing: 1.2}}>EN DESARROLLO · CÓDIGO ABIERTO</div>
        <div style={{marginTop: 20, color: 'rgba(246,239,227,.62)', fontFamily: sans, fontSize: 22}}>github.com/XusBadia/altillo</div>
      </div>
    </AbsoluteFill>
  );
};

const PaperWipes = () => {
  const frame = useCurrentFrame();
  const starts = [148, 273, 458, 613, 763];
  return (
    <>
      {starts.map((start, i) => {
        const f = snap(frame - start);
        const x = interpolate(f, [0, 10, 18], [-2100, 0, 2100], clamp);
        const visible = f >= 0 && f <= 18;
        return visible ? (
          <div
            key={start}
            style={{
              ...paperEdge,
              position: 'absolute',
              zIndex: 90,
              left: x,
              top: -90,
              width: 2100,
              height: 1260,
              background: [C.kraft, C.paper, C.sky, C.kraft, C.bulb][i],
              transform: `rotate(${i % 2 === 0 ? -3 : 3}deg)`,
              boxShadow: '30px 0 70px rgba(0,0,0,.35)',
            }}
          />
        ) : null;
      })}
    </>
  );
};

const FrameOverlay = () => {
  const frame = useCurrentFrame();
  const x = jitter(frame, 'camera-x', 0.8);
  const y = jitter(frame, 'camera-y', 0.8);
  return (
    <AbsoluteFill style={{pointerEvents: 'none', transform: `translate(${x}px, ${y}px)`, boxShadow: 'inset 0 0 150px rgba(0,0,0,.58)', zIndex: 100}}>
      <div style={{position: 'absolute', left: 54, top: 48, color: 'rgba(246,239,227,.48)', fontFamily: sans, fontSize: 15, fontWeight: 700, letterSpacing: 2.2}}>ALTILLO · PROTOTIPO</div>
      <div style={{position: 'absolute', right: 54, top: 48, color: 'rgba(246,239,227,.32)', fontFamily: sans, fontSize: 14, fontWeight: 700, letterSpacing: 1.6}}>MACOS · CÓDIGO ABIERTO</div>
    </AbsoluteFill>
  );
};

export const AltilloStopMotion = () => (
  <AbsoluteFill style={{backgroundColor: C.ink}}>
    <IntroScene />
    <DoorScene />
    <ShelfScene />
    <UsageScene />
    <AgentsScene />
    <FinaleScene />
    <PaperWipes />
    <FrameOverlay />
    <Html5Audio src={staticFile('/audio/score.m4a')} volume={0.96} />
  </AbsoluteFill>
);
