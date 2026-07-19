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

Ventaja de duplicar lo nativo: **validación 1:1 del valor** — se pone el campo propio al lado del nativo "Tiempo" en la misma pantalla y el **tiempo** debe coincidir siempre (tolerancia 1 s de fase). El **aspecto** puede diferir a propósito: en celda no completa y ≥1h nuestro formato compuesto (5.2, nivel 2) invierte la jerarquía del nativo (segundos chicos volados en vez de hora chica volada).

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

Para `hours > 0` hay **tres niveles** según el espacio de la celda (5.3), de más a menos ancho; `hours == 0` es un único formato.

| # | Condición | Formato | Ejemplo | Notas de construcción |
|---|---|---|---|---|
| — | `hours == 0` — cualquier celda | `M:SS` (una pieza) | `0:00`, `5:07`, `59:59` | `Lang.format("$1$:$2$", [minutes, seconds.format("%02d")])` |
| 1 | `hours > 0`, `H:MM:SS` entra **a lo ancho** en la misma fuente que usa `H:MM` (celda ancha) | `H:MM:SS` (una pieza, tamaño uniforme) | `1:00:00`, `10:23:45` | `Lang.format("$1$:$2$:$3$", [hours, minutes.format("%02d"), seconds.format("%02d")])` |
| 2 | `hours > 0`, no entra el nivel 1 pero sí el compuesto | **`H:MM` grande + `:SS` chico volado** (dos piezas) | `1:23`＋`:45` | Pieza grande `Lang.format("$1$:$2$", [hours, minutes.format("%02d")])`; pieza chica `Lang.format(":$1$", [seconds.format("%02d")])`. Render en 6.6. |
| 3 | `hours > 0`, no entra ni el compuesto | `H:MM` (una pieza) | `1:00`, `10:23` | `Lang.format("$1$:$2$", [hours, minutes.format("%02d")])` |

- **Formato compuesto (nivel 2), decisión de producto cerrada 2026-07-18:** los segundos se dibujan en fuente más chica y **volados** (superíndice) a la derecha del `H:MM` grande, con `:` adelante (`1:23` grande, `:45` chico y arriba). Es la mejor jerarquía para un campo que se mira de reojo: `H:MM` es lo que importa, los segundos son el detalle fino. Origen: el 840 nativo hace lo inverso (hora chica volada + `MM:SS` grande) y la hora chica se lee mal → invertimos la jerarquía (ver observación en 11.3).
- **La ambigüedad `H:MM` vs `M:SS` se resuelve** en el nivel 2: `1:23` grande + `:45` chico es inequívocamente 1 h 23 min 45 s, no se confunde con 1 min 23 s. Solo queda en el nivel 3 (celda tan chica que se tiran los segundos); ahí el label y el contexto (venías viendo `59:xx`) alcanzan.
- Horas y el primer campo de minutos **sin cero inicial** (como el nativo). Horas pueden tener 2+ dígitos (`10:23:45`): el algoritmo de ajuste lo absorbe midiendo, no contando caracteres.
- En `compute()` se construyen los strings candidatos del estado actual: si `hours == 0`, solo `M:SS`; si `hours > 0`, `H:MM:SS`, `H:MM` **y** `:SS` (la pieza chica del nivel 2). La elección de nivel es de `onUpdate()`, que es quien conoce la celda.
- **Orden de implementación:** primero el camino de una sola pieza (niveles 1 y 3 + `M:SS`) con la selección de fuente andando en el simulador; **después** el nivel 2 compuesto (render de dos piezas, 6.6). El nivel 2 es el diseño objetivo v1, pero se agrega en una segunda iteración sobre una base ya verificada.

### 5.3 Selección de formato y fuente (en `onUpdate(dc)`, con caché)

**Escalera de fuentes** (constantes API 1.0.0, de mayor a menor):

```
LADDER = [FONT_SYSTEM_NUMBER_THAI_HOT, FONT_SYSTEM_NUMBER_HOT, FONT_SYSTEM_NUMBER_MEDIUM,
          FONT_SYSTEM_NUMBER_MILD, FONT_MEDIUM, FONT_SMALL, FONT_TINY, FONT_XTINY]
```

- **Fuentes del SISTEMA (decisión en device, 2026-07-19):** las cuatro numéricas son `FONT_SYSTEM_NUMBER_*` porque su trazo **iguala el del campo nativo**; las `FONT_NUMBER_*` "de app" miden lo mismo (alturas en 11.1) pero el estilo difiere. Verificado a ojo contra el campo nativo en el Edge 840 real.

**Regla de espacio (`hours > 0`) — el discriminante es el ANCHO, no el tamaño de fuente:**
0. `big` = la **fuente más grande de la escalera que entra `H:MM`** (por ancho y alto). Es el tamaño natural del valor para esa celda.
1. **`H:MM:SS` uniforme** si el `H:MM:SS` completo **también entra a lo ancho a esa misma fuente `big`**. Consecuencia buscada: un campo **ancho pero bajo** (fuente chica por el alto) muestra igual el uniforme, porque el ancho alcanza. Corrección 2026-07-18: primero se ató mal al tamaño de fuente (el compuesto aparecía en campos anchos, no deseado); el discriminante correcto es el ancho.
2. Si el `H:MM:SS` **no** entra a lo ancho a `big` (celda angosta) → **compuesto**: `H:MM` a `big` + `:SS` chico volado. Cabe si `ancho("8:88", big) + GAP_SUP + ancho(":88", fuenteChica) ≤ usableW`. La `fuenteChica` es la mayor de la escalera con `altura ≤ round(SUP_RATIO · altura(big))`. Constantes: `GAP_SUP = 2 px`, `SUP_RATIO = 0.6` (afinables en simulador).
3. Si ni el compuesto entra → **`H:MM` pelado** a `big`.

**Anti-parpadeo — medir plantillas, no el string vivo:** para que la decisión no cambie de un segundo a otro (dígitos de distinto ancho podrían hacer que `1:11:11` quepa y `1:44:44` no → alternancia de formato dentro de la misma hora), la medición usa una **plantilla de anchura estable**: el string candidato con todos los dígitos reemplazados por `8` (p. ej. `8:88:88`, `88:88:88`, `8:88`). La plantilla solo cambia cuando cambia el **patrón de dígitos** (aparecen horas, 9→10 h, 9→10 min en `M:SS`…), nunca por el tick de segundos.

**Algoritmo completo de `onUpdate(dc)`:**

```
1. w = dc.getWidth(); h = dc.getHeight()
2. usableW = w − 2·PAD                       // PAD = 2 px
3. Zona de label (6.2): si h ≥ LABEL_MIN_H (inicial: 60 px) → labelH = altura de FONT_XTINY
   (dc.getFontHeight, API 1.0.0); valueH = h − labelH. Si no → labelH = 0; valueH = h.
4. Caché: si (w, h, plantillaLarga, plantillaCorta) == último cálculo → saltar a 7.
5. Elegir NIVEL y fuente(s):
   Si hours == 0:
     nivel = "M:SS"; font = primera de LADDER con ancho(plantillaCorta) ≤ usableW y alto ≤ valueH
   Si hours > 0:
     // fuente de H:MM: la mayor que entra por ancho y alto (define el tamaño del valor)
     big = primera de LADDER con ancho(plantillaCorta) ≤ usableW y getFontHeight ≤ valueH
           (si ninguna cumple → big = FONT_XTINY, se acepta clipping)
     // Nivel 1 — uniforme si el H:MM:SS completo TAMBIÉN entra a lo ancho a esa misma `big`
     si getTextWidthInPixels(plantillaLarga "8:88:88"…, big) ≤ usableW → nivel = 1; font = big
     si no:
       // Nivel 2 — H:MM a `big` + :SS chico volado
       small = mayor de LADDER con getFontHeight(small) ≤ round(SUP_RATIO · getFontHeight(big))
       wComp = getTextWidthInPixels(plantillaCorta, big) + GAP_SUP + getTextWidthInPixels(":88", small)
       si wComp ≤ usableW → nivel = 2; fontBig = big; fontSmall = small
       si no → nivel = 3; font = big   // Nivel 3 — H:MM pelado
6. Guardar (nivel, fuentes) en caché.
7. Colores (6.4) → dc.setColor(fg, bg); dc.clear()
8. Si labelH > 0: drawText(w/2, 0, FONT_XTINY, label, TEXT_JUSTIFY_CENTER)
9. Dibujar el valor centrado en la zona [labelH … h]:
     nivel 1 / 3 / M:SS  → drawText(w/2, labelH + valueH/2, font, stringVivo,
                                    TEXT_JUSTIFY_CENTER | TEXT_JUSTIFY_VCENTER)
     nivel 2 (compuesto) → dos piezas, ver 6.6
```

- Constantes verificadas: `TEXT_JUSTIFY_RIGHT=0, CENTER=1, LEFT=2, VCENTER=4` (OR-eable con la horizontal), `drawText` API 1.0.0.
- **Invalidación de caché (por tupla, no por lista de casos):** se recalcula el paso 4 cuando cambia cualquier componente de la clave `(w, h, plantillaLarga, plantillaCorta)`. Así quedan cubiertos, sin enumerarlos a mano: cambio de tamaño de celda (el usuario edita el layout en marcha), 59:59→1:00:00 (aparece el formato largo), 9:59:59→10:00:00 y 9:59→10:00 (una plantilla se ensancha un dígito), y el paso a celda chica (`H:MM`/`8:88`). El tick normal de segundos no cambia ninguna plantilla → no invalida.
- Coste en régimen: `onUpdate()` hace 0 mediciones con caché válida; ante invalidación, ≤ 3 niveles × 8 fuentes de `getTextWidthInPixels` (el nivel 2 suma 1 medición de `getFontHeight` por fuente para elegir `fontSmall`) — trivial a 1 Hz.

### 5.4 Estados y ciclo de vida

- **No hay estado propio que mantener**: `timerTime` ya se congela en pausa y se resetea al descartar/guardar. Sin buffers, sin hooks, sin `Application.Storage`.
- Actividad no iniciada o recién reseteada (`timerTime` null/0): muestra `0:00` atenuado (6.4).
- \> 24 h: `H:MM:SS`/`H:MM` siguen creciendo (`25:00:00`); sin manejo especial.

## 6. Render adaptativo — detalles

### 6.1 Filosofía
Una sola métrica, centrada, en la fuente más grande que quepa. Nada de layouts múltiples tipo FULL/HALF/SMALL (eso llega con la Opción B): aquí la adaptación es **continua** vía la escalera de fuentes + el cambio de formato.

### 6.2 Label
- String del resource `FieldLabel` en **MAYÚSCULAS**, fuente **`FONT_GLANCE`** (la del sistema que iguala el estilo del label nativo; decidido en device 2026-07-19 tras probar `FONT_MEDIUM` y `FONT_SYSTEM_MEDIUM`), centrada, con **margen superior de 4 px**. Se reserva solo su **ascent** (lo visible): el descendente vacío se solapa con el aire superior del valor y deja más lugar al número. Fuente fija: no escala con la celda (decisión — el target es la celda de 2 campos). **Localizado:** base `resources/` = `"Timer"` (inglés + fallback), `resources-spa/` = `"Tiempo"`. El idioma `spa` está declarado en `<iq:languages>` del manifest (si no, la carpeta se ignora). El `.mc` no cambia: `loadResource()` resuelve el idioma del dispositivo solo.
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
- `compute()`: construye ≤ 5 strings/s (con horas: 3 candidatos `H:MM:SS`/`H:MM`/`:SS` + 2 plantillas) — aceptable, es la técnica estándar (los strings de Monkey C son inmutables; el GC absorbe 1×/s sin problema).
- `onUpdate()`: cero allocations con caché válida (solo lecturas de miembros y `drawText`); las plantillas se construyen en `compute()` junto con los candidatos.

### 6.6 Render del formato compuesto (nivel 2)

Dos `drawText` con `fontBig` (para `H:MM`) y `fontSmall` (para `:SS`), con los segundos **volados** (top-alineados con el techo del `H:MM`):

```
wBig   = getTextWidthInPixels(H:MM vivo, fontBig)
wSmall = getTextWidthInPixels(:SS vivo, fontSmall)
W      = wBig + GAP_SUP + wSmall                 // ancho total del compuesto
leftX  = (w − W) / 2                             // centrado horizontal en la celda
cY     = labelH + valueH / 2                     // centro vertical de la zona de valor
topY   = cY − getFontHeight(fontBig) / 2         // techo del H:MM grande

// pieza grande: H:MM centrado verticalmente, anclado a la izquierda
dc.drawText(leftX, cY, fontBig, H:MM vivo, TEXT_JUSTIFY_LEFT | TEXT_JUSTIFY_VCENTER)
// pieza chica volada: :SS con la 'y' = techo (sin VCENTER, la y es el tope del texto)
dc.drawText(leftX + wBig + GAP_SUP, topY, fontSmall, :SS vivo, TEXT_JUSTIFY_LEFT)
```

- El color es el mismo (`fg`) para ambas piezas; el atenuado en pausa (6.4) aplica igual.
- ⚠️ La alineación fina del volado depende del ascendente real de cada fuente; ajustar `topY` (y opcionalmente usar `Graphics.getFontAscent`, API 1.2.0) mirándolo en el simulador — anotar el offset que quede bien.
- Las anchuras vivas (`wBig`/`wSmall`) se miden aquí porque la posición sí depende del string real; el **nivel** ya se decidió en 5.3 con plantillas estables, así que esto no reintroduce parpadeo.

### 6.7 Centrado vertical (validado en device, 2026-07-19)

Las fuentes numéricas reservan **descendente** que los dígitos no usan → centrar por la caja deja el número alto, con hueco abajo. Reglas aplicadas:
- **Valor:** centrar y luego empujar `cY += getFontDescent(font)/2` (centra lo visible).
- **Label:** reservar solo `getFontAscent` + margen explícito (4 px), no la caja completa.
- **Ajustes finos:** label y valor 2 px más arriba cada uno (nudges validados a ojo contra el nativo en el 840 real). El resultado quedó pixel-perfect vs el campo nativo (v0.1.5).

## 7. Settings

**No hay** (decisión de producto: solo timer, sin opciones). El mecanismo de settings se aprende en la Opción B.

## 8. Fuera de alcance v1 (anotado para después)

- `elapsedTime` (tiempo total con pausas) como métrica alternativa o setting.
- Hooks de timer (`onTimerStart/...`, API 1.3.0) — innecesarios aquí; se aprenden en la B.
- **Iconito monocromo junto al label — IMPLEMENTADO y committeado (2026-07-19, tag `v0.1.6`):** cronómetro (cuerpo circular + botón/corona arriba + una aguja a la ~1 en punto + pip central) dibujado con primitivas de `dc` en el color de frente → theme-aware y se atenúa en pausa, sin PNG ni tintado. **Forma elegida:** cronómetro (coincide con el launcher icon), no relojito. **Tamaño relativo, no fijo:** diámetro = `ascent(FONT_GLANCE) × 4/5` → escala en las 6 resoluciones (no los ~14 px fijos que decía el plan original). Va a la IZQUIERDA del texto; se centra el grupo `[ícono + gap + texto]` (`ICON_GAP=4`). **Degradación:** si el grupo no entra a lo ancho (`groupW > w - 2·PAD`) o el ícono queda < 8 px, se descarta el ícono y se centra solo el texto (celdas angostas seguras). **Rendimiento:** la geometría (posición/tamaño, medición del label) se **cachea** y se recalcula solo cuando cambia `w`/`h`/`mLabel` (helper `computeLabelLayout`); el tick por segundo solo dibuja, consistente con "zero measuring per tick" del caché del valor. Tunables en el código: `ICON_GAP`, la ratio `4/5` del diámetro, y dentro de `drawStopwatchIcon` la aguja (endpoint `cx+r/2, cy−r·7/10`, grosor `pen+1`), corona (`ch`/`cw`) y grosor de contorno (`pen`). **Validado en simulador** (las capturas del store muestran el `⏱ TIMER` renderizando en los 3 niveles de formato). Aguja **afinada tras feedback**: más larga (~0.85r) y más gruesa (`pen+1`) para que se lea; corona sin cambios.
- FIT recording, alertas, táctil: nada de eso aplica a este campo.

## 9. Presupuesto y rendimiento

- Límite real: 128 KB. **Objetivo: < 32 KB en uso** (app trivial; medir en simulador, *File → View Memory*).
- Sin colecciones dinámicas; miembros escalares + un array fijo de 8 fuentes.

## 10. Criterios de aceptación

- [ ] Compila sin warnings con el SDK actual, targets `edge830` y `edge840`, `minApiLevel 3.3.0`.
- [ ] Sin actividad iniciada: muestra `0:00` atenuado; no crashea (null-safety de `timerTime`/`timerState`).
- [ ] Start → cuenta `0:01, 0:02…` en formato `M:SS` en **todos** los layouts del simulador (1 a 10 campos).
- [ ] **Transición 59:59 → 1:00:00** en celda grande (layout 1–2 campos): pasa a `H:MM:SS` sin parpadeo ni salto visual.
- [ ] **Transición 59:59 → 1:00 (o compuesto)** en celda chica (layout 8–10 campos): en cuanto no entra `H:MM:SS`, cae al **nivel 2** (`H:MM` grande + `:SS` chico volado) o, si la celda es aún más chica, al **nivel 3** (`H:MM` pelado).
- [ ] **Formato compuesto (nivel 2)**: en una celda intermedia (≥1h), `H:MM` se ve grande y `:SS` chico y **volado** arriba a la derecha, con `:` adelante; alineación correcta (segundos no se solapan ni se cortan) en fondo blanco y negro.
- [ ] **9:59:59 → 10:00:00**: el string se ensancha un dígito y el nivel/fuente se re-selecciona correctamente (sin clipping), tanto en `H:MM:SS` como en el compuesto (`10:00`+`:00`).
- [ ] **Sin flapping**: con el timer en 1:XX:XX estable en una celda dada, el formato no alterna entre updates (verificar la caché por plantilla).
- [ ] Pausa manual y auto-pausa: el valor se congela y se atenúa; al reanudar recupera color y sigue. (Además responde la pregunta ⚠️: ¿`compute()` sigue llamándose en pausa?)
- [ ] Reset/guardar actividad: vuelve a `0:00` atenuado sin crash.
- [ ] **Validación 1:1 del valor**: junto al campo nativo "Tiempo" en la misma pantalla, el tiempo coincide siempre (tolerancia 1 s de fase). El aspecto puede diferir a propósito (nivel 2 compuesto).
- [ ] Fondo blanco y fondo negro: contraste correcto en ambos temas.
- [ ] Los `:` se renderizan bien en todas las fuentes de la escalera (⚠️ glifos de `FONT_NUMBER_*` no documentados).
- [ ] Memoria en régimen < 32 KB en el simulador.
- [ ] La tabla 11.1 (tamaños de celda y alturas de fuente medidos) quedó rellenada en esta SPEC.

## 11. Plan de pruebas en simulador (y mediciones pendientes ⚠️)

### 11.1 Tabla de medición — MEDIDA (hook `DEBUG_MEASURE`, perfil edge830/840, 2026-07-19)

Alturas de fuente de la escalera (constantes por device):

| Fuente | alto | ascent | descent |
|---|---|---|---|
| `FONT_SYSTEM_NUMBER_THAI_HOT` | 67 | 53 | 14 |
| `FONT_SYSTEM_NUMBER_HOT` | 55 | 43 | 12 |
| `FONT_SYSTEM_NUMBER_MEDIUM` | 42 | 33 | 9 |
| `FONT_SYSTEM_NUMBER_MILD` | 35 | 28 | 7 |
| `FONT_MEDIUM` / `SMALL` / `TINY` / `XTINY` | 19 / 17 / 14 / 11 | 14 / 12 / 10 / 8 | 5 / 5 / 4 / 3 |

Tamaños de celda observados (246×322): pantalla completa **246×322**; celdas de **media fila 122×62–66** (p. ej. layout con 2 campos arriba — ahí el valor usa `SYSTEM_NUMBER_MEDIUM` 42, igual que el nativo); celdas de ancho completo en layouts mixtos ≈ **246×136–139**. `LABEL_MIN_H = 60` queda **validado** para estos tamaños. Completar otros layouts solo si hace falta.

### 11.2 Ciclo básico
Simulator → *Simulation → Activity Data*: start, correr > 1 h (el simulador permite acelerar/forzar valores; si no, editar el tiempo simulado), pausa, resume, stop, reset. Repetir en layouts 1, 2, 5 y 10 campos, y con perfil `edge840`.

### 11.3 Verificaciones ⚠️ pendientes de la sección 4/5 (anotar resultados AQUÍ)
1. ¿`timerTime` se congela en pausa y auto-pausa? (esperado: sí)
2. ¿`compute()` sigue llamándose con el timer en pausa? (esperado: sí — por eso se gatea el color por `timerState`, no por la cadencia)
3. Valor de `timerTime`/`timerState` antes de arrancar: ¿null o 0/OFF?
4. ¿El campo nativo "Tiempo" trunca o redondea los segundos? ¿Muestra `M:SS` antes de la hora?
5. ¿`FONT_NUMBER_*` del Edge 830 incluyen el glifo `:`? Alturas reales de cada fuente.
6. **Observado (Edge 840, 2026-07-18):** en celda no completa y ≥1h, el campo nativo dibuja la **hora chica y volada** (superíndice) seguida de `MM:SS` grande (p. ej. `1`⁺`30:20`). Fue el origen del formato compuesto del nivel 2 (5.2), pero con la jerarquía **invertida**: nosotros dejamos `H:MM` grande y volamos `:SS` chico, porque la hora chica se lee mal. Confirmar el mismo comportamiento (o no) en el 830.

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

## 13. Pendiente antes de publicar

Checklist de lo que falta para una publicación real (no bloquea la Fase 0 de aprendizaje):

- [x] **Íconos — REHECHOS (2026-07-19, v0.1.6):** **Launcher** (35/36/40/56/68 px por device en `resources[-device]/drawables/launcher_icon.png`): cronómetro **plano dibujado con primitivas** (Pillow, no export de un render 3D), legible a 35 px — reemplazó el glossy reducido que quedaba una mancha borrosa. Transparente, identidad azul `#0070F0` + botones amarillo/rojo. **Store icon** (`store/store-icon-500.png`, 500×500 sRGB, fondo gris claro sólido `#E6E6E6`, 10 px padding) regenerado desde el nuevo **master analógico** (`store/icon-master-1024.png`, transparencia real). ⚠️ el PNG original de Gemini traía un **damero de "transparencia" horneado como píxeles opacos** (bug típico de Gemini) → removido por flood-fill antes de usarlo. Cero warnings en los 13 builds.
- [x] **Tipos de actividad / deportes — resuelto (2026-07-18):** existe `<iq:activityFilter>` en el manifest, pero es **API 5.2+ / System 8** → el **edge830 (3.3) no lo soporta**, y para un timer que sirve en cualquier actividad conviene **dejarlo universal, sin filtro**. No se agrega.
- [x] **Permisos — resuelto:** `<iq:permissions/>` vacío es correcto. El campo solo **lee** `timerTime` (que llega a `compute()` sin permiso); no escribe al FIT, así que **no** necesita `FitContributor` ni ningún otro permiso.
- [~] **Tienda:** subida como **BETA** (serie v0.1.x; la versión se pone en el portal al subir, no en ningún XML — los tags de git `v0.1.0`–`v0.1.6` registran cada build). **`.iq` de v0.1.6 generado** ("Monkey C: Export Project" → 13 devices firmados) para subir a la beta. Ficha con descripción/cover cargadas. **NO publicada:** el portal exige subir la versión de producción como app nueva con **otro ID de app**. **Flujo beta/prod DECIDIDO (Opción A: rama `release` permanente + tags)** — ver CLAUDE.md §«Flujo de release y publicación»; EN PAUSA, sin publish oficial todavía. **Capturas: HECHAS** (`store/activity-timer-{1,2,3}.png` fondo blanco/día + `-inv` fondo negro/noche, 482×232, opacas). Pendiente: la subida de producción con el id nuevo.
- [~] **Compatibilidad con otros Edge — ampliada (2026-07-18):** `<iq:products>` ahora lista los **13** Edge compatibles (soportan `datafield` + color + CIQ ≥ 3.3): `edge530`, `edge540`, `edge830`, `edge840` (todos **246×322**, resolución probada), + `edge550`, `edge850`, `edge1030`/`edge1030plus`/`edge1030bontrager`, `edge1040`, `edge1050`, `edgeexplore2`, `edgemtb` (otras resoluciones). **Excluidos** por CIQ < 3.3: `edge520plus`, `edge820`, `edgeexplore`, `edge_520`, `edge_1000`. Por monocromo: `edge130`/`edge130plus`. ✅ **Resuelto (2026-07-19):** render **validado en las 6 resoluciones distintas** (el layout dinámico + `LABEL_MIN_H=60` se sostienen; único matiz en 240×400: el `:SS` volado cae a `H:MM` pelado en celdas densas, por diseño — ver CLAUDE.md, no bloqueante). Íconos por tamaño **regenerados** (launcher plano legible, sin warnings de escalado).
- [~] **Nombre y metadatos de tienda.** Nombre app: `Activity Timer` / `Tiempo de Actividad` (✅ bilingüe). Capturas ✅ (`store/activity-timer-*`, base=blanco/día, `-inv`=negro/noche). Falta: descripción y categoría.
- [x] **`TEST_MODE = false`** en `ActivityTimerView.mc` (hecho).
- [x] **Hooks de debug excluidos del build de release (2026-07-19):** los hooks de simulador (`TEST_MODE`/reloj rápido y `DEBUG_MEASURE`/medición) no dejan residuo en el binario de release. Esquema: `TEST_MODE` y `DEBUG_MEASURE` quedan como `const false` **planos** → el optimizador de release (`-r`) elimina cada bloque `if (...)` (llamada incluida). Las **definiciones** que solo sirven al debug (`TEST_STEP_MS`, `TEST_MAX_MS`, `mTestMs`, `mMeasuredFonts`) van con `(:debug)`. Los cuerpos se movieron a `testClockMs()` y `debugMeasure()`, cada uno como **par** `(:debug)` (real) + `(:release)` (stub vacío): el stub existe solo para que el call site resuelva en release (el compilador resuelve símbolos antes de podar código muerto); luego el optimizador poda el stub por no referenciado. Para usar un hook: poner el `const` en `true` y correr un build **debug** (F5).
- [x] **Prueba en dispositivo real — HECHA (2026-07-19):** probado y afinado pixel-perfect contra el campo nativo en el Edge 840 del usuario (sideload vía OpenMTP; el 840 es MTP y no monta en Finder). Atraso visual ~1 s vs nativo por muestreo 1×/s: **aceptado** (el FIT graba bien).
- [x] **Tabla de medición §11.1 rellenada** (2026-07-19) y constantes validadas (`LABEL_MIN_H = 60`).
