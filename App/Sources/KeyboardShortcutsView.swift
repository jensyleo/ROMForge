// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import SwiftUI

/// "Keyboard Shortcuts" window (⌘?, Help menu) — jensyleo's own request
/// (2026-08-18), one of the GUI-polish checklist items. Lists only
/// shortcuts ROMForge itself actually implements (see each row's own
/// source below) — not every inherited standard macOS one (⌘W, ⌘Q, ⌘M),
/// which every app already has and a user doesn't need reminded of here.
struct KeyboardShortcutsView: View {
    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let description: String
    }

    private struct Section: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [Shortcut]
    }

    // Kept in sync by hand with the real key handling this app has —
    // `LibraryDetailView`'s `.onKeyPress` calls (database/ROM folder
    // navigation, type-ahead) and `ROMForgeApp`'s own `.commands`.
    private let sections: [Section] = [
        Section(title: "Database / ROM folder navigation", shortcuts: [
            Shortcut(keys: "↑ / ↓", description: "Move the selection up or down, including across the \"Database\" ↔ \"ROM folder\" boundary"),
            Shortcut(keys: "→", description: "Expand the selected category or clone family"),
            Shortcut(keys: "←", description: "Collapse the selected category or clone family"),
        ]),
        Section(title: "Games table", shortcuts: [
            Shortcut(keys: "Type a letter/number", description: "Jump to the first game whose file name starts with what's typed (classic Finder-style type-ahead)"),
        ]),
        Section(title: "ROM folder list", shortcuts: [
            Shortcut(keys: "⌘-drag", description: "Reorder a folder by hand (new folders otherwise sort alphabetically on their own)"),
        ]),
        Section(title: "Window & app", shortcuts: [
            Shortcut(keys: "⌘,", description: "Open Settings"),
            Shortcut(keys: "⌘?", description: "Open this Keyboard Shortcuts window"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Keyboard Shortcuts")
                    .font(.title2.bold())

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.headline)
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                            ForEach(section.shortcuts) { shortcut in
                                GridRow {
                                    Text(shortcut.keys)
                                        .font(.callout.monospaced())
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.leading)
                                    Text(shortcut.description)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 420)
    }
}
