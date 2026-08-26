// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A big-endian, MSB-first bit-level reader — a faithful Swift port of
/// MAME's own `bitstream_in` (`src/lib/util/bitstream.h`), which
/// `chd_file::decompress_v5_map()` uses to read both the Huffman-coded
/// compression-type stream and the raw length/offset/CRC fields that follow
/// it. CHD's own map format is built directly on this exact bit-packing
/// convention, so reading it correctly requires reproducing this algorithm
/// exactly, not just "a" bit reader.
struct CHDBitReader {
    private let data: [UInt8]
    private var buffer: UInt32 = 0
    private var bitsAvailable: Int = 0
    private var byteOffset: Int = 0
    private var bitOffsetInByte: Int = 0

    init(_ data: [UInt8]) {
        self.data = data
    }

    /// Fetches `numBits` (0...32) without advancing the read position.
    mutating func peek(_ numBits: Int) -> UInt32 {
        guard numBits > 0 else { return 0 }
        if numBits > bitsAvailable {
            while bitsAvailable < 32 {
                var newBits: UInt32 = 0
                if byteOffset < data.count {
                    newBits = (UInt32(data[byteOffset]) << bitOffsetInByte) & 0xff
                }
                if bitsAvailable + 8 > 32 {
                    bitOffsetInByte = 32 - bitsAvailable
                    newBits >>= (8 - bitOffsetInByte)
                    buffer |= newBits
                    bitsAvailable += bitOffsetInByte
                } else {
                    buffer |= newBits << (24 - bitsAvailable)
                    bitsAvailable += 8 - bitOffsetInByte
                    bitOffsetInByte = 0
                    byteOffset += 1
                }
            }
        }
        return buffer >> (32 - numBits)
    }

    /// Advances the read position by `numBits` without re-fetching.
    mutating func remove(_ numBits: Int) {
        buffer <<= numBits
        bitsAvailable -= numBits
    }

    /// Fetches and consumes `numBits`.
    mutating func read(_ numBits: Int) -> UInt32 {
        let result = peek(numBits)
        remove(numBits)
        return result
    }
}
