// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Testing
@testable import ROMForgeCore

@Suite("GameNameDetails")
struct GameNameDetailsTests {
    @Test func decodesRegionLanguagesRevisionAndStage() {
        let d = GameNameDetails.parse(name: "Foo (Europe) (En,Fr,De) (Rev 1) (Beta 2) (Virtual Console) (Unl)")
        #expect(d.regions == ["Europe"])
        #expect(d.languages == ["English", "French", "German"])
        #expect(d.revision == "1")
        #expect(d.releaseStage == "Beta 2")
        #expect(d.distribution == ["Virtual Console"])
        #expect(d.flags == ["Unlicensed"])
        #expect(d.videoStandard == "PAL (50 Hz)")
    }

    @Test func tiedRegionsAndPlatformScoping() {
        let note = RegionQualityNotes.note(forGameName: "Contra III - The Alien Wars (USA)", platform: "SNES")
        #expect(note?.bestRegionsLabel == "Japan or USA")
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "SNES") == nil)
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "NES") != nil)
    }
}
