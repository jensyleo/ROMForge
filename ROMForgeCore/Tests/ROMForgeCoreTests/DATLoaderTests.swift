// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("DATLoader")
struct DATLoaderTests {
    @Test("loads a Logiqx DAT directly")
    func loadsLogiqxDAT() throws {
        let xml = """
        <?xml version="1.0"?>
        <datafile>
            <header>
                <name>Test System</name>
                <description>Test System DAT</description>
                <version>1.0</version>
                <author>ROMForge</author>
            </header>
            <game name="Correct Game">
                <description>Correct Game</description>
                <rom name="correct.bin" size="7" crc="f45595a1"/>
            </game>
        </datafile>
        """
        let dat = try DATLoader.load(data: Data(xml.utf8))
        #expect(dat.header.name == "Test System")
        #expect(dat.games.count == 1)
    }

    @Test("falls back to MAME -listxml when the root isn't <datafile>")
    func fallsBackToMAMEFormat() throws {
        let xml = """
        <mame build="0.278">
            <machine name="neogeo" isbios="yes">
                <description>Neo-Geo</description>
                <year>1990</year>
                <manufacturer>SNK</manufacturer>
                <rom name="sp-s2.sp1" size="131072" crc="9036d879"/>
            </machine>
            <machine name="mslug" romof="neogeo">
                <description>Metal Slug</description>
                <year>1996</year>
                <manufacturer>SNK</manufacturer>
                <rom name="038-p1.p1" size="524288" crc="1e174290"/>
            </machine>
            <machine name="cpu_device" isdevice="yes">
                <description>Shared CPU core</description>
            </machine>
        </mame>
        """
        let dat = try DATLoader.load(data: Data(xml.utf8))

        #expect(dat.header.name == "MAME")
        // Devices are no longer excluded from `dat.games` — real bug found
        // by jensyleo (2026-07-28): a device with an actual physical
        // romset (e.g. CPS2's `qsound_hle`, whose one rom is
        // `merge="..."`-inherited from another device) could never be
        // matched at all, permanently showing its real archive as an
        // unrecognized surplus file. `cpu_device` here declares no roms of
        // its own, so it still shows up (with zero roms to match), just
        // like a real romless/abstract device would.
        #expect(dat.games.map(\.name).sorted() == ["cpu_device", "mslug", "neogeo"])

        let mslug = try #require(dat.games.first { $0.name == "mslug" })
        #expect(mslug.romOf == "neogeo")
        #expect(mslug.roms[0].crc == "1e174290")
    }

    @Test("falls back to MAME software list when neither Logiqx nor -listxml roots match")
    func fallsBackToSoftwareListFormat() throws {
        let xml = """
        <softwarelist name="pasogo" description="PasoGo cartridges">
            <software name="taikyoku" cloneof="taikyoku1">
                <description>Taikyoku-kun I</description>
                <year>1996</year>
                <publisher>Koei</publisher>
                <part name="cart" interface="pasogo_cart">
                    <dataarea name="rom" size="4">
                        <rom name="ks-1001.ic4" size="4" crc="2753bb6c"/>
                    </dataarea>
                </part>
            </software>
        </softwarelist>
        """
        let dat = try DATLoader.load(data: Data(xml.utf8))

        #expect(dat.header.name == "pasogo")
        #expect(dat.games.count == 1)
        let game = try #require(dat.games.first)
        #expect(game.name == "taikyoku")
        #expect(game.cloneOf == "taikyoku1")
        #expect(game.roms.count == 1)
        #expect(game.roms[0].crc == "2753bb6c")
    }

    @Test("MAME -listxml conversion applies split-mode layout, excluding a clone's merge=-marked inherited rom")
    func mameConversionExcludesMergedRomsFromClones() throws {
        // Real bug this guards against: a real -listxml dump declares every
        // rom for every clone, marking ones inherited from the parent with
        // merge="..." — without split-mode filtering, ROMForge would ask a
        // split-organized clone archive (which never contains that file,
        // by convention) for a rom it was never supposed to have, and
        // report it "missing" instead of correctly leaving it to the
        // parent archive.
        let xml = """
        <mame build="0.278">
            <machine name="mslug">
                <description>Metal Slug</description>
                <year>1996</year>
                <manufacturer>SNK</manufacturer>
                <rom name="038-p1.p1" size="524288" crc="1e174290"/>
            </machine>
            <machine name="mslugx" cloneof="mslug" romof="mslug">
                <description>Metal Slug X</description>
                <year>1999</year>
                <manufacturer>SNK</manufacturer>
                <rom name="201-p1.p1" size="524288" crc="2c37b0f7"/>
                <rom name="038-p1.p1" size="524288" crc="1e174290" merge="038-p1.p1"/>
            </machine>
        </mame>
        """
        let dat = try DATLoader.load(data: Data(xml.utf8))

        let clone = try #require(dat.games.first { $0.name == "mslugx" })
        #expect(clone.roms.map(\.name) == ["201-p1.p1"], "the merge=-marked rom belongs to the parent archive, not the clone's")

        let parent = try #require(dat.games.first { $0.name == "mslug" })
        #expect(parent.roms.map(\.name) == ["038-p1.p1"], "the parent itself is unaffected — nothing to inherit from")
    }

    @Test("mergeMode is configurable per load — .nonMerged folds the BIOS's roms into the dependent machine's own archive")
    func mergeModeIsConfigurable() throws {
        let xml = """
        <mame build="0.278">
            <machine name="neogeo" isbios="yes">
                <description>Neo-Geo</description>
                <rom name="sp-s2.sp1" size="131072" crc="9036d879"/>
            </machine>
            <machine name="mslug" romof="neogeo">
                <description>Metal Slug</description>
                <rom name="038-p1.p1" size="524288" crc="1e174290"/>
            </machine>
        </mame>
        """
        let split = try DATLoader.load(data: Data(xml.utf8), mergeMode: .split)
        let splitMslug = try #require(split.games.first { $0.name == "mslug" })
        #expect(splitMslug.roms.map(\.name) == ["038-p1.p1"], "split mode leaves the BIOS's rom to the BIOS's own archive")

        // ROM merge mode alone (default biosMergeMode: .split) never
        // touches BIOS roms at all — that's `biosMergeMode`'s job, a fully
        // independent setting (see `biosMergeModeIsIndependentOfRomMergeMode`).
        let nonMerged = try DATLoader.load(data: Data(xml.utf8), mergeMode: .nonMerged)
        let nonMergedMslug = try #require(nonMerged.games.first { $0.name == "mslug" })
        #expect(
            nonMergedMslug.roms.map(\.name) == ["038-p1.p1"],
            "non-merged ROM mode alone doesn't duplicate the BIOS's rom — that needs biosMergeMode: .nonMerged too"
        )

        let nonMergedBoth = try DATLoader.load(data: Data(xml.utf8), mergeMode: .nonMerged, biosMergeMode: .nonMerged)
        let nonMergedBothMslug = try #require(nonMergedBoth.games.first { $0.name == "mslug" })
        #expect(
            Set(nonMergedBothMslug.roms.map(\.name)) == ["038-p1.p1", "sp-s2.sp1"],
            "non-merged ROM mode combined with non-merged BIOS mode does duplicate the BIOS's rom into the dependent"
        )
    }

    @Test("merged mode excludes clones from the top-level games list — a real Merged set has no separate clone archive")
    func mergedModeExcludesClonesFromGamesList() throws {
        let xml = """
        <mame build="0.278">
            <machine name="parent">
                <description>Parent Game</description>
                <rom name="prog.bin" size="1024" crc="11111111"/>
            </machine>
            <machine name="clone" cloneof="parent" romof="parent">
                <description>Parent Game (alt)</description>
                <rom name="prog.bin" size="1024" crc="11111111" merge="prog.bin"/>
                <rom name="extra.bin" size="256" crc="22222222"/>
            </machine>
        </mame>
        """
        let split = try DATLoader.load(data: Data(xml.utf8), mergeMode: .split)
        #expect(split.games.map(\.name).sorted() == ["clone", "parent"], "split keeps a separate archive per clone")

        let nonMerged = try DATLoader.load(data: Data(xml.utf8), mergeMode: .nonMerged)
        #expect(nonMerged.games.map(\.name).sorted() == ["clone", "parent"], "non-merged keeps a separate, self-contained archive per clone")

        let merged = try DATLoader.load(data: Data(xml.utf8), mergeMode: .merged)
        #expect(merged.games.map(\.name) == ["parent"], "a real Merged set has no separate clone archive at all — everything lives in the parent's own")
        let parent = try #require(merged.games.first { $0.name == "parent" })
        #expect(Set(parent.roms.map(\.name)) == ["prog.bin", "extra.bin"], "the clone's own (non-shared) rom is still folded into the parent's merged archive")

        // Real bug found live by jensyleo (2026-08-04): `merged.games`
        // above has NO game with `cloneOf != nil` at all (the clone was
        // excluded from the list itself) — code that derived "does this
        // DAT have any clones" from `games.contains { $0.cloneOf != nil }`
        // would wrongly read `false` here, even though this dataset
        // plainly has a real clone. `DATFile.hasClones` must stay `true`
        // regardless of which merge mode built the `DATFile`, since it's
        // computed from the raw dataset before this exclusion happens.
        #expect(merged.hasClones, "hasClones must reflect the dataset's real clone relationships, not the merge-mode-filtered games list")
        #expect(split.hasClones)
        #expect(nonMerged.hasClones)
    }

    @Test("biosMergeMode is a fully independent axis from mergeMode — Split/Merged/Non-Merged, confirmed against a real reference tool")
    func biosMergeModeIsIndependentOfRomMergeMode() throws {
        let xml = """
        <mame build="0.278">
            <machine name="neogeo" isbios="yes">
                <description>Neo-Geo</description>
                <rom name="sp-s2.sp1" size="131072" crc="9036d879"/>
            </machine>
            <machine name="mslug" romof="neogeo">
                <description>Metal Slug</description>
                <rom name="038-p1.p1" size="524288" crc="1e174290"/>
            </machine>
        </mame>
        """
        // Split (the default): BIOS keeps its own separate entry; no
        // dependent game contains its roms.
        let split = try DATLoader.load(data: Data(xml.utf8), biosMergeMode: .split)
        #expect(split.games.map(\.name).sorted() == ["mslug", "neogeo"])
        let splitMslug = try #require(split.games.first { $0.name == "mslug" })
        #expect(splitMslug.roms.map(\.name) == ["038-p1.p1"])

        // Merged: BIOS's own entry is dropped — its roms now live folded
        // into the dependent's (root) archive instead.
        let merged = try DATLoader.load(data: Data(xml.utf8), biosMergeMode: .merged)
        #expect(merged.games.map(\.name) == ["mslug"], "the BIOS no longer gets its own top-level entry — its roms are folded into the dependent instead")
        let mergedMslug = try #require(merged.games.first { $0.name == "mslug" })
        #expect(Set(mergedMslug.roms.map(\.name)) == ["038-p1.p1", "sp-s2.sp1"])

        // Non-Merged: BIOS's own entry still exists (unlike Merged), *and*
        // its roms are also duplicated into the dependent.
        let nonMerged = try DATLoader.load(data: Data(xml.utf8), biosMergeMode: .nonMerged)
        #expect(nonMerged.games.map(\.name).sorted() == ["mslug", "neogeo"])
        let nonMergedMslug = try #require(nonMerged.games.first { $0.name == "mslug" })
        #expect(Set(nonMergedMslug.roms.map(\.name)) == ["038-p1.p1", "sp-s2.sp1"])
    }

    @Test("throws a combined error when neither format parses")
    func throwsWhenNeitherFormatParses() {
        let garbage = Data("this is not xml at all { } < >".utf8)
        #expect(throws: DATLoaderError.self) {
            try DATLoader.load(data: garbage)
        }
    }
}
