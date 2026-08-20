// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A pure, Core-side mirror of App's `DatabaseFilter` — same cases, same
/// meaning, but with no SwiftUI/SF-Symbol concerns attached, so the actual
/// filtering logic (`apply(to:)`) can be unit-tested here instead of only
/// ever exercised by opening the app. `DatabaseFilter` maps 1:1 to this via
/// its own `coreCategory` computed property; this type never needs to know
/// `DatabaseFilter` exists.
///
/// Moved out of `LibraryDetailView.swift`'s `categoryFiltered(_:matching:)`
/// (2026-08-13, "Grupo A" of the App-logic extraction) — behavior
/// unchanged, pure relocation.
public enum DatabaseCategory: String, CaseIterable, Sendable {
    case allGames = "All games"
    case verifiedGames = "Verified games"
    case originals = "Originals"
    case clones = "Clones"
    case biosFiles = "Bios files"
    case gamesWithCHD = "Games with CHD"
    case gamesWithSamples = "Games with samples"
    case gamesWithBadDumps = "Games with bad dumps"
    /// jensyleo's own report (2026-08-13): `.gamesWithBadDumps` above
    /// collapses BOTH `baddump` and `nodump` into one branch (that's what
    /// `isBadDump` means — see its own doc comment on `AuditEntry`), so a
    /// genuine `nodump` game (no reference hash exists at all, not "exists
    /// but is known corrupt") was mixed in there with no way to see just
    /// those. `romDumpStatus` (also on `AuditEntry`) keeps the real
    /// distinction; this branch filters on it directly instead of the
    /// collapsed boolean.
    case gamesWithNodump = "Games with nodump"
    case byManufacturer = "By manufacturer"
    case byYear = "By year"
    case missingGames = "Missing games"
    case incorrectGames = "Incorrect games"
    case gamesRequiringBIOS = "Games requiring BIOS"
    case gamesWithDeviceRefs = "Games with device refs"
    case completeGames = "Complete games"
    case fixableGames = "Fixable games"
    case partialGames = "Partial games"
    case emptyGames = "Empty games"
    /// A physically-present BIOS archive (`neogeo.zip` and similar) that no
    /// currently-present game in this same collection actually depends on —
    /// see `OrphanedBIOSDetector`'s own doc comment for how it's computed
    /// and why it deliberately covers BIOS only, not samples (ROMForge has
    /// no sample-file scanning at all to check an orphan against). Added
    /// 2026-08-19, jensyleo's own request: a BIOS downloaded as part of a
    /// bulk set can easily outlive every game that needed it, quietly
    /// wasting space with no report anywhere pointing it out.
    case unusedBiosFiles = "Unused BIOS files"
    /// A file named per the TOSEC/GoodTools embedded-CRC convention whose
    /// declared CRC32 disagrees with its own actual content hash — see
    /// `AuditEntry.hasFilenameCRCMismatch`/`FilenameCRCVerifier` for how
    /// it's computed. Added 2026-08-19 alongside `.zipCRCInconsistencies`
    /// below, same read-only auditing spirit as `.unusedBiosFiles`.
    case filenameCRCMismatches = "Filename CRC mismatches"
    /// A `.zip` whose local-header CRC32 disagrees with its own
    /// central-directory CRC32 for the same entry — a structural
    /// inconsistency in the archive itself, not a DAT mismatch. See
    /// `AuditEntry.hasInternalZipCRCMismatch`/`ZipIntegrityAuditor`. Only
    /// ever populated after that on-demand check has actually run for this
    /// system (see that type's own doc comment) — empty otherwise, same as
    /// every other branch before its first real scan.
    case zipCRCInconsistencies = "ZIP internal CRC inconsistencies"

    /// Filters a flat `[AuditEntry]` list down to just the entries
    /// belonging to this category — identical logic to the original
    /// App-side `categoryFiltered(_:matching:)`.
    public func apply(to entries: [AuditEntry]) -> [AuditEntry] {
        switch self {
        // `.byManufacturer`/`.byYear` regroup the same full list "All
        // games" itself shows — not a subset, so they scope identically.
        case .allGames, .byManufacturer, .byYear: return entries
        case .verifiedGames:
            // A game counts as verified only if ALL of its roms matched —
            // filtering individual .correct entries would also surface a
            // few correct roms from an otherwise-incomplete game.
            let byGame = Dictionary(grouping: entries.filter { $0.game != nil }, by: { $0.game! })
            let verifiedGameNames = byGame.filter { _, gameEntries in gameEntries.allSatisfy { $0.status == .correct } }.keys
            return entries.filter { entry in entry.game.map(verifiedGameNames.contains) ?? false }
        case .originals: return entries.filter { $0.cloneOf == nil }
        case .clones: return entries.filter { $0.cloneOf != nil }
        case .biosFiles: return entries.filter { $0.isBios }
        case .gamesWithCHD: return entries.filter { $0.hasCHD }
        case .gamesWithSamples: return entries.filter { $0.hasSamples }
        case .gamesWithBadDumps: return entries.filter { $0.isBadDump }
        case .gamesWithNodump: return entries.filter { $0.romDumpStatus == .nodump }
        case .missingGames: return entries.filter { $0.status == .missing }
        case .incorrectGames: return entries.filter { $0.status == .incorrect }
        case .gamesRequiringBIOS: return entries.filter { $0.requiredBiosNames != nil }
        case .gamesWithDeviceRefs: return entries.filter { $0.deviceRefNames != nil }
        case .completeGames, .fixableGames, .partialGames, .emptyGames:
            let wanted: GameCompletionStatus = {
                switch self {
                case .completeGames: return .complete
                case .fixableGames: return .fixable
                case .partialGames: return .partial
                default: return .empty
                }
            }()
            let byGame = Dictionary(grouping: entries.filter { $0.game != nil }, by: { $0.game! })
            let matchingGameNames = byGame.filter { _, gameEntries in GameCompletionStatus.compute(for: gameEntries) == wanted }.keys
            return entries.filter { entry in entry.game.map(matchingGameNames.contains) ?? false }
        case .unusedBiosFiles: return entries.filter { $0.isOrphanedBios }
        case .filenameCRCMismatches: return entries.filter { $0.hasFilenameCRCMismatch }
        case .zipCRCInconsistencies: return entries.filter { $0.hasInternalZipCRCMismatch }
        }
    }
}
