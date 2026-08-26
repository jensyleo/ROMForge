// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Converts a Genesis/Mega Drive `.smd` dump — a 512-byte header followed by
/// 16KB blocks with their first/second 8KB halves byte-interleaved — into
/// the plain, non-interleaved layout a No-Intro/Goodgen-style DAT actually
/// hashes.
///
/// Unlike `HeaderSkipRule` (which only ever skips leading bytes), `.smd`
/// needs the block content itself reordered — the exact interleave/
/// de-interleave logic here mirrors what's documented in RomCenter's own
/// signature-plugin sources (`Goodxxx/fmt/genesis.cpp` in
/// github.com/ebolefeysot/RomcenterPlugins, GPL-3.0): after the header, each
/// 16KB block is split into two 8KB halves stored back-to-back in the file;
/// de-interleaving alternates bytes from the second half then the first
/// half to reconstruct the original, sequential ROM content.
public enum GenesisSMDConverter {
    private static let headerSize = 512
    private static let blockSize = 16384

    /// True if `fileSize` matches the `.smd` convention: a 512-byte header
    /// followed by one or more complete 16KB blocks.
    public static func isSMDInterleaved(fileSize: Int64) -> Bool {
        guard fileSize > headerSize else { return false }
        return (fileSize - Int64(headerSize)) % Int64(blockSize) == 0
    }

    /// De-interleaves `data` (a full `.smd` file's bytes) into the standard
    /// non-interleaved Genesis ROM layout, header stripped — or nil if
    /// `data`'s size doesn't match the convention.
    public static func deinterleave(_ data: Data) -> Data? {
        guard data.count > headerSize else { return nil }
        let bodyCount = data.count - headerSize
        guard bodyCount > 0, bodyCount % blockSize == 0 else { return nil }

        let bytes = [UInt8](data)
        var output = [UInt8](repeating: 0, count: bodyCount)
        let half = blockSize / 2
        var blockStart = headerSize
        var outStart = 0
        while blockStart < bytes.count {
            let firstHalfStart = blockStart
            let secondHalfStart = blockStart + half
            for k in 0..<half {
                output[outStart + 2 * k] = bytes[secondHalfStart + k]
                output[outStart + 2 * k + 1] = bytes[firstHalfStart + k]
            }
            blockStart += blockSize
            outStart += blockSize
        }
        return Data(output)
    }
}
