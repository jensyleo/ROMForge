// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

public enum CHDHunkReaderError: Error, Equatable {
    case cannotOpenFile(URL)
    case truncatedMapHeader(URL)
    case unsupportedCodec(UInt8)
    case parentRequired(hunk: Int)
    case hunkIndexOutOfRange(Int)
}

/// Reads and decompresses individual hunks from a real CHD v5 file, tying
/// together `CHDHeaderReader` (locates the map), `CHDV5MapReader` (decodes
/// it), and `CHDZlibDecompressor` (the one hunk-body codec implemented so
/// far). Only `compressionType0` (mapped to zlib — the only codec index
/// this environment can decompress; a real CHD may use LZMA/Huffman/FLAC/CD
/// composite at that same index depending on how it was created, which
/// this cannot distinguish without a real file to confirm against — see
/// ROADMAP.md), `compressionNone`, and `compressionSelf` are resolvable
/// without external dependencies this environment doesn't have.
/// `compressionParent` requires the parent CHD's own reader.
public final class CHDHunkReader {
    public let header: CHDHeader
    public let mapEntries: [CHDMapEntry]
    private let handle: FileHandle
    private let parent: CHDHunkReader?
    private var selfCache: [Int: [UInt8]] = [:]

    public init(contentsOf url: URL, parent: CHDHunkReader? = nil) throws {
        guard let handle = FileHandle(forReadingAtPath: url.path) else {
            throw CHDHunkReaderError.cannotOpenFile(url)
        }
        self.handle = handle
        self.header = try CHDHeaderReader.read(contentsOf: url)
        self.parent = parent

        try handle.seek(toOffset: header.mapOffset)
        guard let mapHeaderData = try handle.read(upToCount: 16), mapHeaderData.count == 16 else {
            throw CHDHunkReaderError.truncatedMapHeader(url)
        }
        let mapBytes = Self.readUInt32BE(mapHeaderData, at: 0)
        let firstOffset = Self.readUInt48BE(mapHeaderData, at: 4)
        let mapCRC = UInt16(Self.readUInt16BE(mapHeaderData, at: 10))
        let lengthBits = Int(mapHeaderData[mapHeaderData.startIndex + 12])
        let selfBits = Int(mapHeaderData[mapHeaderData.startIndex + 13])
        let parentBits = Int(mapHeaderData[mapHeaderData.startIndex + 14])

        guard let compressedMap = try handle.read(upToCount: Int(mapBytes)), compressedMap.count == Int(mapBytes) else {
            throw CHDHunkReaderError.truncatedMapHeader(url)
        }

        let hunkCount = Int((header.logicalBytes + UInt64(header.hunkBytes) - 1) / UInt64(header.hunkBytes))
        self.mapEntries = try CHDV5MapReader.decode(
            compressed: [UInt8](compressedMap),
            hunkCount: hunkCount,
            hunkBytes: header.hunkBytes,
            unitBytes: header.unitBytes,
            firstOffset: firstOffset,
            lengthBits: lengthBits,
            selfBits: selfBits,
            parentBits: parentBits,
            expectedMapCRC16: mapCRC
        )
    }

    /// Returns the decompressed bytes for hunk `index` (always
    /// `header.hunkBytes` long, except possibly the final hunk of a file
    /// whose `logicalBytes` isn't an exact multiple of `hunkBytes`).
    public func readHunk(_ index: Int) throws -> [UInt8] {
        guard mapEntries.indices.contains(index) else {
            throw CHDHunkReaderError.hunkIndexOutOfRange(index)
        }
        if let cached = selfCache[index] { return cached }

        let entry = mapEntries[index]
        let result: [UInt8]
        switch entry.compressionType {
        case CHDV5MapReader.compressionNone:
            try handle.seek(toOffset: entry.offset)
            guard let raw = try handle.read(upToCount: Int(entry.length)) else {
                throw CHDHunkReaderError.hunkIndexOutOfRange(index)
            }
            result = [UInt8](raw)
        case CHDV5MapReader.compressionType0, CHDV5MapReader.compressionType1,
             CHDV5MapReader.compressionType2, CHDV5MapReader.compressionType3:
            try handle.seek(toOffset: entry.offset)
            guard let raw = try handle.read(upToCount: Int(entry.length)) else {
                throw CHDHunkReaderError.hunkIndexOutOfRange(index)
            }
            result = try Self.decompressTaggedSlot(
                [UInt8](raw), slot: Int(entry.compressionType), header: header
            )
        case CHDV5MapReader.compressionSelf:
            result = try readHunk(Int(entry.offset))
        case CHDV5MapReader.compressionParent:
            guard let parent else {
                throw CHDHunkReaderError.parentRequired(hunk: index)
            }
            let parentHunkIndex = Int(entry.offset * UInt64(header.unitBytes) / UInt64(parent.header.hunkBytes))
            result = try parent.readHunk(parentHunkIndex)
        default:
            throw CHDHunkReaderError.unsupportedCodec(entry.compressionType)
        }

        selfCache[index] = result
        return result
    }

    /// FourCC tags, big-endian 4-char codes exactly as MAME defines them
    /// (`CHD_MAKE_TAG`, `chdcodec.h`) — e.g. 'z','l','i','b' packed into one
    /// UInt32 reads as 0x7a6c6962.
    private static func fourCC(_ chars: String) -> UInt32 {
        chars.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    private static let tagZlib = fourCC("zlib")
    private static let tagLZMA = fourCC("lzma")
    private static let tagHuffman = fourCC("huff")
    private static let tagCDZlib = fourCC("cdzl")
    private static let tagCDLZMA = fourCC("cdlz")
    private static let tagCDFlac = fourCC("cdfl")

    /// Resolves compression "slot" 0-3 (what a map entry's own
    /// `compressionType` names) to the actual codec this specific CHD
    /// declared for that slot (`header.compressorTags`), then decompresses
    /// accordingly. Two different CHDs can use slot 0 for entirely
    /// different codecs — always resolve through the header, never assume.
    private static func decompressTaggedSlot(_ raw: [UInt8], slot: Int, header: CHDHeader) throws -> [UInt8] {
        guard header.compressorTags.indices.contains(slot) else {
            throw CHDHunkReaderError.unsupportedCodec(UInt8(slot))
        }
        let tag = header.compressorTags[slot]
        switch tag {
        case tagZlib:
            return try CHDZlibDecompressor.decompress(raw, decompressedSize: Int(header.hunkBytes))
        case tagLZMA:
            return try CHDLZMADecompressor.decompress(raw, decompressedSize: Int(header.hunkBytes))
        case tagHuffman:
            return try CHDHuffmanDecompressor.decompress(raw, decompressedSize: Int(header.hunkBytes))
        case tagCDZlib:
            return try CHDCDCompositeDecompressor.decompress(raw, decompressedSize: Int(header.hunkBytes), base: .zlib)
        case tagCDLZMA:
            return try CHDCDCompositeDecompressor.decompress(raw, decompressedSize: Int(header.hunkBytes), base: .lzma)
        case tagCDFlac:
            // Not yet implemented — MAME's own custom FLAC bitstream
            // framing for CD hunks (`chd_cd_flac_decompressor`) isn't a
            // standard container libFLAC's public API can read directly,
            // and no real CHD sample using this slot was available to
            // validate a port against (see ROADMAP.md). None of a real
            // CPS3 CHD's 2849 hunks used this slot in practice (only
            // `cdlz`/`cdzl` did) — reported clearly rather than
            // guessed at.
            throw CHDHunkReaderError.unsupportedCodec(UInt8(slot))
        default:
            throw CHDHunkReaderError.unsupportedCodec(UInt8(slot))
        }
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let start = data.startIndex + offset
        return data[start..<start + 4].reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static func readUInt48BE(_ data: Data, at offset: Int) -> UInt64 {
        let start = data.startIndex + offset
        return data[start..<start + 6].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func readUInt16BE(_ data: Data, at offset: Int) -> UInt16 {
        let start = data.startIndex + offset
        return data[start..<start + 2].reduce(0) { ($0 << 8) | UInt16($1) }
    }
}
