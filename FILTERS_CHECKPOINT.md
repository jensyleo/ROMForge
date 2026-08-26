# 🎯 CHECKPOINT: Filter System Implemented Correctly

**Date:** 2026-07-30
**Status:** ✅ COMPLETE AND VERIFIED LIVE

---

## 📋 Summary

The 5-independent-button filter system in ROMForge was implemented correctly, after resolving multiple conceptual and implementation bugs. The filters now work intuitively and consistently across both views (Database tree and Games table).

---

## 🎮 The 5 Filters Implemented

### 1. **Correct** ✅ (Green)
- 100% healthy games: all roms present, correctly named, with correct hashes
- **Definition:** No rom is missing, all have correct names and match the DAT's hashes

### 2. **Incorrect** ⚠️ (Yellow)
- Games with **name-only** problems — misnamed files or files found in the wrong place, but whose content DOES match something real in the DAT
- **Definition:** Location/naming problem, not a content problem

### 3. **Bad** 🔶 (Orange)
- **Incomplete** games (some, not all, roms missing) OR with **wrong hash** (content doesn't match the declared CRC32/MD5/SHA1)
- **Definition:** A real content problem — either missing roms or corrupt/wrong content
- **Note:** Internally reuses `AuditStatus.surplus` but relabeled "Bad" in the UI

### 4. **Unknown** ❓ (Gray)
- Genuinely **unknown** files — archives that don't match ANY game in the DAT
- **Definition:** Zero relation to the database
- **Behavior:** Always shown; **never counted under "Bad"**
- **Note:** Gray denotes "unrecognized," distinct from orange (a known-but-incomplete problem)

### 5. **Missing** ❌ (Red)
- Games that **don't exist at all** — zero files found for that game on disk
- **Definition:** The DAT expects the game, but there isn't a single file for it
- **Note:** Only makes sense in "Database" view (DAT-wide); "Rom files" is scoped to real files on disk, so a completely absent game doesn't appear there anyway

---

## 🏗️ Filtering Architecture

### Decision Levels

1. **Real Category Calculation (Toggle-Independent)**
   - `gameCategory(for:)` function — calculates each game's true category from **all** its roms (unfiltered)
   - Stored in `gameAggregateStatusByName` — updated every time the audit report changes
   - **Never depends** on which buttons are pressed

2. **Show/Hide Game**
   - If the game is `Unknown` (a bucket of a file with no DAT match) → **always visible** (respects `showUnknownArchives`)
   - If it's a real game → **visible only if its real category is in `activeStatusFilters`**
   - The 4 buttons (Correct/Incorrect/Bad/Missing) are **independent multi-select**

3. **Rom Rows in the Detail Panel**
   - Selected game = show **all** its roms unfiltered
   - The Correct/Incorrect/Bad/Missing buttons **do NOT control which roms you see** here — that was a previous bug
   - Each rom row has its own status in the table (✅✓❌?) but the game selection doesn't depend on that

---

## 🐛 Bugs Fixed Along the Way

### 1. **"Bad" games showed gray instead of orange**
- **Cause:** Row icons reused the generic `.surplus` function (gray)
- **Fix:** Created `gameSymbolName(for:)` / `gameTint(for:)` specific to real games
  - Real game + `.surplus` = ⚠️ orange
  - Genuinely unknown file = ❓ gray

### 2. **"Bad" count included Unknown files**
- **Cause:** `computeScopedStatusCounts()` summed all `isSurplusBucket` buckets
- **Fix:** "Unknown" isn't counted in any toggle — they're always-visible, separate
- **Result:** "Bad: 2" now means 2 incomplete/corrupt games, not 2+N unknown files

### 3. **Extra files inside games showed as a separate "Unknown"**
- **Cause:** The "does this file belong to a known game?" check depended on which toggles were active
- **Fix:** Now uses `gameAggregateStatusByName` (toggle-independent) for the check
- **Result:** An extra file inside `sf2.zip` correctly folds under "Street Fighter II," not as "Unknown game"

### 4. **Toggles hid games when they should only hide rom rows**
- **Cause:** An earlier attempt to make toggles filter games directly filtered rows first
- **Fix:** Clear separation:
  - Rows: the Correct/Incorrect/Bad/Missing toggles control **which rows you see in the ROM panel**
  - Games: a game's **real category** (toggle-independent) controls **whether the game appears in the list**
  - Unknown: separate `showUnknownArchives` toggle (not one of the 4)

---

## 🎛️ Filter Order in the UI

From the "Show all" button rightward:

```
[Correct] [Incorrect] [Bad] [Unknown] [Missing]
```

Defined by jensyleo, 2026-07-30.

---

## 🧪 Live Verification

- ✅ "Show all" button activates all 5 (the 4 statuses + Unknown toggle)
- ✅ `gng.zip` (2 missing roms, 17 correct) = "Bad" status (orange)
- ✅ "Bad" count = real incomplete/corrupt games only
- ✅ Unknown files always visible (when `showUnknownArchives = true`)
- ✅ A selected game's ROM panel shows **all** its roms (unfiltered by toggles)
- ✅ Database tree and Games table always agree on which games are shown

---

## 📝 Checkpoint

This filter system is **stable, coherent, and ready for expansion**.

Future improvements can build on this foundation without changing the core concepts:
- Additional categories (by BIOS, by year, by manufacturer, etc.)
- More granular filters at the individual-rom level
- Advanced grouping in the tree

But the core — the 5 buttons and their semantics — is **correct and verified live**.

---

**Made by:** Claude + jensyleo
**Technology:** SwiftUI state + `gameAggregateStatusByName` + multi-select toggles
**Bug lineage:** Device exclusion → Status mismatch → Filter semantics → Color coding → Count accuracy
