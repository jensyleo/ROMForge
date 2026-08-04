// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Reads a zip's own archive-level comment — the free-text field a zip tool
/// can set on the whole archive (End of Central Directory record), distinct
/// from any per-entry comment. jensyleo's own request (2026-07-30): surface
/// this in the "Info" column alongside each rom's own audit status, since
/// some real-world romsets carry notes (dump source, fixer credits, etc.) in
/// this field that ROMForge otherwise silently discards.
///
/// ZIPFoundation (this project's own zip library) parses this same field
/// internally but never exposes it through its public API — its
/// `EndOfCentralDirectoryRecord` type and the property holding it are both
/// non-public. Reading it here is a small, self-contained implementation of
/// the same well-documented format (PKWARE's APPNOTE.TXT §4.3.16) rather
/// than a fork/patch of the vendored library.
public enum ZipCommentReader {
    private static let signature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
    /// The comment length field is 16 bits, so 65535 bytes is the absolute
    /// maximum a zip's own comment can ever be; +22 for the fixed-size part
    /// of the record itself, ahead of the comment bytes.
    private static let maxRecordSize = 65535 + 22

    /// `nil` for a missing/unreadable file, a file with no End of Central
    /// Directory record at all (not actually a zip), or a zip with an empty
    /// comment — all treated alike, since none of them have anything to show.
    public static func comment(ofZipAt url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let fileSize = try? handle.seekToEnd() else { return nil }
        let readSize = min(UInt64(maxRecordSize), fileSize)
        guard readSize >= 22 else { return nil }
        let offset = fileSize - readSize
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        guard let tail = try? handle.readToEnd(), !tail.isEmpty else { return nil }

        // The signature can appear more than once in a comment that happens
        // to contain those same 4 bytes — searching from the END finds the
        // real record, since the comment (if any) is everything AFTER it.
        guard let signatureStart = lastRange(of: signature, in: tail) else { return nil }
        let commentLengthOffset = signatureStart + 20
        guard tail.count >= commentLengthOffset + 2 else { return nil }
        let lengthBytes = tail[tail.startIndex + commentLengthOffset ..< tail.startIndex + commentLengthOffset + 2]
        let commentLength = Int(UInt16(lengthBytes[lengthBytes.startIndex]) | (UInt16(lengthBytes[lengthBytes.startIndex + 1]) << 8))
        guard commentLength > 0 else { return nil }
        let commentStart = tail.startIndex + commentLengthOffset + 2
        guard tail.distance(from: commentStart, to: tail.endIndex) >= commentLength else { return nil }
        let commentData = tail[commentStart ..< tail.index(commentStart, offsetBy: commentLength)]
        // The zip spec never mandates an encoding for this field — real
        // tools from the DOS/Win9x era wrote it as Latin-1/CP437, so that's
        // tried as a fallback when it isn't valid UTF-8, rather than
        // dropping the comment entirely.
        let text = String(data: Data(commentData), encoding: .utf8)
            ?? String(data: Data(commentData), encoding: .isoLatin1)
        return text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? text : nil
    }

    private static func lastRange(of pattern: [UInt8], in data: Data) -> Int? {
        guard pattern.count <= data.count else { return nil }
        let bytes = [UInt8](data)
        var index = bytes.count - pattern.count
        while index >= 0 {
            if Array(bytes[index ..< index + pattern.count]) == pattern { return index }
            index -= 1
        }
        return nil
    }
}
