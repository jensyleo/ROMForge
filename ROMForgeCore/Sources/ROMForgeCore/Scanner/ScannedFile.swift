// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A loose (uncompressed) file found on disk during a folder scan, not yet
/// hashed or matched against any DAT.
public struct ScannedFile: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let size: Int64
    /// The file's last modification date — for a loose file, its own; for a
    /// zip-entry-shaped `ScannedFile` (see `CollectionHasher`), the
    /// *containing archive's* mtime, since an entry has none of its own and
    /// the archive's mtime is what actually signals its contents could have
    /// changed. Used by `ScanCache` to skip re-hashing unchanged files
    /// between scans. Defaults to the Unix epoch (not `Date()`, which would
    /// make two otherwise-identical `ScannedFile`s compare unequal) so
    /// existing call sites that don't care about caching are unaffected.
    public let modificationDate: Date

    public init(url: URL, name: String, size: Int64, modificationDate: Date = Date(timeIntervalSince1970: 0)) {
        self.url = url
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
    }
}
