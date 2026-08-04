// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Which of CRC32/MD5/SHA1 to actually compute while hashing — a
/// user-facing speed/thoroughness tradeoff (MD5 and SHA1 cost real CPU time
/// on top of CRC32, especially across a large collection), not a
/// correctness one: `ROMMatcher` only ever compares hashes both the DAT
/// declares *and* were actually computed, so disabling an algorithm never
/// causes a false "missing" — it just narrows how a rom can be confirmed.
/// At least one algorithm must stay enabled for matching to mean anything
/// at all; the app's settings UI enforces that.
public struct HashAlgorithms: OptionSet, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let crc32 = HashAlgorithms(rawValue: 1 << 0)
    public static let md5 = HashAlgorithms(rawValue: 1 << 1)
    public static let sha1 = HashAlgorithms(rawValue: 1 << 2)

    public static let all: HashAlgorithms = [.crc32, .md5, .sha1]
}
