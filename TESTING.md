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
| 15 | A `nodump` rom with NO real file anywhere | **Explained 2026-08-11, not yet executed.** that rom entry: absent (no row at all) — NOT `missing`, NOT `surplus` | — |
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

## After finishing

Update this file's checkboxes as you go (`- [ ]` → `- [x]`), and note the
date + a one-line result next to anything unexpected (a bug, a slower time
than expected, etc.) so it's easy to turn into a `TODO.md`/`CHANGELOG.md`
entry. If you hit an actual bug, stop and report it rather than working
around it — that's exactly what this checklist exists to surface.
