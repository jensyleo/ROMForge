// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameStatusRollup")
struct GameStatusRollupTests {
    private func entry(status: AuditStatus, isOptional: Bool = false, isDisk: Bool = false, name: String = "rom.bin") -> AuditEntry {
        AuditEntry(status: status, game: "game", isOptional: isOptional, isDisk: isDisk, name: name, path: nil)
    }

    @Test("missing outranks everything else")
    func missingIsWorst() {
        let entries = [entry(status: .correct), entry(status: .missing), entry(status: .badDump)]
        #expect(GameStatusRollup.gameCategory(for: entries) == .missing)
    }

    @Test("an optional missing entry doesn't drag the game down to missing")
    func optionalMissingIsExempt() {
        let entries = [entry(status: .correct), entry(status: .missing, isOptional: true)]
        #expect(GameStatusRollup.gameCategory(for: entries) == .correct)
    }

    @Test("badDump outranks incorrect and correct")
    func badDumpOutranksIncorrect() {
        let entries = [entry(status: .correct), entry(status: .incorrect), entry(status: .badDump)]
        #expect(GameStatusRollup.gameCategory(for: entries) == .badDump)
    }

    @Test("a game with only an unverifiable (undumped) entry reports unverifiable, not a false correct")
    func onlyUnverifiableIsNotCorrect() {
        #expect(GameStatusRollup.gameCategory(for: [entry(status: .unverifiable)]) == .unverifiable)
    }

    @Test("romOnlyGameCategory ignores a missing disk when roms are otherwise correct")
    func romOnlyIgnoresDiskStatus() {
        let entries = [entry(status: .correct), entry(status: .missing, isDisk: true, name: "disk.chd")]
        #expect(GameStatusRollup.romOnlyGameCategory(for: entries) == .correct)
    }

    @Test("romOnlyGameCategory falls back to disk entries when the game has no roms at all")
    func romOnlyFallsBackToDiskWhenNoRoms() {
        let entries = [entry(status: .missing, isDisk: true, name: "disk.chd")]
        #expect(GameStatusRollup.romOnlyGameCategory(for: entries) == .missing)
    }
}
