// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("FolderScanner")
struct FolderScannerTests {
    @Test("lists loose files recursively, skipping hidden files")
    func listsFilesRecursivelySkippingHidden() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let topFile = root.appendingPathComponent("Game.sfc")
        try Data("top".utf8).write(to: topFile)

        let nestedFile = nested.appendingPathComponent("Another Game.sfc")
        try Data("nested-content".utf8).write(to: nestedFile)

        let hiddenFile = root.appendingPathComponent(".DS_Store")
        try Data("hidden".utf8).write(to: hiddenFile)

        let files = try FolderScanner.scan(folder: root)
        let names = Set(files.map(\.name))

        #expect(names == ["Game.sfc", "Another Game.sfc"])
        let nestedResult = try #require(files.first { $0.name == "Another Game.sfc" })
        #expect(nestedResult.size == Int64("nested-content".utf8.count))
    }

    @Test("throws when the folder does not exist")
    func throwsWhenFolderMissing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(throws: ScannerError.folderNotFound(missing)) {
            try FolderScanner.scan(folder: missing)
        }
    }

    @Test("throws when the path is a file, not a folder")
    func throwsWhenPathIsAFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(throws: ScannerError.notADirectory(file)) {
            try FolderScanner.scan(folder: file)
        }
    }

    @Test("scanning multiple folders concatenates their loose files")
    func scanningMultipleFoldersConcatenatesFiles() throws {
        let rootA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootB = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        try Data("a".utf8).write(to: rootA.appendingPathComponent("gameA.bin"))
        try Data("b".utf8).write(to: rootB.appendingPathComponent("gameB.bin"))

        let files = try FolderScanner.scan(folders: [rootA, rootB])
        #expect(Set(files.map(\.name)) == ["gameA.bin", "gameB.bin"])
    }

    @Test("scanning multiple folders throws if any one of them is missing")
    func scanningMultipleFoldersThrowsIfOneMissing() throws {
        let rootA = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootA) }
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        #expect(throws: ScannerError.folderNotFound(missing)) {
            try FolderScanner.scan(folders: [rootA, missing])
        }
    }

    @Test("scanSingleFile returns a ScannedFile for one specific file, not its containing folder")
    func scanSingleFileReturnsOneFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let target = root.appendingPathComponent("sf2ee.zip")
        try Data("sf2ee-content".utf8).write(to: target)
        try Data("sibling".utf8).write(to: root.appendingPathComponent("sf2.zip"))

        let file = try FolderScanner.scanSingleFile(target)
        #expect(file.name == "sf2ee.zip")
        #expect(file.size == Int64("sf2ee-content".utf8.count))
    }

    @Test("scanSingleFile throws when given a directory instead of a file")
    func scanSingleFileThrowsOnDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ScannerError.notADirectory(root)) {
            try FolderScanner.scanSingleFile(root)
        }
    }

    @Test("allows exactly one level of subfolder — the real <system>/<game>/<file> convention")
    func allowsOneLevelOfSubfolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let gameFolder = root.appendingPathComponent("sfiii3")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("chd-content".utf8).write(to: gameFolder.appendingPathComponent("cap-33s-1.chd"))

        let files = try FolderScanner.scan(folder: root)
        #expect(files.map(\.name) == ["cap-33s-1.chd"])
    }

    @Test("throws ScannerError.folderTooDeep rather than scanning past one level of subfolder — jensyleo's own request (2026-08-05) so pointing this at something far too broad (a whole drive, a home folder) never silently tries to enumerate everything underneath it")
    func throwsWhenNestingExceedsOneLevel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Mirrors the real case that surfaced this: a system folder with an
        // extra subfolder (e.g. "BATOCERA") sitting ABOVE the per-game
        // folder, one level deeper than the convention this project's own
        // testing has always used.
        let tooDeep = root.appendingPathComponent("BATOCERA").appendingPathComponent("sfiii3")
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("chd-content".utf8).write(to: tooDeep.appendingPathComponent("cap-33s-1.chd"))

        #expect(throws: ScannerError.self) {
            try FolderScanner.scan(folder: root)
        }
    }

    @Test("scan(paths:) mixes whole folders and individual files in one pass — jensyleo's own request (2026-07-28) to scan just one archive without rescanning its entire containing folder")
    func scanPathsMixesFoldersAndIndividualFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("a".utf8).write(to: root.appendingPathComponent("gameA.zip"))
        try Data("b".utf8).write(to: root.appendingPathComponent("gameB.zip"))

        let looseFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
        try Data("loose".utf8).write(to: looseFile)
        defer { try? FileManager.default.removeItem(at: looseFile) }

        let files = try FolderScanner.scan(paths: [root, looseFile])
        #expect(Set(files.map(\.name)) == ["gameA.zip", "gameB.zip", looseFile.lastPathComponent])
    }
}
