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
    /// entry (skipping any folder in `recentlyScannedPaths`) that owns a
    /// copy of a game is treated as that game's "primary" one.
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
    ///
    /// - Parameter recentlyScannedPaths: jensyleo's own explicit rule
    ///   (2026-09-16) for the per-rom "Duplicated archive, not needed
    ///   here" flag (`ROMMatcher.match`'s own `recentlyScannedPaths`) —
    ///   the just-scanned folder's copy loses out to an untouched folder's
    ///   copy. Found live, via a background audit, that THIS detector's
    ///   own "primary" pick previously used a completely different,
    ///   static rule (always the earliest-configured folder, regardless
    ///   of scan history) — the two features could then contradict each
    ///   other about which folder is "the good one" for the exact same
    ///   duplicated game. Threading the same signal through here keeps
    ///   both in agreement. Empty by default, preserving the original
    ///   static-order behavior for any caller that doesn't pass this.
    public static func detect(in report: AuditReport, rootFolders: [URL], recentlyScannedPaths: [URL] = []) -> [AuditEntry] {
        guard rootFolders.count > 1 else { return [] }
        let orderedFolderPaths = rootFolders.map(\.path)
        let recentlyScannedPrefixes = recentlyScannedPaths.map(\.path)
        let recentlyScannedFolderIndices: Set<Int> = recentlyScannedPrefixes.isEmpty
            ? []
            : Set(orderedFolderPaths.indices.filter { index in
                recentlyScannedPrefixes.contains { ScanCache.key(orderedFolderPaths[index], isUnder: $0) }
            })

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
            let primaryFolder = sortedFolders.first { !recentlyScannedFolderIndices.contains($0) } ?? sortedFolders.first
            guard let primaryFolder, let primaryEntry = byFolder[primaryFolder] else { continue }
            // `dropFirst()` on `sortedFolders` would only ever be correct
            // if the primary were ALWAYS `sortedFolders[0]` — no longer
            // true once recency can pick a later index as primary instead.
            for folder in sortedFolders where folder != primaryFolder {
                guard let duplicateEntry = byFolder[folder] else { continue }
                duplicates.append(
                    AuditEntry(
                        status: .duplicateSet, game: duplicateEntry.game, gameDescription: duplicateEntry.gameDescription,
                        cloneOf: duplicateEntry.cloneOf, isBios: duplicateEntry.isBios,
                        duplicateSetPrimaryPath: primaryEntry.path,
                        name: duplicateEntry.name, actualEntryName: duplicateEntry.actualEntryName, path: duplicateEntry.path
                    )
                )
            }
        }
        return duplicates
    }
}
