# a-activity-timer — releases

Registro de versiones de ESTA app (fuente de verdad del versionado; ver la regla en el
`CLAUDE.md` del repo, sección «Flujo de release»). La versión **no vive en el paquete**
(`manifest.xml version="3"` es la versión del *formato*, no de la app): se tipea a mano en el
portal de Connect IQ al subir el `.iq`. Este archivo dice qué número tipear y qué cambió.

- **Canal `beta`** → id `953a28119edc4511b09dca2366738f5e` (en `main`). No se taguea.
- **Canal `prod`** → id `90f54fc135bd444f966d9b0c69849851` (rama `release`). Tag `a-activity-timer/vX.Y.Z`.
- Los tags planos `v0.1.0`–`v0.1.7` del repo son **legacy** (anteriores al esquema namespaced) y
  corresponden todos a esta app.

Entradas, más nueva primero.

## PENDIENTE — release nuevo solo para mejorar la ficha (anotado 2026-07-26)

Las capturas y el hero de `store/` se **reemplazaron por versiones nuevas, mucho más grandes y
legibles** que las que se subieron con la v0.1.7 (las viejas eran de 482×232; las nuevas van de
1699×926 a 1808×870). El código no cambió: es un release **solo de ficha**, para que la página del
store se vea como se ve ahora la de la Opción J.

Falta: **decidir el número** (el autor lo elige, no se adivina el salto), y entonces el flujo de
prod de siempre — entrada acá, merge `main→release`, "Export Project" y tag `a-activity-timer/vX.Y.Z`.

⚠️ **El nombre `hero-image-1440x720.png` ya miente:** el archivo mide **1774×887**. Mantiene la
proporción 2:1, así que sirve igual, pero conviene renombrarlo o volver a exportarlo a 1440×720 para
que el nombre no engañe al próximo que lo mire.

## v0.1.7 — 2026-07-19 — prod
Primera subida a **producción** (id de prod nuevo). Ficha completa en el portal: título
«Adaptive Activity Timer» / «Tiempo de Actividad Adaptable», descripción EN+ES, categoría Cycling,
hero image 1440×720, contacto `el.soldador.garmin@gmail.com`. Íconos launcher per-device nítidos en
los 13 dispositivos. Tag legacy: `v0.1.7`.

## v0.1.6 — 2026-07-19 — beta
Iconito de cronómetro inline junto al label (primitivas `dc`, theme-aware, geometría cacheada).
Launcher icons rehechos (cronómetro plano legible a 35px). Assets del store: `store-icon-500.png`
desde master analógico + 6 capturas día/noche. Tag legacy: `v0.1.6`.

## v0.1.0 – v0.1.5 — 2026-07-19 — beta
Afinado pixel-perfect contra el campo nativo en el Edge 840 real: fuentes del sistema
(`FONT_SYSTEM_NUMBER_*` + `FONT_GLANCE`), centrado por ascent/descent, ícono real de cronómetro (5
tamaños), 13 devices en el manifest, exclusión de hooks de debug del build de release. Subida a la
IQ Store solo como beta. Tags legacy: `v0.1.0`–`v0.1.5`.
