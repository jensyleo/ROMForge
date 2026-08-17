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

    @Test("a surplus file with a requiredByGameDescription is reclassified .incorrect, not .unknownFile")
    func surplusWithKnownOwnerIsIncorrectNotSurplus() throws {
        // jensyleo's own correction (2026-08-04): "surplus" must mean
        // genuinely unrecognized — a leftover file whose content is fully
        // identified (it hash-matches a real rom some other DAT game
        // declares, e.g. a Split-mode clone's zip still holding a rom its
        // parent's archive actually wants) is the opposite of unknown, so
        // it belongs in the same bucket as a misnamed rom, not "Unknown".
        let recognized = SurplusFile(file: hashedFile(name: "s92_01.bin", size: 1), requiredByGameDescription: "Street Fighter II': Champion Edition")
        let genuinelyUnknown = SurplusFile(file: hashedFile(name: "random.txt", size: 2))
        let report = try AuditReporter.generate(from: MatchReport(games: [], surplusFiles: [recognized, genuinelyUnknown]))

        let recognizedEntry = report.entries.first { $0.name == "s92_01.bin" }
        let unknownEntry = report.entries.first { $0.name == "random.txt" }
        #expect(recognizedEntry?.status == .incorrect)
        #expect(recognizedEntry?.requiredByGameDescription == "Street Fighter II': Champion Edition")
        // A loose file (no archive at all) with no matching hash anywhere
        // in the DAT — `.unknownFile`, not `.surplusInArchive` (that needs
        // a real, recognized archive name containing it; see
        // `AuditStatus`'s own doc comment for the 2026-08-06 split).
        #expect(unknownEntry?.status == .unknownFile)
        #expect(report.incorrect == 1)
        #expect(report.surplus == 1)
    }

    @Test("counts one entry per status and includes surplus files")
    func countsEachStatus() throws {
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
            surplusFiles: [SurplusFile(file: hashedFile(name: "extra.bin", size: 99))]
        )

        let report = try AuditReporter.generate(from: matchReport)

        #expect(report.correct == 1)
        #expect(report.incorrect == 1)
        #expect(report.missing == 1)
        #expect(report.surplus == 1)
        #expect(report.entries.count == 4)
        #expect(report.entries.contains { $0.status == .unknownFile && $0.name == "extra.bin" && $0.game == nil })
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
            surplusFiles: [SurplusFile(file: surplus)]
        )

        let report = try AuditReporter.generate(from: matchReport)

        let correctEntry = try #require(report.entries.first { $0.status == .correct })
        #expect(correctEntry.expectedCRC == "deadbeef")
        #expect(correctEntry.expectedMD5 == "expectedmd5")
        #expect(correctEntry.actualMD5 == "actualmd5")

        let missingEntry = try #require(report.entries.first { $0.status == .missing })
        #expect(missingEntry.expectedCRC == "cafefeed")
        #expect(missingEntry.actualCRC == nil, "a missing rom has no local file to hash")

        let surplusEntry = try #require(report.entries.first { $0.status == .unknownFile })
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

        let report = try AuditReporter.generate(from: matchReport)
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
            surplusFiles: [SurplusFile(file: hashedFile(name: "extra.bin", size: 1))]
        )

        let report = try AuditReporter.generate(from: matchReport)

        let goodEntry = try #require(report.entries.first { $0.name == "good.bin" })
        #expect(goodEntry.hasCHD == true)
        #expect(goodEntry.hasSamples == true)
        #expect(goodEntry.isBadDump == false)

        let badEntry = try #require(report.entries.first { $0.name == "bad.bin" })
        #expect(badEntry.isBadDump == true)

        let surplusEntry = try #require(report.entries.first { $0.status == .unknownFile })
        #expect(surplusEntry.hasCHD == false, "surplus files have no DAT game to inherit flags from")
        #expect(surplusEntry.isBadDump == false)
    }

    @Test("an empty match report yields an all-zero audit")
    func emptyReportYieldsZeroCounts() throws {
        let report = try AuditReporter.generate(from: MatchReport(games: [], surplusFiles: []))

        #expect(report.entries.isEmpty)
        #expect(report.correct == 0)
        #expect(report.incorrect == 0)
        #expect(report.missing == 0)
        #expect(report.surplus == 0)
    }

    @Test("gray-file split (2026-08-06): a nodump-by-name surplus, a surplus inside a known archive, and a surplus inside an unknown archive each get their own distinct status")
    func grayFileSplitAssignsDistinctStatuses() throws {
        // 1) Nodump-by-name — checked first, regardless of `isInKnownArchive`
        //    (a nodump rom has no hash, so this can only ever be reached by
        //    name; see `AuditStatus`'s own doc comment).
        let nodumpRom = DATRom(name: "007766.20d.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .nodump)
        let nodumpGame = DATGame(name: "gryzor", description: "Gryzor", cloneOf: "contra", romOf: "contra", roms: [nodumpRom])
        let nodumpSurplus = SurplusFile(
            file: hashedFile(name: "007766.20d.bin", size: 1),
            matchesNodumpRomName: true, isInKnownArchive: true
        )

        // 2) Inside a real, DAT-recognized archive, but this exact file
        //    matches no rom anywhere — "check me, probably a duplicate".
        let surplusInArchive = SurplusFile(file: hashedFile(name: "leftover.bin", size: 3), isInKnownArchive: true)

        // 3) Not inside any DAT-recognized archive at all, matches nothing
        //    — genuinely unrecognized junk (e.g. "TEST 1.zip" holding a
        //    screenshot, the real case that motivated this split).
        let unknownFile = SurplusFile(file: hashedFile(name: "Screenshot.png", size: 4), isInKnownArchive: false)

        let matchReport = MatchReport(
            games: [GameMatchResult(game: nodumpGame, matches: [RomMatch(rom: nodumpRom, status: .missing)])],
            surplusFiles: [nodumpSurplus, surplusInArchive, unknownFile]
        )
        let report = try AuditReporter.generate(from: matchReport)

        #expect(report.entries.first { $0.name == "007766.20d.bin" && $0.game == nil }?.status == .unverifiable)
        #expect(report.entries.first { $0.name == "leftover.bin" }?.status == .surplusInArchive)
        #expect(report.entries.first { $0.name == "Screenshot.png" }?.status == .unknownFile)
        // The nodump one rolls up into its own separate `unverifiable`
        // count; only the other two share the aggregate `surplus` count —
        // the split only changes the per-entry `status`, not these summaries.
        #expect(report.surplus == 2)
        #expect(report.unverifiable == 1)
    }

    @Test("threads isOptional, mergeName, requiredBiosNames, deviceRefNames, and matchedViaHeaderStrip all together onto one real entry")
    func propagatesEveryGameAndRomLevelFieldTogether() throws {
        // Each of these fields is individually plumbed by `makeEntry` in
        // `AuditReporter.generate`, but no test ever exercised more than
        // one at a time — the "displays correctly across all app modes"
        // goal needs proof they land correctly together, since UI logic
        // downstream branches on combinations of these, not each alone.
        let rom = DATRom(name: "game.bin", size: 1, crc: nil, md5: nil, sha1: nil, mergeName: "parent-rom.bin", optional: true)
        // `romOf: "biosset"` points at a real BIOS machine also present in
        // this same scan — `biosSetNames` here is deliberately this
        // machine's OWN (unrelated) PCB variant list, proving
        // `requiredBiosNames` below resolves via `romOf`/`isBios`, not
        // `biosSetNames` (see `DATGame.resolvedBiosMachineName`'s own doc
        // comment for the real, confusing bug this distinction fixes).
        let game = DATGame(
            name: "clonewithbios", description: "Clone With BIOS", cloneOf: "parent", romOf: "biosset", roms: [rom],
            biosSetNames: ["single", "multi"], deviceRefs: ["shared_cpu"]
        )
        let biosGame = DATGame(name: "biosset", description: "Bios Set", cloneOf: nil, romOf: nil, roms: [], isBios: true)
        let local = hashedFile(name: "renamed.bin", size: 1)

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(local, viaHeaderStrip: true))]),
                GameMatchResult(game: biosGame, matches: []),
            ],
            surplusFiles: []
        )
        let report = try AuditReporter.generate(from: matchReport)

        let entry = try #require(report.entries.first { $0.game == "clonewithbios" })
        #expect(entry.isOptional == true)
        #expect(entry.mergeName == "parent-rom.bin")
        #expect(entry.requiredBiosNames == "biosset")
        #expect(entry.deviceRefNames == "shared_cpu")
        #expect(entry.matchedViaHeaderStrip == true)
        #expect(entry.cloneOf == "parent")
        #expect(entry.status == .correct)
    }
}
