#!/usr/bin/env python3
"""
Compone el hero de la ficha del store de j-trend-arrow. Solo numpy.

    python3 gen_hero.py        ->  hero-image-1440x720.png

Misma composicion que el hero de la Opcion A: el icono grande a la izquierda sobre un degradado
navy radial (mas claro justo detras del icono), y a la derecha CAPTURAS REALES del campo como
tarjetas con esquinas redondeadas y sombra suave. Se eligieron `trend-arrow-3` (pantalla completa,
actual + promedio) y `trend-arrow-5` (modo inline en tema oscuro) porque entre las dos cuentan lo
que hace la app de un vistazo: el numero grande con su flecha, y que compara contra tu media.

Las capturas se RECORTAN antes de montarlas (funcion trim): traen un margen uniforme alrededor y
el de la captura oscura, blanco sobre el navy del hero, parecia un error de montaje.

1440x720 (2:1) es el tamano que uso la Opcion A. Si el portal pidiera otro, cambiar W/H: todo el
layout esta en proporciones del lienzo.
"""
import numpy as np, struct, zlib

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

W, H = 1440, 720                      # 2:1, misma proporcion que el hero de la A
BG_IN  = np.array([0x1B,0x2C,0x47], np.float32)   # navy claro, detras del icono
BG_OUT = np.array([0x06,0x0A,0x11], np.float32)   # casi negro en los bordes
S = '.'   # se ejecuta desde apps/j-trend-arrow/store/

def boxr(a, n):
    a = a.astype(np.float64); Hh = a.shape[0]
    e = np.arange(n+1)*Hh/n
    c = np.concatenate([np.zeros((1,)+a.shape[1:]), a.cumsum(axis=0)], axis=0)
    i = np.clip(np.rint(e).astype(int), 0, Hh)
    return (c[i[1:]]-c[i[:-1]])/np.maximum(i[1:]-i[:-1],1).reshape((-1,)+(1,)*(a.ndim-1))

def resize(im, w, h):
    o = np.swapaxes(boxr(np.swapaxes(boxr(im, h), 0, 1), w), 0, 1)
    return np.clip(o, 0, 255)

def rounded(h, w, r):
    """mascara de esquinas redondeadas con antialias por supersampling"""
    ss = 4
    yy, xx = np.mgrid[0:h*ss, 0:w*ss].astype(np.float32)
    yy = (yy+0.5)/ss; xx = (xx+0.5)/ss
    m = np.ones((h*ss, w*ss), np.float32)
    for cy, cx in ((r, r), (r, w-r), (h-r, r), (h-r, w-r)):
        near = ((yy-cy)*(1 if cy==r else -1) < 0) & ((xx-cx)*(1 if cx==r else -1) < 0)
        out = np.sqrt((yy-cy)**2 + (xx-cx)**2) > r
        m[near & out] = 0.0
    return m.reshape(h, ss, w, ss).mean(axis=(1,3))

# --- fondo: degradado radial centrado en el icono ---
yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
cx, cy = W*0.245, H*0.5
d = np.sqrt(((xx-cx)/(W*0.78))**2 + ((yy-cy)/(H*0.95))**2)
t = np.clip(d, 0, 1)[:, :, None]**0.9
canvas = BG_IN*(1-t) + BG_OUT*t

def paste(img, alpha, x, y):
    h, w = alpha.shape
    reg = canvas[y:y+h, x:x+w]
    canvas[y:y+h, x:x+w] = reg*(1-alpha[:,:,None]) + img*alpha[:,:,None]

def shadow(x, y, w, h, r=26, spread=18, strength=0.55):
    """sombra suave debajo de una tarjeta: la mascara redondeada difuminada por cajas"""
    m = np.zeros((H, W), np.float32)
    y0, y1 = max(0,y+8), min(H, y+h+14)
    x0, x1 = max(0,x-4), min(W, x+w+4)
    m[y0:y1, x0:x1] = 1.0
    k = spread
    c = np.cumsum(np.cumsum(np.pad(m, k, mode='constant'), axis=0), axis=1)
    box = (c[2*k:, 2*k:] - c[:-2*k, 2*k:] - c[2*k:, :-2*k] + c[:-2*k, :-2*k])/((2*k)**2)
    box = box[:H, :W]
    global canvas
    canvas = canvas*(1 - (box*strength)[:,:,None])

# --- tarjetas: capturas reales del campo ---
CARD_W = 560
cards = []
def trim(a):
    """Quita el margen uniforme que traen las capturas: se toma el color de la esquina como
    fondo y se recorta al bounding box de lo que difiere. Importa para la captura del tema
    oscuro, cuyo marco blanco sobre el navy del hero parecia un error."""
    bg = a[0,0]
    dif = np.abs(a - bg).max(axis=2) > 18
    ys, xs = np.where(dif)
    if len(ys) == 0: return a
    return a[ys.min():ys.max()+1, xs.min():xs.max()+1]

for name in ('trend-arrow-3.png', 'trend-arrow-5.png'):
    a = trim(read_png(f'{S}/{name}')[:,:,:3].astype(np.float32))
    h0, w0, _ = a.shape
    ch = int(round(CARD_W*h0/w0))
    cards.append(resize(a, CARD_W, ch))
gap = 30
total = sum(c.shape[0] for c in cards) + gap
y = (H - total)//2
x = 748
for c in cards:
    ch = c.shape[0]
    shadow(x, y, CARD_W, ch)
    paste(c, rounded(ch, CARD_W, 22), x, y)
    y += ch + gap

# --- icono a la izquierda, con su alpha real ---
ic = read_png(f'{S}/icon-master-1024.png').astype(np.float32)
SZ = 470
irgb = resize(ic[:,:,:3], SZ, SZ)
ial = resize(ic[:,:,3:4], SZ, SZ)[:,:,0]/255.0
paste(irgb, ial, int(cx-SZ/2), int(H/2-SZ/2))

write_png(f'{S}/hero-image-1440x720.png', np.clip(canvas,0,255).astype(np.uint8))
print(f"escrito {S}/hero-image-1440x720.png  ({W}x{H})")
