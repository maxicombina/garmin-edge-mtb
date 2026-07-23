# SPEC — `j-trend-arrow` (Opción J)

> Data field Connect IQ para Garmin Edge: **flecha de tendencia estilo Cateye** — compara el valor **actual** de una métrica contra su **promedio de la actividad** y dibuja ▲ (por encima), ▼ (por debajo) o nada (dentro de la banda muerta). **MVP = velocidad, con 1 decimal, mostrando actual+flecha Y promedio juntos en el mismo campo** (decisión del autor 2026-07-23: quiere ver ambos números de un vistazo para validar que la flecha tiene sentido). Especificación de implementación, **autocontenida**: no requiere leer ninguna conversación previa. La spec maestra ([`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md) §4 Opción J) da el contexto de producto y la decisión de prioridad. Las apps hermanas — [`apps/a-activity-timer/`](../a-activity-timer/) y [`apps/b-grade-vam/`](../b-grade-vam/) — son la referencia de patrones (fuentes, caché, hooks de debug, tests); **leer ambas SPECs antes de implementar**, en particular A §5.3/6 (escalera de fuentes + caché) y B §6.5 (primitivas `dc` para íconos/flechas).
>
> **Esta app es más simple que la B a propósito.** B necesita un pipeline entero (buffer, filtro de outliers, EMA) porque calcula pendiente y VAM **desde cero** — Connect IQ no las expone. Acá, para el MVP (velocidad), **Garmin ya da el promedio calculado** (`Activity.Info.averageSpeed`) — no hace falta buffer, ni suavizado, ni filtro. `compute()` es casi trivial. Esa es la gracia de empezar por una métrica "Tier 1" (ver §3.1).
>
> ⚠️ **Diferencia de arquitectura importante respecto de la B — leer antes de tocar código:** en la Opción B hay una **regla dura**: el ícono/rampa decorativo va **SOLO junto al label, nunca junto al valor** (es un glifo estático de "esto es pendiente"). **Acá es al revés a propósito:** la flecha va **junto al VALOR actual**, porque la flecha **ES el dato** — cambia de tick a tick según actual-vs-promedio, igual que el número. No es una decoración fija. Si algo en el código de B te hace dudar, esta nota manda para esta app.
>
> ✅ **Glifo `.` verificado en el SIMULADOR, perfil edge840 (2026-07-23) — NO en hardware físico:** `FONT_SYSTEM_NUMBER_MEDIUM` renderiza correctamente `.`, `,`, `:`, `-` y `%`, confirmado con captura de pantalla del simulador corriendo en la pantalla del autor (no de memoria ni de un foro — ver metodología en §2). ⚠️ Esto es **verificación de simulador**, no de dispositivo físico — sigue siendo el estándar que usa el resto del repo para decisiones de fuente (A y B también se validaron primero en simulador), pero no confundir con "probado en el Edge 840 real del autor" (eso es una categoría de verificación distinta y más fuerte en este repo). Esto **simplifica el diseño**: el valor con 1 decimal se dibuja como **un solo string, en una sola fuente** — nada de partir en dos fuentes como el truco del `%` de la B. (Ese hallazgo, de hecho, pone en duda si la B lo necesitaba — ver la nota en §5.2 y en `CLAUDE.md`; **no se toca el código de B** sin que el autor lo pida explícitamente.)

---

## 1. Objetivo y rol (honesto)

1. **Diferencial real frente a lo nativo:** Garmin muestra velocidad actual y velocidad media **en celdas separadas**. Ningún campo nativo combina ambas en un indicador único de tendencia (la flechita del viejo ciclocomputador Cateye del autor, que este proyecto revive). Ese es el único motivo para usarlo en la calle.
2. **v1 muestra AMBOS números, no solo la flecha.** Decisión explícita del autor: en celdas con espacio, el campo dibuja **velocidad actual (grande, con flecha) Y velocidad promedio (más chica, debajo)** en el mismo data field — no solo un indicador binario. Motivo: poder verificar de un vistazo que el promedio es razonable y que la flecha corresponde. En celdas sin espacio para la línea de promedio, se degrada con gracia a mostrar solo actual+flecha (§6).
3. **Arquitectura genérica, aunque el v1 solo la use para una métrica.** El módulo que decide arriba/abajo/nada (`TrendArrow`, §5.1) **no sabe qué métrica está comparando** — recibe dos números ya redondeados y compara. Sumar FC o cadencia más adelante es escribir un adaptador de formato nuevo (§7), no tocar la lógica.
4. **Vehículo de aprendizaje:** primer uso de **primitivas `dc` para una flecha que es DATO** (no decoración estática como en B) — reusa la geometría de `drawUpArrow` de la B pero con una flecha hermana hacia abajo; y primer uso de un **valor con 1 decimal renderizado directo** (sin partir en dos fuentes — ver la nota del glifo verificado arriba).

## 2. Plataforma (heredado, sin re-verificar — ya confirmado para A y B)

Misma plataforma exacta que A y B, sin cambios: **13 Edge devices**, **Edge 840 como referencia**, **API 3.3.x** como target de compilación, tipo de app `datafield`, sin permisos especiales. No hace falta re-derivar nada de esto — copiar tal cual de [`apps/b-grade-vam/SPEC.md`](../b-grade-vam/SPEC.md) §2 (tabla de devices, límite de memoria 128 KB idéntico en los 13, `Graphics.fitTextToArea` NO disponible en 3.3).

**Unidad de velocidad — km/h o mph, NUNCA "m/h" (aclaración importante):** el device da `currentSpeed`/`averageSpeed` en **m/s** (metros por segundo). Se convierte a **km/h** (métrico) o **mph** (millas por hora, imperial) — nunca a "m/h" (metros por hora), que sería una unidad absurdamente chica para velocidad horizontal. (El único lugar del repo donde "m/h" es correcto es la **VAM** de la B — velocidad *vertical* de ascenso, donde metros por hora sí tiene sentido porque los valores son chicos. No confundir los dos casos.)

**Campo de unidad verificado (2026-07-23, doc oficial `Toybox.System.DeviceSettings`):** la unidad de velocidad la gobierna **`System.getDeviceSettings().paceUnits`** (`System.UnitsSystem`, desde API **1.0.0**) — **NO** `distanceUnits` (gobierna la distancia acumulada, campo independiente) ni `elevationUnits` (el que usa la B para la VAM, también independiente). Los tres devuelven el mismo enum compartido `UNIT_METRIC`/`UNIT_STATUTE`, pero cada uno se configura por separado en el device — no asumir que van sincronizados. Igual que `elevationUnits` en la B, no hay garantía documentada de que un cambio de `paceUnits` dispare `onSettingsChanged` (eso es solo para *settings de la app*, no del device) → **releer en cada `compute()`** (barato), mismo patrón que B §5.5.

**Glifos de `FONT_SYSTEM_NUMBER_MEDIUM` — VERIFICADO EN EL SIMULADOR, perfil `edge840` (2026-07-23):** app de prueba desechable, compilada y corrida en el **simulador** (no en hardware físico — el simulador corrió en la pantalla real del autor; el asistente no puede abrir la GUI del simulador desde su propio sandbox, que no tiene sesión de pantalla — ver nota metodológica abajo), dibujando lado a lado `12.3`, `12,3`, `12:34`, `-12`, `12%3` en esa fuente. **Los cinco renderizan correctamente**, incluido el punto decimal. Esto es **más permisivo** que lo que documenta un developer de Garmin en el foro oficial (búsqueda 2026-07-23) para `NUMBER_HOT` en `fenix5xplus`/`vivoactive4s` — ahí también confirma `.`/`%`/`:`/`-` presentes, pero aclara *"not all fonts have all of those glyphs, and some have additional glyphs"* (hay variación real entre device families) y **no cubre ningún Edge**. O sea: la fuente del foro no prueba nada para Edge por sí sola, pero es consistente con lo que el autor confirmó a ojo en el simulador de su propio 840. Se toma como **válido para los 13 devices** con el mismo criterio que el resto de la plataforma (edge840 = referencia, confirmar el 830 si algo se ve raro) — y, como con cualquier hallazgo de solo-simulador en este repo, **queda pendiente de una confirmación eventual en hardware físico** (no bloqueante: A y B también arrancaron validando fuentes en simulador antes del sideload).

## 3. Arquitectura

**Clase base: `WatchUi.DataField` completo** (no `SimpleDataField`) — igual razón que A/B: queremos controlar fuente/formato/color nosotros.

### 3.1 Los dos tiers de métrica (de la spec maestra) y por qué el MVP es "casi gratis"

| Tier | Qué pasa | Ejemplos | Esfuerzo |
|---|---|---|---|
| **1 — Garmin da actual Y promedio** | Se leen dos campos de `Activity.Info`, se convierte a la unidad de display, se compara. **Sin buffer, sin filtro, sin estado propio entre ticks.** | **Velocidad** (`currentSpeed`/`averageSpeed`, MVP), FC (`currentHeartRate`/`averageHeartRate`), cadencia (`currentCadence`/`averageCadence`) | Trivial |
| **2 — hay que derivar el actual y/o el promedio** | Ni Garmin lo expone (VAM/pendiente, como la B), ni tiene promedio nativo (tasa de calorías) | VAM, pendiente, cal/min | Requiere acumular estado propio (ver §8) |

El **MVP implementa SOLO Tier 1 con velocidad**. La arquitectura de abajo ya deja el hueco para Tier 2 sin rediseñar nada (§8), pero **no lo construyas ahora** — sería trabajo no pedido para el v1 (regla del repo: no construir para hipotéticos).

### 3.2 Estructura de archivos

```
j-trend-arrow/
├── manifest.xml               # type=datafield; 13 products; minApiLevel 3.3.0; launcherIcon
├── monkey.jungle               # mínimo (auto-discovery), igual que A y B
├── source/
│   ├── TrendArrowApp.mc        # AppBase: getInitialView() → [view]. SIN settings en v1 (§9) →
│   │                           # no hace falta onSettingsChanged (a diferencia de B).
│   ├── TrendArrowView.mc       # DataField: compute() (wrapper fino) + onUpdate() (render, §6).
│   │                           # NO testeable, lo más chico posible (mismo principio que A/B).
│   ├── TrendArrow.mc           # PURO. Módulo genérico: (actual, promedio) → UP/DOWN/NONE (§5.1)
│   ├── TrendArrowTest.mc       # tests de TrendArrow (§10)
│   ├── SpeedFormat.mc          # PURO. Adaptador Tier-1 de velocidad: m/s → string con 1 decimal (§5.2)
│   ├── SpeedFormatTest.mc      # tests de SpeedFormat (§10)
│   ├── TestUtil.mc             # helpers PLANOS assertNear/assertIsNumber (NO (:test) — ver B §10
│   │                           # gotcha 2). COPIA PROPIA de este archivo — el repo prohíbe compartir
│   │                           # código entre apps salvo decisión explícita (CLAUDE.md); no importar
│   │                           # el TestUtil.mc de la B.
│   └── (ningún módulo de buffer/filtro/EMA — no hace falta para Tier 1, ver §3.1)
├── resources/
│   ├── strings/strings.xml     # AppName, SpeedLabel, AvgLabel (§6.4) — SIN settings/ (v1 no tiene, §9)
├── resources-spa/strings/      # español
└── resources-<device>/drawables/  # ícono launcher, PLACEHOLDER al empezar (copiar el de A/B; rediseñar después)
```

**Nota dura del repo (CLAUDE.md):** "Nada compartido entre apps salvo documentación. Si surge código común, decidir explícitamente." `TestUtil.mc` se **copia**, no se importa desde B. Si en el futuro se decide extraer algo común de verdad, esa es una decisión aparte, explícita, no implícita por comodidad.

Reglas de la clase (idénticas a A/B, no re-derivar): `compute(info)` ~1×/s, no dibuja; `onUpdate(dc)` dibuja, no calcula; sin orden garantizado entre ambos → todo miembro inicializado en `initialize()`.

## 4. Entradas — `Activity.Info` (verificado 2026-07-22 por doc oficial + compile-probe contra el SDK)

| Campo | Tipo | Unidad | Desde | Notas |
|---|---|---|---|---|
| `currentSpeed` | `Float or Null` | m/s | 1.0.0 | null antes del primer fix / parado sin GPS |
| `averageSpeed` | `Float or Null` | m/s | 1.0.0 | promedio de la actividad, calculado por Garmin (probablemente sobre tiempo en movimiento si Auto Pause está activo — detalle no documentado, pero **no importa**: el único requisito es que actual y promedio sean consistentes entre sí, y lo son porque ambos salen del mismo cálculo de Garmin) |
| `timerState` | `TimerState or Null` | — | 2.1.0 | `TIMER_STATE_OFF/STOPPED/PAUSED/ON` (0–3), gatea el atenuado (§6.5, igual que A/B) |

**Regla dura (heredada, sin excepción):** ambos campos de velocidad pueden ser `null` → si cualquiera lo es, no hay flecha (`TrendArrow.NONE`) y ese valor muestra `--`. Nunca crashea, nunca inventa un número.

## 5. Algoritmos

### 5.1 `TrendArrow` — módulo puro, genérico, sin estado

```monkeyc
module TrendArrow {
    const UP   = 1;
    const NONE = 0;
    const DOWN = -1;

    // Ambos argumentos son los ENTEROS YA REDONDEADOS que el usuario ve en pantalla (el mismo
    // valor que se usó para construir el string de display) -- NO los floats crudos. Comparar
    // sobre lo redondeado ES la banda muerta: nunca puede haber una flecha que contradiga al
    // número (si el número muestra el mismo entero, no hay flecha). null en cualquiera -> NONE.
    //
    // Nota (SPEC 5.2): con velocidad a 1 decimal, "el entero redondeado" son en realidad DÉCIMAS
    // (p. ej. 24,3 km/h -> el entero 243) -- a este módulo le da igual la escala, solo compara.
    function classify(shownCurrent as Number or Null, shownAverage as Number or Null) as Number {
        if (shownCurrent == null || shownAverage == null) {
            return NONE;
        }
        if (shownCurrent > shownAverage) { return UP; }
        if (shownCurrent < shownAverage) { return DOWN; }
        return NONE;
    }
}
```

**Por qué esto YA es la banda muerta (simplificación consciente respecto de la spec maestra):** la spec maestra describe la banda muerta como "sin flecha si `round(actual) == round(promedio)`". En vez de pasarle floats crudos + un parámetro de paso de redondeo a `TrendArrow`, la **View redondea una sola vez** (con la misma función que usa para el string de pantalla, `SpeedFormat.shownTenths`, §5.2) y le pasa a `classify` los dos ENTEROS ya redondeados. Resultado idéntico, una función más simple, y **imposible que el número y la flecha se contradigan** (comparten la misma fuente de redondeo). Documentado acá para que quien lea la spec maestra y compare con el código no piense que hay una discrepancia — es un refinamiento de diseño, no una desviación.

**Consecuencia de mostrar 1 decimal (leer antes de sorprenderse con el comportamiento):** al comparar sobre **décimas** de km/h (paso de display 0,1) en vez de km/h enteros (paso 1), la banda muerta es **10 veces más fina** → la flecha reacciona a diferencias mucho más chicas. Con **sensor de rueda** (el del autor) esto es aceptable porque la lectura es limpia. Si en el futuro se prueba con GPS solo y la flecha titila cerca del cruce, ver la nota de histéresis abajo.

**Nota de diseño (SECUNDARIO — no implementar salvo que se pida):** la spec maestra deja abierta una histéresis/persistencia opcional si la flecha parpadea cerca del cruce. **No implementar en v1.** Si hiciera falta, el patrón ya existe en la B: `STOP_PERSIST_TICKS` en `GradeVamEngine.mc` (contador de N ticks consecutivos antes de cambiar de estado) — mismo idioma, aplicado a `TrendArrow` en vez de al guard de VAM.

### 5.2 `SpeedFormat` — módulo puro, adaptador Tier-1 de velocidad, con 1 decimal

**El valor se dibuja como UN SOLO string, en UNA SOLA fuente** (sin partir en dos como el truco del `%` de la B) — porque el glifo `.` **está confirmado presente** en `FONT_SYSTEM_NUMBER_MEDIUM`, verificado en el simulador de perfil edge840 (§2). No hace falta la maquinaria de fuente-de-texto-proporcional que sí necesita el `%` en algunas circunstancias.

⚠️ **Nota que invita a reconsiderar la B (NO tocarla ahora sin que el autor lo pida):** este mismo hallazgo también contradice, al menos parcialmente, la razón original por la que B dibuja `%` en una fuente de texto aparte (`apps/b-grade-vam/source/GradeVamView.mc`, `drawGradeBlock`) — ver el detalle en `CLAUDE.md`. El código de B **sigue funcionando perfecto tal cual está** (no es un bug); esto solo significa que quizás no hacía falta tanta ceremonia. Queda anotado, no actuado.

**Por qué la construcción del string se hace con enteros, no formateando el float directo (esto SÍ sigue aplicando, es independiente del hallazgo del glifo):** `v.toString()` sobre un `Float` en Monkey C puede arrastrar ruido de punto flotante (p. ej. `24.299999...`). Para evitarlo, se redondea a **décimas como un `Number` entero** (`243` para 24,3) y se separa por aritmética entera (`/10`, `%10`) antes de armar el string — cero ambigüedad, cero ruido. Esta función (`shownTenths`) es además la ÚNICA fuente de redondeo del módulo: tanto el string de pantalla como la comparación de `TrendArrow` (§5.1) parten del mismo entero — por construcción, número y flecha nunca pueden contradecirse.

```monkeyc
module SpeedFormat {
    const KMH_PER_MPS = 3.6;       // exacto: 1 m/s = 3600 s/h / 1000 m/km
    const MPH_PER_MPS = 2.23694;   // 1 m/s = 3600 / 1609.344 mph (1609.344 m/milla, exacto)

    // m/s -> unidad de display (float, SIN redondear). null-safe.
    function toDisplayUnit(mps as Float or Null, statute as Boolean) as Float or Null {
        if (mps == null) {
            return null;
        }
        return statute ? (mps * MPH_PER_MPS) : (mps * KMH_PER_MPS);
    }

    // Entero, half away from zero (7.5 -> 8, -7.5 -> -8) -- misma función que Units.roundHalf en
    // la B (COPIA propia, no importada -- ver la nota de "nada compartido" en §3.2).
    function roundHalf(x as Float) as Number {
        if (x >= 0) {
            return (x + 0.5).toNumber();
        }
        return (x - 0.5).toNumber();
    }

    // El valor de display redondeado a la DÉCIMA más cercana, expresado como un ENTERO que
    // cuenta décimas (243 para 24,3; -13 para -1,3). ÚNICA función de redondeo del módulo (ver
    // nota de arriba): la comparte displayString() y TrendArrow.classify(). null-safe.
    function shownTenths(mps as Float or Null, statute as Boolean) as Number or Null {
        var v = toDisplayUnit(mps, statute);
        if (v == null) {
            return null;
        }
        return roundHalf(v * 10.0);
    }

    // String final "24.3" / "-1.3" / "--" a partir de un conteo de décimas YA REDONDEADO (el que
    // devuelve shownTenths). Se arma por aritmética ENTERA (whole = |tenths|/10, dec = |tenths|%10)
    // para no arrastrar ruido de punto flotante -- NO usar tenths/10.0 + toString() directo.
    function displayString(tenths as Number or Null) as String {
        if (tenths == null) {
            return "--";
        }
        var sign = (tenths < 0) ? "-" : "";
        var absT = (tenths < 0) ? -tenths : tenths;
        var whole = absT / 10;      // división entera
        var dec = absT % 10;
        return sign + whole.toString() + "." + dec.toString();
    }

    function unitLabel(statute as Boolean) as String {
        return statute ? "MPH" : "KM/H";
    }
}
```

### 5.3 `compute()` de la View — casi trivial (sin pipeline, a diferencia de la B)

```
1. mIsStatute = (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE)   // releer cada tick (§2)
2. state = info.timerState (null-safe); mRunning = (state == Activity.TIMER_STATE_ON)
3. curTenths = SpeedFormat.shownTenths(info.currentSpeed, mIsStatute)
4. avgTenths = SpeedFormat.shownTenths(info.averageSpeed, mIsStatute)
5. mCurStr = SpeedFormat.displayString(curTenths)
6. mAvgStr = SpeedFormat.displayString(avgTenths)
7. mArrowState = TrendArrow.classify(curTenths, avgTenths)
8. mUnitLabel = SpeedFormat.unitLabel(mIsStatute)
```

Eso es **todo** — sin buffer, sin push, sin filtro. `onUpdate()` solo dibuja `mCurStr`/`mAvgStr`/`mArrowState`/`mUnitLabel`, cero formateo por tick (mismo principio A/B: `compute()` calcula y formatea, `onUpdate()` solo dibuja).

## 6. Render adaptativo (`onUpdate(dc)`)

### 6.1 Un layout continuo con dos valores (NO 3 modos como la B, pero SÍ dos números)

A diferencia del diseño inicial de esta spec, **v1 muestra DOS valores**: actual (grande, con flecha) y promedio (más chico, debajo) — decisión del autor (§1). No hace falta el sistema FULL/HALF/SMALL de la B (que existe porque ahí las dos métricas son independientes y del mismo tamaño); acá hay una jerarquía clara (actual = protagonista, promedio = apoyo), así que basta con **una banda secundaria más chica debajo del valor principal**, con su propio umbral de alto — el mismo espíritu que la línea auxiliar de `totalAscent` en el modo FULL de la B (`drawAscentAux`), aplicada acá al promedio.

- **Label** (opcional, umbral de alto): `LABEL_MIN_H = 60` px — el mismo valor ya validado de la A en las 6 resoluciones, reusado tal cual (la forma de esta celda es la misma que la de la A: valor(es) grandes + label arriba).
- **Línea de promedio** (opcional, umbral de alto MAYOR): `AVG_MIN_H = 110` px — un valor intermedio entre la "media fila" (~65 px, medida en A) y el "ancho completo mixto" (~137 px, medida en A): en celdas chicas NO hay espacio para una 3ª línea, así que se omite con gracia y el campo se degrada a "solo actual + flecha" (ningún dato se pierde de forma confusa: sigue siendo un indicador de tendencia útil). **Recalibrar en el simulador** con las 6 resoluciones, como se hizo con `LABEL_MIN_H` en la A.
- **Valor + flecha**: la flecha va **junto al número actual** (no al label — ver la nota de arquitectura al principio del documento), a la izquierda, como en el Cateye original. El promedio **no lleva flecha** (es la referencia, no el dato que se compara).

### 6.2 Constantes de layout

```monkeyc
const PAD = 3;              // padding horizontal por lado (igual que B)
const LABEL_MARGIN = 4;     // px arriba del label (igual que A/B)
const LABEL_MIN_H = 60;     // umbral para mostrar el label (heredado de A, validado en 6 resoluciones)
const AVG_MIN_H = 110;      // umbral para mostrar la línea de promedio (nuevo, a validar en sim)
const AVG_BAND_PCT = 35;    // % de la altura post-label reservado a la línea de promedio (el resto
                             // es para el valor actual) -- mismo idioma que HALF_GRADE_PCT de B
const ARROW_GAP = 4;        // px entre la flecha y el valor actual (igual que GRADE_ICON_GAP de B)
const AVG_LABEL_GAP = 4;    // px entre el prefijo "AVG"/"PROM" y el número de promedio
const VALUE_NUDGE = 2;      // px: mismo nudge fino que A/B para centrar ópticamente el valor
const ARROW_NUDGE = 2;      // px: mismo nudge fino que B usó para alinear la flecha con el texto
const VALUE_TPL = "888.8";  // plantilla de ancho estable: 3 dígitos enteros + "." + 1 decimal
                             // (cubre 0.0-999.9; la velocidad no lleva signo en la práctica)
```

### 6.3 Fuentes (herencia directa de A/B — reusar tal cual, sin reinventar)

- **Escalera numérica, idéntica a A/B** (mismo array, mismo orden, ya validado en device) — se usa TANTO para el valor actual como para el promedio (cada uno elige su propio tamaño dentro de su banda, ver §6.4). **Ya no hace falta una escalera de fuente de texto** (`mTextLadder` de la B): con el `.` confirmado en la fuente numérica (§2), todo el string `"24.3"` se dibuja en UNA sola fuente de esta escalera:
  ```
  mLadder = [FONT_SYSTEM_NUMBER_THAI_HOT, FONT_SYSTEM_NUMBER_HOT, FONT_SYSTEM_NUMBER_MEDIUM,
             FONT_SYSTEM_NUMBER_MILD, FONT_MEDIUM, FONT_SMALL, FONT_TINY, FONT_XTINY]
  ```
- **Label: `FONT_GLANCE`, en MAYÚSCULAS**, reservando solo `ascent` + margen — mismo patrón A/B, misma salvedad del edge830 sin glance font (B §6.2) a verificar en el simulador con ese perfil.
- **Prefijo "AVG"/"PROM": `FONT_XTINY` FIJO** (no ladder) — mismo patrón que el header `"PEND/VAM"` de B en modo SMALL: es una etiqueta chica de apoyo, no necesita escalar.
- La unidad va en el label del valor actual (`"SPEED KM/H"`, igual que B con `"VAM M/H"`) — no se repite en la línea de promedio (ya está implícita: mismo campo, misma unidad).
- **Selección con caché**, igual patrón que A/B: recalcular SOLO cuando cambia `(w, h, mIsStatute)`. (Nota: `VALUE_TPL` en sí no cambia de ancho entre km/h y mph — a diferencia del template de VAM en B, que sí pasa de 5 a 6 glifos entre m/h y ft/h — así que `mIsStatute` no es estrictamente necesario en la clave de fuente; se incluye igual porque el LABEL sí cambia de texto con la unidad, y mantiene la caché con el mismo criterio conservador que el resto del repo.)

### 6.4 Selección de fuentes (algoritmo completo)

```
selectFonts(dc, usableW, h, labelH):
    postLabelH = h - labelH
    mShowAvg = (h >= AVG_MIN_H)
    if mShowAvg:
        primaryBandH = (postLabelH * (100 - AVG_BAND_PCT)) / 100
        avgBandH = postLabelH - primaryBandH
    else:
        primaryBandH = postLabelH
        avgBandH = 0

    // --- Fuente del valor ACTUAL + flecha ---
    mArrowFits = false
    for f in mLadder (mayor a menor):
        if getFontHeight(f) > primaryBandH * 0.9: continue
        ah = getFontAscent(f) * 4 / 5          // MISMA proporción que drawUpArrow/drawAscentAux de B
        aw = ah * 3 / 5                        // (apps/b-grade-vam/source/GradeVamView.mc:520-521)
        groupW = aw + ARROW_GAP + getTextWidthInPixels(VALUE_TPL, f)
        if groupW <= usableW:
            mValueFont = f; mArrowFits = true; break

    if (no se encontró ninguna en el paso anterior):
        // La flecha no entró en NINGÚN tamaño (celda muy angosta) -> fallback gracioso: soltar
        // la flecha y probar el valor solo (MISMO idioma que B usa para su rampa: si el grupo
        // decorado no entra, se cae al elemento esencial solo).
        for f in mLadder:
            if getTextWidthInPixels(VALUE_TPL, f) <= usableW and getFontHeight(f) <= primaryBandH * 0.9:
                mValueFont = f; mArrowFits = false; break
        si ninguna entra: mValueFont = FONT_XTINY; mArrowFits = false

    // --- Fuente del PROMEDIO (sin flecha, con su propio prefijo de texto fijo) ---
    if mShowAvg:
        prefixW = getTextWidthInPixels(mAvgPrefix, FONT_XTINY)   // "AVG" o "PROM"
        for f in mLadder (mayor a menor):
            if getFontHeight(f) > avgBandH * 0.85: continue
            groupW = prefixW + AVG_LABEL_GAP + getTextWidthInPixels(VALUE_TPL, f)
            if groupW <= usableW:
                mAvgFont = f; break
        si ninguna entra: mAvgFont = FONT_XTINY
```

**Label del valor actual:** `mLabel` = string cargado una vez de `Rez.Strings.SpeedLabel` en `initialize()`, en MAYÚSCULAS (mismo patrón que `mGradeLabel` en B). Se dibuja como `mLabel + " " + SpeedFormat.unitLabel(mIsStatute)`, p. ej. `"SPEED KM/H"` (igual patrón que B con `"VAM M/H"`).

### 6.5 Dibujo (`onUpdate`)

```
1. w = dc.getWidth(); h = dc.getHeight()
2. Colores: fg = mRunning ? color-tema-normal : gris-atenuado; dc.setColor(fg,bg); dc.clear()
            (tabla idéntica a A §6.4 / B onUpdate)
3. labelShow = (h >= LABEL_MIN_H)
   labelH = labelShow ? (LABEL_MARGIN + getFontAscent(FONT_GLANCE) + 2) : 0
   mShowAvg = (h >= AVG_MIN_H)   // implica labelShow, porque AVG_MIN_H > LABEL_MIN_H
4. Caché: si (w,h,mIsStatute) cambió -> selectFonts(dc, w - 2*PAD, h, labelH)  -- pasa h TOTAL y
          labelH para que selectFonts calcule postLabelH = h - labelH internamente
5. Si labelShow: drawText(w/2, LABEL_MARGIN, FONT_GLANCE, mLabel + " " + mUnitLabel, CENTER)

6. -- bandas verticales --
   postLabelH = h - labelH
   if mShowAvg:
       primaryBandH = (postLabelH * (100 - AVG_BAND_PCT)) / 100
       avgBandH = postLabelH - primaryBandH
   else:
       primaryBandH = postLabelH; avgBandH = 0
   primaryCy = labelH + primaryBandH/2 + getFontDescent(mValueFont)/2 - VALUE_NUDGE

7. -- valor ACTUAL + flecha --
   wValue = dc.getTextWidthInPixels(mCurStr, mValueFont)   // ancho del string VIVO (posición, no
            // nivel/fuente -- ya se decidió con la plantilla estable en el paso 4)
   showArrow = mArrowFits && (mArrowState != TrendArrow.NONE) && !mCurStr.equals("--")
   if showArrow:
       ah = getFontAscent(mValueFont) * 4 / 5
       aw = ah * 3 / 5
       totalW = aw + ARROW_GAP + wValue
       x = w/2 - totalW/2
       arrowCy = primaryCy - getFontDescent(mValueFont)/2 + ARROW_NUDGE   // mismo truco que B:
              // la flecha se alinea con los GLIFOS VISIBLES del número, no con su caja completa
       if mArrowState == TrendArrow.UP:   drawUpArrow(dc, x, arrowCy, aw, ah)
       else:                              drawDownArrow(dc, x, arrowCy, aw, ah)
       dc.drawText(x + aw + ARROW_GAP, primaryCy, mValueFont, mCurStr, LEFT | VCENTER)
   else:
       // Sin flecha (NONE, sin dato, o no entraba): el string se CENTRA solo, sin reservar el
       // hueco de la flecha (decisión de la spec maestra: "sin flecha = no se dibuja nada, sin
       // reservar hueco molesto" -- el número se corre un poco cuando la flecha aparece/
       // desaparece, comportamiento del Cateye original, aceptado).
       dc.drawText(w/2, primaryCy, mValueFont, mCurStr, CENTER | VCENTER)

8. -- línea de PROMEDIO (solo si mShowAvg) --
   if mShowAvg:
       avgCy = labelH + primaryBandH + avgBandH/2 + getFontDescent(mAvgFont)/2 - VALUE_NUDGE
       wAvg = dc.getTextWidthInPixels(mAvgStr, mAvgFont)
       prefixW = dc.getTextWidthInPixels(mAvgPrefix, FONT_XTINY)
       totalAvgW = prefixW + AVG_LABEL_GAP + wAvg
       x = w/2 - totalAvgW/2
       dc.setColor(fg, TRANSPARENT)
       dc.drawText(x, avgCy, FONT_XTINY, mAvgPrefix, LEFT | VCENTER)
       dc.drawText(x + prefixW + AVG_LABEL_GAP, avgCy, mAvgFont, mAvgStr, LEFT | VCENTER)
```

`mAvgPrefix` = string cargado una vez (`Rez.Strings.AvgLabel`, en MAYÚSCULAS, `"AVG"`/`"PROM"`), igual patrón que `mGradeLabel`/`mVamLabelBase` en B.

### 6.6 Primitivas de flecha (reusar + espejar)

**Reusar tal cual** `drawUpArrow` de la B (`apps/b-grade-vam/source/GradeVamView.mc:536-544`): cabeza triangular rellena (`fillPolygon`) + tallo rectangular (`fillRectangle`), ocupando `[x0, x0+w]` de ancho y centrada verticalmente en `cyMid` con alto `h`.

```monkeyc
// COPIA de apps/b-grade-vam/source/GradeVamView.mc:536-544 (misma firma, mismo cuerpo).
private function drawUpArrow(dc as Graphics.Dc, x0 as Number, cyMid as Number, w as Number, h as Number) as Void {
    var top = cyMid - h / 2;
    var headH = (h * 55) / 100;
    var headBase = top + headH;
    dc.fillPolygon([[x0 + w / 2, top], [x0, headBase], [x0 + w, headBase]]);
    var stemW = w / 3;
    if (stemW < 2) { stemW = 2; }
    dc.fillRectangle(x0 + w / 2 - stemW / 2, headBase, stemW, h - headH);
}

// NUEVA: espejo vertical exacto de drawUpArrow -- cabeza abajo (ápice apuntando hacia abajo),
// tallo arriba. Misma proporción de cabeza (55% del alto), mismo grosor de tallo.
private function drawDownArrow(dc as Graphics.Dc, x0 as Number, cyMid as Number, w as Number, h as Number) as Void {
    var bot = cyMid + h / 2;
    var headH = (h * 55) / 100;
    var headTop = bot - headH;
    dc.fillPolygon([[x0 + w / 2, bot], [x0, headTop], [x0 + w, headTop]]);
    var stemW = w / 3;
    if (stemW < 2) { stemW = 2; }
    dc.fillRectangle(x0 + w / 2 - stemW / 2, cyMid - h / 2, stemW, h - headH);
}
```

Color: `fg` (el mismo que el texto, atenuado en pausa) — la flecha comparte el color del valor, no un color de zona (esta app no tiene zonas de color).

⚠️ **Gotcha ya conocido (documentado en B):** `fillPolygon` espera `Array<[Numeric, Numeric]>` (tupla) — pasar el literal `[[x,y],[x,y],[x,y]]` **sin cast**. Un `as Array<Array<Number>>` rompe el build (visto y corregido en la B).

### 6.7 Centrado vertical (regla dura del repo — NO re-descubrir)

Ídem A §6.7 / B §6.2 / spec maestra §3.4: las fuentes `FONT_SYSTEM_NUMBER_*` reservan un descendente que los dígitos no usan → `cY += getFontDescent(font)/2` al centrar el valor; el label reserva solo su `ascent` + margen. Ya está en el algoritmo de §6.5 arriba (aplicado tanto al valor actual como a la línea de promedio, cada uno con el descent de SU PROPIA fuente) — mencionado acá solo para que quede explícito el POR QUÉ.

### 6.8 Modo ancho INLINE (EXPERIMENTAL — 2026-07-23, a probar en el simulador)

Además del layout apilado de §6.1 (actual grande + flecha, promedio en línea secundaria debajo), en **celdas full-width** el campo muestra **ambos valores en UNA sola línea**: `[flecha] actual / promedio` (p. ej. `▲ 24.1 / 15.0`), con el **label nombrando las dos columnas**: `SPEED / AVG KM/H` (`VEL / PROM KM/H` en ES). Pedido del autor para ver de un vistazo actual-vs-promedio en fila ancha; **es un experimento de layout, el final se decidirá mirándolo en el sim** ("al menos para probarlo").

- **Detección de "ancho del todo":** se compara el ancho de la celda contra el **ancho de pantalla del device** (`System.getDeviceSettings().screenWidth`): `mIsWide = (w * WIDE_DEN >= screenW * WIDE_NUM)` con `WIDE_NUM=8, WIDE_DEN=10` → **celda ≥ 80 % del ancho de pantalla**. Así una fila full-width entra en modo inline, y una media-columna (~50 %) NO. `screenWidth` está presente en todos los devices (CIQ 1.0.0); guarda `!= null` por robustez.
- **Fuente:** misma escalera numérica, mayor tamaño cuyo grupo `[flecha + gap + "888.8 / 888.8"]` (plantilla `INLINE_TPL`) entra a lo ancho, con tope de alto contra la banda post-label. Fallback: si la flecha no entra a ningún tamaño, se descarta y se ajusta solo el par (mismo idioma que el fallback de §6.4).
- **Flecha:** es la tendencia del **actual vs promedio** (misma `classify()` que el modo apilado), precede a TODO el par. Mismo centrado `descent/2 + ARROW_NUDGE` que el valor apilado (§6.7).
- **La flecha sigue siendo DATO** (va con el valor, no con el label) — la regla de arquitectura no cambia; solo cambia que en fila ancha el "valor" es el par actual/promedio en vez del actual solo.
- El modo apilado (no-ancho) queda **idéntico**; `mShowAvg` se fuerza a `false` en modo ancho (el promedio ya está inline).
- Constantes nuevas: `WIDE_NUM=8`, `WIDE_DEN=10`, `INLINE_SEP=" / "`, `INLINE_TPL="888.8 / 888.8"`. Implementado en `TrendArrowView.mc` (`selectInlineFont` + `drawTrendValue`, branch en `selectFonts`/`onUpdate`). Compila limpio (release 840+830, `-w`) y tests verdes (los módulos puros no cambian). **PENDIENTE:** validación visual del autor en el sim (afinar si el umbral 80 % y los tamaños se ven bien en las 6 resoluciones).

### 6.9 Unidad estilo NATIVO (apilada a la derecha del número — 2026-07-23)

Tras comparar contra el campo nativo del Edge (capturas `b-grade-vam/screenshots/2026-07-20-21-04-51.BMP` = "VELOCIDAD 13.3 km/h" y `…22-37-12.BMP` = "VELOCIDAD MEDIA 13.8 km/h"), el autor pidió **hacerlo como el nativo**: la unidad **NO va en el label**, sino como un **`km/h` chiquito apilado en dos líneas (`km` sobre `h`) a la derecha del número**, arriba (como superíndice). El label pasa a ser solo el nombre de la métrica.

- **`SpeedFormat` (puro):** nuevas `unitTop(statute)`/`unitBottom(statute)` → métrico `["km","h"]`, statute `["mph",""]` (bottom vacío = una sola línea). Minúsculas, como el nativo. `unitLabel` (mayúsculas) queda pero **ya no se usa en el render** (sí en su test). Test `testUnitParts` (10 tests en total ahora).
- **Label:** apilado → solo `mLabel` (p.ej. `SPEED`/`VEL`); ancho → `mLabel / mAvgPrefix` (p.ej. `SPEED / AVG`). Se quitó el `" " + unidad` del label en ambos.
- **Dibujo:** helper único `drawTrendValue(dc,w,fg,font,str,cy,showArrow)` dibuja `[flecha] valor [unidad apilada]` como un grupo centrado (lo usan el valor primario apilado Y la línea ancha). Helpers `unitBlockWidth` (ancho = máx de las dos líneas) y `drawStackedUnit`. La línea de promedio también lleva su unidad chica.
- **Alineación vertical de la unidad — a la BASE del número (2026-07-23, tras captura nativa):** el nativo apoya el `km/h` **abajo**: la `h` se sienta sobre la misma línea base que los pies de los dígitos (NO como superíndice arriba). `drawStackedUnit(dc, x, baseY, font)` recibe la **baseline objetivo** y coloca la línea de abajo con su baseline en `baseY` y la de arriba un `ascent` por encima (juntas). Para un valor dibujado con `VCENTER` en `cy`, la baseline del número es `baseY = cy + (ascent − descent)/2 + UNIT_BOTTOM_NUDGE`. (Para statute, una sola línea `mph` con su baseline en `baseY`.)
- **Selección de fuentes:** todas las plantillas de ancho ahora reservan `+ UNIT_GAP + unitBlockWidth(FONT_XTINY)` (primario, fallback sin flecha, promedio y ancho) para que número+unidad no desborden.
- **Constantes nuevas:** `UNIT_GAP=3`, `UNIT_BOTTOM_NUDGE=0` (positivo empuja la unidad HACIA ABAJO; nudge fino a afinar en el sim — mismo idioma que `VALUE_NUDGE`/`ARROW_NUDGE`). Unidad en `FONT_XTINY` fija.
- Compila limpio (release 840+830, `-w`) + **10/10 tests verdes**. **PENDIENTE (autor):** afinar en el sim el `UNIT_BOTTOM_NUDGE` (alto exacto de la unidad respecto de los dígitos) y confirmar que `km`/`h` no pisa el número ni se sale de la celda en las resoluciones chicas.

## 7. Extender a otras métricas Tier 1 (documentado, NO implementar en v1)

Sumar FC o cadencia más adelante es, literalmente:
1. Un módulo `HeartRateFormat.mc` (o `CadenceFormat.mc`) análogo a `SpeedFormat.mc` — **sin conversión de unidad** (bpm/rpm ya son el valor nativo, sin metric/statute) **y probablemente sin decimal** (bpm/rpm se muestran enteros de forma nativa) — así que es MÁS simple que `SpeedFormat` en los dos sentidos.
2. Cambiar en `compute()` los dos campos leídos (`currentHeartRate`/`averageHeartRate` en vez de `currentSpeed`/`averageSpeed`) y el label/unidad.
3. **`TrendArrow.mc` no cambia ni un carácter** — ya es genérico.

Esto no es una promesa de v1.1, es solo la prueba de que la arquitectura cumple el objetivo "genérica" de la spec maestra sin haber construido nada de más ahora (regla del repo: no diseñar para hipotéticos).

## 8. Fuera de alcance v1 (Tier 2 — anotado para más adelante)

- **VAM/pendiente con flecha de tendencia:** requiere un **promedio propio acumulado** (no lo da Garmin) además del valor actual ya suavizado de la B. Fórmula del promedio incremental (derivada y verificada en conversación con el autor, 2026-07-22 — **no reinventar**, copiar):
  ```
  avg_n = avg_{n-1} + (x - avg_{n-1}) / n
  ```
  Es matemáticamente idéntica a `suma/n`, pero sin arrastrar una suma que crece sin límite (mejor higiene numérica en una salida de horas). **Memoria: 2 variables (`avg`, `n`)**, sin importar cuántas muestras pasen. Con `paso = 1/n` da el promedio de TODA la actividad (memoria "infinita", como pide el Cateye); con un `paso = α` FIJO (en vez de `1/n`) da un **EMA** — la misma fórmula, memoria "corta" (sigue lo reciente, olvida lo viejo) — útil si se quiere la variante "ventana móvil" del §7 de la spec maestra.
- **Tasa de calorías con flecha:** `energyExpenditure` da el actual (kcal/min); el promedio se deriva de `calories` (acumulado) / tiempo transcurrido — es un caso de **tasa** (como la velocidad), así que su promedio real es gratis: `caloríasTotales / tiempoTotal`, sin necesitar el acumulador incremental de arriba (ese es solo para métricas escalares tipo FC/temperatura, no tasas).
- **Setting de métrica objetivo, ancho de banda muerta, promedio global vs. ventana móvil:** dejados fuera del v1 a propósito (ver §7 de la spec maestra) — el v1 es 100 % hardcodeado a velocidad + promedio global de la actividad, **cero settings**, para minimizar superficie de implementación (ver §9).
- **Temperatura:** de valor dudoso para esta feature (no es miembro de `Activity.Info`, sesgada por el calor del propio equipo) — descartada, no solo pospuesta.

## 9. Settings: NINGUNO en v1 (decisión de producto — como la Opción A)

A diferencia de la B (4 settings), esta app **no tiene ningún setting en v1**: métrica fija = velocidad, promedio = global de la actividad, banda muerta = implícita en el redondeo a décimas (§5.1). Mismo patrón que A §7 ("No hay — decisión de producto: sin opciones"). Esto significa: **sin `resources/settings/`, sin `properties.xml`, sin `settings.xml`, sin `onSettingsChanged` en `TrendArrowApp.mc`** — el `AppBase` es literalmente `initialize()` + `getInitialView()`, nada más.

## 10. Unit tests (obligatorio — convención del repo desde 2026-07-19)

Patrón exacto de A/B: módulos puros + funciones `(:test)` de `Toybox.Test`, un `<Módulo>Test.mc` por módulo, helpers de `TestUtil.mc` **planos** (NO `(:test)` — el runner ejecuta toda función `(:test)` como caso; ver B §10 gotcha 2). Para comparar contra `null` usar **`Test.assertMessage(x == null, ...)`**, NUNCA `Test.assertEqualMessage(x, null, ...)` (invoca `.equals()` sobre el actual y explota si es `null` — gotcha ya descubierto en B).

**`TrendArrowTest.mc` — casos concretos:**
```monkeyc
(:test)
function testTrendArrowUp(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(253, 240), TrendArrow.UP, "25.3 > 24.0 -> UP");
    Test.assertEqualMessage(TrendArrow.classify(-50, -100), TrendArrow.UP, "-5.0 > -10.0 -> UP");
    return true;
}

(:test)
function testTrendArrowDown(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(150, 200), TrendArrow.DOWN, "15.0 < 20.0 -> DOWN");
    Test.assertEqualMessage(TrendArrow.classify(-100, -50), TrendArrow.DOWN, "-10.0 < -5.0 -> DOWN");
    return true;
}

(:test)
function testTrendArrowNone(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(200, 200), TrendArrow.NONE, "equal -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(0, 0), TrendArrow.NONE, "zero == zero -> NONE");
    return true;
}

(:test)
function testTrendArrowNullSafety(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(null, 200), TrendArrow.NONE, "null current -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(200, null), TrendArrow.NONE, "null average -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(null, null), TrendArrow.NONE, "both null -> NONE");
    return true;
}
```

**`SpeedFormatTest.mc` — casos concretos** (tolerancia 0,001 para conversiones exactas (km/h, `KMH_PER_MPS` es exacto), 0,01 para conversiones con constante redondeada (mph, `MPH_PER_MPS` redondeado a 5 cifras) — mismo criterio de B para ft/h):
```monkeyc
(:test)
function testToDisplayUnit(logger as Test.Logger) as Boolean {
    TestUtil.assertNear(SpeedFormat.toDisplayUnit(10.0, false), 36.0, 0.001, "10 m/s -> 36.0 km/h exact");
    TestUtil.assertNear(SpeedFormat.toDisplayUnit(10.0, true), 22.3694, 0.01, "10 m/s -> mph");
    Test.assertMessage(SpeedFormat.toDisplayUnit(null, false) == null, "null -> null");
    return true;
}

(:test)
function testSpeedRoundHalf(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.roundHalf(7.5), 8, "7.5 -> 8");
    Test.assertEqualMessage(SpeedFormat.roundHalf(-7.5), -8, "-7.5 -> -8 (robustez, aunque velocidad no es negativa en la práctica)");
    Test.assertEqualMessage(SpeedFormat.roundHalf(7.4), 7, "7.4 -> 7");
    return true;
}

(:test)
function testShownTenths(logger as Test.Logger) as Boolean {
    // 10 m/s -> 36.0 km/h -> 360 décimas exacto
    Test.assertEqualMessage(SpeedFormat.shownTenths(10.0, false), 360, "10 m/s -> 360 tenths (36.0 km/h)");
    // 10.2 m/s -> 36.72 km/h -> redondea a 36.7 -> 367 décimas
    Test.assertEqualMessage(SpeedFormat.shownTenths(10.2, false), 367, "10.2 m/s -> 367 tenths (36.7 km/h)");
    Test.assertMessage(SpeedFormat.shownTenths(null, false) == null, "null -> null");
    return true;
}

(:test)
function testDisplayString(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.displayString(243), "24.3", "243 tenths -> \"24.3\"");
    Test.assertEqualMessage(SpeedFormat.displayString(-13), "-1.3", "-13 tenths -> \"-1.3\" (sign kept)");
    Test.assertEqualMessage(SpeedFormat.displayString(0), "0.0", "zero -> \"0.0\"");
    Test.assertMessage(SpeedFormat.displayString(null).equals("--"), "null -> --");
    return true;
}

(:test)
function testUnitLabel(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.unitLabel(false), "KM/H", "metric");
    Test.assertEqualMessage(SpeedFormat.unitLabel(true), "MPH", "statute");
    return true;
}
```

## 11. Hooks de debug para el simulador (patrón A §13 / B §9 — obligatorio)

- **`TEST_MODE`** (`const false` plano): con `true` + build DEBUG, `compute()` consume un generador sintético `(:debug)`. **Perfil de velocidad con decimales** (tabla de tramos, MÁS SIMPLE que la de B porque no hace falta simular ruido — Tier 1 no tiene pipeline de suavizado):
  ```
  speedsKmh = [10.4, 25.7, 10.1, 30.2, 15.6, 20.3,  8.5, 28.9]
  dursSec   = [  15,   15,   15,   15,   15,   15,   15,   15]
  ```
  El generador acumula **su propia distancia y tiempo** y calcula el promedio **exactamente como Garmin** (`distanciaAcumulada / tiempoAcumulado`, la misma fórmula de tasa vista en §8) — así el promedio converge de forma realista a lo largo del ciclo y la demo muestra las 3 flechas (arriba en los tramos rápidos, abajo en los lentos, sin flecha cerca del cruce) **y a la vez deja ver el número de promedio evolucionando** en la línea secundaria (§6), que es exactamente lo que el autor quiere validar de un vistazo.
- **`DEBUG_MEASURE`** (`const false` plano, patrón A/B): imprime a la consola cada tamaño de celda distinto + las fuentes elegidas (valor/promedio, alto/ascent/descent) + si la flecha entró (`mArrowFits`) + si se muestra el promedio (`mShowAvg`). Misma utilidad que en A/B: es la data para afinar el layout en las 6 resoluciones.
- **Esquema de exclusión del release:** idéntico a A/B — `const false` plano (el optimizador `-r` elimina el bloque) + `(:debug)`/`(:release)` pares para las funciones llamadas desde el guard. Volver ambos flags a `false` antes de todo build de release.

## 12. Presupuesto y rendimiento

- Límite real: 128 KB (idéntico en los 13 devices). Objetivo: **< 32 KB en uso** — esta app es más simple que la A (sin buffer, sin pipeline), así que debería pesar menos.
- Cero colecciones dinámicas; miembros escalares + un array fijo de fuentes (`mLadder` de 8). Cero mediciones/allocations en `onUpdate()` en el tick normal salvo las mediciones de ancho de los strings vivos para posicionar los dos grupos (igual costo que B en SMALL — despreciable a 1 Hz).

## 13. Criterios de aceptación (cuantificados)

- [ ] Compila sin errores para los 13 targets (warning tolerado: el del Edge 1030 viejo, visto en A/B).
- [ ] **Todos los unit tests de §10 en verde** ("Monkey C: Run Tests", perfil edge840).
- [ ] `TEST_MODE`: durante un ciclo completo del perfil sintético (§11) se observan las 3 flechas (▲, ▼, sin flecha) y el valor actual nunca se contradice con la flecha (misma décima mostrada ⇒ nunca hay flecha).
- [ ] **Ambos valores visibles a la vez** en una celda razonablemente alta (≥ `AVG_MIN_H`): actual con 1 decimal + flecha arriba, promedio con 1 decimal debajo, sin superposición ni clipping.
- [ ] En una celda entre `LABEL_MIN_H` y `AVG_MIN_H`: se ve el label + actual + flecha, **sin** la línea de promedio (degradación esperada, no un bug).
- [ ] Arranque sin datos (GPS sin fix): `--` en ambos valores, sin flecha, sin crash.
- [ ] Parado (velocidad 0,0, promedio > 0): actual muestra `0.0`, flecha ▼ (comportamiento esperado y correcto, no un bug — consecuencia directa del algoritmo genérico de §5.1, que no distingue "parado" como caso especial: 0 < promedio siempre da DOWN).
- [ ] Cambiar el device del simulador a statute: el label pasa a `MPH`, ambos valores se recalculan, sin desbordar en ningún tamaño de celda de la escalera.
- [ ] Celda muy angosta (layout denso, 8-10 campos): la flecha se descarta con gracia (fallback de §6.4) y el número actual sigue legible, sin clipping.
- [ ] Label legible en el perfil **edge830** (misma salvedad de `FONT_GLANCE` que B §6.2). Confirmar también que el `.` renderiza bien en el 830 (el hallazgo de §2 se verificó en el 840; si el 830 se ve raro, ver la nota de variación por device family).
- [ ] Memoria en régimen < 32 KB.
- [ ] `TestUtil.mc` es una copia propia del archivo (no un import de la B) — confirmar que compila standalone.

## 14. Plan de pruebas

1. **Unit tests primero** (§10) — la comparación y el formateo se validan sin simulador.
2. **`TEST_MODE`** (§11): ciclo sintético para ver las 3 flechas, el promedio conviviendo con el actual, y el fallback de celda angosta sin necesitar un FIT.
3. **Simulación integrada:** Simulator → *Activity Data* con velocidad variable; confirmar que la flecha sigue al promedio real que reporta Garmin (comparar contra el campo nativo "Avg Speed" al lado, y contra el número de promedio que el propio campo ya muestra).
4. **Unidades:** cambiar el device del simulador a statute y re-mirar.
5. **FIT playback (opcional para v1):** un FIT real con tramos de velocidad variable, cruzando contra lo que muestra Garmin Connect para "Avg Speed".

## 15. Referencias

- `Activity.Info` (currentSpeed/averageSpeed/timerState): https://developer.garmin.com/connect-iq/api-docs/Toybox/Activity/Info.html
- `System.DeviceSettings` (`paceUnits`, verificado 2026-07-23): https://developer.garmin.com/connect-iq/api-docs/Toybox/System/DeviceSettings.html
- Glifos de `FONT_SYSTEM_NUMBER_*`: verificación propia en device (edge840, 2026-07-23, ver §2) + foro Garmin (developer "Travis.ConnectIQ", "Font Specifications", discusión 251679 — fenix5xplus/vivoactive4s, no Edge, pero consistente).
- Patrones heredados: [`apps/a-activity-timer/SPEC.md`](../a-activity-timer/SPEC.md) §5.3/6 (escalera de fuentes + caché de un solo valor, `LABEL_MIN_H`), [`apps/b-grade-vam/SPEC.md`](../b-grade-vam/SPEC.md) §6.5 (primitivas `dc` para íconos/flechas, gotcha de `fillPolygon`), §9 (hooks de debug), §10 (convención de tests).
- Spec maestra: [`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md) §4 Opción J (contexto de producto, tiers de métrica, decisión de prioridad).
