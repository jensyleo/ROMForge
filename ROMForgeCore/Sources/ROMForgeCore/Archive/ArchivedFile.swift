// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A file entry found inside a ZIP archive, not yet hashed.
public struct ArchivedFile: Equatable, Sendable {
    public let archiveURL: URL
    public let entryPath: String
    public let name: String
    public let size: Int64

    public init(archiveURL: URL, entryPath: String, name: String, size: Int64) {
        self.archiveURL = archiveURL
        self.entryPath = entryPath
        self.name = name
        self.size = size
    }
}
