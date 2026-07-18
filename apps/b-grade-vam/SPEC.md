# SPEC — `b-grade-vam` (Opción B)

> Data field Connect IQ para Edge 830/840: **pendiente actual (%) + VAM (m/h)** calculadas on-device desde el altímetro barométrico. Especificación de implementación, autocontenida: no requiere leer la conversación previa. La spec maestra del proyecto ([`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md)) da el contexto de producto.
>
> Todos los datos de plataforma citados aquí (nombres de API, niveles, límites de memoria, comportamiento nativo) fueron **verificados contra la documentación oficial de Garmin el 2026-07-13**. No "corregirlos" de memoria.

---

## 1. Objetivo y rol (honesto)

**Hallazgo de la verificación:** el Edge 830 **ya incluye de fábrica** campos nativos de VAM (`VAM`, `30s VAM`, `Avg VAM`, `Lap VAM`) y de pendiente. Un data field que solo muestre VAM duplica funcionalidad nativa.

Por tanto el rol de esta app es:

1. **Vehículo de aprendizaje** (segundo proyecto Monkey C del autor): primera app con algoritmos reales — buffers, suavizado, settings. Las piezas base (proyecto CIQ, `compute()`, render adaptativo, simulador, sideload) llegan aprendidas de la Opción A (`apps/a-activity-timer/`).
2. **Pipeline reutilizable**: el buffer de muestras de altitud/distancia y su suavizado son la base directa de las opciones C (descenso), H (stamina) e I (test de subida).
3. **Diferenciales reales frente a lo nativo** (los únicos motivos para usarla en la calle):
   - **Ambas métricas en un solo campo** (pendiente + VAM juntas; en nativo son dos celdas).
   - **Ventana de suavizado configurable** (la VAM nativa instantánea es una media móvil fija de 30 s; aquí 5/10/30 s a elección).
   - **Zonas de color** para la pendiente (lectura de un vistazo con guantes).

Nota: Connect IQ **no expone** la VAM ni la pendiente nativas por API (`Activity.Info` no tiene esos miembros en 3.3) → hay que calcularlas desde cero. Eso es precisamente lo que queremos aprender.

## 2. Plataforma (verificado)

| Aspecto | Edge 830 | Edge 840 |
|---|---|---|
| ID de dispositivo (manifiesto) | `edge830` | `edge840` |
| API level máx | **3.3** | 6.0 |
| **Límite de memoria — app type `datafield`** | **131 072 B (128 KB)** | 131 072 B (128 KB) |
| Pantalla | 246 × 322 px, rectangular, 65 536 colores, táctil | idéntica |
| Layout de 2 campos (referencia) | ~246 × 160 px por campo | idéntico |

- **Target de compilación: API 3.3.x** (mínimo común; el 840 lo ejecuta sin cambios).
- Tipo de app: `datafield`. Sin permisos especiales (ni Positioning ni Sensor: todo llega por `Activity.Info`).

## 3. Arquitectura

**Clase base: `WatchUi.DataField` completo** (no `SimpleDataField`). Motivo: `SimpleDataField` solo devuelve *un* valor y el sistema lo dibuja; necesitamos dos métricas, layout adaptativo y color → dibujamos nosotros en `onUpdate(dc)`.

Estructura estándar CIQ del proyecto (autocontenida en esta carpeta):

```
b-grade-vam/
├── manifest.xml          # type=datafield; products: edge830, edge840; minApiLevel 3.3.0
├── monkey.jungle
├── source/
│   ├── GradeVamApp.mc   # AppBase: getInitialView() → [view]  (v1 sin delegate táctil)
│   ├── GradeVamView.mc  # DataField: compute(), onLayout(), onUpdate(), hooks de timer
│   └── SampleBuffer.mc   # ring buffer de muestras (reutilizable por C/H/I)
└── resources/
    ├── settings/         # properties.xml + settings.xml (sección 7)
    └── strings/          # strings.xml (label, unidades)
```

Reglas de la clase (verificadas en la doc):
- `compute(info as Activity.Info)` se llama **1×/s** y NO dibuja: solo actualiza estado en miembros.
- `compute()` y `onUpdate()` son **asíncronos sin orden garantizado** → inicializar TODOS los miembros en `initialize()`, jamás asumir que `compute()` corrió antes que `onUpdate()`.
- Tamaño del campo: `dc.getWidth()` / `dc.getHeight()` en `onUpdate()` (el `Dc` ya viene recortado a la celda).
- Fondo: `getBackgroundColor()` (API 1.2) devuelve `COLOR_WHITE` o `COLOR_BLACK` → elegir colores de contraste en cada update.
- `getObscurityFlags()`: en Edge (pantalla rectangular) será normalmente 0; ignorar en v1.

## 4. Entradas — `Activity.Info` (tipos y nulabilidad verificados)

| Campo | Tipo | Unidad | Desde | Notas |
|---|---|---|---|---|
| `altitude` | `Float or Null` | m | 1.0 | barómetro o GPS, el más preciso. **Null hasta tener fuente.** |
| `elapsedDistance` | `Float or Null` | m | 1.0 | null sin fix/actividad |
| `timerTime` | `Number or Null` | **ms** | 1.0 | tiempo de TIMER (no avanza en pausa) — la base temporal correcta |
| `currentSpeed` | `Float or Null` | m/s | 1.0 | solo para display auxiliar |
| `totalAscent` / `totalDescent` | `Float or Null`* | m | 1.0 | *doc inconsistente (declara Number, Returns Float) → tratar como Float |
| `timerState` | `TimerState or Null` | — | 2.1 | `TIMER_STATE_OFF/STOPPED/PAUSED/ON` (0–3) |

**Regla dura: TODOS los campos pueden ser null** → null-check antes de cada uso; sin datos se muestra `--`, nunca se crashea ni se inventa.

Hooks de timer disponibles (API 1.3, todos en `DataField`): `onTimerStart/onTimerStop/onTimerPause/onTimerResume/onTimerReset/onTimerLap`.

⚠️ **No documentado por Garmin** (verificar en simulador, Fase 0): si `compute()` sigue llamándose con el timer en pausa. El conocimiento común dice que sí sigue → **gatear por `timerState == TIMER_STATE_ON`** en vez de confiar en la cadencia de llamadas.

## 5. Algoritmos

### 5.1 Adquisición — ring buffer compartido

En cada `compute()` con datos válidos (`timerState == ON`, `altitude != null`, `elapsedDistance != null`, `timerTime != null`):

```
push {t: timerTime(ms), d: elapsedDistance(m), h: altitude(m)}
```

- **Ring buffer de 32 muestras** (~32 s @1 Hz), tamaño fijo, cero allocations tras `initialize()`.
- **Filtro de outliers barométricos:** si `|Δh| > 5 m` entre muestras consecutivas (imposible en bici: 5 m/s verticales ≈ 18 000 m/h), descartar la muestra (mantener la anterior). Protege de saltos de presión (portazos de coche, viento, túneles).

### 5.2 Pendiente (%)

```
grade = 100 × (h_now − h_ref) / (d_now − d_ref)
```

- Ventana **por distancia, no por tiempo**: `h_ref/d_ref` = muestra más antigua dentro de los últimos `W_grade` metros (default **20 m**, setting 10/20/30 m). Motivo: a velocidad variable (MTB) una ventana temporal da pendientes erráticas en lento y sobre-suavizadas en rápido.
- **Guarda de parado:** si `(d_now − d_ref) < 5 m`, no calcular → mostrar `--` (evita división ruidosa parado o a paso de trialera).
- **Clamp** a ±40 % (fuera de eso es error de datos, no terreno).
- Redondeo a entero para display; signo siempre visible (`+7 %` / `−12 %`).

### 5.3 VAM (m/h)

```
vam = (h_now − h_ref_t) / (t_now − t_ref_t) × 3 600 000    // t en ms
```

- Ventana **temporal** `W_vam` (default **10 s**; setting 5/10/30 s — con 30 s replica la "30s VAM" nativa, útil para validar).
- Mostrar VAM negativa en descenso (con signo); es información válida (velocidad de descenso vertical).
- Nota física: con ruido barométrico de ±0,5 m, una ventana de 5 s tiene error ~±360 m/h; 10 s ~±180; 30 s ~±60. El default de 10 s es el compromiso; documentarlo en la descripción del setting.

### 5.4 Estados y ciclo de vida

- `timerState != ON` (pausa/stop/auto-pause): **congelar** — no push al buffer, display mantiene últimos valores con indicador tenue (p. ej. valores en gris). El buffer NO se contamina con muestras de pausa; al reanudar (`onTimerResume`), **resetear las referencias de ventana** (la primera muestra nueva reinicia ambas ventanas: evita Δt gigantes a través de la pausa).
- `onTimerReset()` (fin de actividad): vaciar buffer, volver a estado inicial.
- Arranque en frío (buffer con < 2 muestras válidas): mostrar `--` en ambas métricas.

### 5.5 Unidades

- Pendiente: `%` universal.
- VAM: respetar `System.getDeviceSettings().elevationUnits` — `UNIT_METRIC` → m/h; `UNIT_STATUTE` → ft/h (×3,281). (Decisión de la spec maestra, pregunta 1: respetar configuración del dispositivo.)

## 6. Render adaptativo (`onUpdate(dc)`)

Decidir modo por `dc.getHeight()` (celda de 246 × 322 total):

| Modo | Condición (alto) | Contenido |
|---|---|---|
| **FULL** | ≥ 200 px | pendiente XL con zona de color + VAM grande + línea auxiliar (velocidad o ascenso total) |
| **HALF** | 90–199 px | pendiente + VAM lado a lado, número grande + etiqueta pequeña |
| **SMALL** | < 90 px | **una** métrica (elegida por setting `primaryMetric`) + etiqueta mínima |

- Fuentes del sistema (`Graphics.FONT_NUMBER_*`), elegidas por altura disponible; **sin fuentes custom** en v1 (memoria).
- **Zonas de color de pendiente** (setting on/off, default on): fondo o número coloreado — `< −3 %` azul (bajando), `−3…3 %` neutro, `3…8 %` verde, `8…12 %` amarillo, `> 12 %` rojo. Ajustar contraste según `getBackgroundColor()` (fondo blanco → colores oscuros; fondo negro → colores brillantes).
- Cero allocations en `onUpdate()`: strings pre-formateados en `compute()` (1×/s) y guardados en miembros; `onUpdate` solo dibuja.

## 7. Settings (editables desde Garmin Connect Mobile)

Mecanismo verificado para `datafield` en 3.3: `resources/settings/properties.xml` (defaults) + `settings.xml` (UI) + `Application.Properties.getValue()` (API 2.4) + `AppBase.onSettingsChanged()` (recargar y `WatchUi.requestUpdate()`).

| Key | Tipo | Default | Valores |
|---|---|---|---|
| `vamWindowSec` | number (list) | 10 | 5 / 10 / 30 |
| `gradeWindowM` | number (list) | 20 | 10 / 20 / 30 |
| `primaryMetric` | number (list) | 0 (grade) | 0 = grade, 1 = VAM |
| `colorZones` | boolean | true | on/off |

## 8. Fuera de alcance v1 (anotado para v1.1+)

- **FIT recording** de grade/VAM como developer fields (`DataField.createField`, API 1.3 — verificado disponible): candidato natural a v1.1; responde la pregunta 3 de la spec maestra.
- **Táctil:** verificado que los data fields de Edge táctiles SÍ reciben `onTap` (vía `[view, delegate]` en `getInitialView()`; debe devolver `true` para evitar el menú de navegación del Edge). No se usa en v1 — anotado porque **desbloquea la Opción D** (crono de tramos) y el ajuste en marcha de la H.
- Alertas (`showAlert`, API 3.2 — disponible): no en v1.
- Fuentes/gráficos custom, histéresis de estados (eso es de la Opción C).

## 9. Presupuesto y rendimiento

- Límite real: **128 KB** para datafield en ambos targets. Objetivo: **< 64 KB en uso** (50 %) medido en el simulador (menú *File → View Memory*).
- Buffer fijo de 32 muestras × 3 valores; sin colecciones dinámicas en régimen; strings reformateados 1×/s como máximo.

## 10. Criterios de aceptación

- [ ] Compila sin warnings con SDK actual, targets `edge830` y `edge840`, `minApiLevel 3.3.0`.
- [ ] En simulador (perfil Edge 830) con actividad simulada que incluya subida: pendiente y VAM muestran valores plausibles y estables (sin parpadeo errático entre updates).
- [ ] Con `vamWindowSec = 30`, la VAM propia coincide aproximadamente con el campo nativo "30s VAM" del simulador (misma actividad, tolerancia razonable) — validación cruzada.
- [ ] Arranque sin datos (sin fix, timer OFF): muestra `--`, no crashea (null-safety total).
- [ ] Pausa/auto-pausa: valores congelados en gris; al reanudar no aparecen picos falsos (ventanas reseteadas).
- [ ] Los 3 modos de render se ven legibles en layouts de 1, 2 y 10 campos del simulador.
- [ ] Cambiar cada setting desde el simulador (App Settings) surte efecto sin reiniciar.
- [ ] Memoria en régimen < 64 KB en el simulador.
- [ ] Parado (velocidad ~0): pendiente muestra `--` (guarda de división), VAM tiende a 0 — sin NaN ni Infinity.

## 11. Plan de pruebas en simulador

1. **Simulación integrada:** Simulator → *Simulation → Activity Data* (perfil con pendiente variable) para el ciclo básico.
2. **FIT playback:** reproducir un FIT real del Edge 830 del autor con subida y bajada conocidas (Simulator → *Simulation → FIT Playback*) y comparar contra los valores que Garmin Connect reporta para ese recorrido.
3. **Casos borde a mano:** timer pause/resume/reset desde el simulador; borrar fix GPS; forzar valores nulos al inicio.
4. Anotar en este archivo el resultado de la verificación pendiente de la sección 4 (¿`compute()` corre en pausa?).

## 12. Referencias (verificadas 2026-07-13)

- `Activity.Info`: https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html
- `WatchUi.DataField`: https://developer.garmin.com/connect-iq/api-docs/Toybox/WatchUi/DataField.html
- Device reference (memoria/pantalla): https://developer.garmin.com/connect-iq/device-reference/ (artículos `edge830.html`, `edge840.html`)
- Compatible devices (API levels): https://developer.garmin.com/connect-iq/compatible-devices/
- Campos nativos del Edge 830 (incluye los 4 VAM): manual de usuario, página "Data Fields"
