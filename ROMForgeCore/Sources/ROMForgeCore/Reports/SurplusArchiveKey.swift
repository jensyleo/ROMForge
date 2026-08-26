// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Groups a surplus (game-less) `AuditEntry` by the archive it physically
/// lives in — moved out of `LibraryDetailView.swift` (2026-08-13, "Grupo A"
/// of the App-logic extraction) so it's unit-testable. Keyed by FULL path
/// (not filename alone) so two same-named archives in different ROM
/// folders stay two distinct buckets.
public enum SurplusArchiveKey {
    public static func key(for entry: AuditEntry) -> String {
        entry.path?.path ?? entry.name
    }

    /// The filename to display for a `key(for:)` result — the key itself
    /// is a full path, only ever used for grouping/identity.
    public static func displayName(forKey key: String) -> String {
        key.contains("/") ? (key as NSString).lastPathComponent : key
    }
}
