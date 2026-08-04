// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// One hunk's entry in a decoded CHD v5 map: which codec compresses it (a
/// raw `CompressionType` value — `0`–`3` are the file's own declared codecs
/// in `CHDHeader`; `4` "none", `5` "self", `6` "parent" are pseudo-codecs
/// needing no external decompressor), its compressed length, its byte
/// offset in the file (or hunk index, for self/parent), and its stored
/// CRC16 (0 for self/parent, which have no compressed payload of their own
/// to check).
public struct CHDMapEntry: Equatable, Sendable {
    public let compressionType: UInt8
    public let length: UInt32
    public let offset: UInt64
    public let crc16: UInt16

    public init(compressionType: UInt8, length: UInt32, offset: UInt64, crc16: UInt16) {
        self.compressionType = compressionType
        self.length = length
        self.offset = offset
        self.crc16 = crc16
    }
}

/// Decodes a CHD v5 file's compressed hunk map — the part of the format
/// that makes reading *any* CHD v5 hunk (regardless of its own codec)
/// non-trivial in the first place: the map itself is Huffman-compressed
/// with run-length-encoded repeats, since consecutive hunks are frequently
/// identical in size/codec. Faithfully ported from MAME's own
/// `chd_file::decompress_v5_map()` (`src/lib/util/chd.cpp`).
///
/// This reads the map only — it does not decompress hunk *bodies* (LZMA/
/// MAME's own hunk-body Huffman/FLAC/CD-composite are still not
/// implemented; zlib is, via `CHDZlibDecompressor`), which remains
/// separate, later work (see ROADMAP.md). The map's CRC16 (`mapcrc`) is
/// verified when the caller supplies it, using `CHDCRC16` (MAME's own
/// variant, `util::crc16_creator`) over the same 12-byte-per-hunk raw
/// layout the real format checks against.
public enum CHDV5MapReader {
    public enum MapIntegrityError: Error, Equatable {
        case crc16Mismatch(expected: UInt16, actual: UInt16)
    }

    // Raw values match MAME's `chd_file::compression_type` enum exactly
    // (`src/lib/util/chd.cpp`) — auto-incrementing after the explicit ones.
    static let compressionType0: UInt8 = 0
    static let compressionType1: UInt8 = 1
    static let compressionType2: UInt8 = 2
    static let compressionType3: UInt8 = 3
    static let compressionNone: UInt8 = 4
    static let compressionSelf: UInt8 = 5
    static let compressionParent: UInt8 = 6
    static let compressionRLESmall: UInt8 = 7
    static let compressionRLELarge: UInt8 = 8
    static let compressionSelf0: UInt8 = 9
    static let compressionSelf1: UInt8 = 10
    static let compressionParentSelf: UInt8 = 11
    static let compressionParent0: UInt8 = 12
    static let compressionParent1: UInt8 = 13

    /// - Parameters:
    ///   - compressed: the map's compressed bytes (everything after the
    ///     16-byte map header: `mapbytes`/`firstoffs`/`mapcrc`/`lengthbits`/
    ///     `selfbits`/`parentbits`, already parsed by the caller).
    ///   - hunkCount: total hunks in the CHD (`chd.h`'s hunk count, derived
    ///     from `logicalBytes`/`hunkBytes`).
    ///   - hunkBytes/unitBytes: from `CHDHeader`.
    ///   - firstOffset/lengthBits/selfBits/parentBits: the four remaining
    ///     fields of the 16-byte map header.
    ///   - expectedMapCRC16: the map header's own `mapcrc` field, if the
    ///     caller wants the decoded map verified against it (throws
    ///     `MapIntegrityError.crc16Mismatch` on a mismatch). Nil skips
    ///     verification.
    public static func decode(
        compressed: [UInt8],
        hunkCount: Int,
        hunkBytes: UInt32,
        unitBytes: UInt32,
        firstOffset: UInt64,
        lengthBits: Int,
        selfBits: Int,
        parentBits: Int,
        expectedMapCRC16: UInt16? = nil
    ) throws -> [CHDMapEntry] {
        var bits = CHDBitReader(compressed)
        var decoder = CHDMapHuffmanDecoder()
        try decoder.importTreeRLE(&bits)

        // Pass 1: decode the per-hunk compression-type stream, expanding
        // the RLE_SMALL/RLE_LARGE repeat tokens into actual per-hunk types.
        var rawTypes = [UInt8](repeating: 0, count: hunkCount)
        var lastComp: UInt8 = 0
        var repeatCount = 0
        for hunkNum in 0..<hunkCount {
            if repeatCount > 0 {
                rawTypes[hunkNum] = lastComp
                repeatCount -= 1
                continue
            }
            let value = UInt8(decoder.decodeOne(&bits))
            switch value {
            case compressionRLESmall:
                rawTypes[hunkNum] = lastComp
                repeatCount = 2 + decoder.decodeOne(&bits)
            case compressionRLELarge:
                rawTypes[hunkNum] = lastComp
                repeatCount = 2 + 16 + (decoder.decodeOne(&bits) << 4)
                repeatCount += decoder.decodeOne(&bits)
            default:
                rawTypes[hunkNum] = value
                lastComp = value
            }
        }

        // Pass 2: walk the hunks in order, reading each one's own
        // length/offset/CRC (or resolving a self/parent reference),
        // exactly mirroring the real per-case logic in
        // `decompress_v5_map`, including the pseudo-type fallthroughs.
        var entries: [CHDMapEntry] = []
        entries.reserveCapacity(hunkCount)
        var curOffset = firstOffset
        var lastSelf: UInt64 = 0
        var lastParent: UInt64 = 0

        for hunkNum in 0..<hunkCount {
            var type = rawTypes[hunkNum]
            var offset = curOffset
            var length: UInt32 = 0
            var crc16: UInt16 = 0

            switch type {
            case compressionType0, compressionType1, compressionType2, compressionType3:
                length = bits.read(lengthBits)
                curOffset += UInt64(length)
                crc16 = UInt16(bits.read(16))
            case compressionNone:
                length = hunkBytes
                curOffset += UInt64(length)
                crc16 = UInt16(bits.read(16))
            case compressionSelf:
                let value = UInt64(bits.read(selfBits))
                lastSelf = value
                offset = value
            case compressionParent:
                let value = UInt64(bits.read(parentBits))
                offset = value
                lastParent = value
            case compressionSelf1:
                lastSelf += 1
                type = compressionSelf
                offset = lastSelf
            case compressionSelf0:
                type = compressionSelf
                offset = lastSelf
            case compressionParentSelf:
                type = compressionParent
                let value = UInt64(hunkNum) * UInt64(hunkBytes) / UInt64(unitBytes)
                lastParent = value
                offset = value
            case compressionParent1:
                lastParent += UInt64(hunkBytes / unitBytes)
                type = compressionParent
                offset = lastParent
            case compressionParent0:
                type = compressionParent
                offset = lastParent
            default:
                break
            }

            entries.append(CHDMapEntry(compressionType: type, length: length, offset: offset, crc16: crc16))
        }

        if let expectedMapCRC16 {
            let actual = CHDCRC16.compute(rawMapBytes(for: entries))
            guard actual == expectedMapCRC16 else {
                throw MapIntegrityError.crc16Mismatch(expected: expectedMapCRC16, actual: actual)
            }
        }

        return entries
    }

    /// Rebuilds the same 12-byte-per-hunk raw layout (`type`, 3-byte
    /// length, 6-byte offset, 2-byte CRC, all big-endian) that
    /// `decompress_v5_map()` computes its `mapcrc` check over.
    private static func rawMapBytes(for entries: [CHDMapEntry]) -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(entries.count * 12)
        for entry in entries {
            bytes.append(entry.compressionType)
            bytes.append(contentsOf: bigEndianBytes(UInt64(entry.length), count: 3))
            bytes.append(contentsOf: bigEndianBytes(entry.offset, count: 6))
            bytes.append(contentsOf: bigEndianBytes(UInt64(entry.crc16), count: 2))
        }
        return bytes
    }

    private static func bigEndianBytes(_ value: UInt64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8((value >> (8 * (count - 1 - $0))) & 0xff) }
    }
}
