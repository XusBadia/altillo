import {AbsoluteFill, Composition, Img, staticFile} from 'remotion';
import {Cursor, SCREEN} from './parts';
import {DragImage, DropHighlight, FinderWindow, MailWindow, finderFile, finderItemCenter, mailDropRect} from './windows';

// Vista previa aislada de las ventanas de Tahoe (no forma parte del anuncio).
const finder = {x: 150, y: 200, width: 520, height: 360};
const mail = {x: 790, y: 300, width: 520, height: 380};

const Desktop = ({scale, focusX, focusY, lang, drop}: {scale: number; focusX: number; focusY: number; lang: 'es' | 'en'; drop?: boolean}) => {
  const pdf = finderFile(0, lang);
  const drag = drop ? {x: mailDropRect(mail).x + 150, y: mailDropRect(mail).y + 90} : {x: 720, y: 150};
  const r = mailDropRect(mail);
  return (
    <AbsoluteFill style={{background: '#120C07', overflow: 'hidden'}}>
      <div
        style={{
          position: 'absolute',
          width: SCREEN.width,
          height: SCREEN.height,
          left: 960 - focusX * scale,
          top: 540 - focusY * scale,
          transform: `scale(${scale})`,
          transformOrigin: '0 0',
        }}
      >
        <Img src={staticFile('anuncio/product/wallpaper.png')} style={{position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover'}} />
        <FinderWindow {...finder} lang={lang} selectedIndex={0} draggingIndex={0} />
        <MailWindow {...mail} lang={lang} attached={drop ? 0 : 1} />
        {drop ? <DropHighlight {...r} progress={1} /> : null}
        <DragImage {...drag} label={pdf.label} kind={pdf.kind} copyBadge />
        <Cursor {...drag} />
      </div>
    </AbsoluteFill>
  );
};

const zoom = finderItemCenter(0, finder);

export const WindowsPreviewRoot = () => (
  <>
    <Composition id="Wide" component={() => <Desktop scale={1.2} focusX={SCREEN.width / 2} focusY={SCREEN.height / 2} lang="es" />} width={1920} height={1080} fps={30} durationInFrames={1} />
    <Composition id="WideEn" component={() => <Desktop scale={1.2} focusX={SCREEN.width / 2} focusY={SCREEN.height / 2} lang="en" drop />} width={1920} height={1080} fps={30} durationInFrames={1} />
    <Composition id="Zoom" component={() => <Desktop scale={2.3} focusX={zoom.x + 90} focusY={zoom.y + 60} lang="es" />} width={1920} height={1080} fps={30} durationInFrames={1} />
    <Composition id="ZoomMail" component={() => <Desktop scale={2.3} focusX={mail.x + 220} focusY={mail.y + 200} lang="es" />} width={1920} height={1080} fps={30} durationInFrames={1} />
  </>
);
