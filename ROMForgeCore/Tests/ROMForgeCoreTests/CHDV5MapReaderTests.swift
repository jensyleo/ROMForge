// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

/// No real CHD file was available to test against in this environment (the
/// same restriction that applies to sourcing ROMs — see TESTING.md). These
/// tests instead hand-construct valid bitstreams per the exact algorithm
/// ported from MAME's `chd_file::decompress_v5_map()`, verified by manual
/// trace of `assign_canonical_codes` for the simplest non-trivial case: 16
/// symbols all sharing a 4-bit code length. That configuration is a
/// "complete" code (2^4 == 16 symbols), and tracing the real canonical-code
/// assignment algorithm by hand for it shows each symbol's 4-bit code
/// equals its own numeric value directly (node `i` gets `bits = i`) — which
/// makes hand-building a real, valid compressed bitstream tractable without
/// needing a full encoder implementation.
@Suite("CHDV5MapReader")
struct CHDV5MapReaderTests {
    /// Packs values MSB-first into a byte array — the same bit order
    /// `CHDBitReader`/MAME's `bitstream_in` expects.
    private struct BitPacker {
        private var bytes: [UInt8] = [0]
        private var bitPos = 0 // next free bit position in the last byte, MSB-first

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

    /// A uniform 16-symbol/4-bit-per-code tree import block: 16 raw
    /// 4-bit values, all equal to 4 (a value that's never 1, so no RLE
    /// escape logic is triggered on import).
    private func appendUniformTreeImport(_ packer: inout BitPacker) {
        for _ in 0..<16 {
            packer.append(4, bits: 4)
        }
    }

    @Test("decodes a map with a COMPRESSION_NONE hunk followed by a COMPRESSION_PARENT hunk")
    func decodesNoneAndParentHunks() throws {
        var packer = BitPacker()
        appendUniformTreeImport(&packer)
        // Hunk 0: symbol value 4 (COMPRESSION_NONE) — per the uniform-tree
        // trace above, symbol V's code is just V's own 4-bit value.
        packer.append(4, bits: 4)
        // Hunk 1: symbol value 6 (COMPRESSION_PARENT).
        packer.append(6, bits: 4)
        // Pass-2 data reads, in hunk order: hunk 0 (NONE) reads a 16-bit
        // CRC; hunk 1 (PARENT) reads an 8-bit offset (parentBits=8 below).
        packer.append(0x1234, bits: 16)
        packer.append(42, bits: 8)

        let entries = try CHDV5MapReader.decode(
            compressed: packer.result,
            hunkCount: 2,
            hunkBytes: 100,
            unitBytes: 1,
            firstOffset: 0,
            lengthBits: 0,
            selfBits: 0,
            parentBits: 8
        )

        #expect(entries.count == 2)
        #expect(entries[0].compressionType == CHDV5MapReader.compressionNone)
        #expect(entries[0].length == 100)
        #expect(entries[0].offset == 0)
        #expect(entries[0].crc16 == 0x1234)

        #expect(entries[1].compressionType == CHDV5MapReader.compressionParent)
        #expect(entries[1].offset == 42)
        #expect(entries[1].crc16 == 0)
    }

    @Test("verifies the decoded map against its own CRC16, and rejects a wrong one")
    func verifiesMapCRC16() throws {
        var packer = BitPacker()
        appendUniformTreeImport(&packer)
        packer.append(4, bits: 4)
        packer.append(6, bits: 4)
        packer.append(0x1234, bits: 16)
        packer.append(42, bits: 8)

        // Computed independently in Python using the same table/algorithm
        // as CHDCRC16, over the raw 12-byte-per-hunk layout these two
        // entries produce (type/length/offset/crc16, big-endian) —
        // 04 00 00 64 00 00 00 00 00 00 12 34
        // 06 00 00 00 00 00 00 00 00 2a 00 00
        let correctCRC: UInt16 = 0x068d

        // A correct expected CRC doesn't throw.
        _ = try CHDV5MapReader.decode(
            compressed: packer.result, hunkCount: 2, hunkBytes: 100, unitBytes: 1,
            firstOffset: 0, lengthBits: 0, selfBits: 0, parentBits: 8, expectedMapCRC16: correctCRC
        )

        // A wrong one does.
        #expect(throws: CHDV5MapReader.MapIntegrityError.self) {
            _ = try CHDV5MapReader.decode(
                compressed: packer.result, hunkCount: 2, hunkBytes: 100, unitBytes: 1,
                firstOffset: 0, lengthBits: 0, selfBits: 0, parentBits: 8, expectedMapCRC16: 0xdead
            )
        }
    }

    @Test("expands an RLE_SMALL repeat token across multiple hunks")
    func expandsRLESmallRepeat() throws {
        var packer = BitPacker()
        appendUniformTreeImport(&packer)
        // Hunk 0: explicit symbol 4 (COMPRESSION_NONE) — becomes lastComp.
        packer.append(4, bits: 4)
        // Hunk 1: RLE_SMALL (7) token, then an extra-count symbol of 0,
        // meaning repeatCount = 2 + 0 = 2 — covering hunks 2 and 3 too, all
        // repeating lastComp (COMPRESSION_NONE) without their own symbol.
        packer.append(7, bits: 4)
        packer.append(0, bits: 4)
        // Pass-2 reads: all 4 hunks are COMPRESSION_NONE, each reads a
        // 16-bit CRC (length is always hunkBytes for COMPRESSION_NONE).
        for crc in [0x1111, 0x2222, 0x3333, 0x4444] {
            packer.append(crc, bits: 16)
        }

        let entries = try CHDV5MapReader.decode(
            compressed: packer.result,
            hunkCount: 4,
            hunkBytes: 50,
            unitBytes: 1,
            firstOffset: 0,
            lengthBits: 0,
            selfBits: 0,
            parentBits: 0
        )

        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.compressionType == CHDV5MapReader.compressionNone && $0.length == 50 })
        #expect(entries.map(\.crc16) == [0x1111, 0x2222, 0x3333, 0x4444])
        // Offsets accumulate hunkBytes each time, starting from firstOffset.
        #expect(entries.map(\.offset) == [0, 50, 100, 150])
    }

    @Test("throws on a truncated/invalid tree-import stream")
    func throwsOnInvalidTreeImport() {
        // Too few bits to even complete the 16-entry tree import.
        let tooShort: [UInt8] = [0xFF]
        #expect(throws: (any Error).self) {
            _ = try CHDV5MapReader.decode(
                compressed: tooShort, hunkCount: 1, hunkBytes: 10, unitBytes: 1,
                firstOffset: 0, lengthBits: 0, selfBits: 0, parentBits: 0
            )
        }
    }
}
