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
    ├── gen_icon.py             # dibuja TODO el ícono: master + ficha + los 13 launchers (§3.4.3)
    ├── gen_hero.py             # compone el hero 1440×720 (§3.4.4)
    ├── opt_screenshots.py      # deja las capturas bajo los 150 KB del portal (§3.4.5)
    ├── icon-master-1024.png    # master RGBA con alpha real, para regenerar
    ├── store-icon-500.png      # 500×500 opaco sobre gris #E6E6E6, para la ficha del portal
    ├── hero-image-1440x720.png # hero de la ficha
    └── cadence-trend-arrow-*.png  # capturas de la ficha (y las tarjetas del hero)
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

### 3.4 Ícono y assets de la ficha — CERRADOS (2026-07-28). Una BIELA, y el sistema de la familia

**Motivo final: una BIELA vista de frente** — aro cobalto `#0070F0` con dos brazos en diagonal y un
**pedal en cada punta**, y dentro, sobre cara azul muy oscuro `#0E1A38`, **la misma raya ámbar y la
misma flecha blanca que J**. Sin texto, sin números, sin dientes.

⚠️ **Hubo un ícono anterior, un cuerpo de pedal CUADRADO, y se descartó** (2026-07-28, el autor: *«el
logo no me gusta»*). Su razonamiento no era malo —la silueta cuadrada distinguía de J y no podía leerse
como engranaje— pero **no decía cadencia**: su único trabajo era «no soy la J». Cuando el autor confirmó
que la flecha de tendencia se va a repetir en más métricas, o sea que **esto es una FAMILIA**, el criterio
cambió: la silueta tiene que ganarse su lugar diciendo cuál es la métrica.

### 3.4.1 EL SISTEMA DE LA FAMILIA (lo importante de esta sección)

Vale más que este ícono, porque manda sobre los que vengan (la Opción L y las que sigan):

| | |
|---|---|
| **CONSTANTE** — dice «esto es tendencia contra tu promedio» | cara oscura + **raya ámbar** (= tu promedio) + **flecha blanca** cruzándola |
| **VARIABLE** — dice **qué métrica es** | la **SILUETA EXTERIOR**, en cobalto: aro de rueda = velocidad, **biela = cadencia**, corazón = frecuencia cardíaca |

**Por qué la métrica va en la silueta y NUNCA en un detalle interior:** a 35 px el detalle no existe,
la silueta sí. Está verificado mirando los launchers de 35 px de J y K lado a lado.

**Y por qué el interior se conserva idéntico entre hermanas:** la prueba a ciegas del ícono de J (7
observadores sin contexto) dio que **el objeto no se lee nunca** —0 de 7 vieron un neumático— pero que
**la raya cruzada por la flecha sí**: 7 de 7 llegaron a «línea de referencia que la flecha cruza». O sea
que el interior es lo único que comunica algo, así que no se toca.

⚠️ **NO usar un plato para cadencia**, que es el motivo obvio: en esa misma prueba, **7 de 7 leyeron los
tacos del neumático de J como «engranaje / tuerca / ajustes»** — el peor falso amigo en una lista de
campos de datos, y lo que le costó los tacos a J. **Un plato es literalmente un engranaje.** La biela no
tiene dientes, así que esquiva el problema y además sí dice cadencia.

⚠️ **Consecuencia para la Opción J, anotada y NO ejecutada:** con este sistema, J queda como la hermana
sin metáfora — su aro liso dejó de leerse como rueda cuando le sacamos los tacos. Si la familia crece,
tendría sentido devolverle una silueta de rueda propia. **Es un cambio de ícono en una app publicada**,
así que se decide con tiempo, no dentro de un release (el autor, 2026-07-28: «deja ya con la J, así está
bien»).

### 3.4.2 Geometría, y por qué los pedales van inclinados 18°

**Los dos pedales están inclinados 18°, bajando hacia la izquierda y paralelos entre sí.** No es
capricho: es la inclinación **medida en el glifo de la biela que el campo NATIVO dibuja** junto al rótulo
`CADENCIA` (12-18°, §6.3). Con eso el ícono y el glifo de la pantalla pasan a ser **el mismo objeto**.
Sin inclinar, los pedales leen como pestañas — se probaron las dos y el autor eligió mirando.

Variante elegida sobre tres mockups: **brazo largo** (`A2`), que es la que da la silueta más distintiva.
Costo aceptado y medido: con los brazos largos el aro es más chico que el de J, así que **a 35 px el
interior de K tiene menos cuerpo que el de su hermana**.

### 3.4.3 Los tres generadores de `store/` (solo numpy, ni Pillow)

| Script | Qué produce |
|---|---|
| [`gen_icon.py`](store/gen_icon.py) | `icon-master-1024.png` (RGBA, con brillo), `store-icon-500.png` (opaco sobre gris) y los **13 launchers**, cada uno **dibujado a su tamaño** (35/36/40/56/68), **planos** y sin filete interior abajo de 56 px |
| [`gen_hero.py`](store/gen_hero.py) | `hero-image-1440x720.png`: ícono a la izquierda sobre degradado navy, capturas a la derecha como tarjetas |
| [`opt_screenshots.py`](store/opt_screenshots.py) | deja las capturas de la ficha bajo el **límite de 150 KB** del portal |

**No editar los PNG a mano: editar el script y re-correrlo.** Reducir el master a 35 px deja una mancha
borrosa — lección de la Opción A, y el motivo de dibujar cada tamaño por separado.

### 3.4.4 El hero: cuatro cosas que salieron mal y sus reglas

Las funciones de composición son **las del hero de J, copiadas**. La primera versión las escribió
«parecidas» y el resultado se veía mal justo donde el autor lo notó: **el borde entre la tarjeta blanca y
el fondo azul**. Cada error dejó una regla:

1. **La máscara redondeada era BINARIA** (alpha 0 o 1). En un arco eso deja **escalera**, con el salto
   entero de blanco a navy —unos 240 niveles— metido en un píxel. La de J tiene **antialias por
   supersampling ×4**. *Era la causa principal.* Medido después del arreglo: **64 píxeles intermedios en
   la esquina contra 87 de J**; antes, prácticamente cero.
2. **Ampliar las capturas las vuelve blandas.** La primera versión estiraba una captura de 486 px a 600.
   A factor fraccionario unos píxeles se duplican y otros no, los trazos quedan desparejos y eso se lee
   como borroso: **medido, los grises por píxel de borde pasaban de 0,53 (J) a 0,99**. **Regla: ampliar
   nunca, reducir sí** — reducir desde una imagen grande es antialias limpio, y es *por eso* que el hero
   de J se ve nítido (sus capturas son de 1000 px y las **baja**). Con las capturas grandes del autor el
   hero quedó en **0,52 contra 0,53 de J**.
3. **La sombra era demasiado cerrada** (muchas pasadas de caja de radio 1 pegadas al borde) y leía como
   un **contorno oscuro**. La de J es **una** caja de semiancho 18, desplazada hacia abajo y aplicada al
   lienzo **antes** de pegar la tarjeta.
4. **El degradado era más oscuro y plano** que el de J, lo que endurecía el contraste contra el blanco.
   Ahora son los colores y la caída elíptica de J.

**Y una quinta, que MEJORA al hero de J en vez de copiarlo** (la destapó una auditoría del script de J):
J mezcla directamente los valores de 8 bits, que están **codificados en gamma sRGB**. Mezclar en gamma un
blanco de 255 contra un navy de ~30 da un resultado **más oscuro que el físicamente correcto** — al 50 %
sale **142** cuando debería salir **189** — y eso ensucia exactamente el filo donde la tarjeta se
encuentra con el fondo. El hero de K **mezcla en LUZ LINEAL** (sRGB → lineal → mezcla → sRGB), y solo lo
paga en los píxeles de alpha fraccionario, o sea los arcos: el interior sale idéntico. Es la única parte
donde este script se aparta del de J a propósito.

**Y dos detalles de estas capturas en particular**, que no son del simulador sino renders de ficha: traen
su **propio marco redondeado y margen blanco**, así que el hero **recorta al contenido** (el margen sobre
el navy se vería como un recuadro blanco); y ese marco propio es **casi invisible** (medido: 248 contra
251 del interior) con un radio que **varía muchísimo entre imágenes** (15 px en una, 59 en otra), razón
por la cual **no se intenta hacerlo coincidir** con la máscara y se usa un radio propio y consistente.

**Cuántas tarjetas:** el script prueba de más a menos y toma la mayor cantidad que deje tarjetas con
cuerpo (≥ 420 px). Con estas proporciones da **dos** — el mismo número al que llegó J.

### 3.4.5 El límite de 150 KB del portal

**El portal de Connect IQ acepta como máximo 150 KB por captura.** Las de la ficha llegaron en RGB de
1535 px pesando ~780 KB, cinco veces el límite. `opt_screenshots.py` las deja en 118-139 KB con la receta
de J:

1. **Reducir a 1000 px** de ancho promediando bloques.
2. **Pasar a escala de grises**, o sea **PNG de tipo de color 0: un byte por píxel en vez de tres**. Ahí
   está el grueso del ahorro, y es **sin pérdida** porque el campo es negro sobre blanco. *Esa es la
   diferencia que el autor notó entre las capturas de J y las de K: tipo 0 contra tipo 2.*
3. **Si aun así no entra, bajar el ancho por pasos.**

⚠️ **La guarda de «¿hay color?» mira una PROPORCIÓN, no el máximo.** El primer intento decía «si algún
píxel separa más de 12 niveles entre R, G y B, hay color», y con eso una captura quedó marcada como color
y en **324 KB** — cuando su separación máxima era 13, la **media 0,29** y solo el **0,003 %** de los
píxeles pasaba de 8: ruido del generador, no color. **Un máximo lo decide un puñado de píxeles; una
proporción describe la imagen.**

**Pendiente relacionado:** este ícono **no pasó por la prueba a ciegas** que sí hizo el de J. Vale hacerla
antes de subir la app si se quiere el mismo nivel de evidencia — la técnica está en J §3.3.

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

> ✅ **ESTADO: CERRADO (2026-07-28), en cuatro vueltas y todas corregidas por el autor mirando.** Cada
> intento fallido dejó una lección, así que valen más que el resultado:
>
> 1. **Un diámetro completo** cruzando el aro → **leía como un signo de prohibido**: un diámetro llena
>    el aro.
> 2. **Un brazo largo casi horizontal** tangente al techo → no existe en el nativo.
> 3. **Una sola biela**, del centro hacia abajo-derecha → el autor: *«la biela superior izquierda no
>    está, falta la línea»*. El glifo quedaba manco.
> 4. **La buena: DOS bielas sobre la misma diagonal, con la diagonal INTERRUMPIDA en el centro del
>    aro** — dos trazos cortos con un hueco donde iría el eje. Eso explica de una vez por qué el
>    diámetro entero y la biela sola se veían mal. Más los **dos pedales inclinados y paralelos**.
>
> Ajustado contra **dos capturas ampliadas del 840 real** a la vez: coincide en el **87 %** de los
> píxeles del mapa chico y el **96 %** del grande. Validado a ojo por el autor en el simulador.
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
| 1 | ~~Íconos propios~~ — **CERRADO el 2026-07-28** (§3.4): **biela** con los pedales a 18°, los 13 launchers + master + ícono de ficha, todo generado por código. El primer diseño (pedal cuadrado) se descartó por no decir cadencia. | ✅ |
| 1b | ~~Assets de la ficha~~ — **hero** a la par del de J (nitidez medida) y **tres capturas bajo los 150 KB** del portal (§3.4.4, §3.4.5). | ✅ |
| 2 | ~~El glifo de la biela no coincidía con el nativo~~ — **CERRADO el 2026-07-28** (§6.3), en cuatro vueltas y con capturas ampliadas del 840 real: coincide en el **87 %** de los píxeles del tamaño chico y el **96 %** del grande, y el autor lo validó a ojo en el simulador. Las perillas quedan documentadas por si hace falta: `ICON_H_NUM`/`ICON_DY_NUM` en el barrel y las fracciones de `drawCadenceIcon`. | ✅ |
| 3 | ~~«En el 830 con seis campos se ven cosas raras»~~ — **DIAGNOSTICADO Y ARREGLADO el 2026-07-28**: era el glifo de ESPACIO ausente en la fuente numérica de la familia bitmap, no el glifo de la biela (§6.3 y `GARMIN_MTB_SPEC.md` §3.4.1). | ✅ |
| 4 | **Resto de la validación visual en el simulador** (F5, `TEST_MODE = true`): que la flecha siga al promedio, que los dos tramos de 0 no muestren flecha, el layout en celdas de varios tamaños, y el paseo *promedio → objetivo → promedio* cambiando el setting en caliente, que en el simulador sí se puede (§7). | autor |
| 5 | **Validación en device real** con sensor de cadencia: que nuestro promedio coincida con el nativo, y de paso cerrar §4.1 (¿incluye los ceros?). | autor |
| 6 | **Los TEXTOS de la ficha** (título y descripción EN+ES). Van directo al portal: por decisión del 2026-07-27 los textos de ficha **no se versionan en el repo** (ver `CLAUDE.md` §«Flujo de release»). El formulario **no acepta markdown**. | autor |
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
