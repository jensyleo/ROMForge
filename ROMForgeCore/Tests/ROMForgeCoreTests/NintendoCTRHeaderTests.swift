import Foundation
import Testing
@testable import ROMForgeCore

@Suite("Nintendo 3DS header")
struct NintendoCTRHeaderTests {
    private func makeHeader(code: String, imageUnits: UInt32, noCrypto: Bool) -> Data {
        var data = Data(count: 0x4400)
        data.replaceSubrange(0x100..<0x104, with: Array("NCSD".utf8))
        func put(_ value: UInt32, at offset: Int) {
            for i in 0..<4 { data[offset + i] = UInt8((value >> (8 * UInt32(i))) & 0xFF) }
        }
        put(imageUnits, at: 0x104)
        put(0x20, at: 0x120)  // first partition at 0x4000, as on real cartridges
        let ncch = 0x4000
        data.replaceSubrange(ncch + 0x100..<ncch + 0x104, with: Array("NCCH".utf8))
        data.replaceSubrange(ncch + 0x150..<ncch + 0x150 + code.utf8.count, with: Array(code.utf8))
        data[ncch + 0x188 + 7] = noCrypto ? 0x04 : 0x00
        return data
    }

    @Test("reads product code, image size and encryption flag")
    func parses() {
        let encrypted = NintendoCTRHeader.parse(makeHeader(code: "CTR-P-ASVP", imageUnits: 0x100000, noCrypto: false))
        #expect(encrypted == NintendoCTRHeader(productCode: "CTR-P-ASVP", imageSize: 536_870_912, state: .encrypted))
        #expect(NintendoCTRHeader.parse(makeHeader(code: "CTR-P-ASVP", imageUnits: 1, noCrypto: true))?.isEncrypted == false)
    }

    @Test("plain content without the header flag is reported as such, not as encrypted")
    func flagMissing() {
        let data = makeHeader(code: "CTR-P-ASVP", imageUnits: 1, noCrypto: false)
        #expect(NintendoCTRHeader.parse(data, exeFSStart: Data(".code\0\0\0".utf8), romFSStart: Data("IVFC".utf8))?.state == .decryptedFlagMissing)
        #expect(NintendoCTRHeader.parse(data, exeFSStart: Data([0xE3, 0xF3, 0x81, 0x3C]), romFSStart: Data([0x74, 0xF2, 0x41, 0xD5]))?.state == .encrypted)
    }

    @Test("rejects data that is not a 3DS cartridge image")
    func rejectsOtherData() {
        #expect(NintendoCTRHeader.parse(Data(count: 0x4400)) == nil)
        #expect(NintendoCTRHeader.parse(Data()) == nil)
    }

    @Test("reads a real-layout file from disk")
    func readsFromDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".3ds")
        defer { try? FileManager.default.removeItem(at: file) }
        try makeHeader(code: "CTR-P-AQEP", imageUnits: 0x100000, noCrypto: true).write(to: file)
        #expect(NintendoCTRHeader.read(url: file) == NintendoCTRHeader(productCode: "CTR-P-AQEP", imageSize: 536_870_912, state: .decrypted))
    }

    @Test("a trimmed dump is matched to its DAT game by product code")
    func serialSuggestion() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Mystery.3ds")
        try makeHeader(code: "CTR-P-ASVP", imageUnits: 0x100000, noCrypto: false).write(to: file)
        let rom = DATRom(name: "Shinobi (Europe).3ds", size: 536_870_912, crc: "69af12dc", md5: nil, sha1: nil, serial: "CTR-P-ASVP")
        let other = DATRom(name: "Other (USA).3ds", size: 536_870_912, crc: "00000001", md5: nil, sha1: nil, serial: "CTR-P-AAAA")
        let dat = DATFile(header: DATHeader(name: "3DS", description: "3DS", version: "1", author: "t"), games: [
            DATGame(name: "Shinobi (Europe)", description: "Shinobi (Europe)", cloneOf: nil, romOf: nil, roms: [rom]),
            DATGame(name: "Other (USA)", description: "Other (USA)", cloneOf: nil, romOf: nil, roms: [other]),
        ])
        let hashed = HashedFile(file: ScannedFile(url: file, name: "Mystery.3ds", size: 100, modificationDate: Date()), hash: FileHash(crc32: "11111111", md5: nil, sha1: nil))
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [hashed])
        #expect(report.surplusFiles.first?.similarNameSuggestion?.suggestedName == "Shinobi (Europe)")
    }
}

@Suite("Extra entry inside a claimed single-ROM archive")
struct ExtraEntryInClaimedArchiveTests {
    @Test("a readme next to the game's ROM is useless, not 'required by' that game")
    func readmeIsUnrecognized() throws {
        let zip = URL(fileURLWithPath: "/roms/Game (Europe).zip")
        let rom = DATRom(name: "Game (Europe).3ds", size: 10, crc: "0000000a", md5: nil, sha1: nil)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [
            DATGame(name: "Game (Europe)", description: "Game (Europe)", cloneOf: nil, romOf: nil, roms: [rom]),
        ])
        func file(_ name: String, _ size: Int64, _ crc: String) -> HashedFile {
            HashedFile(file: ScannedFile(url: zip, name: name, size: size, modificationDate: Date(), entryPath: name), hash: FileHash(crc32: crc, md5: nil, sha1: nil))
        }
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [file("Game (Europe).3ds", 10, "0000000a"), file("readme.txt", 116, "050a79f3")], nameOnlyMatching: true)
        let readme = try #require(report.surplusFiles.first { $0.file.file.name == "readme.txt" })
        #expect(readme.requiredByGameDescription == nil)
        #expect(RebuildPlanner.planRemoveUselessFiles(matchReport: report).count == 1)
    }
}

@Suite("Region notes for variant platforms")
struct RegionNoteAliasTests {
    @Test("an SNES-MSU1 system reads the SNES notes")
    func msu1UsesSNESNotes() throws {
        let snesGame = try #require(RegionQualityNotes.seed.first { $0.platform == "SNES" })
        let note = RegionQualityNotes.note(forGameName: snesGame.gameFamily + " (USA)", platform: "SNES-MSU1")
        #expect(note?.gameFamily == snesGame.gameFamily)
    }
}

@Suite("3DS dumps inside a zip")
struct CTRZipTests {
    @Test("a decrypted dump without the header flag is recognized inside a zip too")
    func zipEntry() throws {
        var data = Data(count: 0x4000 + 0x2800 + 0x200)
        data.replaceSubrange(0x100..<0x104, with: Array("NCSD".utf8))
        data[0x104] = 1
        data[0x120] = 0x20  // partition at 0x4000
        let ncch = 0x4000
        data.replaceSubrange(ncch + 0x100..<ncch + 0x104, with: Array("NCCH".utf8))
        data.replaceSubrange(ncch + 0x150..<ncch + 0x160, with: Array("CTR-P-TEST".utf8) + Array(repeating: 0, count: 6))
        data[ncch + 0x1A0] = 0x14  // ExeFS 0x14 units (0x2800) after the partition start
        data.replaceSubrange(ncch + 0x2800..<ncch + 0x2808, with: Array(".code".utf8) + [0, 0, 0])
        #expect(NintendoCTRHeader.parse(prefix: data)?.state == .decryptedFlagMissing)
        var cipher = data
        cipher.replaceSubrange(ncch + 0x2800..<ncch + 0x2808, with: [0xE3, 0xF3, 0x81, 0x3C, 0xF3, 0xFC, 0xAC, 0xB0])
        #expect(NintendoCTRHeader.parse(prefix: cipher)?.state == .encrypted)
    }
}
