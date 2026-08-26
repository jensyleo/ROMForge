// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

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

    @Test("re-opening the same database file preserves previously saved data")
    func persistsAcrossReopens() throws {
        let path = tempDBPath()
        try AuditReportDatabase(path: path).saveReport(sampleReport(), systemID: "sys-1", datName: "A", datVersion: "1", scannedAt: Date())

        let reopened = try AuditReportDatabase(path: path)
        let loaded = try #require(try reopened.loadReport(systemID: "sys-1"))
        #expect(loaded.entries.count == 3)
    }
}
