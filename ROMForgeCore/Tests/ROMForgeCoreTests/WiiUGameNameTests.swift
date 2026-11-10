// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("Wii U (WUX) game names")
struct WiiUGameNameTests {
    @Test("a WUP disc-ID description shows the DAT game name, not the ID")
    func wupDescriptionUsesGameName() {
        let game = DATGame(name: "Ben 10 - Omniverse 2 (Europe) (En,Fr,De,Es,It)", description: "Game ID: WUP-P-ABVP-00-301EUR-0, Disc CRC: 433FE85C", cloneOf: nil, romOf: nil, roms: [])
        let entry = AuditEntry(status: .correct, game: game.name, gameDescription: game.description, name: "x.wux", path: URL(fileURLWithPath: "/roms/x.wux"))
        let node = GameNode(id: "g", name: game.name, entries: [entry], aggregateStatus: .correct, sourceGame: game)
        #expect(node.gameName == "Ben 10 - Omniverse 2 (Europe) (En,Fr,De,Es,It)")
    }

    @Test("other descriptions are unchanged")
    func otherDescriptionsUnchanged() {
        let game = DATGame(name: "pacman", description: "Pac-Man (Set 1)", cloneOf: nil, romOf: nil, roms: [])
        let entry = AuditEntry(status: .correct, game: game.name, gameDescription: game.description, name: "pacman.zip", path: URL(fileURLWithPath: "/roms/pacman.zip"))
        let node = GameNode(id: "g", name: game.name, entries: [entry], aggregateStatus: .correct, sourceGame: game)
        #expect(node.gameName == "Pac-Man (Set 1)")
    }
}
