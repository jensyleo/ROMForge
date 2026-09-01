// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Turns a `MatchReport` into a plan of filesystem operations. Planning never
/// touches disk — only `RebuildExecutor` does — so a plan can be reviewed
/// before anything is renamed, copied or moved.
public enum RebuildPlanner {
    /// Reduces a DAT-sourced name (rom or game name) to a single safe path
    /// component before it's ever appended to a filesystem `URL`. Rom/game
    /// names come straight out of parsed DAT XML — nothing here validates
    /// that a `<rom name="...">` or `<machine name="...">` attribute is
    /// actually a bare filename rather than e.g. `"../../../etc/passwd"` or
    /// an absolute path. `appendingPathComponent` happily honors both,
    /// which would let a maliciously crafted DAT steer `planRebuild`/
    /// `planRebuildAsZip`/`planRepair`'s output (and therefore
    /// `RebuildExecutor`'s real disk writes) outside the destination folder
    /// the user actually picked. Stripping to `lastPathComponent` collapses
    /// any `/`-separated traversal down to its final segment, and the
    /// `..`/`.` check catches a bare traversal segment that survives that
    /// (e.g. a name of exactly `".."`).
    static func safePathComponent(_ name: String) -> String {
        let last = (name as NSString).lastPathComponent
        return (last.isEmpty || last == "." || last == "..") ? "_" : last
    }

    /// True when `url` IS a `.zip`/`.7z` archive's own path rather than a
    /// loose file — the exact same distinction `LibraryViewModel`'s own
    /// `archivedRenameExtensions` draws for `fix()`'s renames. A matched
    /// rom's `HashedFile.file.url` is this archive path whenever the rom's
    /// real content lives inside it as one entry among others (see
    /// `CollectionHasher`'s own construction of a zip/7z-entry
    /// `ScannedFile`) — reading or writing that URL as if it were the rom's
    /// own standalone file would silently touch the WHOLE archive instead.
    private static func isArchivePath(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "zip" || ext == "7z"
    }

    private static func isZipPath(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    /// Renames misnamed local files in place (same folder) to the name their
    /// DAT entry expects. Files that are already correct or missing are left
    /// untouched.
    public static func planRepair(matchReport: MatchReport) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .misnamed(let hashedFile, _) = romMatch.status else { continue }
                let destination = hashedFile.file.url
                    .deletingLastPathComponent()
                    .appendingPathComponent(safePathComponent(romMatch.rom.name))
                operations.append(.rename(from: hashedFile.file.url, to: destination))
            }
        }
        return operations
    }

    /// Copies (or moves) every matched ROM — correct or misnamed — into
    /// `destination`, organized as `<destination>/<game name>/<rom name>`.
    /// Missing ROMs are skipped; there is nothing local to move. A rom whose
    /// content lives inside a `.zip` is extracted as its own file
    /// (`.extractZipEntry`, never `.copy`/`.move` — see that case's own doc
    /// comment for why); a rom inside a `.7z` is skipped entirely for now
    /// (no 7z-entry extraction support yet), same conservative "not
    /// supported yet" choice `fix()` already makes for a `.7z`-sourced
    /// rename.
    public static func planRebuild(matchReport: MatchReport, destination: URL, move: Bool) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            let gameFolder = destination.appendingPathComponent(safePathComponent(gameResult.game.name))
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _):
                    hashedFile = file
                case .missing, .foundElsewhere, .hashMismatch, .nodump:
                    // `.foundElsewhere`'s file genuinely belongs to another
                    // game's own archive (see its own doc comment) —
                    // rebuilding from it here would duplicate/steal a file
                    // that isn't really this game's own, so it's skipped
                    // exactly like a truly missing rom. `.nodump`'s file has
                    // no DAT hash to verify it against at all — rebuilding
                    // from it would silently package unverifiable content as
                    // if it were confirmed-correct, so it's skipped too.
                    hashedFile = nil
                }
                guard let hashedFile else { continue }
                let target = gameFolder.appendingPathComponent(safePathComponent(romMatch.rom.name))
                if isZipPath(hashedFile.file.url) {
                    operations.append(.extractZipEntry(archive: hashedFile.file.url, entryName: hashedFile.file.name, to: target))
                } else if isArchivePath(hashedFile.file.url) {
                    continue
                } else {
                    operations.append(move ? .move(from: hashedFile.file.url, to: target) : .copy(from: hashedFile.file.url, to: target))
                }
            }
        }
        return operations
    }

    /// Packs every matched ROM of each game into its own
    /// `<destination>/<game name>.zip`, the layout most emulators expect.
    /// Games with no matched ROMs produce no operation.
    public static func planRebuildAsZip(matchReport: MatchReport, destination: URL) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            let entries: [ArchiveEntrySource] = gameResult.matches.compactMap { romMatch in
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _):
                    hashedFile = file
                case .missing, .foundElsewhere, .hashMismatch, .nodump:
                    // `.foundElsewhere`'s file genuinely belongs to another
                    // game's own archive (see its own doc comment) —
                    // rebuilding from it here would duplicate/steal a file
                    // that isn't really this game's own, so it's skipped
                    // exactly like a truly missing rom. `.nodump`'s file has
                    // no DAT hash to verify it against at all — rebuilding
                    // from it would silently package unverifiable content as
                    // if it were confirmed-correct, so it's skipped too.
                    hashedFile = nil
                }
                guard let hashedFile else { return nil }
                // A 7z-sourced rom is skipped (no 7z-entry extraction
                // support yet) — this game's rebuilt zip just ends up
                // missing that one rom rather than the whole game being
                // skipped, same "do what's possible, report what wasn't"
                // spirit as `rebuildToFolder`'s own per-operation loop.
                guard !isArchivePath(hashedFile.file.url) || isZipPath(hashedFile.file.url) else { return nil }
                let innerEntryName = isZipPath(hashedFile.file.url) ? hashedFile.file.name : nil
                return ArchiveEntrySource(source: hashedFile.file.url, entryName: safePathComponent(romMatch.rom.name), sourceArchiveEntryName: innerEntryName)
            }
            guard !entries.isEmpty else { continue }
            let archiveURL = destination.appendingPathComponent("\(safePathComponent(gameResult.game.name)).zip")
            operations.append(.createTorrentZipArchive(entries: entries, to: archiveURL))
        }
        return operations
    }

    /// Deletes every file the DAT recognizes nothing about at all — Fase 2
    /// Step 7 ("Remove useless files"). Deliberately narrow: only a
    /// `SurplusFile` with `requiredByGameDescription == nil` (no OTHER game
    /// in the DAT claims this file's content either) AND
    /// `matchesNodumpRomName == false` (its name doesn't even match a
    /// declared-`nodump` placeholder some tool might have created on
    /// purpose) qualifies — genuinely unrecognized junk, never a file that's
    /// merely misplaced or belongs to a sibling set. The most destructive
    /// item in the whole Fase 2 checklist; callers must gate this behind
    /// its own explicit confirmation, separate from the general write-access
    /// gate (`LibraryViewModel.modificationsEnabled`).
    ///
    /// A surplus entry living INSIDE a `.zip`/`.7z` is excluded entirely,
    /// never planned as a `.delete` — jensyleo's own report (2026-09-01),
    /// caught before any real-ROM testing: `SurplusFile.file.file.url` for
    /// an archived entry is the containing archive's OWN path (see
    /// `CollectionHasher`'s own construction of a zip/7z-entry
    /// `ScannedFile`), so deleting it would permanently destroy the WHOLE
    /// archive — including every OTHER, legitimately-needed rom sitting
    /// next to that one unrecognized entry. Removing a single entry from
    /// inside an otherwise-kept archive needs a central-directory rewrite
    /// not built yet (same gap "Remove useless roms" in Settings → Fix is
    /// honestly marked "not yet connected" for) — until then, only a
    /// genuinely loose surplus file is ever safe to plan here.
    public static func planRemoveUselessFiles(matchReport: MatchReport) -> [RebuildOperation] {
        matchReport.surplusFiles
            .filter { $0.requiredByGameDescription == nil && !$0.matchesNodumpRomName && !isArchivePath($0.file.file.url) }
            .map { .delete($0.file.file.url) }
    }
}
