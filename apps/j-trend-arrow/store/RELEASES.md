# j-trend-arrow — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el
`CLAUDE.md` del repo, sección «Flujo de release»). La versión **no vive en el paquete**
(`manifest.xml version="3"` es la versión del *formato*, no de la app): se tipea a mano en el
portal de Connect IQ al subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

- **Canal `beta`** → id `140986d8c6bc4026880e117255a6ce67` (en `main`). No se taguea.
- **Canal `prod`** → todavía NO existe: cuando esta app vaya a producción hay que generar su
  propio id (`uuidgen`), aplicarlo a mano en el `manifest.xml` del lado de la rama `release` y
  taguear `j-trend-arrow/vX.Y.Z` sobre ese commit.

Entradas, más nueva primero.

## v0.0.1 — 2026-07-25 — beta

Primera subida. Campo de datos que muestra la **velocidad actual** en grande con una **flecha ↑/↓
al lado**, comparándola contra la **velocidad promedio de la actividad** (estilo Cateye), y el
promedio en una línea secundaria cuando la celda es alta.

- **Lógica** en dos módulos puros con tests (11/11): `TrendArrow` (clasificador genérico sin estado:
  dos enteros ya redondeados → `UP`/`NONE`/`DOWN`) y `SpeedFormat` (m/s → km/h o mph según
  `paceUnits` del device, redondeo único en décimas, string `"24.3"` por aritmética entera).
- **Banda muerta semántica de ±0,1 km/h**: si la diferencia contra tu media es ≤ 0,1 no hay flecha
  («vas a la media»). No es anti-parpadeo, es una decisión de significado.
- **Render estilo nativo**: número grande, unidad `km`/`h` apilada a su derecha alineada a la base
  de los dígitos, label con el nombre de la métrica (`VELOCIDAD`, corto `VEL` si la celda es
  angosta). Layout adaptativo con caché por celda; modo inline `actual / promedio` en celdas
  anchas y cortas. Sin decimal a partir de 100 km/h para no achicar la fuente.
- **13 devices** (`edge530/540/830/840/550/850/1030 ×3/1040/1050/explore2/mtb`), `eng` + `spa`,
  CIQ 3.3.0, sin settings.
- **Íconos** propios (ya no el placeholder de la A): aro cobalto con la raya ámbar del promedio y
  la flecha blanca cruzándola. Master 1024 con alpha real, ícono de tienda 500×500 y los 13
  launchers dibujados a su tamaño. Ver `SPEC.md` §3.3.

Pendiente antes de subir: capturas del simulador (482×232), textos de la ficha y hero 1440×720.
