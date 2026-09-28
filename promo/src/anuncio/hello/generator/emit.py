import sys, json; import os; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
import numpy as np
from gen import *
import words
SCALE=18.5
PAD=3.0  # unidades Hershey de margen (trazo + halo)
def speed_lut(poly, corners_s, N=121):
  seg=np.linalg.norm(np.diff(poly,axis=0),axis=1); s=np.concatenate([[0],np.cumsum(seg)]); L=s[-1]
  # curvatura por ángulo de giro sobre ventana
  n=len(poly); k=np.zeros(n); w=3
  for i in range(n):
    a=poly[max(0,i-w)]; b=poly[i]; c=poly[min(n-1,i+w)]
    v1=b-a; v2=c-b; 
    if np.linalg.norm(v1)<1e-6 or np.linalg.norm(v2)<1e-6: continue
    ang=abs(math.atan2(v1[0]*v2[1]-v1[1]*v2[0], v1@v2)); ds=(np.linalg.norm(v1)+np.linalg.norm(v2))/2
    k[i]=ang/ds
  k=np.convolve(k,np.ones(9)/9,mode='same')
  R=L/40  # escala de radio relativa
  v=1/(1+1.1*k*R)
  for cs in corners_s:  # desaceleración en cúspides
    v*=1-0.75*np.exp(-0.5*((s-cs)/(L*0.012))**2)
  env=np.minimum(1, 0.3+0.7*np.clip(s/(L*0.07),0,1)**0.8)  # arranque suave
  env*=np.minimum(1, 0.55+0.45*np.clip((L-s)/(L*0.05),0,1))
  v=np.maximum(v*env,0.08)
  dt=seg/((v[:-1]+v[1:])/2); t=np.concatenate([[0],np.cumsum(dt)]); t/=t[-1]
  u=np.linspace(0,1,N); frac=np.interp(u,t,s/L)
  return [round(float(x),4) for x in frac], float(L)
out={}
for w,fn in words.WORDS.items():
  pts=to_pts(fn())
  runs=stroke_to_dense(pts)
  allp=np.vstack(runs)
  minx,miny=allp.min(0)-PAD; maxx,maxy=allp.max(0)+PAD
  d,poly=to_bezier(runs,SCALE,minx,miny)
  # posición de cúspides en longitud de arco
  seg=np.linalg.norm(np.diff(poly,axis=0),axis=1); s=np.concatenate([[0],np.cumsum(seg)])
  cs=[]
  for p in pts:
    if p[2]:
      q=(np.array(p[:2])-[minx,miny])*SCALE; cs.append(float(s[np.argmin(np.linalg.norm(poly-q,axis=1))]))
  lut,L=speed_lut(poly,cs)
  out[w]={'width':round(float((maxx-minx)*SCALE),1),'height':round(float((maxy-miny)*SCALE),1),
          'baseline':round(float((9-miny)*SCALE),1),'xHeight':round(float(9*SCALE),1),
          'strokes':[{'d':d,'length':round(L,1),'timing':lut}]}
  print(w,out[w]['width'],out[w]['height'],L,len(d),file=sys.stderr)
hdr='''// GENERADO por generator/emit.py (pip install Hershey-Fonts numpy) — no editar a mano.
// Fuente: Hershey Script Simplex ("scripts") de A. V. Hershey (U.S. National
// Bureau of Standards, 1967), dominio público; leído vía el paquete PyPI
// Hershey-Fonts. Esqueletos de letra redibujados y unidos a mano en un único
// trazo cursivo por palabra; suavizado Catmull-Rom centrípeto + gaussiano y
// convertido a cúbicas Bézier. Lettering original: no deriva del «hello» de Apple.
//
// Unidades: px del viewBox (0 0 width height). `timing` son 121 muestras de la
// fracción de longitud dibujada en tiempo uniforme (0..1): la mano frena en
// curvas cerradas y cúspides y corre en los trazos largos.
'''
ts=hdr+'''
export type HelloStroke = {d: string; length: number; timing: number[]};
export type HelloGlyph = {
  width: number;
  height: number;
  baseline: number;
  xHeight: number;
  strokes: HelloStroke[];
};

export const HELLO_GLYPHS = '''+json.dumps(out,indent=1)+''' as const satisfies Record<string, HelloGlyph>;

export type HelloWord = keyof typeof HELLO_GLYPHS;
'''
open(sys.argv[1],'w').write(ts)
