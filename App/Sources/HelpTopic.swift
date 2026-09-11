// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One page of the Help window — a sidebar of topics rather than one long
/// scrolling page, so a question has a place to be looked up rather than
/// scrolled to. Structure and styling deliberately mirror `HelpTopic`/
/// `HelpView` from jensyleo's own HardwareSentry (2026-09-03 request:
/// "ponle la documentacion de ayuda como la que usa hardwareSentry. Es mas
/// profesional") — same `HelpSection`/`Row` shape, same searchable sidebar,
/// same term-row styling for enumerable settings/actions.
struct HelpTopic: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
    let sections: [HelpSection]

    static func == (lhs: HelpTopic, rhs: HelpTopic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct HelpSection: Identifiable, Hashable {
    let id = UUID()
    var heading: String?
    var paragraphs: [String] = []
    /// Term-and-explanation rows, for actions and settings enumerated one
    /// after another (every Fix menu action, every status color, every
    /// Settings → Fix policy).
    var rows: [Row] = []

    struct Row: Identifiable, Hashable {
        let id = UUID()
        let term: String
        let detail: String
        /// A quiet tag beside the term — a default value, "Off by default".
        var note: String?
    }
}

enum HelpLibrary {
    static let topics: [HelpTopic] = [
        HelpTopic(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", symbol: "keyboard", sections: [
            HelpSection(paragraphs: [
                "Only shortcuts ROMForge itself actually implements — not every inherited standard macOS one (⌘W, ⌘Q, ⌘M), which every app already has and doesn't need repeating here.",
            ]),
            HelpSection(heading: "Database / ROM folder navigation", rows: [
                .init(term: "↑ / ↓", detail: "Move the selection up or down, including across the \"Database\" ↔ \"ROM folder\" boundary."),
                .init(term: "→", detail: "Expand the selected category or clone family."),
                .init(term: "←", detail: "Collapse the selected category or clone family."),
            ]),
            HelpSection(heading: "Games table", rows: [
                .init(term: "Type a letter/number", detail: "Jump to the first game whose file name starts with what's typed (classic Finder-style type-ahead)."),
            ]),
            HelpSection(heading: "ROM folder list", rows: [
                .init(term: "⌘-drag", detail: "Reorder a folder by hand (new folders otherwise sort alphabetically on their own)."),
            ]),
            HelpSection(heading: "Window & app", rows: [
                .init(term: "⌘,", detail: "Open Settings."),
            ]),
        ]),
        HelpTopic(id: "what-it-does", title: "What ROMForge does", symbol: "sparkles", sections: [
            HelpSection(paragraphs: [
                "ROMForge audits a ROM collection against a DAT (MAME `-listxml`, Logiqx, or a MAME Software List) and reports, per game, whether it's Correct, Incorrect (misnamed), Bad Dump, Missing, or unrecognized (\"Surplus\").",
                "By default it only ever reads and reports — nothing renames, moves, or deletes a file on disk until you deliberately turn that on (see \"Enabling write actions\"). Until then, every scan and audit stays completely safe to run against a real collection.",
            ]),
            HelpSection(heading: "Terminology: File vs ROM", paragraphs: [
                "Every Fix action name draws a strict line between these two words, so it's worth knowing before either shows up in a menu.",
                "**File** — the physical thing sitting on disk: an archive (`.zip`/`.7z`) or a standalone loose file. A File is a container. One File can hold many ROMs (a multi-rom `.zip`) or exactly one (a loose file, or a single-rom archive).",
                "**ROM** — one unit of game/BIOS/system content, as the DAT itself declares it. A ROM's bytes live either as their own standalone File, or as one entry inside an archive File alongside possibly several sibling ROMs.",
                "\"Fix\" a File's name means renaming the archive/loose file itself — nothing inside it changes. \"Fix\" a ROM's name means renaming one entry inside an archive, without touching the archive's own filename or any other ROM sitting next to it. The two are never interchangeable.",
            ]),
            HelpSection(heading: "Adding a system", paragraphs: [
                "The sidebar's \"Add System\" button (+) opens a sheet: a name, an optional category (with quick-fill buttons for categories you've already used), a DAT, and one or more ROM folders.",
                "No separate DAT file on hand? \"Generate from Installed MAME…\" runs the configured `mame` executable's own `-listxml` and uses its output directly, once a MAME executable is located in Settings → Systems. Leaving the name blank while picking or generating a DAT auto-fills it from the DAT's own filename (or \"MAME\", for a generated one) — a convenience, not a requirement.",
                "\"Add\" stays disabled until a name, a DAT, and at least one ROM folder are all present.",
            ]),
        ]),
        HelpTopic(id: "browsing", title: "Browsing your collection", symbol: "sidebar.left", sections: [
            HelpSection(heading: "The \"Database\" and \"ROM folder\" sidebar", paragraphs: [
                "\"Database\" browses the loaded DAT's own catalog — All games, Clones, By manufacturer, By year, and more — filtered by whichever branches are switched on in Settings → Systems. \"ROM folder\" lists the actual folders on disk configured for this system. Clicking either scopes the Games table on the right to match; the two are mutually exclusive.",
                "Both panels support arrow-key navigation once a row is selected: ↑/↓ move between rows (including across the \"Database\"/\"ROM folder\" boundary), → expands a category or a clone family, ← collapses it.",
                "Reorder \"ROM folder\" with the ↑/↓ chevrons that appear on the right of each row — new folders (\"Add Folder…\") slot into alphabetical order automatically, and the chevrons let you rearrange them by hand afterward.",
            ]),
            HelpSection(heading: "Searching a large \"Database\" category", paragraphs: [
                "A category like \"All games\" can hold tens of thousands of rows — typing in the search field above the tree narrows it down instantly, and auto-expands the currently-selected category if it was collapsed. Without a search, a very large category shows its first page only, with a \"Show N more\" row to reveal more in bounded steps rather than rendering everything at once.",
                "A plain search (no wildcards) matches from the start of a name — \"street\" matches \"Street Fighter\", not \"64 Street\". Use `*` (any run of characters) and `?` (any single character) for more control: \"*street*\" matches anywhere in the name, \"*64\" matches anything ending in \"64\".",
            ]),
            HelpSection(heading: "Right-click a game", rows: [
                .init(term: "Rescan This File", detail: "The same narrow rescan as the toolbar's \"Scan File\", for just this one game."),
                .init(term: "Play in MAME", detail: "Launches this one game directly in a configured MAME (see \"Playing in MAME\")."),
                .init(term: "Reveal in Finder", detail: "Jumps straight to the actual file on disk."),
                .init(term: "Verify ZIP Integrity", detail: "Checks whether this file's ZIP local-header and central-directory CRC32 agree — see \"Extra audit checks\"."),
            ]),
        ]),
        HelpTopic(id: "scanning", title: "Scanning, playing, exporting", symbol: "doc.text.magnifyingglass", sections: [
            HelpSection(heading: "Scanning", rows: [
                .init(term: "Scan File", detail: "Reads and rehashes just the one selected game's own file, genuinely on its own — nothing else on disk is touched. If that file has since been deleted or moved outside ROMForge, logs \"File not found\" immediately instead of quietly finishing and only then flipping the row to Missing."),
                .init(term: "Scan Folder", detail: "Reads and rehashes only the currently-selected \"ROM folder\", even if nothing there changed — no other folder is walked or re-read at all."),
                .init(term: "Scan All Folders", detail: "Reads every configured folder, but only genuinely rehashes whatever's actually changed since the last scan."),
            ]),
            HelpSection(heading: "How a scoped scan still stays correct", paragraphs: [
                "\"Scan File\"/\"Scan Folder\" only ever touch disk for their own scope — but the report they produce still reflects your WHOLE collection at once: every other folder's already-known files are pulled straight from the last scan's own cache rather than a fresh read, and everything (fresh plus remembered) is matched together in one pass. A duplicate rom sitting in two folders, or a game whose set spans more than one, is still resolved correctly — nothing about scoping the disk access makes the app \"forget\" what it already knew about the rest.",
            ]),
            HelpSection(heading: "\"Maximum subfolder depth\" — Settings → General", paragraphs: [
                "How many levels of subfolder a scan will descend into below a configured ROM folder — \"1\" (the default) covers the common `<system>/<game>/<file>` layout. A folder nested past this limit is skipped entirely, not scanned (logged as \"Skipped (nested too deep, not scanned)\"), rather than the whole scan failing over one too-deep subtree.",
                "Raise this if your own folders nest deeper — an extra organizational folder above the game level (e.g. a BATOCERA-style export: `<system>/BATOCERA/<game>/<file>`) needs \"2\". Kept deliberately capped rather than unlimited, so pointing a ROM folder at something far too broad (an entire drive) can't silently try to enumerate everything underneath it.",
            ]),
            HelpSection(heading: "Playing a game in MAME", paragraphs: [
                "The toolbar's \"Play\" button launches the selected game directly in a real, configured MAME — useful for confirming a rom actually runs, not just that ROMForge considers it Correct. Needs a genuine `mame` executable located first, in Settings → Systems; only MAME systems can use this at all.",
                "\"Purge MAME Auxiliary Files\" (also in Settings → Systems) clears whatever MAME itself wrote under its own working directory while running games launched this way — per-game config, screenshots, and in-progress hard-disk scratch state. It never touches your ROMs, DATs, or any scan result.",
            ]),
            HelpSection(heading: "Exporting", rows: [
                .init(term: "Export Report…", detail: "Saves a printable HTML report combining every configured system's last scan — a shareable snapshot, not a live view."),
                .init(term: "Export Fix DAT…", detail: "Saves a DAT containing only this scan's missing/incorrect entries, for feeding into another tool that already understands DAT format."),
                .init(term: "Export List to CSV…", detail: "Saves exactly what the Games table is currently showing (filters, search, and 1G1R hiding all apply) as a spreadsheet-ready file."),
                .init(term: "Compare DAT Versions…", detail: "Compares the currently loaded DAT against an older/different one you pick from disk — pure metadata comparison, never touches the scanned collection. \"Added\"/\"Removed\" list games gained or lost; \"Possible renames\" pairs up games that look like the same machine renamed."),
            ]),
        ]),
        HelpTopic(id: "status", title: "Status colors & columns", symbol: "circle.grid.2x2", sections: [
            HelpSection(heading: "Status colors", rows: [
                .init(term: "Correct", detail: "The file matches the DAT exactly.", note: "Green"),
                .init(term: "Incorrect", detail: "A real file was found but under the wrong name/location — usually fixable by renaming.", note: "Yellow"),
                .init(term: "Bad Dump", detail: "The DAT itself flags this exact rom as a known-bad or unverifiable dump.", note: "Orange"),
                .init(term: "Missing", detail: "Nothing was found for this rom at all.", note: "Red"),
                .init(term: "Surplus", detail: "A local file that matches nothing in the DAT — not necessarily useless, just unrecognized; safe to review and delete if unwanted.", note: "Gray"),
                .init(term: "Unverifiable", detail: "The DAT itself declares this rom has no dump to check against (a \"nodump\" entry), so its presence is neither right nor wrong.", note: "Half-gray"),
                .init(term: "Duplicate set", detail: "A game's set is physically present under more than one of this system's configured ROM folders — not a problem with the set itself, just an extra copy elsewhere.", note: "Blue"),
            ]),
            HelpSection(heading: "Duplicate sets across ROM folders", paragraphs: [
                "When a system has more than one configured ROM folder, the same game's set can end up physically present in two of them (different drives, region subfolders, etc.). ROMForge flags this rather than silently reporting the second copy as ordinary surplus — the row shows which folder holds the extra copy and which one is treated as the primary. Nothing is deleted or moved automatically; it's purely informational.",
            ]),
            HelpSection(heading: "The \"Family\" column", paragraphs: [
                "Shows parent/clone completeness, RomCenter-style. A parent game's row reads \"n/m clones\" — how many of its declared clone variants are actually present out of the total the DAT lists — turning orange once any are missing. A clone whose own parent set isn't present at all instead shows a small amber \"Parent missing\" warning. The two never appear on the same row.",
            ]),
            HelpSection(heading: "The \"Dependencies\" column", paragraphs: [
                "Shows what a game actually depends on to run under real MAME — a required BIOS set, a CHD disk, an internal device it references, sample sounds, or (for a clone) its parent set — as a short row of chips. Hover a chip for the exact detail.",
            ]),
        ]),
        HelpTopic(id: "1g1r", title: "1G1R", symbol: "star", sections: [
            HelpSection(paragraphs: [
                "\"One Game, One ROM\": many MAME DATs list the same game several times over, once per regional release — a world version, a USA version, a Japan version — related as a parent set and its clones. 1G1R is a purely visual feature: it picks one preferred variant per family and can hide the rest, so the table reads as one row per game instead of three or four near-duplicates. It never deletes, moves, or renames any file.",
            ]),
            HelpSection(heading: "How region is detected", paragraphs: [
                "Region detection reads the game's description straight out of the DAT, looking for a recognizable region name inside the parenthesized release tag most DATs already carry — e.g. \"Street Fighter II' (World 910522)\" is detected as World. Nothing is guessed from the filename or the internal machine name.",
                "Which region wins when a family has more than one recognizable variant is configured in Settings → View Options → \"1G1R region priority\": an ordered list where earlier beats later — drag entries to reorder.",
            ]),
            HelpSection(heading: "The star and the toggle", paragraphs: [
                "The star in the \"1G1R\" column marks exactly one row per family: whichever variant wins under the current region priority. It shows up whether or not \"Show Only 1G1R\" is on — the star answers \"which one would be preferred,\" the toggle answers \"should the others be hidden right now.\"",
                "\"Show Only 1G1R\" hides every non-preferred sibling in a family from the table, leaving just the starred row. The games list title reflects this with a \"· 1G1R hides n\" suffix.",
                "A family where no variant's description names any region on the priority list is left alone either way: nothing gets a star, and nothing is hidden — with no reliable way to rank the variants, ROMForge shows all of them rather than guessing.",
            ]),
        ]),
        HelpTopic(id: "audit-checks", title: "Extra audit checks", symbol: "checkmark.shield", sections: [
            HelpSection(rows: [
                .init(term: "Unused BIOS files", detail: "A physically-present BIOS archive (e.g. `neogeo.zip`) that nothing currently in the collection actually depends on — often left over after the games that needed it were removed or renamed away. Nothing is ever deleted automatically.", note: "Off by default"),
                .init(term: "Filename CRC mismatches", detail: "Some ROM sets (TOSEC/GoodTools-style) embed a file's CRC32 directly in its filename, e.g. \"Sonic The Hedgehog [12AB34CD].zip\". Flags a file whose embedded CRC disagrees with what its actual content hashes to.", note: "Off by default"),
                .init(term: "ZIP internal CRC inconsistencies", detail: "A `.zip` stores each entry's CRC32 twice — once in its local header, once in the central directory. A mismatch means something touched one copy and not the other, usually a truncated or corrupted file. Also runnable on demand for one file via \"Verify ZIP Integrity\" in its right-click menu.", note: "Off by default"),
            ]),
            HelpSection(paragraphs: [
                "All three are off by default in Settings → Systems' \"Database tree branches\" — checking them means extra reading of every archive, worth paying for only when you suspect a real problem.",
            ]),
        ]),
        HelpTopic(id: "write-access", title: "Enabling write actions", symbol: "lock.open", sections: [
            HelpSection(heading: "View-only mode", paragraphs: [
                "By default, ROMForge only ever reads and reports. The \"View-only mode\" banner (eye icon) above the Games table is a permanent reminder of that while it's active: nothing you do in the app renames, moves, deletes, or otherwise touches a ROM file on disk. It disappears once write actions are turned on — at that point the \"Fix\" toolbar dropdown becomes enabled instead.",
            ]),
            HelpSection(heading: "\"Enable file modifications\" — Settings → General", paragraphs: [
                "The single gate every rebuild/repair/rename/move/delete action in the app checks before doing anything — off by default, with a one-time confirmation dialog explaining what turning it on actually means before it takes effect. Turn it back off any time; every write action goes back to disabled immediately.",
                "Nothing here ever silently overwrites a file: a failed operation always leaves the original untouched, and every destructive action shows its own separate confirmation dialog on top of this general gate — turning this on doesn't skip those.",
            ]),
        ]),
        HelpTopic(id: "fix-menu", title: "The \"Fix\" menu", symbol: "wrench.and.screwdriver", sections: [
            HelpSection(paragraphs: [
                "Once write access is enabled, the toolbar's \"Fix\" button becomes a dropdown of every rebuild/repair action. Each previews exactly what it would do (a count of files/roms affected) and asks for explicit confirmation before touching a single file. Re-scan afterward to see the real, on-disk result.",
            ]),
            HelpSection(rows: [
                .init(term: "Fix Mismatched Files", detail: "Fixes a misnamed archive or loose File to the DAT's declared name, AND re-styles an already-correct one — both in one pass, styled per \"Sets case\" in Settings → Fix: the DAT's own exact case (default), all lowercase, all uppercase, or Capitalized. Acts on the File's own name only — a misnamed ROM entry inside an otherwise-correctly-named archive needs \"Fix Misnamed ROMs Inside Their Archives…\" below instead."),
                .init(term: "Rebuild to Folder…", detail: "Copies (or moves) every matched rom into a folder you pick, laid out as one subfolder per game."),
                .init(term: "Repair from Sibling Sets…", detail: "Fills in a rom missing from one game by copying it from a parent/clone sibling that already has the exact same content correctly. Never invents a location — a game with nothing of its own on disk yet is skipped."),
                .init(term: "Repair from Maintenance Folder…", detail: "The same idea as \"Repair from Sibling Sets…\", except the donor comes from the optional, read-only Maintenance folder configured in Settings → General — see \"The Maintenance folder\"."),
                .init(term: "Make Self-Contained…", detail: "Copies a rom already found genuinely present elsewhere in the scan (inherited from a BIOS or parent) into a game's own archive."),
                .init(term: "Strip Redundant ROMs (Split)…", detail: "The inverse of \"Make Self-Contained…\": once a clone's parent already has the exact same content, removes the clone's own now-redundant copy. Never touches the parent's own archive."),
                .init(term: "Fix Misnamed ROMs Inside Their Archives…", detail: "The ROM-level counterpart to \"Fix Mismatched Files\": fixes a misnamed ROM entry AND re-styles an already-correct one, both inside an otherwise-correctly-named archive, styled per \"Roms case\" in Settings → Fix (same four case choices), without touching the archive File's own filename or any other ROM inside it."),
                .init(term: "Handle Corrupted Files…", detail: "Applies whichever \"Corrupted files\" policy is configured in Settings → Fix (Don't Touch / Delete / Move to a quarantine folder) to every rom confirmed internally corrupt."),
                .init(term: "Merge Clones (Merged)…", detail: "Folds each clone's own unique roms into its parent's archive, then deletes the clone's now-empty archive entirely — the one action here that deletes a whole archive rather than one entry, built to be safe by construction."),
                .init(term: "Remove Useless Files…", detail: "Permanently deletes every file the DAT recognizes nothing about at all. The most destructive action here — its own confirmation is deliberately separate and explicit."),
            ]),
        ]),
        HelpTopic(id: "maintenance-folder", title: "The Maintenance folder", symbol: "tray.and.arrow.down", sections: [
            HelpSection(paragraphs: [
                "An optional, global, entirely read-only donor folder you configure once in Settings → General → \"Maintenance folder\" — left unset by default. Drop new or extra ROM dumps into it over time, under any filename you like; ROMForge never renames, moves, or deletes anything inside it, ever.",
                "\"Repair from Maintenance Folder…\" (the Fix dropdown) scans it and matches its content — by size and hash, never by filename — against every rom the current scan reports as Missing elsewhere in your collection, filling those in the same way \"Repair from Sibling Sets…\" does. If you already keep your own donor folder outside ROMForge, there's no need to use this at all.",
            ]),
        ]),
        HelpTopic(id: "settings-general", title: "Settings — General & View Options", symbol: "gearshape", sections: [
            HelpSection(heading: "General", paragraphs: [
                "Choose which hash algorithms (CRC32/MD5/SHA1) a scan computes, whether write actions are enabled, and the optional Maintenance folder.",
            ]),
            HelpSection(heading: "View Options", paragraphs: [
                "Toggle any of the six main panels (Database, ROM folder, Games, Roms, Detail, Log) off to declutter the window — \"Reset to Defaults\" brings them all back.",
                "The Log panel's toolbar has \"Copy Log\" (copies the whole log as plain text) and \"Clear Log\" (wipes it) — the log itself supports native text selection, so a specific range can be copied on its own instead of the whole thing. It also caps itself at 2000 lines, silently dropping the oldest entries past that point so a very long session can't grow the log without bound.",
                "\"Purge Saved Views\" resets remembered window layout only — which \"Database\"/\"ROM folder\" view was last selected per system, and every split-panel's size. It never touches any scan result.",
                "\"Purge Database View\" clears every system's last scan result instead (both the cached file hashes and the saved audit report) — each system needs a fresh Scan afterward. The two are deliberately separate actions.",
            ]),
        ]),
        HelpTopic(id: "settings-fix", title: "Settings — Fix", symbol: "slider.horizontal.3", sections: [
            HelpSection(paragraphs: [
                "Configures exactly what the \"Fix\" dropdown's policy-driven actions do, mirroring ClrMamePro's own Fix panel.",
            ]),
            HelpSection(rows: [
                .init(term: "Test archives before fixing", detail: "Runs a ZIP integrity check on every archive before \"Fix\" does anything else, applying the \"Corrupted files\" policy to whatever it finds.", note: "Off by default"),
                .init(term: "Remove useless files/roms automatically during Fix", detail: "Whether the general \"Fix\" pass also removes surplus without a separate prompt each time — the standalone \"Remove Useless Files…\" action always confirms regardless."),
                .init(term: "Corrupted files policy", detail: "Don't Touch / Delete / Move to a quarantine folder you choose — applied by \"Handle Corrupted Files…\"."),
                .init(term: "Sets case / Roms case", detail: "Don't Touch / Uppercase / Lowercase / Datafile Case / Capitalized. \"Fix Mismatched Files\"/\"Fix Misnamed ROMs Inside Their Archives…\" always apply this unconditionally, both to a genuinely wrong name (fixed TO this style — \"Don't Touch\" still fixes it, using the DAT's exact case) AND to an already-correct one (re-styled to it too, same click). \"Sets case\" applies to a zip-per-game archive's own filename; \"Roms case\" applies to a rom entry living inside a zip. Correcting a wrong name is not itself optional — this only ever governs HOW the name is styled. Any style other than Datafile Case makes the name differ from the DAT's own exact case — harmless on this Mac, but some tools/emulators are case-sensitive and may then fail to find the file, which can stop a game from running there."),
            ]),
            HelpSection(heading: "The DAT is always the source of truth", paragraphs: [
                "ROMForge's own \"Correct\"/\"Incorrect\" status (and \"Ok\"/\"Bad name\" in the Roms panel) is always decided by comparing a name to the DAT's own declared name EXACTLY, case included — never against whatever ROMForge itself last wrote there.",
                "This means choosing anything other than Datafile Case here is a real, permanent trade-off, not a cosmetic preference: if the DAT declares \"awbios.zip\" and \"Sets case\" is set to Uppercase, \"Fix Mismatched Files\" will happily rename it to \"AWBIOS.zip\" — and the very next Scan will report that same File as Incorrect/\"Bad file name\" again, because \"AWBIOS.zip\" ≠ the DAT's own \"awbios.zip\". Running \"Fix\" again just renames it right back to uppercase, forever — Fix and Scan disagreeing with each other on a loop, by design, for as long as this setting stays anything but Datafile Case.",
                "Datafile Case is the only style that can ever result in a genuinely, permanently \"Correct\"/\"Ok\" status — because it's the only one that styles a name to be byte-for-byte identical to what the DAT itself declares. Pick Uppercase/Lowercase/Capitalized only when a specific external tool or emulator needs that exact casing and you've accepted that ROMForge's own audit will keep calling it a mismatch.",
            ]),
            HelpSection(heading: "Not yet available", paragraphs: [
                "A few toggles further down (finding missing roms in scavenging folders, dummy roms for nodump entries, sample fixing, zip-comment removal, unzip-and-rezip, multiple rom formats) are visibly disabled — each needs its own not-yet-built infrastructure. They're shown anyway so this tab already reflects the full scope of ClrMamePro's own panel.",
            ]),
        ]),
        HelpTopic(id: "settings-systems", title: "Settings — Systems", symbol: "list.bullet", sections: [
            HelpSection(heading: "MAME executable", paragraphs: [
                "Locates a real `mame` binary (\"Default\" for the standard Homebrew path, or \"Locate…\" to pick one) — needed for the toolbar's \"Play\" button and \"Generate from Installed MAME…\". \"Purge MAME Auxiliary Files\" clears MAME's own per-game scratch state without touching anything ROMForge itself manages.",
            ]),
            HelpSection(heading: "Database", paragraphs: [
                "Re-points EVERY configured system at one new DAT in a single step — MAME's own database updates often, and every system configured here is normally just a category split of the same underlying MAME DAT, so re-picking each one by hand doesn't scale. Two sources, same ones \"Add System\" itself offers: \"Choose DAT File…\" picks any `.dat`/`.xml` already on disk; \"Generate from Installed MAME…\" runs the configured MAME executable's own `-listxml` directly (only shown once a MAME executable is set above).",
                "Confirms first, naming every system it's about to affect. Each affected system's last scan result is cleared as part of the same step — a system whose DAT just changed showing its OLD DAT's scan results until you happen to rescan would be actively misleading, not just stale — so run Scan Folder/Scan All Folders again afterward.",
                "There's no way yet to update only ONE specific system's DAT from here — edit that system directly for that (not yet built). A future non-MAME system type would get its own equivalent \"Database\" section here, not this one.",
            ]),
            HelpSection(heading: "Rom/Bios merge mode", rows: [
                .init(term: "Un-merged", detail: "Each archive is fully self-contained — the recommended default, at the cost of some duplicated disk space.", note: "Recommended"),
                .init(term: "Split", detail: "A clone only ever contains its own unique roms, relying on the parent for the rest."),
                .init(term: "Merged", detail: "One archive per parent holding every clone's content too, with clones producing no archive of their own."),
            ]),
            HelpSection(paragraphs: [
                "Applies to every MAME system at once, not per-system. Changing this re-parses a system's DAT the next time it's opened or scanned — rescan afterward for it to actually take effect.",
            ]),
            HelpSection(heading: "Database tree branches", paragraphs: [
                "Controls which categories appear under \"Database\" in the sidebar (MAME-specific for now), including the three off-by-default audit checks from \"Extra audit checks\".",
            ]),
        ]),
    ]
}
