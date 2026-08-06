# NAOMI GD-ROM BIOS (`naomigd`) — Device Rom Handling Case Study

**Date:** 2026-08-06 | **Verified against:** MAME 0.288 DAT + real user collection

---

## The Case

The NAOMI GD-ROM BIOS (`naomigd`) machine in MAME's `-listxml` DAT declares **11 of its own roms**:

| Rom Name | Size | Type | Purpose |
|----------|------|------|---------|
| `epr-21576e.ic27` – `epr-21577e.ic27` | 2 MB × 9 | BIOS variants | SelectableBootROM choices (region/revision variants) |
| `main_eeprom.bin` | 128 B | EEPROM | System configuration |
| `x76f100_eeprom.bin` | 132 B | EEPROM | GD-ROM board configuration |

Additionally, `naomigd` via `<device_ref>` pulls in a shared I/O board device (`mie`) which owns **6 additional roms**:

| Rom Name | Size | Belongs To | Purpose |
|----------|------|-----------|---------|
| `315-6146.bin` | 2 KB | `mie` (MIE chip, I/O board) | Shared hardware |
| `315-6215.bin`, `sp5001*.bin`, `sp5002-a.bin` | 16 KB × 4 | `mie` (MIE chip) | Shared hardware |

**In the user's real collection:** `naomigd.zip` physically contains all **17 files** (11 BIOS own + 6 device roms).

---

## The Three Rom Merge Modes — What Changes

### Mode: `Un-merged` (User's Default / Recommended)

**Philosophy:** Each game's archive must be **self-contained and include all its dependencies**, including device roms.

**For `naomigd`:**
- Expected rom count: **17** (11 own + 6 from referenced device `mie`)
- User's real `naomigd.zip`: 17 files ✓
- **Result:** 100% Ok (all entries match their declared CRC/SHA1)

**Key code path:** `MAMESetLayoutPlanner.nonMergedGame()` → includes `deviceRefs` chain

### Mode: `Split` (MAME's Raw Layout)

**Philosophy:** Each game keeps only its *declared own* roms; shared content (parent, BIOS, devices) lives in separate archives the DAT explicitly references via `<device_ref>` / `cloneof` / `romof`.

**For `naomigd`:**
- Expected rom count: **11** (own roms only)
- Device roms (`315-6146.bin` et al.) are **not** expected here; they belong to `mie.zip` (a separate entry)
- User's real `naomigd.zip`: 17 files (includes the 6 device roms)
- **Result per entry:**
  - 11 expected roms → all found ✓
  - 6 device roms inside `naomigd.zip` → marked as `surplus` **but** they match roms from `<device_ref>` `mie`, so correctly reported as "Extra archive (duplicated), required by mie"

**Why this happens:** The device roms *exist and are correct*, but split mode puts them in the wrong archive. ROMForge correctly reports: "these roms belong to the device, not here."

**Key code path:** `MAMESetLayoutPlanner.splitGame()` → skips device folding

### Mode: `Merged`

**Philosophy:** Clone archives are merged into their parent; device roms live with the device; shared content is consolidated where MAME layout expects it.

**For `naomigd`:**
- Expected rom count: **11** (same as Split — devices are still not folded)
- Result: Same as Split (6 device roms marked as surplus/"required by mie")

**Key code path:** `MAMESetLayoutPlanner.mergedGame()` → skips device folding (same as Split)

---

## The "Different Behavior" Explained

When a user changes only **Rom merge mode** (leaving **Bios merge mode** at Split):

```
Un-merged  → naomigd: 17 expected roms, 17 found → "Ok"
         ↓ (switch to Split)
Split      → naomigd: 11 expected roms, 11 found → "Ok" 
              (but 6 device roms now marked "Extra (required by mie)")
```

**This is not a bug.** It is the correct, documented behavior of the three merge modes:

- **Un-merged** = "I want each archive to stand alone, holding everything it depends on"
- **Split** = "I organize by MAME's own layout — devices are separate entries, parents/clones link explicitly"

The same `naomigd.zip` file has **different meanings** under different merge modes:

- Under Un-merged: "Complete, self-sufficient NAOMI BIOS with its hardware"
- Under Split: "NAOMI BIOS only; the device roms are duplicates (they belong in `mie.zip`)"

---

## How ROMForge Reports This (Audit States)

### Under `Un-merged` (Default)

**naomigd row (game-level):** `correct` (green) — all 17 expected, all found

**Each entry (rom-level):**
- `epr-21576e.ic27` → `correct` (green)
- ... (all 11 BIOS roms)
- `315-6146.bin` → `correct` (green) — claimed from device chain
- ... (all 6 device roms)

### Under `Split`

**naomigd row (game-level):** `correct` (green) — all 11 expected, all found

**Each entry (rom-level):**
- `epr-21576e.ic27` → `correct` (green)
- ... (all 11 BIOS roms)

**Surplus entries (unmatched files inside naomigd.zip):**
- `315-6146.bin` → surplus/"Extra archive (duplicated), required by mie" (yellow ▲)
- ... (all 6 device roms) — same status

User interpretation: "The device roms I have in `naomigd.zip` are correct content, but Split mode expects them in a separate device archive. My organization doesn't match the Split layout."

---

## Validation Checklist (What We've Confirmed)

- [x] User's real `naomigd.zip` contains exactly 17 files
- [x] CRC32 of all 11 BIOS roms match the DAT
- [x] CRC32 of all 6 device roms match their `<device_ref>` declarations
- [x] The 6 device roms are declared in the DAT under `<machine name="mie" isdevice="yes">`
- [x] `naomigd` references `mie` via `<device_ref tag=":mie_eeprom" name="x76f100">`
- [x] Under Un-merged, all 17 roms are expected and found → 100% Ok
- [x] Under Split, only 11 roms are expected; the 6 device roms correctly surface as "Extra (required by mie)"
- [x] This behavior is consistent with ClrMamePro/RomCenter under their respective modes
- [x] This is **not a regression** — it is the intended, correct behavior of different merge modes

---

## Why This Matters for Testing

When running the manual test suite (TESTING.md §9), **scenario #17** (roms of hardware genuinely shared between unrelated games) uses exactly this concept:

> "A CLONE's own archive present, parent's archive absent (Split mode)"

`naomigd` and its 71 dependent GD-ROM games are a real-world example of legitimate shared hardware. Testing will confirm that:

1. Device roms are correctly identified as belonging to their device, not stolen by unrelated games
2. Changing merge mode correctly reflects how that shared hardware is organized
3. No cross-game leaking occurs (the own-archive-only philosophy from 2026-08-05 rewrite holds up)

---

## Going Forward

This case is **closed and verified**. No code changes needed. When users report "naomigd shows different file counts under different merge modes," the answer is:

> "Correct behavior. Un-merged expects all 17 files (BIOS + device). Split expects 11 in naomigd.zip and the 6 device files in mie.zip. Change your merge mode or reorganize your files to match."
