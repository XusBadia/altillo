import React, {type CSSProperties, type ReactNode, useId} from 'react';
import {staticFile} from 'remotion';

/** Film-only reconstruction of the shipping SwiftUI Desván surfaces. Coordinates
 * are native points; the camera may scale the whole component without raster UI.
 * No clocks, timers, random values or CSS animations: the caller owns time. */
export const palette = {
  notch: '#000000', wood: '#1E1914', woodRaised: '#2A231C', plank: '#3A3027',
  paper: '#F6EFE3', secondary: '#F6EFE39E', tertiary: '#F6EFE361', ink: '#2B241D',
  bulb: '#FFB547', kraft: '#C9A77C', cardboard: '#B08858', sky: '#86B6D9',
  sage: '#9DB88A', tomato: '#F2674A',
} as const;

const system = '-apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif';
const rounded = '"SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif';

export type GlyphName = 'shelf' | 'house' | 'usage' | 'agents' | 'calendar' | 'mirror' | 'music' | 'gear' | 'play' | 'pause' | 'previous' | 'next' | 'clock' | 'check' | 'arrow' | 'close' | 'plane';
export const Glyph: React.FC<{name: GlyphName | string; size?: number; color?: string; style?: CSSProperties}> = ({name, size = 14, color = palette.paper, style}) => {
  let art: ReactNode;
  switch (name) {
    case 'shelf': case 'house': art = <><path d="M4 10 12 3l8 7v10H4Z"/><path d="M9 10h6v5H9Z" fill={palette.bulb} stroke="none"/></>; break;
    case 'usage': art = <><path d="M4 19V12M9 19V7M14 19V10M19 19V4" strokeWidth="2.6"/></>; break;
    case 'agents': art = <><rect x="4" y="7" width="16" height="13" rx="4"/><path d="M12 7V3m-2 0h4M8 12h.1M16 12h.1M9 16h6"/></>; break;
    case 'calendar': art = <><rect x="3" y="5" width="18" height="16" rx="3"/><path d="M7 3v5m10-5v5M3 10h18M7 14h2m3 0h2m3 0h.1M7 17h2m3 0h2"/></>; break;
    case 'mirror': art = <><rect x="4" y="3" width="16" height="18" rx="5"/><path d="m8 8 3-2m-3 7 7-5"/></>; break;
    case 'music': art = <><path d="M10 17V5l10-2v12M10 8l10-2"/><ellipse cx="7" cy="18" rx="3" ry="2.3" fill={color}/><ellipse cx="17" cy="16" rx="3" ry="2.3" fill={color}/></>; break;
    case 'gear': art = <><path d="m9 3 1-1h4l1 3 3 1 3 1v4l-2 2 1 3-3 3-3-1-2 3H9l-1-3-3-1-2-2 1-4-1-2 3-3 3 1Z"/><circle cx="12" cy="12" r="3.4"/></>; break;
    case 'pause': art = <><rect x="6" y="4" width="4" height="16" rx="1" fill={color} stroke="none"/><rect x="14" y="4" width="4" height="16" rx="1" fill={color} stroke="none"/></>; break;
    case 'play': art = <path d="M6 3 21 12 6 21Z" fill={color} stroke="none"/>; break;
    case 'previous': art = <><path d="M18 4 6 12l12 8Z" fill={color} stroke="none"/><path d="M5 4v16" strokeWidth="2.6"/></>; break;
    case 'next': art = <><path d="m6 4 12 8L6 20Z" fill={color} stroke="none"/><path d="M19 4v16" strokeWidth="2.6"/></>; break;
    case 'clock': art = <><circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/></>; break;
    case 'check': art = <path d="m4 12 5 5L20 6" strokeWidth="2.6"/>; break;
    case 'arrow': art = <path d="M12 3v16m-6-6 6 6 6-6"/>; break;
    case 'close': art = <path d="m5 5 14 14M19 5 5 19"/>; break;
    case 'plane': art = <><path d="M22 2 2 11l8 3 3 8Z" fill={color}/><path d="m10 14 12-12" stroke={palette.ink} strokeWidth=".8"/></>; break;
    default: art = <circle cx="12" cy="12" r="7"/>;
  }
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.65" strokeLinecap="round" strokeLinejoin="round" style={{display: 'block', flexShrink: 0, ...style}}>{art}</svg>;
};

export type FileKind = 'pdf' | 'image' | 'note' | 'zip';
export const FileArtwork: React.FC<{kind: FileKind; size: number; style?: CSSProperties}> = ({kind, size, style}) => {
  const uid = useId().replace(/:/g, '');
  return <svg width={size} height={size} viewBox="0 0 100 100" style={{display: 'block', overflow: 'visible', filter: 'drop-shadow(0 3px 2px #0006)', ...style}}>
    <defs>
      <linearGradient id={`${uid}-paper`} x2="0" y2="1"><stop stopColor="#FFFDF6"/><stop offset="1" stopColor="#DED7C9"/></linearGradient>
      <linearGradient id={`${uid}-sky`} x2="0" y2="1"><stop stopColor="#A5CED6"/><stop offset="1" stopColor="#E8D6B5"/></linearGradient>
      <linearGradient id={`${uid}-folder`} x2="0" y2="1"><stop stopColor="#EBBA78"/><stop offset="1" stopColor="#B57D43"/></linearGradient>
    </defs>
    {kind === 'pdf' && <>
      <path d="M22 5h40l17 18v69a4 4 0 0 1-4 4H22a4 4 0 0 1-4-4V9a4 4 0 0 1 4-4Z" fill={`url(#${uid}-paper)`}/>
      <path d="M62 5v15a3 3 0 0 0 3 3h14" fill="#C6BCAE"/>
      <rect x="26" y="31" width="46" height="31" rx="1" fill="#A65137"/>
      <circle cx="54" cy="43" r="7" fill="#F3CB8A"/><path d="m26 62 17-19 12 13 9-9 8 15Z" fill="#643D2E"/>
      <path d="M27 70h43M27 75h33M27 80h39" stroke="#A9A092" strokeWidth="2"/>
      <rect x="11" y="84" width="33" height="13" rx="3" fill="#C95344"/><text x="27.5" y="93" textAnchor="middle" fontFamily={system} fontWeight="700" fontSize="8" fill="white">PDF</text>
    </>}
    {kind === 'image' && <>
      <rect x="7" y="17" width="87" height="68" rx="4" fill={`url(#${uid}-paper)`}/>
      <rect x="12" y="22" width="77" height="51" rx="1" fill={`url(#${uid}-sky)`}/>
      <circle cx="70" cy="34" r="7" fill="#FFF4CE"/>
      <path d="m12 66 22-25 18 17 17-14 20 21v8H12Z" fill="#849183"/>
      <path d="m12 70 27-16 21 10 15-12 14 16v5H12Z" fill="#344F49"/>
      <path d="m20 73 18-7 18 4 15-3 18 6" fill="#25443E"/>
    </>}
    {kind === 'note' && <>
      <path d="M17 8h69v71L70 94H17Z" fill="#EADBAB"/><path d="M70 79h16L70 94Z" fill="#C4AF75"/>
      <rect x="17" y="8" width="69" height="17" fill="#D3BC7E"/>
      <path d="M28 38h44M28 47h38M28 56h44M28 65h28M28 74h35" stroke="#8C7A54" strokeWidth="2.2" opacity=".6"/>
      <path d="M27 6v8m12-8v8m12-8v8m12-8v8m12-8v8" stroke="#F3EACA" strokeWidth="3" strokeLinecap="round"/>
    </>}
    {kind === 'zip' && <>
      <path d="M9 27v-9a4 4 0 0 1 4-4h27l9 10h36a6 6 0 0 1 6 6v57H9Z" fill="#B87B40"/>
      <path d="M8 30h83v53a5 5 0 0 1-5 5H13a5 5 0 0 1-5-5Z" fill={`url(#${uid}-folder)`}/>
      <path d="M50 29v49" stroke="#775431" strokeWidth="10"/>
      {Array.from({length: 8}, (_, i) => <rect key={i} x={i % 2 ? 50 : 46} y={31 + i * 5} width="4" height="3.5" fill="#EDD7AF"/>)}
      <rect x="45" y="69" width="10" height="14" rx="3" fill="#DBC398" stroke="#715535" strokeWidth="1"/>
    </>}
  </svg>;
};

// The native alpha texture is BELOW content, attenuated by the base-colour
// layer. It must never be painted over document art, labels or controls.
export const woodMaterial: CSSProperties = {
  backgroundColor:'#211C16',
  backgroundImage:`linear-gradient(180deg,#211C16D4 40%,#191510D4 100%),url("${staticFile('materials/wood.png')}")`,
  backgroundSize:'100% 100%,720px 220px',
};
const cardStyle: CSSProperties = {
  position: 'relative', height: '100%', borderRadius: 14, overflow: 'hidden',
  ...woodMaterial,
  boxShadow: 'inset 0 .75px 0 #F6EFE32A, inset 0 -.75px 0 #0008, inset 1px 0 0 #F6EFE30A, inset -1px 0 0 #F6EFE30A',
};

export type ShelfFilmItem = {kind: FileKind; name: string; opacity?: number; y?: number; rotation?: number; scale?: number; selected?: boolean};
const defaultItems: ShelfFilmItem[] = [{kind: 'pdf', name: 'Propuesta'}, {kind: 'image', name: 'Montaña'}, {kind: 'note', name: 'Ideas'}];

export const ShelfContent: React.FC<{items?: ShelfFilmItem[]}> = ({items = defaultItems}) => <div style={cardStyle}>
  <div style={{position: 'absolute', top: 66, left: 0, right: 0, height: 4, background: 'linear-gradient(#3E3329,#54463A)'}}/>
  <div style={{position: 'absolute', top: 70, left: 0, right: 0, height: 7, borderTop: '.5px solid #E8CFA64D', background: 'linear-gradient(#3F3329,#3A3027,#261E17)', boxShadow: '0 8px 10px #0007'}}/>
  <div style={{display: 'flex', justifyContent: 'center', height: '100%'}}>
    {items.map((item, i) => <div key={`${item.name}-${i}`} style={{position: 'relative', width: 82, flexShrink: 0, opacity: item.opacity ?? 1}}>
      <div style={{position: 'absolute', top: 66, left: 17, width: 48, height: 4, borderRadius: '50%', background: '#0009', filter: 'blur(2px)'}}/>
      <div style={{position: 'absolute', top: 19, left: 16, transformOrigin: '50% 100%', transform: `translateY(${item.y ?? 0}px) rotate(${item.rotation ?? [-1.1, 1, -.5][i % 3]}deg) scale(${item.scale ?? 1})`, filter: item.selected ? 'drop-shadow(0 0 5px #FFB54755)' : undefined}}><FileArtwork kind={item.kind} size={50}/></div>
      <div style={{position: 'absolute', top: 81, width: '100%', fontSize: 10.5, fontWeight: 500, textAlign: 'center', color: item.selected ? palette.bulb : palette.secondary, whiteSpace: 'nowrap'}}>{item.name}</div>
    </div>)}
  </div>
</div>;

/** Flaps use the same 3-D projection and 118° hinge range as DesvanBox.swift. */
export const CardboardBox: React.FC<{openness?: number; width?: number}> = ({openness = 1, width = 113}) => {
  const id = useId().replace(/:/g, '');
  const e = 26 * Math.PI / 180;
  const project = (x: number, y: number, z: number) => {
    const f = 1 / (1 + -(y * Math.sin(e) + z * Math.cos(e)) * .0026);
    return [98 + x * f, 146 * .84 - (y * Math.cos(e) - z * Math.sin(e)) * f];
  };
  const poly = (points: number[][]) => points.map(([x,y,z]) => project(x,y,z).join(',')).join(' ');
  const angle = Math.max(0, Math.min(1, openness)) * 118 * Math.PI / 180;
  return <svg width={width} height={width * 146 / 196} viewBox="0 0 196 146" style={{display: 'block', overflow: 'visible'}}>
    <defs><linearGradient id={`${id}-box`} x2="0" y2="1"><stop stopColor="#AD8656"/><stop offset=".5" stopColor="#98734A"/><stop offset="1" stopColor="#7F5F3C"/></linearGradient><radialGradient id={`${id}-light`}><stop stopColor={palette.bulb}/><stop offset="1" stopColor="#3A2614"/></radialGradient></defs>
    <ellipse cx="98" cy="134" rx="69" ry="6" fill="#0007"/>
    <polygon points={poly([[-54,54,22],[54,54,22],[54,54,-22],[-54,54,-22]])} fill={openness > .1 ? `url(#${id}-light)` : '#2A1E13'}/>
    {[-1,1].map(side => <polygon key={side} points={poly([[side*54,54,22],[side*54-side*Math.cos(angle)*53.5,54+Math.sin(angle)*53.5,22],[side*54-side*Math.cos(angle)*53.5,54+Math.sin(angle)*53.5,-22],[side*54,54,-22]])} fill={side < 0 ? '#B38C5E' : '#9D764A'} stroke="#DEC294" strokeWidth="1.4"/>)}
    <polygon points={poly([[-54,0,22],[54,0,22],[54,54,22],[-54,54,22]])} fill={`url(#${id}-box)`} stroke="#65492D" strokeWidth=".75"/>
    <path d={`M${project(-54,54,22).join(',')}L${project(54,54,22).join(',')}`} stroke="#D7B886" strokeWidth="2"/>
    <rect x="88" y="99" width="20" height="24" rx="1" fill="#DECC9F" opacity=".65"/>
    <path d="m93 117 5-5 5 5m-5-5v10" stroke="#76603D" fill="none" strokeWidth="1.3"/>
  </svg>;
};

export const DropContent: React.FC<{hoveredZone?: 'shelf' | 'airDrop' | null; openness?: number; count?: number; copyOpacity?: number}> = ({hoveredZone = 'shelf', openness = 1, count = 0, copyOpacity=1}) => <div style={{display: 'flex', gap: 8, height: '100%'}}>
  <div style={{...cardStyle, flex: 1, display: 'flex', alignItems: 'center', gap: 0, boxShadow: `${cardStyle.boxShadow}, ${hoveredZone === 'shelf' ? 'inset 0 0 0 1px #FFB547B0, 0 0 8px #FFB54718' : '0 0 0 transparent'}`}}>
    <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at 20% 45%,#FFB54725,transparent 75%)', opacity: hoveredZone === 'shelf' ? 1 : 0}}/>
    <CardboardBox openness={openness} width={108}/>
    <div style={{position: 'relative', opacity: (hoveredZone === 'shelf' ? 1 : .4)*copyOpacity, paddingRight: 9}}>
      <div style={{fontFamily: rounded, fontSize: 16, fontWeight: 600, letterSpacing: '-.25px', whiteSpace: 'nowrap'}}>{hoveredZone === 'shelf' ? 'Suéltalo, ya lo guardo' : 'Guárdalo arriba'}</div>
      <div style={{fontSize: 11.5, marginTop: 4, color: palette.secondary}}>{count > 0 ? `Ya hay ${count} esperando.` : 'Hasta que lo bajes.'}</div>
    </div>
  </div>
  <div style={{...cardStyle, width: 128, flexShrink: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', boxShadow: `${cardStyle.boxShadow}, ${hoveredZone === 'airDrop' ? 'inset 0 0 0 1px #86B6D9BB' : '0 0 0 transparent'}`}}>
    <div style={{transform: `translateY(${hoveredZone === 'airDrop' ? -3 : 0}px) rotate(-5deg)`, marginBottom: 4, opacity: hoveredZone === 'airDrop' ? 1 : .5}}><Glyph name="plane" size={34} color={hoveredZone === 'airDrop' ? '#BBD8E4' : palette.paper}/></div>
    <div style={{textAlign: 'center', opacity: hoveredZone === 'airDrop' ? 1 : .4}}><div style={{fontFamily: rounded, fontSize: 12, fontWeight: 600}}>AirDrop</div><div style={{fontSize: 10.5, color: palette.secondary, marginTop: 1}}>a otro dispositivo</div></div>
  </div>
</div>;

export const MusicContent: React.FC<{progress?: number; playing?: boolean; title?:string}> = ({progress = .34, playing = true, title='Arriba'}) => {
  const p = Math.max(0, Math.min(1, progress));
  const elapsed = Math.round(p * 225);
  const time = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2,'0')}`;
  return <div style={{...cardStyle, borderRadius: 13, display: 'flex', alignItems: 'center', gap: 12, padding: '8px 10px', boxSizing: 'border-box'}}>
    <div style={{width: 66, height: 66, flexShrink: 0, borderRadius: 7, overflow: 'hidden', position: 'relative', background: '#C2AB86', boxShadow: `inset 0 .75px 0 #FFF4, 0 3px 6px #0008, 0 0 10px ${playing ? '#FFB54729' : 'transparent'}`}}>
      <svg viewBox="0 0 66 66" width="66" height="66"><rect width="66" height="66" fill="#D5BC90"/><circle cx="43" cy="19" r="13" fill="#E3A14A"/><path d="M0 66 26 13 55 66Z" fill="#3B4942"/><path d="M27 66 46 31 66 66Z" fill="#6E785E"/><path d="m26 13 9 36-16-21Z" fill="#62715B"/><text x="6" y="60" fontFamily={system} fontSize="5" fontWeight="600" letterSpacing="1.8" fill="#FAE7C5">ARRIBA</text></svg>
    </div>
    <div style={{flex: 1, minWidth: 0}}>
      <div style={{fontSize: 13.5, fontWeight: 600}}>{title}</div>
      <div style={{fontSize: 11.5, color: palette.secondary, marginTop: 2}}>Altillo <span style={{color: palette.tertiary}}>· Sesiones en el desván</span></div>
      <div style={{display: 'flex', alignItems: 'center', gap: 7, marginTop: 8}}><div style={{height: 5, flex: 1, borderRadius: 5, background: palette.plank, boxShadow: 'inset 0 1px 1px #0006'}}><div style={{height: '100%', width: `${p * 100}%`, borderRadius: 5, background: 'linear-gradient(#FFBE5D,#DE9833)', boxShadow: '0 0 3px #FFB54755'}}/></div><span style={{fontSize: 10.5, fontVariantNumeric: 'tabular-nums', color: palette.tertiary, whiteSpace: 'nowrap'}}>{time} / 3:45</span></div>
    </div>
    <div style={{display: 'flex', alignItems: 'center', gap: 4}}><div style={{padding: 6}}><Glyph name="previous" size={11} color={palette.secondary}/></div><div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', width: 33, height: 28, borderRadius: 7, background: 'linear-gradient(#FFC66D,#E8A03A)', boxShadow: 'inset 0 1px 0 #FFE6B799, 0 1px 3px #0006'}}><Glyph name={playing ? 'pause' : 'play'} size={12} color="#2B1A05"/></div><div style={{padding: 6}}><Glyph name="next" size={11} color={palette.secondary}/></div></div>
  </div>;
};

export const CalendarContent: React.FC<{joinPressed?: boolean}> = ({joinPressed = false}) => <div style={{height: '100%'}}>
  <div style={{...cardStyle, height: 46, borderRadius: 12, display: 'flex', alignItems: 'center', padding: '0 8px 0 10px', gap: 10, background: 'radial-gradient(ellipse at 100% 50%,#FFB54718,transparent 65%),linear-gradient(#211C16,#191510)', boxShadow: `${cardStyle.boxShadow},inset 0 0 0 .75px #FFB54780`}}>
    <div style={{width: 3.5, height: 28, borderRadius: 4, background: 'linear-gradient(#A3BCDB,#75879B)', boxShadow: '0 0 3px #86B6D944'}}/>
    <div style={{flex: 1}}><div style={{fontSize: 13, fontWeight: 600}}>Revisión de diseño</div><div style={{fontSize: 11.5, color: palette.secondary, marginTop: 3}}>15:00 – 15:30 <span style={{color: palette.tertiary}}>· Estudio</span></div></div>
    <div style={{display: 'flex', alignItems: 'center', gap: 4, color: palette.bulb, whiteSpace: 'nowrap', fontSize: 11.5, fontWeight: 600, fontFamily: rounded}}><Glyph name="clock" size={10} color={palette.bulb}/>en 12 min</div>
    <div style={{height: 24, padding: '0 10px', display: 'flex', alignItems: 'center', borderRadius: 6, fontSize: 11.5, fontWeight: 600, color: '#2B1A05', background: joinPressed ? '#DD9A3A' : 'linear-gradient(#FFC66D,#E8A03A)', transform: `scale(${joinPressed ? .96 : 1})`, boxShadow: 'inset 0 .75px 0 #FFE6B799,0 1px 2px #0005'}}>Unirse</div>
  </div>
  <div style={{...cardStyle, height: 24, marginTop: 5, borderRadius: 8, display: 'flex', alignItems: 'center', gap: 8, padding: '0 9px', fontSize: 11.5}}><div style={{width: 6, height: 6, borderRadius: '50%', background: palette.sage}}/><span style={{fontSize: 11, color: palette.secondary, fontVariantNumeric: 'tabular-nums'}}>16:00</span><span>Entrega final</span></div>
</div>;

export type NotchPanelProps = {
  module: 'shelf' | 'drop' | 'music' | 'calendar'; width?: number; children?: ReactNode;
  count?: number; progress?: number; playing?: boolean; shelfItems?: ShelfFilmItem[];
  hoveredZone?: 'shelf' | 'airDrop' | null; openness?: number; joinPressed?: boolean;
  /** Optional caller-owned body opacity, useful for frame-driven module swaps. */
  bodyOpacity?: number; style?: CSSProperties;
};

/** 560 × 150 native-point silhouette. Children override the body (x26,y36,w508,h104).
 * Shelf tile centers are width/2 + [-82,0,82], artwork center y80 and plank y102.
 * Hardware camera area stays empty: x=(width-185)/2,y0,w185,h32. */
export const NotchPanel: React.FC<NotchPanelProps> = ({module, width = 560, children, count = 3, progress = .34, playing = true, shelfItems, hoveredZone = 'shelf', openness = 1, joinPressed = false, bodyOpacity = 1, style}) => {
  const tab = module === 'drop' ? 'shelf' : module;
  const modules = [{id: 'shelf', label: 'Altillo'}, {id: 'usage', label: 'Uso'}, {id: 'agents', label: 'Agentes'}, {id: 'calendar', label: 'Agenda'}, {id: 'mirror', label: 'Espejo'}, {id: 'music', label: 'Sonando'}];
  const body = children ?? (module === 'shelf' ? <ShelfContent items={shelfItems ?? defaultItems.slice(0, count)}/> : module === 'drop' ? <DropContent hoveredZone={hoveredZone} openness={openness} count={count}/> : module === 'music' ? <MusicContent progress={progress} playing={playing}/> : <CalendarContent joinPressed={joinPressed}/>);
  return <div style={{position: 'relative', width, height: 150, color: palette.paper, fontFamily: system, WebkitFontSmoothing: 'antialiased', fontSize: 12, ...style}}>
    <svg width={width} height="150" viewBox={`0 0 ${width} 150`} style={{position: 'absolute', inset: 0, overflow: 'visible', filter: 'drop-shadow(0 8px 14px #0005)'}}><path d={`M0 0Q14 0 14 14V126Q14 150 38 150H${width - 38}Q${width - 14} 150 ${width - 14} 126V14Q${width - 14} 0 ${width} 0Z`} fill="#000"/></svg>
    <div style={{position: 'absolute', left: 20, top: 5, height: 22, display: 'flex', alignItems: 'center', gap: 0, opacity: module === 'drop' ? .4 : 1}}>
      {modules.map(m => <div key={m.id} style={{height: 22, width: m.id === tab ? undefined : 17, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 3, padding: m.id === tab ? '0 6px' : 0, borderRadius: 7, boxSizing: 'border-box', background: m.id === tab ? 'linear-gradient(#3B3026,#2B231B)' : undefined, border: m.id === tab ? '1px solid #A9824A' : undefined, boxShadow: m.id === tab ? 'inset 0 .5px 0 #E8C98799,inset 0 -1px 0 #0006,0 1px 1.5px #000B' : undefined}}><Glyph name={m.id} size={11} color={m.id === tab ? palette.paper : palette.secondary}/>{m.id === tab && <span style={{fontFamily: rounded, fontSize: 10.5, fontWeight: 600, whiteSpace: 'nowrap'}}>{m.label}</span>}</div>)}
    </div>
    {module !== 'drop' && <div style={{position: 'absolute', top: 5, right: 23, height: 22, display: 'flex', alignItems: 'center', gap: 7, fontSize: 11, color: palette.tertiary}}>{module === 'shelf' && <><span><span style={{color: palette.paper, fontWeight: 600}}>{count}</span> {count === 1 ? 'cosa' : 'cosas'} arriba</span><span style={{color: palette.secondary, padding: '3px 6px', borderRadius: 5, background: '#FFFFFF08'}}>Vaciar</span></>}<Glyph name="gear" size={11} color={palette.secondary}/></div>}
    <div style={{position: 'absolute', left: 26, right: 26, top: 36, height: module === 'shelf' ? 97 : module === 'drop' ? 100 : 104, opacity: bodyOpacity}}>{body}</div>
    <div style={{position: 'absolute', left: 26, right: 26, top: 34, height: 103, borderRadius: 14, background: `radial-gradient(ellipse at 50% 0%,rgba(255,181,71,${module === 'drop' ? .07 : .035}),transparent 74%)`, pointerEvents: 'none'}}/>
  </div>;
};
