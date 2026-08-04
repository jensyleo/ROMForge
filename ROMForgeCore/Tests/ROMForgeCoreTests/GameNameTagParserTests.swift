// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameNameTagParser")
struct GameNameTagParserTests {
    @Test("reads a single region tag")
    func readsSingleRegion() {
        let tags = GameNameTagParser.parse(name: "Sonic the Hedgehog (USA)")
        #expect(tags.region == "USA")
        #expect(tags.languages.isEmpty)
    }

    @Test("reads region and a language list in separate tag groups")
    func readsRegionAndLanguages() {
        let tags = GameNameTagParser.parse(name: "Final Fantasy VII (Europe) (En,Fr,De,Es,It)")
        #expect(tags.region == "Europe")
        #expect(tags.languages == ["En", "Fr", "De", "Es", "It"])
    }

    @Test("ignores unrelated tags like revision numbers")
    func ignoresUnrelatedTags() {
        let tags = GameNameTagParser.parse(name: "Chrono Trigger (Japan) (Rev 1)")
        #expect(tags.region == "Japan")
        #expect(tags.languages.isEmpty)
    }

    @Test("recognizes World as a region")
    func recognizesWorldRegion() {
        #expect(GameNameTagParser.parse(name: "Tetris (World)").region == "World")
    }

    @Test("returns nil region and no languages when there are no recognizable tags")
    func returnsEmptyWhenNoTags() {
        let tags = GameNameTagParser.parse(name: "Homebrew Demo")
        #expect(tags.region == nil)
        #expect(tags.languages.isEmpty)
    }
}
