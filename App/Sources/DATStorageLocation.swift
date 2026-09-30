// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// ROMForge's own internal copy of a DAT the user picked from disk via an
/// `NSOpenPanel` — jensyleo's own report (2026-09-29): after moving the
/// external `.dat` file he'd picked for NES into a different folder,
/// ROMForge lost track of it entirely ("Scan Failed... no such file"), and
/// he pointed out the same thing would happen to MAME's own DAT if it were
/// ever moved (he just hadn't hit it there yet). Any real document-based
/// app copies what you hand it into its own storage the moment you pick
/// it, rather than keeping a live reference to wherever it happened to sit
/// on disk — `copy(from:)` is that copy step, called right after the user
/// picks a file in the Open panel, BEFORE `RomSystem.datURL`/an "Update
/// Database" re-point is ever set, everywhere a DAT is chosen from disk:
/// `AddSystemSheet.chooseDAT()`, and "Update Database" → "Choose DAT
/// File…" for both MAME and console systems (`SystemSettingsView.swift`).
///
/// Deliberately NOT involved in "Generate from Installed MAME…"
/// (`MAMEDATGenerator`) — that path never references an external,
/// user-owned file to begin with; its own output already lands directly
/// under ROMForge's Application Support directory, so there's nothing
/// external to lose track of there.
///
/// One stored DAT can legitimately be shared by several systems at once
/// (e.g. "Update Database" re-points every MAME system at one new DAT in
/// a single step) — `copy(from:)` makes no assumption of a 1:1
/// system-to-file relationship, matching how the external path already
/// worked. Each call gets its own fresh, collision-proof filename, so
/// `removeIfOrphaned(_:keeping:)` can later tell whether a given internal
/// copy is still referenced by anything before deleting it.
enum DATStorageLocation {
    private static func directory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ROMForge", isDirectory: true).appendingPathComponent("DATs", isDirectory: true)
    }

    /// True for a URL already living inside ROMForge's own DAT storage —
    /// used before deleting an old value to make sure it's genuinely one
    /// of ours, never a path the user still owns elsewhere.
    static func isInternal(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory().standardizedFileURL.path + "/")
    }

    /// Copies `source` into ROMForge's own storage under a fresh name and
    /// returns that internal URL — the value to actually store as
    /// `RomSystem.datURL`. Preserves the original file's extension
    /// (`.dat`/`.xml`/none, defaulting to `.dat`) so nothing about the
    /// existing Logiqx/MAME/software-list auto-detection downstream ever
    /// sees a different shape of file than before. Falls back to the
    /// original `source` URL untouched if the copy genuinely fails (e.g. a
    /// full disk) — same "never silently lose a value" caution as every
    /// other `try?`-guarded write in this app, just surfaced here as a
    /// fallback to external reference rather than a silent no-op, so
    /// "Add"/"Choose DAT File…" still works even in that rare case.
    static func copy(from source: URL) -> URL {
        let directory = directory()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "dat" : source.pathExtension
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch {
            return source
        }
    }

    /// Deletes `url` if — and only if — it's genuinely one of ROMForge's
    /// own internal copies AND no system in `keeping` references it
    /// anymore. Called right after replacing a system's (or several
    /// systems') `datURL`, passing the OLD value(s) and the just-updated
    /// system list, so a DAT still shared by another system (or the very
    /// one just re-pointed, if re-pointed at the same file for some
    /// reason) is never deleted out from under it. A no-op for an external
    /// path the user still owns — this only ever cleans up ROMForge's own
    /// storage.
    static func removeIfOrphaned(_ url: URL, keeping systems: [RomSystem]) {
        guard isInternal(url) else { return }
        guard !systems.contains(where: { $0.datURL == url }) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
