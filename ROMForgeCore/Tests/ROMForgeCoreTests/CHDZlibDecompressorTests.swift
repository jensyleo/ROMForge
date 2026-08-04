// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("CHDZlibDecompressor")
struct CHDZlibDecompressorTests {
    @Test("decompresses a real raw-deflate buffer produced by Python's zlib at wbits=-15")
    func decompressesRealRawDeflateBuffer() throws {
        // Generated independently via:
        //   compressor = zlib.compressobj(9, zlib.DEFLATED, -15)
        //   compressed = compressor.compress(data) + compressor.flush()
        // wbits=-15 is raw deflate (no zlib header/trailer/Adler32) — the
        // exact same configuration MAME's chd_zlib_compressor uses
        // (deflateInit2(..., -MAX_WBITS, ...)). Using a real, independently
        // produced buffer (not a round-trip against our own compressor,
        // since ROMForge has none) is what actually proves the decoder
        // reads CHD's real on-disk zlib format, not just "some" deflate.
        let expected = """
        Hello CHD hunk decompression test! This is the actual hunk content that would live inside a CHD v5 file, \
        compressed with raw deflate (no zlib header/trailer), exactly matching MAME chd_zlib_compressor deflateInit2 \
        with negative window bits.
        """
        let compressedHex = "358ec16a42410c457fe576a7200a857e80b4825dbc9d7b8933d1098d1999c973d4af77ac3cc82a9c9c932dab667c6f7f9046fb43e490cf97c2b54a363857ffc02e49451f4f0c0a3e92bed990cdd9bcefc9d1f2a8112a57865895d8d17febf50b47515e60f27244134f28d47aeda8e48c99653c540e484c91cbca0bf59b325f806fbda8779cc943123b61580f1b8414f72f7e3f4973995cbf26fef92e189fc85f0f35b1981b0ee275f904"
        let compressed = try #require(bytes(fromHex: compressedHex))

        let decompressed = try CHDZlibDecompressor.decompress(compressed, decompressedSize: expected.utf8.count)

        #expect(String(decoding: decompressed, as: UTF8.self) == expected)
    }

    @Test("throws sizeMismatch when the declared decompressed size doesn't match the actual output")
    func throwsOnSizeMismatch() throws {
        let compressedHex = "358ec16a42410c457fe576a7200a857e80b4825dbc9d7b8933d1098d1999c973d4af77ac3cc82a9c9c932dab667c6f7f9046fb43e490cf97c2b54a363857ffc02e49451f4f0c0a3e92bed990cdd9bcefc9d1f2a8112a57865895d8d17febf50b47515e60f27244134f28d47aeda8e48c99653c540e484c91cbca0bf59b325f806fbda8779cc943123b61580f1b8414f72f7e3f4973995cbf26fef92e189fc85f0f35b1981b0ee275f904"
        let compressed = try #require(bytes(fromHex: compressedHex))

        #expect(throws: (any Error).self) {
            _ = try CHDZlibDecompressor.decompress(compressed, decompressedSize: 10)
        }
    }

    private func bytes(fromHex hex: String) -> [UInt8]? {
        var result: [UInt8] = []
        result.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }
}
