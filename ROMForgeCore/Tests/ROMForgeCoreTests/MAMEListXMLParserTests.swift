// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("MAMEListXMLParser")
struct MAMEListXMLParserTests {
    private let xml = """
    <?xml version="1.0"?>
    <mame build="0.278">
        <machine name="neogeo" isbios="yes">
            <description>Neo-Geo</description>
            <year>1990</year>
            <manufacturer>SNK</manufacturer>
            <rom name="sp-s2.sp1" size="131072" crc="9036d879" sha1="4f210adf5ba0a67c766c3f0c8dda389c9c4d3e1a"/>
        </machine>
        <machine name="mslug" romof="neogeo">
            <description>Metal Slug</description>
            <year>1996</year>
            <manufacturer>SNK</manufacturer>
            <biosset name="neogeo" description="Neo-Geo (Asia, MVS)"/>
            <rom name="038-p1.p1" size="524288" crc="1e174290" sha1="c2ea0388270d939281839f57bbfc93a1f5b715e5"/>
            <rom name="v1.v1" size="1" crc="00000000" status="baddump"/>
            <disk name="mslug" sha1="7c9e8a7e372e08c93c81b8ceb18e731e26f4cbb2"/>
            <sample name="jump"/>
            <device_ref name="hd6301"/>
            <chip type="cpu" tag="maincpu" name="Motorola 68000" clock="12000000"/>
            <chip type="audio" tag="ymsnd" name="Yamaha YM2610" clock="8000000"/>
        </machine>
        <machine name="mslugx" cloneof="mslug" romof="mslug">
            <description>Metal Slug X</description>
            <year>1999</year>
            <manufacturer>SNK</manufacturer>
            <rom name="201-p1.p1" size="524288" crc="2c37b0f7" sha1="0000000000000000000000000000000000000a"/>
            <rom name="038-p1.p1" size="524288" crc="1e174290" sha1="c2ea0388270d939281839f57bbfc93a1f5b715e5" merge="038-p1.p1"/>
        </machine>
    </mame>
    """

    @Test("parses machines with BIOS, parent/clone and hardware metadata")
    func parsesMachinesWithMetadata() throws {
        let dataset = try MAMEListXMLParser.parse(data: Data(xml.utf8))
        #expect(dataset.machines.count == 3)

        let bios = try #require(dataset.machine(named: "neogeo"))
        #expect(bios.isBios == true)
        #expect(bios.romOf == nil)
        #expect(bios.roms.count == 1)

        let parent = try #require(dataset.machine(named: "mslug"))
        #expect(parent.romOf == "neogeo")
        #expect(parent.cloneOf == nil)
        #expect(parent.biosSets == [MAMEBiosSet(name: "neogeo", description: "Neo-Geo (Asia, MVS)")])
        #expect(parent.disks == [MAMEDisk(name: "mslug", sha1: "7c9e8a7e372e08c93c81b8ceb18e731e26f4cbb2")])
        #expect(parent.deviceRefs == ["hd6301"])
        #expect(parent.chips == [
            MAMEChip(type: "cpu", name: "Motorola 68000"), MAMEChip(type: "audio", name: "Yamaha YM2610"),
        ])
        #expect(parent.hasSamples == true)
        #expect(parent.roms.first { $0.name == "v1.v1" }?.status == .baddump)
        #expect(parent.roms.first { $0.name == "038-p1.p1" }?.status == .good)

        let clone = try #require(dataset.machine(named: "mslugx"))
        #expect(clone.cloneOf == "mslug")
        #expect(clone.romOf == "mslug")
        #expect(clone.isBios == false)
        #expect(clone.roms.first { $0.name == "201-p1.p1" }?.mergeName == nil, "the clone's own unique rom has no merge marker")
        #expect(clone.roms.first { $0.name == "038-p1.p1" }?.mergeName == "038-p1.p1", "inherited from the parent, per MAME's merge= attribute")
    }

    @Test("throws when the root <mame> element is missing")
    func throwsWhenRootElementMissing() {
        #expect(throws: MAMEParsingError.missingRootElement) {
            try MAMEListXMLParser.parse(data: Data("<somethingElse></somethingElse>".utf8))
        }
    }

    @Test("throws on malformed XML")
    func throwsOnMalformedXML() {
        #expect(throws: MAMEParsingError.self) {
            try MAMEListXMLParser.parse(data: Data("<mame><machine name=\"x\">".utf8))
        }
    }
}

@Suite("BIOSResolver")
struct BIOSResolverTests {
    private func dataset() throws -> MAMEDataset {
        try MAMEListXMLParser.parse(data: Data("""
        <mame>
            <machine name="neogeo" isbios="yes">
                <description>Neo-Geo</description>
                <year>1990</year>
                <manufacturer>SNK</manufacturer>
            </machine>
            <machine name="mslug" romof="neogeo">
                <description>Metal Slug</description>
                <year>1996</year>
                <manufacturer>SNK</manufacturer>
            </machine>
            <machine name="mslugx" cloneof="mslug" romof="mslug">
                <description>Metal Slug X</description>
                <year>1999</year>
                <manufacturer>SNK</manufacturer>
            </machine>
        </mame>
        """.utf8))
    }

    @Test("resolves the full dependency chain from clone to BIOS, furthest ancestor first")
    func resolvesFullChain() throws {
        let chain = try BIOSResolver.resolveDependencies(of: "mslugx", in: dataset())
        #expect(chain.map(\.name) == ["neogeo", "mslug", "mslugx"])
    }

    @Test("resolves a lone BIOS machine to just itself")
    func resolvesLoneBIOSMachine() throws {
        let chain = try BIOSResolver.resolveDependencies(of: "neogeo", in: dataset())
        #expect(chain.map(\.name) == ["neogeo"])
    }

    @Test("throws when the machine does not exist in the dataset")
    func throwsWhenMachineNotFound() throws {
        #expect(throws: BIOSResolutionError.machineNotFound("unknown")) {
            try BIOSResolver.resolveDependencies(of: "unknown", in: try dataset())
        }
    }

    @Test("throws on a circular romof reference instead of looping forever")
    func throwsOnCircularReference() throws {
        let circular = MAMEDataset(machines: [
            MAMEMachine(name: "a", description: "A", year: "", manufacturer: "", cloneOf: nil, romOf: "b", isBios: false, isDevice: false, biosSets: [], roms: [], disks: [], deviceRefs: []),
            MAMEMachine(name: "b", description: "B", year: "", manufacturer: "", cloneOf: nil, romOf: "a", isBios: false, isDevice: false, biosSets: [], roms: [], disks: [], deviceRefs: []),
        ])

        #expect(throws: BIOSResolutionError.self) {
            try BIOSResolver.resolveDependencies(of: "a", in: circular)
        }
    }
}
