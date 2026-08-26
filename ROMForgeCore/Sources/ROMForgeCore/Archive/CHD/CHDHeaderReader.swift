// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Reads a CHD v5 header directly — 124 big-endian bytes, verified against
/// MAME's own `src/lib/util/chd.h`/`chd.cpp` (the "MComprHD" tag at offset 0,
/// `sha1` at offset 84). No hunk data is read or decompressed: the header's
/// own `sha1` is already what a DAT's `<disk sha1="...">` is compared
/// against, so verification never needs to touch the compressed body.
public enum CHDHeaderReader {
    private static let headerSize = 124
    private static let magic = Data("MComprHD".utf8)

    public static func read(contentsOf url: URL) throws -> CHDHeader {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw CHDError.cannotOpenFile(url)
        }
        defer { try? handle.close() }

        guard let data = try handle.read(upToCount: headerSize),
              data.count == headerSize,
              data.prefix(8).elementsEqual(magic) else {
            throw CHDError.notAValidCHD(url)
        }

        let version = readUInt32BE(data, at: 12)
        guard version == 5 else {
            throw CHDError.unsupportedVersion(version, url)
        }

        return CHDHeader(
            version: version,
            logicalBytes: readUInt64BE(data, at: 32),
            mapOffset: readUInt64BE(data, at: 40),
            hunkBytes: readUInt32BE(data, at: 56),
            unitBytes: readUInt32BE(data, at: 60),
            compressorTags: (0..<4).map { readUInt32BE(data, at: 16 + $0 * 4) },
            rawSHA1: hexString(data, from: 64, count: 20),
            sha1: hexString(data, from: 84, count: 20),
            parentSHA1: nonZeroHexString(data, from: 104, count: 20)
        )
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return data[start..<start + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func readUInt64BE(_ data: Data, at offset: Int) -> UInt64 {
        let start = data.startIndex + offset
        return data[start..<start + 8].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func hexString(_ data: Data, from offset: Int, count: Int) -> String {
        let start = data.startIndex + offset
        return data[start..<start + count].map { String(format: "%02x", $0) }.joined()
    }

    private static func nonZeroHexString(_ data: Data, from offset: Int, count: Int) -> String? {
        let start = data.startIndex + offset
        let bytes = data[start..<start + count]
        return bytes.allSatisfy { $0 == 0 } ? nil : hexString(data, from: offset, count: count)
    }
}
