// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("ParentCloneSummary")
struct ParentCloneSummaryTests {
    private func game(_ name: String, cloneOf: String? = nil) -> DATGame {
        DATGame(name: name, description: name, cloneOf: cloneOf, romOf: cloneOf, roms: [])
    }

    @Test("empty status map (no scan yet) yields an empty summary")
    func noScanYieldsEmpty() {
        let games = [game("sf2"), game("sf2a", cloneOf: "sf2")]
        let summary = ParentCloneSummary.compute(games: games, statusByName: [:])
        #expect(summary.cloneCompletionByParent.isEmpty)
        #expect(summary.clonesMissingParent.isEmpty)
    }

    @Test("counts present clones out of every declared clone")
    func countsCloneCompletion() {
        let games = [
            game("sf2"), game("sf2a", cloneOf: "sf2"), game("sf2b", cloneOf: "sf2"), game("sf2c", cloneOf: "sf2"),
        ]
        let status: [String: AuditStatus] = ["sf2": .correct, "sf2a": .correct, "sf2b": .missing, "sf2c": .incorrect]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        let completion = summary.cloneCompletionByParent["sf2"]
        #expect(completion?.present == 2)
        #expect(completion?.total == 3)
    }

    @Test("flags a present clone whose parent is missing")
    func flagsMissingParent() {
        let games = [game("sf2"), game("sf2a", cloneOf: "sf2")]
        let status: [String: AuditStatus] = ["sf2": .missing, "sf2a": .correct]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        #expect(summary.clonesMissingParent == ["sf2a"])
    }

    @Test("does not flag a present clone whose parent is also present")
    func doesNotFlagWhenParentPresent() {
        let games = [game("sf2"), game("sf2a", cloneOf: "sf2")]
        let status: [String: AuditStatus] = ["sf2": .correct, "sf2a": .correct]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        #expect(summary.clonesMissingParent.isEmpty)
    }

    @Test("does not flag an absent clone even when its parent is also absent")
    func doesNotFlagAbsentClone() {
        let games = [game("sf2"), game("sf2a", cloneOf: "sf2")]
        let status: [String: AuditStatus] = ["sf2": .missing, "sf2a": .missing]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        #expect(summary.clonesMissingParent.isEmpty)
    }

    @Test("a parent absent from statusByName entirely (never scanned into a game row) still counts as absent")
    func unknownParentStatusCountsAsAbsent() {
        let games = [game("sf2"), game("sf2a", cloneOf: "sf2")]
        let status: [String: AuditStatus] = ["sf2a": .correct]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        #expect(summary.clonesMissingParent == ["sf2a"])
    }

    @Test("a parent with no clones at all gets no entry")
    func noEntryForClonelessParent() {
        let games = [game("pacman")]
        let status: [String: AuditStatus] = ["pacman": .correct]
        let summary = ParentCloneSummary.compute(games: games, statusByName: status)
        #expect(summary.cloneCompletionByParent.isEmpty)
    }
}
