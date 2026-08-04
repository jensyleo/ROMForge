// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("ROMMatcher")
struct ROMMatcherTests {
    private func hashedFile(name: String, size: Int64, crc: String, sha1: String) -> HashedFile {
        HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/\(name)"), name: name, size: size),
            hash: FileHash(crc32: crc, md5: "00000000000000000000000000000000", sha1: sha1)
        )
    }

    /// A zip-entry-shaped `HashedFile`: `url` is the *containing archive*
    /// (distinct from `name`, the entry's own name) — this is what makes
    /// `ROMMatcher` treat the scan as archive-organized and apply its
    /// per-archive scoping, unlike the loose-file-shaped `hashedFile(...)`
    /// above (whose `url` always equals its own `name`).
    private func zipEntryHashedFile(archiveName: String, entryName: String, size: Int64, crc: String, sha1: String) -> HashedFile {
        HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/\(archiveName).zip"), name: entryName, size: size),
            hash: FileHash(crc32: crc, md5: "00000000000000000000000000000000", sha1: sha1)
        )
    }

    private let dat = DATFile(
        header: DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge"),
        games: [
            DATGame(
                name: "Correct Game",
                description: "Correct Game",
                cloneOf: nil,
                romOf: nil,
                roms: [DATRom(name: "correct.bin", size: 100, crc: "aaaaaaaa", md5: nil, sha1: "1111111111111111111111111111111111111111")]
            ),
            DATGame(
                name: "Misnamed Game",
                description: "Misnamed Game",
                cloneOf: nil,
                romOf: nil,
                roms: [DATRom(name: "expected-name.bin", size: 200, crc: "bbbbbbbb", md5: nil, sha1: "2222222222222222222222222222222222222222")]
            ),
            DATGame(
                name: "Missing Game",
                description: "Missing Game",
                cloneOf: nil,
                romOf: nil,
                roms: [DATRom(name: "missing.bin", size: 300, crc: "cccccccc", md5: nil, sha1: "3333333333333333333333333333333333333333")]
            ),
        ]
    )

    @Test("marks a rom correct when name, size and hash all match")
    func marksCorrectWhenEverythingMatches() {
        let local = hashedFile(name: "correct.bin", size: 100, crc: "aaaaaaaa", sha1: "1111111111111111111111111111111111111111")
        let report = ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(local))
    }

    @Test("marks a rom misnamed when hash matches but filename differs")
    func marksMisnamedWhenOnlyNameDiffers() {
        let local = hashedFile(name: "wrong-name.bin", size: 200, crc: "bbbbbbbb", sha1: "2222222222222222222222222222222222222222")
        let report = ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Misnamed Game" }!
        #expect(result.matches[0].status == .misnamed(local))
    }

    @Test("marks a rom missing when no local file matches")
    func marksMissingWhenNoFileMatches() {
        let report = ROMMatcher.match(dat: dat, hashedFiles: [])

        let result = report.games.first { $0.game.name == "Missing Game" }!
        #expect(result.matches[0].status == .missing)
    }

    @Test("does not match on filename alone when hash differs — reports a genuine hash mismatch (Bad), not correct or plain missing")
    func doesNotMatchOnNameAloneWhenHashDiffers() {
        // Same name and size as the expected ROM, but a different hash —
        // must not be treated as correct. jensyleo's own definition
        // (2026-08-04): a file genuinely sitting in this rom's own slot
        // (same name) with the wrong content is `.hashMismatch` ("Bad"),
        // distinct from `.missing` (nothing there at all). Left unconsumed
        // (same as `.foundElsewhere`), so it still shows up as surplus too.
        let local = hashedFile(name: "correct.bin", size: 100, crc: "ffffffff", sha1: "9999999999999999999999999999999999999999")
        let report = ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .hashMismatch(local))
        #expect(report.surplusFiles == [local])
    }

    @Test("a hash the DAT declares but the scan didn't compute (HashAlgorithms skipped it) doesn't reject an otherwise-correct match")
    func uncomputedHashDoesNotRejectAMatch() {
        // The DAT declares both crc and sha1 for "Correct Game", but this
        // scan only computed crc32 (as if `HashAlgorithms` excluded sha1
        // for speed) — matching must still succeed on the hash that *was*
        // computed, not silently fail because a declared-but-uncomputed one
        // can't be confirmed.
        let local = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/correct.bin"), name: "correct.bin", size: 100),
            hash: FileHash(crc32: "aaaaaaaa", md5: nil, sha1: nil)
        )
        let report = ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(local))
    }

    @Test("leaves unmatched local files as surplus")
    func leavesUnmatchedFilesAsSurplus() {
        let extra = hashedFile(name: "extra.bin", size: 999, crc: "deadbeef", sha1: "0000000000000000000000000000000000000000")
        let report = ROMMatcher.match(dat: dat, hashedFiles: [extra])

        #expect(report.surplusFiles == [extra])
    }

    @Test("matches a headered local file against a headerless DAT entry via its header-stripped identity")
    func matchesViaHeaderStrippedIdentity() {
        // The DAT declares the headerless (No-Intro-style) hash/size, but
        // the local file is a raw iNES-headered dump — same game data, 16
        // extra header bytes. Only the strip-and-rehash path can find this.
        let headerlessDat = DATFile(
            header: dat.header,
            games: [
                DATGame(name: "NES Game", description: "NES Game", cloneOf: nil, romOf: nil,
                        roms: [DATRom(name: "game.nes", size: 29, crc: "cbf43926", md5: nil, sha1: nil)]),
            ]
        )
        let strippedHash = FileHasher.hash(data: Data("123456789".utf8)) // known CRC32 cbf43926
        let local = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/game.nes"), name: "game.nes", size: 45),
            hash: FileHash(crc32: "00000000", md5: "0", sha1: "0"), // the whole (headered) file's own hash — irrelevant here
            headerStripped: HeaderStrippedHash(rule: .iNES, size: 29, hash: strippedHash)
        )

        let report = ROMMatcher.match(dat: headerlessDat, hashedFiles: [local])
        let result = report.games.first { $0.game.name == "NES Game" }!
        #expect(result.matches[0].status == .correct(local, viaHeaderStrip: true))
        #expect(report.surplusFiles.isEmpty)
    }

    @Test("does not double-match the same local file to two different roms")
    func doesNotDoubleMatchTheSameFile() {
        let sharedDat = DATFile(
            header: dat.header,
            games: [
                DATGame(name: "A", description: "A", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
                DATGame(name: "B", description: "B", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
            ]
        )
        let local = hashedFile(name: "shared.bin", size: 50, crc: "12345678", sha1: "4444444444444444444444444444444444444444")
        let report = ROMMatcher.match(dat: sharedDat, hashedFiles: [local])

        let statuses = report.games.map(\.matches[0].status)
        #expect(statuses.filter { $0 == .correct(local) }.count == 1)
        // Real bug found live by jensyleo (2026-08-04), stated as a general
        // rule: a rom that's genuinely visible somewhere in the scan is
        // never truly absent, even when (as here) some other rom slot
        // already legitimately claimed the one physical file — it must
        // report `.foundElsewhere`, not `.missing`.
        #expect(statuses.contains(.foundElsewhere(local)))
    }

    @Test("in an archive-organized scan, a game whose own archive is missing does not STEAL (claim) a file from another real game's own-named archive")
    func doesNotStealFromAnotherGamesOwnArchive() {
        // Both games declare the exact same rom (mirrors real MAME DATs,
        // where several unrelated machines independently declare a shared
        // hardware ROM as their own, unmerged, rom) — only "B"'s archive is
        // actually present. "A" must never *claim* (consume) "B"'s file.
        //
        // "A" reports plain `.missing`, NOT `.foundElsewhere`: jensyleo's own
        // report (2026-08-04, second round) — this exact shape is the real
        // `1943j` bug (a clone the user doesn't own at all, whose roms shared
        // with its parent are visibly sitting in the parent's own complete
        // archive) showing up yellow/"Bad file name" instead of red/missing.
        // "A" owns nothing here (no `A.zip` in the scan at all), and the
        // content is only visible inside an archive that genuinely belongs
        // to another real DAT game, so there's no naming/layout problem to
        // report — the user simply doesn't have "A". `.foundElsewhere` stays
        // reserved for the two cases that really are layout problems: a game
        // that does own files but has one filed in the wrong place (the
        // NEOGEO shared-BIOS case), and content sitting in an archive
        // belonging to no DAT game at all (a whole archive the user renamed
        // — see `nonMergedCloneFamilyStillNeverBorrowsFromAnotherArchive`).
        let sharedDat = DATFile(
            header: dat.header,
            games: [
                DATGame(name: "A", description: "A", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
                DATGame(name: "B", description: "B", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
            ]
        )
        let onlyBsArchive = zipEntryHashedFile(archiveName: "B", entryName: "shared.bin", size: 50, crc: "12345678", sha1: "4444444444444444444444444444444444444444")
        let report = ROMMatcher.match(dat: sharedDat, hashedFiles: [onlyBsArchive])

        let resultA = report.games.first { $0.game.name == "A" }!
        let resultB = report.games.first { $0.game.name == "B" }!
        #expect(resultA.matches[0].status == .missing)
        #expect(resultB.matches[0].status == .correct(onlyBsArchive))
    }

    @Test("a clone the user doesn't own at all reports missing, not a layout problem, even though its parent-shared roms sit in the parent's own archive")
    func unownedCloneReportsMissingRatherThanFoundElsewhere() {
        // The real shape jensyleo hit live (2026-08-04): MAME's `1943`
        // family. The parent's archive is fully present; the clone's own
        // archive is absent entirely, and its genuinely unique roms exist
        // nowhere in the scan. Under Un-merged the clone's expected list
        // includes every rom it shares with the parent, all of which ARE
        // visible inside the parent's own `1943.zip` — which used to make
        // every such clone report `.foundElsewhere` (→ yellow "Bad file
        // name") for ~35 of its 38 roms, instead of the plain missing it
        // actually is. Not one rom of this clone may report a layout
        // problem.
        let parent = DATGame(
            name: "1943", description: "1943", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "shared.bin", size: 700, crc: "77777777", md5: nil, sha1: "7777777777777777777777777777777777777777")]
        )
        let unownedClone = DATGame(
            name: "1943j", description: "1943j", cloneOf: "1943", romOf: "1943",
            roms: [
                DATRom(name: "shared.bin", size: 700, crc: "77777777", md5: nil, sha1: "7777777777777777777777777777777777777777"),
                DATRom(name: "clone-unique.bin", size: 800, crc: "88888888", md5: nil, sha1: "8888888888888888888888888888888888888888"),
            ]
        )
        let cloneFamilyDAT = DATFile(header: dat.header, games: [parent, unownedClone], mergeMode: .nonMerged)
        let onlyParentsArchive = zipEntryHashedFile(archiveName: "1943", entryName: "shared.bin", size: 700, crc: "77777777", sha1: "7777777777777777777777777777777777777777")
        let report = ROMMatcher.match(dat: cloneFamilyDAT, hashedFiles: [onlyParentsArchive])

        let parentResult = report.games.first { $0.game.name == "1943" }!
        let cloneResult = report.games.first { $0.game.name == "1943j" }!
        #expect(parentResult.matches[0].status == .correct(onlyParentsArchive))
        #expect(cloneResult.matches.allSatisfy { $0.status == .missing })
    }
    // Note: `doesNotDoubleMatchTheSameFile` above already covers the
    // loose-file case of this same rule (two games sharing one rom, only
    // loose files in the scan, no zip archives at all) — jensyleo's own
    // explicit statement of the general rule (2026-08-04) was "another
    // game, a loose file, a different path, etc.", and that test's `local`
    // fixture is exactly a loose file (`url == name`).

    @Test("foundElsewhere never fires on a bare size coincidence — only a real declared hash may satisfy it")
    func foundElsewhereNeverFiresOnSizeAloneAcrossGames() {
        // Real bug found live by jensyleo (2026-08-04): a whole "OTHER"
        // system folder (590 games, almost none physically owned) showed
        // *every single game* resolving to the one archive that actually
        // was present, all reporting "Bad file name" — because each
        // unowned game's real declared hash was never found anywhere
        // (its own archive is simply absent), `candidateIndices` fell all
        // the way through to its last-resort size-only tier, and that
        // *coincidental* same-size match got reported as `.foundElsewhere`
        // — resurrecting the exact cross-game "steal" problem
        // `isInClaimedArchive` exists to prevent. "A" declares a real CRC
        // that matches nothing in the scan at all; "PresentGame"'s own
        // archive happens to contain a same-*sized*, differently-hashed
        // file. "A" must report `.missing`, never `.foundElsewhere`.
        let unownedGame = DATGame(
            name: "A", description: "A", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "a.bin", size: 65536, crc: "aaaaaaaa", md5: nil, sha1: nil)]
        )
        let presentGame = DATGame(
            name: "PresentGame", description: "PresentGame", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "present.bin", size: 65536, crc: "bbbbbbbb", md5: nil, sha1: nil)]
        )
        let sizeCoincidenceDAT = DATFile(header: dat.header, games: [unownedGame, presentGame])
        let presentFile = zipEntryHashedFile(archiveName: "PresentGame", entryName: "present.bin", size: 65536, crc: "bbbbbbbb", sha1: "6666666666666666666666666666666666666666")
        let report = ROMMatcher.match(dat: sizeCoincidenceDAT, hashedFiles: [presentFile])

        let resultA = report.games.first { $0.game.name == "A" }!
        #expect(resultA.matches[0].status == .missing)
    }

    @Test("in an archive-organized scan, a whole archive renamed by the user is still found via an unclaimed (non-DAT-name) archive")
    func findsRomInsideARenamedArchive() {
        // The archive itself ("renamed-by-user.zip") doesn't match any DAT
        // game's own name, so it's not "claimed" by any other game — a
        // real game whose own archive is absent can still resolve its rom
        // from here (the common real case: the user renamed the whole
        // archive, but its contents/entry name are untouched).
        let renamedArchive = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "expected-name.bin", size: 200, crc: "bbbbbbbb", sha1: "2222222222222222222222222222222222222222")
        let report = ROMMatcher.match(dat: dat, hashedFiles: [renamedArchive])

        let result = report.games.first { $0.game.name == "Misnamed Game" }!
        #expect(result.matches[0].status == .correct(renamedArchive))
    }

    @Test("under Un-merged mode, a game with no clone/parent relationship at all still uses the renamed-archive fallback")
    func nonMergedStandaloneGameStillBorrowsFromRenamedArchive() {
        // Real bug found live by jensyleo (2026-08-03): this test used to
        // assert the opposite (`.missing`) — Un-merged's self-containment
        // rule ("a game must never need a rom that actually lives in a
        // different file on disk, clone/bootleg/parent or otherwise") was
        // applied as one blanket DAT-wide toggle, regardless of whether
        // the game in question had any clone/parent relationship to
        // actually be strict *about*. For a system where NO game has any
        // clone anywhere (e.g. every NEOGEO title), that meant Rom merge
        // mode alone changed real audit results — a renamed archive
        // resolved fine under Split/Merged but reported `.missing` under
        // Un-merged — even though the entire concept "clone/bootleg/
        // parent" doesn't apply to "Misnamed Game" at all (`cloneOf: nil`,
        // and nothing in `dat` clones it either). Fixed by gating the
        // strict-self-containment behavior per-game, on whether that game
        // actually participates in a clone relationship — see
        // `ROMMatcher.swift`'s own `strictOwnArchiveOnly` doc comment.
        let nonMergedDAT = DATFile(header: dat.header, games: dat.games, mergeMode: .nonMerged)
        let renamedArchive = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "expected-name.bin", size: 200, crc: "bbbbbbbb", sha1: "2222222222222222222222222222222222222222")
        let report = ROMMatcher.match(dat: nonMergedDAT, hashedFiles: [renamedArchive])

        let result = report.games.first { $0.game.name == "Misnamed Game" }!
        #expect(result.matches[0].status == .correct(renamedArchive))
    }

    @Test("under Un-merged mode, a game that IS part of a real clone/parent family still never CLAIMS a rom from a renamed archive")
    func nonMergedCloneFamilyStillNeverBorrowsFromAnotherArchive() {
        // The other half of the fix above: the strictness itself is still
        // real and still applies — just correctly scoped to games that
        // actually have a clone/parent relationship, rather than to every
        // game in the DAT regardless.
        let parent = DATGame(
            name: "Parent Game", description: "Parent Game", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "parent-own.bin", size: 400, crc: "dddddddd", md5: nil, sha1: "4444444444444444444444444444444444444444")]
        )
        let clone = DATGame(
            name: "Clone Game", description: "Clone Game", cloneOf: "Parent Game", romOf: "Parent Game",
            roms: [DATRom(name: "clone-own.bin", size: 500, crc: "eeeeeeee", md5: nil, sha1: "5555555555555555555555555555555555555555")]
        )
        let nonMergedDAT = DATFile(header: dat.header, games: dat.games + [parent, clone], mergeMode: .nonMerged)
        let renamedArchive = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "clone-own.bin", size: 500, crc: "eeeeeeee", sha1: "5555555555555555555555555555555555555555")
        let report = ROMMatcher.match(dat: nonMergedDAT, hashedFiles: [renamedArchive])

        let result = report.games.first { $0.game.name == "Clone Game" }!
        // Real bug found live by jensyleo (2026-08-04): reporting this the
        // same as a truly absent rom (`.missing`) made an otherwise-intact
        // collection show as "Bad"/incomplete rather than a naming/
        // organization problem — the content genuinely exists (just in a
        // renamed archive, not this clone's own self-contained one), so it
        // must report `.foundElsewhere`, not `.missing`. It still must
        // never be *claimed* (consumed) for this clone's own completeness —
        // that's what the surrounding suite's other tests already cover.
        if case .foundElsewhere(let file) = result.matches[0].status {
            #expect(file == renamedArchive)
        } else {
            Issue.record("expected .foundElsewhere, got \(result.matches[0].status)")
        }
    }

    @Test("under Un-merged mode, a game still matches a rom that's genuinely inside its own archive")
    func nonMergedStillMatchesOwnArchive() {
        let nonMergedDAT = DATFile(header: dat.header, games: dat.games, mergeMode: .nonMerged)
        let ownArchiveFile = zipEntryHashedFile(archiveName: "Correct Game", entryName: "correct.bin", size: 100, crc: "aaaaaaaa", sha1: "1111111111111111111111111111111111111111")
        let report = ROMMatcher.match(dat: nonMergedDAT, hashedFiles: [ownArchiveFile])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(ownArchiveFile))
    }
}
