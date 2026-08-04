// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One file, from disk, to be packed into a `.createArchive` operation under
/// `entryName`.
public struct ArchiveEntrySource: Equatable, Sendable {
    public let source: URL
    public let entryName: String

    public init(source: URL, entryName: String) {
        self.source = source
        self.entryName = entryName
    }
}

/// A single filesystem action needed to repair or rebuild a collection.
/// Planning (`RebuildPlanner`) and execution (`RebuildExecutor`) are kept
/// separate so a plan can be previewed before anything touches disk.
public enum RebuildOperation: Equatable, Sendable {
    case rename(from: URL, to: URL)
    case copy(from: URL, to: URL)
    case move(from: URL, to: URL)
    /// Packs loose files from disk into a new ZIP archive (one set == one game).
    case createArchive(entries: [ArchiveEntrySource], to: URL)
}
