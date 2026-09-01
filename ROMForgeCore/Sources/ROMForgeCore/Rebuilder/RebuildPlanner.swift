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

    /// Where a game's rom collection actually lives — the base every
    /// "cross-set repair" borrow gets added into. Determined by looking at
    /// that SAME game's own already-`.correct`/`.misnamed` roms (never
    /// invented from scratch): if any of them sits in a `.zip`, that zip is
    /// the anchor (`.addEntryToZip` rewrites it in place); if any is a
    /// genuinely loose file, that file's own containing folder is the
    /// anchor. A game with no anchor at all (every rom missing, or its only
    /// present roms sit inside an unsupported `.7z`) is skipped entirely —
    /// there's nowhere real to put a borrowed rom without inventing a
    /// location this planner has no business guessing at.
    private enum RepairAnchor {
        case zip(URL)
        case looseFolder(URL)
    }

    private static func existingAnchor(for gameResult: GameMatchResult) -> RepairAnchor? {
        for match in gameResult.matches {
            let hashedFile: HashedFile?
            switch match.status {
            case .correct(let file, _), .misnamed(let file, _): hashedFile = file
            default: hashedFile = nil
            }
            guard let hashedFile else { continue }
            if isZipPath(hashedFile.file.url) {
                return .zip(hashedFile.file.url)
            } else if !isArchivePath(hashedFile.file.url) {
                return .looseFolder(hashedFile.file.url.deletingLastPathComponent())
            }
        }
        return nil
    }

    /// True when two DAT-declared roms are the same underlying content —
    /// compared by declared size plus whichever ONE hash both sides happen
    /// to declare (CRC32 first, then MD5, then SHA1), same "only compare
    /// what's actually declared on both sides" caution `ROMMatcher`'s own
    /// `matchesRaw` uses. `false`, never a guess, when neither side shares a
    /// common declared hash at all.
    private static func datRomsShareContent(_ a: DATRom, _ b: DATRom) -> Bool {
        guard a.size == b.size else { return false }
        if let ac = a.crc, let bc = b.crc { return ac == bc }
        if let am = a.md5, let bm = b.md5 { return am == bm }
        if let asha = a.sha1, let bsha = b.sha1 { return asha == bsha }
        return false
    }

    /// The first sibling in `family` (excluding `excludingGameName`) that
    /// already has this exact rom content correctly on disk — the "donor"
    /// a missing rom gets borrowed from. A donor whose own file sits inside
    /// a `.7z` is skipped (no 7z-entry extraction support yet); a `.zip`- or
    /// loose-sourced donor is fine, since both can be read by
    /// `RebuildExecutor.readEntryData`/`extractZipEntry`.
    private static func findDonor(for missingRom: DATRom, in family: [GameMatchResult], excludingGameName: String) -> HashedFile? {
        for sibling in family where sibling.game.name != excludingGameName {
            for match in sibling.matches {
                guard datRomsShareContent(match.rom, missingRom) else { continue }
                let hashedFile: HashedFile?
                switch match.status {
                case .correct(let file, _), .misnamed(let file, _): hashedFile = file
                default: hashedFile = nil
                }
                guard let hashedFile else { continue }
                if isArchivePath(hashedFile.file.url) && !isZipPath(hashedFile.file.url) { continue }
                return hashedFile
            }
        }
        return nil
    }

    private static func archiveEntrySource(forDonor donor: HashedFile, outputEntryName: String) -> ArchiveEntrySource {
        let innerEntryName = isZipPath(donor.file.url) ? donor.file.name : nil
        return ArchiveEntrySource(source: donor.file.url, entryName: outputEntryName, sourceArchiveEntryName: innerEntryName)
    }

    /// Repairs a missing rom by borrowing it from a sibling parent/clone set
    /// that already has it — Fase 2 Step 3. "Sibling" means same family:
    /// `DATGame.cloneOf` chases every clone back to its shared parent, so
    /// two clones of the same parent (or a clone and its own parent) both
    /// count. Never invents a game's own storage location from scratch —
    /// see `existingAnchor`'s own doc comment for why a game with no
    /// anchor at all is skipped rather than guessed at.
    public static func planCrossSetRepair(matchReport: MatchReport) -> [RebuildOperation] {
        func familyKey(for game: DATGame) -> String { game.cloneOf ?? game.name }
        let families = Dictionary(grouping: matchReport.games, by: { familyKey(for: $0.game) })

        var operations: [RebuildOperation] = []
        for family in families.values where family.count > 1 {
            for gameResult in family {
                guard let anchor = existingAnchor(for: gameResult) else { continue }
                for romMatch in gameResult.matches {
                    guard case .missing = romMatch.status else { continue }
                    guard let donor = findDonor(for: romMatch.rom, in: family, excludingGameName: gameResult.game.name) else { continue }
                    let outputEntryName = safePathComponent(romMatch.rom.name)
                    switch anchor {
                    case .zip(let targetArchive):
                        operations.append(.addEntryToZip(
                            targetArchive: targetArchive,
                            entryName: outputEntryName,
                            source: archiveEntrySource(forDonor: donor, outputEntryName: outputEntryName)
                        ))
                    case .looseFolder(let folder):
                        let destination = folder.appendingPathComponent(outputEntryName)
                        if isZipPath(donor.file.url) {
                            operations.append(.extractZipEntry(archive: donor.file.url, entryName: donor.file.name, to: destination))
                        } else {
                            operations.append(.copy(from: donor.file.url, to: destination))
                        }
                    }
                }
            }
        }
        return operations
    }
}
