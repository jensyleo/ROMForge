# ROMForge — Estados de identificación (ROM/CHD/Juego)

Documento de referencia único para toda la lógica de "¿qué estado tiene esto y qué mensaje se muestra?". Es la base para la futura fase de manipulación de archivos (rebuild/fix) — cualquier decisión sobre qué hacer con un archivo depende de identificar primero, sin ambigüedad, en qué estado está.

No documenta el código en sí (eso vive en los doc-comments de cada archivo); documenta el **modelo de decisión**: qué hechos determinan cada estado, y qué le mostramos al usuario en cada caso.

---

## 1. Los tres niveles de estado

Hay tres niveles distintos, cada uno con su propio vocabulario. No mezclarlos:

| Nivel | Tipo Swift | Dónde vive | Para qué |
|---|---|---|---|
| **Resultado crudo del matcher** | `RomMatchStatus` | `ROMForgeCore/Matcher/MatchReport.swift` | Salida de `ROMMatcher.match()` — nunca se persiste, nunca lo ve la UI directamente |
| **Estado de auditoría (persistido)** | `AuditStatus` | `ROMForgeCore/Reports/AuditReport.swift` | Lo que se guarda en SQLite y ve la UI para CADA fila individual de rom o disco |
| **Estado agregado de juego** | `AuditStatus` (mismo enum, reusado) | `App/LibraryDetailView.swift` (`gameCategory`) | El ícono/color de la fila de UN juego en la lista, resumen de todas sus roms (o discos) |

---

## 2. Nivel 1 — Resultado crudo por rom (`RomMatchStatus`)

Esto es lo que decide `ROMMatcher.swift` para **cada rom individual** de un juego, comparando contra los archivos escaneados. Nunca llega tal cual a la UI — siempre se traduce a `AuditStatus` (tabla §3).

| Caso | Significa | Se dispara cuando |
|---|---|---|
| `.correct(file, viaHeaderStrip)` | Nombre y contenido coinciden exactamente | Un archivo en el lugar esperado (su propio archivo/zip) tiene el hash Y el nombre correctos |
| `.misnamed(file, viaHeaderStrip)` | Contenido correcto, nombre incorrecto | El hash coincide, pero el nombre del archivo dentro del zip es distinto al esperado |
| `.foundElsewhere(file)` | El juego **existe de verdad**, pero este rom específico está en el lugar equivocado | El rom no está en el archivo propio del juego, PERO (a) el juego sí tiene al menos un rom propio reclamado en su propio archivo, O (b) el contenido está en un archivo que no pertenece a NINGÚN juego del DAT (archivo renombrado por el usuario) |
| `.hashMismatch(file)` | Hay un archivo exactamente en el lugar esperado (mismo nombre, mismo archivo/zip), pero su contenido está mal | El nombre coincide dentro del zip propio, pero el hash no |
| `.missing` | Ausencia real, en ningún lado del escaneo | Ninguna de las anteriores aplica — incluye el caso "el juego no existe en absoluto" (ver Nota A) |

**Nota A — la regla que costó tres intentos (04-ago-2026):** `.foundElsewhere` NUNCA debe disparar solo porque el contenido coincide por tamaño con algo de OTRO juego real que sí tienes. Debe significar *"tienes este juego, pero un rom suyo está mal ubicado"* — nunca *"no tienes este juego, pero otro juego contiene roms que este también necesitaría"*. Ver `ROMMatcher.swift`'s `gameOwnsRealFiles` para la implementación exacta.

**`nodump`** (declarado así por el DAT, no es un `RomMatchStatus` — es `RomDumpStatus`): se omite del reporte por completo, ni correct ni missing. MAME/ClrMamePro/RomCenter tampoco lo cuentan contra la completitud del set.

---

## 3. Nivel 2 — Estado de auditoría por fila (`AuditStatus`)

5 valores, usados tanto para roms como para discos (CHD). Es lo que se persiste en SQLite y lo que colorea cada fila individual en el panel derecho (detalle del juego seleccionado).

| `AuditStatus` | Color | Ícono | Prioridad (peor→mejor) |
|---|---|---|---|
| `.missing` | 🔴 Rojo | `xmark.circle.fill` | 1 (peor) |
| `.badDump` | 🟠 Naranja | `exclamationmark.octagon.fill` | 2 |
| `.incorrect` | 🟡 Amarillo | `exclamationmark.triangle.fill` | 3 |
| `.correct` | 🟢 Verde | `checkmark.circle.fill` | 4 (mejor) |
| `.surplus` | ⚪️ Gris | `questionmark.circle.fill` | — (no es severidad, es "no reconocido") |

### 3a. Mapeo `RomMatchStatus` → `AuditStatus` (roms)

| `RomMatchStatus` | `AuditStatus` | Texto en la fila (panel derecho) |
|---|---|---|
| `.correct` | `.correct` | "Ok" (o "Ok (header removed to match)" si aplicó strip de header) |
| `.misnamed` | `.incorrect` | "Bad name" |
| `.foundElsewhere` | `.incorrect` | "Available in another game (`<archivo>`)" |
| `.hashMismatch` | `.badDump` | "Bad (hash mismatch)" |
| `.missing` | `.missing` | "Missing" |
| (surplus file, sin rom que lo reclame) | `.surplus` | "Unrecognized" |

Modificador adicional, independiente del estado anterior: si el DAT mismo declara el rom como `baddump`/`nodump` (`RomDumpStatus`, un hecho sobre el dump de *referencia*, no sobre tu archivo local):
- Cualquier estado excepto Missing: se le agrega `"(bad dump in DAT)"` al texto.
- Missing: en vez de eso, `"Missing (also a known bad dump in DAT)"` — nunca implica que se encontró algo.

### 3b. Estado de disco/CHD (`DiskAuditor` + `CHDMatcher`)

Un CHD solo tiene 3 estados posibles (nunca `.badDump`, nunca `.foundElsewhere` — se verifica por el SHA1 del header, no hay "está en otro lado"):

| `CHDDiskStatus` | `AuditStatus` | Texto en fila de disco (izquierda) |
|---|---|---|
| `.correct(url)` | `.correct` | "Correct" |
| `.incorrect(url)` | `.incorrect` | "Incorrect" |
| `.missing` | `.missing` | "Missing" |

Un `.chd` en disco que no corresponde a NINGÚN disco declarado por el DAT actualmente no aparece en ningún lado (ni como disco, ni como surplus) — gap conocido, no corregido todavía.

---

## 4. Nivel 3 — Estado agregado del juego (fila de la lista izquierda)

Cada juego puede generar **hasta 2 filas independientes** en la lista de juegos: una para sus roms, otra para su CHD (`GameNode.isDiskRow`). Nunca se mezclan en el cálculo del estado — jensyleo (30-jul-2026): "si el .zip está OK mostrarlo como Correct, pero separado del .chd".

### 4a. Regla de agregación (worst-of), igual para roms y para disco

```
gameCategory(entries) =
    si algún entry == .missing   → .missing   (rojo)
    sino si algún entry == .badDump → .badDump (naranja)
    sino si algún entry == .incorrect → .incorrect (amarillo)
    sino → .correct (verde)
```

Un solo rom missing pinta TODO el juego rojo (para esa fila — rom o disco, según cuál tenga el problema).

### 4b. Vista Database vs vista de carpeta "Rom files" (04-ago-2026, corregido)

**Regla actual (única, sin excepciones por vista):** "Missing" se calcula y se muestra igual en ambas vistas. La diferencia entre vistas NO es "ocultar missing en carpeta" — es **de dónde vienen las entradas que se agregan**:

- **Database**: usa la verdad completa del DAT (`gameAggregateStatusByName`) — un rom ausente en TODO el sistema pinta el juego rojo.
- **Carpeta "Rom files"**: usa solo las entradas que sobrevivieron el filtro de "¿este juego tiene algo realmente suyo en esta carpeta?" (`scoped(_:)`). Esto importa cuando un sistema tiene VARIAS carpetas de roms: si el rom de un juego vive en la carpeta B, no debe pintarse rojo al ver la carpeta A solo porque no está ahí — esto no es "ocultar Missing", es que ese rom simplemente no es `.missing` desde el punto de vista de esta carpeta si genuinamente existe en la carpeta B (ver `merge()` en `LibraryViewModel.swift`, que reconcilia resultados entre escaneos de distintas carpetas).
- Un juego que NO tiene ningún archivo propio en la carpeta actual (fantasma/no poseído) **no aparece en absoluto** en esa carpeta — filtrado antes de llegar a la agregación (`recomputeGamesInFolder`/`scoped(_:)`, excluye específicamente contenido `.foundElsewhere`).

### 4c. Caso especial: juego con ROM + CHD, la ROM propia falta pero el CHD está bien

**Regla explícita (confirmada 04-ago-2026, después de probar la alternativa en vivo):** si el CHD de un juego es `.correct` (o `.incorrect`, cualquier cosa distinta de `.missing`) y TODAS las entradas de rom de ese mismo juego son `.missing`, **la fila de la ROM no se muestra en absoluto**. Solo se ve la fila del disco (verde/correcto). El juego aparece 100% "Ok" en la lista de juegos.

- Se probó lo opuesto (mostrar la fila de la ROM en rojo, separada) el mismo día — se descartó: una fila roja junto a una fila verde del mismo juego generó más confusión que claridad.
- **Excepción dentro de la excepción:** si la ROM está `.incorrect` (mal nombrada) o `.badDump` — es decir, hay algo ahí, solo que está mal — la fila SÍ se muestra, siempre. Solo una ROM *totalmente ausente* se oculta cuando el CHD compensa.
- El **conteo del encabezado** ("Missing: N") sigue contando este juego como missing aunque su fila no se vea — inconsistencia conocida y preexistente (no introducida hoy), no corregida por decisión explícita del usuario de no tocar más de lo pedido.

### 4d. Mensajes de la fila de juego (`GameNode.infoText`)

**Fila de disco** (`isDiskRow == true`):

| Estado agregado | Texto |
|---|---|
| `.missing` | "Missing" |
| `.incorrect` | "Incorrect" |
| `.badDump` | "Bad" |
| `.correct` / `.surplus` | "Correct" |

**Fila de rom** (juego normal):

| Estado agregado | Texto | Distinción |
|---|---|---|
| `.missing` | "Incomplete (rom missing)" | — |
| `.badDump` | "Bad (hash mismatch)" | — |
| `.incorrect` | "Bad file name" | El nombre del ARCHIVO completo no coincide con `<juego>.zip` esperado |
| `.incorrect` | "Rom need fix" | El archivo tiene el nombre correcto, pero algún rom DENTRO está mal nombrado |
| `.correct` (con algún `.surplus` adentro) | "Extra file in archive" | El zip tiene un archivo de más que el DAT no espera |
| `.correct` | "Ok" | Todo coincide |

**Bucket "Unknown game"** (`isSurplusBucket == true`): siempre "Unknown game", sin importar nada más — no hay juego real del DAT detrás.

**Antes de escanear** (`aggregateStatus == nil`): "Not scanned yet".

---

## 5. Conteos del encabezado (botones de filtro)

`computeScopedStatusCounts` — cuenta **juegos/archivos**, no roms individuales, y es **rom-only**: el estado del CHD nunca afecta estos 4 números (por eso un CHD roto no cambia el conteo de "Incorrect" si las roms del mismo juego están bien).

| Botón | Cuenta juegos cuya agregación de ROMS (no disco) es... |
|---|---|
| Correct: N | `.correct` |
| Incorrect: N | `.incorrect` |
| Bad: N | `.badDump` |
| Missing: N | `.missing` |
| Unknown: N | (aparte — cuenta buckets "Unknown game", no es un `AuditStatus`) |

---

## 6. Resumen visual rápido (para no perderse)

```
                    ROM                              CHD
  .missing    →  🔴 Missing                    →  🔴 Missing
  .badDump    →  🟠 Bad (hash mismatch)         →  🟠 Bad
  .incorrect  →  🟡 Bad name / Rom need fix     →  🟡 Incorrect
  .correct    →  🟢 Ok / Extra file in archive  →  🟢 Correct
  .surplus    →  ⚪️ Unrecognized (no es un juego real)

  EXCEPCIÓN: rom 100% missing + CHD del mismo juego != missing
             → la fila de ROM no se muestra. Solo se ve el CHD (🟢).
```

---

## 7. Qué falta documentar (pendiente, no bloqueante)

- El bug de visualización en CPS3 mencionado el 04-ago-2026 (pendiente de investigar).
- Comportamiento de un `.chd` en disco que no corresponde a ningún disco del DAT (actualmente invisible, ni disco ni surplus).
- Esta tabla es la base para la fase de manipulación de archivos (rebuild/fix) — cuando esa fase empiece, cada acción posible (renombrar, mover, reconstruir zip, etc.) debe mapearse explícitamente a uno de los estados de arriba, no inventarse ad-hoc.
