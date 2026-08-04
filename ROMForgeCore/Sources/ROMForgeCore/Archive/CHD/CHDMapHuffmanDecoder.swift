// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

public enum CHDHuffmanError: Error, Equatable {
    case invalidData
    case internalInconsistency
}

/// Ports MAME's `huffman_decoder<16, 8>` (`src/lib/util/huffman.h`/`.cpp`) —
/// the exact codec `chd_file::decompress_v5_map()` uses to compress a CHD
/// v5 file's own hunk map (16 possible compression-type symbols, at most
/// 8 bits per code). Only the two operations that reading actually needs
/// are ported: importing an RLE-encoded code-length table
/// (`import_tree_rle`) and decoding one symbol at a time (`decode_one`).
/// MAME's generic tree-from-histogram and huffman-encoded-tree paths exist
/// only for *writing* a CHD, never for reading one, so they aren't ported.
struct CHDMapHuffmanDecoder {
    static let numCodes = 16
    static let maxBits = 8

    private struct Node {
        var numBits = 0
        var bits = 0
    }

    private var nodes = [Node](repeating: Node(), count: CHDMapHuffmanDecoder.numCodes)
    private var lookup = [UInt16](repeating: 0, count: 1 << CHDMapHuffmanDecoder.maxBits)

    /// Reads a delta-RLE-encoded table of code lengths (one per symbol) and
    /// builds the canonical codes and fast-lookup table from it —
    /// faithfully ported from `huffman_context_base::import_tree_rle`.
    mutating func importTreeRLE(_ bits: inout CHDBitReader) throws {
        // `numbits` per table entry depends on maxBits: >=16 -> 5, >=8 -> 4,
        // else 3. CHD's map tree always uses maxBits=8, so this is always 4,
        // but the branching is kept to mirror the original source exactly.
        let numBitsPerEntry: Int
        if Self.maxBits >= 16 {
            numBitsPerEntry = 5
        } else if Self.maxBits >= 8 {
            numBitsPerEntry = 4
        } else {
            numBitsPerEntry = 3
        }

        var curNode = 0
        while curNode < Self.numCodes {
            var nodeBits = Int(bits.read(numBitsPerEntry))
            if nodeBits != 1 {
                nodes[curNode].numBits = nodeBits
                curNode += 1
            } else {
                // A value of 1 is an escape code: a second 1 means "the
                // length is literally 1"; anything else is a repeat count.
                nodeBits = Int(bits.read(numBitsPerEntry))
                if nodeBits == 1 {
                    nodes[curNode].numBits = nodeBits
                    curNode += 1
                } else {
                    var repCount = Int(bits.read(numBitsPerEntry)) + 3
                    while repCount > 0, curNode < Self.numCodes {
                        nodes[curNode].numBits = nodeBits
                        curNode += 1
                        repCount -= 1
                    }
                }
            }
        }
        guard curNode == Self.numCodes else { throw CHDHuffmanError.invalidData }

        try assignCanonicalCodes()
        buildLookupTable()
    }

    /// Ported from `huffman_context_base::assign_canonical_codes`.
    private mutating func assignCanonicalCodes() throws {
        var bitHisto = [Int](repeating: 0, count: 33)
        for node in nodes {
            guard node.numBits <= Self.maxBits else { throw CHDHuffmanError.internalInconsistency }
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

        for i in 0..<Self.numCodes where nodes[i].numBits > 0 {
            nodes[i].bits = bitHisto[nodes[i].numBits]
            bitHisto[nodes[i].numBits] += 1
        }
    }

    /// Ported from `huffman_context_base::build_lookup_table`.
    private mutating func buildLookupTable() {
        for i in 0..<Self.numCodes {
            let node = nodes[i]
            guard node.numBits > 0 else { continue }
            let value = UInt16((i << 5) | (node.numBits & 0x1f))
            let shift = Self.maxBits - node.numBits
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
        let peeked = bits.peek(Self.maxBits)
        let value = lookup[Int(peeked)]
        bits.remove(Int(value & 0x1f))
        return Int(value >> 5)
    }
}
