import type {CSSProperties, ReactNode} from 'react';
import {system} from './parts';

// Ventanas de macOS 26 «Tahoe» (Finder, redacción de Mail) y el arrastre de archivos.
// Todo en puntos de macOS: el padre escala el escritorio entero, así que solo CSS y SVG.

type Lang = 'es' | 'en';
export type FileKind = 'pdf' | 'txt' | 'png' | 'zip' | 'numbers' | 'folder';

const ACCENT = '#0A84FF';
const text = {primary: 'rgba(255,255,255,.88)', secondary: 'rgba(255,255,255,.52)', tertiary: 'rgba(255,255,255,.3)'};

const copy = {
  es: {
    documents: 'Documentos',
    favorites: 'Favoritos',
    locations: 'Ubicaciones',
    sidebar: ['AirDrop', 'Recientes', 'Aplicaciones', 'Escritorio', 'Documentos', 'Descargas'],
    files: ['Propuesta Altillo v2.pdf', 'notas-reunión.txt', 'Captura 10.24.12.png', 'altillo-assets.zip', 'Presupuesto 2026.numbers', 'Proyecto'],
    newMessage: 'Nuevo mensaje',
    to: 'Para:',
    subject: 'Asunto:',
    subjectText: 'Propuesta del notch',
    body: ['Hola Marta,', 'te paso la propuesta. ¡Dime qué te parece!'],
    size: '2,4 MB',
  },
  en: {
    documents: 'Documents',
    favorites: 'Favorites',
    locations: 'Locations',
    sidebar: ['AirDrop', 'Recents', 'Applications', 'Desktop', 'Documents', 'Downloads'],
    files: ['Altillo Proposal v2.pdf', 'meeting-notes.txt', 'Screenshot 10.24.12.png', 'altillo-assets.zip', 'Budget 2026.numbers', 'Project'],
    newMessage: 'New Message',
    to: 'To:',
    subject: 'Subject:',
    subjectText: 'Notch proposal',
    body: ['Hi Marta,', 'here’s the proposal. Let me know what you think!'],
    size: '2.4 MB',
  },
} as const;

const KINDS: FileKind[] = ['pdf', 'txt', 'png', 'zip', 'numbers', 'folder'];

/** Nombre y tipo de cada archivo de la carpeta Documentos (índice 0: el PDF que se arrastra). */
export const finderFile = (index: number, lang: Lang) => ({label: copy[lang].files[index], kind: KINDS[index]});
export const attachmentSize = (lang: Lang) => copy[lang].size;

// ————— Cristal y piezas comunes —————

const windowChrome = (radius: number): CSSProperties => ({
  position: 'absolute',
  borderRadius: radius,
  overflow: 'hidden',
  fontFamily: system,
  WebkitFontSmoothing: 'antialiased',
  background: 'linear-gradient(180deg, rgba(38,36,35,.86), rgba(27,26,25,.9))',
  backdropFilter: 'blur(40px) saturate(1.5)',
  boxShadow: [
    'inset 0 0 0 .5px rgba(255,255,255,.16)',
    'inset 0 1px 0 rgba(255,255,255,.08)',
    '0 0 0 .5px rgba(0,0,0,.7)',
    '0 10px 24px rgba(0,0,0,.28)',
    '0 32px 80px rgba(0,0,0,.45)',
  ].join(', '),
});

const glass: CSSProperties = {
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  height: 32,
  borderRadius: 16,
  background: 'linear-gradient(180deg, rgba(255,255,255,.13), rgba(255,255,255,.07))',
  boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.14), inset 0 .5px 0 rgba(255,255,255,.22), 0 1px 4px rgba(0,0,0,.25)',
  color: text.primary,
};

const Glyph = ({children, size = 16, color = 'currentColor', w = 1.5}: {children: ReactNode; size?: number; color?: string; w?: number}) => (
  <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth={w} strokeLinecap="round" strokeLinejoin="round" style={{flexShrink: 0}}>
    {children}
  </svg>
);

const TrafficLights = ({x, y}: {x: number; y: number}) => (
  <div style={{position: 'absolute', left: x, top: y, display: 'flex', gap: 8}}>
    {['#FF5F57', '#FEBC2E', '#28C840'].map((c) => (
      <div key={c} style={{width: 13, height: 13, borderRadius: 7, background: c, boxShadow: 'inset 0 0 0 .5px rgba(0,0,0,.22)'}} />
    ))}
  </div>
);

// Glifos al estilo SF Symbols para la barra lateral y la barra de herramientas.
const icons = {
  airdrop: (
    <>
      <path d="M4.2 11.6a5.2 5.2 0 1 1 7.6 0" />
      <path d="M5.9 9.9a2.8 2.8 0 1 1 4.2 0" />
      <circle cx="8" cy="7.9" r=".9" fill="currentColor" stroke="none" />
    </>
  ),
  clock: (
    <>
      <circle cx="8" cy="8" r="6.2" />
      <path d="M8 4.6V8l2.3 1.5" />
    </>
  ),
  apps: (
    <>
      <path d="M5.6 12.6 8.7 3.4" />
      <path d="m8.3 7.6 2.3 5" />
      <path d="M3.6 10.6h8.8" />
    </>
  ),
  desktop: (
    <>
      <rect x="1.8" y="2.8" width="12.4" height="8.4" rx="1.4" />
      <path d="M6 13.8h4M8 11.2v2.6" />
    </>
  ),
  doc: (
    <>
      <path d="M4 1.8h5l3 3v8.4a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V2.8a1 1 0 0 1 1-1Z" />
      <path d="M9 1.8v3h3" />
    </>
  ),
  download: (
    <>
      <circle cx="8" cy="8" r="6.2" />
      <path d="M8 4.7v6M5.4 8.3 8 10.8l2.6-2.5" />
    </>
  ),
  cloud: <path d="M4.6 12.4h7a2.9 2.9 0 0 0 .3-5.8 4 4 0 0 0-7.7.9 2.5 2.5 0 0 0 .4 4.9Z" />,
  back: <path d="M9.8 3.4 5.2 8l4.6 4.6" />,
  forward: <path d="M6.2 3.4 10.8 8l-4.6 4.6" />,
  grid: (
    <>
      <rect x="2.2" y="2.2" width="4.6" height="4.6" rx="1.1" />
      <rect x="9.2" y="2.2" width="4.6" height="4.6" rx="1.1" />
      <rect x="2.2" y="9.2" width="4.6" height="4.6" rx="1.1" />
      <rect x="9.2" y="9.2" width="4.6" height="4.6" rx="1.1" />
    </>
  ),
  chevronDown: <path d="m4.6 6.4 3.4 3.4 3.4-3.4" />,
  more: (
    <>
      <circle cx="3.6" cy="8" r=".6" fill="currentColor" />
      <circle cx="8" cy="8" r=".6" fill="currentColor" />
      <circle cx="12.4" cy="8" r=".6" fill="currentColor" />
    </>
  ),
  share: (
    <>
      <path d="M8 1.9v8M5.3 4.4 8 1.7l2.7 2.7" />
      <path d="M5.2 6.6H4.4a1 1 0 0 0-1 1v5.6a1 1 0 0 0 1 1h7.2a1 1 0 0 0 1-1V7.6a1 1 0 0 0-1-1h-.8" />
    </>
  ),
  search: (
    <>
      <circle cx="7" cy="7" r="4.6" />
      <path d="m10.4 10.4 3.4 3.4" />
    </>
  ),
  send: (
    <>
      <path d="M14.2 1.8 1.9 7l4.9 2.1 2.1 4.9Z" />
      <path d="M14.2 1.8 6.8 9.1" />
    </>
  ),
  paperclip: <path d="m13 7.4-5.2 5.2a3.2 3.2 0 0 1-4.5-4.5l5.6-5.6a2.1 2.1 0 0 1 3 3L6.3 11.1a1 1 0 0 1-1.5-1.5l5-5" />,
  photo: (
    <>
      <rect x="1.8" y="3" width="12.4" height="10" rx="1.6" />
      <circle cx="5.4" cy="6.4" r="1.1" />
      <path d="m2.2 11.8 3.6-3.2 2.6 2.2 2.2-1.8 3.4 2.8" />
    </>
  ),
  smile: (
    <>
      <circle cx="8" cy="8" r="6.2" />
      <path d="M5.6 9.6a3 3 0 0 0 4.8 0" />
      <circle cx="6" cy="6.6" r=".5" fill="currentColor" />
      <circle cx="10" cy="6.6" r=".5" fill="currentColor" />
    </>
  ),
};

// ————— Iconos de archivo —————

/** Página de documento de macOS: esquina doblada, degradado suave y contorno fino. */
const Page = ({children, label, labelColor}: {children?: ReactNode; label?: string; labelColor?: string}) => (
  <>
    <defs>
      <linearGradient id="fi-page" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#FFFFFF" />
        <stop offset="1" stopColor="#EEEDEA" />
      </linearGradient>
      <linearGradient id="fi-fold" x1="0" y1="1" x2="1" y2="0">
        <stop offset="0" stopColor="#D9D7D2" />
        <stop offset="1" stopColor="#FAFAF8" />
      </linearGradient>
    </defs>
    <path d="M14.5 4h24.8L52 16.7V58a2.5 2.5 0 0 1-2.5 2.5h-35A2.5 2.5 0 0 1 12 58V6.5A2.5 2.5 0 0 1 14.5 4Z" fill="url(#fi-page)" stroke="rgba(0,0,0,.18)" strokeWidth=".5" />
    <path d="M39.3 4v10.2a2.5 2.5 0 0 0 2.5 2.5H52Z" fill="url(#fi-fold)" stroke="rgba(0,0,0,.14)" strokeWidth=".5" strokeLinejoin="round" />
    {children}
    {label ? (
      labelColor ? (
        <>
          <rect x="17" y="46" width="30" height="10" rx="2.4" fill={labelColor} />
          <text x="32" y="53.6" textAnchor="middle" fontFamily={system} fontSize="7.4" fontWeight="800" fill="#fff" letterSpacing=".4">{label}</text>
        </>
      ) : (
        <text x="32" y="55" textAnchor="middle" fontFamily={system} fontSize="7.6" fontWeight="700" fill="#8E8B86" letterSpacing=".5">{label}</text>
      )
    ) : null}
  </>
);

const lines = (ys: number[], x1 = 18, x2 = 46, color = '#C9C6C0') =>
  ys.map((y, i) => <path key={y} d={`M${x1} ${y}H${i % 3 === 2 ? x2 - 9 : x2}`} stroke={color} strokeWidth="1.3" strokeLinecap="round" />);

const iconArt: Record<FileKind, ReactNode> = {
  pdf: (
    <Page label="PDF" labelColor="#E0443E">
      <rect x="18" y="11" width="15" height="3.4" rx="1" fill="#E9A54A" />
      {lines([19.5, 23.5, 27.5, 31.5, 35.5, 39.5], 18, 46, '#CFCBC4')}
    </Page>
  ),
  txt: <Page label="TXT">{lines([12, 16, 20, 24, 28, 32, 36, 40], 18, 46)}</Page>,
  zip: (
    <Page label="ZIP">
      <path d="M32 4v34" stroke="#B9B5AE" strokeWidth="3.2" strokeDasharray="2.2 2.2" />
      <rect x="29.4" y="36" width="5.2" height="7.5" rx="1.4" fill="#A8A49D" />
    </Page>
  ),
  numbers: (
    <Page>
      {[14, 20, 26, 32].map((y) => (
        <path key={y} d={`M18 ${y}H46`} stroke="#D3D0CA" strokeWidth=".8" />
      ))}
      <path d="M27 11v24M36.5 11v24" stroke="#D3D0CA" strokeWidth=".8" />
      <rect x="18" y="11" width="28" height="3" fill="#DDEFD9" />
      <defs>
        <linearGradient id="fi-num" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3FD27A" />
          <stop offset="1" stopColor="#1FA956" />
        </linearGradient>
      </defs>
      <rect x="23" y="39" width="18" height="18" rx="4.6" fill="url(#fi-num)" />
      <path d="M27.6 53v-4M31 53v-8M34.4 53v-6M37.8 53v-9.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
    </Page>
  ),
  png: (
    <>
      <defs>
        <linearGradient id="fi-sky" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3A2A55" />
          <stop offset=".55" stopColor="#D8744A" />
          <stop offset="1" stopColor="#F2B45E" />
        </linearGradient>
      </defs>
      <rect x="4" y="13" width="56" height="38" rx="2" fill="#fff" stroke="rgba(0,0,0,.2)" strokeWidth=".5" />
      <rect x="6.5" y="15.5" width="51" height="33" rx=".8" fill="url(#fi-sky)" />
      <circle cx="44" cy="30" r="4.2" fill="#FFE2A8" opacity=".9" />
      <path d="M6.5 48.5V40l10-7.5 8 5.5 9-8 11 9 13 5v4.5Z" fill="#2B1D2A" opacity=".85" />
      <path d="M6.5 48.5V44l13-5.5 11 4 12-3.5 15 4.5v5Z" fill="#170F17" />
    </>
  ),
  folder: (
    <>
      <defs>
        <linearGradient id="fi-fback" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#3C9BEF" />
          <stop offset="1" stopColor="#2A83DD" />
        </linearGradient>
        <linearGradient id="fi-ffront" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#7FC6FF" />
          <stop offset="1" stopColor="#4BA6F5" />
        </linearGradient>
      </defs>
      <path d="M5 13.5A3.5 3.5 0 0 1 8.5 10h13.2c1 0 1.9.4 2.6 1.1l2.4 2.4c.7.7 1.6 1.1 2.6 1.1h26.2A3.5 3.5 0 0 1 59 18.1V50a3.5 3.5 0 0 1-3.5 3.5h-47A3.5 3.5 0 0 1 5 50Z" fill="url(#fi-fback)" />
      <rect x="5" y="19.5" width="54" height="34" rx="3.5" fill="url(#fi-ffront)" />
      <path d="M8.5 20h47" stroke="rgba(255,255,255,.55)" strokeWidth=".8" strokeLinecap="round" />
    </>
  ),
};

/** Icono de archivo estilo macOS dibujado en vectorial (se ve nítido a cualquier escala). */
export const FileIcon = ({kind, size = 64, style}: {kind: FileKind; size?: number; style?: CSSProperties}) => (
  <svg width={size} height={size} viewBox="0 0 64 64" style={{display: 'block', overflow: 'visible', filter: 'drop-shadow(0 1px 1.5px rgba(0,0,0,.35))', ...style}}>
    {iconArt[kind]}
  </svg>
);

// ————— Finder —————

const F = {radius: 16, inset: 8, sidebar: 168, toolbar: 54, cellH: 112, icon: 64, gridTop: 12, gridPad: 10};
const finderContentX = F.inset + F.sidebar;

/** Centro del icono `index` en la cuadrícula del Finder (mismos puntos que las props de la ventana). */
export const finderItemCenter = (index: number, win: {x: number; y: number; width?: number; height?: number}) => {
  const width = win.width ?? 520;
  const cellW = (width - finderContentX - 2 * F.gridPad) / 3;
  const col = index % 3;
  const row = Math.floor(index / 3);
  return {
    x: win.x + finderContentX + F.gridPad + cellW * (col + 0.5),
    y: win.y + F.toolbar + F.gridTop + row * F.cellH + 4 + F.icon / 2,
  };
};

const sidebarIcons = [icons.airdrop, icons.clock, icons.apps, icons.desktop, icons.doc, icons.download];

const SidebarRow = ({icon, label, selected}: {icon: ReactNode; label: string; selected?: boolean}) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 7,
      height: 26,
      padding: '0 8px',
      borderRadius: 8,
      fontSize: 13,
      color: text.primary,
      background: selected ? 'rgba(255,255,255,.12)' : undefined,
    }}
  >
    <Glyph color={ACCENT}>{icon}</Glyph>
    <span style={{whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis'}}>{label}</span>
  </div>
);

const SectionTitle = ({children}: {children: ReactNode}) => (
  <div style={{fontSize: 11, fontWeight: 600, color: text.tertiary, padding: '10px 8px 4px'}}>{children}</div>
);

export const FinderWindow = ({
  x,
  y,
  width = 520,
  height = 360,
  lang,
  draggingIndex,
  selectedIndex,
}: {
  x: number;
  y: number;
  width?: number;
  height?: number;
  lang: Lang;
  draggingIndex?: number;
  selectedIndex?: number;
}) => {
  const t = copy[lang];
  const cellW = (width - finderContentX - 2 * F.gridPad) / 3;
  return (
    <div style={{...windowChrome(F.radius), left: x, top: y, width, height}}>
      {/* Barra lateral flotante de cristal, con los semáforos dentro */}
      <div
        style={{
          position: 'absolute',
          left: F.inset,
          top: F.inset,
          bottom: F.inset,
          width: F.sidebar - F.inset,
          borderRadius: F.radius - F.inset + 4,
          background: 'linear-gradient(180deg, rgba(255,255,255,.085), rgba(255,255,255,.05))',
          boxShadow: 'inset 0 0 0 .5px rgba(255,255,255,.1), 0 2px 10px rgba(0,0,0,.18)',
          padding: '40px 8px 0',
        }}
      >
        <TrafficLights x={12} y={12} />
        <SectionTitle>{t.favorites}</SectionTitle>
        {t.sidebar.map((label, i) => (
          <SidebarRow key={label} icon={sidebarIcons[i]} label={label} selected={i === 4} />
        ))}
        <SectionTitle>{t.locations}</SectionTitle>
        <SidebarRow icon={icons.cloud} label="iCloud Drive" />
      </div>

      {/* Barra de herramientas: controles de cristal flotando sobre el contenido */}
      <div style={{position: 'absolute', left: finderContentX + 10, right: 10, top: 11, display: 'flex', alignItems: 'center', gap: 10}}>
        <div style={{...glass, width: 68, gap: 12}}>
          <Glyph size={15} w={1.8}>{icons.back}</Glyph>
          <span style={{opacity: 0.35, display: 'flex'}}>
            <Glyph size={15} w={1.8}>{icons.forward}</Glyph>
          </span>
        </div>
        <div style={{fontSize: 15, fontWeight: 700, color: text.primary, letterSpacing: '-.2px', flex: 1, whiteSpace: 'nowrap'}}>{t.documents}</div>
        <div style={{...glass, padding: '0 9px', gap: 3}}>
          <Glyph size={15}>{icons.grid}</Glyph>
          <Glyph size={10} w={1.8}>{icons.chevronDown}</Glyph>
        </div>
        <div style={{...glass, width: 32}}>
          <Glyph size={15}>{icons.more}</Glyph>
        </div>
        <div style={{...glass, width: 32}}>
          <Glyph size={15} w={1.7}>{icons.search}</Glyph>
        </div>
      </div>

      {/* Vista de iconos */}
      <div style={{position: 'absolute', left: finderContentX + F.gridPad, top: F.toolbar + F.gridTop, width: cellW * 3, display: 'flex', flexWrap: 'wrap'}}>
        {t.files.map((name, i) => {
          const selected = i === selectedIndex;
          return (
            <div key={name} style={{width: cellW, height: F.cellH, display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
              <div
                style={{
                  padding: 4,
                  borderRadius: 8,
                  background: selected ? 'rgba(255,255,255,.13)' : undefined,
                  opacity: i === draggingIndex ? 0.45 : 1,
                }}
              >
                <FileIcon kind={KINDS[i]} size={F.icon} />
              </div>
              <div
                style={{
                  marginTop: 3,
                  maxWidth: cellW - 10,
                  padding: '1px 5px',
                  borderRadius: 5,
                  fontSize: 12,
                  lineHeight: '15px',
                  textAlign: 'center',
                  color: selected ? '#fff' : text.primary,
                  background: selected ? '#0A5FD1' : undefined,
                  display: '-webkit-box',
                  WebkitLineClamp: 2,
                  WebkitBoxOrient: 'vertical',
                  overflow: 'hidden',
                  wordBreak: 'break-word',
                }}
              >
                {name}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

// ————— Mail —————

const M = {radius: 16, toolbar: 54, row: 34, pad: 18};
const mailBodyTop = M.toolbar + 3 * M.row;

/** Zona de soltar: el cuerpo del mensaje (mismos puntos que las props de la ventana). */
export const mailDropRect = (win: {x: number; y: number; width?: number; height?: number}) => {
  const width = win.width ?? 520;
  const height = win.height ?? 380;
  return {x: win.x + 8, y: win.y + mailBodyTop + 6, width: width - 16, height: height - mailBodyTop - 14};
};

const Field = ({label, children}: {label: string; children?: ReactNode}) => (
  <div
    style={{
      height: M.row,
      margin: `0 ${M.pad}px`,
      display: 'flex',
      alignItems: 'center',
      gap: 6,
      fontSize: 13,
      borderBottom: '.5px solid rgba(255,255,255,.11)',
    }}
  >
    <span style={{color: text.secondary}}>{label}</span>
    {children}
  </div>
);

export const MailWindow = ({
  x,
  y,
  width = 520,
  height = 380,
  lang,
  attached,
}: {
  x: number;
  y: number;
  width?: number;
  height?: number;
  lang: Lang;
  attached: number;
}) => {
  const t = copy[lang];
  const a = Math.max(0, Math.min(1, attached));
  return (
    <div style={{...windowChrome(M.radius), left: x, top: y, width, height}}>
      <TrafficLights x={20} y={20} />
      <div style={{position: 'absolute', left: 90, right: 12, top: 11, display: 'flex', alignItems: 'center', gap: 10}}>
        <div style={{...glass, width: 40, color: ACCENT}}>
          <Glyph size={16} w={1.6}>{icons.send}</Glyph>
        </div>
        <div style={{fontSize: 15, fontWeight: 700, color: text.primary, letterSpacing: '-.2px', flex: 1, whiteSpace: 'nowrap'}}>{t.newMessage}</div>
        <div style={{...glass, padding: '0 12px', gap: 16}}>
          <Glyph size={15}>{icons.paperclip}</Glyph>
          <span style={{fontSize: 14, fontWeight: 500, lineHeight: 1}}>Aa</span>
          <Glyph size={15}>{icons.smile}</Glyph>
          <Glyph size={15}>{icons.photo}</Glyph>
        </div>
      </div>

      <div style={{position: 'absolute', left: 0, right: 0, top: M.toolbar}}>
        <Field label={t.to}>
          <span
            style={{
              color: '#6CB4FF',
              background: 'rgba(10,132,255,.16)',
              borderRadius: 6,
              padding: '2px 7px',
            }}
          >
            Marta Ruiz
          </span>
        </Field>
        <Field label="Cc:" />
        <Field label={t.subject}>
          <span style={{color: text.primary}}>{t.subjectText}</span>
        </Field>
      </div>

      <div style={{position: 'absolute', left: M.pad, right: M.pad, top: mailBodyTop + 16, fontSize: 13, lineHeight: '19px', color: text.primary}}>
        {t.body.map((l) => (
          <div key={l}>{l}</div>
        ))}
        {/* Adjunto: aparece con un pequeño muelle guiado por `attached` */}
        <div
          style={{
            marginTop: 18,
            width: 150,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            opacity: Math.min(1, a * 1.8),
            transform: `scale(${0.6 + 0.4 * a})`,
            transformOrigin: '50% 30%',
          }}
        >
          <FileIcon kind="pdf" size={60} />
          <div style={{marginTop: 4, fontSize: 12, lineHeight: '15px', color: text.primary, whiteSpace: 'nowrap'}}>{t.files[0]}</div>
          <div style={{fontSize: 11, lineHeight: '14px', color: text.secondary}}>{t.size}</div>
        </div>
      </div>
    </div>
  );
};

// ————— Arrastre —————

/**
 * Imagen de arrastre de macOS: icono al 80 % con su nombre en una etiqueta.
 * (x, y) es la punta del cursor; el icono queda centrado algo abajo a la derecha.
 */
export const DragImage = ({
  x,
  y,
  label,
  kind,
  copyBadge,
  opacity = 1,
  size = 64,
}: {
  x: number;
  y: number;
  label: string;
  kind: FileKind;
  copyBadge?: boolean;
  opacity?: number;
  size?: number;
}) => (
  <div style={{position: 'absolute', left: x, top: y, opacity, fontFamily: system, pointerEvents: 'none'}}>
    <div style={{position: 'absolute', left: -size / 2 + 14, top: -size / 2 + 22, width: size, display: 'flex', flexDirection: 'column', alignItems: 'center'}}>
      <FileIcon kind={kind} size={size} style={{opacity: 0.8}} />
      <div
        style={{
          marginTop: 3,
          padding: '1px 6px',
          borderRadius: 5,
          fontSize: 12,
          lineHeight: '15px',
          whiteSpace: 'nowrap',
          color: '#fff',
          background: 'rgba(10,95,209,.72)',
          WebkitFontSmoothing: 'antialiased',
        }}
      >
        {label}
      </div>
    </div>
    {copyBadge ? (
      <svg width="18" height="18" viewBox="0 0 18 18" style={{position: 'absolute', left: 12, top: 19, filter: 'drop-shadow(0 1px 2px rgba(0,0,0,.4))'}}>
        <circle cx="9" cy="9" r="8.4" fill="#2FBF4F" stroke="#fff" strokeWidth="1.2" />
        <path d="M9 5.2v7.6M5.2 9h7.6" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
      </svg>
    ) : null}
  </div>
);

/** Resalte del destino al arrastrar encima (borde de acento redondeado). */
export const DropHighlight = ({x, y, width, height, progress}: {x: number; y: number; width: number; height: number; progress: number}) => {
  const p = Math.max(0, Math.min(1, progress));
  return (
    <div
      style={{
        position: 'absolute',
        left: x,
        top: y,
        width,
        height,
        borderRadius: 10,
        opacity: p,
        boxShadow: `inset 0 0 0 ${2 + p}px rgba(10,132,255,.9)`,
        background: 'rgba(10,132,255,.08)',
        pointerEvents: 'none',
      }}
    />
  );
};
