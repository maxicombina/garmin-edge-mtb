# Prompts para generar los assets de j-trend-arrow

Al modelo de imagen (ChatGPT Images 2.0 / `gpt-image-2`) le pedimos **solo dos imágenes grandes y opacas**: (1) el **master del ícono en 1:1** —se pide en relación de aspecto, no en píxeles: el UI devuelve ~2048×2048 y yo lo bajo con Pillow a `icon-master-1024.png` (1024×1024)— y (2) opcionalmente el **hero en 2:1** (~2048×1024, que recorto a exactamente 1440×720). Todo lo demás lo derivo yo después con Pillow en el venv de siempre, dentro de `apps/j-trend-arrow/store/` (directorio nuevo) y `apps/j-trend-arrow/resources[-device]/drawables/`: `store-icon-500.png` (500×500 sRGB, fondo gris claro sólido, como el de la A), los **cinco** `launcher_icon.png` (35/36/40/56/68 px) **redibujados planos**, y si querés el ícono opcional de la tienda on-device (128×128, variante full-colour + variante 64 colores). Las **capturas salen del simulador**, nunca del modelo (la A subió seis de 482×232, día + `-inv` noche; Garmin no publica spec de capturas).

## 1. Icono master 1024x1024 (el que hay que pedirle a ChatGPT)

Motivo elegido: **rueda/neumático MTB de frente + UNA flecha blanca que cruza una línea ámbar de referencia** (la línea es "tu promedio", la flecha es "dónde estás ahora"). Pegar tal cual, en un chat nuevo, con el selector de relación de aspecto en 1:1.

```
Generate a brand-new image from scratch. There is no reference, source or uploaded image: this is not an edit, a restoration or a variation of anything. Follow every instruction below to the letter, and do not rewrite or summarise them.

Square 1:1, highest quality and largest resolution available; do not target a pixel size.

Background: one perfectly flat, uniform, saturated magenta (#FF00FF), identical in every pixel, edge to edge — no gradient, texture, noise or pattern — and magenta nowhere else. The single centred subject fills the middle 86% of the canvas, touches no edge, and casts no shadow, glow or colour bleed onto the background.

Subject: a mountain-bike tyre, face-on as a perfect circle — a thick ring of vivid electric cobalt blue (#0070F0) enclosing a plain very dark navy face. Around the outside of the ring sit exactly six shallow ROUNDED tread nubs, evenly spaced at equal angles: each one is a soft bump about twice as wide as it is tall, protruding only a little, with fully rounded corners. They are soft rubber lugs, never square tabs, never sharp radial teeth: this must read as a knobby tyre and must NEVER look like a gear, cog, sprocket or a settings symbol. No spokes, no hub, no fine serration.

On the face, one level amber-yellow reference line sits LOW — about two thirds of the way down the face — spanning two thirds of the icon's width, thick and unmissable at one twelfth of the image width from top to bottom, with square-cut ends. Exactly ONE bold pure-white up arrow crosses it: its tail starts just below that line, the line is interrupted where the arrow passes, and its solid triangular head rises high above it. The arrow is WIDE AND POWERFUL, never a thin needle: its head spans nearly half the width of the face and its stem is half as wide as the head. It fills the upper two thirds of the icon and its tip clearly protrudes past the outer edge of the ring, plainly breaking the round silhouette; only the bottom quarter of the navy face is left empty. One arrow only: never a second or downward arrow, never a long uniform shaft running the whole height, never a road sign.

Palette: cobalt blue dominant, one lighter blue inner rim, very dark navy, pure white, one amber accent — nothing else. Illustrative finish lit from the upper left: that inner rim plus one broad soft highlight on the ring's upper-left edge; every other region one solid flat colour. No shimmer, sparkle, bevel, emboss, 3D render, texture, drop shadow, frame, app-tile framing, sticker outline or watermark.

It must reduce to four masses — blue knobby ring, navy face, white arrow, amber line — with maximum white-on-navy contrast, legible on white and on black. Nothing thinner than one twelfth of the image width; anything thinner is left out. No letters, digits, words or units anywhere; no logos or brand marks; no watch, dial, ticks or hands; the amber line is a plain straight bar, never a chevron, zigzag or ramp.
```

### Variantes de motivo (si el resultado no gusta)

**gauge-arrow (velocímetro analógico sin aguja).** Preferirlo si querés máxima hermandad visual con el cronómetro de la A (misma familia "instrumento redondo") y no te importa perder la señal MTB. Reemplazar **solo** el párrafo `Subject:` por:

```
Subject: a circular analogue speed gauge, face-on — a thick ring of vivid electric cobalt blue (#0070F0) enclosing a plain very dark navy face, with six chunky white tick wedges spread across the top of the face, each at least one twelfth of the image width thick. No needle, no centre pivot, no numerals, no sub-dial, no crown or side buttons, and never a diagonal line from the centre.
```

**number-plus-arrow (cuerpo de ciclocomputadora).** Preferirlo si querés que se lea "campo de datos / instrumento", no "bici". Reemplazar el párrafo `Subject:` por lo siguiente, y en el resto del prompt cambiar `the ring` → `the bezel` y `blue knobby ring` → `blue bezel`:

```
Subject: a small cycling-computer instrument body, seen straight on — a rounded rectangle only slightly wider than tall (about 8:7), a thick bezel of vivid electric cobalt blue (#0070F0) enclosing a plain very dark navy inset face. A free-standing object with flat background visible on all four sides: never a full-bleed tile, never a frame around the image, and never a depiction of a real product (no mounting tab, no side-button row, no screen chin).
```

**chevron-baseline (marca abstracta plana).** Preferirlo si las versiones ilustrativas salen barrosas, o si querés que el master y el launcher sean **la misma geometría** (traza 1:1 en Pillow). Borrar el párrafo `Subject:` completo, reemplazar el de la flecha por el de abajo, y cambiar `four masses` → `two masses — cobalt arrow and amber line` y `Illustrative finish ... upper-left edge;` → `Completely flat finish with no lighting and no highlight;`:

```
Subject: one straight amber-yellow horizontal reference line, 80% of the image wide and one eighth of it thick, with square-cut ends; exactly ONE bold cobalt-blue (#0070F0) up arrow crosses it — tail below the line, the line interrupted where the arrow passes, solid triangular head clearly above. The arrow is half the image wide and four fifths of it tall, its head 55% of that height at full width, its stem one third of that width. One arrow only.
```

**Ajuste puntual (no cambia el motivo):** si la rueda sale con pinta de piñón/engranaje, cambiar `with exactly six large square tread knobs, widely spaced, each as thick as the ring,` por `with a perfectly smooth outer edge and no tread blocks, teeth or notches of any kind,`.

## 2. Hero 1440x720 (opcional, para la ficha del store)

Pedir **2:1 landscape** (el UI no respeta píxeles exactos: devuelve ~2048×1024); yo lo recorto/redimensiono a exactamente **1440×720** y compongo encima, en el área vacía, capturas **reales del simulador**. Por eso el prompt exige que esa zona quede limpia, sin UI falsa y sin texto.

```
Generate a brand-new image from scratch. There is no reference, source or uploaded image: this is not an edit, a restoration or a variation of anything. Follow every instruction below to the letter, and do not rewrite or summarise them.

Ultra-wide 2:1 landscape composition, highest quality and largest resolution available; do not target a pixel size.

On the left third of the frame, one single large illustrated object: a mountain-bike tyre seen face-on as a perfect circle — a thick ring of vivid electric cobalt blue (#0070F0) with six large square tread knobs, widely spaced, enclosing a plain very dark navy face; on that face one level amber-yellow reference line and exactly ONE bold pure-white up arrow crossing it, tail below the line, solid triangular head above, its tip breaking past the top of the ring. Palette: cobalt blue, one lighter blue inner rim, very dark navy, pure white, one amber accent — nothing else. One broad soft highlight on the ring's upper-left edge; every other region one solid flat colour.

Background: a deep navy radial gradient, brightest just behind the object and falling smoothly to near-black at the edges. Perfectly smooth: no texture, noise, stars, grid, lines, particles, light rays, photography, landscape or scenery.

The right two thirds of the frame stay completely clean and empty — nothing there but that dark gradient. No device, screen, phone, watch, bike computer, mockup, panel, card, chart, dial or user interface of any kind, no extra icons or shapes, no logos, no reflections and no shadows in that area.

No letters, digits, words, captions, labels, signature or watermark anywhere in the image.

Keep the object clear of all four edges, with at least a twentieth of the image width of empty gradient around it: the image will be cropped.
```

## 3. Qué hago yo despues (Pillow)

- **`store/icon-master-1024.png`** — recorto el magenta con tolerancia HSV (no es bit-exacto: SynthID mete corrimientos sub-visibles), desflecado del borde, remapeo el azul dominante a exactamente `#0070F0`, y bajo de ~2048 a **1024×1024** con LANCZOS (nunca ampliar). Queda con **alpha real**, como el master de la A.
- **`store/store-icon-500.png`** — **500×500 sRGB** (requisito verificado), master compuesto sobre gris claro sólido `#E6E6E6` igual que la A, con el arte dentro del centro dejando ≥10 px de margen (≈480×480 útiles, también verificado). **Opaco**: Garmin desalienta explícitamente fondo transparente o negro.
- **Launcher: cinco tamaños redibujados PLANOS** (no downscale del master) en `resources[-device]/drawables/launcher_icon.png`, RGBA: **35** (edge530/540/**830**/**840**), **36** (edge1030/1030plus/1030bontrager/edgeexplore2/edgemtb), **40** (edge1040), **56** (edge550/850), **68** (edge1050). Se dibujan con primitivas (dos elipses + polígono + rectángulo): la lección de la A está escrita en `apps/a-activity-timer/SPEC.md:292` — el master glossy reducido a 35 px quedaba una **mancha borrosa** y hubo que rehacerlo plano. Abajo de 56 px tiro los knobs, el brillo y el aro interior: quedan anillo + cara + flecha (la línea ámbar solo si entra ≥1/12 del ancho).
- **Azul del launcher `#0055FF`, no `#0070F0`**: los MIP (830/840/1030/1040…) renderizan solo 64 colores (canales 00/55/AA/FF) y `#0070F0` **no** está en la paleta → se ditherea. Evalúo además `dithering="none"` + `<palette>` explícita en el XML del drawable para que el 35 px salga nítido.
- **Opcional, ícono de tienda on-device 128×128** (la A no lo tiene: es un hueco de su ficha): dos archivos, uno full-colour y uno restringido a los 64 colores, y **tienen que diferir** entre sí (el portal rechaza dos subidas byte-idénticas — reporte de foro, no confirmado por Garmin).
- **Hero**: recorte/resize a exactamente **1440×720** y composición de las capturas reales del simulador en el tercio derecho vacío.
- **Capturas**: del simulador, pares día + `-inv` noche a 482×232 como la A (Garmin no publica spec; el "500×500 y 150 KB" del foro es no verificado y lo contradice la ficha ya publicada de la A).

## 4. Checklist al recibir la imagen

- **Damero horneado**: el archivo tiene que venir **opaco, con fondo magenta parejo**. Abrilo en Preview y hacé zoom al 400 %: si aparece un cuadriculado gris/blanco que **escala con el zoom**, está pintado en los píxeles (el fondo de transparencia real de Preview no escala) → descartar y regenerar en sesión nueva. Chequeo duro: `python3 -c "from PIL import Image; im=Image.open('x.png'); print(im.mode, im.size, [im.convert('RGB').getpixel(p) for p in [(2,2),(im.width-3,2),(2,im.height-3),(im.width-3,im.height-3)]])"` — las cuatro esquinas deben dar ~(255,0,255) y ninguna gris.
- **Fondo uniforme**: mismo chequeo en esquinas + medios de cada lado. Variación de unos pocos puntos por canal es normal (SynthID); un degradé o una mancha visible, no — rompe el keying.
- **Colores**: cuentagotas sobre el aro (un azul vivo y plano, no "azul profundo" apagado), la cara (navy casi negro), la flecha (blanco puro), la línea (ámbar). **Cero rojo, verde, naranja o gris** en el sujeto; el magenta no debe aparecer en ninguna parte del dibujo.
- **Cero texto**: zoom 100 % sobre la cara y el borde buscando dígitos, unidades, marcas de agua o firmas diminutas. Cualquier glifo = regenerar (regla explícita de Garmin para el ícono del store).
- **Silueta legible**: alejá el zoom hasta ~35 px (o entrecerrá los ojos a un brazo de distancia). Tienen que quedar tres masas: anillo azul, cara oscura, flecha blanca. Si la flecha se pierde, regenerar.
- **La punta rompe el anillo**: verificá que el vértice de la flecha sobresale del aro — es lo que distingue este ícono de la silueta redonda del cronómetro de la A. Poné los dos launchers de la A y de la J lado a lado a 35 px: no deben confundirse.
- **No es un engranaje**: si los seis knobs se leen como dientes de piñón, aplicar el "ajuste puntual" de arriba (borde liso).
- **Centrado y márgenes parejos**: `python3 -c "from PIL import Image, ImageChops; ..."` o a ojo con la regla de Preview — el sujeto no toca ningún borde y los cuatro márgenes son iguales dentro de un ~2 % (necesito ≥10 px equivalentes de aire para el 500×500).
- **Cuadrada**: ancho == alto (si vino 1536×1024, el selector de aspecto estaba mal; regenerar, no recortar).
- **Sin sombra proyectada**: nada de halo más oscuro en el magenta alrededor del objeto, ni glow, ni reflejo; el borde tiene que ser filoso (una sombra suave sobre el magenta arruina el recorte y deja fleco rosa).
- **Sin producto real**: que no aparezca nada que identifique un modelo de ciclocomputadora ni marcas/logos de terceros.
