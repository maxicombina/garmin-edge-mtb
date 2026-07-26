#!/usr/bin/env python3
"""
Generador del icono de j-trend-arrow (Opcion J). Requiere SOLO numpy.

    python3 gen_icon.py

Escribe, relativo a apps/j-trend-arrow/:
    store/icon-master-1024.png                     1024x1024 RGBA (alpha real)
    store/store-icon-500.png                       500x500 RGB sobre gris #E6E6E6 (ficha del store)
    resources-<device>/drawables/launcher_icon.png 35/36/40/56/68 px RGBA, uno por device

Motivo (elegido por el autor 2026-07-25, variante "C"): neumatico MTB de frente -- aro cobalto
#0070F0 con seis tacos redondeados, cara azul muy oscuro; dentro, una raya AMBAR horizontal a dos
tercios de la altura = EL PROMEDIO de la actividad, y una flecha BLANCA gorda que la CRUZA = el
valor actual esta por encima de tu media. Sin texto, sin numeros, sin aguja.

Por que se dibuja con codigo y no con un modelo de imagen: el icono es geometria exacta
(proporciones de flecha, grosor de la raya, forma de los tacos) y tres intentos con gpt-image-2 no
acertaron ninguna de las proporciones pedidas -- ver apps/j-trend-arrow/SPEC.md 3.3.

Cada tamano se DIBUJA A SU TAMANO (nunca se reduce el master): la leccion de la Opcion A es que el
master ilustrativo reducido a 35 px queda una mancha borrosa. De ahi las simplificaciones por
tamano: los launchers van planos (sin brillo), sin filete interior abajo de 56 px, y con la punta de
la flecha DENTRO de la cara (asomando por fuera del aro solo en el master, donde se ve grande).
"""
import numpy as np, os, struct, zlib

def write_png(path, arr, rgba=False):
    h, w, _ = arr.shape
    raw = b''.join(b'\x00' + arr[y].tobytes() for y in range(h))
    def chunk(t, data):
        c = struct.pack('>I', len(data)) + t + data
        return c + struct.pack('>I', zlib.crc32(t+data) & 0xffffffff)
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6 if rgba else 2, 0,0,0))
    png += chunk(b'IDAT', zlib.compress(raw, 9))
    png += chunk(b'IEND', b'')
    open(path,'wb').write(png)


COBALT=(0x00,0x70,0xF0); RIM=(0x4D,0x9B,0xF8); NAVY=(0x0E,0x1A,0x38)
WHITE=(0xFF,0xFF,0xFF); AMBER=(0xFF,0xC4,0x00); STORE_BG=(230,230,230)

# --- geometria, en fracciones del lienzo (identica a la variante C validada a ojo) ---
R_OUT=0.4375; R_IN=0.35
KNOB_W=0.1797; KNOB_H=0.1016; KNOB_OUT=0.0586
RIM_T=0.0117
LINE_T=1/12; LINE_HW=1/3
LINE_Y=(0.5-R_IN)+0.667*(2*R_IN)
HEAD_W=R_IN; STEM_W=R_IN/2
TIP_Y=0.5-R_OUT-0.039
TAIL_Y=LINE_Y+LINE_T/2+0.13
HEAD_H=0.55*(TAIL_Y-TIP_Y); BASE_Y=TIP_Y+HEAD_H

def render(n, ss=8, rim=True, sheen=False, tip_out=True, gloss=0.70, nubs_mode='big'):
    S=n*ss
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
    u=xx/S; v=yy/S                                  # coords normalizadas 0..1
    def disc(r,ox=0.0,oy=0.0): return ((u-0.5-ox)**2+(v-0.5-oy)**2)<=r*r
    def rect(x0,y0,x1,y1): return (u>=x0)&(u<=x1)&(v>=y0)&(v<=y1)
    def capsule(x0,y0,x1,y1,r):
        m=disc(r,x0-0.5,y0-0.5)|disc(r,x1-0.5,y1-0.5)
        dx,dy=x1-x0,y1-y0; L=max((dx*dx+dy*dy)**.5,1e-9)
        nx,ny=-dy/L,dx/L; px,py=u-x0,v-y0
        t=(px*dx+py*dy)/(L*L); d=np.abs(px*nx+py*ny)
        return m|((t>=0)&(t<=1)&(d<=r))
    def tri(p0,p1,p2):
        def side(a,b): return (b[0]-a[0])*(v-a[1])-(b[1]-a[1])*(u-a[0])
        s0,s1,s2=side(p0,p1),side(p1,p2),side(p2,p0)
        return ((s0>=0)&(s1>=0)&(s2>=0))|((s0<=0)&(s1<=0)&(s2<=0))
    def dilate(m,px):
        o=m.copy(); r=max(int(px*S),1)
        for dx,dy in [(r,0),(-r,0),(0,r),(0,-r),(r,r),(-r,-r),(r,-r),(-r,r)]: o|=np.roll(np.roll(m,dy,0),dx,1)
        return o

    tip_y = TIP_Y if tip_out else (0.5-R_IN)+0.018
    head_h = 0.55*(TAIL_Y-tip_y); base_y = tip_y+head_h
    knobs=np.zeros((S,S),bool)
    for a in ([] if nubs_mode=='none' else range(0,360,60)):
        t=np.radians(a); rr=R_OUT+KNOB_OUT-KNOB_H/2
        ex,ey=np.cos(t)*rr, -np.sin(t)*rr
        tx,ty=-np.sin(t)*(KNOB_W/2-KNOB_H/2), -np.cos(t)*(KNOB_W/2-KNOB_H/2)
        knobs|=capsule(0.5+ex-tx,0.5+ey-ty,0.5+ex+tx,0.5+ey+ty,KNOB_H/2)
    ring=disc(R_OUT)&~disc(R_IN); face=disc(R_IN)
    arrow=tri((0.5,tip_y),(0.5-HEAD_W/2,base_y),(0.5+HEAD_W/2,base_y))|rect(0.5-STEM_W/2,base_y-0.004,0.5+STEM_W/2,TAIL_Y)
    line=rect(0.5-LINE_HW,LINE_Y-LINE_T/2,0.5+LINE_HW,LINE_Y+LINE_T/2)&face
    # Hueco de la franja = silueta EXACTA de la flecha, sin dilatar: la raya se lee como UNA
    # linea que pasa por detras. Igual criterio que gen_master.py (SPEC 3.3).
    line&=~arrow

    layers=[(knobs,COBALT),(ring,COBALT),(face,NAVY)]
    if rim: layers.append((disc(R_IN)&~disc(R_IN-RIM_T),RIM))
    # el brillo NO es una capa: es un degradado que se mezcla sobre el azul del aro (ver abajo)
    layers+= [(line,AMBER),(arrow,WHITE)]

    rgb=np.zeros((S,S,3),np.float32); al=np.zeros((S,S),np.float32)
    for m,c in layers: rgb[m]=c; al[m]=1.0
    if sheen:
        # BRILLO ESPECULAR (solo master/store; los launchers van planos con sheen=False).
        # Arco sobre el aro, arriba-izquierda, con caida suave EN RADIO y EN ANGULO -> las puntas
        # se difuminan y lee como reflejo, no como un rayon (el primer intento era un arco de
        # borde duro y parecia un aranazo). Se mezcla hacia BLANCO sobre el azul del aro/tacos.
        r=np.sqrt((u-0.5)**2+(v-0.5)**2)
        th=np.degrees(np.arctan2(-(v-0.5), u-0.5))
        rc=R_IN+0.60*(R_OUT-R_IN); hw=0.34*(R_OUT-R_IN)     # centro y semiancho de la banda
        wr=np.clip(1.0-((r-rc)/hw)**2, 0.0, 1.0)
        wa=np.clip(1.0-((th-133.0)/44.0)**2, 0.0, 1.0)      # centrado en 133 grados, +/-44
        w=((wr*wa)**0.85)*gloss
        w[~((knobs|ring)&~arrow)]=0.0
        # un lavado tenue adicional arriba-izquierda para dar volumen al aro entero
        base=np.clip(((0.5-u)+(0.5-v))/0.95, 0.0, 1.0)**1.7*0.22*gloss
        base[~((knobs|ring)&~arrow)]=0.0
        for wgt, col in [(base,(0x8F,0xC4,0xFF)), (w,(0xFF,0xFF,0xFF))]:
            m=wgt[:,:,None]
            rgb=rgb*(1-m)+np.array(col,np.float32)*m
    pm=(rgb*al[:,:,None]).reshape(n,ss,n,ss,3).mean(axis=(1,3))
    aa=al.reshape(n,ss,n,ss).mean(axis=(1,3))
    return pm,aa

def rgba(pm,aa):
    a=np.clip(aa*255,0,255)
    with np.errstate(divide='ignore',invalid='ignore'):
        c=np.where(aa[:,:,None]>0, pm/np.maximum(aa[:,:,None],1e-6), 0)
    return np.dstack([np.clip(c,0,255).astype(np.uint8), a.astype(np.uint8)])

def flatten(pm,aa,bg): return np.clip(pm+np.array(bg,np.float32)*(1-aa[:,:,None]),0,255).astype(np.uint8)

ROOT='/Users/maxicombina/src/garmin-edge-mtb/apps/j-trend-arrow'
# Los assets de tienda (master 1024 + icono 500) NO salen de aca: los deriva gen_master.py
# desde 3-flecha-arreglada.png. Este script dibuja SOLO los launchers, para no pisarlos nunca.
# Launchers: dibujados a su tamano, PLANOS (sin brillo); sin filete interior abajo de 56
SIZES={35:['edge530','edge540','edge830','edge840'],
       36:['edge1030','edge1030bontrager','edge1030plus','edgeexplore2','edgemtb'],
       40:['edge1040'], 56:['edge550','edge850'], 68:['edge1050']}
for n,devs in SIZES.items():
    # nubs_mode='none': aro liso, igual que el master (ver SPEC 3.3 -- los tacos leían
    # como "ajustes" en la prueba a ciegas y no como neumático).
    pm,aa=render(n, ss=8, rim=(n>=56), sheen=False, tip_out=False, nubs_mode='none')
    img=rgba(pm,aa)
    for d in devs:
        write_png(f'{ROOT}/resources-{d}/drawables/launcher_icon.png', img, rgba=True)
    print(f"  {n}x{n} -> {len(devs)} devices")
print("listo")
