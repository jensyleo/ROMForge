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

    /// Whether this `ScannedFile` is an ENTRY INSIDE an archive rather than
    /// a file in its own right — the codebase's canonical test for the
    /// File-vs-ROM distinction, and the one every planner must use before
    /// deciding whether an operation targets a container or its contents.
    ///
    /// A zip/7z entry's `ScannedFile` reuses the CONTAINING ARCHIVE's own
    /// `url` and carries the entry name in `name` (see `CollectionHasher`'s
    /// construction of one, and `ScanCache.key(for:)`/`ROMMatcher
    /// .annotateMisnamedArchives`, both of which already discriminate this
    /// exact way). A file in its own right has `url.lastPathComponent ==
    /// name`.
    ///
    /// jensyleo's own instruction (2026-09-10): "distingue entre renombrar
    /// archivos .zip/7z y renombrar el contenido de los mismos, cosas muy
    /// distintas". Testing the PATH EXTENSION instead (`isZipPath`) answers
    /// a different question — "does this path end in .zip" — which is true
    /// both for an entry inside an archive AND for a junk archive that is
    /// itself the file in question, so it cannot tell the two apart. Every
    /// place that decided "container or contents?" from the extension alone
    /// was therefore guessing.
    private static func isArchivedEntry(_ file: ScannedFile) -> Bool {
        file.url.lastPathComponent != file.name
    }

    /// This rom's bytes live inside a `.zip` ENTRY — entry-level operations
    /// (`.extractZipEntry`/`.addEntryToZip`/`.removeEntryFromZip`) apply,
    /// and `file.url` is the CONTAINER, never the rom itself.
    private static func isZipEntry(_ file: ScannedFile) -> Bool {
        isArchivedEntry(file) && isZipPath(file.url)
    }

    /// This rom's bytes live inside an archive whose entries ROMForge has
    /// no rewrite support for (`.7z` — `SevenZipRunner` exposes no entry
    /// add/remove). Such a rom is always skipped rather than approximated
    /// by an operation on its container, which would hit every OTHER rom
    /// sitting next to it.
    private static func isUnrewritableArchiveEntry(_ file: ScannedFile) -> Bool {
        isArchivedEntry(file) && !isZipPath(file.url)
    }

    /// This rom IS a file in its own right, not an entry inside anything —
    /// File-level operations (`.rename`/`.copy`/`.move`/`.delete`) apply
    /// directly to `file.url`. True for a plain `.bin`, and also for a
    /// `.zip`/`.7z` that is itself the scanned file rather than a container
    /// being looked into — the case an extension test gets wrong.
    private static func isLooseFile(_ file: ScannedFile) -> Bool {
        !isArchivedEntry(file)
    }

    /// The target name a "Fix Mismatched Files"/"Fix Misnamed ROMs Inside
    /// Their Archives…" rename should produce, given the DAT's own declared
    /// name and a chosen case style — jensyleo's own request (2026-09-09):
    /// "Dejarlo como dice el DAT / Todo minúsculas / Todo mayúsculas /
    /// Capitalized" for BOTH File- and ROM-level fixes.
    ///
    /// Deliberately distinct from `caseTransformTarget` below (the other
    /// half `LibraryViewModel.fix()`/`renameRomsInArchive()` run in the
    /// SAME pass as this one): that one transforms an EXISTING,
    /// presumed-correct name's own case, since it only ever touches names
    /// that are already right. A mismatched File/ROM's
    /// CURRENT name is exactly what's wrong here instead — case-
    /// transforming it would just produce a differently-cased version of
    /// the WRONG name — so this always derives the result from the DAT's
    /// own declared name. `.dontTouch` has no meaning for "fix a mismatch"
    /// (there's always a real rename to make, by definition); treated the
    /// same as `.datafileCase`.
    private static func mismatchFixName(declaredName: String, policy: FileCasePolicy) -> String {
        let base = safePathComponent(declaredName)
        switch policy {
        case .dontTouch, .datafileCase: return base
        case .uppercase: return base.uppercased()
        case .lowercase: return base.lowercased()
        case .capitalized: return capitalizedPreservingExtension(base)
        }
    }

    /// `String.capitalized` title-cases the WHOLE string, extension
    /// included ("game.bin" → "Game.Bin") — not what "Capitalized" means
    /// for a filename (nobody wants ".Bin"/".Zip"). Title-cases only the
    /// base name and keeps the extension itself lowercase, the de facto
    /// convention every ROM/archive extension already follows.
    ///
    /// Shared by `mismatchFixName` above (a genuine mismatch's target
    /// name) AND `caseTransformTarget` below (an already-correct name
    /// being re-styled) — jensyleo's own instruction (2026-09-10) to
    /// review the app for coherence surfaced a real, previously
    /// undetected gap: `caseTransformTarget`'s own `.capitalized` branch
    /// called `current.capitalized` directly, with no extension
    /// protection at all. That's harmless for "Sets case" (the caller
    /// there already strips the extension before calling in), but for
    /// "Roms case" — where `current` is a full entry name WITH its own
    /// extension ("game.bin") — it silently produced "Game.Bin" for an
    /// entry that was already otherwise correct, exactly the bug this
    /// function exists to prevent, just reached through the other door.
    private static func capitalizedPreservingExtension(_ name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent.capitalized
        return ext.isEmpty ? stem : "\(stem).\(ext.lowercased())"
    }

    /// Renames misnamed local files in place (same folder) to the name their
    /// DAT entry expects, styled per `filesCasePolicy` (default: the DAT's
    /// own exact declared case). Files that are already correct or missing
    /// are left untouched. Three genuinely distinct sources of a File-level
    /// mismatch, all handled here:
    ///
    /// 1. A LOOSE file whose own name doesn't match its rom's declared name
    ///    — `hashedFile.file.url` IS the file to rename directly.
    /// 2. A whole ARCHIVE sitting under the wrong filename while its content
    ///    clearly belongs to one specific game
    ///    (`SurplusFile.misnamedArchiveForGameName`) — jensyleo's own
    ///    real-world test case (2026-09-11): an archive whose entries are
    ///    all individually named correctly for their game never produces a
    ///    single `.misnamed` rom match (every entry's own name already
    ///    equals its rom's declared name — only the CONTAINER's name is
    ///    wrong), so this whole scenario silently fixed nothing before this
    ///    loop existed, despite being exactly what "Fix Mismatched Files"
    ///    is for.
    /// 3. An archive that genuinely IS this game's own — every entry
    ///    matched correctly by hash — but whose OWN filename carries the
    ///    wrong CASE ("AWBIOS.zip" instead of "awbios.zip"). jensyleo's own
    ///    real-world NEOGEO test (2026-09-10): once a prior "Roms case"
    ///    pass has already re-styled every entry's own name to match its
    ///    declared rom name exactly, no rom in that archive is ever
    ///    `.misnamed` either — same silent-no-op shape as #2, just with the
    ///    archive belonging to the RIGHT game instead of the wrong one.
    ///
    /// A `.misnamed` rom whose content lives INSIDE a `.zip`/`.7z` entry
    /// never renames its container by itself in loop #1 above — its own
    /// CONTAINER name is a separate concern, handled (if actually wrong)
    /// by loop #3; the ENTRY's own name inside it is "Fix Misnamed ROMs
    /// Inside Their Archives…"'s job, never this File-level action's.
    /// Treating a `.misnamed` entry's OWN name as the container's target
    /// (as this function used to) would rename the WHOLE container to look
    /// like one entry's own name — exactly wrong.
    public static func planRepair(matchReport: MatchReport, filesCasePolicy: FileCasePolicy = .datafileCase) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .misnamed(let hashedFile, _) = romMatch.status else { continue }
                guard isLooseFile(hashedFile.file) else { continue }
                let destination = hashedFile.file.url
                    .deletingLastPathComponent()
                    .appendingPathComponent(mismatchFixName(declaredName: romMatch.rom.name, policy: filesCasePolicy))
                operations.append(.rename(from: hashedFile.file.url, to: destination))
            }
        }
        // `ROMMatcher.annotateMisnamedArchives` flags a misnamed archive by
        // stamping `misnamedArchiveForGameName` onto EVERY surplus entry
        // inside it (it has no archive-level row of its own to stamp) — so
        // an archive holding 5 surplus entries arrives here as 5
        // `SurplusFile`s that all name the SAME container. Planning one
        // rename per entry produced 5 identical renames of one file: the
        // first succeeded and the other 4 failed with `sourceMissing`,
        // since the container no longer existed under its old name.
        // jensyleo's own report (2026-09-10) of Fix "failing" is exactly
        // this shape. Deduplicated by container URL — renaming a File is
        // one operation on one File, however many ROMs happen to be inside
        // it.
        var plannedArchiveRenames: Set<URL> = []
        for surplusFile in matchReport.surplusFiles {
            guard let gameName = surplusFile.misnamedArchiveForGameName else { continue }
            let currentURL = surplusFile.file.file.url
            guard plannedArchiveRenames.insert(currentURL).inserted else { continue }
            let ext = currentURL.pathExtension
            let declaredName = ext.isEmpty ? gameName : "\(gameName).\(ext)"
            let destination = currentURL.deletingLastPathComponent().appendingPathComponent(mismatchFixName(declaredName: declaredName, policy: filesCasePolicy))
            operations.append(.rename(from: currentURL, to: destination))
        }
        // An archive that genuinely IS this game's own — every entry that
        // matters is matched by HASH to this exact game, `.correct` or
        // `.misnamed` alike — but is itself sitting under a wrong-CASE
        // filename ("AWBIOS.zip" instead of "awbios.zip"). jensyleo's own
        // real-world NEOGEO test (2026-09-10) plus his own follow-up
        // correction the same day: hash identity is what proves an entry
        // belongs to this game, regardless of whether its OWN name also
        // happens to be right yet — requiring every entry to already be
        // `.correct` first would force "Fix Misnamed ROMs Inside Their
        // Archives…" to run before "Fix Mismatched Files" ever could, an
        // ordering dependency jensyleo explicitly rejected ("el CRC32
        // identifica el archivo... aunque el nombre esté mal"). Safe to
        // include `.misnamed` here because the CONTAINER's target name is
        // always derived from `gameResult.game.name` (the DAT's own
        // declared game), never from the entry's own — still wrong — name;
        // see `planRepairSkipsEntryLevelMismatchesInsideArchives` for the
        // one thing this deliberately never does. Deduplicated by container
        // URL exactly like the surplus-archive loop above, since several
        // entries of the same game share one container.
        var plannedOwnArchiveRenames: Set<URL> = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _):
                    hashedFile = file
                case .missing, .foundElsewhere, .hashMismatch, .nodump:
                    hashedFile = nil
                }
                guard let hashedFile, isArchivedEntry(hashedFile.file) else { continue }
                let currentURL = hashedFile.file.url
                guard plannedArchiveRenames.contains(currentURL) == false,
                      plannedOwnArchiveRenames.insert(currentURL).inserted
                else { continue }
                let ext = currentURL.pathExtension
                let declaredName = ext.isEmpty ? gameResult.game.name : "\(gameResult.game.name).\(ext)"
                let expectedName = mismatchFixName(declaredName: declaredName, policy: filesCasePolicy)
                guard currentURL.lastPathComponent != expectedName else { continue }
                let destination = currentURL.deletingLastPathComponent().appendingPathComponent(expectedName)
                operations.append(.rename(from: currentURL, to: destination))
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
    public static func planRenameRomsInArchive(matchReport: MatchReport, romsCasePolicy: FileCasePolicy = .datafileCase) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .misnamed(let hashedFile, _) = romMatch.status else { continue }
                guard isZipEntry(hashedFile.file) else { continue }
                let currentEntryName = hashedFile.file.name
                let expectedEntryName = mismatchFixName(declaredName: romMatch.rom.name, policy: romsCasePolicy)
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
                if isZipEntry(hashedFile.file) {
                    operations.append(.extractZipEntry(archive: hashedFile.file.url, entryName: hashedFile.file.name, to: target))
                } else if isUnrewritableArchiveEntry(hashedFile.file) {
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
                guard !isUnrewritableArchiveEntry(hashedFile.file) else { return nil }
                let innerEntryName = isZipEntry(hashedFile.file) ? hashedFile.file.name : nil
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
                let file = surplus.file.file
                let url = file.url
                // Container or contents? Decided by `isArchivedEntry` (see
                // its own doc comment), never by the path extension: a junk
                // `.zip` that is ITSELF the unrecognized file also has a
                // `.zip` extension, and the old `isZipPath` test sent it
                // down the entry-removal branch — planning
                // `.removeEntryFromZip(archive: junk.zip, entryName:
                // "junk.zip")`, which can only ever fail, instead of
                // deleting the junk archive it was asked to remove.
                guard isArchivedEntry(file) else { return .delete(url) }
                // A genuine entry inside a container: remove just that
                // entry, never the container. Only `.zip` supports it
                // (`SevenZipRunner` exposes no entry removal), so a
                // `.7z`-held surplus entry is skipped rather than
                // approximated by deleting its whole archive.
                guard isZipPath(url) else { return nil }
                return .removeEntryFromZip(archive: url, entryName: file.name)
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
            if isZipEntry(hashedFile.file) {
                return .zip(hashedFile.file.url)
            } else if isLooseFile(hashedFile.file) {
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
                if isUnrewritableArchiveEntry(hashedFile.file) { continue }
                return hashedFile
            }
        }
        return nil
    }

    private static func archiveEntrySource(forDonor donor: HashedFile, outputEntryName: String) -> ArchiveEntrySource {
        let innerEntryName = isZipEntry(donor.file) ? donor.file.name : nil
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
                        if isZipEntry(donor.file) {
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
                guard !isUnrewritableArchiveEntry(donor.file) else { continue }
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
                    if isZipEntry(donor.file) {
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
                guard !isUnrewritableArchiveEntry(donor.file) else { continue }
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
                    if isZipEntry(donor.file) {
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
                    guard let hashedFile, isZipEntry(hashedFile.file) else { continue }
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
        // See `capitalizedPreservingExtension`'s own doc comment — bare
        // `current.capitalized` would title-case a ROM entry's own
        // extension too ("game.bin" → "Game.Bin"), same bug
        // `mismatchFixName` already guards against for a genuine mismatch.
        case .capitalized: target = capitalizedPreservingExtension(current)
        }
        return target == current ? nil : target
    }

    /// A container whose own FILENAME is already correct apart from its
    /// case — the only thing "Sets case" is ever allowed to re-style.
    ///
    /// jensyleo's own report (2026-09-10): "no confundas renombrar el
    /// contenido del .zip/.7z con renombrar el nombre del archivo". This
    /// function is where that confusion was load-bearing. `RomMatchStatus`
    /// is decided PURELY by the ENTRY name (`ROMMatcher`: `hashedFile
    /// .file.name == rom.name ? .correct : .misnamed`) — the container's
    /// own filename is never consulted to produce it, because the matcher
    /// matches by HASH, not by filename. So a `.correct` rom proves only
    /// that one entry INSIDE the archive is named right; it says nothing
    /// whatsoever about the archive's own name.
    ///
    /// `correctOnlyArchiveAnchor` (this function's predecessor) leaned on
    /// `.correct` as if it meant "this File's name is right", so an
    /// archive named `unknown123.zip` full of perfectly-named entries got
    /// uppercased to `UNKNOWN123.zip` — re-casing a genuinely WRONG File
    /// name, which is exactly what excluding `.misnamed` was written to
    /// prevent, just measured on the wrong name. The container's name has
    /// to be compared against the DAT's own game name directly, which is
    /// what happens here: same name apart from case means a real case
    /// policy job; different beyond case means a genuine File-level
    /// mismatch, which is "Fix Mismatched Files"' job and never this one's.
    private static func caseOnlyMismatchedArchiveAnchor(for gameResult: GameMatchResult) -> URL? {
        let declaredBasename = safePathComponent(gameResult.game.name).lowercased()
        for match in gameResult.matches {
            // `isArchivedEntry` first: `file.file.url` is only a CONTAINER
            // path when the rom is genuinely an entry inside one. A loose
            // `.zip` that is itself a rom passes `isArchivePath` too, and
            // re-casing it is a File-level rename of that rom, not a set
            // rename — this action has no business claiming it as a set.
            guard case .correct(let file, _) = match.status,
                  isArchivedEntry(file.file), isArchivePath(file.file.url)
            else { continue }
            let currentBasename = file.file.url.deletingPathExtension().lastPathComponent
            guard currentBasename.lowercased() == declaredBasename else { continue }
            return file.file.url
        }
        return nil
    }

    /// Renames a game's own archive FILENAME (the container itself — never
    /// anything inside it) to match `policy` — Fase 2 Step 9's "Sets case".
    /// The `.zip`/`.7z` container is renamed as a plain filesystem rename,
    /// which needs no entry rewriting and so works identically for both;
    /// the entries inside are untouched by this function entirely (that's
    /// `planApplyRomsCasePolicy` below, a genuinely different operation).
    ///
    /// Only ever applies to a container whose own filename already matches
    /// the DAT's declared game name apart from case — see
    /// `caseOnlyMismatchedArchiveAnchor`'s own doc comment for why that has
    /// to be checked against the container's name directly rather than
    /// inferred from a rom's `.correct`/`.misnamed` status. A loose-file
    /// collection has no single "set" filename for this to mean anything
    /// about, and is skipped. The extension itself is never touched, only
    /// the basename.
    public static func planApplySetsCasePolicy(matchReport: MatchReport, policy: FileCasePolicy) -> [RebuildOperation] {
        guard policy != .dontTouch else { return [] }
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            guard let currentURL = caseOnlyMismatchedArchiveAnchor(for: gameResult) else { continue }
            let currentBasename = currentURL.deletingPathExtension().lastPathComponent
            guard let targetBasename = caseTransformTarget(current: currentBasename, datafileDeclaredName: gameResult.game.name, policy: policy) else { continue }
            let targetURL = currentURL.deletingLastPathComponent()
                .appendingPathComponent(targetBasename)
                .appendingPathExtension(currentURL.pathExtension)
            operations.append(.rename(from: currentURL, to: targetURL))
        }
        return operations
    }

    /// Renames every matched rom's own ENTRY NAME inside its `.zip` — the
    /// content of the archive, never the archive's own filename (that's
    /// `planApplySetsCasePolicy` above) — to match `policy`. Fase 2 Step
    /// 9's "Roms case". Same add-then-remove shape as
    /// `planRenameRomsInArchive`, just driven by a case transform instead
    /// of a DAT-name mismatch.
    ///
    /// Only a genuinely `.correct` rom qualifies, and unlike the set-level
    /// half above, `.correct` IS the right test here: it's decided purely
    /// by `hashedFile.file.name == rom.name` (`ROMMatcher`), which is
    /// exactly this operation's own subject — the entry's name. A
    /// `.misnamed` one is "Fix Misnamed ROMs Inside Their Archives…"'s
    /// job, never this action's, since re-casing a wrong entry name just
    /// produces a differently-cased wrong name.
    ///
    /// A `.7z`-sourced rom is skipped (rewriting an entry needs archive
    /// support that only exists for `.zip`) — note this is a genuinely
    /// different constraint from the set-level half, which renames the
    /// container as a plain filesystem rename and so handles `.7z` fine. A
    /// loose rom is skipped too: it has no containing archive, so its case
    /// is a File-level concern, not an entry-level one.
    ///
    /// KNOWN GAP (2026-09-10, unfixed by design decision pending):
    /// a loose rom therefore falls through BOTH halves — `planApplySetsCasePolicy`
    /// skips it for having no container, and this skips it for having no
    /// archive — so no action re-cases a loose file at all.
    public static func planApplyRomsCasePolicy(matchReport: MatchReport, policy: FileCasePolicy) -> [RebuildOperation] {
        guard policy != .dontTouch else { return [] }
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .correct(let hashedFile, _) = romMatch.status, isZipEntry(hashedFile.file) else { continue }
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
            // `entry.path` is the CONTAINER and `entry.name` the entry
            // inside it, so the same container-vs-contents test applies
            // here as everywhere else (see `isArchivedEntry`): equal names
            // would mean the flagged item is the file itself, and every
            // operation below would then be addressing a nonexistent entry
            // named after its own archive.
            guard let path = entry.path, isZipPath(path), path.lastPathComponent != entry.name else { continue }
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
