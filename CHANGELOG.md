# Changelog

All notable changes to ROMForge are documented in this file.

## [0.1.7] - 2026-08-27

### Fixed — Detail panel's rom fields didn't match the Roms table's real columns

jensyleo's own correction: "la idea es que tenga exactamente los mismos campos que se pueden
configurar en las columnas." The rom half of the Detail panel shipped with its own field set
(Game/Clone of/DAT/Path) that corresponded to nothing — none of those are real Roms table
columns. Now shows the exact same fields as `romsList`'s own customizable columns — File name,
Info, Size, Folder, CRC, SHA-1, MD5, Dump status, Type — each with matching content (e.g.
"Folder" now shows the containing folder's name, same as the column, not the full path this used
to show). "Rom name" and the status icon aren't separate toggleable rows, same as before, since
they're this panel's own always-shown header/tint, not optional fields — matching how the Games
table's own "Game name" column isn't optional either.

## [0.1.6] - 2026-08-27

### Fixed — new app-modal Settings window shipped clipped, with no tab icons

Two real regressions in 0.1.5's move to a plain `NSWindow` for Settings, both jensyleo's own
reports right after installing it. Content was showing up cut off on both edges — `NSWindow
(contentViewController:)` doesn't reliably pick up `AppSettingsView`'s own `.frame(minWidth: 760,
minHeight: 560)` at creation time, so `AppSettingsWindowController` now sets that size directly
(and made the window resizable, so it's never stuck too small). The "General"/"View Options"/
"Systems" tab switcher also lost its icons — a plain `TabView` only gets the icon-over-label
"Preferences pane" look automatic when it's the root content of a `Settings { }` scene, which
0.1.5 stopped using; replaced with a small custom tab bar (`SettingsTabBar`) that draws its own
icon+label buttons directly, so the look no longer depends on which container is hosting it.

## [0.1.5] - 2026-08-27

### Fixed — Detail panel's "game fields" toggles didn't actually do what they looked like

0.1.4 shipped the Detail panel's CHD/Samples/Required BIOS/Device refs as four separate
toggles, under names that just duplicated the existing "Dependencies column" settings — turning
one off didn't affect the other, which read as "no está funcionando." The Detail panel now shows
those four as the exact same "Dependencies" chips as the Games table's own column (same badges,
same tooltips, same filtering), governed by the one existing BIOS/CHD/Hardware/Samples toggle
set — turning one off now hides that chip everywhere at once, table and panel both.

### Changed — Settings → View Options reorganized and documented in-app

Several sections all named their own subset of panels/fields with no indication of which
on-screen area each one actually touched. The "Panels" subtab now opens with a one-paragraph map
of all six panels and where they sit on screen, every panel toggle is labeled with its own
location ("Detail (bottom-left)", "Roms (top-right table)", etc.), and "Dependencies column" is
renamed plain "Dependencies (Games table column + Detail panel row)" now that it governs both.

### Changed — Settings window is now a real app-modal window

jensyleo's own request: clicking outside the Settings window used to just switch focus to
whatever was behind it, letting you interact with the main window while Settings stayed open —
standard macOS behavior for a Preferences window, but not what was wanted here. Settings is now
presented as a genuine app-modal `NSWindow` (`AppSettingsWindowController`, driven by
`NSApp.runModal(for:)`) instead of SwiftUI's `Settings { }` scene, which has no supported way to
do this at all — while it's open, no other window in the app can receive clicks or keystrokes
until it's closed via "Done", Escape, or the red close button.

## [0.1.4] - 2026-08-27

### Added — Detail panel fields are now individually configurable

Another fase-1 loose end, jensyleo's own request: the Detail panel (bottom-left — the selected
game/rom's own info) showed a fixed set of fields with no way to hide any of them, unlike the
Dependencies column's own per-chip toggles. Settings → View Options → Panels now has two new
sections, "Detail panel — game fields" (Internal name, Clone of, Year, Manufacturer, BIOS set,
CHD, Samples, Required BIOS, Device refs, Status) and "Detail panel — rom fields" (Game, Clone
of, DAT, Path, CRC32, MD5, SHA1), each with a per-field toggle and its own "Reset to Defaults" —
same `@AppStorage`-backed pattern as every other panel-customization setting in this app. A
field with no value (e.g. a game with no declared year) is still skipped automatically,
unchanged — these toggles only control fields that DO have a value.

### Added — Log panel lines now colored by message type, not just error/not-error

Another fase-1 loose end: the Log panel only ever distinguished red errors from everything else.
`LogLine` now carries a `kind` (`.info`/`.success`/`.warning`/`.error`) instead of a plain
`isError` flag — green for a whole operation's own completion summary (a finished scan with
nothing needing attention, a clean ZIP integrity check), orange for a problem that didn't stop
the operation (a skipped too-deep subfolder, a results-save that failed even though the scan
itself succeeded, a cancelled scan/DAT load), red for a real failure (unchanged), and the
default color for ordinary progress narration. A scan that finishes but finds incorrect/missing
roms logs its "Done" summary in orange rather than green — a green "Done" would read as
"everything's fine" when it isn't.

## [0.1.3] - 2026-08-27

### Added — real CPU/Sound chip data from MAME's `-listxml`, replacing guesswork

jensyleo's own question: does the DAT actually mark a chip like QSound as a sound device
anywhere? It does — MAME `-listxml` emits a `<chip type="cpu"|"audio" name="...">` element per
machine, entirely separate from `<device_ref>`, with a human-readable name (e.g. "Capcom QSound
(custom)") rather than an internal short name. ROMForge never parsed it before this.

`MAMEListXMLParser` now captures `<chip>`, threaded through `MAMEMachine` → `DATGame` →
`AuditReport`/`GameNode` (including SQLite persistence — schema v20, `cpu_chip_names`/
`audio_chip_names` columns, same wipe-and-rescan pattern as every prior schema bump) into the
Dependencies column's "Hardware" tooltip. When a game has real chip data, the tooltip now shows:

    CPU: Zilog Z80
    Sound: Capcom QSound (custom)

instead of the CPU-only, name-guessing heuristic added in 0.1.2. That heuristic isn't gone — it's
the fallback for a game with no `<chip>` data at all (an older/partial DAT, or a non-MAME format),
so CPU identification degrades gracefully instead of disappearing. `device_ref` names never
covered by `<chip>` still surface under `Other:`.

## [0.1.2] - 2026-08-27

### Changed — Hardware dependency tooltip now splits CPU from other devices

The Dependencies column's Hardware badge previously listed every `device_ref` name from the
DAT as one flat, comma-separated string — meaningful to MAME internals, cryptic to most users.
The tooltip now splits recognized CPU device names onto their own `CPU:` line, leaving
everything else under `Other:`. Matching is against a curated, deliberately incomplete list of
around 60 common MAME CPU short names (case-insensitive) — MAME's `<device_ref>` carries only a
device name, no type, so this isn't sourced from the DAT itself, and an unrecognized name always
falls into `Other:` rather than being silently mislabeled.

Every Dependencies badge tooltip also dropped its restatement of its own chip label — "Requires
BIOS:", "Uses CHD:", "Uses hardware:", "Uses samples" all repeated information already on
screen in the chip itself. Tooltips now carry only the actual names (or nothing at all, for
Samples, which has none). The CHD tooltip's disk count kept, since that's real information the
label alone doesn't carry.

### Security

**Decompression bomb guard for `.7z` archives.** `SevenZipArchiveHasher` used to buffer a `.7z`
entry's fully decompressed output with no size limit, unlike `ZipArchiveHasher`, which has
always aborted a suspiciously over-decompressing entry mid-stream. `SevenZipRunner` now reads
7-Zip's stdout incrementally and aborts the process once output exceeds `declaredSize x 10`
(floor 1 MiB), matching the existing zip guard's heuristic. Verified end-to-end against a real
`7zz` process with a 50 MiB payload compressed to a few KB.

**Argument-injection guard for 7-Zip entry names.** A crafted archive can name an entry however
it likes, including something that looks like a `7zz` command-line switch (e.g.
`-p1234looksLikeASwitch.bin`). `SevenZipArchiveHasher` now passes `--` before both the archive
path and the entry path so such a name can never be parsed as an option.

**Symlinks are no longer followed during a folder scan.** `FolderScanner` now checks
`isSymbolicLinkKey` and skips symlinked files entirely and symlinked directories without
descending into them, closing a path where a symlink planted inside a scanned ROM folder could
have caused ROMForge to read files outside the folder the user selected (e.g. `~/.ssh`, Keychain
files).

### Performance — two more per-frame costs removed from divider dragging

Follow-up to the fix below, after jensyleo reported dragging was better but still slow.
Re-profiled a real drag; with the previous hot spot gone, two new ones stood out and both are
now fixed.

**`AuditReport.worstStatus` was a computed property doing two full-report allocations per
read.** It ran `entries.filter { !$0.isDisk }` — copying every matching `AuditEntry`, with all
the retain/release traffic its stored strings imply — then `.map`ped that into a second array.
`LibraryDetailView`'s header reads it on every body evaluation, and the body is re-evaluated
while a divider is being dragged, so a large MAME report paid that twice per frame. The
profile showed `worstStatus` plus its `AuditEntry` copy/destroy churn as the dominant remaining
cost in ROMForge's own code. `AuditReport` is immutable, so the value is now derived once in
`init` and stored; the derivation itself is also allocation-free (lazy sequences into
`AuditStatus.worst(among:)`, which early-outs on the first `.missing`).

**The saved-layout restore had stopped being one-shot.** Earlier today, while chasing the
persistence bug, the `didApplyRestore` guard that made `applyRestoredLayoutIfPossible` run
exactly once was removed in favour of re-applying whenever the split view's own length
changed. That is correct for the transient-startup-width case it was written for, but it also
means any *nested* split whose length genuinely changes mid-drag — dragging the sidebar
divider changes the width of the side-by-side split inside the detail area — re-read
`UserDefaults` and re-issued a `setPosition` per divider on every mouse-moved frame. It now
locks permanently as soon as an apply lands unclamped, which is the only case where there was
ever anything left to correct.

After both, ROMForge's own frames disappear from a drag profile entirely: `worstStatus` is
gone, and every remaining ROMForge symbol sits at a single sample, with the rest of the time
inside AppKit/SwiftUI's own layout machinery.

Also applied, but explicitly *not* individually verified: each pane's `NSHostingView` now sets
`sizingOptions = []` (a pane's size is dictated entirely by the split view, so measuring the
hosted content's own min/ideal/max sizes and publishing them as constraints is wasted work at
each of five nesting levels) and `clipsToBounds = true`. Both are sound in principle and the
layout was confirmed visually unchanged, but the drag metric turned out to have roughly tenfold
run-to-run variance on an identical build (24, 26 and 261 samples across three runs), which is
far too wide to attribute any improvement to them.

**Still open.** Dragging remains slower than it should be, and the remaining cause is
identified but not yet fixed: the Tables bind `columnCustomization` to `@State` declared on
`LibraryDetailView` itself, so a width-driven column write-back invalidates that whole
~4400-line view once per mouse-moved event, which cascades through `updateNSView` into
reassigning `rootView` on every pane of all five nested splits. Fixing it properly means
extracting each Table and its customization state into its own small child view so the
invalidation stays local — a real refactor of a large file, deliberately deferred rather than
attempted late in a session that has already had to revert unverified changes.

### Fixed — dragging a split divider lagged badly behind the mouse

jensyleo's own report (2026-08-26). Root-caused with a sampling profiler taken during a real
divider drag, after four wrong theories had been tried and discarded — the profile pointed
straight at ROMForge's own code:

    NSHostingView.layout()
      -> AppKitOutlineTableCoordinator.update(to:with:diffRows:diffColumns:)
        -> TableColumnList.visitAll
          -> LibraryDetailView.gameTreeTableContent   ("Clone of" column)
            -> gameDescription(forMachineName:)        116 samples
              -> gamesByName(_:)                        44 samples

`gameDescription(forMachineName:)` resolved a machine name to its human-readable description
by calling `gamesByName(preloadedGames)`, which builds a dictionary of the **entire loaded
DAT** — every game, each keyed by a freshly allocated `lowercased()` string. That is a
per-call rebuild, and the call sits inside the "Clone of" column's own content closure, so it
ran once per visible row, on every table layout pass. Dragging a divider re-lays the table out
on every mouse-moved event, which made each frame cost (visible rows x whole DAT): on a full
MAME set, tens of thousands of dictionary insertions and twice as many string allocations per
row, per frame. The divider could only advance once the main thread finished all of it, which
is exactly the "doesn't follow the mouse" symptom.

Fixed by indexing the DAT once into a `GamesByNameCache` and rebuilding it only when the
underlying game list actually changes, turning the per-row work into a single dictionary
lookup. It is a plain reference-type cache rather than `@State`, matching the existing
`ZipCommentCache` in the same file, because it is filled while the view body is being
evaluated and mutating SwiftUI state mid-render is undefined behavior.

Measured on a real drag, before and after, with `sample(1)`: time in the AppKit layout /
CoreAnimation transaction-flush path dropped from 506 samples to 6, and both
`gameDescription(forMachineName:)` and `gamesByName(_:)` disappeared from the profile
entirely. The bug predates this session (the "Clone of" column has resolved descriptions this
way since 2026-08-17); it was not introduced by the split-persistence work below, which was
investigated first and cleared by measurement.

### Fixed — split panel sizes not surviving a relaunch, and dividers lagging behind the mouse

jensyleo's own report (2026-08-26): shrinking a split view panel worked on screen, but closing and reopening the app brought it back noticeably bigger than left. Chasing it turned up a second, related problem — dragging any divider lagged visibly behind the mouse — and both trace back to the same place.

**Root cause.** `splitViewDidResizeSubviews` persisted the layout on *every* resize notification `NSSplitView` sends, and most of those have nothing to do with the user: this view's own initial arrangement at launch (logged live as `[0.173, 0.825, 0.0]` — the right pane at literally zero width), every window resize, and the teardown passes as a window closes. Any layout AppKit settled on by itself was written straight over the proportions the user had chosen, and the next launch faithfully restored *that*. The startup case did the most damage: the split view's first non-trivial width is a transient one (measured ~868pt) narrower than its real final width (~1438pt), and a saved fraction that is perfectly valid at the real width can compute below a pane's minimum at the transient one, where `setPosition` silently clamps it — so what got persisted was the clamped layout, not the user's.

**Fix.** Saving is now gated on the user actually dragging a divider. That is detected exactly: `NSSplitView` runs its divider drag as a modal event-tracking loop inside `mouseDown(with:)`, so the whole drag sits between an override setting a flag and `super` returning at mouse-up, with a final save once it ends. (`splitView(_:constrainSplitPosition:ofSubviewAt:)` was tried first, being documented as a drag-time callback — logging showed AppKit also calling it during the initial arrangement at launch, with no mouse involved, which was enough to persist the degenerate startup layout.)

With the stored value guaranteed to be something the user chose, restoring needs no timing heuristic: it re-applies whenever the split view's own length changes, reading the saved value fresh. A transient launch width applies clamped and harmlessly; the real width that follows re-applies correctly, with nothing persisted in between to poison the next launch. A drag never changes the split view's own length — only how that length is divided — so this cannot fight a drag either.

**On the lag.** Two intermediate attempts at the persistence bug used timing instead. The second deferred the restore through `DispatchQueue.main.asyncAfter` scheduled from `layout()`, and that is what introduced the drag lag: `layout()` runs on every layout pass, and `DispatchWorkItem.cancel()` does not remove an already-scheduled `asyncAfter` from the queue — it only makes the block a no-op — so every pass left another timer behind to wake the main queue at its own deadline, burying the run loop AppKit drives its modal divider-tracking loop on. The current fix uses no timers at all, so that pressure is gone.

Ruled out along the way, by measurement rather than reasoning: per-frame `UserDefaults` writes during a drag (timed at ~0.3ms, and debouncing them changed nothing — reverted); the restore repositioning the divider mid-drag (logged `setPosition` calls during an instrumented drag: zero); and an apparent ~180ms per SwiftUI body re-evaluation, which turned out to be `osascript` invocation overhead in the test harness rather than app work, and is withdrawn. A further harness correction matters for anyone re-testing this: editing `com.jensyleo.romforge.plist` directly (via `PlistBuddy`/`plutil`) races `cfprefsd`, which serves and later flushes its own cached copy — several early "passing" results were artifacts of reading the file instead of the live defaults. Verification was redone through `UserDefaults` itself, covering launch, activation, a window-resize sweep, a real divider drag, quit, and relaunch: the value now round-trips exactly at every step.

### Fixed — fase 1 leftover: Column Presets now reorderable, Settings window focus restored on close

- **Panel Presets list was read-only** — no way to reorder saved presets except delete and recreate. Now supports drag-to-reorder via SwiftUI's `ForEach.onMove`, with order persisted across launches.
- **"Done" button in Presets sheet didn't return to Settings** — the sheet was dimming the Settings window behind it, and pressing "Done" left the main library window in focus instead. Fixed by matching the Settings window against its actual tab titles ("General", "View Options", "Systems") instead of a literal "Settings" string — SwiftUI's macOS Settings window titles itself after the active tab, not the frame title itself.

### Added — bundled 7-Zip engine, no install step needed for `.7z` scanning

The official `7zz` binary (universal, x86_64 + arm64) now ships inside the
app at `Contents/Resources/Engine/7zz`. `.7z` archives scan and match
correctly with nothing installed on the host system; a Homebrew install
(the `sevenzip` formula) is only ever used as a fallback if the bundled
copy is somehow missing.

### Fixed — a round of real-collection manual testing found several bugs, all fixed

- **`.7z` files were never actually scanned at all** — `CollectionHasher`
  had no dispatch for the `.7z` extension, so every one silently fell into
  the loose-file path and got whole-file-hashed, which can never match a
  DAT rom's own CRC/MD5/SHA1. Wired in properly (`CollectionHasher.hash`
  now expands `.7z` entries via `SevenZipArchiveScanner`/`Hasher`, same
  shape as the existing ZIP path), with a graceful whole-file fallback if
  7-Zip somehow can't be located at all.
- **"Required BIOS" column showed the wrong thing** — it displayed a
  game's own `<biosset>` PCB variant names (e.g. "single"/"multi") instead
  of the actual BIOS machine it depends on. Now resolves the real BIOS
  machine via the DAT's `romOf` chain.
- **A surplus archive could non-deterministically fold into an unrelated
  game's row** (or not) across identical scans, when its filename minus
  extension happened to match some other real DAT game's name (e.g. a
  `.7z` named after a BIOS machine it has nothing to do with). Fixed to
  fold only when it's literally the same physical archive path as that
  game's own matched entries.
- **The "Unknown" archive toggle was a no-op** for genuinely unrecognized
  archives — the filter checked for a legacy status value the code never
  actually assigns anymore.

### Fixed — a round of real-collection manual testing found several "Database"/"ROM folder" bugs, all fixed

This batch came directly out of testing ROMForge against a real, large
MAME ROM collection and DAT.

- **Keyboard focus/arrows didn't work in "Database"** — `.focusable()`/
  `.focused()` were attached to a container that also held the search
  `TextField` as a sibling, which left the real AX focus target an
  ambiguous `group` instead of the list itself. Scoped to just the list
  (a sibling of the search field, not its container) instead.
- **A category header and one of its own selected leaves could both show
  the blue "selected" highlight at once** — the header's own highlight
  now excludes the case where a leaf under it is the real selection.
- **Keyboard navigation in "Database" felt slow**, worst from "All
  games" — two causes, both fixed: every arrow step re-ran a full,
  uncapped recompute (now debounced 80ms), and every sort in the
  tree/table used `localizedCaseInsensitiveCompare` (full ICU collation,
  expensive at ~45,000-row scale) — replaced with a precompute-lowercase-
  once, compare-with-`<` pattern everywhere it mattered.
- **Clicking anywhere on a "Database" row (leaf or category header) didn't
  select it** — unlike "ROM folder"'s own rows, these sit inside a
  `DisclosureGroup`/outline structure, where a plain `.onTapGesture` loses
  the click to the outline view's own native mouseDown handling. Fixed
  with `.simultaneousGesture` instead, which doesn't compete for the
  event. (An intermediate attempt using an overlaid `Button` actually
  caused a genuine app freeze — `NSOutlineView`'s own mouseDown tracking
  loop waits for a mouse-up the `Button` had already consumed — confirmed
  and root-caused via `sample`.)
- **The "Games" table redrew all ~45,000 rows of "All games" on every
  selection change** — now capped at 200 with a "Show more" control,
  same pattern the sidebar tree already used for large categories.
- **Selecting a game with clones was much slower than one without** — the
  clone-family filter used to re-run over the full, uncapped game list on
  every `body` re-evaluation, not just once per click; now cached and
  only recomputed when the family selection or its inputs actually
  change.
- **A category's own highlight/keyboard-position could get "stuck" once a
  game was picked from the "Games" table** — the header's `isSelected`
  and the keyboard nav's own "current position" lookup both required no
  game to be selected at all, which broke the moment a game was chosen
  from the table on the right rather than a sidebar leaf. Both now only
  require that *if* a leaf is visible (category expanded), it isn't a
  double-highlight — a collapsed category with an unrelated table
  selection no longer loses its own highlight or keyboard position.
- **A DAT-declared `nodump` rom (no reference hash exists at all) was
  mislabeled "bad dump in DAT"** — that phrase collapses `baddump` and
  `nodump` into one (used for the "Games with bad dumps" category), but
  the actual label now checks the real distinction and says "nodump" when
  that's what it is. A new, dedicated "Games with nodump" category branch
  (off by default, same as other opt-in branches) was also added so
  these aren't only visible mixed in with genuine bad dumps.
- **Arrow-key navigation never scrolled "ROM folder"** — its rows never
  carried the `.id(url)` a `ScrollViewProxy` needs to find them; the
  `scrollTo` call already existed but was silently a no-op.
- **Opening a category's chevron never scrolled to an already-selected
  game** (e.g. picked from the "Games" table while the category was still
  collapsed) — fixed, including a one-run-loop-tick defer for the
  first-expand/async-cache path, where the target row doesn't exist yet
  in the same update that requests the scroll.
- **Settings only closed on Enter, not Escape** — added.
- **Wildcard search (`*`/`?`) with the wildcard on only one side didn't
  work as "contains"** — `*street` used to require the text to *end*
  exactly there (fully anchored `^...$`), so a real game like "Street
  Fighter II" (which doesn't end with "street") matched nothing. Anchors
  dropped entirely for any wildcard pattern — `*street`, `street*`, and
  `*street*` now all behave the same intuitive "contains" way.

Also added, from the same testing pass: a dedicated "ROM folder" search
field was tried and then removed again at jensyleo's own request (folder
names are few enough, and it duplicated "Database" search's own by-game-
name capability without adding real value); a dead, unused
`scopedEntries` computed property was found and deleted; a full sweep for
other "recomputes the whole DAT on every `body` pass" bugs of the same
class turned up none beyond the ones already listed above.

### Added — CHD (MAME disc) auditing

ROMForge now recognizes and audits `.chd` files (MAME arcade discs — CD
images, hard disks) against a DAT's declared `<disk>` entries, instead of
silently treating every scanned CHD as an unrecognized "surplus" file.
Verification is by each CHD's own header SHA1 (`CHDHeaderReader`/
`CHDMatcher`/`DiskAuditor`) — the same approach RomCenter/ClrMamePro use,
never requiring hunk decompression.

Alongside this, full hunk decompression was also implemented and verified
byte-exact against real MAME CHDs (Capcom CPS3 discs) — not required for
today's audit feature, but needed for any future rebuild/repair/export
work: `zlib`, `LZMA` (via Homebrew's `liblzma`, see README's "Homebrew
dependencies"), and the "cdlz"/"cdzl" CD-composite codecs (including a
from-scratch port of MAME's own Reed-Solomon CD sector ECC reconstruction,
`CDSectorECC`, ported directly from `cdrom.cpp`). The "cdfl" (CD+FLAC)
codec remains unimplemented — no real CHD using it was available to
validate a port against.

### Changed — MAME executable location moved from "General" to "Systems", with a new "Default" button

jensyleo's own call (2026-07-30): every setting about how MAME itself
behaves (which binary, how its sets are laid out) now lives together
under Settings → Systems — the same place more systems will eventually
be configured — instead of split across "General" for no reason tied to
what the setting configures. A new "Default" button next to "Locate…"/
"Clear" fills in the conventional Homebrew install location
(`/opt/homebrew/bin/mame`) directly, so most users never need the file
panel at all.



### Added — a fifth "Unknown" toggle, and the filter order is now Correct, Incorrect, Bad, Unknown, Missing

jensyleo's own call (2026-07-30): genuinely unrecognized archives used to
always show no matter what — now they have their own toggle/count, same
look and philosophy as the other four, just backed by a plain on/off
rather than one of the four real game categories (an unrecognized
archive isn't one of those at all). On by default, so nothing changes
until it's turned off. "Show all" now also re-enables this alongside the
four status toggles.



### Fixed — the "Bad" count included unrecognized archives that aren't actually "Bad"

Real bug found live by jensyleo: the "Bad" filter's own count added in
every genuinely unrecognized ("Unknown game") archive too, so it read
higher than the number of actual incomplete/content-mismatched games
visible with that gray icon. "Bad" now only counts real, known games with
a real problem — an unrecognized archive is a different thing entirely
(gray, not orange) and always shows in the list regardless of any
toggle, with no count of its own to add here.



### Fixed — a "Bad" game (e.g. `gng`) still showed the plain gray "unknown" icon instead of the orange warning

The row icon for a real game's own "Bad" status hadn't caught up with the
new definitions — it still used the same gray question-mark as a
genuinely unrecognized surplus file/archive. jensyleo's own call
(2026-07-30): gray should mean "doesn't match anything known" only — a
real, named DAT game that's merely incomplete or content-mismatched gets
the same orange warning the "Bad" filter button itself already used. The
synthetic "Unknown game" bucket (a truly unrecognized archive) keeps the
plain gray look — that distinction is exactly what gray is for.



### Changed — the four status filters redefined as jensyleo's own game-level definitions

Replaces two earlier, wrong attempts at this same problem (row-level
filtering that hid whole games by accident; then a bolted-on separate
"Bad" toggle). All four are now simple, independent game-level lenses,
filtering which *games* appear in the list, each meaning exactly:
- **Missing**: the game isn't present at all anywhere — meaningful only
  browsing "Database"; a "Rom files" folder is scoped to real files on
  disk, so a wholly-absent game has nothing to scope into there anyway.
- **Correct**: 100% healthy.
- **Incorrect**: a naming problem only — a misnamed file, or found under
  a different game/location than expected — but the content matches
  something real.
- **Bad**: incomplete (some, not all, roms missing) or a rom's content
  doesn't match its declared hash — a real content problem, not a naming
  one (internally still `AuditStatus.surplus`, just relabeled "Bad" here).
A selected game's own ROM detail pane now always lists every one of its
roms, regardless of which of the four are toggled.



### Added — a separate "Bad" filter, and the four status toggles go back to filtering rows, not whole games

jensyleo's own proposal (2026-07-30), after the previous attempt at
tying the four status toggles to which *games* show at all backfired:
turning "Missing" off to declutter a long list of absent-rom rows also
hid every genuinely incomplete game outright, which wasn't the intent.
The four toggles (Correct/Incorrect/Missing/Surplus) are back to their
original job — deciding which individual rom rows a selected game's own
detail pane lists. A new, separate "Bad" toggle now covers the
game-level question instead: on, it shows only games that aren't fully
correct (missing a rom, misnamed, or carrying an unexpected extra file),
using each game's always-true aggregate status, independent of the row
toggles. Off by default — nothing changes until it's turned on.



### Fixed — clicking a status toggle (e.g. "Incorrect") didn't reliably hide/show the games with that status

Real bug found live by jensyleo: the status toggles filtered individual
*rom rows* first, then a game showed up if any of its rows survived — so
a game with a mix of statuses (e.g. mostly Correct, one Incorrect rom)
stayed visible via its Correct rows no matter what "Incorrect" was set
to, and toggling it produced no visible change for that game. Both the
Games table and the "Database" tree now group every game from the full,
un-status-filtered entries first (still scoped by category/folder),
compute its true aggregate status, and only then filter the resulting
*games* by whether that status is currently toggled — so a toggle now
does what it visually promises: hide or show the games that actually
have that status. A shown game's ROM detail pane also now always lists
every one of its roms, not just whichever ones happened to match the
toggles.



### Changed — "Database" now defaults to showing every status at once, like "Rom files" already did

jensyleo's own call (2026-07-30): "Database" used to default to only
"Correct" visible — the exact default that let a real bug (a genuinely
incomplete game reading as fully correct) go unnoticed for a while. Both
contexts now default to Correct+Incorrect+Missing+Surplus all shown at
once; toggling one off to focus on the others is still one click away,
same "Show all" button as before.

### Fixed — a surplus file inside an otherwise-known game's archive could wrongly show as a separate "Unknown game"

Real bug found live by jensyleo: with Correct/Incorrect toggled off,
folding a stray extra file into its actual game's own row (instead of a
separate "Unknown game" bucket) used to check against the *toggle-filtered*
entries — so with the game's own correct/incorrect roms hidden by the
toggle, its archive looked "unknown" and the surplus file got its own
phantom row instead. Now checked against the same toggle-independent
`gameAggregateStatusByName` used for the true-status fix above, so this
decision no longer depends on which statuses happen to be visible.



### Fixed — a game's badge in the Games table could lie about its own status, depending on which status toggles were on

The real root cause of the tree-vs-table mismatch jensyleo caught live
(screenshot: tree correctly red, table still green/"Ok" for the same
game, `gng`): with the "Missing" status toggle off, every missing rom
entry is already filtered out of what `computeGameNodes()` ever sees —
so a genuinely incomplete game (missing 3 real roms) computed as fully
correct, simply because none of its missing rows were still present to
notice. The status toggles are meant to control which individual rom
rows show in the ROM detail pane, not to make a game's own aggregate
badge dishonest. Every game's row now always uses its true,
toggle-independent status (`gameAggregateStatusByName`, the same
always-fresh source the "Database" tree already used) — the tree and
table can no longer disagree.



### Fixed — the ROM detail table's combined "Crc/SHA-1" column never actually showed SHA-1

Real bug found by jensyleo: with CRC32/MD5/SHA1 all enabled in Settings,
the ROM detail table's single "Crc/SHA-1" column only ever displayed the
CRC value — SHA-1 was never reachable at all, reading as if SHA-1 hashing
wasn't really happening even though it was (confirmed: `HashAlgorithms`/
`CollectionHasher`/`ZipArchiveHasher` were all computing it correctly the
whole time — this was purely a column-display bug, not a hashing one).
Split into two real columns, "CRC" and "SHA-1", matching the existing
"MD5" column's own pattern.



### Fixed — "Database" tree could show a stale status color after a rescan

Real bug found live by jensyleo: after rescanning, the Games table
correctly showed a game as red (missing roms), but the "Database" tree
still showed it green — a stale color left over from before the rescan.
A tree leaf's status now always reads from a new `gameAggregateStatusByName`
lookup, computed directly from the current audit report at the same
trustworthy points the Games table's own always-fresh data already is —
never from the tree's own cached node, which is what could go stale.



### Fixed — a device's own real romset could never match, always showing as an unrecognized surplus file

Real bug found by jensyleo: CPS2's `qsound_hle.zip` (a real, correct
archive) always showed gray/unrecognized, in every merge mode. Root cause:
`DATLoader` excluded every MAME `isdevice="yes"` machine from `dat.games`
outright — a device with its own real romset (`qsound_hle`'s one rom is
`merge="..."`-inherited from another device, `qsound`) could then never
have anything to match against at all. Real romset tools (RomVault/
ClrMamePro) do audit a device's own set as its own entry, same as a BIOS —
removed the exclusion; `MAMESetLayoutPlanner`'s existing device-rom-folding
into dependent machines is unaffected either way. Verified against the
real `mame0288.DAT` under the active Un-merged/Split settings: `qsound_hle`
now resolves to exactly one rom (`dl-1425.bin`, 24576 bytes,
`d6cf5ef5`) — matching the real physical file byte-for-byte. 161/161 Core
tests passing (one pre-existing test's expectation updated to match the
corrected behavior).

### Added — rescan just one file, not only whole folders

jensyleo's own request: scanning used to only ever cover a whole folder
(all of "Rom files", or one folder via "Scan Folder") — no way to rescan
one specific game's own archive without rescanning everything alongside
it. A selected game now offers "Scan File" (toolbar) and "Rescan This
File" (right-click), scoped to exactly that game's own physical file —
reuses the existing scoped-rescan merge logic unchanged (already worked
by path prefix, which an exact single file matches just as well as a
whole folder). `FolderScanner` gained `scanSingleFile(_:)` and
`scan(paths:)` (Core) to support scanning an individual file directly,
mixed in alongside whole folders. 161/161 Core tests passing (3 new).

### Added — "Database" categories are now real expandable trees

Each "Database" category (All games, Clones, Bios files, …) can now be
expanded in place to show its actual games as tree children, RomCenter-
style — clicking the category itself still filters the Games table on the
right exactly as before. "All games" specifically nests a clone under its
own parent's row; every other category stays a flat list. Children are
computed lazily, only the first time a category is actually expanded, so
a collapsed category costs nothing extra.

### Fixed — expanding a large category (or toggling a status filter while one was expanded) hung the app

A real bug found live: SwiftUI doesn't lazily virtualize a `DisclosureGroup`'s
content the way it does a `List`'s own top-level rows or a `Table` — a
category with tens of thousands of real games (a full MAME DAT's "All
games" is ~43,000) rebuilding its entire row list in one go (which is
exactly what happens when the underlying audit data changes while that
category is expanded) pegged a core at 100% for minutes, reading as a
crash. Every category now hard-caps at 200 rows (a parent's own clone
children too), with a plain "…and N more — use the Games table for the
full list" notice instead of the rest.


### Changed — Un-merged is now strict: a game's rom is never borrowed from another archive

jensyleo's own definition of Un-merged (2026-07-28): every game's own
archive must be fully self-contained — clone, bootleg, parent, or any
other variant, it must never "need" a rom that actually lives in a
different game's file. The existing renamed-whole-archive fallback (a
game whose own archive is absent can still resolve its roms from some
other, unclaimed archive that happens to contain matching content — meant
for the case where the user renamed the whole archive) stayed available
for Split/Merged, but is now disabled entirely under Rom merge mode
Un-merged. `DATFile` carries which merge mode built it
(`DATLoader.datFile(from:mode:biosMode:)`); `ROMMatcher.match` reads it
and, when `.nonMerged`, scopes every game's candidates down to files
genuinely inside its own archive only. Two new regression tests added
(`ROMMatcherTests.swift`).

### Changed — Bios merge mode default is Split again, not Un-merged

jensyleo's own call (2026-07-28): the Un-merged/Un-merged combination set
the previous day was only meant as that session's manual-testing starting
point, not a permanent choice. Bios merge mode now defaults back to
`.split` (BIOS kept as its own separate archive) — the more common
real-world convention. Rom merge mode stays `.nonMerged` by default. The
running app's current `UserDefaults` were also set directly to match, so
this takes effect immediately without needing a "Restore Default
Settings" click.

### Added — MAME failure reason surfaces in ROMForge instead of silently returning to the app

jensyleo's own report: launching a non-working game in MAME made it quit
back to ROMForge immediately with no explanation at all. `MAMELauncher`
now captures MAME's own stderr and, only when it exits with a non-zero
status, shows that output in ROMForge's own error banner — MAME's stderr
already names the real reason (bad dump, unemulated protection, etc.); it
used to just vanish with the process. A normal, clean quit (status 0)
still shows nothing, same as before.

### Added — a real progress bar for "Comparing against the database…"

`ROMMatcher.match` gained an optional, throttled progress callback over
its own expensive phase (computing per-game candidate files against a
large DAT's hash indices) — the "Comparing against the database…" overlay
now shows a determinate bar with a live games-processed count instead of
a bare spinner for however long that phase takes on a large DAT.

### Changed — Settings tab order: General first, then Systems

jensyleo's own call — General is the more commonly touched tab.

### Added — a way to remove an already-added ROM folder

The "Rom files" tree only ever offered "Add Folder…" — right-clicking a
folder there now offers "Remove Folder" too.

### Fixed — Un-merged CPS1 clones (and any clone whose parent owns an unrelated alternate revision at the same PCB slot) were wrongly reported red

Real bug found against a real MAME 0.288 dump, reported by jensyleo:
CPS1's `sf2ee` clone (and its whole `sf2e*`/`sf2u*`/`sf2j*` family) showed
red under Rom merge mode "Un-merged" — missing, wrong-named roms — even
though every one of those games runs fine in real MAME 0.288 with the
exact same files. Root cause: `MAMESetLayoutPlanner.nonMergedGame` built a
clone's required-rom list by blindly unioning *every* `merge=`-less
("own") rom from every ancestor in the parent chain. But a parent doesn't
just own genuinely shared content — it can also own its *own*, completely
unrelated alternate revision of a rom at the very same region/offset a
clone fills with a different revision of its own (confirmed against the
real DAT: parent `sf2` owns six maincpu roms named `sf2e_30g.11e` etc.,
while clone `sf2ee` separately owns a different six, `sf2e_30e.11e` etc.,
at those same offsets — alternates, not shared content). The old code
required both, demanding a rom from the parent that could never exist in
the clone's own archive. Fixed: a clone now only inherits an ancestor rom
it actually references by its own `merge="name"` attribute, looked up by
that exact name — never a blanket copy of everything the ancestor happens
to own. Regression test added (`MAMESetLayoutPlannerTests.swift`)
reproducing the exact shape of the bug; verified against the real
`mame0288.DAT` + a real CPS1 folder via a temporary `romforge-cli`
extension (reverted after use) — every previously-red `sf2e*`/`sf2u*`/
`sf2j*` clone now matches cleanly.

### Changed — global MAME merge mode defaults to Un-merged/Un-merged, as the starting point for this session's manual testing

Bios merge mode's default changed from `.split` (BIOS kept as its own
separate archive, the more common real-world convention) to `.nonMerged`
(BIOS folded into every dependent game's own archive too) — jensyleo's own
deliberate choice: fully Un-merged on *both* axes is the combination this
session's manual testing pass (`TESTING.md`) starts from. Rom merge mode
was already `.nonMerged` by default. The running app's current
`UserDefaults` were also set directly to match, not just the fallback
default, so this takes effect immediately without needing a "Restore
Default Settings" click.

### Changed — MAME's Rom/Bios merge mode is now one global setting, not per-system

- jensyleo's own call, after seeing two systems (`mame0288`, `mame0287` —
  comparing two MAME versions) each needing the same merge mode
  configured separately in Settings → Systems: this was never really a
  per-*DAT* preference — it's "how do I want MAME sets laid out on disk",
  which doesn't vary by which MAME DAT happens to be loaded. Decoupled
  entirely.
- `RomSystem` no longer stores `mergeMode`/`biosMergeMode` at all (old
  saved systems still decode fine — the fields are just ignored now, per
  the same legacy-compat pattern already used for older abandoned
  designs). Settings → Systems now shows a single fixed "MAME" entry
  instead of a per-system list, with the same Rom/Bios merge mode
  picker — bound to a new global `MAMEMergeModeSettings`
  (`UserDefaults`-backed, same pattern as `HashAlgorithmSettings`) —
  applying to every MAME system uniformly. `AddSystemSheet` no longer
  asks for merge mode when creating a system.
- `LibraryViewModel` reads `MAMEMergeModeSettings.current`/`.currentBios`
  wherever it used to read `system.mergeMode`/`.biosMergeMode` — the
  per-system `DATCacheKey` still naturally invalidates/reparse when this
  global setting changes, no extra invalidation logic needed.


### Fixed — "Play in MAME" stayed disabled even with a real MAME configured

- Reported directly by the user: the button/context menu item appeared
  but never became usable. Root cause #1: `MAMELaunchSettings
  .executablePath` was simply never set yet (no UI action had configured
  it) — set directly to the user's real Homebrew install
  (`/opt/homebrew/bin/mame`) to confirm.
- Root cause #2, per jensyleo's own follow-up call: the feature was also
  gated on `viewModel.datHeader?.name == "MAME"` — the currently-loaded
  DAT's own header name, which depends on transient load state and isn't
  necessarily populated by the time it matters. Decoupled entirely per
  jensyleo's direction: every configured system is now treated as MAME
  for this feature, regardless of which DAT is currently loaded — if more
  than one system/DAT happens to be MAME, "Play" applies to all of them
  uniformly, with no per-system distinction. A non-MAME system's game
  name simply won't resolve as a real MAME machine name — MAME's own
  error surfaces that, same as it already does for an incorrect/missing
  set.

### Docs — README now lists every source jensyleo has shared, DAT and metadata alike

Added a "DAT sources" section (MAME's own `-listxml` output,
[progettosnaps.net](https://www.progettosnaps.net/index.php)/its
[MAME DAT downloads](https://www.progettosnaps.net/dats/MAME/), No-Intro,
TOSEC, Redump, MAME's own docs/links) plus a separate "Metadata/artwork
sources" section for every site from `TODO.md`'s "Research — not
started" list that *isn't* a DAT source (Arcade Database, MobyGames,
TheGamesDB, IGN, GiantBomb, Hardcore Gaming 101, Internet Archive,
ScreenScraper, and the still-unclear `github.com/opengood`) — kept
separate from the real DAT sources above since none of these can verify a
ROM against, only supply metadata/artwork for the not-yet-built scraping
feature. Added a third section, "Development references" — the sites/
projects (MAME's own source, Logiqx's DTD, ClrMamePro/RomCenter/RomVault's
own docs and forums, libretro-database, libchdr, AntoPISA/
MAME_SupportFiles, Batocera.linux) jensyleo originally shared at this
project's start and that its own `ROADMAP.md` research write-ups already
cite throughout — consolidated in the README as one list, pointing back
to `ROADMAP.md` for the full citations/context behind each. Added a fourth
section, "MAME ecosystem resources" — a much broader reference matrix
jensyleo shared covering the whole MAME ecosystem (official project,
game databases, arcade hardware, ROM management tools, frontends,
artwork/multimedia, flyers/manuals, history/support `.dat`/`.ini` files,
cheats, high scores, forums), explicitly noted as a reference list rather
than ROMForge dependencies — most of it (frontends especially) isn't
something ROMForge integrates with or ever will, consistent with this
README's own "never becomes a launcher/frontend" stance. Entries already
linked elsewhere in the README aren't duplicated.

### Added — "Play in MAME": launch the selected game directly in MAME to test it

- jensyleo's request, implemented: a real `mame` executable (never a
  bundled/vendored copy) can now be located once in Settings → General,
  and from then on the selected game can be launched straight into MAME
  itself — from a "Play" toolbar button, or right-click → "Play in MAME"
  on any game row. Deliberately MAME-only for now (gated on
  `viewModel.datHeader?.name == "MAME"`, the same signal
  `DATLoader.datFile(from: MAMEDataset)` already sets, so no new
  per-system field was needed) and entirely opt-in — both entry points
  stay disabled until a real, executable `mame` binary is configured, and
  neither is shown at all for non-MAME systems (Logiqx/software-list
  DATs).
- Invocation: `mame <shortname> -rompath <folders>` — the game's own DAT
  `name` (never its human-readable description) as the shortname, and
  every one of the system's configured "Rom files" folders joined with
  `;` on `-rompath` (MAME's own multi-path search convention), so MAME
  itself resolves parent/clone/BIOS archives across all of them
  regardless of which merge mode they're laid out in.
- New `MAMELauncher` (App layer, not Core — this is a real side effect,
  launching an external process, not something `ROMForgeCore` should
  know about) + a `MAMELaunchSettings` reader mirroring the existing
  `HashAlgorithmSettings` pattern. Settings gained a "MAME" section
  (path field + "Locate…"/"Clear" buttons) above the existing hash
  algorithm toggles.
- `GeneralSettingsView.swift`'s new `MAMELaunchSettings` import required
  regenerating the Xcode project (`xcodegen generate`) to register the
  new `MAMELauncher.swift` source file — this also regenerates
  `Info.plist` from `project.yml`, which silently dropped the
  `LSMultipleInstancesProhibited` key added directly to the file earlier
  this session; moved that key into `project.yml`'s own `info.properties`
  instead so it survives every future regeneration, not just this one.

### Fixed — generic "Loading DAT…" spinner, frozen 100% hashing bar, "Hashing" label with CRC32-only, and a second app instance was possible

All four reported directly by the user, one testing session:

- **Generic loading icon while a DAT loaded.** Root cause: `DATLoader
  .load(contentsOf:)` read the entire DAT file into memory with a single
  blocking `Data(contentsOf:)` call, with zero progress signal, before
  any of the existing counting/parsing progress phases even began — for
  a real full MAME driver-set DAT (hundreds of MB), and worse/less
  predictable under iCloud Drive sync (this app's own ROM folders live
  under `~/Documents`, which is iCloud-synced), that raw read alone could
  take a real, unpredictable stretch of time with nothing but a bare
  spinner and "Loading DAT…" to show for it. Fixed: `DATLoader` now reads
  the file in 4MB chunks via `FileHandle`, reporting real
  (bytesRead, totalBytes) progress — a real determinate bar during this
  phase now, same as the counting/parsing phases already had.
- **Switching between two DATs left the previous one's data fully visible
  and interactive the whole time.** Also reported directly: comparing an
  older MAME version's results by loading its DAT could take a real
  while, and the *entire previous* Games/Database view — including a
  stale "DAT: name version" header — stayed exactly as it was underneath
  the small loading card, reading as if it were still current rather than
  about to be replaced. Fixed: the whole Database/Games/detail area is
  now replaced outright by a real loading placeholder
  (`loadingDATPlaceholder`) while `isLoadingDAT` is true, and the header's
  DAT name/version line says "DAT: Loading…" instead of the old, no-
  longer-accurate one — nothing trustworthy is shown again until the new
  DAT actually finishes.
- **Hash progress bar stuck at 100% for a long time.** Hashing finishing
  doesn't mean the scan is done — comparing every hashed file against a
  large DAT (`ROMMatcher.match`) is its own real, separately-timed phase
  (measured as long as ~13 minutes on a large multi-folder MAME system
  before this session's own parallelization fix), but nothing distinguished
  it from "hashing just finished" — the last-known 100% hashing bar just
  stayed frozen on screen for however long matching then took. Fixed: a
  new, honest "Comparing against the database…" phase indicator, shown
  the moment hashing's progress is handed off to matching.
- **"Hashing" label was wrong for CRC32-only mode.** That mode's fast
  path (see the entry below) doesn't actually hash decompressed bytes at
  all — it reads a stored checksum. Simplified further per feedback: the
  progress label now always says "Calculating" instead of "Hashing",
  regardless of which algorithms are enabled — accurate for CRC32-only
  (no hashing actually happens there) and simpler than conditioning the
  word on the current algorithm selection for the other combinations,
  where "Hashing" wasn't wrong, just more specific than needed.
- **A second instance of the app could be opened.** Added
  `LSMultipleInstancesProhibited` to `Info.plist` — macOS's own
  LaunchServices now activates the existing running instance instead of
  launching a second process, with no app-side code needed. Verified:
  `open -a ROMForge` twice in a row resolves to the same PID both times.

### Performance — CRC32-only mode still fully decompressed every zip entry; now reads the zip's own stored checksum instead

- Reported directly by the user, and a sharp catch: with only CRC32
  enabled (see "choose which hash algorithms" below), a scan of
  compressed archives was still slow — their own hypothesis was that
  compression, not hashing, was the real cost. Confirmed exactly right:
  `ZipArchiveHasher` decompressed every entry's *full* content regardless
  of which algorithm(s) were enabled — `HashAlgorithms` only controlled
  whether a decompressed byte got fed into each specific hash's `update()`,
  never whether decompression itself happened. CRC32 is fast; DEFLATE
  decompression is what actually dominated.
- Fixed for the common case: a ZIP entry's CRC32 is already stored in the
  archive's own central directory record (computed once, when the archive
  was built) — when `algorithms` is CRC32-only, `ZipArchiveHasher` now
  reads that value directly (`ZIPFoundation`'s `Entry.checksum`) instead
  of decompressing anything at all. Deliberately excluded from this fast
  path: Genesis `.smd` entries, since deinterleaving needs the real bytes.
  A real, documented trade-off of this fast path: it can't attempt a
  header-stripped match (that needs to actually read the file's leading
  bytes) — only relevant when the user has already chosen CRC32-only for
  maximum speed.
- Added `ZipArchiveTests` coverage: the fast path returns the exact same
  CRC32 a full decompression+hash would have, correctly leaves
  md5/sha1/headerStripped `nil`, and correctly does *not* take the
  shortcut for a `.smd` entry. 155/155 Core tests passing.

### Performance — clicking between "Database" and "Rom files" views took up to ~4 seconds

- Reported directly by the user. Root cause: every click recomputed the
  same "which games have a file inside this folder" lookup *twice*
  (`LibraryDetailView`'s `computeGameNodes()` and
  `computeScopedStatusCounts()` each call `scoped(_:)` independently), and
  that lookup always scanned the system's *entire* audit report (hundreds
  of thousands of `AuditEntry`s on a large multi-folder MAME system),
  doing a `String.hasPrefix` path comparison per entry — real, measurable
  work, duplicated on every single click.
- Fixed by memoizing that lookup (`cachedGamesInFolder`) — recomputed once
  per actual change (selecting a different "Rom files" folder/"Database"
  category, or a fresh scan producing a new report), not once per
  `scoped(_:)` call. Halves the redundant full-DAT-scan cost on every
  click; a further, deeper pass (indexed lookups instead of a per-click
  linear scan at all) remains a worthwhile follow-up for very large
  multi-folder MAME systems specifically — noted in `TODO.md`.

### Performance — scanning a system's 2nd+ folder used only one CPU core; now uses (cores − 1)

- Reported directly by the user: with only CRC32 enabled, scanning a
  second folder (`CPS1`) on a system that already had one folder scanned
  (`NEOGEO`) against the real 42,880-machine MAME 0.288 DAT looked
  "stuck" — it wasn't (confirmed alive and actively computing via `ps`/
  `sample`), just genuinely very slow: **793.4 seconds** (13.2 minutes),
  pegging a single core the entire time.
- Two real, separate bottlenecks, both single-threaded and both hit
  *every* scan of a 2nd+ folder on a system this large (not specific to
  CRC32-only mode — that was a red herring; the cost is independent of
  which hash algorithms are enabled):
  1. `LibraryViewModel.merge()` (combines a scoped folder's fresh results
     with the system's full previous report) built a `"\(game)|\(name)"`
     string key and re-scanned the ~400k-entry merged array four separate
     times (once per status count) — millions of throwaway `String`
     allocations, almost entirely ARC retain/release overhead in an
     unoptimized Debug build. Fixed: a plain `Hashable` struct key (no
     string concatenation at all) and a single pass computing all four
     counts together.
  2. `ROMMatcher.match()`'s main loop — computing each game's candidate
     file indices (hash-index lookups, plus archive-claim filtering for
     an archive-organized scan) — ran fully sequentially over all 42,880
     games regardless of core count. Fixed: split into two phases —
     phase 1 computes every game's candidates **concurrently**, capped at
     `HashingConcurrency.workerCount` (`cores − 1`, the same policy
     hashing already used, directly addressing the user's own suggested
     formula) via `DispatchQueue.concurrentPerform`; phase 2 claims files
     against those precomputed candidates **sequentially**, in the exact
     same DAT-order priority as before (a file's "who gets it first" rule
     depends on claim order, so that part has to stay single-threaded to
     avoid two games racing for the same physical file) — but phase 2 is
     now cheap (array indexing, no string work), so keeping it sequential
     no longer matters for overall speed.
- Verified via a CLI benchmark (`romforge-cli`, temporarily extended to
  hash+match then reverted) against both real folders combined (2,366
  files) and the real DAT: **100.6 seconds**, down from 793.4s — **~7.9×
  faster**, using measured 10 available cores. Same result both before
  and after (1841 correct roms, 5 surplus files) — the parallelization
  changed nothing about *what* gets reported, only how fast.
- 153/153 Core tests still pass unchanged (existing `ROMMatcher`/
  `MAMESetLayoutPlanner` tests exercise the same per-game logic through
  the now-two-phase structure; none needed rewriting since the phases
  produce bit-identical results to the original single loop, just no
  longer computed in one pass).

### Added — "Database" shows the DAT's catalog before you ever scan a ROM folder

- Reported directly by the user: opening a system (DAT loaded, folder
  configured) showed a completely empty "Database" tree until "Scan
  Folder" was pressed at least once — even though every game's name,
  description, year, manufacturer, clone/BIOS/CHD/sample info is already
  fully known from the DAT alone, with nothing about it depending on
  having scanned any actual files.
- `LibraryViewModel.cachedDATFile`/new `preloadedGames` are now visible to
  the detail view (previously kept private) — a real DAT load already
  happens as soon as a system is opened (`startPreloadDAT`, from an
  earlier fix), it just wasn't exposed for anything to read yet.
- `GameNode` (the games-tree row) now optionally carries the raw
  `DATGame` it came from (`sourceGame`) instead of only ever deriving its
  displayed fields from a real scan's `AuditEntry` list — every column
  (description, year, manufacturer, clone-of, CHD/sample/BIOS presence)
  now falls back to the DAT's own metadata when there's no scan result
  yet. Its status icon is a neutral dashed circle (⋯) rather than any of
  the four real correct/incorrect/missing/surplus states, and "Info" shows
  "Not scanned yet" — nothing here claims a real verification never
  actually happened.
- Only applies to the "Database" categories (All games/Originals/Clones/
  Bios files/Games with CHD/Games with samples) — "Verified games" and
  "Games with bad dumps" stay honestly empty pre-scan (both reflect a real
  scan result, not anything the DAT alone can answer), and a "Rom files"
  folder still needs a real scan too (which physical file is actually *in*
  that folder isn't knowable from the DAT alone).
- No change to `AuditStatus`, `ROMMatcher`, or any persisted-report
  storage — this is purely a "what to show before a scan exists" display
  path in the App layer, so a real scan's results/behavior are completely
  unaffected.

### Fixed — a root BIOS machine's own archive (e.g. `neogeo.zip`) always showed as unrecognized "surplus" under Non-Merged mode

- Found immediately after fixing the BIOS-variant over-requirement bug
  above, while re-verifying live: `neogeo.zip`/`awbios.zip` (real,
  byte-correct BIOS dumps) still showed a "?" Unknown-game icon and counted
  as pure surplus, even though every one of their roms matched the DAT
  perfectly by hash.
- Root cause: `nonMergedGame`'s doc comment says "BIOS ancestors are
  deliberately excluded from this chain" — but the filter
  (`.filter { !$0.isBios }`) excluded *every* BIOS machine in the chain,
  including the chain's own last element. `BIOSResolver.resolveDependencies`
  always includes the requested machine itself as that last element, so
  building a root BIOS machine's *own* standalone entry (e.g. `neogeo`,
  needed under Bios merge mode "Split") filtered out the only entry the
  chain had, leaving it with zero required roms — nothing to match against,
  so a correctly-dumped `neogeo.zip` matched nothing and read as surplus.
- Fixed by only excluding BIOS *ancestors*, not the chain's own last
  element (the requested machine), in `MAMESetLayoutPlanner.nonMergedGame`.
  Added a regression test (`nonMergedIncludesRootBiosOwnRoms`, 153/153 Core
  tests). Verified live end-to-end: after invalidating the stale on-disk
  DAT cache and rescanning the real Neo-Geo folder, `neogeo.zip`/
  `awbios.zip` went from "Unknown"/surplus to fully "Correct" (26 correct,
  0 missing, 0 surplus for the whole folder — up from 24 correct with 2
  BIOS files unrecognized).
- Both this bug and the one above were only caught by the user directly
  scanning a real BIOS-dependent romset — no existing test built a fixture
  where the *requested* machine was itself the chain's own BIOS root.

### Fixed — Non-Merged mode wrongly required every BIOS variant inside each game's own archive

- Found during real-hardware manual testing (2026-07-24): a real Neo-Geo
  romset (`mame0288` DAT, `NEOGEO` folder) that scanned 100% Correct earlier
  this same testing session started reporting **every single game as
  Incomplete** — "Ghost Pilots" alone was suddenly expected to contain 45
  files, only 11 of which its own zip actually has.
- Root cause: a real MAME `-listxml` dump has every BIOS-dependent machine
  redeclare *each* of its BIOS's selectable `<biosset>` variants as its own
  `<rom bios="..." merge="...">` entries — confirmed directly against the
  real 0.288 DAT (`gpilots` alone declares all 34 of `neogeo`'s region/
  Universe-BIOS variants this way, on top of its own 11 real roms).
  `MAMESetLayoutPlanner.nonMergedGame` (used by "Un-merged" Rom merge mode —
  this app's own shipped default) walked a machine's full `<rom>` list
  without excluding `merge="..."`-tagged entries, the same rule `splitGame`
  already applied — so every dependent game ended up requiring its BIOS's
  *entire* variant set bundled inside its own archive, regardless of `Bios
  merge mode` (which is supposed to be the only thing governing that,
  independently, in `foldBiosRoms`).
- Fixed by filtering `rom.mergeName == nil` in `nonMergedGame`'s per-
  ancestor rom-gathering loop, exactly like `splitGame` already does. Added
  a regression test with this exact real-world shape (`MAMESetLayoutPlannerTests.
  nonMergedExcludesOwnMergeTaggedRoms`). Verified live end-to-end: after
  invalidating the stale on-disk DAT cache and rescanning the same real
  Neo-Geo folder, results went from 0 correct/24 incomplete to 24
  correct/0 incomplete/0 missing (2 surplus, unrelated) — matching what the
  same folder correctly reported before this regression was introduced.
- Caught by the user directly using the app with real ROMs, not by
  automated testing — 151/151 Core tests (now 152) were green throughout,
  since no existing test covered a machine redeclaring merge-tagged BIOS
  roms in its own `<rom>` list.

### Added — choose which hash algorithms (CRC32/MD5/SHA1) ROMForge computes

- New "General" tab in Settings (⌘,) with three toggles — Settings now has
  two tabs: "Systems" (existing per-system merge mode) and "General"
  (this, app-wide). At least one algorithm must stay enabled (the toggle
  for the sole remaining one is disabled rather than letting it turn
  off) — MD5 and SHA1 add real CPU cost on top of CRC32, especially
  across a large collection, so a user who only cares about CRC-level
  verification (what most DATs declare anyway) can skip the other two
  for faster scans.
- Threaded a new `HashAlgorithms` option set (Core) through the entire
  hashing pipeline: `StreamingHasher` → `FileHasher`/`ZipArchiveHasher` →
  `CollectionHasher`, down from `LibraryViewModel` reading the app-wide
  `@AppStorage`-backed preference. `FileHash.crc32/md5/sha1` are now
  `String?` (nil for whichever algorithm wasn't computed) rather than
  always-populated `String`s.
- **Correctness, not just a UI toggle**: disabling an algorithm never
  causes a false "missing" — `ROMMatcher.matchesRaw`/`matchesStripped`
  only ever compare a hash field when *both* the DAT declares it and the
  scan actually computed it; an uncomputed hash is skipped, not treated
  as a mismatch. Covered by a new test,
  `uncomputedHashDoesNotRejectAMatch`.
- **Cache invalidation, correctly scoped**: `ScanCache.lookup` now also
  checks that a cached entry already covers every algorithm currently
  requested — a file cached while only CRC32 was enabled is correctly
  treated as a miss (and rehashed) the first time MD5 or SHA1 gets
  re-enabled, rather than silently missing that algorithm forever.
  Covered by a new test, `missingAlgorithmIsAMiss`.
- `DuplicateDetector` (not yet wired into any UI) updated to fall back
  from SHA1 to MD5 to CRC32 for its grouping key, in case SHA1 was
  disabled for a given scan.
- 151/151 Core tests passing (148 + 3 new, covering selective
  computation, matcher tolerance, and cache invalidation).
### Fixed — clicking "General" in Settings did nothing

- jensyleo confirmed with a real click (not just automated testing) that
  the "General" tab didn't switch to anything — a genuine bug, not the
  automation-environment limitation the previous entry above guessed it
  might be.
- First suspected `NavigationSplitView` (used by the "Systems" tab):
  it injects its own toolbar item (a sidebar-toggle button) directly into
  the shared window's toolbar, which could plausibly conflict with
  `TabView`'s own toolbar-based tab switcher. Replaced it with a plain
  `HStack`/`List` master-detail layout that claims no toolbar space at
  all — confirmed via the Accessibility tree that the sidebar-toggle
  button was indeed gone, but the actual bug persisted regardless:
  clicking "General" still did nothing.
- Real root cause: `TabView` had no explicit `selection` binding — each
  tab relied on `TabView`'s own implicit/automatic selection tracking
  instead. Verified directly: a screenshot mid-testing showed "Systems"
  permanently highlighted/selected in the tab bar no matter what was
  clicked. Fixed by adding an explicit `@State` selection (a small
  `SettingsTab` enum) plus a matching `.tag()` on each tab — the
  standard, reliable fix for this exact known SwiftUI quirk (implicit
  `TabView` selection can get stuck, especially once more than the
  trivial single-tab case is involved).
- Verified live this time, both directions: clicked "General" from
  "Systems" via the Accessibility tree and confirmed its 3 checkboxes
  actually appeared (previously only "Systems"' content ever showed no
  matter which tab was clicked); clicked back to "Systems" and confirmed
  its own content returned correctly too.

### Changed — new default merge mode: Non-Merged / BIOS Split, plus a reset button

- jensyleo's own choice, confirmed via a screenshot of the app's Settings
  screen left configured that way: new systems now default to `.nonMerged`
  Rom merge mode (every game's archive fully self-contained — least
  likely to report something unexpectedly "missing" for want of a
  parent/BIOS archive, at the cost of more disk space) and `.split` Bios
  merge mode (BIOS keeps its own separate archive, unchanged). Both
  centralized as `RomSystem.defaultMergeMode`/`defaultBiosMergeMode`, a
  single source of truth reused by `RomSystem.init`'s own defaults,
  `AddSystemSheet`'s initial picker selection, and the new reset button
  below — so the three can never drift out of sync with each other.
  Legacy decode fallbacks (for systems saved before these settings
  existed at all) deliberately still default to `.split`/`.split`,
  preserving what those old systems' *actual* historical behavior was —
  only brand-new systems get the new default.
- Added a "Restore Default Settings" button to the Settings (⌘,) merge
  mode form — resets a system's Rom/Bios merge mode back to the above
  defaults in one click, verified live via the Accessibility tree.

### Changed — BIOS merge mode is now a real 3-way setting (Merged/Split/Un-merged), not a boolean

- jensyleo provided a screenshot of a real MAME frontend's own Settings
  dialog: "Rom merge mode" and "Bios merge mode" are presented as two
  completely independent radio groups, each with the *same*
  Merged/Split/Un-merged choice — confirming the earlier "Include BIOS"
  toggle (a plain boolean whose meaning shifted depending on merge mode)
  was the wrong model entirely, not just imperfectly worded. Rebuilt to
  match:
  - `RomSystem.includeBios: Bool` → `biosMergeMode: SetMergeMode`, mirroring
    `mergeMode`'s own type — reusing `SetMergeMode` rather than adding a
    parallel enum, since the three cases and their names are identical.
  - `MAMESetLayoutPlanner` refactored so ROM-family merge logic
    (`splitGame`/`mergedGame`/`nonMergedGame`) and BIOS-fold logic
    (`foldBiosRoms`, new) are fully decoupled — previously
    `nonMergedGame` bundled BIOS-ancestor resolution into the same walk
    as parent/clone resolution, silently coupling the two axes together
    for that one mode. `foldBiosRoms` alone now decides, per
    `biosMergeMode`: `.split` → no folding, BIOS keeps its own archive;
    `.merged` → folded only into a ROM-family root (not clones directly),
    and the BIOS's own top-level entry is dropped; `.nonMerged` → folded
    into every dependent (root and clone alike), with the BIOS's own
    entry still present alongside that duplication.
  - `DATLoader`'s games-list filter now excludes the BIOS's own entry
    only under `biosMergeMode == .merged` (previously gated by the old
    boolean directly).
  - Verified directly against the real 50,097-machine test DAT via
    `romforge-cli` (now accepts a `bios:split|merged|nonmerged` argument
    too): `bios:merged` produces exactly 80 fewer top-level games than
    `bios:split`/`bios:nonmerged` (42800 vs. 42880) — the real count of
    BIOS machines in that DAT, confirming only the BIOS's own entries
    were dropped, nothing else.
  - `AddSystemSheet`/`SystemSettingsView` UI rebuilt to match the
    reference screenshot's own layout and wording as closely as SwiftUI
    allows: two `GroupBox`es ("Rom merge mode"/"Bios merge mode"), each a
    native macOS radio group with labels like "Merged (BIOS in parent)" /
    "Split (BIOS in separate file)" / "Un-merged (BIOS in parent and
    clones)". Verified live via the Accessibility tree (screenshots kept
    catching unrelated windows/other Claude Code sessions on this
    machine, entirely by coincidence of shared screen regions — deleted
    each without reading further) that both radio groups render with the
    correct 3 options each, and that their selection state correctly
    reflects a real saved system's data (including through the legacy
    boolean → three-way migration).
  - A system saved under the earlier (same-day) boolean design still
    loads: the old `showBiosSeparately` JSON key is read as a fallback,
    mapped `true` → `.split`, `false` → `.merged`.
  - 148/148 Core tests passing, including a rewritten
    `biosMergeModeIsIndependentOfRomMergeMode` covering all three
    `biosMergeMode` values against a fixed `mergeMode`.

### Added — "Database"/"Rom files" tree collapse state now persists

- Collapsing either section in the sidebar tree (via their chevron
  header buttons) reset back to expanded on every relaunch —
  `isDatabaseSectionExpanded`/`isRomFilesSectionExpanded` were plain
  `@State`, scoped to the current session only. Switched both to
  `@AppStorage`, the same persistence `TableColumnCustomization` already
  uses elsewhere, just for a plain `Bool` instead of an encoded struct.
- Verified live: pressed the section header's actual button via the
  Accessibility tree (`AXPress`, found by walking `entire contents` down
  to the specific `AXButton` — a coordinate click intermittently landed
  on a different app's window, since several open apps' windows happen
  to share this machine's exact screen frame), confirmed the row count
  dropped from 13 to 5 (collapsing "Database"'s 8 category rows), then
  confirmed across two independent clean-quit/relaunch cycles that it
  stayed collapsed, and a third cycle confirming re-expanding it also
  persists.

### Fixed — Merged mode wrongly expected a separate archive per clone

- Per RomVault's own merge-type reference
  (wiki.romvault.com/doku.php?id=merge_types): under `.merged`, a clone
  has **no archive of its own at all** — everything is combined into the
  parent's single archive (e.g. `puckman.zip`). `DATLoader.datFile` still
  listed every clone as its own top-level game/archive to scan, exactly
  like `.split`/`.nonMerged` (which correctly *do* keep one archive per
  clone) — meaning ROMForge would permanently report every clone archive
  as "missing" under Merged mode, since a real Merged collection never
  has that file. Verified directly against the real 50,097-machine test
  DAT: Merged now correctly produces 15,205 top-level games (parents +
  BIOS only) instead of the same 42,880 as Split/Non-Merged.
  `MAMESetLayoutPlanner.mergedGame` itself already correctly folded each
  clone's roms into its parent's entry — only the top-level games-list
  filter was missing the exclusion. Covered by a new test,
  `mergedModeExcludesClonesFromGamesList`.
- Flagged by jensyleo as still needing a broader, calmer review of the
  whole merge-mode/BIOS rom-derivation logic beyond this specific fix —
  tracked in `TODO.md`.

### Fixed — internal panel divider sizes now genuinely persist (verified live)

Three real, distinct bugs stacked on top of each other across this
investigation — each one masked the next until fixed in turn. Verified
this time with an actual mouse drag (`cliclick`, installed via Homebrew
for this), reading real divider positions via the Accessibility
(`System Events`) tree rather than screenshots, across two independent
clean-quit (real ⌘Q/Quit-menu)/relaunch cycles that both reproduced the
dragged layout exactly.

1. **Competing Auto Layout constraints.** `AutosavingSplitView`'s first
   version added a plain `greaterThanOrEqualToConstant` width/height
   constraint per pane for minimum sizes — this fights `NSSplitView`'s
   own internal Auto-Layout management of its arranged subviews, and
   every SwiftUI-driven re-render (scan progress, log lines, table
   selection — all frequent) could re-trigger a layout pass where the
   competing constraint won. Fixed by moving minimum-size enforcement to
   `NSSplitViewDelegate`'s `constrainMinCoordinate`/`constrainMaxCoordinate`
   (the idiomatic, non-conflicting mechanism) and setting
   `translatesAutoresizingMaskIntoConstraints = true` on each hosting view.
2. **`NSSplitView.autosaveName` itself turned out unreliable in this
   context.** Even after fix #1, a live drag's saved frame was not being
   restored on relaunch. Direct inspection of the saved
   `UserDefaults` data caught it red-handed: a *previous* test session
   had left a genuinely corrupted frame on disk (two edge panes at
   exactly zero width) — `autosaveName`'s restore is unconditional, so
   it faithfully kept re-applying that corrupted frame forever,
   regardless of fix #1. Replaced `autosaveName` entirely with hand-rolled
   persistence: each `AutosavingSplitView` now saves/restores **fractions
   of its own total length** to a plain `UserDefaults` key, applied only
   once its `NSSplitView` has a real, non-trivial frame (checked
   idempotently from `updateNSView`, not guessed via a fixed delay).
3. **`NSSplitView`'s own default initial layout is non-deterministic in
   this specific SwiftUI-hosted setup.** With *nothing* saved and *no*
   drag involved, three consecutive fresh launches were compared
   side-by-side: two produced a sane, minimum-respecting layout and one
   collapsed both edge panes to zero width anyway — the same corruption
   as #2, but reproducible from a clean slate, proving it wasn't only a
   leftover-bad-data problem. `NSSplitView` apparently never guarantees a
   sane default arrangement for frame-based arranged subviews with no
   explicit initial position. Fixed by never letting that ambiguous
   default apply at all: an explicit position is now set for every
   divider on first real layout, always — restored fractions if any are
   saved, otherwise an even split.
- `TODO.md`'s "not yet conclusively verified" note is resolved.

### Fixed — DAT loading could hang for a very long time on a real full MAME driver set (O(n²))

- Reported as "it got stuck loading the DAT" — genuinely wasn't
  stuck, just catastrophically slow: `MAMEDataset.machine(named:)` did a
  **linear scan of every machine** on each call, and
  `MAMESetLayoutPlanner.buildGame` calls it (directly, or via
  `BIOSResolver`/device-ref resolution) *once per machine* while
  `DATLoader.datFile` converts the whole dataset. For a real full MAME
  driver set (this session's test DAT: 50,097 machines), that's an
  O(n²) pass — tens of billions of comparisons — indistinguishable from
  a genuine hang in an unoptimized Debug build. `MAMESetLayoutPlanner
  .mergedGame`'s own clone lookup (`dataset.machines.filter { $0.cloneOf
  == machineName }`) had the identical problem.
- Fixed by having `MAMEDataset` build `[String: MAMEMachine]` and
  `[String: [MAMEMachine]]` (by parent) indices once at `init`, turning
  every lookup into O(1); `Equatable` is now hand-written to compare
  only `machines` itself, not the derived indices. Measured directly
  against the same 50,097-machine test DAT via `romforge-cli` (now
  accepts an optional merge-mode argument and prints load time): **all
  three merge modes now load in ~10 seconds** (previously would have
  taken minutes to hours) — confirmed for Split, Merged, and
  Non-Merged.
- This was a pre-existing Core bug, not something introduced by this
  session's other changes — it simply hadn't been exercised against a
  real, full-size MAME DAT (50,000+ machines) until now.

### Fixed — internal panel sizes (Database/Games/Roms/Log) now persist too

- Reported right after the main window's own frame-persistence fix: the
  window itself remembered its size, but the panel dividers *inside*
  it (Database/Games/Roms on top, Detail/Log below) reset every
  relaunch. Root cause: SwiftUI's `VSplitView`/`HSplitView` give a
  draggable divider for free but expose no persistence API at all —
  unlike the outer window frame, which SwiftUI happens to restore on
  its own via an internal, `WindowGroup`-content-type-keyed mechanism
  that doesn't extend to split views nested inside the content.
  - Added `AutosavingSplitView` (`App/Sources/AutosavingSplitView.swift`)
    — a small `NSSplitView`-backed `NSViewRepresentable` replacement for
    both, using `NSSplitView.autosaveName` directly (the same kind of
    real AppKit persistence mechanism already verified, for the main
    window's own frame, to survive quit/relaunch reliably).
  - Replaced the nested `VSplitView { HSplitView { ... } HSplitView {
    ... } }` in `LibraryDetailView` with three named
    `AutosavingSplitView`s (`ROMForge.mainRowsSplit`,
    `ROMForge.databaseGamesRomsSplit`, `ROMForge.detailLogSplit`), each
    remembering its own divider position independently.

### Fixed — "Include BIOS" is now fully independent of merge mode

- Two rounds of misreading RomVault's own merge-type reference
  (wiki.romvault.com/doku.php?id=merge_types), corrected in sequence:
  the first pass wrongly claimed the BIOS always gets its own separate
  archive regardless of merge mode; a second pass corrected that for
  Non-Merged specifically, but still kept the BIOS option conceptually
  *tied to and gated by* merge mode (disabled/forced depending on which
  mode was selected). Given the actual wiki definitions quoted directly:
  Split/Merged/Non-Merged describe **only** how a clone's roms relate to
  its parent archive — none of the three mentions BIOS handling as part
  of what defines them. BIOS inclusion is a genuinely separate,
  independent axis.
  - Renamed the setting (and the underlying `RomSystem`/`DATLoader`
    property, `showBiosSeparately`/`includeBiosAsOwnGame` →
    `includeBios`) and its UI to a plain **"Include BIOS"** toggle,
    always enabled regardless of merge mode — no more forced/disabled
    states tied to the Split/Merged/Non-Merged picker. Existing saved
    systems still load correctly (the JSON key is kept as
    `showBiosSeparately` for backward compatibility; only the in-memory
    Swift property name changed).
  - Rewrote the merge-mode help text in the Add System sheet and
    Settings to match the wiki's actual wording — no BIOS mentions in
    the Split/Merged descriptions, since the reference itself doesn't
    make any.
  - `MAMESetLayoutPlanner`'s actual rom-layout logic needed no change —
    it was already correct (Split/Merged exclude BIOS roms from every
    game's own archive; Non-Merged duplicates them in) — only the
    App-layer setting's framing/coupling to merge mode was wrong.

### Added — a real Settings (⌘,) window for per-system merge mode / BIOS setting

- Merge mode and "show BIOS as its own separate entry" were only ever
  set once, in the Add System sheet, with no way back into them for a
  system created before this existed. A first pass put this behind a
  sidebar right-click ("Edit Merge Settings…") — moved instead to a
  proper macOS Settings window (⌘,, `SystemSettingsView`, added via
  SwiftUI's `Settings { }` scene), the conventional place a user
  actually looks for this kind of configuration. Lists every configured
  system on the left; picking one shows its merge mode / BIOS toggle on
  the right, auto-saved on change like every other macOS Settings pane
  (no separate Save button) via the existing `SystemLibraryStore.update`.
  Changing either setting invalidates the cached DAT (both the
  in-memory and on-disk caches key on them), so the next open/scan
  re-parses under the new settings. Required hoisting `SystemLibraryStore`
  from `ContentView` up to `ROMForgeApp` itself, since the Settings
  window is a sibling `Scene`, not a child of `ContentView`.

### Fixed — window size/position not actually being remembered

- The previous fix for this (below) added `.onAppear { ... }` directly
  onto `ContentView()` at the `WindowGroup` call site to try an
  AppKit-level `NSWindow.setFrameAutosaveName` workaround. That never
  actually took effect — traced by direct testing (`NSLog` + manual
  resize/quit/relaunch cycles) to SwiftUI itself already restoring this
  window's frame automatically, with no extra code needed at all, keyed
  off the *exact static type* of `WindowGroup`'s content. Attaching that
  `.onAppear` changed the content's type from `ContentView` to
  `ModifiedContent<ContentView, _AppearanceActionModifier>`, which
  silently orphaned whatever frame had been saved under the original,
  unmodified key — the direct cause of "it doesn't remember the window
  size" being reported. Fixed by reverting to a bare
  `ContentView(store: store)` in `WindowGroup` with zero modifiers
  attached at that call site, letting SwiftUI's own (now verified
  working) restoration do its job undisturbed.
- Column widths/order/visibility for both tables were never actually
  affected by this bug — they persist through a separate, explicit
  `TableColumnCustomization` + `UserDefaults` mechanism (unrelated to
  window-frame restoration) that was already working correctly.
- Added a "Reset Column Sizes" item to the app's View menu — clears both
  tables' saved column customization back to their defaults, in case a
  bad layout needs undoing.

### Fixed — "Counting machines…" now shows real progress

- The up-front byte-count pass `MAMEListXMLParser` does to learn a
  total (before the real parse, which is what the determinate bar
  further down actually uses) had no progress of its own — for a real
  full-driver-set MAME DAT (hundreds of MB) it can take a few real
  seconds, and until now that showed as a bare spinner indistinguishable
  from a stall. It now reports (bytes scanned, total bytes) every ~8MB,
  giving this phase its own real determinate bar too.

### Fixed — DAT no longer re-parses from scratch on every app launch

- Reopening the app on a previously-configured system re-parsed its DAT
  file from zero every time, even when nothing about it had changed —
  `LibraryViewModel`'s DAT cache only ever lived in memory, so a fresh
  process (every app launch) always started with an empty cache. For a
  large MAME `-listxml` dump this could cost the better part of a minute
  on every single launch, not just the first.
- Added `DATFileCache` (Core) and `DATCacheLocation` (App) — a small
  disk-persisted cache alongside the existing `ScanCache`/
  `AuditReportDatabase`, keyed by the DAT file's own (size, modification
  date) plus the merge mode/BIOS-display settings it was parsed under.
  `LibraryViewModel.preloadDAT`/`scan` now check this cache before
  parsing and only fall back to a real parse when the source file
  changed or the settings differ from what's cached — this also fixes
  the reported "closing and reopening the app re-loads the DAT" problem,
  since the disk cache survives across process restarts where the old
  in-memory one couldn't.
- `DATHeader`, `DATRom`, `DATDisk`, `DATGame`, `DATFile`, and
  `RomDumpStatus` gained `Codable` conformance to support this.
- Removing a system now also deletes its DAT disk cache file, alongside
  its existing scan cache/audit-database cleanup.
- **Note**: renaming `includeBiosAsOwnGame` → `includeBios` later in this
  same unreleased batch (see "Include BIOS" entry below) changed this
  cache's JSON key, which silently invalidates any cache file written by
  a build from before that rename — a one-time re-parse next launch,
  not a recurrence of the bug above. Confirmed by inspecting an existing
  cache file directly: it still had the old key name and a stale
  `mergeMode` from before a since-changed system setting, both of which
  correctly forced exactly one fresh parse. It won't happen again once
  a build with the new key has written a fresh cache once.

### Added — configurable MAME merge mode (Split/Merged/Non-Merged) + BIOS display

- `MAMESetLayoutPlanner`'s three merge modes already existed in Core but
  were hardcoded to `.split` at the `DATLoader` call site, with a doc
  comment explicitly noting "ROMForge has no per-system merge-mode
  setting yet". Now genuinely configurable: `DATLoader.load` takes a
  `mergeMode: SetMergeMode` parameter (default `.split`, preserving
  exact prior behavior), and the Add System sheet has a segmented picker
  (Split/Merged/Non-Merged) with mode-specific help text, stored per
  system (`RomSystem.mergeMode`, backward-compatible `Codable` default
  for systems saved before this existed).
- Added a second, related setting: whether a BIOS machine (e.g.
  `neogeo`) gets its own top-level game entry (`RomSystem
  .showBiosSeparately`, default `true`). Researched first, not
  guessed: every real MAME/RomVault/ClrMamePro tool always keeps the
  BIOS as its own set across all three standard modes — what changes
  between modes is only whether its *content* gets duplicated into
  dependent games (Non-Merged only), never whether it has an entry at
  all. So hiding the BIOS's own row is a ROMForge-specific display
  choice, not a standard convention, and is only actually correct under
  Non-Merged (the one mode where a dependent game's own expected roms
  already include the BIOS's) — the toggle is disabled/forced on
  otherwise, with help text explaining why, rather than silently
  producing an audit with the BIOS's roms unaccounted for anywhere.
- 2 new `DATLoader` tests confirming both settings actually change the
  produced `DATFile` (147 tests total).
- **Known gap, tracked in TODO.md**: only settable when adding a system;
  there's no edit flow for an existing one yet.

### Changed — an extra file inside an otherwise-matched game now shows yellow, not green

- Following the "dino.zip shown twice" fix below, a game with a surplus
  entry folded into its own row still showed green (Correct) — silently
  the same as a perfectly clean set. `aggregateStatus(for:)` (the Games
  tree's own icon/color logic, deliberately distinct from the shared
  Core `AuditStatus.worst(among:)`, which treats correct/surplus as
  equally low severity at the entry level) now treats any surplus entry
  the same as incorrect: yellow. "Info" says "Extra file in archive"
  instead of the previous "Ok (extra file in archive)", matching the
  now-yellow icon rather than leading with "Ok".

### Fixed — a matched game could also show as a second, separate "Unknown" row

- Found via a real scan: "dino.zip" appeared twice — once correctly
  matched as "Cadillacs and Dinosaurs (World 930201)", and again as its
  own "Unknown game" row, same filename, gray "?" icon. Root cause: an
  extra file inside `dino.zip` that the DAT doesn't call for (a real
  stray/leftover rom, not a scan bug) was correctly classified
  `.surplus`, but `computeGameNodes` grouped every surplus entry into
  its own row keyed by containing-archive filename with no regard for
  whether that archive already belonged to a real matched game —
  reading as if the same archive had been detected twice.
- Fixed by folding a surplus entry into its *own* game's row when the
  archive it lives in is named after a real matched game, instead of a
  separate phantom node — selecting that game now shows the extra file
  right there in its own Roms list (still flagged `.surplus`/gray "?"),
  and its "Info" column says "Ok (extra file in archive)" rather than a
  bare "Ok" that would otherwise hide the extra content. A surplus file
  in a *genuinely* unrecognized archive still gets its own "Unknown
  game" row, unchanged.

### Added — cancel button for DAT loading/hashing, with a consequence alert

- Both long-running phases (DAT loading and folder-scan/hashing) can now
  be cancelled mid-flight via a "Cancel" button on the progress overlay.
  Real cancellation, not just hiding the UI: `MAMEListXMLParser`,
  `FolderScanner`, `FileHasher`, and `CollectionHasher` now check
  `Task.isCancelled`/`Task.checkCancellation()` cooperatively at several
  points (every ~100 machines while parsing, every ~200 files while
  walking, every file while hashing) — previously nothing in that chain
  ever looked at cancellation, so a cancelled `Task` would have kept
  running to completion regardless.
- Real bug caught while wiring this in: `LibraryViewModel.scan()`/
  `preloadDAT()` run their work inside a `Task.detached` (to get off the
  main actor) — a *detached* task is unstructured, so cancelling the
  wrapper `Task` that awaits it does **not** propagate cancellation to
  it. Fixed by keeping a direct handle to the detached task itself and
  cancelling that explicitly.
- On cancel, an alert explains the concrete consequence rather than
  leaving the user to wonder why the report looks empty/incomplete:
  cancelling DAT loading means nothing can be scanned yet; cancelling
  mid-hash means the report is now stale for whatever wasn't reached
  (shows as missing even if actually present).

### Changed — hashing leaves one CPU core free

- `FileHasher`/`CollectionHasher` sized their concurrent worker pool to
  every available core (`ProcessInfo.processInfo.activeProcessorCount`),
  which could make the rest of the Mac (including ROMForge's own UI
  thread) noticeably sluggish during a big scan. New shared
  `HashingConcurrency.workerCount(for:)` caps it to core count − 1
  instead — a deliberate trade of a little raw hashing throughput for a
  machine that stays responsive while a scan runs in the background.

### Fixed — "Add System" was collapsing into the toolbar's "»" overflow menu

- With no explicit placement, "Add System" competed for the same space
  as the detail view's Scan/Fix/Export buttons and was the one macOS
  chose to hide once the window got narrower — hardly "add a system",
  the app's most basic action. Moved to `.navigation` placement (its own
  group, next to the sidebar toggle) with a visible text label
  (`.titleAndIcon`), so it can't be collapsed into the overflow menu and
  no longer reads as a bare, unlabeled "+".

### Fixed — the "Loading DAT" bar still started as a bare, unexplained spinner

- Root cause found: `LogiqxDATParser` doesn't fail fast on a wrong-format
  document — for a MAME `-listxml` dump (root `<mame>`, not
  `<datafile>`), it kept parsing the *entire* ~320MB document (its
  `<machine>` elements masquerading as valid Logiqx entries, since this
  parser accepts either tag name) before finally failing only at the
  very end on a missing root check. `DATLoader` always tries this parser
  first, so every single MAME scan silently burned through a full parse-
  and-discard pass before ever reaching the parser that actually handles
  it — with zero progress reporting the whole time.
- Fixed by aborting `LogiqxDATParser`'s `XMLParser` the moment the
  document's very first element isn't `<datafile>`, reported as a clean
  `DATParsingError.missingRootElement` rather than a generic XML error.
  A wrong-format DAT now fails near-instantly instead of after a full,
  wasted parse.
- The much smaller remaining gap — `MAMEListXMLParser`'s own up-front
  byte-count pass (needed to learn a total before it can show a
  determinate bar) still takes a few seconds with no bar of its own —
  now labeled "Counting machines…" instead of the same generic "Loading
  DAT…", so it reads as a distinct, brief phase rather than an
  unexplained stall.

### Added — DAT loads immediately on selecting a system, not tied to scanning

- Loading the DAT previously only ever happened as the first phase of a
  real Scan — selecting/adding a system with its DAT and folders already
  configured did nothing on its own until "Scan Folder" was pressed.
  `LibraryViewModel.preloadDAT(system:)` now runs as soon as a system's
  detail view appears (a no-op if that exact DAT is already cached), so
  by the time the user presses Scan, the DAT is very often already
  loaded and cached.

### Added — every readily-available DAT field is now a (hideable) column

- Following a full inventory of the DAT/MAME parsing model, every field
  that was already parsed but never reached the UI is now available as
  a column (all new ones default to hidden — "Edit Columns…" turns them
  on):
  - **Games table:** Clone of, CHD (disk name), Samples, BIOS, Year,
    Manufacturer, Required BIOS (a machine's own selectable BIOS
    variants), Device refs.
  - **Roms table:** MD5, Dump status (spells out `baddump`/`nodump`
    separately, where "Info" only ever said "(bad dump in DAT)" for
    both), Merge name (the `merge=` parent-archive rom this one is
    shared with).
- `DATGame` gained `year`/`manufacturer`/`biosSetNames`/`deviceRefs` —
  parsed by `MAMEListXMLParser` and previously discarded when converting
  a `MAMEMachine` into a `DATGame` in `DATLoader`. `AuditEntry` gained
  matching fields plus `romDumpStatus`/`mergeName`/`chdNames`, persisted
  in the audit database (schema bumped to version 3).
- Fields MAME's `-listxml` exposes but the parser doesn't read *at all*
  yet (driver status, control type, display specs, chip list, software
  list refs) are documented in ROADMAP.md as future work — a bigger
  change (new parser elements, not just new columns).

### Fixed — "Rom files" folders no longer inherit "Database"'s status filter

### Added — DAT is parsed once per system, not on every single Scan

- Every Scan re-parsed the DAT from scratch, even for the exact same
  system it was already parsed for moments ago — for a real MAME DAT
  that's over a minute of pure XML parsing wasted on every rescan, when
  the DAT itself essentially never changes between one scan and the
  next of the same system.
- `LibraryViewModel` now caches the last successfully parsed `DATFile`
  keyed by its `datURL` — a scan of the same system with the same DAT
  reuses it and skips "Loading DAT" entirely (logged as "Using
  already-loaded DAT — scanning folders…"); only actually reparses when
  `system.datURL` changes (a different system, or the same system
  pointed at a new DAT file).

### Fixed — "Loading DAT" bar didn't appear until the first 100 machines parsed

- The determinate progress bar only started showing once the first
  throttled callback fired (every 100 machines) — for however long that
  took, the overlay showed a bare spinner with no bar, then the bar
  suddenly popped in. Now reports "0 of total" immediately once the
  total is known, so the bar is there from the very first frame.

### Changed — swapped "Game name"/"File name" column order in the Games table

### Changed — Games table is flat, no more parent/clone tree; added "Game name" column

- A clone game (e.g. `sf2.zip`'s clone set) used to nest under its parent
  in a disclosure tree — a clone is still its own separate archive file
  on disk, so hiding it behind an expansion arrow made it easy to miss
  entirely. Every game/archive is now its own flat row.
- "Game name" originally (wrongly) showed the DAT's short internal
  machine code (e.g. "sf2") — nearly identical to the archive's own
  filename minus its extension, so the column added no real
  information. Fixed to show the DAT's actual `<description>` instead
  (e.g. "Street Fighter II: The World Warrior (World 910522)") — a new
  `AuditEntry.gameDescription` field threads this through from
  `DATGame.description`, persisted in the audit database (schema
  version bumped to 2, with a migration adding the column to existing
  databases). Column order: File name, Game name, Info, Expected file
  name.
  - **Note:** a system's *previously* persisted scan predates this
    field, so its cached report shows the short code as a fallback
    until scanned again — re-running Scan populates the real
    description going forward.

### Changed — status filter is a real multi-select, not one-at-a-time

- Correct/Incorrect/Missing/Surplus used to be mutually exclusive — only
  one status (or none) could ever be shown at once, so "Correct and
  Incorrect together, Missing hidden" — exactly what a folder-level
  audit needs — wasn't expressible at all. Each status is now an
  independent on/off toggle; click any combination on or off freely.
- Still tracked as two independent sets so "Database" and "Rom files"
  keep their own starting point: `databaseStatusFilters` defaults to
  just Correct ("is my collection good?"), `romFolderStatusFilters`
  defaults to all four ("what's really in this folder?", so nothing a
  folder actually contains is hidden by default). Switching between a
  Database category and a Rom folder keeps each side's own choices
  instead of one bleeding into the other. "Clear filter" is now
  "Show all", turning every status back on.
- Also removed the DAT/folder path list shown under the "DAT: MAME"
  header (redundant with the "Rom files" tree itself).

### Fixed — a "Rom files" folder's Missing filter no longer floods in the whole DAT

- Missing roms have no local path, so the folder-scoping filter used to
  keep them regardless of which folder was selected — meaning turning on
  "Missing" while browsing any one folder showed the DAT's *entire*
  missing list (tens of thousands of entries from completely unrelated
  systems), which drowned out combining Correct+Incorrect+Missing into
  anything actually useful for that folder.
- Now scoped to games that already have at least one real file *in that
  folder* — i.e. incomplete sets the folder is genuinely part of —
  rather than every missing rom in the whole collection.

### Fixed — status button counts didn't change no matter where you clicked

- Correct/Incorrect/Missing/Surplus's numbers came straight from the
  DAT-wide `AuditReport` totals — clicking a "Rom files" folder or a
  "Database" category changed what the table showed, but the counts
  next to each button stayed frozen at the whole-collection numbers,
  which looked broken next to a table now showing a tiny fraction of
  that count.
- Both now share the same category/folder scoping logic
  (`LibraryDetailView.scoped(_:)`) — the counts reflect exactly what's
  in the current scope, for every status, regardless of which status
  toggles happen to be on.

### Changed — status counts are per-archive (ZIP/7z), not per individual ROM

- Correct/Incorrect/Missing/Surplus counted individual ROM entries — a
  single archive routinely holds dozens of them, so a folder with a
  couple dozen ZIPs showed a count in the thousands (e.g. "NEOGEO"
  reporting "3028"), which didn't correspond to anything visible or
  reasoned-about on screen.
- Now counts distinct games/archives instead, using the same
  worst-status aggregation already shown by each row's icon in the
  Games tree — one archive, one count, consistent with what "Games (N)"
  above the table already means. Verified: selecting "NEOGEO" now shows
  "Correct: 26", matching its "Games (26)" header exactly.

### Fixed — resizable panels and a misleading blank "File name" cell

- The Database/Games/Roms row and the Detail/Log row weren't wrapped in
  their own `VSplitView`, and "Database"/"Log" both had a `maxWidth` cap
  that boxed them in almost immediately — every panel divider is now
  freely draggable, including the one between the top and bottom rows.
- The roms table's "File name" column showed a bare empty cell for any
  `.missing` rom (there's no local file, so no path to take a name
  from) — correct, but visually indistinguishable from a rendering bug.
  It now shows a "— not found —" placeholder in secondary color instead,
  while "Rom name" still carries the DAT's expected name.

### Fixed — real false-negative matching bugs, found testing against a real MAME 0.288 DAT and a real Neo-Geo romset

- **Cross-machine ROM "theft" in large DATs** (`ROMMatcher`): matching
  pooled every scanned file into one flat, DAT-wide candidate pool with
  first-match-wins. In a 42,880-game MAME DAT, several *unrelated* machines
  independently declare the same shared hardware ROM as their own
  (non-`merge=`) rom — e.g. `kf2k3pcb`, `ms5pcb`, `neogeo`, and `svcpcb` all
  declare `sfix.sfix`. A machine the user doesn't even own (no archive for
  it in the scan) could still "steal" a real file belonging to one they do,
  simply by coming first in DAT order — reporting the real one "missing"
  even with a perfect dump. Fixed by scoping each game's candidates to its
  own same-named archive when the scan is zip-organized (no cross-archive
  fallback); a loose-file scan keeps the original unrestricted pooling,
  since there's no archive identity to scope by.
- **Duplicate rom declarations within one machine** (`MAMESetLayoutPlanner`):
  some real `-listxml` dumps redeclare the exact same rom (identical name +
  hash) more than once under one machine (e.g. `neogeo`'s `sm1.sm1`) — left
  as two logical requirements for one physical file, one slot could never
  resolve to "correct" even with a complete dump. Now deduplicated.
- Verified against a real MAME 0.288 DAT (50,097 machines, 42,880 after
  filtering internal device machines) and a real 25-zip Neo-Geo romset:
  before the fix, 130 correct / 178 incorrect / 188,232 missing; after,
  308 correct (100% of the physical files present) / 0 incorrect / 187,760
  missing (all legitimately-absent games) / 0 surplus.
- Corrected `ROADMAP.md`'s region/language checklist item, which read as
  verified in general but was only ever tested against No-Intro/TOSEC DATs
  — MAME `-listxml` DATs have no structured or naming-convention-based
  region/language data at all, so showing nothing there is correct
  behavior, not a bug.

### Added — real per-phase progress and timing during a scan

- A scan previously showed one indeterminate "Scanning folders…" spinner
  for its *entire* duration, no matter which of four very different
  phases was actually running — for a large MAME DAT the biggest single
  phase turned out to be parsing the DAT's XML itself (over two minutes
  for a ~320MB DAT in an unoptimized build), which the old message
  actively mislabeled as folder scanning.
- The overlay and log now distinguish, in order: **Loading DAT…** →
  **Scanning folders… (live file count)** → **Reading archive N of
  M…** (each zip's central directory, read sequentially before any
  hashing starts) → **Hashing N of M files…** (the pre-existing
  determinate bar). Every transition is logged with that phase's actual
  duration, so the log panel reads as a real timeline instead of just a
  start line and an end line.
- Fixed a real bug found while verifying this: the "Found N files —
  hashing…" log line was being appended *after* the entire scan
  (including hashing) had already finished, since it lived outside the
  `Task.detached` block instead of firing at the moment the folder walk
  itself completed — so it always reported a stale, meaningless
  timestamp.
- Verified against the same real MAME/CPS1/Neo-Geo collection used to
  verify scoped scanning: log line `[15:41:20] Scanning mame0288 (2
  folders)…` → `[15:44:02] Loaded DAT in 161.7s — scanning folders…` →
  `[15:44:02] Found 112 files on disk in 0.0s — reading archive
  listings…` → `[15:48:59] Done in 458.8s: 1226 correct, 3 incorrect,
  186839 missing, 1137 surplus.` — same result as every prior run, DAT
  parsing alone accounting for over a third of total scan time.

### Added — scan a single ROM folder without rescanning everything else

- The toolbar "Scan" button is now context-aware: with a "Rom files"
  folder selected, it reads "Scan Folder" and only re-derives *that*
  folder from disk; with a "Database" category selected (or nothing
  folder-specific), it stays "Scan" and scans every configured folder,
  same as before.
- A folder-scoped scan's result is *merged* into the existing report
  (`LibraryViewModel.merge`) rather than replacing it — a "missing"
  verdict from a scan that only looked at one folder means "not in this
  folder", not "not found anywhere", so it falls back to the previous
  report's verdict for that exact (game, rom) pair when that was already
  a real match. Otherwise, adding a second ROM folder and scanning it
  would have wrongly flipped every game found only in the *first* folder
  back to "missing".
- Verified against real data: scanned a 25-zip Neo-Geo folder, then added
  and scanned an 86-zip Capcom CPS1 folder (2,058 individual roms) —
  merged report showed 1,226 correct (308 Neo-Geo + 918 CPS1), and the
  Neo-Geo games (`neogeo`, `mslug`, `wh2`, ...) stayed "correct" even
  though the second scan never looked at their folder again.

### Changed — distinct icons per "Database" category (placeholder SF Symbols)

- Every "Database" category shared the exact same `tablecells` icon,
  giving no visual distinction at a glance. Each now has its own SF
  Symbol (`DatabaseFilter.symbolName`). These are still placeholders, not
  real custom icon designs — tracked as a new pending item in
  `ROADMAP.md` for whenever there's time for an icon design pass, same as
  the app's own icon went through earlier.

### Added — add more ROM folders to an existing system, not just at creation

- `SystemLibraryStore.update(_:)` (new) persists an in-place edit to an
  already-configured system, matched by id. `LibraryDetailView` gained an
  "Add Folder…" leaf under "Rom files" (opens the same multi-select
  `NSOpenPanel` `AddSystemSheet` uses) — previously a system's ROM
  folders could only ever be set once, at creation time; there was no way
  to add another folder to a system already in the sidebar without
  removing and recreating it (losing its scan history). `ContentView`
  wires the new folder list back through `store.update`. A Scan still
  has to be run again to actually audit a newly added folder's contents.

### Added — clicking a "Rom files" folder scopes the same audit tree, not a separate raw view

- Clicking a folder under "Rom files" briefly showed an independent raw
  `FolderScanner` disk listing (name/size/path, no status colors). Per
  explicit follow-up feedback, replaced with the *same* audit-driven
  Games tree "Database" categories use — identical columns (File name/
  Info/Expected file name), identical status icons/colors, identical
  selection → ROMs pane → detail pane flow. Only which entries feed the
  tree changes: `databaseFilteredEntries` now also scopes by folder when
  one's selected (an entry's `path` must start with that folder's path),
  in addition to the existing status/category filters — all three axes
  combine. A missing rom (no `path` at all — found nowhere) stays visible
  regardless of which folder is selected, since excluding it would make a
  real gap silently vanish just by picking a folder.
- **"Database"/"Rom files" section headers now collapse/expand** on click
  (a chevron toggles per section) instead of always being fully expanded.

### Changed — Database tree now has two real root nodes, RomCenter-style

- The left pane was a single flat "Database" category list. Replaced with
  a `List` of two `Section`s matching a reference RomCenter screenshot the
  user provided: **Database** (the DAT category filters — now including a
  new **Verified games** case, only games where *every* rom actually
  matched by both name and hash, not just individually-correct rom rows
  from an otherwise-incomplete game) and **Rom files** (one leaf per
  configured ROM folder, informational — not a filter, since there's
  nothing to select).

### Changed — Games panel columns, ClrMamePro/RomCenter-style

- Replaced the "Game"/"Region"/"Language" columns in the left-hand Games
  tree with **File name** (the archive actually found on disk for this
  game, if any), **Info** (a one-line status), and **Expected file name**
  (the `<game>.zip` the DAT implies). Region/Language never applied to
  MAME DATs anyway (see the Fixed section above/`TESTING.md`), so this
  isn't a loss for that use case; it matches a reference scanner-view
  screenshot the user provided.
- **Info** now distinguishes 5 real categories instead of 4: **Ok**,
  **Incomplete (rom missing)**, **Bad file name** (the archive itself is
  misnamed — its contents, once matched by hash, are a real known game),
  **Rom need fix** (the archive's own name is correct, but one or more
  roms *inside* it are misnamed), and **Unknown game** (an archive that
  matches no DAT game at all). Each unrecognized archive is now its own
  row (sorted in alongside real games alphabetically) instead of being
  dumped into one combined "Surplus files" bucket, matching a reference
  screenshot the user provided of a real scanner's results view.
- **`ROMMatcher`**: detecting "Bad file name" required a second look at
  the archive-scoping fix above — restricting a game to only its own
  same-named archive (needed to stop cross-machine ROM theft) also broke
  detecting a whole archive renamed by the user, since the renamed
  archive's name no longer matches any game. Fixed by allowing a
  fallback to *unclaimed* archives only — an archive whose name matches
  no DAT game at all isn't "claimed" by anyone, so it's fair game for a
  different game's rom to resolve from (the renamed-archive case);
  an archive whose name matches some other real DAT game stays
  off-limits, preserving the original theft fix. 2 new tests (145 total)
  cover both the steal-prevention regression and the renamed-archive
  case; verified the real MAME/Neo-Geo scan is unaffected (still 308
  correct / 0 incorrect / 0 surplus).

### Fixed — app hang when browsing a large real MAME DAT's game tree

- `LibraryDetailView`'s `gameNodes` (the parent/clone game tree shown in the
  "Games" pane) was a computed `var`, rebuilt from scratch — dictionaries,
  filtering, recursive node construction — on every SwiftUI `body`
  evaluation, which happens far more often than the underlying data
  actually changes (any hover, focus change, or unrelated state update).
  Invisible with a small hand-built test DAT; with a real MAME DAT's full
  game list (tens of thousands of games), this pegged the main thread
  rebuilding the same huge tree over and over, hanging the app at ~100%
  CPU. Now cached in `@State`, recomputed only when the report or an
  active filter actually changes.

### Added — SQLite persistence of the last scan per system

- **`AuditReportDatabase`** (Core): persists every configured system's last
  audit — every `AuditEntry` plus which DAT produced it and when — using
  Darwin's built-in `SQLite3` module directly (`import SQLite3`, no
  Homebrew/vendored dependency). Schema-versioned (`schema_version` table,
  migration-ready). One shared `romforge.sqlite3` (`AuditDatabaseLocation`,
  App layer) instead of one file per system.
- Opening a previously-scanned system now shows its full last results
  (games list, roms list, status counts, DAT header) immediately —
  `LibraryViewModel.loadPersistedReport(system:)`, called on
  `LibraryDetailView`'s `onAppear`. A real Scan still always re-derives
  everything from disk and overwrites the persisted row.
- Retired the earlier per-system `SystemStatusStore` JSON files — the
  sidebar's status dot now reads the same `AuditReportDatabase`, so there's
  one persistence mechanism for "last known status," not two.
- 6 new tests (round-trip incl. nils/special fields, never-scanned →
  `nil`, saving replaces rather than appends, `removeSystem`, cross-system
  isolation, persists across reopening the same file). 143 tests total.
  Verified live in the real app: Add System → Scan → quit → relaunch shows
  the full persisted report immediately, without touching Scan again.

### Added — GUI polish + hardening (from reviewing an external RomManager C#/.NET prototype)

The user shared a separate, unrelated prototype ("RomManager", C#/.NET 9 +
Avalonia + SQLite, an early uncompiled scaffold from another session) for
inspiration. No code was ported (different language/platform entirely) —
its design ideas were compared against ROMForge's actual current GUI/Core
state (audited first, not assumed), and 6 concretely-scoped items were
implemented:

- **Worst-status aggregation, now reusable Core API**: `AuditStatus.worst(among:)`
  and `AuditReport.worstStatus` (missing > incorrect > correct/surplus,
  same severity order the game tree already used internally) — the game
  tree's own aggregation now calls this shared helper instead of a
  duplicated private one, and the system's overall worst status is shown
  as a badge next to the DAT header in `LibraryDetailView` and as a
  colored dot per system in the sidebar (`ContentView`).
- **Persisted last-scan status per system**: new `SystemStatusStore` (App),
  same per-system-JSON pattern as `ScanCacheLocation` — lets the sidebar
  show a status dot without eagerly rescanning every configured system;
  removed when its system is removed. Verified live: dot appears
  correctly on a cold relaunch (reflects the last real scan), through a
  real Add System → Scan → quit → relaunch cycle in the actual app.
- **Real scan progress**: new `ScanProgress`/`ScanProgressCounter` (Core) —
  a thread-safe, throttled (~200 updates max) completed/total counter
  shared across `FileHasher`'s concurrent workers and
  `CollectionHasher`'s zip-entry hashing, so a scan doing both loose-file
  and zip-entry hashing reports one continuous count instead of two
  resetting phases. Replaces the bare spinner overlay with an actual
  progress bar + "Hashing N of M files…" during the hashing phase
  (folder enumeration itself stays a quick indeterminate spinner — it's
  fast enough not to need its own granular progress).
- **Persistent log panel**: `LibraryViewModel` now collects timestamped
  log lines (scan start, done-with-counts, or failure) shown in a new
  scrolling panel next to the ROM detail pane in `LibraryDetailView`.
  Verified live in the running app.
- **XXE hardening**: `LogiqxDATParser`/`MAMEListXMLParser`/`SoftwareListParser`
  now explicitly set `shouldResolveExternalEntities = false` and
  `externalEntityResolvingPolicy = .never` on their `XMLParser` (Foundation
  already defaulted to this, but it wasn't explicit in code).
- **Zip-bomb guard**: `ZipArchiveHasher` now aborts extraction
  (`ZipArchiveError.suspectedZipBomb`) if an entry's real decompressed byte
  count exceeds its own declared (attacker-controlled) size by more than
  10x — a ZIP's central directory size field can't be trusted as a hard
  cap, but real ROM/CD dumps can legitimately be many GB, so this isn't a
  fixed absolute limit. 1 new test (real payload wildly exceeding a
  deliberately-lied-about declared size).
- **Zip-entry hashing parallelized**: `CollectionHasher` previously hashed
  zip entries serially even though loose files were already concurrent;
  now uses the same bounded `TaskGroup` pattern as `FileHasher` (each
  `ZipArchiveHasher.hash` call reopens its own `Archive` handle, so entries
  across different — or the same — zips are safe to decompress in
  parallel). 1 new test confirms correctness across 24 entries spread
  over 6 zips hashed concurrently.
- 137 tests total (Core, up from 130); Xcode app project rebuilt and
  manually exercised end-to-end in the real running app (Add System → DAT
  auto-load → Scan → progress bar → log panel → status badge → game/rom
  selection → detail pane), not just unit-tested.

### Research (no code changes)

- Deep research pass into what a genuine functional replacement for
  ClrMamePro/RomCenter would require — not just visual similarity. Six
  parallel research efforts against ClrMamePro's real docs/forums,
  RomCenter's real docs/forums, MAME's/libchdr's actual source code,
  RomVault's docs, and DAT format specs (Logiqx DTD, TOSEC, No-Intro,
  Redump, MAME software lists). Findings, priority-ranked, are documented
  in ROADMAP.md's new "Path to a full ClrMamePro/RomCenter replacement"
  section — covering a third DAT dialect ROMForge doesn't parse (MAME
  software lists), a Logiqx-parser permissiveness gap found in a live
  Redump DAT, the full CHD codec spec with a recommendation to wrap
  `libchdr` rather than reimplement, specific merge-mode edge cases/bugs
  from both real tools to deliberately avoid repeating, a fixdat-export
  opportunity neither tool reliably ships, and a validated mtime+size
  scan-cache strategy. No code was changed in this pass — it's the
  evidence base for what to build next, in what order.

### Added

- **CHD v5 hunk reading, tied together end to end** (Core — see ROADMAP.md
  for the full honest scope of what remains environment-blocked): building
  on the hunk-map decoder (`CHDBitReader`, `CHDMapHuffmanDecoder`,
  `CHDV5MapReader`, all ported faithfully from MAME's real source), this
  pass added the pieces needed to actually read a hunk's decompressed
  bytes, not just locate it:
  - `CHDCRC16` — MAME's `util::crc16_creator` (CRC-16/CCITT-FALSE),
    confirmed against its published external check value; `CHDV5MapReader`
    now verifies a decoded map against the format's own `mapcrc` field.
  - `CHDZlibDecompressor` — CHD's zlib codec confirmed from real source to
    use raw DEFLATE (`deflateInit2(..., -MAX_WBITS, ...)`); implemented via
    a new `CZlib` SPM system-library target wrapping macOS's built-in
    `libz` (no Homebrew/vendored dependency). Tested against a real,
    independently Python-generated raw-deflate buffer.
  - `CHDHeader.mapOffset` (previously unread) and new `CHDHunkReader`,
    which opens a real CHD v5 file and decompresses hunks on demand for
    `COMPRESSION_NONE`, `COMPRESSION_TYPE_0`/zlib, and `COMPRESSION_SELF`;
    `COMPRESSION_PARENT` is implemented (resolves against another
    `CHDHunkReader` passed as `parent:`) but untested against a real
    parent/diff-CHD pair.
  - End-to-end proof: since no real CHD file exists in this environment,
    hand-assembled a complete, byte-accurate synthetic CHD v5 file (real
    header, real map header, a provably-valid compressed map, the same
    verified raw-deflate fixture) and confirmed `CHDHunkReader` correctly
    reads back its NONE/zlib/SELF hunks.
  - 125 tests total (Core); Xcode app project rebuilt to confirm the new
    `CZlib` system-library target doesn't break the app — it builds clean.
  - Still genuinely blocked here, not just deferred: LZMA hunk bodies
    (needs Homebrew `xz`, avoided for portability), MAME's own Huffman
    codec for hunk bodies, FLAC (not installed, none vendored),
    CD-composite codecs, and validation against any real, legally-obtained
    CHD file. Not yet wired into `CHDMatcher`/the scan pipeline — remains a
    standalone capability pending a product decision on what ROMForge
    should actually do with decoded hunk content.
- **TorrentZip writer** (Core): `TorrentZipWriter`/`TorrentZipEntry` produce
  archives conforming to the real TorrentZip standard (spec read from
  wiki.romvault.com, mirroring the original `trrntzip` README) — fixed
  12/24/1996 11:32 PM timestamp, fixed flags, deflate method 8 always
  (even zero-byte entries), lowercase-sorted entry order with `\`→`/`
  normalization and redundant-directory filtering, and the
  `TORRENTZIPPED-<CRC32>` EOCD comment. New `DeflateCompressor` (raw
  DEFLATE via the same `CZlib` system-library target added for CHD's zlib
  decompressor — no new dependency). 5 tests, including one verifying the
  output against the project's existing, independent `ZIPFoundation`
  dependency (open/list/extract), not just self-checking. 130 tests total.
  Honestly documented limitation: uses macOS's current system zlib rather
  than the spec's referenced zlib 1.1.3, so output is a valid,
  spec-conforming TorrentZip but not guaranteed byte-identical to a real
  `trrntzip`/RomVault-produced file for the same content. Not yet wired
  into any rebuild/export feature — the app has none yet (still read-only).
- **Scan cache (mtime+size → hash)**: new `ScanCache` (Core), a
  JSON-persisted `[path → (size, mtime, hash)]` map, validated against
  RomVault's own documented strategy of only rehashing new/changed files.
  `ScannedFile` gained a `modificationDate` field; `FileHasher`/
  `CollectionHasher` serve a cached hash (skipping extraction entirely for
  an unchanged zip entry) instead of recomputing it when size+mtime match.
  One cache file per configured system, loaded before a scan and saved
  after; removing a system removes its cache too. 6 tests (116 total).
  Verified end to end in the real app: corrupted a ROM's content while
  preserving its exact mtime — rescanning still showed `Correct` (served
  from cache); then changed the mtime and rescanned again — correctly
  flipped to `Missing`/`Surplus` (cache invalidated, rehashed for real).
- **Merge-mode layout fixed and wired into `DATLoader`**: `MAMESetLayoutPlanner`
  existed in Core but was never called by the app. Fixed three real bugs
  in it (matching documented real-world ClrMamePro/RomCenter bug reports)
  and wired it into `DATLoader`'s MAME `-listxml` conversion:
  - a merged-set hash collision (same rom filename, different content
    across parent/clone) is no longer silently dropped — it's namespaced
    (`cloneName/romName`) instead of one version disappearing;
  - split mode now respects the DAT's `merge="..."` marker (new
    `DATRom.mergeName`) instead of returning every rom a machine declares —
    **this was a live audit-correctness bug**: scanning a real
    split-organized MAME collection could wrongly report a clone's
    parent-inherited files as missing;
  - non-merged now includes device (`device_ref`) roms too, not just the
    BIOS/parent chain, so it's actually self-contained.
  6 tests added (110 total). Verified end to end in the real app: a
  parent + clone fixture where the clone declares a `merge=`-marked
  inherited rom, with only each game's own file on disk, scanned to
  `Correct: 2, Missing: 0, Surplus: 0` — the clone correctly stopped
  demanding a file it was never supposed to have.
- **`HeaderSkipRule` wired into `ROMMatcher`**, loose files and zip entries,
  including Genesis `.smd`: a headered console dump (iNES 16-byte, Lynx
  64-byte, SNES/GB/PCE/SMS 512-byte copier header, or Genesis's
  interleaved `.smd`) now matches a headerless DAT entry, whether it's a
  loose file or inside a `.zip`. `HeaderSkipRule`'s API changed from taking
  a full `Data` buffer to `(fileSize, headBytes)` so detection doesn't
  require loading a large ROM into memory. New `HeaderStrippedHash` type;
  `FileHasher.hash(files:)` and `ZipArchiveHasher.hash` both compute it
  alongside the raw hash when a rule matches (the zip path only pays for a
  second extraction when a header is actually detected); `ROMMatcher`
  indexes and matches on both. New `GenesisSMDConverter` de-interleaves the
  512-byte-header + 16KB-block `.smd` format (studied from the same
  RomcenterPlugins source as the other rules), wired in as its own path
  since it reorders content rather than just trimming a header. 9 tests
  (106 total).
- **MAME Software List parser**: `SoftwareListParser` (Core) reads a third
  DAT dialect — `hash/*.xml`/`-listsoftware` output, root `<softwarelist>`
  — used for cartridge/disk/cassette software on the non-arcade systems
  MAME emulates. Structurally distinct from Logiqx and `-listxml`: a
  `<software>` can have several `<part>` elements (each a separate physical
  medium), flattened into one `DATGame` since ROMForge's generic model has
  no part/interface concept. Lenient about roms missing `name`/`size`
  (loadflag continuation/fill entries) — skipped, not treated as malformed.
  `DATLoader` tries it as a third fallback; `romforge-cli` now goes through
  `DATLoader` instead of calling `LogiqxDATParser` directly, so it exercises
  the same chain the app does. 7 tests (97 total).
- **Fixdat export**: `FixDatExporter` (Core) generates a normal Logiqx-DAT
  containing only the missing/incorrect entries from a scan, grouped by
  game — the "gap" you'd hand to another tool or another source collection.
  Round-trips through `LogiqxDATParser`. New "Export Fixdat" toolbar button
  next to Export Report. 4 tests (90 total). This is something neither
  RomCenter nor ClrMamePro reliably ship (RomCenter promised it twice in
  forum threads, 2011 and 2018, with no confirmation it was ever delivered)
  — see ROADMAP.md's research section for sources.
- `HeaderSkipRule` (Core, detection primitive — not yet wired into the
  matcher/app): studied RomCenter's own signature-plugin sources
  ([github.com/ebolefeysot/RomcenterPlugins](https://github.com/ebolefeysot/RomcenterPlugins),
  GPL-3.0, `Goodxxx/fmt/*.cpp`) for the exact console header conventions
  Goodxxx/clrmamepro/RomCenter already agree on: iNES (16 bytes, `NES\x1A`
  magic), Atari Lynx (64 bytes, `LYNX` magic), and the 512-byte "copier
  header" shared by SNES/Game Boy/PC Engine/Master System dumps (detected
  by file size, `size % 1024 == 512`, no magic). 7 tests. Genesis's
  interleaved `.smd` format and rarer formats (7800, PSID, FDS) from the
  same plugin collection were left out of this pass. **This is a detector
  only** — `ROMMatcher` doesn't call it yet, so a headered console dump
  still won't match a headerless DAT entry today; wiring it in needs
  `FileHasher` to also produce a header-stripped hash+size per file (see
  ROADMAP.md).
- CHD/sample/bad-dump **categorization** (Core + App), rounding out the
  "Database" tree to all 7 of RomCenter's original categories. Both DAT
  parsers now read a rom's `status="baddump"/"nodump"` attribute
  (`DATRom.status: RomDumpStatus`), `<disk>` (already parsed for MAME,
  newly added to `LogiqxDATParser`), and `<sample>` (`DATGame.disks`/
  `hasSamples`). Threaded through `AuditEntry.hasCHD`/`hasSamples`/
  `isBadDump`. **Important limitation, spelled out in ROADMAP.md**: this is
  presence-only, from what the DAT declares — it is NOT CHD file
  verification, NOT sample-file checking. ROMForge still doesn't look for
  a `.chd` file on disk, read one, or verify a sample exists; the "Games
  with CHD"/"Games with samples" filters only tell you which games *need*
  one, same honesty boundary as the already-existing "Bios files" filter.
  79 tests (2 added: DAT parsing of status/disk/sample, `AuditReporter`
  propagation).
- `DATGame.isBios` (Core): threaded from `MAMEMachine.isBios` through
  `DATLoader` into `AuditEntry.isBios`, so the app can tell BIOS sets apart
  from regular games. Always `false` for Logiqx/ClrMamePro DATs, which have
  no such concept.
- "Database" category tree (leftmost pane of `LibraryDetailView`), copying
  RomCenter's own left-hand panel (per
  [romcenter.com/forum/viewtopic.php?t=3459](https://www.romcenter.com/forum/viewtopic.php?t=3459)):
  All games / Originals / Clones / Bios files. Combines with the existing
  status filters (e.g. Clones + Incorrect). RomCenter's "Games with CHD",
  "Games with samples" and "Games with bad dumps" are intentionally left
  out — ROMForge doesn't parse disk/sample/baddump data yet, and faking
  those categories would misreport the collection (see ROADMAP.md).
- `AuditEntry.expectedSize`/`actualSize` (Core): threaded from `DATRom.size`
  and the scanned/hashed file's size, so the app can show a "Size" column.

### Changed

- Right-hand ROM table in `LibraryDetailView` polished to match RomCenter's
  own file list more closely (per a screenshot the user shared): separate
  "File name" (actual on-disk name) and "Rom name" (expected DAT name)
  columns instead of one combined "Name", plus new "Size" and "Crc/SHA-1"
  columns. Each row is now tinted with its status color (green/yellow/red/
  gray, at low opacity) across all columns, not just the leading icon.
  RomCenter's "Merge" checkbox column was left out — it drives merge-set
  rebuilding, which doesn't apply while `modificationsEnabled` is `false`.

- `LibraryDetailView` rebuilt as a RomCenter-inspired two-pane layout
  (adapted to native macOS, via `HSplitView`): a left "Games" tree (parent
  games with clones nested underneath, plus a "Surplus files" bucket) and a
  right-hand pane listing the ROM files belonging to whichever game is
  selected on the left — mirroring RomCenter's "Selection"/set-detail split
  instead of mixing games and ROMs into one combined tree. The existing
  filterable status labels (Correct/Incorrect/Missing/Surplus) are
  unchanged and still filter the games list. Each ROM row shows an
  "Info" column with RomCenter-style wording ("Ok" / "Bad name" / "Missing"
  / "Not needed here"). `AuditEntry` isn't `Identifiable`, so the right-hand
  table wraps it in a small internal `RomRow`. Verified end to end against a
  synthetic MAME-format DAT (`mslug` parent, `mslugx` clone): games list
  populated and grouped correctly, selecting a game populated its own ROM
  list on the right, status counts and the view-only banner rendered as
  expected.

### Added

- Project scaffold: XcodeGen `project.yml`, `ROMForgeCore` SPM package,
  `ROMForge` app target, GPLv3 license.
- `ROMForgeCore/DAT`: model (`DATFile`, `DATHeader`, `DATGame`, `DATRom`) and
  `LogiqxDATParser`, an `XMLParser`-based reader for Logiqx/ClrMamePro-style
  DATs (No-Intro, Redump, TOSEC, FBNeo). Handles `<game>`/`<machine>` roots,
  `cloneof`/`romof` attributes, and normalizes CRC/MD5/SHA1 to lowercase.
- `romforge-cli`: minimal executable to parse a DAT file from the command line.
- Unit tests covering well-formed parsing, malformed XML, a missing root
  element, and a `<rom>` missing its `size` attribute.
- `ROMForgeCore/Scanner`: `FolderScanner`, a recursive folder walker producing
  `ScannedFile` entries (path, name, size) for loose files, skipping hidden
  files. Archive scanning (ZIP/7z/CHD) is deferred to later phases.
- Documented long-term UI direction: visually rich per-game presentation
  (box art, screenshots, metadata) inspired by Batocera.linux, explicitly
  scoped out from becoming a ROM launcher/frontend.
- `ROMForgeCore/Hash`: `CRC32` (streaming zlib/ISO-3309 variant) and
  `FileHasher` (CRC32 + MD5 + SHA1 via CryptoKit), hashing either an in-memory
  buffer or a file streamed in fixed-size chunks so large ROMs never load
  fully into memory. Verified against the standard "123456789" test vectors.
- `ROMForgeCore/Matcher`: `ROMMatcher` compares hashed local files against a
  DAT's expected ROMs on size + declared hashes (CRC/MD5/SHA1) — never on
  filename alone — classifying each expected ROM as correct, misnamed (hash
  matches, name differs) or missing, and collecting unmatched local files as
  surplus. Each local file is consumed by at most one match.
- `ROMForgeCore/Reports`: `AuditReporter` collapses a `MatchReport` into a
  flat, exportable `AuditReport` (correct / incorrect / missing / surplus
  entries plus precomputed counts). **Closes the v0.1 core audit pipeline**:
  DAT → Scanner → Hash → Matcher → Reports is now fully implemented and
  tested end to end in `ROMForgeCore`.
- `ROMForgeCore/Rebuilder`: `RebuildPlanner` turns a `MatchReport` into a plan
  of `RebuildOperation`s (rename misnamed files in place; copy or move
  matched ROMs into `<destination>/<game>/<rom name>`), and `RebuildExecutor`
  applies a plan to the real filesystem. Never overwrites an existing
  destination — a collision is always a thrown error, not a silent clobber.
  **Closes v0.2** (automatic renaming, move/copy files).
- Added [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (MIT) as a
  dependency for ZIP support.
- `ROMForgeCore/Archive`: `ZipArchiveScanner` lists file entries inside a ZIP
  without decompressing them; `ZipArchiveHasher` streams an entry's
  decompressed content through CRC32/MD5/SHA1 without extracting to disk.
  `FileHasher` and the archive hasher now share one `StreamingHasher`.
- `RebuildPlanner.planRebuildAsZip` + a new `RebuildOperation.createArchive`
  case pack every matched ROM of a game into its own `<game>.zip` — the
  layout most emulators expect (set reconstruction).
- `ROMForgeCore/Reports`: `DuplicateDetector` groups hashed local files by
  SHA1, surfacing sets of two or more files with identical content
  regardless of filename. **Closes v0.3** (ZIP scanning/rebuilding, set
  reconstruction, duplicate detection).
- `ROMForgeCore/Archive/SevenZip`: 7z support via the system's `7zz`/`7z`
  binary (not bundled). `SevenZipLocator` checks known Homebrew paths and
  `PATH`, then validates each candidate is genuinely the **official** 7-Zip
  (https://www.7-zip.org) by running it and checking for its "Igor Pavlov"
  copyright banner — a same-named but unrelated binary is rejected, not
  trusted by filename alone. If nothing official is found, it reports how to
  install it: `brew install sevenzip` (confirmed to build from the official
  7-zip.org source, same version as the upstream release) or the direct
  https://www.7-zip.org/download.html link. `SevenZipRunner` shells out
  safely (stderr drained on a background queue to avoid pipe deadlocks).
  `SevenZipArchiveScanner` parses `7zz l -slt` output; `SevenZipArchiveHasher`
  extracts an entry to stdout (`7zz e -so`) and hashes it.
- `SevenZipInstaller.installViaHomebrew` offers a one-click install path for
  the future UI: runs `brew install sevenzip` — the formula name is
  hardcoded, never built from input, so this can only ever install the
  official 7-Zip formula. `BrewLocator` finds the `brew` executable itself
  (known paths + `PATH`), separate from `SevenZipLocator`.
- **Wired `ROMForgeCore` into the app.** `LibraryViewModel` (Observation,
  `@MainActor`) drives: pick a DAT/ROM folder (`NSOpenPanel`), Scan (parses
  the DAT, scans the folder, hashes every file, matches, generates the audit
  report — off the main thread via `Task.detached`), Fix (plans and executes
  repair operations, then rescans), Export Report (CSV via `NSSavePanel`).
  `ContentView` replaces the placeholder with the DAT/folder pickers, a
  ✔/⚠/✖/? status summary, a `Table` of audit entries, and a Scan/Fix/Export
  toolbar — matching the original wireframe. Verified end to end in the
  built app against a real DAT + ROM folder fixture (correct, renamed,
  missing and surplus all classified correctly; Fix renamed the
  misnamed file on disk and the rescan reflected it).
- **Systems sidebar.** `RomSystem` (name + DAT URL + ROM folder URL) and
  `SystemLibraryStore` (JSON persistence in Application Support — a plain
  JSON list is proportionate here; the SQLite/SwiftData catalog in the
  roadmap is a v2.0+ concern for scraped metadata, not this). `ContentView`
  is now a `NavigationSplitView`: a sidebar lists configured systems
  (add via `AddSystemSheet`, remove via context menu) and the detail pane
  (`LibraryDetailView`) runs the Scan/Fix/Export workflow for whichever
  system is selected. Verified end to end in the built app: added a system,
  scanned it, quit and relaunched — the system and its DAT/folder survived.
- **Detail pane.** `AuditEntry` (Core) now carries expected CRC32/MD5/SHA1
  (from the DAT) and actual CRC32/MD5/SHA1 (from the hashed local file) —
  `expected*` is nil for surplus files (the DAT says nothing about them),
  `actual*` is nil for missing ROMs (no local file to hash). The results
  table is now selectable; the bottom detail pane shows the selected row's
  name, game, DAT, path and all three hash pairs, matching the original
  wireframe's "Panel inferior" spec. Verified end to end in the built app.
- `ROMForgeCore/DAT/GameNameTagParser`: reads region and language(s) from a
  game's name/description using the No-Intro/TOSEC parenthesized-tag
  convention (e.g. `"Final Fantasy VII (Europe) (En,Fr,De,Es,It)"`) — DATs
  don't carry these as dedicated XML fields. The results table now has
  Region and Language columns. Verified end to end in the built app.
- `ROMForgeCore/Archive/CHD`: `CHDHeaderReader` parses the CHD v5 header
  (124 bytes, big-endian — offsets verified directly against MAME's
  `src/lib/util/chd.h`/`chd.cpp` source, not guessed) to read `logicalbytes`,
  `hunkbytes`, `unitbytes`, `rawsha1`, `sha1` and `parentsha1`. `CHDMatcher`
  compares a MAME DAT's expected `<disk sha1="...">` directly against a
  scanned `.chd` file's header `sha1` — no hunk decompression needed, since
  CHD already stores that hash itself (the same approach clrmamepro/RomVault
  use). Decoding hunk content for extraction/rebuilding remains a distinct,
  deferred milestone. Covered by synthetic byte-exact v5 headers built in
  tests (no real CHD file needed).
- Added [TESTING.md](TESTING.md): a manual testing checklist for real ROM
  collections. Every automated test uses synthetic fixtures — nothing has
  been run against a real ROM/BIOS/CHD collection yet, since that requires
  ROM files Claude cannot legally source.
- App icon: `Scripts/make-appicon.sh` generates `AppIcon.appiconset` from a
  1024×1024 source PNG, built from the icon provided in
  `Icons/App/rom_manager_icon_1024.png`. Verified it renders correctly on
  the built app.
- App icon replaced with `Icons/App/ROM1.png` (a hard hat on a microchip),
  a better fit for the project. The source photo was 1664×928 (not square,
  no alpha, white studio backdrop) — background removed (near-white,
  low-saturation pixels made transparent with a feathered edge so the
  helmet's yellow highlights and the chip's metal pins are never touched),
  center-cropped to a square, resized to 1024×1024, and masked into the
  macOS rounded-square (squircle) shape before regenerating
  `AppIcon.appiconset`. Saved as `Icons/App/rom1_icon_1024.png`. Verified on
  the built app (app switcher, against the system's own dark background).

### Performance pass

- `ROMMatcher` no longer does a linear scan + O(n) array removal per ROM
  (quadratic against a large DAT/collection). It now indexes hashed files
  by CRC32/MD5/SHA1/size once up front and looks up candidates through that
  index, with a `consumed` bit array instead of mutating the file list —
  same matching semantics (verified by the existing test suite), just no
  longer quadratic.
- `AuditReporter` computed correct/incorrect/missing/surplus counts with
  four separate full passes over `entries` (`filter { }.count` ×4); replaced
  with a single pass.
- `FileHasher.hash(files:)`: hashes many files concurrently (bounded to the
  machine's core count, chunked and reassembled in original order) instead
  of one at a time — a real bottleneck for large collections, since hashing
  is I/O- and CPU-bound per file and independent across files. Verified
  against sequential hashing for correctness (same result, same order).
  `LibraryViewModel.scan` now uses it instead of a sequential `map`.
- `LibraryDetailView`: `GameNameTagParser.parse` was called twice per row
  (once for the Region column, once for Language) on every table render;
  now parsed once per row when building `rows`. Selecting a table row did a
  linear scan rebuilding the whole `rows` array; since `AuditRow.id` is the
  entry's own index, selection is now a direct array lookup.
- `ROMForgeCore/DAT/MAME`: `MAMEListXMLParser` reads `mame -listxml` output
  into a `MAMEDataset` of `MAMEMachine`s — the BIOS/hardware superset of the
  generic Logiqx schema (`isbios`, `biosset`, `device_ref`, `disk`,
  `romof`/`cloneof`). `BIOSResolver` follows `romof` links to resolve a
  machine's full dependency chain (parent set and/or required BIOS) in one
  mechanism. **Closes v0.4** except CHD, deferred to its own milestone.
- `ROMForgeCore/DAT/MAME`: `SetMergeMode` (split/nonMerged/merged) and
  `MAMESetLayoutPlanner`, which computes each machine's output ROM list
  under a merge mode as a plain `DATGame` — so the existing Matcher and
  Rebuilder need no changes to support set variants. **Closes v0.5.** The
  `ROMForgeCore` audit/rebuild pipeline (v0.1–v0.5) is now feature-complete;
  what remains for v1.0 is wiring it into the SwiftUI interface.

### Multiple ROM folders per system

- `RomSystem.romFolderURL` → `romFolderURLs: [URL]` — splitting a collection
  across several folders (different drives, region subfolders) is common.
  Custom `Codable` conformance still reads old single-folder `systems.json`
  entries (falls back to the legacy `romFolderURL` key as a one-element
  list), so existing configured systems aren't lost.
- `FolderScanner.scan(folders:)` scans and concatenates several folders.
- `AddSystemSheet`: the single "Select ROM Folder…" button is now a
  "ROM Folders" list with "Add Folder…" (multi-select `NSOpenPanel`) and a
  remove button per entry.
- `LibraryViewModel.scan` and `LibraryDetailView`'s folder display updated
  for the list. Verified end to end: a system with two separate folders and
  one DAT scans both, classifies correct/incorrect properly across them,
  and Fix renames the misnamed file in whichever folder it actually lives in.

### RomCenter-style tree + filterable status labels

- `AuditEntry.cloneOf` (Core): propagated from the DAT's `cloneof`/`romof`
  via `AuditReporter`, so a UI can group clone sets under their parent
  without re-deriving it from the DAT separately.
- `LibraryDetailView`'s flat table is now a tree (`Table(_, children:)`):
  parent games at the top level, clone games nested under their parent
  (recursively, in case of clone-of-clone data), and each game's own ROMs as
  leaf rows underneath. A "Surplus files" bucket holds game-less entries.
  Verified end to end with a real parent/BIOS/clone MAME set (`neogeo` →
  `mslug` → `mslugx`, expandable, correctly nested).
- The Correct/Incorrect/Missing/Surplus status labels are now buttons:
  clicking one filters the tree to just that status; clicking the active
  one again (or "Clear filter") shows everything. Verified end to end.
- `RomSystem.category` (optional, empty by default): groups the sidebar
  into sections (e.g. "Nintendo", "SNK") instead of one flat list, set via
  a new field in the Add System sheet (with existing categories offered as
  quick-fill buttons). Old `systems.json` entries without a category decode
  as uncategorized. Verified end to end (category persisted, sidebar
  grouped under it after a real add + rescan).

### View-only mode; DAT picker wording

- **ROMForge no longer modifies ROM files, at the user's request.**
  `LibraryViewModel.modificationsEnabled = false` gates `fix()` — it now
  returns immediately with an explanatory message instead of running any
  rename. The Fix button is disabled in the UI (with a tooltip explaining
  why), and a visible "View-only mode" notice sits under the folder list.
  This is a single switch to flip back on later; nothing else changed about
  how repairs are planned.
- Confirmed `.dat`/`.xml` were already both supported regardless of
  extension (the picker has no content-type filter, and `DATLoader` detects
  format by content, not extension) — reworded the picker's helper text to
  say so explicitly instead of implying "XML DAT" only.

### MAME DAT auto-detection + ZIP scanning wired into the app

- **Root cause of "Scan does nothing":** the app's scan pipeline only parsed
  Logiqx/ClrMamePro XML DATs; a MAME `-listxml` DAT (root `<mame>`, not
  `<datafile>`) failed to parse immediately, and only loose files were ever
  scanned — a `.zip` full of ROMs was hashed as one opaque blob (never
  matching any DAT entry) instead of having its contents examined.
- `ROMForgeCore/DAT/DATLoader`: tries the Logiqx parser first, falls back to
  `MAMEListXMLParser` on failure (cheap and reliable, since a MAME dump's
  root element fails the Logiqx parse right away), converting to the same
  generic `DATFile`/`DATGame` model everything else already uses. Device
  machines (MAME's internal sub-components, not real games/BIOS) are
  excluded.
- `ROMForgeCore/Archive/CollectionHasher`: hashes loose files directly and
  expands `.zip` archives, hashing each entry individually instead of the
  archive as a whole — a zip entry's `HashedFile.file.url` points at the
  containing archive (there's no standalone file for one entry), which
  callers must account for before planning any file operation on it.
- `LibraryViewModel` now calls `DATLoader`/`CollectionHasher` instead of
  `LogiqxDATParser`/`FileHasher` directly. `fix()` skips any repair that
  would rename a `.zip`/`.7z` file itself (an archived entry's misnamed ROM
  isn't repairable yet) and reports how many were skipped instead of
  silently corrupting the archive.
- Verified end to end in the built app with a MAME-format DAT (root
  `<mame>`) and a ROM packed inside a `.zip`: the DAT loaded as "MAME"
  (no parse error), and the zipped ROM matched correctly with its path
  shown as the containing archive.

### Fixed

- **DAT picker silently hid `.dat` files.** `AddSystemSheet`'s "Select DAT…"
  panel restricted `allowedContentTypes` to `.xml`, but a `.dat` file's
  UTI doesn't conform to `public.xml` even when its content is XML — the
  panel showed it dimmed/unselectable, so `.dat` DATs (the most common
  extension for No-Intro/TOSEC/MAME DATs) could never be picked at all.
  Removed the content-type restriction entirely; real validation happens
  when the file is parsed, with a clear error if it isn't a valid DAT.
  Verified against a real MAME DAT file.
