#!/usr/bin/env python3
"""
Generador del icono de k-cadence-trend (Opcion K). Requiere SOLO numpy.

    python3 gen_icon.py

Escribe, relativo a apps/k-cadence-trend/:
    store/icon-master-1024.png                     1024x1024 RGBA (alpha real), CON brillo
    store/store-icon-500.png                       500x500 RGB sobre gris #E6E6E6 (ficha del store)
    resources-<device>/drawables/launcher_icon.png 35/36/40/56/68 px RGBA, uno por device, PLANOS

MOTIVO (elegido por el autor el 2026-07-28, variante "A2 inclinado 18"): una BIELA vista de frente
-- aro cobalto #0070F0 con dos brazos en diagonal y un PEDAL en cada punta -- y dentro, sobre cara
azul muy oscuro #0E1A38, la misma raya AMBAR #FFC400 = LA CADENCIA MEDIA y la misma flecha BLANCA
gorda cruzandola = estas girando por encima de tu media.

EL SISTEMA DE LA FAMILIA, que es lo que hay que respetar al agregar la Opcion L y las que vengan:
    CONSTANTE (dice "esto es tendencia contra tu promedio"): cara oscura + raya ambar + flecha
              blanca cruzandola. Es lo UNICO que la prueba a ciegas de la Opcion J demostro que se
              entiende: 0 de 7 observadores identificaron el objeto, 7 de 7 llegaron a "linea de
              referencia que la flecha cruza".
    VARIABLE (dice QUE metrica es): la SILUETA EXTERIOR, en cobalto. Aro de rueda = velocidad,
              biela con pedales = cadencia, corazon = frecuencia cardiaca.
    POR QUE ahi: a 35 px no hay detalle, solo silueta. La metrica va en la silueta y NUNCA en un
              detalle interior, que a ese tamano no existe.

LOS PEDALES VAN INCLINADOS 18 GRADOS, bajando hacia la izquierda, los dos en paralelo. No es
capricho: es la inclinacion medida en el glifo de la biela que el campo NATIVO dibuja junto al
rotulo CADENCIA (12-18 grados; ver la SPEC de K 6.3), y con eso el icono y el glifo de la pantalla
pasan a ser el mismo objeto. Sin inclinar, los pedales leen como pestanas.

Por que NO un plato, que seria el motivo obvio de cadencia: en la prueba a ciegas de la Opcion J,
7 de 7 observadores leyeron los tacos del neumatico como "engranaje / tuerca / AJUSTES" -- el peor
falso amigo posible en una lista de campos de datos. Un plato es literalmente un engranaje. La
biela no tiene dientes, asi que no cae en eso.

Cada tamano se DIBUJA A SU TAMANO (nunca se reduce el master): la leccion de la Opcion A es que el
master ilustrativo reducido a 35 px queda una mancha borrosa. De ahi las simplificaciones por
tamano: los launchers van PLANOS (sin brillo) y sin filete interior abajo de 56 px.
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


# Paleta: la MISMA de la Opcion J, a proposito (son la misma familia de campos). El azul es el
# #0070F0 del proyecto, no el #0055FF que sugeria un research sobre una supuesta paleta de 64
# colores en los MIP -- eso quedo refutado midiendo el launcher de la A, validado en device real.
COBALT=(0x00,0x70,0xF0); RIM=(0x4D,0x9B,0xF8); NAVY=(0x0E,0x1A,0x38)
WHITE=(0xFF,0xFF,0xFF); AMBER=(0xFF,0xC4,0x00); STORE_BG=(230,230,230)

# --- Geometria, en fracciones del lienzo (variante A2 del 2026-07-28) ---
R_OUT=0.295; R_IN=0.230        # aro
RIM_T=0.011                    # filete interior claro (solo >= 56 px)
ARM_L=0.175; ARM_T=0.065       # brazos de biela, a 45 grados
PED_L=0.235; PED_T=0.090       # pedales
PED_TILT=0.3249                # tan(18 grados)
LINE_T=0.075                   # raya del promedio
ARROW_HW=R_IN*0.92             # ancho de la cabeza de la flecha


def render(n, ss=8, rim=True, sheen=False, gloss=0.70):
    S=n*ss
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
    u=xx/S; v=yy/S
    def disc(r,ox=0.0,oy=0.0): return ((u-0.5-ox)**2+(v-0.5-oy)**2)<=r*r
    def rect(x0,y0,x1,y1): return (u>=x0)&(u<=x1)&(v>=y0)&(v<=y1)
    def bar(x0,y0,x1,y1,t):
        dx,dy=x1-x0,y1-y0; L=max((dx*dx+dy*dy)**0.5,1e-9)
        nx,ny=-dy/L,dx/L; px,py=u-x0,v-y0
        tt=(px*dx+py*dy)/(L*L); dd=np.abs(px*nx+py*ny)
        # extremos redondeados: sin esto los brazos cortan en seco contra el aro
        return disc(t/2,x0-0.5,y0-0.5)|disc(t/2,x1-0.5,y1-0.5)|((tt>=0)&(tt<=1)&(dd<=t/2))
    def tri(p0,p1,p2):
        def side(a,b): return (b[0]-a[0])*(v-a[1])-(b[1]-a[1])*(u-a[0])
        s0,s1,s2=side(p0,p1),side(p1,p2),side(p2,p0)
        return ((s0>=0)&(s1>=0)&(s2>=0))|((s0<=0)&(s1<=0)&(s2<=0))

    # Brazos a 135 y 315 grados, saliendo del aro.
    d=ARM_L/(2**0.5); k=R_OUT*0.72
    ax,ay=0.5-k-d, 0.5-k-d
    bx,by=0.5+k+d, 0.5+k+d
    arms = bar(0.5-k,0.5-k, ax,ay, ARM_T) | bar(0.5+k,0.5+k, bx,by, ARM_T)
    # Pedales inclinados 18 grados, bajando hacia la izquierda, los dos paralelos.
    hx, hy = PED_L/2, PED_L/2*PED_TILT
    peds = bar(ax-hx,ay+hy, ax+hx,ay-hy, PED_T) | bar(bx-hx,by+hy, bx+hx,by-hy, PED_T)

    ring=disc(R_OUT)&~disc(R_IN); face=disc(R_IN)
    line_y=(0.5-R_IN)+0.667*(2*R_IN); line_hw=R_IN*0.95
    line=rect(0.5-line_hw,line_y-LINE_T/2,0.5+line_hw,line_y+LINE_T/2)&face
    tip=(0.5-R_IN)+0.02; head_h=ARROW_HW*1.05; stem_w=ARROW_HW/2.1
    base=tip+head_h
    arrow=tri((0.5,tip),(0.5-ARROW_HW/2,base),(0.5+ARROW_HW/2,base)) \
          | rect(0.5-stem_w/2,base-0.004,0.5+stem_w/2,line_y+LINE_T/2+ARROW_HW*0.40)
    # Hueco de la franja = silueta EXACTA de la flecha, sin dilatar: la raya se lee como UNA linea
    # que pasa por detras, continua. En la Opcion J se probaron las dos y la continua gano.
    line = line & ~arrow

    layers=[(arms,COBALT),(peds,COBALT),(ring,COBALT),(face,NAVY)]
    if rim: layers.append((disc(R_IN)&~disc(R_IN-RIM_T),RIM))
    layers+=[(line,AMBER),(arrow,WHITE)]

    rgb=np.zeros((S,S,3),np.float32); al=np.zeros((S,S),np.float32)
    for m,c in layers: rgb[m]=c; al[m]=1.0
    if sheen:
        # BRILLO (solo master y ficha; los launchers van planos). El aro es circular, asi que aca SI
        # sirve el arco polar de la Opcion J: banda sobre el aro arriba-izquierda con caida suave en
        # RADIO y en ANGULO, para que las puntas se difuminen y lea como reflejo y no como un rayon.
        # Mas un lavado diagonal tenue que le da volumen al conjunto.
        metal = (ring|arms|peds) & ~arrow
        r=np.sqrt((u-0.5)**2+(v-0.5)**2)
        th=np.degrees(np.arctan2(-(v-0.5), u-0.5))
        rc=R_IN+0.60*(R_OUT-R_IN); hw=0.42*(R_OUT-R_IN)
        wr=np.clip(1.0-((r-rc)/hw)**2, 0.0, 1.0)
        wa=np.clip(1.0-((th-133.0)/46.0)**2, 0.0, 1.0)
        spec=((wr*wa)**0.85)*gloss
        wash=np.clip(((0.5-u)+(0.5-v))/0.95, 0.0, 1.0)**1.6*0.24*gloss
        spec[~metal]=0.0; wash[~metal]=0.0
        for wgt,col in [(wash,(0x8F,0xC4,0xFF)),(spec,(0xFF,0xFF,0xFF))]:
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

def flatten(pm,aa,bg):
    return np.clip(pm+np.array(bg,np.float32)*(1-aa[:,:,None]),0,255).astype(np.uint8)

ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

pm,aa=render(1024, ss=2, rim=True, sheen=True)
write_png(f'{ROOT}/store/icon-master-1024.png', rgba(pm,aa), rgba=True)
print("  icon-master-1024.png   (RGBA, con brillo)")
pm,aa=render(500, ss=4, rim=True, sheen=True)
write_png(f'{ROOT}/store/store-icon-500.png', flatten(pm,aa,STORE_BG))
print("  store-icon-500.png     (opaco sobre gris E6E6E6)")

SIZES={35:['edge530','edge540','edge830','edge840'],
       36:['edge1030','edge1030bontrager','edge1030plus','edgeexplore2','edgemtb'],
       40:['edge1040'], 56:['edge550','edge850'], 68:['edge1050']}
for n,devs in SIZES.items():
    pm,aa=render(n, ss=8, rim=(n>=56), sheen=False)
    img=rgba(pm,aa)
    for d in devs:
        write_png(f'{ROOT}/resources-{d}/drawables/launcher_icon.png', img, rgba=True)
    print(f"  {n}x{n} -> {len(devs)} devices")
print("listo")
