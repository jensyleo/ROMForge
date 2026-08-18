// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Collapses a `MatchReport` into a flat `AuditReport`: correct (name and
/// hash match), incorrect (hash matches, name doesn't), missing (no local
/// file matches), surplus (local file matches no expected ROM).
public enum AuditReporter {
    /// `throws` only ever propagates `CancellationError` — same fix, and
    /// same reason, as `ROMMatcher.match`'s own doc comment: cancelling a
    /// scan mid-flight showed the cancellation warning immediately but kept
    /// running regardless, because nothing downstream of the matcher ever
    /// actually checked `Task.isCancelled` either. Checked at entry and
    /// throttled inside the loop over `matchReport.games` (every 5000, a
    /// full MAME DAT's ~43,000 games) — this whole function runs
    /// synchronously on the calling `Task`'s own thread, so `Task.isCancelled`
    /// is meaningful everywhere here, unlike `ROMMatcher`'s parallel phase 1.
    public static func generate(from matchReport: MatchReport) throws -> AuditReport {
        try Task.checkCancellation()
        var entries: [AuditEntry] = []

        // Built once for the whole report, not per-game — `romOf`-chain
        // resolution (`resolvedBiosMachineName`) needs to look up arbitrary
        // ancestor machines by name, and every one of them is some other
        // game already in this same DAT/scan.
        let gamesByName = Dictionary(uniqueKeysWithValues: matchReport.games.map { ($0.game.name, $0.game) })

        for gameResult in matchReport.games {
            // Checked every game, not throttled — a lock-free `Task`
            // cancellation read is negligible next to any real per-game
            // work (see `ROMMatcher.match`'s own doc comment for the real
            // bug this same reasoning fixed there).
            try Task.checkCancellation()
            let game = gameResult.game
            let hasCHD = !game.disks.isEmpty
            let hasSamples = game.hasSamples
            // Computed once per game rather than per rom — every rom in a
            // game shares the same game-level metadata.
            let chdNames = game.disks.isEmpty ? nil : game.disks.map(\.name).joined(separator: ", ")
            // The real BIOS machine this game needs (via `romOf`), not this
            // machine's OWN `<biosset>` variants — see
            // `resolvedBiosMachineName`'s own doc comment for the real,
            // confusing report (Mario Kart Arcade GP showing
            // "single, multi, single3") this fixes.
            let requiredBiosNames = game.resolvedBiosMachineName(gamesByName: gamesByName)
            let deviceRefNames = game.deviceRefs.isEmpty ? nil : game.deviceRefs.joined(separator: ", ")
            for romMatch in gameResult.matches {
                let rom = romMatch.rom
                let isBadDump = rom.status != .good
                // Every branch below shares the same game-level fields and
                // this rom's own expected identity — only `status`, `path`,
                // and the `actual*` hash/size (present for a hashed file,
                // absent for `.missing`) actually differ, so those are the
                // only per-case parameters left.
                let makeEntry: (AuditStatus, URL?, HashedFile?, Bool, String?) -> AuditEntry = { status, path, hashedFile, viaHeaderStrip, foundElsewhereArchiveName in
                    AuditEntry(
                        status: status, game: game.name, gameDescription: game.description, cloneOf: game.cloneOf, isBios: game.isBios,
                        hasCHD: hasCHD, hasSamples: hasSamples, isBadDump: isBadDump, isOptional: rom.optional, romDumpStatus: rom.status, mergeName: rom.mergeName,
                        chdNames: chdNames, gameYear: game.year, gameManufacturer: game.manufacturer,
                        requiredBiosNames: requiredBiosNames, deviceRefNames: deviceRefNames,
                        matchedViaHeaderStrip: viaHeaderStrip, foundElsewhereArchiveName: foundElsewhereArchiveName,
                        name: rom.name, path: path,
                        expectedSize: rom.size, actualSize: hashedFile?.file.size,
                        expectedCRC: rom.crc, expectedMD5: rom.md5, expectedSHA1: rom.sha1,
                        actualCRC: hashedFile?.hash.crc32, actualMD5: hashedFile?.hash.md5, actualSHA1: hashedFile?.hash.sha1
                    )
                }
                switch romMatch.status {
                case .correct(let hashedFile, let viaHeaderStrip):
                    entries.append(makeEntry(.correct, hashedFile.file.url, hashedFile, viaHeaderStrip, nil))
                case .misnamed(let hashedFile, let viaHeaderStrip):
                    entries.append(makeEntry(.incorrect, hashedFile.file.url, hashedFile, viaHeaderStrip, nil))
                case .foundElsewhere(let hashedFile):
                    // Genuinely present in the collection — just not
                    // consolidated into this game's own self-contained
                    // archive the way Un-merged expects (see
                    // `RomMatchStatus.foundElsewhere`'s own doc comment) —
                    // a naming/organization problem, same bucket as
                    // `.misnamed`, not a true absence.
                    entries.append(makeEntry(.incorrect, hashedFile.file.url, hashedFile, false, hashedFile.file.url.lastPathComponent))
                case .hashMismatch(let hashedFile):
                    // A file genuinely occupies this rom's own expected
                    // slot (same name, right archive) but its hash doesn't
                    // match — a real content problem ("Bad"), not a
                    // naming/location one.
                    entries.append(makeEntry(.badDump, hashedFile.file.url, hashedFile, false, nil))
                case .missing:
                    entries.append(makeEntry(.missing, nil, nil, false, nil))
                case .nodump(let hashedFile):
                    // A file genuinely sits in this nodump rom's own
                    // expected slot, but the DAT itself has no hash to
                    // verify it against — neither "correct" (nothing to
                    // confirm) nor "surplus" (the DAT explicitly documents
                    // this exact name/slot). See `AuditStatus.unverifiable`'s
                    // own doc comment.
                    entries.append(makeEntry(.unverifiable, hashedFile.file.url, hashedFile, false, nil))
                }
            }
        }

        for surplusFile in matchReport.surplusFiles {
            let hashedFile = surplusFile.file
            // jensyleo's own correction (2026-08-04): `.surplus` means
            // "unrecognized" — genuinely no idea what this file is. A file
            // whose hash matches a real rom *some* DAT game declares
            // (`requiredByGameDescription` set) is the opposite of that:
            // fully identified, just filed somewhere that doesn't currently
            // need it (e.g. a Split-mode clone's zip still holding a rom
            // its parent's own archive is the one that actually wants).
            // That's a real, fixable location problem — the same bucket as
            // a misnamed rom, not "unknown".
            // A file matching neither a real hash nor a known name still
            // gets one more, narrower chance: its own entry name matching a
            // DAT-declared `nodump` rom (`matchesNodumpRomName`, see
            // `SurplusFile`'s own doc comment) — a rom with no hash at all,
            // so a leftover/duplicate copy of it can never be recognized any
            // other way. Distinct from `.incorrect` (that's a real,
            // fixable location problem; this is just an extra, unverifiable
            // copy of something already accounted for elsewhere).
            // jensyleo's own gray-file split (2026-08-06): checked in this
            // exact order — nodump-by-name first (a nodump rom has no hash,
            // so it can never be reached any other way, regardless of which
            // archive it's actually sitting in), then whether the
            // containing archive is itself a real, recognized DAT machine
            // name (`surplusInArchive`) or not (`unknownFile`) — see
            // `AuditStatus`'s own doc comment for the full reasoning and the
            // real, confusing live report (Gryzor's nodump PAL vs. two junk
            // screenshot archives, both plain gray before this) that
            // motivated it.
            let status: AuditStatus
            if surplusFile.requiredByGameDescription != nil {
                status = .incorrect
            } else if surplusFile.matchesNodumpRomName {
                status = .unverifiable
            } else if surplusFile.isInKnownArchive {
                status = .surplusInArchive
            } else {
                status = .unknownFile
            }
            entries.append(
                AuditEntry(
                    status: status, game: nil,
                    requiredByGameDescription: surplusFile.requiredByGameDescription,
                    misnamedArchiveForGameName: surplusFile.misnamedArchiveForGameName,
                    name: hashedFile.file.name, path: hashedFile.file.url,
                    actualSize: hashedFile.file.size,
                    actualCRC: hashedFile.hash.crc32, actualMD5: hashedFile.hash.md5, actualSHA1: hashedFile.hash.sha1
                )
            )
        }

        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0, unverifiable = 0
        for entry in entries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            // `surplusInArchive`/`unknownFile` both roll up into the same
            // `surplus` aggregate count as the legacy single bucket did —
            // the split only matters at the per-entry `status` level (what
            // `LibraryDetailView` actually renders), not this summary tally.
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            }
        }

        return AuditReport(entries: entries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus, unverifiable: unverifiable)
    }

    /// Folds `DiskAuditor.audit(...)`'s own entries into an existing ROM
    /// `AuditReport`, recomputing its per-status counts — kept as a
    /// separate step (not part of `generate(from:)` itself) since disk
    /// auditing has its own independent inputs (`DATFile` + the scanned
    /// `.chd` file list) rather than a `MatchReport`.
    public static func merging(diskEntries: [AuditEntry], into report: AuditReport) throws -> AuditReport {
        try Task.checkCancellation()
        var correct = report.correct, incorrect = report.incorrect, badDump = report.badDump, missing = report.missing, surplus = report.surplus, unverifiable = report.unverifiable
        for entry in diskEntries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            }
        }
        return AuditReport(entries: report.entries + diskEntries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus, unverifiable: unverifiable)
    }

    /// Builds the report to actually *display* after a targeted rescan
    /// ("Rescan This File", or "Scan Folder" on one folder) — every other
    /// entry keeps the exact value it had in `previousReport`, byte-for-byte
    /// unchanged, even though `newReport` is always a complete, freshly
    /// re-matched report across the whole system (see
    /// `LibraryViewModel.scan`'s own doc comment for why matching always
    /// covers everything, regardless of what actually got re-read from
    /// disk). jensyleo's own request (2026-08-17): after a targeted rescan
    /// (e.g. changing BIOS merge mode, then rescanning just one archive to
    /// check it), only that file's own row should visually update — every
    /// other row should look exactly as it did a moment ago, with no
    /// whole-table flicker for a spot check on one file.
    ///
    /// This only ever affects what's *displayed this session*; the caller
    /// still persists `newReport` itself (the complete, correct one) to the
    /// on-disk database — reopening this system fresh always shows the full
    /// truth, never anything artificially held back by this function.
    ///
    /// `rescannedPaths` empty, or no `previousReport` to preserve anything
    /// from (e.g. the system's very first scan), returns `newReport`
    /// unchanged — a full "Scan Folder"/"Scan All Folders" is untouched by
    /// this at all.
    public static func replacingRescannedEntries(in previousReport: AuditReport?, with newReport: AuditReport, rescannedPaths: [URL]) -> AuditReport {
        guard let previousReport, !rescannedPaths.isEmpty else { return newReport }
        let prefixes = rescannedPaths.map(\.path)
        func pathIsRescanned(_ entry: AuditEntry) -> Bool {
            guard let path = entry.path?.path else { return false }
            return prefixes.contains { path.hasPrefix($0) }
        }

        // A rescanned archive can change ANY of a game's own entries —
        // including one that had no path at all before (a `.missing` rom
        // this rescan just found) or has none now (a rom this rescan just
        // lost). Path alone can't catch either direction — matching only
        // by path would leave a stale `.missing` old entry sitting
        // alongside a fresh `.correct` new one for the same rom, showing it
        // twice. So instead, every entry belonging to a game that shows up
        // under the rescanned path(s) in EITHER report gets fully replaced
        // together, not just the individual entries whose own path happens
        // to match.
        var refreshedGames: Set<String> = []
        for entry in previousReport.entries where pathIsRescanned(entry) {
            if let game = entry.game { refreshedGames.insert(game) }
        }
        for entry in newReport.entries where pathIsRescanned(entry) {
            if let game = entry.game { refreshedGames.insert(game) }
        }

        func isRefreshed(_ entry: AuditEntry) -> Bool {
            if let game = entry.game { return refreshedGames.contains(game) }
            // Game-less (surplus) entries have no grouping to fall back
            // on — but always carry a real path (a surplus row only ever
            // exists for a file actually found on disk), so path alone is
            // enough here.
            return pathIsRescanned(entry)
        }

        let untouchedEntries = previousReport.entries.filter { !isRefreshed($0) }
        let refreshedEntries = newReport.entries.filter(isRefreshed)
        let mergedEntries = untouchedEntries + refreshedEntries

        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0, unverifiable = 0
        for entry in mergedEntries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            }
        }
        return AuditReport(entries: mergedEntries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus, unverifiable: unverifiable)
    }
}
