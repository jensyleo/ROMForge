// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Decompresses a CHD hunk compressed with the plain (non-CD) `huff` codec
/// (`chd_huffman_decompressor`, `src/lib/util/chdcodec.cpp`) — MAME's own
/// `huffman_8bit_decoder` (`huffman_decoder<256, 16>`, `src/lib/util/huffman.h`).
/// Real gap found live by jensyleo (2026-08-05, researching what's still
/// genuinely unimplemented after LZMA/CD-composite turned out to already be
/// done): the plain `huff` tag was one of two hunk-body codecs
/// (`huff`/`flac`) with no Swift port at all.
///
/// `huffman_8bit_decoder::decode()` (verbatim from MAME's own source):
/// ```cpp
/// bitstream_in bitbuf(source, slength);
/// huffman_error err = import_tree_huffman(bitbuf);
/// if (err != HUFFERR_NONE) return err;
/// for (uint32_t cur = 0; cur < dlength; cur++)
///     dest[cur] = decode_one(bitbuf);
/// ```
/// — build the tree from `import_tree_huffman` (see `CHDHuffmanTreeDecoder`'s
/// own doc comment for why this, not the map's simpler `import_tree_rle`, is
/// the format this codec actually uses), then decode exactly
/// `decompressedSize` symbols, each one already a raw output byte (0...255,
/// since this instantiation's `numCodes` is 256).
public enum CHDHuffmanDecompressor {
    public static func decompress(_ compressed: [UInt8], decompressedSize: Int) throws -> [UInt8] {
        var bits = CHDBitReader(compressed)
        var tree = CHDHuffmanTreeDecoder(numCodes: 256, maxBits: 16)
        try tree.importTreeHuffman(&bits)

        var output = [UInt8](repeating: 0, count: decompressedSize)
        for i in 0..<decompressedSize {
            output[i] = UInt8(tree.decodeOne(&bits))
        }
        return output
    }
}
