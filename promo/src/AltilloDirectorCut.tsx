import type {CSSProperties, ReactNode} from 'react';
import {AbsoluteFill, Audio, Easing, Freeze, Img, interpolate, OffthreadVideo, Sequence, staticFile, useCurrentFrame} from 'remotion';
import {CalendarContent, DropContent, FileArtwork, MusicContent, NotchPanel} from './FilmUI';
import {DemoShelfBody} from './demo/ShelfScene';
import {Cursor} from './demo/MotionStage';

// One continuous art-directed space. All text and UI are deterministic vectors;
// generative footage is restricted to two short, inspected doorway shots.
export const DIRECTOR_FRAMES = 1200;
const clamp = {extrapolateLeft:'clamp', extrapolateRight:'clamp'} as const;
const smooth = Easing.bezier(.4,0,.2,1);
const out = Easing.bezier(.22,1,.36,1);
const t = (f:number,a:number,b:number,x=0,y=1,curve=out) => interpolate(f,[a,b],[x,y],{...clamp,easing:curve});
const pulse = (f:number,a:number,b:number,c:number,d:number) => t(f,a,b)*(1-t(f,c,d));
const font='"Helvetica Neue", Helvetica, Arial, sans-serif';
const ink='#100e0c';
const paper='#f6efe3';
const full:CSSProperties={width:'100%',height:'100%',objectFit:'cover'};

function Caption({children,f,start,end,y=881,size=44}:{children:ReactNode;f:number;start:number;end:number;y?:number;size?:number}) {
  return <div data-film-caption style={{position:'absolute',left:100,right:100,top:y,textAlign:'center',fontSize:size,lineHeight:1.15,letterSpacing:'-.9px',fontWeight:400,color:paper,opacity:pulse(f,start,start+12,end-12,end),transform:`translateY(${t(f,start,start+20,8,0)}px)`}}>{children}</div>;
}

function Opening({f}:{f:number}) {
  const z=t(f,0,144,1.015,1.10,smooth);
  return <>
    <Sequence durationInFrames={144}>
      <AbsoluteFill style={{overflow:'hidden'}}>
        <Img src={staticFile('film/director-opening.png')} style={{...full,transform:`scale(${z})`,transformOrigin:'58% 27%'}}/>
        <AbsoluteFill style={{background:'linear-gradient(transparent 55%,#08060499)'}}/>
        <Caption f={f} start={13} end={73} y={895} size={52}>Tu Mac ya tenía un altillo.</Caption>
        <Caption f={f} start={79} end={140} y={895} size={52}>Solo le faltaba una puerta.</Caption>
      </AbsoluteFill>
    </Sequence>
    <Sequence from={144} durationInFrames={59}>
      <Macro/>
    </Sequence>
  </>;
}

function Macro(){
  const f=useCurrentFrame();
  return <AbsoluteFill><Freeze frame={Math.min(f,43)}><OffthreadVideo muted src={staticFile('film/director-door-macro.mp4')} playbackRate={.72} style={full}/></Freeze></AbsoluteFill>;
}

function Studio({f}:{f:number}){
  return <AbsoluteFill style={{background:ink}}>
    <AbsoluteFill style={{background:'radial-gradient(ellipse at 52% 47%,#403022 0%,#251d17 30%,#120f0d 64%,#0c0b0a 100%)'}}/>
    <div style={{position:'absolute',width:1800,height:460,left:60,top:480,background:'radial-gradient(ellipse,#c1894220,transparent 65%)',transform:`rotate(${t(f,200,850,-8,4)}deg)`,filter:'blur(35px)'}}/>
    <div style={{position:'absolute',left:100,top:714,width:1720,height:138,borderRadius:'50%',background:'#000',opacity:.43,filter:'blur(50px)'}}/>
    <AbsoluteFill style={{opacity:.035,backgroundImage:'repeating-linear-gradient(112deg,transparent 0px,transparent 2px,#d6c3a7 2.2px,transparent 2.8px)',mixBlendMode:'soft-light'}}/>
  </AbsoluteFill>;
}

// Wipe content, never dissolve two text-bearing states over one another.
function ModuleBody({f}:{f:number}){
  const music=t(f,661,679,0,100,smooth);
  const agenda=t(f,751,769,0,100,smooth);
  return <div style={{position:'relative',height:104,overflow:'hidden',borderRadius:14}}>
    <div style={{position:'absolute',inset:0,clipPath:`inset(0 0 ${music}% 0)`}}><DemoShelfBody frame={f<461?131:220}/></div>
    <div style={{position:'absolute',inset:0,clipPath:`inset(${100-music}% 0 ${agenda}% 0)`}}><MusicContent title={f<713?'Arriba':'Al otro lado'} progress={f<713?.34+(f-661)/225/30:(f-713)/225/30} playing/></div>
    <div style={{position:'absolute',inset:0,clipPath:`inset(${100-agenda}% 0 0 0)`}}><CalendarContent/></div>
  </div>;
}

function Product({f}:{f:number}){
  const intro=t(f,190,254,0,1,smooth);
  const detail=t(f,424,458,0,1,smooth)-t(f,543,569,0,1,smooth);
  const musicCamera=t(f,638,684,0,1,smooth);
  const agendaCamera=t(f,737,783,0,1,smooth);
  const outro=t(f,900,956,0,1,smooth);
  const scale=(5.7-(5.7-2.7)*intro+.37*detail+.85*musicCamera-.4*agendaCamera)*(1-outro)+.43*outro;
  const cx=(1280-320*intro-110*musicCamera+70*agendaCamera)*(1-outro)+969*outro;
  const cy=(477-132*intro-20*musicCamera+5*agendaCamera)*(1-outro)+157*outro;
  const turn=(-11*(1-intro))*(1-outro);
  const opening=t(f,200,238,0,1,smooth);
  const close=t(f,890,918,0,1,smooth);
  const panelHeight=(32+118*opening)*(1-close)+32*close;
  const side=187.5*(1-opening)+187.5*close;
  const landed=f>=360;
  const module=f<661?'shelf':f<751?'music':'calendar';
  const alpha=1-t(f,951,969);
  const px=(local:number)=>cx+(local-280)*scale;
  const py=(local:number)=>cy+local*scale;
  const fileX=(i:number)=>px(182+i*82);
  const fileY=py(80);
  const preview=pulse(f,474,494,542,559);
  const copy=t(f,598,639,0,1,smooth);
  return <AbsoluteFill style={{opacity:alpha}}>
    <div style={{position:'absolute',left:cx,top:cy,perspective:2400}}>
      <div style={{width:560,transformOrigin:'50% 0',transform:`translateX(-50%) rotateY(${turn}deg) rotateZ(${-4*(1-intro)}deg) scale(${scale})`,filter:'drop-shadow(0 20px 24px #0009)'}}>
        <div style={{height:panelHeight,clipPath:`inset(0 ${Math.min(side,187.5)}px 0 ${Math.min(side,187.5)}px round 0 0 14px 14px)`,overflow:'hidden'}}>
          <NotchPanel module={!landed?'drop':module} count={landed?3:0} bodyOpacity={opening}>
            {landed?<ModuleBody f={f}/>:<DropContent count={0} copyOpacity={1-t(f,300,310)}/>}
          </NotchPanel>
        </div>
        <div style={{position:'absolute',height:.6,top:0,left:16,right:16,background:'linear-gradient(90deg,transparent,#b5a08845 40%,#eac78d80 68%,transparent)',opacity:.7}}/>
      </div>
    </div>

    {!landed && ([{kind:'image' as const,x:590,delay:0},{kind:'pdf' as const,x:952,delay:5},{kind:'note' as const,x:1310,delay:10}]).map((it,i)=>{
      const p=t(f,286+it.delay,348+it.delay,0,1,smooth);
      const appear=t(f,232+i*4,258+i*4);
      const x=it.x*(1-p)+fileX(i)*p;
      const y=765*(1-p)+fileY*p-110*Math.sin(p*Math.PI);
      return <div key={it.kind} style={{position:'absolute',left:x,top:y,width:150,height:150,opacity:appear,transform:`translate(-50%,-50%) rotate(${[-7,2,8][i]*(1-p)}deg) scale(${(1-p)*1.13+p*.9})`,filter:'drop-shadow(0 20px 20px #0007)'}}><FileArtwork kind={it.kind} size={150}/></div>;
    })}
    <Caption f={f} start={281} end={424}>Déjalo arriba.</Caption>

    {f>=432&&f<475&&<Cursor x={t(f,432,457,1450,fileX(1)+18)} y={t(f,432,457,775,fileY+20)} press={f>=459&&f<465?1:0} opacity={pulse(f,432,439,468,475)}/>}
    {f>=460&&f<504&&<div style={{position:'absolute',top:874,left:882,width:156,height:49,boxSizing:'border-box',textAlign:'center',paddingTop:11,borderRadius:10,background:'#28231e',border:'1px solid #77634a',boxShadow:'0 3px 0 #060504',fontSize:20,color:'#d9ccbb',opacity:pulse(f,460,466,496,504)}}>espacio</div>}
    {preview>0&&<div style={{position:'absolute',left:fileX(1)+(960-fileX(1))*preview,top:fileY+(540-fileY)*preview,width:630,height:565,background:'#fbf8f1',color:'#29231d',borderRadius:17,boxShadow:'0 50px 110px #000b,0 0 0 1px #ffffff55',overflow:'hidden',transform:`translate(-50%,-50%) scale(${.24+.76*preview})`}}>
      <div style={{height:42,background:'#e9e4db',display:'flex',alignItems:'center',padding:'0 18px',fontSize:16,color:'#776b5d',borderBottom:'1px solid #d9d1c4'}}><span>⊗</span><span style={{margin:'auto'}}>Propuesta.pdf</span><span style={{fontSize:12}}>Vista rápida</span></div>
      <div style={{padding:'37px 52px'}}><div style={{fontSize:10,letterSpacing:2.6,color:'#987a51'}}>ALTILLO / ESTUDIO</div><div style={{fontSize:47,lineHeight:1.24,letterSpacing:-2,marginTop:19}}>Una idea.<br/>Todo su espacio.</div><div style={{height:150,marginTop:24,borderRadius:3,overflow:'hidden',position:'relative',background:'linear-gradient(130deg,#293b37,#788174 65%,#d6be8e)'}}><div style={{position:'absolute',width:230,height:230,borderRadius:'50%',background:'#ead6ad',right:-35,top:-99}}/><div style={{position:'absolute',width:450,height:220,background:'#2d4942',transform:'rotate(-25deg)',left:-130,top:60}}/><div style={{position:'absolute',width:420,height:220,background:'#5e6c58',transform:'rotate(24deg)',right:-180,top:62}}/></div>{[100,92,69].map((v,i)=><div key={i} style={{height:4,background:'#ddd3c5',width:`${v}%`,marginTop:13}}/>)}</div>
    </div>}

    {f>=578&&f<653&&<>
      <div style={{position:'absolute',left:1200,top:757,width:338,height:103,boxSizing:'border-box',borderRadius:15,border:'1px solid #9f8d6d66',background:'#302920',opacity:pulse(f,578,595,640,653),display:'flex',alignItems:'center',padding:24,gap:23}}><div style={{fontSize:31,color:'#ccae7b'}}>↗</div><div><div style={{fontSize:21,fontWeight:500,color:paper}}>Tu proyecto</div><div style={{fontSize:14,color:'#ae9b81',marginTop:6}}>Propuesta.pdf</div></div></div>
      <div style={{position:'absolute',left:fileX(1)+(1280-fileX(1))*copy,top:fileY+(807-fileY)*copy-Math.sin(copy*Math.PI)*90,transform:`translate(-50%,-50%) scale(${1-copy*.42})`,opacity:pulse(f,594,599,634,643),filter:'drop-shadow(0 20px 22px #0007)'}}><FileArtwork kind="pdf" size={135}/></div>
      <Cursor x={fileX(1)+(1280-fileX(1))*copy+25} y={fileY+(807-fileY)*copy-Math.sin(copy*Math.PI)*90+30} opacity={pulse(f,584,594,640,650)}/>
    </>}
    <Caption f={f} start={571} end={652}>Y sigue a lo tuyo.</Caption>

    {/* Navigation motivates every module change; it is not a sequence of cards. */}
    {f>=638&&f<680&&<Cursor x={t(f,638,658,1250,px(154.92)-4)} y={t(f,638,658,815,py(16)-3)} opacity={pulse(f,638,644,673,680)} press={f>=658&&f<665?1:0}/>}
    {f>=690&&f<729&&<Cursor x={t(f,690,709,1590,px(512.5)-4)} y={t(f,690,709,790,py(88)-3)} opacity={pulse(f,690,696,723,729)} press={f>=710&&f<717?1:0}/>}
    <Caption f={f} start={686} end={741}>Tu música, a mano.</Caption>
    {f>=728&&f<773&&<Cursor x={t(f,729,748,px(512.5)-4,px(79.5)-4)} y={t(f,729,748,py(88)-3,py(16)-3)} opacity={pulse(f,728,736,766,773)} press={f>=748&&f<755?1:0}/>}
    <Caption f={f} start={779} end={858}>Lo siguiente, a la vista.</Caption>
    <div style={{position:'absolute',bottom:33,right:65,fontSize:14,letterSpacing:'.2px',color:'#a3927a',opacity:pulse(f,319,337,853,870)}}>Interfaz recreada · Contenido de demostración</div>
  </AbsoluteFill>;
}

function ReturnShot(){
  const f=useCurrentFrame();
  return <AbsoluteFill><Freeze frame={Math.min(f,51)}><OffthreadVideo muted src={staticFile('film/director-return-clean.mp4')} style={full}/></Freeze></AbsoluteFill>;
}

function Signature({f}:{f:number}){
  const p=t(f,1012,1061,0,1,smooth);
  const iconSize=76+324*p;
  const x=969-9*p;
  const y=175+232*p;
  return <>
    <AbsoluteFill style={{background:ink,opacity:t(f,1004,1045)}}/>
    <div style={{position:'absolute',left:470,top:112,width:980,height:650,background:'radial-gradient(ellipse,#9a641719,transparent 66%)',opacity:p}}/>
    <Img src={staticFile('icon/AltilloIconMaster-11A.png')} style={{position:'absolute',left:x-iconSize/2,top:y-iconSize/2,width:iconSize,height:iconSize,opacity:t(f,1012,1027)}}/>
    <div data-film-caption style={{position:'absolute',top:621,width:'100%',textAlign:'center',fontSize:103,lineHeight:1,fontWeight:500,letterSpacing:'-5px',color:paper,opacity:t(f,1050,1074),transform:`translateY(${t(f,1050,1078,10,0)}px)`}}>Altillo</div>
    <div data-film-caption style={{position:'absolute',top:768,width:'100%',textAlign:'center',fontSize:31,lineHeight:1.4,letterSpacing:'-.3px',color:'#cbbca7',opacity:t(f,1078,1100)}}>Un sitio arriba para lo importante.</div>
  </>;
}

export function AltilloDirectorCut(){
  const f=useCurrentFrame();
  const wipe=t(f,186,202,0,1,smooth);
  const edge=1920-2280*wipe;
  return <AbsoluteFill style={{background:ink,fontFamily:font,overflow:'hidden'}}>
    <Opening f={f}/>
    {f>=186&&f<1027&&<AbsoluteFill style={{clipPath:f<202?`inset(0 0 0 ${Math.max(0,edge)}px)`:undefined}}>
      <Studio f={f}/>
      <Product f={f}/>
    </AbsoluteFill>}
    {f>=186&&f<202&&<div style={{position:'absolute',top:-80,bottom:-80,width:320,left:edge-3,background:'linear-gradient(90deg,#0b0806,#181009 88%,#362416)',boxShadow:'-16px 0 32px #0009,2px 0 15px #d8953920',filter:'blur(6px)',transform:'rotate(-1deg)'}}/>}
    <Sequence from={939} durationInFrames={91}>
      <AbsoluteFill style={{opacity:t(f,939,969)}}><ReturnShot/></AbsoluteFill>
    </Sequence>
    {f>=1004&&<Signature f={f}/>}
    <AbsoluteFill style={{background:'#000',opacity:1-t(f,0,12),pointerEvents:'none'}}/>
    <Audio src={staticFile('audio/director-score.wav')} volume={1}/>
    {[360,463,661,713,751].map(frame=><Sequence key={frame} from={frame} durationInFrames={12}><Audio src={staticFile('audio/switch.wav')} volume={.12}/></Sequence>)}
    {[287,476,599].map(frame=><Sequence key={frame} from={frame} durationInFrames={24}><Audio src={staticFile('audio/page-turn.wav')} volume={.13}/></Sequence>)}
  </AbsoluteFill>;
}
