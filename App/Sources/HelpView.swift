// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// "ROMForge Help" window (`CommandGroup(replacing: .help)` in
/// `ROMForgeApp`) — jensyleo's own request (2026-08-12), prompted directly
/// by realizing "ROM folder" reordering (added the same day) had nowhere
/// documented for a user to actually discover it: "la app debe tener un
/// about y un help donde explique cosas como esas... colócalos con lo
/// básico de la app". Covers the basics a first-time user (or jensyleo
/// themself, months later) would want without digging through source
/// comments — not exhaustive API documentation.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("ROMForge Help")
                    .font(.title2.bold())

                helpSection("What ROMForge does") {
                    Text("Audits a ROM collection against a DAT (MAME `-listxml`, Logiqx, or a MAME Software List) and reports, per game, whether it's Correct, Incorrect (misnamed), Bad Dump, Missing, or unrecognized (\"Surplus\"). It only ever reads and reports — it never renames, moves, or deletes a file on disk.")
                    Text("No separate DAT file on hand? \"Add System\" → \"Generate from Installed MAME…\" runs the configured `mame` executable's own `-listxml` and uses its output directly, once a MAME executable is located in Settings → Systems.")
                }

                helpSection("The \"Database\" and \"ROM folder\" sidebar") {
                    Text("\"Database\" browses the loaded DAT's own catalog — All games, Clones, By manufacturer, By year, and more — filtered by whichever branches are switched on in Settings → General. \"ROM folder\" lists the actual folders on disk configured for this system. Clicking either scopes the Games table on the right to match; the two are mutually exclusive.")
                    Text("Both panels support arrow-key navigation once a row is selected: ↑/↓ move between rows (including across the \"Database\"/\"ROM folder\" boundary), → expands a category or a clone family, ← collapses it.")
                    Text("Reorder \"ROM folder\" with the ↑/↓ chevrons that appear on the right of each row — new folders (\"Add Folder…\") slot into alphabetical order automatically, and the chevrons let you rearrange them by hand afterward.")
                }

                helpSection("Searching a large \"Database\" category") {
                    Text("A category like \"All games\" can hold tens of thousands of rows — typing in the search field above the tree narrows it down instantly, and auto-expands the currently-selected category if it was collapsed. Without a search, a very large category shows its first page only, with a \"Show N more\" row to reveal more in bounded steps rather than rendering everything at once.")
                    Text("A plain search (no wildcards) matches from the *start* of a name — \"street\" matches \"Street Fighter\", not \"64 Street\". Use * (any run of characters) and ? (any single character) for more control: \"*street*\" matches anywhere in the name, \"*64\" matches anything ending in \"64\".")
                }

                helpSection("Scanning") {
                    Text("\"Scan Folder\" rescans just the currently-selected \"ROM folder\" (forcing a fresh re-read of that one, even if nothing there changed) while still matching against every other configured folder. \"Scan All Folders\" does the same for every folder at once, but only genuinely re-reads whatever's actually changed since the last scan — both report which folder they're currently walking, in the progress overlay and in the Log panel.")
                }

                helpSection("Settings → View Options") {
                    Text("Toggle any of the six main panels (Database, ROM folder, Games, Roms, Detail, Log) off to declutter the window — \"Reset to Defaults\" brings them all back.")
                    Text("\"Purge Saved Views\" resets remembered window layout only — which \"Database\"/\"ROM folder\" view was last selected per system, and every split-panel's size. It never touches any scan result.")
                    Text("\"Purge Database View\" clears every system's last scan result instead (both the cached file hashes and the saved audit report) — each system needs a fresh Scan afterward. It never touches remembered layout/selection. The two are deliberately separate actions.")
                }

                helpSection("Settings → General") {
                    Text("Choose which hash algorithms (CRC32/MD5/SHA1) a scan computes, and which \"Database\" branches show at all in the sidebar — \"Select Minimum\", \"Select None\", and \"Reset to Defaults\" are quick presets for that second part.")
                }

                helpSection("View-only mode") {
                    Text("ROMForge only ever reads and reports. The \"View-only mode\" banner (eye icon) above the Games table is a permanent reminder of that: nothing you do in the app renames, moves, deletes, or otherwise touches a ROM file on disk.")
                }

                helpSection("Status colors") {
                    Text("Green = Correct, the file matches the DAT exactly. Yellow = Incorrect, a real file was found but under the wrong name/location — usually fixable by renaming. Orange = Bad Dump, the DAT itself flags this exact rom as a known-bad or unverifiable dump. Red = Missing, nothing was found for this rom at all.")
                    Text("Gray = Surplus, a local file that matches nothing in the DAT — not necessarily useless, just unrecognized; safe to review and delete if unwanted. Lighter/half-gray = Unverifiable, a rom the DAT itself declares has no dump to check against (a \"nodump\" entry), so its presence is neither right nor wrong. Blue = Duplicate set, an informational note that a game's set is physically present under more than one of this system's configured ROM folders — not a problem with the set itself, just an extra copy elsewhere.")
                }

                helpSection("Duplicate sets across ROM folders") {
                    Text("When a system has more than one configured ROM folder, the same game's set can end up physically present in two of them (different drives, region subfolders, etc.). ROMForge flags this as a \"Duplicate set\" (blue) rather than silently reporting the second copy as ordinary surplus — the row shows which folder holds the extra copy and which one is treated as the primary (the earliest-configured folder that already has it). Nothing is deleted or moved automatically; it's purely informational.")
                }

                helpSection("The \"Family\" column") {
                    Text("Shows parent/clone completeness, RomCenter-style. A parent game's row reads \"n/m clones\" — how many of its declared clone variants are actually present out of the total the DAT lists — turning orange once any are missing. A clone whose own parent set isn't present at all instead shows a small amber \"Parent missing\" warning. The two never appear on the same row.")
                }

                helpSection("The \"Dependencies\" column") {
                    Text("Shows what a game actually depends on to run under real MAME — a required BIOS set, a CHD disk, an internal device it references, sample sounds, or (for a clone) its parent set — as a short row of chips. Hover a chip for the exact detail (which BIOS, which device, how many disks, which parent).")
                }

                helpSection("1G1R — \"Show Only 1G1R\"") {
                    Text("\"One Game, One ROM\": within a parent/clone family, show only the single preferred regional variant instead of every clone side by side. Toggle it from the star button in the Games table's own toolbar — filled star means it's active. The preferred variant of a visible family gets a star of its own so it's easy to spot even with all variants showing.")
                    Text("Which region wins when a family has to pick one variant is configured in Settings → View Options → \"1G1R region priority\": an ordered list where earlier beats later. A variant whose description names none of the listed regions is never hidden by the filter and never taken as the family's own preferred pick either way.")
                }

                helpSection("\"Compare DAT Versions…\"") {
                    Text("Compares the system's currently loaded DAT against an older or different DAT file you pick from disk — pure metadata comparison, it never touches the scanned collection. \"Added\" lists games the new DAT introduces that the old one didn't have; \"Removed\" lists games the old DAT had that are gone from the new one; \"Possible renames\" pairs up an added and a removed game that look like the same machine renamed (matched by hash/structure, not just by name) so a rename doesn't read as one game vanishing and an unrelated one appearing.")
                }

                helpSection("\"Unused BIOS files\"") {
                    Text("A physically-present BIOS archive (e.g. `neogeo.zip`) that nothing currently in the collection actually depends on — often left over after the games that needed it were removed, renamed away, or never added. Off by default in Settings → General's \"Database\" branch list; nothing is ever deleted automatically, this only flags the archive so it's easy to find and review.")
                }

                helpSection("\"Filename CRC mismatches\"") {
                    Text("Some ROM sets (TOSEC/GoodTools-style, not MAME's own naming) embed a file's CRC32 directly in its filename, e.g. \"Sonic The Hedgehog [12AB34CD].zip\". This check flags a file whose embedded CRC disagrees with what its actual content hashes to — independent of whether the file sits in the right DAT slot or not, it only asks whether the name's own claim matches the bytes. Off by default in Settings → General's \"Database\" branch list.")
                }

                helpSection("\"ZIP internal CRC inconsistencies\" / \"Verify ZIP Integrity\"") {
                    Text("A `.zip` file stores each entry's CRC32 twice — once in its local header, once in the central directory. A real, undamaged archive keeps both copies identical; a mismatch means something touched one copy and not the other, usually a truncated or corrupted file. This is a manual, on-demand check (\"Verify ZIP Integrity\" in the Games table's toolbar, or the off-by-default \"ZIP internal CRC inconsistencies\" Database branch) rather than something every scan does automatically — checking it means re-reading every archive's own central directory a second time, which adds real time on a large collection for a problem that's rare in practice.")
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 560)
    }

    @ViewBuilder
    private func helpSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
