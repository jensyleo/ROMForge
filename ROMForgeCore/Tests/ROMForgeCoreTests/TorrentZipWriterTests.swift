// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("TorrentZipWriter")
struct TorrentZipWriterTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("torrentzip-\(UUID().uuidString).zip")
    }

    @Test("writes an archive ZIPFoundation (an independent implementation) can open, list, and extract correctly")
    func readableByIndependentZipImplementation() throws {
        let entries = [
            TorrentZipEntry(name: "game/rom2.bin", data: Data("second rom content".utf8)),
            TorrentZipEntry(name: "game/rom1.bin", data: Data("first rom content, longer so deflate actually compresses something meaningful here".utf8)),
            TorrentZipEntry(name: "game/empty.bin", data: Data()),
        ]
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try TorrentZipWriter.write(entries, to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        var seenNames: [String] = []
        for entry in archive {
            seenNames.append(entry.path)
            var extracted = Data()
            _ = try archive.extract(entry) { extracted.append($0) }
            let original = entries.first { $0.name == entry.path }
            #expect(original?.data == extracted)
        }
        // Sorted by lowercase filename, per spec.
        #expect(seenNames == ["game/empty.bin", "game/rom1.bin", "game/rom2.bin"])
    }

    @Test("every entry uses the fixed TorrentZip timestamp, flags, and compression method")
    func usesFixedTorrentZipFields() throws {
        let entries = [TorrentZipEntry(name: "a.bin", data: Data("hello".utf8))]
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try TorrentZipWriter.write(entries, to: url)

        let raw = try Data(contentsOf: url)
        // Local file header: signature(4) version(2) flag(2) method(2) time(2) date(2) ...
        #expect(raw[0..<4] == Data([0x50, 0x4b, 0x03, 0x04]))
        let flag = UInt16(raw[6]) | (UInt16(raw[7]) << 8)
        #expect(flag == 2) // ASCII name, no unicode bit
        let method = UInt16(raw[8]) | (UInt16(raw[9]) << 8)
        #expect(method == 8) // deflate, even for this tiny input
        let time = UInt16(raw[10]) | (UInt16(raw[11]) << 8)
        let date = UInt16(raw[12]) | (UInt16(raw[13]) << 8)
        #expect(time == 48128)
        #expect(date == 8600)
    }

    @Test("the EOCD comment is TORRENTZIPPED- followed by the uppercase-hex CRC32 of the central directory")
    func writesValidTorrentZippedComment() throws {
        let entries = [
            TorrentZipEntry(name: "b.bin", data: Data("b content".utf8)),
            TorrentZipEntry(name: "a.bin", data: Data("a content".utf8)),
        ]
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try TorrentZipWriter.write(entries, to: url)

        let raw = try Data(contentsOf: url)
        // Find EOCD signature 0x06054b50 (little-endian bytes 50 4b 05 06) from the end.
        let sig: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
        var eocdStart = -1
        var i = raw.count - 4
        while i >= 0 {
            if [UInt8](raw[i..<i + 4]) == sig { eocdStart = i; break }
            i -= 1
        }
        let start = try #require(eocdStart >= 0 ? eocdStart : nil)
        let commentLength = Int(raw[start + 20]) | (Int(raw[start + 21]) << 8)
        let comment = String(decoding: raw[(start + 22)..<(start + 22 + commentLength)], as: UTF8.self)

        #expect(comment.hasPrefix("TORRENTZIPPED-"))
        #expect(comment.count == "TORRENTZIPPED-".count + 8)

        let centralDirLength = UInt32(raw[start + 12]) | (UInt32(raw[start + 13]) << 8) | (UInt32(raw[start + 14]) << 16) | (UInt32(raw[start + 15]) << 24)
        let socd = UInt32(raw[start + 16]) | (UInt32(raw[start + 17]) << 8) | (UInt32(raw[start + 18]) << 16) | (UInt32(raw[start + 19]) << 24)
        let centralDirBytes = raw[Int(socd)..<Int(socd + centralDirLength)]
        let expectedCRC = String(format: "%08X", CRC32.checksum(of: Data(centralDirBytes)))
        #expect(comment == "TORRENTZIPPED-\(expectedCRC)")
    }

    @Test("rejects duplicate entry names")
    func rejectsDuplicateNames() {
        let entries = [
            TorrentZipEntry(name: "a.bin", data: Data("1".utf8)),
            TorrentZipEntry(name: "a.bin", data: Data("2".utf8)),
        ]
        #expect(throws: TorrentZipWriterError.duplicateEntryName("a.bin")) {
            _ = try TorrentZipWriter.write(entries, to: self.tempURL())
        }
    }

    @Test("drops a directory entry implied by a file already under it, but keeps a genuinely empty directory")
    func filtersRedundantDirectoryEntries() throws {
        let entries = [
            TorrentZipEntry(name: "set1/", data: Data()),
            TorrentZipEntry(name: "set1/test1.rom", data: Data("x".utf8)),
            TorrentZipEntry(name: "set2/", data: Data()),
        ]
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try TorrentZipWriter.write(entries, to: url)

        let archive = try #require(Archive(url: url, accessMode: .read))
        let names = archive.map(\.path).sorted()
        #expect(names == ["set1/test1.rom", "set2/"])
    }
}
