// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("CHDCRC16")
struct CHDCRC16Tests {
    @Test("matches the well-known CRC-16/CCITT-FALSE check value for \"123456789\"")
    func matchesStandardCheckValue() {
        // Confirms MAME's crc16_creator (init 0xffff, poly 0x1021, no
        // reflect, no output xor) is the standard CRC-16/CCITT-FALSE
        // variant — 0x29b1 is that variant's own published check value for
        // the ASCII string "123456789", the same convention CRC32/MD5/SHA1
        // implementations are usually cross-checked against.
        #expect(CHDCRC16.compute([UInt8]("123456789".utf8)) == 0x29b1)
    }

    @Test("an empty input returns the initial value unchanged")
    func emptyInputReturnsInitialValue() {
        #expect(CHDCRC16.compute([]) == 0xffff)
    }
}
