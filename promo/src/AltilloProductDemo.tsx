import {Audio,Sequence,staticFile,interpolate,useCurrentFrame} from 'remotion';
import {Stage,clamp} from './demo/MotionStage';
import {ShelfScene} from './demo/ShelfScene';
import {MusicScene,CalendarScene} from './demo/ModuleScenes';

export const AltilloProductDemo=()=>{
  const frame=useCurrentFrame();
  return <Stage>
    <Sequence durationInFrames={330} name="Archivos · dejar, mirar, recuperar"><ShelfScene/></Sequence>
    <Sequence from={330} durationInFrames={120} name="Sonando · pausa"><MusicScene/></Sequence>
    <Sequence from={450} durationInFrames={150} name="Agenda · lo siguiente"><CalendarScene/></Sequence>
    <Audio src={staticFile('audio/demo-bed.m4a')} volume={interpolate(frame,[0,15,391,397,430,438,573,599],[0,.75,.75,0,0,.75,.75,0],clamp)}/>
    {[128,141,198,286,397,432,459].map((at)=><Sequence key={at} from={at} durationInFrames={24}><Audio src={staticFile('audio/switch.wav')} volume={.14}/></Sequence>)}
    {[70,208,290].map((at)=><Sequence key={at} from={at} durationInFrames={40}><Audio src={staticFile('audio/page-turn.wav')} volume={.18}/></Sequence>)}
  </Stage>;
};
