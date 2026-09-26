// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Flags a `.missing` rom that "Find ROMs…"
/// (`RebuildPlanner.planRepairFromMaintenanceFolder`) would actually be able
/// to repair right now — jensyleo's own request (2026-09-14): after
/// confirming (via a live diagnostic, then a real end-to-end repair) that
/// "Find ROMs…" correctly plans and performs this fix, the remaining gap was
/// purely visual — a missing rom with a donor already staged still showed
/// the exact same plain red as one with no fix in sight at all.
///
/// Purely informational, same read-only spirit as `OrphanedBIOSDetector`:
/// nothing is copied or written here — this only marks existing rows so the
/// UI can render such a rom differently (see `AuditStatusTint`'s own
/// App-layer consumer) than one with no known fix at all.
///
/// Deliberately reuses `RebuildPlanner.romsRepairableFromMaintenanceFolder`
/// rather than re-deriving "has a donor" by a plain hash comparison —
/// jensyleo's own live report (2026-09-14): a game with no anchor at all
/// (its own archive/file genuinely absent, e.g. deleted entirely) still
/// showed every one of its roms as "donor available" purely because the
/// Maintenance folder happened to have a matching donor for each, even
/// though `planRepairFromMaintenanceFolder` itself can never write anywhere
/// without a real anchor to attach to — "Find ROMs…" would silently do
/// nothing for it, making the yellow indicator a false promise. Sharing the
/// exact same anchor+donor-match guards (rather than a second, independent
/// copy of them) is what guarantees "looks fixable" here can never disagree
/// with what "Find ROMs…" would actually do.
/// jensyleo's own follow-up (2026-09-14): "fusionalo con repair from
/// maintenance folder. A la larga es lo mismo" — a `.badDump` (hash
/// mismatch) rom with a verified-correct donor staged is, from the user's
/// own point of view, the exact same situation as a `.missing` rom with one:
/// something in the Maintenance folder can fix this row right now. Both
/// therefore share this one detector and this one `hasMaintenanceDonor`
/// flag — the App layer's "Find ROMs…" action (both
/// its toolbar entry and its context-menu counterpart) now plans and
/// executes both kinds of fix together, rather than needing a second,
/// separate "Replace Corrupted ROMs…" action for what is, to the user, the
/// same "fix it from Maintenance" gesture.
public enum MaintenanceDonorDetector {
    public static func markingDonorsAvailable(in report: AuditReport, matchReport: MatchReport, donorFiles: [HashedFile]) -> AuditReport {
        guard !donorFiles.isEmpty else { return report }
        let repairable = RebuildPlanner.romsRepairableFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles)
        let replaceable = RebuildPlanner.romsReplaceableFromMaintenanceFolder(matchReport: matchReport, donorFiles: donorFiles)
        guard !repairable.isEmpty || !replaceable.isEmpty else { return report }

        var changed = false
        let mappedEntries: [AuditEntry] = report.entries.map { entry in
            // A `.missing`/`.badDump` rom with a real `game` owner is the
            // original, already-working case above. A misfiled rom found
            // as a SURPLUS somewhere else — `entry.game == nil`, but
            // `requiredByGameMachineName` names the REAL owning machine
            // (jensyleo's own real collection, 2026-09-17:
            // `CAPCOM/CPS2/naomi.zip`'s own extra rom genuinely belongs to
            // machine "naomi", elsewhere in this same system) — is the
            // SAME physical rom, under the SAME name, just sitting in the
            // wrong place. It keys into the exact same `repairable`/
            // `replaceable` sets the owning game's own `.missing`/
            // `.badDump` row would (built from `matchReport.games`, so
            // "naomi"'s own entry there is what actually gets repaired —
            // this surplus row is just a second, right-clickable door onto
            // that same fix, not a separate mechanism). Right-clicking
            // EITHER the owning game's own missing-rom row or this stray
            // file's own row ends up planning and executing the identical
            // `RebuildPlanner` operation.
            let machineName = entry.game ?? entry.requiredByGameMachineName
            guard let machineName else { return entry }
            let key = "\(machineName)\u{0}\(entry.name)"
            let hasDonor: Bool
            if entry.game != nil {
                // A `.foundElsewhere` rom (content genuinely absent from
                // THIS game's own archive, merely borrowed informationally
                // from another game's — see `RomMatchStatus.foundElsewhere`'s
                // own doc comment) is reported as `.incorrect` by
                // `AuditReporter`, not `.missing` — real bug found live by
                // jensyleo (2026-09-21): after extending
                // `RebuildPlanner.romsRepairableFromMaintenanceFolder`
                // itself to also repair `.foundElsewhere` roms (a NAOMI
                // BIOS rom shared with `mvsc2`), this flag still required
                // `entry.status == .missing`, so "Repair from Maintenance
                // Folder…" never even appeared in the context menu and the
                // "Available in another game" text kept showing instead of
                // the Maintenance-donor one, even though the repair itself
                // would have worked. Checking `foundElsewhereArchiveName`
                // here keeps the same "only when this game's own game-row
                // entry lacks it" scope `.missing`/`.badDump` already have.
                hasDonor = (entry.status == .missing && repairable.contains(key))
                    || (entry.status == .badDump && replaceable.contains(key))
                    || (entry.status == .incorrect && entry.foundElsewhereArchiveName != nil && repairable.contains(key))
            } else {
                // A surplus/misfiled entry never carries `.missing`/
                // `.badDump` itself (it physically exists, just in the
                // wrong place) — `status == .incorrect` is what
                // `AuditReporter` assigns whenever
                // `requiredByGameMachineName`/`requiredByGameDescription`
                // is set, so that's the gate here instead.
                hasDonor = entry.status == .incorrect && (repairable.contains(key) || replaceable.contains(key))
            }
            guard hasDonor else { return entry }
            changed = true
            return entry.markedMaintenanceDonor()
        }
        guard changed else { return report }

        return AuditReport(
            entries: mappedEntries, correct: report.correct, incorrect: report.incorrect, badDump: report.badDump,
            missing: report.missing, surplus: report.surplus, unverifiable: report.unverifiable, duplicateSets: report.duplicateSets
        )
    }
}
