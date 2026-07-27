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
│   ├── TrendArrowApp.mc        # AppBase: getInitialView() → [view] + onSettingsChanged (§9.4) →
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
│   ├── strings/strings.xml     # AppName, SpeedLabel (+ SpeedLabelShort, §6.10), AvgLabel — settings/ desde §9 (v1 no tenía)
├── resources-spa/strings/      # español
├── resources-<device>/drawables/  # ícono launcher, uno por device (35/36/40/56/68 px) — ya NO placeholder (§3.3)
└── store/                      # assets de la ficha del store + el generador del ícono (§3.3)
```

**Nota dura del repo (CLAUDE.md):** "Nada compartido entre apps salvo documentación. Si surge código común, decidir explícitamente." `TestUtil.mc` se **copia**, no se importa desde B. Si en el futuro se decide extraer algo común de verdad, esa es una decisión aparte, explícita, no implícita por comodidad.

Reglas de la clase (idénticas a A/B, no re-derivar): `compute(info)` ~1×/s, no dibuja; `onUpdate(dc)` dibuja, no calcula; sin orden garantizado entre ambos → todo miembro inicializado en `initialize()`.

### 3.3 Ícono — CERRADO (2026-07-25). Híbrido: aro de un modelo de imagen + geometría dibujada por código

**Motivo final:** aro cobalto `#0070F0` **liso** con volumen y brillo, cara azul muy oscuro `#0E1A38`; dentro, una **raya ámbar `#FFC400` horizontal a dos tercios de la altura = el PROMEDIO de la actividad**, y una **flecha blanca gorda que la CRUZA y la deja continua por detrás = el valor actual está por encima de tu media**. Sin texto, sin números, sin aguja.

**Reparto de trabajo, y por qué es híbrido.** Ninguna de las dos técnicas alcanzaba sola:

- **El modelo de imagen (`gpt-image-2`) aporta el ARO:** volumen, degradado y brillo que un dibujo plano por código no iguala. Lo que **no** sabe hacer es geometría exacta: en tres intentos no acertó **una sola** de las proporciones pedidas, y cada iteración arreglaba una cosa rompiendo otra — flecha ancho/alto 0,38 → 0,51 → 0,40 (se pedía 0,60); raya ámbar 4 % → 6 % → **2 %** (se pedía 8 %); tacos cuadrados → redondeados → cuadrados otra vez.
- **El código aporta la GEOMETRÍA:** la flecha de `3.png` tenía la cabeza al 39 % del diámetro de la cara y la cola pegada al borde; se le **transplantó** la del generador (cabeza 49 %, astil 25 %, punta al 2,6 % y cola al 91 % desde el techo de la cara) y se **redibujó la franja ámbar** con antialias propio.

Ese resultado está **bakeado** en `store/3-flecha-arreglada.png` (1254×1254, fondo magenta), que es el **único insumo versionado**: los PNG crudos del modelo ya no hacen falta y se sacaron del repo.

| archivo en `store/` | qué es |
|---|---|
| `3-flecha-arreglada.png` | la fuente: imagen del modelo + flecha y franja corregidas, fondo magenta plano |
| `gen_master.py` | recorta los tacos, saca el magenta (tolerancia + despill), recentra → escribe los dos de abajo |
| `icon-master-1024.png` | 1024×1024 RGBA con **alpha real** (46 % transparente, 2202 px de borde suave) |
| `store-icon-500.png` | 500×500 RGB **opaco** sobre gris `#E6E6E6`, igual que el de la Opción A |
| `gen_icon.py` | dibuja SOLO los 13 launchers (35/36/40/56/68 px), planos, con la MISMA geometría de flecha |
| `ICON_PROMPT.md` | los prompts; hoy solo sigue vigente el del **hero 1440×720** |

**Regla dura heredada de A: cada tamaño se DIBUJA a su tamaño, nunca se reduce el master** (el master ilustrativo reducido a 35 px quedaba una mancha borrosa). Por eso los launchers son dibujo propio y no un downscale, y por eso `gen_icon.py` y `gen_master.py` escriben a archivos distintos: ninguno puede pisar al otro.

#### Prueba a ciegas (2026-07-25): qué comunica el ícono de verdad

Se testearon el master y el launcher de 35 px con **7 observadores independientes sin contexto** + 2 jueces con contexto (workflow de 10 agentes; ver la limitación al final). Resultado, contra la intención del diseño:

| pregunta | respuesta |
|---|---|
| ¿se entiende que es un neumático? | **NO** — 0 de 7. **7 de 7** leyeron engranaje / tuerca / bisel |
| ¿se entiende que la raya es el promedio? | **NO** — 0 de 7 dijo "promedio"; 7 de 7 sí llegaron a "línea de referencia / umbral que la flecha cruza" |
| qué sí comunica | unánime: "arriba / más / subiendo / superar un nivel" |

Riesgos repetidos: **ajustes/configuración 7 de 7** (el peor falso amigo en una lista de apps), upload/firmware 7/7, eject 6/7. Además 4 de 7 vieron la franja partida como **dos marcas sueltas** en vez de una línea ocluida.

**Consecuencia aplicada, pero ASIMÉTRICA (decisión del autor, 2026-07-26).** Los tacos se sacaron **solo de los launchers**; el master y el ícono de tienda **los conservan**:

| asset | tacos | por qué |
|---|---|---|
| `icon-master-1024.png` + `store-icon-500.png` | **sí** | a tamaño de ficha se lee el neumático y le gusta al autor; el riesgo de "ajustes" era un fenómeno de tamaño chico |
| los 13 `launcher_icon.png` (35–68 px) | **no**, aro liso | a 35 px los lóbulos eran justo lo que hacía leer engranaje (7 de 7) sin aportar el neumático (0 de 7) |

`gen_master.py` lleva el flag `DROP_KNOBS` (hoy `False`) que recorta los tacos detectando el radio exterior del aro — el mayor radio cuyo perímetro está cubierto >95 %, porque más afuera solo hay lóbulos y en pocos ángulos; `gen_icon.py` dibuja los launchers con `nubs_mode='none'`. **La franja ámbar quedó continua** por detrás de la flecha (hueco = silueta exacta, sin dilatar). Lo que ningún dibujo arregla es "la raya = tu promedio": eso lo explican el nombre de la app, la ficha y el propio campo en pantalla; al ícono le alcanza con diferenciar y no mentir.

*Limitación de la prueba: son observadores de IA, no un estudio con usuarios humanos. Sirven para detectar lecturas erróneas evidentes (el "ajustes" 7/7 lo es), no para medir preferencia ni recordación.*

#### Tres artefactos de la franja ámbar, y por qué aparecieron (patrón reutilizable)

Al transplantar la flecha hubo que borrar la vieja y reconstruir lo que tapaba. Parchear **por clasificación de color** dejó tres residuos, los tres visibles solo al ampliar:

1. **Píxeles huérfanos** justo antes de la flecha (p. ej. `(126,100,44)`): eran el **antialias del ámbar viejo contra la flecha vieja**, que no clasifica ni como ámbar ni como flecha. → Se dejó de parchear: ahora se **borra la franja entera y se redibuja** con antialias propio, así el problema no puede existir.
2. **Costura horizontal** en el borde superior: la fila de antialias original (`(46,41,68)`) quedaba fuera del rango borrado y hacía escalón contra el borde nuevo. → Se borran **3 px de más** a cada lado.
3. **Hilo oscuro siguiendo el aro** en los extremos exteriores: el relleno y el recorte iban a `0,995·rf` y entre el ámbar y el filete interior quedaba una tirita de navy. → Recorte del ámbar a `rf` exacto (se comparó `1,000` contra `1,006` contra el original antes de elegir).

Queda, y es correcto, **una columna de 1 px** más oscura en un encuentro del master: es antialias legítimo (al bajar de 1254 a 1024 ese borde cae a mitad de píxel y la mezcla navy+ámbar da un oliva turbio). Invisible al tamaño real.

**Sobre el magenta:** el fondo **no** se compara por igualdad. Desde el 2026-05-19 toda imagen de OpenAI lleva **SynthID**, que corre los píxeles unos puntos (medido: el fondo es `(239,3,232)`, no `(255,0,255)`), y además los bordes tienen antialias. Se keyea con umbral suave + **despill** (des-componer `color = fg·α + magenta·(1−α)`), o quedaría fleco rosa. Control: magenta-idad máxima dentro del dibujo = 60/255.

**Dato del research REFUTADO con evidencia (no repetirlo):** que los launchers de los MIP haya que dibujarlos en una paleta de 64 colores (canales `00/55/AA/FF`, y por eso usar `#0055FF`). El launcher de la Opción A —validado en el Edge 840 real del autor— tiene **282 colores distintos y solo 2 caen en esa grilla**. Se usa el `#0070F0` del proyecto.

Compila limpio (release `-w`) en un device por cada tamaño de launcher: edge840, edge830, edgemtb, edge1040, edge850, edge1050.

### 3.4 Capturas para la ficha del store (2026-07-26)

`store/trend-arrow-{1,2,3}.png` + `trend-arrow-4-inv.png`: la pantalla del Edge 840 (246×322) a escala 2×, recortada de capturas del simulador, **sin reescalar** (píxeles originales). Muestran los cuatro casos que valen la pena: campo a pantalla completa con actual+promedio, layout mixto con el campo grande en el medio, modo inline `30.0 / 20.6`, y el mismo layout en **tema oscuro**.

Cómo se recortaron, y los dos errores que costó (el script quedó en el scratchpad, no en el repo — el autor prefiere rehacerlas con otra herramienta):

- Los bordes IZQ/DER salen de las **líneas separadoras azules** del simulador, que abarcan exactamente el ancho de la pantalla. Cuando no hay separadores (campo a pantalla completa) se cae al gradiente por columna: los dos bordes de la pantalla acumulan un conteo **parecido entre sí** (644 y 624 px) mientras el borde de la VENTANA acumula mucho más (1104) — elegir por "conteo máximo" agarra la ventana, hay que elegir por parecido.
- Los bordes ARRIBA/ABAJO salen de puntuar **cada fila** por la fracción de píxeles "de pantalla" entre los bordes laterales. Hay que **suavizar el perfil** (media móvil de 7 filas) porque alguna fila suelta que cruza el medio de los dígitos grandes es casi toda antialias y cae por debajo del umbral, cortando el recorrido.
- **Error 1:** el primer recorte incluía la línea de borde de la pantalla y las **esquinas redondeadas del bisel** → marco negro alrededor. Solución: meter el recorte 6 px hacia dentro y repintar las esquinas con el color de fondo.
- **Error 2:** el color de fondo se detectaba mirando el **centro** de la imagen, que en el tema oscuro cae sobre texto blanco → rellenó las esquinas de blanco sobre negro. Solución: color **dominante** de todo el recorte (moda sobre histograma grueso).

**Límite de peso del portal: 150 KB por captura (verificado por el autor al subir, 2026-07-26).** Las
capturas llegaban pesando 664-1050 KB y entraron **sin bajar un solo píxel**, porque el peso no estaba
en la resolución sino en el **ruido de color**: eran imágenes de texto negro sobre blanco con más de
6000 colores distintos, ruido del pipeline que las generó (desvío de gris máximo 6 sobre 255, media
0,16). Receta, en orden de rendimiento:

1. **A escala de grises** — visualmente idéntico, y pasa de 3 canales a 1.
2. **Pegar al blanco y al negro puros** los valores casi puros (≥249 → 255, ≤6 → 0): convierte los
   fondos planos en tiradas largas del mismo byte.
3. **Filtro PNG por fila**, eligiendo entre `none`/`sub`/`up`/`average` el de menor suma absoluta (la
   heurística estándar): sobre un fondo plano, `up` da ceros.

Con eso solo: 664-1050 KB → **48-75 KB a resolución completa**. Después, con el lado mayor llevado a
1000 px, quedan en **24-34 KB**, y una comparación ampliada del mismo dígito no distingue una de otra.
Lección reutilizable: antes de sacrificar resolución, mirar cuántos colores tiene la imagen.

**Atajo para la próxima:** el simulador tiene su propia función de captura y guarda directamente la pantalla en 246×322 (son los `.BMP` de `screenshots/`, que está gitignoreado). Esos no necesitan recorte ninguno.

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

    // Los dos primeros argumentos son los ENTEROS YA REDONDEADOS que el usuario ve en pantalla (el
    // mismo valor que se usó para construir el string de display) -- NO los floats crudos. El
    // tercero, `deadBand`, es la SEMI-anchura de la banda muerta en las MISMAS unidades enteras (con
    // velocidad: décimas, así `deadBand=1` == +/-0,1 km/h). La flecha aparece solo si la diferencia
    // SUPERA la banda; dentro de la banda la lectura es neutra ("va a la media"). null en cualquiera
    // de los dos valores -> NONE.
    //
    // Nota (SPEC 5.2): con velocidad a 1 decimal, "el entero redondeado" son en realidad DÉCIMAS
    // (p. ej. 24,3 km/h -> el entero 243), así que `deadBand` también va en décimas -- a este
    // módulo le da igual la escala, solo compara.
    function classify(shownCurrent as Number or Null, shownAverage as Number or Null, deadBand as Number) as Number {
        if (shownCurrent == null || shownAverage == null) {
            return NONE;
        }
        var diff = shownCurrent - shownAverage;
        if (diff > deadBand)  { return UP; }
        if (diff < -deadBand) { return DOWN; }
        return NONE;
    }
}
```

**Banda muerta SEMÁNTICA de ±0,1 km/h (`DEAD_BAND_TENTHS = 1` en la View, decisión del autor 2026-07-24):** el arma no es anti-titileo — el titileo se ve bien como estaba. Es una decisión de **significado**: para el autor, una diferencia de ≤ 0,1 km/h entre actual y promedio significa *"realmente vas a la velocidad media"*, así que "por encima / por debajo" solo tiene sentido cuando la diferencia **supera** 0,1. Con décimas: `diff ∈ {−1, 0, +1}` (o sea |Δ| ≤ 0,1) → **NONE**; recién `|diff| ≥ 2` (≥ 0,2) muestra flecha. Es conceptualmente la banda muerta "de 1 dígito" del Cateye (no verificado como fuente dura). La View define la constante (el conocimiento "una décima = 0,1 km/h" es específico de velocidad) y se la pasa a `classify`, que sigue **genérico** (la banda va en las unidades enteras que le pasa el llamador; §8 Tier 2 podría darle a cada métrica su propia banda).

**Refinamiento de arquitectura respecto de la spec maestra:** la spec maestra describe la banda muerta como "sin flecha si `round(actual) == round(promedio)`". Acá la **View redondea una sola vez** (con `SpeedFormat.shownTenths`, §5.2) y le pasa a `classify` los enteros ya redondeados **más** el ancho de banda; no hace falta pasarle floats crudos ni un paso de redondeo aparte. Documentado para que quien compare la spec maestra con el código no piense que hay discrepancia.

**Consecuencia (leer antes de sorprenderse): con `deadBand > 0`, el número y la flecha PUEDEN "no coincidir" a propósito** — p. ej. `24,3` actual / `24,2` promedio muestra los dos números distintos pero **sin flecha** (la diferencia de 0,1 cae en la banda = "va a la media"). Esto RELAJA a propósito la invariante anterior "la flecha nunca contradice al número" (que valía con `deadBand=0`): para una flecha de tendencia es lo esperado y correcto. Con **sensor de rueda** (el del autor) la lectura es limpia, y el promedio (`Activity.Info.averageSpeed`, cociente distancia/tiempo acumulado) es una referencia casi inmóvil, así que la banda fija se comporta de forma estable.

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
        if (absT >= 1000) {
            return sign + ((absT + 5) / 10).toString();   // >= 100.0 -> entero (ver nota abajo)
        }
        var whole = absT / 10;      // división entera
        var dec = absT % 10;
        return sign + whole.toString() + "." + dec.toString();
    }

    function unitLabel(statute as Boolean) as String {
        return statute ? "MPH" : "KM/H";
    }
}
```

**Sin decimal a partir de 100 (2026-07-25, §6.10):** arriba de 99,9 el string pasa a entero (`"104"`). No es capricho de formato, es lo que **permite que el número se dibuje grande**: la fuente se elige contra la plantilla `VALUE_TPL = "88.8"`, y como `w("888") < w("88.8")` en todas las fuentes numéricas, ningún valor real puede desbordar esa plantilla. Reservar `"888.8"` costaba un escalón entero de fuente en las celdas de media pantalla por una velocidad que en bici no existe. Consecuencia aceptada: por encima de 100 la flecha puede indicar una tendencia que los dos enteros mostrados ya no revelan (misma relajación que la banda muerta de §5.1).

### 5.3 `compute()` de la View — casi trivial (sin pipeline, a diferencia de la B)

```
1. mIsStatute = (System.getDeviceSettings().paceUnits == System.UNIT_STATUTE)   // releer cada tick (§2)
2. state = info.timerState (null-safe); mRunning = (state == Activity.TIMER_STATE_ON)
3. curTenths = SpeedFormat.shownTenths(info.currentSpeed, mIsStatute)
4. avgTenths = SpeedFormat.shownTenths(info.averageSpeed, mIsStatute)
5. mCurStr = SpeedFormat.displayString(curTenths)
6. refTenths = (objetivo configurado y válido) ? mTargetTenths : avgTenths          // §9
7. mAvgStr = SpeedFormat.displayString(refTenths)
8. mArrowState = TrendArrow.classify(curTenths, refTenths, DEAD_BAND_TENTHS)   // banda ±0,1 km/h (§5.1)
9. mUnitTop = SpeedFormat.unitTop(mIsStatute); mUnitBottom = SpeedFormat.unitBottom(mIsStatute)
```

Eso es **todo** — sin buffer, sin push, sin filtro. `onUpdate()` solo dibuja `mCurStr`/`mAvgStr`/`mArrowState` y las dos líneas de la unidad, cero formateo por tick (mismo principio A/B: `compute()` calcula y formatea, `onUpdate()` solo dibuja).

⚠️ **Dos pasos de este pseudocódigo cambiaron después de escribirlo, y esto ya refleja el código real:** la
unidad dejó de ser un string pegado al label (`mUnitLabel = unitLabel(...)`) y pasó a las dos líneas
apiladas al lado del número (**§6.9**; `unitLabel` sigue existiendo pero **no se usa en el render**), y el
segundo número dejó de ser siempre el promedio: puede ser un objetivo fijo configurable (**§9**).

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
                            // ⚠️ SUPERSEDED 2026-07-27 (§6.13): reemplazada por ARROW_INK_BIAS = 1;
                            // el objetivo de la flecha NO es "descent/2 + nudge" (error que crece con
                            // la fuente del número), es una constante de 1 px sobre cy.
const VALUE_TPL = "888.8";  // plantilla de ancho estable: 3 dígitos enteros + "." + 1 decimal
                             // (cubre 0.0-999.9; la velocidad no lleva signo en la práctica)
```

> ⚠️ **§6.10 (2026-07-25) supersede parte de esta tabla:** `VALUE_TPL = "88.8"` (2 dígitos enteros; ≥100 va sin decimal) y se agregan `BAND_SLACK`, `UNIT_LINE_GAP`, `UNIT_NUM`/`UNIT_DEN`, `UNIT_SHRINK_STEPS`.

### 6.3 Fuentes (herencia directa de A/B — reusar tal cual, sin reinventar)

- **Escalera numérica, idéntica a A/B** (mismo array, mismo orden, ya validado en device) — se usa TANTO para el valor actual como para el promedio (cada uno elige su propio tamaño dentro de su banda, ver §6.4). **Ya no hace falta una escalera de fuente de texto** (`mTextLadder` de la B): con el `.` confirmado en la fuente numérica (§2), todo el string `"24.3"` se dibuja en UNA sola fuente de esta escalera:
  ```
  mLadder = [FONT_SYSTEM_NUMBER_THAI_HOT, FONT_SYSTEM_NUMBER_HOT, FONT_SYSTEM_NUMBER_MEDIUM,
             FONT_SYSTEM_NUMBER_MILD, FONT_MEDIUM, FONT_SMALL, FONT_TINY, FONT_XTINY]
  ```
- **Label: `FONT_GLANCE`, en MAYÚSCULAS**, reservando solo `ascent` + margen — mismo patrón A/B, misma salvedad del edge830 sin glance font (B §6.2) a verificar en el simulador con ese perfil.
- **Prefijo "AVG"/"PROM": `FONT_XTINY` FIJO** (no ladder) — mismo patrón que el header `"PEND/VAM"` de B en modo SMALL: es una etiqueta chica de apoyo, no necesita escalar.
- La unidad va en el label del valor actual (`"SPEED KM/H"`, igual que B con `"VAM M/H"`) — no se repite en la línea de promedio (ya está implícita: mismo campo, misma unidad).

> ⚠️ **Superseded dos veces:** §6.9 (2026-07-23) saca la unidad del label y la dibuja apilada junto al número; §6.10 (2026-07-25) **repone `mTextLadder`** (`[MEDIUM, SMALL, TINY, XTINY]`) porque la unidad y el prefijo `AVG`/`PROM` pasan a ser **proporcionales al número** (ya no `FONT_XTINY` fijo), y el label usa la misma escalera como fallback cuando el nombre largo no entra.
- **Selección con caché**, igual patrón que A/B: recalcular SOLO cuando cambia `(w, h, mIsStatute)`. (Nota: `VALUE_TPL` en sí no cambia de ancho entre km/h y mph — a diferencia del template de VAM en B, que sí pasa de 5 a 6 glifos entre m/h y ft/h — así que `mIsStatute` no es estrictamente necesario en la clave de fuente; se incluye igual porque el LABEL sí cambia de texto con la unidad, y mantiene la caché con el mismo criterio conservador que el resto del repo.)

### 6.4 Selección de fuentes (algoritmo completo)

> ⚠️ **§6.10 (2026-07-25) supersede el pseudocódigo de abajo en tres puntos:** (a) el gate de alto es `getFontAscent(f) <= bandH - BAND_SLACK`, **no** `getFontHeight(f) > bandH*0,9`; (b) la unidad se elige por cada fuente candidata (`fitUnitFont`, proporcional y con hasta 2 escalones de encogimiento) en vez de reservar un ancho fijo de `FONT_XTINY`; (c) el prefijo `AVG`/`PROM` se mide en la fuente de la unidad. La ESTRUCTURA (escalera de mayor a menor, plantilla de ancho estable, fallback sin flecha) no cambia.

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

**Label del valor actual:** `mLabel` = string cargado una vez de `Rez.Strings.SpeedLabel` en `initialize()`, en MAYÚSCULAS (mismo patrón que `mGradeLabel` en B). ⚠️ **SUPERSEDED por §6.9/§6.10:** el diseño original lo dibujaba como `mLabel + " " + SpeedFormat.unitLabel(mIsStatute)`, p. ej. `"SPEED KM/H"` (igual patrón que B con `"VAM M/H"`). El código real dibuja **solo el nombre de la métrica** (`VELOCIDAD`, con degradación a `VEL` y después por la escalera de fuentes vía `selectLabel`), porque la unidad se movió a las dos líneas apiladas al lado del número.

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
5. Si labelShow: drawText(w/2, LABEL_MARGIN, mLabelFont, mLabel, CENTER)
     // ⚠️ SUPERSEDED: el label ya NO lleva la unidad pegada (era `mLabel + " " + mUnitLabel`).
     // La unidad va apilada al lado del número (§6.9) y el label es solo el nombre de la
     // métrica, con degradación largo -> corto -> fuente menor (§6.10, `selectLabel`).

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
              // ⚠️ SUPERSEDED 2026-07-27 (§6.13): esta línea es HOY `primaryCy - ARROW_INK_BIAS`.
              // La intención (alinear con la tinta, no con la caja) sigue valiendo; la fórmula no.
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

> **Glifo si el device puede, primitiva si no — IMPLEMENTADO (2026-07-25, decisión del autor).** La primitiva **sigue siendo obligatoria** porque es la única que funciona en los 13 (§11.2: `↑ ↓ ▲ ▼` no están en ninguna fuente numérica ni en la de texto de 6 devices, y un glifo ausente **desaparece sin dejar rastro**). Pero el Edge 840 real **sí los pinta**, vía una cadena de fuentes de respaldo no documentada, así que el autor pidió aprovecharlo donde exista. El código **prueba la disponibilidad en el propio device** y elige; el peor caso es exactamente el comportamiento anterior. Ver §6.11 para la mecánica y §11.2 para las mediciones.

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

### 6.8 Modo ancho: inline SOLO en celdas anchas y CORTAS (2026-07-23)

En **celdas full-width Y cortas** (sin alto para apilar) el campo muestra **ambos valores en UNA sola línea**: `[flecha] actual / promedio` (p. ej. `▲ 24.1 / 15.0`), label `SPEED / AVG` (`VEL / PROM` en ES). Una celda full-width **alta** NO usa inline: cae al layout apilado de §6.1 (actual grande + flecha, promedio en su línea) — **decisión del autor tras verlo en el sim (2026-07-23):** una línea inline solo crece hasta el ancho de la celda, así que en una celda ancha y alta el número queda chico con mucho hueco vertical; apilado, el actual usa el alto y sale **grande como el nativo**.

- **Gate:** `fullWidth = (w * WIDE_DEN >= screenW * WIDE_NUM)` con `WIDE_NUM=8, WIDE_DEN=10` (**celda ≥ 80 % del ancho de pantalla**, vía `System.getDeviceSettings().screenWidth`, presente en todos los devices; guarda `!= null`). **`mIsWide = fullWidth && (h < AVG_MIN_H)`** → inline solo si además es corta (no entra la línea de promedio apilada). `fullWidth && h ≥ AVG_MIN_H` → cae al apilado (que muestra el promedio como 2ª línea). Una media-columna (~50 %) nunca es inline.
- **Fuente inline:** misma escalera numérica, mayor tamaño cuyo grupo `[flecha + gap + "888.8 / 888.8" + gap + unidad]` (plantilla `INLINE_TPL`) entra a lo ancho, tope de alto contra la banda. Fallback: si la flecha no entra, se descarta y se ajusta `[par + unidad]` (mismo idioma que §6.4).
- **Flecha:** tendencia del **actual vs promedio** (misma `classify()`), precede a TODO el par. Mismo centrado que el valor apilado (§6.7) — hoy `cy − ARROW_INK_BIAS`, ⚠️ ya **no** `descent/2 + ARROW_NUDGE` (§6.13). Sigue siendo DATO (va con el valor).
- Constantes: `WIDE_NUM=8`, `WIDE_DEN=10`, `INLINE_SEP=" / "`, `INLINE_TPL="888.8 / 888.8"`. Implementado en `TrendArrowView.mc` (`selectInlineFont` + `drawTrendValue`, branch en `selectFonts`/`onUpdate`). Compila limpio (release 840+830, `-w`) + 10/10 tests. **PENDIENTE:** validación visual del autor en el sim (umbral 80 %, y que el apilado en celda ancha-alta se vea bien en las 6 resoluciones).

### 6.9 Unidad estilo NATIVO (apilada a la derecha del número — 2026-07-23)

Tras comparar contra el campo nativo del Edge (capturas `b-grade-vam/screenshots/2026-07-20-21-04-51.BMP` = "VELOCIDAD 13.3 km/h" y `…22-37-12.BMP` = "VELOCIDAD MEDIA 13.8 km/h"), el autor pidió **hacerlo como el nativo**: la unidad **NO va en el label**, sino como un **`km/h` chiquito apilado en dos líneas (`km` sobre `h`) a la derecha del número**, arriba (como superíndice). El label pasa a ser solo el nombre de la métrica.

- **`SpeedFormat` (puro):** nuevas `unitTop(statute)`/`unitBottom(statute)` → métrico `["km","h"]`, statute `["mph",""]` (bottom vacío = una sola línea). Minúsculas, como el nativo. `unitLabel` (mayúsculas) queda pero **ya no se usa en el render** (sí en su test). Test `testUnitParts` (10 tests en total ahora).
- **Label:** apilado → solo `mLabel` (p.ej. `SPEED`/`VEL`); ancho → `mLabel / mAvgPrefix` (p.ej. `SPEED / AVG`). Se quitó el `" " + unidad` del label en ambos.
- **Dibujo:** helper único `drawTrendValue(dc,w,fg,font,str,cy,showArrow)` dibuja `[flecha] valor [unidad apilada]` como un grupo centrado (lo usan el valor primario apilado Y la línea ancha). Helpers `unitBlockWidth` (ancho = máx de las dos líneas) y `drawStackedUnit`. La línea de promedio también lleva su unidad chica.
- **Alineación vertical de la unidad — a la BASE del número (2026-07-23, tras captura nativa):** el nativo apoya el `km/h` **abajo**: la `h` se sienta sobre la misma línea base que los pies de los dígitos (NO como superíndice arriba). `drawStackedUnit(dc, x, baseY, font)` recibe la **baseline objetivo** y coloca la línea de abajo con su baseline en `baseY` y la de arriba un `ascent` por encima (juntas). Para un valor dibujado con `VCENTER` en `cy`, la baseline del número es `baseY = cy + (ascent − descent)/2 + UNIT_BOTTOM_NUDGE`. (Para statute, una sola línea `mph` con su baseline en `baseY`.)
- **Selección de fuentes:** todas las plantillas de ancho ahora reservan `+ UNIT_GAP + unitBlockWidth(FONT_XTINY)` (primario, fallback sin flecha, promedio y ancho) para que número+unidad no desborden.
- **Constantes nuevas:** `UNIT_GAP=3`, `UNIT_BOTTOM_NUDGE=0` (positivo empuja la unidad HACIA ABAJO; nudge fino a afinar en el sim — mismo idioma que `VALUE_NUDGE`/`ARROW_NUDGE`). Unidad en `FONT_XTINY` fija.
- Compila limpio (release 840+830, `-w`) + **10/10 tests verdes**. **PENDIENTE (autor):** afinar en el sim el `UNIT_BOTTOM_NUDGE` (alto exacto de la unidad respecto de los dígitos) y confirmar que `km`/`h` no pisa el número ni se sale de la celda en las resoluciones chicas.

### 6.10 Paridad con el campo nativo: número GRANDE, unidad proporcional, label largo (2026-07-25)

Screenshot del autor (`screenshots/2026-07-25-11-08-23.BMP`, edge840 en el sim, página de mapa con 2 campos abajo: **izquierda = velocidad NATIVA, derecha = la nuestra**) → nuestro campo se veía **más chico en todo**. Medido pixel a pixel sobre el BMP (celda de **122×62 px** en ambos casos, divisor en x=122–123):

| | nativo | nuestro (antes) |
|---|---|---|
| dígitos `9.3` (tinta) | **27 px de alto**, 51 de ancho → `FONT_SYSTEM_NUMBER_MEDIUM` | 22 × 35 → `…_MILD` (un escalón menos) |
| unidad `km`/`h` (tinta) | **11 px por línea**, bloque 20 de ancho (~`FONT_SMALL`) | 8 px, bloque 12 (`FONT_XTINY`) |
| `h` respecto de `km` | **centrada** debajo | pegada a la izquierda |
| label | `VELOCIDAD` | `VEL` |
| baselines de la unidad | 14 px de separación; la `h` apoya en los pies de los dígitos | ascent exacto (12) |

**Métricas reales de fuente del edge840** (obtenidas headless, ver §11.1): `NUMBER_MEDIUM` h=42 a=33 d=9, w("88.8")=73, w("888.8")=94; `NUMBER_MILD` h=35 a=28; `FONT_SMALL` a=12 w("km")=19; `FONT_GLANCE` a=15 w("VELOCIDAD")=85.

Tres causas, tres arreglos:

1. **El gate de alto usaba `getFontHeight` (REGLA NUEVA: usar `getFontAscent`).** Con label, la banda del valor es `62 − 21 = 41` px. `getFontHeight(NUMBER_MEDIUM) = 42 > 41·0,9 = 36` → se descartaba, aunque **sus dígitos solo pintan 27 px**: la altura de una fuente numérica incluye un descendente que los dígitos NUNCA usan (la misma regla dura de centrado de §6.7, aplicada ahora a la SELECCIÓN). El nativo mete una fuente de 42 px de alto en una banda de 41 justamente por eso. Ahora: `getFontAscent(f) <= bandH - BAND_SLACK` (`BAND_SLACK = 2`) → elige `NUMBER_MEDIUM`, **igual que el nativo**.
2. **`VALUE_TPL` pasó de `"888.8"` a `"88.8"`** (y `INLINE_TPL` a `"88.8 / 88.8"`): reservar 3 dígitos enteros + decimal costaba 21 px de ancho por una velocidad que en bici no existe. Para que la plantilla siga siendo una cota REAL, `SpeedFormat.displayString` **suelta el decimal a partir de 100** (`"104"`), y `w("888") < w("88.8")` en todas las fuentes numéricas → ningún valor posible desborda la plantilla (§5.2). Consecuencia aceptada: por encima de 100 la flecha puede indicar una tendencia que los dos enteros ya no revelan (la misma relajación que ya hace la banda muerta de §5.1).
3. **Unidad PROPORCIONAL al número, no `FONT_XTINY` fija.** Ratio del nativo: ascent de unidad 12 sobre ascent de número 33 ≈ **2/5** → `UNIT_NUM/UNIT_DEN = 2/5`; se elige la mayor fuente de texto con `ascent <= ascentNúmero·2/5`. Si el grupo no entra a lo ancho, **primero se encoge la UNIDAD** (hasta `UNIT_SHRINK_STEPS = 2` escalones) y solo después se baja un tamaño el **NÚMERO** (el número es el dato; la unidad es una pista). Vuelve `mTextLadder` (`[MEDIUM, SMALL, TINY, XTINY]`), que §6.3 había eliminado. `drawStackedUnit` ahora **centra las dos líneas** entre sí (`TEXT_JUSTIFY_CENTER` sobre el centro del bloque) y separa las baselines `ascent + UNIT_LINE_GAP` (`=2`, que es exactamente los 14 px medidos en el nativo con `FONT_SMALL`). La línea de promedio comparte esa fuente para su unidad **y para el prefijo `AVG`/`PROM`** (ya no `FONT_XTINY` fijo), así toda la línea secundaria escala junta.

**Label largo con degradación (como el nativo, que abrevia en celdas angostas):** dos strings por idioma — `SpeedLabel` (largo: `Velocidad`/`Speed`) y `SpeedLabelShort` (`Vel`/`Speed`). `selectLabel` usa el largo si entra en `FONT_GLANCE`, si no el corto, y si tampoco entra baja el corto por `mTextLadder`. El alto del label (`mLabelH`) usa el `ascent` de la fuente elegida.

**Verificado headless en las 6 celdas típicas** (§11.1). En la celda del screenshot (122×62, métrico): valor `NUMBER_MEDIUM` (a=33) + unidad `FONT_SMALL` (a=12, bloque 19 px) + label `VELOCIDAD` + flecha → **tinta de dígitos calculada en y 28..55 vs. 28..54 del nativo, `km` en 30..41 vs. 30..40, `h` en 45..55 vs. 44..54** (≤1 px de diferencia en todo). Celda ancha corta (246×62) también sube a `NUMBER_MEDIUM` inline. Celda de 3 columnas (82×62) sigue cayendo a fuente de texto: el grupo `[flecha + "88.8" + unidad]` no entra ni con la unidad en `XTINY` — **no es una regresión** (el comportamiento anterior era idéntico) y se acepta: se prefiere flecha + número chico a número grande sin flecha (la flecha ES la app). En el edge830 (sin glance font, label a=10) el valor también sube a `NUMBER_MEDIUM`.

Compila limpio (release 840+830, `-w`) + **11/11 tests verdes**. **PENDIENTE (autor):** validación visual en el sim contra el nativo (afinar `UNIT_LINE_GAP`/`UNIT_BOTTOM_NUDGE` y el `BAND_SLACK` si el número roza el label).

### 6.11 Flecha: glifo con fallback a primitiva, y el hueco que no se mueve (2026-07-25)

**Elección en runtime, nunca por lista de devices.** `arrowGlyphFont(dc, targetAscent)` decide, y lo hace **midiendo en el device que está corriendo** — las tablas de fuente no predicen el render y el simulador se equivoca en las dos direcciones (§11.2). Dos señales, las dos deben pasar:

1. el glifo avanza **más de 2 px** — en la familia `.cft` (530/830/1030×3/explore2) un glifo ausente mide exactamente **1 px**;
2. **no mide lo mismo que `U+E000`** (área de uso privado, que ninguna fuente puede tener legítimamente) — en esa misma familia la fuente numérica devuelve **22 px para ambos**: es una única caja *notdef* compartida.

Si cualquiera falla → primitiva. Medido: edge840 `w(↑)=17` en `FONT_LARGE` (control 0) → **GLIFO**; edge830 `w(↑)=1` en las tres fuentes de texto → **PRIMITIVA**.

**El glifo se pide en una fuente de TEXTO, no en la del valor.** Es contraintuitivo porque en fuente numérica el 840 lo dibuja *más grande* (26 px, justo el tamaño que el campo quiere), pero ahí `getTextWidthInPixels` devuelve **0**: medida y renderizador no coinciden y no hay ancho con el cual maquetar. En fuente de texto los dos concuerdan (11 y 11). El costo es el techo: `FONT_LARGE`, ascent 22, contra los 42 px que alcanza la primitiva junto a un `THAI_HOT`.

**Se resuelve UNA vez, en `selectFonts`** (cacheada por `(w, h, unidades)`), y se guarda en `mGlyphFont` / `mInlineGlyphFont`. Estuvo mal implementado un rato —se probaba dentro de `drawTrendValue`, o sea en cada tick— y lo detectó el autor: rompía la regla del repo de *medir en `selectFonts`, dibujar en `onUpdate`, cero medición por tick*.

**EL HUECO DE LA FLECHA SE RESERVA SIEMPRE, se pinte o no.** Bug reportado por el autor viéndolo en el simulador: el grupo `[flecha][gap][valor][gap][unidad]` va centrado, así que cuando la flecha desaparecía en la banda muerta el grupo se achicaba y **el número saltaba lateralmente** media flecha + medio gap — y eso pasa cada vez que cruzás tu media, o sea todo el tiempo. Ahora `drawTrendValue` recibe `reserveArrow` (¿cabe una flecha acá?) y deriva adentro si toca pintarla; el ancho reservado es **el mayor entre ↑ y ↓**, así tampoco se mueve al cambiar de dirección, y el glifo se dibuja centrado en ese hueco.

**Gotcha de plataforma:** al agregar un parámetro, el método quedó con 10 argumentos y **el edge830 dejó de compilar — CIQ 3.3 admite 9 como máximo**. El edge840 compilaba igual. Por eso `paintArrow` se deriva de miembros en vez de pasarse. (Regla general en `CLAUDE.md`: compilar contra todos los devices, no contra dos.)

**Constantes:** `USE_ARROW_GLYPH` (a `false` fuerza la primitiva en todos lados), `ARROW_GLYPH_UP`/`DOWN` (`\u2191`/`\u2193`; `\u25B2`/`\u25BC` para triángulos sólidos), `GLYPH_CONTROL = \uE000`, `GLYPH_MIN_W = 2`.

### 6.12 La flecha-glifo es MÁS CHICA que los dígitos, y el 4/5 no es la causa (MEDIDO 2026-07-27, NO implementado)

El autor lo vio en el 840 real: la flecha se ve más chica que el número. **No es una ilusión de
posición** — el glifo se dibuja `VCENTER` sobre `cy − descent/2`, o sea centrado en los dígitos
visibles, no arriba. Es más chica de verdad, y **el techo no es el objetivo de 4/5 sino la fuente**:
el glifo se pide en fuente de TEXTO (§11.2 explica por qué: en la numérica el 840 lo pinta más grande
pero `getTextWidthInPixels` devuelve **0** y no hay con qué maquetar), y la mayor fuente de texto es
`FONT_LARGE`, con ascent **22 px**. Ese tope ya manda en casi toda la escalera.

Medido en el edge840 con un probe headless (§11.1), ascents reales:

| Fuente del número | ascent | primitiva (4/5) | glifo (tope `FONT_LARGE`) |
|---|---|---|---|
| `NUMBER_THAI_HOT` | 53 | 42 · 79 % | **22 · 41 %** |
| `NUMBER_HOT` | 43 | 34 · 79 % | **22 · 51 %** |
| `NUMBER_MEDIUM` | 33 | 26 · 78 % | **22 · 66 %** |
| `NUMBER_MILD` | 28 | 22 · 78 % | 22 · 78 % |

⚠️ **Consecuencia que no se había notado: la app se ve DISTINTA según la familia de fuentes.** Los
devices que caen a la primitiva (830, 530, 1030 ×3, explore2) tienen la flecha al 79 % del número;
los que resuelven el glifo (840, 540, 550, 850, 1040, 1050, mtb) la tienen al 41 % en celda grande.
No es un bug de código —cada rama hace lo que dice— pero sí una inconsistencia de producto.

**Subir el objetivo de 4/5 a 1/1 NO lo arregla:** haría crecer la primitiva (53 px en `THAI_HOT`) y
dejaría el glifo clavado en 22, porque no hay fuente de texto más grande. Empeoraría la brecha entre
familias.

**Cambio anotado como posible, NO hecho (preferencia del autor, 2026-07-27):** *primitiva siempre,
con la altura como constante* — se saca el glifo, las dos familias dibujan lo mismo y el tamaño pasa
a ser una decisión nuestra (4/5 o completa, a gusto). Se pierde el glifo nativo, que en la práctica
solo veía la mitad de los devices y se veía chico. Alternativa descartada por frágil: pedir el glifo
en la fuente numérica adivinando su ancho (no medible, y varía por familia). Alternativa intermedia
si algún día se quiere conservar el glifo: usarlo **solo en celdas chicas** (donde queda al 66-78 %) y
primitiva en las grandes — a costa de que el trazo cambie entre campos de una misma pantalla.

Por ahora **queda como está**: el 840 sigue con el glifo chico. `USE_ARROW_GLYPH = false` ya fuerza la
primitiva en todos lados si se quiere probar el cambio sin tocar nada más.

### 6.13 La flecha-glifo estaba 4,5 px ARRIBA de los dígitos (BUG MEDIDO Y CORREGIDO 2026-07-27)

Hallado por el autor mirando la Opción K en el simulador (perfil 840, celda 125×62): la flecha se veía
desplazada hacia arriba respecto del número. **No era la ilusión del punto §6.12** (ahí la flecha es
más CHICA; esto es que además estaba más ALTA), y se confirmó midiendo la captura píxel a píxel:

| | tinta (y) | alto | centro |
|---|---|---|---|
| dígitos `70` (`NUMBER_MEDIUM`) | 44 … 69 | 26 px | 56,5 |
| flecha (glifo `↓` en `FONT_LARGE`) | 42 … 62 | 21 px | **52,0** |

→ **4,5 px de desfase**, con la asimetría delatora: 2 px de más por arriba y **7 px de dígito
sobrante por abajo**.

**Causa: el glifo arrastra el descendente de SU PROPIA fuente, y nadie lo compensaba.** El código
calculaba una sola `arrowCy = cy − descent(fuenteDelValor)/2 + ARROW_NUDGE` y la usaba para las dos
ramas, pero las dos ramas no se comportan igual:

- **primitiva** (`drawUpArrow`/`drawDownArrow`): derivan `top`/`bot` del alto REAL de la figura, así que
  centrarlas en `arrowCy` centra la tinta. **Estaba bien** → el 830 y su familia se veían correctos.
- **glifo**: es TEXTO dibujado con `VCENTER`, o sea que lo centrado es la **caja** de `FONT_LARGE`
  (alto 31, ascent 22, **descent 9**), y el glifo no pinta ese descendente → la tinta flota
  `descent/2 = 4,5 px` hacia arriba.

Cuentas con las métricas reales del 840 (`NUMBER_MEDIUM` 42/33/9, `FONT_LARGE` 31/22/9), que
reproducen la medición de la captura al píxel: baseline de los dígitos en `cy+12`, tinta en
`[cy−14, cy+12]` → centro `cy−1`; baseline del glifo en `cy+4,5`, tinta en `[cy−16,5, cy+4,5]` →
centro `cy−6`. Diferencia **5 px** calculada vs. **4,5 px** medida.

**Arreglo #1 (una línea, en las DOS copias del motor):** sumarle al `y` del glifo el descendente de su
fuente — `arrowCy + Graphics.getFontDescent(gf)/2`.

#### Segunda iteración, el mismo día: el arreglo #1 era correcto pero INCOMPLETO

El autor mandó una segunda captura, esta vez con **7 celdas de distintos tamaños en una pantalla** — y
ahí se vio lo que una sola celda no podía mostrar:

| celda | fuente del número | dígitos (tinta) | flecha | desfase |
|---|---|---|---|---|
| 121×62 (×6) | `NUMBER_MEDIUM` | y29-54 · h26 · centro **41,5** | y31-51 · h21 · centro **41,0** | **0,5 px** ✅ |
| 244×125 | `NUMBER_THAI_HOT` | y38-79 · h42 · centro **58,5** | y44-64 · h21 · centro **54,0** | **4,5 px** ❌ |

**Seis de siete perfectas, la grande igual de mal que antes.** Causa: el objetivo mismo estaba mal. El
código apuntaba a `cy − descent(fuenteDelValor)/2`, un término que **escala con la fuente del número**
(`MEDIUM` d=9 → −4 px; `THAI_HOT` d=14 → −7 px), mientras la compensación del glifo es fija
(`FONT_LARGE`, +4). En la celda de 62 px los dos se cancelaban por casualidad; en la grande sobraban 3.

**Y esto corrige algo que yo había afirmado de más:** dije que "la primitiva estaba bien". Estaba bien
**en esa celda**. La primitiva usa el mismo `arrowCy`, así que en una celda grande el 830 también dibuja
la flecha ~3,5 px arriba. El defecto era de las DOS ramas; la del glifo solo lo tenía peor.

**Dónde está de verdad la tinta de los dígitos (medido, dos fuentes):** `NUMBER_MEDIUM` pinta 26 px en
una caja de 42 (7 de aire arriba, 9 de descendente abajo) y `THAI_HOT` 42 en 67. En las dos la tinta
queda **~1 px por encima del centro de la caja**, y ese 1 px **no escala**. O sea que el objetivo
correcto es una CONSTANTE, no un término de fuente.

**Arreglo #2 (el definitivo):** `ARROW_INK_BIAS = 1` reemplaza a `ARROW_NUDGE` y

```
var arrowCy = cy - ARROW_INK_BIAS;          // antes: cy - getFontDescent(valueFont)/2 + ARROW_NUDGE
```

Verificado por cálculo con las métricas reales del 840 para las cuatro fuentes numéricas y las dos
ramas: el desfase queda en **≤ 0,5 px** en todos los casos (`MEDIUM` 0 · `HOT` 0,5 · `THAI_HOT` 0,5 ·
`MILD` 0,5), que es el piso de una grilla de enteros.

#### Tercera iteración: el 830, y por qué NINGUNA constante podía servir

El autor miró entonces el **830** (la otra familia, la que dibuja la primitiva) y la flecha se veía
**baja**, con el desfase escalando igual que antes:

| celda | dígitos (tinta) | flecha (primitiva) | desfase |
|---|---|---|---|
| 121×62 (×6) | y24-52 · h29 · centro **38,0** | y28-52 · h25 · centro **40,0** | **2 px abajo** |
| 244×125 | y26-75 · h50 · centro **50,5** | y34-76 · h43 · centro **55,0** | **4,5 px abajo** |

Probando las métricas de las dos familias (`monkeydo -t`, un `(:test)` que solo llama a
`getFontAscent/Descent/Height` — no necesita `Dc`, así que corre en las dos) apareció **el dato que
cierra todo el asunto: las dos familias llenan el `ascent` de forma distinta.**

| | `N_MEDIUM` | `N_THAI_HOT` | tinta / ascent | flecha 4/5 vs. tinta |
|---|---|---|---|---|
| **840** (TTF) | a=33 d=9 h=42, tinta 26 | a=53 d=14 h=67, tinta 42 | **0,79** | 26 vs 26 → **iguales** |
| **830** (bitmap `.cft`) | a=32 d=10 h=42, tinta 29 | a=53 d=17 h=70, tinta ~49 | **0,91** | 25 vs 29 → 4 px menos |

O sea que **el 4/5 histórico coincide por casualidad con el alto de la tinta en la familia TTF**, y por
eso en el 840 la flecha parecía perfecta. En el 830 los dígitos son más altos que la flecha: **no había
error de posición, era diferencia de ALTO.**

**Y de ahí sale el límite duro: centrar es imposible de forma portable.** El centro de la tinta es
`baseline − tinta/2`, y **`tinta` no lo da ninguna API** — varía por familia (0,79 vs 0,91) y no se
puede derivar de `ascent`/`descent`/`height` (en las dos familias `a+d = h`, así que no hay ni una
señal para distinguirlas). Cualquier constante es un valor horneado de una captura, que un device nuevo
rompe. Las dos iteraciones anteriores fueron exactamente eso, y cada una falló en la otra familia.

**Lo que SÍ es exacto y queryable: la baseline.** Verificado en las dos familias — la tinta de los
dígitos **termina exactamente en la baseline** (830: y52 con baseline 52 · 840: y54 con baseline 54;
los glifos redondos `6`/`0` se pasan 1 px, que es *overshoot* tipográfico normal).

**Decisión del autor (2026-07-27, por AskUserQuestion): la flecha se apoya en la baseline**, como la
unidad. Implementación — y el matiz importa porque las dos ramas llenan distinto:

- Se ancla la **BANDA** de la flecha, no la figura: `[valueBaseY − aH, valueBaseY]` con `aH = 4/5` del
  ascent del valor. `valueBaseY = cy + (ascent − descent)/2`, el mismo que ya usaba la unidad.
- La **primitiva LLENA la banda** → su base cae exacta en los pies de los dígitos, en toda fuente.
- El **glifo va CENTRADO DENTRO de la banda** (con su `+ descent/2`), **no apoyado en el piso**: está
  topeado en `FONT_LARGE` (§6.12), así que en celda grande su tinta mide la mitad que los dígitos
  (21 vs 42 px) y apoyarlo lo habría hundido **13 px**, leyéndose como un subíndice. Detectado por
  cálculo ANTES de que el autor lo viera.

Desfase predicho con esto (calculado con métricas reales, las dos familias × chica y grande): **830
0 px en la base** (la primitiva coincide con los pies; 2-4 px más corta arriba, que es el alto, no la
posición) y **840 0,5 px en celda chica y 1,5 px en la grande**. Desaparecieron las dos constantes
(`ARROW_NUDGE` y `ARROW_INK_BIAS`): no quedó ninguna perilla vertical para la flecha.

**Tres cosas que este bug enseña y valen para todo el repo** (subidas a `GARMIN_MTB_SPEC.md` §3.4):

1. **Es el mismo hecho de la regla dura de centrado, un nivel más abajo:** la regla habla del
   descendente de la fuente del NÚMERO; acá el que sobraba era el de la fuente del SÍMBOLO. Cada vez
   que se dibuja un glifo con `VCENTER` para alinearlo con otra cosa, hay que restarle su propio aire.
2. **Fue un defecto ASIMÉTRICO POR FAMILIA de fuentes,** o sea invisible si validás en un solo device:
   el 830 (primitiva) lo tenía mucho más leve que el 840 (glifo). Es el segundo caso de la lista
   de §11.2 en que "se ve bien en un device" no dice nada del otro.
3. **Y ASIMÉTRICO POR TAMAÑO DE CELDA, que es peor porque conviven en la misma pantalla:** un error
   proporcional a la fuente del número se esconde en la celda donde afinaste. **Regla nueva: la
   alineación se valida en una pantalla con celdas de varios tamaños, no en una.** La captura de 7
   celdas del autor encontró en un intento lo que la de 1 celda no podía encontrar nunca.

⚠️ **Y fue el segundo cambio que hubo que aplicar DOS VECES** (barrel + la copia de J, que sigue sin
migrar) — en realidad **cuatro ediciones duplicadas**, contando las dos iteraciones. La divergencia que
se aceptó al montar el barrel ya cobró, el mismo día. Argumento a favor de migrar J.

Verificado en cada iteración: export de los 17 targets limpio en las dos apps, **J 12/12 y K 9/9**. La
comprobación final de que la tinta coincide es del autor con F5 — el probe headless de §11.1 mide
fuentes y decide layout, pero **no lee píxeles** (no hay `getPixel` en Monkey C). Lo que sí se puede
hacer, y fue lo que resolvió esto, es **medir la captura del autor píxel a píxel** (BMP + numpy, sin
Pillow: `sips -s format bmp` y parsear el header) y comparar los centros de tinta contra las cuentas.

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

## 9. Settings — la referencia configurable (DECIDIDO e IMPLEMENTADO 2026-07-26; v1 no tenía ninguno)

**Historia:** v1 salió sin settings a propósito (patrón de la A: métrica fija, promedio global, banda muerta implícita — el `AppBase` era `initialize()` + `getInitialView()` y nada más). Esta sección especifica la **primera iteración con settings**, pedida por el autor: elegir contra qué se compara la velocidad actual. Las cuatro preguntas de diseño que esta sección dejaba abiertas quedaron **resueltas con el autor el 2026-07-26**; sus respuestas están integradas abajo y marcadas con «(decisión)».

### 9.1 Producto

Dos referencias posibles:

| modo | referencia | la flecha significa | segunda línea |
|---|---|---|---|
| **0 — Promedio de la salida** (default) | `Activity.Info.averageSpeed`, se mueve sola | «vas más rápido/lento que tu media» | `PROM 20.4` / `AVG 20.4` |
| **1 — Objetivo fijo** | número que el usuario tipea en los settings | «vas por encima/debajo de tu objetivo» (ritmo pautado) | `META 25.0` / `GOAL 25.0` |

- **Dos settings** (decisión): una lista con los dos modos + el número del objetivo. El estado inconsistente que esto habilita (modo objetivo con número en 0/vacío) **degrada en silencio al promedio** — un setting sin tocar jamás deja el campo inservible.
- **El número se interpreta en la unidad del device** (`paceUnits`: km/h métrico, mph imperial) (decisión). Sin conversión. Consecuencia documentada en el rótulo del setting: si el usuario cambia las unidades del device DESPUÉS, el mismo número pasa a significar la otra unidad. Aceptado.
- **Prefijo de la segunda línea en modo objetivo: `Meta`/`Goal`** (decisión), en MAYÚSCULAS al dibujar, mismo tratamiento que `Prom`/`Avg`.
- **Banda muerta: la MISMA ±0,1 (`DEAD_BAND_TENTHS = 1`) en los dos modos** (decisión). Cero constantes nuevas; si en la calle la flecha resulta inquieta contra un objetivo fijo, se ensancha después (`classify` ya recibe el parámetro).
- **Dónde se configura (verificado 2026-07-26, y B ya lo tenía anotado):** desde el TELÉFONO — Garmin Connect Mobile (device → Activities & App Management → Data Fields) o la app Connect IQ Store — o Garmin Express. **En el propio Edge NO se puede** (límite de plataforma para data fields). Al guardar, al device le llega `onSettingsChanged()` en caliente, sin reiniciar la actividad.

### 9.2 Archivos nuevos (copiar el patrón de B, que ya funciona en producción)

**`resources/settings/properties.xml`** — literal:

```xml
<properties>
    <!-- Reference the arrow compares against (SPEC 9). Stored values are magnitudes, not
         list indices. targetSpeed is in the DEVICE's speed unit (paceUnits) by decision:
         no conversion anywhere. -->
    <property id="referenceMode" type="number">0</property>   <!-- 0 = ride average, 1 = fixed target -->
    <property id="targetSpeed" type="float">0.0</property>    <!-- 0/negative = not configured -->
</properties>
```

**`resources/settings/settings.xml`** — literal:

```xml
<settings>
    <!-- Edited from the phone (Garmin Connect Mobile / Connect IQ Store app) or Garmin
         Express. Data fields cannot be configured on-device (platform limit; same note
         as b-grade-vam). -->
    <setting propertyKey="@Properties.referenceMode" title="@Strings.SetReference">
        <settingConfig type="list">
            <listEntry value="0">@Strings.RefAverage</listEntry>
            <listEntry value="1">@Strings.RefTarget</listEntry>
        </settingConfig>
    </setting>
    <setting propertyKey="@Properties.targetSpeed" title="@Strings.SetTargetSpeed">
        <settingConfig type="numeric" min="0" max="99.9" />
    </setting>
</settings>
```

(El `max="99.9"` mantiene el objetivo dentro de la plantilla `"88.8"`; no hay pérdida real — un objetivo de tres dígitos no existe en bici.)

**Schema VERIFICADO compilando (2026-07-26):** estos dos XML, con la property `float` y el `settingConfig type="numeric"` con `min`/`max` — la única combinación que B no usa y que nadie había probado en este repo — **compilan limpios en edge840 y edge830** con el SDK 9.2.0 (probe temporal, revertido). El implementador puede pegarlos tal cual.

**Strings** — agregar a `resources/strings/strings.xml` (base EN):

```xml
<string id="SetReference">Compare against</string>
<string id="RefAverage">Ride average</string>
<string id="RefTarget">Fixed target</string>
<string id="SetTargetSpeed">Target speed, 1 decimal (in your device speed unit, km/h or mph)</string>
<string id="TargetLabel">Goal</string>
```

y a `resources-spa/strings/strings.xml`:

```xml
<string id="SetReference">Comparar contra</string>
<string id="RefAverage">Promedio de la salida</string>
<string id="RefTarget">Objetivo fijo</string>
<string id="SetTargetSpeed">Velocidad objetivo, 1 decimal (en la unidad de tu dispositivo, km/h o mph)</string>
<string id="TargetLabel">Meta</string>
```

⚠️ Recordatorios de plataforma ya pagados en este repo: nada de `--` dentro de comentarios XML, y el manifest **no** necesita cambios por settings.

### 9.3 `SpeedFormat` — una función pura nueva (con test, §10)

```monkeyc
// Target speed typed by the user -> tenths, the SAME integer domain shownTenths uses, so
// TrendArrow.classify compares like with like (SPEC 9). The value is ALREADY in display
// units (device paceUnits) by decision: no conversion. null / zero / negative mean "not
// configured" -> null, and the caller falls back to the ride average.
function targetTenths(value as Float or Number or Null) as Number or Null {
    if (value == null) { return null; }
    var f = value.toFloat();
    if (f <= 0.0) { return null; }
    return roundHalf(f * 10.0);
}
```

### 9.4 `TrendArrowApp.mc` — pasa a reenviar settings (deja de ser mínimo)

Reemplazar la clase completa por el patrón de B (`GradeVamApp.mc`):

```monkeyc
class TrendArrowApp extends Application.AppBase {

    private var mView as TrendArrowView or Null = null;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        mView = new TrendArrowView();
        return [mView];
    }

    // Fired when the user saves app settings from the phone / Express. NOT fired by a
    // device units change -- compute() re-reads paceUnits every tick for that.
    function onSettingsChanged() as Void {
        if (mView != null) {
            mView.reloadSettings();
        }
        WatchUi.requestUpdate();
    }
}
```

(Actualizar también el comentario de cabecera del archivo, que hoy dice «v1 has NO settings».)

### 9.5 `TrendArrowView.mc` — cambios exactos

Agregar `import Toybox.Application;` a los imports.

**Miembros nuevos** (junto a `mAvgPrefix`):

```monkeyc
private var mTargetPrefix as String = "GOAL";        // "Meta"/"Goal" uppercased (loaded once)
private var mRefPrefix as String = "AVG";            // ACTIVE prefix: mAvgPrefix or mTargetPrefix
private var mUseTarget as Boolean = false;           // referenceMode == 1
private var mTargetTenths as Number or Null = null;  // pre-rounded target, null = not usable
```

**`initialize()`**: tras cargar `mAvgPrefix`, cargar `mTargetPrefix = (WatchUi.loadResource(Rez.Strings.TargetLabel) as String).toUpper();` y llamar `reloadSettings();` al final.

**Funciones nuevas** (calco de B; `readNumber` es COPIA del de `GradeVamView.mc`):

```monkeyc
// Re-read the 2 app settings (called from initialize() and from TrendArrowApp.
// onSettingsChanged()). Never called per-tick.
function reloadSettings() as Void {
    mUseTarget = (readNumber("referenceMode", 0) == 1);
    mTargetTenths = SpeedFormat.targetTenths(readFloat("targetSpeed", 0.0));
    // Active prefix: GOAL/META only when the target is actually usable; target mode with
    // an unset/zero number silently behaves as average mode (SPEC 9.1).
    mRefPrefix = (mUseTarget && mTargetTenths != null) ? mTargetPrefix : mAvgPrefix;
    mCacheW = -1;   // prefix width changed -> force font/layout re-selection (B's idiom)
}

private function readNumber(key as String, dflt as Number) as Number {
    var v = Application.Properties.getValue(key);
    if (v instanceof Lang.Number) { return v; }
    if (v instanceof Lang.Float) { return v.toNumber(); }
    return dflt;
}

private function readFloat(key as String, dflt as Float) as Float {
    var v = Application.Properties.getValue(key);
    if (v instanceof Lang.Float) { return v; }
    if (v instanceof Lang.Number) { return v.toFloat(); }
    return dflt;
}
```

**`compute()`** — el único cambio de lógica. Donde hoy dice

```monkeyc
mAvgStr = SpeedFormat.displayString(avgTenths);
mBothStr = mCurStr + INLINE_SEP + mAvgStr;
mArrowState = TrendArrow.classify(curTenths, avgTenths, DEAD_BAND_TENTHS);
```

pasa a

```monkeyc
// The reference the arrow AND the second line compare against: the fixed target when
// configured and valid, else the ride average (silent fallback, SPEC 9.1). Same
// DEAD_BAND_TENTHS in both modes (author's decision, 2026-07-26).
var refTenths = (mUseTarget && mTargetTenths != null) ? mTargetTenths : avgTenths;
mAvgStr = SpeedFormat.displayString(refTenths);
mBothStr = mCurStr + INLINE_SEP + mAvgStr;
mArrowState = TrendArrow.classify(curTenths, refTenths, DEAD_BAND_TENTHS);
```

(`mAvgStr`/`mAvgFont`/`mAvgBandH` CONSERVAN su nombre — ahora significan «la referencia»; documentarlo en el comentario del miembro y no renombrar, para que el diff sea mínimo.)

**Los 4 usos de `mAvgPrefix` fuera de `initialize()` pasan a `mRefPrefix`** — hoy son exactamente estos, y ninguno más:

1. `onUpdate()`, medición de la línea secundaria: `dc.getTextWidthInPixels(mAvgPrefix, mAvgUnitFont)` → `mRefPrefix`.
2. `onUpdate()`, dibujo del prefijo de esa línea: `dc.drawText(ax, avgCy, mAvgUnitFont, mAvgPrefix, ...)` → `mRefPrefix`.
3. `selectLabel()`, sufijo del label ancho: `var suffix = mIsWide ? (INLINE_SEP + mAvgPrefix) : "";` → `mRefPrefix` (el label ancho pasa a decir `VELOCIDAD / META` en modo objetivo).
4. `fitUnitFont()`, reserva de ancho `withPrefix`: `dc.getTextWidthInPixels(mAvgPrefix, u)` → `mRefPrefix`.

**Nada más cambia.** Ni fuentes, ni tamaños, ni centrado, ni la unidad apilada, ni el glifo/primitiva de la flecha (§6.6/§6.11): el prefijo activo entra en las mismas mediciones de siempre y el `mCacheW = -1` de `reloadSettings()` garantiza que la escalera se re-elija con el ancho del prefijo nuevo.

**Anchos MEDIDOS de los prefijos (2026-07-26, probe headless en los dos devices), porque una versión anterior de esta spec afirmaba de más que «miden igual»:**

| fuente | AVG | GOAL | PROM | META |
|---|---|---|---|---|
| `FONT_MEDIUM` (840) | 31 | **40** | 42 | 40 |
| `FONT_XTINY` (840) | 19 | **25** | 26 | 24 |
| `FONT_MEDIUM` (830) | 37 | **48** | 53 | 49 |
| `FONT_XTINY` (830) | 18 | **23** | 26 | 25 |

En **español** `META` es más angosto que `PROM`: el modo objetivo nunca aprieta más que el actual. En **inglés**, en cambio, `GOAL` es **6-9 px más ancho que `AVG`** (~30 %). **No hay desborde** —`fitUnitFont` reserva el prefijo ACTIVO, así que el grupo siempre entra— pero la consecuencia real y aceptada es que **en una celda angosta y en inglés el modo objetivo puede elegir un escalón de fuente menos que el modo promedio**. Es visible solo comparando los dos modos en la misma celda chica, y es preferible a recortar el rótulo.

### 9.6 Casos borde (todos con comportamiento definido)

| caso | comportamiento |
|---|---|
| modo objetivo, número 0 / negativo / nunca tocado | promedio, prefijo `PROM`/`AVG` — indistinguible del modo 0 |
| el usuario cambia settings EN MEDIO de una actividad | `onSettingsChanged` → `reloadSettings` → efecto inmediato al siguiente tick |
| cambia las unidades del device con objetivo fijado | el número se reinterpreta en la unidad nueva (decisión); la flecha sigue coherente porque actual y objetivo están ambos en décimas de display |
| tipos raros desde GCM (Number donde Float, null) | `readNumber`/`readFloat` degradan al default, como en B |
| objetivo válido pero sin GPS aún (`curTenths == null`) | `classify` ya devuelve NONE con null; el campo muestra `--` como hoy |

### 9.7 Cómo probarlo sin salir a andar

En el **simulador**: correr con F5 y editar los settings en caliente desde el menú del simulador (en el 9.2.0 es la opción que edita los *App Settings*; el nombre exacto del menú puede variar entre versiones del SDK — es la misma que se usó para probar los 4 settings de B, y dispara `onSettingsChanged` de verdad). Con `TEST_MODE = true` el generador converge la media a **20,0 km/h** (§11): fijar objetivo `25.0` → la flecha debe quedar ABAJO en todos los tramos salvo el de 30,0, y la segunda línea debe decir `META 25.0` fija; volver el modo a promedio → vuelve `PROM` y la línea se mueve. En **device real**: cambiar el setting desde Garmin Connect Mobile con el campo en pantalla y verificar que cambia sin reiniciar.

**Criterios de aceptación:** los de siempre (§13) más: (1) suite verde incluido `testTargetTenths`; (2) export de los 17 targets sin warnings; (3) en el sim, el ciclo completo promedio→objetivo→promedio sin tocar F5; (4) el prefijo cambia también en el label del modo ancho.

### 9.8 Estado: IMPLEMENTADO y EN LA STORE como v0.2.1 (canal beta, 2026-07-26)

**Subido al canal beta como `v0.2.1`** el 2026-07-26 (la `v0.2.0` quedó quemada: se exportó con
`TEST_MODE = true` y el portal no permite reusar el número — ver `store/RELEASES.md`). La ficha de
producción (v0.1.0) no se tocó.

Todo lo de §9.2–§9.5 está escrito y verificado por CLI: **export de los 17 targets limpio** (solo el aviso conocido del Edge 1030 con CIQ 3.2.5) y **suite 12/12** (los 11 de antes + `testTargetTenths`). Los cuatro usos de `mAvgPrefix` que §9.5 listaba se reemplazaron y `mAvgPrefix` quedó únicamente en su carga desde recursos y en la línea que elige el prefijo activo.

**Pendiente, y solo el autor puede hacerlo:** los criterios (3) y (4) de arriba — el paseo por el simulador cambiando el setting en caliente, y mirar el modo objetivo en una celda angosta en inglés, que es donde el `GOAL` más ancho puede bajar un escalón de fuente.

### 9.8.1 El default es el PROMEDIO DE LA SALIDA (requisito duro, VERIFICADO end-to-end 2026-07-26)

Una instalación nueva, o un usuario que nunca abre los ajustes, tiene que comportarse **exactamente
como la v0.1.0**: flecha contra el promedio real de la salida. Se sostiene en cuatro capas
independientes, y las cuatro apuntan al promedio:

| Capa | Qué dice |
|---|---|
| `properties.xml` | `referenceMode` = **0**, `targetSpeed` = **0.0** |
| `settings.xml` | el valor **0** es `RefAverage` (y es la PRIMERA entrada de la lista) |
| `reloadSettings()` | `readNumber("referenceMode", 0)` → el fallback si la clave no se puede leer **también** es 0 |
| inicializadores de miembro | `mUseTarget = false`, `mTargetTenths = null`, `mRefPrefix = "AVG"` |

Y hay una quinta red: `targetSpeed` = 0.0 → `targetTenths` devuelve `null` → aun con el modo en
objetivo, la condición `mUseTarget && mTargetTenths != null` es falsa y la referencia vuelve al
promedio. O sea: **para salir del promedio hacen falta las DOS cosas** (modo en objetivo *y* un número
> 0), lo cual es justamente la degradación silenciosa de §9.6.

**El default de `properties.xml` es de PRIMERA INSTALACIÓN, no un valor que se reimponga.** Se usa
solo cuando la propiedad todavía no existe; una vez que hay un valor guardado, ese manda y cambiar el
XML no lo pisa. Evidencia directa: borrando el `.SET` del simulador, la corrida siguiente volvió a
leer `0` (probado abajo); la otra mitad (que un valor existente le gana a un XML nuevo) sale del foro
y es coherente con eso. **Para los usuarios juega a favor:** quien viene de la v0.1.0 no tiene ningún
valor guardado para estas claves → al actualizar le aplica el default = promedio.

⚠️ **Corolario para depurar:** si el simulador muestra el modo objetivo "sin motivo", lo primero es
mirar si hay un valor guardado de una prueba anterior — el XML ya no manda. Se limpia borrando el
`.SET` (se regenera con los defaults). Y **la fuente de verdad de en qué modo está la app NO es el
formulario del editor** (lo renderiza un servidor de Garmin y esa zona tiene bugs reportados con las
entradas de lista), **es el prefijo de la segunda línea en pantalla**: `PROM` = promedio, `META` =
objetivo.

**Verificado atravesando la plataforma, no leyendo el XML** (2026-07-26): se borró el `.SET` del
simulador para forzar una instalación limpia y un probe `(:test)` temporal leyó
`Application.Properties.getValue` de verdad → `referenceMode=0`, `targetSpeed=0.000000`,
`targetTenths=null`, y además `new TrendArrowView()` + `onUpdate()` pintó sin excepción con esos
defaults. El probe se borró después (misma técnica de §11.1).

⚠️ `Application.Properties.getValue` **lanza excepción** si la clave no existe, y estos lectores no
usan `try/catch` — a propósito: es el mismo patrón que `GradeVamView` de la Opción B (líneas 162/169),
y las claves están garantizadas porque se compilan dentro del `.prg` desde `properties.xml`. No
divergir de B acá sin motivo.

### 9.9 Cómo se prueban estos settings (VERIFICADO 2026-07-26)

Tres caminos, y el orden importa porque **solo el primero es completo**.

**1. Simulador — SÍ, es el camino real.** Dos piezas distintas, en dos menús distintos (verificado
2026-07-26 inspeccionando las cadenas del binario `ConnectIQ.app/Contents/MacOS/simulator`):

- **`File > App Settings Editor`** — el formulario. Sus controles son `Select an app` + `Language`
  (⚠️ el selector de idioma es lo que permite probar `META` vs `GOAL` sin cambiar el device) y los
  botones `Close`/`Save`, con `Settings Saved` al confirmar. Lee el schema del
  `<app>-settings.json` que genera el compilador (existe ya: `bin/test-settings.json`, con las 2
  claves, los `configMin/configMax` y los strings de los dos idiomas); si no lo encuentra dice
  *"No settings file found for this app. This app may not have settings."*
- **`Simulation > Trigger App Settings`** — dispara el evento de settings sin reiniciar la app, o sea
  lo que ejercita `onSettingsChanged()` → `reloadSettings()` (§9.6). Vive entre `Force onHide` /
  `Trigger Goal` / `Set Weather`. Al lado hay un `Timeout App Settings` (simula que el push falla).

⚠️ **El editor es SERVER-BACKED, no local** — hallazgo que conviene saber antes de perder tiempo: el
binario postea a `https://<host>.garmin.com/<...>/appSettings2/sdk/input` con un
`Authorization: Bearer`, y tiene el error *"Unable to get Connect credentials. Please log in to the
Connect IQ SDK Manager."* → **hace falta internet y estar logueado en el SDK Manager** con la cuenta
de Garmin. Es el mismo backend que renderiza el formulario del teléfono, y explica por qué el
formulario no acepta markdown y por qué el schema tiene tan pocos atributos (§9.10).

Los valores quedan en un archivo `.SET` en el sandbox del simulador:

```
/var/folders/.../T/com.garmin.connectiq/GARMIN/APPS/SETTINGS/<NOMBRE>.SET
```

(en esta máquina ya existen `J-TEST.SET` y `B-TEST.SET`; se localizan con
`find /var/folders -name "*.SET"`). Formato: magic `abcdabcd`, la lista de claves en texto plano
(`targetSpeed`, `referenceMode`), magic `da7ada7a`, y los valores.
⚠️ **El nombre del `.SET` NO sale del nombre del `.prg`:** probado el 2026-07-26 corriendo un
`ZZPROBE.prg` — escribió `J-TEST.SET`, no `ZZPROBE.SET`. El simulador mapea por app, no por archivo.

**2. Sideload + teléfono → NO SE PUEDE (RESUELTO con un canal beta, 2026-07-26).** Los settings de una app sideloadeada **no** se pueden
editar desde Garmin Connect Mobile ni desde Garmin Express: el mecanismo de settings cuelga del
vínculo con la Connect IQ Store, y el sideload nunca establece ese vínculo. Es limitación de
plataforma, no un bug nuestro. Como J **ya está publicada** (v0.1.0, canal producción), la vía
soportada es subir la versión con settings a la store e instalarla desde ahí: recién entonces
aparecen los ajustes en el teléfono. **Decisión tomada el 2026-07-26:** para no gastar una ronda de
review por iteración contra la ficha publicada, J estrena el desdoblamiento de ids de la Opción A —
id **beta** `f70f3c984e4c43d496006628f3510817` en `main` (entrada del portal **sin publicar**, se
instala por el link de `apps.garmin.com` + Connect Mobile) e id **prod**
`140986d8c6bc4026880e117255a6ce67` pinneado en `release`. Los dos ids, el riesgo del merge y el
procedimiento están en `store/RELEASES.md` y en `CLAUDE.md`.

⚠️ **Y antes de exportar el `.iq`: `TEST_MODE` en `false`.** Con `TEST_MODE = true` un build de
release compila limpio pero muestra `--` eternamente (el generador sintético es `(:debug)` y el stub
`(:release)` devuelve nulls). Pasó con el primer `.iq` beta de la v0.2.0. El workaround que documenta Garmin es copiar a mano el `.SET`
del simulador a `GARMIN/APPS/SETTINGS/` del device por OpenMTP — **probado y descartado**: un
`Properties.setValue` desde un probe headless se lee bien dentro de la misma corrida pero **no llega
al `.SET` en disco** (el simulador no vuelca sin que la app termine bien), y aparte (el
nombre que espera el firmware del device no está confirmado; si el prefijo sale mal, la app
simplemente sigue con los defaults, así que el costo de probar es bajo y se nota al toque porque el
prefijo de la línea secundaria pasa de `PROM` a `META`).

**Receta concreta con `TEST_MODE = true`** (el perfil sintético promedia exactamente 20,0 km/h):
poner el objetivo en **25,0** y no en 20 — contra 25 la flecha solo apunta arriba en el segmento de
30 km/h, así que el patrón cambia de forma OBVIA respecto del modo promedio y se ve que la referencia
cambió de verdad. Segunda señal independiente: la línea de abajo queda **clavada** (un objetivo no se
mueve) mientras que el promedio deriva. Y para ver la cuantización de §9.10, tipear **22.37** → la
pantalla tiene que decir **22.4**.

**3. Para validar en el 840 solamente el RENDER del modo objetivo** (que `META`/`GOAL` entre y no
desborde) no hacen falta settings: alcanza un hook `(:debug)` que clave `mUseTarget = true` y
`mTargetTenths`, del mismo modo que `TEST_MODE`, y sideloadear ese `.prg`. Separa la pregunta
"¿se ve bien?" (device) de la pregunta "¿el setting llega?" (simulador).

### 9.10 El decimal del objetivo: por qué la UI no lo puede forzar

**Decidido: 1 decimal.** Pero el schema de settings **no puede exigirlo**. La autoridad es
`resources.xsd` del SDK (verificado 2026-07-26): `settingConfigType` acepta **solo** los atributos
`type`, `readonly`, `required`, `min`, `max`, `maxLength`, `errorMessage`. **No existe `step` ni
`decimals`** — un `type="numeric"` acepta cualquier float dentro de `min`/`max`, así que el usuario
puede tipear `22.37`.

Lo resuelve el código, que ya está implementado y es la razón por la que `targetTenths` existe:
cuantiza a décimas (`roundHalf(v*10)`) y **la línea secundaria muestra el valor cuantizado**, así que
lo que se ve en pantalla es siempre exactamente contra lo que compara la flecha (`22.37` → muestra
`22.4` → compara 224 décimas). El título del setting lo dice: *"Target speed, 1 decimal"*.

La única forma de que la UI misma imponga el decimal sería un `type="list"` con las entradas
enumeradas (p. ej. 10,0 → 40,0 de a 0,5 = 61 entradas) — **descartado**: cuesta 61 strings, limita el
rango y no aporta nada sobre la cuantización, que es exacta igual. **Tampoco se escribe de vuelta** el valor cuantizado a la
propiedad, y esto se evaluó con evidencia (2026-07-26) porque es lo primero que uno quiere hacer:

- *Escribirlo* funciona: `Properties.setValue` sobre una clave que YA es un setting declarado persiste
  en el device (confirmado por un ingeniero de Garmin en el foro y verificado en hardware por quien
  reportó — el matiz de ese hilo es que en el SIMULADOR no persiste sin matar la app con Ctrl-K).
- *Verlo al reabrir los ajustes en el teléfono* NO funciona: hay un bug abierto que describe
  exactamente este caso (la app corrige el valor en el device, el teléfono sigue mostrando el que
  tipeó el usuario). Respuesta de Garmin: *"We are currently trying to see if there's an issue with
  GCM receiving information"*. Guardar transfiere los valores solo HACIA el reloj, no de vuelta.
- Modo de fallo peor (inferencia a partir de ese hilo, NO verificado): si el teléfono conserva
  `10.27` cacheado y el usuario después toca el OTRO setting, al guardar empuja su bundle entero y
  revive el `10.27`, pisando nuestro `10.3` → el número iría y vendría solo.

Por eso el redondeo queda del lado del device y no se reescribe: **la pantalla del Edge ya muestra el
valor cuantizado** con prefijo `META`/`GOAL`, que es el único lugar donde el ciclista lo mira. Lo que
queda desalineado es el formulario del teléfono, y eso no está en nuestras manos arreglarlo de forma
confiable.

## 10. Unit tests (obligatorio — convención del repo desde 2026-07-19)

Patrón exacto de A/B: módulos puros + funciones `(:test)` de `Toybox.Test`, un `<Módulo>Test.mc` por módulo, helpers de `TestUtil.mc` **planos** (NO `(:test)` — el runner ejecuta toda función `(:test)` como caso; ver B §10 gotcha 2). Para comparar contra `null` usar **`Test.assertMessage(x == null, ...)`**, NUNCA `Test.assertEqualMessage(x, null, ...)` (invoca `.equals()` sobre el actual y explota si es `null` — gotcha ya descubierto en B).

**`TrendArrowTest.mc` — casos concretos:**
```monkeyc
// deadBand=0 = comparación estricta (cualquier diferencia redondeada muestra flecha).
(:test)
function testTrendArrowUp(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(253, 240, 0), TrendArrow.UP, "25.3 > 24.0 -> UP");
    Test.assertEqualMessage(TrendArrow.classify(-50, -100, 0), TrendArrow.UP, "-5.0 > -10.0 -> UP");
    return true;
}

(:test)
function testTrendArrowDown(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(150, 200, 0), TrendArrow.DOWN, "15.0 < 20.0 -> DOWN");
    Test.assertEqualMessage(TrendArrow.classify(-100, -50, 0), TrendArrow.DOWN, "-10.0 < -5.0 -> DOWN");
    return true;
}

(:test)
function testTrendArrowNone(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(200, 200, 0), TrendArrow.NONE, "equal -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(0, 0, 0), TrendArrow.NONE, "zero == zero -> NONE");
    return true;
}

(:test)
function testTrendArrowNullSafety(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(null, 200, 1), TrendArrow.NONE, "null current -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(200, null, 1), TrendArrow.NONE, "null average -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(null, null, 1), TrendArrow.NONE, "both null -> NONE");
    return true;
}

// Banda muerta semántica de ±0,1 km/h (deadBand = 1 décima): |Δ| <= 0,1 -> NONE ("va a la media");
// solo |Δ| > 0,1 (o sea >= 0,2) muestra flecha.
(:test)
function testTrendArrowDeadBand(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(TrendArrow.classify(240, 240, 1), TrendArrow.NONE, "24.0 vs 24.0 -> NONE");
    Test.assertEqualMessage(TrendArrow.classify(241, 240, 1), TrendArrow.NONE, "+0.1 gap -> NONE (at avg)");
    Test.assertEqualMessage(TrendArrow.classify(239, 240, 1), TrendArrow.NONE, "-0.1 gap -> NONE (at avg)");
    Test.assertEqualMessage(TrendArrow.classify(242, 240, 1), TrendArrow.UP, "+0.2 gap -> UP");
    Test.assertEqualMessage(TrendArrow.classify(238, 240, 1), TrendArrow.DOWN, "-0.2 gap -> DOWN");
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
    // >= 100 sin decimal (2026-07-25, §5.2/§6.10): 999 -> "99.9", 1000 -> "100", 1006 -> "101",
    // -1023 -> "-102" (redondea a la unidad, mantiene el signo).
    return true;
}

(:test)
function testUnitLabel(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.unitLabel(false), "KM/H", "metric");
    Test.assertEqualMessage(SpeedFormat.unitLabel(true), "MPH", "statute");
    return true;
}
```

**`SpeedFormatTest.mc` — caso nuevo para la referencia configurable (§9.3):**

```monkeyc
(:test)
function testTargetTenths(logger as Test.Logger) as Boolean {
    Test.assertEqualMessage(SpeedFormat.targetTenths(25.0), 250, "25.0 -> 250 tenths");
    // 22.25 is exact in binary: 22.25*10 = 222.5 exactly -> half away from zero -> 223.
    // Do NOT use values like 22.35 here: they are not representable and the test would
    // hinge on float noise.
    Test.assertEqualMessage(SpeedFormat.targetTenths(22.25), 223, "22.25 -> 223 (half away)");
    Test.assertEqualMessage(SpeedFormat.targetTenths(15), 150, "integer Number accepted");
    Test.assertMessage(SpeedFormat.targetTenths(0.0) == null, "0 -> null (not configured)");
    Test.assertMessage(SpeedFormat.targetTenths(-5.0) == null, "negative -> null");
    Test.assertMessage(SpeedFormat.targetTenths(null) == null, "null -> null");
    return true;
}
```

La elección de referencia en sí (`refTenths = objetivo o promedio`) vive en `compute()` — View fina, no testeable por convención (§3); por eso el fallback se prueba desde la función pura (`0 → null`) más el paseo del simulador de §9.7.

## 11. Hooks de debug para el simulador (patrón A §13 / B §9 — obligatorio)

- **`TEST_MODE`** (`const false` plano): con `true` + build DEBUG, `compute()` consume un generador sintético `(:debug)`. **Perfil de velocidad con decimales** (tabla de tramos, MÁS SIMPLE que la de B porque no hace falta simular ruido — Tier 1 no tiene pipeline de suavizado):
  ```
  speedsKmh = [10.4, 25.7, 10.1, 30.2, 15.6, 20.3,  8.5, 28.9]
  dursSec   = [  15,   15,   15,   15,   15,   15,   15,   15]
  ```
  El generador acumula **su propia distancia y tiempo** y calcula el promedio **exactamente como Garmin** (`distanciaAcumulada / tiempoAcumulado`, la misma fórmula de tasa vista en §8) — así el promedio converge de forma realista a lo largo del ciclo y la demo muestra las 3 flechas (arriba en los tramos rápidos, abajo en los lentos, sin flecha cerca del cruce) **y a la vez deja ver el número de promedio evolucionando** en la línea secundaria (§6), que es exactamente lo que el autor quiere validar de un vistazo.
  **Perfil actualizado 2026-07-25** para ejercitar la FLECHA, no solo el número: ocho valores que promedian **exactamente 20,0 km/h** (`[30.0, 10.0, 20.0, 25.0, 15.0, 20.1, 19.9, 20.0]`, segmentos de 3 s), así la media converge ahí y el ciclo recorre los tres estados a propósito — arriba (30/25), abajo (10/15) y **sin flecha** (20,0 y los bordes ±0,1 donde decide `DEAD_BAND_TENTHS`). Las transiciones flecha↔sin-flecha son las que destaparon el salto lateral de §6.11. Los perfiles anteriores quedan **comentados en el código, no borrados** (pedido del autor).

- **`DEBUG_MEASURE`** (`const false` plano, patrón A/B): imprime a la consola cada tamaño de celda distinto + las fuentes elegidas (valor/promedio, alto/ascent/descent) + si la flecha entró (`mArrowFits`) + si se muestra el promedio (`mShowAvg`). Misma utilidad que en A/B: es la data para afinar el layout en las 6 resoluciones.
- **Esquema de exclusión del release:** idéntico a A/B — `const false` plano (el optimizador `-r` elimina el bloque) + `(:debug)`/`(:release)` pares para las funciones llamadas desde el guard. Volver ambos flags a `false` antes de todo build de release.

### 11.1 Medir el layout SIN abrir la GUI del simulador (técnica nueva, 2026-07-25)

Hallazgo importante: **se puede verificar la selección de fuentes de una celda de cualquier tamaño sin ver la pantalla**, desde un test `(:test)` corrido con `monkeydo -t` (que sí anda headless). Con esto se caza en minutos lo que antes requería F5 + ojo del autor, y se puede barrer las 6 resoluciones de una.

Receta (fue un archivo **temporal**, `source/FontProbeTest.mc`, borrado después de usarlo — no queda en el repo):

1. Un `Dc` offscreen del tamaño exacto de la celda: `new Graphics.BufferedBitmap({:width=>w, :height=>h}).getDc()`. ⚠️ **La API cambió entre devices:** en el **edge830** (CIQ 3.3) funciona el constructor `new Graphics.BufferedBitmap(...)` y NO existe `Graphics.createBufferedBitmap`; en el **edge840** es al revés (el constructor tira `Symbol Not Found`). Un probe permanente tendría que ramificar con `Graphics has :createBufferedBitmap`.
2. `var view = new TrendArrowView(); view.onUpdate(dc);` — la View se instancia y dibuja **fuera del ciclo de vida del data field sin problema** (`getBackgroundColor()`, `WatchUi.loadResource` y `getDeviceSettings()` responden bien en el test).
3. Con `DEBUG_MEASURE = true`, cada `onUpdate` imprime la celda + las fuentes elegidas → la decisión REAL del código, no una re-derivación a mano. (Al hacerlo se descubrió que `debugMeasure` no reportaba la rama inline de §6.8; ahora imprime también `mInlineFont`/`mInlineUnitFont`/`mInlineArrowFits`.)
4. Para medir métricas crudas de fuente (`getFontAscent/Descent`, `getFontHeight`, `getTextWidthInPixels` de plantillas y labels) alcanza el mismo `Dc` offscreen sin la View — así se armó la tabla de §6.10.

Lo que la técnica **NO** reemplaza: ver los píxeles. No hay lectura de píxeles desde Monkey C (`Dc` no tiene `getPixel`), así que la validación estética final (¿se ve bien?) sigue siendo del autor con F5. Lo que sí da: certeza de QUÉ fuente/tamaño se elige en cada celda de cada device, que es donde estaban los bugs.

### 11.2 `GLYPH_PROBE` — la flecha como glifo de fuente: experimento y resultado (2026-07-25)

Hook de debug (`const GLYPH_PROBE = false` + par `(:debug)`/`(:release)`, igual que `TEST_MODE`) que reemplaza todo el campo por una galería de glifos. Existe para contestar, **en hardware real**, si la flecha podía dejar de ser primitiva. Está diseñado para **auto-diagnosticarse**: dos de sus tres filas son CONTROLES cuyo resultado esperado es "no se pinta nada".

| fila | contenido | para qué |
|---|---|---|
| 1 | `↑↓▲▼` en fuente de TEXTO | los candidatos |
| 2 | `↑▲8` en fuente NUMÉRICA | **control**: por tabla no existen ahí; el `8` solo prueba que la fila se dibujó. Si aparecen flechas → el runtime **sustituye fuentes** |
| 3 | `⬆` (U+2B06, ausente hasta del TTF) + las dos primitivas | **control** de "glifo ausente" + comparación de forma |

**Resultados — y no coinciden entre sí, que es justamente el hallazgo:**

| fila | predicción por tablas de fuente | SIMULADOR (840) | **EDGE 840 REAL** (captura `bin/2026-07-25-20-29-34.BMP`) |
|---|---|---|---|
| 1 · texto | las 4 | las 4 | **las 4** |
| 2 · numérica *(control)* | solo el `8` | flechas + `8` | **`↑` 12×26 px, `▲` 22×22, `8`** |
| 3 · `⬆` *(control)* | nada | **nada** | **pintó, 10×15 px** |

(Las otras dos formas de la fila 3 miden 7×11 y son las primitivas: el cálculo daba 6×11.)

Tres conclusiones, ninguna obvia de antemano:

1. **Existe una cadena de FUENTES DE RESPALDO no documentada.** El 840 pintó los dos glifos en fuente numérica, que no los tiene, y pintó U+2B06, que **no está en ningún archivo de fuente del SDK**. Las tablas de fuente dicen qué hay en el archivo nominal; **no predicen lo que el device dibuja**.
2. **El simulador se equivoca en LAS DOS direcciones**: falsos positivos (fila 2) y falsos **negativos** (fila 3 — el device pinta lo que el sim no). Es MÁS restrictivo que el hardware, al revés de lo que uno asumiría. Ningún resultado del simulador sobre un carácter no-ASCII sirve como prueba.
3. **El argumento de tamaño se cae**: el `↑` sustituido en fuente numérica salió de **26 px de alto**, justo lo que J necesita. Pedido en fuente de texto toparía en 18 px; pedido en numérica, la sustitución lo escala.

**Decisión del autor: aprovechar el glifo donde exista, con fallback.** La primitiva no se toca — sigue siendo lo que funciona en los 13 y lo único que escala hasta 42 px. Pero como el 840 sí resuelve el glifo, el código lo detecta en runtime y lo usa ahí; en la familia `.cft` cae a la primitiva, que es el comportamiento de siempre. Mecánica en §6.11. Lo que NO se hizo, a propósito: confiar en el tamaño grande que da la sustitución en fuente numérica, porque ahí la medida devuelve 0 y no se puede maquetar.

**HECHO en hardware** (Edge 840 real, sideload del `.prg` de debug, 2026-07-25) — resultados en la tabla de arriba. Lo único que quedaría por comprobar es un **Edge 830 físico**, que el autor no tiene; por eso la recomendación no depende de conseguirlo.

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
