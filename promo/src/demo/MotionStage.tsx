import type {ReactNode} from 'react';
import {AbsoluteFill, Easing, interpolate, useCurrentFrame} from 'remotion';

export const clamp = {extrapolateLeft:'clamp', extrapolateRight:'clamp'} as const;
export const ease = Easing.bezier(.22, 1, .36, 1);
export const tween = (f:number, a:number, b:number, x=0, y=1) => interpolate(f,[a,b],[x,y],{...clamp,easing:ease});
export const DEMO_FRAMES = 600;

export const Stage = ({children}:{children:ReactNode}) => {
  const f=useCurrentFrame();
  return <AbsoluteFill style={{background:'#eee9e1',overflow:'hidden',fontFamily:'"Helvetica Neue", sans-serif',color:'#211b16'}}>
    <AbsoluteFill style={{background:'radial-gradient(ellipse at 52% 28%, #fffdfa 0%, #f0e8dd 48%, #d1c0ac 100%)'}}/>
    <div style={{position:'absolute',left:280,top:725,width:1360,height:105,borderRadius:'50%',background:'#5f4330',filter:'blur(55px)',opacity:.14}}/>
    {children}
    <div style={{position:'absolute',bottom:45,left:80,fontSize:16,letterSpacing:'.08em',color:'#695c4f'}}>ALTILLO / macOS</div>
    <div style={{position:'absolute',bottom:45,right:80,fontSize:16,color:'#695c4f'}}>Interfaz recreada · Contenido de demostración</div>
    <AbsoluteFill style={{background:'#17110c',pointerEvents:'none',opacity:1-tween(f,0,22)}}/>
    <AbsoluteFill style={{background:'#17110c',pointerEvents:'none',opacity:tween(f,580,599)}}/>
  </AbsoluteFill>;
};

export const Headline = ({first,second,frame}:{first:string;second?:string;frame:number}) => <div style={{position:'absolute',top:105,left:0,width:'100%',textAlign:'center',opacity:tween(frame,10,30),transform:`translateY(${tween(frame,10,38,18,0)}px)`}}>
  <div style={{fontSize:80,fontWeight:550,letterSpacing:'-3.5px',lineHeight:1.06}}>{first}</div>
  {second&&<div style={{fontSize:29,marginTop:20,letterSpacing:'-.5px',color:'#817160'}}>{second}</div>}
</div>;

export const Camera = ({children,scale=2.65,y=378,angle=0,x=960}:{children:ReactNode;scale?:number;y?:number;angle?:number;x?:number}) => <div style={{position:'absolute',left:x,top:y,perspective:2200}}><div style={{width:560,transformOrigin:'50% 0',transform:`translateX(-50%) rotateX(${angle}deg) scale(${scale})`,filter:'drop-shadow(0 22px 28px #34201428)'}}>{children}</div></div>;

export const Cursor = ({x,y,press=0,opacity=1}:{x:number;y:number;press?:number;opacity?:number}) => <svg width="43" height="54" viewBox="0 0 32 40" style={{position:'absolute',left:x,top:y,opacity,filter:'drop-shadow(0 3px 3px #0005)',transform:`scale(${1-press*.12})`,transformOrigin:'4px 3px'}}><path d="M3 2 L4 31 L12 24 L19 38 L25 35 L18 22 L29 21 Z" fill="#151515" stroke="white" strokeWidth="2.2" strokeLinejoin="round"/></svg>;
