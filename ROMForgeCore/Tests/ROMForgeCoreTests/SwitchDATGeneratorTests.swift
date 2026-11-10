// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("Switch DAT generation")
struct SwitchDATGeneratorTests {
    /// A minimal PFS0 container: header, entry table, string table, then each entry's bytes.
    private func pfs0(_ entries: [(name: String, content: Data)]) -> Data {
        var strings = Data()
        var table = Data()
        var offset: UInt64 = 0
        func le<T: FixedWidthInteger>(_ value: T) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        for entry in entries {
            table += le(offset) + le(UInt64(entry.content.count)) + le(UInt32(strings.count)) + le(UInt32(0))
            strings += Data(entry.name.utf8) + Data([0])
            offset += UInt64(entry.content.count)
        }
        var data = Data("PFS0".utf8) + le(UInt32(entries.count)) + le(UInt32(strings.count)) + le(UInt32(0)) + table + strings
        for entry in entries { data += entry.content }
        return data
    }

    private func write(_ data: Data, named name: String, in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private let titleDB = SwitchTitleDB(
        names: ["0100000000010000": "Super Mario Odyssey™", "0100D71004694000": "Minecraft", "01007EF00011E000": "The Legend of Zelda™: Breath of the Wild – Nintendo Switch™ 2 Edition"],
        latestVersions: ["0100000000010800": 393216, "0100D71004694800": 10551296]
    )

    @Test("reads the Title ID from the ticket name and the version from the metadata XML")
    func readsTitleIDFromInsideTheFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("romforge-nsp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let xml = Data("<ContentMeta><Id>0x0100d71004694000</Id><Version>65536</Version></ContentMeta>".utf8)
        let withTicket = try write(pfs0([("0100d710046940000000000000000004.tik", Data(count: 8)), ("abc.cnmt.xml", xml)]), named: "no-id.nsp", in: folder)
        let onlyXML = try write(pfs0([("aaaa.nca", Data(count: 4)), ("abc.cnmt.xml", xml)]), named: "no-ticket.nsp", in: folder)
        let notNSP = try write(Data("not a container".utf8), named: "junk.nsp", in: folder)

        #expect(SwitchNSPReader.info(ofFileAt: withTicket) == SwitchNSPReader.Info(titleID: "0100D71004694000", version: 65536))
        #expect(SwitchNSPReader.info(ofFileAt: onlyXML)?.titleID == "0100D71004694000")
        #expect(SwitchNSPReader.info(ofFileAt: notNSP) == nil)
    }

    @Test("groups base, update and DLC under one game named after the official title")
    func groupsFilesByGame() {
        let files = [
            SwitchDATGenerator.File(fileName: "Super Mario Odyssey [0100000000010800][v393216][US](nsw2u.com).nsp", size: 30),
            SwitchDATGenerator.File(fileName: "Super Mario Odyssey [0100000000010000][v0].nsp", size: 10),
            SwitchDATGenerator.File(fileName: "Zelda BOTW [DLC Pack 1] [01007EF00011F001][v196608].nsp", size: 5),
            SwitchDATGenerator.File(fileName: "Zelda BOTW [01007EF00011E000][v0].nsp", size: 7),
        ]
        let result = SwitchDATGenerator.generate(files: files, titleDB: titleDB, version: "1")

        #expect(result.dat.games.map(\.name) == ["Super Mario Odyssey", "The Legend of Zelda - Breath of the Wild"])
        #expect(result.dat.games[0].roms.map(\.name) == [
            "Super Mario Odyssey [0100000000010000][v0].nsp",
            "Super Mario Odyssey [0100000000010800][v393216][US](nsw2u.com).nsp",
        ])
        #expect(result.dat.games[1].roms.map(\.name) == ["Zelda BOTW [01007EF00011E000][v0].nsp", "Zelda BOTW [DLC Pack 1] [01007EF00011F001][v196608].nsp"])
        #expect(result.availableUpdates.isEmpty)
    }

    @Test("a file without a Title ID in its name joins its game through the embedded ID, and a newer update is listed as missing")
    func embeddedIDAndNewerUpdate() {
        let files = [
            SwitchDATGenerator.File(fileName: "Minecraft_v0_switch-xci.com.nsp", size: 100, embeddedTitleID: "0100d71004694000"),
            SwitchDATGenerator.File(fileName: "Minecraft [0100D71004694800][v10485760][Up v1.26.45].nsp", size: 200),
            SwitchDATGenerator.File(fileName: "mystery.nsp", size: 1),
        ]
        let result = SwitchDATGenerator.generate(files: files, titleDB: titleDB, version: "1")

        #expect(result.dat.games.count == 1)
        #expect(result.dat.games[0].roms.map(\.name) == [
            "Minecraft_v0_switch-xci.com.nsp",
            "Minecraft [0100D71004694800][v10485760][Up v1.26.45].nsp",
            "Minecraft [0100D71004694800][v10551296].nsp",
        ])
        #expect(result.dat.games[0].roms.last?.size == 0)
        #expect(result.availableUpdates == ["Minecraft"])
        #expect(result.unidentifiedFiles == ["mystery.nsp"])
    }

    @Test("the generated XML loads back through the Logiqx parser")
    func xmlRoundTrips() throws {
        let files = [SwitchDATGenerator.File(fileName: "A & B <Game> [0100AAAAAAAAA000][v0].nsp", size: 42)]
        let result = SwitchDATGenerator.generate(files: files, titleDB: SwitchTitleDB(names: [:], latestVersions: [:]), version: "1")
        let parsed = try LogiqxDATParser.parse(data: Data(SwitchDATGenerator.xml(for: result.dat).utf8))

        #expect(parsed.games.count == 1)
        #expect(parsed.games[0].roms[0].name == "A & B <Game> [0100AAAAAAAAA000][v0].nsp")
        #expect(parsed.games[0].roms[0].size == 42)
    }

    @Test("DLC Title IDs map back to their base game")
    func baseTitleID() {
        #expect(SwitchDATGenerator.baseTitleID(of: "01007EF00011F001") == "01007EF00011E000")
        #expect(SwitchDATGenerator.baseTitleID(of: "0100000000010800") == "0100000000010000")
        #expect(SwitchDATGenerator.baseTitleID(of: "01006a800016f072") == "01006A800016E000")
    }
}
