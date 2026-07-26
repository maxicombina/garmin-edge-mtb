# b-grade-vam — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el
`CLAUDE.md` del repo, sección «Flujo de release»). La versión **no vive en el paquete**
(`manifest.xml version="3"` es la versión del *formato*, no de la app): se tipea a mano en el
portal de Connect IQ al subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

- **Canal `beta`** → id `e1b243f4b9da42ea9384718d77451f19` (en `main`). No se taguea.
- **Canal `prod`** → id **pendiente de generar** (rama `release`, mismo flujo que la App A).
  Tag `b-grade-vam/vX.Y.Z` al primer release de producción.

Entradas, más nueva primero.

## (sin releases todavía)
App **en desarrollo**: implementada, compilando y con unit tests en verde (43/43), validándose en
el simulador. Aún **no subida a la store** en ningún canal. La primera entrada se registra acá
cuando se haga el primer submit (beta o prod).
