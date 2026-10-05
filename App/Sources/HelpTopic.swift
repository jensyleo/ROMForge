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
            HelpSection(heading: "Where to get a DAT for a console/computer system", paragraphs: [
                "Unlike MAME (which can generate its own DAT via \"Generate from Installed MAME…\"), no console/computer emulator produces an equivalent listing — that DAT has to come from a community cataloging project instead. The two maintained, actively-curated sources are **No-Intro** (`datomatic.no-intro.org`) and **TOSEC** (`tosecdev.org`). Both publish the same Logiqx XML schema ROMForge already reads — no separate import format needed.",
                "**No-Intro publishes two separate DATs per system where a copier/format header exists — \"Headered\" and \"Headerless\"** (the latter often named with a `.unh` extension) — with genuinely different size/CRC/MD5/SHA1 values for the exact same physical file, not just a naming difference. Mixing files dumped for one variant into a scan run against the other DAT produces confusing, unrelated hash mismatches. For NES specifically, pick the **Headered** DAT: ROMForge's own header-skip logic already knows how to strip the 16-byte iNES header when hashing, which is the far more common real-world dump convention.",
                "A ready-made mirror (e.g. on GitHub) may look convenient, but check its actual format before using it — some community mirrors re-export No-Intro's data in the older ClrMamePro plain-text `clrmamepro ( ... )` format rather than Logiqx XML, or fold the Headered and Headerless variants into a single combined file. Neither matches what \"Add System\" expects here; get the DAT directly from No-Intro/TOSEC's own site instead.",
            ]),
            HelpSection(heading: "Removing a system", paragraphs: [
                "Right-click a system in the sidebar → \"Remove…\" asks for confirmation before doing anything — a plain \"Remove System\" forgets it (the sidebar entry, its scan cache, and its saved audit report), and \"Remove System and Delete Maintenance Folder\" also permanently deletes its own Maintenance subfolder and every donor rom inside it. Your actual ROM files are never touched by either choice — only the reference to them is forgotten.",
                "By default the Maintenance subfolder is kept even after removing a system, in case you add it back later with the same name.",
            ]),
        ]),
        HelpTopic(id: "browsing", title: "Browsing your collection", symbol: "sidebar.left", sections: [
            HelpSection(heading: "The \"Database\" and \"ROM folder\" sidebar", paragraphs: [
                "\"Database\" browses the loaded DAT's own catalog — All games, Clones, By manufacturer, By year, and more — filtered by whichever branches are switched on in Settings → Systems. \"ROM folder\" lists the actual folders on disk configured for this system. Clicking either scopes the Games table on the right to match; the two are mutually exclusive.",
                "Both panels support arrow-key navigation once a row is selected: ↑/↓ move between rows (including across the \"Database\"/\"ROM folder\" boundary), → expands a category or a clone family, ← collapses it.",
                "Reorder \"ROM folder\" with the ↑/↓ chevrons that appear on the right of each row — new folders (\"Add Folder…\") slot into alphabetical order automatically, and the chevrons let you rearrange them by hand afterward.",
                "Each \"ROM folder\" row's own icon shows what kind of volume it actually lives on — an internal-disk icon for local storage, an external-drive icon for a pendrive or external HDD, or a network-drive icon for an SMB/AFP/NFS share (a NAS) — detected from the real volume, never guessed from the path. Hover a row for the same information in its tooltip.",
                "Up to four special rows can appear at the bottom of this list, each with its own distinct icon instead of a volume icon — a tools icon (🔧) for the Maintenance subfolder (see \"The Maintenance folder\"), a chip icon (🖥️) for the BIOS folder, a puzzle-piece icon (🧩) for the Complementary Chips folder, and a speaker icon (🔊) for the Samples folder (see \"Settings — Systems\" → \"BIOS folder\"/\"Complementary Chips\"/\"Samples\"). All four are read-only areas ROMForge manages itself: none has the ↑/↓ reorder chevrons, and none can be removed from here — only from their own Settings page. Selecting BIOS/Complementary Chips shows their real matched games, same as any ordinary folder; selecting Samples or Maintenance correctly shows nothing in the Games table instead — neither one's content is ever part of this system's own audit.",
            ]),
            HelpSection(heading: "Searching a large \"Database\" category", paragraphs: [
                "A category like \"All games\" can hold tens of thousands of rows — typing in the search field above the tree narrows it down instantly, and auto-expands the currently-selected category if it was collapsed. Without a search, a very large category shows its first page only, with a \"Show N more\" row to reveal more in bounded steps rather than rendering everything at once.",
                "A plain search (no wildcards) matches from the start of a name — \"street\" matches \"Street Fighter\", not \"64 Street\". Use `*` (any run of characters) and `?` (any single character) for more control: \"*street*\" matches anywhere in the name, \"*64\" matches anything ending in \"64\".",
            ]),
            HelpSection(heading: "Right-click a game", rows: [
                .init(term: "Rescan This File", detail: "The same narrow rescan as the toolbar's \"Scan File\", for just this one game."),
                .init(term: "Play in MAME / Play in <emulator>", detail: "Launches this one game directly in a real, installed emulator — MAME for an Arcade system, or whichever emulator is configured in Settings → Systems → Consoles for a console/computer one (see \"Playing a game — MAME, or a configurable console emulator\")."),
                .init(term: "Reveal in Finder", detail: "Jumps straight to the actual file on disk."),
            ]),
        ]),
        HelpTopic(id: "scanning", title: "Scanning, playing, exporting", symbol: "doc.text.magnifyingglass", sections: [
            HelpSection(heading: "Scanning", rows: [
                .init(term: "Scan File", detail: "Reads and rehashes just the one selected game's own file, genuinely on its own — nothing else on disk is touched. If that file has since been deleted or moved outside ROMForge, logs \"File not found\" immediately instead of quietly finishing and only then flipping the row to Missing."),
                .init(term: "Scan Folder", detail: "Reads and rehashes only the currently-selected \"ROM folder\", even if nothing there changed — no other folder is walked or re-read at all."),
                .init(term: "Scan All Folders", detail: "Reads every configured folder, but only genuinely rehashes whatever's actually changed since the last scan."),
                .init(term: "Scan BIOS Folder", detail: "Scopes a scan to only the configured BIOS folder — same real scan \"Scan Folder\" performs for any other folder, just reachable directly from this dropdown (or the BIOS row's own context menu in the sidebar) without first selecting it. See \"Settings — Systems\" → \"BIOS folder\"."),
                .init(term: "Scan Complementary Chips Folder", detail: "The exact same idea as \"Scan BIOS Folder\" above, for the Complementary Chips folder instead. See \"Settings — Systems\" → \"Complementary Chips\"."),
                .init(term: "Scan Samples Folder", detail: "The exact same idea as \"Scan BIOS Folder\" above, for the Samples folder instead — refreshes what's actually sitting there, even though (unlike BIOS/Complementary Chips) none of it is ever matched against the DAT. See \"Settings — Systems\" → \"Samples\"."),
            ]),
            HelpSection(heading: "How a scoped scan still stays correct", paragraphs: [
                "\"Scan File\"/\"Scan Folder\" only ever touch disk for their own scope — never any other folder, not even a quick re-listing. Every other folder's already-known files (including the Maintenance folder's own donor list) are pulled straight from the last scan's own cache instead, and everything — fresh plus remembered — is matched together in one pass. A duplicate rom sitting in two folders, or a game whose set spans more than one, is still resolved correctly against the WHOLE collection; nothing about scoping the disk access makes the app \"forget\" what it already knew about the rest.",
                "What actually gets rewritten — on screen, and in the on-disk database — is decided the same simple way in both places: by comparing the fresh result directly against what was already known for that exact rom/file, entry by entry. Whatever's identical stays untouched (no flicker, no wasted disk write); whatever's new, gone, or genuinely different gets updated — regardless of whether it sits inside the folder you asked to rescan or is a knock-on effect somewhere else entirely (e.g. rescanning one archive can reveal that a completely different file, in another folder, is now the real owner of a shared rom). This is a direct comparison, never a guess about \"which other folders a rescan could have affected\" — so a knock-on effect anywhere in the collection is always reflected correctly, never left showing stale information.",
                "A `.zip`/`.7z` whose own modification date hasn't changed since the last time it was read is never even re-listed (its own directory of entries is served from the cache) — for a `.7z` in particular, that skips a real subprocess call per archive, which matters once a collection has more than a handful of them.",
            ]),
            HelpSection(heading: "What counts as a duplicate", paragraphs: [
                "Two files are treated as duplicates of each other only when BOTH their name and their content match exactly — content meaning a byte-for-byte identical hash, never just a similar size or a guess. The container's own extension is ignored for this comparison: a `.zip` and a `.7z` holding the exact same rom under the exact same name are still recognized as duplicates of one another, not treated as two unrelated files just because their extensions differ. Two files that merely share a name but hold different content (e.g. one is missing some of what the other has) are never merged or treated as interchangeable — each is judged entirely on its own.",
                "This same exact-match rule applies whether it's a whole File (an archive or loose file) or a single ROM entry living inside one — duplicate detection always looks at actual content, never just a filename.",
            ]),
            HelpSection(heading: "\"Maximum subfolder depth\" — Settings → General", paragraphs: [
                "How many levels of subfolder a scan will descend into below a configured ROM folder — \"1\" (the default) covers the common `<system>/<game>/<file>` layout. A folder nested past this limit is skipped entirely, not scanned (logged as \"Skipped (nested too deep, not scanned)\"), rather than the whole scan failing over one too-deep subtree.",
                "Raise this if your own folders nest deeper — an extra organizational folder above the game level (e.g. a BATOCERA-style export: `<system>/BATOCERA/<game>/<file>`) needs \"2\". Kept deliberately capped rather than unlimited, so pointing a ROM folder at something far too broad (an entire drive) can't silently try to enumerate everything underneath it.",
            ]),
            HelpSection(heading: "Playing a game — MAME, or a configurable console emulator", paragraphs: [
                "The toolbar's \"Play\" button (and a game's own right-click menu) launches the selected game directly in a real, installed emulator — useful for confirming a rom actually runs, not just that ROMForge considers it Correct. For an Arcade/MAME system, that's a genuine `mame` executable located in Settings → Systems → MAME.",
                "For a console/computer system, unlike MAME there's no single canonical emulator — Settings → Systems → Consoles lists every console system, each with its own \"Play games with\" choice, limited to emulators that can run that platform: NES offers Nestopia (`brew install --cask nestopia`) or FCEUX (`brew install fceux`), SNES offers Snes9x (`brew install --cask snes9x`), and any platform offers \"Custom…\" to point at an emulator you already have (a plain command-line executable or a `.app`, either works; the Custom path itself is shared by every system set to Custom). The same list also has each system's own \"Choose DAT…\", which replaces only that system's DAT.",
                "Either MAME or the configured console emulator only ever appears as an option when it's genuinely installed right now — never from a stale or leftover setting alone. Nestopia specifically is found by macOS itself (via its own app identity), so it works wherever Homebrew happens to have installed it, version folder and all — nothing to configure by hand.",
                "\"Purge MAME Auxiliary Files\" (Settings → Systems → MAME) clears whatever MAME itself wrote under its own working directory while running games launched this way — per-game config, screenshots, and in-progress hard-disk scratch state. It never touches your ROMs, DATs, or any scan result. No console emulator has an equivalent here — each manages its own files.",
                "For MAME, a gray \"Unknown game\" row can't be launched — MAME needs a real DAT machine name to run anything, and an unrecognized row has none. For a console/computer system, a gray/unrecognized row CAN still be played: \"Play\" there launches whatever file actually sits on disk, matched to a DAT entry or not — the exact same file \"Reveal in Finder\" already opens.",
            ]),
            HelpSection(heading: "Exporting", paragraphs: [
                "All three live under the toolbar's own \"Export\" dropdown, the same one-icon-many-actions shape \"Fix\" already uses.",
            ], rows: [
                .init(term: "Export Report…", detail: "Saves a printable HTML report combining every configured system's last scan — a shareable snapshot, not a live view."),
                .init(term: "Export Fix DAT…", detail: "Saves a DAT containing only this scan's missing/incorrect entries, for feeding into another tool that already understands DAT format."),
                .init(term: "Export List to CSV…", detail: "Saves exactly what the Games table is currently showing (filters, search, and 1G1R hiding all apply) as a spreadsheet-ready file."),
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
            HelpSection(heading: "\"— Has ZIP comment\" in the \"Info\" column", paragraphs: [
                "A `.zip`'s own file comment shows up as \"— Has ZIP comment\" appended to \"Info\", in both the Games and Roms tables — never the comment's actual text inline, to keep the column readable. Hover the cell to read the real comment in a tooltip. A file with no comment shows no suffix at all.",
            ]),
            HelpSection(heading: "\"Recognized content, but X doesn't have it either\"", paragraphs: [
                "A rom the DAT recognizes, sitting inside a game's own otherwise-correct archive, whose content is actually declared by a DIFFERENT game (\"X\") — but X has no confirmed real copy of it anywhere else in the scan. Real example: `gng.zip` (\"Ghosts'n Goblins (World? set 1)\", every one of its OWN roms genuinely correct) also holds a few roms that are byte-for-byte identical to \"Ghosts'n Goblins (World? set 2)\"'s own declared content — but set 2 has no archive of its own anywhere in the collection.",
                "No Fix action offers to touch this rom, on purpose, and that's not a bug: deleting it isn't safe (X might still need it) and there's nothing to \"repair\" here either, since this game's own archive is already correct. \"Remove Redundant Files…\"/\"Remove Redundant ROMs…\" only ever offer a rom once X's own real copy is CONFIRMED present elsewhere (the message then reads \"Duplicated archive/file, not needed here\" instead) — never merely because the content looks like it belongs somewhere else.",
                "The one action that can actually resolve this is \"Make Self-Contained…\" (the Fix dropdown) — it copies a rom found genuinely present elsewhere in the scan into the game that's actually missing it, so re-running it would give X (\"set 2\" in the example above) its own real copy, built from exactly this rom. It only works when X already has SOME real anchor of its own on disk (at least one other rom or its own archive) to copy into — a game entirely absent everywhere still needs a real archive obtained some other way first.",
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
                .init(term: "ZIP internal CRC inconsistencies", detail: "A `.zip` stores each entry's CRC32 twice — once in its local header, once in the central directory. A mismatch means something touched one copy and not the other, usually a truncated or corrupted file.", note: "Off by default"),
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
                .init(term: "Fix All…", detail: "Runs every fully-automatic action below in one pass, ClrMamePro-style, instead of clicking through each one by hand — in a safe order: names first, then the configured set layout (Split/Merged/Non-merged — MAME only, meaningless for a console DAT), then repairs (Sibling Sets, then the Maintenance folder), then Handle Corrupted Files, then the genuinely destructive cleanup (Remove Redundant ROMs/Files, then Remove Useless Files), and finally Zip Comments, Samples, BIOS, and Complementary Chips housekeeping. The ONE action never included is \"Rebuild to Folder…\", since it needs a destination only you can pick. Shows one combined preview count before asking for confirmation, same as every action below — but note the Log only ever shows the MOST RECENT step's own lines by the time it finishes (each step re-scans on its own, which clears the Log), so the final \"every automatic Fix action has run\" line is the one guaranteed to still be visible."),
                .init(term: "Fix Mismatched Files", detail: "Fixes a misnamed archive or loose File to the DAT's declared name, AND re-styles an already-correct one — both in one pass, styled per \"Sets case\" in Settings → Fix: the DAT's own exact case (default), all lowercase, all uppercase, or Capitalized. Acts on the File's own name only — a misnamed ROM entry inside an otherwise-correctly-named archive needs \"Fix Misnamed ROMs Inside Their Archives…\" below instead."),
                .init(term: "Rebuild to Folder…", detail: "Copies (or moves) every matched rom into a folder you pick, laid out as one subfolder per game."),
                .init(term: "Repair from Sibling Sets…", detail: "Fills in a rom missing from one game by copying it from a parent/clone sibling that already has the exact same content correctly. Never invents a location — a game with nothing of its own on disk yet is skipped."),
                .init(term: "Find ROMs…", detail: "Fills in a rom missing entirely, AND replaces one whose content is confirmed corrupt (a hash mismatch), from the optional, read-only Maintenance folder configured in Settings → Systems → MAME — see \"The Maintenance folder\". Also reachable by right-clicking one or more games in the Games table that have a donor available."),
                .init(term: "Make Self-Contained…", detail: "Copies a rom already found genuinely present elsewhere in the scan (inherited from a BIOS or parent) into a game's own archive."),
                .init(term: "Strip Redundant ROMs (Split)…", detail: "The inverse of \"Make Self-Contained…\": once a clone's parent already has the exact same content, removes the clone's own now-redundant copy. Never touches the parent's own archive."),
                .init(term: "Fix Misnamed ROMs Inside Their Archives…", detail: "The ROM-level counterpart to \"Fix Mismatched Files\": fixes a misnamed ROM entry AND re-styles an already-correct one, both inside an otherwise-correctly-named archive, styled per \"Roms case\" in Settings → Fix (same four case choices), without touching the archive File's own filename or any other ROM inside it."),
                .init(term: "Handle Corrupted Files…", detail: "Applies whichever \"Corrupted files\" policy is configured in Settings → Fix (Don't Touch / Delete / Move to a quarantine folder) to every rom confirmed internally corrupt."),
                .init(term: "Merge Clones (Merged)…", detail: "Folds each clone's own unique roms into its parent's archive, then deletes the clone's now-empty archive entirely — the one action here that deletes a whole archive rather than one entry, built to be safe by construction."),
                .init(term: "Remove Useless Files…", detail: "Permanently deletes every file the DAT recognizes nothing about at all. The most destructive action here — its own confirmation is deliberately separate and explicit. Deliberately skips a file whose exact name matches a `nodump` rom declared ANYWHERE in the loaded DAT (any game, not just the one it's sitting in) — real example, jensyleo's own live report (2026-09-23): a genuinely-junk leftover named exactly \"blswhstl\" (no extension, a stray from macOS's own AppleDouble metadata inside a `.zip` copied off a NAS) survived a \"Remove Useless Files…\" pass untouched, still showing \"Unrecognized (inside a known archive)\" in the Games table, because some MAME machine's own DAT entry happens to declare an undumped chip literally named \"blswhstl\" (a `nodump` rom has no reference hash to verify anything against, so there's no way to tell apart \"this really is that missing dump\" from \"this just happens to share its name\" — the safe default is to never auto-delete either possibility). This is NOT a bug or a leftover from a failed removal — it's intentional caution, checked by name alone, everywhere in the DAT, regardless of which game's archive the file is actually sitting in. If you've confirmed a specific survivor really is junk (not anyone's attempt at supplying that nodump content), delete it yourself: right-click the row → File Actions → Move to Trash/Delete Permanently, which never checks this protection at all."),
                .init(term: "Remove Redundant Files… / Remove Redundant ROMs…", detail: "The complement to \"Remove Useless Files…\": deletes a copy of content the DAT DOES recognize, but that isn't needed in this exact location because another game already has its own copy elsewhere (\"Not needed here (required by X)\"). \"Files\" removes a whole redundant loose file; \"ROMs\" removes only the redundant entry inside a `.zip`. Also reachable by right-clicking one or more games in the Games table."),
                .init(term: "Remove Zip Comments…", detail: "Removes the trailing file comment from every matched archive, without touching any entry inside it — see \"— Has ZIP comment\" in \"Status colors & columns\". Also reachable by right-clicking one or more Files in the Games table that have a comment."),
                .init(term: "Organize BIOS Files…", detail: "Moves every BIOS file found across this system's own configured ROM folders into the BIOS folder configured in Settings → Systems → MAME → \"BIOS\". A redundant further copy is removed only once another copy is confirmed safe elsewhere — same protection \"Remove Redundant Files…\" relies on. Toolbar-only, unlike most other actions here: since a BIOS can be referenced by games under any of this system's ROM folders, it always acts on the whole system rather than just the folder currently selected. Dynamic — only enabled when the current scan actually found a BIOS to move (hover it when it's greyed out to see exactly why); the confirmation dialog lists every BIOS by name before you commit, and the Log lists the same names again once it finishes, not just a bare count."),
                .init(term: "Organize Complementary Chips…", detail: "The exact same action as \"Organize BIOS Files…\" above, for MAME's own \"Device\" concept instead of BIOS — a sound DSP's own firmware, an I/O board's own program, a touchscreen controller, etc., each declared in the DAT as its own separate device machine (MAME's own official documentation: \"Device sets contain reusable circuit designs and their associated firmware that appear across multiple, otherwise unrelated arcade boards\", e.g. NAMCO51.ZIP). Moves each such device's own file into the Complementary Chips folder (Settings → Systems → MAME → \"Complementary Chips\"); a chip's rom that's genuinely embedded inside a game's own archive instead (never its own separate device file) is never touched. Same dynamic-enable, confirmation-lists-by-name, and Log-reports-by-name behavior as \"Organize BIOS Files…\"."),
            ]),
        ]),
        HelpTopic(id: "maintenance-folder", title: "The Maintenance folder", symbol: "tray.and.arrow.down", sections: [
            HelpSection(paragraphs: [
                "An optional, entirely read-only donor AREA — two levels of opt-in. First, set up the shared root once in Settings → Systems → \"Maintenance folder\" (either the MAME or Consoles tab — same one setting either way) — left unset by default; you pick where it should live and ROMForge creates a \"Maintenance\" folder there itself. Second, each system decides for ITSELF whether to actually use it, via its own toggle in that same section — off by default for every system, even one already using this feature before (jensyleo's own request, 2026-09-29: adding a new system shouldn't inherit a Maintenance row it never asked for just because the shared root happens to be configured already). Only a system with its own toggle on gets its own subfolder (\"Maintenance/MAME\", \"Maintenance/NES\", etc.) and its own sidebar row. Drop new or extra ROM dumps into a system's OWN subfolder, under any filename you like — ROMForge never renames, moves, or deletes anything inside any of it, ever.",
                "\"Find ROMs…\" (the Fix dropdown) scans ONLY the current system's own subfolder — never a different system's — and matches its content by size and hash, never by filename, against every rom the current scan reports as Missing elsewhere in your collection, filling those in the same way \"Repair from Sibling Sets…\" does. A system's own subfolder also shows up as a read-only entry in its \"ROM folder\" sidebar list, marked with a tools icon (🔧 `wrench.and.screwdriver.fill`) so it reads at a glance as different from your own configured folders, without being selectable as a normal, writable ROM folder. If you already keep your own donor folder(s) outside ROMForge, there's no need to use this at all.",
            ]),
        ]),
        HelpTopic(id: "settings-general", title: "Settings — General & View Options", symbol: "gearshape", sections: [
            HelpSection(heading: "General", paragraphs: [
                "Choose which hash algorithms (CRC32/MD5/SHA1) a scan computes and whether write actions are enabled. The Maintenance folder moved to \"Settings — Systems\" (2026-09-24) — see \"The Maintenance folder\".",
            ]),
            HelpSection(heading: "Matching — \"Ignore CRC/hash verification for console/computer systems\"", paragraphs: [
                "Never applies to an Arcade/MAME system, no matter how this is set — MAME's own parent/clone/BIOS structure depends on genuinely verified content (a wrong board revision or a bad dump can share the exact right file name), so an arcade scan always verifies CRC/MD5/SHA1 regardless of this toggle.",
                "For a console/computer system, turning this on makes a scan skip content verification entirely: a file already sitting under its exact expected name, in its own game's archive, is marked Correct — even if its hash doesn't match what the DAT declares at all. A genuinely corrupted or wrongly-substituted file with the right name is NOT flagged \"Bad\" in this mode; it reads as a plain, false Correct. Every file is still hashed (the CRC/MD5/SHA1 columns keep working for reference), only the Correct/Bad decision itself stops depending on that hash.",
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
                "A few toggles further down (dummy roms for nodump entries, sample fixing) are visibly disabled — each needs its own not-yet-built infrastructure. They're shown anyway so this tab already reflects the full scope of ClrMamePro's own panel.",
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
            HelpSection(heading: "Maintenance folder", paragraphs: [
                "Moved here from Settings → General (2026-09-24) — a real MAME/per-system concept, not a general app preference. See \"The Maintenance folder\" for the full picture; \"Choose Location…\" picks WHERE it should live, ROMForge creates (or reuses) \"Maintenance\" there plus one subfolder per configured system, after a confirmation naming the exact path.",
                "The root itself is shared across EVERY configured system, MAME or otherwise — moving its settings UI here doesn't narrow what it covers, only where you go to configure it.",
            ]),
            HelpSection(heading: "Samples", paragraphs: [
                "Optional, off by default — enable it and press \"Choose…\" to pick a folder (an already-existing one, chosen as-is — no create-confirmation step, unlike BIOS/Complementary Chips/Maintenance). \"Fix Samples\" (toolbar → Fix) searches this system's own configured ROM folders for a same-named sample zip and copies it in here, matched purely by filename since MAME's own DAT never declares a hash for a sample.",
                "Once configured, every scan reads this folder too, and it shows up as its own row (🔊 `speaker.wave.2.fill`) at the bottom of the \"ROM folder\" sidebar list, same convenience as BIOS/Complementary Chips — no manual ROM-folder entry needed. Deliberately different from those two in one way: its content is excluded from this system's own audit entirely, so selecting this row correctly shows an EMPTY Games table rather than a table full of \"Surplus\"/unrecognized rows — there's nothing in the DAT a sample could ever match against by hash, so folding it into the normal audit the way BIOS's real, hash-verified content is would just be noise.",
            ]),
            HelpSection(heading: "BIOS folder", paragraphs: [
                "Optional, off by default — enable it and press \"Choose…\" to pick WHERE it should live, same two-step behavior as the Maintenance folder right above: you choose the parent location, ROMForge creates (or reuses, if one already exists there) a \"BIOS\" folder inside it, after a confirmation naming the exact path — nothing is created without that confirmation.",
                "By itself, enabling this and choosing a folder moves nothing — it only makes the folder available. \"Organize BIOS Files…\" (toolbar → Fix) is the actual action that moves BIOS files into it; see \"The \\\"Fix\\\" menu\".",
                "Once configured, every scan (Scan Folder, Scan All Folders, or the verification rescan any Fix action runs afterward) automatically also reads this folder — you never add it as one of your own, editable ROM folders, and it's never part of that reorderable list. This is different from how the Maintenance folder's own automatic check works: a rom found there only ever gets flagged \"a donor is available\", still showing missing until you actually run a repair. A BIOS moved into the BIOS folder is the same real file, just relocated — so it keeps matching and showing correct, with nothing extra to run.",
                "It still shows up as its own row at the bottom of the \"ROM folder\" sidebar list, marked with a chip icon (🖥️ `cpu.fill`) so it reads at a glance as something different from your own configured folders — the Maintenance subfolder right above it gets the same visual treatment with a tools icon (🔧 `wrench.and.screwdriver.fill`). Tapping either just shows that folder's own real content in the Games panel, same as tapping any ordinary ROM folder; neither can be reordered, renamed, or removed from this list — that's done from Settings instead (BIOS folder here; Maintenance folder, both here in Settings → Systems → MAME).",
                "Its own columns: since browsing BIOS content calls for different columns than an ordinary game set, arrange the Games table the way you want while this row is selected, then save a column preset named exactly \"BIOS\" (View Options → Panels → column presets). ROMForge applies that preset automatically every time you select this row, and restores whatever columns were showing right before, automatically, the moment you select anything else — no separate \"BIOS view\" to maintain, just the existing column-preset feature reused for this one row.",
            ]),
            HelpSection(heading: "Complementary Chips", paragraphs: [
                "Practically identical to \"BIOS folder\" right above, for a different DAT category: MAME's own \"Device\" concept — a sound DSP's own firmware, an I/O board's own program, a touchscreen controller, and similar support hardware reused across otherwise-unrelated arcade boards, each declared as its own separate device machine in the DAT. MAME's own official documentation puts it plainly: \"Device sets contain reusable circuit designs and their associated firmware that appear across multiple, otherwise unrelated arcade boards\" (the example given there is NAMCO51.ZIP).",
                "Same two-step \"Choose…\" behavior, same automatic-scan behavior, same sidebar row treatment (a puzzle-piece icon, 🧩 `puzzlepiece.extension.fill`), and the exact same own-columns mechanism — save a preset named exactly \"Complementary Chips\" while this row is selected, and it auto-applies/restores the same way \"BIOS\" does.",
                "The one thing this deliberately does NOT do: move a chip's rom that's genuinely embedded inside a game's own archive (a real example found and confirmed while designing this feature — CPS2's own QSound sample roms, declared directly under the game's own machine, not a separate device) — only a rom the DAT itself models as belonging to a standalone device machine (like QSound's real firmware, `dl-1425.bin`, or Sega's `segadimm`) ever qualifies. \"Organize Complementary Chips…\" (toolbar → Fix) is the action itself; see \"The \\\"Fix\\\" menu\".",
            ]),
        ]),
        HelpTopic(id: "nes", title: "NES / console-specific notes", symbol: "gamecontroller", sections: [
            HelpSection(heading: "Choosing a DAT: Headered vs. Headerless", paragraphs: [
                "No-Intro publishes TWO separate DATs for NES — \"Headered\" and \"Headerless\" (the latter's rom names often end in `.unh`) — with genuinely different declared CRC/MD5/SHA1 for the exact same physical game, because the 16-byte iNES copier header is either included in that hash or not. Picking the wrong one against a real collection produces hash mismatches on content that's actually fine — a real case found live: a file's true CRC was `ebb1aa05`, but the loaded \"Headered\" DAT expected `3577ab04` for that same game, while the \"Headerless\" DAT's own declared hash for the SAME file, header stripped, matched exactly (`ba58ed29` both sides).",
                "If you're not sure which one your collection actually is: select any one file's Info panel and look at \"Header (iNES)\" — a real header starts with the 4 bytes `4E 45 53 1A` (\"NES\\x1A\"). If every real `.nes` entry inside your zips starts with that, you have headered dumps and should load the \"Headered\" DAT; if entries start directly with PRG-ROM data instead, you have headerless dumps and need \"Headerless\".",
                "ROMForge's own header-skip logic (`HeaderSkipRule`) already detects and strips a known copier header (iNES, and others for different consoles) when hashing, and tries BOTH the raw and header-stripped identity when matching against the DAT — so a headered file can still match a headerless DAT's declared hash. This does NOT work the other way around (a headerless file can never gain a header ROMForge invents), which is why a genuine hash mismatch like the one above means the DAT picked, not the files, was wrong.",
            ]),
            HelpSection(heading: "Mapper / audio-expansion chip naming", paragraphs: [
                "The Info panel's \"Header (iNES)\" line already decodes the mapper number from the header bytes — it now also names the real audio-expansion chip when the mapper implies one: Nintendo MMC5 (mapper 5), Namco 163 (19), Konami VRC6 (24, 26), or Konami VRC7 (85) — e.g. \"Mapper 24 (Konami VRC6 — audio expansion) · PRG 128KB · CHR 128KB…\". Most mappers (including the very common MMC1/MMC3) add no extra audio channels at all and show just the plain number, unchanged.",
                "This matters for exactly one real-world case: a handful of Famicom games shipped with a cartridge-side audio-expansion chip (Akumajou Densetsu's VRC6, Lagrange Point's VRC7, etc.) that adds extra sound channels beyond the console's own built-in APU — those extra channels only play back correctly in an emulator that specifically emulates that chip, and never play back at all on a real, unmodified NES (the expansion audio lines aren't wired on NES's simplified cartridge connector). It's purely informational — ROMForge never refuses to scan/fix a file based on its mapper.",
            ]),
            HelpSection(heading: "A duplicate archive never blocks Fix", paragraphs: [
                "If the exact same game exists in two different ROM folders (a common real case: a \"NO_INTRO\" master folder plus a curated \"SELECTED\" subset), the second copy is correctly flagged as a duplicate (\"Duplicated archive, not needed here\") — but being a duplicate never prevents fixing it. A misnamed rom entry, a wrong filename, or any other real Fix action still applies normally to a duplicate copy, exactly as it would to the one copy ROMForge picked as the \"primary\" — this applies to NES/console systems and MAME alike.",
            ]),
            HelpSection(heading: "Scanning over a NAS/network folder", paragraphs: [
                "A ROM folder on network storage (SMB/AFP/NFS) is dramatically slower to scan than the same collection on a local disk — confirmed, documented behavior of these protocols themselves (Microsoft's own SMB troubleshooting docs: thousands of small files always transfer far slower than one large file of the same total size, because every file open/read/close is its own network round trip). This is why an NES collection (many small individual rom files) feels much slower over NAS than a MAME collection of the same total size (fewer, larger per-machine zips, so fewer round trips for the same bytes) — not a bug, an inherent cost of the network file-sharing protocol itself.",
                "Settings → General → Performance → \"Number of threads\": when this is left on \"Auto\" and the ROM folder being scanned/hashed is detected as a network volume, ROMForge automatically uses a higher worker count (16) instead of the usual \"CPU cores minus one\" — since each worker mostly sits blocked waiting on the network rather than competing for CPU, more requests in flight hides round-trip latency instead of helping throughput the way it would for local, CPU-bound hashing. A manual override (if you set one) always takes priority over this automatic behavior regardless of where the folder lives; try 16–32 by hand if \"Auto\" still feels slow on your particular network.",
            ]),
        ]),
    ]
}
