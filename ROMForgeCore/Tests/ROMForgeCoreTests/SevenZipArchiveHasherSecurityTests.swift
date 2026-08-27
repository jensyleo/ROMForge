// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// jensyleo's own report (2026-08-26, security audit): `SevenZipArchiveHasher`
/// used to buffer a `.7z` entry's fully decompressed output with no size
/// limit — unlike `ZipArchiveHasher`, which has always aborted a suspiciously
/// over-decompressing entry mid-stream. These tests exercise the real 7-Zip
/// process end to end (not a mocked/parsed listing, like
/// `SevenZipArchiveScannerTests`), so they need an actual `7zz`/`7z`
/// executable — `SevenZipLocator` locates whatever this machine has (a
/// Homebrew install or the app's own bundled copy), and every test skips
/// itself cleanly if none is found rather than failing, matching how the app
/// itself degrades when 7-Zip isn't installed.
@Suite("SevenZipArchiveHasher security")
struct SevenZipArchiveHasherSecurityTests {
    private func makeSevenZipArchive(named name: String, entryName: String, contents: Data) throws -> URL? {
        guard let executable = try? SevenZipLocator.locate() else { return nil }
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let entryURL = workDir.appendingPathComponent(entryName)
        try contents.write(to: entryURL)
        let archiveURL = workDir.appendingPathComponent(name)

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = workDir
        process.arguments = ["a", "-mx=9", archiveURL.lastPathComponent, entryURL.lastPathComponent]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: archiveURL.path) else { return nil }
        return archiveURL
    }

    @Test("aborts an entry whose real decompressed size wildly exceeds its declared size (7z decompression-bomb guard)")
    func abortsDecompressionBomb() throws {
        // 50 MiB of zeros compresses to a few KB — the same "tiny on disk,
        // huge decompressed" shape a real decompression bomb has. The
        // scanner-reported `size` (what a crafted archive's metadata could
        // lie about) is simulated directly via `ArchivedFile.size` below,
        // which is exactly the value the hasher's guard is keyed on.
        let bigContent = Data(repeating: 0, count: 50 * 1024 * 1024)
        guard let archiveURL = try makeSevenZipArchive(named: "bomb.7z", entryName: "big.bin", contents: bigContent) else {
            return // No 7-Zip on this machine — skip, matching this suite's own doc comment.
        }
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        // A declared size of 1 KiB against a real 50 MiB payload is far
        // past the guard's `declaredSize × 10` (floor 1 MiB) threshold.
        let lyingFile = ArchivedFile(archiveURL: archiveURL, entryPath: "big.bin", name: "big.bin", size: 1024)

        #expect(throws: SevenZipError.suspectedDecompressionBomb(entryPath: "big.bin", declaredSize: 1024)) {
            try SevenZipArchiveHasher.hash(lyingFile)
        }
    }

    @Test("hashes an entry normally when its declared size is honest")
    func hashesNormallyWithHonestDeclaredSize() throws {
        let content = Data("legitimate rom content".utf8)
        guard let archiveURL = try makeSevenZipArchive(named: "normal.7z", entryName: "rom.bin", contents: content) else {
            return
        }
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let file = ArchivedFile(archiveURL: archiveURL, entryPath: "rom.bin", name: "rom.bin", size: Int64(content.count))
        let hash = try SevenZipArchiveHasher.hash(file)

        #expect(hash == FileHasher.hash(data: content))
    }

    @Test("hashes an entry whose own name begins with a dash (7zz argument-injection guard)")
    func hashesDashPrefixedEntryName() throws {
        // A crafted archive can name an entry however it likes — including
        // something that looks like a 7zz command-line switch. The `--`
        // guard in `SevenZipArchiveHasher` exists so that never changes
        // 7zz's own argument parsing; this confirms extraction still works
        // for exactly that shape of name, end to end against the real
        // process.
        let content = Data("dash-prefixed entry content".utf8)
        guard let archiveURL = try makeSevenZipArchive(named: "dash.7z", entryName: "-p1234looksLikeASwitch.bin", contents: content) else {
            return
        }
        defer { try? FileManager.default.removeItem(at: archiveURL.deletingLastPathComponent()) }

        let file = ArchivedFile(
            archiveURL: archiveURL, entryPath: "-p1234looksLikeASwitch.bin", name: "-p1234looksLikeASwitch.bin",
            size: Int64(content.count)
        )
        let hash = try SevenZipArchiveHasher.hash(file)

        #expect(hash == FileHasher.hash(data: content))
    }
}
