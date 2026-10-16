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
        // MSU-1 groups (see `keyProvider`): "msu-folder|<folder path>" shows
        // the folder's name, "msu-game|<folder>|<base>|<display>" the game's.
        if key.hasPrefix("msu-folder|") { return (String(key.dropFirst("msu-folder|".count)) as NSString).lastPathComponent }
        if key.hasPrefix("msu-game|"), let display = key.split(separator: "|", omittingEmptySubsequences: false).last { return String(display) }
        return key.contains("/") ? (key as NSString).lastPathComponent : key
    }

    private static let msuROMExtensions: Set<String> = ["sfc", "smc", "swc", "fig"]

    /// Name of an MSU-1 file without extension, comparable across a game's
    /// files: lower-cased, underscores as spaces, and — for a `.pcm` track —
    /// without its trailing "-N" ("Batman_Returns_(USA)_(MSU1)-12.pcm" and
    /// "Batman Returns (USA) (MSU1).sfc" share one base).
    private static func normalizedMSUBase(_ url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent.lowercased()
        if url.pathExtension.lowercased() == "pcm", let dash = stem.lastIndex(of: "-"),
           stem[stem.index(after: dash)...].allSatisfy(\.isNumber) {
            stem = String(stem[..<dash])
        }
        return stem.replacingOccurrences(of: "_", with: " ")
    }

    /// The grouping key to use for a batch of entries. Identical to `key(for:)`
    /// except for SNES MSU-1 games: in a folder that holds a `.msu` file or `.pcm` tracks, the
    /// ROM, the `.msu`, the `.bml` and every `.pcm` track belong together —
    /// one group per game folder, or, when several games share one folder,
    /// one group per game name — instead of hundreds of loose "unknown"
    /// files. Detected from the files themselves, not from any setting.
    public static func keyProvider(for entries: [AuditEntry]) -> (AuditEntry) -> String {
        var msuFolders = Set<String>()
        var romsByFolder: [String: [String: String]] = [:]
        for entry in entries {
            guard let path = entry.path else { continue }
            let ext = path.pathExtension.lowercased()
            let folder = path.deletingLastPathComponent().path
            // A folder is an MSU-1 folder when it holds a `.msu` flag file or
            // any `.pcm` audio track — many packs ship without the (empty)
            // `.msu` file or even without the ROM.
            if ext == "msu" || ext == "pcm" {
                msuFolders.insert(folder)
            } else if msuROMExtensions.contains(ext) {
                romsByFolder[folder, default: [:]][normalizedMSUBase(path)] = path.deletingPathExtension().lastPathComponent
            }
        }
        guard !msuFolders.isEmpty else { return { key(for: $0) } }
        return { entry in
            guard let path = entry.path else { return key(for: entry) }
            let folder = path.deletingLastPathComponent().path
            let ext = path.pathExtension.lowercased()
            guard msuFolders.contains(folder), msuROMExtensions.contains(ext) || ["msu", "pcm", "bml"].contains(ext) else {
                return key(for: entry)
            }
            let roms = romsByFolder[folder] ?? [:]
            if roms.count <= 1 { return "msu-folder|" + folder }
            let base = normalizedMSUBase(path)
            return "msu-game|\(folder)|\(base)|\(roms[base] ?? path.deletingPathExtension().lastPathComponent)"
        }
    }
}
