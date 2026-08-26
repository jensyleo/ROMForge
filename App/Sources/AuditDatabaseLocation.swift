// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import ROMForgeCore

/// One shared SQLite database for the whole app (`romforge.sqlite3`,
/// alongside `systems.json`) — persists every configured system's last
/// audit, keyed by the system's own id. Replaces the earlier per-system
/// `SystemStatusStore` JSON files (a real database can answer both "what's
/// this system's last status" and "show me the full last report" from one
/// place, instead of two separate, easily-drifting mechanisms).
enum AuditDatabaseLocation {
    static func open() throws -> AuditReportDatabase {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("ROMForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try AuditReportDatabase(path: directory.appendingPathComponent("romforge.sqlite3").path)
    }
}
