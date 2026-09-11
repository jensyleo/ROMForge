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

    @Test(
        "planRepair styles the fixed File name per filesCasePolicy, always derived from the DAT's own declared name — never from the current, wrong one",
        arguments: [
            (FileCasePolicy.datafileCase, "Expected Name.bin"),
            (.uppercase, "EXPECTED NAME.BIN"),
            (.lowercase, "expected name.bin"),
            (.capitalized, "Expected Name.bin"),
            // .dontTouch has no meaning for fixing a mismatch — treated the
            // same as .datafileCase rather than leaving the wrong name alone.
            (.dontTouch, "Expected Name.bin"),
        ]
    )
    func planRepairStylesFixedNamePerPolicy(policy: FileCasePolicy, expectedName: String) {
        let folder = URL(fileURLWithPath: "/roms")
        // The DAT itself declares Mixed Case — a policy other than
        // .datafileCase must still ignore the WRONG on-disk name
        // ("wrong-name.bin", itself already lowercase) and derive the
        // result from the DAT's own name instead, not from what's there now.
        let misnamedRom = DATRom(name: "Expected Name.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [misnamedRom])
        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: misnamedRom, status: .misnamed(hashedFile(name: "wrong-name.bin", in: folder))),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: policy)

        #expect(plan == [.rename(from: folder.appendingPathComponent("wrong-name.bin"), to: folder.appendingPathComponent(expectedName))])
    }

    @Test("planRepair never plans a rename for a rom whose content lives INSIDE a zip/7z entry — that's Fix Misnamed ROMs Inside Their Archives' job, not this File-level action's")
    func planRepairSkipsEntryLevelMismatchesInsideArchives() {
        let folder = URL(fileURLWithPath: "/roms")
        let misnamedRom = DATRom(name: "expected.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [misnamedRom])
        // A zip ENTRY's own HashedFile reuses the archive's own `url` with a
        // different `name` — see `CollectionHasher`'s construction. Named
        // "Game.zip" (matching the DAT's own declared case exactly) so this
        // fixture isolates ONLY the thing this test checks — a misnamed
        // ENTRY never drives a container rename to that entry's own name —
        // without also, coincidentally, being a real container-case
        // mismatch that the newer own-archive-wrong-case rule (2026-09-10)
        // would legitimately want to fix on its own terms.
        let archiveURL = folder.appendingPathComponent("Game.zip")
        let entryFile = HashedFile(
            file: ScannedFile(url: archiveURL, name: "wrong-entry-name.bin", size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        )
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: misnamedRom, status: .misnamed(entryFile))])],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan.isEmpty, "renaming the whole archive to look like one entry's own name would be exactly wrong")
    }

    @Test("planRepair renames an archive's OWN container when it genuinely is this game's own set but sits under the wrong-case filename — jensyleo's own real-world NEOGEO test (2026-09-10)")
    func planRepairRenamesOwnArchiveWithWrongCaseContainer() {
        let folder = URL(fileURLWithPath: "/roms")
        let rom = DATRom(name: "awbios.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "awbios", description: "Neo-Geo BIOS", cloneOf: nil, romOf: nil, roms: [rom])
        // Every entry inside is individually correct by name AND hash (a
        // prior "Roms case" pass already re-styled it) — only the
        // CONTAINER's own filename still carries the wrong case.
        let archiveURL = folder.appendingPathComponent("AWBIOS.zip")
        let entryFile = HashedFile(
            file: ScannedFile(url: archiveURL, name: "awbios.bin", size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        )
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(entryFile))])],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan == [.rename(from: archiveURL, to: folder.appendingPathComponent("awbios.zip"))])
    }

    @Test("planRepair renames a wrong-case container even when its own entry is STILL misnamed too — hash identity alone proves it belongs to this game, no need to fix \"Roms case\" first — jensyleo's own real-world follow-up (2026-09-10)")
    func planRepairRenamesWrongCaseContainerEvenWithAStillMisnamedEntry() {
        let folder = URL(fileURLWithPath: "/roms")
        let rom = DATRom(name: "awbios.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "awbios", description: "Neo-Geo BIOS", cloneOf: nil, romOf: nil, roms: [rom])
        // Both halves are still wrong at once, exactly as jensyleo found
        // them on disk: the CONTAINER carries the wrong case ("AWBIOS.zip")
        // AND the entry inside it is still under its OLD, wrong-case name
        // ("AWBIOS.BIN") — no "Roms case" pass has run yet. The CRC32 hash
        // is what identifies this entry as this exact game's own rom
        // regardless of either name being wrong, so the container-rename
        // rule must not require the entry to already be `.correct` first.
        let archiveURL = folder.appendingPathComponent("AWBIOS.zip")
        let entryFile = HashedFile(
            file: ScannedFile(url: archiveURL, name: "AWBIOS.BIN", size: 1),
            hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
        )
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .misnamed(entryFile))])],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan == [.rename(from: archiveURL, to: folder.appendingPathComponent("awbios.zip"))])
    }

    @Test("planRepair renames a whole misnamed archive to the game it clearly belongs to — jensyleo's own real-world test case (2026-09-11)")
    func planRepairRenamesAWholeMisnamedArchive() {
        let folder = URL(fileURLWithPath: "/roms")
        let misnamedArchiveURL = folder.appendingPathComponent("unknown123.zip")
        // Every entry inside is individually named correctly for its own
        // rom — this archive would never produce a single `.misnamed` rom
        // match on its own; only the CONTAINER's own name is wrong.
        let surplusFile = SurplusFile(
            file: HashedFile(file: ScannedFile(url: misnamedArchiveURL, name: "sfiii.06", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")),
            misnamedArchiveForGameName: "sfiii"
        )
        let matchReport = MatchReport(games: [], surplusFiles: [surplusFile])

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan == [.rename(from: misnamedArchiveURL, to: folder.appendingPathComponent("sfiii.zip"))])
    }

    @Test("planRepair plans ONE rename per misnamed archive, however many surplus ROMs inside it carry the same flag")
    func planRepairDeduplicatesAMisnamedArchiveAcrossItsOwnEntries() {
        let folder = URL(fileURLWithPath: "/roms")
        let misnamedArchiveURL = folder.appendingPathComponent("unknown123.zip")
        // `ROMMatcher.annotateMisnamedArchives` stamps
        // `misnamedArchiveForGameName` onto EVERY surplus entry inside the
        // archive — it has no archive-level row of its own to stamp. Five
        // entries therefore arrive as five SurplusFiles all naming the SAME
        // container. Renaming a File is one operation on one File: before
        // the dedup, this planned five identical renames, of which the
        // first succeeded and the other four failed `sourceMissing`.
        let surplusFiles = ["sfiii.06", "sfiii.07", "sfiii.08", "sfiii.09", "sfiii.10"].map { entryName in
            SurplusFile(
                file: HashedFile(file: ScannedFile(url: misnamedArchiveURL, name: entryName, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")),
                misnamedArchiveForGameName: "sfiii"
            )
        }
        let matchReport = MatchReport(games: [], surplusFiles: surplusFiles)

        let plan = RebuildPlanner.planRepair(matchReport: matchReport)

        #expect(plan == [.rename(from: misnamedArchiveURL, to: folder.appendingPathComponent("sfiii.zip"))])
    }

    @Test("planRepair styles a whole misnamed archive's new name per filesCasePolicy, same as any other File-level fix", arguments: [
        (FileCasePolicy.uppercase, "SFIII.ZIP"),
        (.lowercase, "sfiii.zip"),
        (.capitalized, "Sfiii.zip"),
    ])
    func planRepairStylesAWholeMisnamedArchivePerPolicy(policy: FileCasePolicy, expectedName: String) {
        let folder = URL(fileURLWithPath: "/roms")
        let misnamedArchiveURL = folder.appendingPathComponent("unknown123.zip")
        let surplusFile = SurplusFile(
            file: HashedFile(file: ScannedFile(url: misnamedArchiveURL, name: "sfiii.06", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")),
            misnamedArchiveForGameName: "sfiii"
        )
        let matchReport = MatchReport(games: [], surplusFiles: [surplusFile])

        let plan = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: policy)

        #expect(plan == [.rename(from: misnamedArchiveURL, to: folder.appendingPathComponent(expectedName))])
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
            .createTorrentZipArchive(
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
