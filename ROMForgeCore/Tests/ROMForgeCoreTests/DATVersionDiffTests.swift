// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("DATVersionDiff")
struct DATVersionDiffTests {
    private func rom(_ name: String, sha1: String? = nil, crc: String? = nil) -> DATRom {
        DATRom(name: name, size: 1, crc: crc, md5: nil, sha1: sha1)
    }

    private func game(_ name: String, roms: [DATRom] = []) -> DATGame {
        DATGame(name: name, description: name, cloneOf: nil, romOf: nil, roms: roms)
    }

    private func file(_ games: [DATGame]) -> DATFile {
        DATFile(header: DATHeader(name: "Test", description: "", version: "1", author: ""), games: games)
    }

    @Test("identical DATs yield an empty diff")
    func identicalYieldsEmpty() {
        let games = [game("sf2"), game("pacman")]
        let diff = DATVersionDiff.compare(oldFile: file(games), newFile: file(games))
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
        #expect(diff.renamed.isEmpty)
    }

    @Test("a name only in the new DAT is added")
    func detectsAdded() {
        let old = file([game("sf2")])
        let new = file([game("sf2"), game("sf2t")])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.added.map(\.name) == ["sf2t"])
        #expect(diff.removed.isEmpty)
    }

    @Test("a name only in the old DAT is removed")
    func detectsRemoved() {
        let old = file([game("sf2"), game("sf2t")])
        let new = file([game("sf2")])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.removed.map(\.name) == ["sf2t"])
        #expect(diff.added.isEmpty)
    }

    @Test("matching case-insensitively keeps a differently-cased name from being flagged")
    func nameMatchIsCaseInsensitive() {
        let old = file([game("SF2")])
        let new = file([game("sf2")])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
    }

    @Test("a shared rom sha1 between a removed and an added game flags a possible rename")
    func detectsRenameBySha1() {
        let old = file([game("oldname", roms: [rom("prog.bin", sha1: "aaaa")])])
        let new = file([game("newname", roms: [rom("prog.bin", sha1: "aaaa")])])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.removed.map(\.name) == ["oldname"])
        #expect(diff.added.map(\.name) == ["newname"])
        #expect(diff.renamed == [DATRenameCandidate(oldName: "oldname", newName: "newname", matchedRomName: "prog.bin")])
    }

    @Test("falls back to crc when a rom has no sha1")
    func detectsRenameByCRCFallback() {
        let old = file([game("oldname", roms: [rom("prog.bin", crc: "deadbeef")])])
        let new = file([game("newname", roms: [rom("prog.bin", crc: "deadbeef")])])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.renamed.map(\.oldName) == ["oldname"])
        #expect(diff.renamed.map(\.newName) == ["newname"])
    }

    @Test("a hash shared by more than one candidate on either side is not treated as a confident rename")
    func ambiguousHashIsNotPaired() {
        let old = file([
            game("old1", roms: [rom("shared.bin", sha1: "cccc")]),
            game("old2", roms: [rom("shared.bin", sha1: "cccc")]),
        ])
        let new = file([game("newname", roms: [rom("shared.bin", sha1: "cccc")])])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.renamed.isEmpty)
        #expect(Set(diff.removed.map(\.name)) == ["old1", "old2"])
        #expect(diff.added.map(\.name) == ["newname"])
    }

    @Test("a nodump rom (no hash at all) never participates in rename matching")
    func nodumpRomNeverMatches() {
        let old = file([game("oldname", roms: [DATRom(name: "prog.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .nodump)])])
        let new = file([game("newname", roms: [DATRom(name: "prog.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .nodump)])])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.renamed.isEmpty)
    }

    @Test("a removed game only pairs with one added game even if it shares roms with two")
    func removedGamePairsAtMostOnce() {
        let old = file([game("oldname", roms: [rom("a.bin", sha1: "1111"), rom("b.bin", sha1: "2222")])])
        let new = file([
            game("newA", roms: [rom("a.bin", sha1: "1111")]),
            game("newB", roms: [rom("b.bin", sha1: "2222")]),
        ])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.renamed.count == 1)
        #expect(diff.renamed.first?.oldName == "oldname")
    }

    @Test("two machine names differing only by case don't crash the comparison (malformed/hand-edited DAT)")
    func caseCollidingNamesDontCrash() {
        let old = file([game("Foo"), game("foo")])
        let new = file([game("Foo")])
        let diff = DATVersionDiff.compare(oldFile: old, newFile: new)
        #expect(diff.added.isEmpty)
        #expect(diff.removed.isEmpty)
    }
}
