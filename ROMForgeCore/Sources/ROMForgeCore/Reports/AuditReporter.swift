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
    public static func generate(from matchReport: MatchReport) -> AuditReport {
        var entries: [AuditEntry] = []

        for gameResult in matchReport.games {
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
            entries.append(
                AuditEntry(
                    status: .surplus, game: nil,
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
    public static func merging(diskEntries: [AuditEntry], into report: AuditReport) -> AuditReport {
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
