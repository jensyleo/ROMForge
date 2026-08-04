// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CZlib
import Foundation
import Testing
@testable import ROMForgeCore

@Suite("CHDCDCompositeDecompressor")
struct CHDCDCompositeDecompressorTests {
    private static func rawDeflate(_ data: [UInt8]) -> [UInt8] {
        var stream = z_stream()
        deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        defer { deflateEnd(&stream) }
        var input = data
        var output = [UInt8](repeating: 0, count: data.count * 2 + 128)
        let written: Int = input.withUnsafeMutableBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                stream.next_in = inPtr.baseAddress
                stream.avail_in = uInt(inPtr.count)
                stream.next_out = outPtr.baseAddress
                stream.avail_out = uInt(outPtr.count)
                _ = deflate(&stream, Z_FINISH)
                return outPtr.count - Int(stream.avail_out)
            }
        }
        return Array(output[0..<written])
    }

    /// Hand-assembles a 2-frame CD hunk exactly as
    /// `chd_cd_compressor::compress` would (mirrors the decompressor's own
    /// doc comment on the on-disk layout) so the round trip through
    /// `CHDCDCompositeDecompressor.decompress` can be checked against known
    /// input, without depending on any real CHD file.
    @Test("round-trips 2 frames through the zlib-base composite format, including ECC reconstruction")
    func roundTripsWithECCReconstruction() {
        let frameSize = 2448
        let maxSectorData = 2352
        let maxSubcodeData = 96
        let frames = 2

        var originalSectors: [[UInt8]] = []
        for f in 0..<frames {
            var sector = (0..<maxSectorData).map { UInt8(truncatingIfNeeded: $0 + f * 37 + 11) }
            sector[0x00f] = 1 // mode 1
            sector.replaceSubrange(0..<12, with: [0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00])
            CDSectorECC.generate(&sector)
            originalSectors.append(sector)
        }
        let originalSubcodes = (0..<frames).map { f in (0..<maxSubcodeData).map { UInt8(truncatingIfNeeded: $0 + f * 5) } }

        var originalFrames = [UInt8]()
        for f in 0..<frames {
            originalFrames.append(contentsOf: originalSectors[f])
            originalFrames.append(contentsOf: originalSubcodes[f])
        }
        #expect(originalFrames.count == frames * frameSize)

        // Strip sync+ECC (both sectors qualify, since both were freshly generated) and build the "base" buffer (all sector data, sync/ECC zeroed).
        var strippedSectors = originalSectors
        for f in 0..<frames {
            strippedSectors[f].replaceSubrange(0..<12, with: [UInt8](repeating: 0, count: 12))
            CDSectorECC.clear(&strippedSectors[f])
        }
        var baseBuffer = [UInt8]()
        for f in 0..<frames { baseBuffer.append(contentsOf: strippedSectors[f]) }
        var subcodeBuffer = [UInt8]()
        for f in 0..<frames { subcodeBuffer.append(contentsOf: originalSubcodes[f]) }

        let baseCompressed = Self.rawDeflate(baseBuffer)
        let subcodeCompressed = Self.rawDeflate(subcodeBuffer)

        let eccBytes = (frames + 7) / 8
        let complenBytes = 2
        var hunk = [UInt8](repeating: 0, count: eccBytes)
        hunk[0] = 0xff // both frames had sync/ECC stripped
        hunk.append(contentsOf: [UInt8(baseCompressed.count >> 8), UInt8(baseCompressed.count & 0xff)])
        hunk.append(contentsOf: baseCompressed)
        hunk.append(contentsOf: subcodeCompressed)
        _ = complenBytes

        let decompressed = try! CHDCDCompositeDecompressor.decompress(hunk, decompressedSize: frames * frameSize, base: .zlib)
        #expect(decompressed == originalFrames)
    }
}
