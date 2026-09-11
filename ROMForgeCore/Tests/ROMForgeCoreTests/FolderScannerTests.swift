// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

// `.serialized`: `raisingMaxSubfolderDepthReachesDeeperFolders` mutates
// `FolderScanner.maxSubfolderDepth` — a real, global, mutable setting now
// (see that property's own doc comment) — and restores it afterward, but
// only ever safely if no sibling test reads it concurrently mid-mutation.
// Swift Testing runs a suite's tests in parallel by default; without this,
// that test raced visibly against `skipsTooDeepSubfolderInsteadOfThrowing`
// (confirmed live, 2026-09-10): the latter saw depth 2 instead of the
// default 1 and stopped skipping the folder it exists to prove gets skipped.
@Suite("FolderScanner", .serialized)
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

    @Test("never follows a symlink to a file outside the scanned folder")
    func skipsSymlinkedFileOutsideFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Stands in for a file the scan must never read the content of —
        // outside the folder the user actually pointed the scan at, the
        // same shape as e.g. `~/.ssh/id_rsa` or a Keychain file.
        let secretOutside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("outside-secret-content".utf8).write(to: secretOutside)
        defer { try? FileManager.default.removeItem(at: secretOutside) }

        let realGame = root.appendingPathComponent("Game.sfc")
        try Data("real-game".utf8).write(to: realGame)

        let symlink = root.appendingPathComponent("Planted Link.sfc")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: secretOutside)

        let files = try FolderScanner.scan(folder: root)

        #expect(files.map(\.name) == ["Game.sfc"])
        #expect(!files.contains { $0.name == "Planted Link.sfc" })
    }

    @Test("never descends into a symlinked directory")
    func skipsSymlinkedDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let outsideDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDir) }
        try Data("outside-nested-secret".utf8).write(to: outsideDir.appendingPathComponent("secret.bin"))

        let symlinkedDir = root.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: symlinkedDir, withDestinationURL: outsideDir)

        let files = try FolderScanner.scan(folder: root)

        #expect(files.isEmpty)
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

    @Test("scanSingleFile reports the TRUE on-disk name/case, not whatever case the caller's URL happened to spell — the default macOS volume (APFS) is case-insensitive-but-case-preserving, so a stale-case URL (e.g. captured before a rename) still resolves fine")
    func scanSingleFileReportsRealOnDiskCaseNotTheCallersURLCase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // The real file on disk is uppercase — as if a case-only rename
        // (e.g. "Fix Mismatched Files" with "Sets case" = Uppercase) had
        // just run. jensyleo's own report (2026-09-10): "Rescan This File"
        // afterward kept showing the OLD lowercase name in the app, even
        // though the file itself was genuinely already uppercase on disk.
        let realURL = root.appendingPathComponent("CYBERLIP.zip")
        try Data("content".utf8).write(to: realURL)

        // The STALE, pre-rename (lowercase) URL — what a caller holding
        // onto a name captured before the rename would still pass in.
        let staleURL = root.appendingPathComponent("cyberlip.zip")

        let file = try FolderScanner.scanSingleFile(staleURL)

        #expect(file.name == "CYBERLIP.zip", "must reflect the real on-disk name, not the stale case the caller asked for")
        #expect(file.url.lastPathComponent == "CYBERLIP.zip")
    }

    @Test("scanSingleFile still reports the real on-disk case even when the OLD path was already queried once before the rename — the actual sequence a real rescan-after-fix hits, which a same-process one-shot query doesn't")
    func scanSingleFileSurvivesAPriorQueryOnTheStalePathBeforeRename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let originalURL = root.appendingPathComponent("cyberlip.zip")
        try Data("content".utf8).write(to: originalURL)

        // jensyleo's own report (2026-09-10): renaming "cyberlip.zip" to
        // "CYBERLIP.zip" and immediately rescanning it (inside the SAME
        // running app) still showed the OLD name — reproducible ONLY when
        // this exact path was already looked at once earlier in the same
        // process. `scanSingleFileReportsRealOnDiskCaseNotTheCallersURLCase`
        // above never queries `originalURL` before renaming it away, so it
        // passed even against a naive `.nameKey`-only fix that didn't
        // actually solve the real bug. This test reproduces the real
        // sequence: scan once (while the file is still "cyberlip.zip",
        // exactly like the very first "Scan Folder" of a session would),
        // THEN rename, THEN scan the same (now stale) path again.
        _ = try FolderScanner.scanSingleFile(originalURL)

        try FileManager.default.moveItem(at: originalURL, to: root.appendingPathComponent("CYBERLIP.zip"))

        let file = try FolderScanner.scanSingleFile(originalURL)

        #expect(file.name == "CYBERLIP.zip", "must reflect the real on-disk name even after this exact path was already resolved once before the rename")
        #expect(file.url.lastPathComponent == "CYBERLIP.zip")
    }

    @Test("scan(paths:) with several files in the SAME folder resolves every one's real on-disk case correctly, sharing one directory listing rather than one per file")
    func scanPathsWithSeveralFilesInSameFolderShareOneListing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // jensyleo's own follow-up concern (2026-09-10, spinning cursor
        // during testing): fixing several Files at once shouldn't pay for
        // a separate full directory listing per File in the same folder —
        // `scan(paths:)` now shares one `DirectoryListingCache` across the
        // whole call. This confirms that sharing doesn't break
        // correctness: BOTH files, previously queried under their stale
        // pre-rename names (same setup as the single-file test above),
        // must still resolve to their real, current on-disk case.
        let originalA = root.appendingPathComponent("shocktro.zip")
        let originalB = root.appendingPathComponent("cyberlip.zip")
        try Data("a".utf8).write(to: originalA)
        try Data("b".utf8).write(to: originalB)
        _ = try FolderScanner.scan(paths: [originalA, originalB])

        try FileManager.default.moveItem(at: originalA, to: root.appendingPathComponent("SHOCKTRO.zip"))
        try FileManager.default.moveItem(at: originalB, to: root.appendingPathComponent("CYBERLIP.zip"))

        let files = try FolderScanner.scan(paths: [originalA, originalB]).sorted { $0.name < $1.name }

        #expect(files.map(\.name) == ["CYBERLIP.zip", "SHOCKTRO.zip"])
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

    @Test("maxSubfolderDepth is a real, mutable setting — raising it reaches a folder an extra level deeper (e.g. a real BATOCERA export) that the default of 1 would otherwise skip")
    func raisingMaxSubfolderDepthReachesDeeperFolders() throws {
        let originalDepth = FolderScanner.maxSubfolderDepth
        defer { FolderScanner.maxSubfolderDepth = originalDepth }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Same real-world shape as `skipsTooDeepSubfolderInsteadOfThrowing`
        // below (an extra "BATOCERA" folder above the game level) — jensyleo's
        // own report (2026-09-10): with the default depth of 1, EVERY file
        // in a folder shaped like this is silently skipped; raising the
        // setting is the actual fix, not a source change.
        let gameFolder = root.appendingPathComponent("BATOCERA").appendingPathComponent("sfiii3")
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("chd-content".utf8).write(to: gameFolder.appendingPathComponent("cap-33s-1.chd"))

        FolderScanner.maxSubfolderDepth = 1
        #expect(try FolderScanner.scan(folder: root).isEmpty, "at the default depth, this folder should still be skipped entirely")

        FolderScanner.maxSubfolderDepth = 2
        let files = try FolderScanner.scan(folder: root)
        #expect(files.map(\.name) == ["cap-33s-1.chd"], "raised to 2, the same folder's real file should now be found")
    }

    @Test("skips (rather than throwing on) a subfolder nested past one level, reporting it via onSkippedTooDeep, while still scanning everything else normally — jensyleo's own correction (2026-08-05) after trying the throw-and-refuse-everything behavior live: one too-deep subtree shouldn't make an otherwise-scannable folder completely unusable")
    func skipsTooDeepSubfolderInsteadOfThrowing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        // Mirrors the real case that surfaced this: a system folder with an
        // extra subfolder (e.g. "BATOCERA") sitting ABOVE the per-game
        // folder, one level deeper than the convention this project's own
        // testing has always used — alongside a perfectly normal, real
        // game folder at the allowed depth.
        let tooDeep = root.appendingPathComponent("BATOCERA").appendingPathComponent("sfiii3")
        try FileManager.default.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        let normalGameFolder = root.appendingPathComponent("sfiii2")
        try FileManager.default.createDirectory(at: normalGameFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("chd-content".utf8).write(to: tooDeep.appendingPathComponent("cap-33s-1.chd"))
        try Data("rom-content".utf8).write(to: normalGameFolder.appendingPathComponent("cap-3ga000.chd"))

        final class Skipped: @unchecked Sendable {
            private let lock = NSLock()
            private var urls: [URL] = []
            func append(_ url: URL) {
                lock.lock()
                defer { lock.unlock() }
                urls.append(url)
            }
            var all: [URL] {
                lock.lock()
                defer { lock.unlock() }
                return urls
            }
        }
        let skipped = Skipped()
        let files = try FolderScanner.scan(folder: root, onSkippedTooDeep: { skipped.append($0) })

        // The too-deep file never gets enumerated at all; the normal one does.
        #expect(files.map(\.name) == ["cap-3ga000.chd"])
        #expect(skipped.all.count == 1)
        #expect(skipped.all.first?.lastPathComponent == "sfiii3")
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
