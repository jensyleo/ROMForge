// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("MaintenanceDonorDetector")
struct MaintenanceDonorDetectorTests {
    private func rom(name: String, size: Int64, crc: String) -> DATRom {
        DATRom(name: name, size: size, crc: crc, md5: nil, sha1: nil)
    }

    private func missingEntry(game: String, name: String, size: Int64, crc: String) -> AuditEntry {
        AuditEntry(status: .missing, game: game, name: name, path: nil, expectedSize: size, expectedCRC: crc)
    }

    private func donor(name: String, size: Int64, crc: String) -> HashedFile {
        HashedFile(file: ScannedFile(url: URL(fileURLWithPath: "/maintenance/\(name)"), name: name, size: size), hash: FileHash(crc32: crc, md5: "0", sha1: "0"))
    }

    private func zipFile(archive: String, entryName: String, size: Int64, crc: String) -> HashedFile {
        HashedFile(file: ScannedFile(url: URL(fileURLWithPath: "/roms/\(archive).zip"), name: entryName, size: size), hash: FileHash(crc32: crc, md5: "0", sha1: "0"))
    }

    @Test("a missing rom whose exact content sits in the donor pool IS flagged when its own game still has a real anchor on disk")
    func flagsMissingRomWithMatchingDonorAndAnchor() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let missingRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [anchorRom, missingRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "gng", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: missingRom, status: .missing),
            ])],
            surplusFiles: []
        )
        let entry = missingEntry(game: "gng", name: "mm_c_03", size: 32768, crc: "1def138a")
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 1, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "mm_c_03", size: 32768, crc: "1def138a")]
        )

        #expect(result.entries.first { $0.name == "mm_c_03" }?.hasMaintenanceDonor == true)
        #expect(result.entries.first { $0.name == "mm_c_03" }?.status == .missing, "the real status stays .missing — this is a display-only flag, not a repair")
    }

    @Test("a rom whose status is .foundElsewhere (game-owned, content borrowed from an unrelated game's archive) IS flagged when its own game still has a real anchor and Maintenance has a matching donor — jensyleo's own real incident (2026-09-21): NAOMI BIOS's 315-6146.bin, also declared by unrelated 'mvsc2', reported .incorrect/foundElsewhere (never .missing), and this flag used to require exactly .missing")
    func flagsFoundElsewhereRomWithMatchingDonorAndAnchor() {
        let anchorRom = rom(name: "boot.bin", size: 16384, crc: "ecfccf07")
        let sharedRom = rom(name: "315-6146.bin", size: 128, crc: "1def138a")
        let game = DATGame(name: "naomi", description: "NAOMI BIOS", cloneOf: nil, romOf: nil, roms: [anchorRom, sharedRom])
        let elsewhereFile = zipFile(archive: "mvsc2", entryName: "315-6146.bin", size: 128, crc: "1def138a")
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "naomi", entryName: "boot.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: sharedRom, status: .foundElsewhere(elsewhereFile)),
            ])],
            surplusFiles: []
        )
        let entry = AuditEntry(
            status: .incorrect, game: "naomi", foundElsewhereArchiveName: "mvsc2.zip",
            name: "315-6146.bin", path: elsewhereFile.file.url, expectedSize: 128, expectedCRC: "1def138a"
        )
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 1, missing: 0, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "315-6146.bin", size: 128, crc: "1def138a")]
        )

        #expect(result.entries.first { $0.name == "315-6146.bin" }?.hasMaintenanceDonor == true)
        #expect(result.entries.first { $0.name == "315-6146.bin" }?.status == .incorrect, "the real status stays .incorrect — this is a display-only flag, not a repair")
    }

    @Test("a game with NO real anchor at all (its own archive is entirely absent) is NEVER flagged, even with a matching donor for every rom — real bug found live by jensyleo (2026-09-14): 'Find ROMs…' can never write anywhere without a real anchor to attach to, so the yellow indicator was a false promise")
    func doesNotFlagWhenGameHasNoAnchorAtAll() {
        let onlyRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [onlyRom])
        // Every rom of this game is .missing — no .correct/.misnamed match
        // anywhere, so `existingAnchor` finds nothing to attach a repair to.
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: onlyRom, status: .missing)])],
            surplusFiles: []
        )
        let entry = missingEntry(game: "gng", name: "mm_c_03", size: 32768, crc: "1def138a")
        let report = AuditReport(entries: [entry], correct: 0, incorrect: 0, missing: 1, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "mm_c_03", size: 32768, crc: "1def138a")]
        )

        #expect(result.entries.first?.hasMaintenanceDonor == false)
    }

    @Test("a missing rom with no matching donor is left unflagged")
    func doesNotFlagWithoutMatchingDonor() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let missingRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [anchorRom, missingRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "gng", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: missingRom, status: .missing),
            ])],
            surplusFiles: []
        )
        let entry = missingEntry(game: "gng", name: "mm_c_03", size: 32768, crc: "1def138a")
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 1, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "unrelated.bin", size: 16384, crc: "deadbeef")]
        )

        #expect(result.entries.first?.hasMaintenanceDonor == false)
    }

    @Test("a correct/present rom is never flagged, even if a donor coincidentally shares its content")
    func neverFlagsNonMissingEntries() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [anchorRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "gng", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
            ])],
            surplusFiles: []
        )
        let correctEntry = AuditEntry(status: .correct, game: "gng", name: "gg1.bin", path: URL(fileURLWithPath: "/roms/gng.zip"), expectedSize: 16384, expectedCRC: "ecfccf07")
        let report = AuditReport(entries: [correctEntry], correct: 1, incorrect: 0, missing: 0, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "gg1.bin", size: 16384, crc: "ecfccf07")]
        )

        #expect(result.entries.first?.hasMaintenanceDonor == false)
    }

    @Test("an empty donor pool is a no-op")
    func noOpWithNoDonors() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let missingRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [anchorRom, missingRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "gng", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: missingRom, status: .missing),
            ])],
            surplusFiles: []
        )
        let entry = missingEntry(game: "gng", name: "mm_c_03", size: 32768, crc: "1def138a")
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 0, missing: 1, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(in: report, matchReport: matchReport, donorFiles: [])

        #expect(result.entries.first?.hasMaintenanceDonor == false)
    }

    @Test("a misfiled rom found elsewhere (game: nil, requiredByGameMachineName set to the real owner) IS flagged when that real owner has a real anchor and a matching donor — jensyleo's own real collection (2026-09-17): CAPCOM/CPS2/naomi.zip's own extra rom genuinely belongs to machine 'naomi' elsewhere in the same system, and right-clicking THIS stray file's own row should offer the same 'Repair from Maintenance Folder' fix as naomi's own missing-rom row would")
    func flagsMisfiledSurplusRomWhoseRealOwnerHasAnchorAndDonor() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let missingRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "naomi", description: "Naomi Bios", cloneOf: nil, romOf: nil, roms: [anchorRom, missingRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "naomi", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: missingRom, status: .missing),
            ])],
            surplusFiles: []
        )
        // The stray CPS2 file's own entry — physically present, just not
        // where the DAT says it belongs. `game` stays `nil` (nothing
        // claimed it here), `requiredByGameMachineName` names the real
        // owner.
        let strayEntry = AuditEntry(
            status: .incorrect, game: nil, requiredByGameDescription: "Naomi Bios", requiredByGameMachineName: "naomi",
            name: "mm_c_03", path: URL(fileURLWithPath: "/roms/CPS2/naomi.zip")
        )
        let report = AuditReport(entries: [strayEntry], correct: 1, incorrect: 1, missing: 0, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "mm_c_03", size: 32768, crc: "1def138a")]
        )

        #expect(result.entries.first?.hasMaintenanceDonor == true)
        #expect(result.entries.first?.status == .incorrect, "the real status stays .incorrect — this is a display-only flag, not a repair")
    }

    @Test("the same misfiled-rom case is NEVER flagged when the real owner has no anchor at all — same guard as the game-owned case above")
    func doesNotFlagMisfiledSurplusRomWhenRealOwnerHasNoAnchor() {
        let onlyRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "naomi", description: "Naomi Bios", cloneOf: nil, romOf: nil, roms: [onlyRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [RomMatch(rom: onlyRom, status: .missing)])],
            surplusFiles: []
        )
        let strayEntry = AuditEntry(
            status: .incorrect, game: nil, requiredByGameDescription: "Naomi Bios", requiredByGameMachineName: "naomi",
            name: "mm_c_03", path: URL(fileURLWithPath: "/roms/CPS2/naomi.zip")
        )
        let report = AuditReport(entries: [strayEntry], correct: 0, incorrect: 1, missing: 0, surplus: 0)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "mm_c_03", size: 32768, crc: "1def138a")]
        )

        #expect(result.entries.first?.hasMaintenanceDonor == false)
    }

    @Test("flagging never changes the report's own status counts")
    func doesNotChangeCounts() {
        let anchorRom = rom(name: "gg1.bin", size: 16384, crc: "ecfccf07")
        let missingRom = rom(name: "mm_c_03", size: 32768, crc: "1def138a")
        let game = DATGame(name: "gng", description: "Ghosts'n Goblins", cloneOf: nil, romOf: nil, roms: [anchorRom, missingRom])
        let matchReport = MatchReport(
            games: [GameMatchResult(game: game, matches: [
                RomMatch(rom: anchorRom, status: .correct(zipFile(archive: "gng", entryName: "gg1.bin", size: 16384, crc: "ecfccf07"))),
                RomMatch(rom: missingRom, status: .missing),
            ])],
            surplusFiles: []
        )
        let entry = missingEntry(game: "gng", name: "mm_c_03", size: 32768, crc: "1def138a")
        let report = AuditReport(entries: [entry], correct: 1, incorrect: 2, badDump: 3, missing: 4, surplus: 5, unverifiable: 6, duplicateSets: 7)

        let result = MaintenanceDonorDetector.markingDonorsAvailable(
            in: report, matchReport: matchReport, donorFiles: [donor(name: "mm_c_03", size: 32768, crc: "1def138a")]
        )

        #expect(result.correct == 1 && result.incorrect == 2 && result.badDump == 3 && result.missing == 4)
        #expect(result.surplus == 5 && result.unverifiable == 6 && result.duplicateSets == 7)
    }
}
