// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("GenesisSMDConverter")
struct GenesisSMDConverterTests {
    private let blockSize = 16384
    private let headerSize = 512

    /// Builds a synthetic one-block .smd file: a 512-byte header, then a
    /// 16KB block whose first half is all 0x11 and second half all 0x22 —
    /// deinterleaving should alternate 0x22/0x11 for the whole block.
    private func oneBlockSMD() -> (smd: Data, expectedDeinterleaved: Data) {
        var smd = Data(repeating: 0, count: headerSize)
        let half = blockSize / 2
        smd.append(Data(repeating: 0x11, count: half))
        smd.append(Data(repeating: 0x22, count: half))

        var expected = Data(capacity: blockSize)
        for _ in 0..<half {
            expected.append(0x22)
            expected.append(0x11)
        }
        return (smd, expected)
    }

    @Test("recognizes a valid .smd size: header plus whole 16KB blocks")
    func recognizesValidSize() {
        #expect(GenesisSMDConverter.isSMDInterleaved(fileSize: Int64(headerSize + blockSize)))
        #expect(GenesisSMDConverter.isSMDInterleaved(fileSize: Int64(headerSize + blockSize * 3)))
    }

    @Test("rejects a size that isn't header + whole blocks")
    func rejectsInvalidSize() {
        #expect(!GenesisSMDConverter.isSMDInterleaved(fileSize: Int64(headerSize + blockSize - 1)))
        #expect(!GenesisSMDConverter.isSMDInterleaved(fileSize: Int64(headerSize)))
    }

    @Test("deinterleaves a single block: alternates second-half then first-half bytes")
    func deinterleavesOneBlock() throws {
        let (smd, expected) = oneBlockSMD()
        let result = try #require(GenesisSMDConverter.deinterleave(smd))
        #expect(result == expected)
        #expect(result.count == blockSize, "the 512-byte header is stripped, block content size is unchanged")
    }

    @Test("returns nil for data too small or the wrong size to be a valid .smd")
    func returnsNilForInvalidData() {
        #expect(GenesisSMDConverter.deinterleave(Data(repeating: 0, count: headerSize)) == nil)
        #expect(GenesisSMDConverter.deinterleave(Data(repeating: 0, count: headerSize + blockSize - 1)) == nil)
    }
}
