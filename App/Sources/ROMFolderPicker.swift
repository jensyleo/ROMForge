// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import Foundation

/// The "pick one or more ROM folders" `NSOpenPanel` — shared by
/// `AddSystemSheet`'s and `LibraryDetailView`'s own "Add Folder…" actions,
/// found duplicated (same panel flags, same message wording, same
/// already-configured-folder dedup) during a 2026-08-18 code audit. Each
/// caller still does its own thing with the result — `AddSystemSheet` just
/// appends, `LibraryDetailView` inserts alphabetically — only the panel
/// itself and the dedup-against-`existing` filter were actually identical.
@MainActor
enum ROMFolderPicker {
    static func pickFolders(existing: [URL]) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more folders containing this system's ROMs"
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.filter { !existing.contains($0) }
    }
}
