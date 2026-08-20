// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("DuplicateSetDetector")
struct DuplicateSetDetectorTests {
    private func correctEntry(game: String, path: String) -> AuditEntry {
        AuditEntry(status: .correct, game: game, gameDescription: game, name: "\(game).zip", path: URL(fileURLWithPath: path))
    }

    private func incorrectEntry(game: String, path: String) -> AuditEntry {
        AuditEntry(status: .incorrect, game: game, gameDescription: game, name: "\(game).zip", path: URL(fileURLWithPath: path))
    }

    @Test("a game whose set is present under two distinct root folders is flagged")
    func flagsCrossFolderDuplicate() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let report = AuditReport(
            entries: [
                correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"),
                correctEntry(game: "sf2", path: "/roms/folderB/sf2.zip"),
            ],
            correct: 2, incorrect: 0, missing: 0, surplus: 0
        )

        let duplicates = DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB])

        #expect(duplicates.count == 1)
        let duplicate = try! #require(duplicates.first)
        #expect(duplicate.status == .duplicateSet)
        #expect(duplicate.game == "sf2")
        // The FIRST configured folder always wins as "primary" — same
        // "earliest folder owns it" rule `ROMMatcher.uniqued` already
        // guarantees for which physical copy `ROMMatcher` itself claims.
        #expect(duplicate.duplicateSetPrimaryPath == URL(fileURLWithPath: "/roms/folderA/sf2.zip"))
        #expect(duplicate.path == URL(fileURLWithPath: "/roms/folderB/sf2.zip"))
    }

    @Test("primary folder is always the earliest configured one, regardless of entry order")
    func primaryFolderIsEarliestConfiguredRegardlessOfEntryOrder() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        // Entries deliberately listed with folder B's copy first — the
        // detector must still pick folder A as primary, since that's the
        // one configured first, not whichever happened to be scanned/
        // listed first.
        let report = AuditReport(
            entries: [
                correctEntry(game: "sf2", path: "/roms/folderB/sf2.zip"),
                correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"),
            ],
            correct: 2, incorrect: 0, missing: 0, surplus: 0
        )

        let duplicates = DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB])

        #expect(duplicates.count == 1)
        #expect(duplicates.first?.duplicateSetPrimaryPath == URL(fileURLWithPath: "/roms/folderA/sf2.zip"))
        #expect(duplicates.first?.path == URL(fileURLWithPath: "/roms/folderB/sf2.zip"))
    }

    @Test("a same-named archive duplicated inside ONE folder (BATOCERA-style subfolder) is not flagged")
    func doesNotFlagDuplicatesWithinTheSameRootFolder() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let report = AuditReport(
            entries: [
                correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"),
                // A second physical copy nested inside folder A's own
                // subtree, not a distinct configured root folder at all.
                incorrectEntry(game: "sf2", path: "/roms/folderA/BATOCERA/sf2.zip"),
            ],
            correct: 1, incorrect: 1, missing: 0, surplus: 0
        )

        let duplicates = DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB])

        #expect(duplicates.isEmpty)
    }

    @Test("a single configured root folder never produces duplicates, even with multiple matching paths")
    func singleRootFolderNeverFlagsDuplicates() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let report = AuditReport(
            entries: [
                correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"),
                incorrectEntry(game: "sf2", path: "/roms/folderA/dupe/sf2.zip"),
            ],
            correct: 1, incorrect: 1, missing: 0, surplus: 0
        )

        #expect(DuplicateSetDetector.detect(in: report, rootFolders: [folderA]).isEmpty)
    }

    @Test("a game present in only one folder is never flagged")
    func doesNotFlagAGameOwnedByOnlyOneFolder() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let report = AuditReport(
            entries: [correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip")],
            correct: 1, incorrect: 0, missing: 0, surplus: 0
        )

        #expect(DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB]).isEmpty)
    }

    @Test("surplus/missing/disk entries never seed a duplicate detection")
    func ignoresSurplusMissingAndDiskEntries() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let missingEntry = AuditEntry(status: .missing, game: "sf2", name: "missing.bin", path: nil)
        let surplusEntry = AuditEntry(status: .unknownFile, game: nil, name: "junk.txt", path: URL(fileURLWithPath: "/roms/folderB/junk.txt"))
        let diskEntry = AuditEntry(status: .correct, game: "sf2", isDisk: true, name: "sf2.chd", path: URL(fileURLWithPath: "/roms/folderB/sf2.chd"))
        let report = AuditReport(
            entries: [correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"), missingEntry, surplusEntry, diskEntry],
            correct: 2, incorrect: 0, missing: 1, surplus: 1
        )

        #expect(DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB]).isEmpty)
    }

    @Test("multiple roms belonging to the same duplicated game collapse into one row per extra folder")
    func collapsesMultipleRomsIntoOneRowPerFolder() {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let report = AuditReport(
            entries: [
                AuditEntry(status: .correct, game: "sf2", name: "rom1.bin", path: URL(fileURLWithPath: "/roms/folderA/sf2.zip")),
                AuditEntry(status: .correct, game: "sf2", name: "rom2.bin", path: URL(fileURLWithPath: "/roms/folderA/sf2.zip")),
                AuditEntry(status: .correct, game: "sf2", name: "rom1.bin", path: URL(fileURLWithPath: "/roms/folderB/sf2.zip")),
                AuditEntry(status: .correct, game: "sf2", name: "rom2.bin", path: URL(fileURLWithPath: "/roms/folderB/sf2.zip")),
            ],
            correct: 4, incorrect: 0, missing: 0, surplus: 0
        )

        #expect(DuplicateSetDetector.detect(in: report, rootFolders: [folderA, folderB]).count == 1)
    }

    @Test("AuditReporter.addingDuplicateSets appends the rows and bumps duplicateSets, leaving other counts untouched")
    func addingDuplicateSetsWiresIntoAuditReporter() throws {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let folderB = URL(fileURLWithPath: "/roms/folderB")
        let report = AuditReport(
            entries: [
                correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip"),
                correctEntry(game: "sf2", path: "/roms/folderB/sf2.zip"),
            ],
            correct: 2, incorrect: 0, missing: 0, surplus: 0
        )

        let result = try AuditReporter.addingDuplicateSets(to: report, rootFolders: [folderA, folderB])

        #expect(result.entries.count == 3)
        #expect(result.duplicateSets == 1)
        #expect(result.correct == 2)
        #expect(result.entries.filter { $0.status == .duplicateSet }.count == 1)
    }

    @Test("addingDuplicateSets is a no-op for a single-folder system")
    func addingDuplicateSetsNoOpForSingleFolder() throws {
        let folderA = URL(fileURLWithPath: "/roms/folderA")
        let report = AuditReport(entries: [correctEntry(game: "sf2", path: "/roms/folderA/sf2.zip")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = try AuditReporter.addingDuplicateSets(to: report, rootFolders: [folderA])

        #expect(result.entries.count == 1)
        #expect(result.duplicateSets == 0)
    }

    @Test("AuditStatus.worst(among:) never lets a duplicateSet row drag a correct game down")
    func duplicateSetDoesNotAffectWorstStatus() {
        #expect(AuditStatus.worst(among: [.correct, .duplicateSet]) == .correct)
        #expect(AuditStatus.worst(among: [.duplicateSet]) == .correct)
    }
}
