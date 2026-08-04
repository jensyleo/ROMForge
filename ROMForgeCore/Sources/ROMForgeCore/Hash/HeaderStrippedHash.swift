// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A file's hash/size computed with a detected leading copier header
/// (`HeaderSkipRule`) stripped off — lets `ROMMatcher` match a headered
/// local dump against a headerless DAT entry, the same identity a
/// No-Intro/Goodxxx-style DAT actually hashes.
public struct HeaderStrippedHash: Equatable, Sendable, Codable {
    public let rule: HeaderSkipRule
    public let size: Int64
    public let hash: FileHash

    public init(rule: HeaderSkipRule, size: Int64, hash: FileHash) {
        self.rule = rule
        self.size = size
        self.hash = hash
    }
}
