#!/usr/bin/env python3
"""
Compone el hero de la ficha del store de k-cadence-trend. Solo numpy.

    python3 gen_hero.py        ->  hero-image-1440x720.png

Misma composicion que el hero de las Opciones A y J: degradado navy radial mas claro detras del
icono, el icono grande a la izquierda, y las capturas del campo a la derecha como tarjetas de
esquinas redondeadas con sombra suave. 1440x720 (2:1), el tamano que usaron las otras dos.

LAS FUNCIONES DE COMPOSICION SON LAS DE `apps/j-trend-arrow/store/gen_hero.py`, COPIADAS A
PROPOSITO. La regla del repo es que nada se comparte entre apps salvo por decision explicita, y esto
no la amerita: son 30 lineas y cada ficha puede evolucionar por separado. Pero copiarlas IMPORTA,
porque la primera version de este script las escribio "parecidas" y el resultado se veia mal justo
donde el autor lo noto: el borde entre la tarjeta blanca y el fondo azul.

TRES COSAS QUE LA PRIMERA VERSION HIZO MAL, y las tres estaban en el borde:

  1) LA MASCARA REDONDEADA ERA BINARIA (`(dist<=r*r).astype(float)`): alpha 0 o 1 y nada en medio. En
     un arco eso deja ESCALERA, con el salto entero de blanco a navy -- unos 240 niveles -- metido en
     un solo pixel. La de J tiene ANTIALIAS POR SUPERSAMPLING x4, que da alphas fraccionarios en el
     filo. Esta era la causa principal.
  2) EL RADIO ERA FIJO (18 px) para tarjetas de anchos distintos, asi que las esquinas no eran
     consistentes entre una tarjeta y otra. Ahora es PROPORCIONAL al ancho (4,6 %, la proporcion de la
     J: 26 px sobre 560).
  3) LA SOMBRA ERA DEMASIADO CERRADA: 14 pasadas de caja de radio 1 pegadas al borde, que leen como un
     contorno oscuro y no como sombra. La de J es UNA caja de semiancho 18, desplazada hacia abajo y
     aplicada al lienzo ANTES de pegar la tarjeta.

Y una cuarta, de fondo y no de borde: el degradado era mas oscuro y mas plano que el de la J, lo que
endurecia el contraste contra el blanco de la tarjeta. Ahora son los colores y la caida de la J.

MODOS: si hay capturas en store/cadence-trend-*.png arma el layout de dos columnas; si no, un hero con
el icono centrado (lo unico que se puede generar sin capturas, que salen del simulador con F5).
"""
import numpy as np, os, struct, zlib, glob

W,H = 1440,720
BG_IN  = np.array([0x1B,0x2C,0x47], np.float32)   # navy claro, detras del icono  (identico al de J)
BG_OUT = np.array([0x06,0x0A,0x11], np.float32)   # casi negro en los bordes
CARD_R_PCT = 0.046                                # radio de esquina = 4,6 % del ancho (J: 26/560)

def write_png(path, arr):
    h,w,_=arr.shape
    raw=b''.join(b'\x00'+arr[y].tobytes() for y in range(h))
    def chunk(t,d):
        c=struct.pack('>I',len(d))+t+d
        return c+struct.pack('>I', zlib.crc32(t+d)&0xffffffff)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))
    png+=chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    open(path,'wb').write(png)

def read_png(path, want_alpha=False):
    """Devuelve RGB, o (RGB, alpha) si want_alpha. Soporta gris, RGB y RGBA de 8 bits."""
    d=open(path,'rb').read(); i=8; idat=b''
    while i<len(d):
        ln=struct.unpack('>I',d[i:i+4])[0]; t=d[i+4:i+8]; c=d[i+8:i+8+ln]
        if t==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',c[:10])
        if t==b'IDAT': idat+=c
        i+=12+ln
    nch={0:1,2:3,4:2,6:4}[ct]; raw=zlib.decompress(idat); st=w*nch
    px=np.zeros((h,w,nch),np.uint8); prev=np.zeros(st,np.int32)
    for y in range(h):
        f=raw[y*(st+1)]
        ln=np.frombuffer(raw[y*(st+1)+1:(y+1)*(st+1)],np.uint8).astype(np.int32).copy()
        if f==1:
            for x in range(nch,st): ln[x]=(ln[x]+ln[x-nch])&255
        elif f==2: ln=(ln+prev)&255
        elif f==3:
            for x in range(st): ln[x]=(ln[x]+((ln[x-nch] if x>=nch else 0)+prev[x])//2)&255
        elif f==4:
            for x in range(st):
                a=ln[x-nch] if x>=nch else 0; b=prev[x]; cc=prev[x-nch] if x>=nch else 0
                pp=a+b-cc; pa,pb,pc=abs(pp-a),abs(pp-b),abs(pp-cc)
                ln[x]=(ln[x]+(a if (pa<=pb and pa<=pc) else (b if pb<=pc else cc)))&255
        prev=ln; px[y]=ln.reshape(w,nch)
    if nch==1: rgb=np.repeat(px,3,2); al=np.full((h,w),255,np.uint8)
    elif nch==2: rgb=np.repeat(px[:,:,:1],3,2); al=px[:,:,1]
    elif nch==3: rgb=px; al=np.full((h,w),255,np.uint8)
    else: rgb=px[:,:,:3]; al=px[:,:,3]
    return (rgb,al) if want_alpha else rgb

def boxr(a, n):
    """Escalado por AREA con sumas acumuladas (la de J). Promedia bloques de verdad, que es antialias
    limpio; tomar un pixel de cada N deja los trazos comidos."""
    a=a.astype(np.float64); Hh=a.shape[0]
    e=np.arange(n+1)*Hh/n
    c=np.concatenate([np.zeros((1,)+a.shape[1:]), a.cumsum(axis=0)], axis=0)
    i=np.clip(np.rint(e).astype(int), 0, Hh)
    return (c[i[1:]]-c[i[:-1]])/np.maximum(i[1:]-i[:-1],1).reshape((-1,)+(1,)*(a.ndim-1))

def resize(im, w, h):
    return np.clip(np.swapaxes(boxr(np.swapaxes(boxr(im, h), 0, 1), w), 0, 1), 0, 255)

def rounded(h, w, r):
    """Mascara de esquinas redondeadas CON ANTIALIAS por supersampling x4 (la de J).

    El x4 es el punto: sin el, la mascara vale 0 o 1, el arco sale en escalera y todo el salto de
    blanco a navy cae en un pixel. Con el, el filo tiene alphas intermedios y se lee como curva."""
    ss=4
    yy,xx=np.mgrid[0:h*ss, 0:w*ss].astype(np.float32)
    yy=(yy+0.5)/ss; xx=(xx+0.5)/ss
    m=np.ones((h*ss, w*ss), np.float32)
    for cy,cx in ((r,r),(r,w-r),(h-r,r),(h-r,w-r)):
        near=((yy-cy)*(1 if cy==r else -1) < 0) & ((xx-cx)*(1 if cx==r else -1) < 0)
        out=np.sqrt((yy-cy)**2+(xx-cx)**2) > r
        m[near & out]=0.0
    return m.reshape(h, ss, w, ss).mean(axis=(1,3))

def trim(a):
    """Recorta al CONTENIDO: la caja de todo lo que no es blanco de fondo.

    Estas imagenes de ficha traen su propio marco redondeado y bastante margen blanco. Ese margen,
    sobre el navy, se veria como un recuadro blanco alrededor de la tarjeta.
    NOTA sobre ese marco propio: es CASI INVISIBLE (medido: 248 contra 251 del interior) y su radio
    varia mucho de una imagen a otra (15 px en una, 59 en otra). Por eso NO se intenta hacerlo
    coincidir con la mascara: se usa un radio propio, consistente para todas las tarjetas, y el marco
    de ellas cae donde caiga, que a esa diferencia de tono no se distingue."""
    g=a.mean(2); m=g<245
    if not m.any(): return a
    ys=np.where(m.any(1))[0]; xs=np.where(m.any(0))[0]
    return a[ys.min():ys.max()+1, xs.min():xs.max()+1]

ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..'))
caps=sorted(glob.glob(f'{ROOT}/store/cadence-trend-*.png'))
two_col=len(caps)>=2

# --- fondo: degradado radial ELIPTICO, mas claro detras del icono (formula y colores de la J) ---
icon_cx = 0.245 if two_col else 0.5
yy,xx=np.mgrid[0:H,0:W].astype(np.float32)
d=np.sqrt(((xx-W*icon_cx)/(W*0.78))**2+((yy-H*0.5)/(H*0.95))**2)
t=np.clip(d,0,1)[:,:,None]**0.9
canvas=BG_IN*(1-t)+BG_OUT*t

# --- Mezcla en LUZ LINEAL (esto es MEJOR que el hero de la J, y a proposito) -------------------
# El de J mezcla directamente los valores de 8 bits, que estan codificados en gamma sRGB. Mezclar en
# gamma un blanco de 255 contra un navy de ~20 da un resultado MAS OSCURO que la mezcla fisicamente
# correcta, y eso ensucia justo el filo donde la tarjeta blanca se encuentra con el fondo azul -- que
# es donde el autor dijo "el cambio de color no esta bien". Se paga solo en los pixeles con alpha
# fraccionario, o sea los arcos de las esquinas; el interior (alpha 1) sale identico.
def to_lin(c):
    c=np.clip(c,0,255)/255.0
    return np.where(c<=0.04045, c/12.92, ((c+0.055)/1.055)**2.4)
def to_srgb(l):
    l=np.clip(l,0.0,1.0)
    return np.where(l<=0.0031308, l*12.92, 1.055*l**(1/2.4)-0.055)*255.0

def paste(img, alpha, x, y):
    h,w=alpha.shape
    reg=canvas[y:y+h, x:x+w]
    a=alpha[:,:,None]
    hard=(a>=1.0)
    mixed=to_srgb(to_lin(reg)*(1-a)+to_lin(img)*a)
    # Donde alpha es exactamente 1 se copia el original tal cual: ida y vuelta por la curva sRGB
    # redondea y moveria algun valor un nivel sin motivo.
    canvas[y:y+h, x:x+w]=np.where(hard, img, mixed)

def shadow(x, y, w, h, spread=18, strength=0.55):
    """Sombra suave DEBAJO de la tarjeta: una caja difuminada por sumas acumuladas, desplazada hacia
    abajo, aplicada al lienzo ANTES de pegar la tarjeta (la de J). Una caja ancha lee como sombra;
    muchas pasadas cortas leen como contorno oscuro, que es lo que hacia la version vieja."""
    global canvas
    m=np.zeros((H,W),np.float32)
    m[max(0,y+8):min(H,y+h+14), max(0,x-4):min(W,x+w+4)]=1.0
    k=spread
    c=np.cumsum(np.cumsum(np.pad(m,k,mode='constant'),axis=0),axis=1)
    box=(c[2*k:,2*k:]-c[:-2*k,2*k:]-c[2*k:,:-2*k]+c[:-2*k,:-2*k])/((2*k)**2)
    canvas=canvas*(1-(box[:H,:W]*strength)[:,:,None])

# --- icono ------------------------------------------------------------------------------------
irgb,ial=read_png(f'{ROOT}/store/icon-master-1024.png', want_alpha=True)
side = 430 if two_col else 460
a0=ial.astype(np.float32)/255.0
# PREMULTIPLICAR ANTES DE REDUCIR: si el color y el alpha se reducen por separado, los pixeles
# transparentes (que son negros) tinen de oscuro el filo del icono.
pm=resize(irgb.astype(np.float32)*a0[:,:,None], side, side)
al=resize(a0[:,:,None], side, side)[:,:,0]
with np.errstate(divide='ignore',invalid='ignore'):
    col=np.where(al[:,:,None]>1e-4, pm/np.maximum(al[:,:,None],1e-6), 0)
x0=int(icon_cx*W-side/2); y0=int(H/2-side/2)
paste(np.clip(col,0,255), np.clip(al,0,1), x0, y0)

# --- tarjetas ---------------------------------------------------------------------------------
if two_col:
    # CUANTAS ENTRAN: apiladas tienen que caber a lo alto y seguir teniendo cuerpo. Con estas
    # proporciones, tres quedarian en ~340 px de ancho y el lienzo medio vacio; se prueba de mas a
    # menos y se toma la primera cantidad que deje tarjetas de >= 420 px. La J llego a dos igual.
    allc=[trim(read_png(p)) for p in caps]
    def fit_width(cs):
        w=600
        for _ in range(60):
            hs=[max(1,int(c.shape[0]*w/c.shape[1])) for c in cs]
            if sum(hs)+26*(len(cs)-1) <= 0.86*H: return w
            w=int(w*0.97)
        return w
    cards=allc[:2]
    for n in range(len(allc),1,-1):
        if fit_width(allc[:n])>=420: cards=allc[:n]; break
    # AMPLIAR NUNCA, REDUCIR SI: ampliar suma grises sobre un original que ya trae antialias y el
    # texto se ve blando (medido contra el hero de la J: los grises por pixel de borde pasaban de 0,53
    # a 0,99). Reducir desde una imagen grande es antialias limpio.
    gap=26; cw=min(fit_width(cards), min(c.shape[1] for c in cards))
    hs=[max(1,int(c.shape[0]*cw/c.shape[1])) for c in cards]
    total=sum(hs)+gap*(len(cards)-1); cy=int(H/2-total/2); cx=int(0.72*W-cw/2)
    r=max(6, int(round(cw*CARD_R_PCT)))
    for c,ch_ in zip(cards,hs):
        shadow(cx, cy, cw, ch_)
        paste(resize(c.astype(np.float32), cw, ch_), rounded(ch_, cw, r), cx, cy)
        cy+=ch_+gap
    print(f"  dos columnas: {len(cards)} tarjetas de {cw} px, radio {r} px, mascara con antialias x4")
else:
    print("  hero con el ICONO CENTRADO (no hay capturas en store/cadence-trend-*.png).")

write_png(f'{ROOT}/store/hero-image-1440x720.png', np.clip(canvas,0,255).astype(np.uint8))
print("  hero-image-1440x720.png")
