import {AbsoluteFill, Img, staticFile} from 'remotion';
import {palette, system} from './parts';

// Imágenes del canal de YouTube. Banner 2560×1440: todo lo importante dentro de la zona segura central de
// 1546×423 (lo único visible en móvil); el resto es fondo. Avatar 800×800: YouTube lo recorta en círculo.
// Miniatura 1280×720 para el vídeo del anuncio.

export const YTBanner = () => (
  <AbsoluteFill style={{backgroundColor: palette.ink, fontFamily: system, color: palette.paper}}>
    <Img
      src={staticFile('anuncio/product/wallpaper.png')}
      style={{position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', opacity: 0.55}}
    />
    <AbsoluteFill style={{background: 'radial-gradient(ellipse 45% 30% at 50% 50%, rgba(16,14,12,.78), rgba(16,14,12,.35) 70%, rgba(16,14,12,.2))'}} />
    {/* Zona segura 1546×423 centrada */}
    <div
      style={{
        position: 'absolute',
        left: (2560 - 1546) / 2,
        top: (1440 - 423) / 2,
        width: 1546,
        height: 423,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: 56,
      }}
    >
      <Img
        src={staticFile('icon/AltilloIconMaster-11A.png')}
        style={{width: 250, height: 250, borderRadius: 56, boxShadow: '0 30px 70px rgba(0,0,0,.55)'}}
      />
      <div>
        <div style={{fontSize: 132, fontWeight: 650, letterSpacing: '-5px', lineHeight: 1}}>Altillo</div>
        <div style={{fontSize: 50, fontWeight: 500, letterSpacing: '-1px', color: '#EAD9BF', marginTop: 18}}>
          Your Mac already had an attic.
        </div>
        <div style={{fontSize: 30, fontWeight: 600, color: palette.amber, marginTop: 20}}>
          Free &amp; open source · altillo.app
        </div>
      </div>
    </div>
  </AbsoluteFill>
);

export const YTAvatar = () => (
  <AbsoluteFill style={{backgroundColor: palette.ink, alignItems: 'center', justifyContent: 'center'}}>
    <div
      style={{
        position: 'absolute',
        width: 800,
        height: 800,
        background: 'radial-gradient(circle, rgba(233,165,74,.28), transparent 62%)',
      }}
    />
    <Img src={staticFile('icon/AltilloIconMaster-11A.png')} style={{width: 520, height: 520, borderRadius: 118}} />
  </AbsoluteFill>
);

export const YTThumb = () => (
  <AbsoluteFill style={{backgroundColor: palette.ink, fontFamily: system, color: palette.paper}}>
    <Img src={staticFile('anuncio/youtube/frame-drop.png')} style={{position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover'}} />
    {/* La caja abierta queda a la vista a la izquierda; el texto, sobre el lado oscurecido. */}
    <AbsoluteFill style={{background: 'linear-gradient(270deg, rgba(16,14,12,.98) 0%, rgba(16,14,12,.96) 50%, transparent 63%)'}} />
    <div style={{position: 'absolute', right: 60, top: 0, bottom: 0, display: 'flex', flexDirection: 'column', justifyContent: 'center', width: 560}}>
      <div style={{display: 'flex', alignItems: 'center', gap: 20}}>
        <Img src={staticFile('icon/AltilloIconMaster-11A.png')} style={{width: 84, height: 84, borderRadius: 19}} />
        <div style={{fontSize: 56, fontWeight: 650, letterSpacing: '-2px'}}>Altillo</div>
      </div>
      <div style={{fontSize: 68, fontWeight: 700, letterSpacing: '-2.4px', lineHeight: 1.02, marginTop: 30}}>
        Your Mac&apos;s notch, finally useful.
      </div>
    </div>
  </AbsoluteFill>
);
