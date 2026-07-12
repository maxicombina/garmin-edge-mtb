# CLAUDE.md — garmin-edge-mtb

## Qué es este proyecto

Apps Connect IQ para **Garmin Edge 830/840** orientadas a MTB (XC, senderos técnicos). Proyecto **personal** de `maxicombina`

## Fuente de verdad

**`GARMIN_MTB_SPEC.md`** — leerla ANTES de escribir código. Contiene:

- Hardware del usuario y restricciones de plataforma (sección 2–3).
- Las opciones de producto A–H con su estado (sección 4).
- **Fórmulas y coeficientes ya verificados contra fuentes** (Opción H, sección 3.2): NO "corregirlos" de memoria — si algo parece mal, verificar contra fuentes primero.
- Roadmap (sección 5) y preguntas abiertas (sección 9).

Cuando se tome una decisión de diseño en conversación, **actualizar la spec** en el mismo turno (las decisiones se anotan en la pregunta abierta correspondiente o en la opción afectada).

## Idioma

- **Con el usuario:** castellano, siempre.
- **Código, comentarios, nombres, mensajes de commit:** inglés, siempre.

## Stack y targets

- **Lenguaje:** Monkey C (VM + GC, tipado dinámico — parecido a Java/JS, no a C).
- **Toolchain:** Connect IQ SDK + SDK Manager, VS Code con la extensión oficial "Monkey C", simulador del SDK.
- **Dispositivos:** `edge830` + `edge840` en el manifiesto desde el día 1.
- **API level:** compilar contra **CIQ 3.3** (el 830 llega a 3.3.6; es el mínimo común). No usar APIs 4.x/5.x.

## Restricciones técnicas que no hay que olvidar

- Data fields: `compute()` corre 1×/s; memoria de decenas de KB → cálculos incrementales, buffers acotados, nada de reprocesar históricos.
- El render debe adaptarse al tamaño del campo (celda pequeña → 1 valor grande).
- Sin internet/backend en v1: todo on-device.
- Sensores del usuario: FC, velocidad, cadencia. **Sin potenciómetro** — ninguna feature puede asumir potencia.
- Grit/Flow/Stamina/saltos nativos de Garmin **no están expuestos** a Connect IQ.

## Reglas duras

- **NUNCA** commitear la developer key (`*.der`, `*.pem`) — el `.gitignore` ya la cubre; no relajarlo.
- **No commitear ni pushear sin que el usuario lo pida explícitamente.**
- Identidad git de este repo: `maxicombina@gmail.com` (ya configurada localmente). Jamás el email de trabajo.
- El remote es privado: `github.com/maxicombina/garmin-edge-mtb`. No hacerlo público ni compartir contenido fuera sin pedirlo.

## Estado actual

Fase 0 pendiente: esqueleto Connect IQ (manifiesto `edge830`+`edge840`, hello-world en simulador). Aún no hay código — solo especificación.
