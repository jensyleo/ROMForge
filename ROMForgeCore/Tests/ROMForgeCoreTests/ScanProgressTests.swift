// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("ScanProgress")
struct ScanProgressTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("reports progress up to the true total across concurrent workers, thread-safely")
    func reportsFinalProgressAcrossConcurrentFiles() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        var files: [ScannedFile] = []
        for i in 0..<40 {
            let url = root.appendingPathComponent("file\(i).bin")
            try Data("content-\(i)".utf8).write(to: url)
            files.append(ScannedFile(url: url, name: url.lastPathComponent, size: Int64("content-\(i)".utf8.count), modificationDate: .distantPast))
        }

        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var seen: [ScanProgress] = []
            func record(_ progress: ScanProgress) {
                lock.lock(); seen.append(progress); lock.unlock()
            }
        }
        let collector = Collector()
        let counter = ScanProgressCounter(total: files.count) { collector.record($0) }

        _ = try await FileHasher.hash(files: files, progress: counter)

        #expect(collector.seen.last?.completed == files.count)
        #expect(collector.seen.allSatisfy { $0.total == files.count })
        // Monotonically non-decreasing, even with concurrent workers reporting.
        #expect(zip(collector.seen, collector.seen.dropFirst()).allSatisfy { $0.completed <= $1.completed })
    }

    @Test("CollectionHasher reports one continuous total across loose files and zip entries")
    func collectionHasherReportsCombinedTotal() async throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let looseURL = root.appendingPathComponent("loose.bin")
        try Data("loose".utf8).write(to: looseURL)

        let entrySource = root.appendingPathComponent("entry-source.bin")
        try Data("zipped".utf8).write(to: entrySource)
        let zipURL = root.appendingPathComponent("game.zip")
        let archive = try Archive(url: zipURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: entrySource, compressionMethod: .deflate)

        let scannedFiles = try FolderScanner.scan(folder: root)

        final class Collector: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var seen: [ScanProgress] = []
            func record(_ progress: ScanProgress) {
                lock.lock(); seen.append(progress); lock.unlock()
            }
        }
        let collector = Collector()

        let hashedFiles = try await CollectionHasher.hash(scannedFiles: scannedFiles) { collector.record($0) }

        // 2 real files to hash (loose.bin + game.bin inside the zip); entry-source.bin was consumed into the zip and removed from disk conceptually but still exists as a loose file here since we didn't delete it — account for that.
        let expectedTotal = scannedFiles.filter { $0.url.pathExtension.lowercased() != "zip" }.count + 1
        #expect(collector.seen.last?.completed == expectedTotal)
        #expect(hashedFiles.count == expectedTotal)
    }
}
