# Generador de glyphs.ts a partir de Hershey Script Simplex (dominio público).
import math, json, sys
import numpy as np

# Puntos Hershey 'scripts' (y hacia abajo; x-height 0..9, base y=9, ascendente -12).
# '*' marca vértice (cúspide) que no se suaviza.
H = {
 'h': [(0,4),(2,1),(5,-4),(6,-6),(7,-9),(7,-11),(6,-12),(4,-11),(3,-9),(2,-5),(1,1),'*',(0,9),(1,6),(2,4),(4,1),(6,0),(8,0),(9,1),(9,3),(8,6),(8,8),(9,9),(10,9),(12,8),(13,7),(15,4)],
 'o': [(6,0),(4,0),(2,1),(1,2),(0,4),(0,6),(1,8),(3,9),(5,9),(7,8),(8,7),(9,5),(9,3),(8,1),(6,0),(5,1),(5,3),(6,5),(8,6),(11,6),(13,5),(14,4)],
 'l': [(0,4),(2,1),(5,-4),(6,-6),(7,-9),(7,-11),(6,-12),(4,-11),(3,-9),(2,-5),(1,2),(1,8),(2,9),(3,9),(5,8),(6,7),(8,4)],
 'a': [(9,3),(8,1),(6,0),(4,0),(2,1),(1,2),(0,4),(0,6),(1,8),(3,9),(5,9),(7,8),(8,6),'*',(10,0),'*',(9,5),(9,8),(10,9),(11,9),(13,8),(14,7),(16,4)],
 'e': [(1,7),(3,6),(4,5),(5,3),(5,1),(4,0),(3,0),(1,1),(0,3),(0,6),(1,8),(3,9),(5,9),(7,8),(8,7),(10,4)],
}
ADV = {'h':15,'o':14,'l':8,'a':16,'e':10}

def parse(lst, dx):
  pts=[]; corner=False
  for p in lst:
    if p=='*': pts[-1]=(pts[-1][0],pts[-1][1],True); continue
    pts.append((p[0]+dx,p[1],False))
  return pts

def to_pts(lst):
  pts=[]
  for p in lst:
    if p=='*': pts[-1]=(pts[-1][0],pts[-1][1],True); continue
    if pts and abs(pts[-1][0]-p[0])<1e-9 and abs(pts[-1][1]-p[1])<1e-9: continue
    pts.append((p[0],p[1],False))
  return pts

def build(word, spec):
  """spec: dict con 'gap' por letra y reemplazos opcionales."""
  x=0; out=[]
  for i,ch in enumerate(word):
    lst = spec.get('glyph',{}).get((i,ch), H[ch])
    pts=parse(lst, x)
    if out and abs(out[-1][0]-pts[0][0])<1e-6 and abs(out[-1][1]-pts[0][1])<1e-6: pts=pts[1:]
    out+=pts
    x+=ADV[ch]+spec.get('gap',{}).get(i,0)
  return out

def catmull(P, n=24, alpha=0.5):
  P=np.array(P,float)
  if len(P)<2: return P
  ext=np.vstack([2*P[0]-P[1],P,2*P[-1]-P[-2]])
  res=[]
  for i in range(1,len(ext)-2):
    p0,p1,p2,p3=ext[i-1],ext[i],ext[i+1],ext[i+2]
    t0=0; t1=t0+max(np.linalg.norm(p1-p0)**alpha,1e-6); t2=t1+max(np.linalg.norm(p2-p1)**alpha,1e-6); t3=t2+max(np.linalg.norm(p3-p2)**alpha,1e-6)
    for t in np.linspace(t1,t2,n,endpoint=False):
      a1=(t1-t)/(t1-t0)*p0+(t-t0)/(t1-t0)*p1
      a2=(t2-t)/(t2-t1)*p1+(t-t1)/(t2-t1)*p2
      a3=(t3-t)/(t3-t2)*p2+(t-t2)/(t3-t2)*p3
      b1=(t2-t)/(t2-t0)*a1+(t-t0)/(t2-t0)*a2
      b2=(t3-t)/(t3-t1)*a2+(t-t1)/(t3-t1)*a3
      res.append((t2-t)/(t2-t1)*b1+(t-t1)/(t2-t1)*b2)
  res.append(P[-1]); return np.array(res)

def resample(D, step):
  seg=np.linalg.norm(np.diff(D,axis=0),axis=1); s=np.concatenate([[0],np.cumsum(seg)])
  L=s[-1]; n=max(2,int(round(L/step))+1); u=np.linspace(0,L,n)
  return np.column_stack([np.interp(u,s,D[:,0]),np.interp(u,s,D[:,1])])

def smooth(D, sigma_pts, iters=1):
  D=D.copy()
  for _ in range(iters):
    k=int(3*sigma_pts); w=np.exp(-0.5*(np.arange(-k,k+1)/sigma_pts)**2)
    n=len(D); E=D.copy()
    for i in range(1,n-1):
      kk=min(k,i,n-1-i)  # ventana simétrica: fija extremos
      ww=w[k-kk:k+kk+1]; E[i]=(D[i-kk:i+kk+1]*ww[:,None]).sum(0)/ww.sum()
    D=E
  return D

def stroke_to_dense(pts, step=0.25, sigma=0.9):
  runs=[[]]
  for p in pts:
    runs[-1].append(p[:2])
    if p[2]: runs.append([p[:2]])
  dense=[]
  for r in runs:
    d=resample(catmull(r),step)
    d=smooth(d, sigma/step)
    dense.append(d)
  return dense

def to_bezier(runs, scale, ox, oy, step_out=0.9):
  """Cada tramo: Catmull-Rom uniforme sobre muestras equiespaciadas -> cúbicas."""
  cmds=[]; allpts=[]
  for ri,d in enumerate(runs):
    q=resample(d, step_out)
    q=(q-[ox,oy])*scale
    if ri==0: cmds.append(f"M{q[0,0]:.1f} {q[0,1]:.1f}")
    ext=np.vstack([2*q[0]-q[1],q,2*q[-1]-q[-2]])
    for i in range(1,len(ext)-2):
      p0,p1,p2,p3=ext[i-1],ext[i],ext[i+1],ext[i+2]
      c1=p1+(p2-p0)/6; c2=p2-(p3-p1)/6
      cmds.append(f"C{c1[0]:.1f} {c1[1]:.1f} {c2[0]:.1f} {c2[1]:.1f} {p2[0]:.1f} {p2[1]:.1f}")
      for t in np.linspace(0,1,12,endpoint=False)[(1 if (i>1 or ri>0) and False else 0):]:
        b=(1-t)**3*p1+3*(1-t)**2*t*c1+3*(1-t)*t**2*c2+t**3*p2; allpts.append(b)
    allpts.append(q[-1])
  return ' '.join(cmds), np.array(allpts)
