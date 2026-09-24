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
                // Real bug found live (2026-09-14, via the test suite —
                // "planRepair and planApplySetsCasePolicy never target the
                // same archive"): comparing only against `expectedName`
                // (already STYLED per `filesCasePolicy`) meant an archive
                // whose name is already EXACTLY what the DAT declares (no
                // real mismatch at all) still got flagged here whenever
                // `filesCasePolicy` wasn't `.datafileCase` — purely because
                // it wasn't yet re-styled, which is `planApplySetsCasePolicy`'s
                // own, separate job. Skipping whenever the current name
                // already matches the DAT's own plain `declaredName` too
                // (not just the styled `expectedName`) restores the
                // "these two never target the same archive" guarantee
                // `LibraryViewModel.fix()` relies on to run both in one
                // pass safely — a genuine wrong-case mismatch (e.g.
                // "AWBIOS.zip" vs. a declared "awbios") still matches
                // neither name, so it's still caught and renamed exactly
                // as the NEOGEO fix above intended.
                guard currentURL.lastPathComponent != declaredName, currentURL.lastPathComponent != expectedName else { continue }
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
                // Real bug found live by jensyleo (2026-09-23): `.name`
                // alone (just the last path component) is wrong for an
                // entry nested inside a real subfolder in the zip (e.g. a
                // "__MACOSX/._foo" AppleDouble sidecar) — see
                // `ScannedFile.effectiveEntryPath`'s own doc comment.
                let currentEntryName = hashedFile.file.effectiveEntryPath
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
                    operations.append(.extractZipEntry(archive: hashedFile.file.url, entryName: hashedFile.file.effectiveEntryPath, to: target))
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
                let innerEntryName = isZipEntry(hashedFile.file) ? hashedFile.file.effectiveEntryPath : nil
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
                // `effectiveEntryPath`, not plain `.name` — real bug found
                // live by jensyleo (2026-09-23): a junk entry nested inside
                // a real "__MACOSX/" subfolder (an AppleDouble sidecar
                // macOS itself writes into a zip made from a folder that
                // once lived on a non-Mac filesystem) has a `.name` that's
                // just its own last path component ("._foo.bin"), never the
                // REAL entry path ("__MACOSX/._foo.bin") ZIPFoundation's own
                // lookup actually needs — every one of these failed with
                // "Source file does not exist", 0 removed. See
                // `ScannedFile.effectiveEntryPath`'s own doc comment.
                return .removeEntryFromZip(archive: url, entryName: file.effectiveEntryPath)
            }
    }

    /// Deletes a redundant, LOOSE (non-archive) duplicate copy of content
    /// the DAT genuinely recognizes — jensyleo's own request (2026-09-13),
    /// deliberately split from `planRemoveUselessFiles` above rather than
    /// folded into it: that function only ever targets content the DAT
    /// recognizes NOTHING about at all (`requiredByGameDescription == nil`);
    /// this one is its exact complement, targeting a `SurplusFile` the DAT
    /// DOES recognize (`requiredByGameDescription != nil` — shown in the UI
    /// as "Not needed here (required by X)") but that isn't needed at this
    /// particular location, because some OTHER game already legitimately
    /// claims an equivalent copy elsewhere. Deleting it loses nothing the
    /// collection doesn't already have somewhere else.
    ///
    /// Loose files only, mirroring the `.zip`/loose split
    /// `planReplaceCorruptedRoms` already uses — the archive-entry half of
    /// this exact same duplicate is `planRemoveRedundantRoms`, below.
    ///
    /// Filters on `requiredByGameConfirmedRedundant`, NOT merely
    /// `requiredByGameDescription != nil` — jensyleo's own real incident
    /// (2026-09-19): `requiredByGameDescription` only ever means "the DAT
    /// declares this content belongs to game X," regardless of whether X
    /// actually has a good copy of it anywhere real. A stray `naomi.zip`
    /// full of genuine NAOMI BIOS content got deleted this way, as "safe,"
    /// right as NAOMI BIOS's own real archive was also removed — leaving
    /// NAOMI BIOS with NO real copy left outside the Maintenance folder,
    /// the opposite of what "redundant" is supposed to guarantee.
    /// `requiredByGameConfirmedRedundant` additionally requires that the
    /// owning game already has this exact content satisfied elsewhere in
    /// the real scan (see `SurplusFile.requiredByGameConfirmedRedundant`'s
    /// own doc comment) — `requiredByGameDescription` itself is untouched
    /// and still drives the informational "Not needed here (required by
    /// X)" text and Maintenance-donor lookups.
    ///
    /// Filters on `requiredByGameOwnerSatisfiedElsewhere`, NOT the broader
    /// `requiredByGameConfirmedRedundant` — second round of the same
    /// incident, same day (2026-09-19): that broader field ALSO goes true
    /// merely because this loose file is one of 2+ physically identical,
    /// UNCLAIMED copies (`duplicateAmongSurplusIndices`), even when the
    /// owning game has NO real copy anywhere. That signal is only genuinely
    /// safe for a whole, directly-usable unit (a duplicated whole archive —
    /// see `fullyRedundantArchiveContainers`), never a loose rom fragment: a
    /// loose `epr-21576g.ic27` duplicated via a Finder-style "epr-21576g
    /// 2.ic27" copy, with "NAOMI BIOS" having no real archive anywhere,
    /// must never be offered here — deleting either copy helps nobody and
    /// risks the exact same near-loss pattern this whole field exists to
    /// prevent. See `SurplusFile.requiredByGameOwnerSatisfiedElsewhere`'s
    /// own doc comment.
    public static func planRemoveRedundantFiles(matchReport: MatchReport) -> [RebuildOperation] {
        matchReport.surplusFiles
            .filter { $0.requiredByGameOwnerSatisfiedElsewhere }
            .compactMap { surplus in
                let file = surplus.file.file
                guard !isArchivedEntry(file) else { return nil }
                return .delete(file.url)
            }
    }

    /// Removes a redundant ENTRY inside a `.zip` — the archive-entry
    /// counterpart to `planRemoveRedundantFiles` just above (see its own
    /// doc comment for the shared "recognized, but not needed HERE"
    /// definition both of these act on). Never removes a whole archive,
    /// same reasoning `planRemoveUselessFiles` already documents: a
    /// redundant rom sitting next to other, genuinely-needed roms in the
    /// same archive must lose only its own entry.
    ///
    /// `fullyRedundantContainers` — jensyleo's own request (2026-09-17,
    /// generalizing `planRemoveRedundantWholeArchives`'s own `.7z`-only
    /// mechanism below to `.zip` too): a `.zip` whose ENTIRE content is
    /// redundant (e.g. `CPS2/naomi.zip` holding exactly one rom that's
    /// itself a redundant duplicate, nothing else) is excluded here —
    /// removing just its one entry would leave a pointless, empty zip
    /// behind. That whole-file case belongs to "Remove Redundant
    /// File(s)…" (`planRemoveRedundantWholeArchives`) instead, matching
    /// what already happened by construction for `.7z` (never eligible
    /// here at all, via `isZipPath`). A `.zip` with only SOME redundant
    /// entries (other, still-needed roms sharing the same archive) keeps
    /// the original per-entry behavior unchanged. Callers not yet passing
    /// this (existing tests/call sites) get the exact old behavior via the
    /// default empty set.
    /// Same `requiredByGameOwnerSatisfiedElsewhere` (not the broader
    /// `requiredByGameConfirmedRedundant`) reasoning as
    /// `planRemoveRedundantFiles` above — a single entry inside an
    /// otherwise-mixed archive is just as much a "fragment" as a loose
    /// file: removing it because it merely duplicates another unclaimed
    /// copy, while its declared owner still has no real content anywhere,
    /// helps nobody and carries the same risk. The genuinely-safe
    /// whole-duplicated-archive case is `fullyRedundantArchiveContainers`
    /// below, which still accepts the broader field.
    public static func planRemoveRedundantRoms(matchReport: MatchReport, fullyRedundantContainers: Set<URL> = []) -> [RebuildOperation] {
        matchReport.surplusFiles
            .filter { $0.requiredByGameOwnerSatisfiedElsewhere }
            .compactMap { surplus in
                let file = surplus.file.file
                guard isArchivedEntry(file), isZipPath(file.url), !fullyRedundantContainers.contains(file.url) else { return nil }
                return .removeEntryFromZip(archive: file.url, entryName: file.effectiveEntryPath)
            }
    }

    /// Deletes a WHOLE archive (`.7z` or `.zip`) that's a redundant
    /// duplicate, when EVERY entry inside it is independently redundant —
    /// jensyleo's own
    /// follow-up (2026-09-16), after "Remove Redundant Files…" correctly
    /// deleted 4 duplicate CHDs but left a redundant `nss.7z` stuck
    /// yellow: "pensaría que debería eliminarse en Redundant Files si y
    /// solo si el contenido de las roms son exactamente iguales... aunque
    /// tengan extensión diferente, si contienen los mismos archivos,
    /// permita la eliminación." A real BIOS set is usually several roms,
    /// not one — `nss.7z` turned out to hold all 6 of `nss.zip`'s own
    /// roms, re-packed as `.7z`, every single one already independently
    /// flagged `requiredByGameDescription` (content-identical, claimed
    /// elsewhere) — an entry-COUNT check of exactly 1 (this function's
    /// first cut) wrongly excluded it. The right question is never "how
    /// many entries does this container have," only "does it hold
    /// anything genuinely needed that isn't ALSO a redundant duplicate
    /// somewhere else" — checked by comparing the archive's real, total
    /// entry count against how many of ITS OWN entries this same scan
    /// already flagged redundant; equal means nothing legitimate is left
    /// to lose. For `.7z`, `planRemoveRedundantFiles`/`.planRemoveRedundantRoms`
    /// above always skip a `.7z`-held entry entirely (no `SevenZipRunner`
    /// entry add/remove support at all) — this is the ONLY way a `.7z`'s
    /// redundant content can ever be removed. For `.zip`,
    /// `planRemoveRedundantRoms` CAN remove just one entry, so it instead
    /// excludes whatever this function already claims (via
    /// `fullyRedundantContainers`, the exact same comparison below), so a
    /// fully-redundant `.zip` is offered as a whole-file delete here
    /// instead of a pointless "remove the only entry, leave an empty zip"
    /// — same reasoning `planRemoveUselessFiles` already applies to a
    /// wholly-junk archive.
    ///
    /// `entryCounts` is supplied by the caller (a real archive listing,
    /// genuine disk I/O `RebuildPlanner` itself never performs — see this
    /// file's own header) keyed by container URL; a container missing from
    /// this map is left untouched rather than guessed at.
    public static func planRemoveRedundantWholeArchives(matchReport: MatchReport, entryCounts: [URL: Int]) -> [RebuildOperation] {
        fullyRedundantArchiveContainers(matchReport: matchReport, entryCounts: entryCounts).map { .delete($0) }
    }

    /// The exact same "every entry in this container is independently
    /// redundant" comparison `planRemoveRedundantWholeArchives` uses to
    /// decide what to delete — factored out so `planRemoveRedundantRoms`
    /// can exclude these same containers from its own, finer-grained
    /// per-entry removal (see that function's own `fullyRedundantContainers`
    /// doc comment) without the two ever computing this independently and
    /// risking disagreement.
    ///
    /// Generalized from `.7z`-only to any archived entry (2026-09-17,
    /// jensyleo's own explicit request — "llévalo como regla general, es
    /// obvio" — after noticing `CPS2/naomi.zip`, holding exactly one
    /// redundant rom and nothing else, only ever offered "Remove Redundant
    /// ROM(s)…" (leaving an empty, pointless zip behind) instead of
    /// deleting the whole file).
    /// Deliberately still filters on the BROADER `requiredByGameConfirmedRedundant`
    /// (A or B), not the narrower `requiredByGameOwnerSatisfiedElsewhere` —
    /// unlike a loose fragment (see `planRemoveRedundantFiles`'s own doc
    /// comment), a whole duplicated archive whose EVERY entry is redundant
    /// is a complete, directly-usable unit either way: deleting the extra
    /// copy of `naomi.zip` genuinely loses nothing, since the surviving copy
    /// is already a working set.
    public static func fullyRedundantArchiveContainers(matchReport: MatchReport, entryCounts: [URL: Int]) -> Set<URL> {
        let redundantEntries = matchReport.surplusFiles
            .filter { $0.requiredByGameConfirmedRedundant }
            .map(\.file.file)
            .filter { isArchivedEntry($0) }
        let redundantCountsByContainer = Dictionary(grouping: redundantEntries, by: \.url).mapValues(\.count)
        return Set(redundantCountsByContainer.compactMap { container, redundantCount in
            guard let totalCount = entryCounts[container], totalCount == redundantCount else { return nil }
            return container
        })
    }

    /// The CHD/disk counterpart to `planRemoveRedundantFiles` above —
    /// jensyleo's own report (2026-09-16), testing "Remove Redundant
    /// Files…" for the first time on a real MAME collection: several rows
    /// clearly read "Duplicated archive, not needed here (required by X)"
    /// (e.g. a second, leftover `kinst.chd` copy) yet the action reported
    /// nothing to remove. Root cause: disk auditing (`DiskAuditor.audit`)
    /// is a structurally separate pipeline from `ROMMatcher`/`MatchReport`
    /// — a `.chd` is never one of a game's `DATRom` entries, so it was
    /// never a `SurplusFile` for `planRemoveRedundantFiles` to see at all.
    /// `DiskAuditor` already computes the exact same "recognized
    /// elsewhere, but not needed HERE" signal for a leftover duplicate CHD
    /// (`.incorrect` + `isDisk` + `requiredByGameDescription` set — see
    /// its own doc comment on the loop building these), so this simply
    /// reads that instead of a `SurplusFile`. A CHD is always a loose file
    /// on disk, never a zip entry, so — unlike the rom/entry split above —
    /// there is no separate "redundant disk ENTRY" counterpart needed.
    public static func planRemoveRedundantDisks(auditEntries: [AuditEntry]) -> [RebuildOperation] {
        auditEntries
            .filter { $0.isDisk && $0.status == .incorrect && $0.requiredByGameConfirmedRedundant }
            .compactMap { entry in entry.path.map { .delete($0) } }
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
        let innerEntryName = isZipEntry(donor.file) ? donor.file.effectiveEntryPath : nil
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

    /// Groups `donorFiles` by size once, so every one of `donorMatches`'s
    /// own callers below can narrow to same-size candidates first instead
    /// of scanning the WHOLE Maintenance folder per rom. Found live via a
    /// background performance audit (2026-09-17): with no index at all,
    /// each of the four functions below did a full linear scan of
    /// `donorFiles` for every `.missing`/`.hashMismatch` rom in the entire
    /// scanned collection — effectively O(roms × donor files), and paid
    /// TWICE per user action (once for the preview-count read, once for
    /// the real plan) since neither call shared a cache. `donorMatches`
    /// itself always requires an exact size match first, so grouping by
    /// size turns this into a cheap dictionary lookup plus a scan of only
    /// the (typically tiny) same-size bucket.
    private static func donorsBySize(_ donorFiles: [HashedFile]) -> [Int64: [HashedFile]] {
        Dictionary(grouping: donorFiles, by: \.file.size)
    }

    private static func findDonor(for rom: DATRom, in donorsBySize: [Int64: [HashedFile]]) -> HashedFile? {
        (donorsBySize[rom.size] ?? []).first { donorMatches($0, rom: rom) }
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
    /// Covers `.missing` roms AND `.foundElsewhere` ones — a `.hashMismatch`
    /// rom already occupies its own correct slot under content that's
    /// simply wrong, which needs an overwrite (remove the bad entry, then
    /// add the good one) instead; see `planReplaceCorruptedRoms` below,
    /// which does exactly that, sharing this same donor mechanism.
    ///
    /// `.foundElsewhere` included since jensyleo's own live report
    /// (2026-09-21): a NAOMI BIOS rom shared with an unrelated game
    /// (`315-6146.bin`, also declared by `mvsc2`) showed "Available in
    /// another game (mvsc2.zip)" forever — genuinely absent from naomi's
    /// OWN archive (never `.correct`/`.misnamed` there), yet
    /// `planRepairFromMaintenanceFolder`'s old `.missing`-only guard
    /// skipped it outright regardless of whether a clean donor sat in
    /// Maintenance, since `.foundElsewhere` is a distinct status from
    /// `.missing`. `.foundElsewhere` never claims/consumes the file it
    /// points at (see that case's own doc comment on `RomMatchStatus`), so
    /// it means exactly the same thing `.missing` does for THIS game's own
    /// archive: the content isn't there. Still only ever reads from
    /// `donorFiles` (Maintenance/configured folders) — never from the
    /// `.foundElsewhere` hashed file itself, which stays exactly the
    /// informational pointer it always was. (2026-09-21: briefly reverted
    /// this same day over a suspected overlap with `planConvertToNonMerged`
    /// ("Make Self-Contained…"/Fase 2 Step 4) — jensyleo's own instruction:
    /// that feature was already set aside earlier in this project and is
    /// not the path to use here, so this stays the one real fix.)
    public static func planRepairFromMaintenanceFolder(matchReport: MatchReport, donorFiles: [HashedFile]) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        let donorsBySize = donorsBySize(donorFiles)
        for gameResult in matchReport.games {
            guard let anchor = existingAnchor(for: gameResult) else { continue }
            for romMatch in gameResult.matches {
                switch romMatch.status {
                case .missing, .foundElsewhere: break
                default: continue
                }
                guard let donor = findDonor(for: romMatch.rom, in: donorsBySize) else { continue }
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

    /// Identifies exactly which `.missing` roms `planRepairFromMaintenanceFolder`
    /// above would actually repair, without planning or touching anything —
    /// `MaintenanceDonorDetector`'s own read (ROMForgeCore, purely for
    /// display) needs this same "would Find ROMs really fix this" answer,
    /// and computing it by literally sharing this function's own anchor/
    /// donor-match guards (rather than a second, hand-written copy of
    /// them) is what guarantees the two can never quietly disagree.
    ///
    /// jensyleo's own report (2026-09-14): a game with NO anchor at all
    /// (its own archive/file doesn't exist on disk yet — e.g. deleted
    /// entirely, not merely missing a few roms) still showed every one of
    /// its roms as "donor available" (yellow) purely because the
    /// Maintenance folder happened to have a matching donor for each —
    /// misleading, since `planRepairFromMaintenanceFolder` itself can
    /// never actually write anywhere without a real anchor to attach to,
    /// so "Find ROMs…" would silently do nothing for it. Returned as a
    /// `Set` of `"<game>\u{0}<rom name>"` keys — a plain tuple isn't
    /// `Hashable` — rather than a new public struct, since this exists
    /// purely for one internal cross-check, not a stable public API.
    public static func romsRepairableFromMaintenanceFolder(matchReport: MatchReport, donorFiles: [HashedFile]) -> Set<String> {
        var repairable: Set<String> = []
        let donorsBySize = donorsBySize(donorFiles)
        for gameResult in matchReport.games {
            guard existingAnchor(for: gameResult) != nil else { continue }
            for romMatch in gameResult.matches {
                // See `planRepairFromMaintenanceFolder`'s own doc comment
                // on why `.foundElsewhere` is included alongside `.missing`.
                switch romMatch.status {
                case .missing, .foundElsewhere: break
                default: continue
                }
                guard let donor = findDonor(for: romMatch.rom, in: donorsBySize) else { continue }
                guard !isUnrewritableArchiveEntry(donor.file) else { continue }
                repairable.insert("\(gameResult.game.name)\u{0}\(romMatch.rom.name)")
            }
        }
        return repairable
    }

    /// Replaces a `.hashMismatch` rom's own bad content with a
    /// verified-correct copy found in the exact same external donor
    /// source `planRepairFromMaintenanceFolder` already searches (the
    /// Maintenance folder, optionally plus the system's own configured
    /// ROM folders — see that function's own doc comment) — jensyleo's
    /// own request (2026-09-13), after asking Claude to help track down a
    /// correct dump online and being told that's out of bounds: "crea una
    /// lógica... que si detecta la ROM correcta en alguna parte la
    /// reemplace." "Replace Corrupted ROMs…" in the toolbar.
    ///
    /// The one real difference from that function: a `.missing` slot has
    /// nothing to remove, so a plain `.addEntryToZip`/`.copy` is enough.
    /// A `.hashMismatch` slot already has a REAL file sitting there under
    /// the exact name this rom needs — `donorFiles`' own entry must land
    /// under that identical name, so the bad one has to be removed FIRST
    /// (an add under an already-occupied name is refused, same as every
    /// other "never overwrite" operation in this app). Each rom therefore
    /// plans as a PAIR — remove-then-add (or delete-then-copy/extract for
    /// a loose file) — mirroring `planRenameRomsInArchive`'s own paired
    /// shape (add-then-remove there, reversed here because THAT rename
    /// targets a NEW, not-yet-occupied name while THIS one targets the
    /// exact name already in use). Callers must execute each pair
    /// together, same as `LibraryViewModel.renameRomsInArchive`'s own
    /// `stride(by: 2)` loop: if the remove half succeeds but the add half
    /// fails (e.g. a donor read error), the rom becomes `.missing` rather
    /// than staying `.hashMismatch` or losing anything — recoverable by a
    /// later "Find ROMs"/"Replace Corrupted ROMs…" pass, never silently
    /// corrupting.
    ///
    /// A `.hashMismatch` rom whose bad content lives inside an
    /// unsupported `.7z` is skipped — no 7z-entry rewrite support, same
    /// "not yet" every other planner function here already accepts.
    ///
    /// A `.hashMismatch` rom living inside a `.zip` IS supported —
    /// real crash found live by jensyleo (2026-09-14), first time this
    /// action ever actually ran against a real corrupted zip entry: the
    /// remove half used to call `ZIPFoundation.Archive.remove(_:)`
    /// directly, which rewrites the archive in place using unsigned
    /// arithmetic derived from the REMOVED entry's own (here: CORRUPTED)
    /// local-header size — an inconsistent size there can underflow that
    /// subtraction, an instant uncatchable `SIGTRAP`. Fixed properly at
    /// `RebuildExecutor.removeEntryFromZip`'s own level (see its doc
    /// comment): it now rebuilds the archive from scratch instead of
    /// patching it in place, so this planner function needs no special
    /// case for "the bad entry lives inside a zip" — the `.removeEntryFromZip`
    /// operation it plans below is safe regardless.
    public static func planReplaceCorruptedRoms(matchReport: MatchReport, donorFiles: [HashedFile]) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        let donorsBySize = donorsBySize(donorFiles)
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .hashMismatch(let badFile) = romMatch.status else { continue }
                guard !isUnrewritableArchiveEntry(badFile.file) else { continue }
                guard let donor = findDonor(for: romMatch.rom, in: donorsBySize) else { continue }
                guard !isUnrewritableArchiveEntry(donor.file) else { continue }
                let outputEntryName = safePathComponent(romMatch.rom.name)
                if isZipEntry(badFile.file) {
                    let zipURL = badFile.file.url
                    operations.append(.removeEntryFromZip(archive: zipURL, entryName: badFile.file.effectiveEntryPath))
                    operations.append(.addEntryToZip(
                        targetArchive: zipURL,
                        entryName: outputEntryName,
                        source: archiveEntrySource(forDonor: donor, outputEntryName: outputEntryName)
                    ))
                } else if isLooseFile(badFile.file) {
                    let destination = badFile.file.url
                    operations.append(.delete(destination))
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

    /// Identifies exactly which `.hashMismatch` roms `planReplaceCorruptedRoms`
    /// above would actually replace, without planning or touching anything
    /// — same "share the real guards, don't hand-write a second copy that
    /// could quietly disagree" reasoning as `romsRepairableFromMaintenanceFolder`
    /// just above, for `MaintenanceDonorDetector`'s own display-only read.
    /// No anchor check needed here (unlike that function): a `.hashMismatch`
    /// rom's own archive/file already exists on disk by definition — the
    /// content is merely wrong, not absent — so there's nothing analogous
    /// to "the game was fully deleted" that could make this misleading.
    public static func romsReplaceableFromMaintenanceFolder(matchReport: MatchReport, donorFiles: [HashedFile]) -> Set<String> {
        var replaceable: Set<String> = []
        let donorsBySize = donorsBySize(donorFiles)
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                guard case .hashMismatch(let badFile) = romMatch.status else { continue }
                guard !isUnrewritableArchiveEntry(badFile.file) else { continue }
                guard let donor = findDonor(for: romMatch.rom, in: donorsBySize) else { continue }
                guard !isUnrewritableArchiveEntry(donor.file) else { continue }
                replaceable.insert("\(gameResult.game.name)\u{0}\(romMatch.rom.name)")
            }
        }
        return replaceable
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
                    operations.append(.removeEntryFromZip(archive: hashedFile.file.url, entryName: hashedFile.file.effectiveEntryPath))
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
                // `effectiveEntryPath` for the actual archive read/remove
                // (see `ScannedFile`'s own doc comment) — `currentEntryName`
                // above stays the plain name on purpose, since that's what
                // `caseTransformTarget` needs to compare case against.
                let currentEntryPath = hashedFile.file.effectiveEntryPath
                operations.append(.addEntryToZip(
                    targetArchive: zipURL,
                    entryName: targetEntryName,
                    source: ArchiveEntrySource(source: zipURL, entryName: targetEntryName, sourceArchiveEntryName: currentEntryPath)
                ))
                operations.append(.removeEntryFromZip(archive: zipURL, entryName: currentEntryPath))
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

    /// Creates a zero-byte placeholder for every genuinely absent `nodump`
    /// rom — "Create dummy roms for nodump entries".
    ///
    /// Real bug found live by Claude (2026-09-13), testing this against a
    /// real MAME set for the first time: this used to filter
    /// `gameResult.matches` for `.missing` + `rom.status == .nodump`, but
    /// `ROMMatcher.match` deliberately never assigns `.missing` to an
    /// unclaimed `nodump` rom in the first place — its own doc comment
    /// there says exactly why ("there's still nothing to report... same
    /// as before"): a `nodump` rom nobody's disk can ever satisfy isn't
    /// treated as a real absence, so it's silently dropped from
    /// `romMatches` entirely rather than ever reaching `.missing`. That
    /// made this whole planner unreachable in practice — it could never
    /// find anything to act on, no matter how many undumped roms a real
    /// scan had.
    ///
    /// Fixed by going straight to `gameResult.game.roms` (the DAT's own
    /// full declared list, independent of whatever `ROMMatcher` chose to
    /// report) and checking which `nodump` roms have NO entry at all in
    /// `gameResult.matches` — that absence is exactly what "genuinely
    /// nowhere on disk, nothing claims it" means; a `nodump` rom that DOES
    /// have a same-named file somewhere shows up as `.nodump(HashedFile)`
    /// in `matches` instead (see `RomMatchStatus`'s own doc comment) and
    /// is correctly left untouched here — this planner never overwrites
    /// whatever a user already put there. Uses the same `existingAnchor`
    /// borrowed-location logic as cross-set repair: a game with nowhere
    /// real to put the placeholder (every rom missing, or its only present
    /// roms sit inside an unsupported `.7z`) is skipped entirely rather
    /// than inventing a destination folder from scratch.
    public static func planCreateDummyRoms(matchReport: MatchReport) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        for gameResult in matchReport.games {
            guard let anchor = existingAnchor(for: gameResult) else { continue }
            let claimedRomNames = Set(gameResult.matches.map(\.rom.name))
            for rom in gameResult.game.roms {
                guard rom.status == .nodump, !claimedRomNames.contains(rom.name) else { continue }
                let outputEntryName = safePathComponent(rom.name)
                switch anchor {
                case .zip(let targetArchive):
                    operations.append(.createDummyZipEntry(targetArchive: targetArchive, entryName: outputEntryName, size: rom.size))
                case .looseFolder(let folder):
                    operations.append(.createDummyFile(at: folder.appendingPathComponent(outputEntryName), size: rom.size))
                }
            }
        }
        return operations
    }

    /// Strips the trailing comment from every distinct `.zip` that holds at
    /// least one correctly (or misnamed-but-correctly-hashed) matched rom —
    /// "Remove zip comments". One operation per unique archive, regardless
    /// of how many of its entries matched — `clearZipComment` already
    /// touches the whole file's own tail, never a single entry, so
    /// repeating it per-rom would just plan the same truncation N times.
    /// Every distinct matched `.zip` "Remove Zip Comments…" could ever
    /// possibly touch — pure candidate identification, no disk I/O (per
    /// this whole file's own rule) and no opinion at all about whether any
    /// of them actually HAS a comment to remove. The caller (`LibraryViewModel`,
    /// which already does real disk reads elsewhere, e.g. `donorFiles`)
    /// reads each candidate's own comment and passes back only the ones
    /// that genuinely have one, via `planRemoveZipComments(archivesWithComments:)`
    /// below.
    public static func matchedZipArchiveURLs(matchReport: MatchReport) -> Set<URL> {
        var archives = Set<URL>()
        for gameResult in matchReport.games {
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _): hashedFile = file
                default: hashedFile = nil
                }
                guard let hashedFile, isZipEntry(hashedFile.file) || (isLooseFile(hashedFile.file) && isZipPath(hashedFile.file.url)) else { continue }
                archives.insert(hashedFile.file.url)
            }
        }
        return archives
    }

    /// One `.clearZipComment` per archive in `archivesWithComments` —
    /// real bug found live by jensyleo (2026-09-22): the OLD version of
    /// this function (see `matchedZipArchiveURLs` just above for the part
    /// that survived) planned a removal for EVERY matched zip
    /// unconditionally, never checking whether it actually had a comment
    /// at all — offering "Remove Zip Comment…" (added to the context menu
    /// that same day) for `gryzor.zip`, which never had one, right next
    /// to genuinely commented archives. `archivesWithComments` is real,
    /// already-read data the caller supplies (this function itself still
    /// never touches disk) — see `matchedZipArchiveURLs`'s own doc
    /// comment for why the two are split this way.
    public static func planRemoveZipComments(archivesWithComments: Set<URL>) -> [RebuildOperation] {
        archivesWithComments.sorted { $0.path < $1.path }.map { .clearZipComment(archive: $0) }
    }

    /// Populates MAME's own "samples" folder — a `<name>.zip` per machine
    /// (or per shared `sampleof` group), each holding the `.wav` recordings
    /// a handful of early-80s arcade boards play back for sounds their
    /// hardware never synthesized on its own. Deliberately narrow, for
    /// reasons that don't apply to any other Fase 2 action: MAME's own DAT
    /// declares a sample's NAME only, never a hash — there's no dump to
    /// verify (these are original cabinet audio recordings, not a ROM
    /// dump), so "Fix Samples" can only ever mean "does the whole zip this
    /// game needs exist at all", never "is it the right one". This
    /// planner just copies whichever candidate `foundSampleZips` already
    /// found (by NAME alone, plain filesystem search — see
    /// `LibraryViewModel.collectSamples` for where that search itself
    /// happens; planning stays pure here, same as every other planner
    /// function) into `samplesFolder`, one `<name>.zip` per resolved
    /// sample-set name still missing there.
    ///
    /// `neededSetNames` is every DISTINCT resolved sample-set name the
    /// caller's loaded DAT actually needs — already resolved via `sampleOf
    /// ?? name` (mirrors `cloneOf`/`romOf`'s own one-hop sharing), so two
    /// games sharing one `sampleof` group only ever plan ONE copy for it,
    /// not once per game.
    public static func planCollectSamples(
        neededSetNames: Set<String>,
        foundSampleZips: [String: URL],
        samplesFolder: URL
    ) -> [RebuildOperation] {
        neededSetNames.sorted().compactMap { setName in
            guard let source = foundSampleZips[setName] else { return nil }
            let destination = samplesFolder.appendingPathComponent("\(safePathComponent(setName)).zip")
            return .copy(from: source, to: destination)
        }
    }

    /// "Organize BIOS Files…" — jensyleo's own request (2026-09-23),
    /// exclusively a toolbar File Actions entry: moves every real,
    /// standalone BIOS archive/loose file (`DATGame.isBios == true`)
    /// found anywhere across the system's own configured ROM folders into
    /// one dedicated `biosFolder`, and removes any OTHER unclaimed copy of
    /// that same BIOS's content found elsewhere — jensyleo's own words:
    /// "buscar en todos los ROMS folders y moverlos a la carpeta BIOS. Si
    /// hay repetidos, los elimina." Deliberately works the SAME regardless
    /// of Rom/Bios merge mode ("no importa el modo", his own words) — a
    /// BIOS machine is always matched as its own `GameMatchResult`
    /// independent of whatever merge mode does to fold its content into
    /// OTHER games' own archives, so this only ever touches the BIOS's own
    /// physical file, never anything folded elsewhere.
    ///
    /// Two passes:
    /// 1. For each BIOS machine, `.move` its own real container into
    ///    `biosFolder`, unless it's already sitting there. `hashedFile.file
    ///    .url` is always the real on-disk container regardless of whether
    ///    this particular rom is matched as a loose file or as one of
    ///    several named entries inside a zip — a real BIOS zip
    ///    (`neogeo.zip`, several distinct entries) is the common case, not
    ///    the exception, and moving the whole container file needs no
    ///    entry-level rewrite either way (an earlier version of this
    ///    function wrongly required `isLooseFile`, which only recognizes a
    ///    single-entry-named-after-itself zip — silently skipping every
    ///    genuine multi-entry BIOS zip; caught by
    ///    `planOrganizeBIOSFilesMovesAndDedups`'s own test).
    /// 2. For every OTHER unclaimed copy of that same BIOS's content found
    ///    anywhere in the scan (`SurplusFile.requiredByGameMachineName`
    ///    pointing at one of these BIOS machines) — reusing the exact same
    ///    safety field "Remove Redundant Files…" already relies on
    ///    (`requiredByGameOwnerSatisfiedElsewhere`, the strict subset that
    ///    means the owner genuinely already has a real copy — see that
    ///    field's own doc comment for the 2026-09-19 incident this
    ///    protects against) — plans its removal: `.removeEntryFromZip` for
    ///    an entry inside another archive, `.delete` for a genuine loose
    ///    duplicate.
    public static func planOrganizeBIOSFiles(matchReport: MatchReport, biosFolder: URL) -> [RebuildOperation] {
        organizeSharedMachineOperations(matchReport: matchReport, destinationFolder: biosFolder, isQualifying: { $0.isBios })
    }

    /// "Organize Complementary Chips…" — jensyleo's own request
    /// (2026-09-24), right after a long, sourced investigation (MAME's own
    /// official docs, `docs.mamedev.org/usingmame/aboutromsets.html`:
    /// "Device sets contain reusable circuit designs and their associated
    /// firmware that appear across multiple, otherwise unrelated arcade
    /// boards... categorized as a Device, with the data stored as a Device
    /// set" — the exact same NAMCO51.ZIP-style pattern as a BIOS, just
    /// tagged `isdevice="yes"` instead of `isbios="yes"` in `-listxml`).
    /// jensyleo's own final wording: "lo mismo que BIOS pero para los
    /// demás chips."
    ///
    /// Same exact two-pass mechanics as `planOrganizeBIOSFiles` — see
    /// `organizeSharedMachineOperations`'s own doc comment for why sharing
    /// one implementation is safe here: a rom genuinely embedded INSIDE a
    /// playable game's own archive (jensyleo's own explicit exclusion
    /// rule, confirmed with real DAT data: CPS2's own QSound `region=
    /// "qsound"` sample roms, declared directly under the GAME's own
    /// `<machine>`, not a separate device machine) never shows up as one
    /// of THIS device's own `gameResult.matches` at all — `ROMMatcher`
    /// already claims that physical file for the game's own requirement,
    /// so there's nothing here to move. Only a rom the DAT models as
    /// belonging to the DEVICE's own separate `<machine isdevice="yes">`
    /// entry (e.g. QSound's real chip firmware, `dl-1425.bin`, or Sega's
    /// `segadimm`) ever becomes a candidate — exactly the distinction
    /// jensyleo's own rule called for, with no extra filtering needed
    /// beyond reusing `DATGame.isDevice` in place of `isBios`.
    public static func planOrganizeComplementaryChips(matchReport: MatchReport, chipsFolder: URL) -> [RebuildOperation] {
        organizeSharedMachineOperations(matchReport: matchReport, destinationFolder: chipsFolder, isQualifying: { $0.isDevice })
    }

    /// Shared two-pass mechanics behind both `planOrganizeBIOSFiles` and
    /// `planOrganizeComplementaryChips` — the only real difference between
    /// "a shared BIOS" and "a shared complementary chip" is which
    /// `DATGame` flag marks it (`isBios` vs `isDevice`); everything else
    /// (move the machine's own real container in, remove a further
    /// confirmed-safe duplicate copy elsewhere) is identical.
    private static func organizeSharedMachineOperations(
        matchReport: MatchReport, destinationFolder: URL, isQualifying: (DATGame) -> Bool
    ) -> [RebuildOperation] {
        var operations: [RebuildOperation] = []
        var qualifyingMachineNames = Set<String>()

        for gameResult in matchReport.games where isQualifying(gameResult.game) {
            qualifyingMachineNames.insert(gameResult.game.name)
            var candidateURLs = Set<URL>()
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _), .hashMismatch(let file): hashedFile = file
                default: hashedFile = nil
                }
                guard let hashedFile else { continue }
                candidateURLs.insert(hashedFile.file.url)
            }
            for url in candidateURLs where url.deletingLastPathComponent() != destinationFolder {
                operations.append(.move(from: url, to: destinationFolder.appendingPathComponent(url.lastPathComponent)))
            }
        }

        for surplus in matchReport.surplusFiles {
            guard let machineName = surplus.requiredByGameMachineName, qualifyingMachineNames.contains(machineName) else { continue }
            guard surplus.requiredByGameOwnerSatisfiedElsewhere else { continue }
            let file = surplus.file.file
            if isZipEntry(file) {
                operations.append(.removeEntryFromZip(archive: file.url, entryName: file.effectiveEntryPath))
            } else if isLooseFile(file) {
                operations.append(.delete(file.url))
            }
            // A `.7z`-held entry (`isUnrewritableArchiveEntry`) is skipped
            // entirely, same reasoning as every other entry-removal
            // planner here — `SevenZipRunner` exposes no entry removal.
        }
        return operations
    }

    /// One human-readable line per BIOS machine "Organize BIOS Files…"
    /// would actually touch — jensyleo's own request (2026-09-23): "en ese
    /// menú de confirmación, quiero que muestre el listado de las BIOS que
    /// encontró", right after asking what exactly the action does, worried
    /// about losing BIOS files he already has. Deliberately separate from
    /// `planOrganizeBIOSFiles` itself (that one stays a flat, ordered list
    /// of raw `RebuildOperation`s to execute) — this walks the exact same
    /// two passes purely to describe them, one line per BIOS machine
    /// touched, e.g. `"neogeo — Neo Geo (move; 1 duplicate copy removed)"`,
    /// sorted by machine name so the confirmation dialog reads the same
    /// way every time.
    public static func describeOrganizeBIOSFiles(matchReport: MatchReport, biosFolder: URL) -> [String] {
        describeOrganizeSharedMachines(matchReport: matchReport, destinationFolder: biosFolder, isQualifying: { $0.isBios })
    }

    /// Same reasoning as `describeOrganizeBIOSFiles` — one line per
    /// complementary chip "Organize Complementary Chips…" would touch,
    /// for that action's own confirmation dialog/result log.
    public static func describeOrganizeComplementaryChips(matchReport: MatchReport, chipsFolder: URL) -> [String] {
        describeOrganizeSharedMachines(matchReport: matchReport, destinationFolder: chipsFolder, isQualifying: { $0.isDevice })
    }

    private static func describeOrganizeSharedMachines(
        matchReport: MatchReport, destinationFolder: URL, isQualifying: (DATGame) -> Bool
    ) -> [String] {
        var descriptionByMachineName: [String: String] = [:]
        var movedCountByMachineName: [String: Int] = [:]
        var duplicateCountByMachineName: [String: Int] = [:]
        var qualifyingMachineNames = Set<String>()

        for gameResult in matchReport.games where isQualifying(gameResult.game) {
            qualifyingMachineNames.insert(gameResult.game.name)
            descriptionByMachineName[gameResult.game.name] = gameResult.game.description
            var candidateURLs = Set<URL>()
            for romMatch in gameResult.matches {
                let hashedFile: HashedFile?
                switch romMatch.status {
                case .correct(let file, _), .misnamed(let file, _), .hashMismatch(let file): hashedFile = file
                default: hashedFile = nil
                }
                guard let hashedFile else { continue }
                candidateURLs.insert(hashedFile.file.url)
            }
            let toMove = candidateURLs.filter { $0.deletingLastPathComponent() != destinationFolder }
            if !toMove.isEmpty {
                movedCountByMachineName[gameResult.game.name] = toMove.count
            }
        }

        for surplus in matchReport.surplusFiles {
            guard let machineName = surplus.requiredByGameMachineName, qualifyingMachineNames.contains(machineName) else { continue }
            guard surplus.requiredByGameOwnerSatisfiedElsewhere else { continue }
            let file = surplus.file.file
            guard isZipEntry(file) || isLooseFile(file) else { continue }
            duplicateCountByMachineName[machineName, default: 0] += 1
        }

        let touchedMachineNames = Set(movedCountByMachineName.keys).union(duplicateCountByMachineName.keys)
        return touchedMachineNames.sorted().map { machineName in
            let description = descriptionByMachineName[machineName] ?? machineName
            var parts: [String] = []
            if let moved = movedCountByMachineName[machineName] {
                parts.append(moved == 1 ? "move" : "move \(moved) files")
            }
            if let duplicates = duplicateCountByMachineName[machineName] {
                parts.append(duplicates == 1 ? "1 duplicate copy removed" : "\(duplicates) duplicate copies removed")
            }
            return "\(machineName) — \(description) (\(parts.joined(separator: "; ")))"
        }
    }
}
