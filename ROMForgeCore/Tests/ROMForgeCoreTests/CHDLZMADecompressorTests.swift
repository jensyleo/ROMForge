// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CLZMA
import Foundation
import Testing
@testable import ROMForgeCore

@Suite("CHDLZMADecompressor")
struct CHDLZMADecompressorTests {
    @Test("decompresses a raw LZMA1EXT stream produced by an independent encode call")
    func decompressesIndependentlyEncodedStream() throws {
        let original = Array(repeating: "Hello World! This is a test of raw LZMA1 encoding.", count: 50)
            .joined().data(using: .utf8)!
        let compressed = try Self.encodeReferenceRawLZMA1(original)
        let decoded = try CHDLZMADecompressor.decompress([UInt8](compressed), decompressedSize: original.count, dictSizeOverride: 1 << 20)
        #expect(decoded == [UInt8](original))
    }

    @Test("throws rather than silently returning garbage when the stream is corrupted")
    func corruptedStreamThrows() throws {
        let original = Data("some plain text payload for LZMA to compress".utf8)
        var compressed = [UInt8](try Self.encodeReferenceRawLZMA1(original))
        guard compressed.count > 4 else {
            Issue.record("fixture too small to corrupt meaningfully")
            return
        }
        compressed[2] ^= 0xff
        compressed[3] ^= 0xff
        #expect(throws: (any Error).self) {
            try CHDLZMADecompressor.decompress(compressed, decompressedSize: original.count, dictSizeOverride: 1 << 20)
        }
    }

    /// Encodes via liblzma's own encode-side raw API — an independent code
    /// path from `CHDLZMADecompressor`'s decode call, so this isn't just a
    /// decode-echoing-itself round trip. Matches the format
    /// `CHDLZMADecompressor`'s own doc comment says MAME's encoder
    /// produces: raw LZMA1, no end-of-payload marker, `lc=3`/`lp=0`/`pb=2`.
    private static func encodeReferenceRawLZMA1(_ data: Data) throws -> Data {
        var options = lzma_options_lzma()
        options.dict_size = 1 << 20
        options.lc = 3
        options.lp = 0
        options.pb = 2
        options.mode = LZMA_MODE_NORMAL
        options.nice_len = 64
        options.mf = LZMA_MF_BT4
        options.depth = 0
        options.ext_flags = 0 // no end-of-payload marker, matching the decoder's own assumption

        // LZMA_FILTER_LZMA1EXT / LZMA_VLI_UNKNOWN — see
        // CHDLZMADecompressor.swift's own comment: these `#define`s are
        // structure-typed literals ClangImporter can't bridge as symbols.
        let lzmaFilterLZMA1Ext: UInt64 = 0x4000000000000002
        let lzmaVLIUnknown = UInt64.max
        var output = [UInt8](repeating: 0, count: data.count + 4096)
        var outPos = 0
        var result: lzma_ret = LZMA_OK
        withUnsafeMutablePointer(to: &options) { optionsPtr in
            var filters = [
                lzma_filter(id: lzmaFilterLZMA1Ext, options: UnsafeMutableRawPointer(optionsPtr)),
                lzma_filter(id: lzmaVLIUnknown, options: nil),
            ]
            result = [UInt8](data).withUnsafeBufferPointer { inBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    lzma_raw_buffer_encode(
                        &filters, nil,
                        inBuf.baseAddress, inBuf.count,
                        outBuf.baseAddress, &outPos, outBuf.count
                    )
                }
            }
        }
        #expect(result == LZMA_OK)
        return Data(output[0..<outPos])
    }
}
