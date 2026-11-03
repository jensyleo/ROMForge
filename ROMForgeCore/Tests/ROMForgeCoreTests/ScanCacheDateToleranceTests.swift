import Foundation
import Testing
@testable import ROMForgeCore

@Suite("ScanCache date tolerance")
struct ScanCacheDateToleranceTests {
    @Test("a sub-second mtime survives the JSON round trip as a cache hit")
    func fractionalMtimeHits() throws {
        let mtime = Date(timeIntervalSinceReferenceDate: 723926894.771829600)
        let file = ScannedFile(url: URL(fileURLWithPath: "/tmp/x.3ds"), name: "x.3ds", size: 10, modificationDate: mtime)
        let hashed = HashedFile(file: file, hash: FileHash(crc32: "00000001", md5: nil, sha1: nil))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try ScanCache.build(from: [hashed], chdPaths: []).save(to: url)
        let loaded = try ScanCache.load(contentsOf: url)
        #expect(loaded.lookup(for: file, algorithms: .crc32) != nil)
    }
}
