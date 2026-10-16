// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// What a SNES ROM's own internal header says about the cartridge. Unlike
/// `INESHeaderDecoder`'s NES case (a DAT-declared 16-byte string), this lives
/// INSIDE the ROM data, so decoding always needs real ROM bytes — the first
/// `SNESHeaderDecoder.bytesNeeded` bytes are enough.
public struct SNESHeaderInfo: Equatable, Sendable, Codable {
    /// "LoROM", "HiROM", or "Other (0x…)" for a map mode this decoder does
    /// not name.
    public let mapMode: String
    /// The coprocessor on the cartridge ("Super FX (GSU)", "SA-1", "Cx4"…),
    /// or `nil` for a plain ROM (with or without RAM/battery).
    public let expansionChip: String?

    public init(mapMode: String, expansionChip: String?) {
        self.mapMode = mapMode
        self.expansionChip = expansionChip
    }
}

public enum SNESHeaderDecoder {
    /// Enough bytes to reach the HiROM header (file offset 0xFFC0, plus the
    /// 0x20 bytes it spans) with room for a 512-byte copier header.
    public static let bytesNeeded = 0x10000 + 512

    /// Decodes the header from the START of a ROM image (`prefix`).
    /// `fileSize` is the full ROM size: a size that is 512 bytes more than a
    /// multiple of 1 KB means a leading copier header, skipped here.
    ///
    /// LoROM (header at 0x7FC0) and HiROM (0xFFC0) are both tried. A
    /// location is accepted when the header's own consistency check passes
    /// (checksum + complement = 0xFFFF) and its title looks like text — this
    /// is what real cartridges use even when their map-mode byte is unusual
    /// (Contra III reports 0x53, Super Mario RPG's SA-1 map mode 0x23 at the
    /// LoROM location). A hacked/patched ROM that broke its checksum is
    /// still accepted when the map-mode byte is plausible (0x20–0x3F) and
    /// agrees with the location. Anything else returns `nil` — never a
    /// guess.
    public static func decode(prefix: Data, fileSize: Int64) -> SNESHeaderInfo? {
        let skip = (fileSize % 1024 == 512) ? 512 : 0
        var best: (score: Int, info: SNESHeaderInfo)?
        for (location, isHiROM) in [(0x7FC0, false), (0xFFC0, true)] {
            let base = skip + location
            guard prefix.count >= base + 0x20 else { continue }
            let byte = { (offset: Int) -> UInt8 in prefix[prefix.startIndex + base + offset] }
            let mapModeByte = byte(0x15)
            let complement = UInt16(byte(0x1C)) | UInt16(byte(0x1D)) << 8
            let checksum = UInt16(byte(0x1E)) | UInt16(byte(0x1F)) << 8
            let checksumOK = complement ^ checksum == 0xFFFF
            let printable = (0..<21).filter { (0x20...0x7E).contains(byte($0)) }.count
            let plausibleMapMode = mapModeByte & 0xE0 == 0x20 && (mapModeByte & 0x01 == 0x01) == isHiROM
            // Higher is better: a verified header whose map mode also
            // agrees with the location beats one that merely verifies.
            let score: Int
            switch (checksumOK && printable >= 14, plausibleMapMode) {
            case (true, true): score = 3
            case (true, false): score = 2
            case (false, true): score = 1
            case (false, false): continue
            }
            let info = SNESHeaderInfo(
                mapMode: isHiROM ? "HiROM" : "LoROM",
                expansionChip: expansionChipName(chipsetByte: byte(0x16), subtype: byte(-1) /* 0xFFBF */)
            )
            if best == nil || score > best!.score { best = (score, info) }
        }
        return best?.info
    }

    /// Chipset byte ($FFD6): the LOW nibble says whether a coprocessor is
    /// present (3–6), the HIGH nibble which family. Family `F` ("custom") is
    /// told apart by the extended-header subtype byte ($FFBF).
    private static func expansionChipName(chipsetByte: UInt8, subtype: UInt8) -> String? {
        // 0x1A is the Super FX + RAM + battery variant (e.g. Doom).
        guard (0x3...0x6).contains(chipsetByte & 0x0F) || chipsetByte == 0x1A else { return nil }
        switch chipsetByte & 0xF0 {
        case 0x00: return "DSP (DSP-1/2/3/4)"
        case 0x10: return "Super FX (GSU)"
        case 0x20: return "OBC-1"
        case 0x30: return "SA-1"
        case 0x40: return "S-DD1"
        case 0x50: return "S-RTC"
        case 0xE0: return "Other (Super Game Boy / Satellaview)"
        case 0xF0:
            switch subtype {
            case 0x00: return "SPC7110"
            case 0x01: return "ST010/ST011"
            case 0x02: return "ST018"
            case 0x10: return "Cx4"
            default: return "Custom chip"
            }
        default: return "Unknown coprocessor"
        }
    }
}
