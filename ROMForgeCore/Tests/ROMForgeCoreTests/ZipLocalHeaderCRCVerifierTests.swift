// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("ZipLocalHeaderCRCVerifier")
struct ZipLocalHeaderCRCVerifierTests {
    private func makeTempZip(entries: [TorrentZipEntry]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try TorrentZipWriter.write(entries, to: url)
        return url
    }

    /// `TorrentZipWriter` always writes a matching local-header CRC32 (bytes
    /// 14...17 of the very first local header, which starts at file offset 0
    /// since this is a single-entry archive) — flipping one bit there,
    /// without touching the central directory at the end, is exactly the
    /// "something edited one copy and not the other" scenario this checker
    /// exists to catch.
    private func corruptLocalHeaderCRC(at url: URL) throws {
        var data = try Data(contentsOf: url)
        let crcOffset = 14
        data[crcOffset] = data[crcOffset] ^ 0xFF
        try data.write(to: url)
    }

    @Test("an untouched TorrentZip archive's local and central CRCs agree")
    func agreesForUnmodifiedArchive() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }

        let results = try ZipLocalHeaderCRCVerifier.verify(url)

        #expect(results.count == 1)
        #expect(results.first?.matches == true)
    }

    @Test("a local header CRC hand-corrupted independently of the central directory is flagged as a mismatch")
    func flagsCorruptedLocalHeader() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }
        try corruptLocalHeaderCRC(at: url)

        let results = try ZipLocalHeaderCRCVerifier.verify(url)

        #expect(results.count == 1)
        #expect(results.first?.matches == false)
    }

    @Test("a multi-entry archive only flags the one entry whose local header was corrupted")
    func flagsOnlyTheCorruptedEntry() throws {
        let url = try makeTempZip(entries: [
            TorrentZipEntry(name: "a.bin", data: Data([1, 2, 3, 4])),
            TorrentZipEntry(name: "b.bin", data: Data([5, 6, 7, 8, 9])),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        // TorrentZip sorts entries by lowercased name, so "a.bin" is still
        // the very first local header (file offset 0) after normalization.
        try corruptLocalHeaderCRC(at: url)

        let results = try ZipLocalHeaderCRCVerifier.verify(url)

        #expect(results.count == 2)
        #expect(results.first { $0.entryName == "a.bin" }?.matches == false)
        #expect(results.first { $0.entryName == "b.bin" }?.matches == true)
    }

    @Test("throws for a path that isn't a real file")
    func throwsForMissingFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        #expect(throws: ZipLocalHeaderCRCVerifierError.self) {
            try ZipLocalHeaderCRCVerifier.verify(url)
        }
    }
}

@Suite("ZipIntegrityAuditor")
struct ZipIntegrityAuditorTests {
    private func makeTempZip(entries: [TorrentZipEntry]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try TorrentZipWriter.write(entries, to: url)
        return url
    }

    private func corruptLocalHeaderCRC(at url: URL) throws {
        var data = try Data(contentsOf: url)
        data[14] = data[14] ^ 0xFF
        try data.write(to: url)
    }

    @Test("flags the AuditEntry matching a corrupted zip entry by name")
    func flagsMatchingEntry() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }
        try corruptLocalHeaderCRC(at: url)

        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: url)
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = ZipIntegrityAuditor.verifyingIntegrity(in: report)

        #expect(result.entries.first?.hasInternalZipCRCMismatch == true)
    }

    @Test("does not flag an entry from an untouched archive")
    func doesNotFlagCleanArchive() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }

        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: url)
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = ZipIntegrityAuditor.verifyingIntegrity(in: report)

        #expect(result.entries.first?.hasInternalZipCRCMismatch == false)
    }

    @Test("a non-zip path (e.g. a loose file) is never checked or flagged")
    func ignoresNonZipPaths() {
        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: URL(fileURLWithPath: "/roms/foo.bin"))
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = ZipIntegrityAuditor.verifyingIntegrity(in: report)

        #expect(result.entries.first?.hasInternalZipCRCMismatch == false)
    }

    @Test("an unreadable/nonexistent archive path is skipped without throwing")
    func skipsUnreadableArchive() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: missingURL)
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = ZipIntegrityAuditor.verifyingIntegrity(in: report)

        #expect(result.entries.first?.hasInternalZipCRCMismatch == false)
    }

    @Test("flagging never changes the report's own status counts")
    func doesNotChangeCounts() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }
        try corruptLocalHeaderCRC(at: url)
        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: url)
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 2, badDump: 3, missing: 4, surplus: 5, unverifiable: 6, duplicateSets: 7)

        let result = ZipIntegrityAuditor.verifyingIntegrity(in: report)

        #expect(result.correct == 1 && result.incorrect == 2 && result.badDump == 3 && result.missing == 4)
        #expect(result.surplus == 5 && result.unverifiable == 6 && result.duplicateSets == 7)
    }

    @Test("AuditReporter.verifyingZipIntegrity wires straight through to the auditor")
    func auditReporterWiring() throws {
        let url = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: url) }
        try corruptLocalHeaderCRC(at: url)
        let entry = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: url)
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = AuditReporter.verifyingZipIntegrity(in: report)

        #expect(result.entries.first?.hasInternalZipCRCMismatch == true)
    }

    @Test("DatabaseCategory.zipCRCInconsistencies filters down to only flagged entries")
    func databaseCategoryFiltersOnFlag() throws {
        let corruptURL = try makeTempZip(entries: [TorrentZipEntry(name: "foo.bin", data: Data([1, 2, 3, 4]))])
        defer { try? FileManager.default.removeItem(at: corruptURL) }
        try corruptLocalHeaderCRC(at: corruptURL)
        let cleanURL = try makeTempZip(entries: [TorrentZipEntry(name: "bar.bin", data: Data([5, 6, 7, 8]))])
        defer { try? FileManager.default.removeItem(at: cleanURL) }

        let corrupt = AuditEntry(status: .correct, game: "foo", name: "foo.bin", path: corruptURL)
        let clean = AuditEntry(status: .correct, game: "bar", name: "bar.bin", path: cleanURL)
        let flagged = ZipIntegrityAuditor.verifyingIntegrity(in: AuditReport(entries: [corrupt, clean], correct: 2, incorrect: 0, missing: 0, surplus: 0))

        let filtered = DatabaseCategory.zipCRCInconsistencies.apply(to: flagged.entries)

        #expect(filtered.count == 1)
        #expect(filtered.first?.game == "foo")
    }
}
