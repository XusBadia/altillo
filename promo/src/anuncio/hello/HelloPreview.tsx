import {AbsoluteFill, Composition} from 'remotion';
import {Hello} from './Hello';
import type {HelloWord} from './glyphs';

const FPS = 60;
const DURATION = Math.round(4.5 * FPS);

const Preview = ({word}: {word: HelloWord}) => (
  <AbsoluteFill style={{backgroundColor: '#100E0C'}}>
    <Hello word={word} startFrame={Math.round(0.25 * FPS)} exitFrame={Math.round(3.7 * FPS)} />
  </AbsoluteFill>
);

export const HelloPreviewRoot = () => (
  <>
    <Composition
      id="HelloPreview"
      component={Preview}
      durationInFrames={DURATION}
      fps={FPS}
      width={1920}
      height={1080}
      defaultProps={{word: 'hola' as HelloWord}}
    />
    <Composition
      id="HelloPreviewEN"
      component={Preview}
      durationInFrames={DURATION}
      fps={FPS}
      width={1920}
      height={1080}
      defaultProps={{word: 'hello' as HelloWord}}
    />
  </>
);
