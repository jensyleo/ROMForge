// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// A scanned file paired with its computed hashes, ready to be matched
/// against a DAT.
public struct HashedFile: Equatable, Sendable {
    public let file: ScannedFile
    public let hash: FileHash
    /// Set when `FileHasher` detected a known leading copier header
    /// (`HeaderSkipRule`) on this file — lets `ROMMatcher` also try
    /// matching the header-stripped identity against a headerless DAT
    /// entry. Nil for the common case (no header detected).
    public let headerStripped: HeaderStrippedHash?

    public init(file: ScannedFile, hash: FileHash, headerStripped: HeaderStrippedHash? = nil) {
        self.file = file
        self.hash = hash
        self.headerStripped = headerStripped
    }
}
