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

    @Test("RebuildError.localizedDescription returns the SPECIFIC message, not Foundation's generic fallback")
    func rebuildErrorLocalizedDescriptionIsSpecific() {
        // jensyleo's own instruction (2026-09-10) to review the app's whole
        // logging for coherence surfaced this: `RebuildError` used to
        // conform only to `CustomStringConvertible`, so `.localizedDescription`
        // (called by every write action's own `failureLines`, added the
        // same day to fix "la opción de fix sigue sin funcionar") fell back
        // to Foundation's generic NSError-bridged text — something like
        // "The operation couldn't be completed." — instead of ever showing
        // the real, specific reason below. This is the exact property
        // every one of those "Could not <do the thing>: <this message>"
        // log lines depends on to be worth anything at all.
        let error: Error = RebuildError.sourceMissing(URL(fileURLWithPath: "/roms/missing.zip"))
        #expect(error.localizedDescription == "Source file does not exist: /roms/missing.zip")
        #expect(!error.localizedDescription.contains("couldn't be completed"), "must never fall back to Foundation's generic bridged text")
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

    // MARK: - Remove Redundant Files/ROMs (jensyleo's own request, 2026-09-13
    // — the exact complement of "Remove Useless Files": a `SurplusFile` the
    // DAT DOES recognize, just not needed at this exact location.)

    @Test("deletes a loose redundant file the DAT recognizes elsewhere, leaves genuinely unrecognized junk and same-archive duplicates alone")
    func removesOnlyLooseRedundantFiles() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        func hashedFile(name: String) -> HashedFile {
            let url = root.appendingPathComponent(name)
            try? Data(name.utf8).write(to: url)
            return HashedFile(file: ScannedFile(url: url, name: name, size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        }

        let redundant = SurplusFile(
            file: hashedFile(name: "redundant.bin"), requiredByGameDescription: "Some Other Game",
            requiredByGameConfirmedRedundant: true, requiredByGameOwnerSatisfiedElsewhere: true
        )
        let junk = SurplusFile(file: hashedFile(name: "junk.bin"))
        let matchReport = MatchReport(games: [], surplusFiles: [redundant, junk])

        let operations = RebuildPlanner.planRemoveRedundantFiles(matchReport: matchReport)
        #expect(operations == [.delete(root.appendingPathComponent("redundant.bin"))])

        try RebuildExecutor.execute(operations)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("redundant.bin").path))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("junk.bin").path))
    }

    @Test("removes only a redundant ENTRY inside a zip, never the whole archive, never a loose file")
    func removesOnlyRedundantEntryFromZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("mixed.zip")
        try makeZip(at: zipURL, entries: [("redundant.bin", "redundant-content"), ("needed.bin", "needed-content")])

        let redundantInZip = SurplusFile(
            file: HashedFile(file: ScannedFile(url: zipURL, name: "redundant.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")),
            requiredByGameDescription: "Some Other Game", requiredByGameConfirmedRedundant: true, requiredByGameOwnerSatisfiedElsewhere: true
        )
        let looseRedundant = SurplusFile(
            file: HashedFile(file: ScannedFile(url: root.appendingPathComponent("loose.bin"), name: "loose.bin", size: 1), hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0")),
            requiredByGameDescription: "Some Other Game", requiredByGameConfirmedRedundant: true, requiredByGameOwnerSatisfiedElsewhere: true
        )
        let matchReport = MatchReport(games: [], surplusFiles: [redundantInZip, looseRedundant])

        let operations = RebuildPlanner.planRemoveRedundantRoms(matchReport: matchReport)
        #expect(operations == [.removeEntryFromZip(archive: zipURL, entryName: "redundant.bin")])

        try RebuildExecutor.execute(operations)
        #expect(FileManager.default.fileExists(atPath: zipURL.path), "the archive itself must survive")
        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["redundant.bin"] == nil, "the redundant entry must be gone")
        #expect(archive["needed.bin"] != nil, "every OTHER rom in the same archive must survive untouched")
    }

    @Test("a genuinely unrecognized surplus file is never touched by either redundant-removal planner")
    func redundantPlannersIgnoreGenuinelyUnrecognizedJunk() throws {
        let junk = SurplusFile(file: HashedFile(file: ScannedFile(url: URL(fileURLWithPath: "/tmp/junk.bin"), name: "junk.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))
        let matchReport = MatchReport(games: [], surplusFiles: [junk])

        #expect(RebuildPlanner.planRemoveRedundantFiles(matchReport: matchReport).isEmpty)
        #expect(RebuildPlanner.planRemoveRedundantRoms(matchReport: matchReport).isEmpty)
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

    // MARK: - Repair from Maintenance Folder

    @Test("repairs a missing rom by borrowing it, by content, from an external Maintenance-folder donor")
    func repairFromMaintenanceFolderAddsMissingRomFromDonorContent() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameZip = root.appendingPathComponent("game.zip")
        try makeZip(at: gameZip, entries: [("a-only.bin", "A-only-content")])

        // The donor file lives entirely outside the scan — a different
        // folder, a different (irrelevant) filename — and is matched
        // purely by content (size + CRC), never by name.
        let donorURL = root.appendingPathComponent("maintenance/some-random-dump-name.bin")
        try FileManager.default.createDirectory(at: donorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shared-content".utf8).write(to: donorURL)

        let sharedRom = DATRom(name: "shared.bin", size: Int64("shared-content".utf8.count), crc: "deadbeef", md5: nil, sha1: nil)
        let aOnlyRom = DATRom(name: "a-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [aOnlyRom, sharedRom])

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: aOnlyRom, status: .correct(HashedFile(file: ScannedFile(url: gameZip, name: "a-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))),
                    RomMatch(rom: sharedRom, status: .missing),
                ]),
            ],
            surplusFiles: []
        )
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: donorURL.lastPathComponent, size: Int64("shared-content".utf8.count)), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")),
        ]

        let operations = RebuildPlanner.planRepairFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles)
        #expect(operations.count == 1)
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: gameZip, accessMode: .read)
        guard let entry = archive["shared.bin"] else {
            Issue.record("Game A's own zip should now contain the borrowed \"shared.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "shared-content")
        #expect(archive["a-only.bin"] != nil)
        // The donor file itself must survive completely untouched — the
        // whole point of the Maintenance folder being read-only.
        #expect(FileManager.default.fileExists(atPath: donorURL.path))
        #expect(try String(contentsOf: donorURL, encoding: .utf8) == "shared-content")
    }

    @Test("repairs a rom whose status is .foundElsewhere (not .missing) from a Maintenance-folder donor — jensyleo's own real incident (2026-09-21): a NAOMI BIOS rom (315-6146.bin) also declared by an unrelated game (mvsc2) showed \"Available in another game (mvsc2.zip)\" forever, since .foundElsewhere content is genuinely absent from naomi's OWN archive but the old .missing-only guard skipped it regardless of whether Maintenance had a clean donor")
    func repairFromMaintenanceFolderAlsoRepairsFoundElsewhereRoms() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameZip = root.appendingPathComponent("naomi.zip")
        try makeZip(at: gameZip, entries: [("a-only.bin", "A-only-content")])

        let donorURL = root.appendingPathComponent("maintenance/315-6146.bin")
        try FileManager.default.createDirectory(at: donorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shared-chip-content".utf8).write(to: donorURL)

        let sharedRom = DATRom(name: "315-6146.bin", size: Int64("shared-chip-content".utf8.count), crc: "deadbeef", md5: nil, sha1: nil)
        let aOnlyRom = DATRom(name: "a-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "naomi", description: "NAOMI BIOS", cloneOf: nil, romOf: nil, roms: [aOnlyRom, sharedRom])

        // The unrelated game "mvsc2" also declares this exact hash, and its
        // own unclaimed copy is what ROMMatcher reports as .foundElsewhere
        // for naomi's own row — genuinely absent from naomi.zip itself.
        let elsewhereFile = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/CPS2/mvsc2.zip"), name: "315-6146.bin", size: Int64("shared-chip-content".utf8.count)),
            hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")
        )
        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: game, matches: [
                    RomMatch(rom: aOnlyRom, status: .correct(HashedFile(file: ScannedFile(url: gameZip, name: "a-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))),
                    RomMatch(rom: sharedRom, status: .foundElsewhere(elsewhereFile)),
                ]),
            ],
            surplusFiles: []
        )
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: donorURL.lastPathComponent, size: Int64("shared-chip-content".utf8.count)), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")),
        ]

        let operations = RebuildPlanner.planRepairFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles)
        #expect(operations.count == 1)
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: gameZip, accessMode: .read)
        guard let entry = archive["315-6146.bin"] else {
            Issue.record("naomi's own zip should now contain the repaired \"315-6146.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "shared-chip-content")
    }

    @Test("never borrows from a Maintenance-folder donor whose content doesn't actually match the missing rom")
    func repairFromMaintenanceFolderSkipsNonMatchingDonor() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameZip = root.appendingPathComponent("game.zip")
        try makeZip(at: gameZip, entries: [("a-only.bin", "A-only-content")])

        let donorURL = root.appendingPathComponent("maintenance/unrelated.bin")
        try FileManager.default.createDirectory(at: donorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("totally-unrelated-content".utf8).write(to: donorURL)

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let aOnlyRom = DATRom(name: "a-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game A", description: "Game A", cloneOf: nil, romOf: nil, roms: [aOnlyRom, sharedRom])

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: aOnlyRom, status: .correct(HashedFile(file: ScannedFile(url: gameZip, name: "a-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")))),
                RomMatch(rom: sharedRom, status: .missing),
            ])],
            surplusFiles: []
        )
        // The game DOES have an anchor (its own correct "a-only.bin") — the
        // only reason nothing should be planned is that the donor's actual
        // content simply doesn't match the missing rom's declared hash.
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: "unrelated.bin", size: Int64("totally-unrelated-content".utf8.count)), hash: FileHash(crc32: "ffffffff", md5: "0", sha1: "0")),
        ]

        #expect(RebuildPlanner.planRepairFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles).isEmpty)
    }

    // MARK: - Replace Corrupted ROMs

    @Test("replaces a hash-mismatched zip entry's bad content with a verified-correct Maintenance-folder donor")
    func replaceCorruptedRomsOverwritesBadZipEntryFromDonorContent() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameZip = root.appendingPathComponent("game.zip")
        try makeZip(at: gameZip, entries: [("bad.bin", "wrong-content")])

        let donorURL = root.appendingPathComponent("maintenance/some-random-dump-name.bin")
        try FileManager.default.createDirectory(at: donorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("correct-content".utf8).write(to: donorURL)

        let rom = DATRom(name: "bad.bin", size: Int64("correct-content".utf8.count), crc: "deadbeef", md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let badHashedFile = HashedFile(file: ScannedFile(url: gameZip, name: "bad.bin", size: Int64("wrong-content".utf8.count)), hash: FileHash(crc32: "ffffffff", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .hashMismatch(badHashedFile))])],
            surplusFiles: []
        )
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: donorURL.lastPathComponent, size: Int64("correct-content".utf8.count)), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")),
        ]

        let operations = RebuildPlanner.planReplaceCorruptedRoms(matchReport: matchReport, donorFiles: donorFiles)
        #expect(operations == [
            .removeEntryFromZip(archive: gameZip, entryName: "bad.bin"),
            .addEntryToZip(targetArchive: gameZip, entryName: "bad.bin", source: ArchiveEntrySource(source: donorURL, entryName: "bad.bin")),
        ])
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: gameZip, accessMode: .read)
        guard let entry = archive["bad.bin"] else {
            Issue.record("game.zip should still have exactly one \"bad.bin\" entry, now with the correct content")
            return
        }
        var extracted = Data()
        _ = try archive.extract(entry) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "correct-content")
        // The donor file itself must survive completely untouched.
        #expect(try String(contentsOf: donorURL, encoding: .utf8) == "correct-content")
    }

    @Test("never touches a hash-mismatched rom when no donor's content actually matches it")
    func replaceCorruptedRomsSkipsNonMatchingDonor() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let gameZip = root.appendingPathComponent("game.zip")
        try makeZip(at: gameZip, entries: [("bad.bin", "wrong-content")])

        let donorURL = root.appendingPathComponent("maintenance/unrelated.bin")
        try FileManager.default.createDirectory(at: donorURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("totally-unrelated-content".utf8).write(to: donorURL)

        let rom = DATRom(name: "bad.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let badHashedFile = HashedFile(file: ScannedFile(url: gameZip, name: "bad.bin", size: 1), hash: FileHash(crc32: "ffffffff", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .hashMismatch(badHashedFile))])],
            surplusFiles: []
        )
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: "unrelated.bin", size: Int64("totally-unrelated-content".utf8.count)), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0")),
        ]

        #expect(RebuildPlanner.planReplaceCorruptedRoms(matchReport: matchReport, donorFiles: donorFiles).isEmpty)
    }

    @Test("never plans a replacement for a .missing rom — that's Repair from Maintenance Folder's own job")
    func replaceCorruptedRomsIgnoresMissingRoms() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let donorURL = root.appendingPathComponent("donor.bin")
        try Data("correct-content".utf8).write(to: donorURL)

        let rom = DATRom(name: "missing.bin", size: Int64("correct-content".utf8.count), crc: "deadbeef", md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .missing)])],
            surplusFiles: []
        )
        let donorFiles = [
            HashedFile(file: ScannedFile(url: donorURL, name: "donor.bin", size: Int64("correct-content".utf8.count)), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0")),
        ]

        #expect(RebuildPlanner.planReplaceCorruptedRoms(matchReport: matchReport, donorFiles: donorFiles).isEmpty)
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

    @Test(
        "planRenameRomsInArchive styles the fixed entry name per romsCasePolicy, always derived from the DAT's own declared name",
        arguments: [
            (FileCasePolicy.datafileCase, "Correct Name.bin"),
            (.uppercase, "CORRECT NAME.BIN"),
            (.lowercase, "correct name.bin"),
            (.capitalized, "Correct Name.bin"),
        ]
    )
    func planRenameRomsInArchiveStylesEntryNamePerPolicy(policy: FileCasePolicy, expectedEntryName: String) throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("wrong-name.bin", "the-real-content")])

        let rom = DATRom(name: "Correct Name.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let misnamedFile = HashedFile(file: ScannedFile(url: zipURL, name: "wrong-name.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .misnamed(misnamedFile))])],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planRenameRomsInArchive(matchReport: matchReport, romsCasePolicy: policy)
        #expect(operations == [
            .addEntryToZip(targetArchive: zipURL, entryName: expectedEntryName, source: ArchiveEntrySource(source: zipURL, entryName: expectedEntryName, sourceArchiveEntryName: "wrong-name.bin")),
            .removeEntryFromZip(archive: zipURL, entryName: "wrong-name.bin"),
        ])
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

    // MARK: - Convert to split (Fase 2 Step 4, split direction)

    @Test("strips a redundant rom from a clone's own zip when the parent already has the exact same content")
    func convertToSplitRemovesRedundantRomFromCloneZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [("shared.bin", "shared-content")])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("clone-only.bin", "clone-only-content"), ("shared.bin", "shared-content")])

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let cloneOnlyRom = DATRom(name: "clone-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [sharedRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [cloneOnlyRom, sharedRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "shared.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))
        let cloneSharedHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "shared.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))
        let cloneOnlyHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "clone-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: sharedRom, status: .correct(parentHashedFile))]),
                GameMatchResult(game: cloneGame, matches: [
                    RomMatch(rom: cloneOnlyRom, status: .correct(cloneOnlyHashedFile)),
                    RomMatch(rom: sharedRom, status: .correct(cloneSharedHashedFile)),
                ]),
            ],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planConvertToSplit(matchReport: matchReport)
        #expect(operations == [.removeEntryFromZip(archive: cloneZip, entryName: "shared.bin")])

        try RebuildExecutor.execute(operations)

        let cloneArchive = try Archive(url: cloneZip, accessMode: .read)
        #expect(cloneArchive["shared.bin"] == nil, "the redundant entry must be gone from the clone")
        #expect(cloneArchive["clone-only.bin"] != nil, "the clone's own unique rom must survive")
        // The parent's own zip — the only remaining copy — must survive completely untouched.
        let parentArchive = try Archive(url: parentZip, accessMode: .read)
        #expect(parentArchive["shared.bin"] != nil)
    }

    @Test("never strips a rom from a clone when the parent doesn't actually have it")
    func convertToSplitNeverStripsWhenParentLacksTheRom() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("shared.bin", "shared-content")])

        let sharedRom = DATRom(name: "shared.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [sharedRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [sharedRom])

        let cloneHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "shared.bin", size: 1), hash: FileHash(crc32: "deadbeef", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                // Parent doesn't have it at all — .missing.
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: sharedRom, status: .missing)]),
                GameMatchResult(game: cloneGame, matches: [RomMatch(rom: sharedRom, status: .correct(cloneHashedFile))]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planConvertToSplit(matchReport: matchReport).isEmpty)
    }

    // MARK: - Fix Mismatched Files + Sets case, combined (jensyleo's own
    // ClrMamePro-parity request, 2026-09-10: one "Fix" pass should both
    // repair a wrong name AND re-style an already-correct one, exactly as
    // `LibraryViewModel.fix()` now runs `planRepair` and
    // `planApplySetsCasePolicy` together)

    @Test("planRepair and planApplySetsCasePolicy never target the same archive — mutually exclusive by construction, so LibraryViewModel.fix() can safely run both in one pass without risking a double-rename")
    func planRepairAndSetsCasePolicyAreMutuallyExclusive() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // A real MAME/NEOGEO-shaped collection: every archive's name
        // already matches its DAT game name exactly (lowercase) — nothing
        // for `planRepair` to fix, everything for a Sets-case Uppercase
        // pass to re-style. jensyleo's own report (2026-09-10): 26 such
        // archives, "Sets case" = Uppercase, "Fix Mismatched Files" logged
        // "nothing to fix" because THIS half genuinely had nothing to do
        // — the fix is that the SAME click also runs the other half.
        var games: [GameMatchResult] = []
        for name in ["mslug", "blazstar", "ganryu"] {
            let zipURL = root.appendingPathComponent("\(name).zip")
            try makeZip(at: zipURL, entries: [("\(name).rom", "content")])
            let rom = DATRom(name: "\(name).rom", size: 1, crc: nil, md5: nil, sha1: nil)
            let game = DATGame(name: name, description: name, cloneOf: nil, romOf: nil, roms: [rom])
            let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "\(name).rom", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
            games.append(GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))]))
        }
        let matchReport = MatchReport(games: games, surplusFiles: [])

        let mismatchOperations = RebuildPlanner.planRepair(matchReport: matchReport, filesCasePolicy: .uppercase)
        let caseOnlyOperations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase)

        #expect(mismatchOperations.isEmpty, "nothing here disagrees with the DAT — planRepair's own half has genuinely nothing to do")
        #expect(caseOnlyOperations.count == 3, "all three lowercase archives are eligible for Sets-case re-styling")

        // The actual safety property `fix()` relies on: no source path
        // appears in both plans, so concatenating and executing them
        // together can never rename the same File twice.
        func sourcePath(_ op: RebuildOperation) -> String? {
            if case .rename(let from, _) = op { return from.path }
            return nil
        }
        let mismatchSources = Set(mismatchOperations.compactMap(sourcePath))
        let caseOnlySources = Set(caseOnlyOperations.compactMap(sourcePath))
        #expect(mismatchSources.isDisjoint(with: caseOnlySources))

        // Executing the combined plan (as `fix()` now does) actually
        // performs every rename.
        try RebuildExecutor.execute(mismatchOperations + caseOnlyOperations)
        let onDisk = Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
        #expect(onDisk == ["MSLUG.zip", "BLAZSTAR.zip", "GANRYU.zip"])
    }

    // MARK: - Case policy (Fase 2 Step 9)

    @Test("Roms case = Capitalized re-styles an already-correct entry's BASE name only, keeping its extension lowercase — never 'Game.Bin'")
    func romsCasePolicyCapitalizedKeepsExtensionLowercase() throws {
        // jensyleo's own instruction (2026-09-10) to review the app for
        // coherence surfaced this: `mismatchFixName` (a genuine mismatch's
        // target name) already guards `.capitalized` against title-casing
        // the extension too ("game.bin" → "Game.bin", not "Game.Bin") —
        // but `caseTransformTarget` (an ALREADY-correct entry being
        // re-styled) had no such guard, so "Roms case" = Capitalized
        // silently produced "Game.Bin" for an entry the DAT already
        // matched correctly.
        let zipURL = URL(fileURLWithPath: "/roms/sfiii.zip")
        let rom = DATRom(name: "game.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "sfiii", description: "sfiii", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "game.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let operations = RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: .capitalized)

        #expect(operations.count == 2)
        guard case .addEntryToZip(_, let newName, _) = operations.first else {
            Issue.record("expected the pair to start with .addEntryToZip, got \(String(describing: operations.first))")
            return
        }
        #expect(newName == "Game.bin", "extension must stay lowercase — 'Game.Bin' is the exact bug this test guards against")
    }

    @Test("renames a zip-per-game archive's own filename to uppercase, leaving its extension and contents untouched")
    func setsCasePolicyUppercasesArchiveFilename() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("lowercase-game.zip")
        try makeZip(at: zipURL, entries: [("a.bin", "content")])

        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        // The container's name must match the DAT game name apart from case
        // for this to be a genuine "Sets case" job at all — a name that
        // differs beyond case is a File-level mismatch, not a case one.
        let game = DATGame(name: "lowercase-game", description: "Lowercase Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let operations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase)
        let expectedURL = root.appendingPathComponent("LOWERCASE-GAME.zip")
        #expect(operations == [.rename(from: zipURL, to: expectedURL)])

        try RebuildExecutor.execute(operations)
        // NOT `!fileExists(atPath: zipURL.path)` — on the default macOS
        // volume (case-insensitive, case-PRESERVING APFS), "lowercase-
        // game.zip" and "LOWERCASE-GAME.zip" are the same file, so that
        // check would report "still exists" even after a fully successful
        // case-only rename. The real proof the rename actually changed
        // the on-disk case is the directory listing itself.
        #expect(FileManager.default.fileExists(atPath: expectedURL.path))
        let siblingNames = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(siblingNames.contains("LOWERCASE-GAME.zip"), "the on-disk name itself must be uppercase now, not just case-insensitively reachable")
        let archive = try Archive(url: expectedURL, accessMode: .read)
        #expect(archive["a.bin"] != nil, "contents must survive the rename untouched")
    }

    @Test("re-cases a .7z set's own container filename too — renaming a container never rewrites entries, so restricting this to .zip left every 7z collection silently unfixable")
    func setsCasePolicyUppercasesSevenZipFilename() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Only the container's NAME matters to this planner — it plans a
        // plain filesystem rename and never opens the archive, so a stub
        // file at a .7z path is a faithful fixture here.
        let archiveURL = root.appendingPathComponent("lowercase-game.7z")
        try Data("stub".utf8).write(to: archiveURL)

        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        // The container's name must match the DAT game name apart from case
        // for this to be a genuine "Sets case" job at all — a name that
        // differs beyond case is a File-level mismatch, not a case one.
        let game = DATGame(name: "lowercase-game", description: "Lowercase Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: archiveURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let operations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase)
        #expect(operations.count == 1)
        guard case .rename(let from, let to) = operations.first else {
            Issue.record("expected a single .rename operation, got \(String(describing: operations.first))")
            return
        }
        #expect(from == archiveURL)
        #expect(to.lastPathComponent == "LOWERCASE-GAME.7z", "basename uppercased, extension left exactly as it was")
    }

    @Test("never re-cases a container whose own FILENAME is wrong beyond case, even when every ENTRY inside it is .correct — entry status says nothing about the container's name")
    func setsCasePolicySkipsContainerWhoseFilenameIsGenuinelyWrong() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // The container's own name has nothing to do with the game; the
        // entry inside it is named exactly right. `ROMMatcher` matches by
        // HASH, so this rom comes back `.correct` — a status decided
        // purely by the ENTRY name — while the File's own name is
        // genuinely wrong. Uppercasing it here would just produce
        // "UNKNOWN123.zip": a differently-cased WRONG File name.
        let zipURL = root.appendingPathComponent("unknown123.zip")
        try makeZip(at: zipURL, entries: [("a.bin", "content")])

        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "sfiii", description: "sfiii", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        #expect(
            RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase).isEmpty,
            "renaming this File is \"Fix Mismatched Files\"' job, never a case policy's"
        )
    }

    @Test("re-cases only the container's own filename, leaving every entry name inside it exactly as it was")
    func setsCasePolicyNeverTouchesEntryNames() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // Container name differs from the game name by case only — a real
        // "Sets case" job. The entry inside is deliberately lowercase and
        // must survive untouched: this half renames the FILE, never its
        // contents.
        let zipURL = root.appendingPathComponent("sfiii.zip")
        try makeZip(at: zipURL, entries: [("a.bin", "content")])

        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "SFIII", description: "SFIII", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let operations = RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase)
        #expect(operations.count == 1)
        for operation in operations {
            if case .addEntryToZip = operation { Issue.record("a Sets-case rename must never rewrite an entry") }
            if case .removeEntryFromZip = operation { Issue.record("a Sets-case rename must never rewrite an entry") }
        }
        try RebuildExecutor.execute(operations)

        let renamed = root.appendingPathComponent("SFIII.zip")
        let archive = try Archive(url: renamed, accessMode: .read)
        #expect(archive["a.bin"] != nil, "the entry name must be untouched — only the container was renamed")
    }

    @Test("never re-cases a game whose only anchor is .misnamed — that's Fix Mismatched Files' job, and re-casing the CURRENT (wrong) name would just produce a differently-cased version of it")
    func setsCasePolicySkipsMisnamedAnchor() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // The zip's own name is "wrongname.zip" — not even close to the
        // DAT's declared game name — mirroring a genuinely misidentified
        // archive, not just a case mismatch.
        let zipURL = root.appendingPathComponent("wrongname.zip")
        try makeZip(at: zipURL, entries: [("a.bin", "content")])

        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Sfiii", description: "Sfiii", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .misnamed(hashedFile))])], surplusFiles: [])

        // Before the fix, this would have produced
        // .rename(wrongname.zip, WRONGNAME.zip) — uppercasing the WRONG
        // name instead of leaving it for "Fix Mismatched Files" to
        // actually correct.
        #expect(RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase).isEmpty)
    }

    @Test("never plans a sets-case rename when the policy is dontTouch or the name already matches")
    func setsCasePolicyDontTouchAndAlreadyMatchingProduceNoOperations() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("ALREADY-UPPER.zip")
        try makeZip(at: zipURL, entries: [("a.bin", "content")])
        let rom = DATRom(name: "a.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Already Upper", description: "Already Upper", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "a.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        #expect(RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .dontTouch).isEmpty)
        #expect(RebuildPlanner.planApplySetsCasePolicy(matchReport: matchReport, policy: .uppercase).isEmpty, "already uppercase — nothing to rename")
    }

    @Test("renames a rom entry inside a zip to lowercase via add-then-remove, preserving content and siblings")
    func romsCasePolicyLowercasesEntryName() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("UPPER.BIN", "the-content"), ("sibling.bin", "sibling-content")])

        let rom = DATRom(name: "UPPER.BIN", size: 1, crc: nil, md5: nil, sha1: nil)
        let siblingRom = DATRom(name: "sibling.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom, siblingRom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "UPPER.BIN", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let siblingFile = HashedFile(file: ScannedFile(url: zipURL, name: "sibling.bin", size: 1), hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0"))
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: rom, status: .correct(hashedFile)),
                RomMatch(rom: siblingRom, status: .correct(siblingFile)),
            ])],
            surplusFiles: []
        )

        let operations = RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: .lowercase)
        #expect(operations == [
            .addEntryToZip(targetArchive: zipURL, entryName: "upper.bin", source: ArchiveEntrySource(source: zipURL, entryName: "upper.bin", sourceArchiveEntryName: "UPPER.BIN")),
            .removeEntryFromZip(archive: zipURL, entryName: "UPPER.BIN"),
        ])
        try RebuildExecutor.execute(operations)

        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["UPPER.BIN"] == nil)
        #expect(archive["sibling.bin"] != nil, "the untouched sibling entry must survive")
        guard let renamed = archive["upper.bin"] else {
            Issue.record("zip should now contain the lowercased entry")
            return
        }
        var extracted = Data()
        _ = try archive.extract(renamed) { extracted.append($0) }
        #expect(String(data: extracted, encoding: .utf8) == "the-content")
    }

    @Test("never re-cases a rom entry whose own status is .misnamed — that's Fix Misnamed ROMs Inside Their Archives' job")
    func romsCasePolicySkipsMisnamedEntry() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("wrong-entry.bin", "the-content")])

        let rom = DATRom(name: "correct-entry.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "Game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "wrong-entry.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .misnamed(hashedFile))])], surplusFiles: [])

        // Before the fix, this would have produced an add/remove pair
        // renaming to "WRONG-ENTRY.BIN" (uppercasing the wrong current
        // name) instead of leaving it for the actual Fix action.
        #expect(RebuildPlanner.planApplyRomsCasePolicy(matchReport: matchReport, policy: .uppercase).isEmpty)
    }

    // MARK: - Corrupted files policy (Fase 2 Step 8)

    /// Same technique `ZipLocalHeaderCRCVerifierTests` uses: flip one bit of
    /// the very first local header's own CRC32 field (byte offset 14 from
    /// the start of the file — true for any single-entry archive,
    /// TorrentZip or plain ZIPFoundation) without touching the central
    /// directory, producing the exact "something edited one copy and not
    /// the other" internal mismatch `ZipIntegrityAuditor` exists to catch.
    private func corruptLocalHeaderCRC(at url: URL) throws {
        var data = try Data(contentsOf: url)
        data[14] = data[14] ^ 0xFF
        try data.write(to: url)
    }

    @Test("corrupted files policy .delete removes the flagged entry, siblings in other archives untouched")
    func corruptedFilesPolicyDeleteRemovesFlaggedEntry() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("foo.bin", "content")])
        try corruptLocalHeaderCRC(at: zipURL)

        let rom = DATRom(name: "foo.bin", size: 7, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "foo.bin", size: 7), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let groups = RebuildPlanner.planCorruptedFilesPolicy(matchReport: matchReport, policy: .delete, quarantineFolder: nil)
        #expect(groups == [[.removeEntryFromZip(archive: zipURL, entryName: "foo.bin")]])

        for group in groups { try RebuildExecutor.execute(group) }
        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["foo.bin"] == nil)
    }

    @Test("corrupted files policy .moveTo extracts the entry to the quarantine folder, then removes it")
    func corruptedFilesPolicyMoveToQuarantinesEntry() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("foo.bin", "content")])
        try corruptLocalHeaderCRC(at: zipURL)
        let quarantine = root.appendingPathComponent("quarantine")

        let rom = DATRom(name: "foo.bin", size: 7, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "foo.bin", size: 7), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let matchReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        let groups = RebuildPlanner.planCorruptedFilesPolicy(matchReport: matchReport, policy: .moveTo, quarantineFolder: quarantine)
        #expect(groups.count == 1)
        #expect(groups[0].count == 2)

        for group in groups { try RebuildExecutor.execute(group) }
        let archive = try Archive(url: zipURL, accessMode: .read)
        #expect(archive["foo.bin"] == nil, "the flagged entry must be gone from the archive")
        #expect(FileManager.default.fileExists(atPath: quarantine.appendingPathComponent("game_foo.bin").path), "the quarantined copy must exist")
    }

    @Test("corrupted files policy plans nothing for .dontTouch or when no archive is actually corrupted")
    func corruptedFilesPolicyNoOpCases() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let zipURL = root.appendingPathComponent("game.zip")
        try makeZip(at: zipURL, entries: [("foo.bin", "content")])
        try corruptLocalHeaderCRC(at: zipURL)

        let rom = DATRom(name: "foo.bin", size: 7, crc: nil, md5: nil, sha1: nil)
        let game = DATGame(name: "game", description: "Game", cloneOf: nil, romOf: nil, roms: [rom])
        let hashedFile = HashedFile(file: ScannedFile(url: zipURL, name: "foo.bin", size: 7), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let corruptedReport = MatchReport(games: [GameMatchResult(game: game, matches: [RomMatch(rom: rom, status: .correct(hashedFile))])], surplusFiles: [])

        #expect(RebuildPlanner.planCorruptedFilesPolicy(matchReport: corruptedReport, policy: .dontTouch, quarantineFolder: nil).isEmpty)

        // A second, genuinely clean archive — nothing should be flagged.
        let cleanZipURL = root.appendingPathComponent("clean.zip")
        try makeZip(at: cleanZipURL, entries: [("bar.bin", "content")])
        let cleanRom = DATRom(name: "bar.bin", size: 7, crc: nil, md5: nil, sha1: nil)
        let cleanGame = DATGame(name: "clean", description: "Clean", cloneOf: nil, romOf: nil, roms: [cleanRom])
        let cleanHashedFile = HashedFile(file: ScannedFile(url: cleanZipURL, name: "bar.bin", size: 7), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let cleanReport = MatchReport(games: [GameMatchResult(game: cleanGame, matches: [RomMatch(rom: cleanRom, status: .correct(cleanHashedFile))])], surplusFiles: [])

        #expect(RebuildPlanner.planCorruptedFilesPolicy(matchReport: cleanReport, policy: .delete, quarantineFolder: nil).isEmpty)
    }

    // MARK: - Convert to merged (Fase 2 Step 4, Merged direction)

    @Test("merges a clone's own unique rom into the parent, then deletes the clone's whole archive")
    func convertToMergedFoldsUniqueRomIntoParentThenDeletesClone() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [("parent-only.bin", "parent-only-content")])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("clone-only.bin", "clone-only-content")])

        let parentOnlyRom = DATRom(name: "parent-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let cloneOnlyRom = DATRom(name: "clone-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [parentOnlyRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [cloneOnlyRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "parent-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let cloneHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "clone-only.bin", size: 1), hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: parentOnlyRom, status: .correct(parentHashedFile))]),
                GameMatchResult(game: cloneGame, matches: [RomMatch(rom: cloneOnlyRom, status: .correct(cloneHashedFile))]),
            ],
            surplusFiles: []
        )

        let groups = RebuildPlanner.planConvertToMerged(matchReport: matchReport)
        #expect(groups.count == 1)
        #expect(groups[0].last == .delete(cloneZip), "the clone's own delete must be the LAST operation in its group")

        for group in groups { try RebuildExecutor.execute(group) }

        #expect(!FileManager.default.fileExists(atPath: cloneZip.path), "the clone's whole archive must be gone")
        let parentArchive = try Archive(url: parentZip, accessMode: .read)
        #expect(parentArchive["parent-only.bin"] != nil, "the parent's own pre-existing rom must survive")
        guard let migrated = parentArchive["clone-only.bin"] else {
            Issue.record("parent's own zip should now contain the migrated \"clone-only.bin\" entry")
            return
        }
        var extracted = Data()
        _ = try archive_extract(parentArchive, migrated, into: &extracted)
        #expect(String(data: extracted, encoding: .utf8) == "clone-only-content")
    }

    /// The critical safety case: if adding a clone's rom into the parent
    /// fails (here, because the parent's archive already has an entry
    /// under that exact name, from something else entirely, so
    /// `.addEntryToZip`'s own `archive[entryName] == nil` guard throws),
    /// `RebuildExecutor.execute(_:)` must stop at that failure — the
    /// clone's own `.delete`, listed AFTER it in the same group, must
    /// never run. Confirms `planConvertToMerged`'s whole safety argument
    /// (ordering, not a separate verification pass) actually holds.
    @Test("never deletes a clone's archive if migrating one of its roms into the parent fails")
    func convertToMergedNeverDeletesCloneIfMigrationFails() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        // The parent's zip already has its own real, declared rom (so it
        // has an anchor of its own to migrate INTO) PLUS an entry under
        // the exact name the clone's own unique rom would need — the
        // collision that makes the add step fail.
        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [
            ("parent-real.bin", "parent-real-content"),
            ("clone-only.bin", "unrelated-existing-content"),
        ])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("clone-only.bin", "clone-only-content")])

        let parentRealRom = DATRom(name: "parent-real.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let cloneOnlyRom = DATRom(name: "clone-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        // Parent's own DAT doesn't declare "clone-only.bin" as one of its
        // roms at all — the existing entry under that name is genuinely
        // unrelated, exactly the "something else entirely" collision case.
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [parentRealRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [cloneOnlyRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "parent-real.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let cloneHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "clone-only.bin", size: 1), hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: parentRealRom, status: .correct(parentHashedFile))]),
                GameMatchResult(game: cloneGame, matches: [RomMatch(rom: cloneOnlyRom, status: .correct(cloneHashedFile))]),
            ],
            surplusFiles: []
        )

        let groups = RebuildPlanner.planConvertToMerged(matchReport: matchReport)
        #expect(groups.count == 1)

        for group in groups {
            // Mirrors how LibraryViewModel would run this: one group at a
            // time, catching (not propagating) a failure so the rest of
            // the scan's OTHER clones still get their own chance.
            try? RebuildExecutor.execute(group)
        }

        #expect(FileManager.default.fileExists(atPath: cloneZip.path), "the clone's own archive must survive — its migration never fully succeeded")
        let cloneArchive = try Archive(url: cloneZip, accessMode: .read)
        #expect(cloneArchive["clone-only.bin"] != nil, "the clone's own rom must still be there, untouched")
    }

    @Test("skips a clone entirely when its own archive also holds an unaccounted-for surplus file")
    func convertToMergedSkipsCloneWithSurplusFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [("parent-only.bin", "content")])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("clone-only.bin", "content"), ("mystery-junk.bin", "junk")])

        let parentOnlyRom = DATRom(name: "parent-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let cloneOnlyRom = DATRom(name: "clone-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [parentOnlyRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [cloneOnlyRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "parent-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let cloneHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "clone-only.bin", size: 1), hash: FileHash(crc32: "bbbbbbbb", md5: "0", sha1: "0"))
        let surplusFile = SurplusFile(file: HashedFile(file: ScannedFile(url: cloneZip, name: "mystery-junk.bin", size: 1), hash: FileHash(crc32: "cccccccc", md5: "0", sha1: "0")))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: parentOnlyRom, status: .correct(parentHashedFile))]),
                GameMatchResult(game: cloneGame, matches: [RomMatch(rom: cloneOnlyRom, status: .correct(cloneHashedFile))]),
            ],
            surplusFiles: [surplusFile]
        )

        #expect(RebuildPlanner.planConvertToMerged(matchReport: matchReport).isEmpty)
    }

    @Test("skips a clone entirely when it has a hash-mismatched rom in its own archive")
    func convertToMergedSkipsCloneWithHashMismatch() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let parentZip = root.appendingPathComponent("parent.zip")
        try makeZip(at: parentZip, entries: [("parent-only.bin", "content")])
        let cloneZip = root.appendingPathComponent("clone.zip")
        try makeZip(at: cloneZip, entries: [("bad.bin", "wrong-content")])

        let parentOnlyRom = DATRom(name: "parent-only.bin", size: 1, crc: nil, md5: nil, sha1: nil)
        let badRom = DATRom(name: "bad.bin", size: 1, crc: "deadbeef", md5: nil, sha1: nil)
        let parentGame = DATGame(name: "Parent", description: "Parent", cloneOf: nil, romOf: nil, roms: [parentOnlyRom])
        let cloneGame = DATGame(name: "Clone", description: "Clone", cloneOf: "Parent", romOf: "Parent", roms: [badRom])

        let parentHashedFile = HashedFile(file: ScannedFile(url: parentZip, name: "parent-only.bin", size: 1), hash: FileHash(crc32: "aaaaaaaa", md5: "0", sha1: "0"))
        let badHashedFile = HashedFile(file: ScannedFile(url: cloneZip, name: "bad.bin", size: 1), hash: FileHash(crc32: "ffffffff", md5: "0", sha1: "0"))

        let matchReport = MatchReport(
            games: [
                GameMatchResult(game: parentGame, matches: [RomMatch(rom: parentOnlyRom, status: .correct(parentHashedFile))]),
                GameMatchResult(game: cloneGame, matches: [RomMatch(rom: badRom, status: .hashMismatch(badHashedFile))]),
            ],
            surplusFiles: []
        )

        #expect(RebuildPlanner.planConvertToMerged(matchReport: matchReport).isEmpty)
    }

    // MARK: - Create Dummy ROMs / Remove Zip Comments

    @Test("creates a zero-byte dummy loose file")
    func createsDummyLooseFile() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("Game/missing.bin")

        try RebuildExecutor.execute([.createDummyFile(at: target, size: 4)])

        let data = try Data(contentsOf: target)
        #expect(data.count == 4)
        #expect(data == Data(count: 4))
    }

    @Test("refuses to overwrite an existing dummy file destination")
    func createDummyFileRefusesExistingDestination() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("existing.bin")
        try Data("real content".utf8).write(to: target)

        #expect(throws: RebuildError.destinationExists(target)) {
            try RebuildExecutor.execute([.createDummyFile(at: target, size: 4)])
        }
        #expect(try Data(contentsOf: target) == Data("real content".utf8))
    }

    @Test("caps a dummy file's size at the safety ceiling instead of honoring an absurd DAT-declared size")
    func createDummyFileCapsSize() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("huge.bin")

        try RebuildExecutor.execute([.createDummyFile(at: target, size: Int64.max)])

        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        let size = attributes[.size] as? Int ?? -1
        #expect(size == 64 * 1024 * 1024)
    }

    @Test("adds a dummy zip entry without disturbing existing entries")
    func createsDummyZipEntry() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("game.zip")
        try makeZip(at: zip, entries: [("present.bin", "content")])

        try RebuildExecutor.execute([.createDummyZipEntry(targetArchive: zip, entryName: "missing.bin", size: 3)])

        let archive = try Archive(url: zip, accessMode: .read)
        #expect(archive["present.bin"] != nil)
        guard let entry = archive["missing.bin"] else {
            Issue.record("dummy entry was not added")
            return
        }
        var data = Data()
        try archive_extract(archive, entry, into: &data)
        #expect(data == Data(count: 3))
    }

    @Test("removes a zip's own trailing comment without touching its entries")
    func clearsZipComment() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("commented.zip")
        try makeZip(at: zip, entries: [("rom.bin", "content")])

        var data = try Data(contentsOf: zip)
        let comment = Data("hello world".utf8)
        var lengthBytes = Data(count: 2)
        lengthBytes[0] = UInt8(comment.count & 0xff)
        lengthBytes[1] = UInt8((comment.count >> 8) & 0xff)
        data.replaceSubrange((data.count - 22 + 20)..<(data.count - 22 + 22), with: lengthBytes)
        data.append(comment)
        try data.write(to: zip)

        try RebuildExecutor.execute([.clearZipComment(archive: zip)])

        let rewritten = try Data(contentsOf: zip)
        #expect(!rewritten.suffix(comment.count).elementsEqual(comment))
        let archive = try Archive(url: zip, accessMode: .read)
        #expect(archive["rom.bin"] != nil)
    }

    @Test("clearing an already-commentless zip's comment is a harmless no-op")
    func clearZipCommentNoOpWhenAlreadyEmpty() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let zip = root.appendingPathComponent("plain.zip")
        try makeZip(at: zip, entries: [("rom.bin", "content")])
        let before = try Data(contentsOf: zip)

        try RebuildExecutor.execute([.clearZipComment(archive: zip)])

        #expect(try Data(contentsOf: zip) == before)
    }

}

/// Small local helper so the "fold roms into parent" test above can read
/// an entry's content without repeating the `var data = Data(); try
/// archive.extract(entry) { data.append($0) }` boilerplate every other
/// test in this file already spells out inline.
private func archive_extract(_ archive: Archive, _ entry: Entry, into data: inout Data) throws {
    _ = try archive.extract(entry) { data.append($0) }
}
