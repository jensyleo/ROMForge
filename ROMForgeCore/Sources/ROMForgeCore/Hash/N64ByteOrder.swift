// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Nintendo 64 dumps come in three byte orders with the same content:
/// big-endian `.z64` (what No-Intro's default DAT hashes), byte-swapped
/// `.v64` and little-endian `.n64`. The first four bytes of every N64 ROM are
/// the same known value, so the order can be read from the file itself —
/// never guessed from its extension, which is often wrong.
public enum N64ByteOrder: Equatable, Sendable {
    case bigEndian      // 80 37 12 40  (.z64)
    case byteSwapped    // 37 80 40 12  (.v64)
    case littleEndian   // 40 12 37 80  (.n64)

    public static func detect(_ head: Data) -> N64ByteOrder? {
        guard head.count >= 4 else { return nil }
        let b = Array(head.prefix(4))
        switch (b[0], b[1], b[2], b[3]) {
        case (0x80, 0x37, 0x12, 0x40): return .bigEndian
        case (0x37, 0x80, 0x40, 0x12): return .byteSwapped
        case (0x40, 0x12, 0x37, 0x80): return .littleEndian
        default: return nil
        }
    }

    /// `data` rewritten in big-endian (`.z64`) order. `data.count` must be a
    /// multiple of 4 (every real N64 ROM is); otherwise `nil`.
    public static func toBigEndian(_ data: Data, from order: N64ByteOrder) -> Data? {
        guard data.count % 4 == 0 else { return nil }
        if order == .bigEndian { return data }
        var bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            switch order {
            case .byteSwapped:
                bytes.swapAt(i, i + 1)
                bytes.swapAt(i + 2, i + 3)
            case .littleEndian:
                bytes.swapAt(i, i + 3)
                bytes.swapAt(i + 1, i + 2)
            case .bigEndian:
                break
            }
            i += 4
        }
        return Data(bytes)
    }
}
