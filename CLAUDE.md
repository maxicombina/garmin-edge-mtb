# CLAUDE.md — garmin-edge-mtb

## Qué es este proyecto

Apps Connect IQ para **Garmin Edge 830/840** orientadas a MTB (XC, senderos técnicos). Proyecto **personal** de `maxicombina`

## Fuente de verdad

**`GARMIN_MTB_SPEC.md`** — leerla ANTES de escribir código. Contiene:

- Hardware del usuario y restricciones de plataforma (sección 2–3).
- Las opciones de producto A–I con su estado (sección 4).
- **Fórmulas y coeficientes ya verificados contra fuentes** (Opción I, sección 3.2): NO "corregirlos" de memoria — si algo parece mal, verificar contra fuentes primero.
- Roadmap (sección 5) y preguntas abiertas (sección 9).

## Persistencia de decisiones (regla dura)

Toda decisión tomada en conversación se escribe **en el mismo turno** en que se toma — nunca "queda en el chat":

- **Producto / diseño / fisiología / fórmulas** → `GARMIN_MTB_SPEC.md` (en la opción afectada, o resolviendo la pregunta abierta correspondiente).
- **Convenciones de trabajo, estructura del repo, tooling, proceso** → este `CLAUDE.md`.
- **Estado del proyecto** (fase alcanzada, qué está hecho/pendiente) → sección "Estado actual" de este `CLAUDE.md`.
- Si el asistente dispone de **memoria persistente de sesión**, reflejar también ahí los cambios de estado y decisiones relevantes.

## Idioma

- **Con el usuario:** castellano, siempre.
- **Código, comentarios, nombres, mensajes de commit:** inglés, siempre.

## Stack y targets

- **Lenguaje:** Monkey C (VM + GC, tipado dinámico — parecido a Java/JS, no a C).
- **Toolchain:** Connect IQ SDK + SDK Manager, VS Code con la extensión oficial "Monkey C", simulador del SDK.
- **Dispositivos:** `edge830` + `edge840` en el manifiesto desde el día 1.
- **API level:** compilar contra **CIQ 3.3** (el 830 llega a 3.3.6; es el mínimo común). No usar APIs 4.x/5.x.

## Estructura del repo

- **Monorepo de apps:** cada opción de la spec vive en `apps/<letra>-<slug>/` como proyecto Connect IQ **completo y auto-contenido** (su propio `manifest.xml`, `monkey.jungle`, `source/`, `resources/`). Motivo: en el futuro cada app podría extraerse a su propio repo sin cirugía.
- **Nombres acordados** (crear el directorio solo cuando se empiece esa opción): `a-activity-timer`, `b-grade-vam`, `c-descent-tracker`, `d-stage-timer`, `e-chunk-meter`, `f-jump-airtime`, `g-battery-forecast`, `h-stamina`, `i-climb-test`. (Nomenclatura desplazada el 2026-07-18: el timer tutorial pasó a ser la Opción A y las antiguas A–H pasaron a B–I.)
- **Nada compartido entre apps** salvo documentación. Si surge código común, decidir explícitamente (¿copiar? ¿extraer?) recordando la posible separación en repos.

## Modo de trabajo con el usuario

- **El usuario ejecuta, el asistente guía.** Para todo lo que sea setup, tooling, configuración de su máquina o cuentas (instalaciones, keys, settings de apps, movimientos de archivos fuera del repo): dar instrucciones claras paso a paso y **no ejecutarlo por él** — el objetivo es que aprenda. Verificar el resultado (lectura) está bien. Las ediciones de archivos *dentro del repo* y los commits que él pida siguen igual que siempre.

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
- **Proyecto 100 % personal e independiente:** ninguna mención al empleador del usuario ni a sus proyectos/repos en NINGÚN archivo de este repo — ni en código, docs, mensajes de commit ni metadatos.
- **Mensajes de commit — atribución de IA:** se permite el trailer `Co-Authored-By: Anthropic <noreply@anthropic.com>`. **NUNCA el nombre del modelo** (ni Fable, ni Opus, ni ningún otro) en ninguna parte del mensaje.
- El remote es privado: `github.com/maxicombina/garmin-edge-mtb`. No hacerlo público ni compartir contenido fuera sin pedirlo.

## Estado actual

- Spec maestra completa (opciones A–I). Estructura `apps/` creada.
- **Spec detallada de la Opción B escrita y verificada contra docs oficiales:** `apps/b-grade-vam/SPEC.md` (API names, límite 128 KB, VAM nativa del 830 descubierta, algoritmos, settings, criterios de aceptación).
- **Toolchain del usuario COMPLETO (2026-07-13):** SDK Manager + SDK 9.2.0 activo + perfiles de dispositivo + VS Code con extensión Monkey C + Temurin (Java) + developer key en `~/garmin-dev/developer_key` (fuera del repo, chmod 600; setting `monkeyC.developerKeyPath` apunta ahí).
- **Fase 0 redefinida (2026-07-18) — Opción A, data field de tiempo de actividad:** vive en `apps/a-activity-timer/`; spec detallada escrita y verificada contra docs oficiales (`apps/a-activity-timer/SPEC.md`). El esqueleto/hello-world y la implementación se hacen ahí. Pendiente: implementar.
