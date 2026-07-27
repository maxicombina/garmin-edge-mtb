#!/usr/bin/env python3
"""
Generador del icono de k-cadence-trend (Opcion K). Requiere SOLO numpy.

    python3 gen_icon.py

Escribe, relativo a apps/k-cadence-trend/:
    store/icon-master-1024.png                     1024x1024 RGBA (alpha real)
    store/store-icon-500.png                       500x500 RGB sobre gris #E6E6E6 (ficha del store)
    resources-<device>/drawables/launcher_icon.png 35/36/40/56/68 px RGBA, uno por device

DIFERENCIA CON EL SCRIPT DE J: aca UN SOLO script escribe los tres artefactos, porque los tres se
dibujan por codigo. En J el master venia de una imagen de modelo parcheada a mano, asi que su
gen_icon.py dibuja SOLO los launchers y gen_master.py los assets de tienda, a archivos distintos, para
que ninguno pueda pisar al otro. Aca ese riesgo no existe.

MOTIVO (elegido por el autor 2026-07-27): cuerpo de PEDAL DE PLATAFORMA visto de frente -- marco
CUADRADO redondeado cobalto #0070F0, cara azul muy oscuro; dentro, la misma raya AMBAR horizontal a
dos tercios de la altura = LA CADENCIA MEDIA, cruzada por la misma flecha BLANCA gorda = estas girando
por encima de tu media. Sin texto, sin numeros, sin dientes.

POR QUE CUADRADO, y esto es lo importante: la geometria interior es IDENTICA a la de J a proposito
-- la prueba a ciegas de J (7 observadores sin contexto) encontro que el objeto no se lee nunca
(0/7 vieron un neumatico) pero que la raya cruzada por la flecha SI (7/7 llegaron a "linea de
referencia que la flecha cruza"). Asi que eso es lo que hace de familia y se conserva. Lo que
distingue a K de J a 35 px es la SILUETA, no el detalle: cuadrado vs. redondo.

Y POR QUE NO UN PLATO, que seria el motivo obvio de cadencia: en esa misma prueba, 7 de 7
observadores leyeron los tacos del neumatico de J como "engranaje / tuerca / AJUSTES" -- el peor falso
amigo posible en una lista de campos de datos. Un plato es literalmente un engranaje, asi que habria
resucitado el problema que le costo los tacos a J. Un cuadrado no puede leerse como engranaje.

Honestidad sobre lo que comunica: el cuadrado NO grita "pedal". Su trabajo es gritar "no soy la J".
Que el objeto no se identifique ya lo sabemos de la prueba a ciegas; lo que el icono tiene que hacer
es ser reconocible como parte de la familia y distinguible de su hermana en la lista del device.

Cada tamano se DIBUJA A SU TAMANO (nunca se reduce el master): la leccion de la Opcion A es que el
master ilustrativo reducido a 35 px queda una mancha borrosa. De ahi las simplificaciones por tamano:
los launchers van planos (sin brillo), sin filete interior abajo de 56 px, y con la punta de la flecha
DENTRO de la cara (asomando por fuera del marco solo en el master, donde se ve grande).
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


# Paleta: la MISMA de J, a proposito (son la misma familia de campos). El azul es el #0070F0 del
# proyecto, no el #0055FF que sugeria un research sobre una supuesta paleta de 64 colores en los MIP
# -- eso quedo refutado midiendo el launcher de la A, validado en device real: 282 colores.
COBALT=(0x00,0x70,0xF0); RIM=(0x4D,0x9B,0xF8); NAVY=(0x0E,0x1A,0x38)
WHITE=(0xFF,0xFF,0xFF); AMBER=(0xFF,0xC4,0x00); STORE_BG=(230,230,230)

# --- geometria, en fracciones del lienzo ---
# Los semi-anchos del marco replican los radios de J (0.4375 / 0.35) para que las dos apps tengan el
# mismo peso visual en la lista; lo unico distinto es que aca son cuadrados redondeados.
OUT_H=0.4375; IN_H=0.35
CORNER_OUT=0.115; CORNER_IN=0.085
RIM_T=0.0117
# Raya de la media y flecha: IDENTICAS a las de J (misma lectura, misma familia).
LINE_T=1/12; LINE_HW=1/3
LINE_Y=(0.5-IN_H)+0.667*(2*IN_H)
HEAD_W=IN_H; STEM_W=IN_H/2
TIP_Y=0.5-OUT_H-0.039
TAIL_Y=LINE_Y+LINE_T/2+0.13

def render(n, ss=8, rim=True, sheen=False, tip_out=True, gloss=0.70):
    S=n*ss
    yy,xx=np.mgrid[0:S,0:S].astype(np.float32)
    u=xx/S; v=yy/S                                  # coords normalizadas 0..1
    def rect(x0,y0,x1,y1): return (u>=x0)&(u<=x1)&(v>=y0)&(v<=y1)
    def roundrect(half,r):
        """Cuadrado centrado de semi-lado `half` con esquinas de radio `r`.
        Truco de SDF: un punto esta dentro si su distancia al rectangulo ENCOGIDO por r es <= r.
        Mas barato y mas exacto que unir 4 discos y 2 rectangulos, y con antialias parejo."""
        x0,x1=0.5-half,0.5+half; y0,y1=0.5-half,0.5+half
        cx=np.clip(u, x0+r, x1-r); cy=np.clip(v, y0+r, y1-r)
        return ((u-cx)**2+(v-cy)**2) <= r*r
    def tri(p0,p1,p2):
        def side(a,b): return (b[0]-a[0])*(v-a[1])-(b[1]-a[1])*(u-a[0])
        s0,s1,s2=side(p0,p1),side(p1,p2),side(p2,p0)
        return ((s0>=0)&(s1>=0)&(s2>=0))|((s0<=0)&(s1<=0)&(s2<=0))

    tip_y = TIP_Y if tip_out else (0.5-IN_H)+0.018
    head_h = 0.55*(TAIL_Y-tip_y); base_y = tip_y+head_h

    outer=roundrect(OUT_H, CORNER_OUT)
    face=roundrect(IN_H, CORNER_IN)
    frame=outer&~face
    arrow=tri((0.5,tip_y),(0.5-HEAD_W/2,base_y),(0.5+HEAD_W/2,base_y))|rect(0.5-STEM_W/2,base_y-0.004,0.5+STEM_W/2,TAIL_Y)
    line=rect(0.5-LINE_HW,LINE_Y-LINE_T/2,0.5+LINE_HW,LINE_Y+LINE_T/2)&face
    # Hueco de la franja = silueta EXACTA de la flecha, sin dilatar: la raya se lee como UNA linea
    # que pasa por detras, continua. En J se probaron las dos y la continua gano.
    line&=~arrow

    layers=[(frame,COBALT),(face,NAVY)]
    if rim: layers.append((face&~roundrect(IN_H-RIM_T, CORNER_IN),RIM))
    layers+=[(line,AMBER),(arrow,WHITE)]

    rgb=np.zeros((S,S,3),np.float32); al=np.zeros((S,S),np.float32)
    for m,c in layers: rgb[m]=c; al[m]=1.0
    if sheen:
        # VOLUMEN (solo master/store; los launchers van planos con sheen=False). En J el brillo era un
        # arco polar sobre el aro; un marco cuadrado no tiene "radio", asi que aca es un degradado
        # DIAGONAL arriba-izquierda, recortado al marco.
        #
        # UNA SOLA RAMPA, A PROPOSITO. El primer intento sumaba una banda especular encima
        # (gaussiana sobre la diagonal) y a 500 px se veia como una CUNA de borde duro en la esquina
        # -- exactamente el "rayon" contra el que advierte el comentario del script de J, que ya
        # habia pisado ese mismo pozo con su version de arco. En una silueta cuadrada la banda no
        # tiene una curva a la que agarrarse, asi que no hay forma de suavizarla: se saca. La rampa
        # sola da el volumen y no inventa un reflejo que no puede existir en un marco plano.
        diag=np.clip(((0.5-u)+(0.5-v))/0.95, 0.0, 1.0)
        base=(diag**1.5)*0.42*gloss
        base[~(frame&~arrow)]=0.0
        m=base[:,:,None]
        rgb=rgb*(1-m)+np.array((0x9F,0xCD,0xFF),np.float32)*m
    pm=(rgb*al[:,:,None]).reshape(n,ss,n,ss,3).mean(axis=(1,3))
    aa=al.reshape(n,ss,n,ss).mean(axis=(1,3))
    return pm,aa

def rgba(pm,aa):
    a=np.clip(aa*255,0,255)
    with np.errstate(divide='ignore',invalid='ignore'):
        c=np.where(aa[:,:,None]>0, pm/np.maximum(aa[:,:,None],1e-6), 0)
    return np.dstack([np.clip(c,0,255).astype(np.uint8), a.astype(np.uint8)])

def flatten(pm,aa,bg): return np.clip(pm+np.array(bg,np.float32)*(1-aa[:,:,None]),0,255).astype(np.uint8)

ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

# --- Assets de tienda: master con volumen. La punta de la flecha va DENTRO de la cara, igual que en
#     el master publicado de J: `tip_out=True` la manda casi al borde del lienzo y queda incomoda,
#     apretada contra el canto. (En J el parametro existe pero su master real tampoco lo usa: salio
#     de gen_master.py, no de este render. Verificado mirando el PNG publicado.) ---
pm,aa=render(1024, ss=2, rim=True, sheen=True, tip_out=False)
write_png(f'{ROOT}/store/icon-master-1024.png', rgba(pm,aa), rgba=True)
print("  icon-master-1024.png")
pm,aa=render(500, ss=4, rim=True, sheen=True, tip_out=False)
write_png(f'{ROOT}/store/store-icon-500.png', flatten(pm,aa,STORE_BG))
print("  store-icon-500.png  (opaco sobre gris E6E6E6)")

# --- Launchers: dibujados a su tamano, PLANOS; sin filete interior abajo de 56; punta adentro ---
SIZES={35:['edge530','edge540','edge830','edge840'],
       36:['edge1030','edge1030bontrager','edge1030plus','edgeexplore2','edgemtb'],
       40:['edge1040'], 56:['edge550','edge850'], 68:['edge1050']}
for n,devs in SIZES.items():
    pm,aa=render(n, ss=8, rim=(n>=56), sheen=False, tip_out=False)
    img=rgba(pm,aa)
    for d in devs:
        write_png(f'{ROOT}/resources-{d}/drawables/launcher_icon.png', img, rgba=True)
    print(f"  {n}x{n} -> {len(devs)} devices")
print("listo")
