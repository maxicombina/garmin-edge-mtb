# garmin-edge-mtb

Aplicaciones Connect IQ para **Garmin Edge** (830 / 840) orientadas a MTB (XC / senderos técnicos).

Proyecto personal. El objetivo es una familia de *data fields* y una *device app* que aporten métricas útiles durante la rodada, calculadas on-device y sin depender de potenciómetro. Hay **dos apps publicadas** en la Connect IQ Store, una tercera implementada sin publicar, y el resto en especificación.

## Estado

🚴 **Dos apps en producción** (Opciones A y J) · **una implementada y en validación** (Opción B) · el resto, en especificación — ver [`GARMIN_MTB_SPEC.md`](GARMIN_MTB_SPEC.md).

La spec define el contexto (hardware, plataforma, restricciones), **10 opciones de producto evaluadas (A–J)** y un roadmap incremental. Resumen:

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
| J | Flecha de tendencia estilo Cateye (actual vs. referencia) | data field | **✅ publicada · prod `v0.1.0` · beta `v0.2.1`** |

## Las apps

### A — `a-activity-timer` · publicada

Tiempo de actividad con **formato adaptativo de 3 niveles** (incluido el compuesto `H:MM` + `:SS` volado, que resuelve la ambigüedad de leer `1:23`), iconito de cronómetro junto al label dibujado con primitivas, y fuentes del sistema afinadas pixel-perfect contra el campo nativo en un Edge 840 real.

[`SPEC.md`](apps/a-activity-timer/SPEC.md) · [walkthrough del código](apps/a-activity-timer/docs/code-walkthrough.html) · [`RELEASES.md`](apps/a-activity-timer/store/RELEASES.md)

### B — `b-grade-vam` · implementada, sin publicar

Pendiente y VAM **juntas en una celda**, reconstruidas desde cero con el altímetro barométrico porque Connect IQ no expone las nativas. Ocho módulos puros, filtro de outliers con re-seed, histéresis de display y zonas de color. Falta el rediseño de íconos y la validación en device.

[`SPEC.md`](apps/b-grade-vam/SPEC.md) · [walkthrough del código](apps/b-grade-vam/docs/code-walkthrough.html) · [`RELEASES.md`](apps/b-grade-vam/store/RELEASES.md)

### J — `j-trend-arrow` · publicada

La flechita de los ciclocomputadores Cateye de los 90: velocidad actual en grande con **↑/↓ al lado** según vayas por encima o por debajo de tu referencia, y sin flecha cuando estás en la media. Desde la `v0.2.x` la referencia es **configurable**: el promedio real de la salida o una velocidad objetivo fija. La flecha usa el **glifo nativo si el device lo tiene y una primitiva dibujada si no**, decidido midiendo en el propio device.

[`SPEC.md`](apps/j-trend-arrow/SPEC.md) · [walkthrough del código](apps/j-trend-arrow/docs/code-walkthrough.html) · [`RELEASES.md`](apps/j-trend-arrow/store/RELEASES.md)

## Estructura

Cada opción vive como proyecto Connect IQ auto-contenido en `apps/<letra>-<slug>/`, de modo que en el futuro pueda extraerse a su propio repositorio sin reestructurar. Nada se comparte entre apps salvo documentación: si hace falta código común, se decide explícitamente (¿copiar? ¿extraer?).

```
apps/<app>/
├── manifest.xml · monkey.jungle
├── source/        # módulos puros + su *Test.mc, App y View
├── resources[-spa]/
├── docs/          # walkthrough del código en HTML
└── store/         # RELEASES.md, íconos y assets de la ficha (no son recursos de build)
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
