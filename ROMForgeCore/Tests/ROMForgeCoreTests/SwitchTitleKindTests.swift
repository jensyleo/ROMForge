// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("SwitchTitleKind")
struct SwitchTitleKindTests {
    @Test("the Title ID suffix decides base, update or DLC", arguments: [
        ("Super Mario Odyssey [0100000000010000][v0].nsp", "Base"),
        ("Super Mario Odyssey [0100000000010800][v393216][US](nsw2u.com).nsp", "Update 6"),
        ("Super Smash Bros. Ultimate (01006A800016E000)(v0).nsp", "Base"),
        ("The Legend of Zelda Breath of the Wild [DLC Pack 1] [01007EF00011F001][v196608].nsp", "DLC: Pack 1"),
        ("Luigi’s Mansion 3 [Luigi’s Mansion 3 Multiplayer Pack 1][0100DCA0064A7001][US][v131072].nsp", "DLC: Multiplayer Pack 1"),
        ("Contra Operation Galuga [Contra Operation Galuga Early-purchase Bonus DLC][0100CF401A98F001][v0][US](nsw2u.com).nsp", "DLC: Early-purchase Bonus"),
        ("LEGO Star Wars - The Skywalker Saga [DLC Andor Character Pack][010042D00D901017][v0].nsp", "DLC: Andor Character Pack"),
        ("Game [0100AAAAAAAAB001][v0][US].nsp", "DLC"),
        ("Minecraft [0100D71004694800][v10485760][Up v1.26.45].nsp", "Update 160"),
        ("Teenage Mutant Ninja Turtles v1.0.9[0100FE701475A800][589824][UPD].nsp", "Update 9"),
        ("Odd Game [0100AAAAAAAAA800][v70000].nsp", "Update v70000"),
        ("Odd Game [0100AAAAAAAAA800].nsp", "Update"),
    ])
    func labels(fileName: String, expected: String) {
        #expect(SwitchTitleKind(fileName: fileName)?.label == expected)
    }

    @Test("a name without a Title ID has no kind")
    func noTitleID() {
        #expect(SwitchTitleKind(fileName: "Minecraft_v0_switch-xci.com.nsp") == nil)
    }

    @Test("base sorts before update, update before DLC")
    func sortOrder() {
        let names = [
            "Game [DLC A][0100AAAAAAAAB001][v0].nsp",
            "Game [0100AAAAAAAAA800][v65536].nsp",
            "Game [0100AAAAAAAAA000][v0].nsp",
        ]
        let ranks = names.compactMap { SwitchTitleKind(fileName: $0)?.sortRank }
        #expect(ranks == [2, 1, 0])
    }

    @Test("the game summary reports the update state and the DLC count")
    func gameSummary() {
        let base = (name: "Game [0100AAAAAAAAA000][v0].nsp", isPresent: true)
        let update6 = (name: "Game [0100AAAAAAAAA800][v393216].nsp", isPresent: true)
        let update11Missing = (name: "Game [0100AAAAAAAAA800][v720896].nsp", isPresent: false)
        let dlc = (name: "Game [DLC Pack][0100AAAAAAAAB001][v0].nsp", isPresent: true)

        #expect(SwitchGameSummary.text(files: [base]) == nil)
        #expect(SwitchGameSummary.text(files: [base, update6, dlc, dlc]) == "Update 6 · 2 DLC")
        #expect(SwitchGameSummary.text(files: [base, update6, update11Missing]) == "Update 11 available (have 6)")
        #expect(SwitchGameSummary.text(files: [base, update11Missing, dlc]) == "Update 11 available (none installed) · 1 DLC")
    }
}
