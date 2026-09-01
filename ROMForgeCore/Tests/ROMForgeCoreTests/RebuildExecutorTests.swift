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
}
