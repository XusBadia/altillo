import {useCurrentFrame} from 'remotion';
import {NotchPanel,MusicContent,CalendarContent} from '../FilmUI';
import {DemoShelfBody} from './ShelfScene';
import {Camera,Cursor,Headline,tween} from './MotionStage';

export const MusicScene=()=>{
  const f=useCurrentFrame();const press=(f>=62&&f<72)||(f>=99&&f<106);const paused=f>=67&&f<102;
  return <>
    <div style={{opacity:1-tween(f,106,119)}}><Headline first="Tu música. Aquí arriba." second="Música y Spotify, sin cambiar de ventana." frame={f}/></div>
    <Camera y={tween(f,0,28,378,390)} scale={tween(f,0,28,2.65,3.05)} angle={0}>
      <NotchPanel module={f<6?'shelf':'music'} playing={!paused}>
        <div style={{position:'absolute',inset:0,opacity:1-tween(f,0,14),transform:`translateY(${-tween(f,0,16)*12}px)`}}><DemoShelfBody/></div>
        <div style={{position:'absolute',inset:0,opacity:tween(f,3,18),transform:`translateY(${tween(f,3,20,14,0)}px)`}}><MusicContent playing={!paused} progress={.34+(paused?67:Math.min(f,67))/1500+(f>102?(f-102)/1500:0)}/></div>
      </NotchPanel>
    </Camera>
    <Cursor x={tween(f,22,55,1610,1571)} y={tween(f,22,55,875,658)} press={press?1:0} opacity={tween(f,20,30)*(1-tween(f,108,120))}/>
    <div style={{position:'absolute',left:0,right:0,top:854,textAlign:'center',fontSize:24,color:'#8b7967',opacity:tween(f,70,80)*(1-tween(f,101,109))}}>Un instante de silencio.</div>
  </>;
};

export const CalendarScene=()=>{
  const f=useCurrentFrame();
  return <>
    <Headline first="Lo siguiente, a la vista." second="Tu próxima reunión. Su enlace. Y nada más." frame={f}/>
    <Camera y={390} scale={tween(f,0,26,3.05,2.8)} angle={tween(f,105,148,0,9)}>
      <div style={{opacity:1-tween(f,143,149),height:150-tween(f,125,149)*118,overflow:'hidden',borderRadius:'0 0 24px 24px'}}><NotchPanel module={f<6?'music':'calendar'}>
        <div style={{position:'absolute',inset:0,opacity:1-tween(f,0,14),transform:`translateY(${-tween(f,0,16)*12}px)`}}><MusicContent progress={.395}/></div>
        <div style={{position:'absolute',inset:0,opacity:tween(f,3,18),transform:`translateY(${tween(f,3,20,14,0)}px)`}}><CalendarContent/></div>
      </NotchPanel></div>
      <div style={{position:'absolute',top:0,left:187.5,width:185,height:32,background:'#000',borderRadius:'0 0 10px 10px',opacity:tween(f,128,148)}}/>
    </Camera>
    <div style={{position:'absolute',top:852,width:'100%',textAlign:'center',fontSize:27,color:'#8b7967',opacity:tween(f,36,56)*(1-tween(f,113,133))}}>En su sitio. Sin ocupar el tuyo.</div>
  </>;
};
