// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("GameNodeBuilder")
struct GameNodeBuilderTests {
    private func entry(
        status: AuditStatus, game: String?, isDisk: Bool = false, path: URL? = nil,
        foundElsewhereArchiveName: String? = nil, requiredByGameDescription: String? = nil, name: String = "rom.bin"
    ) -> AuditEntry {
        AuditEntry(
            status: status, game: game, isDisk: isDisk,
            foundElsewhereArchiveName: foundElsewhereArchiveName, requiredByGameDescription: requiredByGameDescription,
            name: name, path: path
        )
    }

    @Test("groups entries by game into one node per game, sorted alphabetically")
    func groupsByGame() {
        let entries = [entry(status: .correct, game: "zeta"), entry(status: .correct, game: "alpha")]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.map(\.name) == ["alpha", "zeta"])
    }

    @Test("a game with a rom and a CHD disk splits into two independent rows by default")
    func splitsRomAndDiskRows() {
        let entries = [
            entry(status: .correct, game: "g1"),
            entry(status: .missing, game: "g1", isDisk: true, name: "g1.chd"),
        ]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.count == 2)
        #expect(nodes.contains { !$0.isDiskRow && $0.aggregateStatus == .correct })
        #expect(nodes.contains { $0.isDiskRow && $0.aggregateStatus == .missing })
    }

    @Test("combineRomAndCHD folds rom and disk entries back into one row")
    func combineRomAndCHDFoldsIntoOneRow() {
        let entries = [
            entry(status: .correct, game: "g1"),
            entry(status: .missing, game: "g1", isDisk: true, name: "g1.chd"),
        ]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: true, isFolderScoped: false)
        #expect(nodes.count == 1)
        // Missing disk outranks correct rom in the combined rollup.
        #expect(nodes[0].aggregateStatus == .missing)
    }

    @Test("a missing rom row is skipped when the same game's CHD is present and not missing")
    func missingRomRowSkippedWhenDiskIsFine() {
        let entries = [
            entry(status: .missing, game: "g1"),
            entry(status: .correct, game: "g1", isDisk: true, name: "g1.chd"),
        ]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.count == 1)
        #expect(nodes[0].isDiskRow)
    }

    @Test("a surplus entry from a DIFFERENT physical archive than a same-named real game stays its own separate row")
    func surplusFromDifferentArchiveStaysSeparate() {
        // jensyleo's own report (2026-08-13): folding a surplus archive
        // into a real game's own node used to be decided by NAME alone
        // (the archive's filename, minus extension, equal to some real
        // DAT game's name) — but that's just a coincidence, not proof it's
        // the same file: a real `nss.7z` (a genuinely separate, different
        // physical file from the real `nss` BIOS's own `nss.zip`) got
        // folded into "nss"'s row purely because "nss.7z" minus its
        // extension is the string "nss", and that name-based lookup
        // proved non-deterministic across identical scans (confirmed live
        // via `DebugTrace`). Fixed to fold only by matching physical
        // archive *path* — here the surplus entry's path ("/roms/g1.zip")
        // never appears among "g1"'s own entries (which have no path at
        // all in this test), so it correctly stays its own row.
        let entries = [
            entry(status: .correct, game: "g1"),
            entry(status: .unknownFile, game: nil, path: URL(fileURLWithPath: "/roms/g1.zip"), name: "extra.txt"),
        ]
        let gamesByName = ["g1": DATGame(name: "g1", description: "g1", cloneOf: nil, romOf: nil, roms: [])]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: gamesByName, gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.count == 2)
        #expect(nodes.first { $0.isSurplusBucket }?.entries.count == 1)
    }

    @Test("a surplus entry from the SAME physical archive as a real game's own matched roms folds into that game's row")
    func surplusFromSameArchiveFoldsIntoRealGame() {
        // The real live case (jensyleo, 2026-08-13): a single physical
        // `gng.zip` partially matches "Ghosts'n Goblins (World? set 1)"
        // (most of its roms), but a couple of its roms are ALSO a
        // byte-for-byte duplicate of "set 2"'s own roms, becoming
        // game-less surplus entries with the exact same containing
        // archive path as "set 1"'s own matched roms. Those must fold
        // into "set 1"'s row — otherwise "gng.zip" shows up twice, once
        // matched and once "Duplicate", reading as if the file itself
        // were duplicated on disk when it's really one file serving
        // double duty.
        let archive = URL(fileURLWithPath: "/roms/gng.zip")
        let entries = [
            entry(status: .correct, game: "gng", path: archive, name: "gng.bin"),
            entry(status: .unknownFile, game: nil, path: archive, requiredByGameDescription: "Ghosts'n Goblins (World? set 2)", name: "extra.bin"),
        ]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.count == 1)
        #expect(nodes[0].entries.count == 2)
        #expect(!nodes[0].isSurplusBucket)
    }

    @Test("a surplus archive matching no known game becomes its own Unknown game row")
    func unrecognizedSurplusBecomesOwnRow() {
        let entries = [entry(status: .unknownFile, game: nil, path: URL(fileURLWithPath: "/roms/mystery.zip"), name: "junk.txt")]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes.count == 1)
        #expect(nodes[0].isSurplusBucket)
        #expect(nodes[0].aggregateStatus == .unknownFile)
    }

    @Test("a surplus archive with any identified content reads .incorrect (yellow) instead of .unknownFile (gray)")
    func identifiedSurplusReadsIncorrect() {
        let entries = [
            entry(status: .unknownFile, game: nil, path: URL(fileURLWithPath: "/roms/mystery.zip"), requiredByGameDescription: "Some Other Game", name: "identified.bin"),
        ]
        let nodes = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: [:], combineRomAndCHD: false, isFolderScoped: false)
        #expect(nodes[0].aggregateStatus == .incorrect)
    }

    @Test("computeUnknownArchivesCount counts only genuinely-unrecognized surplus buckets")
    func unknownArchivesCount() {
        let nodes = [
            GameNode(id: "1", name: "a", entries: [], aggregateStatus: .surplus, isSurplusBucket: true),
            GameNode(id: "2", name: "b", entries: [], aggregateStatus: .incorrect, isSurplusBucket: true),
            GameNode(id: "3", name: "c", entries: [], aggregateStatus: .correct, isSurplusBucket: false),
        ]
        #expect(GameNodeBuilder.computeUnknownArchivesCount(baseNodes: nodes) == 1)
    }

    @Test("computeScopedStatusCounts counts one per game, using the rom-only rollup")
    func scopedStatusCounts() {
        let entries = [
            entry(status: .correct, game: "g1"),
            entry(status: .missing, game: "g2"),
        ]
        let counts = GameNodeBuilder.computeScopedStatusCounts(scopedEntries: entries, gamesByName: [:])
        #expect(counts[.correct] == 1)
        #expect(counts[.missing] == 1)
    }

    @Test("computeScopedStatusCounts counts an orphaned-but-identified surplus archive under .incorrect")
    func scopedStatusCountsOrphanedIdentifiedArchive() {
        // An archive matching no `gamesByName` entry at all (e.g. a clone
        // excluded from `dat.games` under Merged mode), but containing
        // identified content (`requiredByGameDescription`/`.unverifiable`),
        // must still be counted toward the "Incorrect" button — the same
        // `hasAnyIdentifiedContent` check `gameNodes(from:)` uses to color
        // its row yellow instead of gray.
        let entries = [
            entry(status: .unknownFile, game: nil, path: URL(fileURLWithPath: "/roms/orphan.zip"), requiredByGameDescription: "Some Other Game", name: "identified.bin"),
        ]
        let counts = GameNodeBuilder.computeScopedStatusCounts(scopedEntries: entries, gamesByName: [:])
        #expect(counts[.incorrect] == 1)
    }

    @Test("isFolderScoped: true computes the row's true status from this folder's own roms, not the DAT-wide aggregate")
    func folderScopedStatusIgnoresDATWideAggregate() {
        // A game whose DAT-wide aggregate is .incorrect (part of its roms
        // live in a *different* folder) must still read green in THIS
        // folder if every rom actually physically here is correct —
        // otherwise a game reads red in folder A purely because part of
        // its set legitimately lives in folder B.
        let entries = [entry(status: .correct, game: "g1")]
        let aggregateByName = ["g1": AuditStatus.incorrect]

        let folderScoped = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: aggregateByName, combineRomAndCHD: false, isFolderScoped: true)
        #expect(folderScoped.first?.aggregateStatus == .correct)

        let datWideScoped = GameNodeBuilder.gameNodes(from: entries, gamesByName: [:], gameAggregateStatusByName: aggregateByName, combineRomAndCHD: false, isFolderScoped: false)
        #expect(datWideScoped.first?.aggregateStatus == .incorrect)
    }

    @Test("recomputeGamesInFolder returns only games with a real file physically inside the folder")
    func gamesInFolder() {
        let folder = URL(fileURLWithPath: "/roms/neogeo")
        let entries = [
            entry(status: .correct, game: "inside", path: folder.appendingPathComponent("inside.zip")),
            entry(status: .correct, game: "outside", path: URL(fileURLWithPath: "/roms/other/outside.zip")),
        ]
        #expect(GameNodeBuilder.recomputeGamesInFolder(entries: entries, selectedFolder: folder) == ["inside"])
    }

    @Test("scoped(_:) with a rom folder keeps only entries physically inside it or games already known to be in it")
    func scopedByFolder() {
        let folder = URL(fileURLWithPath: "/roms/neogeo")
        let entries = [
            entry(status: .correct, game: "g1", path: folder.appendingPathComponent("g1.zip")),
            entry(status: .missing, game: "g1"),
            entry(status: .correct, game: "g2", path: URL(fileURLWithPath: "/roms/other/g2.zip")),
        ]
        let result = GameNodeBuilder.scoped(entries, databaseCategory: nil, romFolder: folder, gamesInFolder: ["g1"])
        #expect(result.map(\.game) == ["g1", "g1"])
    }

    @Test("unscannedCatalogNodes builds a row per DAT game with no scan result yet")
    func unscannedCatalogFromDAT() {
        let games = [DATGame(name: "g1", description: "Game One", cloneOf: nil, romOf: nil, roms: [])]
        let nodes = GameNodeBuilder.unscannedCatalogNodes(matching: .allGames, preloadedGames: games)
        #expect(nodes.count == 1)
        #expect(nodes[0].aggregateStatus == nil)
        #expect(nodes[0].gameName == "Game One")
    }

    @Test("unscannedCatalogNodes is honestly empty for a scan-result-only category")
    func unscannedCatalogEmptyForScanOnlyCategory() {
        let games = [DATGame(name: "g1", description: "Game One", cloneOf: nil, romOf: nil, roms: [])]
        #expect(GameNodeBuilder.unscannedCatalogNodes(matching: .missingGames, preloadedGames: games).isEmpty)
        #expect(GameNodeBuilder.unscannedCatalogNodes(matching: .completeGames, preloadedGames: games).isEmpty)
    }
}
