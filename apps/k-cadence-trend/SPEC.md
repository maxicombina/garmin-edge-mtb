# SPEC — `k-cadence-trend` (Opción K)

> Data field Connect IQ para Garmin Edge: **la flecha de tendencia de la Opción J, sobre la cadencia**.
> Muestra la cadencia actual en grande con ▲/▼ al lado según vayas pedaleando más rápido o más lento
> que tu promedio de la salida, y el promedio en una línea secundaria cuando la celda es alta.
> Especificación de implementación **autocontenida**.
>
> **Esta es la app más simple de la familia, y por dos motivos independientes.** (1) La **métrica** es
> la más simple que hay: Garmin la entrega en **rpm enteros** y *rpm es rpm en todos los países*, así
> que no hay conversión de unidades, ni décimas, ni dos grafías de unidad — nada del aparato que
> necesitó la velocidad en J. (2) El **render no vive acá**: lo aporta el barrel
> [`barrels/trend-core/`](../../barrels/trend-core/), extraído de J. La View son ~130 líneas y no
> tiene **ni una línea de layout**.
>
> **Lo que hay que leer antes de tocar código:** la sección «Barrels» del [`CLAUDE.md`](../../CLAUDE.md)
> del repo (cómo se consume, los cuatro gotchas del montaje) y [`apps/j-trend-arrow/SPEC.md`](../j-trend-arrow/SPEC.md)
> §6 completo, que es donde vive documentado el motor de render que esta app usa (§6.10 paridad con el
> campo nativo, §6.11–6.13 la flecha, §6.14 el label). **Esta spec no repite nada de eso**: describe
> solo lo que es propio de la cadencia.
>
> ⚠️ **Regla heredada de J que sigue mandando acá:** la flecha va **junto al VALOR**, nunca junto al
> label — la flecha **ES el dato**, cambia cada tick. Es lo contrario de la rampa decorativa de la
> Opción B, que va solo en el label. Si el código de B te hace dudar, manda esta nota.

---

## 1. Objetivo y rol (honesto)

1. **Diferencial frente a lo nativo:** el Edge muestra cadencia actual y cadencia media, pero **en
   celdas separadas**. Ningún campo nativo las combina en un indicador único de tendencia. Es el
   mismo argumento de J, aplicado a otra métrica.
2. **Para qué sirve de verdad, en MTB:** sostener cadencia es una decisión táctica en subida (¿bajo un
   piñón y giro más, o aguanto la marcha?). La flecha responde «¿estás girando más o menos que tu
   propia media de hoy?» sin tener que leer y comparar dos números.
3. **Muestra los dos números, no solo la flecha** (igual que J, y por el mismo pedido del autor): en
   celdas con espacio, cadencia actual grande con flecha **y** el promedio debajo, para poder verificar
   de un vistazo que la flecha corresponde.

### 1.1 Por qué es una app aparte y no un setting de la Opción J

Decidido el 2026-07-27. La tentación obvia es una sola app con un setting «métrica: velocidad /
cadencia / FC». **No sirve:** en Connect IQ los settings pertenecen a la **APP**, no a cada celda donde
la pusiste (se ve en el sandbox del simulador: hay un archivo de settings por app). Un selector de
métrica mostraría **la misma métrica en todas las instancias del campo**, así que no podrías ver
velocidad y cadencia a la vez — que es exactamente para lo que uno querría el campo.

Costo aceptado: **tres apps** (J velocidad, K cadencia, L frecuencia cardíaca) ocupando tres de los
~10 slots de campo del device, tres fichas en la store y tres ids. A cambio, cada una se puede poner
en la pantalla junto a las otras.

### 1.2 Vehículo de aprendizaje

Primera app del repo **construida sobre un barrel** (el mecanismo de librería de Monkey C). El
resultado medido es el argumento a favor: la View de K son ~130 líneas contra las 858 que tenía la de
J antes de la extracción. Ver §3.2.

## 2. Plataforma (heredada de A/B/J — no re-verificar)

Idéntica a las otras tres apps, sin cambios: **13 Edge devices** en el manifest, **Edge 840 como
referencia** y **Edge 830 como el otro extremo** (familia de fuentes distinta, ver §6), **API 3.3.0**
como target, tipo `datafield`, **sin permisos** (`<iq:permissions/>` vacío). Compilar **siempre contra
los 17 targets** con `monkeyc -e` y **nunca filtrar la salida** — un error puede romper en un solo
device (CIQ 3.3 admite máximo 9 argumentos por método: el 830 lo hace cumplir, el 840 no).

**Unidades: NO HAY NADA QUE DECIDIR.** Es la diferencia más grande contra J. La cadencia se lee y se
muestra en rpm; no existe variante métrica/imperial, así que:

- no hay conversión (J necesita m/s → km/h o mph),
- no se lee `System.getDeviceSettings()` para nada (J relee `paceUnits` en cada tick porque cambiar las
  unidades del device **no** dispara `onSettingsChanged`),
- la unidad se configura **una vez** en `initialize()` y no se vuelve a mirar,
- y el bloque de unidad es de **una sola línea** (`rpm`), no dos apiladas (`km` sobre `h`).

## 3. Arquitectura

**Clase base: `WatchUi.DataField` completo** (no `SimpleDataField`), misma razón que A/B/J: queremos
controlar fuente, formato y color nosotros.

### 3.1 Estructura de archivos

```
k-cadence-trend/
├── manifest.xml                # datafield; 13 products; minApiLevel 3.3.0; <iq:depends TrendCore>
├── monkey.jungle               # declara el barrel TrendCore por FUENTE (ruta relativa)
├── source/
│   ├── CadenceTrendApp.mc      # AppBase mínimo: getInitialView() -> [view]. Sin settings en v1.
│   ├── CadenceTrendView.mc     # DataField: compute() lee y formatea, onUpdate() delega el render
│   │                           # entero al barrel. ~130 líneas, cero layout.
│   ├── CadenceFormat.mc        # PURO. displayString / trendValue / unitTop / unitBottom (§5.1)
│   └── CadenceFormatTest.mc    # 4 tests (§7)
├── resources/strings/          # AppName, CadenceLabel (+ Short), AvgLabel  (inglés = base/fallback)
├── resources-spa/strings/      # español
├── resources-<device>/drawables/  # ícono launcher por device — HOY PLACEHOLDER, ver §3.4
├── docs/code-walkthrough.html  # explicación del código (regla del repo: se mantiene al día)
└── store/RELEASES.md           # versionado de ESTA app (fuente de verdad del número)
```

**No hay `TestUtil.mc` propio**, a diferencia de J: los helpers `assertNear`/`assertIsNumber` son para
comparar floats, y acá **no hay ni un float** — la cadencia es entera de punta a punta. Si algún día
hace falta, el barrel tiene su copia namespaceada (`TrendCore.TestUtil`).

### 3.2 El reparto con el barrel: qué es de quién

`barrels/trend-core/` aporta el **clasificador** (`TrendCore.TrendArrow`, puro y genérico) y el
**motor de render entero** (`TrendCore.TrendRenderer`, ~710 líneas: escalera de fuentes, unidad
apilada estilo nativo, flecha glifo-o-primitiva con el hueco reservado, modo inline para celdas
anchas, caché por celda). Lo aporta **compartido con J y con la futura L**.

| Lo aporta el BARREL (compartido) | Lo aporta ESTA app (propio de la cadencia) |
|---|---|
| `TrendArrow.classify(cur, ref, banda)` → UP/NONE/DOWN | El **valor de banda**: `DEAD_BAND_RPM = 3` (§5.3) |
| Todo el layout, la selección de fuentes y el dibujo | Los **strings** de display, vía `CadenceFormat` (§5.1) |
| La escalera de fuentes y el caché por celda | La **plantilla de ancho estable** `"888"` (§6.1) |
| El bloque de unidad (apilado o de una línea) | La **unidad**: `"rpm"` arriba, nada abajo |
| El label largo/corto que degrada como el nativo | Los **textos** del label y el prefijo (`CADENCIA`/`CAD`/`PROM`) |
| Las constantes de layout, todas medidas contra el nativo | La lectura de `Activity.Info` y el `TEST_MODE` |

**Regla de oro del reparto:** el barrel **no sabe qué métrica dibuja** y no debe enterarse nunca. Si
algo de la cadencia necesita un `if` dentro del barrel, está mal puesto: se resuelve del lado de la app
(como se hizo con el 0 de no pedalear, §5.2, que se resolvió sin tocar una línea del barrel).

### 3.3 Cómo se consume el barrel (y los gotchas ya pisados)

Se consume **por FUENTE**, no como `.barrel` compilado. Dos declaraciones:

```
# monkey.jungle -- forma con CORCHETES = dependencia por fuente, ruta RELATIVA
TrendCore = [../../barrels/trend-core/monkey.jungle]
base.barrelPath = $(TrendCore)
```

```xml
<!-- manifest.xml -->
<iq:barrels>
    <iq:depends name="TrendCore" version="0.1.0"/>
</iq:barrels>
```

Ventaja: **cero paso de build extra**, nada binario que versionar, y editar el barrel se aplica en la
próxima compilación de cualquier consumidor. Los cuatro gotchas están en `CLAUDE.md`; el que importa
para esta app es que **los tests `(:test)` del barrel SÍ corren desde acá** y aparecen namespaceados
(`TrendCore.testX`) junto a los propios — ver §7.

### 3.4 Ícono — PENDIENTE (hoy es un placeholder que engaña)

⚠️ **Los 13 launchers de `resources-<device>/drawables/` son los de la Opción J, copiados y
byte-idénticos** (verificado comparando los archivos, 2026-07-27). Consecuencia concreta: **en la
lista de campos del Edge, K es indistinguible de J salvo por el nombre**. Es un bloqueante blando de
la subida a la store, no del desarrollo.

Cuando se rediseñe, lo aprendido en J §3.3 aplica tal cual y no hay que volver a descubrirlo: el
launcher es un **dibujo aparte y plano** (no un downscale del master), el master lleva volumen, se
generan con Pillow por código para tener geometría exacta, y **conviene testear el motivo a ciegas**
con observadores que no sepan qué quiso decir el autor — así se descubrió que los tacos del neumático
de J hacían leer «ajustes» a 7 de 7. Motivo natural para K: **biela/plato o pedal**, que además
rompe la silueta circular del de J y se distingue de él a 35 px.

## 4. Entradas — `Activity.Info`

Verificado leyendo `api.mir` del SDK 9.2.0 (2026-07-27) y por compile-probe: los dos campos existen y
son `Number or Null`, o sea **rpm enteros** — no hay que redondear nada.

| Campo | Tipo | Qué es | Notas |
|---|---|---|---|
| `info.currentCadence` | `Number or Null` | cadencia instantánea, rpm | `null` sin sensor; **`0` es un valor legítimo** (§5.2) |
| `info.averageCadence` | `Number or Null` | promedio de la actividad, rpm | lo calcula Garmin: **no hay que acumular nada** (Tier 1, ver J §3.1) |
| `info.timerState` | `Number or Null` | estado del cronómetro | `== Activity.TIMER_STATE_ON` → dibujar normal, si no atenuado |

Los tres se leen con guarda `has`, como en A/B/J. La disponibilidad de estos campos como métrica
«Tier 1» (Garmin da actual **y** promedio, sin que la app derive nada) ya estaba verificada por doc
oficial para la Opción J — ver `GARMIN_MTB_SPEC.md` §4, Opción J.

### 4.1 Pregunta abierta: ¿el promedio de Garmin incluye los ceros?

**NO VERIFICADO.** El generador sintético de `TEST_MODE` **excluye** los ceros de su promedio (§8), y
el comentario del código dice que Garmin hace lo mismo «en la mayoría de los devices». Eso es una
**inferencia, no una medición**: no se comprobó ni en el simulador con un FIT real ni en el 840.

Por qué importa, en una línea: si el promedio nativo **incluyera** los ceros de las bajadas, sería
bastante más bajo que el promedio pedaleando, y en subida la flecha marcaría ▲ casi permanentemente —
el campo diría poco. **Cómo cerrarla:** en una salida real (o un FIT con bajadas largas), comparar
nuestro número de promedio contra el campo nativo «Cadencia media» en la misma pantalla; si difieren,
el nuestro es el de Garmin (lo leemos tal cual) y lo que hay que revisar es solo el texto de esta
sección. Anotado también en §9.

## 5. Algoritmos

### 5.1 `CadenceFormat` — módulo puro

Sin `Dc`, sin `Activity.Info`, sin estado de device → enteramente testeable (§7). Cuatro funciones:

```
displayString(rpm)  -> "84" | "0" | NO_DATA        // lo que el usuario ve
trendValue(rpm)     -> 84 | null                    // el entero que la flecha compara
unitTop()           -> "rpm"
unitBottom()        -> ""                           // una sola línea: nada que apilar
```

`displayString` es solo la guarda de `null` más `toString()`: **no hay redondeo** porque el valor
llega entero. Compárese con `SpeedFormat` de J, que necesita conversión de unidad, un dominio en
décimas para tener el redondeo en un solo lugar, y soltar el decimal a partir de 100.

### 5.2 LA decisión de producto: el `0` de no pedalear

**Es la única decisión real de esta app** (autor, 2026-07-27). En MTB, una bajada son minutos sin
pedalear y la cadencia es un **0 legítimo**. Tratar ese 0 como «vas por debajo de tu media» clavaría
una flecha ▼ durante toda la bajada y diría algo **falso**: no estás pedaleando más lento que tu
media, no estás pedaleando.

**Comportamiento elegido: se muestra el `0` real y NO se dibuja flecha.**

Implementado con una asimetría deliberada entre las dos funciones:

| | pedaleando (84) | sin pedalear (0) | sin sensor (`null`) |
|---|---|---|---|
| `displayString` | `"84"` | **`"0"`** | `NO_DATA` (`"--"`) |
| `trendValue` | `84` | **`null`** | `null` |
| flecha resultante | ▲/▼/nada | **nada** | nada |

Lo elegante es **cómo** se consigue: `trendValue` devuelve `null`, lo que **reusa el camino
`null → NONE` que el clasificador ya tenía** para «sin datos». No hubo que tocar `TrendArrow` ni
agregarle un caso especial — y eso importa porque es código **compartido con J y L**, donde 0 no
significa lo mismo. La regla de §3.2 en acción.

⚠️ **Hay un test que junta las dos piezas** (`testCadenceCoastingProducesNoArrow`) y que **falla si
alguien "simplifica" `trendValue` metiéndola dentro de `displayString`**. Esa asimetría parece un
descuido y no lo es; el test está ahí para defenderla.

Nota: `trendValue` también devuelve `null` con rpm **negativos**. No son físicos, pero un valor así
tampoco debe producir flecha (guarda defensiva, con test).

### 5.3 Banda muerta: 3 rpm

`DEAD_BAND_RPM = 3`. La flecha aparece solo si `|actual − promedio| > 3`.

El autor propuso 2 o 3; se eligió **3** porque la lectura a 1 Hz **jitterea sola un par de rpm**
(cadencia de sensor de pedaleo real, no de rueda), así que con 1 la flecha seguiría al ruido en vez
de a tu pedaleo. Como en J, es una decisión **semántica** antes que anti-parpadeo: para el autor,
pedalear dentro de 3 rpm de tu media **es** pedalear a tu media.

Es una sola constante si hay que ensancharla: `TrendArrow.classify` la recibe como parámetro, no la
tiene horneada (por eso J puede pasar décimas y K rpm con el mismo código — ver el test
`testTrendArrowScaleAgnostic` del barrel).

La banda es **inclusiva**: una diferencia igual a 3 todavía lee «a la media» (`+3` → sin flecha,
`+4` → ▲). Fijado por test.

### 5.4 `compute()` — casi trivial

Corre ~1×/s y **no dibuja**. Entero:

1. Leer `timerState`, `currentCadence`, `averageCadence` (con guardas `has`; o el generador sintético
   si `TEST_MODE`).
2. `mRunning = (state == TIMER_STATE_ON)`.
3. `mCurStr = CadenceFormat.displayString(cur)` y `mRefStr = …(avg)`.
4. `mArrowState = TrendCore.TrendArrow.classify(trendValue(cur), trendValue(avg), DEAD_BAND_RPM)`.

**Sin buffer, sin EMA, sin filtro de outliers, sin estado propio entre ticks** — nada del pipeline que
la Opción B necesita para pendiente y VAM. Es lo que significa «Tier 1».

⚠️ Detalle que se ve fácil pasar por alto en el paso 4: se le pasa **`trendValue`, no el rpm crudo**.
Es lo que hace funcionar §5.2. Y se aplica **también al promedio**, no solo al actual: un promedio de 0
(los primeros segundos de la actividad, antes de pedalear) tampoco es una referencia con la que
comparar.

## 6. Render — delegado por completo al barrel

`onUpdate(dc)` son **tres líneas**: pasarle los valores al renderer, pasarle el color de fondo
(`getBackgroundColor()` es un método de `DataField`, así que el barrel no puede llamarlo solo) y
dibujar. No hay una sola medición ni un solo `drawText` en esta app.

Lo que se configura **una vez** en `initialize()`:

- `setLabels(CADENCIA, CAD, PROM)` — nombre largo, corto y prefijo de la línea secundaria, ya
  uppercased. El barrel elige el largo si entra en la celda y el corto si no, como el campo nativo.
- `setTemplates("888", "888 / 888")` — ver §6.1.
- `setUnit("rpm", "")` — una sola línea. **Se puede llamar una vez y olvidarse**, a diferencia de J,
  que la revisa por tick porque las unidades del device pueden cambiar (§2).

### 6.1 La plantilla de ancho estable `"888"`

El barrel elige la fuente midiendo una **plantilla de 8s**, nunca el valor en vivo (si midiera el
valor, un número entraría y el siguiente no, y el layout saltaría cada segundo). La plantilla tiene
que ser **cota superior real de todo valor que la métrica pueda producir**.

`"888"` = 3 dígitos. La cadencia humana no llega a 4 dígitos: los sprints de pista en récord del mundo
andan cerca de 200 rpm, y `displayString` no puede producir nada más ancho que 3 dígitos con datos
físicos. Y es **más angosta** que la de J (`"88.8"`), así que en la misma celda la cadencia suele
poder usar una fuente igual o más grande que la velocidad.

### 6.2 Lo que el barrel hace y acá no hay que volver a pensar

Resumido para no tener que abrir J §6 salvo que se vaya a tocar el motor: la flecha se ancla a la
**baseline** del número (no a la tinta, que no es queryable y difiere por familia de fuentes); el
**hueco de la flecha se reserva siempre**, se pinte o no, para que el número no salte de lado al
cruzar la media; la fuente numérica se elige por **`getFontAscent`**, no por `getFontHeight`; el label
usa **el mayor entre `FONT_GLANCE` y `FONT_SMALL` medido en runtime**, porque en la familia bitmap
`FONT_GLANCE` no existe y cae en silencio a la fuente más chica; y la flecha se dibuja como **glifo si
el device lo resuelve** (medido en el propio device, dos señales) y como **primitiva** si no.

**Consecuencia heredada, no un bug de esta app:** en el 840 la flecha-glifo mide ~41 % del alto de los
dígitos y en el 830 la primitiva mide ~79 %, así que **el campo se ve distinto según la familia de
fuentes**. Está medido y documentado en J §6.12, con el cambio preferido por el autor si algún día se
hace algo: `USE_ARROW_GLYPH = false` para forzar primitiva en todos lados. Se arregla **en el barrel**
y las tres apps lo heredan de una vez — que es el motivo de que el barrel exista.

## 7. Unit tests — 9 en total (4 propios + 5 del barrel)

Criterio del repo: **tests en verde ANTES de la validación visual**. Verificado con `monkeydo -t`
(edge840, build `--unit-test`) el 2026-07-27: **9/9 PASS**.

Los 5 del barrel **corren desde esta app**, namespaceados. No son un extra decorativo: significa que
el clasificador compartido se testea una vez por app consumidora.

| Test | Qué fija |
|---|---|
| `testCadenceDisplayString` | `84`→`"84"`, **`0`→`"0"`** (no `--`), `120`→`"120"` (dentro de `"888"`), `null`→`NO_DATA` |
| `testCadenceTrendValueCoasting` | `84`→`84`; **`0`→`null`**; `null`→`null`; `-5`→`null` (guarda defensiva) |
| `testCadenceCoastingProducesNoArrow` | Las dos piezas juntas, como las usa la View: `0` con media 80 → **NONE, no DOWN**; 90→UP; 70→DOWN; ±3 dentro de la banda. **Este es el test que protege la asimetría de §5.2.** |
| `testCadenceUnitParts` | `"rpm"` arriba y **vacío abajo** (una línea) |
| `TrendCore.testTrendArrowBasics` | arriba/abajo/igual → UP/DOWN/NONE con banda 0 |
| `TrendCore.testTrendArrowNegatives` | el clasificador es genérico: no asume valores positivos |
| `TrendCore.testTrendArrowNullSafety` | `null` en cualquiera → NONE, sin crash |
| `TrendCore.testTrendArrowDeadBand` | la banda es **inclusiva**; incluye el caso de 3 rpm de esta app |
| `TrendCore.testTrendArrowScaleAgnostic` | misma aritmética con décimas (J) y con rpm (K) |

Gotchas de test del repo que aplican acá (ya cometidos y documentados en B §10): las comparaciones con
`null` van con `Test.assertMessage(x == null, …)` y **nunca** con `assertEqualMessage(x, null, …)` (esa
invoca `.equals()` sobre el actual y explota); y los helpers de test deben ser funciones **planas**,
no `(:test)`, porque el runner ejecuta como caso toda función anotada.

## 8. Hooks de debug para el simulador

Mismo esquema que A/B/J, sin novedad: `TEST_MODE` es un **`const false` plano** (el optimizador `-r`
elimina el bloque `if` entero), el generador sintético es `(:debug)` y tiene un par `(:release)` que
es un stub, y `compute()` **nunca referencia un miembro `(:debug)`** — todo vuelve por el valor de
retorno.

**El perfil sintético está armado para ejercitar la FLECHA y la regla del 0, no el número:**
`[95, 84, 0, 70, 87, 81, 0, 60]` rpm, 3 s por tramo. Tiene valores por encima y por debajo de la
media, los bordes de ±3 rpm donde decide la banda muerta, y **dos tramos de 0** (bajada sin pedalear)
que deben mostrar `0` **sin flecha**. El promedio lo acumula el propio generador para que **converja**
como el de Garmin — y excluye los ceros (ver la pregunta abierta de §4.1).

⚠️ **`TEST_MODE = true` en un build de RELEASE deja el campo mostrando `--` para siempre**, compilando
limpio y sin un warning: el generador es `(:debug)` y su stub `(:release)` devuelve nulls, así que la
rama nunca lee `Activity.Info`. **Le costó a J un número de versión quemado** (la v0.2.0). Verificar
el flag antes de exportar cualquier `.iq` o `.prg` de release.

### 8.1 Medir el layout sin abrir la GUI del simulador

La técnica de J §11.1 funciona igual acá, y es la única forma de verificar la selección de fuentes sin
pantalla: un test `(:test)` temporal que hace `new Graphics.BufferedBitmap({…}).getDc()`, instancia la
View real, le llama `compute()` y después `onUpdate(dc)`, e imprime
`TrendCore.TrendRenderer.debugSummary(dc)` — o sea **lo que el motor eligió**, no una re-derivación a
mano. Corre headless con `monkeydo -t`.

Dos trampas ya pagadas: hay que llamar **`compute()` antes** del `onUpdate` (si no, el motor mide con
la unidad vacía y elige fuentes para un grupo más angosto que el real; un `new Activity.Info()` con
todo en null alcanza), y la **API del bitmap difiere por device** (el edge830 quiere
`new Graphics.BufferedBitmap`, el edge840 quiere `Graphics.createBufferedBitmap`).

Lo que **no** reemplaza: mirar los píxeles. Monkey C no tiene `getPixel`, así que la validación
estética es del autor con F5. Lo que sí funciona muy bien es **medir sus capturas** píxel a píxel
(`sips -s format bmp` + numpy), y **pedirlas con celdas de varios tamaños y en los dos devices** — un
defecto de alineación puede ser asimétrico por tamaño **y** por familia de fuentes a la vez, o sea
invisible en una celda de un device.

## 9. Estado y pendientes

**Al 2026-07-27:** implementada, **9/9 tests PASS**, **export de los 17 targets limpio** (único
warning: el Edge 1030 con part number `006-B2924-00`, CIQ 3.2.5, que no llega al `minApiLevel` del
proyecto y queda fuera del `.iq` — esperado, pasa en las cuatro apps). **Sin publicar**; versión
`v0.1.0` registrada en [`store/RELEASES.md`](store/RELEASES.md) para la primera subida al canal beta.

| # | Pendiente | De quién |
|---|---|---|
| 1 | **Íconos propios** (§3.4) — hoy son los de J byte-idénticos. Bloquea la subida a la store, no el desarrollo. | asistente + autor |
| 2 | **Validación visual en el simulador** (F5, `TEST_MODE = true`): que la flecha siga al promedio, que los dos tramos de 0 no muestren flecha, y el layout en celdas de varios tamaños. | autor |
| 3 | **Validación en device real** con sensor de cadencia: que nuestro promedio coincida con el nativo, y de paso cerrar §4.1 (¿incluye los ceros?). | autor |
| 4 | **Assets de la ficha** del store (capturas, hero, textos) cuando se decida subirla. | ambos |

**No es un pendiente de esta app:** la **Opción L** (frecuencia cardíaca) está **en pausa** esperando
una decisión de producto del autor — si la flecha va sobre **bpm** o sobre la **zona de FC**, que es lo
que él usa. Ojo con la segunda: las zonas se leen con
`UserProfile.getHeartRateZones(UserProfile.getCurrentSport())` y eso **exige declarar el permiso
`UserProfile`** en el manifest; hoy **ninguna app del repo declara permisos**, y los permisos se le
muestran al usuario al instalar.

## 10. Referencias

- [`CLAUDE.md`](../../CLAUDE.md) — convenciones del repo, sección «Barrels», flujo de release, versionado por app.
- [`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md) §3.4 — todo lo medido sobre fuentes y glifos de los Edge; §4 Opción J — el producto «flecha de tendencia» y los dos tiers de métrica.
- [`apps/j-trend-arrow/SPEC.md`](../j-trend-arrow/SPEC.md) — **la spec del motor de render que esta app usa**: §6 completo, §11.1 (probe headless), §11.2 (el experimento del glifo).
- [`barrels/trend-core/`](../../barrels/trend-core/) — el código compartido; sus comentarios dicen contra qué se midió cada constante.
- [`docs/code-walkthrough.html`](docs/code-walkthrough.html) — la versión narrada de este documento.
