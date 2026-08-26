// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
import ZIPFoundation
@testable import ROMForgeCore

@Suite("ZipCommentReader")
struct ZipCommentReaderTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makePlainZip(in root: URL) throws -> URL {
        let payload = Data("123456789".utf8)
        let loosePath = root.appendingPathComponent("game.bin")
        try payload.write(to: loosePath)
        let archiveURL = root.appendingPathComponent("Game.zip")
        let archive = try Archive(url: archiveURL, accessMode: .create)
        try archive.addEntry(with: "game.bin", fileURL: loosePath, compressionMethod: .deflate)
        return archiveURL
    }

    /// A comment-less zip's End of Central Directory record is always the
    /// last 22 bytes of the file (comment length 0 → no comment bytes
    /// follow it) — appending a real comment means patching that record's
    /// own 2-byte length field, then appending the comment bytes after it,
    /// exactly what a real zip tool's own "add archive comment" does.
    @Test("reads a zip's own archive-level comment")
    func readsZipComment() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = try makePlainZip(in: root)

        var bytes = try Data(contentsOf: archiveURL)
        let comment = "Fixed by ROMForge — verified good dump"
        let commentData = Data(comment.utf8)
        let commentLengthOffset = bytes.count - 2
        bytes.replaceSubrange(
            commentLengthOffset..<bytes.count,
            with: withUnsafeBytes(of: UInt16(commentData.count).littleEndian) { Data($0) }
        )
        bytes.append(commentData)
        try bytes.write(to: archiveURL)

        #expect(ZipCommentReader.comment(ofZipAt: archiveURL) == comment)
    }

    @Test("returns nil for a zip with no comment")
    func returnsNilWithoutComment() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = try makePlainZip(in: root)

        #expect(ZipCommentReader.comment(ofZipAt: archiveURL) == nil)
    }

    @Test("returns nil for a non-zip file")
    func returnsNilForNonZip() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let notAZip = root.appendingPathComponent("notes.txt")
        try Data("just some text, no zip structure at all".utf8).write(to: notAZip)

        #expect(ZipCommentReader.comment(ofZipAt: notAZip) == nil)
    }
}
