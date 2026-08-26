// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ROMForgeCore

/// A configured system in the sidebar: a name, a DAT, and one or more ROM
/// folders that together make up its collection — splitting a set across
/// several folders (different drives, region subfolders, etc.) is common.
/// `category` groups systems in the sidebar (e.g. "Nintendo") — empty means
/// uncategorized. Persisted by `SystemLibraryStore`.
///
/// Rom/Bios merge mode used to be a per-system field here — jensyleo's own
/// call (2026-07-27): having to configure it separately for every MAME
/// DAT/system (e.g. comparing two MAME versions side by side, each its own
/// `RomSystem`) made no sense for a setting that's really "how do I want
/// MAME sets laid out", not "how does *this specific* DAT want to be laid
/// out" — one MAME DAT's own `-listxml` doesn't declare a layout
/// preference any differently from another's. It's now a single, global
/// setting (`MAMEMergeModeSettings` in `GeneralSettingsView.swift`) that
/// applies uniformly to every MAME system, regardless of which one is
/// currently loaded/selected.
struct RomSystem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var category: String
    var datURL: URL
    var romFolderURLs: [URL]
    /// Whether this system's last-loaded DAT declared any clone
    /// (`cloneOf != nil`) game at all — `nil` until the DAT has been
    /// loaded/scanned at least once. Set by `LibraryDetailView` right
    /// after a DAT finishes loading (`onDATAnalyzed`), so Settings can
    /// warn when "Merged" (Rom/Bios merge mode) is selected for a system
    /// with no real parent/clone family to merge into at all — e.g. every
    /// NEOGEO machine is its own standalone `cloneOf == nil` entry, so
    /// "Merged" degenerates into something that looks like Un-merged for
    /// roms, but silently drops the BIOS's own standalone archive entry
    /// entirely (`DATLoader`'s own `biosMode == .merged` handling),
    /// leaving a real `neogeo.zip` unrecognized. jensyleo's own call
    /// (2026-07-30): kept as a global merge-mode setting (not reverted to
    /// per-system) — this is a *contextual warning* for whichever system
    /// happens to be selected, not a restriction on the setting itself.
    var hasClones: Bool?

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "",
        datURL: URL,
        romFolderURLs: [URL],
        hasClones: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.datURL = datURL
        self.romFolderURLs = romFolderURLs
        self.hasClones = hasClones
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, datURL, romFolderURLs, hasClones
        // From earlier, since-abandoned per-system designs — kept only so
        // systems saved by those builds still decode instead of crashing;
        // the values themselves are never read anymore (merge mode is a
        // global setting now, see this type's own doc comment).
        case legacyMergeMode = "mergeMode"
        case legacyBiosMergeMode = "biosMergeMode"
        case legacyIncludeBios = "showBiosSeparately"
        case legacyRomFolderURL = "romFolderURL"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Absent in systems saved before categories existed.
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ""
        datURL = try container.decode(URL.self, forKey: .datURL)
        // Falls back to the single-folder field from before multi-folder
        // support, so systems saved by older builds still load.
        if let urls = try container.decodeIfPresent([URL].self, forKey: .romFolderURLs) {
            romFolderURLs = urls
        } else {
            romFolderURLs = [try container.decode(URL.self, forKey: .legacyRomFolderURL)]
        }
        hasClones = try container.decodeIfPresent(Bool.self, forKey: .hasClones)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(datURL, forKey: .datURL)
        try container.encode(romFolderURLs, forKey: .romFolderURLs)
        try container.encodeIfPresent(hasClones, forKey: .hasClones)
    }
}
