// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("SoftwareListParser")
struct SoftwareListParserTests {
    @Test("parses a single-part cartridge software entry")
    func parsesSinglePartCartridge() throws {
        let xml = """
        <?xml version="1.0"?>
        <softwarelist name="pasogo" description="PasoGo cartridges">
            <software name="taikyoku" cloneof="taikyoku1">
                <description>Taikyoku-kun I</description>
                <year>1996</year>
                <publisher>Koei</publisher>
                <info name="serial" value="KS-1001"/>
                <part name="cart" interface="pasogo_cart">
                    <dataarea name="rom" size="1048576">
                        <rom name="ks-1001.ic4" size="1048576" crc="2753bb6c" sha1="3603e9ab6d4861a26343f03129eec58f7b5a34f5"/>
                    </dataarea>
                </part>
            </software>
        </softwarelist>
        """
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))

        #expect(dataset.name == "pasogo")
        #expect(dataset.software.count == 1)

        let software = try #require(dataset.software.first)
        #expect(software.name == "taikyoku")
        #expect(software.cloneOf == "taikyoku1")
        #expect(software.description == "Taikyoku-kun I")
        #expect(software.parts.count == 1)
        #expect(software.parts[0].interface == "pasogo_cart")
        #expect(software.allRoms.count == 1)
        #expect(software.allRoms[0].crc == "2753bb6c")
    }

    @Test("flattens roms across multiple parts, e.g. a multi-disc software")
    func flattensMultiplePartsIntoOneSoftware() throws {
        let xml = """
        <softwarelist name="ibm5170_cdrom">
            <software name="11hourd" supported="no">
                <description>The 11th Hour (Germany)</description>
                <year>1995</year>
                <publisher>Virgin</publisher>
                <part name="cdrom1" interface="cdrom">
                    <diskarea name="cdrom">
                        <disk name="11th hour (disc 1 of 2)" sha1="eb0471c3d431dee4b5bcbc2811af6a474b63ac6d"/>
                    </diskarea>
                </part>
                <part name="cdrom2" interface="cdrom">
                    <diskarea name="cdrom">
                        <disk name="11th hour (disc 2 of 2)" sha1="0000000000000000000000000000000000000a"/>
                    </diskarea>
                </part>
            </software>
        </softwarelist>
        """
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))
        let software = try #require(dataset.software.first)

        #expect(software.parts.count == 2)
        #expect(software.allDisks.count == 2)
        #expect(software.allDisks.map(\.name).sorted() == ["11th hour (disc 1 of 2)", "11th hour (disc 2 of 2)"])
    }

    @Test("skips rom entries with no name/size (loadflag continuation/fill entries) instead of throwing")
    func skipsRomsWithoutNameOrSize() throws {
        let xml = """
        <softwarelist name="test">
            <software name="game1">
                <description>Game</description>
                <year>1990</year>
                <publisher>Pub</publisher>
                <part name="cart" interface="test_cart">
                    <dataarea name="rom" size="4">
                        <rom name="game1.bin" size="2" crc="00000000" offset="0"/>
                        <rom size="2" loadflag="continue"/>
                    </dataarea>
                </part>
            </software>
        </softwarelist>
        """
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))
        let software = try #require(dataset.software.first)
        #expect(software.allRoms.count == 1, "the nameless continuation rom should be skipped, not cause a throw")
        #expect(software.allRoms[0].name == "game1.bin")
    }

    @Test("parses a rom's baddump status")
    func parsesBadDumpStatus() throws {
        let xml = """
        <softwarelist name="test">
            <software name="game1">
                <description>Game</description>
                <year>1990</year>
                <publisher>Pub</publisher>
                <part name="cart" interface="test_cart">
                    <dataarea name="rom" size="2">
                        <rom name="game1.bin" size="2" crc="00000000" status="baddump"/>
                    </dataarea>
                </part>
            </software>
        </softwarelist>
        """
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))
        #expect(dataset.software.first?.allRoms.first?.status == .baddump)
    }

    @Test("flattens roms across multiple <dataarea> elements within a single <part> — e.g. cartridge ROM plus battery-backed nvram")
    func flattensMultipleDataareasWithinOnePart() throws {
        let xml = """
        <softwarelist name="test">
            <software name="game1">
                <description>Game</description>
                <year>1990</year>
                <publisher>Pub</publisher>
                <part name="cart" interface="test_cart">
                    <dataarea name="rom" size="2">
                        <rom name="game1.bin" size="2" crc="00000000"/>
                    </dataarea>
                    <dataarea name="nvram" size="1">
                        <rom name="game1.nv" size="1" crc="11111111"/>
                    </dataarea>
                </part>
            </software>
        </softwarelist>
        """
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))
        let software = try #require(dataset.software.first)

        #expect(software.parts.count == 1)
        #expect(software.allRoms.count == 2, "roms from both <dataarea> siblings should be flattened, not just the first")
        #expect(Set(software.allRoms.map(\.name)) == ["game1.bin", "game1.nv"])
    }

    @Test("a well-formed <softwarelist> with zero <software> entries parses successfully to an empty list")
    func parsesEmptySoftwareListSuccessfully() throws {
        let xml = "<softwarelist name=\"empty\" description=\"Nothing here\"></softwarelist>"
        let dataset = try SoftwareListParser.parse(data: Data(xml.utf8))
        #expect(dataset.name == "empty")
        #expect(dataset.software.isEmpty)
    }

    @Test("throws when the root <softwarelist> element is missing")
    func throwsWhenRootElementMissing() {
        #expect(throws: SoftwareListParsingError.missingRootElement) {
            try SoftwareListParser.parse(data: Data("<somethingElse></somethingElse>".utf8))
        }
    }

    @Test("throws on malformed XML")
    func throwsOnMalformedXML() {
        #expect(throws: SoftwareListParsingError.self) {
            try SoftwareListParser.parse(data: Data("<softwarelist><software name=\"x\">".utf8))
        }
    }
}
