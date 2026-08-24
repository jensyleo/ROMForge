// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("OneGameOneROMSelector")
struct OneGameOneROMSelectorTests {
    private func game(_ name: String, _ description: String, cloneOf: String? = nil) -> DATGame {
        DATGame(name: name, description: description, cloneOf: cloneOf, romOf: cloneOf, roms: [])
    }

    // MARK: - detectedRegion

    @Test("finds a region token among a description's parenthesized groups")
    func detectsRegion() {
        let region = OneGameOneROMSelector.detectedRegion(
            inDescription: "Street Fighter II (USA)", order: RegionCatalog.defaultOrder
        )
        #expect(region == "USA")
    }

    @Test("picks the best-ranked region when multiple groups each carry one")
    func picksBestRankedRegion() {
        let region = OneGameOneROMSelector.detectedRegion(
            inDescription: "Sonic the Hedgehog (Japan) (Europe)", order: ["World", "USA", "Europe", "Japan"]
        )
        #expect(region == "Europe")
    }

    @Test("picks the best-ranked region among comma-separated tokens in one group")
    func picksBestRankedRegionAcrossCommaList() {
        let region = OneGameOneROMSelector.detectedRegion(
            inDescription: "Sonic the Hedgehog (Japan, Europe)", order: ["World", "USA", "Europe", "Japan"]
        )
        #expect(region == "Europe")
    }

    @Test("is case-insensitive")
    func isCaseInsensitive() {
        let region = OneGameOneROMSelector.detectedRegion(inDescription: "Some Game (usa)", order: RegionCatalog.defaultOrder)
        #expect(region == "USA")
    }

    @Test("returns nil when no parenthesized token matches a known region")
    func noMatchYieldsNil() {
        let region = OneGameOneROMSelector.detectedRegion(inDescription: "Some Game (Rev A)", order: RegionCatalog.defaultOrder)
        #expect(region == nil)
    }

    @Test("returns nil for a description with no parentheses at all")
    func noParensYieldsNil() {
        let region = OneGameOneROMSelector.detectedRegion(inDescription: "Some Game", order: RegionCatalog.defaultOrder)
        #expect(region == nil)
    }

    @Test("recognizes a region even when a revision date is appended with no comma, as real MAME descriptions do")
    func recognizesRegionWithTrailingRevisionDate() {
        let region = OneGameOneROMSelector.detectedRegion(
            inDescription: "Street Fighter II: The World Warrior (World 910522)", order: RegionCatalog.defaultOrder
        )
        #expect(region == "World")
    }

    @Test("does not treat a word that merely starts with a region name as a match")
    func rejectsPartialWordMatch() {
        let region = OneGameOneROMSelector.detectedRegion(inDescription: "Some Game (Worldwide)", order: RegionCatalog.defaultOrder)
        #expect(region == nil)
    }

    // MARK: - compute

    @Test("picks the higher-priority region as the family's preferred game")
    func picksPreferredByRegionOrder() {
        let games = [
            game("sf2u", "Street Fighter II (USA)"),
            game("sf2j", "Street Fighter II (Japan)", cloneOf: "sf2u"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames == ["sf2u"])
        #expect(summary.hiddenWhenFilteredNames == ["sf2j"])
    }

    @Test("a custom region order changes which variant wins")
    func customOrderChangesWinner() {
        let games = [
            game("sf2u", "Street Fighter II (USA)"),
            game("sf2j", "Street Fighter II (Japan)", cloneOf: "sf2u"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: ["Japan", "USA"])
        #expect(summary.preferredGameNames == ["sf2j"])
        #expect(summary.hiddenWhenFilteredNames == ["sf2u"])
    }

    @Test("a family with no recognized region at all hides nothing and stars nothing")
    func noRecognizedRegionHidesNothing() {
        let games = [
            game("g1", "Some Game (Rev A)"),
            game("g1a", "Some Game (Alt)", cloneOf: "g1"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames.isEmpty)
        #expect(summary.hiddenWhenFilteredNames.isEmpty)
    }

    @Test("an unrecognized variant inside an otherwise-recognized family stays visible, never hidden")
    func unrecognizedVariantNeverHidden() {
        let games = [
            game("sf2u", "Street Fighter II (USA)"),
            game("sf2p", "Street Fighter II (Prototype)", cloneOf: "sf2u"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames == ["sf2u"])
        #expect(summary.hiddenWhenFilteredNames.isEmpty)
    }

    @Test("a lone game (no clone family) is never marked preferred or hidden")
    func loneGameNeverMarked() {
        let games = [game("pacman", "Pac-Man (World)")]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames.isEmpty)
        #expect(summary.hiddenWhenFilteredNames.isEmpty)
    }

    @Test("a family of three picks the single best-ranked winner and hides the other two")
    func familyOfThree() {
        let games = [
            game("g", "Game (Europe)"),
            game("ga", "Game (USA)", cloneOf: "g"),
            game("gb", "Game (Japan)", cloneOf: "g"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames == ["ga"])
        #expect(summary.hiddenWhenFilteredNames == ["g", "gb"])
    }

    @Test("empty region order yields an empty summary")
    func emptyOrderYieldsEmpty() {
        let games = [game("sf2u", "Street Fighter II (USA)"), game("sf2j", "Street Fighter II (Japan)", cloneOf: "sf2u")]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: [])
        #expect(summary == .empty)
    }

    @Test("a real MAME sf2 family (region + trailing revision date, no comma) still gets a winner and hidden clones")
    func realMameSf2FamilyStillResolves() {
        let games = [
            game("sf2", "Street Fighter II: The World Warrior (World 910522)"),
            game("sf2u", "Street Fighter II: The World Warrior (USA 910228)", cloneOf: "sf2"),
            game("sf2j", "Street Fighter II: The World Warrior (Japan 910522)", cloneOf: "sf2"),
        ]
        let summary = OneGameOneROMSelector.compute(games: games, regionOrder: RegionCatalog.defaultOrder)
        #expect(summary.preferredGameNames == ["sf2"])
        #expect(summary.hiddenWhenFilteredNames == ["sf2u", "sf2j"])
    }

    @Test("empty games list yields an empty summary")
    func emptyGamesYieldsEmpty() {
        let summary = OneGameOneROMSelector.compute(games: [], regionOrder: RegionCatalog.defaultOrder)
        #expect(summary == .empty)
    }
}
