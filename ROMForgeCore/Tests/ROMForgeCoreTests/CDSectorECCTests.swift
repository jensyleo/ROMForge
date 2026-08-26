// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("CDSectorECC")
struct CDSectorECCTests {
    @Test("a sector's own generated ECC bytes verify successfully")
    func generatedECCVerifies() {
        var sector = (0..<2352).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) }
        sector[0x00f] = 1 // mode 1
        CDSectorECC.generate(&sector)
        #expect(CDSectorECC.verify(sector))
    }

    @Test("corrupting a payload byte after generating ECC makes verification fail")
    func corruptedPayloadFailsVerification() {
        var sector = (0..<2352).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) }
        sector[0x00f] = 1
        CDSectorECC.generate(&sector)
        sector[100] ^= 0xff
        #expect(!CDSectorECC.verify(sector))
    }

    @Test("clearing ECC bytes and regenerating them reproduces the exact same bytes")
    func clearThenGenerateRoundTrips() {
        var sector = (0..<2352).map { UInt8(truncatingIfNeeded: $0 * 13 + 5) }
        sector[0x00f] = 1
        CDSectorECC.generate(&sector)
        let original = sector
        CDSectorECC.clear(&sector)
        #expect(!CDSectorECC.verify(sector))
        CDSectorECC.generate(&sector)
        #expect(sector == original)
    }
}
