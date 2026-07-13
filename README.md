# garmin-edge-mtb

Aplicaciones Connect IQ para **Garmin Edge** (830 / 840) orientadas a MTB (XC / senderos técnicos).

Proyecto personal, en fase de especificación. El objetivo es una familia de *data fields* y una *device app* que aporten métricas útiles durante la rodada, calculadas on-device y sin depender de potenciómetro.

## Estado

📋 **Especificación** — ver [`GARMIN_MTB_SPEC.md`](GARMIN_MTB_SPEC.md).

La spec define el contexto (hardware, plataforma, restricciones), 8 opciones de producto evaluadas (A–H) y un roadmap incremental. Resumen de las opciones:

| | Opción | Formato | Estado |
|---|---|---|---|
| A | Pendiente + VAM | data field | idea |
| B | Descenso actual | data field | **MVP propuesto** |
| C | Cronómetro de tramos (enduro) | data field / device app | idea |
| D | Chunk meter (Grit casero, acelerómetro) | data field | idea |
| E | Detector de saltos / air time | data field | idea |
| F | Estimador de batería restante | data field | idea |
| G | Stamina casera (modelo de depósito por FC) | device app | idea |
| H | Test de subida (VO2max de campo + tracker de forma) | data field / device app | idea |

## Estructura

Cada opción vive como proyecto Connect IQ auto-contenido en `apps/<letra>-<slug>/` (p. ej. [`apps/a-grade-vam/`](apps/a-grade-vam/)), de modo que en el futuro pueda extraerse a su propio repositorio sin reestructurar.

## Stack

- **Lenguaje:** Monkey C
- **SDK:** Connect IQ SDK + SDK Manager
- **IDE:** VS Code + extensión Monkey C
- **Target:** Edge 830 (Connect IQ 3.3.6) y Edge 840; se compila contra 3.3 como mínimo común.

## Desarrollo

Pendiente (Fase 0): esqueleto del proyecto Connect IQ, manifiesto con `edge830` + `edge840`, y "hola mundo" en el simulador.
