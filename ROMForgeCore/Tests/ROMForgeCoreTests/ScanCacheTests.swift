// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("ScanCache")
struct ScanCacheTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("build(from:) round-trips a hit for an unchanged file")
    func buildAndLookupRoundTrips() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let file = ScannedFile(url: URL(fileURLWithPath: "/tmp/game.bin"), name: "game.bin", size: 4, modificationDate: mtime)
        let hashedFile = HashedFile(file: file, hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let cache = ScanCache.build(from: [hashedFile])
        let hit = cache.lookup(for: file)

        #expect(hit == hashedFile)
    }

    @Test("a size or mtime mismatch is a cache miss")
    func mismatchIsAMiss() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let file = ScannedFile(url: URL(fileURLWithPath: "/tmp/game.bin"), name: "game.bin", size: 4, modificationDate: mtime)
        let cache = ScanCache.build(from: [HashedFile(file: file, hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))])

        let changedSize = ScannedFile(url: file.url, name: file.name, size: 5, modificationDate: mtime)
        #expect(cache.lookup(for: changedSize) == nil)

        let changedMTime = ScannedFile(url: file.url, name: file.name, size: 4, modificationDate: Date(timeIntervalSince1970: 2_000_000))
        #expect(cache.lookup(for: changedMTime) == nil)
    }

    @Test("a cache entry missing an algorithm the caller now wants is a miss, even if size/mtime still match")
    func missingAlgorithmIsAMiss() {
        let mtime = Date(timeIntervalSince1970: 1_000_000)
        let file = ScannedFile(url: URL(fileURLWithPath: "/tmp/game.bin"), name: "game.bin", size: 4, modificationDate: mtime)
        // Built as if only CRC32 was enabled when this was cached.
        let cache = ScanCache.build(from: [HashedFile(file: file, hash: FileHash(crc32: "aaaaaaaa", md5: nil, sha1: nil))])

        #expect(cache.lookup(for: file, algorithms: .crc32) != nil, "still a hit for the algorithm it actually has")
        #expect(cache.lookup(for: file, algorithms: [.crc32, .md5]) == nil, "a miss — md5 was never computed for this entry")
        #expect(cache.lookup(for: file, algorithms: .all) == nil, "a miss — neither md5 nor sha1 were ever computed for this entry")
    }

    @Test("a zip entry's key combines the archive path and entry name, distinct from the archive's own key")
    func zipEntryKeyIsComposite() {
        let archiveURL = URL(fileURLWithPath: "/tmp/Game.zip")
        let entry = ScannedFile(url: archiveURL, name: "rom.bin", size: 4, modificationDate: Date(timeIntervalSince1970: 1))
        let looseArchiveItself = ScannedFile(url: archiveURL, name: "Game.zip", size: 4, modificationDate: Date(timeIntervalSince1970: 1))

        #expect(ScanCache.key(for: entry) == "/tmp/Game.zip::rom.bin")
        #expect(ScanCache.key(for: looseArchiveItself) == "/tmp/Game.zip")
    }

    @Test("FileHasher.hash(files:cache:) uses the cached hash instead of rehashing, for both the single-file and concurrent paths")
    func fileHasherUsesCacheInstead() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("game.bin")
        try Data("real content".utf8).write(to: url)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = attrs[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let size = Int64(attrs[.size] as? Int ?? 0)

        let file = ScannedFile(url: url, name: "game.bin", size: size, modificationDate: mtime)
        // A deliberately wrong hash — if the real content got rehashed, this wouldn't come back.
        let staleButValidHash = FileHash(crc32: "deadbeef", md5: "stale", sha1: "stale")
        let cache = ScanCache.build(from: [HashedFile(file: file, hash: staleButValidHash)])

        let singleResult = try await FileHasher.hash(files: [file], cache: cache)
        #expect(singleResult.first?.hash == staleButValidHash, "single-file path should serve the cached hash, not recompute it")

        let secondFile = ScannedFile(url: url, name: "game.bin", size: size, modificationDate: mtime)
        let multiResult = try await FileHasher.hash(files: [file, secondFile], cache: cache)
        #expect(multiResult.allSatisfy { $0.hash == staleButValidHash }, "concurrent path should also serve the cached hash")
    }

    @Test("CollectionHasher serves a cached hash for an unchanged zip entry without re-extracting it")
    func collectionHasherUsesCacheForZipEntries() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let loosePath = root.appendingPathComponent("game.bin")
        try Data("123456789".utf8).write(to: loosePath)
        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: loosePath, compressionMethod: .deflate)

        let zipAttrs = try FileManager.default.attributesOfItem(atPath: archiveURL.path)
        let zipMTime = zipAttrs[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let zipSize = Int64(zipAttrs[.size] as? Int ?? 0)
        let zipFile = ScannedFile(url: archiveURL, name: "Game.zip", size: zipSize, modificationDate: zipMTime)

        let entryFile = ScannedFile(url: archiveURL, name: "game.bin", size: 9, modificationDate: zipMTime)
        let staleButValidHash = FileHash(crc32: "deadbeef", md5: "stale", sha1: "stale")
        let cache = ScanCache.build(from: [HashedFile(file: entryFile, hash: staleButValidHash)])

        let results = try await CollectionHasher.hash(scannedFiles: [zipFile], cache: cache)
        #expect(results.first?.hash == staleButValidHash, "should serve the cached entry hash instead of re-extracting/re-hashing it")
    }

    @Test("round-trips through JSON, save and load")
    func roundTripsThroughJSON() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = ScannedFile(url: URL(fileURLWithPath: "/tmp/game.bin"), name: "game.bin", size: 4, modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let cache = ScanCache.build(from: [HashedFile(file: file, hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))])

        let cacheURL = root.appendingPathComponent("cache.json")
        try cache.save(to: cacheURL)
        let loaded = try ScanCache.load(contentsOf: cacheURL)

        #expect(loaded.lookup(for: file) != nil)
    }
}
