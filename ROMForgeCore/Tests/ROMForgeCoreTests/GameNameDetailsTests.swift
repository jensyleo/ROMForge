// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
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

    @Test func decodesMultiCartLanguagesAndGBAStyleTags() {
        let multi = GameNameDetails.parse(name: "2 in 1 (Europe) (En,Fr,De+En)")
        #expect(multi.languages == ["English", "French", "German"])
        #expect(GameNameDetails.parse(name: "X (Unknown)").regions == ["Unknown"])
        #expect(GameNameDetails.parse(name: "Y (USA) (Test Program)").releaseStage == "Test program")
        #expect(GameNameDetails.parse(name: "Z (World) (Debug)").releaseStage == "Debug")
        #expect(GameNameDetails.parse(name: "W (Japan) (Netcard)").distribution == ["Netcard"])
    }

    @Test func tiedRegionsAndPlatformScoping() {
        let note = RegionQualityNotes.note(forGameName: "Contra III - The Alien Wars (USA)", platform: "SNES")
        #expect(note?.bestRegionsLabel == "Japan or USA")
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "SNES") == nil)
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "NES") != nil)
    }
}

@Suite("CollectionHasher RAR volumes")
struct RARVolumeTests {
    @Test func recognizesRARVolumes() {
        for ext in ["rar", "r00", "r42"] { #expect(CollectionHasher.isRARVolume(ext)) }
        for ext in ["zip", "7z", "sfc", "r", "rom", "r4x"] { #expect(!CollectionHasher.isRARVolume(ext)) }
    }
}

@Suite("RegionQualityOverrides")
struct RegionQualityOverridesTests {
    @Test func parsesLenientlyAndReportsProblems() {
        let json = """
        { "version": 1, "notes": [
          { "gameFamily": "Contra III - The Alien Wars", "recommendedRegion": "Japan", "tiedRegions": ["USA"], "reason": "Mine", "sourceURL": "https://example.com/x" },
          { "gameFamily": "No Reason Game", "recommendedRegion": "USA" },
          { "reason": "no family at all" },
          { "gameFamily": "Bad Url", "recommendedRegion": "USA", "reason": "r", "sourceURL": "javascript:alert(1)" },
          { "gameFamily": "Contra", "platform": "NES", "disabled": true }
        ] }
        """
        let result = RegionQualityOverrides.parse(data: Data(json.utf8), knownPlatforms: ["NES", "SNES"])
        #expect(result.notes.map(\.gameFamily) == ["Contra III - The Alien Wars", "Bad Url", "Contra"])
        #expect(result.notes[1].sourceURL.isEmpty)
        #expect(result.issues.count == 3)
    }

    @Test func userNoteWinsAndDisabledSuppressesBuiltIn() {
        let mine = RegionQualityNote(gameFamily: "contra iii - the alien wars", platform: "SNES", recommendedRegion: "Japan", reason: "mine", sourceURL: "", sourceLicense: "", consultedDate: "")
        #expect(RegionQualityNotes.note(forGameName: "Contra III - The Alien Wars (USA)", platform: "SNES", overrides: [mine])?.reason == "mine")
        let off = RegionQualityNote(gameFamily: "Contra", platform: "NES", recommendedRegion: "", reason: "", sourceURL: "", sourceLicense: "", consultedDate: "", disabled: true)
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "NES", overrides: [off]) == nil)
        #expect(RegionQualityNotes.note(forGameName: "Contra (USA)", platform: "NES") != nil)
    }

    @Test func rejectsInvalidAndOversizedFiles() {
        #expect(RegionQualityOverrides.parse(data: Data("nonsense".utf8)).notes.isEmpty)
        #expect(RegionQualityOverrides.parse(data: Data(count: RegionQualityOverrides.maxFileBytes + 1)).notes.isEmpty)
    }
}

@Suite("ForeignProgramFiles")
struct ForeignProgramFilesTests {
    @Test func protectsFrontEndFilesButNotMacJunk() {
        for path in ["/r/snes-msu1/gamelist.xml", "/r/snes-msu1/gamelist.xml.old", "/r/snes-msu1/_info.txt",
                     "/r/snes-msu1/images/Game-image.png", "/r/snes-msu1/videos/Game.mp4", "/r/x/manuals/a/b.pdf",
                     "/r/Metadata.txt"] {
            #expect(ForeignProgramFiles.isProtected(URL(fileURLWithPath: path)), "\\(path)")
        }
        for path in ["/r/snes/.DS_Store", "/r/snes/._cx4.rom", "/r/snes/readme.txt", "/r/snes/Some Game.sfc", "/r/snes/a/b/c/images2/x.png"] {
            #expect(!ForeignProgramFiles.isProtected(URL(fileURLWithPath: path)), "\\(path)")
        }
    }
}

@Suite("SNESHeaderDecoder")
struct SNESHeaderDecoderTests {
    private func rom(loROM: Bool, chipset: UInt8, subtype: UInt8 = 0, checksum: Bool = true, copier: Bool = false) -> (Data, Int64) {
        var data = Data(count: (copier ? 512 : 0) + 0x10000)
        let base = (copier ? 512 : 0) + (loROM ? 0x7FC0 : 0xFFC0)
        data[base + 0x15] = loROM ? 0x20 : 0x21
        for i in 0..<21 { data[base + i] = 0x41 }
        data[base + 0x16] = chipset
        data[(copier ? 512 : 0) + (loROM ? 0x7FBF : 0xFFBF)] = subtype
        if checksum { data[base + 0x1C] = 0x00; data[base + 0x1D] = 0x00; data[base + 0x1E] = 0xFF; data[base + 0x1F] = 0xFF }
        return (data, Int64(data.count) + (copier ? 0 : 0))
    }

    @Test func decodesMapModeAndChips() {
        let cases: [(Bool, UInt8, UInt8, String?)] = [
            (true, 0x00, 0, nil), (true, 0x02, 0, nil), (true, 0x13, 0, "Super FX (GSU)"), (true, 0x15, 0, "Super FX (GSU)"),
            (true, 0x34, 0, "SA-1"), (true, 0x03, 0, "DSP (DSP-1/2/3/4)"), (false, 0x43, 0, "S-DD1"), (true, 0xF3, 0x10, "Cx4"),
            (false, 0xF5, 0x00, "SPC7110"),
        ]
        for (lo, chipset, subtype, expected) in cases {
            let (data, size) = rom(loROM: lo, chipset: chipset, subtype: subtype)
            let info = SNESHeaderDecoder.decode(prefix: data, fileSize: size)
            #expect(info?.mapMode == (lo ? "LoROM" : "HiROM"))
            #expect(info?.expansionChip == expected, "chipset \\(chipset)")
        }
    }

    @Test func acceptsUnusualMapModeWhenChecksumIsValid() {
        // Contra III (map mode 0x53) and Super Mario RPG (SA-1: 0x23 at the LoROM location), as seen in real dumps.
        for (mapMode, chipset, expected) in [(UInt8(0x53), UInt8(0x00), String?.none), (UInt8(0x23), UInt8(0x35), "SA-1")] {
            let (data, size) = rom(loROM: true, chipset: chipset)
            var patched = data
            patched[0x7FC0 + 0x15] = mapMode
            let info = SNESHeaderDecoder.decode(prefix: patched, fileSize: size)
            #expect(info?.mapMode == "LoROM")
            #expect(info?.expansionChip == expected)
        }
    }

    @Test func handlesCopierHeaderBadChecksumAndGarbage() {
        let (withCopier, _) = rom(loROM: true, chipset: 0x13, copier: true)
        #expect(SNESHeaderDecoder.decode(prefix: withCopier, fileSize: 512 + 0x80000)?.expansionChip == "Super FX (GSU)")
        let (noChecksum, size) = rom(loROM: true, chipset: 0x34, checksum: false)
        #expect(SNESHeaderDecoder.decode(prefix: noChecksum, fileSize: size)?.expansionChip == "SA-1")
        #expect(SNESHeaderDecoder.decode(prefix: Data(count: 0x10200), fileSize: 0x80000) == nil)
        #expect(SNESHeaderDecoder.decode(prefix: Data(count: 100), fileSize: 100) == nil)
    }
}

@Suite("N64 byte order")
struct N64ByteOrderTests {
    private func z64() -> Data {
        var d = Data([0x80, 0x37, 0x12, 0x40])
        d.append(Data((0..<4092).map { UInt8(($0 &* 7) % 256) }))
        return d
    }

    @Test func detectsAndConvertsEveryOrder() throws {
        let be = z64()
        var v64 = [UInt8](be); var n64 = [UInt8](be)
        var i = 0
        while i < be.count { v64.swapAt(i, i + 1); v64.swapAt(i + 2, i + 3); n64.swapAt(i, i + 3); n64.swapAt(i + 1, i + 2); i += 4 }
        #expect(N64ByteOrder.detect(be) == .bigEndian)
        #expect(N64ByteOrder.detect(Data(v64)) == .byteSwapped)
        #expect(N64ByteOrder.detect(Data(n64)) == .littleEndian)
        #expect(N64ByteOrder.toBigEndian(Data(v64), from: .byteSwapped) == be)
        #expect(N64ByteOrder.toBigEndian(Data(n64), from: .littleEndian) == be)
        #expect(N64ByteOrder.detect(Data([1, 2, 3, 4])) == nil)
    }

    @Test("a little-endian .n64 file matches a big-endian DAT entry end-to-end") func n64FileMatchesZ64DAT() async throws {
        let be = z64()
        var n64 = [UInt8](be)
        var i = 0
        while i < be.count { n64.swapAt(i, i + 3); n64.swapAt(i + 1, i + 2); i += 4 }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Game (USA).n64")
        try Data(n64).write(to: url)
        let hashed = try await FileHasher.hash(files: [ScannedFile(url: url, name: url.lastPathComponent, size: Int64(n64.count))])
        let h = FileHasher.hash(data: be)
        let game = DATGame(name: "Game (USA)", description: "Game (USA)", cloneOf: nil, romOf: nil, roms: [DATRom(name: "Game (USA).n64", size: Int64(be.count), crc: h.crc32, md5: h.md5, sha1: h.sha1)])
        let dat = DATFile(header: DATHeader(name: "T", description: "T", version: "1", author: "t"), games: [game])
        let audit = try AuditReporter.generate(from: try ROMMatcher.match(dat: dat, hashedFiles: hashed))
        #expect(audit.entries.first { $0.game == "Game (USA)" }?.status == .correct)
    }
}
