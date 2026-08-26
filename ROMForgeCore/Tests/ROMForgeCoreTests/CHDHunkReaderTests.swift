// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// No real, legally-obtainable CHD file was available in this environment
/// (same restriction as sourcing ROMs — see TESTING.md). This test instead
/// hand-assembles a complete, byte-accurate synthetic CHD v5 file — real
/// 124-byte header, real 16-byte map header, a real Huffman-compressed map
/// (same uniform-tree construction verified in `CHDV5MapReaderTests`), and
/// a real raw-deflate hunk body (the same independently Python-generated
/// fixture used in `CHDZlibDecompressorTests`) — and exercises the full,
/// tied-together read path (`CHDHeaderReader` + `CHDV5MapReader` +
/// `CHDZlibDecompressor`) end to end through `CHDHunkReader`. This proves
/// the pieces work together on a self-consistent file; it does not
/// substitute for validating against an authentic chdman-produced CHD,
/// which remains explicitly flagged as not yet done (see ROADMAP.md).
@Suite("CHDHunkReader")
struct CHDHunkReaderTests {
    private struct BitPacker {
        private var bytes: [UInt8] = [0]
        private var bitPos = 0

        mutating func append(_ value: Int, bits: Int) {
            for i in stride(from: bits - 1, through: 0, by: -1) {
                let bit = (value >> i) & 1
                if bitPos == 8 {
                    bytes.append(0)
                    bitPos = 0
                }
                bytes[bytes.count - 1] |= UInt8(bit) << (7 - bitPos)
                bitPos += 1
            }
        }

        var result: [UInt8] { bytes }
    }

    private func appendUniformTreeImport(_ packer: inout BitPacker) {
        for _ in 0..<16 {
            packer.append(4, bits: 4)
        }
    }

    private func bigEndian(_ value: UInt64, count: Int) -> [UInt8] {
        (0..<count).map { UInt8((value >> (8 * (count - 1 - $0))) & 0xff) }
    }

    private func bytes(fromHex hex: String) -> [UInt8] {
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            result.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return result
    }

    @Test("reads a NONE hunk, a zlib (type0) hunk, and a SELF hunk from a hand-built synthetic CHD v5 file")
    func readsRealHunksFromSyntheticFile() throws {
        // Hunk 1's payload: the same real raw-deflate fixture (Python's
        // zlib.compressobj(9, zlib.DEFLATED, -15)) already independently
        // verified in CHDZlibDecompressorTests.
        let hunk1Plain = """
        Hello CHD hunk decompression test! This is the actual hunk content that would live inside a CHD v5 file, \
        compressed with raw deflate (no zlib header/trailer), exactly matching MAME chd_zlib_compressor deflateInit2 \
        with negative window bits.
        """
        let hunk1Compressed = bytes(fromHex: "358ec16a42410c457fe576a7200a857e80b4825dbc9d7b8933d1098d1999c973d4af77ac3cc82a9c9c932dab667c6f7f9046fb43e490cf97c2b54a363857ffc02e49451f4f0c0a3e92bed990cdd9bcefc9d1f2a8112a57865895d8d17febf50b47515e60f27244134f28d47aeda8e48c99653c540e484c91cbca0bf59b325f806fbda8779cc943123b61580f1b8414f72f7e3f4973995cbf26fef92e189fc85f0f35b1981b0ee275f904")
        let hunkBytes = UInt32(hunk1Plain.utf8.count)

        // Hunk 0's payload (COMPRESSION_NONE — stored verbatim), padded/
        // truncated to the same hunkBytes as every other hunk in the file
        // (CHD requires a single uniform hunk size).
        var hunk0Plain = [UInt8]("NONE-HUNK-RAW-BYTES-".utf8)
        while hunk0Plain.count < Int(hunkBytes) { hunk0Plain.append(0x2a) }
        hunk0Plain = Array(hunk0Plain.prefix(Int(hunkBytes)))

        // --- Build the map: 3 hunks — NONE, type0(zlib), SELF(->hunk0) ---
        var packer = BitPacker()
        appendUniformTreeImport(&packer)
        packer.append(4, bits: 4) // hunk0: COMPRESSION_NONE
        packer.append(0, bits: 4) // hunk1: COMPRESSION_TYPE_0 (zlib)
        packer.append(5, bits: 4) // hunk2: COMPRESSION_SELF
        // Pass-2 reads, in hunk order:
        packer.append(0x0000, bits: 16) // hunk0 NONE: 16-bit crc (unused by reader, but format requires it)
        let lengthBits = 32
        packer.append(hunk1Compressed.count, bits: lengthBits) // hunk1 type0: length
        packer.append(0x0000, bits: 16) // hunk1 type0: 16-bit crc
        let selfBits = 8
        packer.append(0, bits: selfBits) // hunk2 SELF: self-hunk index 0

        let compressedMap = packer.result

        // Compute the real entries the same way CHDV5MapReader will, purely
        // to derive file offsets/mapcrc for assembly (not a shortcut around
        // decoding — CHDV5MapReader re-decodes independently when the file
        // is actually read below).
        let dataSectionStart: UInt64 = 124 + 16 + UInt64(compressedMap.count)
        let entries = try CHDV5MapReader.decode(
            compressed: compressedMap, hunkCount: 3, hunkBytes: hunkBytes, unitBytes: 1,
            firstOffset: dataSectionStart, lengthBits: lengthBits, selfBits: selfBits, parentBits: 0
        )
        let mapCRC = CHDCRC16.compute(rawMapBytesForAssembly(entries))

        // --- Assemble the full file ---
        var file = [UInt8]()
        // 124-byte v5 header.
        file.append(contentsOf: [UInt8]("MComprHD".utf8)) // offset 0
        file.append(contentsOf: bigEndian(UInt64(124), count: 4)) // offset 8: header length
        file.append(contentsOf: bigEndian(5, count: 4)) // offset 12: version
        // offset 16: 4 compressor tags — slot 0 declares "zlib" (this
        // synthetic file's hunk1 uses compressionType0, which now resolves
        // through the header's own tag rather than being hardcoded to zlib).
        file.append(contentsOf: [UInt8]("zlib".utf8))
        file.append(contentsOf: [UInt8](repeating: 0, count: 12))
        file.append(contentsOf: bigEndian(UInt64(hunkBytes) * 3, count: 8)) // offset 32: logicalbytes
        file.append(contentsOf: bigEndian(124, count: 8)) // offset 40: mapoffset (right after header)
        file.append(contentsOf: bigEndian(0, count: 8)) // offset 48: metaoffset
        file.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 4)) // offset 56: hunkbytes
        file.append(contentsOf: bigEndian(1, count: 4)) // offset 60: unitbytes
        file.append(contentsOf: [UInt8](repeating: 0, count: 20)) // offset 64: rawsha1
        file.append(contentsOf: [UInt8](repeating: 0, count: 20)) // offset 84: sha1
        file.append(contentsOf: [UInt8](repeating: 0, count: 20)) // offset 104: parentsha1
        #expect(file.count == 124)

        // 16-byte map header.
        file.append(contentsOf: bigEndian(UInt64(compressedMap.count), count: 4)) // mapbytes
        file.append(contentsOf: bigEndian(dataSectionStart, count: 6)) // firstoffs
        file.append(contentsOf: bigEndian(UInt64(mapCRC), count: 2)) // mapcrc
        file.append(UInt8(lengthBits))
        file.append(UInt8(selfBits))
        file.append(UInt8(0)) // parentbits
        file.append(0) // pad to 16 bytes total

        // Compressed map.
        file.append(contentsOf: compressedMap)
        #expect(UInt64(file.count) == dataSectionStart)

        // Hunk data section: hunk0 (NONE, raw) then hunk1 (type0, compressed) — hunk2 is SELF, no bytes of its own.
        file.append(contentsOf: hunk0Plain)
        file.append(contentsOf: hunk1Compressed)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-\(UUID().uuidString).chd")
        try Data(file).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let reader = try CHDHunkReader(contentsOf: tempURL)
        #expect(try reader.readHunk(0) == hunk0Plain)
        #expect(String(decoding: try reader.readHunk(1), as: UTF8.self) == hunk1Plain)
        #expect(try reader.readHunk(2) == hunk0Plain) // SELF -> hunk 0
    }

    /// `COMPRESSION_PARENT` was implemented but had zero test coverage at
    /// all (not even synthetic) — real gap found live by jensyleo
    /// (2026-08-05, "el punto 3" of a research follow-up), confirmed by an
    /// investigation agent: the only existing PARENT-adjacent test was
    /// `CHDV5MapReaderTests`' own hand-built PARENT-type map fixture, which
    /// only exercises the *map-decoding* pointer arithmetic, never a real
    /// child-reads-from-parent hunk flow through `CHDHunkReader` itself.
    /// This builds two complete, byte-accurate synthetic CHD v5 files (a
    /// "parent" with one real `NONE` hunk, and a "child" whose only hunk is
    /// `COMPRESSION_PARENT`, `unitBytes == hunkBytes` on both so the parent
    /// hunk index resolves to exactly hunk 0) and confirms the child's own
    /// `CHDHunkReader`, given the parent's reader via `parent:`, correctly
    /// returns the parent's hunk content — the one flow no test exercised
    /// before this.
    @Test("COMPRESSION_PARENT resolves against a real parent CHDHunkReader end to end")
    func readsParentHunkThroughRealParentReader() throws {
        let parentPlainTemplate = "PARENT-HUNK-CONTENT-LIVES-HERE-"
        let hunkBytes = UInt32(64)
        var parentPlain = [UInt8](parentPlainTemplate.utf8)
        while parentPlain.count < Int(hunkBytes) { parentPlain.append(0x2a) }
        parentPlain = Array(parentPlain.prefix(Int(hunkBytes)))

        // --- Parent file: 1 hunk, COMPRESSION_NONE ---
        var parentPacker = BitPacker()
        appendUniformTreeImport(&parentPacker)
        parentPacker.append(4, bits: 4) // hunk0: COMPRESSION_NONE
        parentPacker.append(0x0000, bits: 16) // hunk0 NONE: 16-bit crc
        let parentCompressedMap = parentPacker.result

        let parentDataStart: UInt64 = 124 + 16 + UInt64(parentCompressedMap.count)
        let parentEntries = try CHDV5MapReader.decode(
            compressed: parentCompressedMap, hunkCount: 1, hunkBytes: hunkBytes, unitBytes: hunkBytes,
            firstOffset: parentDataStart, lengthBits: 32, selfBits: 8, parentBits: 0
        )
        let parentMapCRC = CHDCRC16.compute(rawMapBytesForAssembly(parentEntries))

        var parentFile = [UInt8]()
        parentFile.append(contentsOf: [UInt8]("MComprHD".utf8))
        parentFile.append(contentsOf: bigEndian(124, count: 4))
        parentFile.append(contentsOf: bigEndian(5, count: 4))
        parentFile.append(contentsOf: [UInt8]("none".utf8))
        parentFile.append(contentsOf: [UInt8](repeating: 0, count: 12))
        parentFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 8)) // logicalbytes (1 hunk)
        parentFile.append(contentsOf: bigEndian(124, count: 8)) // mapoffset
        parentFile.append(contentsOf: bigEndian(0, count: 8)) // metaoffset
        parentFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 4)) // hunkbytes
        parentFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 4)) // unitbytes == hunkbytes
        parentFile.append(contentsOf: [UInt8](repeating: 0, count: 20)) // rawsha1
        parentFile.append(contentsOf: [UInt8](repeating: 0, count: 20)) // sha1
        parentFile.append(contentsOf: [UInt8](repeating: 0, count: 20)) // parentsha1 (none)
        #expect(parentFile.count == 124)
        parentFile.append(contentsOf: bigEndian(UInt64(parentCompressedMap.count), count: 4))
        parentFile.append(contentsOf: bigEndian(parentDataStart, count: 6))
        parentFile.append(contentsOf: bigEndian(UInt64(parentMapCRC), count: 2))
        parentFile.append(32) // lengthbits (unused, no tagged-slot hunks)
        parentFile.append(8) // selfbits (unused)
        parentFile.append(0) // parentbits (unused, this file has no PARENT hunks itself)
        parentFile.append(0)
        parentFile.append(contentsOf: parentCompressedMap)
        #expect(UInt64(parentFile.count) == parentDataStart)
        parentFile.append(contentsOf: parentPlain)

        let parentURL = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-parent-\(UUID().uuidString).chd")
        try Data(parentFile).write(to: parentURL)
        defer { try? FileManager.default.removeItem(at: parentURL) }
        let parentReader = try CHDHunkReader(contentsOf: parentURL)
        #expect(try parentReader.readHunk(0) == parentPlain) // sanity: parent reads back correctly on its own

        // --- Child file: 1 hunk, COMPRESSION_PARENT -> parent hunk 0 ---
        let parentBits = 8
        var childPacker = BitPacker()
        appendUniformTreeImport(&childPacker)
        childPacker.append(6, bits: 4) // hunk0: COMPRESSION_PARENT (raw type 6, not a pseudo-fallthrough)
        childPacker.append(0, bits: parentBits) // offset value 0 -> parent hunk index 0 (unitBytes == parent.hunkBytes)
        let childCompressedMap = childPacker.result

        let childDataStart: UInt64 = 124 + 16 + UInt64(childCompressedMap.count)
        let childEntries = try CHDV5MapReader.decode(
            compressed: childCompressedMap, hunkCount: 1, hunkBytes: hunkBytes, unitBytes: hunkBytes,
            firstOffset: childDataStart, lengthBits: 32, selfBits: 8, parentBits: parentBits
        )
        let childMapCRC = CHDCRC16.compute(rawMapBytesForAssembly(childEntries))

        var childFile = [UInt8]()
        childFile.append(contentsOf: [UInt8]("MComprHD".utf8))
        childFile.append(contentsOf: bigEndian(124, count: 4))
        childFile.append(contentsOf: bigEndian(5, count: 4))
        childFile.append(contentsOf: [UInt8]("none".utf8))
        childFile.append(contentsOf: [UInt8](repeating: 0, count: 12))
        childFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 8)) // logicalbytes (1 hunk)
        childFile.append(contentsOf: bigEndian(124, count: 8)) // mapoffset
        childFile.append(contentsOf: bigEndian(0, count: 8)) // metaoffset
        childFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 4)) // hunkbytes
        childFile.append(contentsOf: bigEndian(UInt64(hunkBytes), count: 4)) // unitbytes == hunkbytes
        childFile.append(contentsOf: [UInt8](repeating: 0, count: 20)) // rawsha1
        childFile.append(contentsOf: [UInt8](repeating: 0, count: 20)) // sha1
        // parentsha1: a non-zero placeholder — real chdman would put the
        // real parent's own sha1 here, but `CHDHunkReader` never cross-checks
        // this field against the `parent:` reader it's handed, so any
        // non-zero value exercises the same code path.
        childFile.append(contentsOf: [UInt8](repeating: 0xab, count: 20))
        #expect(childFile.count == 124)
        childFile.append(contentsOf: bigEndian(UInt64(childCompressedMap.count), count: 4))
        childFile.append(contentsOf: bigEndian(childDataStart, count: 6))
        childFile.append(contentsOf: bigEndian(UInt64(childMapCRC), count: 2))
        childFile.append(32) // lengthbits
        childFile.append(8) // selfbits
        childFile.append(UInt8(parentBits))
        childFile.append(0)
        childFile.append(contentsOf: childCompressedMap)
        #expect(UInt64(childFile.count) == childDataStart)
        // No data-section bytes of its own — the PARENT hunk has nothing to store.

        let childURL = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-child-\(UUID().uuidString).chd")
        try Data(childFile).write(to: childURL)
        defer { try? FileManager.default.removeItem(at: childURL) }

        let childReader = try CHDHunkReader(contentsOf: childURL, parent: parentReader)
        #expect(try childReader.readHunk(0) == parentPlain)
    }

    private func rawMapBytesForAssembly(_ entries: [CHDMapEntry]) -> [UInt8] {
        var bytes = [UInt8]()
        for entry in entries {
            bytes.append(entry.compressionType)
            bytes.append(contentsOf: bigEndian(UInt64(entry.length), count: 3))
            bytes.append(contentsOf: bigEndian(entry.offset, count: 6))
            bytes.append(contentsOf: bigEndian(UInt64(entry.crc16), count: 2))
        }
        return bytes
    }
}
