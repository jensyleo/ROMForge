# ROMForge

A native macOS ROM collection manager. ROMForge validates ROM collections
against DAT files, repairs filenames, and rebuilds sets — inspired by the
workflow of clrmamepro and RomCenter, built from scratch with modern Swift.

It is not a frontend for emulation; it manages and audits ROM collections.
Future versions will present the library visually — box art, screenshots and
per-game metadata, in the spirit of
[Batocera.linux](https://github.com/batocera-linux/batocera.linux)'s game
list — but ROMForge will never become a ROM launcher/frontend (no emulator
launching, no controller UI, no "play" button, unlike Batocera, RetroBat or
EmulationStation). It targets arcade, consoles and other systems alike.

## Status

`ROMForgeCore` implements the full v0.1–v1.0 roadmap as a library, covered by
76 automated unit tests against synthetic fixtures: Logiqx/ClrMamePro DAT
parsing (No-Intro, Redump, TOSEC, FBNeo) and MAME `-listxml` parsing (BIOS
sets, `device_ref`, disks, parent/clone); scanning loose files, ZIP
archives, 7z archives (via the system's own `7zz`/`7z`) and CHD v5 headers;
CRC32/MD5/SHA1 hashing; matching by size and hash — never by filename
alone; reporting correct/incorrect/missing/surplus plus duplicate-by-hash
groups; repairing (rename/move/copy) and rebuilding sets (loose, ZIP,
split/non-merged/merged); resolving MAME BIOS/parent-clone dependency
chains; verifying CHD content against a MAME DAT's `<disk sha1="...">`
without decompressing hunks; and locating/installing the official 7-Zip.

**The SwiftUI app currently exercises a subset of that.** Today's working
end-to-end flow is: a multi-system sidebar (name + one or more ROM folders +
a DAT — Logiqx/ClrMamePro XML or MAME `-listxml`, auto-detected, `.dat`/`.xml`
or any other extension all work since detection is by content) — persisted
across launches — that scans loose files and `.zip` archives (each entry
matched individually against the DAT, not the archive as a whole), matches,
reports (with Region/Language columns read from the No-Intro/TOSEC naming
convention and a detail pane showing expected-vs-actual hashes), and exports
a CSV. **The app is currently view-only, at the user's request**: repairing
(renaming a misnamed ROM) is implemented in `ROMForgeCore` and covered by
tests, but disabled in the app behind a single switch
(`LibraryViewModel.modificationsEnabled`) — it never touches a ROM file.
7z/CHD scanning, duplicate detection, and standalone BIOS/parent-clone
dependency resolution are implemented and tested in `ROMForgeCore` but
**not yet wired into the app's scan pipeline** — see
[ROADMAP.md](ROADMAP.md) for what connecting them looks like.

None of this — Core or app — has been run against a real ROM/BIOS/CHD
collection yet; every test uses synthetic fixtures. See
[TESTING.md](TESTING.md) for the manual checklist (needs real dumps Claude
can't source — run it yourself).

## Using the app

The same basics are also available inside the app itself (Help menu →
"ROMForge Help", and the "About ROMForge" window) — this section covers the
same ground for anyone reading the repo instead.

- **"Database" and "ROM folder" sidebar.** "Database" browses the loaded
  DAT's own catalog (All games, Clones, By manufacturer, By year, and
  more — see Settings → General for which branches show at all); "ROM
  folder" lists the actual folders on disk configured for this system.
  Clicking either scopes the Games table to match; the two are mutually
  exclusive. Both support arrow-key navigation (↑/↓ move between rows,
  including across the "Database"/"ROM folder" boundary; →/← expand/
  collapse a category or clone family).
- **Reordering "ROM folder".** Newly-added folders slot into alphabetical
  order automatically. To reorder them by hand, use the ↑/↓ chevrons that
  appear on the right of each row — drag-to-reorder was tried and dropped
  (see `CHANGELOG.md`): on macOS, a `List` row that's also a click target
  fights a drag gesture attached to the same row, which kept making a
  plain click unreliable no matter how the drag was implemented. Plain
  buttons have no such conflict.
- **Searching a large "Database" category.** A category like "All games"
  can hold tens of thousands of rows — the search field above the tree
  narrows it down instantly. Without a search, a very large category shows
  only its first page, with a "Show N more" row to reveal more in bounded
  steps rather than rendering everything at once (the fix for a real
  freeze this same design once caused — see `CHANGELOG.md`).
- **Adding a system without a separate DAT.** "Generate from Installed
  MAME…" (next to "Select DAT…" in "Add System", once a real `mame`
  executable is configured in Settings → Systems) runs that executable's
  own `-listxml` and uses its output directly — no need to separately
  track down a `-listxml` dump matching whichever MAME version is actually
  installed. Precedent: ClrMamePro supports the same idea via its
  `engine.cfg` "datfile engines".
- **Scanning.** "Scan Folder" rescans just the selected "ROM folder"
  (forcing a fresh re-read of that one) while still matching against every
  other configured folder; "Scan All Folders" does the same for every
  folder at once, genuinely re-reading only what's actually changed. Both
  report which folder they're currently walking, in the progress overlay
  and in the Log panel.
- **Settings → View Options.** Toggle any of the six main panels (Database,
  ROM folder, Games, Roms, Detail, Log) off to declutter the window.
  "Purge Saved Views" resets remembered window layout only (which
  "Database"/"ROM folder" view was last selected per system, and every
  split-panel's size) — it never touches any scan result. "Purge Database
  View" clears every system's last scan result instead (cached file hashes
  and the saved audit report) — it never touches remembered layout/
  selection. The two are deliberately separate actions.

## DAT sources

ROMForge doesn't bundle or generate DAT files — bring your own from a
source you trust. Known-good places to get one:

- [MAME's own `-listxml` output](https://www.mamedev.org) — the
  authoritative source for MAME arcade sets; run `mame -listxml >
  mame.xml` against a local MAME install (`brew install mame`) rather
  than downloading one from a third party.
- [progettosnaps.net](https://www.progettosnaps.net/index.php) — a
  well-known, actively-maintained source for curated MAME DATs/romsets by
  driver status, category, and more; its DAT downloads specifically live
  at [progettosnaps.net/dats/MAME](https://www.progettosnaps.net/dats/MAME/).
- [No-Intro](https://datomatic.no-intro.org) — console/handheld
  cartridge dumps.
- [TOSEC](https://www.tosecdev.org) — a broader, less strictly-curated
  cross-platform DAT set.
- [Redump](http://redump.org/downloads/) — disc-based systems (CHD/CD
  DAT sets).
- [MAME docs/links](https://docs.mamedev.org) (also
  [mamedev.org/links.php](https://www.mamedev.org/links.php)) — background
  on romset conventions, not a DAT download itself, but useful context
  for how MAME's own sets are organized.

### Metadata/artwork sources (not DAT sources — for a future scraping feature)

Not usable for verifying ROMs against — these are game info/artwork
databases, relevant only to the not-yet-built "Metadata scraping" feature
(see `ROADMAP.md`)/`TODO.md`'s v2.0+ item:

- [Arcade Database (adb.arcadeitalia.net)](https://adb.arcadeitalia.net) —
  arcade-specific metadata/artwork.
- [MobyGames](https://www.mobygames.com) — broad game metadata database.
- [TheGamesDB](https://thegamesdb.net) — public API.
- [IGN reviews](https://www.ign.com/reviews/games) — check API/ToS before
  relying on this one.
- [GiantBomb](https://www.giantbomb.com) — public API.
- [Hardcore Gaming 101](https://www.hg101.net) — in-depth game write-ups;
  likely no API, scrape-only if ever used.
- [Internet Archive](https://archive.org) — well-documented public API,
  also hosts many DAT-adjacent preservation collections.
- [ScreenScraper](https://www.screenscraper.fr) — known API, the one
  Batocera/RetroBat themselves use for their own scraping.
- `github.com/opengood` — unclear what this refers to; needs confirming
  with jensyleo before it's usable for anything.

### Development references

Not sources for *your* DAT/ROM files — these are the technical references
consulted while building ROMForge itself (file formats, real-tool
behavior, known bugs to avoid repeating). Full context and specific
citations for each are in [ROADMAP.md](ROADMAP.md); this is the
consolidated list of sites/projects behind that research:

- [MAME's own source](https://github.com/mamedev/mame) — `-listxml`/
  software-list DTD, and the CHD format itself (`chd.h`/`chd.cpp`/
  `chdcodec.cpp`).
- [MAME docs](https://docs.mamedev.org) — romset conventions
  (`usingmame/aboutromsets.html`), MAME's data plugin
  (`plugins/data.html`).
- [Logiqx's own DTD](https://github.com/Logiqx/logiqx-www) — the
  Logiqx/ClrMamePro XML format definition.
- [ClrMamePro's own docs](https://mamedev.emulab.it/clrmamepro/docs/htm/datfile.htm)
  (`datfile.htm`), plus its
  [merger docs](https://mamedev.emulab.it/clrmamepro/docs/htm/merger.htm) —
  used to verify `MAMESetLayoutPlanner`'s Split/Merged/Non-Merged
  implementation against the universal standard (2026-07-28).
- [RomCenter's forum](https://www.romcenter.com/forum/) — real,
  documented merge-mode/BIOS-handling bugs and edge cases from actual
  users, cross-referenced against ROMForge's own behavior so the same
  mistakes aren't repeated.
- [Emulab forum](https://www.emulab.it/forum/) — additional MAME/romset
  behavior confirmation.
- [RomVault](https://www.romvault.com) / [its wiki](https://wiki.romvault.com) —
  TorrentZip's real specification (`trrntzip_explained.pdf`) and FAQ, plus
  its [merge_types page](https://wiki.romvault.com/doku.php?id=merge_types) —
  used to verify `MAMESetLayoutPlanner`'s Split/Merged/Non-Merged
  implementation against the universal standard (2026-07-28).
- [Retro Arcade Guides' MAME wiki](https://pleasuredome.miraheze.org/wiki/MAME_Split_Merged_and_Non-Merged_Sets) —
  another real-world explainer of the same Split/Merged/Non-Merged
  convention, cross-referenced during the same verification pass.
- [libretro/libretro-database](https://github.com/libretro/libretro-database) —
  a real No-Intro DAT example referenced during Logiqx-format testing.
- [TOSEC](https://www.tosecdev.org/tosec-naming-convention) — TOSEC's own
  naming convention documentation.
- [libchdr](https://github.com/rtissera/libchdr) — reference CHD
  decoding implementation (BSD-3-Clause, license-compatible).
- [AntoPISA/MAME_SupportFiles](https://github.com/AntoPISA/MAME_SupportFiles) —
  MAME sidecar metadata files (`catver.ini`, `nplayers.ini`, etc.) for
  the future metadata work.
- [Redump](http://redump.org) — a real disc-based DAT example
  (`datfile/psx/`) referenced during CHD/disk-matching work.
- [Batocera.linux](https://github.com/batocera-linux/batocera.linux) —
  the game-list UI ROMForge's own future visual library view takes
  inspiration from (see this file's intro — ROMForge itself will never
  become a launcher/frontend the way Batocera is).

### MAME ecosystem resources

A broader reference matrix jensyleo shared, covering the whole MAME
ecosystem — not all of it is a ROMForge dependency or something the app
integrates with; kept here as a reference list. Entries already linked
above (mamedev.org, docs.mamedev.org, Arcade Database, MobyGames, Archive.org,
progettosnaps.net, TOSEC, Redump) aren't repeated.

**Official project**

- [Wiki MAME](https://wiki.mamedev.org)

**Game databases**

- [Progetto EMMA](https://www.progettoemma.net) — emulation status, ROM/CHD
  requirements per machine.
- [Arcade History](https://www.arcade-history.com) — arcade machine history.
- [Arcade Museum / KLOV](https://www.arcade-museum.com) — cabinet/PCB history.
- [Games Database](https://www.gamesdatabase.org) — general retro game database.
- [Wikipedia](https://en.wikipedia.org)

**Arcade hardware**

- [System16](http://www.system16.com) — Sega arcade hardware specifically.

**ROM management (other tools, not ROMForge)**

- [ClrMamePro](https://mamedev.emulab.it/clrmamepro) / [RomCenter](https://mamedev.emulab.it/romcenter) —
  already referenced under "Development references" above as the tools
  ROMForge's own workflow is inspired by.
- [RomVault](https://www.romvault.com) — same, already referenced above.

**Frontends** (ROMForge itself deliberately isn't and won't become one — see
this file's intro):

- [LaunchBox](https://www.launchbox-app.com)
- [Attract Mode](https://attractmode.org)
- [HyperSpin](https://hyperspin-fe.com)
- [EmulationStation](https://emulationstation.org)

**Artwork/multimedia**

- [Mr. Do's Arcade](https://mrdo.mameworld.info) — bezels, marquees, control
  panels, flyers, side art, PCB scans.
- [Arcade Artwork](https://www.arcadeartwork.org)
- [Progetto Snaps](https://www.progettosnaps.net) (also the DAT source
  above) — snapshots, titles, cabinets, icons, videos, logos.
- [EmuMovies](https://emumovies.com) — video snaps for frontends.

**Flyers/manuals**

- [Arcade Museum flyers](https://flyers.arcade-museum.com)
- [ReplacementDocs](https://www.replacementdocs.com)

**History/support `.dat`/`.ini` files** (sidecar metadata files MAME/
frontends can read alongside a romset, not DAT files ROMForge itself
audits against): `history.dat`, `mameinfo.dat`, `command.dat`,
`gameinit.dat`, `messinfo.dat`, `catver.ini`, `genre.ini`, `series.ini`,
`bestgames.ini`, `nplayers.ini`, `languages.ini`, `controls.ini`,
`mature.ini` — see [AntoPISA/MAME_SupportFiles](https://github.com/AntoPISA/MAME_SupportFiles)
above for where to actually get these.

**Cheats**

- [MAME Cheat](https://www.mamecheat.co.uk)
- [andrewj76/mame-cheat](https://github.com/andrewj76/mame-cheat)

**High scores**

- [RetroAchievements](https://retroachievements.org)
- [Twin Galaxies](https://www.twingalaxies.com)

**Forums/community**

- [MAMEWorld Forums](https://forums.bannister.org)
- [r/MAME](https://www.reddit.com/r/MAME)
- [Arcade Projects](https://www.arcade-projects.com)
- [Build Your Own Arcade Controls](https://forum.arcadecontrols.com)

**A note on ROMs**: MAME (and ROMForge) require ROM sets, and in some
cases CHD files, that this project does not distribute or link to.
Obtain ROMs legally — from software you legitimately own, public-domain
titles, or otherwise properly licensed sources.

## Ideas considered and deliberately deferred

- **Whole-archive content hash as a rescan cache fallback** (discussed
  2026-07-28). A rescan today invalidates a zip's cached per-entry hashes
  whenever the archive's own `(size, modificationDate)` no longer matches
  what was recorded last time — cheap for the common "nothing changed"
  case, but it means a `mtime` that drifts without the content actually
  changing (e.g. iCloud Drive re-syncing a file) still forces a full
  internal re-hash. The idea: fall back to a fast whole-archive hash (CRC32
  over the zip's own compressed bytes, no decompression) before assuming a
  full rehash is needed — if it matches, skip straight to reusing the
  cached per-entry hashes. jensyleo's own call: rescans are something the
  user explicitly triggers, so this extra cost/complexity isn't worth it
  for now — deliberately **not implemented**, kept here to revisit later
  in case that changes.

## Design principles

1. Core (`ROMForgeCore`) never depends on the UI — every feature works
   headless, so the SwiftUI app is just one consumer among possible others
   (today's `romforge-cli` is a minimal DAT-parsing demo, not a full pipeline).
2. One responsibility per module: DAT parsing, scanning, hashing, matching and
   rebuilding are independent, composable pieces.
3. No unverified reporting — a ROM is only "correct" when its computed hash
   matches the DAT, never by filename alone.

## Building

Requires Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and
macOS 15+.

```bash
Scripts/build.sh          # generate, build, install
Scripts/build.sh --run    # ...and launch it
```

### Homebrew dependencies

CHD's `lzma`/"cdlz" hunk codec links against Homebrew's `liblzma`, not
bundled with macOS the way zlib (part of `libSystem`) is:

```bash
brew install xz
```

Built/tested against `xz` 5.8.3. If a future update changes `liblzma`'s C
API in a way that breaks the build, check
`ROMForgeCore/Sources/CLZMA/shim.h` first — it hardcodes the Homebrew
include path directly (Xcode's own build doesn't reliably pick up
`Package.swift`'s header search path for an embedded SPM package the way
`swift build` does).

`brew install flac` is also required at build time (`CFLAC` module,
`ROMForgeCore/Sources/CFLAC/`) even though no code calls into it yet — it
was wired in ahead of implementing CHD's "cdfl" (CD+FLAC) codec, which
remains unimplemented (see ROADMAP.md). Safe to leave installed; nothing
regresses if it's ever dropped once cdfl support lands or is abandoned.

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
