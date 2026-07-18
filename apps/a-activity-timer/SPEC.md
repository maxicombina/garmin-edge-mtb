# SPEC — `a-activity-timer` (Opción A)

> Data field Connect IQ para Edge 830/840: **tiempo de actividad (timer)** con formato adaptativo al tamaño de la celda. Especificación de implementación, autocontenida: no requiere leer la conversación previa. La spec maestra del proyecto ([`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md)) da el contexto de producto.
>
> Todos los datos de plataforma citados aquí (nombres de API, tipos, niveles "Since", constantes) fueron **verificados contra la documentación oficial de Garmin el 2026-07-18** (sección 12). Lo que NO pudo verificarse en docs está marcado ⚠️ y tiene mandato explícito de medición en simulador (sección 11). No "corregir" nada de memoria.

---

## 1. Objetivo y rol (honesto)

Este campo **duplica a propósito** el campo nativo "Tiempo" (Timer) del Edge. Es el **proyecto tutorial** del autor (Fase 0 del roadmap) y su valor es 100 % de aprendizaje:

1. **Esqueleto completo de un proyecto Connect IQ** tipo data field: `manifest.xml`, `monkey.jungle`, AppBase, View, resources, compilación para dos targets, simulador y sideload.
2. **El ciclo `compute()` / `onUpdate()`** y sus reglas (asincronía, null-safety, presupuesto de memoria).
3. **Objetivo didáctico central: render adaptativo por medición de texto** — decidir formato y fuente según el espacio real de la celda (`dc.getWidth()/getHeight()` + `dc.getTextWidthInPixels()`), que es la base de todas las apps siguientes.

Ventaja de duplicar lo nativo: **validación 1:1** — se pone el campo propio al lado del nativo "Tiempo" en la misma pantalla y deben coincidir siempre.

## 2. Plataforma (verificado)

| Aspecto | Edge 830 | Edge 840 |
|---|---|---|
| ID de dispositivo (manifiesto) | `edge830` | `edge840` |
| API level máx | **3.3** (3.3.6) | 6.0 |
| Límite de memoria — app type `datafield` | 131 072 B (128 KB) | 131 072 B (128 KB) |
| Pantalla | 246 × 322 px, rectangular, color, táctil | idéntica |

- **Target de compilación: API 3.3.x** (mínimo común). ⚠️ `Graphics.fitTextToArea` existe pero es **API 4.2.1 → NO disponible**: el ajuste de texto se implementa a mano (y ese es precisamente el ejercicio).
- Tipo de app: `datafield`. **Sin permisos** (todo llega por `Activity.Info`).
- ⚠️ **No documentado:** el tamaño en píxeles de la celda en cada layout (1–10 campos). Se mide en Fase 0 (sección 11.1) y se anota aquí.

## 3. Arquitectura

**Clase base: `WatchUi.DataField` completo (API 1.0.0), NO `SimpleDataField`.** Motivo verificado: en `SimpleDataField` el sistema dibuja el valor (el `compute()` devuelve un valor y ahí termina el control); no hay manera de elegir formato ni fuente. Todo el punto de esta app es controlar el render → `DataField` con `onUpdate(dc)` propio.

```
a-activity-timer/
├── manifest.xml               # type=datafield; products: edge830, edge840; minApiLevel 3.3.0
├── monkey.jungle
├── source/
│   ├── ActivityTimerApp.mc    # AppBase: getInitialView() → [view]
│   └── ActivityTimerView.mc   # DataField: compute(), onUpdate(), lógica de formato/fuente
└── resources/
    └── strings/strings.xml    # app name + label "Timer"
```

Reglas de la clase (verificadas en la doc):
- `compute(info as Activity.Info)` se llama **~1×/s** y NO dibuja: solo actualiza miembros. ⚠️ La cadencia real de `onUpdate()` en el dispositivo no está documentada (reportes de foro: ~1–1,5 s) — no asumir sincronía con `compute()`.
- `compute()` y `onUpdate()` son **asíncronos sin orden garantizado** → inicializar TODOS los miembros en `initialize()`; `onUpdate()` debe poder dibujar antes del primer `compute()`.
- Tamaño de celda: `dc.getWidth()` / `dc.getHeight()` (API 1.0.0) en `onUpdate()` — el `Dc` ya viene recortado a la celda.
- Fondo: `getBackgroundColor()` (API 1.2.0) → `COLOR_WHITE` o `COLOR_BLACK`; elegir contraste en cada update.
- `getObscurityFlags()` (API 1.0.0; `OBSCURE_LEFT=1, TOP=2, RIGHT=4, BOTTOM=8`): en Edge (pantalla rectangular) será normalmente 0 → **ignorar en v1**.
- **Sin hooks de timer en v1** (`onTimerStart/Pause/...`, API 1.3.0): no hacen falta — `timerTime` es la única fuente de verdad y ya se congela/resetea solo. Anotado como aprendizaje para la Opción B. (Los `onTimerLap2/onTimerSplit*` son API 5.2.2 → fuera de alcance de la plataforma.)

## 4. Entradas — `Activity.Info` (tipos y nulabilidad verificados)

| Campo | Tipo | Unidad | Desde | Semántica |
|---|---|---|---|---|
| `timerTime` | `Number or Null` | **ms** | 1.0.0 | "The current Timer value" — el cronómetro de actividad. ⚠️ Que se congela en pausa/auto-pausa NO está en la doc del API (sí se infiere del manual del Edge: el timer se pausa con Auto Pause); confirmarlo en simulador (11.3). |
| `timerState` | `TimerState or Null` | — | 2.1.0 | `TIMER_STATE_OFF=0 / STOPPED=1 / PAUSED=2 / ON=3` (desde 2.1.0). Gatea el color (sección 6.4). |
| `elapsedTime` | `Number or Null` | ms | 1.0.0 | Tiempo total transcurrido (incluye pausas, según foros). **NO se usa en v1** — decisión de producto: se muestra el timer. |

**Regla dura: ambos campos usados pueden ser null** (tipos declarados `or Null`; ⚠️ el valor exacto antes de arrancar la actividad — null vs 0 — no está documentado, medirlo en 11.3):
- `timerTime == null` → tratar como **0 ms** → se muestra `0:00` (aspecto del campo nativo antes de arrancar).
- `timerState == null` → tratar como `TIMER_STATE_OFF`.

## 5. Algoritmos

### 5.1 Descomposición del tiempo (en `compute()`, 1×/s)

```
ms      = (info.timerTime != null) ? info.timerTime : 0
totalS  = ms / 1000          // división entera de Numbers → trunca (floor)
hours   = totalS / 3600
minutes = (totalS % 3600) / 60
seconds = totalS % 60
```

- **Truncado, no redondeo** (el segundo 59 se muestra hasta que se cumple el 60). ⚠️ Si el nativo redondea distinto se notará en la validación 1:1 (11.3) — anotar el resultado aquí.
- Guardar en miembros: los strings formateados (5.2) y `timerState`. `compute()` no mide ni dibuja nada.

### 5.2 Formatos (decisión de producto, cerrada 2026-07-18)

| Condición | Formato | Ejemplo | Construcción (`Lang.format`, API 1.0.0 + `Number.format("%02d")`, API 1.0.0) |
|---|---|---|---|
| `hours == 0` — cualquier celda | `M:SS` | `0:00`, `5:07`, `59:59` | `Lang.format("$1$:$2$", [minutes, seconds.format("%02d")])` |
| `hours > 0` y la celda tiene espacio (5.3) | `H:MM:SS` | `1:00:00`, `10:23:45` | `Lang.format("$1$:$2$:$3$", [hours, minutes.format("%02d"), seconds.format("%02d")])` |
| `hours > 0` y la celda NO tiene espacio | `H:MM` | `1:00`, `10:23` | `Lang.format("$1$:$2$", [hours, minutes.format("%02d")])` |

- Horas y el primer campo de minutos **sin cero inicial** (como el nativo). Horas pueden tener 2+ dígitos (`10:23:45`): el algoritmo de ajuste lo absorbe midiendo, no contando caracteres.
- Ambigüedad conocida y aceptada: `1:23` puede leerse como 1 h 23 min (H:MM) o 1 min 23 s (M:SS). Con el label y el contexto (venías viendo `59:xx`) alcanza en v1; si molesta en la calle, anotar para v1.1 (sufijo "h" pequeño).
- En `compute()` se construyen los strings candidatos del estado actual: si `hours == 0`, solo `M:SS`; si `hours > 0`, `H:MM:SS` **y** `H:MM` (la elección final es de `onUpdate()`, que es quien conoce la celda).

### 5.3 Selección de formato y fuente (en `onUpdate(dc)`, con caché)

**Escalera de fuentes** (constantes API 1.0.0, de mayor a menor):

```
LADDER = [FONT_NUMBER_THAI_HOT (8), FONT_NUMBER_HOT (7), FONT_NUMBER_MEDIUM (6),
          FONT_NUMBER_MILD (5), FONT_MEDIUM (3), FONT_SMALL (2), FONT_TINY (1), FONT_XTINY (0)]
```

**Regla "la celda tiene espacio":** el formato `H:MM:SS` se usa si cabe en **alguna fuente numérica** (`FONT_NUMBER_*`, las cuatro primeras de la escalera — las diseñadas para valores de data field, legibles con guantes). Si `H:MM:SS` solo cabría en fuentes de texto (`FONT_MEDIUM` o menores) → la celda "no es completa" → formato `H:MM` y se re-recorre la escalera desde arriba.

**Anti-parpadeo — medir plantillas, no el string vivo:** para que la decisión no cambie de un segundo a otro (dígitos de distinto ancho podrían hacer que `1:11:11` quepa y `1:44:44` no → alternancia de formato dentro de la misma hora), la medición usa una **plantilla de anchura estable**: el string candidato con todos los dígitos reemplazados por `8` (p. ej. `8:88:88`, `88:88:88`, `8:88`). La plantilla solo cambia cuando cambia el **patrón de dígitos** (aparecen horas, 9→10 h, 9→10 min en `M:SS`…), nunca por el tick de segundos.

**Algoritmo completo de `onUpdate(dc)`:**

```
1. w = dc.getWidth(); h = dc.getHeight()
2. usableW = w − 2·PAD                       // PAD = 2 px
3. Zona de label (6.2): si h ≥ LABEL_MIN_H (inicial: 60 px) → labelH = altura de FONT_XTINY
   (dc.getFontHeight, API 1.0.0); valueH = h − labelH. Si no → labelH = 0; valueH = h.
4. Caché: si (w, h, plantillaLarga, plantillaCorta) == último cálculo → saltar a 7.
5. Si hours > 0:
     font = primera de LADDER con getTextWidthInPixels(plantilla("8:88:88"…), font) ≤ usableW
            y getFontHeight(font) ≤ valueH
     si font es FONT_NUMBER_* → formato = H:MM:SS
     si no → formato = H:MM; re-recorrer LADDER con plantilla("8:88" u "88:88" si horas ≥ 10) → font
   Si hours == 0:
     formato = M:SS; font = primera de LADDER que cumpla ancho y alto con plantilla("88:88" o "8:88")
6. Si ninguna fuente cumple (celda absurda): font = FONT_XTINY (se acepta clipping; los
   criterios de aceptación exigen que no ocurra en ningún layout real). Guardar caché.
7. Colores (6.4) → dc.setColor(fg, bg); dc.clear()
8. Si labelH > 0: drawText(w/2, 0, FONT_XTINY, label, TEXT_JUSTIFY_CENTER)
9. drawText(w/2, labelH + valueH/2, font, stringVivo del formato elegido,
            TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER)
```

- Constantes verificadas: `TEXT_JUSTIFY_RIGHT=0, CENTER=1, LEFT=2, VCENTER=4` (OR-eable con la horizontal), `drawText` API 1.0.0.
- **Invalidación de caché (por tupla, no por lista de casos):** se recalcula el paso 4 cuando cambia cualquier componente de la clave `(w, h, plantillaLarga, plantillaCorta)`. Así quedan cubiertos, sin enumerarlos a mano: cambio de tamaño de celda (el usuario edita el layout en marcha), 59:59→1:00:00 (aparece el formato largo), 9:59:59→10:00:00 y 9:59→10:00 (una plantilla se ensancha un dígito), y el paso a celda chica (`H:MM`/`8:88`). El tick normal de segundos no cambia ninguna plantilla → no invalida.
- Coste en régimen: `onUpdate()` hace 0 mediciones con caché válida; ante invalidación, ≤ 2 pasadas × 8 fuentes de `getTextWidthInPixels` — trivial a 1 Hz.

### 5.4 Estados y ciclo de vida

- **No hay estado propio que mantener**: `timerTime` ya se congela en pausa y se resetea al descartar/guardar. Sin buffers, sin hooks, sin `Application.Storage`.
- Actividad no iniciada o recién reseteada (`timerTime` null/0): muestra `0:00` atenuado (6.4).
- \> 24 h: `H:MM:SS`/`H:MM` siguen creciendo (`25:00:00`); sin manejo especial.

## 6. Render adaptativo — detalles

### 6.1 Filosofía
Una sola métrica, centrada, en la fuente más grande que quepa. Nada de layouts múltiples tipo FULL/HALF/SMALL (eso llega con la Opción B): aquí la adaptación es **continua** vía la escalera de fuentes + el cambio de formato.

### 6.2 Label
- String `"Timer"` (resource `strings.xml`; traducciones fuera de alcance v1), `FONT_XTINY`, centrado arriba.
- Se dibuja solo si `h ≥ LABEL_MIN_H` (**inicial: 60 px** — recalibrar con la tabla de medición 11.1 y anotar aquí el valor final).

### 6.3 Padding
`PAD = 2 px` por lado. Las celdas del Edge tienen separadores propios; no desperdiciar ancho.

### 6.4 Colores (según `getBackgroundColor()`, API 1.2.0)
| Estado | Fondo blanco | Fondo negro |
|---|---|---|
| `timerState == TIMER_STATE_ON` | `COLOR_BLACK` | `COLOR_WHITE` |
| Cualquier otro estado / null (parado, pausa, auto-pausa, pre-inicio) | `COLOR_DK_GRAY` | `COLOR_LT_GRAY` |

El atenuado enseña de un vistazo que el timer no corre (y de paso enseña `timerState`).

### 6.5 Presupuesto de allocations
- `compute()`: construye ≤ 4 strings/s (hasta 2 candidatos + 2 plantillas en el caso con horas) — aceptable, es la técnica estándar (los strings de Monkey C son inmutables; el GC absorbe 1×/s sin problema).
- `onUpdate()`: cero allocations con caché válida (solo lecturas de miembros y `drawText`); la plantilla se construye en `compute()` junto con los candidatos.

## 7. Settings

**No hay** (decisión de producto: solo timer, sin opciones). El mecanismo de settings se aprende en la Opción B.

## 8. Fuera de alcance v1 (anotado para después)

- `elapsedTime` (tiempo total con pausas) como métrica alternativa o setting.
- Sufijo desambiguador "h" en `H:MM`.
- Traducciones del label.
- Hooks de timer (`onTimerStart/...`, API 1.3.0) — innecesarios aquí; se aprenden en la B.
- FIT recording, alertas, táctil: nada de eso aplica a este campo.

## 9. Presupuesto y rendimiento

- Límite real: 128 KB. **Objetivo: < 32 KB en uso** (app trivial; medir en simulador, *File → View Memory*).
- Sin colecciones dinámicas; miembros escalares + un array fijo de 8 fuentes.

## 10. Criterios de aceptación

- [ ] Compila sin warnings con el SDK actual, targets `edge830` y `edge840`, `minApiLevel 3.3.0`.
- [ ] Sin actividad iniciada: muestra `0:00` atenuado; no crashea (null-safety de `timerTime`/`timerState`).
- [ ] Start → cuenta `0:01, 0:02…` en formato `M:SS` en **todos** los layouts del simulador (1 a 10 campos).
- [ ] **Transición 59:59 → 1:00:00** en celda grande (layout 1–2 campos): pasa a `H:MM:SS` sin parpadeo ni salto visual.
- [ ] **Transición 59:59 → 1:00** en celda chica (layout 8–10 campos): pasa a `H:MM`.
- [ ] **9:59:59 → 10:00:00**: el string se ensancha un dígito y la fuente/formato se re-selecciona correctamente (sin clipping).
- [ ] **Sin flapping**: con el timer en 1:XX:XX estable en una celda dada, el formato no alterna entre updates (verificar la caché por plantilla).
- [ ] Pausa manual y auto-pausa: el valor se congela y se atenúa; al reanudar recupera color y sigue. (Además responde la pregunta ⚠️: ¿`compute()` sigue llamándose en pausa?)
- [ ] Reset/guardar actividad: vuelve a `0:00` atenuado sin crash.
- [ ] **Validación 1:1**: junto al campo nativo "Tiempo" en la misma pantalla, coincide siempre (tolerancia 1 s de fase).
- [ ] Fondo blanco y fondo negro: contraste correcto en ambos temas.
- [ ] Los `:` se renderizan bien en todas las fuentes de la escalera (⚠️ glifos de `FONT_NUMBER_*` no documentados).
- [ ] Memoria en régimen < 32 KB en el simulador.
- [ ] La tabla 11.1 (tamaños de celda y alturas de fuente medidos) quedó rellenada en esta SPEC.

## 11. Plan de pruebas en simulador (y mediciones pendientes ⚠️)

### 11.1 Tabla de medición (rellenar en Fase 0 — es parte del entregable)
Con un `System.println` temporal en `onUpdate()`, anotar por layout del Edge 830: `dc.getWidth() × dc.getHeight()`, y una vez: `dc.getFontHeight()` de las 8 fuentes de la escalera. Con esos datos, recalibrar `LABEL_MIN_H` y validar la regla "fuente numérica mínima".

| Layout (campos) | Ancho × alto de celda (px) |
|---|---|
| 1 / 2 / 3 / … / 10 | *(medir)* |

### 11.2 Ciclo básico
Simulator → *Simulation → Activity Data*: start, correr > 1 h (el simulador permite acelerar/forzar valores; si no, editar el tiempo simulado), pausa, resume, stop, reset. Repetir en layouts 1, 2, 5 y 10 campos, y con perfil `edge840`.

### 11.3 Verificaciones ⚠️ pendientes de la sección 4/5 (anotar resultados AQUÍ)
1. ¿`timerTime` se congela en pausa y auto-pausa? (esperado: sí)
2. ¿`compute()` sigue llamándose con el timer en pausa? (esperado: sí — por eso se gatea el color por `timerState`, no por la cadencia)
3. Valor de `timerTime`/`timerState` antes de arrancar: ¿null o 0/OFF?
4. ¿El campo nativo "Tiempo" trunca o redondea los segundos? ¿Muestra `M:SS` antes de la hora?
5. ¿`FONT_NUMBER_*` del Edge 830 incluyen el glifo `:`? Alturas reales de cada fuente.

### 11.4 Validación 1:1
Pantalla con el campo propio + el nativo "Tiempo": correr 5 min con pausas → deben coincidir siempre.

## 12. Referencias (verificadas 2026-07-18)

- `Activity.Info` (timerTime, elapsedTime, timerState): https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html
- `Activity` (TIMER_STATE_*): https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity.html
- `WatchUi.DataField` / `SimpleDataField`: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html / SimpleDataField.html
- `Graphics.Dc` (getTextWidthInPixels, getFontHeight, drawText, getWidth/getHeight): https://developer.garmin.com/connect-iq/api-docs/Toybox/Graphics/Dc.html
- `Graphics` (FONT_*, TEXT_JUSTIFY_*, fitTextToArea=4.2.1): https://developer.garmin.com/connect-iq/api-docs/Toybox/Graphics.html
- `Lang.format` / `Number.format`: https://developer.garmin.com/connect-iq/api-docs/Toybox/Lang.html / Lang/Number.html
- Manual Edge 830 — data fields nativos (Timer/Elapsed Time) y Auto Pause: https://www8.garmin.com/manuals/webhelp/edge830/EN-US/GUID-53FC7978-187F-4E53-AA33-04853F86B05F.html
- Semántica timer vs elapsed en pausa (foro, ⚠️ no oficial): https://forums.garmin.com/developer/connect-iq/f/discussion/4731/sys-gettimer-vs-info-elapsedtime-in-compute-data-field
