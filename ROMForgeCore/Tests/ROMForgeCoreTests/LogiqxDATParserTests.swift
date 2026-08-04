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
}
