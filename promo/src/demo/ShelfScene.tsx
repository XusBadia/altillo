import {useCurrentFrame} from 'remotion';
import {FileArtwork, NotchPanel, woodMaterial} from '../FilmUI';
import {Camera, Cursor, Headline, tween} from './MotionStage';

const items=[{kind:'image' as const,name:'Portada.png'},{kind:'pdf' as const,name:'Propuesta.pdf'},{kind:'note' as const,name:'Ideas.txt'}];

export const DemoShelfBody=({frame:f=329}:{frame?:number})=><div style={{height:97,position:'relative',borderRadius:14,...woodMaterial,overflow:'hidden'}}>
  <div style={{position:'absolute',left:0,right:0,top:64,height:8,background:'linear-gradient(#756043,#352a20 45%,#15110d 100%)',boxShadow:'0 5px 8px #0009'}}/>
  {items.map((it,i)=><div key={it.name} style={{position:'absolute',left:131+i*82,top:19,transform:`translateY(${f<153?Math.sin(Math.max(0,f-131)/22*Math.PI)*2:i===1?-2:0}px)`}}>
    <div style={{width:50,height:50,filter:i===1&&f>180?'drop-shadow(0 2px 5px #ffb54766)':'none'}}><FileArtwork kind={it.kind} size={50}/></div>
    <div style={{position:'absolute',top:61,left:-13,width:76,textAlign:'center',fontSize:9.4,color:i===1&&f>180?'#ffb547':'#c4b7a7',whiteSpace:'nowrap'}}>{it.name.replace(/\.[^.]+$/,'')}</div>
  </div>)}
</div>;

export const ShelfScene=()=>{
  const f=useCurrentFrame();
  const open=tween(f,8,43);
  const landed=f>=131;
  const zoom=tween(f,154,185,2.65,3.1)-tween(f,252,280,0,.45);
  const preview=tween(f,200,220)-tween(f,254,272);
  const pull=tween(f,286,321);
  const fileX=(i:number,s=zoom)=>960+(26+156+i*82-280)*s;
  const fileY=378+(36+44)*zoom;
  return <>
    <div style={{opacity:1-tween(f,183,199)}}><Headline first="Déjalo arriba." second="Archivos a mano, entre una app y otra." frame={f}/></div>
    <div style={{opacity:tween(f,201,221)*(1-tween(f,315,329))}}><Headline first="Y sigue a lo tuyo." second="Una vista rápida. Y de vuelta a tu proyecto." frame={f}/></div>
    <Camera scale={zoom} y={378} angle={tween(f,0,48,12,0)}>
      <div style={{height:150*open,overflow:'hidden',borderRadius:'0 0 24px 24px',opacity:open}}>
        <NotchPanel module={landed?'shelf':'drop'} count={landed?3:0}>
          {landed?<DemoShelfBody frame={f}/>:undefined}
        </NotchPanel>
      </div>
      <div style={{position:'absolute',width:185,height:32,left:187.5,top:0,background:'#000',borderRadius:'0 0 9px 9px',opacity:1-open}}/>
    </Camera>
    {!landed&&items.map((it,i)=>{
      const p=tween(f,58+i*7,119+i*6);const x=(500+i*290)*(1-p)+fileX(i,2.65)*p;const y=790*(1-p)+(378+80*2.65)*p-Math.sin(p*Math.PI)*190;
      return <div key={it.name} style={{position:'absolute',left:x,top:y,width:150,height:150,transform:`translate(-50%,-50%) rotate(${(i-1)*12*(1-p)}deg) scale(${1-p*.1167})`,filter:'drop-shadow(0 15px 16px #53361b25)'}}><FileArtwork kind={it.kind} size={150}/><div style={{fontSize:20,textAlign:'center',marginTop:15,color:'#685646',opacity:1-p}}>{it.name}</div></div>;
    })}
    {f>175&&f<286&&<Cursor x={tween(f,176,197,1520,fileX(1)+10)} y={tween(f,176,197,840,fileY+10)} press={f>196&&f<202?1:0} opacity={(1-preview)*tween(f,175,188)}/>}
    {f>=197&&f<258&&<div style={{position:'absolute',top:888,left:876,width:168,height:46,textAlign:'center',paddingTop:10,borderRadius:9,background:'#fff9ef',border:'1px solid #c9baaa',boxShadow:'0 3px 0 #b8a794',fontSize:20,color:'#756453',opacity:tween(f,197,204)*(1-tween(f,249,258))}}>espacio</div>}
    {preview>0&&<div style={{position:'absolute',left:fileX(1)+(960-fileX(1))*preview,top:fileY+(597-fileY)*preview,width:610,height:560,background:'#fcfaf5',borderRadius:18,boxShadow:'0 45px 100px #24150950,0 0 0 1px #ffffff',overflow:'hidden',opacity:preview,transform:`translate(-50%,-50%) scale(${.25+.75*preview})`}}>
      <div style={{height:43,background:'#ebe7df',display:'flex',alignItems:'center',padding:'0 17px',fontSize:16,color:'#655a4e',borderBottom:'1px solid #d9d2c6'}}>⊗<span style={{margin:'auto'}}>Propuesta.pdf</span><span style={{fontSize:12}}>Vista rápida</span></div>
      <div style={{padding:'50px 60px'}}><div style={{fontSize:11,letterSpacing:3,color:'#a98650'}}>ALTILLO / ESTUDIO</div><div style={{fontSize:46,lineHeight:1.04,letterSpacing:-2,marginTop:20}}>Una idea.<br/>Todo su espacio.</div><div style={{height:125,marginTop:24,borderRadius:5,background:'radial-gradient(ellipse at 70% 100%,#ffd088,transparent 65%),linear-gradient(135deg,#282021,#8c6645)'}}/>{[100,95,73].map((v,i)=><div key={i} style={{height:5,background:'#dfd6c9',width:`${v}%`,marginTop:15}}/>)}</div>
    </div>}
    {pull>0&&<><div style={{position:'absolute',left:1210,top:745,width:390,height:124,borderRadius:18,border:'1px solid #aa927655',background:'#fff9ef99',opacity:tween(f,279,298),display:'flex',alignItems:'center',padding:28,gap:22}}><div style={{fontSize:40,color:'#927554'}}>↗</div><div><div style={{fontSize:23,fontWeight:500}}>Tu proyecto</div><div style={{fontSize:16,color:'#927d66',marginTop:7}}>Propuesta.pdf</div></div></div>
      <div style={{position:'absolute',left:fileX(1)+(1360-fileX(1))*pull,top:fileY+(790-fileY)*pull-Math.sin(pull*Math.PI)*80,transform:`translate(-50%,-50%) scale(${1-pull*.4})`,opacity:1-tween(f,315,328),filter:'drop-shadow(0 20px 20px #6a4e3833)'}}><FileArtwork kind="pdf" size={135}/></div>
      <Cursor x={fileX(1)+(1360-fileX(1))*pull+25} y={fileY+(790-fileY)*pull-Math.sin(pull*Math.PI)*80+30} opacity={1-tween(f,315,329)}/></>}
  </>;
};
