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
    /// The exact path of this file INSIDE its containing zip, when it lives
    /// under a real subfolder there — `nil` for a loose file, or a zip entry
    /// that already sits at the archive's own top level (`name` alone is
    /// already the whole story). Real bug found live by jensyleo
    /// (2026-09-23): a `.zip` created from a folder that once lived on a
    /// non-Mac filesystem can contain a real "__MACOSX/._<name>" AppleDouble
    /// resource-fork sidecar subfolder — `RebuildPlanner
    /// .planRemoveUselessFiles` used to plan `.removeEntryFromZip` with just
    /// `name` ("._foo.bin", the entry's OWN doc comment on why that's
    /// normally right for DAT-name matching), which ZIPFoundation's own
    /// `Archive[entryName]` lookup then correctly failed to find — the REAL
    /// entry lives at "__MACOSX/._foo.bin", not "._foo.bin" — "Source file
    /// does not exist" for every single one, 0 removed. `effectiveEntryPath`
    /// below is what any caller that needs to address the exact zip entry
    /// (removal, rename-in-archive) should use instead of `name` alone.
    public let entryPath: String?

    public init(url: URL, name: String, size: Int64, modificationDate: Date = Date(timeIntervalSince1970: 0), entryPath: String? = nil) {
        self.url = url
        self.name = name
        self.size = size
        self.modificationDate = modificationDate
        self.entryPath = entryPath == name ? nil : entryPath
    }

    /// The real identifier to use when addressing this file inside its own
    /// container — `entryPath` when this is a nested zip entry, otherwise
    /// `name` (a loose file, or a top-level zip entry, where the two are
    /// already identical).
    public var effectiveEntryPath: String { entryPath ?? name }
}
