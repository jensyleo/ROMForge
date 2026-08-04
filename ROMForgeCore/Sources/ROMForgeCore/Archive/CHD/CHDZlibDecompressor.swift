// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CZlib

public enum CHDZlibError: Error, Equatable {
    case initFailed(Int32)
    case decompressionFailed(Int32)
    case sizeMismatch(expected: Int, actual: Int)
}

/// Decompresses a CHD hunk compressed with the `zlib` codec
/// (`CHDV5MapReader.compressionType0`, when a CHD's header declares zlib as
/// that codec slot) — via system zlib (`libSystem`, always present, no
/// Homebrew/vendored dependency), using **raw DEFLATE** specifically:
/// MAME's own `chd_zlib_compressor` calls `deflateInit2(..., -MAX_WBITS,
/// ...)` — a *negative* window-bits value, which is zlib's convention for
/// "raw deflate, no zlib header/trailer/Adler32", not the ordinary
/// zlib-wrapped format `inflateInit()` alone would expect. Verified against
/// a real raw-deflate buffer produced by Python's own `zlib` module at
/// `wbits=-15` (see `CHDZlibDecompressorTests`), not just against
/// self-produced data.
public enum CHDZlibDecompressor {
    public static func decompress(_ compressed: [UInt8], decompressedSize: Int) throws -> [UInt8] {
        var stream = z_stream()
        let initResult = compressed.withUnsafeBufferPointer { _ in
            inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        }
        guard initResult == Z_OK else {
            throw CHDZlibError.initFailed(initResult)
        }
        defer { inflateEnd(&stream) }

        var input = compressed
        var output = [UInt8](repeating: 0, count: decompressedSize)
        let result: Int32 = input.withUnsafeMutableBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                stream.next_in = inPtr.baseAddress
                stream.avail_in = uInt(inPtr.count)
                stream.next_out = outPtr.baseAddress
                stream.avail_out = uInt(outPtr.count)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END else {
            throw CHDZlibError.decompressionFailed(result)
        }
        guard Int(stream.total_out) == decompressedSize else {
            throw CHDZlibError.sizeMismatch(expected: decompressedSize, actual: Int(stream.total_out))
        }
        return output
    }
}
