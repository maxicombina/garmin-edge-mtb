# j-trend-arrow — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el
`CLAUDE.md` del repo, sección «Flujo de release»). La versión **no vive en el paquete**
(`manifest.xml version="3"` es la versión del *formato*, no de la app): se tipea a mano en el
portal de Connect IQ al subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

- **id de la app:** `140986d8c6bc4026880e117255a6ce67` (el del `manifest.xml` en `main`). Esta app no
  usa el desdoblamiento beta/prod que tiene la Opción A: hay un solo id y es este.
- Si algún día hiciera falta un id aparte, el flujo es el de siempre: generarlo con `uuidgen`,
  aplicarlo a mano en el `manifest.xml` del lado de la rama `release` y taguear `j-trend-arrow/vX.Y.Z`.

Entradas, más nueva primero.

## v0.1.0 — 2026-07-26 — prod

**SUBIDA al portal el 2026-07-26.** El `.iq` salió del commit `1a6417a` de la rama `release`, que es
el que lleva el tag `j-trend-arrow/v0.1.0`; versión tipeada a mano en el portal: `0.1.0`. Ficha con
los textos EN/ES de [`LISTING.md`](LISTING.md), categoría Cycling, seis capturas, hero 1440×720 y
contacto `el.soldador.garmin@gmail.com`.

Primera subida. Campo de datos que muestra la **velocidad actual** en grande con una **flecha ↑/↓
al lado**, comparándola contra la **velocidad promedio de la actividad** (estilo Cateye), y el
promedio en una línea secundaria cuando la celda es alta.

- **Lógica** en dos módulos puros con tests (11/11): `TrendArrow` (clasificador genérico sin estado:
  dos enteros ya redondeados → `UP`/`NONE`/`DOWN`) y `SpeedFormat` (m/s → km/h o mph según
  `paceUnits` del device, redondeo único en décimas, string `"24.3"` por aritmética entera).
- **Banda muerta semántica de ±0,1 km/h**: si la diferencia contra tu media es ≤ 0,1 no hay flecha
  («vas a la media»). No es anti-parpadeo, es una decisión de significado.
- **Render estilo nativo**: número grande, unidad `km`/`h` apilada a su derecha alineada a la base
  de los dígitos, label con el nombre de la métrica (`VELOCIDAD`, corto `VEL` si la celda es
  angosta). Layout adaptativo con caché por celda; modo inline `actual / promedio` en celdas
  anchas y cortas. Sin decimal a partir de 100 km/h para no achicar la fuente.
- **13 devices** (`edge530/540/830/840/550/850/1030 ×3/1040/1050/explore2/mtb`), `eng` + `spa`,
  CIQ 3.3.0, sin settings.
- **Flecha con GLIFO cuando el device puede, primitiva cuando no.** La disponibilidad se **mide en el
  propio device** (dos señales: ancho > 2 px y distinto del de un codepoint de uso privado), nunca por
  lista de modelos: en la familia TTF (840, 540, 550, 850, 1040, 1050, mtb) se dibuja el carácter; en la
  de bitmaps (830, 530, 1030 ×3, explore2) cae a las primitivas `fillPolygon`+`fillRectangle`. El peor
  caso es el comportamiento anterior, así que no hay regresión posible.
- **El hueco de la flecha se reserva siempre**, se pinte o no: antes el grupo iba centrado y se encogía en
  los segundos sin flecha, con lo que el número saltaba de lado cada vez que la velocidad cruzaba la media.
- **Íconos propios** (ya no el placeholder de la A): aro cobalto con la raya ámbar del promedio y la
  flecha blanca cruzándola. Master 1024 RGBA y `store-icon-500` **con** los tacos redondeados del
  neumático; los 13 launchers dibujados a su tamaño y **lisos**, porque a 35 px los tacos hacían leer
  "ajustes" (`SPEC.md` §3.3). Seis capturas para la ficha en `store/trend-arrow-*.png`.

No se publicó ninguna `v0.0.1`: ese número se registró un día y se reemplazó por este antes de subir nada.

Pendiente **posterior** a esta subida: elegir entre la flecha `↑` y el triángulo `▲` mirando el
sideload en el 840 (son dos constantes, `ARROW_GLYPH_UP`/`DOWN`), y la iteración de la referencia
configurable de la SPEC §9.1.
