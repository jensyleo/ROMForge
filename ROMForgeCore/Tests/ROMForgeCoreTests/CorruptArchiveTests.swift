import Foundation
import Testing
@testable import ROMForgeCore

@Suite("Corrupt archives never stop a scan")
struct CorruptArchiveTests {
    @Test("an unreadable zip is reported as corrupt and the rest still hashes")
    func corruptZipDoesNotAbort() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("broken.zip")
        try Data("PK\u{3}\u{4} this is not a real zip".utf8).write(to: bad)
        let good = dir.appendingPathComponent("good.nes")
        try Data([1, 2, 3, 4]).write(to: good)
        let scanned = try FolderScanner.scan(paths: [dir])
        let hashed = try await CollectionHasher.hash(scannedFiles: scanned)
        #expect(hashed.contains { $0.file.name == "broken.zip" && $0.hash.crc32 == CollectionHasher.corruptMarker })
        #expect(hashed.contains { $0.file.name == "good.nes" && $0.hash.crc32 != CollectionHasher.corruptMarker })
    }
}
