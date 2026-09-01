// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("RebuildExecutor")
struct RebuildExecutorTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("renames a file in place")
    func renamesFileInPlace() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("wrong-name.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("expected.bin")

        try RebuildExecutor.execute([.rename(from: source, to: destination)])

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("copies a file into a new destination folder, creating it")
    func copiesFileCreatingDestinationFolder() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("game.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Rebuilt/Super Game/game.bin")

        try RebuildExecutor.execute([.copy(from: source, to: destination)])

        #expect(FileManager.default.fileExists(atPath: source.path), "copy must not remove the source")
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("moves a file into a new destination folder, creating it")
    func movesFileCreatingDestinationFolder() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("game.bin")
        try Data("payload".utf8).write(to: source)
        let destination = root.appendingPathComponent("Rebuilt/Super Game/game.bin")

        try RebuildExecutor.execute([.move(from: source, to: destination)])

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test("throws and does not overwrite when the destination already exists")
    func throwsWhenDestinationExists() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source.bin")
        try Data("source".utf8).write(to: source)
        let destination = root.appendingPathComponent("destination.bin")
        try Data("original".utf8).write(to: destination)

        #expect(throws: RebuildError.destinationExists(destination)) {
            try RebuildExecutor.execute([.copy(from: source, to: destination)])
        }
        #expect(try Data(contentsOf: destination) == Data("original".utf8), "existing destination must be left untouched")
    }

    @Test("throws when the source file is missing")
    func throwsWhenSourceMissing() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("missing.bin")
        let destination = root.appendingPathComponent("destination.bin")

        #expect(throws: RebuildError.sourceMissing(source)) {
            try RebuildExecutor.execute([.move(from: source, to: destination)])
        }
    }

    /// Fase 2 Step 1 end-to-end: `RebuildPlanner.planRebuild` against a
    /// synthetic two-game `MatchReport` with real files on disk, then
    /// actually executed — covers the full "classic rebuild" path
    /// `LibraryViewModel.rebuildToFolder(system:destination:move:)` drives,
    /// not just the planner's pure output (already covered in
    /// `RebuildPlannerTests`).
    @Test("rebuilds a multi-game MatchReport into <destination>/<game>/<rom> for every matched rom")
    func rebuildsMultiGameMatchReportEndToEnd() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceFolder = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("rebuilt")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)

        func hashedFile(name: String) -> HashedFile {
            let url = sourceFolder.appendingPathComponent(name)
            try? Data(name.utf8).write(to: url)
            return HashedFile(file: ScannedFile(url: url, name: name, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        }

        let romA = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [romA])
        let romB1 = DATRom(name: "b1.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let romB2 = DATRom(name: "b2.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let missingRom = DATRom(name: "missing.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameB = DATGame(name: "Game B", description: "Game B", cloneOf: nil, romOf: nil, roms: [romB1, romB2, missingRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: gameA, matches: [RomMatch(rom: romA, status: .correct(hashedFile(name: "a.bin")))]),
                GameMatchResult(game: gameB, matches: [
                    RomMatch(rom: romB1, status: .correct(hashedFile(name: "b1.bin"))),
                    RomMatch(rom: romB2, status: .correct(hashedFile(name: "b2.bin"))),
                    RomMatch(rom: missingRom, status: .missing),
                ]),
            ],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: false)
        #expect(operations.count == 3)
        try RebuildExecutor.execute(operations)

        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game A/a.bin").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game B/b1.bin").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game B/b2.bin").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game B/missing.bin").path))
        // Copy (not move): sources must survive.
        #expect(FileManager.default.fileExists(atPath: sourceFolder.appendingPathComponent("a.bin").path))
    }

    @Test("rebuilds as TorrentZip archives with correct structure (Fase 2 Step 2)")
    func rebuildsTorrentZipMultiGameEndToEnd() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceFolder = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("rebuilt_zip")
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)

        func hashedFile(name: String) -> HashedFile {
            let url = sourceFolder.appendingPathComponent(name)
            try? Data(name.utf8).write(to: url)
            return HashedFile(file: ScannedFile(url: url, name: name, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        }

        let romA = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [romA])
        let romB = DATRom(name: "b.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameB = DATGame(name: "Game B", description: "Game B", cloneOf: nil, romOf: nil, roms: [romB])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: gameA, matches: [RomMatch(rom: romA, status: .correct(hashedFile(name: "a.bin")))]),
                GameMatchResult(game: gameB, matches: [RomMatch(rom: romB, status: .correct(hashedFile(name: "b.bin")))]),
            ],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRebuildAsZip(matchReport: matchReport, destination: destination)
        #expect(operations.count == 2)
        try RebuildExecutor.execute(operations)

        // Verify .zip files were created
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game A.zip").path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Game B.zip").path))

        // Verify zips are valid (can be read back) — basic sanity check
        let zipA = destination.appendingPathComponent("Game A.zip")
        let zipData = try Data(contentsOf: zipA)
        #expect(zipData.count > 0, "ZIP file should contain data")
        #expect(zipData.starts(with: [0x50, 0x4b, 0x03, 0x04]), "ZIP file should start with PK signature")
    }

    @Test("removes only genuinely unrecognized surplus files, never one another game still needs (Fase 2 Step 7)")
    func removesOnlyGenuinelyUnrecognizedSurplusFiles() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        func hashedFile(name: String) -> HashedFile {
            let url = root.appendingPathComponent(name)
            try? Data(name.utf8).write(to: url)
            return HashedFile(file: ScannedFile(url: url, name: name, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        }

        // Genuinely unrecognized junk — the only one that should be deleted.
        let junk = SurplusFile(file: hashedFile(name: "junk.bin"))
        // Needed by another game's own archive (Split-mode leftover) — must survive.
        let neededElsewhere = SurplusFile(file: hashedFile(name: "needed.bin"), requiredByGameDescription: "Some Other Game")
        // Name matches a declared-nodump placeholder — must survive.
        let nodumpNamed = SurplusFile(file: hashedFile(name: "nodump.bin"), matchesNodumpRomName: true)

        let matchReport = MatchReport(games: [], surplusFiles: [junk, neededElsewhere, nodumpNamed])

        let operations = RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport)
        #expect(operations == [.delete(root.appendingPathComponent("junk.bin"))])

        try RebuildExecutor.execute(operations)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("junk.bin").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("needed.bin").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("nodump.bin").path))
    }
}
