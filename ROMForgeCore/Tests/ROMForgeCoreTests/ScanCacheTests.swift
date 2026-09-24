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

    @Test("removingEntries(under:) drops a folder's own files and its archives' entries, keeping every other folder's")
    func removingEntriesUnderAFolder() {
        let cps3 = URL(fileURLWithPath: "/roms/CPS3", isDirectory: true)
        let other = URL(fileURLWithPath: "/roms/OTHER", isDirectory: true)
        let date = Date(timeIntervalSince1970: 1)
        func file(_ archive: URL, entry: String) -> ScannedFile {
            ScannedFile(url: archive, name: entry, size: 4, modificationDate: date)
        }
        let cps3Entry = file(cps3.appendingPathComponent("ghouls.zip"), entry: "09.4a")
        let cps3Loose = file(cps3.appendingPathComponent("disk.chd"), entry: "disk.chd")
        let otherEntry = file(other.appendingPathComponent("ghouls.zip"), entry: "09.4a")
        let cache = ScanCache.build(from: [cps3Entry, cps3Loose, otherEntry].map {
            HashedFile(file: $0, hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        })

        // Sanity: all three are hits before pruning.
        #expect(cache.lookup(for: cps3Entry) != nil)
        #expect(cache.lookup(for: otherEntry) != nil)

        let pruned = cache.removingEntries(under: [cps3])

        #expect(pruned.lookup(for: cps3Entry) == nil, "a zip entry under the pruned folder must be dropped")
        #expect(pruned.lookup(for: cps3Loose) == nil, "a loose file under the pruned folder must be dropped")
        #expect(pruned.lookup(for: otherEntry) != nil, "another folder's identically-named archive must survive")
    }

    @Test("removingEntries(under:) accepts a single file path, dropping only that archive's own entries")
    func removingEntriesUnderASingleFile() {
        let date = Date(timeIntervalSince1970: 1)
        let target = URL(fileURLWithPath: "/roms/OTHER/ghouls.zip")
        let neighbour = URL(fileURLWithPath: "/roms/OTHER/contra.zip")
        let targetEntry = ScannedFile(url: target, name: "09.4a", size: 4, modificationDate: date)
        let neighbourEntry = ScannedFile(url: neighbour, name: "633e01.12a", size: 4, modificationDate: date)
        let cache = ScanCache.build(from: [targetEntry, neighbourEntry].map {
            HashedFile(file: $0, hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        })

        let pruned = cache.removingEntries(under: [target])

        #expect(pruned.lookup(for: targetEntry) == nil)
        #expect(pruned.lookup(for: neighbourEntry) != nil, "a sibling archive in the same folder must survive")
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

    @Test("CollectionHasher skips re-listing an unchanged zip's own directory entirely, not just re-hashing its entries")
    func collectionHasherSkipsRelistingUnchangedZip() async throws {
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

        // A real first pass — actually lists and hashes the zip, building a
        // complete, genuine cache for it (unlike the sibling test above,
        // which hand-builds a cache without ever really scanning).
        let warmCache = ScanCache.build(from: try await CollectionHasher.hash(scannedFiles: [zipFile], cache: ScanCache()))

        // Now corrupt the archive on disk WITHOUT touching its mtime —
        // if `CollectionHasher` actually tried to re-list this zip's
        // central directory on the next call, that would throw. A second
        // call that still succeeds, with the same result, proves the
        // listing itself was skipped — not just the per-entry hashing
        // (already covered above).
        try Data("not a zip file anymore".utf8).write(to: archiveURL)
        try FileManager.default.setAttributes([.modificationDate: zipMTime], ofItemAtPath: archiveURL.path)

        let results = try await CollectionHasher.hash(scannedFiles: [zipFile], cache: warmCache)
        #expect(results.count == 1)
        #expect(results.first?.file.name == "game.bin")
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

    @Test("reconstructedHashedFiles() rebuilds both a loose file and a zip entry entirely from the cache, with no disk access at all")
    func reconstructedHashedFilesRebuildsLooseFileAndZipEntry() {
        let looseFile = ScannedFile(url: URL(fileURLWithPath: "/roms/loose.bin"), name: "loose.bin", size: 4, modificationDate: Date(timeIntervalSince1970: 1_000_000))
        let looseHash = FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        let zipURL = URL(fileURLWithPath: "/roms/game.zip")
        let entryFile = ScannedFile(url: zipURL, name: "inner.bin", size: 8, modificationDate: Date(timeIntervalSince1970: 2_000_000))
        let entryHash = FileHash(crc32: "bbbbbbbb", md5: "1", sha1: "1")
        let cache = ScanCache.build(from: [
            HashedFile(file: looseFile, hash: looseHash),
            HashedFile(file: entryFile, hash: entryHash),
        ])

        let reconstructed = cache.reconstructedHashedFiles()

        #expect(reconstructed.count == 2)
        guard let rebuiltLoose = reconstructed.first(where: { $0.file.url == looseFile.url }) else {
            Issue.record("loose file should reconstruct")
            return
        }
        #expect(rebuiltLoose.file.name == "loose.bin")
        #expect(rebuiltLoose.file.size == 4)
        #expect(rebuiltLoose.hash == looseHash)

        guard let rebuiltEntry = reconstructed.first(where: { $0.file.url == zipURL && $0.file.name == "inner.bin" }) else {
            Issue.record("zip entry should reconstruct with its own entry name, distinct from the archive's own path")
            return
        }
        #expect(rebuiltEntry.file.size == 8)
        #expect(rebuiltEntry.hash == entryHash)
    }

    // MARK: - CHD paths (Fase 1 disk auditing)

    @Test("CHD paths survive a save/load round-trip and never leak into reconstructedHashedFiles, so DiskAuditor sees them and ROMMatcher never does")
    func chdPathsRoundTripAndStayOutOfTheHashedFiles() throws {
        let chdURL = URL(fileURLWithPath: "/roms/cps3/sfiii.chd")
        let looseFile = ScannedFile(url: URL(fileURLWithPath: "/roms/cps3/a.bin"), name: "a.bin", size: 4, modificationDate: Date(timeIntervalSince1970: 100))
        let hashed = HashedFile(file: looseFile, hash: FileHash(crc32: "aaaaaaaa", md5: nil, sha1: nil))

        let cache = ScanCache.build(from: [hashed], chdPaths: [chdURL])
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try cache.save(to: tempURL)
        let reloaded = try ScanCache.load(contentsOf: tempURL)

        #expect(reloaded.reconstructedCHDPaths() == [chdURL])
        // The whole reason CHDs live outside `entries`: this list feeds
        // `ROMMatcher`, which has no concept of a disk and would try to
        // match one as a rom.
        #expect(reloaded.reconstructedHashedFiles().map(\.file.url) == [looseFile.url])
    }

    @Test("removingEntries(under:) drops a rescanned folder's CHDs too, so a CHD deleted from that folder doesn't survive in the cache forever")
    func removingEntriesAlsoDropsCHDPathsInScope() {
        let inScope = URL(fileURLWithPath: "/roms/cps3/sfiii.chd")
        let elsewhere = URL(fileURLWithPath: "/roms/konami/other.chd")
        let cache = ScanCache.build(from: [], chdPaths: [inScope, elsewhere])

        let scoped = cache.removingEntries(under: [URL(fileURLWithPath: "/roms/cps3")])

        #expect(scoped.reconstructedCHDPaths() == [elsewhere])
    }

    @Test("a legacy cache file (a bare dictionary, written before chdPaths existed) still decodes — refusing it would force a full cold rehash of the whole collection")
    func legacyBareDictionaryCacheStillDecodes() throws {
        let legacyJSON = """
        {"/roms/a.bin":{"size":4,"modificationDate":100,"hash":{"crc32":"aaaaaaaa"}}}
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        try Data(legacyJSON.utf8).write(to: tempURL)

        let reloaded = try ScanCache.load(contentsOf: tempURL)

        #expect(reloaded.reconstructedHashedFiles().count == 1, "the legacy hash entries must still load")
        #expect(reloaded.reconstructedCHDPaths().isEmpty, "a legacy cache simply has no CHD list yet")
    }

    @Test("reconstructedHashedFiles is ordered by cache key, so ROMMatcher's first-match-wins claim never depends on Dictionary iteration order")
    func reconstructedHashedFilesIsDeterministicallyOrdered() {
        // Two byte-identical archives holding the same entry name — the
        // exact shape (a `.7z` and a `.zip` of the same set) where
        // `ROMMatcher` picks whichever comes FIRST as the game's own set
        // and reports the other as a redundant duplicate. Unsorted, that
        // verdict rode on `entries`' unspecified Dictionary order.
        let hash = FileHash(crc32: "aaaaaaaa", md5: nil, sha1: nil)
        let date = Date(timeIntervalSince1970: 100)
        let sevenZip = ScannedFile(url: URL(fileURLWithPath: "/roms/nintendo/nss.7z"), name: "spc700.rom", size: 4, modificationDate: date)
        let zip = ScannedFile(url: URL(fileURLWithPath: "/roms/nintendo/nss.zip"), name: "spc700.rom", size: 4, modificationDate: date)
        let cache = ScanCache.build(from: [
            HashedFile(file: sevenZip, hash: hash),
            HashedFile(file: zip, hash: hash),
        ])

        let keysInOrder = cache.reconstructedHashedFiles().map { "\($0.file.url.path)::\($0.file.name)" }

        #expect(keysInOrder == keysInOrder.sorted(), "output must be key-sorted, not in Dictionary order")
        // Same cache, repeated reads: identical order every time. Two
        // freshly-built caches would each get their own hash seed within
        // one process, so this asserts the property that actually matters
        // downstream — a stable, reproducible sequence.
        #expect(cache.reconstructedHashedFiles().map(\.file.url.path) == cache.reconstructedHashedFiles().map(\.file.url.path))
    }
}
