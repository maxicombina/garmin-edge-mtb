# garmin-edge-mtb

Aplicaciones Connect IQ para **Garmin Edge** (830 / 840) orientadas a MTB (XC / senderos técnicos).

Proyecto personal. El objetivo es una familia de *data fields* y una *device app* que aporten métricas útiles durante la rodada, calculadas on-device y sin depender de potenciómetro. Hay **dos apps publicadas** en la Connect IQ Store, **dos más implementadas** sin publicar, y el resto en especificación.

## Estado

🚴 **Dos apps en producción** (Opciones A y J, la J con ajustes desde la `v0.2.2`) · **dos implementadas y en validación** (B y K) · el resto, en especificación — ver [`GARMIN_MTB_SPEC.md`](GARMIN_MTB_SPEC.md).

La spec define el contexto (hardware, plataforma, restricciones), **10 opciones de producto evaluadas (A–J)** y un roadmap incremental. De la **K** en adelante son productos pensados después, no parte de esa ronda de evaluación; la letra es una etiqueta estable, no un orden. Resumen:

| | Opción | Formato | Estado |
|---|---|---|---|
| A | Tiempo de actividad (formato adaptativo) | data field | **✅ publicada · prod `v0.1.7`** |
| B | Pendiente + VAM | data field | **🛠️ implementada · 43/43 tests · sin publicar** |
| C | Descenso actual | data field | MVP propuesto |
| D | Cronómetro de tramos (enduro) | data field / device app | idea |
| E | Chunk meter (Grit casero, acelerómetro) | data field | idea |
| F | Detector de saltos / air time | data field | idea |
| G | Estimador de batería restante | data field | idea |
| H | Stamina casera (modelo de depósito por FC) | device app | idea |
| I | Test de subida (VO2max de campo + tracker de forma) | data field / device app | idea |
| J | Flecha de tendencia estilo Cateye (actual vs. referencia) | data field | **✅ publicada · prod `v0.2.3`** |
| K | La misma flecha, sobre la **cadencia** | data field | **🛠️ lista · 10/10 tests · `v0.1.0` sin subir** |
| L | La misma flecha, sobre la **frecuencia cardíaca** | data field | en diseño |

## Las apps

### A — `a-activity-timer` · publicada

Tiempo de actividad con **formato adaptativo de 3 niveles** (incluido el compuesto `H:MM` + `:SS` volado, que resuelve la ambigüedad de leer `1:23`), iconito de cronómetro junto al label dibujado con primitivas, y fuentes del sistema afinadas pixel-perfect contra el campo nativo en un Edge 840 real.

[`SPEC.md`](apps/a-activity-timer/SPEC.md) · [walkthrough del código](apps/a-activity-timer/docs/code-walkthrough.html) · [`RELEASES.md`](apps/a-activity-timer/store/RELEASES.md)

### B — `b-grade-vam` · implementada, sin publicar

Pendiente y VAM **juntas en una celda**, reconstruidas desde cero con el altímetro barométrico porque Connect IQ no expone las nativas. Ocho módulos puros, filtro de outliers con re-seed, histéresis de display y zonas de color. Falta el rediseño de íconos y la validación en device.

[`SPEC.md`](apps/b-grade-vam/SPEC.md) · [walkthrough del código](apps/b-grade-vam/docs/code-walkthrough.html) · [`RELEASES.md`](apps/b-grade-vam/store/RELEASES.md)

### J — `j-trend-arrow` · publicada

La flechita de los ciclocomputadores Cateye de los 90: velocidad actual en grande con **↑/↓ al lado** según vayas por encima o por debajo de tu referencia, y sin flecha cuando estás en la media. Desde la `v0.2.2`, ya en producción, la referencia es **configurable**: el promedio real de la salida o una velocidad objetivo fija. La flecha usa el **glifo nativo si el device lo tiene y una primitiva dibujada si no**, decidido midiendo en el propio device.

[`SPEC.md`](apps/j-trend-arrow/SPEC.md) · [walkthrough del código](apps/j-trend-arrow/docs/code-walkthrough.html) · [`RELEASES.md`](apps/j-trend-arrow/store/RELEASES.md)

### K — `k-cadence-trend` · implementada, sin publicar

La misma flecha de J, sobre la **cadencia**. La métrica más simple de la familia: llega en rpm enteros y rpm es rpm en todos los países, así que no hay conversión ni unidades que cambien. Su única decisión de producto es el **0 de no pedalear**: en una bajada pasás minutos sin pedalear, y llamar a eso "por debajo de tu media" sería falso, así que muestra el `0` real **sin flecha**. Fue la primera app construida sobre el barrel, y su View quedó en ~130 líneas porque no tiene una sola línea de layout. J se migró al mismo barrel el 2026-07-27 y bajó de 858 líneas a 225. Lleva la **referencia configurable** de J (promedio de la salida u objetivo fijo, acá un entero de rpm) y el **glifo de la biela junto al nombre**, como el campo nativo. Su ícono es una **biela** con un pedal en cada punta, y con él quedó fijado el sistema de la familia: el **interior es constante** —la raya ámbar del promedio cruzada por la flecha— y la **silueta exterior dice la métrica**, porque a 35 px la silueta es lo único que sobrevive.

[`SPEC.md`](apps/k-cadence-trend/SPEC.md) · [walkthrough del código](apps/k-cadence-trend/docs/code-walkthrough.html) · [`RELEASES.md`](apps/k-cadence-trend/store/RELEASES.md)

## Estructura

Cada opción vive como proyecto Connect IQ auto-contenido en `apps/<letra>-<slug>/`, de modo que en el futuro pueda extraerse a su propio repositorio sin reestructurar. **La letra es una etiqueta estable, no un orden** — no se renumera.

Por defecto **nada se comparte entre apps** salvo documentación; cuando hace falta código común se decide explícitamente. Esa decisión se tomó una vez, para la familia de la flecha de tendencia (J, K, L), que comparte un **barrel** — el mecanismo de librería de Monkey C.

```
apps/<app>/
├── manifest.xml · monkey.jungle
├── source/        # módulos puros + su *Test.mc, App y View
├── resources[-spa]/
├── docs/          # walkthrough del código en HTML
└── store/         # RELEASES.md, íconos y assets de la ficha (no son recursos de build)

barrels/trend-core/   # clasificador + motor de render, compartido por J, K y L
```

## Stack

- **Lenguaje:** Monkey C
- **SDK:** Connect IQ SDK + SDK Manager
- **IDE:** VS Code + extensión Monkey C
- **Target:** Edge 830 (Connect IQ 3.3.6) y 840 como referencia; el manifiesto lista **13 Edge** compatibles (CIQ ≥ 3.3). Se compila contra 3.3 como mínimo común, y **siempre contra los 17 targets** (`monkeyc -e`), porque un error puede romper solo en un device.

## Convenciones

- **Tests obligatorios:** toda la lógica de cálculo o formato vive en **módulos puros** (sin `Dc`, sin `Activity.Info`, sin estado de device) con unit tests `(:test)` de `Toybox.Test`, que el compilador excluye del release. La View queda como wrapper fino. Patrón de referencia: `apps/a-activity-timer/source/TimeFormat*.mc`. Criterio de aceptación: **los tests en verde antes de la validación visual**.
- **Versionado por app:** cada app lleva su propio `store/RELEASES.md` (la versión se tipea a mano en el portal, no vive en el paquete). Tags namespaced `<app>/vX.Y.Z`, solo en releases de producción.
- **Documentación:** el `README.md`, la spec maestra y las specs por app se actualizan **en el mismo turno** en que se toma la decisión que las afecta.

Las reglas completas de trabajo, release y plataforma están en [`CLAUDE.md`](CLAUDE.md).

## Contacto

Consultas y feedback de las apps en la Connect IQ Store: **el.soldador.garmin@gmail.com** (es el email de contacto cargado en la ficha del store; no es el email personal ni el de git del repo).
