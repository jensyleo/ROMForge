// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameNode.detailBadges")
struct GameDetailsTests {
    private func game(
        _ name: String, driverStatus: String? = nil, displayType: String? = nil, displayRotate: String? = nil,
        players: String? = nil, coins: String? = nil
    ) -> DATGame {
        DATGame(
            name: name, description: name, cloneOf: nil, romOf: nil, roms: [],
            driverStatus: driverStatus, displayType: displayType, displayRotate: displayRotate, players: players, coins: coins
        )
    }

    private func node(_ game: DATGame) -> GameNode {
        GameNode(id: game.name, name: game.name, entries: [], aggregateStatus: nil, sourceGame: game)
    }

    @Test("a game with no descriptive metadata gets no detail badges")
    func noDetails() {
        #expect(node(game("pacman")).detailBadges.isEmpty)
    }

    @Test("a driver status yields a bare Emulation badge naming the exact status in its tooltip")
    func driverStatusBadge() {
        let badges = node(game("mslug", driverStatus: "imperfect")).detailBadges
        #expect(badges.map(\.kind) == [.driverStatus])
        #expect(badges[0].label == "Emulation")
        #expect(badges[0].tooltip == "MAME driver status: Imperfect")
    }

    @Test("a horizontal raster display yields a bare Display badge with orientation and type in its tooltip")
    func horizontalDisplayBadge() {
        let badges = node(game("mslug", displayType: "raster", displayRotate: "0")).detailBadges
        #expect(badges.map(\.kind) == [.display])
        #expect(badges[0].label == "Display")
        #expect(badges[0].tooltip == "Orientation: Horizontal\nType: Raster")
    }

    @Test("a vertical-rotated display (90/270) names Vertical in its tooltip")
    func verticalDisplayBadge() {
        #expect(node(game("dkong", displayRotate: "90")).detailBadges.first?.tooltip == "Orientation: Vertical")
        #expect(node(game("galaga", displayRotate: "270")).detailBadges.first?.tooltip == "Orientation: Vertical")
    }

    @Test("a vector display is named in its tooltip like any other type")
    func vectorDisplayBadge() {
        let badges = node(game("asteroid", displayType: "vector", displayRotate: "0")).detailBadges
        #expect(badges[0].tooltip == "Orientation: Horizontal\nType: Vector")
    }

    @Test("players and a real coin count yield a bare Players badge naming both in its tooltip")
    func playersAndCoinsBadge() {
        let badges = node(game("mslug", players: "2", coins: "1")).detailBadges
        #expect(badges.map(\.kind) == [.players])
        #expect(badges[0].label == "Players")
        #expect(badges[0].tooltip == "2 players\n1 coin slot")
    }

    @Test("a single player is worded in the singular in the tooltip")
    func singlePlayerBadge() {
        let badges = node(game("pacman", players: "1", coins: "1")).detailBadges
        #expect(badges[0].label == "Players")
        #expect(badges[0].tooltip == "1 player\n1 coin slot")
    }

    @Test("zero coins reads as Free Play rather than a bare coin count")
    func freePlayBadge() {
        let badges = node(game("freeplaygame", players: "1", coins: "0")).detailBadges
        #expect(badges[0].tooltip == "1 player\nFree Play (no coin mechanism)")
    }

    @Test("a game can carry all three detail badges at once, in a fixed order")
    func allThreeBadges() {
        let badges = node(game(
            "mslug", driverStatus: "good", displayType: "raster", displayRotate: "0", players: "2", coins: "1"
        )).detailBadges
        #expect(badges.map(\.kind) == [.driverStatus, .display, .players])
    }

    @Test("a clone gets its own detail badges independently of its parent")
    func cloneGetsOwnBadges() {
        let clone = DATGame(name: "mslugx", description: "Metal Slug X", cloneOf: "mslug", romOf: "mslug", roms: [], driverStatus: "imperfect")
        #expect(node(clone).detailBadges.map(\.kind) == [.driverStatus])
    }

    @Test("the synthetic surplus-files bucket never gets detail badges")
    func surplusBucketNoBadges() {
        var node = GameNode(id: "surplus", name: "Surplus files", entries: [], aggregateStatus: nil)
        node.isSurplusBucket = true
        #expect(node.detailBadges.isEmpty)
    }

    @Test("a CHD disk row never gets detail badges of its own")
    func diskRowNoBadges() {
        var node = node(game("mslug", driverStatus: "good"))
        node.isDiskRow = true
        #expect(node.detailBadges.isEmpty)
    }
}
