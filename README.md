# garmin-edge-mtb

Aplicaciones Connect IQ para **Garmin Edge** (830 / 840) orientadas a MTB (XC / senderos técnicos).

Proyecto personal. El objetivo es una familia de *data fields* y una *device app* que aporten métricas útiles durante la rodada, calculadas on-device y sin depender de potenciómetro. La primera app (Opción A) ya está implementada, probada en un Edge real y publicada como **beta** en la Connect IQ Store; el resto está en especificación.

## Estado

🚴 **Opción A completada (Fase 0) y en beta**; el resto de las opciones, en especificación — ver [`GARMIN_MTB_SPEC.md`](GARMIN_MTB_SPEC.md).

La spec define el contexto (hardware, plataforma, restricciones), 9 opciones de producto evaluadas (A–I) y un roadmap incremental. Resumen de las opciones:

| | Opción | Formato | Estado |
|---|---|---|---|
| A | Tiempo de actividad (formato adaptativo) | data field | **✅ Fase 0 completada · beta `v0.1.6`** |
| B | Pendiente + VAM | data field | spec lista |
| C | Descenso actual | data field | **MVP propuesto** |
| D | Cronómetro de tramos (enduro) | data field / device app | idea |
| E | Chunk meter (Grit casero, acelerómetro) | data field | idea |
| F | Detector de saltos / air time | data field | idea |
| G | Estimador de batería restante | data field | idea |
| H | Stamina casera (modelo de depósito por FC) | device app | idea |
| I | Test de subida (VO2max de campo + tracker de forma) | data field / device app | idea |

## Estructura

Cada opción vive como proyecto Connect IQ auto-contenido en `apps/<letra>-<slug>/` (p. ej. [`apps/a-activity-timer/`](apps/a-activity-timer/)), de modo que en el futuro pueda extraerse a su propio repositorio sin reestructurar.

## Stack

- **Lenguaje:** Monkey C
- **SDK:** Connect IQ SDK + SDK Manager
- **IDE:** VS Code + extensión Monkey C
- **Target:** Edge 830 (Connect IQ 3.3.6) y 840 como referencia; el manifiesto lista **13 Edge** compatibles (CIQ ≥ 3.3). Se compila contra 3.3 como mínimo común.

## Desarrollo

**Fase 0 (Opción A) — completada:** data field de tiempo de actividad en [`apps/a-activity-timer/`](apps/a-activity-timer/), con formato adaptativo de 3 niveles (incluido el compuesto `H:MM` + `:SS` volado), iconito de cronómetro junto al label, fuentes del sistema afinadas pixel-perfect contra el campo nativo, y hooks de debug excluidos del build de release. Probado en un Edge 840 real y publicado como **beta** (`v0.1.6`). Spec de implementación: [`apps/a-activity-timer/SPEC.md`](apps/a-activity-timer/SPEC.md) · walkthrough del código: [`docs/code-walkthrough.html`](apps/a-activity-timer/docs/code-walkthrough.html).

Próximo: **Opción B** (pendiente + VAM), que ya tiene spec detallada.

## Contacto

Consultas y feedback de las apps en la Connect IQ Store: **el.soldador.garmin@gmail.com** (es el email de contacto cargado en la ficha del store; no es el email personal ni el de git del repo).
