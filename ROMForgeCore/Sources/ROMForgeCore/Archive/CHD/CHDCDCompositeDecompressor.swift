// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum CHDCDCompositeError: Error, Equatable {
    case notAFrameMultiple(hunkBytes: UInt32)
    case truncatedHeader
    case eccRegionOutOfRange
}

/// The actual codec real MAME CD-CHDs use for their hunk bodies — CD
/// "composite" codecs (`cdlz`/`cdzl`; `cdfl`'s FLAC variant is a separate,
/// not-yet-implemented codec) are NOT a plain compressed blob the way
/// `CHDZlibDecompressor`/`CHDLZMADecompressor` decode "type 0"/"type 1" CHDs
/// (e.g. hard disk images). Confirmed directly against a real CPS3 CHD
/// (`cap-sf3-3.chd`, 2026-07-30): its own header declares `cdlz`/`cdzl`/
/// `cdfl` as its 3 codec slots, and every one of its 2849 hunks used only
/// the first two.
///
/// Ported from MAME's `chd_cd_decompressor` template
/// (`src/lib/util/chdcodec.cpp`, fetched 2026-07-30 from
/// github.com/mamedev/mame). Each CD hunk holds several whole 2448-byte CD
/// frames (sync+header+data+ECC, plus 96 bytes of subcode) —
/// `frames = hunkBytes / 2448`. The encoder:
///  1. Splits each frame into its 2352-byte sector portion and 96-byte
///     subcode portion, and reorders the hunk as ALL sector data first,
///     then ALL subcode data (not interleaved per-frame).
///  2. For any sector whose 12-byte sync pattern and P/Q ECC bytes are
///     already exactly what regenerating them would produce (`CDSectorECC
///     .verify`) — true for the overwhelming majority of real, valid CD
///     dumps — both are zeroed out before compression, since ECC bytes
///     compress terribly (they're pseudo-random parity, not payload) and
///     are one bit-flag away from being reconstructed instead of stored.
///  3. The sector-data block is compressed with the CD codec's own "base"
///     compressor (LZMA for `cdlz`, zlib for `cdzl`); the subcode block is
///     ALWAYS zlib, regardless of which CD codec variant this is.
/// A per-hunk header (a `frames`-bit bitmap of which sectors had their
/// sync/ECC stripped, plus the base-compressed-length as 2 or 3 bytes)
/// precedes the two compressed blocks.
public enum CHDCDCompositeDecompressor {
    private static let frameSize = 2448
    private static let maxSectorData = 2352
    private static let maxSubcodeData = 96
    private static let syncOffset = 0
    private static let syncNumBytes = 12
    private static let syncHeader: [UInt8] = [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00]

    public enum BaseCodec {
        case zlib
        case lzma
    }

    /// - Parameters:
    ///   - compressed: the hunk's compressed bytes exactly as stored (map
    ///     entry's own `length`, starting at its own `offset`).
    ///   - decompressedSize: `header.hunkBytes` for every hunk except
    ///     possibly the file's last one.
    public static func decompress(_ compressed: [UInt8], decompressedSize: Int, base: BaseCodec) throws -> [UInt8] {
        guard decompressedSize % frameSize == 0 else {
            throw CHDCDCompositeError.notAFrameMultiple(hunkBytes: UInt32(decompressedSize))
        }
        let frames = decompressedSize / frameSize
        let complenBytes = decompressedSize < 65536 ? 2 : 3
        let eccBytes = (frames + 7) / 8
        let headerBytes = eccBytes + complenBytes
        guard compressed.count >= headerBytes else {
            throw CHDCDCompositeError.truncatedHeader
        }

        let complenBase: Int
        if complenBytes > 2 {
            complenBase = Int(compressed[eccBytes]) << 16 | Int(compressed[eccBytes + 1]) << 8 | Int(compressed[eccBytes + 2])
        } else {
            complenBase = Int(compressed[eccBytes]) << 8 | Int(compressed[eccBytes + 1])
        }

        let baseCompressed = Array(compressed[headerBytes ..< headerBytes + complenBase])
        let subcodeCompressed = Array(compressed[(headerBytes + complenBase)...])

        let sectorDataSize = frames * maxSectorData
        let subcodeDataSize = frames * maxSubcodeData
        let sectorData: [UInt8]
        switch base {
        case .zlib:
            sectorData = try CHDZlibDecompressor.decompress(baseCompressed, decompressedSize: sectorDataSize)
        case .lzma:
            sectorData = try CHDLZMADecompressor.decompress(baseCompressed, decompressedSize: sectorDataSize)
        }
        let subcodeData = try CHDZlibDecompressor.decompress(subcodeCompressed, decompressedSize: subcodeDataSize)

        var dest = [UInt8](repeating: 0, count: decompressedSize)
        for frame in 0..<frames {
            var sector = Array(sectorData[frame * maxSectorData ..< (frame + 1) * maxSectorData])
            // Bit `frame % 8` of byte `frame / 8` in the per-hunk ECC bitmap
            // marks a sector whose sync/ECC were stripped at compress time
            // — reconstitute both exactly, or the sector (and the file's
            // overall hash) won't match the original.
            if (compressed[frame / 8] & (1 << (frame % 8))) != 0 {
                sector.replaceSubrange(syncOffset ..< syncOffset + syncNumBytes, with: syncHeader)
                CDSectorECC.generate(&sector)
            }
            let destOffset = frame * frameSize
            dest.replaceSubrange(destOffset ..< destOffset + maxSectorData, with: sector)
            let subcodeOffset = frame * maxSubcodeData
            dest.replaceSubrange(
                destOffset + maxSectorData ..< destOffset + maxSectorData + maxSubcodeData,
                with: subcodeData[subcodeOffset ..< subcodeOffset + maxSubcodeData]
            )
        }
        return dest
    }
}
