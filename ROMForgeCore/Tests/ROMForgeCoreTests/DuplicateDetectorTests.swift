// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("DuplicateDetector")
struct DuplicateDetectorTests {
    private func hashedFile(name: String, sha1: String) -> HashedFile {
        HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/\(name)"), name: name, size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: sha1)
        )
    }

    @Test("groups files sharing the same SHA1, ignoring filename")
    func groupsFilesBySHA1() {
        let a = hashedFile(name: "a.bin", sha1: "same")
        let b = hashedFile(name: "b.bin", sha1: "same")
        let unique = hashedFile(name: "unique.bin", sha1: "different")

        let groups = DuplicateDetector.find(in: [a, b, unique])

        #expect(groups.count == 1)
        #expect(groups[0].sha1 == "same")
        #expect(groups[0].files == [a, b])
    }

    @Test("returns no groups when every file is unique")
    func returnsNoGroupsWhenAllUnique() {
        let a = hashedFile(name: "a.bin", sha1: "one")
        let b = hashedFile(name: "b.bin", sha1: "two")

        #expect(DuplicateDetector.find(in: [a, b]).isEmpty)
    }

    @Test("groups the same archive-entry name sharing a hash across two physically distinct archives — the real BATOCERA-subfolder duplicate case")
    func groupsSameEntryAcrossDifferentArchives() {
        // Real case documented in `ROMMatcher.swift`'s own doc comments: two
        // whole copies of a set (e.g. a second `BATOCERA` mirror folder)
        // sharing the same archive/entry name at different physical paths.
        let main = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/main/sfiii2.zip"), name: "sfiii2.bin", size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "shared")
        )
        let mirrored = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/BATOCERA/sfiii2.zip"), name: "sfiii2.bin", size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "shared")
        )

        let groups = DuplicateDetector.find(in: [main, mirrored])

        #expect(groups.count == 1)
        #expect(groups[0].files == [main, mirrored])
    }

    @Test("falls back to CRC32 when SHA1 and MD5 were never computed")
    func fallsBackToCRC32WhenNoStrongerHashAvailable() {
        // `HashAlgorithms` may have skipped SHA1/MD5 for speed — grouping
        // must still work off whichever hash a scan actually computed.
        let a = HashedFile(file: ScannedFile(url: URL(fileURLWithPath: "/roms/a.bin"), name: "a.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: nil, sha1: nil))
        let b = HashedFile(file: ScannedFile(url: URL(fileURLWithPath: "/roms/b.bin"), name: "b.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: nil, sha1: nil))

        let groups = DuplicateDetector.find(in: [a, b])

        #expect(groups.count == 1)
        #expect(groups[0].sha1 == "deadbeef")
    }
}
