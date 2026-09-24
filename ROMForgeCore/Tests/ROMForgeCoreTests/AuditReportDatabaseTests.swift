// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// A lock-protected accumulator for a `@Sendable` progress callback's own
/// ticks — plain array mutation from inside such a closure is a real
/// Swift 6 strict-concurrency error, not just a style nit.
private final class TickBox: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [(completed: Int, total: Int)] = []
    func record(_ tick: (completed: Int, total: Int)) {
        lock.lock()
        defer { lock.unlock() }
        ticks.append(tick)
    }
    var all: [(completed: Int, total: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return ticks
    }
}

@Suite("AuditReportDatabase")
struct AuditReportDatabaseTests {
    private func tempDBPath() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent("audit-\(UUID().uuidString).sqlite3").path
    }

    private func sampleReport() -> AuditReport {
        let correct = AuditEntry(
            status: .correct, game: "Game One", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false,
            name: "gameone.bin", path: URL(fileURLWithPath: "/roms/gameone.bin"),
            expectedSize: 9, actualSize: 9, expectedCRC: "cbf43926", expectedMD5: "25f9e79", expectedSHA1: "f7c3bc1",
            actualCRC: "cbf43926", actualMD5: "25f9e79", actualSHA1: "f7c3bc1"
        )
        let missing = AuditEntry(
            status: .missing, game: "Game Two", cloneOf: "Game One", isBios: true, hasCHD: true, hasSamples: true, isBadDump: true,
            name: "gametwo.bin", path: nil, expectedSize: 100, expectedCRC: "deadbeef"
        )
        let surplus = AuditEntry(status: .surplus, game: nil, name: "extra.bin", path: URL(fileURLWithPath: "/roms/extra.bin"), actualSize: 42)
        return AuditReport(entries: [correct, missing, surplus], correct: 1, incorrect: 0, missing: 1, surplus: 1)
    }

    @Test("round-trips a full report, preserving every field including nils and special characters")
    func roundTripsReport() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let report = sampleReport()
        let scannedAt = Date(timeIntervalSince1970: 1_700_000_000)

        try db.saveReport(report, systemID: "sys-1", datName: "GUI Test Set", datVersion: "1.0", scannedAt: scannedAt)
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        #expect(loaded.correct == 1)
        #expect(loaded.incorrect == 0)
        #expect(loaded.missing == 1)
        #expect(loaded.surplus == 1)
        #expect(Set(loaded.entries.map(\.name)) == Set(report.entries.map(\.name)))

        let reloadedMissing = try #require(loaded.entries.first { $0.name == "gametwo.bin" })
        #expect(reloadedMissing.cloneOf == "Game One")
        #expect(reloadedMissing.isBios == true)
        #expect(reloadedMissing.hasCHD == true)
        #expect(reloadedMissing.hasSamples == true)
        #expect(reloadedMissing.isBadDump == true)
        #expect(reloadedMissing.path == nil)
        #expect(reloadedMissing.expectedSize == 100)
        #expect(reloadedMissing.actualSize == nil)

        let meta = try #require(try db.loadScanMeta(systemID: "sys-1"))
        #expect(meta.datName == "GUI Test Set")
        #expect(meta.datVersion == "1.0")
        #expect(abs(meta.scannedAt.timeIntervalSince(scannedAt)) < 1)
    }

    @Test("saveReport diffs against what's already persisted: an unchanged entry survives untouched, a changed one updates in place, a dropped one is removed, and a new one is added")
    func saveReportDiffsInsteadOfRewritingEverything() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let unchanged = AuditEntry(status: .correct, game: "Game One", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gameone.bin", path: URL(fileURLWithPath: "/roms/gameone.bin"), expectedSize: 9, actualSize: 9)
        let aboutToChange = AuditEntry(status: .missing, game: "Game Two", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gametwo.bin", path: nil, expectedSize: 9)
        let aboutToBeDropped = AuditEntry(status: .surplus, game: nil, name: "gone.bin", path: URL(fileURLWithPath: "/roms/gone.bin"), actualSize: 9)
        let firstReport = AuditReport(entries: [unchanged, aboutToChange, aboutToBeDropped], correct: 1, incorrect: 0, missing: 1, surplus: 1)
        try db.saveReport(firstReport, systemID: "sys-diff", datName: nil, datVersion: nil, scannedAt: Date())

        // Same game/name identity as `aboutToChange`, but now repaired (found
        // on disk) — this must be treated as an UPDATE of the same logical
        // row, not a delete+insert, per `entryIdentityKey`'s own contract.
        let nowRepaired = AuditEntry(status: .correct, game: "Game Two", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gametwo.bin", path: URL(fileURLWithPath: "/roms/gametwo.bin"), expectedSize: 9, actualSize: 9)
        let brandNew = AuditEntry(status: .surplus, game: nil, name: "new.bin", path: URL(fileURLWithPath: "/roms/new.bin"), actualSize: 9)
        let secondReport = AuditReport(entries: [unchanged, nowRepaired, brandNew], correct: 2, incorrect: 0, missing: 0, surplus: 1)
        try db.saveReport(secondReport, systemID: "sys-diff", datName: nil, datVersion: nil, scannedAt: Date())

        let loaded = try #require(try db.loadReport(systemID: "sys-diff"))
        #expect(Set(loaded.entries.map(\.name)) == ["gameone.bin", "gametwo.bin", "new.bin"], "gone.bin must be dropped, new.bin must be added, and the other two kept")
        let reloadedGameTwo = try #require(loaded.entries.first { $0.name == "gametwo.bin" })
        #expect(reloadedGameTwo.status == .correct)
        #expect(reloadedGameTwo.path == URL(fileURLWithPath: "/roms/gametwo.bin"))
        #expect(reloadedGameTwo.actualSize == 9)
    }

    @Test("saveReport reports real (completed, total) progress across deletes, updates and inserts, ending exactly at the total")
    func saveReportReportsProgress() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let toKeep = AuditEntry(status: .correct, game: "Game One", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gameone.bin", path: URL(fileURLWithPath: "/roms/gameone.bin"), expectedSize: 9, actualSize: 9)
        let toChange = AuditEntry(status: .missing, game: "Game Two", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gametwo.bin", path: nil, expectedSize: 9)
        let toDrop = AuditEntry(status: .surplus, game: nil, name: "gone.bin", path: URL(fileURLWithPath: "/roms/gone.bin"), actualSize: 9)
        try db.saveReport(AuditReport(entries: [toKeep, toChange, toDrop], correct: 1, incorrect: 0, missing: 1, surplus: 1), systemID: "sys-progress", datName: nil, datVersion: nil, scannedAt: Date())

        let changed = AuditEntry(status: .correct, game: "Game Two", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false, name: "gametwo.bin", path: URL(fileURLWithPath: "/roms/gametwo.bin"), expectedSize: 9, actualSize: 9)
        let brandNew = AuditEntry(status: .surplus, game: nil, name: "new.bin", path: URL(fileURLWithPath: "/roms/new.bin"), actualSize: 9)
        let reportedTicks = TickBox()
        try db.saveReport(
            AuditReport(entries: [toKeep, changed, brandNew], correct: 2, incorrect: 0, missing: 0, surplus: 1),
            systemID: "sys-progress", datName: nil, datVersion: nil, scannedAt: Date(),
            onProgress: { completed, total in reportedTicks.record((completed, total)) }
        )

        // 1 delete (gone.bin) + 1 update (gametwo.bin) + 1 insert (new.bin) = 3.
        let ticks = reportedTicks.all
        #expect(!ticks.isEmpty)
        #expect(ticks.last?.completed == 3)
        #expect(ticks.allSatisfy { $0.total == 3 })
    }

    @Test("a large report (past the parallel-load threshold) round-trips identically to the plain single-connection path — jensyleo's own real collection (2026-09-17), 323,568 entries taking 6.5s to load, motivated splitting loadReport's read across several worker connections")
    func largeReportRoundTripsViaParallelLoad() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        // Comfortably past the 20,000-row threshold that switches
        // `loadEntries` from its plain single-connection loop to the
        // multi-connection, rowid-range-partitioned one.
        let entryCount = 25_000
        var entries: [AuditEntry] = []
        entries.reserveCapacity(entryCount)
        for i in 0..<entryCount {
            entries.append(
                AuditEntry(
                    status: i.isMultiple(of: 2) ? .correct : .missing,
                    game: "game\(i)", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false,
                    name: "rom\(i).bin",
                    path: i.isMultiple(of: 2) ? URL(fileURLWithPath: "/roms/rom\(i).bin") : nil,
                    expectedSize: Int64(i), actualSize: i.isMultiple(of: 2) ? Int64(i) : nil,
                    expectedCRC: String(format: "%08x", i)
                )
            )
        }
        let correctCount = entries.filter { $0.status == .correct }.count
        let missingCount = entries.filter { $0.status == .missing }.count
        let report = AuditReport(entries: entries, correct: correctCount, incorrect: 0, missing: missingCount, surplus: 0)

        try db.saveReport(report, systemID: "sys-large", datName: "Large Test Set", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-large"))

        #expect(loaded.entries.count == entryCount)
        #expect(loaded.correct == correctCount)
        #expect(loaded.missing == missingCount)
        // Order-independent: the parallel path merges chunks by index, not
        // guaranteed to match the original save order row-for-row, but
        // every name/status/expectedCRC combination must still be present
        // exactly once.
        #expect(Set(loaded.entries.map(\.name)) == Set(entries.map(\.name)))
        let loadedByName = Dictionary(uniqueKeysWithValues: loaded.entries.map { ($0.name, $0) })
        for original in entries {
            let reloaded = try #require(loadedByName[original.name])
            #expect(reloaded.status == original.status)
            #expect(reloaded.expectedCRC == original.expectedCRC)
            #expect(reloaded.path == original.path)
        }
    }

    @Test("saveEntriesDiffed's own up-front read of what's already persisted uses the parallel rowid-partitioned path above the same threshold loadEntries does, and still diffs correctly against it")
    func saveEntriesDiffedUsesParallelReadPastThreshold() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        // Past the 20,000-row parallel threshold — jensyleo's own report
        // (2026-09-19): a real ~50,368-game "Scan All Folders" got stuck
        // on a frozen progress bar for a long stretch, root-caused to
        // `saveEntriesDiffed`'s own up-front read running as a single
        // sequential decode loop over the WHOLE existing table (the exact
        // same cost `loadEntries` was already parallelized for) — worse
        // than the plain rewrite it replaced whenever most rows differ,
        // exactly what a first save after this session's own schema/logic
        // changes looks like.
        let entryCount = 25_000
        var firstEntries: [AuditEntry] = []
        firstEntries.reserveCapacity(entryCount)
        for i in 0..<entryCount {
            firstEntries.append(
                AuditEntry(
                    status: .missing, game: "game\(i)", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false,
                    name: "rom\(i).bin", path: nil, expectedSize: Int64(i)
                )
            )
        }
        try db.saveReport(
            AuditReport(entries: firstEntries, correct: 0, incorrect: 0, missing: entryCount, surplus: 0),
            systemID: "sys-diff-large", datName: nil, datVersion: nil, scannedAt: Date()
        )

        // Second save changes EVERY surviving entry's status (worst case
        // for the diff — nothing is "unchanged"), drops the last 100, and
        // adds 50 brand-new ones — exercising update, delete and insert
        // together through the parallel read path.
        var secondEntries: [AuditEntry] = (0..<(entryCount - 100)).map { i in
            AuditEntry(
                status: .correct, game: "game\(i)", cloneOf: nil, isBios: false, hasCHD: false, hasSamples: false, isBadDump: false,
                name: "rom\(i).bin", path: URL(fileURLWithPath: "/roms/rom\(i).bin"), expectedSize: Int64(i), actualSize: Int64(i)
            )
        }
        for i in 0..<50 {
            secondEntries.append(
                AuditEntry(
                    status: .surplus, game: nil, name: "new\(i).bin", path: URL(fileURLWithPath: "/roms/new\(i).bin"), actualSize: Int64(i)
                )
            )
        }
        try db.saveReport(
            AuditReport(entries: secondEntries, correct: entryCount - 100, incorrect: 0, missing: 0, surplus: 50),
            systemID: "sys-diff-large", datName: nil, datVersion: nil, scannedAt: Date()
        )

        let loaded = try #require(try db.loadReport(systemID: "sys-diff-large"))
        #expect(loaded.entries.count == entryCount - 100 + 50)
        let loadedByName = Dictionary(uniqueKeysWithValues: loaded.entries.map { ($0.name, $0) })
        #expect(loadedByName["rom0.bin"]?.status == .correct)
        #expect(loadedByName["rom0.bin"]?.path == URL(fileURLWithPath: "/roms/rom0.bin"))
        #expect(loadedByName["rom\(entryCount - 1).bin"] == nil, "the dropped tail must actually be gone, not just unreferenced")
        #expect(loadedByName["new0.bin"]?.status == .surplus)
    }

    @Test("a system that's never been scanned has no persisted report")
    func neverScannedReturnsNil() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        #expect(try db.loadReport(systemID: "never-scanned") == nil)
        #expect(try db.loadScanMeta(systemID: "never-scanned") == nil)
    }

    @Test("saving a new report for the same system replaces the old one, not appends to it")
    func savingReplacesOldReport() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        try db.saveReport(sampleReport(), systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())

        let secondReport = AuditReport(
            entries: [AuditEntry(status: .correct, game: "Only Game", name: "only.bin", path: nil)],
            correct: 1, incorrect: 0, missing: 0, surplus: 0
        )
        try db.saveReport(secondReport, systemID: "sys-1", datName: "v2", datVersion: "2.0", scannedAt: Date())

        let loaded = try #require(try db.loadReport(systemID: "sys-1"))
        #expect(loaded.entries.count == 1)
        #expect(loaded.entries[0].name == "only.bin")
    }

    @Test("removeSystem deletes both the report and its scan metadata")
    func removeSystemDeletesEverything() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        try db.saveReport(sampleReport(), systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        try db.removeSystem("sys-1")

        #expect(try db.loadReport(systemID: "sys-1") == nil)
        #expect(try db.loadScanMeta(systemID: "sys-1") == nil)
    }

    @Test("removeEntries deletes only rows whose path falls under the given prefix, leaving everything else untouched")
    func removeEntriesDeletesOnlyMatchingPrefix() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let report = AuditReport(
            entries: [
                AuditEntry(status: .correct, game: "In folder A", name: "a.bin", path: URL(fileURLWithPath: "/roms/folderA/a.bin")),
                AuditEntry(status: .correct, game: "In folder B", name: "b.bin", path: URL(fileURLWithPath: "/roms/folderB/b.bin")),
                // A path that merely shares folderA's name as a *prefix*
                // (e.g. "folderA2") must never be swept up by a naive
                // string-prefix match — this is exactly why `removeEntries`
                // matches on the folder's own full path (with its trailing
                // structure), not a bare substring.
                AuditEntry(status: .correct, game: "In folder A2", name: "c.bin", path: URL(fileURLWithPath: "/roms/folderA2/c.bin")),
                AuditEntry(status: .missing, game: "No path at all", name: "d.bin", path: nil),
            ],
            correct: 3, incorrect: 0, missing: 1, surplus: 0
        )
        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())

        let deletedCount = try db.removeEntries(systemID: "sys-1", pathPrefix: "/roms/folderA/")

        #expect(deletedCount == 1)
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))
        #expect(Set(loaded.entries.map(\.name)) == ["b.bin", "c.bin", "d.bin"])
    }

    @Test("removeEntries only touches the requested system, never another system's rows sharing the same path prefix")
    func removeEntriesKeepsOtherSystemsUntouched() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let entry = AuditEntry(status: .correct, game: "Shared path", name: "a.bin", path: URL(fileURLWithPath: "/roms/shared/a.bin"))
        try db.saveReport(AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0), systemID: "sys-1", datName: nil, datVersion: nil, scannedAt: Date())
        try db.saveReport(AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0), systemID: "sys-2", datName: nil, datVersion: nil, scannedAt: Date())

        try db.removeEntries(systemID: "sys-1", pathPrefix: "/roms/shared/")

        #expect(try db.loadReport(systemID: "sys-1")?.entries.isEmpty == true)
        #expect(try db.loadReport(systemID: "sys-2")?.entries.count == 1)
    }

    @Test("reports for different systems don't interfere with each other")
    func keepsSystemsIndependent() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        try db.saveReport(sampleReport(), systemID: "sys-1", datName: "A", datVersion: "1", scannedAt: Date())
        try db.saveReport(
            AuditReport(entries: [AuditEntry(status: .missing, game: "G", name: "g.bin", path: nil)], correct: 0, incorrect: 0, missing: 1, surplus: 0),
            systemID: "sys-2", datName: "B", datVersion: "2", scannedAt: Date()
        )

        try db.removeSystem("sys-1")

        #expect(try db.loadReport(systemID: "sys-1") == nil)
        let sys2 = try #require(try db.loadReport(systemID: "sys-2"))
        #expect(sys2.entries.count == 1)
    }

    /// Regression test for a real bug (2026-07-30): `isDisk` wasn't
    /// persisted at all until schema v4 — every disk (`.chd`) row silently
    /// came back as a rom (`isDisk: false`) after being saved and reloaded,
    /// undoing the "audit ROM and CHD independently" fix the moment a user
    /// relaunched the app or re-selected a system rather than freshly
    /// scanning.
    @Test("a disk entry's isDisk flag survives a save/load round trip")
    func isDiskFlagSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let diskEntry = AuditEntry(status: .correct, game: "Some Game", isDisk: true, name: "disk.chd", path: nil)
        let romEntry = AuditEntry(status: .correct, game: "Some Game", isDisk: false, name: "rom.bin", path: nil)
        let report = AuditReport(entries: [diskEntry, romEntry], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedDisk = try #require(loaded.entries.first { $0.name == "disk.chd" })
        let reloadedRom = try #require(loaded.entries.first { $0.name == "rom.bin" })
        #expect(reloadedDisk.isDisk == true)
        #expect(reloadedRom.isDisk == false)
    }

    /// Regression test for the exact same class of bug as `isDisk` above,
    /// one schema version later (v5, 2026-08-04):
    /// `foundElsewhereArchiveName` wasn't persisted either. That field is
    /// what the app's folder-scoped views use to tell "a rom this game
    /// genuinely owns here" apart from "content merely visible in some other
    /// archive" — so losing it on reload silently un-did that filter, and
    /// games the user doesn't own reappeared in "Rom files" folder views.
    /// jensyleo reported it as a fix that had worked and then regressed;
    /// what actually happened is a fresh scan was always right and only the
    /// reloaded-from-disk path was wrong.
    @Test("an entry's foundElsewhereArchiveName survives a save/load round trip")
    func foundElsewhereArchiveNameSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let borrowed = AuditEntry(status: .incorrect, game: "Some Game", foundElsewhereArchiveName: "neogeo.zip", name: "sfix.sfix", path: nil)
        let owned = AuditEntry(status: .correct, game: "Some Game", name: "own.bin", path: nil)
        let report = AuditReport(entries: [borrowed, owned], correct: 1, incorrect: 1, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedBorrowed = try #require(loaded.entries.first { $0.name == "sfix.sfix" })
        let reloadedOwned = try #require(loaded.entries.first { $0.name == "own.bin" })
        #expect(reloadedBorrowed.foundElsewhereArchiveName == "neogeo.zip")
        #expect(reloadedOwned.foundElsewhereArchiveName == nil)
    }

    /// Same class of bug once more, one schema version later (v18,
    /// 2026-08-19), for `AuditEntry.isOrphanedBios` — added the `ALTER
    /// TABLE` and this test in the same commit as the field itself, exactly
    /// like `requiredByGameDescription` below already learned to do, rather
    /// than discovering the gap only after a relaunch silently reset the
    /// flag (as first happened for `isDisk`/`foundElsewhereArchiveName`
    /// above).
    @Test("an entry's cpuChipNames and audioChipNames survive a save/load round trip")
    func chipNamesSurviveRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let withChips = AuditEntry(
            status: .correct, game: "dkong", cpuChipNames: "Zilog Z80, Intel 8035", audioChipNames: "Discrete",
            name: "dkong.zip", path: URL(fileURLWithPath: "/roms/dkong.zip")
        )
        let withoutChips = AuditEntry(status: .correct, game: "pacman", name: "pacman.zip", path: URL(fileURLWithPath: "/roms/pacman.zip"))
        let report = AuditReport(entries: [withChips, withoutChips], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedWithChips = try #require(loaded.entries.first { $0.name == "dkong.zip" })
        let reloadedWithoutChips = try #require(loaded.entries.first { $0.name == "pacman.zip" })
        #expect(reloadedWithChips.cpuChipNames == "Zilog Z80, Intel 8035")
        #expect(reloadedWithChips.audioChipNames == "Discrete")
        #expect(reloadedWithoutChips.cpuChipNames == nil)
        #expect(reloadedWithoutChips.audioChipNames == nil)
    }

    @Test("an entry's driverStatus, displayType, displayRotate, players and coins survive a save/load round trip")
    func detailFieldsSurviveRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let withDetails = AuditEntry(
            status: .correct, game: "mslug", driverStatus: "good", displayType: "raster", displayRotate: "0", players: "2", coins: "1",
            name: "mslug.zip", path: URL(fileURLWithPath: "/roms/mslug.zip")
        )
        let withoutDetails = AuditEntry(status: .correct, game: "pacman", name: "pacman.zip", path: URL(fileURLWithPath: "/roms/pacman.zip"))
        let report = AuditReport(entries: [withDetails, withoutDetails], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedWithDetails = try #require(loaded.entries.first { $0.name == "mslug.zip" })
        let reloadedWithoutDetails = try #require(loaded.entries.first { $0.name == "pacman.zip" })
        #expect(reloadedWithDetails.driverStatus == "good")
        #expect(reloadedWithDetails.displayType == "raster")
        #expect(reloadedWithDetails.displayRotate == "0")
        #expect(reloadedWithDetails.players == "2")
        #expect(reloadedWithDetails.coins == "1")
        #expect(reloadedWithoutDetails.driverStatus == nil)
        #expect(reloadedWithoutDetails.displayType == nil)
        #expect(reloadedWithoutDetails.displayRotate == nil)
        #expect(reloadedWithoutDetails.players == nil)
        #expect(reloadedWithoutDetails.coins == nil)
    }

    @Test("an entry's isDevice flag survives a save/load round trip")
    func isDeviceSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let device = AuditEntry(status: .correct, game: "qsound_hle", isDevice: true, name: "qsound_hle.zip", path: URL(fileURLWithPath: "/roms/qsound_hle.zip"))
        let realGame = AuditEntry(status: .correct, game: "sf2", isDevice: false, name: "sf2.zip", path: URL(fileURLWithPath: "/roms/sf2.zip"))
        let report = AuditReport(entries: [device, realGame], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedDevice = try #require(loaded.entries.first { $0.name == "qsound_hle.zip" })
        let reloadedRealGame = try #require(loaded.entries.first { $0.name == "sf2.zip" })
        #expect(reloadedDevice.isDevice == true)
        #expect(reloadedRealGame.isDevice == false)
    }

    @Test("an entry's isOrphanedBios flag survives a save/load round trip")
    func isOrphanedBiosSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let orphaned = AuditEntry(status: .correct, game: "neogeo", isBios: true, isOrphanedBios: true, name: "neogeo.zip", path: URL(fileURLWithPath: "/roms/neogeo.zip"))
        let inUse = AuditEntry(status: .correct, game: "decocass", isBios: true, isOrphanedBios: false, name: "decocass.zip", path: URL(fileURLWithPath: "/roms/decocass.zip"))
        let report = AuditReport(entries: [orphaned, inUse], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedOrphaned = try #require(loaded.entries.first { $0.name == "neogeo.zip" })
        let reloadedInUse = try #require(loaded.entries.first { $0.name == "decocass.zip" })
        #expect(reloadedOrphaned.isOrphanedBios == true)
        #expect(reloadedInUse.isOrphanedBios == false)
    }

    @Test("an entry's hasContainerCaseMismatch flag survives a save/load round trip — added in the same commit as the field itself (v24), following the exact pattern the earlier isOrphanedBios/actualEntryName gaps established")
    func hasContainerCaseMismatchSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let mismatched = AuditEntry(status: .correct, game: "awbios", hasContainerCaseMismatch: true, name: "awbios.bin", path: URL(fileURLWithPath: "/roms/AWBIOS.zip"))
        let matching = AuditEntry(status: .correct, game: "decocass", hasContainerCaseMismatch: false, name: "decocass.bin", path: URL(fileURLWithPath: "/roms/decocass.zip"))
        let report = AuditReport(entries: [mismatched, matching], correct: 2, incorrect: 0, missing: 0, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedMismatched = try #require(loaded.entries.first { $0.name == "awbios.bin" })
        let reloadedMatching = try #require(loaded.entries.first { $0.name == "decocass.bin" })
        #expect(reloadedMismatched.hasContainerCaseMismatch == true)
        #expect(reloadedMatching.hasContainerCaseMismatch == false)
    }

    @Test("an entry's hasMaintenanceDonor flag survives a save/load round trip — added in the same commit as the field itself (v25); jensyleo's own live report caught this exact gap (the yellow icon reverted to plain red after every app relaunch) before this test did")
    func hasMaintenanceDonorSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let withDonor = AuditEntry(status: .missing, game: "gng", hasMaintenanceDonor: true, name: "mm_c_03", path: nil)
        let withoutDonor = AuditEntry(status: .missing, game: "gng", hasMaintenanceDonor: false, name: "mm_c_06", path: nil)
        let report = AuditReport(entries: [withDonor, withoutDonor], correct: 0, incorrect: 0, missing: 2, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedWithDonor = try #require(loaded.entries.first { $0.name == "mm_c_03" })
        let reloadedWithoutDonor = try #require(loaded.entries.first { $0.name == "mm_c_06" })
        #expect(reloadedWithDonor.hasMaintenanceDonor == true)
        #expect(reloadedWithoutDonor.hasMaintenanceDonor == false)
    }

    @Test("an entry's actualEntryName survives a save/load round trip — added in the same commit as the field itself (v23), following the exact pattern the earlier isDisk/foundElsewhereArchiveName gaps established")
    func actualEntryNameSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        // jensyleo's own report (2026-09-10): renaming a misnamed rom entry
        // inside a zip left nothing anywhere showing the entry's own
        // CURRENT real name — "Rom name" is always the DAT's declared
        // name, and "File name" (`path.lastPathComponent`) is the
        // CONTAINER's filename for a zip entry, never the entry's own.
        let misnamed = AuditEntry(status: .incorrect, game: "awbios", name: "bios0.ic23", actualEntryName: "Bios0.Ic23", path: URL(fileURLWithPath: "/roms/awbios.zip"))
        let missing = AuditEntry(status: .missing, game: "awbios", name: "bios1.ic23", path: nil)
        let report = AuditReport(entries: [misnamed, missing], correct: 0, incorrect: 1, missing: 1, surplus: 0)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedMisnamed = try #require(loaded.entries.first { $0.name == "bios0.ic23" })
        let reloadedMissing = try #require(loaded.entries.first { $0.name == "bios1.ic23" })
        #expect(reloadedMisnamed.actualEntryName == "Bios0.Ic23")
        #expect(reloadedMissing.actualEntryName == nil, "no HashedFile ever existed for a missing rom, so this must stay nil, not an empty string")
    }

    /// Same class of bug once more, one schema version later (v6,
    /// 2026-08-04), for `AuditEntry.requiredByGameDescription` — added the
    /// `ALTER TABLE` and this test in the same commit as the field itself
    /// this time, rather than discovering the gap only after a relaunch
    /// silently lost it (as happened twice already, for `isDisk` and
    /// `foundElsewhereArchiveName`).
    @Test("a surplus entry's requiredByGameDescription survives a save/load round trip")
    func requiredByGameDescriptionSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let recognizedSurplus = AuditEntry(status: .surplus, game: nil, requiredByGameDescription: "Street Fighter II': Champion Edition", name: "s92_01.bin", path: nil)
        let junkSurplus = AuditEntry(status: .surplus, game: nil, name: "random.txt", path: nil)
        let report = AuditReport(entries: [recognizedSurplus, junkSurplus], correct: 0, incorrect: 0, missing: 0, surplus: 2)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedRecognized = try #require(loaded.entries.first { $0.name == "s92_01.bin" })
        let reloadedJunk = try #require(loaded.entries.first { $0.name == "random.txt" })
        #expect(reloadedRecognized.requiredByGameDescription == "Street Fighter II': Champion Edition")
        #expect(reloadedJunk.requiredByGameDescription == nil)
    }

    @Test("an entry's requiredByGameMachineName survives a save/load round trip — added in the same commit as the field itself (v26); jensyleo's own real collection (2026-09-17), CPS2/naomi.zip's own extra rom needed this real DAT machine name (not just the human-readable description already covered above) for \"Repair from Maintenance Folder\" to ever find it a donor")
    func requiredByGameMachineNameSurvivesRoundTrip() throws {
        let db = try AuditReportDatabase(path: tempDBPath())
        let recognizedSurplus = AuditEntry(
            status: .incorrect, game: nil, requiredByGameDescription: "Naomi Bios", requiredByGameMachineName: "naomi",
            name: "epr-21580a.ic27", path: nil
        )
        let junkSurplus = AuditEntry(status: .surplus, game: nil, name: "random.txt", path: nil)
        let report = AuditReport(entries: [recognizedSurplus, junkSurplus], correct: 0, incorrect: 1, missing: 0, surplus: 1)

        try db.saveReport(report, systemID: "sys-1", datName: "v1", datVersion: "1.0", scannedAt: Date())
        let loaded = try #require(try db.loadReport(systemID: "sys-1"))

        let reloadedRecognized = try #require(loaded.entries.first { $0.name == "epr-21580a.ic27" })
        let reloadedJunk = try #require(loaded.entries.first { $0.name == "random.txt" })
        #expect(reloadedRecognized.requiredByGameMachineName == "naomi")
        #expect(reloadedJunk.requiredByGameMachineName == nil)
    }

    @Test("re-opening the same database file preserves previously saved data")
    func persistsAcrossReopens() throws {
        let path = tempDBPath()
        try AuditReportDatabase(path: path).saveReport(sampleReport(), systemID: "sys-1", datName: "A", datVersion: "1", scannedAt: Date())

        let reopened = try AuditReportDatabase(path: path)
        let loaded = try #require(try reopened.loadReport(systemID: "sys-1"))
        #expect(loaded.entries.count == 3)
    }
}
