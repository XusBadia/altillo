import {Composition} from 'remotion';
import {AltilloStopMotion} from './AltilloStopMotion';
import {AltilloLaPuerta, LA_PUERTA_DURATION} from './AltilloLaPuerta';
import {AltilloProductDemo} from './AltilloProductDemo';
import {AltilloDirectorCut,DIRECTOR_FRAMES} from './AltilloDirectorCut';
import {AltilloAnuncio, ANUNCIO_FPS, ANUNCIO_FRAMES} from './anuncio/Anuncio';
import {YTAvatar, YTBanner, YTThumb} from './anuncio/YouTube';
import {AltilloMisterio, MISTERIO_FPS, MISTERIO_FRAMES} from './anuncio/Misterio';
import {PHFeatures, PHOpen, PHThumb, PH_THUMB_FRAMES} from './anuncio/ProductHunt';

const AltilloAnuncioEN = () => <AltilloAnuncio lang="en" score="b"/>;

const AltilloMisterioEN = () => <AltilloMisterio lang="en"/>;

const AltilloTrailerDemo = () => <AltilloLaPuerta productDemo/>;

export const RemotionRoot = () => (
  <>
    <Composition id="AltilloAnuncio" component={AltilloAnuncio} durationInFrames={ANUNCIO_FRAMES} fps={ANUNCIO_FPS} width={1920} height={1080}/>
    <Composition id="AltilloMisterio" component={AltilloMisterio} durationInFrames={MISTERIO_FRAMES} fps={MISTERIO_FPS} width={1920} height={1080}/>
    <Composition id="AltilloMisterioEN" component={AltilloMisterioEN} durationInFrames={MISTERIO_FRAMES} fps={MISTERIO_FPS} width={1920} height={1080}/>
    <Composition id="PHFeatures" component={PHFeatures} durationInFrames={1} fps={30} width={1270} height={760}/>
    <Composition id="PHOpen" component={PHOpen} durationInFrames={1} fps={30} width={1270} height={760}/>
    <Composition id="PHThumb" component={PHThumb} durationInFrames={PH_THUMB_FRAMES} fps={30} width={240} height={240}/>
    <Composition id="YTBanner" component={YTBanner} durationInFrames={1} fps={30} width={2560} height={1440}/>
    <Composition id="YTAvatar" component={YTAvatar} durationInFrames={1} fps={30} width={800} height={800}/>
    <Composition id="YTThumb" component={YTThumb} durationInFrames={1} fps={30} width={1280} height={720}/>
    <Composition id="AltilloAnuncioEN" component={AltilloAnuncioEN} durationInFrames={ANUNCIO_FRAMES} fps={ANUNCIO_FPS} width={1920} height={1080}/>
    <Composition id="AltilloDirectorCut" component={AltilloDirectorCut} durationInFrames={DIRECTOR_FRAMES} fps={30} width={1920} height={1080}/>
    <Composition id="AltilloTrailerDemo" component={AltilloTrailerDemo} durationInFrames={1200} fps={30} width={1920} height={1080}/>
    <Composition id="AltilloDemoOnly" component={AltilloProductDemo} durationInFrames={600} fps={30} width={1920} height={1080}/>
    <Composition
      id="AltilloStopMotion"
      component={AltilloStopMotion}
      durationInFrames={990}
      fps={30}
      width={1920}
      height={1080}
    />
    <Composition
      id="AltilloLaPuerta"
      component={AltilloLaPuerta}
      durationInFrames={LA_PUERTA_DURATION}
      fps={30}
      width={1920}
      height={1080}
    />
  </>
);
