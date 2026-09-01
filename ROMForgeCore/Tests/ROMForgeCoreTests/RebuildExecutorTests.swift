// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("RebuildExecutor")
struct RebuildExecutorTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Builds a real `.zip` with the given entry name → content pairs, for
    /// tests that need a genuine archived-rom scenario (as opposed to every
    /// other test in this file, which uses loose files).
    private func makeZip(at url: URL, entries: [(name: String, content: String)]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for entry in entries {
            let data = Data(entry.content.utf8)
            try archive.addEntry(with: entry.name, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
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

    // MARK: - Zip-sourced roms (jensyleo's own report, 2026-09-01 — see
    // `RebuildOperation.extractZipEntry`'s own doc comment for the bug this
    // whole section guards against: a naive `.copy`/`.move`/`.delete` on a
    // zip-entry `HashedFile`'s own `.file.url` silently touches the WHOLE
    // containing archive instead of the one rom entry it actually names).

    @Test("rebuilds a rom that lives inside a zip by extracting just that entry, not copying the whole archive")
    func rebuildExtractsSingleEntryFromZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("gamea.zip")
        try makeZip(at: zipURL, entries: [
            ("a.bin", "AAAA-content"),
            ("b.bin", "BBBB-content"),
        ])
        let destination = root.appendingPathComponent("rebuilt")

        let romA = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let romB = DATRom(name: "b.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [romA, romB])

        func zipEntryFile(name: String) -> HashedFile {
            HashedFile(file: ScannedFile(url: zipURL, name: name, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        }

        let matchReport = MatchReport(
            games: [GameMatchResult(game: gameA, matches: [
                RomMatch(rom: romA, status: .correct(zipEntryFile(name: "a.bin"))),
                RomMatch(rom: romB, status: .correct(zipEntryFile(name: "b.bin"))),
            ])],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRebuild(matchReport: matchReport, destination: destination, move: false)
        #expect(operations == [
            .extractZipEntry(archive: zipURL, entryName: "a.bin", to: destination.appendingPathComponent("Game A/a.bin")),
            .extractZipEntry(archive: zipURL, entryName: "b.bin", to: destination.appendingPathComponent("Game A/b.bin")),
        ])
        try RebuildExecutor.execute(operations)

        let extractedA = try String(contentsOf: destination.appendingPathComponent("Game A/a.bin"), encoding: .utf8)
        let extractedB = try String(contentsOf: destination.appendingPathComponent("Game A/b.bin"), encoding: .utf8)
        #expect(extractedA == "AAAA-content", "must be that entry's own content, not the whole zip's bytes")
        #expect(extractedB == "BBBB-content")
        // The source zip itself must be untouched — `move: false`.
        #expect(FileManager.default.fileExists(atPath: zipURL.path))
    }

    @Test("rebuilds as TorrentZip from zip-sourced roms by reading each entry's real bytes")
    func rebuildAsZipReadsRealEntryBytesFromSourceZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceZipURL = root.appendingPathComponent("gamea.zip")
        try makeZip(at: sourceZipURL, entries: [("a.bin", "AAAA-content")])
        let destination = root.appendingPathComponent("rebuilt_zip")

        let romA = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [romA])
        let hashedFile = HashedFile(file: ScannedFile(url: sourceZipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: gameA, matches: [RomMatch(rom: romA, status: .correct(hashedFile))])],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRebuildAsZip(matchReport: matchReport, destination: destination)
        try RebuildExecutor.execute(operations)

        let rebuiltZipURL = destination.appendingPathComponent("Game A.zip")
        let archive = try Archive(url: rebuiltZipURL, accessMode: .read)
        guard let entry = archive["a.bin"] else {
            Issue.record("rebuilt zip is missing its own \"a.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "AAAA-content", "must be that entry's own content, not the whole source zip's bytes")
    }

    @Test("removes only the unrecognized entry from inside a zip, never the whole archive")
    func removesOnlyUnrecognizedEntryFromZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("mixed.zip")
        try makeZip(at: zipURL, entries: [("junk.bin", "junk-content"), ("needed.bin", "needed-content")])

        let surplusInZip = SurplusFile(file: HashedFile(file: ScannedFile(url: zipURL, name: "junk.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))
        let matchReport = MatchReport(games: [], surplusFiles: [surplusInZip])

        let operations = RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport)
        #expect(operations == [.removeEntryFromZip(archive: zipURL, entryName: "junk.bin")])

        try RebuildExecutor.execute(operations)
        #expect(FileManager.default.fileExists(atPath: zipURL.path), "the archive itself must survive")
        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["junk.bin"] == nil, "the unrecognized entry must be gone")
        #expect(archive["needed.bin"] != nil, "every OTHER rom in the same archive must survive untouched")
    }

    @Test("still excludes a 7z-sourced surplus entry entirely — no 7z-entry removal support")
    func excludesSevenZipSourcedSurplusFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let sevenZipURL = root.appendingPathComponent("mixed.7z")
        try Data("fake 7z content".utf8).write(to: sevenZipURL)

        let surplusInSevenZip = SurplusFile(file: HashedFile(file: ScannedFile(url: sevenZipURL, name: "junk.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))
        let matchReport = MatchReport(games: [], surplusFiles: [surplusInSevenZip])

        #expect(RebuildPlanner.planRemoveUselessFiles(matchReport: matchReport).isEmpty)
    }

    // MARK: - Cross-set repair (Fase 2 Step 3)

    @Test("repairs a missing rom by borrowing it from a sibling clone's own zip, adding it into the broken set's existing zip in place")
    func crossSetRepairAddsMissingRomFromSiblingZipIntoOwnZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // "Game A" (parent) is missing "shared.bin"; "Game A Clone" (its
        // clone) already has the exact same rom, correctly, in its own zip.
        let parentZip = root.appendingPathComponent("gamea.zip")
        try makeZip(at: parentZip, entries: [("a-only.bin", "A-only-content")])
        let cloneZip = root.appendingPathComponent("gameaclone.zip")
        try makeZip(at: cloneZip, entries: [("shared.bin", "shared-content")])

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let aOnlyRom = DATRom(name: "a-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [aOnlyRom, sharedRom])
        let gameAClone = DATGame(name: "Game A Clone", description: "Game A Clone", cloneOf: "Game A", romOf: "Game A", roms: [sharedRom])

        func hashed(url: URL, name: String) -> HashedFile {
            HashedFile(file: ScannedFile(url: url, name: name, size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))
        }

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: gameA, matches: [
                    RomMatch(rom: aOnlyRom, status: .correct(hashed(url: parentZip, name: "a-only.bin"))),
                    RomMatch(rom: sharedRom, status: .missing),
                ]),
                GameMatchResult(game: gameAClone, matches: [
                    RomMatch(rom: sharedRom, status: .correct(hashed(url: cloneZip, name: "shared.bin"))),
                ]),
            ],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planCrossSetRepair(matchReport: matchReport)
        #expect(operations.count == 1)
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: parentZip, accessMode: .read)
        guard let entry = archive["shared.bin"] else {
            Issue.record("Game A's own zip should now contain the borrowed \"shared.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "shared-content")
        // The original entry the borrowed rom already had must still exist too.
        #expect(archive["a-only.bin"] != nil)
        // The donor's own zip must survive completely untouched.
        #expect(FileManager.default.fileExists(atPath: cloneZip.path))
    }

    @Test("never repairs a game with no existing anchor of its own, even if a sibling has the missing rom")
    func crossSetRepairSkipsGameWithNoExistingAnchor() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cloneZip = root.appendingPathComponent("gameaclone.zip")
        try makeZip(at: cloneZip, entries: [("shared.bin", "shared-content")])

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        // "Game A" has EVERY rom missing — no anchor to add a borrowed rom into.
        let gameA = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [sharedRom])
        let gameAClone = DATGame(name: "Game A Clone", description: "Game A Clone", cloneOf: "Game A", romOf: "Game A", roms: [sharedRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: gameA, matches: [RomMatch(rom: sharedRom, status: .missing)]),
                GameMatchResult(game: gameAClone, matches: [
                    RomMatch(rom: sharedRom, status: .correct(HashedFile(file: ScannedFile(url: cloneZip, name: "shared.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")))),
                ]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planCrossSetRepair(matchReport: matchReport).isEmpty)
    }

    // MARK: - Convert to non-merged (Fase 2 Step 4)

    @Test("makes a clone self-contained by copying its parent's rom (found elsewhere) into the clone's own zip")
    func convertToNonMergedCopiesFoundElsewhereRomIntoOwnZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [("shared.bin", "shared-content")])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("clone-only.bin", "clone-only-content")])

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let cloneOnlyRom = DATRom(name: "clone-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [sharedRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [cloneOnlyRom, sharedRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "shared.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))
        let cloneOnlyHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "clone-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: sharedRom, status: .correct(parentHashedFile))]),
                // Under the clone's own configured merge mode, "shared.bin" is
                // satisfied by the PARENT's archive — `.foundElsewhere` — while
                // the clone's own zip only has its own unique rom so far.
                GameMatchResult(game: cloneGame, matches: [
                    RomMatch(rom: cloneOnlyRom, status: .correct(cloneOnlyHashedFile)),
                    RomMatch(rom: sharedRom, status: .foundElsewhere(parentHashedFile)),
                ]),
            ],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planConvertToNonMerged(matchReport: matchReport)
        #expect(operations == [.addEntryToZip(targetArchive: cloneZip, entryName: "shared.bin", source: ArchiveEntrySource(source: parentZip, entryName: "shared.bin", sourceArchiveEntryName: "shared.bin"))])

        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: cloneZip, accessMode: .read)
        #expect(archive["clone-only.bin"] != nil, "the clone's own pre-existing rom must survive")
        guard let entry = archive["shared.bin"] else {
            Issue.record("clone's own zip should now contain the copied-in \"shared.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "shared-content")
        // The parent's own zip — the donor — must survive completely untouched.
        let parentArchive = try Archive(url: parentZip, accessMode: .read)
        #expect(parentArchive["shared.bin"] != nil)
    }

    // MARK: - Rename roms inside archives (Fase 2 Step 6)

    @Test("renames a misnamed rom entry inside a zip via add-then-remove, preserving its content and every sibling entry")
    func renamesRomEntryInsideZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("wrong-name.bin", "the-real-content"), ("other.bin", "other-content")])

        let rom = DATRom(name: "correct-name.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let otherRom = DATRom(name: "other.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom, otherRom])

        let misnamedFile = HashedFile(file: ScannedFile(url: zipURL, name: "wrong-name.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))
        let otherFile = HashedFile(file: ScannedFile(url: zipURL, name: "other.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: rom, status: .misnamed(misnamedFile)),
                RomMatch(rom: otherRom, status: .correct(otherFile)),
            ])],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport)
        #expect(operations == [
            .addEntryToZip(targetArchive: zipURL, entryName: "correct-name.bin", source: ArchiveEntrySource(source: zipURL, entryName: "correct-name.bin", sourceArchiveEntryName: "wrong-name.bin")),
            .removeEntryFromZip(archive: zipURL, entryName: "wrong-name.bin"),
        ])
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["wrong-name.bin"] == nil, "the old-named entry must be gone")
        #expect(archive["other.bin"] != nil, "the untouched sibling entry must survive")
        guard let renamed = archive["correct-name.bin"] else {
            Issue.record("zip should now contain the renamed entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(renamed) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "the-real-content", "the renamed entry must keep its original content")
    }

    @Test("never plans a rename for a rom already using its expected entry name")
    func doesNotRenameAlreadyCorrectlyNamedEntry() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("correct-name.bin", "content")])

        let rom = DATRom(name: "correct-name.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "correct-name.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .misnamed(hashedFile))])],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport).isEmpty)
    }
}
