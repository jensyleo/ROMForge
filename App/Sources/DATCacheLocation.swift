// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One parsed-`DATFile` cache per configured system, alongside `systems.json`
/// and `ScanCache` — keyed by the system's own id so removing/re-adding a
/// system starts fresh rather than inheriting a stale cache by
/// path/URL coincidence.
enum DATCacheLocation {
    static func url(for system: RomSystem) -> URL {
        PerSystemCacheLocation.url(for: system, subdirectory: "DATCaches")
    }

    static func remove(for system: RomSystem) {
        PerSystemCacheLocation.remove(for: system, subdirectory: "DATCaches")
    }
}
