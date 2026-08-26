// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("AuditReport worstStatus")
struct AuditReportWorstStatusTests {
    private func entry(_ status: AuditStatus, isDisk: Bool = false) -> AuditEntry {
        AuditEntry(status: status, game: "Game", isDisk: isDisk, name: isDisk ? "disk.chd" : "rom.bin", path: nil)
    }

    @Test("missing outranks incorrect, which outranks correct/surplus")
    func severityOrder() {
        #expect(AuditStatus.worst(among: [.correct, .surplus]) == .correct)
        #expect(AuditStatus.worst(among: [.correct, .incorrect]) == .incorrect)
        #expect(AuditStatus.worst(among: [.incorrect, .missing]) == .missing)
        #expect(AuditStatus.worst(among: [.correct, .incorrect, .missing, .surplus]) == .missing)
    }

    @Test("an empty sequence has no worst status")
    func emptyIsNil() {
        #expect(AuditStatus.worst(among: [AuditStatus]()) == nil)
    }

    @Test("AuditReport.worstStatus rolls up the same way over its entries")
    func reportRollsUp() {
        let allCorrect = AuditReport(entries: [entry(.correct), entry(.surplus)], correct: 1, incorrect: 0, missing: 0, surplus: 1)
        #expect(allCorrect.worstStatus == .correct)

        let withMissing = AuditReport(entries: [entry(.correct), entry(.incorrect), entry(.missing)], correct: 1, incorrect: 1, missing: 1, surplus: 0)
        #expect(withMissing.worstStatus == .missing)

        let empty = AuditReport(entries: [], correct: 0, incorrect: 0, missing: 0, surplus: 0)
        #expect(empty.worstStatus == nil)
    }

    /// jensyleo's own report (2026-07-30, see ROADMAP.md "CHD/ROM
    /// independence"): a missing CHD disk anywhere in a large MAME DAT
    /// (the common case — nobody has every arcade CD/hard-disk image)
    /// used to permanently pin this whole-system badge to "Bad" even when
    /// every rom the user actually cares about was perfectly correct.
    @Test("a missing/incorrect disk entry never affects worstStatus when rom entries exist")
    func diskEntriesDoNotAffectWorstStatusAlongsideRoms() {
        let allRomsCorrectOneDiskMissing = AuditReport(
            entries: [entry(.correct), entry(.correct), entry(.missing, isDisk: true)],
            correct: 2, incorrect: 0, missing: 1, surplus: 0
        )
        #expect(allRomsCorrectOneDiskMissing.worstStatus == .correct)

        let oneRomMissingOneDiskCorrect = AuditReport(
            entries: [entry(.correct), entry(.missing), entry(.correct, isDisk: true)],
            correct: 2, incorrect: 0, missing: 1, surplus: 0
        )
        #expect(oneRomMissingOneDiskCorrect.worstStatus == .missing)
    }

    @Test("falls back to disk-only status when a machine declares a CHD but no roms at all")
    func fallsBackToDiskOnlyWhenNoRomsExist() {
        let diskOnly = AuditReport(entries: [entry(.missing, isDisk: true)], correct: 0, incorrect: 0, missing: 1, surplus: 0)
        #expect(diskOnly.worstStatus == .missing)
    }
}
