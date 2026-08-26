// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

/// Hand-builds a real bitstream matching MAME's own `import_tree_huffman`
/// wire format bit-for-bit (traced by hand against the verbatim C++ source
/// quoted in `CHDHuffmanTreeDecoder`'s own doc comment), rather than
/// generating it by running our own decompressor's logic backwards — the
/// same "independently constructed, not self-referential" standard already
/// applied to `CHDZlibDecompressorTests`/`CHDLZMADecompressorTests`.
///
/// Chooses a *uniform* 256-symbol main tree (every symbol coded at exactly
/// 8 bits — the same "uniform tree" trick `CHDV5MapReaderTests`/
/// `CHDHunkReaderTests` already use for their own Huffman fixtures) so the
/// canonical-code assignment is easy to verify by hand: symbol `i`'s code
/// is simply `i` itself, 8 bits — meaning the data section of the encoded
/// stream is just the plain bytes, MSB-first, once the tree header is past.
@Suite("CHDHuffmanDecompressor")
struct CHDHuffmanDecompressorTests {
    private struct BitPacker {
        private(set) var bytes: [UInt8] = [0]
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
    }

    @Test("decodes a uniform 256-symbol tree (every code 8 bits) built by hand per MAME's import_tree_huffman wire format")
    func decodesUniformTreeFromHandBuiltStream() throws {
        var packer = BitPacker()

        // --- Small tree (24 codes, 6 max bits): only index 0 (RLE escape)
        // and index 9 (value 9 -> main numBits = 9-1 = 8) are used, both at
        // 1 bit. Traced by hand against `import_tree_huffman`'s literal
        // read sequence:
        //   node0.numbits = read(3)            -> 1
        //   start = read(3) + 1                -> 7+1=8 (indices 1..7 auto-zero)
        //   index 8:  count = read(3)           -> 0  => numbits[8]=0
        //   index 9:  count = read(3)           -> 1  => numbits[9]=1
        //   index 10: count = read(3)           -> 7  => numbits[10]=0, count now ==7
        //   indices 11..23: auto-zero via count==7, no further bits read
        packer.append(1, bits: 3) // small.node0.numbits = 1
        packer.append(7, bits: 3) // start = 8
        packer.append(0, bits: 3) // index 8 -> numbits 0
        packer.append(1, bits: 3) // index 9 -> numbits 1
        packer.append(7, bits: 3) // index 10 -> numbits 0, count latches at 7

        // --- Main tree (256 codes, 16 max bits) lengths, decoded via the
        // small tree just built:
        //   decode_one() -> 9 (small tree's 1-bit code for index 9)
        //     => main[0].numbits = last = 9-1 = 8; curcode=1
        //   decode_one() -> 0 (small tree's 1-bit code for index 0, RLE escape)
        //     => count = read(3)+2 = 7+2 = 9; since count==9, count += read(8) = 246
        //     => count = 255; fills main[1..255].numbits = last = 8
        //   curcode reaches 256 -> loop ends, every one of the 256 symbols is 8 bits.
        // Small tree codes (both 1 bit, canonical order by ascending index):
        // index 0 -> "0", index 9 -> "1".
        packer.append(1, bits: 1) // decode "1" -> small-tree value 9
        packer.append(0, bits: 1) // decode "0" -> small-tree value 0 (RLE escape)
        packer.append(7, bits: 3) // count base: read(3)=7 -> count=9
        packer.append(246, bits: 8) // extended count: read(8)=246 -> count=9+246=255

        // --- Data: with every one of the 256 main-tree symbols coded at a
        // uniform 8 bits, canonical assignment makes symbol i's code simply
        // `i` itself (ascending order, same reasoning already verified for
        // `CHDV5MapReaderTests`' own uniform-tree case) — so the data
        // section is just the plain output bytes, MSB-first.
        let expected: [UInt8] = [0x00, 0x2A, 0xFF, 0x07, 0x80, 0x01]
        for byte in expected {
            packer.append(Int(byte), bits: 8)
        }

        let decoded = try CHDHuffmanDecompressor.decompress(packer.bytes, decompressedSize: expected.count)
        #expect(decoded == expected)
    }
}
