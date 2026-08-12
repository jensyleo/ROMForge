// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameCompletionStatus")
struct GameCompletionStatusTests {
    private func entry(status: AuditStatus, isOptional: Bool = false, isDisk: Bool = false, name: String = "rom.bin") -> AuditEntry {
        AuditEntry(status: status, game: "game", isOptional: isOptional, isDisk: isDisk, name: name, path: nil)
    }

    @Test("empty entry list has no completion status")
    func emptyIsNil() {
        #expect(GameCompletionStatus.compute(for: []) == nil)
    }

    @Test("all correct is complete")
    func allCorrectIsComplete() {
        let entries = [entry(status: .correct), entry(status: .correct)]
        #expect(GameCompletionStatus.compute(for: entries) == .complete)
    }

    @Test("all missing is empty")
    func allMissingIsEmpty() {
        let entries = [entry(status: .missing), entry(status: .missing)]
        #expect(GameCompletionStatus.compute(for: entries) == .empty)
    }

    @Test("a mix of present and missing is partial")
    func mixedIsPartial() {
        let entries = [entry(status: .correct), entry(status: .missing)]
        #expect(GameCompletionStatus.compute(for: entries) == .partial)
    }

    @Test("everything present but misnamed is fixable, not complete")
    func allIncorrectIsFixable() {
        let entries = [entry(status: .incorrect), entry(status: .correct)]
        #expect(GameCompletionStatus.compute(for: entries) == .fixable)
    }

    @Test("a bad dump with nothing missing is partial, not fixable — renaming can't repair wrong content")
    func badDumpWithNoMissingIsPartialNotFixable() {
        let entries = [entry(status: .correct), entry(status: .badDump)]
        #expect(GameCompletionStatus.compute(for: entries) == .partial)
    }

    @Test("a missing optional entry is excluded from the required count, same as gameCategory(for:)'s own exemption")
    func missingOptionalDoesNotDragDownComplete() {
        let entries = [entry(status: .correct), entry(status: .missing, isOptional: true)]
        #expect(GameCompletionStatus.compute(for: entries) == .complete)
    }

    @Test("a game with only optional entries is vacuously complete")
    func onlyOptionalEntriesIsComplete() {
        let entries = [entry(status: .missing, isOptional: true)]
        #expect(GameCompletionStatus.compute(for: entries) == .complete)
    }

    @Test("a disk (CHD) entry never affects the rom-only completion verdict")
    func diskEntryExcludedWhenRomsExist() {
        // A missing CHD alongside an otherwise-complete rom set must not
        // drag the game down to .partial — same CHD/ROM independence rule
        // as `romOnlyGameCategory(for:)` in LibraryDetailView.
        let entries = [entry(status: .correct), entry(status: .missing, isDisk: true, name: "disk.chd")]
        #expect(GameCompletionStatus.compute(for: entries) == .complete)
    }

    @Test("a game with only a disk entry falls back to judging that disk")
    func diskOnlyGameFallsBackToDiskEntries() {
        let entries = [entry(status: .missing, isDisk: true, name: "disk.chd")]
        #expect(GameCompletionStatus.compute(for: entries) == .empty)
    }
}
