// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Finds a game whose set is physically present under more than one of a
/// system's own configured ROM folders (`RomSystem.romFolderURLs`, several
/// folders scanned together for the same system) and produces one
/// `.duplicateSet` `AuditEntry` per extra copy — see `AuditStatus
/// .duplicateSet`'s own doc comment for why this is a separate case from
/// the per-rom `.incorrect`/"Not needed here" a same-named archive in a
/// second folder already gets from `ROMMatcher`/`AuditReporter.generate`.
/// That per-rom reporting is correct but scattered, one rom row at a
/// time — this adds the one game-level row that actually says "this whole
/// set already exists in another folder."
public enum DuplicateSetDetector {
    /// `rootFolders` in the system's own configured order — the earliest
    /// entry that owns a copy of a game is always treated as that game's
    /// "primary" one, matching `ROMMatcher.uniqued`'s own "first folder
    /// with a copy owns it" rule (same doc comment, same reasoning:
    /// deterministic, never dependent on which folder happened to be
    /// scanned last).
    ///
    /// Only rom entries with a real physical path are considered
    /// (`.correct`/`.incorrect`/`.badDump`, `path != nil`, never `.isDisk`
    /// — a CHD's own folder-duplication isn't this feature's scope, and
    /// ROMForge is MAME-only for now anyway). `.missing` has no path to
    /// place under any folder; the surplus statuses (`.surplus`/
    /// `.surplusInArchive`/`.unknownFile`) carry no `game`, so they can't
    /// be grouped by one.
    ///
    /// Collapses every rom belonging to the same (game, folder) pair down
    /// to a single synthetic entry — a duplicated archive typically holds
    /// many roms, and one row per rom would just be noise repeating the
    /// same fact.
    public static func detect(in report: AuditReport, rootFolders: [URL]) -> [AuditEntry] {
        guard rootFolders.count > 1 else { return [] }
        let orderedFolderPaths = rootFolders.map(\.path)

        // For a given file path, the first configured folder it falls
        // under — `nil` if it matches none (e.g. a path outside every
        // configured folder, which shouldn't normally happen but isn't
        // this detector's problem to diagnose).
        func folderIndex(forPath path: String) -> Int? {
            orderedFolderPaths.firstIndex { ScanCache.key(path, isUnder: $0) }
        }

        // One representative entry per (game, folder) — first one seen
        // wins, purely for a stable, deterministic representative path;
        // every rom under that same archive would say the same thing.
        var representativeByGameAndFolder: [String: [Int: AuditEntry]] = [:]
        for entry in report.entries {
            guard !entry.isDisk, let game = entry.game, let path = entry.path?.path else { continue }
            switch entry.status {
            case .correct, .incorrect, .badDump: break
            default: continue
            }
            guard let folder = folderIndex(forPath: path) else { continue }
            var byFolder = representativeByGameAndFolder[game] ?? [:]
            if byFolder[folder] == nil { byFolder[folder] = entry }
            representativeByGameAndFolder[game] = byFolder
        }

        var duplicates: [AuditEntry] = []
        for (_, byFolder) in representativeByGameAndFolder.sorted(by: { $0.key < $1.key }) {
            guard byFolder.count > 1 else { continue }
            let sortedFolders = byFolder.keys.sorted()
            guard let primaryFolder = sortedFolders.first, let primaryEntry = byFolder[primaryFolder] else { continue }
            for folder in sortedFolders.dropFirst() {
                guard let duplicateEntry = byFolder[folder] else { continue }
                duplicates.append(
                    AuditEntry(
                        status: .duplicateSet, game: duplicateEntry.game, gameDescription: duplicateEntry.gameDescription,
                        cloneOf: duplicateEntry.cloneOf, isBios: duplicateEntry.isBios,
                        duplicateSetPrimaryPath: primaryEntry.path,
                        name: duplicateEntry.name, path: duplicateEntry.path
                    )
                )
            }
        }
        return duplicates
    }
}
