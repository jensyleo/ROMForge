// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import zlib

/// Streaming CRC32 (the standard zlib/ISO-3309 variant used by DAT tools).
public enum CRC32 {
    /// The running state to feed successive chunks into via `update(_:with:)`.
    public static let initial: UInt32 = 0xFFFF_FFFF

    /// Uses zlib's `crc32` (hardware-accelerated on Apple Silicon, ~100x the
    /// old byte-at-a-time table loop — multi-GB console images were
    /// dominated by this). zlib works on the *finalized* form of the
    /// checksum, while this type's running state is the pre-finalize one,
    /// hence the complement on the way in and out.
    public static func update(_ crc: UInt32, with data: Data) -> UInt32 {
        data.withUnsafeBytes { raw -> UInt32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress, !raw.isEmpty else { return crc }
            var state = ~crc
            var offset = 0
            // zlib's length parameter is a 32-bit `uInt`.
            while offset < raw.count {
                let step = min(raw.count - offset, Int(UInt32.max) / 2)
                state = UInt32(truncatingIfNeeded: zlib.crc32(UInt(state), base + offset, uInt(step)))
                offset += step
            }
            return ~state
        }
    }

    /// Converts the running state into the final published CRC32 value.
    public static func finalize(_ crc: UInt32) -> UInt32 {
        crc ^ 0xFFFF_FFFF
    }

    public static func checksum(of data: Data) -> UInt32 {
        finalize(update(initial, with: data))
    }
}
