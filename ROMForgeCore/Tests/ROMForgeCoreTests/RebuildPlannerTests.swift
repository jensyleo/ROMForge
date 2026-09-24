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

    // MARK: - planCreateDummyRoms

    @Test("plans a dummy loose file only for a nodump rom ROMMatcher left entirely unclaimed")
    func plansDummyForMissingNodumpRomOnly() {
        // jensyleo's own report (2026-09-13, via Claude's own live testing):
        // `ROMMatcher.match` never assigns `.missing` to an unclaimed
        // `nodump` rom at all — it's simply left OUT of `matches`
        // entirely (see that function's own doc comment for why: "nothing
        // the user could even do about it"). A real `missingGoodRom` DOES
        // get a genuine `.missing` `RomMatch` — only the DAT-declared
        // nodump rom is missing from `matches` here, matching what a real
        // scan actually produces.
        let folder = URL(fileURLWithPath: "/roms")
        let nodumpRom = DATRom(name: "undumped.bin", size: 7, crc: nil, md5: nil, sha1: nil, status: .nodump)
        let missingGoodRom = DATRom(name: "regular-missing.bin", size: 3, crc: nil, md5: nil, sha1: nil)
        let anchorRom = DATRom(name: "present.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [anchorRom, nodumpRom, missingGoodRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: anchorRom, status: .correct(hashedFile(name: "present.bin", in: folder))),
                    RomMatch(rom: missingGoodRom, status: .missing),
                ]),
            ],
            surplusFiles: []
        )

        let plan = RebuildPlanner.planCreateDummyRoms(matchReport: matchReport)

        #expect(plan == [.createDummyFile(at: folder.appendingPathComponent("undumped.bin"), size: 7)])
    }

    @Test("never plans a dummy for a nodump rom that already has some file present")
    func skipsDummyWhenNodumpRomAlreadyPresent() {
        let folder = URL(fileURLWithPath: "/roms")
        let nodumpRom = DATRom(name: "undumped.bin", size: 7, crc: nil, md5: nil, sha1: nil, status: .nodump)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [nodumpRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: nodumpRom, status: .nodump(hashedFile(name: "undumped.bin", in: folder))),
                ]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planCreateDummyRoms(matchReport: matchReport).isEmpty)
    }

    // MARK: - planRemoveZipComments / matchedZipArchiveURLs

    @Test("matchedZipArchiveURLs finds one distinct matched zip, not per rom")
    func matchedZipArchiveURLsFindsOneDistinctZip() {
        let zip = URL(fileURLWithPath: "/roms/Game.zip")
        let rom1 = DATRom(name: "rom1.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let rom2 = DATRom(name: "rom2.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom1, rom2])
        let entry1 = HashedFile(file: ScannedFile(url: zip, name: "rom1.bin", size: 1), hash: FileHash(crc32: "a", md5: "0", sha1: "0"))
        let entry2 = HashedFile(file: ScannedFile(url: zip, name: "rom2.bin", size: 1), hash: FileHash(crc32: "b", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: rom1, status: .correct(entry1)),
                    RomMatch(rom: rom2, status: .correct(entry2)),
                ]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.matchedZipArchiveURLs(matchReport: matchReport) == [zip])
    }

    @Test("matchedZipArchiveURLs finds nothing for a loose (non-zip) rom")
    func matchedZipArchiveURLsFindsNothingForLooseRom() {
        let folder = URL(fileURLWithPath: "/roms")
        let rom = DATRom(name: "loose.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: rom, status: .correct(hashedFile(name: "loose.bin", in: folder))),
                ]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.matchedZipArchiveURLs(matchReport: matchReport).isEmpty)
    }

    @Test("planRemoveZipComments plans one .clearZipComment per archive it's given, and nothing for an archive that isn't in the set — jensyleo's own real incident (2026-09-22): the OLD version planned a removal for every matched zip unconditionally, offering \"Remove Zip Comment…\" for gryzor.zip, which never had one")
    func planRemoveZipCommentsOnlyPlansGivenArchives() {
        let withComment = URL(fileURLWithPath: "/roms/dlair.zip")
        let plan = RebuildPlanner.planRemoveZipComments(archivesWithComments: [withComment])
        #expect(plan == [.clearZipComment(archive: withComment)])
    }

    @Test("planRemoveZipComments plans nothing for an empty set")
    func planRemoveZipCommentsEmptyForNoComments() {
        #expect(RebuildPlanner.planRemoveZipComments(archivesWithComments: []).isEmpty)
    }

    // MARK: - planCollectSamples

    @Test("plans one copy per needed sample set name that was actually found")
    func plansOneCopyPerFoundSampleSet() {
        let samplesFolder = URL(fileURLWithPath: "/samples")
        let found = URL(fileURLWithPath: "/roms/qbert.zip")

        let plan = RebuildPlanner.planCollectSamples(
            neededSetNames: ["qbert", "gorf"],
            foundSampleZips: ["qbert": found],
            samplesFolder: samplesFolder
        )

        #expect(plan == [.copy(from: found, to: samplesFolder.appendingPathComponent("qbert.zip"))])
    }

    @Test("plans nothing for a needed sample set that was never found")
    func plansNothingForUnfoundSampleSet() {
        let plan = RebuildPlanner.planCollectSamples(
            neededSetNames: ["gorf"],
            foundSampleZips: [:],
            samplesFolder: URL(fileURLWithPath: "/samples")
        )

        #expect(plan.isEmpty)
    }

    @Test("sanitizes a path-traversal sample set name before appending it to the samples folder")
    func planCollectSamplesSanitizesTraversal() {
        let found = URL(fileURLWithPath: "/roms/evil.zip")
        let samplesFolder = URL(fileURLWithPath: "/samples")

        let plan = RebuildPlanner.planCollectSamples(
            neededSetNames: ["../../etc/passwd"],
            foundSampleZips: ["../../etc/passwd": found],
            samplesFolder: samplesFolder
        )

        guard case .copy(_, let destination)? = plan.first else {
            Issue.record("expected a single copy operation")
            return
        }
        #expect(plan.count == 1)
        #expect(destination == samplesFolder.appendingPathComponent("passwd.zip"))
    }

    // jensyleo's own report (2026-09-16), first real-collection test of
    // "Remove Redundant Files…": several rows clearly read "Duplicated
    // archive, not needed here (required by X)" for a leftover CHD copy,
    // but the action reported nothing to remove — CHD/disk audit entries
    // never flow through `MatchReport`, so `planRemoveRedundantFiles`
    // (which only reads `matchReport.surplusFiles`) could never see them.
    @Test("planRemoveRedundantDisks deletes a leftover duplicate CHD the DAT recognizes elsewhere, never a disk's own primary/correct copy")
    func planRemoveRedundantDisksDeletesOnlyTheDuplicate() {
        let primary = URL(fileURLWithPath: "/roms/kinst/kinst.chd")
        let duplicate = URL(fileURLWithPath: "/roms/other/kinst.chd")
        let entries = [
            AuditEntry(status: .correct, game: "kinst", isDisk: true, name: "kinst.chd", path: primary),
            AuditEntry(status: .incorrect, game: nil, isDisk: true, requiredByGameDescription: "Killer Instinct", requiredByGameConfirmedRedundant: true, name: "kinst.chd", path: duplicate),
            // A genuinely unrecognized CHD (no `requiredByGameDescription`)
            // must never be swept up here — that's "Remove Useless Files"'s
            // job, not this one's, mirroring the rom-level split above.
            AuditEntry(status: .surplus, game: nil, isDisk: true, name: "unknown.chd", path: URL(fileURLWithPath: "/roms/other/unknown.chd")),
        ]

        let plan = RebuildPlanner.planRemoveRedundantDisks(auditEntries: entries)

        #expect(plan == [RebuildOperation.delete(duplicate)])
    }

    // jensyleo's own follow-up (2026-09-16), same session: a redundant
    // rom living as an entry inside a `.7z` (no ROMForge support for
    // rewriting `.7z` entries) was left untouched even when the DAT
    // recognizes it fine elsewhere — "pensaría que debería eliminarse en
    // Redundant Files si y solo si el contenido de las roms son
    // exactamente iguales... aunque tengan extensión diferente". Real
    // case: a whole BIOS set (several roms, not just one) re-packed as
    // `.7z`, every single entry independently already redundant — safe to
    // delete the whole container since NOTHING legitimate is left inside,
    // regardless of how many entries it actually holds.
    @Test("planRemoveRedundantWholeArchives deletes a whole .7z when EVERY one of its entries is independently redundant, never when only SOME are")
    func planRemoveRedundantWholeArchivesWhenFullyRedundant() {
        let fullyRedundantContainer = URL(fileURLWithPath: "/roms/nss.7z")
        let partiallyRedundantContainer = URL(fileURLWithPath: "/roms/mixed.7z")
        let surplusFiles = [
            // The whole BIOS set, repacked as .7z — every one of its 2
            // (for this test) roms is independently redundant.
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: fullyRedundantContainer, name: "chip0.bin", size: 1),
                    hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Nintendo Super System BIOS", requiredByGameConfirmedRedundant: true
            ),
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: fullyRedundantContainer, name: "chip1.bin", size: 1),
                    hash: FileHash(crc32: "cccccccc", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Nintendo Super System BIOS", requiredByGameConfirmedRedundant: true
            ),
            // Only ONE of this container's real 2 entries is redundant —
            // the other one (not represented as a `SurplusFile` at all,
            // since it's legitimately claimed) must keep the whole archive
            // alive.
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: partiallyRedundantContainer, name: "other.bin", size: 1),
                    hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Some Other Game", requiredByGameConfirmedRedundant: true
            ),
        ]
        let matchReport = MatchReport(games: [], surplusFiles: surplusFiles)

        let plan = RebuildPlanner.planRemoveRedundantWholeArchives(
            matchReport: matchReport, entryCounts: [fullyRedundantContainer: 2, partiallyRedundantContainer: 2]
        )

        #expect(plan == [RebuildOperation.delete(fullyRedundantContainer)])
    }

    @Test("planRemoveRedundantWholeArchives generalizes to .zip too, and planRemoveRedundantRoms excludes whatever it claims — jensyleo's own explicit request (2026-09-17), after CAPCOM/CPS2/naomi.zip (one redundant rom, nothing else) only ever offered removing the one entry, leaving a pointless empty zip behind")
    func planRemoveRedundantWholeArchivesGeneralizesToZip() {
        let fullyRedundantZip = URL(fileURLWithPath: "/roms/CPS2/naomi.zip")
        let partiallyRedundantZip = URL(fileURLWithPath: "/roms/mixed.zip")
        let surplusFiles = [
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: fullyRedundantZip, name: "epr-21580a.ic27", size: 1),
                    hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Naomi Bios", requiredByGameMachineName: "naomi", requiredByGameConfirmedRedundant: true
            ),
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: partiallyRedundantZip, name: "other.bin", size: 1),
                    hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Some Other Game", requiredByGameConfirmedRedundant: true,
                requiredByGameOwnerSatisfiedElsewhere: true
            ),
        ]
        let matchReport = MatchReport(games: [], surplusFiles: surplusFiles)
        let entryCounts: [URL: Int] = [fullyRedundantZip: 1, partiallyRedundantZip: 2]

        let wholeArchivePlan = RebuildPlanner.planRemoveRedundantWholeArchives(matchReport: matchReport, entryCounts: entryCounts)
        #expect(wholeArchivePlan == [RebuildOperation.delete(fullyRedundantZip)])

        let fullyRedundant = RebuildPlanner.fullyRedundantArchiveContainers(matchReport: matchReport, entryCounts: entryCounts)
        let romPlan = RebuildPlanner.planRemoveRedundantRoms(matchReport: matchReport, fullyRedundantContainers: fullyRedundant)
        #expect(romPlan == [RebuildOperation.removeEntryFromZip(archive: partiallyRedundantZip, entryName: "other.bin")], "the fully-redundant naomi.zip must be excluded here — it's the whole-archive plan's job instead")
    }

    // jensyleo's own request (2026-09-23): "Debe buscar en todos los ROM
    // folders y moverlos a la carpeta BIOS. Si hay repetidos, los
    // elimina." — a BIOS's own real container (found under some other ROM
    // folder, still sitting there as a loose file/its own zip) gets moved
    // into the BIOS folder; a redundant further copy elsewhere is removed
    // ONLY once confirmed safe via the same `requiredByGameOwnerSatisfiedElsewhere`
    // guard "Remove Redundant Files…" already relies on — never a plain
    // "delete every duplicate" pass.
    @Test("planOrganizeBIOSFiles moves a BIOS's own loose file into the BIOS folder, and removes only a redundant copy already confirmed safe elsewhere")
    func planOrganizeBIOSFilesMovesAndDedups() {
        let biosFolder = URL(fileURLWithPath: "/roms/BIOS")
        let biosOwnFile = URL(fileURLWithPath: "/roms/neogeo/neogeo.zip")
        let redundantCopy = URL(fileURLWithPath: "/roms/mvs/neogeo.zip")
        let unsafeCopy = URL(fileURLWithPath: "/roms/other/neogeo.zip")

        let biosGame = DATGame(
            name: "neogeo", description: "Neo Geo BIOS", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "sp1.jipan.1024", size: 1, crc: "aaaaaaaa", md5: nil, sha1: nil)],
            isBios: true
        )
        let matches = [
            RomMatch(
                rom: DATRom(name: "sp1.jipan.1024", size: 1, crc: "aaaaaaaa", md5: nil, sha1: nil),
                status: .correct(HashedFile(
                    file: ScannedFile(url: biosOwnFile, name: "sp1.jipan.1024", size: 1),
                    hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
                ))
            ),
        ]
        let surplusFiles = [
            // Confirmed safe — the BIOS already has its own real copy
            // (`biosOwnFile`) — this duplicate is fair game to remove.
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: redundantCopy, name: "neogeo.zip", size: 1),
                    hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Neo Geo BIOS", requiredByGameMachineName: "neogeo",
                requiredByGameOwnerSatisfiedElsewhere: true
            ),
            // NOT confirmed safe (`requiredByGameOwnerSatisfiedElsewhere ==
            // false`, the default) — must survive untouched, same
            // protection `removeRedundantFiles` already relies on.
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: unsafeCopy, name: "neogeo.zip", size: 1),
                    hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "Neo Geo BIOS", requiredByGameMachineName: "neogeo"
            ),
        ]
        let matchReport = MatchReport(games: [GameMatchResult(game: biosGame, matches: matches)], surplusFiles: surplusFiles)

        let plan = RebuildPlanner.planOrganizeBIOSFiles(matchReport: matchReport, biosFolder: biosFolder)

        #expect(plan.contains(.move(from: biosOwnFile, to: biosFolder.appendingPathComponent("neogeo.zip"))))
        #expect(plan.contains(.delete(redundantCopy)))
        #expect(!plan.contains(.delete(unsafeCopy)))
        #expect(plan.count == 2)
    }

    // jensyleo's own request (2026-09-24), after a long, sourced
    // investigation confirming MAME's own official "Device set" concept
    // (docs.mamedev.org/usingmame/aboutromsets.html: "Device sets contain
    // reusable circuit designs and their associated firmware... the exact
    // same NAMCO51.ZIP-style pattern as a BIOS") — "lo mismo que BIOS pero
    // para los demás chips." His own explicit exclusion rule, confirmed
    // with real DAT data: a chip's rom that's genuinely embedded INSIDE a
    // playable game's own archive (like CPS2's own QSound sample roms,
    // `region="qsound"`, declared directly under the game's own machine)
    // must never be swept up here — only the chip's own SEPARATE device
    // machine (like QSound's real firmware, `dl-1425.bin`, confirmed via
    // archive.org's own mame-0.221-roms-merged listing to ship as its own
    // "qsound.zip") counts.
    @Test("planOrganizeComplementaryChips moves a device machine's own container, and never touches a normal game's own archive even if that game embeds a same-family rom of its own")
    func planOrganizeComplementaryChipsMovesDeviceOnly() {
        let chipsFolder = URL(fileURLWithPath: "/roms/ComplementaryChips")
        let chipOwnFile = URL(fileURLWithPath: "/roms/cps2/qsound.zip")
        let redundantCopy = URL(fileURLWithPath: "/roms/other/qsound.zip")

        let chipMachine = DATGame(
            name: "qsound", description: "QSound", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "dl-1425.bin", size: 24576, crc: "d6cf5ef5", md5: nil, sha1: nil)],
            isDevice: true
        )
        let chipMatches = [
            RomMatch(
                rom: DATRom(name: "dl-1425.bin", size: 24576, crc: "d6cf5ef5", md5: nil, sha1: nil),
                status: .correct(HashedFile(
                    file: ScannedFile(url: chipOwnFile, name: "dl-1425.bin", size: 24576),
                    hash: FileHash(crc32: "d6cf5ef5", md5: "0", sha1: "0")
                ))
            ),
        ]
        // A perfectly ordinary game, own archive, own embedded sample rom
        // — never a device, never touched by this planner at all, even
        // though it happens to live in a "qsound"-adjacent family.
        let normalGame = DATGame(
            name: "1944", description: "1944: The Loop Master", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "nff.11m", size: 4194304, crc: "243e4e05", md5: nil, sha1: nil)]
        )
        let normalMatches = [
            RomMatch(
                rom: DATRom(name: "nff.11m", size: 4194304, crc: "243e4e05", md5: nil, sha1: nil),
                status: .correct(HashedFile(
                    file: ScannedFile(url: URL(fileURLWithPath: "/roms/cps2/1944.zip"), name: "nff.11m", size: 4194304),
                    hash: FileHash(crc32: "243e4e05", md5: "0", sha1: "0")
                ))
            ),
        ]
        let surplusFiles = [
            SurplusFile(
                file: HashedFile(
                    file: ScannedFile(url: redundantCopy, name: "qsound.zip", size: 24576),
                    hash: FileHash(crc32: "d6cf5ef5", md5: "0", sha1: "0")
                ),
                requiredByGameDescription: "QSound", requiredByGameMachineName: "qsound",
                requiredByGameOwnerSatisfiedElsewhere: true
            ),
        ]
        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: chipMachine, matches: chipMatches),
                GameMatchResult(game: normalGame, matches: normalMatches),
            ],
            surplusFiles: surplusFiles
        )

        let plan = RebuildPlanner.planOrganizeComplementaryChips(matchReport: matchReport, chipsFolder: chipsFolder)

        #expect(plan.contains(.move(from: chipOwnFile, to: chipsFolder.appendingPathComponent("qsound.zip"))))
        #expect(plan.contains(.delete(redundantCopy)))
        #expect(!plan.contains(where: { operation in
            if case .move(let from, _) = operation { return from.lastPathComponent == "1944.zip" }
            if case .delete(let url) = operation { return url.lastPathComponent == "1944.zip" }
            return false
        }))
        #expect(plan.count == 2)
    }
}
