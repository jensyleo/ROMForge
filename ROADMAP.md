# Roadmap

Architecture: hybrid phasing. v0.1–1.0 build the clrmamepro-style audit/rebuild
core, fully decoupled from the UI. v2.0+ add RomCenter-style library features
(metadata, database, emulator launching) as new modules on top of the same
core, without rewriting it.

Pending/in-progress work tracked locally in `TODO.md` (gitignored, not
part of the published repo) — see there for the current punch list.

## Honest gap vs. RomCenter (last updated 2026-08-05)

ROMForge is visually and structurally *inspired* by RomCenter 4.0.0, but it is
still far from functionally equivalent. Worth stating plainly rather than
implying parity:

- **CHD**: header-SHA1 verification IS wired into the scan pipeline (`DiskAuditor`
  + `CHDMatcher`, since 2026-07-30) — a `.chd` file is looked for, its v5
  header read, and its own SHA1 compared against the DAT's declared one,
  same as RomCenter itself does ("Romcenter gets the sha-1 from the chd
  header... doesn't calculate the full file sha-1 for chd" — see this
  file's own CHD research section below). `.unverifiable` (2026-08-05)
  covers a DAT-declared `nodump` disk (undumped media, no sha1 at all —
  184 real cases in a real MAME 0.288 dump) and an orphan `.chd` matching
  no `<disk>` at all now surfaces as a surplus/"Unknown" entry instead of
  vanishing (2026-08-05, real case: `cap-33s-22.chd`). The gap that
  genuinely remains: neither ROMForge nor (per that same research) RomCenter
  decompresses hunks to verify the actual disc *image* content — only the
  header's own claimed SHA1. Full hunk decoding exists in Core
  (`CHDHunkReader`, zlib only) but isn't wired to any verification path —
  see its own section below for exactly what's blocked and why.
- **Samples**: same gap — "Games with samples" is DAT-declared only, no
  sample file is ever looked for or checked.
- **Headered dumps (copier headers)** — closed: a headered dump (iNES
  16-byte, Lynx 64-byte, the shared SNES/GB/PCE/SMS 512-byte copier header,
  or Genesis's interleaved `.smd`) now matches a headerless DAT entry,
  whether the file is loose or inside a `.zip` (see the "Path to a full
  replacement" section below for how). Not covered: any *other* console's
  header/interleave convention not in this list — this closes the ones
  RomCenter's own plugin sources documented, not necessarily every
  convention that exists in the wild.
- **Bad dumps**: RomCenter tracks this per the DAT too, so this one is
  actually close — but ROMForge doesn't yet combine "DAT says baddump" with
  "and here's what a rebuild/repair should do about it" the way RomCenter's
  Fix pipeline does (moot for now anyway, since Fix is disabled while
  view-only mode is on).
- **Merge sets / rebuilding**: the *audit* side is now correct —
  `MAMESetLayoutPlanner` computes what each machine's archive should
  contain per merge mode (split/non-merged/merged), including the
  collision/BIOS/device edge cases (see the "Path to a full replacement"
  section below), and `DATLoader` applies split-mode layout when converting
  a real MAME DAT. What's still missing is the *rebuild* side: RomCenter's
  "Merge" checkbox and Fix pipeline actively rebuild split/merged/non-merged
  sets on disk, move files between games that share a rom, and pack/unpack
  archives interactively. ROMForge's `RebuildPlanner`/`RebuildExecutor` can
  do rename/move/copy/archive operations in Core, but the app never exposes
  set-rebuilding — and Fix itself is disabled while view-only mode is on.
- **No metadata layer at all**: no covers, screenshots, genre, players,
  history — RomCenter doesn't really have this either (that's more a
  Batocera/EmulationStation thing), so this is a v2.0+ ROMForge-only
  ambition, not a RomCenter gap per se.
- **No database persistence**: RomCenter keeps a real local database of the
  collection state across runs; ROMForge re-scans from scratch every time
  (no SQLite/SwiftData catalog yet — v2.0+ item).
- **Single DAT/system at a time in the UI**: RomCenter can hold many
  "Rom paths" and switch between loaded DATs in tabs; ROMForge's sidebar
  supports multiple configured systems, but there's no multi-DAT-tab
  workspace like RomCenter's screenshot shows.

None of this means the current work is wasted — the audit pipeline
(scan → hash → match → report) is real and independently tested, and each UI
pass has made the app read closer to RomCenter's layout. It just means
"looks like RomCenter" and "does what RomCenter does" are two different
distances, and right now ROMForge is much further along on the first than
the second.

## Path to a full ClrMamePro/RomCenter replacement — research findings (2026-07-18)

At the user's request ("investiga a fondo... busca en la red todas las fuentes"),
six research passes were run against ClrMamePro's own docs/forums, RomCenter's
docs/forums, MAME's/libchdr's real source code, RomVault's docs/wiki, and DAT
format specs (Logiqx DTD, TOSEC, No-Intro, Redump, MAME software lists). This
is a research summary — **nothing below is implemented yet**, it's the
evidence base for deciding what to build next and in what order. Full agent
transcripts aren't preserved verbatim here; the URLs are the citations that
matter.

### DAT format coverage — real gaps, ranked by value

1. **MAME Software Lists (`hash/*.xml`, `-listsoftware`)** — a third, genuinely
   different DAT dialect ROMForge doesn't parse at all today. Structurally
   distinct from both dialects we handle: `<software>` → one or more
   `<part>` (each a physically separate cartridge/disk/cassette with its own
   `interface`) → `<dataarea>`/`<diskarea>` → `<rom>`/`<disk>`, plus
   `<sharedfeat>`/`<feature>` (two-tier metadata) and `<dipswitch>`. This is
   MAME's own format for every non-arcade system it emulates (computers,
   consoles, handhelds) — the highest-value DAT gap to close, since it's
   fully specified (DTD fetched verbatim from
   [`hash/softwarelist.dtd`](https://github.com/mamedev/mame/blob/master/hash/softwarelist.dtd))
   and directly unlocks a whole category of systems ROMForge currently can't
   audit at all.
2. **Logiqx parser permissiveness** — a real bug waiting to happen, not a
   missing feature: a **live fetch of a real Redump PlayStation DAT**
   ([redump.org/datfile/psx/](http://redump.org/datfile/psx/)) shows
   production DATs routinely add elements the Logiqx DTD never declared
   (`<category>`, `<serial>`, `<version>` as direct children of `<game>`,
   in an order that violates the DTD's own declared sequence). `LogiqxDATParser`
   must tolerate/ignore unrecognized child elements rather than assume a
   fixed element set — this is likely already fine given it's a streaming
   `XMLParser` delegate keyed by element name, but worth an explicit test
   with a real Redump-shaped fixture to confirm nothing chokes on it.
3. **Classic plaintext ClrMamePro dialect** (`clrmamepro ( name "..." )
   game ( name "..." rom ( name "..." size ... crc ... ) )`, no XML at all)
   — still circulates for some No-Intro mirrors (confirmed live on
   [libretro/libretro-database](https://github.com/libretro/libretro-database/blob/master/metadat/no-intro/Nintendo%20-%20Game%20Boy.dat)).
   A small, separate parser, not a Logiqx variant.
4. **TOSEC/No-Intro/Redump are NOT separate structural dialects** — good
   news: all three ride the same Logiqx DTD/DOCTYPE. What differs is
   convention, not schema: TOSEC encodes region/language/version entirely in
   the name string per the TOSEC Naming Convention grammar (fetched from
   [tosecdev.org](https://www.tosecdev.org/tosec-naming-convention)), while
   Logiqx's own DTD separately defines a structured `<release name region
   language date default>` element `GameNameTagParser` doesn't read (it only
   parses the parenthesized-tag convention in names). Redump represents
   multi-track discs as sibling `<rom>` entries (`(Track 01).bin`,
   `(Track 02).bin`, ...) with the `.cue` sheet as just another `<rom>` — no
   disc-image-specific DAT semantics at all, that's on the rebuilder to know.
5. **The Logiqx DTD itself** ([full text](https://github.com/Logiqx/logiqx-www/blob/master/Dats/datafile.dtd))
   defines several elements neither of ROMForge's parsers touch:
   `<release>` (see #4), `<biosset>` in the *Logiqx* sense (alternate BIOS
   revisions, distinct from MAME `-listxml`'s own biosset), `<archive>` (a
   fourth opaque file-kind alongside rom/disk/sample), `<sample>` (top-level
   Logiqx sample sets, not just MAME's arcade convention), and the
   `<clrmamepro>`/`<romcenter>` header blocks (`forcemerging`,
   `forcepacking`, `rommode`/`biosmode`/`samplemode` — profile-level hints
   about how the DAT expects sets to be packed, worth parsing and exposing
   even if ROMForge doesn't obey them yet).

### CHD/ROM independence — deliberate design decision, not an oversight (2026-07-30)

A game's overall status (the "Bad"/"Ok"/"Missing" badge in the "Database"
tree, the header's worst-status summary, the per-status filter counts) is
computed **only from that game's rom entries** — its CHD disk's own
correctness is deliberately excluded from that rollup. jensyleo's own
report after using the newly-wired CHD auditing: a CHD that verified
perfectly correct was still shown as an overall "Bad" game, because a
completely unrelated rom the user has zero interest in owning was missing.
The two used to be folded into one worst-of-all verdict (`gameCategory(for:)`
in `LibraryDetailView.swift`, fed a mixed rom+disk `[AuditEntry]` array);
jensyleo's call was explicit: "simplemente valida la ROM y el CHD por
separado, no busques esa paridad CHD + ROM" — no ROM↔CHD parity check,
ever, and **not worth making configurable either** (a toggle would only
exist to let a user opt back into behavior that's simply wrong).

The disk's own true status is never hidden — it's still fully audited
(`DiskAuditor`, `CHDMatcher`, header-SHA1-based) and shown in its own row
with its own real Correct/Incorrect/Missing status; it just no longer
drags a game's headline badge down (or up) based on the state of a
completely independent rom set, and vice versa.

**If a future user genuinely wants ROM↔CHD parity enforced** (i.e. a game
should only count as "Ok" when *both* its roms and its CHD are present and
correct): the fix is in exactly one place — `romOnlyGameCategory(for:)` in
`App/Sources/LibraryDetailView.swift`, which currently does:
```swift
private func romOnlyGameCategory(for entries: [AuditEntry]) -> AuditStatus {
    let romEntries = entries.filter { !$0.isDisk }
    return romEntries.isEmpty ? gameCategory(for: entries) : gameCategory(for: romEntries)
}
```
Reverting to combined behavior means passing `entries` (the full mixed
rom+disk array) straight to `gameCategory(for:)` instead of filtering out
`isDisk` rows first — both call sites (`computeGameAggregateStatusByName()`
and `computeScopedStatusCounts()`) already route through this one function,
so it's a single-function change, not a scattered one. `AuditEntry.isDisk`
(ROMForgeCore, `Reports/AuditReport.swift`) is what makes the distinction
possible at all — keep that field even if this behavior ever changes, since
per-row disk status (in the table itself) still depends on it being able to
tell a disk row from a rom row.

**Second, easy-to-miss spot with the same bug (found live, 2026-07-30):**
`AuditReport.worstStatus` — the *whole-system* header/sidebar badge
(`LibraryDetailView.swift` line ~604, `ContentView.swift` line ~100) — was
still computed from `entries.map(\.status)` unfiltered, i.e. every rom AND
disk entry across the *entire* DAT at once. Since almost nobody owns every
arcade CD/hard-disk image a full MAME DAT declares, this pinned the
whole-system badge to permanent "Bad" regardless of how correct the user's
actual roms were — the per-game fix above didn't touch this because it's a
report-level rollup, not a per-game one. Fixed the same way: rom entries
only, `entries.filter { !$0.isDisk }`, falling back to all entries only if
there are no roms at all in the report. If any *other* rollup gets added
later (e.g. a per-folder or per-category summary), check it for this same
mixed-rom+disk mistake before shipping it.

**Third spot, the one that actually explained "sigo viéndolo mezclado" after
the two fixes above (found live, 2026-07-30):** `AuditReportDatabase`
(`Persistence/AuditReportDatabase.swift`) — the SQLite cache that lets
reopening ROMForge or re-selecting a system show the last scan's results
without a fresh rescan — had no `is_disk` column at all. Every disk row
saved and reloaded came back with `isDisk` defaulted to `false` (i.e.
silently reclassified as a rom), which undid both fixes above the moment
the report came from this cache instead of a fresh in-memory scan. Fixed
in schema v4: added the `is_disk` column (`ALTER TABLE ... DEFAULT 0` for
existing databases, so old rows just default to the old always-rom
assumption until the next real Scan repopulates them correctly), and both
`saveReport`/`loadReport`'s column lists updated to include it. **The
general lesson, not just this one bug:** any time a new `AuditEntry` field
is added, check `AuditReportDatabase`'s INSERT/SELECT column lists too —
`Codable`/struct field additions are silent and compile fine even when a
manual SQL column list is now out of sync with the struct.

### CHD — full spec now understood; wrapping `libchdr` is the recommended path

Full header layout (V1–V5), hunk-map structure (V5's map is itself
Huffman-compressed with RLE), and every compression codec (zlib, LZMA with
MAME-specific framing, MAME's own proprietary Huffman, FLAC, and the
CD-composite codecs cdzl/cdlz/cdfl which de-interleave 2352-byte sector data
from 96-byte subcode before compressing each separately) were confirmed
directly from MAME's own source
([`chd.h`](https://raw.githubusercontent.com/mamedev/mame/master/src/lib/util/chd.h),
[`chd.cpp`](https://raw.githubusercontent.com/mamedev/mame/master/src/lib/util/chd.cpp),
[`chdcodec.cpp`](https://raw.githubusercontent.com/mamedev/mame/master/src/lib/util/chdcodec.cpp)).
Parent/diff-CHD chains (a hunk can say "identical to my parent's hunk N") are
**required**, not optional, the moment real extraction/rebuilding is
attempted — many official MAME CHD sets use them to save space.

Building this from scratch in pure Swift is realistically a **multi-week
effort** (bit-exact decompression is unforgiving — hunks are verified against
stored CRC32/SHA1, "close enough" fails outright). The much better path:
**[libchdr](https://github.com/rtissera/libchdr)** (BSD-3-Clause — compatible
with inclusion in ROMForge's GPL-3.0 codebase, just retain its notice) is an
actively-maintained (commits through June 2026), already-correct C
implementation of the full decode path — including the tricky CD
de-interleave logic and the V5 compressed-map Huffman/RLE decode — exposing a
small, clean API (`chd_open`/`chd_read`/`chd_get_header`) that wraps cleanly
via an SPM C target. Estimated effort to wrap it: **a few days to ~1–2
weeks**, versus multi-week for a from-scratch port. Recommendation: attempt a
local libchdr build on macOS/arm64 first (not independently confirmed in this
research pass — FreeBSD arm64 builds were confirmed, macOS specifically
wasn't) before committing to either path.

RomVault's own CHD support (native, not chdman-wrapped, via its own
`CHDSharp`/`CHDlib`) confirms this is a solved problem in the ecosystem, not
a novel one — nobody needs to reverse-engineer the format from scratch.

**Important scope note directly from RomCenter's own developer**: RomCenter
itself only ever does the same header-only SHA1 check ROMForge's
`CHDMatcher` already does — "*Romcenter gets the sha-1 from the chd
header... It doesn't calculate the full file sha-1 for chd*"
([forum post](http://www.romcenter.com/forum/viewtopic.php?t=3405)), and its
own developer flagged this as a real weakness ("*it is very easy to create a
fake chd by changing the header*"). So ROMForge's current CHD verification
is **already at RomCenter's real-world level**, not behind it — full hunk
decode would be a genuine improvement *beyond* RomCenter, not just catch-up.

### Merge modes — confirmed semantics plus specific bugs to not repeat

- **Merged-set hash collisions** (same filename, different content, across a
  parent and its clone) are a real, named problem — ClrMamePro's own author
  confirmed it on the [Emulab forum](https://www.emulab.it/forum/index.php?topic=4070.0)
  and solved it with a configurable rename pattern (default
  `setname\romname`) for the colliding clone-side file. RomCenter's older
  behavior for the same case was worse — it silently deleted/overwrote one
  version until a fix made it leave duplicates un-merged instead
  ([bug thread](https://www.romcenter.com/forum/viewtopic.php?t=1789)).
  `MAMESetLayoutPlanner`/`RebuildPlanner` should have an explicit collision
  rule from day one rather than discovering this the hard way.
- **Split-set "shared with parent" matching** is (name, hash) together, not
  hash alone — inferred from ClrMamePro's own "Double ROMs" warning
  semantics (same hash, different name across parent/clone is flagged as a
  data anomaly, not silently deduplicated), though this wasn't found stated
  as an explicit one-line rule anywhere and deserves one more confirmation
  pass (e.g. against a real MAME `-listxml` `merge="..."` attribute sample)
  before being load-bearing.
- **Non-merged duplicates BIOS and device ROMs too**, not just parent/clone
  overlap — confirmed via [docs.mamedev.org](https://docs.mamedev.org/usingmame/aboutromsets.html)
  and cross-referenced community sources. Split/merged never duplicate BIOS
  into game archives; non-merged does, by definition of "fully
  self-contained."
- **Known bugs in real tools worth deliberately avoiding**: RomCenter has a
  documented bug where switching merge mode without restarting leaves a
  stale parent reference, causing every split-mode set to wrongly show
  "Incomplete" until relaunch
  ([forum thread](http://www.romcenter.com/forum/viewtopic.php?t=1364)); and
  a still-apparently-unresolved bug (MAME 0.216+) where device ROMs get
  merged into the main game file even with both rom and BIOS merge modes set
  to split
  ([forum thread](https://forum.romcenter.com/forum/viewtopic.php?t=3499)).
  Both are concrete regression-test cases worth writing before this ships in
  ROMForge, precisely because two different real tools got them wrong.
- **SabreTools distinguishes more than three merge modes** (Split, Merged,
  Full Merged, Full Non-Merged, and a proposed Device Non-Merged) — worth
  checking whether `SetMergeMode`'s three-case enum needs a 4th/5th case for
  broader DAT-ecosystem compatibility before treating it as finished.

### Fixdat — a real, concrete opportunity to exceed both tools

A fixdat is **just a normal Logiqx-shaped DAT, filtered down to only the
missing/incorrect entries** — no special fixdat header tag or marker exists
in ClrMamePro's own format ([`datfile.htm`](https://mamedev.emulab.it/clrmamepro/docs/htm/datfile.htm)).
Meanwhile **RomCenter has promised fixdat support twice in public forum
threads (2011, 2018 with a tracked issue #122) and there is no confirmation
it ever shipped** — a real, user-visible gap in a tool people actually pay
attention to. ROMForge already has everything needed to generate one: take
`AuditReport.entries` filtered to `.missing`/`.incorrect`, and re-emit them
as a minimal `DATFile`/`LogiqxDATParser`-compatible XML document via a new
`FixDatExporter`. This is a small, well-scoped, high-value feature — a
genuine "we do something RomCenter never actually delivered" win, not just
catch-up.

### Archive formats — TorrentZip is a fully-specified, implementable target

The TorrentZip spec (fetched from
[romvault.com/trrntzip_explained.pdf](https://www.romvault.com/trrntzip_explained.pdf))
pins every byte that matters for deterministic output: compression method 8
(Deflate) at zlib 1.1.3 level 9 specifically (not just "max compression" —
the exact library version, since compressed bytes must be bit-identical
across independent implementations), a fixed MAME-epoch timestamp
(1996-12-24 23:32), lowercase-sorted entry order, forward-slash paths,
empty-directory-only directory entries, and a validation checksum embedded
as the 22-byte zip comment `TORRENTZIPPED-XXXXXXXX` (CRC32 of the central
directory bytes). Achieving *byte-identical* output against the reference
zlib 1.1.3 specifically (not just "any zlib") is the one open question flagged
by the research — modern zlib versions can differ in compressed-byte output
at the same level, so this needs empirical verification, not assumption.
Neither ClrMamePro nor RomCenter natively produce TorrentZip (both need a
separate pass with a dedicated tool); RomVault does, natively, plus a newer
Zstandard-based successor "RVZstd" that's only partially publicly documented
(would need to read RomVault's `RVZstdSharp` source directly for exact
compatibility, not just its wiki). **RAR support exists in ClrMamePro** (via
shelling out to an external `rar.exe`/`unrar`, same architecture ROMForge
already uses for 7z) and is one of the few things RomVault itself doesn't
have — a possible differentiator if ROMForge ever adds it, low priority.

### Scanning performance — the mtime+size cache strategy is validated, not just assumed

RomVault's own FAQ confirms exactly the caching strategy worth building:
files are only rehashed "if they are either new or their timestamps have
changed compared to the RV cache"
([wiki.romvault.com/doku.php?id=faq](https://wiki.romvault.com/doku.php?id=faq)).
ROMForge currently rescans and rehashes everything on every Scan — for large
collections (arcade sets easily run to tens of thousands of files) this is
the single biggest real-world usability gap once CHD/software-list support
lands and collections get bigger. A persisted `(path, size, mtime) → hash`
cache, keyed per system, invalidated only when size or mtime disagree, is a
concrete, scoped, high-value piece of future work — RomVault's own custom
binary cache format was a performance/control choice specific to C#; nothing
suggests ROMForge needs anything more exotic than SQLite for the same job on
Apple platforms.

### Sidecar metadata (for a future richer "Info" panel)

Confirmed current, actively-maintained sources if ROMForge ever wants
RomCenter/ClrMamePro-style category/player-count/history enrichment:
`catver.ini` and `nplayers.ini` from progetto-SNAPS
([github.com/AntoPISA/MAME_SupportFiles](https://github.com/AntoPISA/MAME_SupportFiles),
confirmed current as of the fetched page), and `history.dat`/`history.xml`
from **Gaming-History** (formerly Arcade-History.com), which MAME's own
built-in Lua "Data" plugin consumes directly
([docs.mamedev.org/plugins/data.html](https://docs.mamedev.org/plugins/data.html)).
Some adjacent files in the same ecosystem are explicitly **defunct**
(`sysinfo.dat`, `story.dat`, per MAME's own plugin docs) — worth not
building against those. This is v2.0+ scope (metadata layer), not urgent.

### Samples — filename-only matching is a MAME/DAT limitation, not a tool choice

Confirmed independently from both ClrMamePro ("*MAME only checks the names
of the samples and not the signatures*") and RomCenter ("*Samples are
recognized by rc by their name... Anyone can have any file renamed to
whatever.wav*" — [forum post](https://www.romcenter.com/forum/viewtopic.php?t=3589)):
neither tool — nor MAME itself — has ever had checksum-level sample
verification, because MAME's own DAT data for samples carries no CRC/MD5/
SHA1 at all. ROMForge's current "presence-only, DAT-declared" `hasSamples`
flag is therefore not behind either tool — this is the ceiling, not a gap to
close. A dedicated samples DAT does exist (progetto-SNAPS' versioned
"Samples DAT") for anyone who wants name-level auditing beyond what ROMForge
does today, worth linking to rather than reimplementing.

### Multi-DAT / multi-profile workspace

Both real tools support working across many systems, differently: ClrMamePro
centers everything on a **Profiler** (a saved DAT + its own remembered
scanner/rebuilder settings, switchable, but processed one at a time — no
native concurrent multi-DAT scan); RomCenter added multi-database tabs in
v4. ROMForge's sidebar (multiple configured systems, each with its own DAT
+ folders) is already conceptually closer to RomCenter's model than
ClrMamePro's hub-and-spoke one — this is not a priority gap, more a "keep
doing what we're doing."

### Bottom line: suggested priority order for actual engineering work

1. [x] **Fixdat export** — done. `FixDatExporter` (Core) emits a normal
   Logiqx-shaped DAT containing only the missing/incorrect entries from an
   `AuditReport`, grouped by game, with the DAT's expected size/crc/md5/
   sha1 per rom. Round-trips through `LogiqxDATParser` (verified by test).
   Wired into the app as an "Export Fixdat" toolbar button next to Export
   Report. 4 tests added (90 total). Verified end to end in the real app: a
   synthetic scan with 1 correct + 1 missing rom produced a fixdat
   containing only the missing one. Caught and fixed a real bug along the
   way — the save panel's `allowedContentTypes = [.xml]` doesn't conform to
   a ".dat" filename's UTI, so it silently appended ".xml" onto the name
   (`fixDat_Test.dat.xml`) instead of respecting it; same pitfall as the
   DAT-open picker fixed earlier, same fix (drop the content-type
   restriction).
2. [x] **MAME Software List parser** — done. `SoftwareListParser` (Core,
   new) reads `hash/*.xml`/`-listsoftware` output (root `<softwarelist>`):
   `<software>` → one or more `<part>` (a physically separate cartridge/
   disk/cassette) → `<dataarea>`/`<diskarea>` → `<rom>`/`<disk>`. Roms/disks
   are flattened across all of a software's parts into one `DATGame`
   (`DATGame` has no part/interface concept — same simplification already
   applied to MAME `-listxml` machines). Deliberately lenient: unlike the
   other two parsers, a `<rom>` missing `name`/`size` (common for
   `loadflag="continue"/"reload"/"fill"` entries that describe reassembly
   rather than declaring content) is silently skipped rather than treated
   as malformed — throwing there would make nearly every real software list
   unparseable. `DATLoader` tries it as a third fallback after Logiqx and
   `-listxml` both fail; `romforge-cli` switched from calling
   `LogiqxDATParser` directly to `DATLoader.load`, so it now exercises the
   same three-dialect chain the app does. 7 tests (97 total). Verified with
   `romforge-cli` against a real software-list fixture (`pasogo — PasoGo
   cartridges (v)`, 1 game), and — once System Events' Automation
   permission (lost mid-session, unrelated to this change) was restored —
   in the real app too: "DAT: pasogo", game "taikyoku" shown Correct. The
   downstream scan pipeline (`FolderScanner`/`CollectionHasher`/
   `ROMMatcher`/`AuditReporter`) needed no changes at all since it only
   ever sees the same generic `DATFile`/`DATGame`/`DATRom` types regardless
   of source dialect, already covered by the existing suites for those
   types.
3. [x] **Wire `HeaderSkipRule` into `ROMMatcher`** — done, including the
   two follow-ups originally deferred (closed out before moving to item 4,
   per the user's explicit request to close every pending item per step).
   `HeaderSkipRule.headerLength`/`detect` refactored to take `(fileSize,
   headBytes)` instead of a full `Data`, so detection never needs to load a
   large ROM into memory. New `HeaderStrippedHash` (rule + stripped size +
   hash). `FileHasher.hash(files:)` computes both the raw hash and, when a
   rule's signature matches, a header-stripped one per file, exposed as
   `HashedFile.headerStripped`. `ROMMatcher` builds a second set of indices
   over `headerStripped` and tries both raw and stripped identity when
   matching a rom — fully backward compatible (empty when no header is
   detected, the common case). Verified end to end through the real
   compiled Core library (not just unit tests): a real iNES-headered file
   on disk matched a headerless DAT entry — `correct=1 missing=0`.
   - **Zip-entry hashing closed**: `ZipArchiveHasher.hash` now also
     detects and hashes a header-stripped identity for an archived entry
     (via a cheap first pass collecting the first 64 bytes for detection,
     then — only if a header is actually found, the rare case — a second
     extraction pass for the stripped hash). `CollectionHasher` threads
     `headerStripped` onto the `HashedFile`s it builds for zip entries.
   - **Genesis `.smd` closed**: new `GenesisSMDConverter` (Core) —
     de-interleaves the 512-byte-header + 16KB-block format (first/second
     8KB halves swapped) into the plain sequential layout a Goodgen-style
     DAT hashes, per the same RomcenterPlugins source studied earlier
     (`Goodxxx/fmt/genesis.cpp`). Wired into both `FileHasher` (loose
     `.smd` files) and `ZipArchiveHasher` (zipped `.smd` entries) as a
     separate path from the generic byte-skip rules, since deinterleaving
     reorders content rather than just trimming a header — tagged via a
     new `HeaderSkipRule.genesisSMD` case used purely as a label (its
     `headerLength` always returns 0, it's never selected by the generic
     size/magic-based `detect`).
   - 9 tests added across these two follow-ups (106 total).
4. [x] **Merge-mode rebuild wiring with the specific collision/BIOS/device
   edge cases as explicit test cases** — done. `MAMESetLayoutPlanner`
   (which already existed in Core but was unused, like `CHDMatcher` before
   it) fixed and wired into `DATLoader`'s real MAME `-listxml` conversion:
   - **Merged-set hash collision fixed**: a clone rom whose name collides
     with the parent's (or another clone's) but whose *content differs* is
     no longer silently dropped — it's namespaced as `cloneName/romName`,
     matching ClrMamePro's own documented fix for the exact bug its author
     described on the Emulab forum. A truly identical clone rom (same
     hash, with or without a `merge=` marker) is still correctly
     deduplicated, not turned into a spurious duplicate.
   - **Split mode fixed to respect `merge="..."`**: `DATRom.mergeName`
     (new field, parsed from MAME `-listxml`'s `merge` attribute) marks a
     clone rom as identical to one already in its parent/BIOS archive.
     Split-mode layout now excludes those roms rather than returning every
     rom a machine happens to declare. **This was a real, live audit-
     correctness bug**, not just an unwired capability: `DATLoader`'s MAME
     conversion previously handed every declared rom straight through
     unfiltered, so scanning a real split-organized MAME collection (the
     most common convention) would wrongly report a clone's
     parent-inherited files as "missing" even when they were correctly
     present only in the parent archive. Fixed by routing every machine
     through `MAMESetLayoutPlanner.buildGame(..., mode: .split, ...)`
     during conversion (ROMForge has no per-system merge-mode setting yet,
     so `.split` — the most common real-world convention — is the default).
   - **Non-merged fixed to include device roms**: previously only the
     BIOS/parent (`romof`) chain was included; a machine depending on a
     shared device (`device_ref`, e.g. a CPU/sound sub-board) wasn't
     actually self-contained. Now recursively resolved.
   - 4 tests added to `MAMESetLayoutPlannerTests` (one per fix above,
     named after the real bug each guards against), 1 to
     `MAMEListXMLParserTests` (parses `merge=`), 1 integration test in
     `DATLoaderTests` proving the split-mode fix applies through the real
     `DATLoader.load()` path end to end. 110 tests total.
   - Verified in the real app with a from-scratch fixture mirroring the
     exact bug scenario: a parent (`shared.bin`) and a clone declaring both
     its own unique rom and a `merge="shared.bin"`-marked inherited rom,
     with only the parent's and the clone's *own* files on disk (no
     duplicate of `shared.bin` in the clone's expected set). Result:
     `Correct: 2, Missing: 0, Surplus: 0` — the clone correctly didn't
     demand `shared.bin` for itself.
5. [x] **Scan cache (mtime+size → hash)** — done, validated against
   RomVault's own documented strategy ("only rehash if new or timestamps
   changed"). New `ScanCache` (Core): a `[path: (size, mtime) → hash]`
   JSON-persisted map. `ScannedFile` gained a `modificationDate` field
   (from `FolderScanner`'s existing directory walk — nearly free, it's
   already stat-ing each file for size). `FileHasher.hash(files:cache:)`
   and `CollectionHasher.hash(scannedFiles:cache:)` both serve a cached
   `HashedFile` when a file's current size+mtime match what's on record,
   skipping the hash (and, for zip entries, the extraction) entirely — a
   zip entry's cache key/validity is derived from the *containing
   archive's* mtime, since an entry has none of its own. The app persists
   one cache file per configured system (`ScanCacheLocation`, alongside
   `systems.json`), loaded before a scan and rebuilt/saved after — removing
   a system also removes its now-orphaned cache file. 6 tests added (116
   total). **Verified end to end in the real app** with a methodology that
   actually proves cache usage rather than just exercising the code path:
   corrupted a ROM's on-disk content while preserving its exact (including
   sub-second) mtime and size via `os.utime` — rescanning still reported
   `Correct: 1`, proving the stale cached hash was served instead of the
   file being re-read. Then touched the same file's mtime (content still
   corrupted) and rescanned again — this time it correctly flipped to
   `Missing: 1, Surplus: 1`, proving the cache invalidates properly the
   moment mtime changes. (An earlier attempt using `touch -t`, which only
   sets whole-second precision, produced a false "cache didn't work"
   result — worth remembering: APFS mtimes carry sub-second precision, and
   `touch -t` alone isn't a faithful way to "preserve" one for a test.)
6. [~] **CHD hunk decode** — updated 2026-08-05 after re-auditing actual
   code state against this section's own (partly stale) claims. Zlib,
   LZMA, both CD-composite variants (`cdzl`/`cdlz`), and now the plain
   (non-CD) `huff` codec are all real, working, and actually wired into
   `CHDHunkReader`'s own dispatch (`decompressTaggedSlot`, below) — not
   "not attempted" as an earlier draft of this section said. Only
   `flac`/`cdfl` remain genuinely unimplemented. Ported directly from
   MAME's own source rather
   than wrapping `libchdr` (no Homebrew `libchdr` formula exists at all —
   confirmed again 2026-08-05, `brew search` finds nothing named `libchdr`;
   porting the algorithm directly has no C-library runtime dependency risk
   across machines).

   **What's real and tested — the full chain, tied together and exercised
   end to end**:
   - `CHDBitReader` — exact port of `bitstream_in`'s MSB-first bit-level
     peek/read/remove.
   - `CHDMapHuffmanDecoder` — exact port of `huffman_decoder<16, 8>`'s
     `import_tree_rle`/`assign_canonical_codes`/`build_lookup_table`/
     `decode_one` (only the read-side operations; histogram-based tree
     construction and the huffman-encoded-tree path only matter for
     *writing* a CHD, so weren't ported).
   - `CHDV5MapReader` — exact port of `decompress_v5_map()`'s two-pass
     per-hunk reconstruction (RLE-token expansion, then each hunk's own
     length/offset/CRC16 or self/parent resolution, including every
     pseudo-type fallthrough: `SELF_0`/`SELF_1`/`PARENT_SELF`/
     `PARENT_0`/`PARENT_1`). Its decoded map is now verified against the
     format's own `mapcrc` field via `CHDCRC16` (below) when the caller
     supplies it — a real integrity check, not a TODO.
   - `CHDCRC16` — exact port of MAME's `util::crc16_creator` (table,
     init `0xffff`, poly `0x1021`, no reflection/final-xor). Confirmed to
     be the standard CRC-16/CCITT-FALSE variant against its published
     check value (`0x29b1` for `"123456789"`) — a genuine external
     reference, not a self-consistency check.
   - `CHDZlibDecompressor` — CHD's zlib codec confirmed from real MAME
     source (`chdcodec.cpp`) to use **raw DEFLATE**
     (`deflateInit2(..., -MAX_WBITS, ...)` — no zlib header/trailer/
     Adler32), implemented via a new `CZlib` SPM system-library target
     wrapping macOS's always-present `libz`/`zlib.h` (no Homebrew/vendored
     dependency). Tested against a real, independently-generated raw-deflate
     buffer (Python's `zlib.compressobj(9, zlib.DEFLATED, -15)`), not a
     round-trip against our own compressor.
   - `CHDLZMADecompressor` (added 2026-07-30) — MAME's specific
     `LZMA_FILTER_LZMA1EXT` raw-stream framing (no end marker, `dictSize`/
     `lc`=3/`lp`=0/`pb`=2 recomputed exactly like MAME's own encoder), via
     the `CLZMA` SPM system-library target wrapping Homebrew's `xz`
     (liblzma isn't system-provided on macOS — a real, documented external
     dependency, unlike zlib). Tested against a payload independently
     encoded via liblzma's own raw encode API inside the test itself, plus
     the decompressor's own doc comment records empirical confirmation
     against a real CHD hunk on the day it was written.
   - `CHDCDCompositeDecompressor` (added 2026-07-30) — MAME's CD-composite
     framing (`cdzl`/`cdlz`): de-interleaves 2352-byte sectors into
     2048-byte data + ECC/subcode, decompresses the data portion with
     whichever base codec the tag names (`.zlib`/`.lzma`), then
     reconstructs each sector's ECC via `CDSectorECC`. This is the codec
     MAME actually uses in real CPS3 CD-based CHDs — confirmed against a
     real CHD's hunks reporting only `cdlz`/`cdzl`, never plain `lzma`/`zlib`
     or `cdfl`.
   - `CHDHuffmanTreeDecoder`/`CHDHuffmanDecompressor` (added 2026-08-05) —
     the plain (non-CD) `huff` hunk-body codec, `huffman_8bit_decoder` =
     `huffman_decoder<256, 16>` in MAME's own terms. `CHDHuffmanTreeDecoder`
     generalizes the map decoder's engine to arbitrary `numCodes`/`maxBits`
     and adds `import_tree_huffman` (a nested `huffman_decoder<24, 6>`
     decodes the main tree's own code lengths — genuinely different framing
     from the map's `import_tree_rle`), ported verbatim from MAME's real
     `huffman_context_base::import_tree_huffman` source. Verified against a
     hand-built bitstream tracing that exact wire format bit-by-bit, not a
     round-trip against our own encoder.
   - `CHDHeader` gained `mapOffset` (previously unread, needed to actually
     locate the map instead of only verifying the file's declared
     identity).
   - `CHDHunkReader` (new) — the tie-together piece: opens a real CHD v5
     file, reads its map via `CHDHeaderReader` + `CHDV5MapReader` (with
     `mapcrc` verification), and decompresses individual hunks on demand
     for `COMPRESSION_NONE` (raw copy), `COMPRESSION_SELF` (recursive
     lookup, cached), and `COMPRESSION_PARENT` (resolves against another
     `CHDHunkReader` passed in as `parent:` — see its own test below for
     current coverage). For a "tagged slot" compression type
     (`COMPRESSION_TYPE_0`-`3`), `decompressTaggedSlot` resolves the CHD's
     own per-slot codec FourCC (`header.compressorTags`, since two
     different CHDs can use the same slot number for different codecs) and
     dispatches to `CHDZlibDecompressor` (`zlib`), `CHDLZMADecompressor`
     (`lzma`), or `CHDCDCompositeDecompressor` (`cdzl`/`cdlz`) accordingly
     — all four tags are real, wired, and tested (see each decompressor's
     own section below). Only `flac`/`cdfl` remain unsupported
     (`CHDHunkReaderError.unsupportedCodec`, explicit and reported, never
     silently wrong).
   - **End-to-end test**: since no real CHD file exists here to test
     against, hand-assembled a complete, byte-accurate synthetic CHD v5
     file — real 124-byte header, real 16-byte map header, a real
     Huffman-compressed map (same provably-valid uniform-tree construction
     as the map-reader tests), and the same independently-verified
     raw-deflate fixture as the zlib test — and confirmed `CHDHunkReader`
     correctly reads back a `NONE` hunk, a zlib hunk, and a `SELF` hunk
     that resolves to the `NONE` hunk's content. This proves the pieces
     work together on a self-consistent file; it is not a substitute for
     validating against an authentic chdman-produced CHD.
   - 125 tests total (Core package), all passing; the Xcode app project
     was rebuilt after adding the `CZlib` system-library target to confirm
     it doesn't break the app target — it builds clean.

   **What remains — genuinely environment-blocked, not merely deferred**:
   - **Corrected 2026-08-05** — this bullet used to claim no real CHD file
     was ever available to validate against; that stopped being true once
     the user's own real MAME collection became reachable in-session
     (`CHDLZMADecompressor.swift`'s own doc comment records empirically
     debugging the `LZMA1EXT` framing choice against a real CHD hunk on
     2026-07-30, and `CHDCDCompositeDecompressor`'s notes it confirmed
     `cdlz`/`cdzl` are the only tags a real CPS3 CHD's hunks actually use).
     The automated test suite itself still only exercises hand-built/
     independently-generated *synthetic* fixtures, not a full real CHD end
     to end — that specific gap is real, just narrower than originally
     stated; no `libchdr`/`chdman` Homebrew formula exists either way, so
     ROMForge's own port remains the only path regardless.
   - **MAME's own Huffman codec for hunk bodies (`huff` tag) — closed
     2026-08-05.** `CHDHuffmanTreeDecoder` generalizes the map decoder's own
     engine (numCodes/maxBits as parameters instead of the map's hardcoded
     16/8) and adds `import_tree_huffman` — a genuinely different tree
     format from the map's `import_tree_rle`: a nested `huffman_decoder<24,
     6>` first decodes the *lengths* of the real, 256-symbol main tree
     (`huffman_8bit_decoder` = `huffman_decoder<256, 16>`), traced verbatim
     from MAME's real `huffman_context_base::import_tree_huffman`/
     `huffman_8bit_decoder::decode()` source. `CHDHuffmanDecompressor`
     wires it into `CHDHunkReader`'s tagged-slot dispatch. Verified against
     a real bitstream hand-built bit-by-bit per the exact wire format
     (`CHDHuffmanDecompressorTests`, a uniform 256-symbol/8-bit-code tree —
     not generated by running the decoder backwards).
   - **FLAC hunk bodies** (`flac`/`cdfl` tags) — genuinely unimplemented,
     but *not* environment-blocked the way this bullet previously claimed:
     `flac` (1.5.0) is actually installed via Homebrew on this machine, and
     the `CFLAC` SPM system-library target is already declared in
     `Package.swift` (built but unused so far). What's actually blocking
     `cdfl` specifically is that MAME's own CD-FLAC framing
     (`chd_cd_flac_decompressor`) isn't a standard container libFLAC's
     public API reads directly — real work, not a missing dependency. None
     of a real CPS3 CHD's hunks used this slot in practice (only
     `cdlz`/`cdzl` did), so it's lower real-world priority even once built.
   - LZMA hunk bodies and CD-composite codecs (`cdzl`/`cdlz`) — see their
     own descriptions above; this line intentionally left as a marker that
     they're no longer "what remains" as of 2026-08-05, not removed
     outright, so a diff against an older version of this file shows
     exactly what changed.
   - **`COMPRESSION_PARENT` test coverage — closed 2026-08-05**:
     `CHDHunkReaderTests.readsParentHunkThroughRealParentReader()` builds
     two complete synthetic CHD v5 files (a parent with a real `NONE` hunk,
     a child whose only hunk is `COMPRESSION_PARENT`) and confirms the
     child's `CHDHunkReader`, given the parent's own reader via `parent:`,
     resolves and returns the parent's hunk content end to end — the one
     flow nothing exercised before (only the map-decoder's own pointer
     arithmetic was covered, never a real child-reads-from-parent read).
   - **Not wired into `CHDMatcher`/the scan pipeline** — `CHDMatcher` itself
     (header-SHA1-only comparison) WAS wired in on 2026-07-30, and is what
     every real CHD audit in the app actually uses today; this note is
     specifically about `CHDHunkReader`'s own hunk *decompression*, a
     different, unwired capability. Still a standalone, independently-
     tested capability, same as `HeaderSkipRule` was before its own wiring
     pass. Wiring it in would mean deciding what ROMForge actually *does*
     with decoded hunk content (verification-only audit vs.
     extraction/rebuild), which is a product decision beyond this step's
     scope — and, per this file's own CHD research above, arguably
     unnecessary: RomCenter itself never verifies past the header either.
   - **Real bug found live and fixed 2026-08-05: liblzma was a hard launch
     dependency for the whole app, with no detection or message at all.**
     `CLZMA`'s modulemap used to `link "lzma"` unconditionally — `otool -L`
     on the built app confirmed an absolute, unconditional `LC_LOAD_DYLIB`
     on `/opt/homebrew/opt/xz/lib/liblzma.5.dylib`, regardless of whether
     any CHD file was ever scanned. Missing that one exact file (no
     Homebrew, a different prefix, an Intel Mac with Homebrew at
     `/usr/local`, `xz` simply never installed) crashed the *entire app* at
     launch with a dyld error, before any ROMForge code could report
     anything. Fixed by removing the `link` directive and resolving the one
     real function `CHDLZMADecompressor` calls
     (`lzma_raw_buffer_decode`/`lzma_raw_buffer_encode` in its own test)
     via `dlopen`/`dlsym` at runtime instead (`HomebrewDylibLoader`,
     `HomebrewLibraryDependency`) — the app now always launches, and
     `ContentView` checks proactively on appear, showing a clear alert with
     exact `brew install xz` instructions if it's missing, instead of
     either crashing or failing silently mid-scan. Verified live both ways
     (temporarily pointing the dependency at a nonexistent dylib name to
     confirm the alert renders correctly, then restoring the real one and
     confirming no alert and `otool -L` shows no more liblzma reference at
     all).
7. [x] **TorrentZip writer** — `TorrentZipWriter` (Core), producing archives
   that conform to the real TorrentZip standard (spec fetched and read from
   wiki.romvault.com/doku.php?id=torrentzip, itself a mirror of the
   original SourceForge `trrntzip` README, rather than guessed): every
   structural byte a TorrentZip-consuming tool checks is fixed —
   fixed DOS timestamp (12/24/1996 11:32 PM, MAME's first-release date),
   general-purpose flag `2` (`0x800` added only for non-ASCII names),
   compression method always `8`/deflate (even zero-byte entries — a real
   spec quirk, not an oversight), entries sorted by lowercased filename
   after normalizing `\` to `/`, redundant directory entries (implied by a
   file already under them) dropped while genuinely empty ones are kept,
   and the EOCD comment set to `TORRENTZIPPED-` + the uppercase-hex CRC32
   of the central directory bytes.
   - New `DeflateCompressor` (raw DEFLATE via the same `CZlib` system-library
     target added for `CHDZlibDecompressor` — no new dependency) and
     `TorrentZipWriter`/`TorrentZipEntry`.
   - Reused the existing `CRC32` (already in Core, used for DAT/rom
     verification) for both per-entry and central-directory checksums.
   - 5 tests, verified against a genuinely independent implementation: the
     project's existing `ZIPFoundation` dependency (already used elsewhere
     to *read* zips) opens, lists, and extracts a written archive
     correctly — not just this project's own code checking its own output.
     Additional tests confirm the fixed timestamp/flags/method by reading
     raw header bytes, the EOCD comment's CRC32 against an independently
     recomputed value, duplicate-name rejection, and redundant-directory
     filtering. 130 tests total (Core); Xcode app project rebuilt clean.
   - **Honest limitation, not glossed over**: the spec's own reference
     requirement is "compressed exactly as zlib version 1.1.3 at level 9".
     This uses macOS's current system `libz` (whatever version Apple
     ships), which produces valid, spec-conforming DEFLATE but is not
     guaranteed to be byte-for-bit identical to that specific old zlib
     release for the same input. So a file written here is structurally a
     correct TorrentZip (fixed dates/flags/order/comment, decompresses
     correctly, opens in any zip tool) but isn't guaranteed to be the exact
     same bytes a real `trrntzip`/RomVault-produced file would be for the
     same content. Closing that gap would mean vendoring zlib 1.1.3 itself,
     which this project has deliberately avoided elsewhere (see `CZlib`'s
     reliance on the system library instead of a pinned vendored version).
   - **Not wired into any rebuild/export feature** — ROMForge has no
     rebuild/write action yet (the app is still read-only,
     `LibraryViewModel.modificationsEnabled = false`); this is a standalone,
     tested Core capability waiting for that feature, same pattern as
     `CHDHunkReader`/`HeaderSkipRule` before their own wiring passes.

All 7 items above are now implemented (see each item's own notes for exact
scope and honest remaining gaps) — this section remains as the research
record that justified the order they were built in, not a "not started yet"
disclaimer.

### GUI polish pass (2026-07-21) — informed by reviewing an external, unrelated prototype

The user shared a separate C#/.NET 9 + Avalonia + SQLite prototype
("RomManager", an early uncompiled scaffold from a different chat session)
for comparison. No code was ported — different language/platform entirely —
but its design ideas were checked against ROMForge's actual current GUI/Core
state (audited first, not assumed) and 6 concretely-scoped items were
approved and implemented:

1. **Worst-status aggregation as reusable Core API**: `AuditStatus.worst(among:)`
   and `AuditReport.worstStatus` (missing > incorrect > correct/surplus) —
   the game tree's own aggregation (previously a private, duplicated helper
   in `LibraryDetailView`) now calls this shared helper; a badge showing the
   whole system's worst status appears next to the DAT header.
2. **Persisted last-scan status per system** (`SystemStatusStore`, same
   per-system-JSON pattern as `ScanCacheLocation`): a colored dot per system
   in the sidebar, without eagerly rescanning every configured system just
   to populate the list. Verified live through a real Add System → Scan →
   quit → relaunch cycle — the dot survives correctly. Known, accepted
   limitation: doesn't live-update within the same session without
   navigating away and back (SwiftUI doesn't re-evaluate a sidebar row when
   an unrelated view saves a file to disk) — not fixed, since forcing that
   reactivity isn't worth the added coupling for a cosmetic staleness
   window this small.
3. **Real scan progress**: new `ScanProgress`/`ScanProgressCounter` (Core) —
   a thread-safe, throttled (~200 updates max) completed/total counter
   shared across `FileHasher`'s concurrent workers and
   `CollectionHasher`'s zip-entry hashing, replacing the bare spinner with
   an actual progress bar + "Hashing N of M files…". Folder enumeration
   itself stays an indeterminate spinner — fast enough not to need its own
   granular progress.
4. **Persistent log panel**: `LibraryViewModel` collects timestamped log
   lines (scan start/done-with-counts/failure), shown in a new scrolling
   panel beside the ROM detail pane.
5. **XXE hardening + zip-bomb guard**: `LogiqxDATParser`/`MAMEListXMLParser`/
   `SoftwareListParser` now explicitly set `shouldResolveExternalEntities =
   false`/`externalEntityResolvingPolicy = .never` on their `XMLParser`
   (Foundation already defaulted to this — now explicit, not implicit).
   `ZipArchiveHasher` aborts (`ZipArchiveError.suspectedZipBomb`) if an
   entry's real decompressed size exceeds its own declared (attacker-
   controlled) size by more than 10x — not a fixed absolute cap, since real
   ROM/CD dumps can legitimately be many GB.
6. **Zip-entry hashing parallelized**: `CollectionHasher` hashed zip entries
   serially even though loose files were already concurrent; now uses the
   same bounded `TaskGroup` pattern as `FileHasher` (each
   `ZipArchiveHasher.hash` call reopens its own `Archive` handle, so
   parallel decompression across — or within — zips is safe).

137 tests total (Core, up from 130); Xcode app project rebuilt clean and the
full flow manually exercised in the real running app (Add System → DAT
auto-load → Scan → progress bar → log panel → status badge → game/rom
selection → detail pane).

**Update (2026-07-21, approved)**: the deferred item above — SQLite
persistence — is now implemented. New `AuditReportDatabase` (Core), using
Darwin's built-in `SQLite3` module directly (no Homebrew/vendored
dependency, `import SQLite3` just works via the system's own module map —
verified before committing to this approach, not assumed). One shared
`romforge.sqlite3` per app (`AuditDatabaseLocation`, App layer), schema-
versioned (`schema_version` table, same migration pattern as the C#
prototype's own `SqliteRepository` — a genuinely good idea worth keeping)
with two tables: `scans` (one row per system: DAT name/version, scanned-at)
and `audit_entries` (every `AuditEntry` from the last real scan, keyed by
system id). `LibraryViewModel.loadPersistedReport(system:)` loads this on
`LibraryDetailView.onAppear`, so opening a previously-scanned system shows
its full last results (games list, roms list, status counts, DAT header)
immediately — no more empty view until the user hits Scan again. A real
Scan always re-derives the truth from disk and overwrites the persisted
row (transactional: delete-then-insert, not merge). Retired the earlier
per-system `SystemStatusStore` JSON files entirely — the sidebar's status
dot (`ContentView`) now reads `AuditReportDatabase` too, so there's one
persistence mechanism for this, not two. 6 new Core tests (round-trip with
nils/special fields, never-scanned-returns-nil, replace-not-append,
`removeSystem`, cross-system isolation, persists-across-reopens) — 143
tests total. Verified live in the real app: Add System → Scan → quit →
relaunch shows the full persisted report immediately, without touching
Scan.

## v0.1 — Core audit pipeline

- [x] DAT module: read Logiqx/ClrMamePro XML, validate structure, build the
      in-memory model.
- [x] Scanner: walk folders, read loose files.
- [x] Hash: CRC32, MD5, SHA1.
- [x] Matcher: compare scanned ROMs against the DAT (name, size, hashes).
- [x] Reports: correct / incorrect / missing / surplus.

## v0.2 — Repair

- [x] Automatic renaming.
- [x] Move / copy files.

## v0.3 — Archives and duplicates

- [x] ZIP scanning and rebuilding.
- [x] Set reconstruction (pack matched ROMs into per-game ZIPs).
- [x] Duplicate detection.

## v0.4 — Arcade support

- [x] 7z (via the system's `7zz`/`7z` — not bundled; ROMForge detects it and
      tells the user how to install it with Homebrew if missing).
- [x] CHD — scoped to identification and verification, not full
      decoding/rebuilding: `CHDHeaderReader` parses the v5 header (124
      bytes, big-endian, offsets verified against MAME's own
      `src/lib/util/chd.h`/`chd.cpp`) and `CHDMatcher` compares its stored
      `sha1` field directly against a `<disk sha1="...">` from the MAME
      DAT — exactly what clrmamepro/RomVault do, since CHD already computes
      and stores that hash, so verification never needs to decompress a
      hunk. Decoding hunk *content* (for extraction/rebuilding a CHD itself)
      remains a separate future milestone — the chunked, multi-codec body
      (zlib/LZMA/Huffman/FLAC) is real decoder work distinct from reading
      the header.
- [x] Parent/clone sets.
- [x] BIOS handling.
- [x] MAME `-listxml` parser (superset of Logiqx: `biosset`, `romof`/`cloneof`,
      `device_ref`, `disk`).

## v0.5 — Set variants

- [x] Merged / split / non-merged sets.

## v1.0

- [x] Core pipeline wired into a working SwiftUI app: pick a DAT, pick a ROM
      folder, Scan (parses DAT → scans folder → hashes → matches → reports),
      Fix (repairs misnamed files in place, then rescans), Export Report
      (CSV). Verified end to end against a real fixture (correct/renamed/
      missing/surplus all classified correctly, Fix renamed the file on
      disk). Matches the original wireframe (DAT name, folder picker, status
      counts, Scan/Fix/Export).
- [x] Systems sidebar: add/remove configured systems (name + DAT + ROM
      folder), persisted as JSON in Application Support, `NavigationSplitView`
      with a per-system detail pane. Verified end to end (add, scan,
      relaunch — persistence confirmed).
- [x] Detail pane: selecting a row shows name, game, DAT, path, and
      expected-vs-actual CRC32/MD5/SHA1. Verified end to end (selected row
      highlighted, all three hashes displayed and matching).
- [x] Region/Language columns: `GameNameTagParser` reads the No-Intro/TOSEC
      parenthesized-tag convention (e.g. "Final Fantasy VII (Europe)
      (En,Fr,De,Es,It)") since these aren't structured DAT fields. Verified
      end to end **for No-Intro/TOSEC-style DATs only**. A MAME `-listxml`
      DAT's machine short names (e.g. `mslug`, `wh2j`) never carry this
      convention and have no structured region/language field either — real
      MAME scans correctly show nothing here, not a bug, just a source the
      DAT format doesn't provide (2026-07-21, found while testing against a
      real MAME 0.288 DAT).
- [x] Multiple ROM folders per system: a single DAT can be matched against
      several folders at once (splitting a collection across drives/region
      subfolders is common). `FolderScanner.scan(folders:)` concatenates
      them; the Add System sheet has an add/remove folder list instead of a
      single picker. Old single-folder `systems.json` entries still load
      (decoded as a one-folder list). Verified end to end: two folders, one
      DAT, correct/incorrect classified right, Fix renamed the file in the
      folder it actually lived in.
- [ ] CHD support, as its own milestone (deferred from v0.4) — full
      hunk-content verification/extraction, distinct from the categorization
      below.
- [x] Sample and bad-dump *categorization* (not verification): both DAT
      parsers now read `<disk>` (already parsed for MAME, now also read by
      `LogiqxDATParser`), `<sample>`, and a rom's `status="baddump"`/
      `"nodump"` attribute. Threaded through `DATGame.disks`/`hasSamples`
      and `DATRom.status` → `AuditEntry.hasCHD`/`hasSamples`/`isBadDump`.
      This only tells the app what the DAT *declares* — it does not check
      whether a `.chd` file exists, verify its hash, or check for sample
      files on disk (that remains the CHD milestone above, plus a
      not-yet-planned sample-verification one). 79 tests.
- [x] View-only mode: repairing (renaming) is disabled behind a single
      switch (`LibraryViewModel.modificationsEnabled = false`) at the
      user's request — Fix is disabled in the UI with a visible notice.
      Flip the switch back to re-enable.
- [x] Filterable status labels: clicking Correct/Incorrect/Missing/Surplus
      filters the tree to just that status (click again to clear).
- [x] RomCenter-style tree, both requested levels: (1) clone sets nest
      under their parent game in the results tree instead of a flat list
      (`AuditEntry.cloneOf`, from the DAT's `cloneof`/`romof`); (2) the
      sidebar groups systems into categories (`RomSystem.category`,
      optional, set when adding a system) instead of one flat list.
      Verified end to end (parent/clone nesting, category grouping,
      filtering — all in the real app).
- [x] RomCenter-style two-pane layout: a left "Games" list (parent/clone
      tree) and a right-hand pane showing the ROM files of whichever game
      is selected, replacing the earlier single combined tree — adapted to
      native macOS (`HSplitView`) instead of copying RomCenter's Windows
      chrome. The filterable status labels were kept as-is. Verified end to
      end with a synthetic DAT.
- [x] "Database" category tree (leftmost pane), copying RomCenter's own
      left-hand panel: All games / Originals / Clones / Bios files, plus
      (once the DAT-property plumbing above landed) Games with CHD / Games
      with samples / Games with bad dumps — all 7 of RomCenter's original
      categories. Combines with the status filters. Verified end to end
      with a synthetic DAT (parent/clone set); the CHD/samples/bad-dumps
      categories are presence-only per the note above, not yet audited
      against what's actually on disk.
- [x] ROM table polish to match RomCenter's own file list more closely:
      separate File name / Rom name columns, added Size and Crc/SHA-1
      columns, per-row status color tinting across the whole row (not just
      the icon). "Merge" checkbox intentionally omitted — it implies
      merge-set rebuilding, out of scope while view-only mode is on.
- [x] `HeaderSkipRule` (Core, detection primitive only — NOT wired into
      `ROMMatcher` yet): studied RomCenter's own signature-plugin sources
      (github.com/ebolefeysot/RomcenterPlugins, GPL-3.0, `Goodxxx/fmt/*.cpp`)
      to get the exact header conventions clrmamepro/RomCenter/Goodxxx tools
      already agree on — iNES (16 bytes, `NES\x1A` magic), Lynx (64 bytes,
      `LYNX` magic), and the shared 512-byte "copier header" used by SNES/
      Game Boy/PC Engine/Master System dumps (detected by file size:
      `size % 1024 == 512`, no magic). 7 tests. **Not wired into the app or
      the matcher**: right now a headered local dump still won't match a
      headerless DAT entry, because `ROMMatcher` only ever hashes/compares
      the whole file. Wiring this in means `FileHasher`/`HashedFile` also
      producing a header-stripped hash+size per file and `ROMMatcher`
      indexing by both — real plumbing, deliberately deferred rather than
      rushed. Genesis's interleaved `.smd` format (a byte deinterleave, not
      just a header skip) and rarer formats (Atari 7800, PSID, FDS) from the
      same plugin collection were left out of this pass too.

## v2.0+ — Library features

- [ ] Metadata scraping (covers, screenshots, descriptions) — visually rich
      per-game presentation inspired by
      [Batocera.linux](https://github.com/batocera-linux/batocera.linux)'s
      game list (box art, screenshots, synopsis, genre, players).
- [ ] Local SQLite/SwiftData catalog: System / Game / Rom, split into a
      catalog layer (from the DAT) and a local collection layer (user's
      files, verification state, enriched metadata).
- [ ] Favorites, collections, history.
- [ ] Multi-system support: arcade, consoles, handhelds and computer systems
      (same scope as the DAT/MAME modules — one DAT profile per system).

**Explicitly out of scope**: ROMForge is not, and will not become, a ROM
launcher/frontend like Batocera, RetroBat, EmulationStation or LaunchBox. No
emulator launching, no controller/gamepad UI, no "play" button. The scope
stops at managing, auditing and presenting the collection — running games is
left entirely to the user's own emulators.

## Fase 2 — rebuild/repair (not started, read-only mode active until this)

Research pass (2026-08-19) comparing ROMForge against RomCenter, ClrMamePro,
RomVault, and Igir specifically for **write** capabilities — everything here
requires modifying/moving/renaming a user's actual ROM files, which is why
none of it starts before the read-only phase (see `LibraryViewModel
.modificationsEnabled`) is retired. Ordered roughly by dependency, not
priority — each later item builds on the one before it.

### ClrMamePro's own "Fix" preferences panel (screenshot review, 2026-08-20)

The user shared a screenshot of ClrMamePro's Preferences → Fix tab.
**Decision: once fase 2 starts, these settings get their own tab in
ROMForge's Settings window, named "Fix" or "Fix Preferences"** (parallel
to the existing General/Romsets/Emulators/Releases-style tabs ClrMamePro
uses) — not folded into an existing tab, not a one-off sheet. Each item
below records what actually has to be built to make it real, not just the
UI checkbox.

**Fix parameters:**
- [ ] **Test archives** — run `ZipIntegrityAuditor` (already implemented,
      today on-demand only) automatically as a Fix pre-pass. Needs: a
      toggle in the new Fix tab; wiring so the Fix action, when enabled,
      calls the existing auditor before doing anything else and folds its
      findings into the same "corrupted files" policy below. No new
      detection logic — this is pure orchestration of what already exists.
- [ ] **Rename files** (archive-level) — needs a real filesystem rename
      operation (`FileManager.moveItem`) for the outer archive to match
      the DAT's declared name, gated by the not-yet-built write-permission
      layer (`modificationsEnabled`). Straightforward once that gate
      exists; no new detection needed since "misnamed" is already known
      from fase 1's `.incorrect`/case-mismatch data.
- [ ] **Rename roms** (entry-level, inside an archive) — harder: requires
      rewriting a ZIP's central directory/entry name in place (or a
      full extract-rename-repack round trip) rather than a simple
      filesystem rename. Builds directly on the TorrentZip writer's
      existing low-level ZIP-writing code.
- [ ] **Remove useless files / Remove useless roms** — delete an
      archive/entry the DAT doesn't recognize at all (today's "surplus"
      status already identifies exactly these). Needs: the actual
      delete operation, PLUS its own explicit confirmation dialog
      distinct from any other Fix step — this is the most destructive
      item on the whole list and must never be bundled silently into a
      general "Fix everything" action.
- [ ] **Find missing roms** — before reporting a ROM as missing, search
      one or more user-configured "scavenging" folders (separate from the
      system's own configured ROM folders) for a same-hash file and pull
      it in. Needs: a new per-system or global setting for scavenging
      folder paths (new UI, new persisted preference), plus matching logic
      that's mostly a variant of the existing `ROMMatcher` hash lookup
      pointed at a different folder set. Same underlying need as the
      already-documented "rebuild from external scavenging folders" item
      further down this roadmap — implement once, expose in both places.
- [ ] **Create dummy roms / Create ghost games** — generate placeholder
      files/entries so a frontend's game list stays visually complete.
      Needs: deciding on a placeholder file format/size convention (no
      existing precedent to copy from ROMForge's own code). **Low
      priority** — conflicts with [[feedback_romforge_mame_first]] and the
      "never a launcher" scope decision in [[project_romforge]]; only
      worth building if a concrete future need appears, not speculatively.
- [ ] **Fix samples** — blocked entirely on the missing sample-scanning
      infrastructure already noted in [[project_romforge]]'s Samples
      pending item (no physical sample file inventory exists yet to fix
      against). Cannot start before that infrastructure exists.
- [ ] **Remove zip comments** — mechanical: locate and clear the ZIP end-
      of-central-directory comment field. Needs a small addition to the
      binary ZIP writer path already built for TorrentZip — no new
      detection, no new UI beyond the toggle itself.
- [ ] **Unzip and rezip** — force every archive in a system through a full
      extract + rewrite via the TorrentZip writer, even when nothing else
      about the archive is wrong. Needs: a batch-mode entry point into the
      existing rebuild/TorrentZip code that runs unconditionally per
      archive rather than only on detected problems, plus progress
      reporting for a potentially large sweep (reuse the existing scan-
      progress infra).
- [ ] **Allow multiple rom formats** — don't force one output archive
      format (zip only) when rebuilding/fixing. Needs: fase 2's rebuild
      engine to support at least one alternative container before this
      toggle means anything — currently there is only one write path
      (zip via TorrentZip), so this setting has nothing to select between
      yet. Depends on decisions not yet made about which other formats
      (7z? raw loose files?) fase 2 will actually write.
- [ ] **Number of threads** — a user-facing concurrency slider for the Fix
      pass specifically. Needs: exposing whatever concurrency primitive
      the eventual Fix engine uses (likely mirroring
      `HashingConcurrency.workerCount()`'s existing pattern) as a
      persisted, user-overridable setting instead of an internal-only
      constant — small once the Fix engine itself exists, meaningless
      before it does.

**Corrupted files — three-way policy, not just detect-and-report:**
- [ ] **Don't touch / Delete / Move to (a configured folder)** — fase 1
      only *detects* corruption today (`ZipIntegrityAuditor`, filename CRC
      mismatch flags); nothing acts on that finding. Needs: a new
      persisted enum setting (`.dontTouch`/`.delete`/`.moveTo(URL)`), a
      folder picker UI for the "Move to" case (same `NSOpenPanel` pattern
      already used elsewhere, directory-selection mode), and the actual
      file-move/delete operation wired to run whenever a Fix pass
      encounters a confirmed-bad file. Recommend defaulting the setting to
      "Move to" (quarantine) rather than "Delete" — reversible by default,
      matching this project's general caution around destructive actions.
- [ ] Also needs its own confirmation gate before the FIRST time a user
      enables "Delete" specifically (mirrors the destructive-action
      pattern already flagged for "Remove useless files/roms" above).

**Sets case / Roms case — independent policies:**
- [ ] **Don't touch / Uppercase / Lowercase / Datafile case**, applied
      separately to archive-level names ("Sets case") and entry-level
      names inside an archive ("Roms case"). Needs: two independent
      persisted enum settings; the actual case-conversion + rename
      operation (reuses the same rename machinery as "Rename files/roms"
      above — same underlying write path, different source of the target
      name: DAT-declared name vs. a case transform of the existing name);
      and, for the archive-level case, the same central-directory rewrite
      concern as "Rename roms" above (an entry's name lives inside the
      ZIP's own directory structure, not just as a filesystem name).
      Directly follows up on fase 1's already-implemented "case-only
      mismatch" detection — fase 1 flags the discrepancy, this is the
      fase-2 policy for actually resolving it.

**Cross-cutting prerequisite, not specific to any one item above**: every
write action on this list needs the not-yet-designed permission/
confirmation layer that gates fase 2 as a whole (today `LibraryViewModel
.modificationsEnabled = false` blocks all of this at the root) — that
gate itself is a separate, one-time piece of work this whole tab depends
on, not something to build per-checkbox.

None of the above needs deciding right now — recorded so the eventual
"design the Fix tab" conversation starts from a concrete, proven
reference and a real accounting of what each checkbox actually costs,
instead of from scratch.

- [ ] **Classic rebuild from loose files → complete sets** (RomCenter/
      ClrMamePro). Package loose ROM files into correctly named zips per the
      DAT. The mandatory starting point — everything else in this phase
      builds on it. Size: large.
- [ ] **Cross-set repair** (ClrMamePro's "Rebuilder"). Repair a broken set by
      copying a missing ROM from a sibling set (parent/clone share ROMs).
      Builds directly on the already-implemented TorrentZip writer and
      merge-mode detection. Size: large.
- [ ] **Real split/merge/non-merge writing** (detection already exists —
      only the write side is missing). Actually move shared ROMs to the
      parent (merge) or duplicate them into every clone (split/non-merge).
      `HeaderSkipRule` + merge-mode wiring already give this a running
      start. Size: large.
- [ ] **RomVault-style "DatRoot"/deep storage.** Internal hash-addressed ROM
      store; zips are generated on the fly from it per the active DAT
      instead of duplicating shared bytes across sets on disk. The most
      architecturally ambitious item here — changes the storage model, not
      just the rebuild logic. Size: large.
- [ ] **Physical duplicate dedup via hardlinks.** A lighter alternative to
      full deep storage — avoid duplicating identical bytes shared between
      sets using filesystem hardlinks instead. Size: medium-large.
- [ ] **Rebuild from external scavenging folders** (ClrMamePro). Point at
      other collections/backups as a repair source, complementing cross-set
      repair above. Size: medium.

Also noted, not MAME-scoped and therefore not prioritized per [[feedback_romforge_mame_first]]:
Igir's automatic "detect which hashes are actually needed" approach could
still apply usefully to fase 1's own hashing pipeline, independent of any
write capability.

- [ ] **"Corrupt" vs "absent" distinction in the repair flow** (RomVault). A
      physically present but damaged file should trigger a different
      replacement path than a genuinely missing one — avoids false
      "missing" reads when the real fix is an overwrite. Size: medium.
- [ ] **Preservation-archive auto-download** (myrient-downloader-style
      tools). Feed the fixdat/wanted-list to an automatic downloader.
      Note (2026-08-19 research): Myrient itself shut down 2026-03-31;
      Minerva Archive picked up the same ~385TB via torrents. Carries real
      legal/ethical considerations the user must decide on explicitly
      before any work starts here — not a pure engineering call. Size:
      large.
- [ ] **Rollback set** (mentioned in MAME rebuild community discussion,
      pyra-handheld.com). Rebuild a set faithful to an *older* MAME
      version — distinct from the already-implemented DAT-version diff
      (pure comparison, no reconstruction); this would actually rebuild
      backward toward a historical MAME release. Size: large.

No solid evidence found (2026-08-19 research pass) of true transactional
undo/rollback for completed write operations in any tool in this space
(RomVault/ClrMamePro/Igir) — Igir's `--clean-dry-run` only previews before
writing. Undoing an already-executed rebuild would be unexplored ground if
ROMForge ever implements it.

## Fase 1 — read-only items found in a second research pass (2026-08-19)

- [x] ~~`dir2dat`-style report~~ (Igir) — declined by the user (2026-08-19,
      "1, no"). Not implementing.
- [ ] **"Known vs unknown files" report** (Igir). A third explicit status
      for files that match nothing catalogued at all, distinct from the
      existing missing/surplus categories. Size: small.
- [ ] **Case-only-mismatch category** (RomVault's own error-message
      taxonomy). Hash matches but the filename differs only in
      upper/lowercase — keep it out of the existing "renamed" bucket so a
      case-sensitive-vs-insensitive filesystem quirk doesn't masquerade as
      a real rename. Size: small.
- [ ] **Filename-embedded CRC verification** (GoodTools/TOSEC
      `[name] [CRC32].ext` convention). Detect "the filename claims CRC X
      but the actual content hashes to Y." Rare in native MAME sets, but
      useful for imported external sets using that convention. Size: small.
- [ ] **Cross-checksum verification inside a ZIP itself** (Igir). Compare
      the local file header's CRC against the central directory's CRC to
      catch a corrupt/truncated ZIP container without decompressing
      anything — builds on the low-level ZIP parsing already touched for
      the TorrentZip writer. Size: medium.

## Fase 1 — deferred read-only items (2026-08-19)

Set aside during the read-only research pass, not discarded — revisit later.

- [ ] **Collection progress dashboard** (RomCenter/RomVault-style). Aggregate
      view of % sets complete, per-status counts, optional breakdown by
      year/manufacturer. Zero new computation — every number already exists
      in `AuditReport`/SQLite; this is purely a presentation layer. Size:
      small-medium. User: "5 no, dejalo documentado" (deprioritized, not
      rejected).
- [ ] **Incremental fixdat (delta between scans).** Report what changed
      since the last scan ("N games newly present, N disappeared") using
      the existing mtime+size scan cache, instead of comparing two old
      fixdats by hand. Only valuable for a workflow of repeated,
      time-spaced scans tracking progress — if the user's actual pattern is
      "load, audit, fix once, done," this adds little. Size: medium (the new
      part is deciding when to freeze a snapshot — before each scan? a
      manual "mark this point" button? — plus the diff logic itself, which
      is simple but new). User: "el 7 no" (declined, kept documented per
      their own request in case the workflow changes later).

## Research questions (not started)

Tracked in `TODO.md` (local, gitignored): automatic DAT/metadata source
integration (per-source API check), and whether MAME's web-published XML
can be read as-is by `MAMEListXMLParser` or needs the same transformation
`mame -listxml` does at the command line.
