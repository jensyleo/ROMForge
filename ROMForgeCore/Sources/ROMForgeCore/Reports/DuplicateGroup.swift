// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Two or more local files whose content identity matches — the same
/// content stored more than once, regardless of filename.
public struct DuplicateGroup: Equatable, Sendable {
    /// Usually a SHA1, but falls back to MD5 or CRC32 if SHA1 wasn't
    /// computed for this scan (see `DuplicateDetector.identityKey`).
    public let sha1: String
    public let files: [HashedFile]

    public init(sha1: String, files: [HashedFile]) {
        self.sha1 = sha1
        self.files = files
    }
}
