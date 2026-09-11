# Manual testing checklist

Automated coverage (151 unit tests, `swift test --package-path ROMForgeCore`)
and static build verification are in place, using synthetic fixtures (small
in-memory files, hand-built DAT/CHD headers). **Nothing here has been run
against a real ROM/BIOS/CHD collection** — that requires ROM files Claude
cannot legally source or possess, so every item below needs to be run by you,
with your own legally-owned dumps. Each item now has explicit step-by-step
instructions, not just a one-line goal. Run them when convenient, in any
order — they're independent except where noted.

Before starting: back up (or work on a copy of) your real ROM/BIOS/CHD
folders. Some sections below (Repair, "rename one file", "delete one file")
deliberately modify files on disk.

---

## 1. DAT parsing

### 1.1 Real No-Intro/Redump DAT (console/handheld, non-MAME)
- [ ] Download or locate a real No-Intro or Redump DAT for a system you have
      real ROMs/discs for (a few thousand games is a good stress size).
- [ ] In ROMForge, add a new system (⌘N or the "+" in the sidebar), pick that
      system's console/name, and point "DAT file" at the downloaded `.dat`.
- [ ] Confirm the DAT loads without error and the game count shown in the
      app matches what the DAT's own header (`<header><game count>` or
      similar, or just the number of `<game>`/`<machine>` entries if you
      `grep -c` the file) claims.

### 1.2 Real MAME `-listxml` dump
- [x] **Done 2026-07-21** — see `CHANGELOG.md`. No further action needed
      unless you want to re-verify with a newer MAME version.

---

## 2. Scan / Hash / Match / Reports

### 2.1 Known-good folder → 100% Correct
- [x] **Done 2026-07-21** — see `CHANGELOG.md`. Safe to re-run any time as a
      quick smoke test: Scan Folder on a folder you know is byte-exact
      correct should always come back 100% Correct / 0 Incorrect / 0
      Missing / 0 Surplus.

### 2.2 Rename → "Incorrect"
- [ ] Pick one ROM (or one entry inside a `.zip`) that currently shows
      "Correct" in a scanned system.
- [ ] Quit ROMForge (so it isn't holding a stale in-memory scan open), or
      just note the game's current row.
- [ ] In Finder/Terminal, rename that file (e.g. `mslug.zip` →
      `mslug_renamed.zip`, or if it's an entry inside a zip, rename the file
      before zipping, or use `zip -j` tricks — simplest is a loose-file
      system, or rename the whole zip if the system uses one-zip-per-game).
- [ ] Re-run Scan Folder on that system.
- [ ] Confirm the renamed file's game now shows **Incorrect** — not Missing
      (the hash still matches something, just under the wrong name) and not
      Surplus (it's still recognized as belonging to a known game).
- [ ] Rename it back and rescan to confirm it returns to Correct.

### 2.3 Delete → "Missing"
- [ ] Pick one ROM/zip you know is Correct.
- [ ] Move it out of the folder (don't delete permanently — drag to a temp
      folder outside the ROM folder so you can restore it after).
- [ ] Re-run Scan Folder.
- [ ] Confirm that game now shows **Missing**.
- [ ] Move the file back and rescan to confirm it returns to Correct.

### 2.4 Add unrelated file → "Surplus"
- [ ] Copy any file NOT in the DAT (e.g. a random `.txt`, or a ROM from a
      completely different game not in this DAT) into the scanned folder.
- [ ] Re-run Scan Folder.
- [ ] Confirm it shows as **Surplus**.
- [ ] Remove it and rescan to confirm the Surplus entry disappears.

### 2.5 Large-collection timing
- [ ] Point ROMForge at your biggest real collection (ideally thousands of
      files / several GB — a full MAME romset or a large No-Intro set is
      ideal).
- [ ] Start Scan Folder and time it (stopwatch or just note wall-clock
      start/end from the in-app log timestamps, which are already
      millisecond-stamped, e.g. `[13:23:24]`).
- [ ] While the scan runs, confirm the app **stays responsive** — you can
      still move/resize the window, switch sidebar systems, open Settings,
      etc. (scanning/hashing must not block the main thread).
- [ ] Note the total time somewhere (this TESTING.md, a comment, or just
      mentally) so future runs have a baseline to compare against if
      performance regresses.

### 2.6 Hash-algorithm selection actually changes behavior (functional, not cosmetic)
This is the CRC32/MD5/SHA1 toggle added recently — already verified once by
Claude directly inspecting the on-disk cache (see `CHANGELOG.md`), but worth
you confirming yourself too since it changes what protection you get against
false-positive matches:
- [ ] Open Settings (⌘,) → **General** tab. Confirm you see three toggles:
      CRC32, MD5, SHA1 (all on by default).
- [ ] Turn off MD5 and SHA1, leaving only CRC32 on.
- [ ] Scan a system (any real one). Confirm the scan still completes and
      games still show Correct/Incorrect as expected (CRC32 alone is enough
      to match against most DATs).
- [ ] Quit ROMForge, then inspect the cache file directly:
      `~/Library/Application Support/ROMForge/ScanCaches/<system-uuid>.json`
      (the UUID is per-system; if you have only one system it's the only
      file there). Open it in a text editor or `cat` it — confirm entries
      show `crc32` populated and `md5`/`sha1` **absent or null**.
- [ ] Re-enable MD5 and SHA1 in Settings, rescan the same system, and
      confirm the cache now shows all three hash fields populated again.

### 2.7 "Maximum subfolder depth" (added 2026-09-10)
- [ ] Reproduce the real case that surfaced this: create a folder shaped
      like `<ROM folder>/BATOCERA/<game>/<file>` (an extra organizational
      folder above the game level) and add it as (or point an existing
      system's) ROM folder.
- [ ] With Settings → General → "Maximum subfolder depth" at its default
      (1), scan it — confirm the Log shows "Skipped (nested too deep, not
      scanned): .../BATOCERA/<game>" and that game's roms show as
      **Missing**, even though the real files are sitting right there on
      disk.
- [ ] Raise "Maximum subfolder depth" to **2**, rescan the SAME folder —
      confirm the game is now found and scanned normally (no more skip
      message for it), with correct/incorrect status same as any other
      properly-read file.
- [ ] Quit and relaunch ROMForge (don't touch Settings first) — confirm a
      scan still respects the value you set (2), not the compiled-in
      default (1) — this is the part that needs applying at launch, not
      only when Settings happens to be open.
- [ ] Set it back to 1 — confirm the same BATOCERA-shaped folder goes back
      to being skipped (not a one-way, "leaked" setting).

### 2.8 "Scan Folder"/"Scan File" genuinely scope their own disk access (added 2026-09-11)
With at least two ROM folders configured for the same system:
- [ ] Run "Scan All Folders" once first, so every folder has a fresh cache
      entry.
- [ ] Select one specific ROM folder in the ROM folder panel, then run
      "Scan Folder". Watch the Log: confirm you now see "Scanning
      <that folder>…" and nothing else — no "Scanning <other folder>…"
      lines for folders you didn't select.
- [ ] Confirm the resulting report is still fully correct across BOTH
      folders — any duplicate ROM or parent/clone relationship spanning
      the two folders should still show correctly, not as if the other
      folder had vanished.
- [ ] Right-click a single game/file and choose "Rescan This File" (or
      "Scan File" from the menu on a selected node) — confirm the Log
      again shows only that one file, not every configured folder.
- [ ] Delete or move a file outside ROMForge (Finder), then use "Rescan
      This File"/"Scan File" on it — confirm the Log immediately shows
      "File not found: <path>" instead of silently finishing and only
      then flipping the row to Missing.

---

## 3. Repair (Fix)

⚠️ This section modifies files on disk. Work on a **copy** of a real folder,
not your only copy.

- [ ] Take a folder of correctly-hashed but misnamed ROMs (rename a few
      correct files to wrong names, e.g. swap two games' filenames, or
      rename `mslug.zip` → `wrongname.zip` while its contents are still the
      real, correct `mslug` data).
- [ ] Scan it — confirm the misnamed files show as Incorrect (or
      Missing+Surplus pairs, depending on how ROMForge classifies a
      correct-hash-wrong-name file — note whichever it is).
- [ ] Run **Fix** (the repair action) on that system.
- [ ] Confirm the misnamed files are renamed in place to their correct
      names.
- [ ] Rescan and confirm 100% Correct now.
- [ ] Separately: run Fix again on a folder that's ALREADY 100% Correct and
      confirm it makes **no changes at all** (no files touched, nothing in
      the log about renames) — Fix should be a no-op on an already-correct
      set, and it must never touch genuinely Missing entries (there's
      nothing to rename them from).

---

## 4. Archives

### 4.1 Zip sets
- [ ] Scan a folder of real `.zip` ROM sets (one zip per game, the common
      MAME/arcade layout).
- [ ] Confirm each zip's internal entries are listed correctly (expand the
      game row in the UI if there's a per-file breakdown) and hashed/matched
      against the DAT correctly.

### 4.2 Zip rebuild
- [ ] If ROMForge has a rebuild/export-to-zip feature active in your build,
      rebuild a set as `.zip` and confirm:
  - [ ] The resulting `.zip` opens correctly in Finder (double-click) and in
        The Unarchiver or `unzip -l`.
  - [ ] Rescanning the rebuilt zip against the same DAT shows Correct.
- [ ] (If this feature isn't wired into the UI yet in your build — check
      `ROADMAP.md`/`CHANGELOG.md` for TorrentZip status — skip this and note
      it as not-yet-applicable rather than a failure.)

### 4.3 7-Zip sets
- [ ] Install the official 7-Zip: `brew install sevenzip`.
- [ ] Scan a folder of real `.7z` sets. Confirm `SevenZipLocator` finds the
      Homebrew install (no manual path config needed) and entries
      list/hash/match correctly.
- [ ] Uninstall it temporarily (`brew uninstall sevenzip`) and try scanning
      `.7z` files again. Confirm ROMForge shows a clear, accurate error
      message with correct install instructions (not a crash or a silent
      empty result).
- [ ] Reinstall it afterward (`brew install sevenzip`) if you use it
      normally.

---

## 5. MAME: parent/clone, BIOS, set layouts

### 5.1 BIOS dependency chain
- [ ] Using a real MAME DAT and a real Neo-Geo (or other BIOS-dependent)
      game plus its BIOS set (e.g. `mslug` + `neogeo`), select that game in
      the UI and check wherever `BIOSResolver`'s output surfaces (game
      detail panel / dependency info).
- [ ] Confirm it correctly reports the full chain: the game requires
      `neogeo`, and if `neogeo` itself has sub-dependencies those show too.

### 5.2 Rom merge mode (3-way: Merged / Split / Un-merged)
- [ ] Open Settings (⌘,) → **Systems** tab, select your MAME system.
- [ ] Set **Rom merge mode** to **Split**. Rescan. Confirm parent and clone
      ROMs are expected as **separate** files — a clone's zip should only
      need to contain files that differ from its parent (check against what
      you actually have on disk for a parent/clone pair you own, e.g. `wh1`/
      `wh2`).
- [ ] Change **Rom merge mode** to **Merged**. Rescan. Confirm the app now
      expects clone-specific files to be present **inside the parent's
      zip**, not as a separate clone zip.
- [ ] Change **Rom merge mode** to **Un-merged** (the new default). Rescan.
      Confirm each clone is expected to contain its **entire** file set
      (parent's files + its own), independent of any other zip.
- [ ] For each of the 3 modes, confirm the in-app log or a "Changes re-parse
      this system's DAT" note appears (merge-mode changes should trigger a
      DAT reparse, not silently reuse a stale in-memory layout).

### 5.3 Bios merge mode (independent 3-way)
- [ ] Still in Settings → Systems for the same MAME system, set **Bios
      merge mode** independently of whatever Rom merge mode you left it at
      (e.g. Rom = Un-merged, Bios = Split — this is the shipped default; try
      the other two combinations too).
- [ ] With **Bios merge mode = Split**, confirm the BIOS (e.g. `neogeo.zip`)
      is expected as its own separate file, not folded into every game that
      needs it.
- [ ] With **Bios merge mode = Merged**, confirm BIOS content is expected
      folded into the parent game's zip instead of standing alone.
- [ ] With **Bios merge mode = Un-merged**, confirm BIOS content is expected
      duplicated into every game (parent and clones) that needs it.
- [ ] Confirm changing Bios merge mode does NOT also silently change Rom
      merge mode, and vice versa — they're independent settings; this is
      the main thing this feature exists to guarantee (see `CHANGELOG.md`'s
      "BIOS merge mode is now a real 3-way setting" entry for why).

### 5.4 Real MAME can load the resulting set
- [ ] For at least one small arcade romset you have (a handful of games +
      their BIOS), build/arrange the files on disk to match one merge-mode
      layout ROMForge reports as correct.
- [ ] Point a real MAME install (`brew install mame`, or your existing copy)
      at that folder (`mame <shortname> -rompath /path/to/folder`) and
      confirm **MAME itself launches the game** without a "ROM not found" or
      checksum error. This is the real ground-truth test — ROMForge saying
      "Correct" and MAME actually booting the game should agree.

---

## 6. CHD

### 6.1 Real CHD verification
- [ ] Get a real `.chd` you legally own (e.g. a PSX or arcade CD-based game,
      produced by the real `chdman` tool — `brew install mame` includes
      `chdman`, or use one you already have).
- [ ] Confirm the DAT you're using declares that disk's `<disk sha1="...">`
      value (open the DAT in a text editor and search for the game's disk
      entry if unsure).
- [ ] Scan the system containing that CHD.
- [ ] Confirm `CHDMatcher` reports it as **correct** — this is the first
      time this code path runs against a CHD produced by real `chdman`
      rather than a synthetic hand-built header, so treat any mismatch here
      as a real, reportable bug rather than assuming it's your file.

### 6.2 Corrupted/truncated CHD
- [ ] Make a copy of a real, working `.chd` (don't touch your original).
- [ ] Truncate it: `dd if=copy.chd of=truncated.chd bs=1M count=1` (keeps
      only the first 1MB — enough to have a valid-looking header but
      missing hunk data), or corrupt a few bytes in the middle with a hex
      editor.
- [ ] Put `truncated.chd` in place of the real file in a scanned folder (or
      as an extra file) and rescan.
- [ ] Confirm ROMForge reports it cleanly as "not a valid CHD" / truncated /
      corrupt — **not a crash**, and not silently reported as Correct or
      Missing.
- [ ] Delete the truncated/corrupted test file afterward.

### 6.3 Parent/diff CHD
- [ ] If you have a CHD with a non-zero `parentsha1` (a diff image against a
      parent — common for CHD update/diff sets), scan the system containing
      it.
- [ ] Confirm `parentSHA1` is read and reported correctly (check wherever
      that surfaces — game detail panel or a log line).
- [ ] (If you don't own any parent/diff CHDs, skip this — note it as
      not-tested-for-lack-of-fixture rather than a failure.)

---

## 7. Multi-system sidebar

- [ ] Add at least 3-4 real systems you actually have (e.g. NES, SNES,
      Genesis, PS1, MAME — whatever mix you own), each with its own real DAT
      + real folder.
- [ ] Scan each one independently. Confirm each system's results are
      correct and don't bleed into another system's counts/status.
- [ ] Quit ROMForge completely (⌘Q, not force-kill) and relaunch.
- [ ] Confirm all systems are still listed, in the same order, with their
      last-known scan status still showing (not reset to "never scanned").
- [ ] Remove one system (whatever the removal UI is — right-click/context
      menu or a "-" button).
- [ ] Quit and relaunch again. Confirm the removed system is gone and check
      `~/Library/Application Support/ROMForge/` for orphaned files (a
      `ScanCaches/<uuid>.json`, `DATCaches/<uuid>.json`, or similar left
      behind for the deleted system's old UUID) — there should be none.

---

## 8. Export

- [ ] Run a real scan on any system with a decent number of games (dozens+).
- [ ] Export the report (whatever the export action is — menu item or
      button) to CSV.
- [ ] Open the CSV in a real spreadsheet app (Numbers/Excel/Google Sheets).
- [ ] Confirm columns are correct (game name, status, path, hashes —
      whatever the report includes) and every row's status matches what the
      app showed on screen.
- [ ] Stress-test escaping: if any of your real game/file names contain a
      comma, quote, or newline (rare but check a MAME set — some official
      game descriptions do have commas, e.g. "Street Fighter II: The World
      Warrior, Japan"), confirm that row didn't get corrupted/misaligned in
      the CSV (the value should be properly quoted, not split into extra
      columns).

---

## 9. Duplicates, wrong names, and every state — Finder/RomCenter philosophy (added 2026-08-05)

Added after the "own-archive-only" matching rewrite (see git log around
2026-08-05: `blazstar copy.zip`/`ghouls copy.zip` cross-game leak bugs). Goal:
systematically confirm every duplicate/misnamed scenario lands on the right
`AuditStatus`, and that no game/rom ever shows correct/partially-correct
content it doesn't actually, physically own. **Planned for tomorrow — none of
this run yet.**

### 9.1 The states this app can show (updated 2026-08-06 — gray-file split)

| State (`AuditStatus`) | What it means | How the panel shows it |
|---|---|---|
| `correct` | Right file, right name, right hash, inside the game's OWN archive | Green ✓, "Ok" |
| `incorrect` | Right content (hash matches) but wrong name, and/or a genuinely known duplicate elsewhere | Yellow ▲ — "Bad file name" / "Rom need fix" / "Duplicated file, not needed here" / "Duplicated archive, not needed here (required by X)" |
| `badDump` | A file sits in the rom's own expected slot, but its hash is wrong (corrupt/bad dump) | Orange ⯁ — "Bad (hash mismatch)" |
| `missing` | Nothing matching this rom exists anywhere the app can see | Red ✕ — "Incomplete (rom missing)" |
| `unverifiable` | The rom is DAT-declared `nodump`; detected by NAME globally, in ANY archive — a file sits in its exact slot but there's no hash to check | Light gray ⊘ — "Nodump (unverifiable)" |
| `surplusInArchive` **(new)** | Hash matches no rom in the whole DAT, but the containing archive's name IS a real DAT machine — likely a leftover/duplicate | Gray ⚠ — "Extra file in archive" / "Unrecognized (inside a known archive)" |
| `unknownFile` **(new)** | Hash matches nothing, archive (if any) isn't recognized either — genuine junk | Gray ❓ — "Unrecognized" / "Unknown file in archive" / "Unknown game" |

Also confirm the row-level (not just entry-level) aggregate text: "Ok",
"Incomplete (rom missing)", "Bad (hash mismatch)", "Bad file name", "Rom need
fix", "Duplicated file, not needed here", "Extra file in archive",
"Ok (contains a nodump rom)".

### 9.2 Combinations to test

For each row: set it up, run a full rescan (not partial), record the actual
game-row status + entry-level status + File Name column text, and flag
anything that doesn't match "Expected".

| # | Setup | Expected game-row state | Expected File Name |
|---|---|---|---|
| 1 | A game's own archive present, untouched | **Confirmed 2026-08-11.** `correct` | its own `name.zip` |
| 2 | A game's own archive missing entirely, nothing else touches it | **Confirmed 2026-08-11.** `missing` | game's short name (no file) |
| 3 | Copy a game's own archive (Finder duplicate) to a NEW name, same folder | Original: `correct`. Duplicate: `incorrect`, "Duplicated archive…" | Original keeps its name; duplicate shows its own new name |
| 4 | Copy a game's own archive to a SECOND configured ROM folder, same name | Original: `correct`. Duplicate: shows as `incorrect`/"required by X" surplus, not silently swallowed. **Then verify it's stable:** "Scan Folder" on folder A, confirm the game still appears under folder B; "Scan Folder" on B, confirm it still appears under A. Neither copy may ever vanish, and the duplicate must stay flagged either way (regression: the 2026-08-06 flip-flop) | — |
| 5 | Copy a game's own archive into a subfolder past the depth-1 scan limit | **Confirmed 2026-08-11.** Skipped + reported in the log, not silently ignored, not counted as duplicate | — |
| 6 | Rename ONE entry INSIDE a game's own real archive to a nonsense name (e.g. `XXXXPPP`) | **Confirmed 2026-08-11.** `incorrect`, "Bad file name" | the archive's real name (unchanged) |
| 7 | Rename the WHOLE archive (Finder rename, not copy) to a nonsense name — e.g. `1943.zip` → `1949.zip` | **Verified 2026-08-06.** Game row: `incorrect`, "Bad file name — rename 1949.zip to 1943.zip". Renamed archive's own row: "Bad file name — rename to 1943.zip". Never green (the game still doesn't claim from a foreign-named archive), and never called a duplicate — nothing is duplicated and the file IS needed. Requires ≥60% of the archive's files to be that one game's roms, and that game to own no archive of its own | game's short name |
| 7b | Same as #7, but ALSO leave a correctly-named copy elsewhere (so both `1943.zip` and `1949.zip` exist) | Now the renamed one IS a spare: `1943.zip` green/`correct`, `1949.zip` back to "Duplicated archive, not needed here". The app must never suggest renaming over a good set | — |
| 8 | Corrupt/truncate one byte of a real rom inside its own archive (bad dump) | **Verified 2026-08-11.** `badDump`, "Bad (hash mismatch)". Fixed a real ghost-duplicate bug along the way (2026-08-10, commit `cb744f2`): the corrupted file used to also reappear a second time as a gray "Unrecognized" surplus row for the identical bytes — confirmed gone | unchanged |
| 9 | Delete one rom from inside an otherwise-correct archive | **Confirmed 2026-08-11.** that rom: `missing`; game row: `incorrect`/"Rom need fix" if it has its own real problem | unchanged |
| 10 | Add a genuinely unknown/junk file into a game's own archive | `surplusInArchive` entry, "Extra file in archive" fold-in, game row stays otherwise correct | unchanged |
| 10b | A duplicate archive holding a MIX: some real roms of a game **plus** junk (e.g. `1943 copy.zip` with 4 real `1943` roms + a .docx + a screenshot) | **Verified 2026-08-06.** Archive row: yellow ⚠, "Duplicated archive, not needed here (required by 1943…)" — one real rom is enough, it must NOT go gray "Unknown game". The junk entries inside keep their own gray ❓ "Unrecognized" rows. Also confirm the header's "Incorrect" count includes this archive (row and counter must never disagree). Produced two bugs: the all-or-nothing rule, and an order-dependent lookup that broke when the archive's first entry was the junk one | the archive's own name |
| 11 | Add a genuinely unknown/junk file loose in the ROM folder (not in any archive) | `unknownFile` — its own "Unknown game" bucket | the junk file's own name |
| 11b | A whole archive of junk, named nothing like a real machine (e.g. `TEST 1.zip` full of screenshots) | **Verified 2026-08-06.** `unknownFile` (gray ❓), one row per physical archive. Crucially it must NEVER be proposed as some game's "Bad file name — rename to X" — the ≥60% rule only counts files matching real DAT roms, so junk can never reach the bar. Expected behavior, by design, not coincidence | the archive's own name |
| 12 | A CLONE's own archive present, parent's archive absent (Split mode) | **Confirmed 2026-08-11** (contra/gryzor, no files moved — gryzor.zip's own physically-present shared roms reclassify under Split regardless of whether contra.zip exists). Clone: `correct` for its own roms; the 9 shared-with-parent roms inside gryzor.zip show yellow "Duplicated file, not needed here (required by Contra)" | — |
| 13 | Same as #12 but Merged mode (clone has no archive of its own by design) | **Confirmed 2026-08-11 — corrected mid-test.** Gryzor's row disappears (folded into Contra); `gryzor.zip` shows as a yellow duplicate. **Contra itself goes RED** (`missing`/incomplete), not green as first assumed — verified against the real DAT: Merged raises Contra's own expected list from 12 to 104 roms (every clone's unique roms folded in), and those clones' own files physically live only in their own `.zip`s, which Contra's own-archive-only matching can never reach. Real insight: Merged only "works" cleanly if you actually build one combined archive per family — an Un-merged/Split-style collection (one zip per clone, jensyleo's own layout) will show every parent red under Merged | — |
| 14 | Same family, Un-merged mode, BOTH parent and clone archives present, each self-contained | **Confirmed 2026-08-11.** Both `correct` independently — this is jensyleo's normal/default mode | — |
| 15 | A `nodump` rom with NO real file anywhere | **⏳ PENDING (2026-08-11) — genuinely not tested.** No real case identified yet in jensyleo's collection (Gryzor's `007766.20d.bin`, the only nodump case tried so far, is #16's scenario — the file DOES exist). Needs a nodump rom whose exact name doesn't exist anywhere across the whole family before this can be confirmed live. Expected: that rom entry absent (no row at all) — NOT `missing`, NOT `surplus` | — |
| 16 | A `nodump` rom whose exact-named file DOES exist somewhere in its clone family | **Already satisfied — this is exactly Gryzor's `007766.20d.bin`, confirmed 2026-08-06.** `unverifiable`, "Nodump (unverifiable)" | — |
| 17 | Two totally unrelated games that legitimately share a real hardware sub-rom (e.g. CPS1 `aboardplds`, NeoGeo `sfix.sfix`/`sm1.sm1`) — only ONE of them has its own archive | **Already satisfied — this is exactly the Ganbare!/Ghouls'n Ghosts `aboardplds` case, confirmed 2026-08-06 (jensyleo has no `ganbare.zip`).** The owning game: `correct`. The other (no archive at all): stays fully `missing`, the shared rom shows at most `.foundElsewhere`, NEVER green/correct | game's short name for the absent one |
| 18 | A `.chd` duplicated (Finder copy) in the same CHD folder | **Confirmed 2026-08-11.** Original: `correct`. Duplicate: flagged as a known duplicate (see §9.3) | — |
| 19 | A `.chd` duplicated into a nested/BATOCERA-style subfolder past the depth limit | **Confirmed 2026-08-11.** Same skip-and-report behavior as #5 | — |
| 20 | A `.chd` renamed to a nonsense name (Finder rename, not copy) | **Confirmed 2026-08-11.** Should behave like #7's rom equivalent — confirm it does, this is the CHD gap noted in §9.3 | — |

### 9.3 CHD — flagged as "looks fine but not confirmed 100% Finder" (jensyleo, 2026-08-05)

`DiskAuditor`/`CHDMatcher` match purely by exact SHA1 against each game's own
declared `<disk>` — no cross-archive-name concept exists (CHDs aren't zip
entries), so in principle there's no equivalent of the rom-side "renamed
archive" bug. **Confirmed live 2026-08-11 — jensyleo ran #18/#19/#20 and
reported all three OK.**

- [x] #18 above: does a duplicated `.chd` get flagged the same way a
      duplicated `.zip` does (yellow, "duplicated, required by X"), or does
      it show up as a plain gray "Unknown"? — **OK**
- [x] #20 above: rename (not copy) a real `.chd` to a nonsense filename —
      does the game correctly show its disk as `missing` (Finder-strict,
      matching the new rom philosophy), or does something still resolve it
      by content regardless of filename? — **OK**
- [x] Confirm a `.chd` that matches NO `<disk>` in the DAT at all (orphan)
      still shows as a real, visible surplus row, not silently invisible.

---

## 10. Duplicate sets, parent/clone family, 1G1R, DAT compare, BIOS/CRC audits (added 2026-08-20)

Covers the read-only audit features added in the session behind commits
`59e38c9`, `ef8b1ec`, `8e604bd`, `6975fae` (`git log --oneline` in the repo
shows the exact messages). None of this has been run against a real
collection yet — everything below needs your own MAME set.

### 10.1 Cross-folder duplicate set detection
- [ ] In Settings → your MAME system's page, confirm it has **at least 2 ROM
      folders** configured under "Rom files" (add a second one temporarily
      if needed).
- [ ] Copy one game's own archive (e.g. `mslug.zip`), unchanged, into the
      **second** folder as well — so the exact same set exists physically in
      both configured folders.
- [ ] Run **Scan All Folders**.
- [ ] Confirm the copy in the second folder shows the blue `.duplicateSet`
      tint and its File Name column reads "Duplicate set (also in
      `mslug.zip`)" (the exact wording appears in the entry's info text —
      check the detail panel or hover).
- [ ] Confirm the header's status summary now includes a nonzero duplicate-
      set count, and that BOTH copies still individually appear (this must
      never make one of the two silently vanish — this is the same class of
      bug §9.2 row 4 above already guards against, just now flagged as its
      own distinct status rather than folded into "incorrect").
- [ ] Remove the extra copy and rescan; confirm the duplicate-set count
      returns to 0.

### 10.2 Parent/clone family indicator ("Family" column)
- [ ] In the Games table, right-click any column header → confirm a
      **"Family"** column exists (it ships visible by default — no need to
      enable it via the column picker, though you can still hide it there if
      you want).
- [ ] Pick a real MAME parent/clone pair you own (e.g. `contra`/`gryzor`) and
      make sure the parent's own archive is present and Un-merged/Split mode
      is in effect (see §5.2) so parent and clones are independent files.
- [ ] Scan the system. Select the **parent** row (e.g. `contra`). Confirm its
      "Family" cell shows "`n`/`m` clones" (present/total), in gray if
      complete or orange if some clones are missing.
- [ ] Remove (move out) one clone's archive and rescan. Confirm the parent's
      "n/m clones" count drops by one and turns orange.
- [ ] Now remove the **parent's** own archive but keep at least one clone's
      archive present, and rescan. Confirm that clone's own "Family" cell
      shows an orange warning triangle icon, and hovering it shows the tooltip
      "This clone is present, but its parent set (`<parent>`) is missing from
      the collection."
- [ ] Restore all files and rescan to confirm both indicators clear.

### 10.3 1G1R filter ("Show Only 1G1R")
- [ ] Open Settings → View Options → **"1G1R region priority"** section.
      Confirm you can reorder region tags (drag/using the up/down controls)
      and that there's a reset-to-default action.
- [ ] Pick an order (e.g. USA before Europe before Japan) for a real family
      you own with multiple region variants (e.g. a game with `(USA)`,
      `(Europe)`, `(Japan)` clones).
- [ ] Back in the Games table (no need to rescan — this is presentation-only,
      not scan-result-driven), confirm the variant matching your top-priority
      region shows a **yellow filled star** next to its name in the "Game
      name" column, and no other variant in that family does.
- [ ] Click the toolbar button (title reads **"Show Only 1G1R"** when off,
      with an outline star icon). Confirm the table now hides every
      non-starred variant of every family that has at least one recognized
      region, while a variant with no recognized region tag stays visible
      regardless.
- [ ] Confirm the button's title/icon flips to **"Show All Variants"** (filled
      star icon) while active, and clicking it again restores every hidden
      variant.
- [ ] Change the region order in Settings (move Japan above USA) and confirm
      the star moves to the Japan variant instead, without needing a rescan.

### 10.4 DAT version comparison
- [ ] With a system's DAT already loaded, click the toolbar's **"Compare DAT
      Versions…"** button (enabled once a DAT is loaded).
- [ ] In the sheet titled "Compare DAT Versions", click **"Choose Older
      DAT…"** and pick a genuinely different/older version of the same
      system's DAT (e.g. an older MAME `-listxml` dump, or the same DAT with
      a few `<machine>` entries manually deleted/renamed in a text editor if
      you don't have two real versions handy).
- [ ] Confirm three sections appear: **"Added (`n`)"**, **"Removed (`n`)"**,
      and **"Possible Renames (`n`)"**, each listing entries as `name —
      description` (Added/Removed) or `oldName → newName  (matched rom:
      romName)` (Renames), or "None" if a section is empty.
- [ ] Confirm this never touches your actual scan/audit — closing the sheet
      and checking the Games table shows no change from the comparison.
- [ ] Click **"Export as Text…"**, save the file, and open it in a text
      editor — confirm it contains the same Added/Removed/Possible Renames
      breakdown as the sheet.

### 10.5 Unused BIOS files (orphaned BIOS detection)
- [ ] Open Settings → your MAME system's page → **"Database tree branches"**
      section, and enable **"Unused BIOS files"** (it ships off by default).
- [ ] Pick a real MAME BIOS set you own (e.g. `neogeo.zip`) that no game
      currently in your scanned collection actually depends on — or
      temporarily remove every game requiring it from the scanned folder,
      leaving just the BIOS archive itself.
- [ ] Scan the system. In the "Database" tree, click **"Unused BIOS files"**.
      Confirm the orphan BIOS archive (e.g. `neogeo`) appears there, and that
      it does NOT appear if a real dependent game is present and scanned.
- [ ] Add back a game that depends on it and rescan; confirm it drops out of
      "Unused BIOS files".

### 10.6 Filename-embedded CRC check (GoodTools/TOSEC style)
- [ ] Enable **"Filename CRC mismatches"** the same way as 10.5 (Settings →
      system → Database tree branches).
- [ ] Take one real ROM file and rename it to include a GoodTools/TOSEC-style
      bracketed CRC that does NOT match its actual content, e.g.
      `Some Game [12345678].zip` (pick any 8 hex digits that aren't the
      file's real CRC32).
- [ ] Scan the system. Click **"Filename CRC mismatches"** in the Database
      tree. Confirm this file appears there.
- [ ] Rename it back (or fix the embedded CRC to the real value) and rescan;
      confirm it disappears from that category. Also confirm a file with NO
      bracketed CRC in its name at all never shows up here (nothing to
      mismatch against).

### 10.7 ZIP internal CRC cross-check (on-demand)
- [ ] Enable **"ZIP internal CRC inconsistencies"** the same way as 10.5/10.6.
- [ ] Take a real `.zip` ROM archive and corrupt its **central directory's**
      recorded CRC for one entry without touching the actual compressed
      bytes (a hex editor on the "CRC-32" field of one entry's central
      directory record is the reliable way — simply corrupting file bytes
      will just show up as a normal bad dump via the regular scan, not this
      check) so the zip's own local/central CRC disagrees with the entry's
      real, decompressed content.
- [ ] Scan the system normally first — note this mismatch does NOT surface
      automatically from a plain Scan Folder/Scan All Folders.
- [ ] Right-click that game's row in the Games table and choose **"Verify
      ZIP Integrity"** from the context menu (only enabled once a scan has
      run).
- [ ] Confirm the archive now appears under **"ZIP internal CRC
      inconsistencies"** in the Database tree, and that the log panel shows a
      completion line ending in "…entr(y/ies) with an internal CRC
      mismatch."
- [ ] Restore the original file and re-run "Verify ZIP Integrity" (or
      rescan); confirm it disappears from that category, and the log line
      instead reads "…no internal CRC inconsistencies found."

---

## 11. Fase 2 — Rebuild/Repair (write actions, added 2026-09-01)

⚠️ **Every test in this section modifies files on disk.** Work on a
**disposable copy** of real ROMs, never your only copy of a collection —
several of these actions are genuinely destructive (permanent deletion,
in-place archive rewriting) and this is their first real-ROM test pass.

**Setup once, used by every subsection below:**
- [ ] Pick 3-4 small real MAME sets you own legally, including at least one
      parent/clone PAIR (e.g. a game and one of its clones/bootlegs sharing
      some ROMs) — the clone-sharing case is what Step 3 (11.4) needs.
      Prefer small ROMs (a few KB–MB each) so copy/rebuild is fast to verify.
- [ ] Copy them into a scratch folder, e.g.
      `~/Desktop/ROMForge-Fase2-Test/roms/` — **never point any of this
      section's actions at your real, permanent collection.**
- [ ] Add that scratch folder as a ROM folder under your MAME system in
      ROMForge, and do one normal **Scan Folder** first — confirm it reports
      **Correct** for all of them before touching anything else. If it
      doesn't, fix the setup (wrong DAT version, wrong ROMs) before
      continuing — every test below assumes a clean, fully-Correct starting
      point.
- [ ] Settings → General → **Write access** → enable **"Enable file
      modifications"** (confirm the warning dialog). Every action in this
      section is disabled/grayed out in the toolbar until this is on.

### 11.0 Write-access gate itself
- [ ] With Write access OFF (the default), confirm every Fase 2 toolbar
      button below ("Rebuild to Folder…", "Remove Useless Files…", "Repair
      from Sibling Sets…") is visibly **disabled**, and hovering shows a
      tooltip explaining it's off in Settings.
- [ ] Turn it back off, then on again — confirm the buttons re-enable
      immediately without needing to relaunch or rescan.

### 11.0b "Scan Required" alert (added 2026-09-09)
- [ ] Quit and relaunch ROMForge, open a system you've already scanned
      before (so it shows its persisted results immediately, without you
      scanning again this session).
- [ ] Confirm every Fix button LOOKS enabled (this is deliberate — see
      CHANGELOG) — click **any** one of them (e.g. "Fix Mismatched Files")
      WITHOUT running Scan Folder/Scan All Folders first.
- [ ] Confirm a **"Scan Required"** alert pops up immediately (not just a
      line in the Log panel) telling you to scan first.
- [ ] Dismiss it, run a real Scan, then try the same action again —
      confirm it now works normally (preview count, confirmation, etc.)
      with no alert.
- [ ] Repeat for at least one preview-count-style action too (e.g.
      "Repair from Sibling Sets…") — confirm it shows the SAME alert
      immediately, before any folder picker or confirmation dialog
      appears.

### 11.1 Rebuild to Folder — loose files (Step 1)
- [ ] From your scratch scan, extract one game's `.zip` into loose files in
      its own subfolder (so you have a genuine loose-file source, not just
      zips) — re-scan that folder and confirm it's still Correct as loose
      files.
- [ ] Click the **"Fix"** toolbar dropdown → **"Rebuild to Folder…"**.
- [ ] Choose a NEW empty destination folder (e.g.
      `~/Desktop/ROMForge-Fase2-Test/rebuilt-loose/`).
- [ ] Confirm the dialog shows an accurate file count before you commit, and
      choose **"Copy"** (not "Move", for this first pass).
- [ ] Confirm the destination now has one subfolder per game
      (`<destination>/<game name>/<rom name>`), and that your ORIGINAL loose
      files are untouched (still present at the source).
- [ ] Add the destination as a new ROM folder and **Scan Folder** it —
      confirm it reports **Correct** for everything just rebuilt.
- [ ] Repeat once more choosing **"Move (removes from source)"** instead —
      confirm this time the source files are gone and only the destination
      has them.

### 11.2 Rebuild to Folder — zip-sourced roms (Step 1, the critical case)
This is the case a real bug was caught and fixed for before this test pass
existed (see CHANGELOG's "critical" fix entry) — a zip-sourced rom was
previously at risk of silently rebuilding as a corrupt copy of the WHOLE
zip instead of just that one rom. This subsection exists specifically to
confirm that fix holds up against real ROMs, not just the synthetic test
suite.
- [ ] Using your scratch folder's real `.zip` sets (untouched, still zipped
      — most MAME collections are exactly this), click **"Rebuild to
      Folder…"** again with a fresh empty destination.
- [ ] After it completes, for at least one multi-rom game: open the
      REBUILT files (now loose, per Step 1's own layout) and confirm each
      one's file SIZE and content look like an actual individual ROM —
      **not** the same size as the original `.zip` file repeated for every
      rom in that game (the exact shape of the bug that was fixed).
- [ ] Scan the rebuilt destination and confirm **Correct** for every rom —
      this is the real proof the extracted bytes are actually right, not
      just "the right size by coincidence."

### 11.3 Rebuild as TorrentZip (Step 2)
- [ ] Currently reached the same way as 11.1/11.2 above (rebuild always
      produces TorrentZip-conformant `.zip` output per game, per
      `RebuildPlanner.planRebuildAsZip`) — if a later build adds a visible
      "output format" choice in the UI, use that instead and note here
      which one you tested.
- [ ] Confirm each rebuilt `.zip` opens correctly in Finder (double-click)
      and in `unzip -l`/The Unarchiver — a valid, standard zip.
- [ ] `unzip -v <rebuilt.zip>` — confirm it lists every rom entry with a
      plausible CRC (compare against the DAT's own declared CRC for that
      rom if you want to cross-check by hand).
- [ ] Rescan the rebuilt zip — confirm **Correct**.

### 11.4 Repair from Sibling Sets (Step 3)
- [ ] Using your parent/clone pair from the setup step: pick one rom that's
      genuinely SHARED between the parent and the clone (same CRC — check
      the DAT, or just pick a rom neither set's own description marks as
      unique). Temporarily rename or delete that rom's file from the
      PARENT's own zip (keep the clone's copy of it intact) — e.g.
      `zip -d parent.zip sharedrom.bin` (adjust for the real rom name).
- [ ] Scan — confirm the parent now shows that one rom as **Missing**, and
      the clone still shows it (and everything else) as Correct.
- [ ] Click the **"Fix"** toolbar dropdown → **"Repair from Sibling Sets…"**.
- [ ] Confirm the preview count matches the number of missing roms you
      expect it to actually be able to fix (1, in this simple case).
- [ ] Confirm it — check the log for a success message, then **rescan**.
- [ ] Confirm the parent set is now **Correct** again, and inspect the
      parent's own `.zip` directly (`unzip -l parent.zip`) — confirm the
      borrowed rom is really IN there now, alongside every rom it already
      had (nothing else in that zip should have changed).
- [ ] Confirm the clone's own zip is completely untouched (same file count,
      same CRCs) — it's a donor, never a target.
- [ ] Separately: pick a game with EVERY rom missing (temporarily move its
      entire zip out of the scan folder) and confirm "Repair from Sibling
      Sets…" does **NOT** try to repair it even if a sibling has a matching
      rom — there's no existing "anchor" for that game, so it should be
      silently skipped (see the preview count: it should not include this
      game's missing roms).

### 11.5 Remove Useless Files (Step 7 — the most destructive item here)
- [ ] Drop one genuinely unrecognized loose file into your scratch ROM
      folder (e.g. a renamed text file with a `.bin` extension containing
      random content the DAT can't possibly declare).
- [ ] Scan — confirm it shows up as Surplus/unrecognized in the Database
      tree.
- [ ] Click the **"Fix"** toolbar dropdown → **"Remove Useless Files…"** — confirm the preview count is
      exactly right (don't confirm yet if it looks wrong).
- [ ] Confirm the deletion. Rescan — confirm the file is gone and the
      unrecognized-file count drops accordingly.
- [ ] **The critical real-ROM check**: add an extra, unrecognized entry
      INSIDE one of your real `.zip` sets alongside its legitimate roms
      (`zip <game>.zip somejunk.txt`) — scan, confirm it's flagged as
      surplus/unrecognized same as above, then run "Remove Useless
      Files…" again.
- [ ] Confirm the preview count for THIS run DOES include that zip-internal
      junk entry (entry-level removal is supported — `Archive.remove(_:)`
      under ZIPFoundation's `.update` access mode). Confirm it, then verify
      with `unzip -l <game>.zip`:
  - [ ] The junk entry is **gone**.
  - [ ] Every real rom that was already in that zip is **still there,
        completely untouched** (same CRCs as before). This is the single
        most important check in this whole section: a wrong result here
        would mean an unrelated rom got corrupted or lost while removing
        the one entry next to it.
  - [ ] The zip file itself still opens correctly (Finder double-click,
        `unzip -l`) — a valid archive, not corrupted by the in-place
        rewrite.

### 11.6 Make Self-Contained (Step 4 — "non-merged" direction only)
- [ ] Using the same parent/clone pair from 11.4, this time in the OTHER
      direction: pick a rom the CLONE inherits from the PARENT (i.e. the
      clone's own zip does NOT have it, but the parent's zip does — a
      genuinely shared rom under Split-mode-style layout). Scan and confirm
      the clone shows this rom as **matched** (not missing) but the Games
      table/Detail panel indicates it came from elsewhere (check whichever
      status label ROMForge shows for `.foundElsewhere` in your build —
      note it here).
- [ ] Click the **"Fix"** toolbar dropdown → **"Make Self-Contained…"**.
- [ ] Confirm the preview count is accurate, then confirm it.
- [ ] Rescan, then inspect the clone's own zip directly
      (`unzip -l clone.zip`) — confirm the inherited rom is now genuinely
      IN the clone's own archive too, alongside every rom it already had.
- [ ] Confirm the PARENT's zip is completely untouched — this action only
      ever ADDS, it should never remove the rom from where it already was.
- [ ] Note in this checklist which direction (Split/Non-merged/Merged)
      your MAME merge-mode Setting was actually configured to during this
      test, since "Make Self-Contained" only implements the non-merged
      direction — if you test with Merged or Split configured, note
      whether `.foundElsewhere` still appears the way this test expects,
      or whether the merge mode setting changes what gets flagged.

### 11.7 Fix Misnamed ROMs Inside Their Archives (Step 6 — entry-level)
- [x] **Confirmed live 2026-09-10** — jensyleo's real NEOGEO/CPS1 collection
      (shocktro.zip, cyberlip.zip, mslugx and others), through multiple
      rounds tracking down the macOS kernel vnode/namecache staleness bug
      (see CHANGELOG) rather than the exact shell-script repro below —
      same end result confirmed: a misnamed entry gets fixed, its container
      untouched, and the app's own display now reflects the real on-disk
      name immediately after (`FolderScanner`'s directory-listing fix).
- [ ] Using one of your real `.zip` sets, rename ONE internal entry to a
      wrong name without changing the zip's own filename — e.g.
      `printf '' > /tmp/dummy && cd /path/to/set && mv game.zip
      /tmp/backup.zip && unzip /tmp/backup.zip -d /tmp/extracted && cd
      /tmp/extracted && mv correct-rom-name.bin wrong-rom-name.bin && zip
      ../game.zip * && mv ../game.zip /path/to/set/` (adjust names/paths to
      your real set — the point is: the zip's own OUTER filename stays
      correct, only the ENTRY name inside it changes).
- [ ] Scan — confirm this specific rom now shows **Incorrect** (misnamed),
      not Missing.
- [ ] Click the **"Fix"** toolbar dropdown → **"Fix Misnamed ROMs Inside
      Their Archives…"**.
- [ ] Confirm the preview count is accurate, then confirm it.
- [ ] Rescan — confirm the rom is now **Correct**.
- [ ] Verify directly with `unzip -l game.zip`:
  - [ ] The wrong name is **gone**.
  - [ ] The correct name is **present**, with the exact same CRC as the
        original content (confirms the rename preserved the actual bytes,
        not a truncated/corrupted re-add).
  - [ ] Every OTHER entry in that same zip is **unchanged** (same CRCs,
        same count).
  - [ ] The zip file itself still opens correctly (Finder double-click).

### 11.8 Strip Redundant ROMs — Split direction (Step 4, the inverse of 11.6)
- [ ] Using the same parent/clone pair, set your MAME merge-mode Setting to
      **Non-merged** (or just leave a clone with the shared rom physically
      duplicated in its own zip — this test doesn't depend on the merge
      mode actually being enforced, only on the CLONE genuinely already
      having a copy).
- [ ] Confirm (via `unzip -l clone.zip`) the clone's own zip really does
      contain a copy of the shared rom, physically — not just showing as
      matched via `.foundElsewhere`.
- [ ] Click the **"Fix"** toolbar dropdown → **"Strip Redundant ROMs
      (Split)…"**.
- [ ] Confirm the preview count is accurate, then confirm it.
- [ ] Rescan, then `unzip -l clone.zip` again — confirm the shared rom is
      now **gone** from the clone's own archive, and every OTHER rom the
      clone had is still there.
- [ ] Confirm the PARENT's zip is completely untouched (`unzip -l
      parent.zip` — same entries, same CRCs as before).
- [ ] Rescan and check how the clone's family now reports — the clone
      should still show that rom as matched (now via whatever status this
      build uses for "found in parent's archive", not "correct" locally
      anymore) rather than Missing.
- [ ] Separately: confirm running "Strip Redundant ROMs (Split)…" again
      right after (nothing left to strip) reports a 0 count and makes no
      further changes — a clean no-op on an already-stripped scan.

### 11.9 Case policy, applied unconditionally by Fix Mismatched Files / Fix Misnamed ROMs (Step 9 — superseded 2026-09-10)
**"Apply Case Policy…" no longer exists as a separate action.** jensyleo's
own call (2026-09-10), after live-testing it as two side-by-side actions
sharing one Settings pair: "o es una o es la otra" — every scenario below
now runs through the toolbar's regular **"Fix Mismatched Files"** (Sets
case) and **"Fix Misnamed ROMs Inside Their Archives…"** (Roms case)
instead, each of which ALWAYS does both halves — repair a wrong name AND
re-style an already-correct one — in the same click, unconditionally (no
toggle can turn either half off; see 11.13's own rewrite below for why).
- [x] **Confirmed live 2026-09-10** — jensyleo's real NEOGEO folder: set
      **Sets case** to **Uppercase**, ran **"Fix Mismatched Files"** on a
      folder of already-uppercase `.zip` archives (`AWBIOS.zip` etc.) whose
      own DAT-declared name is lowercase — confirmed every archive's
      filename stayed/became uppercase and every game kept showing
      Correct.
- [x] **Confirmed live 2026-09-10** — set **Sets case** back to **Datafile
      Case**, ran "Fix Mismatched Files" again — confirmed archive
      filenames now match the DAT's own declared case exactly.
- [ ] Repeat for **Roms case** against real ROM-entry names inside a zip,
      via "Fix Misnamed ROMs Inside Their Archives…" — not yet explicitly
      re-verified against real entry names post-unification.
- [ ] Confirm content is untouched throughout — rescan after each pass and
      confirm 100% Correct, never Missing/Incorrect from either action
      alone.

### 11.9b A genuinely misnamed archive/rom is still fixed correctly, not left half-fixed (added 2026-09-11, re-verified 2026-09-10)
- [ ] Deliberately rename a real, currently-Correct game's `.zip` to something
      completely unrelated (e.g. `sfiii.zip` → `wrongname.zip`) so it now
      shows as **Incorrect** (misnamed).
- [ ] Set **Sets case** to **Uppercase**, run **"Fix Mismatched Files"**.
- [ ] Confirm it renames the archive to the DAT's own declared name styled
      per "Sets case" (e.g. `SFIII.ZIP`), never to a differently-cased
      version of the still-wrong name (`WRONGNAME.ZIP`) — "Don't Touch"/any
      case choice always derives the target from the DAT's OWN declared
      name for a genuine mismatch, never from the current wrong one (see
      `RebuildPlanner.mismatchFixName`'s own doc comment).
- [ ] Repeat the same check at the ROM-entry level via "Fix Misnamed ROMs
      Inside Their Archives…".

### 11.9c A container whose OWN game matches correctly, but whose filename case is wrong — fixed without needing "Roms case" run first (added 2026-09-10)
jensyleo's own real NEOGEO test: a whole folder of archives whose entries
match their own game by HASH, but whose CONTAINER filename ("AWBIOS.zip")
didn't match the DAT's declared case ("awbios.zip") — `planRepair` had no
code path for this at all (it only handled a loose file's own wrong name,
or a whole archive belonging to a DIFFERENT game); "Fix Mismatched Files"
silently reported "Nothing to fix" despite every File failing "Bad file
name". Fixed same day, then found the fix still required the ROM entry
inside to already be `.correct` (case already fixed) before it would
recognize the container as this game's own — jensyleo's own follow-up
correction: "el CRC32 identifica el archivo... aunque el nombre esté mal",
so this must NOT require "Roms case" to run first. Both are now confirmed:
- [x] **Confirmed live 2026-09-10** — a folder where every entry's OWN name
      already matched (post a prior "Roms case" pass) but the CONTAINER
      filename was still wrong-case: "Fix Mismatched Files" now renames the
      container correctly in one pass.
- [x] **Confirmed live 2026-09-10 (follow-up)** — a container wrong-case
      AND its own entry still under its OLD wrong name at the same time
      (no "Roms case" run yet): "Fix Mismatched Files" still renames the
      container correctly, since identity comes from the CRC32 hash, not
      from either name being right yet. See `RebuildPlannerTests
      .planRepairRenamesWrongCaseContainerEvenWithAStillMisnamedEntry`
      for the synthetic regression test.

### 11.10 Handle Corrupted Files (Step 8)
- [ ] Using a real `.zip` set, corrupt its **local header's** own CRC32
      field for one entry (the "10.7 ZIP internal CRC cross-check" section
      above already documents the hex-editor technique — a mismatch
      between the local header and the central directory, not a
      whole-file corruption).
- [ ] In Settings → **Fix** → "Corrupted files", set the policy to **Move
      to…** and choose a quarantine folder.
- [ ] Right-click that game in the Games table → **"Verify ZIP
      Integrity"** (or however your build surfaces this — see section 10.7)
      to confirm it's flagged.
- [ ] Click the **"Fix"** toolbar dropdown → **"Handle Corrupted Files…"**.
- [ ] Confirm the preview count is accurate, then confirm it.
- [ ] Verify: the corrupted entry is now GONE from the original zip
      (`unzip -l`), and a copy of it now exists in your chosen quarantine
      folder.
- [ ] Confirm every OTHER entry in that same zip is untouched.
- [ ] Repeat with the policy set to **Delete** instead (on a fresh copy of
      the corrupted zip) — confirm the entry is removed and NOT placed
      anywhere.
- [ ] Confirm setting the policy to **Don't Touch** and running the action
      again reports a 0 count and makes no changes.

### 11.11 Merge Clones — Merged direction (Step 4, the last remaining direction)

⚠️ This is the only Fase 2 action that deletes a WHOLE archive, not just
one entry. Work on your disposable scratch copy — never your real
collection — for this one especially.

- [ ] Using your parent/clone pair, confirm the CLONE has at least one rom
      that's genuinely its OWN (not shared with the parent) still
      physically in its own zip.
- [ ] Click the **"Fix"** toolbar dropdown → **"Merge Clones (Merged)…"**.
- [ ] Confirm the preview count is accurate, read the confirmation
      dialog's own wording carefully, then confirm it.
- [ ] Rescan, then:
  - [ ] Confirm the CLONE's own `.zip` file is now **completely gone** from
        disk.
  - [ ] `unzip -l parent.zip` — confirm the parent's zip now contains BOTH
        its own original roms AND the clone's own unique rom(s), and that
        every CRC matches what it was before (content preserved exactly).
  - [ ] Confirm the clone still shows as matched in the Games table
        (now via whatever status your build shows for "found in parent's
        archive" — `.foundElsewhere` — since it has no archive of its own
        anymore).
- [ ] Separately, test the safety guarantee directly: pick a DIFFERENT
      clone, and before merging, manually add an entry to the PARENT's own
      zip using the exact name one of that clone's own unique roms would
      need (`zip parent.zip -j /path/to/some/unrelated/file` renamed to
      collide). Run "Merge Clones (Merged)…" again.
  - [ ] Confirm the log reports that clone's own merge FAILED (not
        succeeded).
  - [ ] Confirm that clone's own `.zip` file **still exists**, completely
        untouched — the whole point of the ordering safety design.
  - [ ] Confirm the parent's zip is unchanged except for the earlier,
        deliberately-added colliding entry — nothing else from the clone
        leaked in partway.

### 11.12 Repair from Maintenance Folder (optional, read-only donor folder)
- [ ] Open Settings → **General** → "Maintenance folder (optional)". Confirm it shows "Not set"
      by default, with "Choose Folder…" and no "Clear" button until one is set.
- [ ] Click "Choose Folder…", pick any empty scratch folder (e.g.
      `~/Desktop/ROMForge-Fase2-Test/maintenance/`). Confirm the path now displays, and a "Clear"
      button appears.
- [ ] Take one rom your scratch collection is currently showing **Missing** (or make one missing:
      move a real rom's file out of its zip). Drop a copy of the exact same rom's real content
      into the Maintenance folder, under **any filename you like** — the point of this test is
      that the name is irrelevant, only the bytes matter.
- [ ] Click the **"Fix"** toolbar dropdown → **"Repair from Maintenance Folder…"**.
- [ ] Confirm the preview count is accurate (1, in this simple case), then confirm it.
- [ ] Rescan, then `unzip -l` the game's own zip — confirm the missing rom is now genuinely
      **present**, under its own DAT-declared name (not the donor file's own filename), with the
      correct content.
- [ ] Confirm the file you dropped into the Maintenance folder is **completely untouched** —
      still there, unrenamed, unmoved — the whole point of it being read-only.
- [ ] Clear the Maintenance folder setting (the "Clear" button in Settings) and confirm "Repair
      from Maintenance Folder…" now logs "No Maintenance folder configured…" instead of silently
      doing nothing.
- [ ] Separately: with the Maintenance folder set again but genuinely empty (or containing only
      unrelated content), confirm the action reports a 0 preview count and makes no changes —
      never a false match.

### 11.13 Settings → Fix tab (rewritten 2026-09-10 — no more mismatch on/off toggle)
There is deliberately **no toggle** to turn mismatch-correction off anymore
— jensyleo's own call (2026-09-10): fixing a name the DAT disagrees with is
the whole reason "Fix Mismatched Files"/"Fix Misnamed ROMs Inside Their
Archives…" (and this app) exist, so it was never really optional the way
"Test archives"/"Corrupted files" genuinely are. The only real knob left is
**how** the corrected (or already-correct) name gets STYLED — "Sets
case"/"Roms case" — which always applies, unconditionally, to both a
repaired mismatch and an already-correct re-style, in the same click.
- [ ] Open Settings → **Fix** — confirm every toggle from the ROADMAP's own
      "ClrMamePro Fix panel" review is present, and that the ones marked
      "not yet connected" in the UI's own caption text are visibly
      disabled (can't be toggled on) rather than silently doing nothing.
- [ ] Confirm there is NO toggle anywhere that can make "Fix Mismatched
      Files"/"Fix Misnamed ROMs Inside Their Archives…" skip a genuine
      mismatch — rename a real file/rom to something wrong and run either
      action; it should always fix it, regardless of any other setting on
      this tab.
- [x] **Confirmed live 2026-09-10** — the "Fix" section's own **"Reset to
      Defaults"** button (jensyleo's own request) resets **Sets case**/
      **Roms case** back to **Datafile Case**; every other section on this
      tab (Test & Verify, Remove, Corrupted files) has its own matching
      reset button too.
- [ ] Quit and relaunch ROMForge — confirm every setting you changed on
      this tab persisted correctly.

### 11.13f Multi-selection Fix — Games table AND Roms panel, entry-level scoping (added 2026-09-10)
jensyleo's own request: "La app no permite selección múltiple... Renombrar
roms de una o varias, también se debe poder" — both tables now support
⌘/⇧-click multi-select, with a real bug found and fixed along the way
(selecting 2 of 5 rom rows renamed all 4/5 of them — container-level
scoping alone can't tell "these 2 rows" from "every rom sharing this
container" when they all share one archive).
- [x] **Confirmed live 2026-09-10** — Games table: select 2+ File rows
      (⌘-click), right-click → "Fix N Mismatched Files"/"Fix Misnamed ROMs
      Inside These N Archives…" — confirmed only the selected Files'
      containers are touched, others untouched.
- [x] **Confirmed live 2026-09-10 (after a real bug fix)** — Roms panel:
      select exactly 2 of several rom rows sharing the SAME container,
      right-click → "Fix These 2 Misnamed ROMs…" — confirmed only those 2
      specific entries get renamed, not every fixable entry in that
      archive. (Originally reported as "selecciono 2 roms y me renombra
      las 4" — root cause was `restrictPairsToScope` only filtering by
      container path, a no-op when every selected row shares one container;
      fixed via `LibraryViewModel.entryScopeKey`/`restrictPairsToEntries`.)
- [x] **Confirmed live 2026-09-10** — the Roms panel's context menu never
      shows "Fix Mismatched File" at all (File-level, container-scoped —
      jensyleo's own explicit call: that concept doesn't belong in a
      per-ROM-entry list, only in the Games table). Only "Fix This/These
      Misnamed ROM(s)…" appears there, and only when there's genuinely
      something to fix (see 11.13g).

### 11.13g Fix menu items hidden when there's genuinely nothing to fix, not just disabled (added 2026-09-10)
- [x] **Confirmed live 2026-09-10** — select rows/Files that already read
      "Ok"/Correct for a chosen scope; right-click — confirm the relevant
      Fix action doesn't appear at all (not merely greyed out), computed
      from the exact same `planFixPreviewCount`/
      `planRenameRomsInArchivePreviewCount` the confirmation dialog itself
      uses, so "would this button do anything" can never disagree with
      "what actually happens on click".
- [x] **Confirmed live 2026-09-10 (real bug + fix)** — opening EITHER
      context menu (Games table or Roms panel) on a freshly-launched app,
      BEFORE running any Scan this session (only a persisted, past-session
      report showing on screen) used to pop the "Scan Required" alert
      immediately from a plain right-click — `requireMatchReport()`'s own
      alert side effect firing just from building the menu's preview
      counts. Fixed via a side-effect-free `LibraryViewModel
      .hasMatchReport` check, called first. Confirm right-clicking a row in
      that exact state (fresh launch, no Scan yet) shows the normal context
      menu with no Fix items and no alert.

### 11.13h "Rescan required" gate — a Fix can't run on a scope the LAST Scan didn't cover (added 2026-09-10)
jensyleo's own explicit, deliberately universal rule: "si le doy rescan
file a un archivo y le doy fix a otro. Esta acción no debería permitirse" —
confirmed as intentional even though `ScanCache` already re-verifies every
file's own size+mtime on every scan regardless of scope (so this is a
workflow safeguard on top of that, not a patch for an actual data-integrity
gap). Applies to every Fase 2 write action, not just the two scoped ones.
- [x] **Confirmed live 2026-09-10** — Rescan one specific File ("Rescan This
      File"), then right-click a DIFFERENT File/selection and choose any
      Fix action — confirm it's BLOCKED: a "Rescan Required" alert pops up
      (in addition to a Log line), naming the scope that wasn't covered,
      and nothing on disk changes.
- [ ] Run "Scan Folder" on ONE folder only (not "Scan All Folders"), then
      try a whole-system Fix action (e.g. "Remove Useless Files…", which
      has no per-file scope of its own) — confirm it's blocked too, since
      the last Scan only covered one folder, not the whole system.
- [ ] Run "Scan All Folders" (or "Scan Folder" covering everything
      configured), then run any Fix action — confirm it proceeds normally,
      no alert.

### 11.13b "Sets case" / "Roms case" — shared by Fix Mismatched + Apply Case Policy (added 2026-09-09, merged 2026-09-10)
Originally two SEPARATE settings pairs ("Fix files to"/"Fix ROMs to" vs "Sets case"/"Roms case") —
merged into one shared pair per jensyleo's own report (2026-09-10) that having both side by side
was confusing ("fisiona eso en un solo grupo de configuraciones, es casi lo mismo"). Now ONE
"Sets case"/"Roms case" choice governs BOTH the two "Fix" toggles above (styling what a genuinely
mismatched name gets fixed TO) AND the separate "Apply Case Policy…" action (re-styling an
ALREADY-correct name, on request) — same picker, both meanings, `.dontTouch` behaving differently
in each (see the Settings → Fix caption text under "Case" for the exact wording).
- [ ] Take a real rom whose DAT-declared name has mixed case (e.g. "Sonic
      The Hedgehog.bin") and rename its on-disk file to something wrong.
- [ ] Settings → Fix → set **"Sets case"** to **Datafile Case**, run
      **Fix Mismatched Files** — confirm the file is renamed to EXACTLY
      what the DAT declares, mixed case included.
- [ ] Set it to **Uppercase**, break the name again, run Fix — confirm the
      result is entirely uppercase, **including the file extension**
      (e.g. "SONIC THE HEDGEHOG.BIN").
- [ ] Set it to **Lowercase** — confirm entirely lowercase, extension
      included.
- [ ] Set it to **Don't Touch** — confirm the fix STILL renames the file
      (to the DAT's exact declared case, same as "Datafile Case") rather
      than leaving the wrong name in place — "Don't Touch" only means
      "leave it alone" for "Apply Case Policy…", never for a genuine fix.
- [ ] Set it to **Capitalized** — confirm Title Case on the base name
      ("Sonic The Hedgehog.bin") but the **extension stays lowercase**
      (".bin", never ".Bin") — this is the one case worth double-checking,
      since Swift's own `.capitalized` would title-case the extension too
      if that bug ever crept back in.
- [ ] Repeat all five for **"Roms case"** against a misnamed ROM entry
      inside a zip (via **Fix Misnamed ROMs Inside Their Archives…**) —
      same expected outcomes, applied to the entry name instead of the
      archive's own filename.
- [ ] Once "Apply Case Policy…" itself gets enabled for testing, confirm
      the SAME "Sets case"/"Roms case" value you configure here is what it
      uses too — no separate, hidden setting for it anymore.

### 11.13c "Fix Mismatched Files" real success/failure reporting + no more all-or-nothing abort (added 2026-09-10)
- [ ] From a real, mostly-zip-per-game MAME collection, confirm the Log
      after running **Fix Mismatched Files** now reports one line per
      outcome that actually happened — "Fixed N mismatched File(s)." when
      at least one succeeded, "N mismatched File(s) failed to rename" when
      at least one failed, the existing "N misnamed ROM(s) left as-is —
      their content lives INSIDE..." when any were skipped as archive
      entries, and "Nothing to fix — every File name already matches the
      DAT." only when literally none of the three above apply. These can
      appear TOGETHER (e.g. both a success and a skip line) — previously
      only the skip line ever showed, even when real renames also
      succeeded.
- [ ] Reproduce the actual bug this fixes: take at least TWO genuinely
      loose (non-archived) misnamed rom files — e.g. two misnamed `.chd`
      files, since `.chd` isn't treated as an archive here — and
      deliberately make the FIRST one's rename fail (e.g. pre-create a
      real file already sitting at its correct destination name, so
      `RebuildExecutor` refuses to overwrite it). Run **Fix Mismatched
      Files**.
  - [ ] Confirm the SECOND file still gets renamed correctly — before this
        fix, one early failure silently aborted every operation queued
        after it in the same run, so the second file would have been left
        untouched with no explanation.
  - [ ] Confirm the Log shows both a "Fixed 1 mismatched File(s)." line
        AND a "1 mismatched File(s) failed to rename" line together, not
        just one generic error swallowing the whole batch.

### 11.13d "Fix" respects the selected ROM folder, like "Scan Folder" already does (added 2026-09-10)
jensyleo's own report (2026-09-10): standing on one specific "ROM folder" in the sidebar (e.g.
NEOGEO) and running a Fix action used to act across the WHOLE system regardless — every configured
folder at once — matching "Scan Folder" in name only. This applies to "Fix Mismatched Files" and
"Fix Misnamed ROMs Inside Their Archives…" (the two currently enabled for testing); the same
restriction needs applying to each remaining Fix action as it gets turned on.
- [ ] Select a system with at least TWO configured ROM folders, both containing real misnamed
      files/roms fixable by one of the two actions above.
- [ ] Click on ONE specific "ROM folder" in the sidebar (not "Database", and not left unselected)
      so it's the active selection — confirm the "Fix" toolbar item's own tooltip (hover, or the
      submenu item's own help text) now says "— only inside "<that folder's name>"".
- [ ] Run the Fix action — confirm ONLY files/roms physically inside the selected folder were
      touched (check the other folder's files directly — untouched, still misnamed).
- [ ] Confirm the reported success/skip counts in the Log match ONLY what's inside the selected
      folder, not the whole system's total.
- [ ] Click "Database" (or otherwise deselect the ROM folder) and run the SAME action again —
      confirm it now acts across every folder again (the original, unscoped, whole-system
      behavior) — `nil` selection must mean "no restriction", not "nothing eligible".

### 11.13e "Clear Log" button + 2000-line cap (added 2026-09-11)
- [ ] In the Log panel's toolbar, confirm you see both "Copy Log" and a
      new "Clear Log" button.
- [ ] Click "Clear Log" — confirm the panel empties immediately.
- [ ] Run a scan or Fix action large enough to generate log lines, select
      a range of text in the middle of the log (native drag-select), and
      confirm Copy (⌘C) copies only that range, not the whole log — this
      is the native `NSTextView` behavior, distinct from "Copy Log".
- [ ] (Optional, slow) Generate more than 2000 log lines (e.g. repeated
      scans of a large collection) — confirm the panel keeps showing the
      2000 most recent lines and older ones quietly disappear from the
      top, rather than the panel growing without bound.

### 11.14 Help window — sidebar redesign + Keyboard Shortcuts merge
- [ ] **Help → ROMForge Help** opens a `NavigationSplitView`: a searchable
      sidebar of topics on the left (with icons), a detail page on the
      right — not the old single long scrolling page.
- [ ] Confirm **"Keyboard Shortcuts"** is now its OWN topic at the top of
      the sidebar (with a keyboard icon) — there is no longer a separate
      "Keyboard Shortcuts" window, and ⌘? no longer opens one (check the
      Help menu itself: it should show only "ROMForge Help", nothing else).
- [ ] Type in the sidebar's search field (e.g. "maintenance") — confirm the
      list narrows to matching topics only, and clearing the field restores
      the full list.
- [ ] Click through a few topics (e.g. "The \"Fix\" menu", "Settings —
      Fix") — confirm each renders as a title + prose sections, with
      "term rows" (a bordered list of action/setting name + explanation,
      sometimes with a small badge like "Off by default") for the
      enumerable ones.
- [ ] Click the **"Done"** button at the bottom of the Help window —
      confirm it closes the window (same as the red traffic-light button).
- [ ] Reopen Help, press **Escape** — confirm it also closes the window.
- [ ] Resize the Help window smaller and larger — confirm it respects a
      sensible minimum size and the sidebar/detail split behaves normally
      (no clipped text, no broken layout).

---

## After finishing

Update this file's checkboxes as you go (`- [ ]` → `- [x]`), and note the
date + a one-line result next to anything unexpected (a bug, a slower time
than expected, etc.) so it's easy to turn into a `TODO.md`/`CHANGELOG.md`
entry. If you hit an actual bug, stop and report it rather than working
around it — that's exactly what this checklist exists to surface.
