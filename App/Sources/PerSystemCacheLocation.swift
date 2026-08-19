// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Shared by every "one JSON file per configured system, alongside
/// `systems.json`" cache location (`ScanCacheLocation`, `DATCacheLocation`)
/// — found duplicated near-byte-identically (same `applicationSupportDirectory`
/// lookup, same temp-directory fallback, same filename convention) during a
/// 2026-08-18 code audit; the only thing that ever differed between them
/// was the subdirectory name.
enum PerSystemCacheLocation {
    static func url(for system: RomSystem, subdirectory: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("ROMForge", isDirectory: true).appendingPathComponent(subdirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(system.id.uuidString).json")
    }

    static func remove(for system: RomSystem, subdirectory: String) {
        try? FileManager.default.removeItem(at: url(for: system, subdirectory: subdirectory))
    }
}
