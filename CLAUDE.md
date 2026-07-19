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
- **Assets de la tienda por app → `apps/<app>/store/`:** ahí van los assets del submission al portal de Connect IQ (NO son recursos de build, no van en `resources/`): `store-icon-500.png` (500×500, fondo gris sólido, para la ficha), `icon-master-1024.png` (master del ícono, transparencia real, para regenerar), y capturas (`*.png`). Se generan con Pillow en un venv fuera del repo y se dejan versionados acá.

## Flujo de release y publicación (DECIDIDO y EJECUTADO 2026-07-19)

- **Testeo (diario):** simulador (F5) + sideload del `.prg` por OpenMTP → **no dependen del `id` ni de la store**, andan con cualquier id.
- **`.iq` de subida a la store:** se genera con **"Monkey C: Export Project"** (VS Code) — empaqueta los 13 devices y lo firma con la developer key. Distinto del `.prg` de F5 (debug, por device).
- **Beta (actual):** el `id` del `manifest.xml` en `main` es `953a28119edc4511b09dca2366738f5e`. Se sube al portal como beta (serie de tags `v0.1.x`).
- **Producción — Opción A elegida (rama `release` permanente + tags):**
  - `main` = id **beta**, desarrollo diario.
  - **Una sola** rama `release` (permanente, **NO** una por versión) que sale de `main` con **un** commit que cambia el `id` al de **producción**. Las versiones son **tags sobre `release`** (el tag, no la rama, es el release reproducible).
  - Cada release: `git checkout release && git merge main` (el id de prod queda sin conflicto — solo cambió de un lado) → "Export Project" desde `release` → `git tag vX.Y.Z`.
  - **Regla de oro:** desarrollar SIEMPRE en `main`; solo mergear **`main→release`, NUNCA al revés**.
  - El **id de producción** (rama `release`) es **`90f54fc135bd444f966d9b0c69849851`** — generado 2026-07-19 con `uuidgen | tr -d '-' | tr 'A-Z' 'a-z'`, aplicado a mano en el `manifest.xml` de `release`; primer tag de prod **`v0.1.7`**. El id **beta** sigue siendo `953a28119edc4511b09dca2366738f5e` en `main`. **Nunca cambiar estos ids** (cada uno es una app distinta en la store).
  - **Contacto de la ficha del store:** `el.soldador.garmin@gmail.com` — email dedicado cargado en el portal (NO el personal `maxicombina@gmail.com` ni el de git del repo).
  - La **developer key es la misma** para ambos ids (`~/garmin-dev/developer_key`); `TEST_MODE=false` antes de todo build de release.
  - ⚠️ **No tocar el `id` con el editor visual del manifest** (reescribe/reformatea el XML — ya borró `spa` una vez); editarlo **a mano**, o el merge `main→release` dará conflicto.
- **Por qué Opción A:** durabilidad del id + cero swapping por release. Descartadas: (0) un solo id en `main` (se quiere conservar el canal beta-store); (B) branch descartable al releasear (el id "se sentía perdido", aunque igual se anota acá).

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
- **Fase 0 (2026-07-18) — Opción A, data field de tiempo de actividad — IMPLEMENTADO y corriendo en el simulador:** `apps/a-activity-timer/` (proyecto CIQ completo: manifest datafield edge830+edge840, App+View, resources, ícono placeholder). `ActivityTimerView.mc` tiene la lógica de la SPEC: formato adaptativo con 3 niveles (uniforme H:MM:SS solo en celdas grandes vía `UNIFORM_MAX_COUNT`; compuesto H:MM + `:SS` volado; H:MM pelado), caché, colores por tema, atenuado en pausa, y `TEST_MODE` (reloj rápido para el simulador). **Label bilingüe:** base `resources/`="Timer" (inglés+fallback), `resources-spa/`="Tiempo"; app name "Activity Timer"/"Tiempo de Actividad"; `spa` declarado en el manifest. Documento explicativo del código: `apps/a-activity-timer/docs/code-walkthrough.html` (+ artifact). **No compilado por el asistente** (no puede); se corre con F5. **Pendientes antes de publicar:** checklist en SPEC §13 (ícono real, tipos de actividad, compatibilidad con otros Edge, `TEST_MODE=false`, prueba en device, tabla de medición §11.1).
- **Fase 0 COMPLETADA en device real (2026-07-19), tags `v0.1.0`–`v0.1.5`:** afinado pixel-perfect contra el campo nativo en el Edge 840 del usuario. Fuentes del sistema (`FONT_SYSTEM_NUMBER_*` dígitos, `FONT_GLANCE` label), centrado por ascent/descent + nudges (aprendizajes generales en spec maestra §3.4; detalle en SPEC §5.3/6.2/6.7/11.1). Ícono real (cronómetro) en los 5 tamaños; 13 devices en el manifest. Subida a la IQ Store **solo como beta** (v0.1.x; el autor la instala vía `apps.garmin.com` + Connect Mobile). **NO publicada:** el portal exige subirla como app nueva con **otro ID de app** para pasarla a producción. Sideload rápido por **OpenMTP** (el 840 es MTP, no monta en Finder). Atraso visual ~1 s vs nativo: aceptado. **Exclusión de hooks de debug del release — HECHA, en `main` y VERIFICADA (2026-07-19), commit `4fb3964` (pusheado, SIN tag):** reaplicada limpia sobre `main` (la rama `refactor/exclude-debug-hooks-from-release` había quedado atrasada respecto del trabajo de fuentes verificado en device, así que se descartó en vez de mergear; la rama LOCAL y su worktree se borraron; **la rama REMOTA también se borró el 2026-07-19**). Esquema `const false` plano + `(:debug)`/`(:release)` documentado en SPEC §13. Build de RELEASE verificado en el simulador (compila sin errores/warnings). **Render VALIDADO en las 6 resoluciones del manifest (2026-07-19):** los 13 devices colapsan en 6 pantallas — 246×322 (530/540/830/840), 240×320 (edgemtb), 240×400 (edgeexplore2), 282×470 (1030/1030plus/1030bontrager/1040), 420×600 (550/850), 480×800 (1050) — todas aceptadas; el layout dinámico (`getWidth`/`getHeight` + fuente por medición) y `LABEL_MIN_H=60` se sostienen. **Matiz observado en 240×400 (edgeexplore2):** en layouts densos (celdas angostas, ~7 campos) NO muestra el `:SS` volado → cae al **nivel 3 de la escalera (`H:MM` pelado, segundos descartados)**, lo cual es el diseño intencional (prioriza legibilidad de H:MM). Aceptado. Pendiente de confirmar si el umbral de ancho del compuesto es demasiado conservador (caería a pelado antes de tiempo) — no bloqueante.

- **v0.1.6 (2026-07-19) — iconito inline + assets del store (commit + tag `v0.1.6`):**
  1. **Iconito de cronómetro junto al label** en el data field: primitivas `dc` en el color de frente (theme-aware, se atenúa en pausa, sin PNG), a la izquierda del texto, tamaño relativo al ascent. Geometría **cacheada** (`computeLabelLayout`, recalcula solo si cambia `w`/`h`/`mLabel`) → cero medición por tick. Aguja afinada (más larga/gruesa) tras feedback. Detalle en SPEC §8. Validado en simulador (las capturas lo muestran).
  2. **Launcher icons REHECHOS:** cronómetro **plano** dibujado con Pillow, legible a 35px (el glossy reducido quedaba una mancha borrosa). 5 tamaños (35/36/40/56/68) en `resources[-device]/drawables/`. Transparente, azul `#0070F0` + botones amarillo/rojo.
  3. **Assets del store en `apps/a-activity-timer/store/`:** `store-icon-500.png` (500×500, gris claro sólido) regenerado desde el nuevo **master analógico** `icon-master-1024.png` (transparencia real — el PNG de Gemini traía un **damero horneado** que hubo que remover por flood-fill). 6 capturas 482×232: `activity-timer-{1,2,3}.png` (fondo blanco/día) + `-inv` (fondo negro/noche).

**Pendientes:**
1. **Submit de producción — EN CURSO (2026-07-19):** rama `release` **creada** con el id de prod nuevo (`90f54fc1…`), tag **`v0.1.7`**, pusheada. **Falta (lo hace el autor):** exportar el `.iq` desde la rama `release` ("Monkey C: Export Project") y subirlo al portal como **app NUEVA** (id nuevo) + cargar los textos de la ficha (descripción, categoría, capturas — hay ayuda pendiente con los textos).
2. **Ficha del store:** falta descripción y categoría (nombre bilingüe ✅, capturas ✅).
3. Menor/no bloqueante: ¿el umbral de ancho del compuesto es demasiado conservador en 240×400? (cae a `H:MM` pelado en celdas densas).
