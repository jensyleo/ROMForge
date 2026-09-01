// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One file, from disk, to be packed into a `.createArchive` operation under
/// `entryName` (the NAME IT GETS in the new archive being built).
public struct ArchiveEntrySource: Equatable, Sendable {
    /// A loose file's own path, OR — when `sourceArchiveEntryName` is set —
    /// the `.zip` archive that actually holds the bytes, one entry among
    /// (usually) several others that must NOT be pulled in along with it.
    public let source: URL
    public let entryName: String
    /// Non-nil when `source` is itself a `.zip` and this rom's real content
    /// is one entry inside it (named here) rather than `source` being a
    /// loose file on its own — see this whole type's own doc comment for
    /// why this distinction has to exist at all. `nil` for a genuinely
    /// loose source file.
    public let sourceArchiveEntryName: String?

    public init(source: URL, entryName: String, sourceArchiveEntryName: String? = nil) {
        self.source = source
        self.entryName = entryName
        self.sourceArchiveEntryName = sourceArchiveEntryName
    }
}

/// A single filesystem action needed to repair or rebuild a collection.
/// Planning (`RebuildPlanner`) and execution (`RebuildExecutor`) are kept
/// separate so a plan can be previewed before anything touches disk.
public enum RebuildOperation: Equatable, Sendable {
    case rename(from: URL, to: URL)
    case copy(from: URL, to: URL)
    case move(from: URL, to: URL)
    /// Extracts one named entry out of a `.zip` — the ONLY correct way to
    /// pull a single rom out of a multi-rom archive onto disk as its own
    /// file. jensyleo's own report (2026-09-01), caught before any real-ROM
    /// testing: `.copy`/`.move` on a zip-entry `HashedFile`'s own `.file.url`
    /// would copy/move the WHOLE containing `.zip` (that URL IS the
    /// archive's own path — see `CollectionHasher`'s own construction of a
    /// zip-entry `ScannedFile`), silently producing N corrupt "rom" files
    /// (each secretly the entire original zip) for an N-rom archive instead
    /// of the actual per-rom content. `RebuildPlanner` now routes every
    /// zip-sourced rom through this case instead.
    case extractZipEntry(archive: URL, entryName: String, to: URL)
    /// Packs loose files from disk into a new ZIP archive (one set == one game).
    case createArchive(entries: [ArchiveEntrySource], to: URL)
    /// Packs loose files into a TorrentZip-compliant archive (Fase 2 Step 2).
    case createTorrentZipArchive(entries: [ArchiveEntrySource], to: URL)
    /// Permanently removes a single file — "Remove useless files" (Fase 2
    /// Step 7). Only ever planned for a file the DAT recognizes nothing
    /// about at all (see `RebuildPlanner.planRemoveUselessFiles`'s own doc
    /// comment for the exact criterion); never for a file some other game
    /// still needs.
    case delete(URL)
    /// Adds one entry, read from a DIFFERENT source (a loose file, or one
    /// entry inside another `.zip`), into an EXISTING `.zip` — Fase 2 Step
    /// 3's "cross-set repair" (borrowing a rom from a sibling parent/clone
    /// set that already has it). Uses ZIPFoundation's `.update` access mode
    /// to rewrite the target archive's own central directory in place,
    /// rather than the extract-rewrite-repack round trip `createArchive`/
    /// `createTorrentZipArchive` need when building a BRAND NEW archive —
    /// this one already exists and every other entry in it must survive
    /// untouched.
    case addEntryToZip(targetArchive: URL, entryName: String, source: ArchiveEntrySource)
    /// Removes one entry from an EXISTING `.zip`, leaving every other entry
    /// in it untouched — "Remove useless roms" (Fase 2 Step 7, entry-level)
    /// and the entry-removal half of "Rename roms inside archives" (Step
    /// 6). Uses ZIPFoundation's `.update` access mode + `Archive.remove(_:)`
    /// — jensyleo's own find (2026-09-01, after the whole-archive-deletion
    /// bug was caught): the entry-removal capability this whole area was
    /// originally documented as blocked on already exists in the ZIP
    /// library this app already depends on for `.addEntryToZip`.
    case removeEntryFromZip(archive: URL, entryName: String)
}
