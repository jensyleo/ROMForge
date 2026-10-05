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

At the user's request ("dig deep... search the web for all the sources"),
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
jensyleo's call was explicit: "just validate the ROM and the CHD
separately, don't look for that CHD + ROM parity" — no ROM↔CHD parity check,
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

**Third spot, the one that actually explained "I'm still seeing it mixed" after
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
   - **Still not wired into any rebuild/export feature — correction,
     2026-09-11**: Fase 2 shipped real write actions long ago
     (`LibraryViewModel.modificationsEnabled` is a real, user-facing toggle
     now, default off but switchable in Settings → General), and
     `RebuildPlanner.planRebuild` (loose-file rebuild) IS wired to the
     toolbar's own "Rebuild to Folder…". But `planRebuildAsZip` (the
     TorrentZip-producing sibling of `planRebuild`, right below it in
     `RebuildPlanner.swift`) never got its own hookup — no button, menu
     item, or CLI flag anywhere calls it, even today. Confirmed by reading
     `LibraryViewModel.rebuildToFolder`'s own body: it only ever calls
     `planRebuild`. For whoever picks this up: the missing piece is purely
     UI — a new toolbar/menu action (e.g. "Rebuild as Zip Sets…", or a
     format picker added to the existing "Rebuild to Folder…" flow) that
     calls `RebuildPlanner.planRebuildAsZip(matchReport:destination:)`
     instead of `planRebuild`, then routes its `.createTorrentZipArchive`
     operations through `RebuildExecutor.execute(_:)` exactly like every
     other Fase 2 write action already does — same preview-count-then-
     confirm dialog pattern as "Rebuild to Folder…" itself. See TESTING.md
     §11.3 for the manual test checklist already written and waiting for
     this hookup to exist.

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
- [ ] **Find missing roms in scavenging folders** — **decided not to
      implement** (jensyleo, 2026-09-11): "la idea es que solo busque las
      ROMs para reparación de la carpeta de reparación o de las ya
      agregadas a Rom Folder" — an arbitrary "scavenging" folder unrelated
      to a system is explicitly out of scope by design, not just
      unbuilt. Removed from Settings → Fix's "Not yet available" section
      outright. What this would have searched is already fully covered by
      "Repair from Maintenance Folder…" (`RebuildPlanner
      .planRepairFromMaintenanceFolder`, `LibraryViewModel
      .planRepairFromMaintenanceFolderPreviewCount`) plus its own Settings
      → Fix → "Find ROMS" → "Search missing ROMs in" scope picker
      (`FixPreferencesSettings.missingRomsSearchScopeKey`/
      `MissingRomsSearchScope`): the Maintenance subfolder alone, or that
      subfolder plus the system's own already-configured ROM folders
      (`system.romFolderURLs`) — deliberately never anything broader.
      Left documented here only so a future implementer has an exact
      starting point if this scope decision is ever revisited. Original
      scope: search one or more user-configured folders unrelated to any
      system for a same-hash file and pull it in — would have needed a
      new per-system or global scavenging-folder-list setting (new UI,
      new persisted preference); the matching logic itself needs nothing
      new (`RebuildPlanner.planRepairFromMaintenanceFolder` already
      matches purely by content, agnostic of where `donorFiles` came
      from — only the folder list feeding it would have differed).
- [ ] **Create dummy roms / Create ghost games** — generate placeholder
      files/entries so a frontend's game list stays visually complete.
      Needs: deciding on a placeholder file format/size convention (no
      existing precedent to copy from ROMForge's own code). **Low
      priority** — conflicts with [[feedback_romforge_mame_first]] and the
      "never a launcher" scope decision in [[project_romforge]]; only
      worth building if a concrete future need appears, not speculatively.
- [x] **Fix samples** — **implemented 2026-09-11** (jensyleo: "implementalo,
      es clave para MAME"). MAME's own DAT declares only a sample's NAME
      (`<sample name="...">`), never a hash — no dump exists to verify
      against, so this can only ever mean "does the whole
      `samples/<name>.zip` this machine needs exist", never "is it the
      right one". Design: `MAMEMachine`/`DATGame.sampleOf` now parses the
      `sampleof="..."` attribute (mirrors `cloneof`/`romof`'s own one-hop
      sharing — a clone that shares its family's samples resolves to
      `sampleOf ?? name` for the zip it actually needs);
      `RebuildPlanner.planCollectSamples` plans a plain `.copy` for every
      needed sample-set name a filename-only search of the system's own
      configured ROM folders (`LibraryViewModel.findSampleZips`, plain
      `FolderScanner`, no hashing) actually found, into a Samples folder
      configured in Settings → Systems → MAME → "Samples" (MAME-exclusive
      placement, per jensyleo's own explicit instruction — off by default,
      since not every collection uses sample-playing games). "Fix
      Samples…" is a standalone toolbar action ("Fix" dropdown), reachable
      once added to `LibraryDetailView.fixActionsEnabledForTesting` per
      the one-at-a-time manual-testing policy.
- [ ] **Remove zip comments** — mechanical: locate and clear the ZIP end-
      of-central-directory comment field. Needs a small addition to the
      binary ZIP writer path already built for TorrentZip — no new
      detection, no new UI beyond the toggle itself.
- [ ] **Unzip and rezip every archive** — **built, then decided against**
      (jensyleo, 2026-09-11): "elimina eso, no lo vamos a usar, no tiene
      sentido para esta app" — fully implemented once (`RebuildOperation
      .rewriteArchiveAsTorrentZip`, `RebuildExecutor`'s temp-file-then-
      atomic-swap executor, `RebuildPlanner.planUnzipAndRezip`, the
      `LibraryViewModel`/`LibraryDetailView` wiring, and Core unit tests),
      then removed outright from all three layers rather than left as a
      disabled toggle. Left documented here only so a future implementer
      has an exact starting point if this decision is ever revisited.
      Original scope: force every archive in a system through a full
      extract + rewrite via the TorrentZip writer, even when nothing else
      about the archive is wrong, only carrying over roms the DAT still
      recognizes (any unmatched/hash-mismatched/nodump entry, or unrelated
      junk, gets dropped on rebuild) — the exact design already worked out
      and built once; nothing here is actually missing, it was a genuine
      product decision, not a technical gap.
- [ ] **Allow multiple rom formats** — **decided not to implement**
      (jensyleo, 2026-09-11): removed from Settings → Fix's "Not yet
      available" section outright rather than kept as a disabled toggle.
      Left documented here only so a future implementer has an exact
      starting point if this is ever revisited. Original scope: don't
      force one output archive format (zip only) when rebuilding/fixing.
      Needs: fase 2's rebuild engine to support at least one alternative
      container before this toggle would mean anything — currently there
      is only one write path (zip via TorrentZip), so this setting had
      nothing to select between. Would also depend on deciding which
      other formats (7z? raw loose files?) fase 2 should actually write —
      none of that groundwork exists today.
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
      ZIP's own directory structure, not just as a filesystem name). Also
      the natural place to detect a case-only mismatch in the first
      place (2026-08-25: removed from fase 1 as its own read-only item —
      see the "Fase 1 — read-only items found in a second research pass"
      section — since a detection with no fase-2 write action to resolve
      it wasn't worth its own item; this policy covers both).

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

- [ ] **BIOS compilation and documentation** (user request, 2026-08-20).
      Automatically organize and document all BIOS files found in a
      scanned system. Needs:
      1. **Automatic folder structure creation**: a one-button "Organize
         BIOS" action that creates a new folder called `BIOS` at a
         user-configured location (alongside or separate from the ROM
         folders) with per-system subfolders (`BIOS/neogeo/`,
         `BIOS/capcom/`, etc.) — determined by examining which systems
         (parent games) actually require each BIOS via the DAT's `romOf`
         chain already used in fase 1's `OrphanedBIOSDetector`.
      2. **Copy or hardlink BIOS files**: either copy each discovered BIOS
         archive into its destination subfolder, or use filesystem hardlinks
         (if available on the user's platform) to avoid duplicate storage
         while keeping the BIOS accessible from a centralized location.
      3. **Auto-generated documentation**: a text/markdown file per BIOS
         (or a single index) listing:
         - Filename and hash (SHA1/MD5/CRC32 already calculated in fase 1).
         - Which system(s) it belongs to (e.g., "Required by: pacman,
           pacmanf, pacmanbx, ...").
         - Which parent games depend on it (audit trail).
         - Format: CSV or markdown table, or a simple `bios_map.txt` keyed
           by BIOS name.
      4. **Dry-run preview before writing**: show the user the proposed
         structure (tree view of folders and files that would be created)
         and ask for confirmation before any writes — no silent file
         copies/moves, matches the cautious pattern elsewhere in fase 2.
      Size: **medium** (reuses existing BIOS detection from fase 1, mainly
      new work is folder/file organization + doc generation; no new
      matching/hashing logic needed). Priority: **low-to-medium** — nice
      organizational feature, not a core rebuild function, can be added
      after the mandatory rebuild items are stable.

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
- [x] ~~"Known vs unknown files" report~~ (Igir) — already covered:
      `AuditStatus.unknownFile`/`.surplusInArchive` already give a local
      file whose hash matches nothing in the DAT its own distinct status,
      separate from a plain surplus. Confirmed by grepping the codebase
      (2026-08-25) rather than assumed from this note alone.
- [ ] ~~Case-only-mismatch category~~ — removed (2026-08-25, user request):
      not its own fase 1 read-only detection after all. RomVault's origin
      for this (its own error-message taxonomy, not a MAME DAT concept —
      the DAT has no notion of casing at all; this is purely a filesystem
      case-sensitivity artifact) belongs with the fase 2 **Sets case /
      Roms case** Fix policy below instead, which already covers deciding
      what to DO about a case mismatch (Datafile case/Uppercase/Lowercase)
      — detecting one without a fase-2 write action to resolve it isn't
      worth its own read-only item.
- [x] **Filename-embedded CRC verification** (GoodTools/TOSEC
      `[name] [CRC32].ext` convention) — done (commit `6975fae`):
      `FilenameEmbeddedCRC.swift`/`FilenameCRCVerifier.swift`, runs
      automatically every scan, surfaced as "Filename CRC mismatches" in
      the Database tree.
- [x] **Cross-checksum verification inside a ZIP itself** (Igir) — done
      (commit `6975fae`): `ZipLocalHeaderCRCVerifier.swift`/
      `ZipIntegrityAuditor.swift`, on-demand via "Verify ZIP Integrity"
      context menu item (not automatic — see that file's own doc comment
      for the performance reasoning), surfaced as "ZIP internal CRC
      inconsistencies" in the Database tree.

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
      is simple but new). User: "not the 7th" (declined, kept documented per
      their own request in case the workflow changes later).

## Research questions (not started)

Tracked in `TODO.md` (local, gitignored): automatic DAT/metadata source
integration (per-source API check), and whether MAME's web-published XML
can be read as-is by `MAMEListXMLParser` or needs the same transformation
`mame -listxml` does at the command line.

## Bugfix log (2026-09-30)

- **"Mapper" line now names the audio-expansion chip, when there is one**:
  the Info panel already decoded the iNES header's mapper number
  (`INESHeaderDecoder`) but just printed the raw number. New
  `NESAudioExpansionChip.name(forMapper:)` (`INESHeaderDecoder.swift`) maps
  mapper 5/19/24/26/85 to their real chip name (MMC5/N163/VRC6/VRC7) —
  sourced from the NESdev Wiki's own "List of games with expansion audio".
  Wired into the one line that prints it
  (`LibraryDetailView.swift:10395`), e.g. "Mapper 24 (Konami VRC6 — audio
  expansion) · PRG ...". `nil` (most mappers) renders identically to
  before — no behavior change for the common case.
- **"Remove Zip Comments" via "Fix All" didn't visually refresh the table —
  real regression, found live (jensyleo: "lo de remover zip comments puede
  que si lo haya hecho, pero no lo vi actualizado en la pantalla")**. Root
  cause: the table's forced-reload mechanism for this specific action
  (`zipCommentTableReloadToken`, a `.id()` bump — `Table`'s own AppKit
  diffing can't detect an off-model, cache-only field change like a zip
  comment) was only ever bumped from the toolbar's
  `commitRemoveZipComments()` and the context menu's
  `commitContextMenuRemoveZipComments()`. `commitFixAll()` calls
  `viewModel.fixAll(...)`, which internally also calls
  `removeZipComments(...)` as one of its automatic sub-actions — but
  `commitFixAll()` never bumped the token itself, since it lives in the
  view model, not the view, and has no access to that `@State`. The
  underlying fix *did* execute correctly (log line confirmed it; the
  scoped `ZipCommentCache` invalidation runs automatically off
  `viewModel.auditReport` changing, so the cache itself wasn't stale
  either) — only the forced table re-render was missing for this one call
  path. Fixed: `commitFixAll()` (`LibraryDetailView.swift`) now also
  increments `zipCommentTableReloadToken` after `fixAll` completes, same
  as the other two call sites. Confirmed via `grep` that these are the
  only three call sites of `removeZipComments`/`fixAll` in the app, so no
  other path has this same gap. Verified build green (Core + Xcode
  Release), installed to `/Applications`.

## Future idea (not started, not prioritized) — region-quality visual indicator

Idea from a 2026-09-30 conversation about regional ROM differences (e.g.
Contra's Japanese Famicom release has more background animation/intro than
the US NES release; Rush'n Attack's Japanese original "Green Beret" has
more lives/ammo/content than the NES port; Bionic Commando's Japanese
"Hitler no Fukkatsu - Top Secret" is uncensored vs. the US/EU releases).
The ask: show a visual signal in the game tree when one region's version of
a game is known to be meaningfully better/more complete than another
region's version the user has (or is missing).

**Why this can't be auto-derived from the DAT**: which region is "better"
is editorial/historical knowledge (extra cutscenes, removed censorship,
extra lives/content, fixed bugs) — it's not something a CRC/hash/DAT field
encodes, and no standard DAT ecosystem (No-Intro/TOSEC/Redump) publishes
this. It would require a hand-curated knowledge base, built up incrementally
per game family (same parent/clone grouping the DAT already gives us), not
something that can ship "complete" on day one.

**Proposed design, if picked up later**:
1. New curated data file (JSON or a SQLite table) — `RegionQualityNotes`:
   entries keyed by game family (the DAT's own parent/clone grouping),
   each with `recommendedRegion`, a short `reason`, and a `source` citation.
2. When a game has region siblings (via existing parent/clone data) and a
   curated note exists for that family, surface it: a small icon/badge in
   `GameTreeTableView` next to the game name, different states for "you
   already have the recommended region" vs. "a better region's version
   exists and you don't have it."
3. Surface the full note (reason + source) in the Info panel for the
   selected file.
4. Let the user add/override their own notes (an Application Support
   overlay file) rather than being locked to whatever ships in the repo,
   since this is opinionated/editorial data that can be wrong or disputed
   for a given title.

**Explicitly out of scope for this idea**: anything about audio expansion
chips (VRC6/VRC7/MMC5/N163/FDS) — that's a separate, already-researched
topic (chip presence can be derived from the iNES header's mapper number,
see `INESHeaderDecoder`, but doesn't change region-vs-region "better"
judgments for the titles checked so far, none of which use an expansion
chip).

**Research update (2026-10-01)** — challenged the "must hand-curate 100%
from scratch" assumption with real research before committing to that as
the only path:
- **No existing structured dataset or API catalogs this.** TCRF (tcrf.net)
  is pure MediaWiki prose with only the generic MediaWiki API (page
  text/revisions, no "regional_quality" field or equivalent). GameFAQs has
  no structured export either. No GitHub dataset found cataloging
  region-vs-region content/censorship differences specifically (No-Intro/
  TOSEC only catalog hashes, confirmed not equivalent). ScreenScraper/
  LaunchBox/IGDB's "Region Priority" is a USER PREFERENCE for picking a
  default duplicate, never an objective content-quality judgment — not
  usable as a source.
- **One real efficiency gain, not a shortcut**: TCRF's own API can still
  help DISCOVERY — searching page text for "censored"/"uncensored"/"extra
  lives"/etc. to find candidate games faster than browsing manually — but
  the actual curation (deciding what the note says) remains manual either
  way.
- **Licensing, confirmed**: TCRF content is **CC BY 3.0** (not CC BY-SA —
  no share-alike clause), permitting commercial use with attribution only.
  The curated data schema should therefore always store `sourceURL` +
  `sourceLicense` + a consultation date, and the `reason` field should be
  written in ROMForge's own words — never TCRF prose copy-pasted verbatim,
  even though the license would technically permit it with attribution.
- **Bottom line**: doesn't change the feature's scope, confirms the
  original plan was already right not to assume a shortcut existed.

**Scope note (2026-10-01)**: jensyleo wants this configurable specifically
in the NES system's own settings first (not a global, cross-system
toggle) — see the cost analysis below for what that implies.

### Cost analysis (2026-10-01) — what building this would actually take

Scoped as: a per-system (starting with NES) toggle in `SystemSettingsView`
("Show region-quality hints"), a small curated JSON seed file shipped in
the app bundle (NOT a SQLite table — far simpler for a read-mostly,
developer-curated list that's small by nature, maybe dozens to low
hundreds of entries even at a mature state), a user-editable override file
in Application Support, a badge in `GameTreeTableView`, and the note
surfaced in the Info panel.

- **Data model + loading** (`ROMForgeCore`): a `RegionQualityNote` struct
  (`gameFamily`, `recommendedRegion`, `reason`, `sourceURL`,
  `sourceLicense`, `consultedDate`) + a loader reading the bundled seed
  JSON and merging a user override file on top. **Small** — a few hours,
  closely mirrors existing patterns already in this codebase (e.g. how
  `SystemLibraryStore`/`DATFileCache` load+merge JSON).
- **Matching a game to a note**: reuses the DAT's own existing parent/clone
  grouping (`GameNode.cloneOf`, already computed) — no new relationship
  data needed, just a lookup by family name. **Small.**
- **Per-system setting (NES-scoped)**: one new `@AppStorage`-backed toggle
  in `SystemSettingsView`'s NES-specific section, read the same way
  `similarNameFixEnabled`/`maintenanceFolderEnabled` already are per
  system. **Small** — this codebase already has several examples of
  exactly this shape of per-system opt-in.
- **UI badge + Info panel surfacing**: a small icon in `GameTreeTableView`
  (two states: "you have the recommended region" vs. "a better region
  exists and you don't have it") + a line in the Info/detail panel showing
  `reason` and a clickable `sourceURL`. **Small-medium** — similar scope to
  the mapper→chip-name label added earlier this session, just with two
  display states instead of one and a clickable link.
- **The actual curated data itself**: **this is the real cost, and it's
  ongoing, not one-time.** Every entry requires real research (web search,
  verifying claims, writing a reason in ROMForge's own words, finding and
  citing a real source) — the kind of work already done live in this
  session for Contra/Rush'n Attack/Bionic Commando (3 games, each one took
  a real research pass). A seed file covering even "the obviously famous
  cases" (the ones already discussed, plus maybe 10-20 more well-known
  ones like Castlevania/Simon's Quest's infamous bad English translation,
  Ghosts'n Goblins difficulty differences, etc.) is realistically its own
  multi-session research effort, not a side task — this is the dominant
  cost of the whole feature by a wide margin, not the code.
- **User-override file**: reuses the exact same JSON shape as the seed,
  loaded from Application Support and merged (user entries win on a
  `gameFamily` collision). **Small.**

**Overall engineering cost: small-medium** (a few focused sessions, mostly
boilerplate this codebase already has patterns for). **The data curation
cost is open-ended** and is a genuinely separate, ongoing commitment from
the code itself — worth deciding explicitly whether to ship with just the
handful of titles already researched this session (Contra, Rush'n Attack,
Bionic Commando) as a proof-of-concept seed, versus delaying until a
bigger curated list exists. Status: **documented and costed, not started,
no commitment to build yet.**

## Bugfix log (2026-09-30, continued) — zip comment display, real root cause

- **The earlier "fixAll didn't bump the reload token" theory was real but
  incomplete** — jensyleo reported the bug persisted even after that fix
  ("para eso ches largos... no aprendieras que probar las compresion
  descompresion no aplica" — correctly calling out that chasing the
  zip-bomb/compression angle was a distraction from this report). Verified
  on disk directly (hex-dumped the EOCD record of a real affected file)
  that `clearZipComment` genuinely works — the comment IS gone from the
  file. The real root cause: `AuditReport`/`AuditEntry` are `Equatable`
  structs that hold NOTHING about a zip's own trailing comment (that's
  `ZipCommentCache`, entirely outside this data model) — so after a
  comment-only change, `removeZipComments`'s own internal re-`scan()`
  produces a NEW `AuditReport` that is **value-equal** to the old one.
  SwiftUI's `.onChange(of: viewModel.auditReport)` — the ONLY place that
  ever called `zipCommentCache.invalidate(underAnyOf:)` — therefore never
  fires at all for this specific case, on EVERY call path (toolbar,
  context menu, and Fix All alike), not just the one this session
  previously patched. The forced-reload token (`zipCommentTableReloadToken`)
  was redrawing `Table` correctly the whole time — it just kept redrawing
  from the same never-invalidated, stale cache.
  Fixed: all three commit sites
  (`commitRemoveZipComments`/`commitContextMenuRemoveZipComments`/
  `commitFixAll`, `LibraryDetailView.swift`) now call
  `zipCommentCache.invalidate(underAnyOf:)` directly after their own
  `removeZipComments`/`fixAll` call, instead of relying on the `onChange`
  side effect that silently doesn't apply to this one action. Verified the
  file-level fix is real before touching any Swift code (raw EOCD bytes
  show comment length `0x0000`), then traced the actual display path
  (`infoText(for:)` → `zipCommentCache.comment(forZipAt:)`) to find the
  missed invalidation. Built Release, installed to `/Applications`.

## Bugfix log (2026-10-01) — global NAS-access premise audit

jensyleo set an explicit, global design premise: "Solo consultar la NAS
para escaneos y Fix. Lo demas debe estar en cache." A full codebase audit
was run against it (App/Sources + ROMForgeCore/Sources), checking every
`FileManager`/`Data(contentsOf:)`/`Archive(url:)`/`ZipCommentReader` call
site for whether it's reachable from a render/selection-change path
instead of an explicit Scan or Fix action.

- **Real violation #1 (already described above, 2026-10-01 entry) —
  `ZipCommentCache` read live per ROM-folder-not-yet-visited-this-session**:
  fixed by skipping the whole preload for `isMAMEStyle` systems and keeping
  it background-preloaded (never live) for console systems.
- **Real violation #2, found by this follow-up audit —
  `GameTreeTableView`'s own Games-table context menu**: building the
  menu (`GameTreeTableView.swift`, the context-menu closure) called
  `viewModel.planRemoveZipCommentsPreviewCount(scopeFolders:)`, which (unlike
  every sibling preview count in the same closure — all pure in-memory
  `matchReport` reads) does a live `ZipCommentReader` disk/NAS read per
  candidate zip. Merely right-clicking/opening the context menu on a
  selection paid this cost, unscoped, every time — the same class of bug
  already fixed elsewhere, missed at this specific call site. Fixed:
  added `ZipCommentCache.hasCachedComment(forZipAt:)` — a true cache-only
  read (no live fallback, returns `false` for a URL not yet warmed by the
  background preload) — and the context menu now counts via that instead.
  The real action, once actually clicked, still goes through the normal,
  accurate `removeZipComments` path — legitimate, since that's an explicit
  Fix action. `ZipCommentCache` itself (`LibraryDetailView.swift`) widened
  from `private` to internal access so `GameTreeTableView.swift` (a
  different file) can reference `ZipCommentCache.shared` directly.
- **Known, deliberately-not-fixed residual edge case**: `ZipCommentCache
  .comment(forZipAt:)` (the ordinary, filling accessor used by
  `infoText`/`zipCommentHelpText`) still falls through to a live read if
  queried for a URL the background preload genuinely hasn't reached yet
  (e.g. a narrow race between a fast folder switch and the detached
  preload task completing). Left as a defensive fallback rather than
  returning a possibly-wrong "no comment" during that narrow window —
  flagged here for visibility rather than silently left unexamined.
- Audited and confirmed already correctly cache-only, not re-litigated:
  `organizeBIOSFilesAvailableCache`/`organizeComplementaryChipsAvailableCache`
  (recomputed only on scan completion, never per-render),
  `maintenanceSubfolderExistsRefreshGeneration` (off-main-actor,
  generation-guarded), every other context-menu preview count besides the
  one fixed above, and every genuinely user-initiated one-off action (Play,
  Reveal in Finder, File Actions, Settings folder pickers) — these are
  expected to touch disk when explicitly triggered, not render-path reads.

## Bugfix log (2026-10-01, continued) — unified scan progress bar covers every real phase

jensyleo's report after a real NES scan: "hay parte del escaneo que no es
parte integral del progreso global de la barra de progreso." Traced all 13
real phases of `scan(system:folders:)`; `overallScanFraction` only weighted
4 of them (listing/hashing/matching/saving) — DAT loading, the folder walk,
every post-match annotation pass (report generation, CHD audit, duplicate
sets, orphaned BIOS, filename/CRC mismatches, Maintenance donors), and the
zip-comment preload tail all ran with the bar either on a disconnected
separate scale or completely frozen (label-only). Worse, the zip-comment
preload (`refreshCachedGameDataAfterAuditReportChangeAsync`'s own tail) is
a fire-and-forget `Task` never awaited by `scan()` — it could keep reading
disk/NAS well after the overlay already disappeared.

Fixed, all in `App/Sources/LibraryDetailView.swift` /
`App/Sources/LibraryViewModel.swift`:
- `ScanOverallPhase` extended with `.datLoad`/`.datLoadIndeterminate`/
  `.folderWalkIndeterminate`/`.postMatchStep`/`.finalPreload`; weights
  rebalanced across 9 phases (fixOps 0.10, DAT load 0.05, folder walk 0.05,
  listing 0.10, hashing 0.30, matching 0.20, post-match 0.05, saving 0.10,
  final preload 0.05 — sums to 1.0), all still one monotonically increasing
  fraction.
- The 3 DAT-loading sub-bars (machine count, file-read bytes, byte-count
  pass) and the folder-walk spinner now plot through `overallScanFraction`
  instead of their own disconnected 0–100% scales.
- New `LibraryViewModel.scanPostMatchStepProgress` — a step counter over a
  FIXED, known-order list of the 6 named post-match passes
  (`postMatchStepOrder`), advancing the bar one coarse notch per pass
  instead of holding completely dead through that whole stretch. A skipped
  conditional step (CHD audit, Maintenance donors) just means the next real
  one jumps the bar by more than one notch — no need to precompute which
  steps will run.
- New `LibraryDetailView.isPreloadingZipComments` (`@State`) — keeps the
  SAME scan overlay up through the zip-comment preload tail (`.overlay`'s
  gate is now `viewModel.isBusy || isPreloadingZipComments`), with its own
  weighted slice, so "the bar says done" and "the scan is actually done"
  are the same moment again. Never set for a MAME system (that preload is
  already skipped entirely there, see the earlier 2026-10-01 entry above).
- Build green, installed to `/Applications`.

## Bugfix log (2026-10-01, continued) — real main-thread NAS hang ("se estrelló")

jensyleo reported "la app se estrelló" while working over NAS — turned out
to be a genuine main-thread freeze, not a crash: `ps`/`sample` on the
running process showed state `UN` (uninterruptible sleep) and a live stack
trace pinned exactly on: right-clicking a row in the Games table →
`NSTableView.menuForEvent` → `GameTreeTableView`'s context-menu closure →
`planRemoveRedundantFilesPreviewCount`/`planRemoveRedundantRomsPreviewCount`
→ `redundantArchiveEntryCounts(matchReport:)` → `ZipArchiveScanner.scan`/
`Archive.init` → a blocking `fopen`/`open$NOCANCEL` on a NAS-mounted file,
all synchronously on the main actor. Both preview-count functions called
this fresh on EVERY context-menu open — the exact same "NAS only for
scans/Fix" violation already fixed for zip comments earlier this session
(`GameTreeTableView.swift:513`), just in a different function this
session's earlier audit didn't happen to flag.

Fixed in `App/Sources/LibraryViewModel.swift`: added
`redundantArchiveEntryCountsCache` (memoized per `matchReport`, invalidated
in its own `didSet` alongside the existing `matchedZipArchiveURLsCache` —
same precedent pattern), and a `redundantArchiveEntryCounts(for:)` instance
wrapper. Both preview-count functions now call the memoized wrapper
instead of the raw `Self.redundantArchiveEntryCounts` static. The two real
Fix-action call sites (`removeRedundantFiles`/`removeRedundantRoms`'s own
`Task.detached` bodies) were deliberately left calling the raw static
directly — those already run off the main actor, so they were never the
bug; reusing the cache value opportunistically there is a natural
follow-up but not required for correctness.

**Honest residual gap**: this stops the hang on every REPEATED menu open
(the common case that actually produced today's incident), but the FIRST
context-menu open after a scan still computes this synchronously on
whatever thread opens the menu (the main actor) — a real, if one-time,
blocking read. A full fix would pre-warm this cache in the background as
part of `scan()`'s own post-match pipeline (the same `postMatchStepOrder`
machinery added earlier today for the progress bar would be a natural fit)
— not done yet, flagged here for a future pass rather than silently
considered closed.

Verified: build green, force-killed the hung process (`UN` state didn't
respond to normal quit), reinstalled, relaunched.

## Bugfix log (2026-10-01, continued again) — residual redundant-counts gap closed

Closed the residual gap flagged in the entry just above: `redundantArchiveEntryCounts`
is now pre-warmed inside `scan()`'s own post-match pipeline (new named step
"Checking for redundant archive containers…", added to `postMatchStepOrder`
— the progress bar now shows 7 post-match steps instead of 6), computed
inside the SAME `Task.detached` the rest of the matching/report-generation
pipeline already runs in (confirmed by a real compiler error when first
attempting to call the `@MainActor`-isolated memoized wrapper from there —
this whole post-match block was already off the main actor, not on it as
first assumed). The result is threaded out through the detached task's own
return tuple and assigned to `redundantArchiveEntryCountsCache` AFTER
`matchReport` itself is set (its own `didSet` clears this same cache, so
order matters). Every context-menu preview count now reuses this for free
— the first right-click after a scan no longer pays any NAS cost at all,
closing the gap documented in the entry above. Build green, installed.

## Feature follow-up (2026-10-01) — region-quality hints, full coverage + panel + link/copy

jensyleo tested the region-quality hint (Games panel + tooltip) and
confirmed it works, then asked for 3 fixes:
1. **"Revisa que no se te escape nada"** — the feature only covered the
   Games panel (`GameNode` overloads); the Roms panel's own `infoText`/
   `zipCommentHelpText(for entry:)` never got it. Fixed: `regionQualityNote`
   refactored into a shared `regionQualityNote(forGameName:)` core, both
   `AuditEntry` overloads now append the same "⭐ Recommended version"/
   "ℹ️ Better version exists" suffix and tooltip, keyed off
   `entry.gameDescription ?? entry.game`.
2. **Bottom-left detail panel** — new `regionQualityDetailRow(forGameName:)`
   (shared by both `gameDetailRow`'s `.info` case and `romDetailSection`),
   showing the full reason as an always-visible row (not just a hover
   tooltip) right under "Info"/"Info: ". Not wired as a toggleable View
   Options field — deliberately simpler, same "nothing to report, don't
   show the row" self-gating `.family`/`.oneGameOneROM` already use.
3. **Clickable link + copy** — the source URL renders as a real SwiftUI
   `Link` (clickable, opens in the default browser) when it parses as a
   valid `URL`, falling back to plain text otherwise; a copy button
   (`doc.on.doc`) next to it copies the full "region recommended: reason
   (url)" text to the pasteboard via `NSPasteboard`.

Build green, installed.

## Bugfix log (2026-10-01, continued) — third audit pass: stuck overlay fix

Third audit pass this session (focused on all NEW code: region-quality
feature, unified progress bar, network-volume auto-concurrency). One real
bug found:

- **`isPreloadingZipComments` could get stuck `true` forever** —
  `refreshCachedGameDataAfterAuditReportChangeAsync()`'s zip-comment preload
  task shares `pendingFolderRecompute`/`folderRecomputeGeneration` with
  `triggerCachedGameDataRecompute()` (the folder-click path). Cancelling
  that shared task (e.g. a folder click arriving while the preload tail was
  still in flight) made the preload task exit through one of its own
  `Task.isCancelled` guards — which never reset `isPreloadingZipComments`,
  only the success path did. Left `true`, this kept the scan overlay stuck
  on screen forever (`.overlay`'s gate is `viewModel.isBusy ||
  isPreloadingZipComments`), blocking all further interaction — a real,
  if narrow-timing-window, freeze. Fixed: both `triggerCachedGameDataRecompute()`
  and `refreshCachedGameDataAfterAuditReportChangeAsync()` now reset the
  flag to `false` immediately after `pendingFolderRecompute?.cancel()`,
  before anything else — harmless when nothing was stuck, since whichever
  function actually proceeds sets it back to `true` moments later if
  applicable.
- **Verified clean** (explicitly checked, not re-litigated): the
  `redundantArchiveEntryCountsCache` pre-warm ordering (survives
  `matchReport`'s own `didSet`), `overallScanFraction`'s weights (sum to
  1.0 exactly), `RegionQualityNotes.baseTitle(for:)` on a plain name with no
  tags, `VolumeLocality.isNetworkVolume` on a nonexistent path (`statfs`
  fails gracefully, no crash), `statfs`/`URL.path` encoding (no injection
  risk, plain local syscall), and every new `LibraryViewModel` cache's
  thread-safety (all `@MainActor`-only access, no unsafe `nonisolated`
  touch).
- **Honest, not-fixed finding**: `RegionQualityNotes.note(forGameName:)`'s
  `overrides` parameter is never actually populated by any real caller —
  the "user override file in Application Support" part of the original
  design (ROADMAP's own region-quality section) was documented but never
  wired up. Not a bug (the parameter defaults to `[]` and behaves exactly
  as intended for the seed-only v1 shipped), just an honest gap between the
  original design doc and what actually got built — flagged here rather
  than left to look finished.

Build green, installed.

## Bugfix log (2026-10-01, continued) — region-quality exhaustive sweep: 2 real bugs

jensyleo asked for one final exhaustive sweep of the region-quality feature
before closing the NES work for this session. Found and fixed:

1. **UI text written in Spanish inside the English app** — `reason` fields
   in `RegionQualityNote.swift`'s seed data were written in Spanish (a
   leftover from drafting the feature in a Spanish-language conversation),
   but this text renders live in the app's own (English) UI — badges,
   tooltips, detail-panel rows. Translated all 3 entries to English.
2. **2 of 3 source URLs were bare domains, not the actual cited pages** —
   `sourceURL` for Rush'n Attack and Bionic Commando was just
   `https://www.movie-censorship.com` (the homepage), not the specific
   comparison report actually referenced. Re-verified via live web search
   and confirmed via the real page titles returned by Google's own index
   (a direct browser fetch hit a Cloudflare bot-check page, which is
   normal for this site and not a sign of a bad URL — the search engine's
   own cached titles were independent enough confirmation): Rush'n Attack
   → `movie-censorship.com/report.php?ID=439710` ("Rush 'n Attack (aka
   Green Beret)... Comparison"), Bionic Commando →
   `movie-censorship.com/report.php?ID=3851` ("Bionic Commando...
   Comparison: International Version - Japanese Version"). Reasons also
   rewritten with more precise detail pulled from this same re-verification
   pass (exact secondary-weapon round counts, exact censorship
   substitutions).
3. **Real matching bug, found during the sweep, not previously caught**:
   `RegionQualityNotes.note(forGameName:)` matched purely by stripping
   region/language tags from a name and comparing the remaining base
   title — but a No-Intro DAT doesn't always use the same base title
   across regions. Two of the 3 seed entries hit this exactly: "Bionic
   Commando" (US/EU) is cataloged as "Hitler no Fukkatsu - Top Secret"
   (Japan) in the DAT, and "Rush'n Attack" (US/EU) is "Green Beret"
   (Japan) — neither would ever have matched `gameFamily`, meaning the
   badge/note silently never appeared for either of these two games despite
   being "confirmed working" earlier against Contra alone (the one seed
   entry where both regions genuinely share one title). Fixed: new
   `RegionQualityNote.alternateTitles: [String]` field — `note(forGameName:)`
   now matches on `gameFamily` OR any `alternateTitles` entry. Contra needs
   none (empty array); Bionic Commando/Rush'n Attack each list their real
   Japanese-DAT title.

Build green, installed. This closes the NES work for this session.

## Pending: SNES expansion-chip display (blocked on real SNES ROMs)

Status (2026-10-02): not started; waiting for a real SNES ROM folder to
verify against. The SNES DAT (No-Intro, 4,131 games, `.sfc`, no copier
header) and the Snes9x launcher are already supported (v1.4.0).

Goal: show a cartridge's coprocessor (Super FX / GSU, SA-1, DSP, S-DD1,
OBC1, S-RTC, SPC7110/Cx4…) in the game info panel, like the NES mapper →
audio-chip line.

Why it is not a copy of the NES case: an NES DAT declares the 16-byte iNES
header as a hex string, so the mapper decodes with no file access. A SNES
DAT declares nothing of the sort — the map mode and chipset byte live INSIDE
the ROM data, at the internal header (LoROM file offset 0x7FC0, HiROM
0xFFC0; map mode at +0x15, chipset at +0x16; +0x200 when a 512-byte copier
header is present). So it needs real ROM bytes, and for a zipped ROM the
first ~64 KB must be decompressed.

Chosen design (user decision, 2026-10-02): compute it during the scan (or
the background preload), store it in the scan cache, and display it from the
cache only — never read the NAS when a row is selected ("only touch the NAS
for scans and Fix actions"; see the NAS performance premise above).

Steps:
1. Rewrite the header decoder (a first version was written and removed as
   dead code in the v1.4.0 audit; plausibility check on the map-mode low
   nibble; chip name from the chipset high nibble when the low nibble is
   3–6; ExLoROM/rare variants unsupported at first).
2. During scan, read the needed prefix of each SNES ROM (loose file or zip
   entry, byte-capped, reusing the existing extraction machinery) and cache
   `mapMode` + `expansionChip` per file.
3. Show it in the Games/Roms info panels from the cache.
4. Verify offsets and chip names against a real collection (Super FX:
   Star Fox; SA-1: Super Mario RPG; DSP: Super Mario Kart; S-DD1:
   Star Ocean) — a wrong chip name is worse than none, so no shipping
   without real ROMs.
5. Targeted unit tests only (no long test runs).

## Idea (future, optional): region-quality research via an AI integration

Status (2026-10-02): idea only, not started. Evaluated, not prioritized.

Goal: let the app research "which regional release is better" itself, the
way the curated notes (NES/SNES) were researched by hand, instead of a
person writing each note.

How it would work: user supplies their own API key for an AI service with
web search (stored in the Keychain); per game the app searches, reads
sources, and drafts a `RegionQualityNote` with a source URL; the user
reviews and accepts each draft before it is saved. Never auto-saved.

Cost / risk (observed while researching by hand this session):
- Many sources fail (HTTP 402/403) or are unusable; only ~5 of ~15 NES
  candidates could be verified.
- Some pages contain text aimed at AI agents (prompt injection) — web
  content must be treated strictly as data, never as instructions.
- Uneven quality: some notes are trade-offs (e.g. original content vs. bug
  fixes), which a draft can state as a clean winner.
- Each game costs tokens on the user's account and sends game names to an
  external service (privacy).
- Needs: API client, key storage, per-game cost cap, a review screen, and
  the user-override store (see below).

Verdict: not worth it yet — reviewing each draft costs about as much as
writing the note, and a typical collection has only a few dozen games with
real regional differences. Revisit if the curated list stops scaling.

Preferred first step (much cheaper, no keys, no network per game):
1. Move the curated notes out of Swift code into a JSON data file in the
   repo.
2. Let the app download the updated file, so new notes ship without an app
   release.
3. Wire the already-designed user-override file (documented gap), so users
   can add their own notes.

Arcade/MAME: deliberately excluded. Research (2026-10-02) showed arcade
quality depends on the game revision more than on region (MAME's own
parent set is the latest bug-fixed World revision by convention, not a
quality ranking), so a per-region indicator would be misleading.

## Multi-platform console rollout (SEGA, Sony, Microsoft) — in preparation

Status (2026-10-04): groundwork done locally (not yet released); platforms
are selectable in Add System but only NES/SNES are verified.

Done:
- Per-system emulator and per-system DAT (Settings → Systems → Consoles);
  the old global emulator and the "re-point every console at one DAT"
  button were wrong as soon as two consoles existed.
- `SystemCategoryKind` now lists every planned platform, grouped
  (Nintendo / SEGA / Sony / Microsoft / Arcade / Other) with a media kind:
  cartridge, disc, or catalog-only. Add System shows a DAT hint per kind
  (No-Intro for cartridges, Redump for discs, with an honest caveat).
- Catalog-only platforms (PS3, PS4, Xbox 360, Xbox One) never offer Play
  and show no emulator picker.
- Hashing already streams in 1 MB chunks, so very large images are
  memory-safe (but slow over a network volume on the first scan).

Rollout order:
1. SEGA cartridges (SG-1000, Master System, Game Gear, Genesis, 32X) —
   same shape as NES/SNES; needs a real No-Intro DAT per platform.
2. One disc platform as the test case (PS1 or SEGA CD) with a Redump DAT
   and a real folder, to verify multi-file games (.cue + .bin, .chd).
3. Remaining disc platforms (PS2, PSP, Saturn, Dreamcast, Xbox).
4. Catalog-only platforms (audit/organize only).

Not verified yet: which Homebrew emulators exist for each platform (only
Nestopia/FCEUX/Snes9x are known-good; others fall back to "Custom…" until
confirmed), and whether loose multi-file disc games match completely.
