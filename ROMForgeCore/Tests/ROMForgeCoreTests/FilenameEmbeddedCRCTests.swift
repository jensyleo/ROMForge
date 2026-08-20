// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("FilenameEmbeddedCRC")
struct FilenameEmbeddedCRCTests {
    @Test("detects an 8-hex-digit CRC in square brackets")
    func detectsBracketedCRC() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Sonic The Hedgehog [12AB34CD].zip") == "12ab34cd")
    }

    @Test("detects an 8-hex-digit CRC in parentheses")
    func detectsParenthesizedCRC() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Sonic The Hedgehog (12AB34CD).bin") == "12ab34cd")
    }

    @Test("lowercases the returned CRC regardless of the filename's own casing")
    func alwaysLowercases() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Foo (deadbeef).zip") == "deadbeef")
    }

    @Test("region tag alone is never mistaken for a CRC")
    func regionTagNotMistakenForCRC() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Sonic The Hedgehog (USA).zip") == nil)
    }

    @Test("a 7-character near-miss inside brackets is not treated as a CRC")
    func rejectsWrongLength() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Foo [1AB34CD].zip") == nil)
    }

    @Test("a non-hex 8-character group is not treated as a CRC")
    func rejectsNonHex() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Foo [GGGGGGGG].zip") == nil)
    }

    @Test("a plain filename with no bracketed group at all returns nil")
    func noGroupsAtAll() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Sonic The Hedgehog.zip") == nil)
    }

    @Test("the first valid 8-hex group wins when several parenthesized groups are present")
    func firstValidGroupWins() {
        #expect(FilenameEmbeddedCRC.embeddedCRC32(inFileName: "Foo (USA) [12AB34CD] (M3).zip") == "12ab34cd")
    }
}

@Suite("FilenameCRCVerifier")
struct FilenameCRCVerifierTests {
    private func entry(path: String, actualCRC: String?) -> AuditEntry {
        AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: URL(fileURLWithPath: path), actualCRC: actualCRC)
    }

    @Test("flags an entry whose embedded filename CRC disagrees with its actual hash")
    func flagsMismatch() {
        let report = AuditReport(entries: [entry(path: "/roms/Foo [12AB34CD].zip", actualCRC: "deadbeef")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == true)
    }

    @Test("does not flag an entry whose embedded filename CRC agrees with its actual hash")
    func doesNotFlagAgreement() {
        let report = AuditReport(entries: [entry(path: "/roms/Foo [12AB34CD].zip", actualCRC: "12AB34CD")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == false)
    }

    @Test("case-insensitive comparison — differently-cased hex still counts as agreement")
    func caseInsensitiveComparison() {
        let report = AuditReport(entries: [entry(path: "/roms/Foo [DEADBEEF].zip", actualCRC: "deadbeef")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == false)
    }

    @Test("a filename with no embedded CRC at all is never flagged")
    func noEmbeddedCRCNeverFlagged() {
        let report = AuditReport(entries: [entry(path: "/roms/Foo.zip", actualCRC: "deadbeef")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == false)
    }

    @Test("an entry with no path (a missing rom) is never flagged")
    func noPathNeverFlagged() {
        let missing = AuditEntry(status: .missing, game: "foo", name: "foo.bin", path: nil)
        let report = AuditReport(entries: [missing], correct: 0, incorrect: 0, missing: 1, surplus: 0)

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == false)
    }

    @Test("flagging never changes the report's own status counts")
    func doesNotChangeCounts() {
        let report = AuditReport(
            entries: [entry(path: "/roms/Foo [12AB34CD].zip", actualCRC: "deadbeef")],
            correct: 1, incorrect: 2, badDump: 3, missing: 4, surplus: 5, unverifiable: 6, duplicateSets: 7
        )

        let result = FilenameCRCVerifier.markingMismatches(in: report)

        #expect(result.correct == 1 && result.incorrect == 2 && result.badDump == 3 && result.missing == 4)
        #expect(result.surplus == 5 && result.unverifiable == 6 && result.duplicateSets == 7)
    }

    @Test("AuditReporter.markingFilenameCRCMismatches wires straight through to the verifier")
    func auditReporterWiring() {
        let report = AuditReport(entries: [entry(path: "/roms/Foo [12AB34CD].zip", actualCRC: "deadbeef")], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = AuditReporter.markingFilenameCRCMismatches(in: report)

        #expect(result.entries.first?.hasFilenameCRCMismatch == true)
    }

    @Test("DatabaseCategory.filenameCRCMismatches filters down to only flagged entries")
    func databaseCategoryFiltersOnFlag() {
        let mismatched = entry(path: "/roms/Foo [12AB34CD].zip", actualCRC: "deadbeef")
        let clean = entry(path: "/roms/Bar [DEADBEEF].zip", actualCRC: "deadbeef")
        let flagged = FilenameCRCVerifier.markingMismatches(in: AuditReport(entries: [mismatched, clean], correct: 2, incorrect: 0, missing: 0, surplus: 0))

        let filtered = DatabaseCategory.filenameCRCMismatches.apply(to: flagged.entries)

        #expect(filtered.count == 1)
    }
}
