// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Audits every `<disk>` (`DATGame.disks`) a DAT declares against the CHD
/// files actually found on disk, producing `AuditEntry` rows exactly like
/// `AuditReporter` does for ROMs — `.correct`/`.incorrect`/`.missing`, by
/// each CHD's own header SHA1 (`CHDMatcher`, never by decompressing hunks;
/// see `CHDHeaderReader`'s own doc comment on why the header alone is
/// sufficient and is what MAME tools have always compared).
///
/// Kept as its own pass, separate from `AuditReporter`/`ROMMatcher`, because
/// disks aren't part of `MatchReport` at all — a `.chd` file is never one of
/// a game's `DATRom` entries, so it was never a candidate for
/// `ROMMatcher.match` in the first place. Before this existed, a scanned
/// `.chd` file fell through to `FileHasher` like any other loose file, then
/// showed up as a plain, unrecognized "surplus" entry — jensyleo's own
/// report (2026-07-30): loading a folder of MAME CHDs, none of them were
/// recognized at all.
public enum DiskAuditor {
    /// - Parameter chdFiles: every scanned file whose extension is `.chd` —
    ///   callers should exclude these from whatever list they hand to
    ///   `FileHasher`/`CollectionHasher`, since a CHD's own hash has no
    ///   relationship to a `DATRom`'s CRC/MD5/SHA1 and matching it there
    ///   would only ever produce a false "surplus" result.
    /// `throws` only ever propagates `CancellationError` — same fix as
    /// `ROMMatcher.match`/`AuditReporter.generate`'s own doc comments:
    /// nothing in this scan-pipeline stage ever checked `Task.isCancelled`
    /// before, so cancelling mid-scan showed the warning but kept running
    /// regardless. Checked at entry and throttled inside the loop over
    /// `dat.games` — this function runs synchronously on the calling
    /// `Task`'s own thread (no concurrent dispatch here), so the check is
    /// meaningful everywhere in this loop.
    public static func audit(dat: DATFile, chdFiles: [URL]) throws -> [AuditEntry] {
        try Task.checkCancellation()
        var entries: [AuditEntry] = []
        // Several clones of the same game often share one physical disk
        // unmodified (MAME's own `romof`/`cloneof` hierarchy — a region or
        // revision variant that changes the program ROM but not the CD/HD
        // image) — every one of those clones declares a `<disk>` with the
        // identical name+sha1. Without deduplicating here, the exact same
        // physical `.chd` produced one audit row *per clone that happens to
        // reference it* — jensyleo's own report (2026-07-30): four rows all
        // named "cap-sf3-3.chd" for four different Street Fighter III 3rd
        // Strike clones. A disk's own identity is its (name, expected sha1)
        // pair, regardless of which/how-many games ask for it — this seen
        // set makes each unique one audited exactly once, keyed by the
        // *first* game (in DAT order, typically parent-first) that
        // declares it.
        var seenDisks = Set<String>()
        for game in dat.games {
            // Checked every game, not throttled — see `ROMMatcher.match`'s
            // own doc comment for why throttling this was a real bug.
            try Task.checkCancellation()
            guard !game.disks.isEmpty else { continue }
            let chdNames = game.disks.map(\.name).joined(separator: ", ")
            for disk in game.disks {
                let diskKey = "\(disk.name)::\(disk.sha1 ?? "")"
                guard seenDisks.insert(diskKey).inserted else { continue }
                let status = CHDMatcher.match(disk: disk, chdFiles: chdFiles)
                switch status {
                case .correct(let url):
                    let header = try? CHDHeaderReader.read(contentsOf: url)
                    entries.append(AuditEntry(
                        status: .correct, game: game.name, gameDescription: game.description,
                        cloneOf: game.cloneOf, isBios: game.isBios, hasCHD: true, chdNames: chdNames,
                        gameYear: game.year, gameManufacturer: game.manufacturer,
                        isDisk: true, name: disk.name, path: url,
                        expectedSize: header.map { Int64($0.logicalBytes) }, actualSize: header.map { Int64($0.logicalBytes) },
                        expectedSHA1: disk.sha1, actualSHA1: header?.sha1
                    ))
                case .incorrect(let url):
                    let header = try? CHDHeaderReader.read(contentsOf: url)
                    entries.append(AuditEntry(
                        status: .incorrect, game: game.name, gameDescription: game.description,
                        cloneOf: game.cloneOf, isBios: game.isBios, hasCHD: true, chdNames: chdNames,
                        gameYear: game.year, gameManufacturer: game.manufacturer,
                        isDisk: true, name: disk.name, path: url,
                        expectedSHA1: disk.sha1, actualSHA1: header?.sha1
                    ))
                case .missing:
                    entries.append(AuditEntry(
                        status: .missing, game: game.name, gameDescription: game.description,
                        cloneOf: game.cloneOf, isBios: game.isBios, hasCHD: true, chdNames: chdNames,
                        gameYear: game.year, gameManufacturer: game.manufacturer,
                        isDisk: true, name: disk.name, path: nil,
                        expectedSHA1: disk.sha1
                    ))
                case .unverifiable(let url):
                    // See `CHDDiskStatus.unverifiable`'s own doc comment —
                    // the DAT declares no sha1 to verify this disk against
                    // at all, so `actualSHA1` is whatever the real header
                    // happens to say, purely informational (never compared).
                    let header = try? CHDHeaderReader.read(contentsOf: url)
                    entries.append(AuditEntry(
                        status: .unverifiable, game: game.name, gameDescription: game.description,
                        cloneOf: game.cloneOf, isBios: game.isBios, hasCHD: true, chdNames: chdNames,
                        gameYear: game.year, gameManufacturer: game.manufacturer,
                        isDisk: true, name: disk.name, path: url,
                        expectedSize: header.map { Int64($0.logicalBytes) }, actualSize: header.map { Int64($0.logicalBytes) },
                        actualSHA1: header?.sha1
                    ))
                }
            }
        }
        return entries
    }
}
