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

    /// Whether this system's DAT parses as a MAME format (`-listxml` or a
    /// Software List) rather than plain Logiqx — decided once, in
    /// `AddSystemSheet.add()`, directly from the "Platform" picker's value
    /// (`category == .mame`), not by actually parsing the DAT — corrected
    /// 2026-10-01, a prior version of this comment claimed the DAT itself
    /// was parsed to decide this; the real code never does that, it trusts
    /// the explicit platform choice. This is what lets the GUI stop mixing
    /// MAME-only concepts (Rom/Bios
    /// merge mode, the MAME executable, Samples, and the MAME-only
    /// "Database" tree branches) into a console system's own settings —
    /// jensyleo's own request (2026-09-23), starting with NES: "hay que
    /// hacer ajustes en la GUI de tal manera que lo de MAME no se mezcle
    /// con los demás sistemas."
    ///
    /// Defaults to `true` for every system saved by a build before this
    /// field existed — every system ROMForge has ever supported until now
    /// WAS a MAME system, so that's the only historically-correct fallback
    /// (never `false`, which would suddenly treat someone's real MAME
    /// system as a plain console one on next launch).
    var isMAMEStyle: Bool

    /// jensyleo's own request (2026-09-29), right after adding NES: the
    /// Maintenance folder used to apply automatically to EVERY configured
    /// system the moment a root was set (originally deliberate — "cubre
    /// todo sistema sin importar el tipo") — confusing once a NEW system
    /// (NES) got a Maintenance sidebar row it never asked for, just
    /// because MAME's own root happened to already be configured. Now
    /// opt-in per system, same shape as BIOS/Samples/Complementary Chips'
    /// own "Enable X folder" toggles — `false` by default, including for
    /// every system saved by a build before this field existed (MAME
    /// itself included: re-enabling it there is a deliberate, one-time
    /// action, not an automatic upgrade).
    var maintenanceFolderEnabled: Bool
    /// Whether "Fix Mismatched Files"/"Fix Misnamed ROMs Inside Their
    /// Archives…" should ALSO offer a rename for a file the DAT recognizes
    /// nothing about by hash, purely because its own name is a close
    /// (but not exact) match for some real DAT game — jensyleo's own
    /// request (2026-09-29): a real GoodNES-style NES collection had many
    /// gray/unrecognized files whose actual, correct content just happens
    /// to sit under a slightly different name (a typo, a truncation, a
    /// stray character) than what the DAT declares. `false` by default —
    /// unlike `GoodToolsNameTranslator` (a fixed, deterministic table of
    /// known-safe rewrites folded silently into matching itself), this is
    /// a genuine best-effort GUESS with no content evidence behind it, so
    /// it stays opt-in, same shape as every other write-capable feature
    /// here. MAME-style systems never offer this toggle at all (see
    /// `SystemSettingsView`'s own Console-only gating) — MAME's own
    /// internal machine names are short and cryptic enough that even a
    /// high similarity threshold risks a false match (`"sf2"` vs `"sf3"`).
    var similarNameFixEnabled: Bool
    /// The minimum similarity (0.50...0.90) `similarNameFixEnabled` above
    /// requires before suggesting a rename — jensyleo's own request, a
    /// configurable range rather than a fixed number, after going back and
    /// forth between 90% (safer, misses more real matches) and 80%
    /// (catches more, slightly more false-match risk). Defaults to 0.80.
    var similarNameFixThreshold: Double
    /// Whether this system shows a region-quality hint badge (and the Info
    /// panel note) for a game ROMForge has a hand-curated note about — e.g.
    /// "the Japanese release has extra content the one you have doesn't".
    /// jensyleo's own request (2026-10-01): configurable per system,
    /// starting with NES — off by default like every other per-system
    /// opt-in here, so an existing system never gains new sidebar/table
    /// decoration it never asked for. See `RegionQualityNote` (Core) for
    /// why this can never be auto-derived from a DAT and has to be
    /// hand-curated.
    var regionQualityHintsEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        category: String = "",
        datURL: URL,
        romFolderURLs: [URL],
        hasClones: Bool? = nil,
        isMAMEStyle: Bool = true,
        maintenanceFolderEnabled: Bool = false,
        similarNameFixEnabled: Bool = false,
        similarNameFixThreshold: Double = 0.80,
        regionQualityHintsEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.datURL = datURL
        self.romFolderURLs = romFolderURLs
        self.hasClones = hasClones
        self.isMAMEStyle = isMAMEStyle
        self.maintenanceFolderEnabled = maintenanceFolderEnabled
        self.similarNameFixEnabled = similarNameFixEnabled
        self.similarNameFixThreshold = similarNameFixThreshold
        self.regionQualityHintsEnabled = regionQualityHintsEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, datURL, romFolderURLs, hasClones, isMAMEStyle, maintenanceFolderEnabled
        case similarNameFixEnabled, similarNameFixThreshold, regionQualityHintsEnabled
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
        isMAMEStyle = try container.decodeIfPresent(Bool.self, forKey: .isMAMEStyle) ?? true
        // Absent in every system saved before this field existed — `false`
        // by design (see this field's own doc comment), never inferred as
        // "was already relying on the old global behavior."
        maintenanceFolderEnabled = try container.decodeIfPresent(Bool.self, forKey: .maintenanceFolderEnabled) ?? false
        similarNameFixEnabled = try container.decodeIfPresent(Bool.self, forKey: .similarNameFixEnabled) ?? false
        similarNameFixThreshold = try container.decodeIfPresent(Double.self, forKey: .similarNameFixThreshold) ?? 0.80
        regionQualityHintsEnabled = try container.decodeIfPresent(Bool.self, forKey: .regionQualityHintsEnabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encode(datURL, forKey: .datURL)
        try container.encode(romFolderURLs, forKey: .romFolderURLs)
        try container.encodeIfPresent(hasClones, forKey: .hasClones)
        try container.encode(isMAMEStyle, forKey: .isMAMEStyle)
        try container.encode(maintenanceFolderEnabled, forKey: .maintenanceFolderEnabled)
        try container.encode(similarNameFixEnabled, forKey: .similarNameFixEnabled)
        try container.encode(similarNameFixThreshold, forKey: .similarNameFixThreshold)
        try container.encode(regionQualityHintsEnabled, forKey: .regionQualityHintsEnabled)
    }
}
