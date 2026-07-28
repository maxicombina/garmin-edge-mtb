# k-cadence-trend — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el `CLAUDE.md` del
repo, sección «Versionado por app»). La versión **no vive en el paquete** (`manifest.xml version="3"`
es la versión del *formato* del manifest, no de la app): se tipea a mano en el portal de Connect IQ al
subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

**Los ids de esta app.** Hoy hay **uno solo**, el de beta, porque nunca se subió nada a producción.
Cada id es una app distinta en el portal y **no se cambia nunca**:

| Canal | id | Vive en | Entrada del portal |
|---|---|---|---|
| **BETA** | `245d380378fd4d208ea89989b8b337a7` | rama `main` | todavía **no existe** |
| **PROD** | — | rama `release` | — |

Cuando K vaya a producción hay que generar su id de prod (`uuidgen | tr -d '-' | tr 'A-Z' 'a-z'`),
aplicarlo **a mano** en `manifest.xml` del lado de `release` (nunca con el editor visual del manifest,
que reformatea el XML) y anotarlo acá. El delta de `release` sobre `main` es exactamente eso y nada
más, así que el merge `main→release` no da conflicto: solo `release` toca esa línea.

Entradas, más nueva primero.

## v0.1.0 — 2026-07-27 — beta

**Número REGISTRADO, todavía SIN SUBIR** — pero ya **sin bloqueantes**: el código está verde y desde el
2026-07-27 la app tiene **ícono propio**. Cuando se suba, va al **canal beta** con el id `245d3803…`,
como entrada **sin publicar**, y se instala por el link de `apps.garmin.com` + Connect Mobile. Lo que
falta antes de subir es de mano del autor: mirarla andar en el simulador y decidir los assets de la
ficha.

Primera versión. Data field que muestra la **cadencia actual** en grande con una **flecha ▲/▼ al
lado**, comparándola contra la **cadencia promedio de la actividad** (estilo Cateye, igual que la
Opción J pero sobre cadencia), y el promedio en una línea secundaria cuando la celda es alta.

- **La métrica más simple de la familia:** Garmin entrega la cadencia en **rpm enteros** y *rpm es rpm
  en todos los países*, así que no hay conversión, ni décimas, ni unidades que cambien con el device —
  nada del aparato que necesitó la velocidad en J.
- **La única decisión de producto: el `0` de no pedalear.** En una bajada de MTB pasás minutos sin
  pedalear, y llamar a eso «vas por debajo de tu media» sería falso. **Se muestra el `0` real, sin
  flecha.** Implementado haciendo que `CadenceFormat.trendValue()` devuelva `null` al no pedalear, lo
  que reusa el camino `null → NONE` que el clasificador compartido ya tenía: no hubo que tocar ni una
  línea del barrel. Hay un test que junta las dos piezas y **falla si alguien las fusiona**.
- **Banda muerta de 3 rpm:** la flecha aparece solo si te separás más de 3 rpm de tu media. La lectura
  a 1 Hz jitterea sola un par de rpm, así que con una banda de 1 la flecha seguiría al ruido. Como en
  J, es una decisión de **significado** antes que anti-parpadeo.
- **Primera app construida sobre el barrel `TrendCore`** (clasificador + motor de render, compartido
  con J y con la futura L). La View quedó en **~130 líneas y sin una sola línea de layout**; el motor
  que dibuja es el mismo que se afinó pixel a pixel contra el campo nativo del Edge, así que la
  paridad con el nativo, la flecha glifo-o-primitiva, la unidad estilo nativo y el modo inline de
  celdas anchas se heredan hechos.
- **Referencia configurable, como J** (`../SPEC.md` §7): dos ajustes editables desde el teléfono —
  *Comparar contra* (promedio de la salida | objetivo fijo) y *Cadencia objetivo* — con el prefijo de la
  segunda línea pasando de `PROM` a `META`. **El default es el promedio**, y con el objetivo sin
  configurar o en 0 se comporta igual que el promedio, en silencio. Más simple que en J: el objetivo es
  **un entero de rpm**, sin unidad del device que interpretar y sin nada que cuantizar. La lógica no
  cambió una línea: el clasificador ya era genérico.
- **Glifo de la BIELA junto al label**, como el campo nativo (`../SPEC.md` §6.3): aro + biela en diagonal
  + un pedal en cada punta, dibujado con primitivas. El nativo pone pictograma en `CADENCIA` y en
  `TIEMPO` pero no en `VELOCIDAD`, así que K lo lleva y J no. Medido de una captura: 23×19 px con 3 px de
  hueco. Para esto el barrel estrenó un hook —reserva la caja y llama de vuelta— **sin enterarse de qué
  dibuja**.
- **Ícono propio** (`../SPEC.md` §3.4), que era el bloqueante de la subida: **cuerpo de pedal
  CUADRADO**, con la misma raya ámbar y la misma flecha blanca que J adentro. Todo generado por
  `gen_icon.py` (solo numpy): master 1024, `store-icon-500` y los 13 launchers, cada uno dibujado a su
  tamaño. **Lo que distingue a K de J a 35 px es la silueta —cuadrado contra redondo—, no el detalle**,
  que a ese tamaño no existe. Y **no es un plato a propósito**: en la prueba a ciegas de J, 7 de 7
  observadores leyeron los tacos del neumático como «engranaje/ajustes», y un plato es literalmente un
  engranaje.
- **13 devices** (`edge530/540/830/840/550/850/1030 ×3/1040/1050/explore2/mtb`), `eng` + `spa`,
  CIQ 3.3.0, sin permisos.
- **Verificado (2026-07-27):** **10/10 tests PASS** con `monkeydo -t` en el edge840 — 5 propios de
  `CadenceFormat` + los 5 del barrel, que corren namespaceados (`TrendCore.testX`) desde esta app — y
  **export de los 17 targets limpio**. El único warning es el conocido del Edge 1030 con part number
  `006-B2924-00` (CIQ 3.2.5), que no llega al `minApiLevel` del proyecto y queda fuera del `.iq`:
  esperado, pasa en las cuatro apps del repo.

⚠️ **Antes de exportar el `.iq`, verificar que `TEST_MODE` esté en `false`** en
`source/CadenceTrendView.mc`. Con `true` el build de release **compila limpio y sin warnings** pero el
campo muestra `--` para siempre (el generador sintético es `(:debug)` y su stub `(:release)` devuelve
nulls, así que nunca lee `Activity.Info`). Le costó a J un número de versión quemado.

Pendiente también, para cuando se suba: los assets de la ficha (capturas, hero 1440×720, textos EN+ES)
y el contacto `el.soldador.garmin@gmail.com`, que es el que usan las fichas de este repo.
