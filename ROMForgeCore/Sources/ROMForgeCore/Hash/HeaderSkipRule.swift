// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A leading "copier header" some console dump conventions add ahead of the
/// actual cartridge/disk data — present in the raw file but absent from the
/// hash a No-Intro/Goodxxx-style DAT expects, so hashing the whole file
/// never matches a headered dump even when its contents are otherwise
/// correct.
///
/// These specific formats/offsets come from studying RomCenter's own
/// signature-plugin sources (`Goodxxx/fmt/*.cpp` in
/// github.com/ebolefeysot/RomcenterPlugins, GPL-3.0), which implement the
/// same widely-documented Goodxxx-tools conventions. Wired into
/// `ROMMatcher` via `FileHasher`'s header-stripped hash (see
/// `HeaderStrippedHash`) — a headered local file can now match a headerless
/// DAT entry.
public enum HeaderSkipRule: String, CaseIterable, Sendable, Codable {
    /// iNES: 16-byte header, magic `"NES\x1A"`.
    case iNES
    /// Atari Lynx: 64-byte header, magic `"LYNX"`.
    case lynx64
    /// A 512-byte copier header used by several conventions (SNES, Game
    /// Boy, PC Engine, Master System) with no fixed magic — detected by
    /// file size instead: the real data is a round multiple of 1024 bytes,
    /// so a correctly-headered file's size mod 1024 is exactly 512.
    case copier512
    /// Genesis/Mega Drive `.smd`: not a simple leading header, a full block
    /// interleave (see `GenesisSMDConverter`). Included here only as a tag
    /// for `HeaderStrippedHash.rule` — detecting and stripping it needs the
    /// file's name (`.smd` extension) and a byte-reordering transform, not
    /// just a byte count, so it's handled as its own path in
    /// `FileHasher`/`ZipArchiveHasher` rather than through `detect(fileSize:
    /// headBytes:)` below. `headerLength` always returns 0 for it — it is
    /// never selected by the generic detection loop.
    case genesisSMD

    /// Bytes to skip from the start of the file when hashing, or 0 if this
    /// rule's signature doesn't match. Takes the total file size (needed
    /// for `copier512`'s size-based check) and just the leading bytes
    /// (enough for a magic-number check) rather than the whole file, so
    /// detection never requires loading a large ROM into memory.
    public func headerLength(fileSize: Int64, headBytes: Data) -> Int {
        switch self {
        case .iNES:
            guard fileSize > 16, headBytes.count >= 4 else { return 0 }
            return headBytes.prefix(4).elementsEqual([0x4E, 0x45, 0x53, 0x1A]) ? 16 : 0
        case .lynx64:
            guard fileSize > 64, headBytes.count >= 4 else { return 0 }
            return headBytes.prefix(4).elementsEqual(Array("LYNX".utf8)) ? 64 : 0
        case .copier512:
            guard fileSize > 512 else { return 0 }
            return fileSize % 1024 == 512 ? 512 : 0
        case .genesisSMD:
            return 0
        }
    }

    /// Tries every rule and returns the first whose signature matches,
    /// along with the header length to skip — or nil if none apply (the
    /// common case: most files have no copier header).
    public static func detect(fileSize: Int64, headBytes: Data) -> (rule: HeaderSkipRule, headerLength: Int)? {
        for rule in allCases {
            let length = rule.headerLength(fileSize: fileSize, headBytes: headBytes)
            if length > 0 {
                return (rule, length)
            }
        }
        return nil
    }
}
