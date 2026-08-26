// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Flags every `AuditEntry` whose containing `.zip` has a local-header vs
/// central-directory CRC32 mismatch for that specific entry (see
/// `ZipLocalHeaderCRCVerifier`'s own doc comment for what that means and why
/// it can happen). Same pure "flag an already-computed row" shape as
/// `OrphanedBIOSDetector`/`FilenameCRCVerifier` — nothing is deleted, moved,
/// or re-matched, only `hasInternalZipCRCMismatch` gets set on existing rows.
///
/// Deliberately its own explicit, on-demand entry point — never wired into
/// `AuditReporter.generate`/the normal scan pipeline. Reading every entry's
/// local header means opening and parsing each `.zip`'s full central
/// directory again, on top of the scan that already read it once for
/// listing/hashing — for a 50k+ game MAME collection, most of it packed in
/// zips, that's tens of thousands of extra archive opens on every single
/// scan, for a check that only ever matters for a genuinely damaged file (a
/// rare event, not something worth paying for every time just in case). A
/// user who wants to check can trigger this pass explicitly instead
/// (jensyleo's own call, given the task's own performance note on this
/// exact trade-off).
public enum ZipIntegrityAuditor {
    /// Verifies every unique `.zip` `report` actually references, then marks
    /// the matching entries. One `ZipLocalHeaderCRCVerifier.verify` call per
    /// unique archive path, not per entry — several roms commonly share one
    /// archive, and each archive's central directory only needs parsing once
    /// regardless of how many of its entries are being checked.
    public static func verifyingIntegrity(in report: AuditReport) -> AuditReport {
        let zipPaths = Set(report.entries.compactMap { entry -> URL? in
            guard let path = entry.path, path.pathExtension.lowercased() == "zip" else { return nil }
            return path
        })
        guard !zipPaths.isEmpty else { return report }

        var mismatchedNamesByPath: [URL: Set<String>] = [:]
        for path in zipPaths {
            guard let results = try? ZipLocalHeaderCRCVerifier.verify(path) else { continue }
            // `entryName` is the ZIP's own stored path, which can carry
            // leading directory components a flat MAME rom name never has —
            // compared by last path component so a real mismatch is still
            // found regardless of that.
            let mismatchedNames = Set(
                results.filter { $0.matches == false }.map { ($0.entryName as NSString).lastPathComponent }
            )
            guard !mismatchedNames.isEmpty else { continue }
            mismatchedNamesByPath[path] = mismatchedNames
        }
        guard !mismatchedNamesByPath.isEmpty else { return report }

        var changed = false
        let mappedEntries: [AuditEntry] = report.entries.map { entry in
            guard let path = entry.path, let mismatchedNames = mismatchedNamesByPath[path], mismatchedNames.contains(entry.name) else {
                return entry
            }
            changed = true
            return entry.markedInternalZipCRCMismatch()
        }
        guard changed else { return report }

        return AuditReport(
            entries: mappedEntries, correct: report.correct, incorrect: report.incorrect, badDump: report.badDump,
            missing: report.missing, surplus: report.surplus, unverifiable: report.unverifiable, duplicateSets: report.duplicateSets
        )
    }
}
