// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ZIPFoundation

/// Reads just the first bytes of a ROM — a loose file or one entry of a
/// `.zip` — without extracting or reading the rest. Used to decode a SNES
/// header during a scan, where reading a few tens of KB per game is cheap
/// even over a network volume.
public enum ROMPrefixReader {
    private struct EnoughBytes: Error {}

    public static func read(url: URL, entryName: String?, maxBytes: Int) throws -> Data {
        if url.pathExtension.lowercased() == "zip", let entryName {
            let archive = try Archive(url: url, accessMode: .read)
            // Flat archives (the common case) match by full path; otherwise
            // fall back to the entry whose last path component matches.
            let entry = archive[entryName]
                ?? archive.first { ($0.path as NSString).lastPathComponent == entryName }
            guard let entry else { throw CocoaError(.fileNoSuchFile) }
            var collected = Data()
            do {
                _ = try archive.extract(entry) { chunk in
                    collected.append(chunk)
                    if collected.count >= maxBytes { throw EnoughBytes() }
                }
            } catch is EnoughBytes {}
            return collected.prefix(maxBytes)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maxBytes) ?? Data()
    }
}
