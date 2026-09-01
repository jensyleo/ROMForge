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

    /// Renames a misnamed rom ENTRY inside an otherwise-correctly-named
    /// `.zip` — the entry-level half of "Rename files/roms" (Fase 2 Step 6)
    /// `planRepair` above can't do (its own `.rename` targets the
    /// containing zip's OWN path, which is exactly wrong for renaming one
    /// entry inside it; `LibraryViewModel.fix()`'s own
    /// `partitionArchivedRenames` already filters those back out before
    /// they ever reach disk). Implemented as add-then-remove — add the
    /// bytes under the new entry name FIRST (reading them via
    /// `RebuildExecutor.readEntryData`'s own `.update`-mode extraction
    /// while the old entry still exists), then remove the stale old-named
    /// entry — so the rom's own content is never briefly absent from the
    /// archive mid-operation if the add step fails.
    public static func planRenameRomsInArchive(matchReport: MatchReport) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .misnamed(let hashedFile, _) = romMatch.status else { continue }
                guard isZipPath(hashedFile.file.url) else { continue }
                let currentEntryName = hashedFile.file.name
                let expectedEntryName = safePathComponent(romMatch.rom.name)
                guard currentEntryName != expectedEntryName else { continue }
                let zipURL = hashedFile.file.url
                operations.append(.addEntryToZip(
                    targetArchive: zipURL,
                    entryName: expectedEntryName,
                    source: ArchiveEntrySource(source: zipURL, entryName: expectedEntryName, sourceArchiveEntryName: currentEntryName)
                ))
                operations.append(.removeEntryFromZip(archive: zipURL, entryName: currentEntryName))
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
    /// A surplus entry living INSIDE a `.zip` is removed as just that one
    /// entry (`.removeEntryFromZip`), never as a `.delete` of the whole
    /// archive — jensyleo's own report (2026-09-01), caught before any
    /// real-ROM testing: `SurplusFile.file.file.url` for an archived entry
    /// is the containing archive's OWN path (see `CollectionHasher`'s own
    /// construction of a zip-entry `ScannedFile`), so a plain `.delete` on
    /// it would have permanently destroyed the WHOLE archive — including
    /// every OTHER, legitimately-needed rom sitting next to that one
    /// unrecognized entry. `.removeEntryFromZip` uses ZIPFoundation's
    /// `.update` access mode to remove exactly that one entry and nothing
    /// else. A `.7z`-sourced surplus entry is still excluded entirely — no
    /// 7z-entry removal support (`SevenZipRunner` doesn't expose one).
    public static func planRemoveUselessFiles(matchReport: MatchReport) -> [RebuildOperation] {
        matchReport.surplusFiles
            .filter { $0.requiredByGameDescription == nil && !$0.matchesNodumpRomName }
            .compactMap { surplus in
                let url = surplus.file.file.url
                if isZipPath(url) {
                    return .removeEntryFromZip(archive: url, entryName: surplus.file.file.name)
                } else if isArchivePath(url) {
                    return nil
                } else {
                    return .delete(url)
                }
            }
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

    /// Makes every game in the scan self-contained by copying in any rom
    /// the matcher already found genuinely present elsewhere in the scan
    /// (`.foundElsewhere` — see that case's own doc comment) but not yet
    /// inside THIS game's own archive — Fase 2 Step 4, the "non-merged"
    /// direction only.
    ///
    /// The "Split" direction now also exists (`planConvertToSplit`, below)
    /// — the entry-removal gap this doc comment originally cited as
    /// blocking it was closed once `Archive.remove(_:)`/`.addEntry`
    /// (ZIPFoundation, `.update` access mode) turned out to already cover
    /// exactly that. "Merged" (fold every clone's own roms into the
    /// parent's archive AND delete the clone's own archive entirely) is
    /// still not offered — unlike Split's single-entry removal, it needs a
    /// whole multi-step, non-atomic sequence (copy every unique rom in,
    /// confirm each succeeded, THEN delete the clone's whole archive) with
    /// real partial-failure risk (a clone's archive deleted before every
    /// one of its roms is confirmed safely in the parent would be a
    /// genuine, unrecoverable data loss) that hasn't been designed yet.
    /// Same "never invent a destination" rule as `planCrossSetRepair`: a
    /// game with no existing anchor of its own is skipped.
    public static func planConvertToNonMerged(matchReport: MatchReport) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            guard let anchor = existingAnchor(for: gameResult) else { continue }
            for romMatch in gameResult.matches {
                guard case .foundElsewhere(let donor) = romMatch.status else { continue }
                guard !isArchivePath(donor.file.url) || isZipPath(donor.file.url) else { continue }
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
        return operations
    }

    /// Strips a rom back OUT of a clone's own archive when the PARENT
    /// already has the exact same content correctly — Fase 2 Step 4, the
    /// "split" direction. The inverse of `planConvertToNonMerged`: that one
    /// only ever ADDS a rom into a game's own archive; this one only ever
    /// REMOVES one, and only when the parent's own archive already,
    /// genuinely has it (never leaves BOTH copies gone — the parent's own
    /// copy is never touched by this function). Only removes from a `.zip`
    /// clone archive (no `.7z`-entry removal support); never touches the
    /// parent's own archive, and never produces an operation for the
    /// parent itself. A family with no identifiable parent (every game in
    /// it has `cloneOf != nil` — shouldn't happen with a well-formed DAT,
    /// but not this planner's job to fix) is skipped entirely.
    public static func planConvertToSplit(matchReport: MatchReport) -> [RebuildOperation] {
        func familyKey(for game: DATGame) -> String { game.cloneOf ?? game.name }
        let families = Dictionary(grouping: matchReport.games, by: { familyKey(for: $0.game) })

        var operations: [RebuildOperation] = []
        for family in families.values where family.count > 1 {
            guard let parent = family.first(where: { $0.game.cloneOf == nil }) else { continue }
            for gameResult in family where gameResult.game.cloneOf != nil {
                for romMatch in gameResult.matches {
                    let hashedFile: HashedFile?
                    switch romMatch.status {
                    case .correct(let file, _), .misnamed(let file, _): hashedFile = file
                    default: hashedFile = nil
                    }
                    guard let hashedFile, isZipPath(hashedFile.file.url) else { continue }
                    guard parentAlreadyHas(romMatch.rom, in: parent) else { continue }
                    operations.append(.removeEntryFromZip(archive: hashedFile.file.url, entryName: hashedFile.file.name))
                }
            }
        }
        return operations
    }

    /// True when `parent` already has `rom`'s exact content correctly on
    /// disk — the guard `planConvertToSplit` uses before ever stripping a
    /// clone's own copy of it.
    private static func parentAlreadyHas(_ rom: DATRom, in parent: GameMatchResult) -> Bool {
        for match in parent.matches {
            guard datRomsShareContent(match.rom, rom) else { continue }
            switch match.status {
            case .correct, .misnamed: return true
            default: continue
            }
        }
        return false
    }
}
