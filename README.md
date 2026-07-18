# garmin-edge-mtb

Aplicaciones Connect IQ para **Garmin Edge** (830 / 840) orientadas a MTB (XC / senderos técnicos).

Proyecto personal, en fase de especificación. El objetivo es una familia de *data fields* y una *device app* que aporten métricas útiles durante la rodada, calculadas on-device y sin depender de potenciómetro.

## Estado

📋 **Especificación** — ver [`GARMIN_MTB_SPEC.md`](GARMIN_MTB_SPEC.md).

La spec define el contexto (hardware, plataforma, restricciones), 9 opciones de producto evaluadas (A–I) y un roadmap incremental. Resumen de las opciones:

| | Opción | Formato | Estado |
|---|---|---|---|
| A | Tiempo de actividad (formato adaptativo) | data field | **Fase 0 — spec lista** |
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
- **Target:** Edge 830 (Connect IQ 3.3.6) y Edge 840; se compila contra 3.3 como mínimo común.

## Desarrollo

En curso (Fase 0 — Opción A): data field de tiempo de actividad en [`apps/a-activity-timer/`](apps/a-activity-timer/) — esqueleto Connect IQ con manifiesto `edge830` + `edge840`, "hola mundo" en el simulador y, sobre él, el campo con formato adaptativo. Spec de implementación: [`apps/a-activity-timer/SPEC.md`](apps/a-activity-timer/SPEC.md).
