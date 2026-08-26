// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Streaming CRC32 (the standard zlib/ISO-3309 variant used by DAT tools).
public enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1 != 0) ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    /// The running state to feed successive chunks into via `update(_:with:)`.
    public static let initial: UInt32 = 0xFFFF_FFFF

    public static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        var c = crc
        for byte in data {
            c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c
    }

    /// Converts the running state into the final published CRC32 value.
    public static func finalize(_ crc: UInt32) -> UInt32 {
        crc ^ 0xFFFF_FFFF
    }

    public static func checksum(of data: Data) -> UInt32 {
        finalize(update(initial, with: data))
    }
}
