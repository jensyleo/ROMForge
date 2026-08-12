// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// Builds a byte-exact synthetic CHD v5 header (124 bytes, big-endian),
/// per MAME's `src/lib/util/chd.h`, so these tests don't need a real
/// (possibly multi-GB) CHD file — only the header format is implemented.
private func makeV5Header(
    version: UInt32 = 5,
    logicalBytes: UInt64 = 0,
    hunkBytes: UInt32 = 0,
    unitBytes: UInt32 = 0,
    rawSHA1: [UInt8] = Array(repeating: 0xAA, count: 20),
    sha1: [UInt8] = Array(repeating: 0xBB, count: 20),
    parentSHA1: [UInt8] = Array(repeating: 0, count: 20)
) -> Data {
    var data = Data(count: 124)
    data.replaceSubrange(0..<8, with: Data("MComprHD".utf8))
    writeUInt32BE(&data, at: 8, value: 124)
    writeUInt32BE(&data, at: 12, value: version)
    writeUInt64BE(&data, at: 32, value: logicalBytes)
    writeUInt32BE(&data, at: 56, value: hunkBytes)
    writeUInt32BE(&data, at: 60, value: unitBytes)
    data.replaceSubrange(64..<84, with: Data(rawSHA1))
    data.replaceSubrange(84..<104, with: Data(sha1))
    data.replaceSubrange(104..<124, with: Data(parentSHA1))
    return data
}

private func writeUInt32BE(_ data: inout Data, at offset: Int, value: UInt32) {
    for i in 0..<4 {
        data[offset + i] = UInt8((value >> (8 * (3 - i))) & 0xFF)
    }
}

private func writeUInt64BE(_ data: inout Data, at offset: Int, value: UInt64) {
    for i in 0..<8 {
        data[offset + i] = UInt8((value >> (8 * (7 - i))) & 0xFF)
    }
}

private func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

@Suite("CHDHeaderReader")
struct CHDHeaderReaderTests {
    private func tempFile(with data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".chd")
        try data.write(to: url)
        return url
    }

    @Test("parses version, sizes and hashes from a v5 header")
    func parsesV5Header() throws {
        let rawSHA1: [UInt8] = Array(repeating: 0x11, count: 20)
        let sha1: [UInt8] = Array(repeating: 0x22, count: 20)
        let url = try tempFile(with: makeV5Header(logicalBytes: 681_984_000, hunkBytes: 19_584, unitBytes: 2_448, rawSHA1: rawSHA1, sha1: sha1))
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try CHDHeaderReader.read(contentsOf: url)

        #expect(header.version == 5)
        #expect(header.logicalBytes == 681_984_000)
        #expect(header.hunkBytes == 19_584)
        #expect(header.unitBytes == 2_448)
        #expect(header.rawSHA1 == hex(rawSHA1))
        #expect(header.sha1 == hex(sha1))
        #expect(header.parentSHA1 == nil)
    }

    @Test("reads a non-zero parent SHA1")
    func readsParentSHA1() throws {
        let parentSHA1: [UInt8] = Array(repeating: 0x33, count: 20)
        let url = try tempFile(with: makeV5Header(parentSHA1: parentSHA1))
        defer { try? FileManager.default.removeItem(at: url) }

        let header = try CHDHeaderReader.read(contentsOf: url)
        #expect(header.parentSHA1 == hex(parentSHA1))
    }

    @Test("throws when the file has no MComprHD tag")
    func throwsWhenTagMissing() throws {
        let url = try tempFile(with: Data(repeating: 0, count: 124))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: CHDError.notAValidCHD(url)) {
            try CHDHeaderReader.read(contentsOf: url)
        }
    }

    @Test("throws when the header is truncated")
    func throwsWhenTruncated() throws {
        let url = try tempFile(with: Data("MComprHD".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: CHDError.notAValidCHD(url)) {
            try CHDHeaderReader.read(contentsOf: url)
        }
    }

    @Test("throws unsupportedVersion for a pre-v5 header")
    func throwsOnUnsupportedVersion() throws {
        let url = try tempFile(with: makeV5Header(version: 3))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: CHDError.unsupportedVersion(3, url)) {
            try CHDHeaderReader.read(contentsOf: url)
        }
    }
}

@Suite("CHDMatcher")
struct CHDMatcherTests {
    private func tempFile(stem: String, sha1: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-\(UUID().uuidString).chd")
        try makeV5Header(sha1: sha1).write(to: url)
        return url
    }

    @Test("matches correct when a CHD's header SHA1 equals the expected disk SHA1")
    func matchesCorrect() throws {
        let expected: [UInt8] = Array(repeating: 0x44, count: 20)
        let chd = try tempFile(stem: "game", sha1: expected)
        defer { try? FileManager.default.removeItem(at: chd) }

        let disk = MAMEDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: hex(expected))
        #expect(CHDMatcher.match(disk: disk, chdFiles: [chd]) == .correct(chd))
    }

    @Test("matches incorrect when a same-named CHD's hash doesn't match")
    func matchesIncorrectByFilename() throws {
        let chd = try tempFile(stem: "game", sha1: Array(repeating: 0x55, count: 20))
        defer { try? FileManager.default.removeItem(at: chd) }

        let disk = MAMEDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: hex(Array(repeating: 0x99, count: 20)))
        #expect(CHDMatcher.match(disk: disk, chdFiles: [chd]) == .incorrect(chd))
    }

    @Test("matches missing when no CHD matches by hash or filename")
    func matchesMissing() {
        let disk = MAMEDisk(name: "ghost", sha1: hex(Array(repeating: 0x66, count: 20)))
        #expect(CHDMatcher.match(disk: disk, chdFiles: []) == .missing)
    }

    @Test("matches missing when the disk declares no expected SHA1")
    func matchesMissingWhenNoExpectedHash() {
        let disk = MAMEDisk(name: "game", sha1: nil)
        #expect(CHDMatcher.match(disk: disk, chdFiles: []) == .missing)
    }

    @Test("matches unverifiable when the disk declares no expected SHA1 but a same-named CHD exists")
    func matchesUnverifiableWhenNoExpectedHashButFileExists() throws {
        // The `.unverifiable` branch (`CHDMatcher.swift` lines 44-53) was
        // previously only ever exercised with `chdFiles: []`, which can
        // only ever reach `.missing` — never the actual "undumped media,
        // file present" case this status exists for.
        let chd = try tempFile(stem: "ghost", sha1: Array(repeating: 0xCC, count: 20))
        defer { try? FileManager.default.removeItem(at: chd) }

        let disk = MAMEDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: nil)
        #expect(CHDMatcher.match(disk: disk, chdFiles: [chd]) == .unverifiable(chd))
    }

    @Test("the headerIndex: overload matches identically to the chdFiles-only one")
    func headerIndexOverloadMatchesSameAsPlainOverload() throws {
        let expected: [UInt8] = Array(repeating: 0x77, count: 20)
        let chd = try tempFile(stem: "game", sha1: expected)
        defer { try? FileManager.default.removeItem(at: chd) }

        let disk = MAMEDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: hex(expected))
        let index = CHDHeaderIndex(chdFiles: [chd])
        #expect(CHDMatcher.match(disk: disk, chdFiles: [chd], headerIndex: index) == .correct(chd))
    }
}

@Suite("CHDHeaderIndex")
struct CHDHeaderIndexTests {
    private func tempFile(stem: String, sha1: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-\(UUID().uuidString).chd")
        try makeV5Header(sha1: sha1).write(to: url)
        return url
    }

    @Test("looks up a header by URL and by its own SHA1")
    func looksUpByURLAndSHA1() throws {
        let sha1: [UInt8] = Array(repeating: 0x88, count: 20)
        let chd = try tempFile(stem: "game", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: chd) }

        let index = CHDHeaderIndex(chdFiles: [chd])
        #expect(index.header(for: chd)?.sha1 == hex(sha1))
        #expect(index.urls(withSHA1: hex(sha1)) == [chd])
    }

    @Test("returns every URL sharing the same SHA1 — a disk's content can legitimately exist in more than one place")
    func returnsAllURLsForADuplicatedDisk() throws {
        let sha1: [UInt8] = Array(repeating: 0x99, count: 20)
        let first = try tempFile(stem: "a", sha1: sha1)
        let second = try tempFile(stem: "b", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }

        let index = CHDHeaderIndex(chdFiles: [first, second])
        #expect(Set(index.urls(withSHA1: hex(sha1))) == [first, second])
    }

    @Test("an unreadable file is simply absent from the index, not a crash")
    func unreadableFileIsAbsent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".chd")
        try Data(repeating: 0, count: 4).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let index = CHDHeaderIndex(chdFiles: [url])
        #expect(index.header(for: url) == nil)
    }
}
