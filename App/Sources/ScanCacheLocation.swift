// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One `ScanCache` file per configured system, alongside `systems.json` —
/// keyed by the system's own id so removing/re-adding a system starts fresh
/// rather than inheriting a stale cache by folder-path coincidence.
enum ScanCacheLocation {
    static func url(for system: RomSystem) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("ROMForge", isDirectory: true).appendingPathComponent("ScanCaches", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(system.id.uuidString).json")
    }

    static func remove(for system: RomSystem) {
        try? FileManager.default.removeItem(at: url(for: system))
    }
}
