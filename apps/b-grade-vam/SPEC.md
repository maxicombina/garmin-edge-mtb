# SPEC — `b-grade-vam` (Opción B)

> Data field Connect IQ para Garmin Edge: **pendiente actual (%) + VAM (m/h)** calculadas on-device desde el altímetro barométrico. Especificación de implementación, autocontenida: no requiere leer ninguna conversación previa. La spec maestra del proyecto ([`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md)) da el contexto de producto; la app hermana **ya terminada y validada en device** ([`apps/a-activity-timer/`](../a-activity-timer/)) es la referencia de patrones (fuentes, caché, hooks de debug, tests, íconos) — **leer su SPEC §5.3/6/8/13 y su código antes de implementar**.
>
> Los datos de plataforma citados aquí fueron verificados contra la documentación oficial de Garmin el 2026-07-13 y **re-verificados el 2026-07-19** (settings de datafield, `Activity.Info`, fuentes, hooks, memoria — todo confirmado; única salvedad: FONT_GLANCE en el 830, ver §6.2). No "corregirlos" de memoria.

---

## 1. Objetivo y rol (honesto)

**Hallazgo de la verificación:** el Edge 830 **ya incluye de fábrica** campos nativos de VAM (`VAM`, `30s VAM`, `Avg VAM`, `Lap VAM`) y de pendiente. Un data field que solo muestre VAM duplica funcionalidad nativa.

Por tanto el rol de esta app es:

1. **Vehículo de aprendizaje** (segundo proyecto Monkey C del autor): primera app con algoritmos reales — buffers, suavizado, settings. Las piezas base (proyecto CIQ, `compute()`, render adaptativo, simulador, sideload, release, tests) llegan aprendidas de la Opción A.
2. **Pipeline reutilizable**: el buffer de muestras de altitud/distancia y su suavizado son la base directa de las opciones C (descenso), H (stamina) e I (test de subida).
3. **Diferenciales reales frente a lo nativo** (los únicos motivos para usarla en la calle):
   - **Ambas métricas en un solo campo** (pendiente + VAM juntas; en nativo son dos celdas).
   - **Ventana de suavizado configurable** (la VAM nativa instantánea es una media móvil fija de 30 s; aquí 5/10/30 s a elección).
   - **Zonas de color** para la pendiente (lectura de un vistazo con guantes).

Nota: Connect IQ **no expone** la VAM ni la pendiente nativas por API (`Activity.Info` no tiene esos miembros en 3.3) → hay que calcularlas desde cero. Eso es precisamente lo que queremos aprender.

## 2. Plataforma (verificado)

**Targets (decidido 2026-07-19): los mismos 13 Edge que la Opción A**, con el **Edge 840 como device de referencia y prioridad** (es el del autor; se valida primero ahí). Verificado contra los device files del SDK (2026-07-19): **los 13 tienen idéntico límite de memoria de datafield (131 072 B = 128 KB)** → no se pierde funcionalidad por ampliar. Táctil varía (530/540/550/edgemtb son de botones) pero v1 no usa touch (§8). Las 6 resoluciones distintas (246×322, 240×320, 240×400, 282×470, 420×600, 480×800) ya fueron validadas con render adaptativo en la Opción A.

| Aspecto | Edge 840 (referencia) | Los otros 12 |
|---|---|---|
| ID (manifiesto) | `edge840` | `edge530/540/550/830/850`, `edge1030/plus/bontrager`, `edge1040/1050`, `edgeexplore2`, `edgemtb` |
| API level mín. común | **3.3** (el 830 llega a 3.3.6) | todos ≥ 3.3 |
| **Memoria app type `datafield`** | **128 KB** | **128 KB — idéntico en los 13** |
| Pantalla de referencia | 246 × 322 px, 65 536 colores, táctil | 6 resoluciones; táctil variable (irrelevante en v1) |

- **Target de compilación: API 3.3.x** (mínimo común).
- Tipo de app: `datafield`. Sin permisos especiales (ni Positioning ni Sensor: todo llega por `Activity.Info`).
- Todos los Edge del manifest tienen altímetro barométrico; `Activity.Info.altitude` funciona igual en todos.
- ⚠️ `Graphics.fitTextToArea` es **API 4.2.1** → NO disponible en 3.3. La selección de fuente se hace midiendo con `getTextWidthInPixels` (patrón de la Opción A).

## 3. Arquitectura

**Clase base: `WatchUi.DataField` completo** (no `SimpleDataField`): dos métricas, layout adaptativo y color → dibujamos nosotros en `onUpdate(dc)`.

**Principio rector (heredado de la A, obligatorio): toda la matemática vive en módulos PUROS testeables** (sin `Dc`, sin `Activity.Info`, sin estado de device). `GradeVamView.compute()` es un wrapper fino que null-chequea `Activity.Info` y delega en el engine — el mismo patrón `ActivityTimerView` → `TimeFormat` de la A, escalado.

```
b-grade-vam/
├── manifest.xml               # type=datafield; 13 products; minApiLevel 3.3.0; launcherIcon
├── monkey.jungle              # mínimo (auto-discovery), como el de la A
├── source/
│   ├── GradeVamApp.mc        # AppBase: getInitialView(); onSettingsChanged() → recarga + requestUpdate
│   ├── GradeVamView.mc       # DataField: compute() (wrapper fino) + onUpdate() (render §6). NO testeable, por diseño lo más chico posible
│   ├── GradeVamEngine.mc     # PURO. Orquestador: buffer + filtros + estado + ventanas → gradePct()/vamMh()
│   ├── SampleBuffer.mc       # PURO. Ring buffer de capacidad parametrizable (reutilizable por C/H/I)
│   ├── AltFilter.mc          # PURO. Filtro de outliers barométricos + re-seed (§5.1)
│   ├── GradeMath.mc          # PURO. Fórmula de pendiente + guardas + clamp (§5.2)
│   ├── VamMath.mc            # PURO. Fórmula de VAM + guardas + clamp (§5.3)
│   ├── RefSelect.mc          # PURO. Selección de referencia por distancia / por tiempo (§5.2/5.3)
│   ├── EngineState.mc        # PURO. Transiciones de timerState → acciones (§5.4)
│   ├── Units.mc              # PURO. Conversión ft/h + formateo de strings (§5.5)
│   ├── TestUtil.mc           # (:test) assertNear / assertIsNumber (§10)
│   └── *Test.mc              # un archivo de tests por módulo puro (§10)
└── resources/                 # base: strings eng (fallback) + settings
    ├── strings/strings.xml    # AppName, labels (§6.4)
    ├── settings/              # properties.xml + settings.xml (§7)
resources-spa/strings/         # español (patrón de la A)
resources-<device>/drawables/  # ícono launcher por device, 13 carpetas, SIN ícono base privilegiado (patrón de la A, ver su monkey.jungle)
```

Reglas de la clase (verificadas):
- `compute(info)` se llama ~1×/s y NO dibuja; `onUpdate(dc)` dibuja y NO calcula. Sin orden garantizado → **todo miembro inicializado en `initialize()`**; `onUpdate()` seguro antes del primer `compute()`.
- Tamaño de celda: `dc.getWidth()/getHeight()` en `onUpdate()`.
- Fondo: `getBackgroundColor()` → blanco o negro; elegir colores de contraste en cada update.
- `getObscurityFlags()`: ignorar en v1 (pantallas rectangulares).

## 4. Entradas — `Activity.Info` (tipos y nulabilidad verificados)

| Campo | Tipo | Unidad | Desde | Notas |
|---|---|---|---|---|
| `altitude` | `Float or Null` | m | 1.0 | barómetro o GPS, el más preciso. **Null hasta tener fuente.** |
| `elapsedDistance` | `Float or Null` | m | 1.0 | null sin fix/actividad |
| `timerTime` | `Number or Null` | **ms** | 1.0 | tiempo de TIMER (no avanza en pausa) — la base temporal correcta |
| `currentSpeed` | `Float or Null` | m/s | 1.0 | para la guarda de parado de VAM (§5.3) |
| `totalAscent` / `totalDescent` | `Float or Null`* | m | 1.0 | *doc inconsistente → tratar como Float. `totalAscent` es la línea auxiliar del modo FULL (§6.1) |
| `timerState` | `TimerState or Null` | — | 2.1 | `TIMER_STATE_OFF/STOPPED/PAUSED/ON` (0–3) |

**Regla dura: TODOS los campos pueden ser null** → null-check antes de cada uso; sin datos se muestra `--`, nunca se crashea ni se inventa.

**Disciplina de tipos (obligatoria):** `t` se almacena como **`Number` (ms enteros)** y las restas `t_now − t_ref` se hacen en `Number` ANTES de convertir a `Float` para dividir. Motivo: `Float` es de 32 bits y pierde exactitud entera por encima de 2^24 ms ≈ 4 h 40 min — plausible en una salida larga. `h` y `d` sí son `Float`.

Hooks de timer (API 1.3): `onTimerStart/Stop/Pause/Resume/Reset/Lap` existen, pero son **secundarios**: la fuente de verdad de las transiciones es el `timerState` observado en `compute()` (§5.4), porque el comportamiento de los hooks bajo auto-pausa no está documentado.

## 5. Algoritmos

Pipeline de `GradeVamEngine.update(timerState, tMs, dM, hM)`, en orden:

```
1. EngineState.onTimerTransition(prev, next)  → NONE / RESET_WINDOWS / CLEAR   (§5.4)
2. EngineState.shouldPush(state)              → solo se muestrea con timer ON
3. mediana-de-3 sobre h cruda                 → mata picos de 1 muestra        (§5.1)
4. AltFilter.classify(lastGoodH, h, rejects)  → ACCEPT / REJECT / RESEED       (§5.1)
5. EMA(α=0.4) sobre h aceptada                → reduce el ruido ~2× (lag ~1.5 s)
6. push {t, d, h_suavizada} al SampleBuffer
7. RefSelect → índices de referencia          → GradeMath / VamMath            (§5.2/5.3)
8. formatear strings de display (Units)       → miembros, cacheados            (§5.5)
```

### 5.1 Adquisición, filtro de outliers y suavizado

- **Ring buffer de 64 muestras** (~64 s @1 Hz), capacidad como argumento del constructor (los tests usan 4). Arrays paralelos `t/d/h` fijos, cero allocations tras `initialize()`. Índice cronológico: 0 = más vieja.
  - *Por qué 64 y no 32:* la ventana de pendiente es por distancia; a 2 km/h (subida técnica lenta, caso de uso core) 30 m tardan ~54 s — 32 muestras solo cubren ~18 m. 64 muestras cubren el peor caso y le dan margen a la ventana VAM de 30 s. Coste: ~0,8 KB, despreciable contra 128 KB.
- **Filtro de outliers barométricos (`AltFilter`), reglas exactas:**
  - La comparación es SIEMPRE contra la **última muestra ACEPTADA** (no contra la anterior cruda).
  - `|Δh| > 5 m` → **REJECT**: la muestra NO se pushea (no fabricar un falso llano pusheando h duplicada).
  - **Re-seed obligatorio:** con **3 REJECT consecutivos** → **RESEED**: aceptar la nueva altitud como nueva línea base y **vaciar el buffer** (reinicia ventanas). Motivo: un pico real dura 1–2 muestras; un desnivel persistente (recalibración del baro, túnel, frente meteorológico, cambio de fuente GPS↔baro) dura para siempre — sin re-seed el filtro se traba y grade/VAM quedan congelados el resto de la salida.
- **Suavizado:** mediana-de-3 antes del filtro (complementa el gate de 5 m matando picos de una muestra) y EMA con α≈0,4 después. Sin esto, el ruido barométrico (σ≈0,4 m por extremo) produce un parpadeo del grade entero de ±2–3 % por segundo con la ventana de 20 m (±5–6 % con la de 10 m) — violaría el criterio de estabilidad de §10.

### 5.2 Pendiente (%)

```
grade = 100 × (h_now − h_ref) / (d_now − d_ref)
```

- **Ventana híbrida** (por distancia con piso temporal): referencia = muestra más antigua que cumpla `(d_now − d) ≤ W_grade` **Y** con un span mínimo de **3 muestras**. El piso evita que en descenso rápido (40 km/h ⇒ 11 m entre muestras) la ventana degenere a una diferencia de 1 s llena de ruido. `W_grade` default **20 m** (setting 10/20/30).
- **Fallback de buffer corto:** si el buffer no abarca `W_grade`, usar la muestra más vieja disponible (ventana efectiva = `min(W_grade, span del buffer)`), siempre que pase la guarda de parado. Documentado: la ventana elegida es un máximo, no una promesa.
- **Guarda de parado:** si `(d_now − d_ref) < 5 m` → no calcular → `--`.
- **Fuera de rango = error de datos:** si `|grade| > 40 %` → mostrar **`--`** (NO el valor clavado en ±40: un valor fuera de rango es error de datos, y mostrarlo clavado presenta un error como lectura real).
- Redondeo a entero, **half away from zero** (7,5→8; −7,5→−8). Signo siempre visible (`+7`/`−12`); el cero sin signo (`0`).
- **Histéresis de display:** el entero mostrado solo cambia cuando el valor crudo cruza el límite de redondeo con un margen de 0,5 % — evita el parpadeo residual entre dos enteros vecinos.

### 5.3 VAM (m/h)

```
vam = (h_now − h_ref_t) / (t_now − t_ref_t) × 3 600 000    // t en ms (Number)
```

- **Ventana temporal:** referencia = muestra más antigua con `(t_now − t) ≤ W_vam`. `W_vam` default **10 s** (setting 5/10/30 — con 30 s replica la "30s VAM" nativa, útil para validar). **El divisor es el Δt REAL medido**, nunca el nominal de la ventana.
- **Guardas (obligatorias — Monkey C lanza error de runtime en división por cero, no devuelve Infinity):** requiere ≥ 2 muestras **Y** `Δt ≥ max(2000 ms, W_vam/2)`; si no → `--`.
- **Guarda de parado:** si `(d_now − d_ref_t) < 2 m` en la ventana, o `currentSpeed < 0,5 m/s` sostenida → mostrar **0** (no `--`: "parado, no asciendes" es información válida; y sin esta guarda la deriva térmica del baro muestra ±180 m/h parado — el criterio de §10 sería infalsable).
- **Clamp de plausibilidad:** `|vam| > 5000 m/h` → `--` (análogo al clamp de pendiente).
- VAM negativa en descenso: válida, se muestra con signo.
- Nota física (documentar en el setting): con ruido de ±0,5 m, error ≈ ±360 m/h con ventana de 5 s; ±180 con 10 s; ±60 con 30 s.

### 5.4 Estados y ciclo de vida (`EngineState`)

Transiciones sobre `timerState` **observado en `compute()`** (los hooks son secundarios; la auto-pausa podría no dispararlos):

| prev → next | Acción |
|---|---|
| ON → ON | NONE (flujo normal) |
| ON → PAUSED/STOPPED | NONE (el gate `shouldPush` congela solo; display mantiene últimos valores en gris) |
| !ON → ON (resume/start) | **RESET_WINDOWS = vaciar el buffer** + resetear mediana/EMA. Regla simple y completa: NO existe "resetear referencias" por separado — las referencias son derivadas del buffer, y conservar muestras pre-pausa produce picos (t/d congelados en pausa + h derivada ⇒ Δd≈0 con Δh real). El costo es un warm-up de ~`W` segundos mostrando los valores congelados, aceptable. |
| cualquiera → OFF (reset) | **CLEAR**: vaciar todo, display a `--` (estado inicial) |

- `shouldPush(state)`: `true` solo con `TIMER_STATE_ON`.
- Arranque en frío (buffer < 2 muestras válidas): `--` en ambas métricas.
- Display durante warm-up post-resume: mantener los últimos strings en gris hasta que el engine produzca valores frescos.

### 5.5 Unidades y formateo (`Units`)

- Pendiente: `%` universal.
- VAM: `System.getDeviceSettings().elevationUnits` — `UNIT_METRIC` → m/h; `UNIT_STATUTE` → **ft/h (×3,281)**. **Releer en `compute()`** (1×/s, barato): el cambio de unidades del device NO dispara `onSettingsChanged` (eso es solo para app settings).
- ⚠️ **Presupuesto de glifos:** en ft/h una VAM normal de descenso (−1500 m/h) son **6 glifos** (`-4921`); la selección de fuentes de §6 DEBE medirse con plantillas de ancho estable de 6 glifos en modo statute (`-88888`), 5 en métrico (`-8888`).
- Strings pre-formateados en `compute()` y guardados en miembros; `onUpdate()` solo dibuja (cero formateo/medición por tick).

## 6. Render adaptativo (`onUpdate(dc)`)

### 6.1 Modos por altura de celda

Umbrales sanity-checkeados contra la tabla medida de la A (§11.1: media fila 122×62–66; ancho completo mixto 246×136–139; pantalla completa 246×322):

| Modo | Condición (alto) | Contenido |
|---|---|---|
| **FULL** | ≥ 200 px | pendiente XL con zona de color + VAM grande + línea auxiliar = **`totalAscent`** (con `--` si null) |
| **HALF** | 90–199 px | pendiente + VAM lado a lado, número grande + etiqueta pequeña |
| **SMALL** | < 90 px | **una** métrica (setting `primaryMetric`) + etiqueta mínima |

Re-validar los umbrales en las 6 resoluciones en el simulador (como se hizo con la A).

### 6.2 Fuentes (aprendizajes de la A — obligatorios)

- **Dígitos: `FONT_SYSTEM_NUMBER_*`** (THAI_HOT 67 px / HOT 55 / MEDIUM 42 / MILD 35 en 246×322) — NO las `FONT_NUMBER_*` "de app": miden igual pero el trazo no es el nativo. Confirmadas en 3.3.
- **Labels: `FONT_GLANCE`, texto en MAYÚSCULAS**, reservando solo el `ascent` + margen (~4 px). ⚠️ **Salvedad verificada 2026-07-19:** la constante existe desde 3.1.8 y compila, pero el device profile del **edge830 no tiene glance font** (el 840 sí) → en el 830 cae a un fallback no documentado. **Verificar el render con el perfil edge830 en el simulador**; si se ve mal, fallback explícito a `FONT_XTINY`/`FONT_TINY` para el label en ese device.
- **Centrado vertical:** las fuentes numéricas reservan descendente que los dígitos no usan → al centrar el valor, `cY += getFontDescent(font)/2`; nudges finos de ±2 px se validan a ojo contra campos nativos (en el 840 real).
- **Selección con caché (patrón A):** fuentes por slot elegidas midiendo **plantillas de ancho estable** (grade: `-88`; VAM: `-8888` métrico / `-88888` statute), recalculadas SOLO cuando cambian `(w, h, unidades)` — cero medición en el tick normal.

### 6.3 Zonas de color de pendiente

Setting on/off (default on): `< −3 %` azul (bajando) · `−3…3` neutro · `3…8` verde · `8…12` amarillo · `> 12` rojo. Contraste según `getBackgroundColor()` (fondo blanco → tonos oscuros; fondo negro → brillantes).

### 6.4 Labels e i18n (patrón A)

- Recursos bilingües: base `resources/` = inglés (fallback), `resources-spa/` = español; `<iq:language>eng|spa</iq:language>` en el manifest.
- Labels: EN `GRADE` / `VAM`; ES `PEND` / `VAM`. App name: `Grade & VAM` / `Pendiente y VAM`.

## 7. Settings (decisión de producto: estas 4 y ninguna más)

Mecanismo re-verificado 2026-07-19 para `datafield` en 3.3: `resources/settings/properties.xml` (defaults) + `settings.xml` (UI) + `Application.Properties.getValue()` (API 2.4) + `AppBase.onSettingsChanged()`. Se editan desde Garmin Connect Mobile / Express (NO on-device — gotcha confirmado, documentarlo en la descripción de la tienda).

| Key | Tipo | Default | Valores | Por qué existe |
|---|---|---|---|---|
| `vamWindowSec` | number (list) | 10 | 5 / 10 / 30 | EL diferenciador vs la VAM nativa fija de 30 s |
| `gradeWindowM` | number (list) | 20 | 10 / 20 / 30 | responsividad vs estabilidad en MTB |
| `primaryMetric` | number (list) | 0 | 0 = grade, 1 = VAM | en SMALL solo entra una métrica |
| `colorZones` | boolean | true | on/off | gustos/contraste |

**Implementación:** leer los 4 valores UNA vez en `initialize()` y recargarlos en `onSettingsChanged()` (cachear en miembros + `engine.setWindows(...)` + `WatchUi.requestUpdate()`). NO llamar `Properties.getValue()` en cada `compute()`.

## 8. Fuera de alcance v1 (anotado para v1.1+)

- **FIT recording** de grade/VAM como developer fields (`FitContributor`, verificado disponible): candidato natural a v1.1.
- **Táctil** (verificado que los datafields de Edge táctiles reciben `onTap`): no en v1 — desbloquea la Opción D.
- Alertas (`showAlert`, API 3.2): no en v1.
- Fuentes/gráficos custom, histéresis de estados subida/bajada (eso es de la Opción C).

## 9. Hooks de debug para el simulador (patrón A §13 — obligatorio)

- **`TEST_MODE`** (`const false` plano): con `true` + build DEBUG, `compute()` ignora `Activity.Info` y consume un **generador sintético de salida** (`(:debug)`): ciclo subida 7 % @ 8 km/h (~90 s) → descenso −10 % @ 30 km/h (~45 s) → llano (~20 s), con ruido gaussiano σ=0,4 m sobre h. Permite ver los 3 modos de render, las zonas de color, VAM negativa y el warm-up sin FIT ni device.
- **Esquema de exclusión del release (idéntico a la A):** guard `if (TEST_MODE)` con const plano `false` (el optimizador `-r` elimina el bloque) + definiciones de debug anotadas `(:debug)` + pares `(:debug)`/`(:release)` para funciones llamadas desde el guard. Cero residuo en release; verificado en la A.

## 10. Unit tests (obligatorios — convención del repo desde 2026-07-19)

Patrón de la A (`TimeFormat.mc`/`TimeFormatTest.mc`): módulos **puros** + funciones **`(:test)`** (`Toybox.Test`), un `<Módulo>Test.mc` junto a cada módulo. Se corren con "Monkey C: Run Tests" (o `monkeydo … -t`); el código `(:test)` queda excluido del release (costo cero contra los 128 KB). Novedades que B necesita y A no tenía, en `TestUtil.mc`:

```monkeyc
(:test) function assertNear(actual, expected, tol, msg) { Test.assertMessage((actual-expected).abs() < tol, msg); }
(:test) function assertIsNumber(x, msg) { Test.assertMessage(x == x, msg); }  // caza NaN
```

Tolerancias: 0,01 para grade %, 0,5 para VAM m/h, 0,05 para conversiones ft/h.

**Suite mínima por módulo** (casos con números concretos — el implementador puede agregar, no quitar):

- **`GradeMath`** — subida normal (Δh=1,4 sobre 20 m → 7,0); descenso (−7,0); guarda `<5 m` (4,9 → null; 5,0 exacto → calcula); fuera de rango → null (Δh=12 sobre 20 m → raw 60 → null; 8/20 = 40,0 exacto NO se descarta); Δd=0 y Δd<0 → null SIN dividir; ningún resultado NaN.
- **`VamMath`** — 1 m en 10 000 ms → 360,0; negativa (−360,0); ventana 30 s (2,5 m/30 s → 300,0); Δt=0 → null (nunca Infinity); Δt=999 → null, 1000 → calcula; llano → 0,0 (cero válido, NO null); usa el Δt real (3,1 m en 31 000 ms → 360,0 aunque la ventana nominal fuera 35 s).
- **`AltFilter`** — primera muestra → ACCEPT; Δh=4,9 → ACCEPT; 5,0 exacto → ACCEPT (regla es `>5`); 5,1 → REJECT; pico recupera (comparación contra la última BUENA, no la rechazada); 3 REJECT consecutivos → RESEED.
- **`SampleBuffer`** — vacío; llenado con integridad de la terna t/d/h; wraparound con cap=4 y con cap producción; `clear()`.
- **`RefSelect`** — el caso clave con velocidad variable (lento 2 m/s → rápido 10 m/s, pendiente constante 7 %): `byDistance(20 m)` y `byTime(10 s)` eligen índices DISTINTOS (prueba que grade usa distancia y VAM tiempo); borde inclusivo; ventana más grande que el buffer → índice 0; `size<2` → −1.
- **`EngineState`** — tabla completa de transiciones (§5.4); `shouldPush` solo ON.
- **`Units`** — ×3,281 con signo preservado; `gradeString`: `+7`, `-8` (half away from zero), `0` sin signo, `--` para null; `vamString` métrico/statute.
- **`GradeVamEngine`** (integración) — cold start (0 y 1 muestras → null); guardas independientes (2 muestras a 2 m: grade null pero VAM 360); input null → no push; PAUSED nunca pushea; **el asesino de picos post-resume** (pausa larga con deriva de h → al reanudar NO hay pico, buffer limpio); salida sintética de 7 % constante → grade estable en 7±1.

## 11. Presupuesto y rendimiento

- Límite real: **128 KB** (idéntico en los 13 devices). Objetivo: **< 64 KB en uso** (simulador, *File → View Memory*).
- Buffer fijo 64×3 (~0,8 KB); sin colecciones dinámicas en régimen; strings reformateados 1×/s como máximo; **cero mediciones/allocations en `onUpdate()`** en el tick normal (todo cacheado, patrón A).

## 12. Criterios de aceptación (cuantificados)

- [ ] Compila sin errores para los 13 targets; el único warning tolerado es el del part number viejo del Edge 1030 (CIQ 3.2.5, inevitable — visto en la A).
- [ ] **Todos los unit tests de §10 en verde** ("Monkey C: Run Tests", perfil edge840).
- [ ] Segmento simulado de pendiente constante (60 s): el grade entero mostrado cambia como máximo 1 paso por update y su desvío estándar ≤ 1 %.
- [ ] Con `vamWindowSec=30`, subida sostenida: la VAM propia coincide con el campo nativo "30s VAM" dentro de **±10 % o ±50 m/h** (lo que sea mayor).
- [ ] **Escalón de presión** (+15 m inyectado en FIT playback): sin pico visible; recuperación (re-seed) en ≤ 3 s; sin quedarse trabado.
- [ ] **Subida lenta** (2,5 km/h, 12 %): grade se muestra (ventana degradada con gracia), sin `--` intermitente.
- [ ] **Descenso rápido** (40 km/h): grade estable (±2 % alrededor del real), VAM negativa correcta.
- [ ] Parado: grade `--`, VAM **0** (por la guarda de parado, no por suerte). Sin NaN/Infinity en ninguna ruta (guardas ANTES de dividir).
- [ ] Arranque sin datos: `--`, no crashea. Pausa/auto-pausa: congelado en gris; al reanudar sin picos (buffer limpiado) y warm-up ≤ W s.
- [ ] **Unidades statute:** ft/h renderiza sin desbordar en los 3 modos (plantilla de 6 glifos).
- [ ] Cambiar cada setting desde el simulador surte efecto sin reiniciar.
- [ ] FIT multi-hora (> 5 h): sin drift de precisión (t como Number).
- [ ] Los 3 modos legibles en layouts de 1, 2 y 10 campos; spot-check en las 6 resoluciones.
- [ ] Label legible en el perfil **edge830** (verificación FONT_GLANCE §6.2).
- [ ] Memoria en régimen < 64 KB.

## 13. Plan de pruebas

1. **Unit tests primero** (§10) — la matemática entera se valida sin simulador.
2. **`TEST_MODE`** (§9): ciclo sintético para ver render/zonas/warm-up sin datos.
3. **Simulación integrada:** Simulator → *Activity Data* (perfil con pendiente variable), ciclo básico + pausa/reanudar/reset.
4. **FIT playback:** un FIT real del Edge del autor con subida y bajada conocidas; validación cruzada contra "30s VAM" nativa y contra lo que Garmin Connect reporta. Incluir: el escalón de presión (editar el FIT o forzar altitud en el sim), un tramo lento (≤ 3 km/h) y un FIT > 5 h.
5. **Unidades:** cambiar el device del sim a statute y re-mirar los 3 modos.
6. Anotar AQUÍ el resultado de la verificación pendiente: ¿`compute()` sigue llamándose con el timer en pausa? (esperado: sí; el diseño no depende de ello gracias al gate por `timerState`).

## 14. Referencias (verificadas 2026-07-13, re-verificadas 2026-07-19)

- `Activity.Info`: https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html
- `WatchUi.DataField`: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html
- `Application.Properties` / settings: https://developer.garmin.com/connect-iq/core-topics/properties-and-app-settings/
- `Toybox.Test` (unit tests): https://developer.garmin.com/connect-iq/api-docs/Toybox/Test.html
- `Graphics` (FONT_SYSTEM_NUMBER_*, FONT_GLANCE 3.1.8): https://developer.garmin.com/connect-iq/api-docs/Toybox/Graphics.html
- Device reference (memoria/pantalla): https://developer.garmin.com/connect-iq/device-reference/
- Campos nativos del Edge 830 (incluye los 4 VAM): manual de usuario, página "Data Fields"
- Patrones heredados: [`apps/a-activity-timer/SPEC.md`](../a-activity-timer/SPEC.md) §5.3 (plantillas/caché), §6 (fuentes/centrado), §8 (iconito), §11.1 (tabla de celdas), §13 (hooks de debug y release)
