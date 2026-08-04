// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("AuditReporter")
struct AuditReporterTests {
    private func hashedFile(name: String, size: Int64) -> HashedFile {
        HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, size: size),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        )
    }

    @Test("counts one entry per status and includes surplus files")
    func countsEachStatus() {
        let correctRom = DATRom(name: "correct.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let incorrectRom = DATRom(name: "expected.bin", size: 2, crc: nil, md5: nil, sha1: nil)
        let missingRom = DATRom(name: "missing.bin", size: 3, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [correctRom, incorrectRom, missingRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: correctRom, status: .correct(hashedFile(name: "correct.bin", size: 1))),
                    RomMatch(rom: incorrectRom, status: .misnamed(hashedFile(name: "renamed.bin", size: 2))),
                    RomMatch(rom: missingRom, status: .missing),
                ]),
            ],
            surplusFiles: [hashedFile(name: "extra.bin", size: 99)]
        )

        let report = AuditReporter.generate(from: matchReport)

        #expect(report.correct == 1)
        #expect(report.incorrect == 1)
        #expect(report.missing == 1)
        #expect(report.surplus == 1)
        #expect(report.entries.count == 4)
        #expect(report.entries.contains { $0.status == .surplus && $0.name == "extra.bin" && $0.game == nil })
    }

    @Test("populates expected hashes from the DAT and actual hashes from the local file")
    func populatesExpectedAndActualHashes() throws {
        let rom = DATRom(name: "game.bin", size: 1, crc: "deadbeef", md5: "expectedmd5", sha1: "expectedsha1")
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let local = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/game.bin"), name: "game.bin", size: 1),
            hash: FileHash(crc32: "deadbeef", md5: "actualmd5", sha1: "actualsha1")
        )
        let missingRom = DATRom(name: "missing.bin", size: 2, crc: "cafefeed", md5: nil, sha1: nil)
        let surplus = hashedFile(name: "extra.bin", size: 99)

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(local))]),
                GameMatchResult(
                    game: DATGame(name: "Other", description: "Other", cloneOf: nil, romOf: nil, roms: [missingRom]),
                    matches: [RomMatch(rom: missingRom, status: .missing)]
                ),
            ],
            surplusFiles: [surplus]
        )

        let report = AuditReporter.generate(from: matchReport)

        let correctEntry = try #require(report.entries.first { $0.status == .correct })
        #expect(correctEntry.expectedCRC == "deadbeef")
        #expect(correctEntry.expectedMD5 == "expectedmd5")
        #expect(correctEntry.actualMD5 == "actualmd5")

        let missingEntry = try #require(report.entries.first { $0.status == .missing })
        #expect(missingEntry.expectedCRC == "cafefeed")
        #expect(missingEntry.actualCRC == nil, "a missing rom has no local file to hash")

        let surplusEntry = try #require(report.entries.first { $0.status == .surplus })
        #expect(surplusEntry.expectedCRC == nil, "the DAT says nothing about a surplus file")
        #expect(surplusEntry.actualCRC == "aaaaaaaa")
    }

    @Test("propagates the game's cloneOf so a UI can group clone sets under their parent")
    func propagatesCloneOf() throws {
        let rom = DATRom(name: "clone.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let cloneGame = DATGame(name: "Clone Game", description: "Clone Game", cloneOf: "Parent Game", romOf: "Parent Game", roms: [rom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: cloneGame, matches: [RomMatch(rom: rom, status: .missing)])],
            surplusFiles: []
        )

        let report = AuditReporter.generate(from: matchReport)
        let entry = try #require(report.entries.first)
        #expect(entry.cloneOf == "Parent Game")
    }

    @Test("propagates hasCHD/hasSamples from the game and isBadDump from the rom's DAT status")
    func propagatesCHDSamplesAndBadDump() throws {
        let goodRom = DATRom(name: "good.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .good)
        let badRom = DATRom(name: "bad.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .baddump)
        let game = DATGame(
            name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [goodRom, badRom],
            disks: [DATDisk(name: "disk1", sha1: nil)], hasSamples: true
        )
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: goodRom, status: .missing),
                RomMatch(rom: badRom, status: .missing),
            ])],
            surplusFiles: [hashedFile(name: "extra.bin", size: 1)]
        )

        let report = AuditReporter.generate(from: matchReport)

        let goodEntry = try #require(report.entries.first { $0.name == "good.bin" })
        #expect(goodEntry.hasCHD == true)
        #expect(goodEntry.hasSamples == true)
        #expect(goodEntry.isBadDump == false)

        let badEntry = try #require(report.entries.first { $0.name == "bad.bin" })
        #expect(badEntry.isBadDump == true)

        let surplusEntry = try #require(report.entries.first { $0.status == .surplus })
        #expect(surplusEntry.hasCHD == false, "surplus files have no DAT game to inherit flags from")
        #expect(surplusEntry.isBadDump == false)
    }

    @Test("an empty match report yields an all-zero audit")
    func emptyReportYieldsZeroCounts() {
        let report = AuditReporter.generate(from: MatchReport(games: [], surplusFiles: []))

        #expect(report.entries.isEmpty)
        #expect(report.correct == 0)
        #expect(report.incorrect == 0)
        #expect(report.missing == 0)
        #expect(report.surplus == 0)
    }
}
