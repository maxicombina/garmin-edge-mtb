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

**Número REGISTRADO, todavía SIN SUBIR.** El código está listo y verde, pero el `.iq` no se exportó ni
se subió al portal: falta el **ícono propio** (ver abajo). Cuando se suba, va al **canal beta** con el
id `245d3803…`, como entrada **sin publicar**, y se instala por el link de `apps.garmin.com` +
Connect Mobile.

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
- **13 devices** (`edge530/540/830/840/550/850/1030 ×3/1040/1050/explore2/mtb`), `eng` + `spa`,
  CIQ 3.3.0, **sin settings** y sin permisos.
- **Verificado (2026-07-27):** **9/9 tests PASS** con `monkeydo -t` en el edge840 — 4 propios de
  `CadenceFormat` + los 5 del barrel, que corren namespaceados (`TrendCore.testX`) desde esta app — y
  **export de los 17 targets limpio**. El único warning es el conocido del Edge 1030 con part number
  `006-B2924-00` (CIQ 3.2.5), que no llega al `minApiLevel` del proyecto y queda fuera del `.iq`:
  esperado, pasa en las cuatro apps del repo.

⚠️ **Bloqueante de la subida: los íconos launcher son los de la Opción J, copiados y byte-idénticos.**
O sea que en la lista de campos del Edge esta app es **indistinguible de J** salvo por el nombre. Hay
que dibujarle un motivo propio antes de subirla (biela/plato o pedal es el candidato natural: además
rompe la silueta circular del de J). Ver [`../SPEC.md`](../SPEC.md) §3.4, que ya lista lo aprendido en
J para no repetirlo.

⚠️ **Antes de exportar el `.iq`, verificar que `TEST_MODE` esté en `false`** en
`source/CadenceTrendView.mc`. Con `true` el build de release **compila limpio y sin warnings** pero el
campo muestra `--` para siempre (el generador sintético es `(:debug)` y su stub `(:release)` devuelve
nulls, así que nunca lee `Activity.Info`). Le costó a J un número de versión quemado.

Pendiente también, para cuando se suba: los assets de la ficha (capturas, hero 1440×720, textos EN+ES)
y el contacto `el.soldador.garmin@gmail.com`, que es el que usan las fichas de este repo.
