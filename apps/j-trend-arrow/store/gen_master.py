#!/usr/bin/env python3
"""
Deriva los assets de tienda de j-trend-arrow (Opcion J) desde `3-flecha-arreglada.png`. Solo numpy.

    python3 gen_master.py

Escribe:  icon-master-1024.png   1024x1024 RGBA, alpha REAL (de aca sale cualquier derivado)
          store-icon-500.png     500x500 RGB opaco sobre gris #E6E6E6 (ficha del store)

FUENTE. `3-flecha-arreglada.png` (1254x1254, fondo magenta plano) es el unico insumo y se versiona
al lado de este script. Es una imagen de gpt-image-2 (ver ICON_PROMPT.md) a la que ya se le
transplanto la flecha con la geometria de gen_icon.py y se le redibujo la franja ambar con
antialias limpio; ese trabajo esta BAKEADO en el PNG, este script ya no lo rehace.

QUE HACE ESTE SCRIPT
  1. Recorta los TACOS: alpha 0 fuera del circulo exterior del aro. El aro se detecta como el mayor
     radio cuyo perimetro esta cubierto >95% (mas afuera solo hay lobulos, en pocos angulos).
     Motivo: en la prueba a ciegas 0 de 7 observadores leyeron "neumatico" y 7 de 7 leyeron
     "ajustes/engranaje" -> los lobulos eran costo puro (SPEC 3.3). Poner DROP_KNOBS=False los deja.
  2. Saca el magenta con TOLERANCIA y despill. No se compara por igualdad: desde 2026-05-19 toda
     imagen de OpenAI lleva SynthID, que mueve los pixeles unos puntos, y ademas los bordes tienen
     antialias. El despill des-compone color = fg*alpha + magenta*(1-alpha) para que no quede
     fleco rosa en el borde semitransparente.
  3. Recentra el sujeto y lo escala al 88% del lienzo; escribe 1024 RGBA y 500 sobre gris.

Los 13 launcher_icon.png NO salen de aca: los dibuja gen_icon.py a cada tamano, planos y con la
MISMA geometria de flecha.
"""
import numpy as np, struct, zlib

SRC='3-flecha-arreglada.png'
OUT_MASTER='icon-master-1024.png'
OUT_500='store-icon-500.png'
DROP_KNOBS=False         # decision del autor 2026-07-26: el MASTER y el icono de tienda van
                         # CON los tacos redondeados (le gustan, y a tamano grande se lee el
                         # neumatico). Los 13 LAUNCHERS, en cambio, van LISOS: a 35 px los
                         # tacos eran lo que hacia leer "ajustes" (SPEC 3.3). True los recorta.
STORE_BG=(230,230,230)   # mismo gris que la ficha de la Opcion A
FILL=0.88                # cuanto del lienzo ocupa el sujeto

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


def read_png(path):
    import zlib, struct
    import numpy as np
    d = open(path,'rb').read()
    assert d[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, pal, trns = 8, b'', None, None
    while pos < len(d):
        ln = struct.unpack('>I', d[pos:pos+4])[0]; typ = d[pos+4:pos+8]; data = d[pos+8:pos+8+ln]
        if typ == b'IHDR':
            w, h, bd, ct, comp, filt, inter = struct.unpack('>IIBBBBB', data)
        elif typ == b'IDAT': idat += data
        elif typ == b'PLTE': pal = np.frombuffer(data, np.uint8).reshape(-1,3)
        elif typ == b'tRNS': trns = np.frombuffer(data, np.uint8)
        elif typ == b'IEND': break
        pos += 12 + ln
    assert bd == 8 and inter == 0, (bd, inter)
    nch = {0:1, 2:3, 3:1, 4:2, 6:4}[ct]
    raw = zlib.decompress(idat)
    stride = w*nch
    out = np.zeros((h, stride), np.uint8); prev = np.zeros(stride, np.uint8)
    p = 0
    for y in range(h):
        f = raw[p]; p += 1
        line = np.frombuffer(raw[p:p+stride], np.uint8).astype(np.int32).copy(); p += stride
        if f == 1:
            for i in range(nch, stride): line[i] = (line[i] + line[i-nch]) & 255
        elif f == 2:
            line = (line + prev) & 255
        elif f == 3:
            for i in range(stride):
                a = line[i-nch] if i >= nch else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = int(line[i-nch]) if i >= nch else 0
                b = int(prev[i]); c = int(prev[i-nch]) if i >= nch else 0
                pp = a+b-c; pa, pb, pc = abs(pp-a), abs(pp-b), abs(pp-c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        line = line.astype(np.uint8); out[y] = line; prev = line
    arr = out.reshape(h, w, nch)
    if ct == 3:
        rgb = pal[arr[:,:,0]]
        al = (trns[arr[:,:,0]] if trns is not None else np.full((h,w),255,np.uint8))
        return np.dstack([rgb, al.reshape(h,w,1)]).astype(np.uint8)
    if ct == 2: return np.dstack([arr, np.full((h,w,1),255,np.uint8)])
    if ct == 6: return arr
    if ct == 0: return np.dstack([arr]*3 + [np.full((h,w,1),255,np.uint8)])
    if ct == 4: return np.dstack([arr[:,:,:1]]*3 + [arr[:,:,1:]])


a=read_png(SRC)[:,:,:3].astype(np.float32)
h,w,_=a.shape
R,G,B=a[:,:,0],a[:,:,1],a[:,:,2]
mness=(R+B)/2.0-G                      # "magenta-idad": ~255 en el fondo, <=60 en el dibujo
al=np.clip((140.0-mness)/80.0, 0.0, 1.0)

if DROP_KNOBS:
    navy=(R<70)&(G<70)&(B<130)
    ys,xs=np.where(navy)
    cx,cy=(xs.min()+xs.max())/2.0,(ys.min()+ys.max())/2.0
    rf=((xs.max()-xs.min()+1)+(ys.max()-ys.min()+1))/4.0
    yy,xx=np.mgrid[0:h,0:w].astype(np.float32)
    rr=np.sqrt((xx-cx)**2+(yy-cy)**2)
    ring_r=rf
    for rq in np.arange(rf, rf*1.6, 2.0):
        sel=(rr>=rq-1.5)&(rr<=rq+1.5)
        if sel.sum()<50: break
        if (al[sel]>0.5).mean()>0.95: ring_r=rq
    al=np.where(rr<=ring_r, al, np.clip(ring_r+1.2-rr,0,1)*al)
    print(f"tacos recortados en r={ring_r:.0f} (cara r={rf:.0f})")

bgc=np.median(a[al<0.02].reshape(-1,3),axis=0)
print(f"fondo medido {bgc} | pixeles de borde parcial {int(((al>0.02)&(al<0.98)).sum())}")
with np.errstate(divide='ignore',invalid='ignore'):
    fg=(a-bgc*(1-al)[:,:,None])/np.maximum(al,1e-3)[:,:,None]
fg=np.where(al[:,:,None]>0.02, np.clip(fg,0,255), 0)

ys,xs=np.where(al>0.5)
ccx,ccy=(xs.min()+xs.max())/2.0,(ys.min()+ys.max())/2.0
side=max(xs.max()-xs.min()+1, ys.max()-ys.min()+1)/FILL
x0,y0=ccx-side/2, ccy-side/2

def sample(n):
    """remuestreo por promedio de area del recorte [x0,y0,side] a n x n, premultiplicando"""
    oc=np.zeros((n,n,3),np.float32); oa=np.zeros((n,n),np.float32)
    ex=np.linspace(x0,x0+side,n+1); ey=np.linspace(y0,y0+side,n+1)
    pm=fg*al[:,:,None]
    for j in range(n):
        j0,j1=int(round(ey[j])),int(round(ey[j+1])); j0c,j1c=max(j0,0),min(j1,h)
        for i in range(n):
            i0,i1=int(round(ex[i])),int(round(ex[i+1])); i0c,i1c=max(i0,0),min(i1,w)
            if i1c<=i0c or j1c<=j0c: continue
            npx=(j1-j0)*(i1-i0)
            oc[j,i]=pm[j0c:j1c,i0c:i1c].reshape(-1,3).sum(axis=0)/npx
            oa[j,i]=al[j0c:j1c,i0c:i1c].sum()/npx
    return oc,oa

pm,aa=sample(1024)
with np.errstate(divide='ignore',invalid='ignore'):
    col=np.where(aa[:,:,None]>0.004, pm/np.maximum(aa,1e-4)[:,:,None], 0)
write_png(OUT_MASTER, np.dstack([np.clip(col,0,255).astype(np.uint8),
                                 (np.clip(aa,0,1)*255).astype(np.uint8)]), rgba=True)
pm5,aa5=sample(500)
with np.errstate(divide='ignore',invalid='ignore'):
    c5=np.where(aa5[:,:,None]>0.004, pm5/np.maximum(aa5,1e-4)[:,:,None], 0)
write_png(OUT_500, np.clip(np.clip(c5,0,255)*aa5[:,:,None]+np.array(STORE_BG,np.float32)*(1-aa5[:,:,None]),0,255).astype(np.uint8))
print(f"escritos {OUT_MASTER} y {OUT_500}")
