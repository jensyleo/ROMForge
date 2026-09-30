// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("INESHeaderDecoder")
struct INESHeaderDecoderTests {
    @Test("decodes a real header from the No-Intro NES DAT (2026-09-29) — '10-Yard Fight (USA, Europe)'")
    func decodesRealHeaderFromDAT() throws {
        let info = try #require(INESHeaderDecoder.decode(hexString: "4E 45 53 1A 02 01 00 08 00 00 00 00 02 00 00 01"))
        #expect(info.prgSizeKB == 32)
        #expect(info.chrSizeKB == 8)
        #expect(info.mapper == 0)
        #expect(info.mirroring == "Horizontal")
        #expect(info.hasBattery == false)
        #expect(info.tvSystem == "NTSC")
    }

    @Test("decodes mapper number split across both nibbles, and a battery-backed, horizontally-mirrored cartridge")
    func decodesMapperNibblesAndBattery() throws {
        // Mapper 4 (MMC3, a real, common NES mapper): low nibble in byte 6
        // bits 4-7 (0x40 -> 4), high nibble in byte 7 bits 4-7 (0x00 -> 0),
        // battery bit (0x02) set, mirroring bit (0x01) clear -> Horizontal.
        let info = try #require(INESHeaderDecoder.decode(hexString: "4E 45 53 1A 10 08 42 00 00 00 00 00 00 00 00 00"))
        #expect(info.mapper == 4)
        #expect(info.mirroring == "Horizontal")
        #expect(info.hasBattery == true)
        #expect(info.prgSizeKB == 256)
        #expect(info.chrSizeKB == 64)
    }

    @Test("four-screen mirroring bit overrides the plain horizontal/vertical bit")
    func fourScreenMirroringTakesPrecedence() throws {
        let info = try #require(INESHeaderDecoder.decode(hexString: "4E 45 53 1A 01 01 09 00 00 00 00 00 00 00 00 00"))
        #expect(info.mirroring == "Four-screen")
    }

    @Test("returns nil for anything that isn't a well-formed 16-byte iNES header")
    func returnsNilForMalformedInput() {
        #expect(INESHeaderDecoder.decode(hexString: "") == nil)
        #expect(INESHeaderDecoder.decode(hexString: "not hex at all") == nil)
        // Too short — no byte 6/7 to read flags from.
        #expect(INESHeaderDecoder.decode(hexString: "4E 45 53 1A 01 01") == nil)
        // Right length, wrong magic.
        #expect(INESHeaderDecoder.decode(hexString: "00 00 00 00 01 01 00 00 00 00 00 00 00 00 00 00") == nil)
    }
}
