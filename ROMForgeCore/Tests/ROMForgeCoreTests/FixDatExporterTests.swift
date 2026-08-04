// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("FixDatExporter")
struct FixDatExporterTests {
    private func report() -> AuditReport {
        AuditReport(
            entries: [
                AuditEntry(
                    status: .missing, game: "mslug", name: "mslug.bin", path: nil,
                    expectedSize: 4, expectedCRC: "d87f7e0c", expectedMD5: "098f6bcd4621d373cade4e832627b4f6", expectedSHA1: "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3"
                ),
                AuditEntry(
                    status: .incorrect, game: "mslug", name: "mslug2.bin", path: URL(fileURLWithPath: "/tmp/renamed.bin"),
                    expectedSize: 8, expectedCRC: "e7b9ed24"
                ),
                AuditEntry(status: .correct, game: "mslug", name: "mslug3.bin", path: URL(fileURLWithPath: "/tmp/mslug3.bin")),
                AuditEntry(status: .surplus, game: nil, name: "extra.bin", path: URL(fileURLWithPath: "/tmp/extra.bin")),
            ],
            correct: 1, incorrect: 1, missing: 1, surplus: 1
        )
    }

    @Test("includes only missing/incorrect entries, grouped by game")
    func includesOnlyMissingAndIncorrect() {
        let xml = FixDatExporter.generate(from: report(), datName: "Test DAT")
        #expect(xml.contains("mslug.bin"))
        #expect(xml.contains("mslug2.bin"))
        #expect(!xml.contains("mslug3.bin"), "correct entries shouldn't appear in a fixdat")
        #expect(!xml.contains("extra.bin"), "surplus (game-less) entries shouldn't appear in a fixdat")
    }

    @Test("round-trips through LogiqxDATParser with the expected hashes intact")
    func roundTripsThroughLogiqxParser() throws {
        let xml = FixDatExporter.generate(from: report(), datName: "Test DAT")
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))

        #expect(dat.games.count == 1)
        let game = try #require(dat.games.first)
        #expect(game.name == "mslug")
        #expect(game.roms.count == 2)

        let missingRom = try #require(game.roms.first { $0.name == "mslug.bin" })
        #expect(missingRom.size == 4)
        #expect(missingRom.crc == "d87f7e0c")
        #expect(missingRom.sha1 == "a94a8fe5ccb19ba61c4c0873d391e987982fbbd3")

        let incorrectRom = try #require(game.roms.first { $0.name == "mslug2.bin" })
        #expect(incorrectRom.size == 8)
        #expect(incorrectRom.crc == "e7b9ed24")
    }

    @Test("escapes XML-special characters in game and rom names")
    func escapesSpecialCharacters() throws {
        let report = AuditReport(
            entries: [
                AuditEntry(status: .missing, game: "Foo & Bar <Rev 1>", name: "foo\"bar.bin", path: nil, expectedSize: 1),
            ],
            correct: 0, incorrect: 0, missing: 1, surplus: 0
        )
        let xml = FixDatExporter.generate(from: report, datName: "Test")
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))

        let game = try #require(dat.games.first)
        #expect(game.name == "Foo & Bar <Rev 1>")
        #expect(game.roms.first?.name == "foo\"bar.bin")
    }

    @Test("an all-correct report yields an empty fixdat with no games")
    func emptyWhenNothingIsMissing() throws {
        let report = AuditReport(
            entries: [AuditEntry(status: .correct, game: "mslug", name: "mslug.bin", path: URL(fileURLWithPath: "/tmp/mslug.bin"))],
            correct: 1, incorrect: 0, missing: 0, surplus: 0
        )
        let xml = FixDatExporter.generate(from: report, datName: "Test")
        let dat = try LogiqxDATParser.parse(data: Data(xml.utf8))
        #expect(dat.games.isEmpty)
    }
}
