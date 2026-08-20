// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("OrphanedBIOSDetector")
struct OrphanedBIOSDetectorTests {
    private func biosEntry(game: String, status: AuditStatus = .correct, path: String? = "/roms/neogeo.zip") -> AuditEntry {
        AuditEntry(status: status, game: game, gameDescription: game, isBios: true, name: "\(game).zip", path: path.map(URL.init(fileURLWithPath:)))
    }

    private func gameEntry(game: String, requiredBiosNames: String?, path: String? = "/roms/game.zip") -> AuditEntry {
        AuditEntry(status: .correct, game: game, gameDescription: game, requiredBiosNames: requiredBiosNames, name: "\(game).zip", path: path.map(URL.init(fileURLWithPath:)))
    }

    @Test("a present BIOS no present game requires is flagged orphaned")
    func flagsOrphanedBIOS() {
        let report = AuditReport(entries: [biosEntry(game: "neogeo")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.first?.isOrphanedBios == true)
    }

    @Test("a present BIOS required by a present game is not flagged")
    func doesNotFlagBIOSInUse() {
        let report = AuditReport(
            entries: [biosEntry(game: "neogeo"), gameEntry(game: "mslug", requiredBiosNames: "neogeo")],
            correct: 2, incorrect: 0, missing: 0, surplus: 0
        )

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.first { $0.isBios }?.isOrphanedBios == false)
    }

    @Test("a BIOS required only by an entirely-missing (not physically present) game is still flagged orphaned")
    func flagsBIOSWhoseOnlyDependentGameIsMissing() {
        let missingGame = AuditEntry(status: .missing, game: "mslug", requiredBiosNames: "neogeo", name: "mslug.zip", path: nil)
        let report = AuditReport(entries: [biosEntry(game: "neogeo"), missingGame], correct: 1, incorrect: 0, missing: 1, surplus: 0)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.first { $0.isBios }?.isOrphanedBios == true)
    }

    @Test("a BIOS with no local file at all is never flagged — nothing physically wasted to report")
    func doesNotFlagAbsentBIOS() {
        let absentBios = biosEntry(game: "neogeo", status: .missing, path: nil)
        let report = AuditReport(entries: [absentBios], correct: 0, incorrect: 0, missing: 1, surplus: 0)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.first?.isOrphanedBios == false)
    }

    @Test("a non-BIOS entry is never flagged, even if somehow unreferenced")
    func neverFlagsNonBiosEntries() {
        let report = AuditReport(entries: [gameEntry(game: "mslug", requiredBiosNames: nil)], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.allSatisfy { !$0.isOrphanedBios })
    }

    @Test("multiple BIOS names on one dependent game's comma-joined list all count as in-use")
    func handlesCommaJoinedMultipleBiosNames() {
        let report = AuditReport(
            entries: [
                biosEntry(game: "neogeo"), biosEntry(game: "decocass", path: "/roms/decocass.zip"),
                gameEntry(game: "mslug", requiredBiosNames: "neogeo, decocass"),
            ],
            correct: 3, incorrect: 0, missing: 0, surplus: 0
        )

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.filter(\.isBios).allSatisfy { !$0.isOrphanedBios })
    }

    @Test("a report with no BIOS rows at all is returned unchanged")
    func noOpWhenNoBiosPresent() {
        let report = AuditReport(entries: [gameEntry(game: "pacman", requiredBiosNames: nil)], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.entries.count == 1)
        #expect(!result.entries[0].isOrphanedBios)
    }

    @Test("flagging never changes the report's own status counts")
    func doesNotChangeCounts() {
        let report = AuditReport(entries: [biosEntry(game: "neogeo")], correct: 1, incorrect: 2, badDump: 3, missing: 4, surplus: 5, unverifiable: 6, duplicateSets: 7)

        let result = OrphanedBIOSDetector.markingOrphaned(in: report)

        #expect(result.correct == 1 && result.incorrect == 2 && result.badDump == 3 && result.missing == 4)
        #expect(result.surplus == 5 && result.unverifiable == 6 && result.duplicateSets == 7)
    }

    @Test("AuditReporter.markingOrphanedBIOS wires straight through to the detector")
    func auditReporterWiring() {
        let report = AuditReport(entries: [biosEntry(game: "neogeo")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = AuditReporter.markingOrphanedBIOS(in: report)

        #expect(result.entries.first?.isOrphanedBios == true)
    }

    @Test("DatabaseCategory.unusedBiosFiles filters down to only orphaned entries")
    func databaseCategoryFiltersOnFlag() {
        let orphaned = biosEntry(game: "neogeo")
        let inUseBios = biosEntry(game: "decocass", path: "/roms/decocass.zip")
        let dependent = gameEntry(game: "mslug", requiredBiosNames: "decocass")
        let flagged = OrphanedBIOSDetector.markingOrphaned(
            in: AuditReport(entries: [orphaned, inUseBios, dependent], correct: 3, incorrect: 0, missing: 0, surplus: 0)
        )

        let filtered = DatabaseCategory.unusedBiosFiles.apply(to: flagged.entries)

        #expect(filtered.count == 1)
        #expect(filtered.first?.game == "neogeo")
    }
}
