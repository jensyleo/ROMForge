// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// The header of a CHD (MAME's Compressed Hunks of Data disk image format),
/// version 5. Only the fields needed to identify and verify a disk are
/// modeled — reading/decompressing the hunk data itself is a separate,
/// later effort (CHD's chunked, multi-codec body is a decoder project of
/// its own, deliberately out of scope here).
public struct CHDHeader: Equatable, Sendable {
    public let version: UInt32
    public let logicalBytes: UInt64
    /// Byte offset of the compressed hunk map (see `CHDV5MapReader`,
    /// `CHDHunkReader`) — needed to actually read hunks, not just verify
    /// the file's declared identity.
    public let mapOffset: UInt64
    public let hunkBytes: UInt32
    public let unitBytes: UInt32
    /// The 4 codec FourCCs a v5 CHD declares (e.g. `zlib`/`lzma`/`cdzl`/
    /// `cdlz`/`cdfl`/`huff`/`zstd`/`cdzs`, 0 for an unused slot) — each
    /// hunk's map entry names one of these slots by *index* (0-3), not by
    /// codec directly, so this array is what actually resolves "compression
    /// type 0" to a real codec for a given file. Different CHDs can and do
    /// use the same slot index for different codecs (e.g. slot 0 is `cdlz`
    /// for a CD image but plain `zlib` for a hard disk image) — always
    /// dispatch through this, never assume a fixed mapping.
    public let compressorTags: [UInt32]
    /// SHA1 of the raw hunk data only.
    public let rawSHA1: String
    /// SHA1 of raw data + metadata — this is the value MAME's `-listxml`
    /// declares as `<disk sha1="...">`, and what DAT tools compare against
    /// without ever decompressing a hunk.
    public let sha1: String
    /// SHA1 of the parent CHD this one diffs against, if any (nil for a
    /// standalone image).
    public let parentSHA1: String?

    public init(version: UInt32, logicalBytes: UInt64, mapOffset: UInt64, hunkBytes: UInt32, unitBytes: UInt32, compressorTags: [UInt32], rawSHA1: String, sha1: String, parentSHA1: String?) {
        self.version = version
        self.logicalBytes = logicalBytes
        self.mapOffset = mapOffset
        self.hunkBytes = hunkBytes
        self.unitBytes = unitBytes
        self.compressorTags = compressorTags
        self.rawSHA1 = rawSHA1
        self.sha1 = sha1
        self.parentSHA1 = parentSHA1
    }
}
