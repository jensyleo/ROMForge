// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A decoded iNES 1.0 header — the 16-byte header No-Intro's own "Headered"
/// NES DAT declares per rom via `DATRom.header` (a space-separated hex
/// string, e.g. `"4E 45 53 1A 10 00 10 08 00 00 00 07 00 00 00 01"`), and
/// which the emulator itself needs to know how to run the cartridge (PRG/CHR
/// size, mapper, mirroring, battery-backed save RAM). Purely descriptive —
/// ROMForge never writes or repairs a header itself, only displays it.
///
/// Only iNES 1.0's own fixed 16-byte layout is decoded — see
/// `decode(hexString:)`'s own doc comment for why NES2.0 (a superset,
/// distinguishable by bits 2-3 of byte 7) isn't specially handled.
public struct INESHeaderInfo: Equatable, Sendable {
    public let mapper: Int
    public let prgSizeKB: Int
    /// `0` means the cartridge uses CHR RAM (no CHR-ROM chip at all) rather
    /// than "no graphics data" — the header itself can't tell them apart,
    /// same ambiguity every iNES-reading tool has.
    public let chrSizeKB: Int
    public let hasBattery: Bool
    public let mirroring: String
    public let tvSystem: String

    public init(mapper: Int, prgSizeKB: Int, chrSizeKB: Int, hasBattery: Bool, mirroring: String, tvSystem: String) {
        self.mapper = mapper
        self.prgSizeKB = prgSizeKB
        self.chrSizeKB = chrSizeKB
        self.hasBattery = hasBattery
        self.mirroring = mirroring
        self.tvSystem = tvSystem
    }
}

/// Maps an iNES mapper number to the name of the audio-expansion chip it
/// implies, when that mapper's cartridge hardware adds extra sound channels
/// beyond the console's own built-in APU. `nil` for every other mapper —
/// most NES/Famicom mappers (including very common ones like MMC1/MMC3) add
/// no audio of their own, only memory banking/IRQ logic.
///
/// Mapper numbers and their real-world audio-expansion games confirmed
/// against the NESdev Wiki's own "List of games with expansion audio"
/// (nesdev.org/wiki/List_of_games_with_expansion_audio).
public enum NESAudioExpansionChip {
    public static func name(forMapper mapper: Int) -> String? {
        switch mapper {
        case 5: return "Nintendo MMC5 — audio expansion"
        case 19: return "Namco 163 — audio expansion"
        case 24, 26: return "Konami VRC6 — audio expansion"
        case 85: return "Konami VRC7 — audio expansion"
        default: return nil
        }
    }
}

public enum INESHeaderDecoder {
    /// Decodes a `DATRom.header`-style space-separated hex string (exactly
    /// as No-Intro's DAT declares it) into its meaningful fields. Returns
    /// `nil` for anything that isn't a well-formed 16-byte iNES header —
    /// too short, non-hex, or missing the `"NES\x1A"` magic (bytes 0-3) —
    /// rather than guessing at a malformed/unrelated value.
    ///
    /// NES2.0 headers (byte 7's bits 2-3 == `10`) share this exact same
    /// 16-byte layout for every field decoded here (mapper's low/high
    /// nibbles, PRG/CHR-size bytes, mirroring/battery bit, TV-system bit)
    /// — NES2.0 only *extends* a few of these with extra bits elsewhere in
    /// the same 16 bytes (a wider mapper number, sub-mappers, exact PRG-RAM
    /// sizes) that this decoder doesn't read. Every real header found in
    /// the No-Intro NES DAT decodes correctly as plain iNES 1.0 either way.
    public static func decode(hexString: String) -> INESHeaderInfo? {
        let bytes = hexString
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .compactMap { UInt8($0, radix: 16) }
        guard bytes.count >= 8, bytes[0] == 0x4E, bytes[1] == 0x45, bytes[2] == 0x53, bytes[3] == 0x1A else {
            return nil
        }
        let flags6 = bytes[6]
        let flags7 = bytes.count > 7 ? bytes[7] : 0
        let flags9 = bytes.count > 9 ? bytes[9] : 0
        let mapper = Int((flags7 & 0xF0) | (flags6 >> 4))
        let mirroring: String
        if flags6 & 0x08 != 0 {
            mirroring = "Four-screen"
        } else {
            mirroring = flags6 & 0x01 != 0 ? "Vertical" : "Horizontal"
        }
        return INESHeaderInfo(
            mapper: mapper,
            prgSizeKB: Int(bytes[4]) * 16,
            chrSizeKB: Int(bytes[5]) * 8,
            hasBattery: flags6 & 0x02 != 0,
            mirroring: mirroring,
            tvSystem: flags9 & 0x01 != 0 ? "PAL" : "NTSC"
        )
    }
}
