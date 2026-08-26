// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Flags a scanned entry whose own physical file is named per the
/// TOSEC/GoodTools embedded-CRC convention (`FilenameEmbeddedCRC`) but whose
/// declared CRC32 disagrees with the CRC32 that file's content actually
/// hashes to — a name-vs-content discrepancy, orthogonal to `AuditStatus`
/// (that's about the DAT; this is about the file's own filename lying about
/// its own bytes). Same pure "flag an already-computed row" shape as
/// `OrphanedBIOSDetector`.
///
/// Cheap enough to run on every scan (just a filename parse plus a string
/// compare against a hash `AuditReporter` already computed — no extra file
/// I/O at all), unlike `ZipIntegrityAuditor`'s deliberately on-demand pass.
public enum FilenameCRCVerifier {
    public static func markingMismatches(in report: AuditReport) -> AuditReport {
        var changed = false
        let mappedEntries: [AuditEntry] = report.entries.map { entry in
            guard let path = entry.path, let actualCRC = entry.actualCRC,
                  let embedded = FilenameEmbeddedCRC.embeddedCRC32(inFileName: path.lastPathComponent),
                  embedded != actualCRC.lowercased() else { return entry }
            changed = true
            return entry.markedFilenameCRCMismatch()
        }
        guard changed else { return report }

        return AuditReport(
            entries: mappedEntries, correct: report.correct, incorrect: report.incorrect, badDump: report.badDump,
            missing: report.missing, surplus: report.surplus, unverifiable: report.unverifiable, duplicateSets: report.duplicateSets
        )
    }
}
