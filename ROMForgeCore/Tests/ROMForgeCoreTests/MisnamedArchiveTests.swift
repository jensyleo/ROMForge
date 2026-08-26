// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

/// `SurplusFile.misnamedArchiveForGameName` — jensyleo's own ≥50% criterion
/// (2026-08-06), after renaming `1943.zip` to `1949.zip` and seeing it
/// reported as a duplicate rather than as a filename to fix.
@Suite("Misnamed archive detection")
struct MisnamedArchiveTests {
    /// `count` roms with distinct, predictable hashes.
    ///
    /// Every hash must depend on `prefix` as well as the index: `romsByHash`
    /// indexes by crc32, md5 AND sha1, so a fixture where only the crc varied
    /// by prefix still cross-attributed every "stranger" rom to the game
    /// through its colliding sha1 — which silently turned a 50%-split fixture
    /// into a 100% one and made a threshold test pass for the wrong reason.
    private func roms(_ count: Int, prefix: String) -> [DATRom] {
        (0..<count).map { i in
            let seed = "\(prefix)-\(i)"
            let digits = seed.unicodeScalars.map { String(format: "%02x", $0.value % 256) }.joined()
            let sha1 = String((digits + String(repeating: "0", count: 40)).prefix(40))
            return DATRom(
                name: "\(prefix)_\(i).bin", size: Int64(100 + i),
                crc: String(sha1.prefix(8)), md5: nil, sha1: sha1
            )
        }
    }

    private func entry(archive: String, rom: DATRom, folder: String = "OTHER") -> HashedFile {
        HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/\(folder)/\(archive).zip"), name: rom.name, size: rom.size),
            hash: FileHash(crc32: rom.crc, md5: nil, sha1: rom.sha1)
        )
    }

    @Test("renaming a game's whole archive is reported as that game's misnamed archive, not as a duplicate")
    func renamedWholeArchiveIsFlaggedAsMisnamed() throws {
        // The exact live case: `1943.zip` renamed to `1949.zip`. Every one of
        // its 38 files is a rom of `1943`, and no `1943.zip` exists anywhere.
        let gameRoms = roms(38, prefix: "bm")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: gameRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        let files = gameRoms.map { entry(archive: "1949", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        // The game never CLAIMS these roms — they may only ever come from its
        // own correctly-named archive (the 2026-08-05 Finder philosophy), so
        // nothing here turns green. It reports `.foundElsewhere` instead,
        // pointing at the renamed archive: the content is genuinely visible
        // on disk, just not where this game's own archive should be.
        #expect(
            report.games.first!.matches.allSatisfy {
                if case .foundElsewhere(let file) = $0.status {
                    file.file.url.lastPathComponent == "1949.zip"
                } else { false }
            },
            "roms are seen in the renamed archive but never claimed from it"
        )
        #expect(report.surplusFiles.count == 38)
        #expect(
            report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == "1943" },
            "every file in the renamed archive must point at the game it really belongs to"
        )
    }

    @Test("an unrelated archive sharing only a couple of roms with a game is NEVER called misnamed — the 50% bar is what makes this safe")
    func sharedRomsAloneNeverTripTheThreshold() throws {
        // The false positive that sank the earlier "≥2 matching roms"
        // version of this idea: unrelated boards genuinely share small
        // hardware roms (CPS1 PALs, filler/padding). Here 2 of a real, ~20-rom
        // game's OWN roms show up in a junk archive — real content, but
        // nowhere near what that game actually needs.
        //
        // The game is deliberately declared with its FULL, realistic rom
        // count (20) — `sharedRoms` is only the 2 of those 20 that happen to
        // sit in this junk archive; `missingRoms` are the other 18 the
        // archive does NOT have. Measuring "2 of ghouls' own 20 roms present
        // here" (10%) is the whole point of the 2026-08-11 refinement; an
        // earlier version of this test declared the game with ONLY 2 roms
        // total, which made 2/2 = 100% under the new game-based measure — a
        // fixture bug that no longer tested the scenario its own name claims.
        let sharedRoms = roms(2, prefix: "pal")
        let missingRoms = roms(18, prefix: "ownmissing")
        let ownRoms = roms(18, prefix: "own")
        let game = DATGame(name: "ghouls", description: "Ghouls'n Ghosts", cloneOf: nil, romOf: nil, roms: sharedRoms + missingRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        // "junkbox" holds the 2 shared roms plus 18 files the DAT knows
        // nothing about at all (NOT `missingRoms` — those are genuinely
        // absent everywhere, which is exactly what makes this ghouls'
        // archive only 10% complete rather than 100%).
        let files = (sharedRoms + ownRoms).map { entry(archive: "junkbox", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        #expect(report.surplusFiles.count == 20)
        #expect(
            report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil },
            "2 of ghouls' 20 own roms (10%) must never make this ghouls' misnamed archive"
        )
    }

    @Test("exactly half of a game's own roms present is NOT enough — the bar is 60%, measured against what the game needs")
    func exactlyHalfOfTheGamesOwnRomsDoesNotMeetTheBar() throws {
        // jensyleo raised the bar from 50% to 60% themselves (2026-08-06) on
        // spotting that "at least half" is satisfiable by BOTH sides of an
        // evenly-split archive. Refined 2026-08-11 to measure against the
        // GAME's own total rom count rather than the archive's file count —
        // here `1943` declares 10 roms total, and only 5 of them (half) sit
        // in this archive; the other 5 files present are unrelated strangers,
        // never part of `1943` at all.
        let presentRoms = roms(5, prefix: "bm")
        let missingRoms = roms(5, prefix: "bmmissing")
        let strangers = roms(5, prefix: "xx")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: presentRoms + missingRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        let files = (presentRoms + strangers).map { entry(archive: "1949", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        #expect(report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil })
    }

    @Test("exactly 60% of a game's own roms present DOES qualify — the bar is inclusive")
    func exactlySixtyPercentOfTheGamesOwnRomsQualifies() throws {
        // `1943` declares 10 roms total; 6 of them (60%) sit in this archive,
        // alongside some unrelated strangers that never count either way.
        let presentRoms = roms(6, prefix: "bm")
        let missingRoms = roms(4, prefix: "bmmissing")
        let strangers = roms(4, prefix: "xx")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: presentRoms + missingRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        let files = (presentRoms + strangers).map { entry(archive: "1949", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        #expect(report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == "1943" })
    }

    @Test("junk padding an otherwise-complete set no longer dilutes anything — the false negative the file-count version had")
    func junkAlongsideACompleteSetNoLongerDilutesTheMeasure() throws {
        // jensyleo's own motivating case for the 2026-08-11 refinement: a
        // nearly-complete 38-rom `1943` set that also picked up a dozen junk
        // files. Under the OLD file-count measure this read 38/50 = 76% —
        // which actually still passed, but the point stands structurally:
        // however much junk piles on top, all 38 of 1943's own roms being
        // present must read as 100% of what THE GAME needs, never diluted by
        // how much unrelated clutter happens to share the same zip.
        let gameRoms = roms(38, prefix: "bm")
        let junk = roms(20, prefix: "screenshot")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: gameRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        let files = (gameRoms + junk).map { entry(archive: "1949", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        let romEntries = report.surplusFiles.filter { $0.file.file.name.hasPrefix("bm_") }
        #expect(romEntries.count == 38)
        #expect(romEntries.allSatisfy { $0.misnamedArchiveForGameName == "1943" })
    }

    @Test("an archive split 50/50 between TWO games, each fully present, is attributed to neither — a real tie under the new measure")
    func aFiftyFiftyTieBetweenTwoGamesResolvesToNeither() throws {
        // jensyleo's own question (2026-08-06): "¿cómo hacemos para el caso
        // especial de 50% vs 50%?". Under the 2026-08-11 game-based measure,
        // two games with different rom counts generally CAN'T both qualify
        // (see `meetsMisnamedThreshold`'s own doc comment on why the old
        // "structurally impossible" proof no longer holds) — but two games
        // that each declare exactly 5 roms, all 5 present in the same
        // 10-file archive, both read 100% and DO produce a real tie. The
        // `qualifying.count == 1` check must still resolve it to neither,
        // exactly as it did under the old measure — just for a genuinely
        // possible tie now, not a mathematically foreclosed one.
        let aRoms = roms(5, prefix: "aa")
        let bRoms = roms(5, prefix: "bb")
        let gameA = DATGame(name: "gamea", description: "Game A", cloneOf: nil, romOf: nil, roms: aRoms)
        let gameB = DATGame(name: "gameb", description: "Game B", cloneOf: nil, romOf: nil, roms: bRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [gameA, gameB])
        let files = (aRoms + bRoms).map { entry(archive: "mixedbag", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        #expect(report.surplusFiles.count == 10)
        #expect(
            report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil },
            "a 50/50 split (each side 100% of ITS OWN roms) must never be attributed to an arbitrarily-chosen side"
        )
    }

    @Test("when the game ALSO owns a correctly-named archive, the extra copy stays a duplicate rather than becoming 'misnamed'")
    func aSpareCopyStaysADuplicate() throws {
        // jensyleo's own distinction: `1949.zip` is only "1943 under the
        // wrong name" while no real `1943.zip` exists. Once one does, the
        // renamed one is genuinely a spare copy — and mislabelling it as a
        // rename-to-fix would tell the user to overwrite their good set.
        let gameRoms = roms(38, prefix: "bm")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: gameRoms)
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game])
        let correctlyNamed = gameRoms.map { entry(archive: "1943", rom: $0, folder: "CPS1") }
        let renamedSpare = gameRoms.map { entry(archive: "1949", rom: $0, folder: "OTHER") }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: correctlyNamed + renamedSpare)

        #expect(report.games.first!.matches.allSatisfy { if case .correct = $0.status { true } else { false } })
        #expect(report.surplusFiles.count == 38)
        #expect(
            report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil },
            "with a real 1943.zip present, the renamed copy is a duplicate, not a rename to fix"
        )
        #expect(report.surplusFiles.allSatisfy { $0.requiredByGameDescription == "1943: The Battle of Midway (Euro)" })
    }

    @Test("a genuinely unknown archive (nothing in it matches any DAT rom) is never proposed as a rename — it just stays unknown")
    func pureJunkIsNeverProposedAsARename() throws {
        // jensyleo's own observation (2026-08-06): "bien que no revise nada
        // para archivos como XYZ ya que no importan… si fue casualidad, igual
        // documéntalo ya que es un comportamiento esperado."
        //
        // It isn't a coincidence — it falls straight out of the criterion.
        // The 60% tally only ever counts files whose hash matches a real DAT
        // rom, so a file the DAT knows nothing about contributes zero and can
        // never push any game to the bar. A junk archive therefore has an
        // empty tally, no game qualifies, and nothing is ever suggested.
        // Pinned by this test so it stays true by design rather than by luck:
        // a rename suggestion on junk would be actively harmful (it would
        // invite the user to rename a screenshot into a game's set name).
        let realGame = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: roms(38, prefix: "bm"))
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [realGame])
        // "TEST 1.zip" holding screenshots — the real live case. None of these
        // hashes appear anywhere in the DAT.
        let junk = roms(6, prefix: "screenshot").map { entry(archive: "TEST 1", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: junk)

        #expect(report.surplusFiles.count == 6)
        #expect(
            report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil },
            "junk must never be proposed as some game's misnamed archive"
        )
        // And it isn't quietly attributed to a game some other way either.
        #expect(report.surplusFiles.allSatisfy { $0.requiredByGameDescription == nil })
        #expect(report.surplusFiles.allSatisfy { !$0.isInKnownArchive })
        // The game itself is untouched by any of this.
        #expect(report.games.first!.matches.allSatisfy { $0.status == .missing })
    }

    @Test("an archive named after a DIFFERENT real machine is never re-attributed to whatever its contents match")
    func archiveNamedAfterAnotherRealMachineIsLeftAlone() throws {
        // `1943kai.zip` is a real, separate machine. If a user wrongly filled
        // it with 1943's roms, that's "1943kai's archive has wrong content" —
        // not "1943 is misnamed". Re-attributing it would hide the real
        // problem and invent a rename that clobbers a legitimate set name.
        let gameRoms = roms(10, prefix: "bm")
        let game = DATGame(name: "1943", description: "1943: The Battle of Midway (Euro)", cloneOf: nil, romOf: nil, roms: gameRoms)
        let otherMachine = DATGame(name: "1943kai", description: "1943 Kai", cloneOf: nil, romOf: nil, roms: roms(3, prefix: "kai"))
        let dat = DATFile(header: DATHeader(name: "t", description: "t", version: "1", author: "t"), games: [game, otherMachine])
        let files = gameRoms.map { entry(archive: "1943kai", rom: $0) }

        let report = try ROMMatcher.match(dat: dat, hashedFiles: files)

        #expect(report.surplusFiles.allSatisfy { $0.misnamedArchiveForGameName == nil })
    }
}
