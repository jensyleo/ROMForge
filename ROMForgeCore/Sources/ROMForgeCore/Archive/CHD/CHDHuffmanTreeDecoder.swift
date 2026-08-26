// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Ports MAME's generic `huffman_decoder<NumCodes, MaxBits>`
/// (`src/lib/util/huffman.h`/`.cpp`) — parameterized so the same engine
/// serves both real instantiations CHD actually reads with: the v5 map's
/// own `huffman_decoder<16, 8>` (`CHDMapHuffmanDecoder`, a separate,
/// independently-tested file — left untouched, since it's already
/// verified working) and the plain `huff` hunk-body codec's
/// `huffman_8bit_decoder` = `huffman_decoder<256, 16>`
/// (`CHDHuffmanDecompressor`), which additionally needs a THIRD, nested
/// instantiation of this exact same engine (`huffman_decoder<24, 6>`) to
/// decode its own tree-of-tree-lengths (`importTreeHuffman`, below).
///
/// Only the read-side operations are ported (`import_tree_rle`,
/// `import_tree_huffman`, `decode_one`) — MAME's histogram-from-data and
/// huffman-encode-the-tree paths exist only for *writing* a CHD.
struct CHDHuffmanTreeDecoder {
    let numCodes: Int
    let maxBits: Int

    private struct Node {
        var numBits = 0
        var bits = 0
    }

    private var nodes: [Node]
    private var lookup: [UInt16]

    init(numCodes: Int, maxBits: Int) {
        self.numCodes = numCodes
        self.maxBits = maxBits
        self.nodes = [Node](repeating: Node(), count: numCodes)
        self.lookup = [UInt16](repeating: 0, count: 1 << maxBits)
    }

    /// Faithfully ported from `huffman_context_base::import_tree_rle` — the
    /// simpler of the two tree-import formats (a delta-RLE-encoded table of
    /// code lengths), used by the CHD v5 map's own Huffman stream. Kept
    /// here too (not just in `CHDMapHuffmanDecoder`) so this general engine
    /// is a complete, independent port on its own, even though the map
    /// reader's existing call site keeps using its own separate,
    /// already-tested copy.
    mutating func importTreeRLE(_ bits: inout CHDBitReader) throws {
        let numBitsPerEntry: Int
        if maxBits >= 16 {
            numBitsPerEntry = 5
        } else if maxBits >= 8 {
            numBitsPerEntry = 4
        } else {
            numBitsPerEntry = 3
        }

        var curNode = 0
        while curNode < numCodes {
            var nodeBits = Int(bits.read(numBitsPerEntry))
            if nodeBits != 1 {
                nodes[curNode].numBits = nodeBits
                curNode += 1
            } else {
                nodeBits = Int(bits.read(numBitsPerEntry))
                if nodeBits == 1 {
                    nodes[curNode].numBits = nodeBits
                    curNode += 1
                } else {
                    var repCount = Int(bits.read(numBitsPerEntry)) + 3
                    while repCount > 0, curNode < numCodes {
                        nodes[curNode].numBits = nodeBits
                        curNode += 1
                        repCount -= 1
                    }
                }
            }
        }
        guard curNode == numCodes else { throw CHDHuffmanError.invalidData }
        try assignCanonicalCodes()
        buildLookupTable()
    }

    /// Faithfully ported from `huffman_context_base::import_tree_huffman` —
    /// the format `chd_huffman_decompressor` (the plain, non-CD `huff`
    /// hunk-body codec) actually uses, distinct from the map's own
    /// `import_tree_rle`. Real case this closes: MAME's own source shows
    /// `huffman_8bit_decoder::decode()` calls `import_tree_huffman`, not
    /// `import_tree_rle` — a genuinely different tree-encoding this project
    /// hadn't ported before 2026-08-05.
    ///
    /// First decodes a small nested tree (`huffman_decoder<24, 6>`) that
    /// itself encodes the *code lengths* of the real, `numCodes`-sized main
    /// tree — a tree describing a tree, MAME's own space-saving trick for a
    /// large alphabet (256 codes) where a plain RLE table would cost more
    /// bits than the data it's meant to save.
    mutating func importTreeHuffman(_ bits: inout CHDBitReader) throws {
        var small = CHDHuffmanTreeDecoder(numCodes: 24, maxBits: 6)
        small.nodes[0].numBits = Int(bits.read(3))
        let start = Int(bits.read(3)) + 1
        var count = 0
        for index in 1..<24 {
            if index < start || count == 7 {
                small.nodes[index].numBits = 0
            } else {
                count = Int(bits.read(3))
                small.nodes[index].numBits = (count == 7) ? 0 : count
            }
        }
        try small.assignCanonicalCodes()
        small.buildLookupTable()

        // Maximum length of an RLE repeat count, sized to this tree's own
        // alphabet — `rlefullbits` in MAME's source.
        var temp = numCodes - 9
        var rleFullBits = 0
        while temp != 0 {
            temp >>= 1
            rleFullBits += 1
        }

        var last = 0
        var curCode = 0
        while curCode < numCodes {
            let value = small.decodeOne(&bits)
            if value != 0 {
                last = value - 1
                nodes[curCode].numBits = last
                curCode += 1
            } else {
                var repCount = Int(bits.read(3)) + 2
                if repCount == 7 + 2 {
                    repCount += Int(bits.read(rleFullBits))
                }
                while repCount != 0, curCode < numCodes {
                    nodes[curCode].numBits = last
                    curCode += 1
                    repCount -= 1
                }
            }
        }
        guard curCode == numCodes else { throw CHDHuffmanError.invalidData }
        try assignCanonicalCodes()
        buildLookupTable()
    }

    /// Ported from `huffman_context_base::assign_canonical_codes`.
    private mutating func assignCanonicalCodes() throws {
        var bitHisto = [Int](repeating: 0, count: 33)
        for node in nodes {
            guard node.numBits <= maxBits else { throw CHDHuffmanError.internalInconsistency }
            if node.numBits <= 32 {
                bitHisto[node.numBits] += 1
            }
        }

        var curStart = 0
        for codeLen in stride(from: 32, through: 1, by: -1) {
            let nextStart = (curStart + bitHisto[codeLen]) >> 1
            if codeLen != 1, nextStart * 2 != (curStart + bitHisto[codeLen]) {
                throw CHDHuffmanError.internalInconsistency
            }
            bitHisto[codeLen] = curStart
            curStart = nextStart
        }

        for i in 0..<numCodes where nodes[i].numBits > 0 {
            nodes[i].bits = bitHisto[nodes[i].numBits]
            bitHisto[nodes[i].numBits] += 1
        }
    }

    /// Ported from `huffman_context_base::build_lookup_table`.
    private mutating func buildLookupTable() {
        for i in 0..<numCodes {
            let node = nodes[i]
            guard node.numBits > 0 else { continue }
            let value = UInt16((i << 5) | (node.numBits & 0x1f))
            let shift = maxBits - node.numBits
            let start = node.bits << shift
            let end = ((node.bits + 1) << shift) - 1
            guard start <= end else { continue }
            for idx in start...end {
                lookup[idx] = value
            }
        }
    }

    /// Ported from `huffman_decoder::decode_one`.
    mutating func decodeOne(_ bits: inout CHDBitReader) -> Int {
        let peeked = bits.peek(maxBits)
        let value = lookup[Int(peeked)]
        bits.remove(Int(value & 0x1f))
        return Int(value >> 5)
    }
}
