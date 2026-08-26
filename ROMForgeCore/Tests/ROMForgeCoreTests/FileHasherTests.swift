// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("FileHasher")
struct FileHasherTests {
    // Known vectors for the ASCII string "123456789".
    private let sample = Data("123456789".utf8)

    @Test("hashes an in-memory buffer against known vectors")
    func hashesDataAgainstKnownVectors() {
        let hash = FileHasher.hash(data: sample)
        #expect(hash.crc32 == "cbf43926")
        #expect(hash.md5 == "25f9e794323b453885f5181f1b624d0b")
        #expect(hash.sha1 == "f7c3bc1d808e04732adf679965ccc34ca7ae3441")
    }

    @Test("computes only the requested algorithms, leaving the rest nil")
    func computesOnlyRequestedAlgorithms() {
        let crcOnly = FileHasher.hash(data: sample, algorithms: .crc32)
        #expect(crcOnly.crc32 == "cbf43926")
        #expect(crcOnly.md5 == nil)
        #expect(crcOnly.sha1 == nil)

        let md5AndSHA1 = FileHasher.hash(data: sample, algorithms: [.md5, .sha1])
        #expect(md5AndSHA1.crc32 == nil)
        #expect(md5AndSHA1.md5 == "25f9e794323b453885f5181f1b624d0b")
        #expect(md5AndSHA1.sha1 == "f7c3bc1d808e04732adf679965ccc34ca7ae3441")
    }

    @Test("hashing a file (streamed) matches hashing the same bytes in memory")
    func hashingFileMatchesHashingData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Force multiple chunks by using a tiny chunk size against a larger payload.
        let payload = Data((0..<10_000).map { UInt8($0 % 256) })
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let streamed = try FileHasher.hash(contentsOf: url, chunkSize: 64)
        let inMemory = FileHasher.hash(data: payload)

        #expect(streamed == inMemory)
    }

    @Test("throws when the file does not exist")
    func throwsWhenFileMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: HasherError.cannotOpenFile(missing)) {
            try FileHasher.hash(contentsOf: missing)
        }
    }

    @Test("concurrent batch hashing matches sequential hashing and preserves order")
    func concurrentBatchHashingMatchesSequential() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var files: [ScannedFile] = []
        for i in 0..<12 {
            let url = root.appendingPathComponent("file\(i).bin")
            let payload = Data((0..<(100 + i)).map { UInt8(($0 + i) % 256) })
            try payload.write(to: url)
            files.append(ScannedFile(url: url, name: url.lastPathComponent, size: Int64(payload.count)))
        }

        let concurrent = try await FileHasher.hash(files: files)
        let sequential = try files.map { HashedFile(file: $0, hash: try FileHasher.hash(contentsOf: $0.url)) }

        #expect(concurrent == sequential)
    }

    @Test("concurrent batch hashing handles an empty file list")
    func concurrentBatchHashingHandlesEmptyList() async throws {
        #expect(try await FileHasher.hash(files: []).isEmpty)
    }

    @Test("detects an iNES-headered file and also hashes its header-stripped content")
    func detectsHeaderAndHashesStrippedContent() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gameData = Data("this is the actual game data".utf8)
        var headeredFile = Data([0x4E, 0x45, 0x53, 0x1A]) // "NES\x1A"
        headeredFile.append(Data(repeating: 0, count: 12)) // pad to a 16-byte header
        headeredFile.append(gameData)

        let url = root.appendingPathComponent("game.nes")
        try headeredFile.write(to: url)
        let scanned = ScannedFile(url: url, name: "game.nes", size: Int64(headeredFile.count))

        let hashed = try await FileHasher.hash(files: [scanned])
        let stripped = try #require(hashed.first?.headerStripped)

        #expect(stripped.rule == .iNES)
        #expect(stripped.size == Int64(gameData.count))
        #expect(stripped.hash == FileHasher.hash(data: gameData))
    }

    @Test("deinterleaves a real .smd file on disk and hashes its Genesis-native content")
    func deinterleavesSMDFileOnDisk() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blockSize = 16384
        var smd = Data(repeating: 0, count: 512) // .smd header
        smd.append(Data(repeating: 0x11, count: blockSize / 2))
        smd.append(Data(repeating: 0x22, count: blockSize / 2))

        let url = root.appendingPathComponent("sonic.smd")
        try smd.write(to: url)
        let scanned = ScannedFile(url: url, name: "sonic.smd", size: Int64(smd.count))

        let hashed = try await FileHasher.hash(files: [scanned])
        let stripped = try #require(hashed.first?.headerStripped)

        #expect(stripped.rule == .genesisSMD)
        #expect(stripped.size == Int64(blockSize))
        #expect(stripped.hash == FileHasher.hash(data: try #require(GenesisSMDConverter.deinterleave(smd))))
    }

    @Test("a file too small/plain for any header rule has no headerStripped hash")
    func noHeaderStrippedHashForAPlainFile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let payload = Data("plain rom content".utf8)
        let url = root.appendingPathComponent("plain.bin")
        try payload.write(to: url)
        let scanned = ScannedFile(url: url, name: "plain.bin", size: Int64(payload.count))

        let hashed = try await FileHasher.hash(files: [scanned])
        #expect(hashed.first?.headerStripped == nil)
    }
}
