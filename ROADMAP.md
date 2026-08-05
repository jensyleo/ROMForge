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
6. [~] **CHD hunk decode** — as complete as this environment genuinely
   allows; marked "in progress" (not done) because several codecs remain
   permanently blocked here (see below), not because more effort would
   close them. Ported directly from MAME's own source rather than wrapping
   `libchdr` (no Homebrew `libchdr` formula exists, and libchdr's own
   dependencies — zlib available via libSystem, but liblzma/zstd only via
   Homebrew's `xz`/`zstd`, and FLAC not installed at all in this
   environment — would have made a C-target wrapper itself fragile across
   machines; porting the algorithm directly has no such runtime dependency
   risk).

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
   - `CHDHeader` gained `mapOffset` (previously unread, needed to actually
     locate the map instead of only verifying the file's declared
     identity).
   - `CHDHunkReader` (new) — the tie-together piece: opens a real CHD v5
     file, reads its map via `CHDHeaderReader` + `CHDV5MapReader` (with
     `mapcrc` verification), and decompresses individual hunks on demand
     for `COMPRESSION_NONE` (raw copy), `COMPRESSION_TYPE_0`/zlib (via
     `CHDZlibDecompressor`), and `COMPRESSION_SELF` (recursive lookup,
     cached). `COMPRESSION_PARENT` is implemented and resolves against
     another `CHDHunkReader` passed in as `parent:`, but is untested
     against a real parent/diff-CHD pair (see below).
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
   - **No real, legally-obtainable CHD file exists in this environment** to
     validate any of the above against (same restriction as sourcing
     ROMs — no Homebrew `libchdr`/`chdman` formula, MAME itself isn't
     installed, and Claude cannot legally source copyrighted disc images).
     Every test above is either a hand-built-but-algorithm-traced fixture
     or an independently-generated-but-synthetic one. **This should be
     validated against a real CHD before being trusted for anything beyond
     further development.**
   - **LZMA hunk bodies** — needs MAME's specific raw-stream framing, not
     just any liblzma call; liblzma is only available via Homebrew's `xz`
     here, not system-provided, so even attempting it would add a
     non-portable dependency this project has otherwise avoided.
   - **MAME's own Huffman codec for hunk bodies** — a distinct, larger
     instantiation from the map decoder (likely `huffman_decoder<256,
     ...>` or similar); not ported.
   - **FLAC hunk bodies** — no FLAC library installed in this environment
     and none vendored; would require adding a real dependency this
     project has deliberately avoided elsewhere.
   - **CD-composite codecs** (sector/subcode de-interleaving on top of any
     of the above) — not attempted.
   - **`COMPRESSION_PARENT` is implemented but untested** — no real
     parent/diff-CHD pair exists here to build a genuine multi-file test
     against; only the pointer-resolution logic itself is exercised (via
     the map-reader's own hand-built PARENT-type fixture), not a full
     child-reads-from-parent flow.
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

## Research questions (not started)

Tracked in `TODO.md` (local, gitignored): automatic DAT/metadata source
integration (per-source API check), and whether MAME's web-published XML
can be read as-is by `MAMEListXMLParser` or needs the same transformation
`mame -listxml` does at the command line.
