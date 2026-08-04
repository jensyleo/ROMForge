// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("CollectionHasher")
struct CollectionHasherTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("hashes loose files directly and expands zip entries instead of hashing the archive itself")
    func hashesLooseFilesAndExpandsZipEntries() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let looseURL = root.appendingPathComponent("loose.bin")
        try Data("loose-content".utf8).write(to: looseURL)

        let entrySourceURL = root.appendingPathComponent("entry-source.bin")
        try Data("zipped-content".utf8).write(to: entrySourceURL)
        let zipURL = root.appendingPathComponent("game.zip")
        let archive = try Archive(url: zipURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: entrySourceURL, compressionMethod: .deflate)

        let scannedFiles = try FolderScanner.scan(folder: root)
        // The temp folder now has loose.bin, entry-source.bin and game.zip.
        #expect(scannedFiles.count == 3)

        let hashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles)

        let looseMatch = try #require(hashedFiles.first { $0.file.name == "loose.bin" })
        #expect(looseMatch.file.url.resolvingSymlinksInPath() == looseURL.resolvingSymlinksInPath())

        let zipEntryMatch = try #require(hashedFiles.first { $0.file.name == "game.bin" })
        #expect(
            zipEntryMatch.file.url.resolvingSymlinksInPath() == zipURL.resolvingSymlinksInPath(),
            "a zip entry's file.url should point at the container, not a standalone file"
        )
        #expect(zipEntryMatch.hash == FileHasher.hash(data: Data("zipped-content".utf8)))

        // The archive itself must never appear as its own hashed entry.
        #expect(!hashedFiles.contains { $0.file.name == "game.zip" })
    }

    @Test("concurrently hashes entries spread across many zips and still returns every one correctly")
    func concurrentlyHashesManyZipEntries() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var expectedByName: [String: Data] = [:]
        for zipIndex in 0..<6 {
            let zipURL = root.appendingPathComponent("set\(zipIndex).zip")
            let archive = try Archive(url: zipURL, accessMode: .create)
            for entryIndex in 0..<4 {
                let name = "rom\(zipIndex)-\(entryIndex).bin"
                let content = Data("content-\(zipIndex)-\(entryIndex)".utf8)
                let sourceURL = root.appendingPathComponent("src-\(zipIndex)-\(entryIndex).bin")
                try content.write(to: sourceURL)
                try archive.addEntry(with: name, fileURL: sourceURL, compressionMethod: .deflate)
                expectedByName[name] = content
                try FileManager.default.removeItem(at: sourceURL)
            }
        }

        let scannedFiles = try FolderScanner.scan(folder: root)
        let hashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles)

        let zipEntries = hashedFiles.filter { $0.file.name.hasSuffix(".bin") }
        #expect(zipEntries.count == 24)
        for (name, content) in expectedByName {
            let match = try #require(zipEntries.first { $0.file.name == name })
            #expect(match.hash == FileHasher.hash(data: content))
        }
    }
}
