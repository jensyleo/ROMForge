// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// Same byte-exact synthetic CHD v5 header builder as `CHDTests.swift` —
/// duplicated locally (top-level `private` in Swift is file-scoped) rather
/// than shared, same reasoning as this codebase's other small duplicated
/// test helpers.
private func diskAuditorTestV5Header(sha1: [UInt8]) -> Data {
    var data = Data(count: 124)
    data.replaceSubrange(0..<8, with: Data("MComprHD".utf8))
    for i in 0..<4 { data[8 + i] = UInt8((124 >> (8 * (3 - i))) & 0xFF) }
    for i in 0..<4 { data[12 + i] = UInt8((5 >> (8 * (3 - i))) & 0xFF) }
    data.replaceSubrange(64..<84, with: Data(Array(repeating: 0xAA, count: 20)))
    data.replaceSubrange(84..<104, with: Data(sha1))
    data.replaceSubrange(104..<124, with: Data(Array(repeating: 0, count: 20)))
    return data
}

private func diskAuditorTestHex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

@Suite("DiskAuditor")
struct DiskAuditorTests {
    private func header() -> DATHeader { DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge") }

    private func tempCHD(stem: String, sha1: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(stem)-\(UUID().uuidString).chd")
        try diskAuditorTestV5Header(sha1: sha1).write(to: url)
        return url
    }

    /// jensyleo's own report (2026-07-30): several clones of the same game
    /// sharing one unmodified physical disk (MAME's own `cloneof`
    /// hierarchy — a region/revision variant, program rom changed, CD/HD
    /// image untouched) each declare a `<disk>` with the identical
    /// name+sha1, and used to produce one audit row *per clone*, not one
    /// per actual distinct disk — four rows all named "cap-sf3-3.chd" for
    /// four different Street Fighter III 3rd Strike clones, in the real
    /// case that surfaced this.
    @Test("multiple clones declaring the identical disk (same name+sha1) produce only one audit entry")
    func dedupesIdenticalDiskAcrossClones() throws {
        let sharedDisk = DATDisk(name: "cap-sf3-3", sha1: "1111111111111111111111111111111111111111")
        let dat = DATFile(
            header: header(),
            games: [
                DATGame(name: "sfiii", description: "Street Fighter III: New Generation (parent)", cloneOf: nil, romOf: nil, roms: [], disks: [sharedDisk]),
                DATGame(name: "sfiiij", description: "Street Fighter III: New Generation (Japan)", cloneOf: "sfiii", romOf: "sfiii", roms: [], disks: [sharedDisk]),
                DATGame(name: "sfiiiu", description: "Street Fighter III: New Generation (US)", cloneOf: "sfiii", romOf: "sfiii", roms: [], disks: [sharedDisk]),
            ]
        )

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.count == 1)
        #expect(entries[0].game == "sfiii")
        #expect(entries[0].status == .missing)
    }

    @Test("clones that declare genuinely different disks (different sha1) each get their own entry")
    func doesNotDedupeGenuinelyDifferentDisks() throws {
        let dat = DATFile(
            header: header(),
            games: [
                DATGame(
                    name: "sfiii3", description: "3rd Strike (rev A)", cloneOf: nil, romOf: nil, roms: [],
                    disks: [DATDisk(name: "cap-33s-1", sha1: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")]
                ),
                DATGame(
                    name: "sfiii3a", description: "3rd Strike (rev B)", cloneOf: "sfiii3", romOf: "sfiii3", roms: [],
                    disks: [DATDisk(name: "cap-33s-2", sha1: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")]
                ),
            ]
        )

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.count == 2)
        #expect(Set(entries.map(\.name)) == ["cap-33s-1", "cap-33s-2"])
    }

    @Test("every disk entry is marked isDisk")
    func marksEveryEntryAsDisk() throws {
        let dat = DATFile(
            header: header(),
            games: [DATGame(name: "g", description: "G", cloneOf: nil, romOf: nil, roms: [], disks: [DATDisk(name: "g", sha1: nil)])]
        )
        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [])
        #expect(entries.allSatisfy { $0.isDisk })
    }

    // MARK: - With real .chd files (previously only ever tested with chdFiles: [])

    @Test("a real matching CHD, shared by a clone, produces one .correct entry deduped across both")
    func realMatchingCHDDedupedAcrossClone() throws {
        let sha1: [UInt8] = Array(repeating: 0x11, count: 20)
        let chd = try tempCHD(stem: "cap-sf3-3", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: chd) }

        let sharedDisk = DATDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: diskAuditorTestHex(sha1))
        let dat = DATFile(
            header: header(),
            games: [
                DATGame(name: "sfiii", description: "3rd Strike (parent)", cloneOf: nil, romOf: nil, roms: [], disks: [sharedDisk]),
                DATGame(name: "sfiiij", description: "3rd Strike (Japan)", cloneOf: "sfiii", romOf: "sfiii", roms: [], disks: [sharedDisk]),
            ]
        )

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [chd])
        #expect(entries.count == 1)
        #expect(entries[0].status == .correct)
        #expect(entries[0].path == chd)
    }

    @Test("a physically duplicated CHD (two files, same sha1) produces one .correct and one .incorrect leftover, not a plain Unknown")
    func duplicatedPhysicalCHDProducesIncorrectLeftover() throws {
        // Real case documented on `DiskAuditor.audit`'s own doc comment: a
        // second `BATOCERA` mirror subtree physically duplicating several
        // real CHDs already claimed by their own real disk.
        let sha1: [UInt8] = Array(repeating: 0x22, count: 20)
        let primary = try tempCHD(stem: "cap-33s-3", sha1: sha1)
        let duplicate = try tempCHD(stem: "cap-33s-3-batocera", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: primary); try? FileManager.default.removeItem(at: duplicate) }

        let disk = DATDisk(name: primary.deletingPathExtension().lastPathComponent, sha1: diskAuditorTestHex(sha1))
        let dat = DATFile(header: header(), games: [DATGame(name: "sfiii3", description: "3rd Strike", cloneOf: nil, romOf: nil, roms: [], disks: [disk])])

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [primary, duplicate])
        #expect(entries.count == 2)
        #expect(entries.contains { $0.status == .correct && $0.path == primary })
        let leftover = entries.first { $0.path == duplicate }
        #expect(leftover?.status == .incorrect)
        #expect(leftover?.requiredByGameDescription == "3rd Strike")
    }

    @Test("an undumped disk (no declared sha1) with a same-named CHD present reads .unverifiable, not .missing")
    func undumpedDiskWithSameNamedFileIsUnverifiable() throws {
        let chd = try tempCHD(stem: "undumped-media", sha1: Array(repeating: 0x33, count: 20))
        defer { try? FileManager.default.removeItem(at: chd) }

        let disk = DATDisk(name: chd.deletingPathExtension().lastPathComponent, sha1: nil)
        let dat = DATFile(header: header(), games: [DATGame(name: "g", description: "G", cloneOf: nil, romOf: nil, roms: [], disks: [disk])])

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [chd])
        #expect(entries.count == 1)
        #expect(entries[0].status == .unverifiable)
        #expect(entries[0].path == chd)
    }

    @Test("a real dump and a nodump clone sharing the same disk name produce only ONE .correct entry, not a contradictory pair")
    func realDumpAndNodumpCloneWithSameNameProduceOneCorrectEntry() throws {
        // The real live case (jensyleo, 2026-08-17): Dragon's Lair (US Rev.
        // F2) declares `<disk name="dlair" sha1="...">` (a real dump); its
        // beta clone, Dragon's Lair (US Beta 1, Pioneer PR-7820), declares
        // `<disk name="dlair">` with NO sha1 at all (MAME's own nodump —
        // nobody's ever hashed *this* set's copy). Same disk name, so same
        // physical media under MAME's own convention — with only one real
        // `dlair.chd` on disk, this used to produce TWO rows for it: one
        // "Correct" (the parent) and one contradictory "Nodump
        // (unverifiable)" (the beta), instead of one unified verdict.
        let sha1: [UInt8] = Array(repeating: 0x55, count: 20)
        let chd = try tempCHD(stem: "dlair", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: chd) }
        let diskName = chd.deletingPathExtension().lastPathComponent

        let dat = DATFile(
            header: header(),
            games: [
                DATGame(name: "dlair", description: "Dragon's Lair (US Rev. F2)", cloneOf: nil, romOf: nil, roms: [], disks: [DATDisk(name: diskName, sha1: diskAuditorTestHex(sha1))]),
                DATGame(name: "dlair_1", description: "Dragon's Lair (US Beta 1, Pioneer PR-7820)", cloneOf: "dlair", romOf: "dlair", roms: [], disks: [DATDisk(name: diskName, sha1: nil)]),
            ]
        )

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [chd])
        #expect(entries.count == 1)
        #expect(entries[0].status == .correct)
        #expect(entries[0].path == chd)
        #expect(entries[0].game == "dlair")
    }

    @Test("a real dump declared AFTER a nodump clone in DAT order still wins — the real sha1 isn't shadowed by iteration order")
    func realDumpDeclaredAfterNodumpCloneStillWins() throws {
        let sha1: [UInt8] = Array(repeating: 0x66, count: 20)
        let chd = try tempCHD(stem: "dlair-reverse", sha1: sha1)
        defer { try? FileManager.default.removeItem(at: chd) }
        let diskName = chd.deletingPathExtension().lastPathComponent

        let dat = DATFile(
            header: header(),
            games: [
                // Nodump clone declared FIRST in DAT order this time.
                DATGame(name: "dlair_1", description: "Dragon's Lair (US Beta 1, Pioneer PR-7820)", cloneOf: "dlair", romOf: "dlair", roms: [], disks: [DATDisk(name: diskName, sha1: nil)]),
                DATGame(name: "dlair", description: "Dragon's Lair (US Rev. F2)", cloneOf: nil, romOf: nil, roms: [], disks: [DATDisk(name: diskName, sha1: diskAuditorTestHex(sha1))]),
            ]
        )

        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [chd])
        #expect(entries.count == 1)
        #expect(entries[0].status == .correct)
        #expect(entries[0].game == "dlair")
    }

    @Test("a .chd matching no declared disk at all is a genuinely unknown surplus entry")
    func unmatchedCHDIsGenuinelySurplus() throws {
        let chd = try tempCHD(stem: "mystery", sha1: Array(repeating: 0x44, count: 20))
        defer { try? FileManager.default.removeItem(at: chd) }

        let dat = DATFile(header: header(), games: [])
        let entries = try DiskAuditor.audit(dat: dat, chdFiles: [chd])
        #expect(entries.count == 1)
        #expect(entries[0].status == .surplus)
        #expect(entries[0].game == nil)
        #expect(entries[0].requiredByGameDescription == nil)
    }
}
