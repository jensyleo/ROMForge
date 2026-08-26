// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("DatabaseCategory")
struct DatabaseCategoryTests {
    private func entry(
        status: AuditStatus, game: String?, cloneOf: String? = nil, isBios: Bool = false,
        hasCHD: Bool = false, hasSamples: Bool = false, isBadDump: Bool = false,
        romDumpStatus: RomDumpStatus? = nil,
        requiredBiosNames: String? = nil, deviceRefNames: String? = nil, name: String = "rom.bin"
    ) -> AuditEntry {
        AuditEntry(
            status: status, game: game, cloneOf: cloneOf, isBios: isBios, hasCHD: hasCHD,
            hasSamples: hasSamples, isBadDump: isBadDump, romDumpStatus: romDumpStatus, requiredBiosNames: requiredBiosNames,
            deviceRefNames: deviceRefNames, name: name, path: nil
        )
    }

    @Test(".allGames returns everything unfiltered")
    func allGamesIsIdentity() {
        let entries = [entry(status: .correct, game: "a"), entry(status: .missing, game: "b")]
        #expect(DatabaseCategory.allGames.apply(to: entries) == entries)
    }

    @Test(".verifiedGames only includes a game whose EVERY rom matched")
    func verifiedGamesRequiresAllCorrect() {
        let entries = [
            entry(status: .correct, game: "fullyGood"),
            entry(status: .correct, game: "fullyGood"),
            entry(status: .correct, game: "partlyGood"),
            entry(status: .missing, game: "partlyGood"),
        ]
        let result = DatabaseCategory.verifiedGames.apply(to: entries)
        #expect(result.allSatisfy { $0.game == "fullyGood" })
        #expect(result.count == 2)
    }

    @Test(".originals excludes any entry with a cloneOf, .clones is the complement")
    func originalsAndClonesPartitionByCloneOf() {
        let entries = [entry(status: .correct, game: "parent"), entry(status: .correct, game: "clone", cloneOf: "parent")]
        #expect(DatabaseCategory.originals.apply(to: entries).map(\.game) == ["parent"])
        #expect(DatabaseCategory.clones.apply(to: entries).map(\.game) == ["clone"])
    }

    @Test(".biosFiles/.gamesWithCHD/.gamesWithSamples/.gamesWithBadDumps filter by their own flag")
    func flagBasedCategories() {
        let entries = [
            entry(status: .correct, game: "biosGame", isBios: true),
            entry(status: .correct, game: "chdGame", hasCHD: true),
            entry(status: .correct, game: "sampleGame", hasSamples: true),
            entry(status: .badDump, game: "badDumpGame", isBadDump: true),
            entry(status: .correct, game: "plainGame"),
        ]
        #expect(DatabaseCategory.biosFiles.apply(to: entries).map(\.game) == ["biosGame"])
        #expect(DatabaseCategory.gamesWithCHD.apply(to: entries).map(\.game) == ["chdGame"])
        #expect(DatabaseCategory.gamesWithSamples.apply(to: entries).map(\.game) == ["sampleGame"])
        #expect(DatabaseCategory.gamesWithBadDumps.apply(to: entries).map(\.game) == ["badDumpGame"])
    }

    @Test(".gamesWithNodump filters by romDumpStatus, not the collapsed isBadDump flag")
    func nodumpIsDistinctFromBadDump() {
        let entries = [
            entry(status: .badDump, game: "badDumpGame", isBadDump: true, romDumpStatus: .baddump),
            entry(status: .badDump, game: "nodumpGame", isBadDump: true, romDumpStatus: .nodump),
            entry(status: .correct, game: "plainGame"),
        ]
        // Both baddump and nodump still collapse into `.gamesWithBadDumps`
        // (that's what `isBadDump` means) — `.gamesWithNodump` picks out
        // just the real "no reference hash exists at all" case.
        #expect(DatabaseCategory.gamesWithBadDumps.apply(to: entries).map(\.game) == ["badDumpGame", "nodumpGame"])
        #expect(DatabaseCategory.gamesWithNodump.apply(to: entries).map(\.game) == ["nodumpGame"])
    }

    @Test(".missingGames/.incorrectGames filter by rom status directly")
    func statusBasedCategories() {
        let entries = [entry(status: .missing, game: "a"), entry(status: .incorrect, game: "b"), entry(status: .correct, game: "c")]
        #expect(DatabaseCategory.missingGames.apply(to: entries).map(\.game) == ["a"])
        #expect(DatabaseCategory.incorrectGames.apply(to: entries).map(\.game) == ["b"])
    }

    @Test(".gamesRequiringBIOS/.gamesWithDeviceRefs filter by non-nil comma-joined names")
    func biosAndDeviceRefCategories() {
        let entries = [
            entry(status: .correct, game: "needsBios", requiredBiosNames: "bios1"),
            entry(status: .correct, game: "needsDevice", deviceRefNames: "dev1"),
            entry(status: .correct, game: "plain"),
        ]
        #expect(DatabaseCategory.gamesRequiringBIOS.apply(to: entries).map(\.game) == ["needsBios"])
        #expect(DatabaseCategory.gamesWithDeviceRefs.apply(to: entries).map(\.game) == ["needsDevice"])
    }

    @Test("completeGames/fixableGames/partialGames/emptyGames delegate to GameCompletionStatus per game")
    func completionStatusCategories() {
        let entries = [
            entry(status: .correct, game: "complete"),
            entry(status: .incorrect, game: "fixable"),
            entry(status: .correct, game: "partial"), entry(status: .missing, game: "partial"),
            entry(status: .missing, game: "empty"),
        ]
        #expect(DatabaseCategory.completeGames.apply(to: entries).map(\.game) == ["complete"])
        #expect(DatabaseCategory.fixableGames.apply(to: entries).map(\.game) == ["fixable"])
        #expect(Set(DatabaseCategory.partialGames.apply(to: entries).map(\.game!)) == ["partial"])
        #expect(DatabaseCategory.emptyGames.apply(to: entries).map(\.game) == ["empty"])
    }
}
