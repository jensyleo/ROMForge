// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One entry to write into a TorrentZip archive: a plain file (non-empty
/// `data`), or an explicit empty-directory marker (`name` ending in `/`,
/// empty `data`) — see `TorrentZipWriter`'s redundant-directory filtering.
public struct TorrentZipEntry: Equatable, Sendable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

public enum TorrentZipWriterError: Error, Equatable {
    case duplicateEntryName(String)
}

/// Writes a `.zip` archive that conforms to the TorrentZip standard (as
/// documented at wiki.romvault.com/doku.php?id=torrentzip, itself a mirror
/// of the original SourceForge `trrntzip` README): every structural byte a
/// TorrentZip-consuming tool checks is fixed to the spec's values, so two
/// independent TorrentZip writers producing the same *file content* also
/// produce the same *archive bytes*.
///
/// Honest limitation, not glossed over: the spec's own reference
/// requirement is "compressed exactly as zlib version 1.1.3 at level 9" —
/// this implementation compresses via macOS's current system `libz`
/// (whatever version Apple ships), which is not guaranteed to produce a
/// byte-identical DEFLATE stream to that specific old zlib release for the
/// same input, even though both are valid, spec-conforming DEFLATE. So a
/// file written here is a structurally correct, spec-conforming TorrentZip
/// (fixed dates/flags/order/comment, decompresses correctly, round-trips),
/// but is not guaranteed bit-for-bit identical to a file the same content
/// produced with the original `trrntzip`/RomVault tools. Closing that last
/// gap would require vendoring zlib 1.1.3 itself, which this project has
/// otherwise deliberately avoided (see CZlib's use of the system library).
public enum TorrentZipWriter {
    /// TorrentZip's fixed timestamp — 12/24/1996 11:32 PM, the date of the
    /// first MAME release — encoded as DOS date/time fields.
    private static let dosTime: UInt16 = 48128
    private static let dosDate: UInt16 = 8600

    private static let versionNeeded: UInt16 = 20
    private static let generalPurposeFlag: UInt16 = 2
    private static let unicodeFlagBit: UInt16 = 0x0800
    private static let localHeaderSignature: UInt32 = 0x0403_4b50
    private static let centralHeaderSignature: UInt32 = 0x0201_4b50
    private static let eocdSignature: UInt32 = 0x0605_4b50

    public static func write(_ entries: [TorrentZipEntry], to url: URL) throws {
        let normalized = try normalize(entries)

        var archive = Data()
        var centralDirectory = Data()
        var localOffsets: [UInt64] = []

        for entry in normalized {
            localOffsets.append(UInt64(archive.count))
            let nameBytes = encodedName(entry.name)
            let isUnicode = nameBytes.isUnicode
            let compressed = try DeflateCompressor.compress([UInt8](entry.data))
            let crc = CRC32.checksum(of: entry.data)
            let flag = generalPurposeFlag | (isUnicode ? unicodeFlagBit : 0)

            var local = Data()
            appendUInt32LE(&local, localHeaderSignature)
            appendUInt16LE(&local, versionNeeded)
            appendUInt16LE(&local, flag)
            appendUInt16LE(&local, 8) // compression method: deflate, always (even empty entries, per spec)
            appendUInt16LE(&local, dosTime)
            appendUInt16LE(&local, dosDate)
            appendUInt32LE(&local, crc)
            appendUInt32LE(&local, UInt32(compressed.count))
            appendUInt32LE(&local, UInt32(entry.data.count))
            appendUInt16LE(&local, UInt16(nameBytes.bytes.count))
            appendUInt16LE(&local, 0) // extra field length
            local.append(contentsOf: nameBytes.bytes)
            local.append(contentsOf: compressed)
            archive.append(local)

            var central = Data()
            appendUInt32LE(&central, centralHeaderSignature)
            appendUInt16LE(&central, 0) // version made by
            appendUInt16LE(&central, versionNeeded)
            appendUInt16LE(&central, flag)
            appendUInt16LE(&central, 8)
            appendUInt16LE(&central, dosTime)
            appendUInt16LE(&central, dosDate)
            appendUInt32LE(&central, crc)
            appendUInt32LE(&central, UInt32(compressed.count))
            appendUInt32LE(&central, UInt32(entry.data.count))
            appendUInt16LE(&central, UInt16(nameBytes.bytes.count))
            appendUInt16LE(&central, 0) // extra field length
            appendUInt16LE(&central, 0) // file comment length
            appendUInt16LE(&central, 0) // disk number start
            appendUInt16LE(&central, 0) // internal attributes
            appendUInt32LE(&central, 0) // external attributes
            appendUInt32LE(&central, UInt32(localOffsets.last!))
            central.append(contentsOf: nameBytes.bytes)
            centralDirectory.append(central)
        }

        let socd = UInt32(archive.count)
        let commentBody = "TORRENTZIPPED-" + String(format: "%08X", CRC32.checksum(of: centralDirectory))

        var eocd = Data()
        appendUInt32LE(&eocd, eocdSignature)
        appendUInt16LE(&eocd, 0)
        appendUInt16LE(&eocd, 0)
        appendUInt16LE(&eocd, UInt16(normalized.count))
        appendUInt16LE(&eocd, UInt16(normalized.count))
        appendUInt32LE(&eocd, UInt32(centralDirectory.count))
        appendUInt32LE(&eocd, socd)
        appendUInt16LE(&eocd, UInt16(commentBody.utf8.count))
        eocd.append(contentsOf: [UInt8](commentBody.utf8))

        var full = archive
        full.append(centralDirectory)
        full.append(eocd)
        try full.write(to: url)
    }

    /// Converts backslashes to forward slashes, drops directory entries
    /// implied by a file entry under them (keeping genuinely empty ones),
    /// and sorts by lowercased filename — the three ordering/normalization
    /// rules the spec requires for reproducibility.
    private static func normalize(_ entries: [TorrentZipEntry]) throws -> [TorrentZipEntry] {
        let slashed = entries.map { TorrentZipEntry(name: $0.name.replacingOccurrences(of: "\\", with: "/"), data: $0.data) }

        var seen = Set<String>()
        for entry in slashed {
            guard seen.insert(entry.name).inserted else {
                throw TorrentZipWriterError.duplicateEntryName(entry.name)
            }
        }

        let filePrefixes = Set(slashed.filter { !$0.name.hasSuffix("/") }.compactMap { entry -> String? in
            guard let lastSlash = entry.name.lastIndex(of: "/") else { return nil }
            return String(entry.name[entry.name.startIndex...lastSlash])
        })
        let kept = slashed.filter { entry in
            !entry.name.hasSuffix("/") || !filePrefixes.contains(entry.name)
        }

        return kept.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private struct EncodedName {
        let bytes: [UInt8]
        let isUnicode: Bool
    }

    /// TorrentZip stores CP437-representable names as-is and falls back to
    /// UTF-8 (flagged via the unicode bit) otherwise. A full CP437 mapping
    /// isn't implemented; this approximates it as "all bytes are printable
    /// ASCII" — true for effectively every real ROM/DAT filename, and a
    /// documented simplification rather than a silent one for the rare
    /// non-ASCII case.
    private static func encodedName(_ name: String) -> EncodedName {
        if name.utf8.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) {
            return EncodedName(bytes: [UInt8](name.utf8), isUnicode: false)
        }
        return EncodedName(bytes: [UInt8](name.utf8), isUnicode: true)
    }

    private static func appendUInt16LE(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
    }

    private static func appendUInt32LE(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }
}
