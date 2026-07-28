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
│   ├── CadenceTrendApp.mc      # AppBase: getInitialView() -> [view] + onSettingsChanged (§7)
│   ├── CadenceTrendView.mc     # DataField: compute() lee y formatea, onUpdate() delega el render
│   │                           # entero al barrel. ~130 líneas, cero layout.
│   ├── CadenceFormat.mc        # PURO. displayString / trendValue / targetRpm / unit* (§5.1, §7)
│   └── CadenceFormatTest.mc    # 5 tests (§8)
├── resources/
│   ├── strings/                # AppName, CadenceLabel (+ Short), AvgLabel, TargetLabel, settings
│   └── settings/               # properties.xml + settings.xml (§7)
├── resources-spa/strings/      # español
├── resources-<device>/drawables/  # ícono launcher por device, GENERADO por store/gen_icon.py (§3.4)
├── docs/code-walkthrough.html  # explicación del código (regla del repo: se mantiene al día)
└── store/
    ├── RELEASES.md             # versionado de ESTA app (fuente de verdad del número)
    ├── gen_icon.py             # dibuja TODO el ícono: master + ficha + los 13 launchers (§3.4)
    ├── icon-master-1024.png    # master RGBA con alpha real, para regenerar
    └── store-icon-500.png      # 500×500 opaco sobre gris #E6E6E6, para la ficha del portal
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
| El label largo/corto que degrada como el nativo | Los **textos** del label y el prefijo (`CADENCIA`/`CAD`/`PROM`/`META`) |
| La **caja** del glifo del label, reservada y centrada (§6.3) | La **geometría** del glifo: aro + biela + pedales |
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

### 3.4 Ícono — HECHO (2026-07-27). Cuerpo de pedal CUADRADO, todo dibujado por código

**Motivo:** cuerpo de **pedal de plataforma visto de frente** — marco **cuadrado** redondeado cobalto
`#0070F0`, cara azul muy oscuro `#0E1A38` y, dentro, **la misma raya ámbar y la misma flecha blanca
que J**. Sin texto, sin números, sin dientes.

**Todo sale de [`store/gen_icon.py`](store/gen_icon.py)** (requiere **solo numpy**, no Pillow): el
master 1024 RGBA, el `store-icon-500` opaco sobre gris, y los 13 launchers, **cada uno dibujado a su
tamaño** (35/36/40/56/68) porque reducir el master deja una mancha borrosa a 35 px — lección de la
Opción A. Los launchers van **planos** (sin brillo) y sin filete interior abajo de 56 px. **No editar
los PNG: editar el script y re-correrlo.**

**Las tres decisiones, y por qué:**

1. **La geometría interior es IDÉNTICA a la de J, a propósito.** La prueba a ciegas de J (7
   observadores sin contexto) encontró que **el objeto no se lee nunca** — 0 de 7 vieron un
   neumático — pero que **la raya cruzada por la flecha sí**: 7 de 7 llegaron a «línea de referencia
   que la flecha cruza». Eso es lo que hace de familia, así que se conserva tal cual.
2. **Lo que distingue a K de J a 35 px es la SILUETA, no el detalle:** cuadrado contra redondo. A ese
   tamaño el detalle no existe; la silueta sí. Verificado mirando los dos launchers de 35 px lado a
   lado.
3. **NO es un plato, que sería el motivo obvio de cadencia.** En esa misma prueba a ciegas, **7 de 7
   leyeron los tacos del neumático de J como «engranaje / tuerca / ajustes»** — el peor falso amigo
   posible en una lista de campos de datos, y lo que le costó los tacos a J. **Un plato es literalmente
   un engranaje**, así que habría resucitado el problema. Un cuadrado no puede leerse como engranaje.

⚠️ **Honestidad sobre lo que comunica:** el cuadrado **no grita «pedal»**. Su trabajo es gritar «no soy
la J». Que el objeto no se identifique ya lo sabemos por la prueba a ciegas de J; lo que el ícono tiene
que lograr es ser reconocible como parte de la familia y distinguible de su hermana en la lista del
device. **Lo que ningún dibujo puede explicar es que la raya sea tu media** — eso lo cargan el nombre
y la ficha.

**Un pozo que este ícono volvió a pisar** (y que el comentario del script de J ya advertía, en su
versión de arco): el primer intento sumaba una **banda especular** sobre el degradado y a 500 px se veía
como una **cuña de borde duro** en la esquina — un rayón, no un reflejo. En una silueta cuadrada la
banda no tiene una curva de la cual agarrarse, así que no hay forma de suavizarla: **se sacó y quedó
una sola rampa diagonal.** Verificado mirando el PNG, no asumido.

**Pendiente relacionado:** este ícono **no pasó por la prueba a ciegas** que sí hizo el de J. Vale
hacerla antes de subir la app si se quiere el mismo nivel de evidencia — la técnica está en J §3.3.

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

**NO VERIFICADO.** El generador sintético de `TEST_MODE` **excluye** los ceros de su promedio (§9), y
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

Sin `Dc`, sin `Activity.Info`, sin estado de device → enteramente testeable (§8). Cuatro funciones:

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

### 6.3 El glifo de la biela junto al label (2026-07-27) — y el hook nuevo del barrel

> ⏳ **ESTADO: TERCERA ITERACIÓN, hecha con capturas del device y pendiente de la mirada del autor
> (2026-07-28).** Rechazó la segunda (*«no se ve igual, aún no te queda bien bien»*) y mandó **dos
> capturas del 840 real con el glifo a DOS TAMAÑOS**: 23×18 px en una celda chica y 30×26 px en una
> celda ancha. Se extrajeron los dos mapas de píxeles y la geometría se ajustó contra **los dos a la
> vez**: coincide en el **87 %** de los píxeles del chico y el **96 %** del grande (91,9 % de promedio).
>
> 🔑 **LECCIÓN DE MEDICIÓN, y es la más reutilizable de todo esto: hacen falta DOS tamaños.** Con una
> sola captura no se puede distinguir **una fracción de una constante** — cualquier medida encaja como
> «tantos píxeles» y como «tanto por ciento del alto», y las dos dan resultados distintos al escalar.
> Los dos tamaños fijan las proporciones de verdad. Vale para el próximo glifo que haya que copiar.
>
> ✅ **EL SEGUNDO PENDIENTE («en el 830 con seis campos se ven cosas raras») YA ESTÁ DIAGNOSTICADO Y
> ARREGLADO (2026-07-28).** No era del glifo: en el layout **ancho** el 830 mostraba `95 ⃞/⃞ 81` porque
> **la fuente numérica de la familia bitmap no tiene el glifo de ESPACIO** y el separador `" / "` salía
> como dos cajas *notdef*. Estaba también en la **Opción J, publicada**. Arreglado en el barrel
> (`INLINE_SEP` sin espacios; el label conserva los suyos porque va en fuente de texto). Hecho y regla
> en `GARMIN_MTB_SPEC.md` §3.4.1. Ojo con la
> pista que ya tenemos: con seis campos las celdas son chicas, y ahí conviven tres cosas nuevas — el glifo (que **es más alto que el
> renglón y puede asomar en la banda del valor**), su umbral `ICON_MIN_H`, y la reserva de ancho que
> puede empujar el label al nombre corto. Es el primer lugar donde mirar. **Y el 830 es la otra familia
> de fuentes**, donde el label usa `FONT_SMALL` (ascent 17) en vez de `FONT_GLANCE`, así que el glifo
> sale más grande que en el 840: 23×19 contra 19×16.
>
> **Lo ya probado, para no repetirlo en la próxima vuelta:** (a) versión 1, un aro con una diagonal
> cruzándolo entero → leía como un signo de prohibido; (b) versión 2, la actual, con el interior abierto
> y el glifo atravesando el renglón. Las constantes a mover están al final de la sección.

El campo nativo del Edge **antepone un pictograma al nombre** de algunas métricas y no de otras: un
cronómetro en `TIEMPO`, un corazón en `ZONA`, **una biela en `CADENCIA`**; `VELOCIDAD`, `DISTANCIA` y
`TEMPERATURA` van sin nada. Por eso K lleva glifo y J no.

**Medido, no inventado** (dos capturas ampliadas del **840 real**). En la celda chica el glifo mide
**23×18 px** al lado de una mayúscula de **12**, deja **3 px** antes del texto, arranca **3 px por
encima del techo de la mayúscula** y **termina 3 px POR DEBAJO de la línea base**. En la celda ancha
mide **30×26** con mayúscula de **19**, hueco de 4, y arranca 5 arriba / termina 2 abajo. De ahí salen
todas las constantes.

⚠️ **DOS COSAS QUE EL PRIMER INTENTO HIZO MAL, las dos encontradas por el autor comparando capturas
ampliadas — y las dos son lecciones, no descuidos:**

1. **La forma:** ver la lista de arriba. **Tres** lecturas equivocadas antes de la buena, todas por
   intentar deducir la forma de un mapa de 18-19 px de alto: diámetro completo → brazo horizontal
   tangente → una sola biela. La buena son **dos bielas con el hueco en el centro**.
2. **El glifo NO cabe dentro del renglón: lo ATRAVIESA.** Yo lo había encajado en la banda del ascent,
   así que quedaba chico y apretado dentro de la altura de las mayúsculas. El nativo lo dibuja **más
   alto que el texto**, empezando arriba de las mayúsculas y **bajando por debajo de la línea base** —
   que es exactamente lo que el autor señaló («la biela baja por debajo del texto»). Es lo que lo hace
   leer como un objeto al lado de la palabra en vez de una letra más.

**La altura se expresa contra el `ascent`**, que es lo que la API da (la altura de mayúscula no la da
nadie): alto = **`ascent × 1,34`** y el techo del glifo = techo del label `+ ascent × 0,18`.

⚠️ **Ese factor NO es la proporción del nativo (que sería 1,12): está subido a propósito, y el motivo es
CUANTIZACIÓN — dos veces.**

1. Con **1,12** el **edge840 daba un glifo de 16 px**, más chico que la muestra nativa más chica que
   tenemos (18), y **por debajo de ~18 px la biela y los pedales se disuelven contra el aro**. El autor
   lo describió exactamente así: *«la biela superior izquierda no está, falta la línea»*.
2. Con **1,20** el 840 caía en 18 y el 830 en 20, y el autor notó que **el pedal inclinado «se ve mucho
   mejor en el 830»** — el mismo dibujo, dos píxeles de tamaño de diferencia.

**Factor actual: `ascent × 1,34`**, que lleva al 840 también a 20. **Medido con el probe headless:**

| Device | ascent del label | glifo | dy | banda del label | **asoma en la banda del valor** |
|---|---|---|---|---|---|
| edge840 | 15 | **25×20** | 2 | 21 px | **5 px** |
| edge830 | 17 | **28×22** | 3 | 23 px | **6 px** |

**Lección general: copiar una proporción no alcanza si el resultado cae por debajo del tamaño donde la
forma se puede resolver en píxeles enteros. Hay que comprobar el tamaño FINAL en cada device.**

⚠️ **El costo, y es lo que hay que vigilar:** cuanto más alto el glifo, más asoma dentro de la banda del
valor. En una celda de 62 px quedan ~3 px de aire hasta la tinta de los dígitos — no se toca, pero está
ajustado. Si alguna vez hay que recuperar espacio, la perilla es `ICON_H_NUM` en el barrel, y **el efecto
se ve en las dos apps de la familia**.

**Forma — leerla bien costó tres intentos, y los dos errores previos valen como aviso:**

- **DOS bielas sobre la misma diagonal, y el detalle que cuesta ver: LA DIAGONAL ESTÁ INTERRUMPIDA EN
  EL CENTRO DEL ARO.** Son dos trazos cortos —uno que baja desde arriba-izquierda, otro que sale hacia
  abajo-derecha— con un **hueco** entre ellos donde iría el eje. Eso explica los dos errores previos: un
  **diámetro completo** llena el aro y **lee como un signo de prohibido**, y **quitar el brazo de
  arriba** deja el glifo manco (el autor lo cazó al toque: *«la biela superior izquierda no está, falta
  la línea»*).
- **LOS DOS PEDALES ESTÁN INCLINADOS**, y paralelos entre sí: son dos plataformas en la misma
  perspectiva. Ese ángulo es la mitad de lo que los hace leer como pedales y no como guiones — y es
  el motivo de que se dibujen como **líneas gruesas** (`drawLine` + `setPenWidth`) y no como
  rectángulos.

Todo con primitivas (`drawCircle` + cuatro `drawLine`), **no con un glifo de fuente** — misma razón que
la flecha: la cobertura de un símbolo no está garantizada en los 13 devices y **un glifo ausente es
invisible**, no una caja.

**Dónde vive el layout, que es la parte interesante.** El label lo dibuja el barrel, así que hubo que
darle soporte **sin que el barrel sepa qué está dibujando** (la regla de §3.2). La solución es un
`setLabelIcon(callback, aspecto)`: el barrel **reserva una caja y llama de vuelta**; la app pone la
geometría. Así el motor sigue sin saber de cadencia, y J o L pueden tener su propio glifo mañana sin
tocarlo.

Detalles del comportamiento, todos verificados con el probe headless de §9.1:

- **La reserva se hace DURANTE la elección del label**, no después, calculada con el ascent de la fuente
  más grande candidata (cota superior: la escalera solo encoge). Eso es lo que permite que una celda
  conserve el nombre largo **y** el glifo, como hace el nativo.
- **Si el grupo `[glifo + hueco + texto]` no entra, se tira el glifo**, no el texto — misma degradación
  con gracia que la rampa de la Opción B. Tirarlo deja exactamente el comportamiento anterior.
- **Debajo de `ICON_MIN_H = 15` px no se dibuja:** a 13 px la geometría se convierte en una mancha
  (verificado renderizándola). En una celda que fuerza `FONT_XTINY` no hay glifo.
- **El tamaño sale del ascent del label**, así que difiere por familia de fuentes: **23×19 en el 830**
  (que usa `FONT_SMALL`; idéntico al nativo) y **19×16 en el 840** (que usa `FONT_GLANCE`, más chica).
  ⚠️ El 840 es el caso a mirar primero: es el más chico de los dos.
- **El glifo puede asomar 1-2 px dentro de la banda del valor**, porque es más alto que el renglón. El
  valor va centrado en su banda con holgura, y **el nativo hace lo mismo**.

## 7. Settings — la referencia configurable (2026-07-27)

**Los mismos dos settings que la Opción J** (su SPEC §9 tiene el razonamiento completo de producto y las
cuatro preguntas de diseño que se resolvieron ahí; acá solo lo que cambia). Editables **solo desde el
teléfono** — GCM / la app de la Connect IQ Store — o Garmin Express: un data field no se configura en el
Edge. Al guardar llega `onSettingsChanged` en caliente.

| Setting | Propiedad | Tipo | Default |
|---|---|---|---|
| *Comparar contra* | `referenceMode` | lista: `0` promedio de la salida · `1` objetivo fijo | `0` |
| *Cadencia objetivo* | `targetCadence` | numérico, `min=0 max=220` | `0` |

**La lógica NO cambió, otra vez.** `TrendCore.TrendArrow.classify` recibe dos enteros y no sabe qué
comparan, así que solo cambia **de dónde sale el segundo número** y el rótulo de la segunda línea
(`PROM` → `META`). Es la tercera vez que ese diseño genérico se paga solo.

**Lo que hace a la cadencia más simple que a la velocidad:** el objetivo es **un entero de rpm**, y rpm
es rpm en todo el mundo. No hay unidad del device que interpretar (J tuvo que decidir que el número se
lee en la unidad del device, sin conversión) y **no hay nada que cuantizar** (J redondea a décimas y
muestra el valor cuantizado, porque el usuario puede tipear 22,37).

⚠️ **Aun así el schema NO puede exigir un entero:** el `resources.xsd` del SDK admite en un
`settingConfig` solo `type`/`readonly`/`required`/`min`/`max`/`maxLength`/`errorMessage` — no existe
`step` ni `decimals`. Así que el título lo dice («número entero») y **`CadenceFormat.targetRpm` redondea
defensivamente** (media hacia arriba, nunca truncando: 84,6 vale 85, no 84). **NO VERIFICADO:** si el
formulario del teléfono rechaza por su cuenta un decimal cuando la propiedad es `type="number"`. No hace
falta saberlo — el comportamiento está definido en cualquier caso.

**Degradación silenciosa, igual que en J:** modo objetivo con el número **sin configurar, en 0 o
negativo** se comporta **exactamente como el modo promedio**, y el prefijo sigue diciendo `PROM`. Hacen
falta las dos cosas —modo objetivo **y** un número usable— para salirse del promedio, así que un ajuste
a medio configurar no puede dejar el campo inservible. `targetRpm` también devuelve `null` si el valor
guardado no es un número en absoluto, en vez de tirar el campo abajo.

**Un detalle de implementación que es fácil hacer mal:** `targetRpm` recibe el valor **CRUDO** de
`Application.Properties`, no uno ya pasado por un `readNumber` que lo convierta a `Number` — esa
conversión **truncaría** el decimal (84,6 → 84) y anularía el redondeo. El orden importa.

Y una consecuencia gratis del diseño: el objetivo pasa por el **mismo `trendValue`** que el resto, así
que un objetivo válido siempre es un entero positivo y la regla del `0` de no pedalear (§5.2) sigue
aplicando sin un solo caso especial nuevo.

⚠️ **Cómo se prueban estos settings, y por qué eso cambia el plan de subida.** Los settings de una app
**sideloadeada no se pueden editar desde el teléfono**: el mecanismo cuelga del vínculo con la Connect
IQ Store, que el sideload nunca establece (limitación de plataforma; el detalle está en la SPEC de J
§9.9). O sea que **probarlos de verdad exige una instalación real de la store** — y por eso K los
estrena teniendo ya un **id de beta propio**, igual que J. En el simulador sí se pueden editar (menú
`Settings` del simulador, no `File`), que alcanza para ver el cambio de `PROM` a `META` en caliente y
la degradación silenciosa.

## 8. Unit tests — 10 en total (5 propios + 5 del barrel)

Criterio del repo: **tests en verde ANTES de la validación visual**. Verificado con `monkeydo -t`
(edge840, build `--unit-test`) el 2026-07-27: **10/10 PASS**.

Los 5 del barrel **corren desde esta app**, namespaceados. No son un extra decorativo: significa que
el clasificador compartido se testea una vez por app consumidora.

| Test | Qué fija |
|---|---|
| `testCadenceDisplayString` | `84`→`"84"`, **`0`→`"0"`** (no `--`), `120`→`"120"` (dentro de `"888"`), `null`→`NO_DATA` |
| `testCadenceTrendValueCoasting` | `84`→`84`; **`0`→`null`**; `null`→`null`; `-5`→`null` (guarda defensiva) |
| `testCadenceCoastingProducesNoArrow` | Las dos piezas juntas, como las usa la View: `0` con media 80 → **NONE, no DOWN**; 90→UP; 70→DOWN; ±3 dentro de la banda. **Este es el test que protege la asimetría de §5.2.** |
| `testCadenceTargetRpm` | El objetivo de los settings (§7): entero → sí mismo; **`0`, negativo y ausente → `null`** (o sea, vuelve al promedio); `84.6`→**85** y `84.5`→85 (redondeo defensivo, no truncado); un valor que no es número → `null` sin tirar el campo |
| `testCadenceUnitParts` | `"rpm"` arriba y **vacío abajo** (una línea) |
| `TrendCore.testTrendArrowBasics` | arriba/abajo/igual → UP/DOWN/NONE con banda 0 |
| `TrendCore.testTrendArrowNegatives` | el clasificador es genérico: no asume valores positivos |
| `TrendCore.testTrendArrowNullSafety` | `null` en cualquiera → NONE, sin crash |
| `TrendCore.testTrendArrowDeadBand` | la banda es **inclusiva**; incluye el caso de 3 rpm de esta app |
| `TrendCore.testTrendArrowScaleAgnostic` | misma aritmética con décimas (J) y con rpm (K) |

Gotchas de test del repo que aplican acá (ya cometidos y documentados en B §11): las comparaciones con
`null` van con `Test.assertMessage(x == null, …)` y **nunca** con `assertEqualMessage(x, null, …)` (esa
invoca `.equals()` sobre el actual y explota); y los helpers de test deben ser funciones **planas**,
no `(:test)`, porque el runner ejecuta como caso toda función anotada.

## 9. Hooks de debug para el simulador

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

### 9.1 Medir el layout sin abrir la GUI del simulador

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

## 10. Estado y pendientes

**Al 2026-07-27:** implementada, **9/9 tests PASS**, **export de los 17 targets limpio** (único
warning: el Edge 1030 con part number `006-B2924-00`, CIQ 3.2.5, que no llega al `minApiLevel` del
proyecto y queda fuera del `.iq` — esperado, pasa en las cuatro apps). **Sin publicar**; versión
`v0.1.0` registrada en [`store/RELEASES.md`](store/RELEASES.md) para la primera subida al canal beta.

| # | Pendiente | De quién |
|---|---|---|
| 1 | ~~Íconos propios~~ — **HECHO el 2026-07-27** (§3.4): pedal cuadrado, los 13 launchers + los assets de tienda, todo generado por código. Ya no bloquea la subida. | ✅ |
| 2 | ⛔ **EL GLIFO DE LA BIELA TODAVÍA NO COINCIDE con el nativo** (§6.3). El autor lo miró en el simulador el 2026-07-27 y lo rechazó; **espera una captura ampliada suya** para medir. Constantes a mover: `ICON_H_NUM`/`ICON_DY_NUM` en el barrel (alto y cuánto baja) y las fracciones de `drawCadenceIcon` (forma). | asistente, con captura |
| 3 | ~~«En el 830 con seis campos se ven cosas raras»~~ — **DIAGNOSTICADO Y ARREGLADO el 2026-07-28**: era el glifo de ESPACIO ausente en la fuente numérica de la familia bitmap, no el glifo de la biela (§6.3 y `GARMIN_MTB_SPEC.md` §3.4.1). | ✅ |
| 4 | **Resto de la validación visual en el simulador** (F5, `TEST_MODE = true`): que la flecha siga al promedio, que los dos tramos de 0 no muestren flecha, el layout en celdas de varios tamaños, y el paseo *promedio → objetivo → promedio* cambiando el setting en caliente, que en el simulador sí se puede (§7). | autor |
| 5 | **Validación en device real** con sensor de cadencia: que nuestro promedio coincida con el nativo, y de paso cerrar §4.1 (¿incluye los ceros?). | autor |
| 6 | **Assets de la ficha** del store (capturas, hero, textos) cuando se decida subirla. | ambos |
| 7 | **Prueba a ciegas del ícono** (opcional, §3.4): el de J la pasó y cambió el diseño; el de K no. | asistente, si se pide |

**No es un pendiente de esta app:** la **Opción L** (frecuencia cardíaca) está **en pausa** esperando
una decisión de producto del autor — si la flecha va sobre **bpm** o sobre la **zona de FC**, que es lo
que él usa. Ojo con la segunda: las zonas se leen con
`UserProfile.getHeartRateZones(UserProfile.getCurrentSport())` y eso **exige declarar el permiso
`UserProfile`** en el manifest; hoy **ninguna app del repo declara permisos**, y los permisos se le
muestran al usuario al instalar.

## 11. Referencias

- [`CLAUDE.md`](../../CLAUDE.md) — convenciones del repo, sección «Barrels», flujo de release, versionado por app.
- [`GARMIN_MTB_SPEC.md`](../../GARMIN_MTB_SPEC.md) §3.4 — todo lo medido sobre fuentes y glifos de los Edge; §4 Opción J — el producto «flecha de tendencia» y los dos tiers de métrica.
- [`apps/j-trend-arrow/SPEC.md`](../j-trend-arrow/SPEC.md) — **la spec del motor de render que esta app usa**: §6 completo, §11.1 (probe headless), §11.2 (el experimento del glifo).
- [`barrels/trend-core/`](../../barrels/trend-core/) — el código compartido; sus comentarios dicen contra qué se midió cada constante.
- [`docs/code-walkthrough.html`](docs/code-walkthrough.html) — la versión narrada de este documento.
