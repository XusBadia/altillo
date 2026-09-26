import {Composition} from 'remotion';
import {AltilloStopMotion} from './AltilloStopMotion';
import {AltilloLaPuerta, LA_PUERTA_DURATION} from './AltilloLaPuerta';
import {AltilloProductDemo} from './AltilloProductDemo';
import {AltilloDirectorCut,DIRECTOR_FRAMES} from './AltilloDirectorCut';

const AltilloTrailerDemo = () => <AltilloLaPuerta productDemo/>;

export const RemotionRoot = () => (
  <>
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
