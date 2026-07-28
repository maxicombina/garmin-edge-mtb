#!/usr/bin/env python3
"""
Deja las capturas de la ficha por debajo del limite de peso del portal. Solo numpy.

    python3 opt_screenshots.py            ->  reescribe cadence-trend-*.png en su sitio

EL PORTAL DE CONNECT IQ ACEPTA COMO MAXIMO 150 KB POR CAPTURA. Las imagenes que llegan de un
generador vienen en RGB de 1500 px y pesan ~780 KB, o sea 5 veces el limite. Esta es la misma receta
que se uso en la Opcion J, cuyas capturas quedaron en 23-33 KB:

  1) REDUCIR a 1000 px de ancho. Es el tamano que uso la J y sobra para la ficha. La reduccion
     promedia bloques (`np.add.reduceat`), que es un antialias de verdad: reducir tomando un pixel de
     cada N deja los trazos comidos.
  2) PASAR A ESCALA DE GRISES, o sea PNG de tipo de color 0, un byte por pixel en vez de tres. Aca
     esta el grueso del ahorro. Es LEGITIMO Y SIN PERDIDA porque el campo de datos es negro sobre
     blanco: el script VERIFICA que la imagen sea neutra antes de convertir, y si encuentra color de
     verdad la deja en RGB.
     LA VERIFICACION MIRA UNA PROPORCION, NO EL MAXIMO. Primer intento: "si algun pixel separa mas de
     12 niveles entre R, G y B, hay color". Con eso una de las tres capturas quedo marcada como color
     y en 324 KB, cuando su separacion maxima era 13 con una MEDIA de 0,29 y solo el 0,003 % de los
     pixeles pasaba de 8: ruido del generador, no color. Un maximo lo decide un punado de pixeles; la
     proporcion describe la imagen.
  3) SI AUN ASI NO ENTRA, bajar el ancho por pasos hasta que entre. El color se decide una vez; el
     tamano es la perilla que queda.

No se toca `hero-image-1440x720.png`: el hero es otro asset y el portal no le pone ese limite.
"""
import numpy as np, os, glob, struct, zlib

LIMIT_KB = 150
TARGET_W = 1000

def read_png(path):
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
    return px[:,:,:3] if nch>=3 else np.repeat(px[:,:,:1],3,2)

def write_png(path, arr, gray):
    """arr: HxW (gris) o HxWx3 (RGB). El filtro 'Up' (2) por fila ayuda mucho en imagenes con
    grandes zonas planas, que es exactamente el caso de una captura de un campo de datos."""
    if gray:
        h,w = arr.shape; ct=0; nch=1; rows=arr.reshape(h,w,1)
    else:
        h,w,_ = arr.shape; ct=2; nch=3; rows=arr
    prev=np.zeros((w*nch,),np.int32); out=[]
    for y in range(h):
        cur=rows[y].reshape(-1).astype(np.int32)
        raw0=b'\x00'+cur.astype(np.uint8).tobytes()
        raw2=b'\x02'+((cur-prev)&255).astype(np.uint8).tobytes()
        out.append(raw0 if len(zlib.compress(raw0,6))<=len(zlib.compress(raw2,6)) else raw2)
        prev=cur
    def chunk(t,d):
        c=struct.pack('>I',len(d))+t+d
        return c+struct.pack('>I', zlib.crc32(t+d)&0xffffffff)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,ct,0,0,0))
    png+=chunk(b'IDAT',zlib.compress(b''.join(out),9))+chunk(b'IEND',b'')
    open(path,'wb').write(png)

def box_down(im, w):
    sh,sw = im.shape[:2]
    if sw<=w: return im.astype(np.float32)
    h=max(1,int(round(sh*w/sw)))
    ys=(np.arange(h+1)*sh//h); xs=(np.arange(w+1)*sw//w)
    a=im.astype(np.float32)
    a=np.add.reduceat(a, ys[:-1], axis=0)/np.diff(ys)[:,None,None]
    a=np.add.reduceat(a, xs[:-1], axis=1)/np.diff(xs)[None,:,None]
    return a

HERE=os.path.dirname(os.path.abspath(__file__))
files=sorted(glob.glob(f'{HERE}/cadence-trend-*.png'))
if not files:
    print("no hay capturas cadence-trend-*.png"); raise SystemExit
for p in files:
    before=os.path.getsize(p)//1024
    im=read_png(p).astype(np.int32)
    sp=im.max(2)-im.min(2)
    colour_frac=float((sp>20).mean())
    gray = colour_frac < 0.001                      # proporcion, no maximo: ver la nota de arriba
    w=TARGET_W
    for _ in range(8):
        small=box_down(im, w)
        arr=(np.clip(small.mean(2),0,255) if gray else np.clip(small,0,255)).astype(np.uint8)
        write_png(p, arr, gray)
        after=os.path.getsize(p)//1024
        if after<=LIMIT_KB-10: break                 # margen: el limite es duro y el peso varia
        w=int(w*0.9)
    tag="gris" if gray else f"RGB (color real en el {colour_frac*100:.2f} % de los pixeles)"
    flag="" if after<=LIMIT_KB else f"  <-- SIGUE POR ENCIMA DE {LIMIT_KB} KB"
    print(f"  {os.path.basename(p):28s} {before:4d} KB -> {after:3d} KB   {arr.shape[1]}x{arr.shape[0]}  {tag}{flag}")
