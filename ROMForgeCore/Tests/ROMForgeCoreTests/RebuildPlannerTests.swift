// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("RebuildPlanner")
struct RebuildPlannerTests {
    private func hashedFile(name: String, in folder: URL) -> HashedFile {
        HashedFile(
            file: ScannedFile(url: folder.appendingPathComponent(name), name: name, size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        )
    }

    @Test("plans a rename for misnamed roms only, in the same folder")
    func plansRenameForMisnamedOnly() {
        let folder = URL(fileURLWithPath: "/roms")
        let correctRom = DATRom(name: "correct.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let misnamedRom = DATRom(name: "expected.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let missingRom = DATRom(name: "missing.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [correctRom, misnamedRom, missingRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: correctRom, status: .correct(hashedFile(name: "correct.bin", in: folder))),
                    RomMatch(rom: misnamedRom, status: .misnamed(hashedFile(name: "wrong-name.bin", in: folder))),
                    RomMatch(rom: missingRom, status: .missing),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan == [.rename(from: folder.appendingPathComponent("wrong-name.bin"), to: folder.appendingPathComponent("expected.bin"))])
    }

    @Test("plans a copy into <destination>/<game>/<rom name> for matched roms, skipping missing ones")
    func plansRebuildCopyIntoGameFolder() {
        let folder = URL(fileURLWithPath: "/roms")
        let destination = URL(fileURLWithPath: "/rebuilt")
        let rom = DATRom(name: "game.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let missingRom = DATRom(name: "missing.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Super Game", description: "Super Game", cloneOf: nil, romOf: nil, roms: [rom, missingRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: rom, status: .correct(hashedFile(name: "game.bin", in: folder))),
                    RomMatch(rom: missingRom, status: .missing),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: false)

        #expect(plan == [
            .copy(
                from: folder.appendingPathComponent("game.bin"),
                to: destination.appendingPathComponent("Super Game").appendingPathComponent("game.bin")
            ),
        ])
    }

    @Test("plans a move instead of a copy when move is requested")
    func plansMoveWhenRequested() {
        let folder = URL(fileURLWithPath: "/roms")
        let destination = URL(fileURLWithPath: "/rebuilt")
        let rom = DATRom(name: "game.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile(name: "game.bin", in: folder)))])],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: true)

        #expect(plan == [.move(from: folder.appendingPathComponent("game.bin"), to: destination.appendingPathComponent("Game").appendingPathComponent("game.bin"))])
    }

    @Test("planRebuildAsZip packs every matched rom into one <game>.zip, skipping missing/foundElsewhere/hashMismatch/nodump")
    func planRebuildAsZipPacksMatchedRomsOnly() {
        let folder = URL(fileURLWithPath: "/roms")
        let destination = URL(fileURLWithPath: "/rebuilt")
        let correctRom = DATRom(name: "correct.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let misnamedRom = DATRom(name: "expected.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let missingRom = DATRom(name: "missing.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let foundElsewhereRom = DATRom(name: "elsewhere.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let badDumpRom = DATRom(name: "bad.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let nodumpRom = DATRom(name: "nodump.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(
            name: "Game", description: "Game", cloneOf: nil, romOf: nil,
            roms: [correctRom, misnamedRom, missingRom, foundElsewhereRom, badDumpRom, nodumpRom]
        )

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: correctRom, status: .correct(hashedFile(name: "correct.bin", in: folder))),
                    RomMatch(rom: misnamedRom, status: .misnamed(hashedFile(name: "wrong-name.bin", in: folder))),
                    RomMatch(rom: missingRom, status: .missing),
                    RomMatch(rom: foundElsewhereRom, status: .foundElsewhere(hashedFile(name: "elsewhere.bin", in: URL(fileURLWithPath: "/roms/other")))),
                    RomMatch(rom: badDumpRom, status: .hashMismatch(hashedFile(name: "bad.bin", in: folder))),
                    RomMatch(rom: nodumpRom, status: .nodump(hashedFile(name: "nodump.bin", in: folder))),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRebuildAsZip(matchReport: matchReport, destination: destination)

        #expect(plan == [
            .createArchive(
                entries: [
                    ArchiveEntrySource(source: folder.appendingPathComponent("correct.bin"), entryName: "correct.bin"),
                    ArchiveEntrySource(source: folder.appendingPathComponent("wrong-name.bin"), entryName: "expected.bin"),
                ],
                to: destination.appendingPathComponent("Game.zip")
            ),
        ])
    }

    @Test("planRebuildAsZip produces no operation for a game with zero matched roms")
    func planRebuildAsZipSkipsGameWithNothingMatched() {
        let destination = URL(fileURLWithPath: "/rebuilt")
        let missingRom = DATRom(name: "missing.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Empty Game", description: "Empty Game", cloneOf: nil, romOf: nil, roms: [missingRom])

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: missingRom, status: .missing)])],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planRebuildAsZip(matchReport: matchReport, destination: destination).isEmpty)
    }

    @Test("safePathComponent sanitizes traversal, dot and empty segments to a single safe component")
    func safePathComponentSanitizesAdversarialInput() {
        #expect(RebuildPlanner.safePathComponent("../x") == "x")
        #expect(RebuildPlanner.safePathComponent("..") == "_")
        #expect(RebuildPlanner.safePathComponent(".") == "_")
        #expect(RebuildPlanner.safePathComponent("a/b/../c") == "c")
        #expect(RebuildPlanner.safePathComponent("normal.zip") == "normal.zip")
    }

    @Test("planRebuild sanitizes path-traversal attempts in a DAT-sourced game/rom name so the target stays inside destination")
    func planRebuildSanitizesPathTraversalInDATNames() {
        let folder = URL(fileURLWithPath: "/roms")
        let destination = URL(fileURLWithPath: "/rebuilt")
        let maliciousRom = DATRom(name: "../../../etc/passwd", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "../../evilgame", description: "evilgame", cloneOf: nil, romOf: nil, roms: [maliciousRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: maliciousRom, status: .correct(hashedFile(name: "passwd", in: folder))),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: false)

        guard case .copy(_, let target)? = plan.first else {
            Issue.record("expected a single copy operation")
            return
        }

        #expect(plan.count == 1)
        #expect(target.path.hasPrefix(destination.path))
        #expect(!target.pathComponents.contains(".."))
        #expect(target == destination.appendingPathComponent("evilgame").appendingPathComponent("passwd"))
    }
}
