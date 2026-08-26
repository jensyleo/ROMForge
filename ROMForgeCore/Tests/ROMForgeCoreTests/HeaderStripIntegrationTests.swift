// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// End-to-end test of the header-strip path, real bytes on disk all the
/// way through to a final `AuditEntry` — `ROMMatcher.swift`'s own doc
/// comment on `matchedViaHeaderStrip` admits this was "not yet verified
/// live... none of NES/Lynx/SNES/Game Boy/PC Engine/Master System/Genesis
/// were available to test this session." Every existing test either
/// exercises `HeaderSkipRule.headerLength` alone (`HeaderSkipRuleTests`) or
/// hand-constructs a `HashedFile` with `headerStripped` already populated
/// (`ROMMatcherTests`) — neither proves a real headered file on disk
/// actually flows through `FileHasher` → `ROMMatcher.match` →
/// `AuditReporter.generate` and comes out the other end `.correct` with
/// `matchedViaHeaderStrip == true`. 2026-08-13, "todos los escenarios
/// posibles" pass.
@Suite("Header strip integration")
struct HeaderStripIntegrationTests {
    private func tempFile(named name: String, contents: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    @Test("a real iNES-headered NES dump matches a headerless DAT rom end-to-end, flagged matchedViaHeaderStrip")
    func iNESHeaderedFileMatchesHeaderlessDATEntryEndToEnd() async throws {
        let payload = Data((0..<256).map { UInt8($0 % 256) })
        var headered = Data([0x4E, 0x45, 0x53, 0x1A]) // "NES\x1A"
        headered.append(Data(repeating: 0, count: 12)) // pad to the full 16-byte iNES header
        headered.append(payload)
        // Named exactly as the DAT expects — a headered dump that's
        // otherwise correctly organized. `ROMMatcher` classifies by name
        // AND hash together: right hash but a DIFFERENT filename would
        // come back `.misnamed` (`.incorrect`), not `.correct` — that's a
        // real, distinct outcome, not what this test is proving.
        let url = try tempFile(named: "Some Game.nes", contents: headered)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let scanned = ScannedFile(url: url, name: url.lastPathComponent, size: Int64(headered.count))
        let hashedFiles = try await FileHasher.hash(files: [scanned])
        let hashedFile = try #require(hashedFiles.first)
        let strippedHash = try #require(hashedFile.headerStripped)
        #expect(strippedHash.rule == .iNES)

        // The DAT declares the payload's own (headerless) hash — exactly
        // what a real No-Intro DAT expects for this rom.
        let expectedHeaderlessHash = FileHasher.hash(data: payload)
        let rom = DATRom(name: "Some Game.nes", size: Int64(payload.count), crc: expectedHeaderlessHash.crc32, md5: expectedHeaderlessHash.md5, sha1: expectedHeaderlessHash.sha1)
        let game = DATGame(name: "somegame", description: "Some Game", cloneOf: nil, romOf: nil, roms: [rom])
        let dat = DATFile(header: DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge"), games: [game])

        let matchReport = try ROMMatcher.match(dat: dat, hashedFiles: hashedFiles)
        let report = try AuditReporter.generate(from: matchReport)

        let entry = try #require(report.entries.first)
        #expect(entry.status == .correct)
        #expect(entry.matchedViaHeaderStrip == true)
        #expect(report.correct == 1)
        #expect(report.missing == 0)
    }

    @Test("a real 512-byte copier-headered file (SNES/GB/PCE/SMS convention) matches end-to-end the same way")
    func copier512HeaderedFileMatchesEndToEnd() async throws {
        // Detected purely by size (real payload a round multiple of 1024,
        // file size mod 1024 == 512) — no magic bytes needed.
        let payload = Data(repeating: 0x5A, count: 1024)
        var headered = Data(repeating: 0xFF, count: 512)
        headered.append(payload)
        let url = try tempFile(named: "Some SNES Game.sfc", contents: headered)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let scanned = ScannedFile(url: url, name: url.lastPathComponent, size: Int64(headered.count))
        let hashedFiles = try await FileHasher.hash(files: [scanned])
        let strippedHash = try #require(hashedFiles.first?.headerStripped)
        #expect(strippedHash.rule == .copier512)

        let expectedHeaderlessHash = FileHasher.hash(data: payload)
        let rom = DATRom(name: "Some SNES Game.sfc", size: Int64(payload.count), crc: expectedHeaderlessHash.crc32, md5: expectedHeaderlessHash.md5, sha1: expectedHeaderlessHash.sha1)
        let game = DATGame(name: "somesnesgame", description: "Some SNES Game", cloneOf: nil, romOf: nil, roms: [rom])
        let dat = DATFile(header: DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge"), games: [game])

        let matchReport = try ROMMatcher.match(dat: dat, hashedFiles: hashedFiles)
        let report = try AuditReporter.generate(from: matchReport)

        let entry = try #require(report.entries.first)
        #expect(entry.status == .correct)
        #expect(entry.matchedViaHeaderStrip == true)
    }

    @Test("a headered file with no matching headerless DAT entry still reports missing, not a false match")
    func headeredFileWithNoDATMatchStillReportsMissing() async throws {
        var headered = Data([0x4E, 0x45, 0x53, 0x1A])
        headered.append(Data(repeating: 0, count: 12))
        headered.append(Data(repeating: 0x01, count: 256))
        let url = try tempFile(named: "unrelated.nes", contents: headered)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let scanned = ScannedFile(url: url, name: url.lastPathComponent, size: Int64(headered.count))
        let hashedFiles = try await FileHasher.hash(files: [scanned])

        let rom = DATRom(name: "Some Game.nes", size: 256, crc: "deadbeef", md5: nil, sha1: nil)
        let game = DATGame(name: "somegame", description: "Some Game", cloneOf: nil, romOf: nil, roms: [rom])
        let dat = DATFile(header: DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge"), games: [game])

        let matchReport = try ROMMatcher.match(dat: dat, hashedFiles: hashedFiles)
        let report = try AuditReporter.generate(from: matchReport)

        #expect(report.missing == 1)
        #expect(report.correct == 0)
    }
}
