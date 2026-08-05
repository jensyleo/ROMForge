// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import CLZMA

public enum CHDLZMAError: Error, Equatable {
    case decompressionFailed(Int32)
    case sizeMismatch(expected: Int, actual: Int)
    /// liblzma itself couldn't be found on this Mac at all — see
    /// `HomebrewDylibLoader`'s own doc comment for why this is now a
    /// catchable error instead of the app failing to launch. `dependency`
    /// carries the exact `brew install` formula name for a caller to
    /// surface to the user.
    case libraryNotAvailable(HomebrewLibraryDependency)
}

/// The one real liblzma function this codec calls, resolved via `dlopen`/
/// `dlsym` (`HomebrewDylibLoader`) instead of a hard link dependency.
/// `lzma_options_lzma()`/`lzma_filter`/`lzma_ret` etc. below are C *type*
/// declarations ClangImporter bridges straight from the header — those
/// cost nothing at link time on their own and need no runtime resolution;
/// only an actual exported C function needs this.
private typealias LzmaRawBufferDecodeFn = @convention(c) (
    UnsafeMutablePointer<lzma_filter>?, UnsafeRawPointer?,
    UnsafePointer<UInt8>?, UnsafeMutablePointer<Int>?, Int,
    UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<Int>?, Int
) -> lzma_ret

private let lzmaDependency = HomebrewLibraryDependency.all.first { $0.formula == "xz" }!

/// Decompresses a CHD hunk (or the base/data portion of a "cdlz" CD hunk)
/// compressed with MAME's LZMA codec (`CHD_CODEC_LZMA`/`CHD_CODEC_CD_LZMA`)
/// — via Homebrew's liblzma (`CLZMA`; see Sources/CLZMA/shim.h), using a raw
/// LZMA1 stream (no .xz/.lzma container).
///
/// MAME's own decoder never stores its LZMA properties in the file — it
/// *recomputes* the exact same `lc`/`lp`/`pb`/`dictSize` the encoder would
/// have derived, purely from the hunk's own uncompressed size, then feeds
/// those into the decoder (`chd_lzma_decompressor`, `chdcodec.cpp`, fetched
/// 2026-07-30 from github.com/mamedev/mame to confirm exactly). Ported here
/// via the 7-Zip SDK's own normalization formula (`LzmaEncProps_Normalize`,
/// `3rdparty/lzma/C/LzmaEnc.c`): level is always 8, so `dictSize` starts at
/// 1<<26 (64MB), then is clamped down to `max(uncompressedSize, 4096)` since
/// that's always smaller for CHD's own hunk sizes; `lc=3`, `lp=0`, `pb=2`
/// are the unconditional LZMA defaults MAME never overrides.
///
/// Uses `LZMA_FILTER_LZMA1EXT`, not the plain `LZMA_FILTER_LZMA1` its name
/// suggests: MAME's encoder (`LzmaEnc_MemEncode(..., writeEndMark: 0, ...)`)
/// never writes an end-of-payload marker — it relies on the *caller*
/// already knowing the uncompressed size (which the CHD hunk map records).
/// Plain `LZMA_FILTER_LZMA1` unconditionally requires that marker to know
/// where the stream ends and fails with `LZMA_DATA_ERROR` without it
/// (confirmed empirically against a real CHD hunk, 2026-07-30 — every
/// `lc`/`lp`/`pb` combination failed identically under `LZMA_FILTER_LZMA1`
/// until switching to `LZMA1EXT` with the known output size). `LZMA1EXT`
/// supports telling the decoder the exact expected size via
/// `ext_size_low`/`ext_size_high` and skipping the marker requirement
/// entirely via `ext_flags = 0`.
public enum CHDLZMADecompressor {
    public static func decompress(_ compressed: [UInt8], decompressedSize: Int, dictSizeOverride: UInt32? = nil) throws -> [UInt8] {
        let rawBufferDecode: LzmaRawBufferDecodeFn
        do {
            rawBufferDecode = try HomebrewDylibLoader.loadSymbol(lzmaDependency, symbol: "lzma_raw_buffer_decode", as: LzmaRawBufferDecodeFn.self)
        } catch is HomebrewDylibLoader.LibraryNotAvailable {
            throw CHDLZMAError.libraryNotAvailable(lzmaDependency)
        }

        let dictSize = dictSizeOverride ?? max(UInt32(decompressedSize), 1 << 12)

        var options = lzma_options_lzma()
        options.dict_size = dictSize
        options.preset_dict = nil
        options.preset_dict_size = 0
        options.lc = 3
        options.lp = 0
        options.pb = 2
        options.mode = LZMA_MODE_NORMAL
        options.nice_len = 64
        options.mf = LZMA_MF_BT4
        options.depth = 0
        options.ext_flags = 0
        options.ext_size_low = UInt32(truncatingIfNeeded: decompressedSize)
        options.ext_size_high = UInt32(truncatingIfNeeded: UInt64(decompressedSize) >> 32)

        var output = [UInt8](repeating: 0, count: decompressedSize)
        var result: lzma_ret = LZMA_OK

        // LZMA_FILTER_LZMA1EXT (0x4000000000000002) and LZMA_VLI_UNKNOWN
        // (UINT64_MAX, the filter-array terminator) — both `#define`d as
        // structure-typed literals ClangImporter can't bridge as symbols,
        // so their values are inlined directly (see lzma/lzma12.h and
        // lzma/vli.h upstream).
        let lzmaFilterLZMA1Ext: UInt64 = 0x4000000000000002
        let lzmaVLIUnknown = UInt64.max
        withUnsafeMutablePointer(to: &options) { optionsPtr in
            var filters = [
                lzma_filter(id: lzmaFilterLZMA1Ext, options: UnsafeMutableRawPointer(optionsPtr)),
                lzma_filter(id: lzmaVLIUnknown, options: nil),
            ]
            var inPos = 0
            var outPos = 0
            result = compressed.withUnsafeBufferPointer { inBuf in
                output.withUnsafeMutableBufferPointer { outBuf in
                    rawBufferDecode(
                        &filters, nil,
                        inBuf.baseAddress, &inPos, inBuf.count,
                        outBuf.baseAddress, &outPos, outBuf.count
                    )
                }
            }
        }

        guard result == LZMA_OK || result == LZMA_STREAM_END || result == LZMA_BUF_ERROR else {
            throw CHDLZMAError.decompressionFailed(Int32(result.rawValue))
        }
        return output
    }
}
