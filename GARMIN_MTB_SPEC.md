# Especificación: Data Field MTB para Garmin Edge (Connect IQ)

> **Propósito de este documento:** servir de contexto completo para que una IA (o un desarrollador) implemente el proyecto sin necesidad de la conversación previa. Redactado para revisión humana antes de arrancar.

---

## 1. Contexto y objetivo

El usuario quiere desarrollar una aplicación para la **Connect IQ Store de Garmin**, orientada a su uso personal en **MTB (mountain bike)**, con posibilidad futura de publicarla en la tienda.

Tras evaluar los tipos de app disponibles (watch face, widget, data field, device app), se decidió que el formato adecuado para un ciclocomputador Edge es un **Data Field**: un campo de datos que se muestra *dentro* de las pantallas de actividad mientras se pedalea. Los widgets solo se ven fuera de la actividad y aportan poco en este caso.

**Objetivo v1:** un data field útil para MTB, funcionando primero en el simulador y luego en el dispositivo real.

---

## 2. Usuario y hardware

| Aspecto | Detalle |
|---|---|
| Dispositivo actual | **Garmin Edge 830** |
| Dispositivo futuro (próximamente) | **Garmin Edge 840** — el proyecto debe declarar ambos en el manifiesto desde el día 1 |
| Pantalla (830 y 840) | Táctil, **246 × 322 px**, color |
| Sensores internos relevantes | GPS, **altímetro barométrico**, acelerómetro, termómetro |
| Sensores externos | Posibles (FC, cadencia, potencia vía ANT+/BLE) — **no asumir que existen**; la app debe degradar bien sin ellos. El usuario tiene sensor de FC, velocidad y cadencia |
| Uso | MTB: Más bien XC. Senderos técnicos.  |
| Experiencia del usuario | Desarrollador de software (backend); conoce C/Java/Python; primera vez con Monkey C |
| Idioma de trabajo | Conversación en castellano; el código y sus comentarios DEBEN ir en inglés |

---

## 3. Plataforma y restricciones técnicas

### 3.1 Stack

- **Lenguaje:** Monkey C (OO, tipado dinámico/opcional, GC, corre en VM — similar a Java/JS, *no* a C).
- **SDK:** Connect IQ SDK + Connect IQ SDK Manager.
- **IDE:** VS Code + extensión oficial "Monkey C" de Garmin.
- **Pruebas:** simulador del SDK (tiene perfil de Edge 830 y 840). El usuario ya tiene claro que trabajará primero en simulador.
- **Firma:** requiere generar una developer key (gratuita, cuenta de desarrollador Garmin).

### 3.2 Datos disponibles en un Data Field

- ✅ Vía `Activity.Info` (en `compute()`): velocidad, distancia, **altitud barométrica**, pendiente aproximada, FC/cadencia/potencia/velocidad si hay sensores, temperatura, posición GPS, tiempos de actividad.
- ✅ **Acelerómetro crudo** vía `Toybox.Sensor.registerSensorDataListener` (ráfagas a ~25 Hz típicamente). ⚠️ **Verificar en simulador/documentación que el Edge 830 lo soporta para data fields** — el hardware lo tiene, pero hay que confirmar el permiso/API level.
- ✅ **Batería** vía `Toybox.System.getSystemStats()`: `battery` (% restante, `Float`, API 1.0 — disponible seguro en el 830) y `charging` (booleano, API 3.0). Existe también `batteryInDays` (API 3.3) pero con soporte de dispositivos limitado — no contar con él; calcular la proyección nosotros.
- ✅ **Gasto energético en vivo** vía `Activity.Info.energyExpenditure` (kcal/min, `Float`, API 1.2): métrica de Firstbeat derivada de FC — insumo directo para un modelo de "depósito de energía" (Opción H) sin potenciómetro.
- ✅ **Perfil de usuario** vía `Toybox.UserProfile.getProfile()`: `restingHeartRate`, `weight`, `birthYear` (API 1.0) y `vo2maxRunning` / `vo2maxCycling` (API 3.3 — el 830 llega justo). ⚠️ `vo2maxCycling` lo calcula el dispositivo solo con potenciómetro; sin él será probablemente `null` → el VO2max debe poder introducirse a mano o **estimarse desde FC/edad** (ver Opción H). Los settings manuales van en los App Settings del propio data field, no en el perfil de Garmin.
- ❌ **Grit, Flow, conteo de saltos y Stamina nativos de Garmin NO están expuestos** al API de Connect IQ (verificado en `Activity.Info`: no existe ningún campo de stamina). Si se quieren métricas equivalentes, hay que calcularlas desde datos crudos (esto es parte del atractivo del proyecto).

### 3.3 Restricciones

- **Memoria limitada** para data fields: **128 KB (131 072 B) en Edge 830 y 840** (verificado en el device reference oficial). Holgado pero no infinito: diseñar con frugalidad (buffers acotados, sin allocations en `compute()`/`onUpdate()`), objetivo < 50 % de uso.
- `compute()` se llama **1 vez por segundo**; `onUpdate()` redibuja según el layout. Cálculos pesados deben ser incrementales, nunca re-procesar históricos completos.
- El data field puede ocupar desde una celda pequeña hasta pantalla completa: el renderizado debe **adaptarse al tamaño del campo** (mostrar menos info en campos chicos).
- API level: el Edge 830 soporta hasta **Connect IQ 3.3.6** (confirmado); el Edge 840 llega hasta **6.0** (verificado en la página oficial de dispositivos compatibles, 2026-07-18). **Compilar contra 3.3** (mínimo común) para compatibilidad total.
- Sin conexión a internet requerida para la v1 (todo on-device).

---

### 3.4 Fuentes y render — verificado en device real (Fase 0, 2026-07-19)

Aprendizajes de la Opción A en el Edge 840, aplicables a **todas** las apps del proyecto:

- **Para igualar el estilo de los campos nativos, usar las fuentes del SISTEMA:** `FONT_SYSTEM_NUMBER_*` para dígitos y `FONT_GLANCE` para labels (en MAYÚSCULAS). Las `FONT_NUMBER_*`/`FONT_MEDIUM` "de app" miden lo mismo pero el trazo es distinto.
- ⚠️ **PERO `FONT_GLANCE` NO EXISTE en la familia de fuentes bitmap, y cae SILENCIOSAMENTE a la más chica (MEDIDO 2026-07-27).** En el edge830 `FONT_GLANCE` tiene **las mismas métricas que `FONT_XTINY` hasta el píxel** (a=10 d=3 h=13) mientras `FONT_SMALL` es a=17; en el edge840 `FONT_GLANCE` es a=15, más grande incluso que `FONT_MEDIUM` (14). O sea que pedir `FONT_GLANCE` a secas deja el label a **10 px de ascent en 6 de los 13 devices**, cuando el campo NATIVO de ese device usa `small` (lo declara su propio `simulator.json`: `datafields…label.font = small`). **Regla: elegir el mayor entre `FONT_GLANCE` y `FONT_SMALL` midiendo el ascent en runtime** — arregla la familia entera sin nombrar un device y no cambia nada en la otra. ⚠️ Y ojo con el diagnóstico: eso se ve como "las fuentes del 830 son peores", y es **medio cierto** — los bordes duros SÍ son del device (fuentes bitmap de **2 bits por píxel**, 4 niveles de gris medidos `0/82/164/255`, contra 8 bits y 32 niveles en el 840; **el campo nativo se ve igual de duro porque usa la misma fuente**), pero el TAMAÑO era nuestro.
- **Métricas (perfil edge830/840, 246×322)** — alto/ascent/descent: `SYSTEM_NUMBER_THAI_HOT` 67/53/14 · `HOT` 55/43/12 · `MEDIUM` 42/33/9 · `MILD` 35/28/7 · texto `MEDIUM…XTINY` 19-11/14-8/5-3. Tabla completa y tamaños de celda: `apps/a-activity-timer/SPEC.md` §11.1.
- **Centrado vertical:** las fuentes numéricas reservan descendente que los dígitos no usan → centrar por caja deja hueco abajo. Regla: al valor `cY += descent/2`; a los labels reservarles solo el `ascent` + margen explícito (~4 px); ajustes finos de ±2 px se validan a ojo contra el nativo.
- **SELECCIÓN de fuente numérica: comparar el `ascent` contra el alto disponible, NUNCA el `getFontHeight` (2026-07-25, Opción J §6.10).** Corolario del punto anterior: si el descendente no se pinta, tampoco hay que exigirle espacio al elegir el tamaño. Un gate tipo `getFontHeight(f) <= banda*0,9` tira un escalón entero de fuente al vacío y el campo sale visiblemente más chico que el nativo (el nativo mete una fuente de 42 px de alto en una banda de 41 porque solo pinta su ascent de 33). Regla: `getFontAscent(f) <= bandaH − 2`.
- **ALINEAR ALGO CON LOS DÍGITOS (una flecha, un ícono): anclarlo a la BASELINE, `cy + (ascent − descent)/2`. Centrarlo con la tinta es IMPOSIBLE de forma portable (MEDIDO en las dos familias el 2026-07-27 — Opción J §6.13).** La tinta de los dígitos **no llena el `ascent`** (hay aire arriba además del descendente abajo) y **cuánto lo llena depende de la FAMILIA**: `NUMBER_MEDIUM` pinta **26 px de 33 de ascent en el 840** (ratio 0,79) y **29 de 32 en el 830** (0,91). Ese alto de tinta **no lo expone ninguna API** y no se puede derivar (en las dos familias `ascent + descent = height`, así que no hay señal que las distinga) → cualquier constante para "centrar" es un valor horneado de una captura que otro device rompe. **Lo que sí es exacto: la tinta de los dígitos TERMINA en la baseline** (verificado en las dos familias; los glifos redondos se pasan 1 px, *overshoot* normal). Regla: anclar la **banda** del adorno a la baseline y que la figura la llene. ⚠️ **Dos corolarios que se pagaron caro:** un objetivo tipo `− descent/2` es un error que **crece con la fuente** (4 px en `MEDIUM`, 7 en `THAI_HOT`), y **validar la alineación en UN tamaño de celda o UN device no vale** — hicieron falta las 7 celdas de una pantalla en las dos familias.
- **Y una PRIMITIVA y un GLIFO no LLENAN esa banda igual, así que no se colocan igual.** Una figura de `fillPolygon` se dibuja desde su alto real: se le da el centro de la banda y la llena, con la base en la baseline. Un **glifo** dibujado con `TEXT_JUSTIFY_VCENTER` centra la **caja de su fuente**, que reserva un descendente que el glifo no pinta → su tinta flota **`descent/2` hacia arriba** y hay que devolvérselo (`+ getFontDescent(fuenteDelGlifo)/2`; en `FONT_LARGE` del 840 son 4 px). Y al glifo conviene **centrarlo EN la banda, no apoyarlo en el piso**: si está topeado (el `↑` del 840 no pasa de `FONT_LARGE`) su tinta puede medir la mitad que los dígitos y apoyarla la hunde — 13 px en celda grande, se lee como subíndice. ⚠️ Como la elección glifo-vs-primitiva depende de la **familia de fuentes del device**, cualquier error acá es **asimétrico por familia** y por lo tanto invisible validando en un solo device (misma trampa que el punto de los glifos, más abajo).
- **Unidades junto al número (estilo nativo): proporcionales, no un `FONT_XTINY` fijo.** Medido al campo nativo de velocidad: ascent de la unidad ≈ **2/5** del ascent del número, apilada (`km` sobre `h`) a la derecha, **las dos líneas centradas entre sí**, baseline de la de abajo sobre la baseline de los dígitos, baselines separadas `ascent + 2`. Si el grupo no entra a lo ancho: **encoger primero la unidad, después el número** (el número es el dato).
- **Los 13 devices se parten en DOS familias de fuente, y la partición NO coincide con las 6 resoluciones (verificado 2026-07-25 leyendo `simulator.json` de cada device + las tablas de las fuentes):**

  | familia | devices | fuente de TEXTO (`FONT_XTINY…LARGE`) | fuente NUMÉRICA |
  |---|---|---|---|
  | **TTF** | 540, **840**, 550, 850, 1040, 1050, mtb | `DejaVuSans_Cd_SemiBold_WGL4.ttf` (658 glifos) | `Garmin_Roboto_Bold.ttf` |
  | **bitmap `.cft`** | 530, **830**, 1030 ×3 | `FNT_ROBOTO_CONDENSED_*.cft` (526 codepoints) | `FNT_DEJAVU_FITNESS_*.cft` (24) |
  | **bitmap `.cft`** | explore2 | `FNT_006B416900_DEJA_VU_SANS_*.cft` | `FNT_006B416900_ROBOTO_BOLD_*.cft` |

  Los `.cft` son **subsets compilados**: el mismo DejaVu pasa de 658 glifos a 526 codepoints y corta en U+2122. **Consecuencia operativa: el 830 y el 840 están en familias distintas, así que validar un glifo en el simulador del 840 no dice NADA del 830.** Los archivos están en `~/Library/Application Support/Garmin/ConnectIQ/Fonts/` y se pueden inspeccionar sin GUI: los `.ttf` por su tabla `cmap`, los `.cft` leyendo `numRanges` en `0x30` y tripletas `(cpInicial, cpFinal, primerGlifo)` desde `0x34`.
- **Cobertura de glifos, verificada por tabla (2026-07-25):** `%`, `.` y los dígitos están en las fuentes numéricas de **las dos** familias (por eso A/B/J pueden dibujar `"7%"` o `"24.3"` en un solo string). **NO están:** las flechas `↑ ↓ ▲ ▼` en NINGUNA fuente numérica de ningún device, ni en la fuente de TEXTO de la familia `.cft` (530/830/1030×3/explore2) — sí están en la de texto de la familia TTF. Tampoco está **la coma** en la fuente numérica de la familia `.cft`: un decimal con `,` rompería en el 830.
- **⚠️ LAS TABLAS DE FUENTE NO PREDICEN EL RENDER: hay una cadena de FUENTES DE RESPALDO no documentada (medido en Edge 840 REAL, 2026-07-25 — corrige lo que este mismo documento afirmaba horas antes).** El probe de `apps/j-trend-arrow/SPEC.md` §11.2, sideloadeado al 840 del autor, pintó `↑` (12×26 px) y `▲` (22×22) **en fuente NUMÉRICA**, donde `Garmin_Roboto_Bold` no los tiene, y pintó **U+2B06, que no está en NINGÚN archivo de fuente del SDK**. Conclusión: las tablas de arriba dicen qué hay en el archivo nominal, **no** qué termina dibujando el device. **La única autoridad es el hardware.**
- **El simulador se equivoca en LAS DOS direcciones.** Falsos positivos: pinta glifos que la fuente pedida no tiene (fila 2 del probe). Falsos **negativos**: el `⬆` no lo pintó en el sim y el 840 real **sí** — o sea que el simulador es MÁS restrictivo que el device, al revés de lo que uno asumiría. **Ningún resultado del simulador sobre un carácter no-ASCII sirve como prueba, en ninguna dirección.**
- **Aun así, las flechas de A/B/J se dibujan como PRIMITIVAS (`fillPolygon` + `fillRectangle`), y esa decisión NO cambia.** El motivo ya no es "la fuente no lo tiene" sino: lo único que haría funcionar el glifo es esa sustitución **no documentada**, verificada en **1 de las 2 familias** de fuente (el 840, TTF) y **sin ninguna evidencia en la familia `.cft`** (530/**830**/1030×3/explore2), que es justo donde la fuente de texto es un subset recortado. Y si allá no existe, **el modo de falla es invisible**: no hay caja ni interrogante, la flecha simplemente no está y el campo parece correcto. Cambiar algo que funciona en los 13 por un comportamiento no documentado verificado en la mitad de la flota, con fallo silencioso, no compensa.
- **Verificar el layout SIN la GUI del simulador:** se puede instanciar la View en un test `(:test)` y dibujarla en un `Dc` offscreen del tamaño exacto de la celda (`BufferedBitmap`), corriendo headless con `monkeydo -t` → reporta qué fuente elige el código de verdad en cada celda y device. Detalle y gotchas en `apps/j-trend-arrow/SPEC.md` §11.1.
- **Cadencia:** un data field CIQ muestrea `Activity.Info` ~1×/s → hasta ~1 s de atraso visual vs el campo nativo. Cosmético (el FIT graba bien).
- **Sideload en Mac:** Edge 540/840/1040+ usan **MTP** (Garmin quitó el modo disco) → no montan en Finder. Funciona **OpenMTP** (probado en Mac M4): copiar el `.prg` a `GARMIN/Apps/` y el device lo consume al reiniciar. La alternativa sin cable es la IQ Store (OTA).

### 3.4.1 Las fuentes numéricas de la familia bitmap NO TIENEN EL GLIFO DE ESPACIO (2026-07-28)

**Medido en el simulador del edge830, y ya había llegado a producción sin que nadie lo viera.** El modo
ancho de la Opción J dibuja `actual / promedio` como **un solo string en fuente numérica**; con el
separador `" / "` el 830 mostraba `95 ⃞/⃞ 81` — **cada espacio salía como la caja *notdef*** compartida de
la fuente. El `/` sí está en las dos familias; el **espacio** no está en la numérica de la familia
bitmap.

- **Es la misma caja notdef** que usa la detección del glifo de la flecha para decidir si un símbolo
  existe (`apps/j-trend-arrow/SPEC.md` §11.2): en esa familia los glifos ausentes de la fuente numérica
  comparten una caja de 22 px. O sea que el mecanismo ya estaba documentado; lo que faltaba era saber
  que **el espacio es uno de los ausentes**.
- **Regla, un paso más allá de la que ya teníamos:** de una `FONT_SYSTEM_NUMBER_*` no hay que esperar
  solo «no tiene letras ni flechas» — **puede no tener el espacio**. Cualquier string que vaya en fuente
  numérica se arma **sin espacios**; si hace falta separación visual, se dibuja como piezas aparte o se
  usa un separador verificado (`/`, `.`, `,`, `:`, `-` sí están).
- **Cómo pasó desapercibido:** el defecto solo aparece en el layout ancho, solo en 6 de los 13 devices,
  y el **label** de la misma línea (que sí lleva espacios) se ve perfecto porque va en **fuente de
  texto**. Se descubrió mirando la Opción K en un 830 — la J lo tenía igual, publicada.

## 4. Opciones de producto evaluadas

Ordenadas de menor a mayor complejidad. La visión es **incremental**: cada opción puede construirse sobre la anterior dentro del mismo proyecto.

### Opción A — Tiempo de actividad (formato adaptativo) → **spec detallada: [`apps/a-activity-timer/SPEC.md`](apps/a-activity-timer/SPEC.md)**
- **Qué muestra:** el timer de la actividad (`Activity.Info.timerTime`, equivalente al campo nativo "Tiempo"), con formato adaptado al espacio de la celda: `M:SS` mientras no haya horas; a partir de 1 h, `H:MM:SS` si la celda tiene espacio suficiente o `H:MM` si no.
- **Rol:** proyecto tutorial del autor (**Fase 0** del roadmap). Duplica a propósito un campo nativo: el valor está en aprender el ciclo completo (proyecto CIQ, `compute()`/`onUpdate()`, render adaptativo por medición de texto, simulador, sideload) con una lógica trivial y validable 1:1 contra el campo nativo.
- **Dificultad:** 🟢 baja. **Valor MTB:** el del aprendizaje — el campo en sí es redundante con el nativo, y ese es el punto: cero riesgo de producto mientras se aprende la plataforma.

### Opción B — Pendiente + VAM → **spec detallada: [`apps/b-grade-vam/SPEC.md`](apps/b-grade-vam/SPEC.md)**
- **Qué muestra:** pendiente actual (%) y velocidad de ascenso vertical (VAM, m/h), calculadas de altitud + distancia.
- **Cálculo:** ver spec detallada (ventana por distancia para pendiente, ventana temporal configurable para VAM, filtro de outliers barométricos).
- ⚠️ **Verificado 2026-07-13:** el Edge 830 **ya trae 4 campos VAM nativos** (VAM / 30s VAM / Avg VAM / Lap VAM) y pendiente nativa. Los diferenciales de esta app: ambas métricas en un campo, ventana de suavizado configurable (la nativa es fija a 30 s) y zonas de color. Connect IQ no expone VAM/pendiente nativas por API → igual hay que calcularlas.
- **Dificultad:** 🟢 baja. **Valor MTB:** ⭐⭐ (duplica parcialmente lo nativo — su valor real es pedagógico y de pipeline).
- **Rol:** ejercicio de calentamiento y **pipeline de altitud reutilizable** por C, H e I; no es el objetivo final.

### Opción C — "Descenso actual" ⭐ candidata a MVP
- **Qué muestra:** al detectar que empieza una bajada, resetea y trackea métricas *de esta bajada*: desnivel perdido (m), velocidad máxima, tiempo de descenso, pendiente media. Al terminar la bajada, congela el resumen unos segundos.
- **Detección de estado:** máquina de estados (SUBIENDO / LLANO / BAJANDO) con **histéresis** sobre la pendiente suavizada (p. ej. entra en BAJANDO con pendiente < −3 % sostenida N segundos; sale con pendiente > −1 % sostenida M segundos) para no rebotar en terreno rompepiernas.
- **Dificultad:** 🟢🟡 baja-media. **Valor MTB:** ⭐⭐⭐⭐.
- **Rol:** **MVP recomendado.** Toca todas las piezas base (lectura de `Activity.Info`, estado, render adaptativo) sin acelerómetro.

### Opción D — Cronómetro de tramos (enduro)
- **Qué hace:** botón táctil grande para iniciar/parar el crono de cada tramo/stage; guarda la lista de tiempos de la salida.
- **Nota técnica:** los data fields tienen interacción táctil limitada (`onTap` en CIQ 3.x según dispositivo); si resultara insuficiente, esta opción podría requerir convertirse en device app. **Investigar antes de comprometerse.**
- **Dificultad:** 🟡 media. **Valor MTB:** ⭐⭐⭐⭐ (para uso enduro específico).

### Opción E — "Chunk meter" / índice de rugosidad (Grit casero)
- **Qué hace:** usa el **acelerómetro crudo** para puntuar en vivo qué tan técnico/roto es el terreno — una versión abierta de la métrica propietaria **Grit** de Garmin (que puntúa la dificultad del recorrido combinando desnivel, sinuosidad y acelerómetro, y que NO está expuesta a Connect IQ).
- **Enfoque de cálculo (propuesta inicial, a refinar):** RMS de la aceleración vertical filtrada (paso alto para quitar gravedad y pedaleo lento) sobre ventana móvil, normalizada por velocidad; mapear a una escala 0–100 o niveles (verde/amarillo/rojo).
- **Dificultad:** 🟡🔴 media-alta (procesamiento de señal + límites de memoria/CPU). **Valor MTB:** ⭐⭐⭐⭐⭐ (no hay buen equivalente gratuito en la tienda → candidata a publicación).

### Opción F — Detector de saltos / air time
- **Qué hace:** detecta fases de caída libre (norma de aceleración ≈ 0 g sostenida) para contar saltos y medir tiempo en el aire; muestra contador y último air time.
- **Retos:** umbrales robustos (falsos positivos en baches/raíces), ventanas de confirmación, calibración.
- **Dificultad:** 🔴 alta. **Valor MTB:** ⭐⭐⭐⭐⭐.
- **Rol:** objetivo aspiracional tras la opción E (comparten la infraestructura de acelerómetro).

### Opción G — Estimador de batería restante (tiempo de autonomía)
- **Qué muestra:** tiempo estimado de batería restante en h:mm a ritmo de consumo actual, y opcionalmente la tasa de descarga (%/h). Complementa al % nativo del Edge, que no proyecta horas según el uso real de *esta* salida.
- **Fuente de datos:** `System.getSystemStats().battery` (% restante, disponible desde API 1.0 → funciona en el 830 sin permisos especiales). `charging == true` (p. ej. conectado a un powerbank) invalida la estimación → pausar/resetear el estimador.
- **Cálculo propuesto:**
  - Muestrear el % en cada `compute()`; registrar el timestamp de cada caída de % (el valor baja en escalones — no hay precisión continua garantizada).
  - Estimar la tasa de descarga con regresión lineal o media móvil exponencial sobre una **ventana móvil** de los últimos 30–60 min (adaptativa: si el usuario enciende retroiluminación/navegación, la tasa sube y la estimación se corrige sola).
  - `tiempo_restante = %_actual / tasa` (con opción de proyectar hasta una reserva del 10 % en vez de hasta 0 %).
- **Sobre la linealidad (decisión de diseño):** el % que reporta el fuel gauge ya viene aproximadamente linealizado respecto a la capacidad, así que **a carga constante la descarga es casi lineal**. Lo que NO es constante es la carga (pantalla, mapas, sensores, temperatura: el frío reduce capacidad y al final de la carga puede acelerarse la caída). Por eso el modelo correcto es **lineal por tramos con tasa adaptativa** (ventana móvil), no una única recta desde el inicio de la salida.
- **Arranque en frío:** con ~20 h de autonomía nominal el 830 pierde ~1 % cada ~12 min → se necesitan ≥ 2–3 caídas de % (~30 min) para una primera estimación fiable. Mitigación: persistir la tasa media de salidas anteriores en `Application.Storage` y usarla como semilla hasta tener datos frescos de la salida actual.
- **Dificultad:** 🟢 baja (sin acelerómetro, sin permisos, matemática simple). **Valor MTB:** ⭐⭐⭐ (muy útil en salidas largas / bikepacking).
- **Rol:** independiente del resto — puede implementarse en cualquier fase, incluso como segundo módulo del MVP.

### Opción H — "Stamina casera" (estimador de energía restante sin potenciómetro)
- **Motivación:** la **Real-Time Stamina** nativa (Edge 840/540/1040, relojes recientes) es un modelo de Firstbeat que estima cuánta energía queda para seguir apretando. Requiere **potenciómetro** (usa la curva de potencia de los últimos 2–3 meses como calibración y la potencia instantánea como señal de intensidad) y **no está expuesta a Connect IQ**. Sin potenciómetro, el usuario no la tendrá ni siquiera en el 840 → una versión propia basada en FC tiene valor en ambos dispositivos.
- **Idea clave del diseño:** el VO2max **no es la señal en tiempo real, es la calibración** del modelo (define el techo aeróbico del ciclista). La señal en vivo debe ser la **FC** (el usuario tiene banda): sin potencia, es el único proxy de intensidad disponible.
- **Objetivo de producto (decidido con el usuario):** responder "¿puedo apretar un poco más?" y "¿me voy recuperando?". Dinámica lenta (decenas de segundos a minutos) es suficiente; capturar arranques de ~10 s queda **fuera de alcance deliberadamente**. Una aproximación honesta ya aporta valor.
- **Entradas — todas opcionales, con cadena de fallbacks.** Van en los **App Settings del propio data field** (editables desde la app Garmin Connect del móvil). Importante: son ajustes de *nuestra* app, no el campo VO2max del perfil de Garmin — ese Garmin lo ignora si se introduce a mano, pero es irrelevante aquí porque nuestro modelo lee sus propios settings.
  - **VO2max:** **semilla blanda**, no entrada crítica (ver nota de calibración abajo). Manual si el usuario lo tiene (laboratorio); si no, `VO2max ≈ 15,3 × FC_max / FC_reposo` (Uth et al. 2004). ⚠️ Sin potenciómetro no se puede estimar bien el VO2max *absoluto* — el método fiable (el de Firstbeat/Garmin) necesita la relación FC↔trabajo externo (vatios), que aquí no tenemos. La fórmula de Uth, además, es mal detector de *progreso*: su única palanca de fitness es la FC_reposo, así que con reposo estancado solo refleja la caída de FC_max por edad. Basta para dimensionar el depósito una vez; no para seguir la evolución.
  - **FC máxima:** manual (de un test) o estimada por edad: `FC_max ≈ 208 − 0,7 × edad` (Tanaka), con la edad derivada de `UserProfile.birthYear`.
  - **FC en reposo:** `UserProfile.restingHeartRate` (el Edge la conoce) o manual.
  - **Peso:** `UserProfile.weight`.
  - **FC umbral (LTHR):** manual si se conoce; por defecto ≈ 87–90 % de FC_max.
- **Modelo propuesto (v1, a refinar):** modelo de "depósito" tipo W′bal pero conducido por FC:
  - Intensidad instantánea: `%HRR = (FC − FC_reposo) / (FC_max − FC_reposo)`, que aproxima bien el %VO2max utilizado (relación casi 1:1 bien establecida en fisiología).
  - Por encima de una intensidad crítica (≈ LTHR o ~85 % FC_max por defecto): el depósito se **vacía** a un ritmo proporcional al exceso de intensidad. Por debajo: se **recarga** con una constante de tiempo (recuperación).
  - Tamaño del depósito calibrado con VO2max + peso (ciclistas con más motor aeróbico sostienen más tiempo el mismo %); **ajustable por el usuario por sensación** tras las primeras salidas ("se vació demasiado pronto" → depósito mayor). El VO2max es solo la semilla inicial de este tamaño; los **anclajes de FC (reposo, máxima y umbral) son el verdadero motor** del modelo, y todos son observables sin potenciómetro. La **Opción I (test de subida)** da la mejor semilla de VO2max disponible sin potenciómetro y debe preferirse a la fórmula de Uth cuando exista un resultado de test.
  - Alternativa/complemento: usar `Activity.Info.energyExpenditure` (kcal/min, Firstbeat, ya derivado de FC) como tasa de gasto y modelar el depósito en kcal "por encima de umbral".
  - Salida: % de stamina restante (número grande + barra de color), como la nativa.
- **Limitaciones a documentar honestamente (gestión de expectativas):**
  - La FC **retrasa** 30–60 s respecto al esfuerzo: los sprints cortos típicos del XC vacían reservas anaeróbicas antes de que la FC reaccione → el modelo suaviza los picos. **Aceptado por diseño** (ver objetivo de producto).
  - **Deriva cardíaca** (calor, deshidratación) infla la FC al final de salidas largas → el modelo drenará más rápido; asumible e incluso deseable (correlaciona con fatiga real percibida).
  - Es un **indicador de tendencia bien fundamentado, no una réplica de Firstbeat**: útil para dosificarse, no para ciencia.
- **Dificultad:** 🟡🔴 media-alta (modelado + settings + calibración; sin acelerómetro). **Valor MTB:** ⭐⭐⭐⭐⭐ para dosificarse en salidas largas; sin equivalente accesible si no tenés potenciómetro.
- **Rol:** independiente de la línea del acelerómetro (E/F); candidata natural tras el MVP. Formato: **data field** (la stamina se mira durante la actividad; un widget no sirve).

#### Dos regímenes en el "tiempo restante" (modelo de Potencia Crítica / W′)

El tiempo hasta el agotamiento NO es un número único: depende del régimen de intensidad. El data field debe distinguirlos:

- **Por encima del umbral (apretando):** hay cuenta atrás finita y real. `tiempo_restante ≈ reserva_disponible / (intensidad_actual − umbral)`. Este es el número que responde "¿cuánto aguanto a este ritmo?". Mostrarlo como tiempo (p. ej. "~7 min").
- **En/por debajo del umbral (sostenible):** el depósito se recarga, no se vacía → una cuenta atrás no tiene sentido físico (el limitante pasa a ser el combustible/glucógeno, escala de horas, **fuera de alcance v1**). Mostrar "sostenible" / "recuperando" y la barra rellenándose, no un tiempo.

Esto reproduce el modelo de la stamina nativa de Garmin: **stamina potencial** (capacidad total del depósito) vs **stamina actual** (lo que queda ahora). El umbral (frontera entre regímenes) sale de los anclajes de FC (≈ LTHR) y su tamaño de depósito, de la calibración de capacidad (Opción I mejora esta calibración).

#### Corrección subjetiva "escucha a tu cuerpo" (calibración por RPE) — requisito de diseño

**Principio:** ninguna estimación basada en FC ve el calor, el sueño, la nutrición, la deshidratación ni la fatiga acumulada de días — pero **el propio ciclista sí los siente**. La sensación de esfuerzo (RPE, escala de Borg) es un integrador de fatiga directo y bien validado. Por tanto el modelo NO debe ser cerrado ("calcula y punto"): debe ser **adaptativo**, permitiendo que el usuario lo corrija en marcha. Esto convierte el modelo de bucle abierto a bucle cerrado y es lo que genera confianza en la métrica.

**Mando único (UX):** exponer **un solo control** — un *factor de forma/capacidad* (p. ej. escala 1–5 o botones +/−), NO parámetros crudos como "VO2max" (poco intuitivos en movimiento). Semántica:
- **"No doy más"** aunque el modelo diga "sostenible/vas sobrado" → bajar el factor → depósito más pequeño → el modelo drena antes y se vuelve conservador.
- **"Me queda resto"** aunque el modelo me dé por fundido → subir el factor → depósito mayor.
Internamente ese factor escala el tamaño del depósito (y opcionalmente reajusta el umbral / el VO2max-semilla), pero el usuario ve un botón, no fisiología.

**Debe persistir y aprender:** la corrección no puede ser solo momentánea. Guardar el factor ajustado en `Application.Storage` para **arrancar mejor calibrado la próxima salida** (aprendizaje entre salidas). Corrección instantánea (este momento) + memoria (siguientes salidas).

**Robustez:** el input subjetivo es ruidoso → **acotar** el rango del factor (p. ej. ×0,6–×1,4), suavizar los saltos y preferir el aprendizaje persistente a cambios bruscos por segundo.

**Reto de ingeniería (no del modelo):** el input en marcha choca con la interacción táctil limitada de los data fields (misma limitación que la Opción D). Posibles vías, a decidir (ver pregunta abierta 8): (a) convertir el módulo de stamina en **device app** en vez de data field; (b) usar el botón de lap u otro gesto disponible; (c) a futuro, **auto-calibración** desde señales fisiológicas — p. ej. deriva cardíaca (FC que sigue trepando a esfuerzo supuestamente sostenible) como indicio de fatiga real que encoge el depósito automáticamente.

**Encuesta de fin de salida ("¿cómo te sentiste?") — canal de calibración principal (session-RPE / método de Foster):**
Al terminar la salida, con el usuario **parado**, preguntar una valoración simple del esfuerzo global (escala 1–5 o "fácil / justo / fundido"). Ventajas sobre el ajuste en marcha:
- **Sin problema de input:** parado se interactúa con la pantalla sin fricción → es el canal más fiable y de menor esfuerzo. El +/− en marcha queda como refinamiento *opcional*.
- **Método validado:** el session-RPE (Foster) es el estándar para cuantificar la carga de una sesión.
- **Cierra el bucle de aprendizaje (aprendizaje supervisado):** el modelo conoce su **predicción** (p. ej. "acabaste al 40 % de depósito") y la contrasta con lo **sentido**. Si el usuario dice "fundido" y el modelo daba resto → encoger la capacidad para la próxima salida; si dice "fácil" y el modelo lo daba por fundido → agrandarla. La corrección persiste en `Application.Storage` y calibra la siguiente salida. En pocas rodadas el factor de forma converge a la fisiología real del usuario.

⚠️ **Implicación de formato:** un data field **no puede** mostrar una pantalla interactiva al guardar la actividad (al terminar, el data field se destruye; no gestiona vistas propias). Una encuesta de fin de salida requiere una **device app** (controla su propia grabación y puede transicionar a una vista de resumen al parar) o, en su defecto, un glance/widget companion que pregunte por la última actividad guardada. Esto refuerza la decisión de la pregunta 8 hacia device app y, a la vez, la resuelve en gran parte: la calibración principal ya no depende de input en marcha.

### Opción I — Test de subida de referencia (semilla de VO2max de campo + rastreador de forma)
- **Qué es:** un modo de test opcional (el "Cooper en bici"). El usuario sube a tope una cuesta consistente durante ~5-6 min; con **desnivel + tiempo + masa total** se estima VO2max/MAP por física, sin potenciómetro. Sirve para dos cosas: (1) dar a la Opción H una **semilla de capacidad mucho mejor** que la fórmula de Uth, y (2) **seguir la evolución de la forma** repitiendo la misma subida (resuelve el problema de "envejezco pero mejoro": mide trabajo externo real, no una regresión de FC).
- **Por qué una subida reduce el ruido:** en cuesta empinada la mayor parte de la potencia va contra la gravedad, que es física conocida. A VAM fija, la velocidad baja al empinar → aero (∝v³) y rodadura (∝v) se encogen y la gravedad domina (>90 % en pendientes fuertes), así que la estimación depende poco de CdA/Crr/viento.
- **Cadena de cálculo (fórmulas verificadas):**
  1. `VAM (m/h) = desnivel_ganado (m) / tiempo (s) × 3600`.
  2. **VAM → W/kg.** Componente de gravedad (identidad exacta): `W/kg_grav = VAM / 367`. Estimación total (empírica, incluye rodadura+aero, **coeficiente corregido**): `W/kg = VAM / (200 + 10 × pendiente%)`. ⚠️ El denominador es `(200 + 10·grade)`, **no** `2·(200+10·grade)`. Ejemplos: 8 % → /280; 10 % → /300; 12 % → /320. El denominador tiende a 367 al empinar (~16,7 %), por eso ambas estimaciones convergen en cuestas duras.
  3. **W/kg → VO2max.** Fórmula **hecha a medida para un test de 5 min** (la mejor para este uso): `VO2max (ml/kg/min) = 16,6 + 8,87 × (W/kg del test)`. Alternativa sobre potencia absoluta, Hawley & Noakes 1992 (r=0,97): `VO2max (L/min) = 0,01141 × MAP(W) + 0,435`. ⚠️ No usar la ecuación ACSM `10,8·W/masa + 7` aquí: está validada solo para 50-200 W en estado estable y a la potencia de un test máximo *subestima* (extrapola fuera de rango).
- **Ejemplo numérico (realista):** subida al 8 %, se ganan **93 m de desnivel en 5 min** (300 s) → VAM = 93 × 3600/300 = 1116 m/h → W/kg = 1116/280 ≈ **4,0 W/kg** → VO2max ≈ 16,6 + 8,87×4,0 ≈ **52 ml/kg/min** (aficionado en buena forma). Comprobación cruzada: 4,0 W/kg para un rider de 75 kg = 300 W; Hawley & Noakes da (0,01141×300+0,435)/75×1000 ≈ 51 ml/kg/min → coherente (~2 %).
- **Advertencias clave (a documentar en la app):**
  - Un test de **~5-6 min** mide el techo aeróbico (VO2max/MAP). Un test de 20 min (tipo FTP) mide el **umbral**, no el VO2max — no confundirlos. El Cooper de 12 min es de *carrera* (fórmula de distancia), no traslada a potencia en bici.
  - Es un **proxy sin analizador de gases**: número aproximado, no VO2max medido. Asume esfuerzo genuinamente máximo y sostenido.
  - **MTB:** la rodadura en tierra (Crr alto y variable) ensucia el valor *absoluto* → para VO2max fiable, hacer el test en **asfalto o pista muy compacta**; para *seguir el progreso*, vale cualquier superficie mientras sea **siempre la misma subida en condiciones parecidas** (el cambio relativo es válido aunque el absoluto esté sesgado).
  - Errores de altímetro barométrico sesgan la VAM directamente → calibrar altitud antes del test.
- **Entradas:** masa total (usuario + bici + equipo; ajuste manual), y detección del segmento de test (marcar inicio/fin, o auto-detectar por pendiente sostenida). Requiere leer altitud, distancia y tiempo — todo ya disponible en `Activity.Info`.
- **Dificultad:** 🟡 media (matemática simple ya verificada; el grueso es la UX del modo test y la detección del segmento). **Valor:** ⭐⭐⭐⭐ (alimenta H y da un rastreador de forma que ni el Garmin nativo ofrece sin potenciómetro).
- **Rol:** complemento de la Opción H. ⚠️ **Restricción de plataforma:** `Application.Storage` es un sandbox **por app** — dos apps Connect IQ distintas NO pueden leerse el storage entre sí. Por tanto I debe vivir **dentro de la misma app que H** (como un segundo modo/vista), o su resultado tendría que copiarse a mano vía App Settings. Esto refuerza la arquitectura de la pregunta abierta 9: H+I juntas en la device app de stamina.

### Opción J — Flecha de tendencia (actual vs. promedio) estilo Cateye ⭐ prioritaria (sembrada 2026-07-22) — **spec detallada: [`apps/j-trend-arrow/SPEC.md`](apps/j-trend-arrow/SPEC.md)**
- **Qué muestra:** una flecha chica (arriba/abajo) al lado de una métrica que compara su valor **actual** contra el **promedio de la actividad**. Arriba = actual por encima del promedio; abajo = por debajo; **sin flecha** cuando coinciden dentro de la resolución de display (banda muerta, regla Cateye "dentro de 1 dígito"). Indicador **genérico** entre métricas; el **MVP es velocidad**. Diferenciador real: Garmin nativo muestra actual y promedio **por separado**, pero NO la flecha combinada.
- **Banda muerta (mecanismo anti-parpadeo PRIMARIO):** el problema no es que la métrica sea poco fiable, sino que cerca del cruce `actual≈promedio` la flecha oscilaría tick a tick. Se resuelve comparando los valores **ya redondeados al display**: `round(actual) == round(promedio)` → sin flecha; `>` → arriba; `<` → abajo. (Equivalente por umbral crudo: sin flecha si `|actual − promedio| < medio paso de display` — con km/h a 1 decimal, medio paso = 0,05; entero, 0,5.) Decidir sobre lo que el usuario ve exactamente → flecha y número nunca se contradicen.
- **Suavizado / histéresis (SECUNDARIO, opcional):** la velocidad de sensor de rueda (la del usuario) es limpia; el parpadeo del cruce ya lo mata la banda muerta. Solo si en device se observa jitter residual con **GPS-only**, agregar un EMA suave sobre "actual" (mismo idiom que la Opción B, α≈0,3–0,4) y/o histéresis en el umbral. No introducir suavizado que **retrase la flecha respecto del número mostrado**.
- **Semántica del promedio:** MVP = **promedio GLOBAL de la actividad** (fiel a Cateye y **gratis** vía `Activity.Info.averageSpeed`, sin buffers). Dejar **ventana móvil** ("¿voy por encima de mi ritmo reciente?", últimos N s/min) como **variante por setting**. (Cálculo incremental del promedio propio en Tier 2: `avg += (x − avg)/n`; ventana móvil = EMA con α fijo — misma fórmula, distinto paso.)
- **Tiers de métrica (disponibilidad VERIFICADA 2026-07-22 por doc oficial + compile-probe contra el SDK):**
  - **Tier 1 — Garmin da actual Y promedio** (promedio gratis, flecha casi trivial): **velocidad** (`currentSpeed`/`averageSpeed`, m/s, desde 1.0.0), **FC** (`currentHeartRate`/`averageHeartRate`, bpm, 1.0.0), **cadencia** (`currentCadence`/`averageCadence`, rpm, 1.0.0). *Potencia* (`currentPower`/`averagePower`, 1.0.0) sería Tier 1 con potenciómetro, pero **EXCLUIDA**: el usuario no tiene → ambos `null`; ninguna feature asume potencia.
  - **Tier 2 — derivamos el actual y/o el promedio nosotros:** **VAM y pendiente** (no expuestas por CIQ; se derivan de `altitude`/`totalAscent` sobre tiempo — lo que ya hace la Opción B, alimentar su VAM suavizada contra un promedio propio acumulado); **tasa de calorías** (`energyExpenditure`, kcal/min, desde 1.2.0, es el *actual*, pero **no hay promedio nativo** → derivarlo del contador acumulado `calories`). *Temperatura* **NO** es miembro de `Activity.Info` (vive en `Sensor.Info`/`SensorHistory`, requiere sensor y está sesgada por el calor del propio equipo) → flecha de valor dudoso, fuera del MVP. **Distancia:** NO lleva flecha (`elapsedDistance` es un odómetro monótono; `averageDistance` (1.2.2) no es su contraparte; "ritmo por distancia" se reduce a velocidad).
- **Cálculo / módulo puro:** un `TrendArrow` puro que recibe `(actual, promedio, paso_de_display)` y devuelve `{UP, DOWN, NONE}` (comparar SIEMPRE en las mismas unidades; `null` en cualquiera → NONE). Sumar una métrica nueva = **cambiar la fuente, no la lógica**. Unit tests obligatorios (banda muerta, cruces exactos, redondeo, nulls) según convención del repo.
- **Render:** reusar la flecha up de la Opción B con primitivas `dc` (`drawUpArrow`: cabeza `fillPolygon` + tallo `fillRectangle`, dimensionada al ascent de la fuente como `drawAscentAux`, en `apps/b-grade-vam/source/GradeVamView.mc`) + su **flecha down ESPEJADA**. **NO** usar glifo de flecha de fuente (cobertura no garantizada en los 13 devices — misma precaución que el `%` ausente en las fuentes numéricas). Layout al lado del número; "sin flecha" = no se dibuja nada; color = foreground del tema, atenuado en pausa.
- **Settings sugeridos:** métrica objetivo (MVP velocidad; extensible a FC/cadencia); ancho de la banda muerta (multiplicador del medio-paso); promedio global (default) vs. ventana móvil (+ largo si móvil); (opcional) suavizado del actual on/off para GPS-only.
- **Dificultad:** 🟢🟡 baja-media (MVP velocidad es Tier 1, promedio gratis). **Valor MTB:** ⭐⭐⭐⭐.
- **Rol:** **prioritaria — decidida 2026-07-22.** Indicador genérico, MVP = velocidad. Reusa el primitivo `drawUpArrow` de la Opción B. Arranca standalone sobre velocidad y luego puede **superponerse** a la pendiente/VAM de B o a otra métrica sin tocar la lógica del módulo puro. ⚠️ **Que la lógica sea genérica NO significa que toda métrica merezca la flecha** — ver el criterio de abajo, que descartó la FC.

### La familia de la flecha de tendencia — qué métrica la merece y qué métrica no (DECIDIDO 2026-07-30)

Nació de una pregunta del autor sobre la Opción L (la misma flecha sobre frecuencia cardíaca): *«no me convence este data field, ¿de qué sirve?»*. La respuesta fue que **no sirve**, y al buscar el motivo salió un criterio general, que es lo que vale para las que vengan.

**Las tres preguntas. Una métrica merece la flecha de tendencia solo si las tres dan SÍ:**

1. **¿Es inmediata?** El valor tiene que responder ahora al esfuerzo de ahora. Si la métrica llega con retraso, la flecha informa de algo que ya cambiaste.
2. **¿La controla el ciclista directamente?** Tiene que haber una acción obvia al ver la flecha (cambiar de piño, apretar). Si solo se controla de forma indirecta, la flecha no es accionable: es un comentario.
3. **¿Le falta una referencia propia?** La flecha *aporta* una referencia (tu promedio, tu objetivo). Si la métrica ya trae una referencia mejor de fábrica, la flecha compite con ella y pierde.

| Métrica | ¿Inmediata? | ¿Controlable? | ¿Sin referencia propia? | Veredicto |
|---|---|---|---|---|
| **Velocidad** (Opción J) | sí | sí | sí | ✅ **en producción** |
| **Cadencia** (Opción K) | sí | sí | sí | ✅ **en producción** |
| **Frecuencia cardíaca** (Opción L) | **no** | **no** | **no** | ❌ **DESCARTADA** |
| Temperatura | no | no | sí | ❌ (y no está en `Activity.Info`, vive en `Sensor.Info`) |
| Potencia | sí | sí | sí | ✅ en teoría — **imposible acá: el autor no tiene potenciómetro** |

**Por qué la FC falla las tres, y por qué no es un problema de diseño que se pueda arreglar con otro layout:**

- **No es inmediata:** la FC responde con **30-60 s de retraso**. Cuando la flecha se mueve, el esfuerzo que la causó ya pasó.
- **No es controlable directamente:** se gobierna a través del esfuerzo, no con un gesto. Ver la flecha no habilita ninguna acción que no estuvieras tomando ya.
- **Ya tiene su referencia, y se llama ZONA.** Una zona *es* una comparación contra tu capacidad — una referencia estructuralmente mejor que «el promedio de la salida de hoy». La flecha estaría compitiendo contra un patrón superior y ya nativo.
- **Y un cuarto defecto, fatal y medible:** el promedio de FC de la actividad **arrastra el calentamiento**. Los primeros ~20 minutos lo tiran hacia abajo, así que en cuanto la salida se pone dura la flecha apunta arriba y **se queda clavada en ▲ el resto del día**. Un indicador que no cambia no informa.
- Contra un **objetivo fijo** funciona mejor, pero ahí el Edge ya tiene **alertas de zona**: un pitido le gana a una flecha justamente cuando la gracia es no tener que mirar.

⚠️ **No confundir DISPONIBILIDAD con VALOR.** La tabla de Tiers de la Opción J dice que la FC es Tier 1, y eso sigue siendo cierto: `currentHeartRate` y `averageHeartRate` existen y son gratis. Tier 1 responde *«¿se puede?»*, las tres preguntas responden *«¿sirve?»*. La FC se puede y no sirve.

**Consecuencia: la familia de la flecha es J y K, y se cierra ahí.** Dos no es un fracaso; lo que empujaba a L era **completar el alfabeto**, que es un impulso de coleccionista y no un beneficio para quien instala la app. La letra L queda **libre para otro producto** (la letra es una etiqueta, no un orden — ver `CLAUDE.md`).

**Lo que sí podría hacerse con la FC alguna vez, y pasaría las tres preguntas: la VELOCIDAD DE RECUPERACIÓN.** Cuánto te baja el pulso en la bajada. En XC se sube al límite y se recupera bajando, y la tasa de recuperación de la FC es una señal de forma real que el Edge **no muestra en vivo**. Es inmediata (la caída se ve mientras pasa), es información nueva (ninguna zona la cubre) y no compite con nada nativo. **Sería una opción NUEVA, no la L**, y no está especificada: queda como idea anotada, sin compromiso.

---

## 5. Roadmap recomendado

1. **Fase 0 — Opción A (tiempo de actividad):** el proyecto tutorial completo en `apps/a-activity-timer/`: esqueleto Connect IQ tipo data field (manifiesto con `edge830` + `edge840`, "hola mundo" en el simulador con perfil Edge 830) y, sobre él, el campo de tiempo con formato adaptativo, probado en simulador y sideload al Edge 830 real.
2. **Fase 1 — MVP (Opción C):** data field "Descenso actual" completo, probado en simulador con datos simulados/FIT de ruta con desnivel, y luego sideload al Edge 830 real.
3. **Fase 2 — Infraestructura de acelerómetro:** spike para validar `registerSensorDataListener` en el 830 (frecuencia real, permisos, consumo de memoria).
4. **Fase 3 — Opción E (chunk meter)** sobre esa infraestructura.
5. **Fase 4 — Opción F (saltos/air time)**, reutilizando el pipeline de señal.
6. **Fase 5 (opcional) — Publicación** en Connect IQ Store (materiales de tienda, revisión de Garmin).

   **Monetización (estado 2025-2026, decisión: v1 gratis):**
   - La tienda tiene **pago nativo con Garmin Pay** desde ago-2024 (apps premium desde ~4,99 USD; reparto Garmin/dev no publicado — investigar si se llega ahí). Vías alternativas: donaciones (PayPal/Ko-fi en la descripción) y trial + código de desbloqueo (soporte oficial de "Trial Apps"; servicios tipo KiezelPay).
   - ⚠️ **Cualquier petición de dinero — incluidas donaciones/propinas — exige "verificación de trader"** (identidad + domicilio, por la DSA europea). Desde feb-2025 Garmin bloquea/retira apps de pago de desarrolladores no verificados. Publicar gratis sin pedir nada no requiere verificación.
   - **Estrategia decidida:** v1 **gratis y sin petición de donaciones** (cero papeleo, acumular instalaciones/reviews). Si alguna app tracciona (candidatas: chunk meter, saltos, stamina sin potenciómetro — sin equivalente gratuito), completar verificación de trader y evaluar freemium (3-5 €) vs donaciones.
   - Expectativa realista: nicho de nicho; los data fields con donaciones generan típicamente decenas-cientos de €/año. Esto es un proyecto por gusto con potencial de propina, no un negocio.

Las opciones B y D quedan como extras opcionales (B como sub-métrica dentro de C; D solo si la interacción táctil en data fields resulta viable). La opción G es independiente y de baja dificultad: puede intercalarse en cualquier fase, p. ej. justo después del MVP.

**Opción J (flecha de tendencia) — PRIORIZADA (decisión 2026-07-22):** independiente y de dificultad baja-media (MVP = velocidad, Tier 1, promedio gratis vía `averageSpeed`). Se prioriza para hacerla pronto — puede intercalarse tras el MVP, como G. Reusa el primitivo de flecha (`drawUpArrow`) ya presente en la Opción B (`apps/b-grade-vam`).

**Línea de stamina (independiente del acelerómetro E/F), en orden lógico:**
- **Opción I (test de subida)** primero: da la semilla de capacidad y el rastreador de forma. Es autocontenida y de dificultad media — buen candidato tras el MVP.
- **Opción H (stamina casera)** después: consume la semilla de I como calibración del depósito. Es el objetivo mayor de esta línea.

Puede desarrollarse en paralelo a las fases 2–4 o priorizarse tras el MVP según interés.

---

## 6. Requisitos no funcionales

- **Robustez sin sensores externos:** todo debe funcionar solo con GPS + barómetro + acelerómetro internos.
- **Render adaptativo:** legible en celda pequeña (1 valor grande) y rica en pantalla completa (varias métricas). Fuentes grandes: se mira en movimiento, con guantes, con sol.
- **Sin estado persistente obligatorio** en v1 (todo vive durante la actividad). Persistencia (p. ej. `Application.Storage` para ajustes) puede llegar después.
- **Presupuesto de memoria:** mantenerse holgadamente por debajo del límite de data field del Edge 830; medirlo en el simulador (View > Memory).
- **Código:** Monkey C idiomático, comentarios en inglés, estructura estándar de proyecto Connect IQ (`manifest.xml`, `monkey.jungle`, `source/`, `resources/`).
- **Unit tests (desde la Opción B, 2026-07-19):** la lógica de cálculo va en módulos puros con tests `(:test)` de `Toybox.Test` (excluidos del release). Convención completa en `CLAUDE.md`; patrón en la Opción A (`TimeFormat*.mc`).
- **Estructura del repo (decidido):** monorepo con cada opción como app auto-contenida en `apps/<letra>-<slug>/` (p. ej. `apps/b-grade-vam/`), extraíble a repo propio en el futuro. Nombres acordados en el CLAUDE.md. Sin código compartido entre apps salvo decisión explícita.

---

## 7. Criterios de aceptación del MVP (Fase 1)

- [ ] Compila sin warnings para `edge830` y `edge840`.
- [ ] En el simulador (Edge 830), con un FIT/simulación que incluya un descenso: el campo detecta la bajada, acumula desnivel/velocidad máx./tiempo, y congela el resumen al terminar.
- [ ] No hay falsos cambios de estado en terreno ondulado (validar con histéresis usando datos con ruido).
- [ ] El render es legible tanto en celda de media pantalla como en campo pequeño.
- [ ] Uso de memoria dentro del límite del dispositivo con margen (> 20 % libre).

---

## 8. Fuera de alcance (v1)

- Grit/Flow nativos de Garmin (API cerrada — no accesibles).
- Conexión a internet o backend de cualquier tipo.
- Soporte de dispositivos que no sean Edge. (Actualizado 2026-07-19: dentro de la línea Edge se apunta a **los 13 devices con CIQ ≥ 3.3** — la Opción A ya los shippea y se verificó que el límite de memoria de datafield es idéntico (128 KB) en todos; el **Edge 840 es el device de referencia y prioridad** por ser el del autor. Regla: máxima compatibilidad salvo que cueste funcionalidad.)
- Publicación en la tienda (se decide al final de la Fase 3/4).
- Proyección de tiempo hasta el agotamiento **por debajo del umbral** (limitada por combustible/glucógeno, escala de horas — requiere modelar ingesta/glucógeno, fuera de v1).
- VO2max medido con analizador de gases: la Opción I es una estimación de campo, no una medición de laboratorio.

## 9. Preguntas abiertas (para decidir antes o durante la implementación)

1. ¿Unidades métricas fijas o respetar la configuración del dispositivo? (propuesta: respetar configuración del usuario del Edge).
2. En el MVP, ¿qué métrica merece el "número grande" durante la bajada: velocidad actual, desnivel perdido o tiempo?
3. ¿Interesa grabar las métricas calculadas en el archivo FIT (`FitContributor`) para verlas luego en Garmin Connect? (posible extra de Fase 1–3).
4. Nombre del proyecto/app (necesario para el manifiesto y, eventualmente, la tienda).
5. Para la Opción H — **decidido:** el modelo debe funcionar sin VO2max de laboratorio, estimando todo desde edad/peso/FC disponibles (una aproximación ya sirve); el VO2max manual queda como refinamiento opcional. **También decidido:** el usuario dispone de una FC máxima observada en sus últimos meses de actividad → usarla como valor manual (es cota inferior de la real y mejor que la fórmula por edad; validar que no sea un artefacto de sensor mirando la curva de la actividad). La fórmula de Tanaka queda solo como fallback para usuarios sin histórico.
6. Para la Opción I: ¿el test se implementa como un **modo dentro del data field de stamina** (más simple de mantener) o como un **data field/app aparte** que persiste el resultado? ¿La detección del segmento de test será manual (marcar inicio/fin) o automática (pendiente sostenida ≥ N min)?
7. Para la Opción I: ¿de dónde sale la **pendiente media** del test para el coeficiente `(200 + 10·grade)` — del desnivel/distancia del propio segmento (más robusto) o de la pendiente instantánea? (propuesta: media del segmento).
8. Para la corrección subjetiva de la Opción H: ¿cómo se introduce el ajuste en marcha dado el input táctil limitado de los data fields? Opciones: (a) module = device app; (b) botón de lap / gesto; (c) solo en App Settings entre salidas (sin ajuste instantáneo) + auto-calibración por deriva cardíaca a futuro. Es la decisión que condiciona si la stamina es data field o device app. **Nota:** la encuesta de fin de salida (session-RPE) inclina la balanza hacia **device app** y hace que el ajuste en marcha sea opcional, no imprescindible.
9. ¿La stamina (H + calibración por RPE + encuesta de fin) se implementa como **device app** (necesaria para la pantalla de resumen al parar) mientras que "Descenso actual" (C), batería (G) y VAM (B) siguen como **data fields**? Es decir: ¿el proyecto acaba teniendo dos formatos (varios data fields + una device app de stamina)? Definir la arquitectura de módulos.
