# Palabras como UN trazo continuo, compuestas con los esqueletos Hershey 'scripts'
# (dominio público) y uniones cursivas reescritas a mano.
C='*'
def sh(lst,dx,dy=0):
  return [p if p==C else (p[0]+dx,p[1]+dy) for p in lst]

H_BODY=[(0.75,4.3),(2,1),(5,-4),(6,-6),(7,-9),(7,-11),(6,-12),(4,-11),(3,-9),(2,-5),(1,1),(0,9),C,(0.35,6.6),(1.2,4.3),(2.5,2.3),(4.2,0.7),(6,0),(8,0),(9,1),(9,3),(8,6),(8,8),(9,9),(10,9),(12,8)]
# o antihoraria desde arriba; la entrada sube por el flanco izquierdo (retrazo)
O_ENTRY=[(0,6),(0,4),(1,2),(2,1),(4,0),(5.1,-0.05),C]
O_BODY=[(4,0),(2,1),(1,2),(0,4),(0,6),(1,8),(3,9),(5,9),(7,8),(8,7),(9,5),(9,3),(8,1),(6,0)]
O_LOOP=[(4.3,1.0),(4.4,2.7),(6.2,3.4),(8.3,2.6),(10.2,1.3),(12.2,0.9)]
L_BODY=[(2,1),(5,-4),(6,-6),(7,-9),(7,-11),(6,-12),(4,-11),(3,-9),(2,-5),(1,2),(1,8),(2,9),(3,9),(5,8),(6,7)]
A_ENTRY=[(0,6),(0,4),(1,2),(2,1),(4,0),(6,0),(8.7,0.6),C]
A_BODY=[(6,0),(4,0),(2,1),(1,2),(0,4),(0,6),(1,8),(3,9),(5,9),(7,8),(8,6),(8.7,0.6),C,(8.7,5),(8.8,8),(9.8,9),(11,9),(13,8),(14,7),(16,4)]
E_BODY=[(3,6),(4,5),(5,3),(5,1),(4,0),(3,0),(1,1),(0,3),(0,6),(1,8),(3,9),(5,9),(7,8),(8,7)]

def hola():
  p=[]
  p+=sh(H_BODY,0)
  ox=17; p+=sh(O_ENTRY,ox)+sh(O_BODY,ox)+sh(O_LOOP,ox)
  lx=ox+12; p+=sh(L_BODY,lx)
  ax=lx+9; p+=sh(A_ENTRY,ax)+sh(A_BODY,ax)
  return p
def hello():
  p=[]
  p+=sh(H_BODY,0)
  ex=15; p+=sh(E_BODY,ex)
  lx=ex+8; p+=sh(L_BODY,lx)
  l2=lx+8; p+=sh(L_BODY,l2)
  ox=l2+9; p+=sh(O_ENTRY,ox)+sh(O_BODY,ox)+sh([(4.3,1.0),(4.4,2.7),(6.2,3.4),(8.3,2.6),(10.4,1.0),(12.6,0.2)],ox)
  return p
WORDS={'hola':hola,'hello':hello}
