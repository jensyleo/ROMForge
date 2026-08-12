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
            }
            .padding(24)
        }
        .frame(width: 520, height: 560)
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
