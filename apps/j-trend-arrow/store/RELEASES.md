# j-trend-arrow — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el
`CLAUDE.md` del repo, sección «Flujo de release»). La versión **no vive en el paquete**
(`manifest.xml version="3"` es la versión del *formato*, no de la app): se tipea a mano en el
portal de Connect IQ al subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

**Los DOS ids de esta app** (desde el 2026-07-26 J usa el mismo desdoblamiento que la Opción A; antes
tenía uno solo). Cada id es una app distinta en el portal, y **ninguno de los dos se cambia nunca**:

| Canal | id | Vive en | Entrada del portal |
|---|---|---|---|
| **PROD** | `140986d8c6bc4026880e117255a6ce67` | rama `release` | la publicada (v0.1.0) |
| **BETA** | `f70f3c984e4c43d496006628f3510817` | rama `main` | entrada **sin publicar**, se instala por el link de `apps.garmin.com` + Connect Mobile |

El id beta se generó el 2026-07-26 con `uuidgen | tr -d '-' | tr 'A-Z' 'a-z'` porque los **settings de
una app sideloadeada no se pueden editar desde el teléfono** (cuelgan del vínculo con la store, ver
`SPEC.md` §9.9), así que probarlos exige una instalación real de la store — y hacerlo contra la ficha
publicada costaba una ronda de review por iteración.

⚠️ **En el próximo release de PROD:** la línea del id cambió en `main`, así que `git merge main` va a
llevar el id **beta** a `release` **sin conflicto** (cambió de un solo lado). Justo después del merge
hay que commitear el swap de vuelta al id de prod tocando solo `apps/j-trend-arrow/manifest.xml`, como
hizo `6ad6be8` con la A. El aviso está también en el comentario del `manifest.xml` y en `CLAUDE.md`.

Entradas, más nueva primero.

## v0.2.1 — 2026-07-26 — beta

⚠️ **La `v0.2.0` está QUEMADA, no la reuses.** Se subió con un `.iq` roto: estaba exportado con
`TEST_MODE = true`, y en un build de release eso deja el campo mostrando `--` para siempre (el
generador sintético es `(:debug)` y su stub `(:release)` devuelve nulls, así que nunca lee
`Activity.Info`; compila limpio y sin warnings). Se rehízo el `.iq` con `TEST_MODE = false`, pero el
portal **no permite reusar un número de versión ya subido**, así que el `.iq` bueno subió como
`0.2.1`. Mismo código, mismo commit: la única diferencia entre las dos es ese flag.
**Lección:** antes de exportar cualquier `.iq`, verificar `TEST_MODE`.

**SUBIDA al canal beta el 2026-07-26** (entrada del portal con el id **beta** `f70f3c98…`, sin
publicar; se instala por el link de `apps.garmin.com` + Connect Mobile). El `.iq` es
`bin/j-trend-arrow-beta.iq`, exportado desde `main` con los 17 targets. La ficha publicada (prod,
v0.1.0) no se tocó. Va al canal beta y no directo a prod porque **los settings de una app
sideloadeada no se pueden editar desde el teléfono**, así que probarlos exige una instalación real de
la store, y contra la ficha publicada eso costaba una ronda de review por iteración.

Qué trae: **la referencia de la flecha es configurable** (SPEC §9). Dos settings editables desde el
teléfono — *Comparar contra* (promedio de la salida | objetivo fijo) y *Velocidad objetivo* — con el
prefijo de la segunda línea pasando de `PROM` a `META` en modo objetivo.

- **El default es el promedio de la salida**, o sea idéntico a la v0.1.0 para quien no toque nada
  (verificado end-to-end contra `Application.Properties`, SPEC §9.8.1).
- **Objetivo a 1 decimal**: el schema de settings no puede exigirlo (no existe `step` ni `decimals`),
  así que lo cuantiza el código y la pantalla muestra el valor cuantizado — tipeás 22.37, ves 22.4.
- **Degradación silenciosa**: modo objetivo con el número sin configurar o en 0 se comporta como
  promedio. Hacen falta las dos cosas para salir del promedio.
- La lógica de `TrendArrow`/`SpeedFormat` **no cambió** (el clasificador ya era genérico): solo cambia
  de dónde sale el segundo número y el rótulo. Suite 12/12.
- ⚠️ **Antes de exportar cualquier `.iq`, `TEST_MODE` tiene que estar en `false`.** En un build de
  release con `TEST_MODE = true` el generador sintético es `(:debug)` y el stub `(:release)` devuelve
  nulls → el campo muestra `--` para siempre, compilando limpio y sin avisar. Pasó justamente con el
  primer `.iq` beta de esta versión y se rehízo.

Sigue pendiente de la v0.1.0: elegir entre `↑` y `▲` mirando el sideload en el 840.

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
