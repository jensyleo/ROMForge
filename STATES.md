# ROMForge — Estados de identificación (ROM/CHD/Juego)

Documento de referencia único para toda la lógica de "¿qué estado tiene esto y qué mensaje se muestra?". Es la base para la futura fase de manipulación de archivos (rebuild/fix) — cualquier decisión sobre qué hacer con un archivo depende de identificar primero, sin ambigüedad, en qué estado está.

No documenta el código en sí (eso vive en los doc-comments de cada archivo); documenta el **modelo de decisión**: qué hechos determinan cada estado, y qué le mostramos al usuario en cada caso.

---

## 0. Fuentes externas — cómo MAME gestiona sus propios ROMs

ROMForge no inventa reglas propias sobre qué es un rom "correcto", "nodump" u "opcional" — todo eso viene directo del formato que MAME mismo define. Estas son las fuentes consultadas y en qué orden de confiabilidad, de mayor a menor:

1. **El DTD embebido en el propio `-listxml`** (las primeras ~100 líneas de cualquier DAT real de MAME, dentro de `<!DOCTYPE mame [...]>`). Es la fuente más confiable posible: lo genera MAME mismo, en la misma versión exacta que produjo el DAT que estás usando. Aquí es donde se confirmaron los atributos `status="nodump"/"baddump"`, `merge="..."`, y `optional="yes"` en `<rom>`/`<disk>` — no en ningún wiki de terceros. Para verlo tú mismo: `head -120 tu_archivo.DAT` y busca `<!ELEMENT` / `<!ATTLIST`.
2. **El código fuente de auditoría de MAME**, [`src/frontend/mame/audit.cpp`](https://github.com/mamedev/mame/blob/master/src/frontend/mame/audit.cpp) — cómo MAME mismo decide si un romset "pasa" para poder ejecutarse (enums `audit_status`/`audit_substatus`, manejo de `ROM_ISOPTIONAL`/`FLAG_NO_DUMP`, lógica de samples). **Nota importante de diseño:** MAME optimiza esto para una sola pregunta binaria ("¿puedo correr este juego?"); ROMForge, al ser un gestor/auditor de colección, deliberadamente NO copia esa lógica de colapso a un solo booleano — muestra el estado real de CADA archivo individual (fila por fila), incluso cuando MAME internamente lo consideraría irrelevante para arrancar el juego. Es una divergencia intencional, no un descuido.
3. **Documentación de línea de comandos de MAME** — [docs.mamedev.org/commandline](https://docs.mamedev.org/commandline/commandline-all.html) — `-listxml`, `-verifyroms`, `-verifysamples`, `-listsamples`.
4. **wiki.romvault.com** (`mame_listxml` y páginas relacionadas) — útil como contexto de cómo otra herramienta real (RomVault) consume el mismo formato, aunque no es una referencia normativa del formato en sí.

**Regla de la sesión (04/05-ago-2026):** cualquier caso especial nuevo se verifica primero contra el DAT real del usuario (`mame0288.DAT`) con `grep`/`awk`/`python3` — nunca se asume que un atributo existe o se usa con cierta frecuencia sin contarlo en el archivo real. Cuando el DAT real no tiene un caso de prueba disponible (ej. el usuario no posee la colección de Astron Belt), se verifica con un archivo sintético (vacío, solo el nombre correcto) contra el DAT real — la lógica de nombre/hash no requiere contenido real para probarse.

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

Un CHD tiene 4 estados posibles (nunca `.badDump`, nunca `.foundElsewhere` — se verifica por el SHA1 del header, no hay "está en otro lado"):

| `CHDDiskStatus` | `AuditStatus` | Texto en fila de disco (izquierda) |
|---|---|---|
| `.correct(url)` | `.correct` | "Correct" |
| `.incorrect(url)` | `.incorrect` | "Incorrect" |
| `.missing` | `.missing` | "Missing" |
| `.unverifiable(url)` | `.unverifiable` | "Nodump (unverifiable)" — ver §4e3 |

**Corregido (05-ago-2026):** un `.chd` en disco que no corresponde a NINGÚN disco declarado por el DAT (para ninguna máquina) ya NO desaparece — `DiskAuditor.audit` rastrea qué archivos `.chd` reclama cada disco (`.correct`/`.incorrect`/`.unverifiable`) y, al final, cualquier `.chd` sin reclamar se reporta como `.surplus` (`game: nil`, `isDisk: true`) — exactamente el mismo mecanismo que ya existía para roms sobrantes, así que la capa de la app (`gameNodes(from:)`) lo agrupa automáticamente en su propio bucket "Unknown game" sin cambios adicionales. Verificado en vivo contra un caso real del usuario: `cap-33s-22.chd` (en `CAPCOM/CPS3/BATOCERA/sfiii3`) no coincide con ningún `<disk>` del DAT real — antes invisible, ahora aparece como sobrante. `AuditReportDatabase.currentSchemaVersion` subido a v14.

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

### 4e5. CHD huérfano vs. CHD duplicado — distinguidos correctamente (agregado 05-ago-2026)

Al implementar el fix de "CHD huérfano ya no desaparece" (§4e3/TODO.md, mismo día), el usuario detectó en vivo un bug real: cualquier `.chd` que existiera en DOS carpetas físicas distintas (su propia colección real: `CAPCOM/CPS3/` y `CAPCOM/CPS3/BATOCERA/` — varios CHDs mirroreados en ambas) mostraba una fila duplicada gris "Unknown game" junto a la fila verde correcta del mismo archivo — el fix inicial solo distinguía "reclamado" vs. "no reclamado", sin reconocer que un `.chd` no reclamado podía seguir siendo contenido CONOCIDO (una segunda copia física de un disco que el DAT sí declara, solo que la primera copia ya lo satisface).

**Corregido:** igual patrón que `romsByHash`/`requiredByGameDescription` ya usa para roms duplicados. `DiskAuditor.audit` ahora construye un índice de TODOS los sha1 de disco que declara el DAT (de cualquier juego), y cuando un `.chd` sobrante no fue reclamado por nadie, compara su propio sha1 de header contra ese índice: si coincide, se reclasifica `.incorrect` con `requiredByGameDescription` (renderiza como "Not needed here (required by X)", el mismo texto y lógica de plegado que ya existe para roms — sin ningún cambio en la capa de la app); si no coincide con nada, sigue siendo `.surplus` genuino ("Unknown game").

Verificado en vivo contra la carpeta CPS3 real del usuario: 4 CHDs duplicados (`cap-sf3-3.chd`, `cap-3ga000.chd`, `cap-33s-1.chd`, `cap-33s-2.chd`, presentes en ambas carpetas) pasaron de mostrar un "Unknown game" fantasma a "Not needed here (required by ...)"; el único huérfano genuino (`cap-33s-22.chd`, solo en BATOCERA) siguió correctamente en `.surplus`. `AuditReportDatabase.currentSchemaVersion` subido a v15.

### 4e4. `optional="yes"` — MAME puede correr sin este archivo (agregado 05-ago-2026)

Segunda ronda de investigación (esta vez pedida explícitamente vía web), tras revisar el DTD que MAME incrusta al inicio de su propio `-listxml` (la referencia más autorizada posible — generada por MAME mismo, no un wiki de terceros). El DTD confirma un atributo real no considerado: `<!ATTLIST rom optional (yes|no) "no">` y el mismo para `<disk>`.

**Distinto de `nodump`:** `nodump` significa "no se puede verificar" (sin hash). `optional="yes"` significa "MAME puede correr la máquina sin este archivo" — el archivo SÍ tiene hash real y es completamente verificable, simplemente no es obligatorio.

**Uso real en el DAT:** 0 roms, 3 discos (`cubeqst`, `cubeqsta`, `atronic`) — todos con `sha1` real. Ninguno de tus sistemas actuales (CPS1-3/NEOGEO) lo usa.

**Implementado:**
- `DATRom.optional`/`DATDisk.optional`, parseados desde el atributo XML.
- `AuditEntry.isOptional` — nuevo campo, persistido en SQLite (columna `is_optional`, sin necesidad de invalidar cachés viejas gracias al `DEFAULT 0`).
- Texto de fila: "Missing (optional)" en vez de "Missing" plano cuando falta un archivo declarado opcional.
- `gameCategory(for:)`: un rom/disco `optional` ausente ya NO fuerza el estado agregado del juego a rojo "Missing" — sigue el mismo razonamiento no-severo que `.unverifiable`. Si el juego tiene otro contenido verificado, el badge queda verde; si el único contenido es ese disco opcional ausente, cae a "Correct" por defecto (mismo comportamiento que ya existía para `.surplus`/`.unverifiable` sin ningún otro contenido).

**Bug adicional encontrado y corregido en el mismo pase:** `AuditReportDatabase.loadReport` nunca calculaba el conteo `unverifiable` al recargar un reporte cacheado desde SQLite (siempre quedaba en 0 pese a que las entradas individuales sí tenían el status correcto) — corregido junto con este cambio.

Verificado en vivo contra el DAT real: `cubeqst.disks.first?.optional == true`, y auditar sin el archivo produce `status=.missing, isOptional=true`. `AuditReportDatabase.currentSchemaVersion` subido a v13.

### 4e3. `.unverifiable` extendido a discos CHD (agregado 05-ago-2026)

Investigación pedida por el usuario tras probar los tres modos de Rom merge mode: revisar el DAT real por otras variables/casos especiales no considerados. Encontrado: **184 elementos `<disk>`** en el DAT real (`mame0288.DAT`) declarados sin atributo `sha1` — el equivalente exacto de un rom `nodump`, pero del lado de discos CHD (ej. `astron`, laserdisc de Sega, `<disk name="astron" status="nodump" .../>`).

**Antes:** `CHDMatcher.match` hacía `guard let expectedSHA1 = diskSHA1 else { return .missing }` de forma incondicional — sin importar si el archivo `.chd` real existía con el nombre correcto, siempre se reportaba "missing".

**Corregido:** mismo patrón aplicado a roms — si el disco no declara `sha1`, se busca por NOMBRE (nuevo caso `CHDDiskStatus.unverifiable(URL)`); si existe un `.chd` con ese nombre, se reporta `.unverifiable` ("Nodump (unverifiable)") en vez de `.missing`. Si no existe ningún archivo, sigue siendo `.missing` (a diferencia de un rom `nodump`, un disco SÍ se sigue reportando si falta — MAME normalmente necesita el CHD para correr el juego, no es opcional como el chip PAL nunca dumpeado).

**Ajuste adicional necesario:** `gameCategory(for:)` (agregación de estado por juego) antes convertía CUALQUIER estado no severo (missing/badDump/incorrect) a `.correct` en silencio — correcto para roms (donde `.unverifiable` casi siempre convive con otros roms sí verificados), pero incorrecto para un disco cuyo ÚNICO estado es `.unverifiable`: mostraría "Correct" falso. Ahora solo cae a `.correct` si hay al menos una entrada genuinamente `.correct`; si no, y hay alguna `.unverifiable`, se reporta como tal.

Verificado con un caso sintético (archivo `.chd` vacío nombrado `astron.chd`, ya que el usuario no posee esa colección) contra el DAT real: con el archivo presente → `.unverifiable`; sin él → `.missing` (sanity check). `AuditReportDatabase.currentSchemaVersion` subido a v12 (no requiere cambio de esquema, solo invalidar caché vieja).

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

## 7. Rom merge mode / Bios merge mode: qué significan, cómo los maneja ROMForge, y cuál usar

Dos ejes **completamente independientes** (confirmado contra el Settings dialog real de un frontend de referencia de MAME — ninguno de los dos implica ni condiciona al otro), cada uno con las mismas tres opciones (Merged / Split / Un-merged), aplicados a TODO el sistema MAME por igual (no configurable por juego).

### 8a. Rom merge mode — qué le hace físicamente a los archivos

| Modo | Cómo se organiza el archivo físico |
|---|---|
| **Split** | El archivo de un clon contiene SOLO lo que le es único; todo lo que comparte con su padre (marcado `merge="..."` en el DAT) se espera únicamente en el archivo del padre. |
| **Merged** | UN SOLO archivo (el del padre) contiene los roms del padre **y** todos los roms únicos de cada uno de sus clones. Los clones no tienen archivo propio. |
| **Un-merged** | Cada máquina (padre y cada clon) tiene su PROPIO archivo, completo y autocontenido — incluye tanto lo que comparte con el padre como lo que le es único. Ningún archivo depende de otro. |

`MAMESetLayoutPlanner.swift` (`splitGame`/`mergedGame`/`nonMergedGame`) es donde se implementa cada uno — ver los doc-comments de cada función para el detalle exacto, incluyendo los casos especiales ya corregidos (roms `merge=` duplicados dentro de una misma máquina, familia completa de discos/roms bajo Merged, etc. — secciones 3 y 4e arriba).

### 8b. Recomendación de ROMForge: **Un-merged**

Es el valor por defecto de la app (`MAMEMergeModeSettings.defaultMergeMode`, `GeneralSettingsView.swift`) y el que se recomienda explícitamente en el selector de Configuración. Razones:

1. **Es el modo con menos falsos "missing".** Bajo Split o Merged, un juego puede depender de que EXISTA el archivo de otra máquina (el padre, o viceversa) — si esa otra máquina falta o está mal organizada, el juego que sí tienes se reporta incompleto sin serlo realmente. Un-merged elimina esa dependencia entre archivos por completo: cada archivo se audita 100% por sí mismo.
2. **Es el modo más tolerante a colecciones parciales o desordenadas** — el caso real más común (nadie tiene el romset completo de MAME). Con Split/Merged, tener SOLO los clones que te interesan (sin el padre) casi garantiza reportes "incomplete"/"Bad" para roms que en realidad SÍ tienes, solo que el DAT los espera en el archivo equivocado bajo ese modo.
3. **Es el más simple de razonar:** "un archivo, un juego, completo por sí mismo" — sin necesidad de entender la relación padre/clon del DAT para saber si tu colección está bien organizada.
4. **Contrapartida real, no oculta:** usa más espacio en disco (contenido compartido duplicado en cada archivo). Para el usuario de ROMForge (auditoría/gestión de colección, no arcades físicos con espacio limitado), esto es normalmente aceptable.

**Cuándo Merged puede sorprender (advertencia ya visible en la app):** con Merged, el archivo del padre DEBE contener también el contenido único de cada uno de sus clones — si solo tienes el padre y ninguno de sus clones, el padre se reporta incompleto, aunque tú nunca hayas querido esos clones. Split no tiene este problema (cada clon es independiente en cuanto a lo que le es propio), pero SÍ requiere que el archivo del padre esté presente para lo compartido.

**Bios merge mode** sigue la misma tabla pero aplicada específicamente a los roms de la BIOS (ej. `neogeo.zip`) en vez de a la relación padre/clon — Split (BIOS en archivo separado) es la convención más común en colecciones reales y es el default de ROMForge para este eje específico.

### 8c. Resumen de casos especiales de MAME ya modelados por ROMForge

| Concepto MAME (atributo real del DAT) | Qué significa | Cómo lo maneja ROMForge | Sección |
|---|---|---|---|
| `merge="..."` en `<rom>`/`<disk>` | Este archivo es idéntico a uno en el padre/BIOS — no lo esperes aquí bajo Split | Filtrado por `mergeName`/layout planner según el modo activo | 8a |
| `status="nodump"` en `<rom>` | Chip real nunca dumpeado — sin hash, solo un placeholder | `.unverifiable` si existe un archivo con el nombre correcto (en el archivo propio o en cualquier archivo de la familia merged); si no existe ninguno, se omite del reporte (MAME no lo necesita para correr) | §4e2 |
| `status="nodump"` en `<disk>` | Igual, pero para CHDs | `.unverifiable` si existe un `.chd` con el nombre correcto; si no, `.missing` (a diferencia del rom, un CHD SÍ suele ser necesario para correr el juego) | §4e3 |
| `status="baddump"` | Dump conocido pero incorrecto (según el propio MAME) | `isBadDump`/`romDumpStatus`, mostrado como sufijo informativo, independiente del hallazgo local | §3d (`AuditEntry.isBadDump`) |
| `optional="yes"` en `<rom>`/`<disk>` | MAME puede correr la máquina sin este archivo, aunque sea real y verificable | "Missing (optional)" en vez de "Missing"; no fuerza el badge del juego a rojo | §4e4 |
| Rom duplicado exacto dentro de la misma máquina (mismo name+hash, dos regiones) | Ej. `neogeo`'s `sm1.sm1` (region `audiobios` y `audiocpu`) | Deduplicado antes de generar los requisitos — una sola entrada, no dos | §4e |
| `isdevice="yes"` con roms reales | Un "device" interno de MAME que también tiene su propio romset auditable (ej. `qsound_hle`) | Auditado como su propia entrada, no excluido solo por ser device | investigado 05-ago-2026, ya corregido antes |
| `<softwarelist>` dentro de `<machine>` | Qué softwarelist(s) de cartucho soporta el driver | Metadata pura, sin hashes — no se parsea (no afecta auditoría de archivos) | investigado 05-ago-2026 |
| `<sample>`/`sampleof` | Archivos de audio opcionales (`.wav`) | Solo presencia (`hasSamples: Bool`) — no se auditan archivos de sample individuales | Ya documentado en `AuditReport.swift` |

---

## 8. Profundidad de carpetas que ROMForge escanea

**Regla explícita (definida 05-ago-2026, decisión del usuario tras evaluar alternativas):** `FolderScanner` solo desciende **1 nivel de subcarpeta** por debajo de la carpeta que configuras para un sistema — la convención `<sistema>/<juego>/<archivo>` (un archivo suelto en la raíz, o dentro de exactamente una subcarpeta de juego). Si encuentra algo más profundo, **no escanea nada de esa carpeta** — lanza `ScannerError.folderTooDeep` con la ruta relativa exacta de lo que encontró, en vez de escanear parcialmente o silenciosamente ignorar el exceso.

**Por qué:** sin límite, apuntar la app a una carpeta demasiado amplia (la raíz del disco, la carpeta de usuario) intentaría enumerar recursivamente TODO lo que hay debajo — sin sentido y potencialmente muy lento. Se evaluaron 3 alternativas (límite más alto tipo 5-6 niveles; límite estricto de 1 nivel; sin límite de niveles pero con tope de cantidad de archivos) — el usuario eligió el límite estricto de 1 nivel, aceptando reorganizar cualquier carpeta real que no cumpla (ej. aplanar una subcarpeta extra tipo `BATOCERA`).

**Caso real que motivó esto:** la carpeta CPS3 real del usuario tiene una subcarpeta `BATOCERA` que duplica varios juegos un nivel más profundo de lo permitido (`CPS3/BATOCERA/sfiii3/cap-33s-1.chd` = 2 niveles, viola el límite de 1). Esa carpeta necesita reorganizarse (aplanar o eliminar `BATOCERA`) antes de poder escanearse — de hecho, esa misma duplicación física es la causa raíz del bug de CHD duplicado corregido en §4e5: una vez aplanada la carpeta, no habrá dos copias físicas del mismo CHD y ese caso deja de aparecer en absoluto.

**No confundir con:** múltiples carpetas de ROMs configuradas para un mismo sistema (ej. una carpeta para NEOGEO y otra separada para sus updates) — eso ya está soportado desde antes y no tiene relación con este límite; el límite aplica a la profundidad DENTRO de cada carpeta configurada, no a cuántas carpetas configures.

---

## 9. Qué falta documentar (pendiente, no bloqueante)

- El bug de visualización en CPS3 mencionado el 04-ago-2026 (pendiente de investigar).
- Esta tabla es la base para la fase de manipulación de archivos (rebuild/fix) — cuando esa fase empiece, cada acción posible (renombrar, mover, reconstruir zip, etc.) debe mapearse explícitamente a uno de los estados de arriba, no inventarse ad-hoc.
