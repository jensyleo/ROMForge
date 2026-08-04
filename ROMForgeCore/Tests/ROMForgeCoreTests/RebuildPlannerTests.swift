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
}
