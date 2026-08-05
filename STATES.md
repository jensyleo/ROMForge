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

**Caso confirmado explícitamente (04-ago-2026): `.correct` + `isBadDump` → sigue siendo VERDE, texto "Ok (bad dump in DAT)".** No es una contradicción ni un bug — son dos hechos independientes que coexisten:
- `entry.status == .correct` responde: *"¿tu archivo local coincide exactamente con lo que el DAT declara?"* → Sí.
- `entry.isBadDump` responde: *"¿el propio DAT admite que su dump de referencia es defectuoso/incompleto?"* → Sí, pero eso es un hecho sobre la REFERENCIA, no sobre tu archivo.

El color siempre refleja la primera pregunta (`tint(for: entry.status)`, nunca `isBadDump`) porque es la única que importa para decidir si hay algo que tú puedas o debas arreglar: si tu archivo ya coincide byte a byte con el dump de referencia — sea ese dump bueno o malo — no existe ninguna acción posible de tu parte. Un archivo "mejor" no puede existir porque, por definición, el DAT no conoce ninguno mejor. El texto entre paréntesis es solo informativo (para que sepas que ese dump en particular es conocido por ser problemático en el hobby MAME en general), nunca una instrucción de "arregla esto".

### 3b. Estado de disco/CHD (`DiskAuditor` + `CHDMatcher`)

Un CHD solo tiene 3 estados posibles (nunca `.badDump`, nunca `.foundElsewhere` — se verifica por el SHA1 del header, no hay "está en otro lado"):

| `CHDDiskStatus` | `AuditStatus` | Texto en fila de disco (izquierda) |
|---|---|---|
| `.correct(url)` | `.correct` | "Correct" |
| `.incorrect(url)` | `.incorrect` | "Incorrect" |
| `.missing` | `.missing` | "Missing" |

Un `.chd` en disco que no corresponde a NINGÚN disco declarado por el DAT actualmente no aparece en ningún lado (ni como disco, ni como surplus) — gap conocido, no corregido todavía.

### 3c. Surplus reconocido vs. surplus genuino (`requiredByGameDescription`)

**Caso real (04-ago-2026):** bajo Split, un clon (ej. `sf2acc`) declara SOLO sus roms únicas — las que comparte con su padre (`merge=` en el DAT) quedan excluidas de su lista propia, porque Split espera que vivan únicamente en el archivo del padre. Pero el `.zip` real del usuario a menudo SÍ contiene ese contenido compartido también (un dump válido y correcto) — y como el escaneo por archivo nunca busca dentro de `sf2acc.zip` las roms de `sf2ce` (el padre), ese archivo queda sin reclamar por nadie y se reportaba como "Unrecognized" genérico, indistinguible de basura real.

**Fix (corregido dos veces el mismo día — versión final):** antes de declarar un archivo sobrante como surplus, se compara su hash contra TODAS las roms del DAT (de cualquier juego, sin filtrar por modo de merge). Si coincide con algo real, **se reclasifica de verdad como `.incorrect`**, no se queda en `.surplus` con un simple cambio de color — corrección del propio usuario (04-ago-2026): "surplus" debe significar *desconocido*, y este caso deja de serlo en cuanto se identifica.

| Situación | `AuditStatus` | Color | Texto (fila individual) |
|---|---|---|---|
| Hash no coincide con NADA del DAT | `.surplus` | ⚪️ Gris | "Unrecognized" |
| Hash coincide con una rom de OTRO juego real | `.incorrect` | 🟡 Amarillo (nativo, sin parche) | "Not needed here (required by `<juego>`)" |
| Sin hash (rom no lo tiene), pero el NOMBRE coincide con un rom `nodump` del DAT | `.unverifiable` | ⚪️ Gris (ícono distinto) | "Nodump (unverifiable)" — ver §4e2 |

El mensaje a nivel del JUEGO (columna izquierda) también distingue este caso — dentro de `.incorrect`, en orden de prioridad:
1. El archivo completo está mal nombrado → "Bad file name"
2. Alguna ROM propia del juego está mal nombrada o encontrada en otro lado → "Rom need fix"
3. Todo lo propio del juego está bien; el único problema es un archivo sobrante ya identificado → **"Extra file, not needed here"**

**Consistencia entre vistas:** este archivo llega "plegado" a la fila de su juego por coincidencia de nombre de archivo (no por el campo `game`, que sigue siendo `nil` para estas entradas) — tanto en la vista "Database" (`computeGameAggregateStatusByName`) como en vista de carpeta (`gameNodes`) como en los conteos del encabezado (`computeScopedStatusCounts`). Los tres pliegan la misma manera exacta, para que nunca puedan discrepar entre sí sobre el estado de un juego.

Implementado en `ROMMatcher.match`'s `romsByHash`/`requiredByGameDescription` (identificación) + `AuditReporter.generate` (reclasificación a `.incorrect`) + los tres puntos de plegado en `LibraryDetailView`. Nunca usado para *reclamar* un archivo (no reabre el problema de "robo entre juegos" — sigue siendo puramente informativo).

**Nunca "required by" el propio juego (04-ago-2026):** si un archivo aparece DUPLICADO dentro del archivo de su propio juego (dos copias físicas del mismo rom, una reclamada y otra sobrante), `requiredByGameDescription` nunca debe decir que ese archivo es necesario "por" su propio juego — no tiene sentido ("necesitado aquí" cuando literalmente está aquí). Se verifica contra las roms propias del juego contenedor (por nombre de archivo) antes de consultar el índice global; solo se reporta cuando el dueño real es OTRO juego distinto.

**Bug de caché entre escaneos con este mismo campo (04-ago-2026):** un juego cuya huella completa en el escaneo fresco es puramente `surplus` (`game: nil` — ej. `qsound_hle` bajo Split, donde su única rom está `merge=`-etiquetada y se excluye por completo de su propia lista esperada) nunca se reconocía como "tocado" por `Self.merge()` en `LibraryViewModel.swift`, porque esa detección solo miraba entradas con `game != nil`. Resultado: una fila vieja y ya incorrecta (`.correct`, de un escaneo anterior bajo OTRO modo donde esa rom sí se reclamaba) se conservaba sin reconciliar, apareciendo DUPLICADA junto a la fila fresca y correcta ("Not needed here") — dos filas contradictorias para el mismo rom. Corregido: cualquier archivo con ruta real dentro del alcance del escaneo (reconocido o no) marca como "tocado" al juego que su propio nombre de archivo implica, sin importar si el matcher terminó atribuyéndoselo a `game: nil` o no. **Requiere volver a escanear la carpeta afectada** — los datos ya guardados de un escaneo anterior no se corrigen solos, solo un escaneo nuevo aplica la lógica corregida.

**Tercer bug, la causa raíz definitiva (04-ago-2026, mismo día):** tras corregir el duplicado, la fila única resultante mostraba "Unknown game" (ícono gris "?") en vez de "QSound (HLE)" en amarillo. Causa: la comprobación de "¿existe este juego de verdad?" que decide si un archivo sobrante se pliega en la fila de un juego conocido o se convierte en un bucket "Unknown game" separado, se basaba en `gameAggregateStatusByName`/`entriesByGame` — diccionarios construidos **solo a partir de resultados del escaneo** (`entry.game != nil`). Un juego real del DAT cuya lista de roms esperadas queda en CERO bajo el modo de merge activo (como `qsound_hle` bajo Split) nunca genera ninguna entrada con `game` asignado — así que nunca existía en esos diccionarios, y su archivo sobrante fallaba la comprobación de existencia en los TRES lugares que la hacen (`gameNodes`, `computeGameAggregateStatusByName`, `computeScopedStatusCounts`).

**Corregido:** la comprobación de existencia ahora usa el catálogo real del DAT (`gamesByName`, derivado de `viewModel.preloadedGames` — todos los juegos que el DAT declara, sin importar si el escaneo produjo alguna entrada suya) en los tres lugares, en vez del resultado del escaneo. Además, cada `GameNode` ahora recibe `sourceGame` (el `DATGame` real) como respaldo para su título — así un juego sin ninguna entrada propia con `gameDescription` (como este caso) sigue mostrando su descripción real ("QSound (HLE)") en vez de su nombre interno crudo ("qsound_hle").

### 3d. Caso de estudio completo: `qsound` / `qsound_hle` (chip de sonido compartido entre decenas de juegos)

Vale la pena documentar este caso con detalle porque expone, en un solo ejemplo real, exactamente para qué existe todo lo de §3c — y porque el propio jensyleo detectó en vivo una afirmación incorrecta mía sobre él (04-ago-2026), que quedó corregida abajo.

**Los hechos reales de la colección** (mame0288.DAT + carpetas `CAPCOM/CPS1` y `CAPCOM/CPS2`):

- `qsound` es la máquina "padre" — el chip de sonido QSound de Capcom en sí, declarado en el DAT con su propia rom `dl-1425.bin` (sin `merge=`, es la copia "original" de referencia).
- `qsound_hle` es una máquina de DISPOSITIVO separada (`isdevice="yes"`, `romof="qsound"`) — la emulación HLE del mismo chip. Declara la MISMA rom, pero con `merge="dl-1425.bin"`: MAME dice explícitamente "esta es la misma rom que la del padre, no la dupliques".
- Docenas de juegos reales de CPS1 y CPS2 (`1941`, `dino`, `punisher`, `wof`, `19xx`, `avsp`, `xmvsf`, `mvsc`, `ssf2`, `sfa`, etc. — cualquier juego que use el chip QSound) tienen, cada uno, su **propia copia física** de `dl-1425.bin` dentro de su propio `.zip` — así es como se distribuyen los romsets "todo incluido"/Un-merged que la gente descarga.
- **Solo `qsound.zip`** (ubicado en la carpeta `CPS2`, no en `CPS1`) existe como archivo dedicado exclusivamente a la máquina `qsound`.

**Verificado byte a byte:** el `dl-1425.bin` dentro de `qsound_hle.zip` (CPS1) y el de `qsound.zip` (CPS2) son idénticos (mismo MD5, `108b113a...`) — es literalmente el mismo archivo, repetido en más de 25 sitios distintos de la colección.

**Bajo Split, escaneando CPS1 + CPS2 juntos** (como estarían configuradas para un mismo sistema):

| Archivo | `dl-1425.bin` reporta |
|---|---|
| `qsound.zip` (CPS2) | 🟢 `.correct` — aquí SÍ es su hogar declarado |
| `qsound_hle.zip` (CPS1) | 🟡 "Not needed here (required by QSound)" |
| `wof.zip`, `dino.zip`, `punisher.zip` (CPS1) | 🟡 "Not needed here (required by QSound)" |
| `19xx.zip`, `avsp.zip`, `xmvsf.zip`, `mvsc.zip`, `ssf2.zip`, `sfa.zip`... (CPS2, 20+ más) | 🟡 "Not needed here (required by QSound)" |

**Error propio corregido en vivo:** en un primer análisis afirmé que `qsound.zip` no existía en la colección del usuario en absoluto — basado en solo haber mirado la carpeta `CPS1`. jensyleo señaló correctamente que sí existía, y en efecto estaba en `CPS2`. Esto es la prueba práctica de por qué `requiredByGameDescription` debe buscarse contra **todo el escaneo combinado** (todas las carpetas del sistema), nunca contra una sola carpeta aislada — exactamente el diseño ya implementado (§3c), solo confirmado aquí con un caso real de gran escala (25+ copias redundantes de un mismo archivo).

### 3e. "Unknown game" (gris) vs. archivo sobrante ya identificado (amarillo) — caso Merged

**Pregunta real de jensyleo (04-ago-2026):** bajo Merged, un clon (ej. `sf2acca.zip`) queda **excluido por completo** de `dat.games` (se pliega en su padre) — así que su archivo físico, aunque el matcher identifica correctamente todo su contenido (ver §3c/3d), no tiene ningún juego real al que plegarse en la lista izquierda. Antes de esta corrección, esto SIEMPRE se mostraba como "Unknown game" gris — aunque el panel derecho, fila por fila, ya mostrara cada rom en amarillo "Not needed here". Gris y amarillo contradiciéndose para el mismo contenido exacto.

**Regla decidida:** "Unknown game" (gris) debe significar honestamente *"no tengo ninguna idea de qué es esto"*. Si **todas** las entradas de un archivo sobrante tienen `requiredByGameDescription` (es decir, el matcher identificó a qué juego real le pertenece cada una), el bucket completo se reclasifica:

| Situación | Color | Texto |
|---|---|---|
| Al menos una entrada genuinamente irreconocible | ⚪️ Gris, `.surplus` | "Unknown game" |
| **Todas** las entradas identificadas (`requiredByGameDescription` en todas) | 🟡 Amarillo, `.incorrect` | "Extra archive, not needed here (required by `<juego>`)" |

Controlado por el toggle correspondiente a su color real: un bucket reclasificado amarillo responde al toggle "Incorrect", no al toggle separado "Unknown" — y el conteo "Unknown: N" del encabezado ya no lo cuenta (contradiría su propio color).

**Límite cerrado (04-ago-2026, mismo día):** este bucket reclasificado ahora SÍ se suma al conteo "Incorrect: N" del encabezado. `computeScopedStatusCounts` aplica el mismo criterio `isFullyIdentified` a cualquier archivo sobrante que no logre plegarse en un juego real de `dat.games` (el caso Merged) — si todas sus entradas están identificadas, cuenta como un archivo más bajo `.incorrect`, exactamente igual que la fila que ves en la lista. Encabezado, fila y toggle ya están sincronizados para este caso.

### 3f. Un clon puede tener su propio CHD distinto al de su padre — Merged debe esperar ambos

**Encontrado revisando el código de Merged a fondo (04-ago-2026), no reportado en vivo por el usuario.** `MAMESetLayoutPlanner.mergedGame` ya unía las roms únicas de toda la familia (padre + clones) en la entrada que sobrevive bajo Merged — pero nadie hacía lo mismo con los **discos**. `DATLoader.datFile` tomaba el campo `disks` directamente de la máquina padre, ignorando los discos propios de sus clones.

**Verificado contra el DAT real (mame0288):** **313 clones declaran un CHD con un SHA1 genuinamente distinto al de su padre** (una revisión/región de disco diferente) — no es un caso raro. Bajo Merged, como el clon queda excluido por completo de `dat.games`, ese CHD propio nunca era esperado por nadie: aunque el usuario tuviera el archivo `.chd` correcto, se reportaba como "Unrecognized" (sobrante genuino), sin ninguna manera de reconocerlo.

**Corregido:** nueva función `DATLoader.mergedDisks(for:mode:dataset:)` — bajo Merged, une los discos propios del juego que sobrevive con los de **todos sus clones directos** (deduplicado por nombre+SHA1, ya que 91 de esos 313 casos SÍ comparten el disco idéntico con el padre). Split/Un-merged no necesitan este cambio — ahí cada clon sigue teniendo su propia entrada en `dat.games`, con su propio disco ya capturado directamente.

**Se descartó una segunda sospecha relacionada:** ¿existen cadenas "clon de un clon" (3 niveles) que romperían la búsqueda de `clones(ofParent:)` (que solo mira hijos directos)? Verificado: **cero casos** en el DAT real — la convención de MAME siempre apunta `cloneof` directo a la raíz verdadera, nunca a un clon intermedio. No era un bug real.

Verificado en vivo: `area51`/`area51t` — bajo Merged, la entrada fusionada "area51" ahora espera ambos discos correctamente.

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
  .surplus       →  ⚪️ Unrecognized (no es un juego real)
  .unverifiable  →  ⚪️ Nodump (unverifiable) — rom nodump, ver §4e2

  EXCEPCIÓN: rom 100% missing + CHD del mismo juego != missing
             → la fila de ROM no se muestra. Solo se ve el CHD (🟢).
```

---

### 4e2. Nuevo estado: `.unverifiable` — roms `nodump` (agregado 04-ago-2026)

**Caso real:** `Neo-Geo MV-6F` no aplicaba aquí, pero un caso paralelo sí: `Gryzor` (`gryzor.zip`, clon de `Contra`) mostraba "Unknown game" (gris) en la lista pese a que casi todas sus filas eran amarillas "Not needed here" — salvo una, `007766.20d.bin`, gris "Unrecognized" puro.

**Causa raíz:** ese rom está declarado `status="nodump"` en el DAT — un PAL nunca dumpeado, sin CRC/MD5/SHA1, solo un placeholder `size="1"`. `contra` (el padre) y TODOS sus clones (incluido `gryzor`) redeclaran el mismo nombre de forma idéntica — no hay ninguna marca en el rom que diga "esto viene de tal clon". El usuario tenía DOS copias físicas del mismo placeholder de 1 byte (una en `contra.zip`, que satisface el único requisito deduplicado; otra en `gryzor.zip`, sobrante). Como `nodump` no tiene hash, el mecanismo existente de "reconocer contenido sobrante por hash" (`romsByHash`) nunca podía reconocer esa copia — cae a "Unrecognized" puro, indistinguible de basura real.

**Corregido con dos mecanismos complementarios:**
1. `DATGame.mergedFamilyMachineNames` (padre + todos los clones plegados bajo Merged) — permite que `ROMMatcher` reclame por NOMBRE un rom `nodump` sin reclamar, buscando en cualquier archivo de la familia, no solo el archivo propio del juego (cubre el caso "el archivo real solo existe en el clon, nunca en el padre").
2. `SurplusFile.matchesNodumpRomName` — un archivo sobrante sin ningún hash conocido, pero cuyo NOMBRE coincide con algún rom `nodump` del DAT, se reclasifica de `.surplus` a `.unverifiable` en vez de quedar "Unrecognized" (cubre el caso real encontrado: copia duplicada del mismo placeholder).

**Nuevo `AuditStatus.unverifiable`:** gris (mismo color que `.surplus`), ícono distinto (`questionmark.circle` sin relleno), nunca eleva severidad (tratado como `.surplus` en `AuditStatus.worst(among:)`). Mensaje de fila: "Nodump (unverifiable)". Un bucket "Unknown game" cuyas entradas están TODAS explicadas (ya sea `requiredByGameDescription` o `.unverifiable`) ahora se reclasifica a "Extra archive, not needed here" (amarillo), igual que el caso ya existente de archivos 100% identificados por hash.

Verificado en vivo contra el DAT y carpeta reales (`CAPCOM/OTHER`): `007766.20d.bin` en `gryzor.zip` pasó de `surplus` a `unverifiable`. `DATFileCache.currentFormatVersion` (v4) y `AuditReportDatabase.currentSchemaVersion` (v11) subidos.

### 4e. Bug real: declaración duplicada de un mismo rom dentro de una máquina (`mergedGame`, corregido 04-ago-2026)

Un `-listxml` real puede declarar el MISMO rom físico (mismo name/crc/sha1/size) dos veces dentro de una sola `<machine>`, bajo distintos `region=`. Caso confirmado en vivo: `neogeo` declara `sm1.sm1` una vez con `region="audiobios"` y otra con `region="audiocpu"`, byte-idénticas — no es un DAT malformado, es así en el dump real.

`splitGame()` ya deduplicaba esto (comentario propio citando este mismo caso), pero `mergedGame()` — la función que se usa bajo `mergeMode = .merged`, el modo real del usuario — no lo hacía. Resultado: dos requisitos lógicos para un solo archivo físico. Uno resolvía `.correct` (reclamaba el archivo), el otro no tenía nada que reclamar, caía al fallback `foundElsewhere` sin restricción, y encontraba el mismo archivo ya reclamado — reportando `.incorrect` con `foundElsewhere` apuntando a su PROPIO archivo (`neogeo.zip`). Esto pintaba el juego "Rom need fix" (amarillo) en la lista aunque cada fila visible del rom mostrara verde "Ok" — porque ninguna fila individual estaba mal, la entrada fantasma duplicada sí.

**No era un problema de mensaje, era un bug real de conteo de requisitos.** Corregido agregando a `mergedGame()` la misma guarda de "salto si ya se agregó un rom idéntico (name+crc+md5+sha1+size)" que `splitGame()` ya tenía. Verificado en vivo contra el DAT y carpeta NEOGEO reales del usuario: antes 35 entradas para `neogeo` (una `.incorrect` fantasma), después 34 entradas, todas `.correct`.

Cache-busting aplicado (regla de la sesión): `DATFileCache.currentFormatVersion` 2→3, `AuditReportDatabase.currentSchemaVersion` 9→10.

---

## 7. Qué falta documentar (pendiente, no bloqueante)

- El bug de visualización en CPS3 mencionado el 04-ago-2026 (pendiente de investigar).
- Comportamiento de un `.chd` en disco que no corresponde a ningún disco del DAT (actualmente invisible, ni disco ni surplus).
- Esta tabla es la base para la fase de manipulación de archivos (rebuild/fix) — cuando esa fase empiece, cada acción posible (renombrar, mover, reconstruir zip, etc.) debe mapearse explícitamente a uno de los estados de arriba, no inventarse ad-hoc.
