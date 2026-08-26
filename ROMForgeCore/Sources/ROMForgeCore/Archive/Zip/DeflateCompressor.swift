// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CZlib
import Foundation

public enum DeflateCompressorError: Error, Equatable {
    case initFailed(Int32)
    case compressionFailed(Int32)
}

/// Raw DEFLATE (no zlib header/trailer/Adler32 — `windowBits = -15`), the
/// same on-the-wire format the ZIP spec's compression method 8 uses inside
/// a `.zip` entry. Uses macOS's built-in system `libz` via the `CZlib`
/// system-library target (already added for `CHDZlibDecompressor`) — no
/// Homebrew/vendored dependency.
public enum DeflateCompressor {
    /// - Parameter level: 0-9, 9 = maximum compression (`TorrentZipWriter`
    ///   always uses 9, matching the TorrentZip spec).
    public static func compress(_ input: [UInt8], level: Int32 = 9) throws -> [UInt8] {
        var stream = z_stream()
        let initResult = deflateInit2_(
            &stream, level, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)
        )
        guard initResult == Z_OK else {
            throw DeflateCompressorError.initFailed(initResult)
        }
        defer { deflateEnd(&stream) }

        var output = [UInt8](repeating: 0, count: max(64, input.count + input.count / 1000 + 128))
        var inputCopy = input
        let compressedCount: Int = try inputCopy.withUnsafeMutableBufferPointer { inputPtr in
            try output.withUnsafeMutableBufferPointer { outputPtr -> Int in
                stream.next_in = inputPtr.baseAddress
                stream.avail_in = UInt32(inputPtr.count)
                stream.next_out = outputPtr.baseAddress
                stream.avail_out = UInt32(outputPtr.count)

                let result = deflate(&stream, Z_FINISH)
                guard result == Z_STREAM_END else {
                    throw DeflateCompressorError.compressionFailed(result)
                }
                return outputPtr.count - Int(stream.avail_out)
            }
        }

        return Array(output.prefix(compressedCount))
    }
}
