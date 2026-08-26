// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("SevenZipArchiveScanner")
struct SevenZipArchiveScannerTests {
    // A representative excerpt of `7zz l -slt archive.7z` output: an
    // archive-level header block, a "----------" separator, then one
    // Key = Value block per entry (files and one directory).
    private let sampleListing = """
    7-Zip [64] 23.01

    Scanning the drive for archives:
    1 file, 512 bytes

    Listing archive: archive.7z

    --
    Path = archive.7z
    Type = 7z
    Physical Size = 512

    ----------
    Path = game.bin
    Folder = -
    Size = 131072
    Packed Size = 65536
    Modified = 2020-01-01 00:00:00
    Attributes = A
    CRC = DEADBEEF
    Encrypted = -
    Method = LZMA2:19

    Path = Subfolder
    Folder = +
    Size = 0
    Attributes = D

    Path = Subfolder/nested.bin
    Folder = -
    Size = 2048
    Attributes = A
    CRC = 12345678

    """

    private let archiveURL = URL(fileURLWithPath: "/roms/archive.7z")

    @Test("parses file entries, skipping the archive header and directories")
    func parsesFileEntriesSkippingHeaderAndDirectories() {
        let entries = SevenZipArchiveScanner.parseEntries(from: sampleListing, archiveURL: archiveURL)

        #expect(entries.count == 2)
        #expect(entries.map(\.entryPath) == ["game.bin", "Subfolder/nested.bin"])
        #expect(entries[0].size == 131_072)
        #expect(entries[0].name == "game.bin")
        #expect(entries[1].name == "nested.bin")
    }

    @Test("returns no entries when the output has no separator line")
    func returnsNoEntriesWithoutSeparator() {
        #expect(SevenZipArchiveScanner.parseEntries(from: "not a real listing", archiveURL: archiveURL).isEmpty)
    }

    @Test("throws cannotOpenArchive when the archive file does not exist")
    func throwsWhenArchiveMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: SevenZipError.cannotOpenArchive(missing)) {
            try SevenZipArchiveScanner.scan(archive: missing)
        }
    }
}
