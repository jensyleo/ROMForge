// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("LogiqxDATParser")
struct LogiqxDATParserTests {
    @Test("parses header and games from a well-formed Logiqx DAT")
    func parsesWellFormedDAT() throws {
        let xml = """
        <?xml version="1.0"?>
        <datafile>
            <header>
                <name>Test System</name>
                <description>Test System DAT</description>
                <version>1.0</version>
                <author>ROMForge Tests</author>
            </header>
            <game name="Super Game (USA)" cloneof="Super Game (Japan)" romof="Super Game (Japan)">
                <description>Super Game (USA)</description>
                <rom name="Super Game (USA).sfc" size="1048576" crc="ABCD1234" md5="d41d8cd98f00b204e9800998ecf8427e" sha1="da39a3ee5e6b4b0d3255bfef95601890afd80709"/>
            </game>
            <game name="Another Game (Japan)">
                <description>Another Game (Japan)</description>
                <rom name="Another Game (Japan).sfc" size="2097152" crc="1234ABCD"/>
            </game>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))

        #expect(dat.header.name == "Test System")
        #expect(dat.header.version == "1.0")
        #expect(dat.games.count == 2)

        let superGame = try #require(dat.games.first { $0.name == "Super Game (USA)" })
        #expect(superGame.cloneOf == "Super Game (Japan)")
        #expect(superGame.roms.count == 1)
        #expect(superGame.roms[0].size == 1_048_576)
        #expect(superGame.roms[0].crc == "abcd1234", "CRC should be normalized to lowercase")

        let anotherGame = try #require(dat.games.first { $0.name == "Another Game (Japan)" })
        #expect(anotherGame.cloneOf == nil)
        #expect(anotherGame.roms[0].md5 == nil)
    }

    @Test("resolves No-Intro's numeric cloneofid to the parent's own name, clone appearing before its parent in the file")
    func resolvesCloneOfIdRegardlessOfDocumentOrder() throws {
        // Real structure confirmed 2026-09-29 against a freshly-downloaded
        // No-Intro NES DAT (DAT-o-MATIC schema v4): parent/clone is declared
        // via a numeric `cloneofid` referencing another `<game>`'s own
        // numeric `id`, not the classic Logiqx `cloneof="<name>"` — and a
        // clone can appear before its own parent in the file, exactly as
        // reproduced here.
        let xml = """
        <?xml version="1.0"?>
        <datafile>
            <header>
                <name>Test System</name>
                <description>Test System DAT</description>
                <version>1.0</version>
                <author>ROMForge Tests</author>
            </header>
            <game name="10-Yard Fight (Japan) (En)" id="0002" cloneofid="0003">
                <description>10-Yard Fight (Japan) (En)</description>
                <rom name="10-Yard Fight (Japan) (En).nes" size="24592" crc="44aa3eeb"/>
            </game>
            <game name="10-Yard Fight (USA, Europe)" id="0003">
                <description>10-Yard Fight (USA, Europe)</description>
                <rom name="10-Yard Fight (USA, Europe).nes" size="40976" crc="c986cda2"/>
            </game>
            <game name="Standalone Game" id="0004">
                <description>Standalone Game</description>
                <rom name="Standalone Game.nes" size="16384" crc="00000000"/>
            </game>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))

        let clone = try #require(dat.games.first { $0.name == "10-Yard Fight (Japan) (En)" })
        #expect(clone.cloneOf == "10-Yard Fight (USA, Europe)")

        let parent = try #require(dat.games.first { $0.name == "10-Yard Fight (USA, Europe)" })
        #expect(parent.cloneOf == nil)

        let standalone = try #require(dat.games.first { $0.name == "Standalone Game" })
        #expect(standalone.cloneOf == nil)

        #expect(dat.hasClones)
    }

    @Test("a game's own by-name cloneof attribute wins over a stray cloneofid, if both are somehow present")
    func nameBasedCloneOfTakesPrecedenceOverCloneOfId() throws {
        let xml = """
        <?xml version="1.0"?>
        <datafile>
            <header>
                <name>Test System</name>
                <description>Test System DAT</description>
                <version>1.0</version>
                <author>ROMForge Tests</author>
            </header>
            <game name="Clone" id="0001" cloneof="Explicit Parent Name" cloneofid="0002">
                <description>Clone</description>
                <rom name="Clone.nes" size="16384" crc="00000000"/>
            </game>
            <game name="Other Parent" id="0002">
                <description>Other Parent</description>
                <rom name="Other Parent.nes" size="16384" crc="11111111"/>
            </game>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))
        let clone = try #require(dat.games.first { $0.name == "Clone" })
        #expect(clone.cloneOf == "Explicit Parent Name")
    }

    @Test("throws on malformed XML")
    func throwsOnMalformedXML() {
        let xml = "<datafile><header><name>Broken</name>"
        #expect(throws: DATParsingError.self) {
            try LogiqxDATParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("throws when the root <datafile> element is missing")
    func throwsWhenRootElementMissing() {
        let xml = "<somethingElse></somethingElse>"
        #expect(throws: DATParsingError.missingRootElement) {
            try LogiqxDATParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("throws when a <rom> is missing its size attribute")
    func throwsWhenRomMissingSize() {
        let xml = """
        <datafile>
            <header><name>T</name><description>T</description><version>1</version><author>A</author></header>
            <game name="G"><description>G</description><rom name="g.bin" crc="00000000"/></game>
        </datafile>
        """
        #expect(throws: DATParsingError.self) {
            try LogiqxDATParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("parses rom status, <disk>, and <sample>")
    func parsesDumpStatusDisksAndSamples() throws {
        let xml = """
        <datafile>
            <header><name>T</name><description>T</description><version>1</version><author>A</author></header>
            <game name="G">
                <description>G</description>
                <rom name="good.bin" size="1" crc="00000000"/>
                <rom name="bad.bin" size="1" crc="11111111" status="baddump"/>
                <rom name="none.bin" size="1" crc="22222222" status="nodump"/>
                <disk name="g" sha1="da39a3ee5e6b4b0d3255bfef95601890afd80709"/>
                <sample name="explosion"/>
            </game>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))
        let game = try #require(dat.games.first)

        #expect(game.roms[0].status == .good)
        #expect(game.roms[1].status == .baddump)
        #expect(game.roms[2].status == .nodump)
        #expect(game.disks.count == 1)
        #expect(game.disks[0].name == "g")
        #expect(game.disks[0].sha1 == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(game.hasSamples == true)
    }

    @Test("parses No-Intro DAT-o-MATIC v4's own extra fields — <category>, rom serial/sha256/header — confirmed against a real freshly-downloaded NES DAT (2026-09-29)")
    func parsesCategorySerialSha256AndHeader() throws {
        let xml = """
        <datafile>
            <header><name>T</name><description>T</description><version>1</version><author>A</author></header>
            <game name="G">
                <category>Games</category>
                <description>G</description>
                <rom name="g.nes" size="1" crc="00000000" sha256="aa" serial="DIF-001" header="4E 45 53 1A"/>
            </game>
            <game name="H">
                <description>H</description>
                <rom name="h.nes" size="1" crc="00000000"/>
            </game>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))
        let g = try #require(dat.games.first { $0.name == "G" })
        let h = try #require(dat.games.first { $0.name == "H" })

        #expect(g.category == "Games")
        #expect(g.roms[0].sha256 == "aa")
        #expect(g.roms[0].serial == "DIF-001")
        #expect(g.roms[0].header == "4E 45 53 1A")
        // A game/rom that declares none of these stays `nil`, not an
        // empty string — same "absent means absent" convention every
        // other optional DAT field here follows.
        #expect(h.category == nil)
        #expect(h.roms[0].sha256 == nil)
        #expect(h.roms[0].serial == nil)
        #expect(h.roms[0].header == nil)
    }

    @Test("throws missingHeader when <datafile> has a game but no <header> at all")
    func throwsMissingHeaderWhenHeaderAbsent() {
        let xml = """
        <datafile>
            <game name="G"><description>G</description><rom name="g.bin" size="1" crc="00000000"/></game>
        </datafile>
        """
        #expect(throws: DATParsingError.missingHeader) {
            try LogiqxDATParser.parse(data: Data(xml.utf8))
        }
    }

    @Test("a well-formed DAT with a header but zero games parses successfully to an empty game list")
    func parsesEmptyDATSuccessfully() throws {
        let xml = """
        <datafile>
            <header><name>Empty</name><description>Empty</description><version>1</version><author>A</author></header>
        </datafile>
        """
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))
        #expect(dat.header.name == "Empty")
        #expect(dat.games.isEmpty)
    }

    @Test("fast-rejects real MAME -listxml (<mame> root) instead of parsing the whole document")
    func fastRejectsRealMAMEListXMLRoot() {
        // `throwsWhenRootElementMissing` above proves the general
        // `missingRootElement` error fires for garbage XML — this proves
        // the SPECIFIC fast-abort-on-first-element path (added to avoid a
        // multi-minute full parse-then-discard of a real, huge MAME DAT)
        // actually fires for genuine MAME `-listxml` structure, not just
        // any wrong root name.
        let xml = """
        <mame build="0.288">
            <machine name="foo">
                <rom name="a.bin" size="1" crc="00000000"/>
            </machine>
        </mame>
        """
        #expect(throws: DATParsingError.missingRootElement) {
            try LogiqxDATParser.parse(data: Data(xml.utf8))
        }
    }
}
