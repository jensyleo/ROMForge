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
            let requiredBiosNames = game.biosSetNames.isEmpty ? nil : game.biosSetNames.joined(separator: ", ")
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
                        hasCHD: hasCHD, hasSamples: hasSamples, isBadDump: isBadDump, romDumpStatus: rom.status, mergeName: rom.mergeName,
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
            let status: AuditStatus = surplusFile.requiredByGameDescription != nil ? .incorrect : .surplus
            entries.append(
                AuditEntry(
                    status: status, game: nil,
                    requiredByGameDescription: surplusFile.requiredByGameDescription,
                    name: hashedFile.file.name, path: hashedFile.file.url,
                    actualSize: hashedFile.file.size,
                    actualCRC: hashedFile.hash.crc32, actualMD5: hashedFile.hash.md5, actualSHA1: hashedFile.hash.sha1
                )
            )
        }

        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0
        for entry in entries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus: surplus += 1
            }
        }

        return AuditReport(entries: entries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus)
    }

    /// Folds `DiskAuditor.audit(...)`'s own entries into an existing ROM
    /// `AuditReport`, recomputing its per-status counts — kept as a
    /// separate step (not part of `generate(from:)` itself) since disk
    /// auditing has its own independent inputs (`DATFile` + the scanned
    /// `.chd` file list) rather than a `MatchReport`.
    public static func merging(diskEntries: [AuditEntry], into report: AuditReport) throws -> AuditReport {
        try Task.checkCancellation()
        var correct = report.correct, incorrect = report.incorrect, badDump = report.badDump, missing = report.missing, surplus = report.surplus
        for entry in diskEntries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus: surplus += 1
            }
        }
        return AuditReport(entries: report.entries + diskEntries, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus)
    }
}
