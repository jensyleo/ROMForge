// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("ZipArchive")
struct ZipArchiveTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("scans entries and hashes their decompressed content")
    func scansAndHashesEntries() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data("123456789".utf8)
        let loosePath = root.appendingPathComponent("game.bin")
        try payload.write(to: loosePath)

        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: loosePath, compressionMethod: .deflate)

        let entries = try ZipArchiveScanner.scan(archive: archiveURL)
        #expect(entries.count == 1)
        #expect(entries[0].name == "game.bin")
        #expect(entries[0].size == Int64(payload.count))

        let (hash, headerStripped) = try ZipArchiveHasher.hash(entries[0])
        #expect(hash.crc32 == "cbf43926")
        #expect(hash.sha1 == "f7c3bc1d808e04732adf679965ccc34ca7ae3441")
        #expect(headerStripped == nil, "plain content with no known header signature")
    }

    @Test("crc32-only mode reads the zip's own stored checksum instead of decompressing the entry")
    func crc32OnlyReadsStoredChecksumWithoutDecompressing() throws {
        // Real user-reported case (2026-07-24): leaving only CRC32 enabled
        // for speed didn't actually make a scan of compressed archives any
        // faster, because every enabled algorithm's `update()` still needs
        // every decompressed byte — so the expensive part (DEFLATE
        // decompression) ran in full regardless. The ZIP format already
        // stores each entry's CRC32 in its own central directory record;
        // this confirms the crc32-only fast path reads the exact same
        // value a full decompression+hash would have computed, and that it
        // correctly gives up md5/sha1/headerStripped rather than guessing.
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data("123456789".utf8)
        let loosePath = root.appendingPathComponent("game.bin")
        try payload.write(to: loosePath)

        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: loosePath, compressionMethod: .deflate)

        let entries = try ZipArchiveScanner.scan(archive: archiveURL)
        let (hash, headerStripped) = try ZipArchiveHasher.hash(entries[0], algorithms: .crc32)
        #expect(hash.crc32 == "cbf43926", "must match what full decompression+hashing computes for the same content")
        #expect(hash.md5 == nil)
        #expect(hash.sha1 == nil)
        #expect(headerStripped == nil, "the fast path never reads bytes, so it can't attempt header-stripped matching")
    }

    @Test("crc32-only mode still fully decompresses a Genesis-SMD entry, since deinterleaving needs the real bytes")
    func crc32OnlyStillDecompressesSMDEntries() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A real (if tiny) interleaved SMD file: `GenesisSMDConverter
        // .isSMDInterleaved` keys off filename suffix + a specific size
        // convention — reusing whatever real fixture its own tests use
        // would be ideal, but this only needs to confirm the crc32-only
        // fast path backs off for `.smd`, not re-verify deinterleaving
        // itself (covered by `GenesisSMDConverterTests`).
        let payload = Data(repeating: 0xAB, count: 16384) // a plain, non-SMD-shaped payload is fine here
        let loosePath = root.appendingPathComponent("game.smd")
        try payload.write(to: loosePath)

        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.smd", fileURL: loosePath, compressionMethod: .deflate)

        let entries = try ZipArchiveScanner.scan(archive: archiveURL)
        let (hash, _) = try ZipArchiveHasher.hash(entries[0], algorithms: .crc32)
        // Not the zip-stored checksum shortcut's job to prove SMD
        // deinterleaving is correct — just that it didn't take the
        // shortcut and skip real decompression for this filename.
        #expect(hash.crc32 != nil)
    }

    @Test("detects a header-stripped identity for a headered entry inside a zip")
    func detectsHeaderStrippedHashInsideZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameData = Data("this is the actual nes game data".utf8)
        var headeredFile = Data([0x4E, 0x45, 0x53, 0x1A]) // "NES\x1A"
        headeredFile.append(Data(repeating: 0, count: 12)) // pad to a 16-byte header
        headeredFile.append(gameData)

        let loosePath = root.appendingPathComponent("game.nes")
        try headeredFile.write(to: loosePath)

        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.nes", fileURL: loosePath, compressionMethod: .deflate)

        let entries = try ZipArchiveScanner.scan(archive: archiveURL)
        let (_, headerStripped) = try ZipArchiveHasher.hash(entries[0])

        let stripped = try #require(headerStripped)
        #expect(stripped.rule == .iNES)
        #expect(stripped.size == Int64(gameData.count))
        #expect(stripped.hash == FileHasher.hash(data: gameData))
    }

    @Test("aborts extraction when an entry's real decompressed size wildly exceeds its declared size (zip-bomb guard)")
    func abortsOnSuspectedZipBomb() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Highly-compressible real payload, deliberately much larger than
        // the "declared size" ArchivedFile will lie about below (a zip's
        // own central directory size field is exactly what an attacker
        // would falsify — ZipArchiveHasher can't trust it as a hard cap).
        let payload = Data(repeating: 0x41, count: 5_000_000)
        let loosePath = root.appendingPathComponent("bomb.bin")
        try payload.write(to: loosePath)

        let archiveURL = root.appendingPathComponent("Bomb.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "bomb.bin", fileURL: loosePath, compressionMethod: .deflate)

        let realEntries = try ZipArchiveScanner.scan(archive: archiveURL)
        let lyingEntry = ArchivedFile(archiveURL: archiveURL, entryPath: realEntries[0].entryPath, name: realEntries[0].name, size: 10)

        #expect(throws: ZipArchiveError.suspectedZipBomb(entryPath: lyingEntry.entryPath, declaredSize: 10)) {
            _ = try ZipArchiveHasher.hash(lyingEntry)
        }
    }

    @Test("throws when the archive does not exist")
    func throwsWhenArchiveMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: ZipArchiveError.cannotOpenArchive(missing)) {
            try ZipArchiveScanner.scan(archive: missing)
        }
    }

    @Test("createArchive operation packs loose files into a new zip")
    func createArchiveOperationPacksFiles() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("loose.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Rebuilt/Game.zip")

        try RebuildExecutor.execute([
            .createArchive(entries: [ArchiveEntrySource(source: source, entryName: "expected.bin")], to: destination),
        ])

        #expect(FileManager.default.fileExists(atPath: destination.path))
        let entries = try ZipArchiveScanner.scan(archive: destination)
        #expect(entries.map(\.name) == ["expected.bin"])
    }

    @Test("createArchive refuses to overwrite an existing destination")
    func createArchiveRefusesToOverwrite() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("loose.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Game.zip")
        try Data("not a zip".utf8).write(to: destination)

        #expect(throws: RebuildError.destinationExists(destination)) {
            try RebuildExecutor.execute([
                .createArchive(entries: [ArchiveEntrySource(source: source, entryName: "expected.bin")], to: destination),
            ])
        }
    }
}
