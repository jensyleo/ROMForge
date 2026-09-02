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

    /// True when `donor`'s real, computed hash is the exact content `rom`
    /// declares — same "only compare what's actually declared on both
    /// sides" caution `datRomsShareContent` uses, just between a
    /// DAT-declared rom and an arbitrary hashed file (one that was never
    /// itself matched against any DAT) rather than two DAT-declared roms.
    private static func donorMatches(_ donor: HashedFile, rom: DATRom) -> Bool {
        guard donor.file.size == rom.size else { return false }
        if let romCRC = rom.crc, let donorCRC = donor.hash.crc32 { return romCRC == donorCRC }
        if let romMD5 = rom.md5, let donorMD5 = donor.hash.md5 { return romMD5 == donorMD5 }
        if let romSHA1 = rom.sha1, let donorSHA1 = donor.hash.sha1 { return romSHA1 == donorSHA1 }
        return false
    }

    /// Repairs a `.missing` rom by borrowing it from an external,
    /// read-only "Maintenance folder" the user configures once, in
    /// Settings → General (`MaintenanceFolderSettings`), and drops new or
    /// extra dumps into over time — jensyleo's own design (2026-09-02).
    ///
    /// Unlike `planCrossSetRepair` (which only ever borrows from a
    /// SIBLING set already present in this same `matchReport`), this
    /// looks entirely outside the scanned collection, at `donorFiles` —
    /// already hashed by the caller from a separate, independent scan of
    /// that folder — matched purely by CONTENT (`donorMatches`: size plus
    /// whichever one hash both sides declare), never by name or by
    /// having been matched against any DAT itself. `donorFiles` is only
    /// ever READ here, exactly like `planCrossSetRepair`'s own sibling
    /// donors: nothing in the Maintenance folder is ever renamed, moved,
    /// or deleted by this planner or by any operation it produces — every
    /// resulting `.copy`/`.extractZipEntry`/`.addEntryToZip` only reads
    /// from a donor's path, the actual write always lands in the SCANNED
    /// collection's own existing anchor (see `existingAnchor`'s own doc
    /// comment for why a game with none is skipped rather than guessed
    /// at).
    ///
    /// Deliberately narrow to `.missing` roms only — a `.hashMismatch`
    /// rom already occupies its own correct slot under content that's
    /// simply wrong, which would need an overwrite (remove the bad entry,
    /// then add the good one) this function doesn't attempt yet.
    public static func planRepairFromMaintenanceFolder(matchReport: MatchReport, donorFiles: [HashedFile]) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            guard let anchor = existingAnchor(for: gameResult) else { continue }
            for romMatch in gameResult.matches {
                guard case .missing = romMatch.status else { continue }
                guard let donor = donorFiles.first(where: { donorMatches($0, rom: romMatch.rom) }) else { continue }
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

    /// Applies `policy` to one current name, returning the target name a
    /// case-policy rename should produce — shared by both `Sets case` and
    /// `Roms case` (Fase 2 Step 9), which differ only in WHAT name they
    /// apply this to (an archive's own filename vs. one entry's name
    /// inside it) and what "the DAT's own declared name" means for
    /// `.datafileCase` in each (a game's name vs. a rom's name) — the
    /// transform itself is identical either way. `nil` when `policy` is
    /// `.dontTouch` or the target would be identical to `current` already
    /// (nothing to rename).
    private static func caseTransformTarget(current: String, datafileDeclaredName: String, policy: FileCasePolicy) -> String? {
        let target: String
        switch policy {
        case .dontTouch: return nil
        case .uppercase: target = current.uppercased()
        case .lowercase: target = current.lowercased()
        case .datafileCase: target = safePathComponent(datafileDeclaredName)
        }
        return target == current ? nil : target
    }

    /// Renames a game's own archive filename to match `policy` — Fase 2
    /// Step 9's "Sets case". Only applies to a `.zip`-anchored game (see
    /// `existingAnchor`'s own doc comment) — a loose-file collection has no
    /// single "set" filename for this to mean anything about. The file
    /// extension itself is never touched, only the basename.
    public static func planApplySetsCasePolicy(matchReport: MatchReport, policy: FileCasePolicy) -> [RebuildOperation] {
        guard policy != .dontTouch else { return [] }
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            guard case .zip(let currentURL)? = existingAnchor(for: gameResult) else { continue }
            let currentBasename = currentURL.deletingPathExtension().lastPathComponent
            guard let targetBasename = caseTransformTarget(current: currentBasename, datafileDeclaredName: gameResult.game.name, policy: policy) else { continue }
            let targetURL = currentURL.deletingLastPathComponent()
                .appendingPathComponent(targetBasename)
                .appendingPathExtension(currentURL.pathExtension)
            operations.append(.rename(from: currentURL, to: targetURL))
        }
        return operations
    }

    /// Renames every matched rom's own entry name inside its `.zip` to
    /// match `policy` — Fase 2 Step 9's "Roms case". Same add-then-remove
    /// shape as `planRenameRomsInArchive`, just driven by a case transform
    /// instead of a DAT-name mismatch. A `.7z`-sourced or loose rom is
    /// skipped (no 7z-entry rewrite support; a loose file's case is really
    /// a "Sets case"-shaped rename, not this one).
    public static func planApplyRomsCasePolicy(matchReport: MatchReport, policy: FileCasePolicy) -> [RebuildOperation] {
        guard policy != .dontTouch else { return [] }
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _): hashedFile = file
                default: hashedFile = nil
                }
                guard let hashedFile, isZipPath(hashedFile.file.url) else { continue }
                let currentEntryName = hashedFile.file.name
                guard let targetEntryName = caseTransformTarget(current: currentEntryName, datafileDeclaredName: romMatch.rom.name, policy: policy) else { continue }
                let zipURL = hashedFile.file.url
                operations.append(.addEntryToZip(
                    targetArchive: zipURL,
                    entryName: targetEntryName,
                    source: ArchiveEntrySource(source: zipURL, entryName: targetEntryName, sourceArchiveEntryName: currentEntryName)
                ))
                operations.append(.removeEntryFromZip(archive: zipURL, entryName: currentEntryName))
            }
        }
        return operations
    }

    /// Applies `policy` to every rom `ZipIntegrityAuditor` confirms is
    /// internally corrupt (a `.zip`'s own local-header vs central-directory
    /// CRC32 disagree for that one entry) — Fase 2 Step 8. Bridges Fase 1's
    /// read-only `AuditReport` (built here via `AuditReporter.generate`,
    /// which is itself already derived straight from `matchReport` — see
    /// its own doc comment) to Fase 2's write-capable `RebuildOperation`s,
    /// rather than duplicating `ZipIntegrityAuditor`'s own detection logic.
    ///
    /// Returns one operation GROUP per corrupted file — `.delete` is a
    /// group of one (`.removeEntryFromZip`); `.moveTo` is a group of two
    /// (extract the entry out to `quarantineFolder` FIRST, then remove it
    /// from the archive — same "never briefly lose the only copy" ordering
    /// `planRenameRomsInArchive` uses) — so a caller can execute and count
    /// "N corrupted files handled" accurately, the same way
    /// `LibraryViewModel.renameRomsInArchive` already does for its own
    /// two-operation renames, rather than miscounting raw operations.
    ///
    /// Only a `.correct` rom (on-disk entry name matches the DAT's declared
    /// name exactly) is eligible — a `.misnamed` rom that's ALSO internally
    /// corrupt is a rare double-fault this planner doesn't try to handle in
    /// one pass; fix the name first, rescan, then run this again. `nil`
    /// `quarantineFolder` under `.moveTo` skips every entry (nowhere
    /// configured to move them to) rather than silently falling back to
    /// `.delete`.
    public static func planCorruptedFilesPolicy(
        matchReport: MatchReport,
        policy: CorruptedFilesPolicy,
        quarantineFolder: URL?
    ) -> [[RebuildOperation]] {
        guard policy != .dontTouch else { return [] }
        guard let auditReport = try? AuditReporter.generate(from: matchReport) else { return [] }
        let flagged = ZipIntegrityAuditor.verifyingIntegrity(in: auditReport).entries
            .filter { $0.hasInternalZipCRCMismatch && $0.status == .correct }

        var groups: [[RebuildOperation]] = []
        for entry in flagged {
            guard let path = entry.path, isZipPath(path) else { continue }
            let entryName = safePathComponent(entry.name)
            switch policy {
            case .dontTouch:
                continue
            case .delete:
                groups.append([.removeEntryFromZip(archive: path, entryName: entryName)])
            case .moveTo:
                guard let quarantineFolder else { continue }
                let gameName = entry.game.map(safePathComponent) ?? "unknown"
                let destination = quarantineFolder.appendingPathComponent("\(gameName)_\(entryName)")
                groups.append([
                    .extractZipEntry(archive: path, entryName: entryName, to: destination),
                    .removeEntryFromZip(archive: path, entryName: entryName),
                ])
            }
        }
        return groups
    }

    /// Folds every clone's own unique roms into its parent's archive, then
    /// deletes the clone's whole archive — Fase 2 Step 4, the "Merged"
    /// direction. The one direction of merge-mode conversion that deletes
    /// a whole archive, not just one entry — the real design work this was
    /// deferred for until now.
    ///
    /// Safety comes from ORDER, not from a separate verification pass:
    /// each clone gets its own operation GROUP with every
    /// `.addEntryToZip` (copying one unique rom into the parent) listed
    /// BEFORE that clone's own `.delete` — the LAST operation in the
    /// group. `RebuildExecutor.execute(_:)` runs a group strictly in
    /// order and stops at the first failure (see its own doc comment), so
    /// the delete can only ever run once every single add before it in
    /// the SAME group has already succeeded. A `.addEntryToZip` failure
    /// (e.g. `RebuildError.destinationExists`, if two clones happen to
    /// share a uniquely-named rom neither the parent nor the other clone
    /// declares) aborts that one clone's whole group before its delete —
    /// that clone's archive survives, just not merged this pass.
    ///
    /// Two more guards keep this conservative:
    /// - A clone whose own archive ALSO holds a genuinely unaccounted-for
    ///   surplus file (`matchReport.surplusFiles`) is skipped entirely —
    ///   deleting that archive would silently destroy content this
    ///   function has no way to preserve elsewhere.
    /// - A clone with a `.hashMismatch`/`.nodump` rom whose own file sits
    ///   in the clone's own archive is skipped entirely too — content this
    ///   function can't safely fold into the parent (a mismatch's real
    ///   bytes don't match what the DAT declares; a nodump placeholder is
    ///   never truly "the rom") is content it also won't gamble on
    ///   discarding.
    ///
    /// Same "never invent a destination"/never-touch-the-parent's-own-copy
    /// spirit as `planConvertToNonMerged`/`planConvertToSplit`: a family
    /// with no identifiable zip-anchored parent, or a clone with no zip
    /// anchor of its own, produces no group for that clone.
    public static func planConvertToMerged(matchReport: MatchReport) -> [[RebuildOperation]] {
        func familyKey(for game: DATGame) -> String { game.cloneOf ?? game.name }
        let families = Dictionary(grouping: matchReport.games, by: { familyKey(for: $0.game) })
        let surplusZipPaths = Set(matchReport.surplusFiles.map { $0.file.file.url })

        var groups: [[RebuildOperation]] = []
        for family in families.values where family.count > 1 {
            guard let parent = family.first(where: { $0.game.cloneOf == nil }),
                  case .zip(let parentZip)? = existingAnchor(for: parent)
            else { continue }

            for gameResult in family where gameResult.game.cloneOf != nil {
                guard case .zip(let cloneZip)? = existingAnchor(for: gameResult), cloneZip != parentZip else { continue }
                guard !surplusZipPaths.contains(cloneZip) else { continue }

                var hasUnsafeContent = false
                var group: [RebuildOperation] = []
                for romMatch in gameResult.matches {
                    switch romMatch.status {
                    case .correct(let hashedFile, _), .misnamed(let hashedFile, _):
                        guard hashedFile.file.url == cloneZip else { continue }
                        guard !parentAlreadyHas(romMatch.rom, in: parent) else { continue }
                        let outputName = safePathComponent(romMatch.rom.name)
                        group.append(.addEntryToZip(
                            targetArchive: parentZip,
                            entryName: outputName,
                            source: archiveEntrySource(forDonor: hashedFile, outputEntryName: outputName)
                        ))
                    case .hashMismatch(let hashedFile), .nodump(let hashedFile):
                        if hashedFile.file.url == cloneZip { hasUnsafeContent = true }
                    case .missing, .foundElsewhere:
                        continue
                    }
                }
                guard !hasUnsafeContent else { continue }
                group.append(.delete(cloneZip))
                groups.append(group)
            }
        }
        return groups
    }
}
