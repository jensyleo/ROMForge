// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// How a confirmed-bad archive is handled — the "Corrupted files" three-way
/// policy from ClrMamePro's own Fix panel (see ROADMAP.md's own review of
/// it). Lives in `ROMForgeCore` (moved here from the App target,
/// 2026-09-01) so `RebuildPlanner` can plan directly from a value of this
/// type instead of the App target translating its own persisted setting
/// into ad-hoc parameters at every call site.
public enum CorruptedFilesPolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case delete
    case moveTo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .delete: return "Delete"
        case .moveTo: return "Move to…"
        }
    }
}

/// How a rename target's case is chosen — applied independently to
/// archive-level names ("Sets case") and entry-level names inside an
/// archive ("Roms case"). "Datafile case" means: whatever case the DAT's
/// own declared name already uses, verbatim — distinct from "Don't touch"
/// (leave the existing on-disk name's case alone, even if it disagrees with
/// the DAT). Lives in `ROMForgeCore` (moved here from the App target,
/// 2026-09-01) for the same reason as `CorruptedFilesPolicy` above.
public enum FileCasePolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case uppercase
    case lowercase
    case datafileCase
    /// Title Case — each word's first letter uppercased, the rest
    /// lowercased (`String.capitalized`'s own definition of a "word").
    /// jensyleo's own request (2026-09-09).
    case capitalized

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .datafileCase: return "Datafile Case"
        case .capitalized: return "Capitalized"
        }
    }
}

/// Which physical copy `CHDMatcher`/`DiskAuditor` treats as the "correct"
/// one when the exact same disk (by header SHA1) exists more than once in
/// the scan — jensyleo's own request (2026-09-19), after noticing a real
/// `kinst2.chd` sitting BOTH directly in a ROM folder's own root AND inside
/// a same-named subfolder one level down (`Nintendo/kinst2.chd` vs
/// `Nintendo/kinst2/kinst2.chd`) — a real, common layout ambiguity (some
/// tools/exports put a game's CHD in its own subfolder, others expect it
/// sitting flat next to the `.zip`), with no single "obviously right"
/// answer ROMForge could safely guess on its own. Deliberately has NO
/// "no preference"/"whichever comes first" option — jensyleo's own
/// correction (2026-09-19): an unpredictable, order-of-discovery pick is
/// exactly the kind of ambiguity this setting exists to remove, so ALWAYS
/// resolving to one explicit, named rule is safer than allowing a silently
/// arbitrary one.
public enum CHDDuplicatePreference: String, CaseIterable, Identifiable, Sendable {
    /// The copy sitting directly in the ROM folder (its containing
    /// directory's name does NOT match the disk's own declared name).
    case preferRootFolder
    /// The copy sitting inside a subfolder named after the disk itself
    /// (its containing directory's name matches the disk's own declared
    /// name) — the `<system>/<game>/<file>` convention `FolderScanner`
    /// already walks one level into by default.
    case preferSubfolder

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .preferRootFolder: return "Prefer ROM Folder Root"
        case .preferSubfolder: return "Prefer Subfolder"
        }
    }
}

/// Where "Repair from Maintenance Folder…" looks for a donor file for a
/// `.missing` rom — jensyleo's own request (2026-09-11). Lives in
/// `ROMForgeCore` for the same reason as `CorruptedFilesPolicy`/
/// `FileCasePolicy` above: `LibraryViewModel.planRepairFromMaintenanceFolder
/// PreviewCount` plans directly from a value of this type.
public enum MissingRomsSearchScope: String, CaseIterable, Identifiable, Sendable {
    /// The system's own Maintenance subfolder only
    /// (`MaintenanceFolderSettings.subfolderURL(for:)`) — the original,
    /// narrower behavior this type replaces as the sole option. Nothing
    /// outside that one folder is ever read.
    case maintenanceFolderOnly
    /// The Maintenance subfolder AND every one of the system's own
    /// currently-configured ROM folders (`RomSystem.romFolderURLs`) — lets a
    /// rom that's merely misplaced in a sibling folder (a different drive, a
    /// region subfolder, an old backup location) donate to a `.missing` rom
    /// elsewhere in the same system, not just a rom deliberately staged in
    /// Maintenance. Still strictly read-only, same as the Maintenance-only
    /// case — nothing here ever writes to a ROM folder, only reads from it
    /// as a donor source.
    case allDeclaredFolders

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .maintenanceFolderOnly: return "Maintenance Folder Only"
        case .allDeclaredFolders: return "Maintenance Folder + All ROM Folders"
        }
    }
}
