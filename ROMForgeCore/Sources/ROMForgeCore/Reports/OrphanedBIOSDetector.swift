// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Flags a physically-present MAME BIOS archive (`neogeo.zip` and similar —
/// `AuditEntry.isBios`) that no *currently present* game in this same scan
/// actually depends on via `romOf` — a BIOS someone downloaded (often as
/// part of a bulk set) that ended up orphaned once its dependent games were
/// removed, renamed away, or never actually added. Purely informational,
/// same read-only spirit as `DuplicateSetDetector`: nothing is deleted or
/// moved, this only marks existing rows so the "Database" tree can surface
/// them under their own branch instead of them sitting silently indistinguish-
/// able from any other BIOS row.
///
/// Samples are the DAT's other "shared, easy to over-collect" file kind
/// (see ROADMAP.md's "Samples — filename-only matching" section), but
/// ROMForge has no sample-file scanning at all yet — `AuditEntry.hasSamples`
/// is presence-only (does the DAT declare one), never backed by an actual
/// scanned sample file/path the way a rom or CHD is. There is currently
/// nothing this detector could check a sample archive's physical presence
/// against, so it deliberately covers BIOS only; extending it to samples is
/// blocked on that scanning gap being closed first, not a further
/// modification to this file itself.
public enum OrphanedBIOSDetector {
    /// A BIOS machine counts as "in use" the moment some non-BIOS game with
    /// a genuine local file (`path != nil` — actually found on disk this
    /// scan, regardless of whether its own content matched correctly)
    /// declares that BIOS machine's name as its `requiredBiosNames`
    /// (`AuditReporter.generate`'s own `resolvedBiosMachineName` resolution,
    /// already computed per rom entry — this reads it back rather than
    /// re-walking `romOf` chains itself). A game that's entirely `.missing`
    /// contributes nothing: if nothing of it is actually present, its BIOS
    /// dependency isn't actually being exercised by this collection either.
    public static func markingOrphaned(in report: AuditReport) -> AuditReport {
        guard report.entries.contains(where: { $0.isBios && $0.path != nil }) else { return report }

        var usedBiosNames: Set<String> = []
        for entry in report.entries where !entry.isBios && entry.path != nil {
            guard let names = entry.requiredBiosNames, !names.isEmpty else { continue }
            for name in names.split(separator: ",") {
                usedBiosNames.insert(name.trimmingCharacters(in: .whitespaces))
            }
        }

        var changed = false
        let mappedEntries: [AuditEntry] = report.entries.map { entry in
            guard entry.isBios, entry.path != nil, let game = entry.game, !usedBiosNames.contains(game) else { return entry }
            changed = true
            return entry.markedOrphanedBios()
        }
        guard changed else { return report }

        return AuditReport(
            entries: mappedEntries, correct: report.correct, incorrect: report.incorrect, badDump: report.badDump,
            missing: report.missing, surplus: report.surplus, unverifiable: report.unverifiable, duplicateSets: report.duplicateSets
        )
    }
}
