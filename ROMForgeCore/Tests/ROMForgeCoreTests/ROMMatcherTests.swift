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
    func marksCorrectWhenEverythingMatches() throws {
        let local = hashedFile(name: "correct.bin", size: 100, crc: "aaaaaaaa", sha1: "1111111111111111111111111111111111111111")
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(local))
    }

    @Test("marks a rom misnamed when hash matches but filename differs")
    func marksMisnamedWhenOnlyNameDiffers() throws {
        let local = hashedFile(name: "wrong-name.bin", size: 200, crc: "bbbbbbbb", sha1: "2222222222222222222222222222222222222222")
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Misnamed Game" }!
        #expect(result.matches[0].status == .misnamed(local))
    }

    @Test("marks a rom missing when no local file matches")
    func marksMissingWhenNoFileMatches() throws {
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [])

        let result = report.games.first { $0.game.name == "Missing Game" }!
        #expect(result.matches[0].status == .missing)
    }

    @Test("does not match on filename alone when hash differs — reports a genuine hash mismatch (Bad), not correct or plain missing")
    func doesNotMatchOnNameAloneWhenHashDiffers() throws {
        // Same name and size as the expected ROM, but a different hash —
        // must not be treated as correct. jensyleo's own definition
        // (2026-08-04): a file genuinely sitting in this rom's own slot
        // (same name) with the wrong content is `.hashMismatch` ("Bad"),
        // distinct from `.missing` (nothing there at all).
        //
        // Left unconsumed in `consumed[]` (so a coincidental hash match by
        // some OTHER rom can still claim it normally), but must NOT also
        // reappear a second time in `surplusFiles` — real bug found live by
        // jensyleo (2026-08-10, TESTING.md §9.2 scenario #8: corrupting one
        // real rom's byte in its own archive): the same physical file showed
        // up twice, once correctly as orange "Bad (hash mismatch)" and once
        // as a confusing, duplicate gray "Unrecognized" ghost row for the
        // exact same bytes. A corrupted file's real hash matches nothing
        // valid by definition, so in the overwhelmingly common case nothing
        // else will ever legitimately claim it either — reporting it via
        // `.hashMismatch` already fully explains it.
        let local = hashedFile(name: "correct.bin", size: 100, crc: "ffffffff", sha1: "9999999999999999999999999999999999999999")
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .hashMismatch(local))
        #expect(report.surplusFiles.isEmpty, "a hashMismatch file must never also appear as a surplus ghost row")
    }

    @Test("a hashMismatch file is still free to be claimed by a DIFFERENT rom it coincidentally, genuinely hash-matches")
    func hashMismatchFileStaysClaimableByAnotherRom() throws {
        // The exact case `hashMismatch`'s own "never consumed" design exists
        // for, still confirmed after the 2026-08-10 fix above: NOT tracking
        // this in `consumed[]` (only excluding it from the surplus list)
        // means a second rom whose own real, declared hash genuinely matches
        // this same file can still claim it normally.
        let elsewhereRom = DATRom(name: "elsewhere.bin", size: 100, crc: "ffffffff", md5: nil, sha1: "9999999999999999999999999999999999999999")
        let elsewhereGame = DATGame(name: "Elsewhere Game", description: "Elsewhere Game", cloneOf: nil, romOf: nil, roms: [elsewhereRom])
        let twoGameDAT = DATFile(header: dat.header, games: dat.games + [elsewhereGame])
        let local = hashedFile(name: "correct.bin", size: 100, crc: "ffffffff", sha1: "9999999999999999999999999999999999999999")

        let report = try ROMMatcher.match(dat: twoGameDAT, hashedFiles: [local])

        let misnamed = report.games.first { $0.game.name == "Correct Game" }!
        #expect(misnamed.matches[0].status == .hashMismatch(local))
        let claimed = report.games.first { $0.game.name == "Elsewhere Game" }!
        #expect(claimed.matches[0].status == .misnamed(local))
        #expect(report.surplusFiles.isEmpty)
    }

    @Test("a hash the DAT declares but the scan didn't compute (HashAlgorithms skipped it) doesn't reject an otherwise-correct match")
    func uncomputedHashDoesNotRejectAMatch() throws {
        // The DAT declares both crc and sha1 for "Correct Game", but this
        // scan only computed crc32 (as if `HashAlgorithms` excluded sha1
        // for speed) — matching must still succeed on the hash that *was*
        // computed, not silently fail because a declared-but-uncomputed one
        // can't be confirmed.
        let local = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/correct.bin"), name: "correct.bin", size: 100),
            hash: FileHash(crc32: "aaaaaaaa", md5: nil, sha1: nil)
        )
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [local])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(local))
    }

    @Test("leaves unmatched local files as surplus")
    func leavesUnmatchedFilesAsSurplus() throws {
        let extra = hashedFile(name: "extra.bin", size: 999, crc: "deadbeef", sha1: "0000000000000000000000000000000000000000")
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [extra])

        #expect(report.surplusFiles == [SurplusFile(file: extra)])
    }

    @Test("matches a headered local file against a headerless DAT entry via its header-stripped identity")
    func matchesViaHeaderStrippedIdentity() throws {
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

        let report = try ROMMatcher.match(dat: headerlessDat, hashedFiles: [local])
        let result = report.games.first { $0.game.name == "NES Game" }!
        #expect(result.matches[0].status == .correct(local, viaHeaderStrip: true))
        #expect(report.surplusFiles.isEmpty)
    }

    @Test("does not double-match the same local file to two different roms")
    func doesNotDoubleMatchTheSameFile() throws {
        let sharedDat = DATFile(
            header: dat.header,
            games: [
                DATGame(name: "A", description: "A", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
                DATGame(name: "B", description: "B", cloneOf: nil, romOf: nil, roms: [DATRom(name: "shared.bin", size: 50, crc: "12345678", md5: nil, sha1: nil)]),
            ]
        )
        let local = hashedFile(name: "shared.bin", size: 50, crc: "12345678", sha1: "4444444444444444444444444444444444444444")
        let report = try ROMMatcher.match(dat: sharedDat, hashedFiles: [local])

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
    func doesNotStealFromAnotherGamesOwnArchive() throws {
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
        let report = try ROMMatcher.match(dat: sharedDat, hashedFiles: [onlyBsArchive])

        let resultA = report.games.first { $0.game.name == "A" }!
        let resultB = report.games.first { $0.game.name == "B" }!
        #expect(resultA.matches[0].status == .missing)
        #expect(resultB.matches[0].status == .correct(onlyBsArchive))
    }

    @Test("a clone the user doesn't own at all reports missing, not a layout problem, even though its parent-shared roms sit in the parent's own archive")
    func unownedCloneReportsMissingRatherThanFoundElsewhere() throws {
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
        let report = try ROMMatcher.match(dat: cloneFamilyDAT, hashedFiles: [onlyParentsArchive])

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
    func foundElsewhereNeverFiresOnSizeAloneAcrossGames() throws {
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
        let report = try ROMMatcher.match(dat: sizeCoincidenceDAT, hashedFiles: [presentFile])

        let resultA = report.games.first { $0.game.name == "A" }!
        #expect(resultA.matches[0].status == .missing)
    }

    @Test("a surplus file inside a clone's own archive that hash-matches a rom belonging to a different game (e.g. its Split-mode parent) is tagged, not left as a plain unrecognized surplus")
    func surplusFileTaggedWhenItMatchesAnotherGamesRom() throws {
        // Real case found live by jensyleo (2026-08-04): under Split, a
        // clone's own expected rom list excludes every rom it shares with
        // its parent (`mergeName != nil`, stripped upstream by
        // `MAMESetLayoutPlanner` before `ROMMatcher` ever sees it — not
        // reproduced here, since this test operates on already-planned
        // `dat.games`, exactly like the real pipeline hands them over). A
        // real `sf2acc.zip` still physically contains that shared graphics
        // rom too (a genuine, correct dump) — with nothing in Split's own
        // per-archive scoping ever looking inside `sf2acc.zip` for
        // `sf2ce`'s own roms, it went completely unclaimed and read as
        // bare "Unrecognized", indistinguishable from actual junk.
        let parent = DATGame(
            name: "sf2ce", description: "Street Fighter II': Champion Edition", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "s92-1m.3a", size: 100, crc: "12345678", md5: nil, sha1: "1111111111111111111111111111111111111111")]
        )
        // "sf2acc" (the clone) declares none of the parent's shared roms at
        // all under Split — only its own unique one.
        let clone = DATGame(
            name: "sf2acc", description: "Street Fighter II': Champion Edition (Accelerator Board)", cloneOf: "sf2ce", romOf: "sf2ce",
            roms: [DATRom(name: "sf2ca_23-c.bin", size: 50, crc: "eeeeeeee", md5: nil, sha1: "5555555555555555555555555555555555555555")]
        )
        let splitDAT = DATFile(header: dat.header, games: [parent, clone], mergeMode: .split)
        let ownRom = zipEntryHashedFile(archiveName: "sf2acc", entryName: "sf2ca_23-c.bin", size: 50, crc: "eeeeeeee", sha1: "5555555555555555555555555555555555555555")
        // Physically present inside sf2acc.zip too, named after the raw
        // (pre-layout-planning) machine's own declared name for it, exactly
        // matching the parent's hash — the real leftover this test covers.
        let sharedButUnclaimed = zipEntryHashedFile(archiveName: "sf2acc", entryName: "s92_01.bin", size: 100, crc: "12345678", sha1: "1111111111111111111111111111111111111111")
        let report = try ROMMatcher.match(dat: splitDAT, hashedFiles: [ownRom, sharedButUnclaimed])

        #expect(report.surplusFiles.count == 1)
        let surplus = report.surplusFiles.first
        #expect(surplus?.file == sharedButUnclaimed)
        #expect(surplus?.requiredByGameDescription == "Street Fighter II': Champion Edition")
    }

    @Test("a duplicate of an already-claimed rom, inside its own game's own archive, is never tagged as required by that same game")
    func duplicateWithinOwnArchiveIsNotTaggedAsRequiredByItself() throws {
        // Real bug found live by jensyleo (2026-08-04): `qsound_hle.zip`
        // physically contains "dl-1425.bin" *twice* — one copy correctly
        // claims the game's own expected rom, the second is a genuine
        // leftover duplicate. It still hash-matches the exact same rom in
        // the DAT's own rom-by-hash index — but the game that declares
        // that rom is "QSound (HLE)" itself, the very archive this
        // duplicate sits inside, so tagging it "Not needed here (required
        // by QSound (HLE))" is nonsensical: it *is* needed here, there's
        // just already a copy. Must report a plain, genuinely-unrecognized
        // `.missing` `requiredByGameDescription` (`nil`) instead.
        let qsound = DATGame(
            name: "qsound_hle", description: "QSound (HLE)", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "dl-1425.bin", size: 10, crc: "99999999", md5: nil, sha1: "3333333333333333333333333333333333333333")]
        )
        let dupDAT = DATFile(header: dat.header, games: [qsound])
        let claimedCopy = zipEntryHashedFile(archiveName: "qsound_hle", entryName: "dl-1425.bin", size: 10, crc: "99999999", sha1: "3333333333333333333333333333333333333333")
        let duplicateCopy = zipEntryHashedFile(archiveName: "qsound_hle", entryName: "dl-1425.bin", size: 10, crc: "99999999", sha1: "3333333333333333333333333333333333333333")
        let report = try ROMMatcher.match(dat: dupDAT, hashedFiles: [claimedCopy, duplicateCopy])

        #expect(report.surplusFiles.count == 1)
        #expect(report.surplusFiles.first?.requiredByGameDescription == nil)
    }

    @Test("a duplicate archive with the SAME base name in a DIFFERENT folder is tagged as required by that game, not silently swallowed as if it were the game's own archive")
    func duplicateArchiveAtDifferentPathIsStillTagged() throws {
        // Real bug found live by jensyleo (2026-08-05), right after
        // `FolderScanner`'s new depth limit made it possible for a
        // same-named archive to legitimately exist at two different
        // scanned paths (a real second ROM folder, or — before the
        // too-deep-skip fix — a subfolder like "BATOCERA"): the "own
        // archive" check used to compare archive *names* only
        // (`sfiii2.zip`'s own base name vs. the game named "sfiii2"), so a
        // second, genuinely different physical `sfiii2.zip` at another
        // path got silently treated as if it WERE the game's own claimed
        // archive — reporting nil instead of "Not needed here (required by
        // sfiii2)".
        let game = DATGame(
            name: "sfiii2", description: "Street Fighter III 2nd Impact", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "sfiii2_usa.29f400.u2", size: 60, crc: "77777777", md5: nil, sha1: "6666666666666666666666666666666666666666")]
        )
        let singleGameDAT = DATFile(header: dat.header, games: [game])
        let realCopy = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/PathA/sfiii2.zip"), name: "sfiii2_usa.29f400.u2", size: 60),
            hash: FileHash(crc32: "77777777", md5: "00000000000000000000000000000000", sha1: "6666666666666666666666666666666666666666")
        )
        let duplicateAtDifferentPath = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/tmp/PathB/sfiii2.zip"), name: "sfiii2_usa.29f400.u2", size: 60),
            hash: FileHash(crc32: "77777777", md5: "00000000000000000000000000000000", sha1: "6666666666666666666666666666666666666666")
        )
        let report = try ROMMatcher.match(dat: singleGameDAT, hashedFiles: [realCopy, duplicateAtDifferentPath])

        #expect(report.games.first?.matches.first?.status == .correct(realCopy))
        #expect(report.surplusFiles.count == 1)
        #expect(report.surplusFiles.first?.file == duplicateAtDifferentPath)
        #expect(report.surplusFiles.first?.requiredByGameDescription == "Street Fighter III 2nd Impact")
    }

    @Test("the FIRST ROM folder holding a copy always owns it — even when a later folder's copy would sort first through the plain-hash index")
    func firstFolderAlwaysOwnsTheArchive() throws {
        // jensyleo's own requirement (2026-08-06): the first folder holding a
        // copy is the original (green), every other copy is a duplicate
        // (yellow) — never ambiguous, never decided by which folder happened
        // to be scanned last.
        //
        // The ordering trap this pins down: `candidateIndices` concatenates a
        // plain-hash lookup with a header-stripped one, and concatenation is
        // unordered. Here folder A's copy carries a copier header (so it only
        // matches via the STRIPPED index) while folder B's is plain — so the
        // raw concatenation yields [B, A], handing the claim to the later
        // folder. Only sorting candidates ascending gives A (the first
        // folder, index 0) the claim.
        let payload = Data(repeating: 0xAB, count: 100)
        let rom = DATRom(
            name: "prog.bin", size: Int64(payload.count),
            crc: "cccc1111", md5: nil, sha1: "3333333333333333333333333333333333333333"
        )
        let game = DATGame(name: "hdr", description: "Header Test", cloneOf: nil, romOf: nil, roms: [rom])
        let singleGameDAT = DATFile(header: dat.header, games: [game])

        // Folder A (walked FIRST): the file on disk carries a 512-byte copier
        // header, so its own hash differs and only its header-stripped hash
        // matches the DAT.
        let inFolderA = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/A/hdr.zip"), name: "prog.bin", size: Int64(payload.count) + 512),
            hash: FileHash(crc32: "ffff9999", md5: nil, sha1: "9999999999999999999999999999999999999999"),
            headerStripped: HeaderStrippedHash(
                rule: .copier512,
                size: Int64(payload.count),
                hash: FileHash(crc32: "cccc1111", md5: nil, sha1: "3333333333333333333333333333333333333333")
            )
        )
        // Folder B (walked SECOND): a plain, unheadered copy.
        let inFolderB = HashedFile(
            file: ScannedFile(url: URL(fileURLWithPath: "/roms/B/hdr.zip"), name: "prog.bin", size: Int64(payload.count)),
            hash: FileHash(crc32: "cccc1111", md5: nil, sha1: "3333333333333333333333333333333333333333")
        )

        let report = try ROMMatcher.match(dat: singleGameDAT, hashedFiles: [inFolderA, inFolderB])

        let claimed = report.games.first!.matches.first!.status
        if case .correct(let file, _) = claimed {
            #expect(
                file.file.url.path == "/roms/A/hdr.zip",
                "the FIRST folder's copy must own it, even though it only matched after header-stripping"
            )
        } else {
            Issue.record("expected the first folder's copy to be claimed, got \(claimed)")
        }
        // And folder B's copy is the duplicate, tagged rather than unknown.
        #expect(report.surplusFiles.count == 1)
        #expect(report.surplusFiles.first?.file.file.url.path == "/roms/B/hdr.zip")
        #expect(report.surplusFiles.first?.requiredByGameDescription == "Header Test")
    }

    @Test("the same archive present in FOUR different ROM folders: exactly one is claimed and ALL THREE extras are tagged as duplicates — never left unrecognized")
    func sameArchiveInManyFoldersTagsEverySingleExtra() throws {
        // jensyleo's own question (2026-08-06), after seeing scenario #4
        // work with two folders: does this still hold when a copy sits in
        // *several* folders? The two-folder test above can't answer it —
        // tagging an extra copy depends on `requiredByGameDescription`
        // finding a real hash owner while the file itself went unclaimed, so
        // a bug that tagged only the *first* extra and dropped the rest to
        // plain gray "Unrecognized" would pass that test and fail here.
        //
        // Uses a two-rom game deliberately: with several roms per archive,
        // each rom claims independently, so a per-rom (rather than
        // per-archive) claim leak would show up as a *partially* claimed
        // duplicate rather than a cleanly tagged one.
        let game = DATGame(
            name: "ghouls", description: "Ghouls'n Ghosts (World)", cloneOf: nil, romOf: nil,
            roms: [
                DATRom(name: "09.4a", size: 60, crc: "aa110011", md5: nil, sha1: "1111111111111111111111111111111111111111"),
                DATRom(name: "10.4b", size: 70, crc: "bb220022", md5: nil, sha1: "2222222222222222222222222222222222222222"),
            ]
        )
        let singleGameDAT = DATFile(header: dat.header, games: [game])
        func copy(in folder: String) -> [HashedFile] {
            [
                zipEntryHashedFile(archiveName: "ghouls", entryName: "09.4a", size: 60, crc: "aa110011", sha1: "1111111111111111111111111111111111111111"),
                zipEntryHashedFile(archiveName: "ghouls", entryName: "10.4b", size: 70, crc: "bb220022", sha1: "2222222222222222222222222222222222222222"),
            ].map { file in
                HashedFile(
                    file: ScannedFile(
                        url: URL(fileURLWithPath: "/roms/\(folder)/ghouls.zip"),
                        name: file.file.name, size: file.file.size
                    ),
                    hash: file.hash, headerStripped: file.headerStripped
                )
            }
        }
        let folders = ["CPS1", "NEOGEO", "CPS3", "OTHER"]
        let report = try ROMMatcher.match(dat: singleGameDAT, hashedFiles: folders.flatMap(copy))

        // Exactly one archive satisfies the game — both of its roms claimed
        // out of the same physical copy, not one rom from each folder.
        let claimedPaths = Set(report.games.first!.matches.compactMap { match -> URL? in
            guard case .correct(let file, _) = match.status else { return nil }
            return file.file.url
        })
        #expect(report.games.first!.matches.allSatisfy { if case .correct = $0.status { true } else { false } })
        #expect(claimedPaths.count == 1, "all of a game's roms must be claimed from ONE archive, not spread across duplicates")

        // Every one of the remaining three copies (2 roms each) is tagged as
        // a known duplicate of this game — none silently unrecognized.
        #expect(report.surplusFiles.count == 6, "3 unclaimed copies x 2 roms")
        #expect(
            report.surplusFiles.allSatisfy { $0.requiredByGameDescription == "Ghouls'n Ghosts (World)" },
            "every extra copy must be tagged, not just the first"
        )
        // And they really are the other three folders, one claimed folder
        // excluded — no copy counted twice or missed.
        let surplusFolders = Set(report.surplusFiles.map { $0.file.file.url.deletingLastPathComponent().lastPathComponent })
        #expect(surplusFolders.count == 3)
        #expect(surplusFolders.union(claimedPaths.map { $0.deletingLastPathComponent().lastPathComponent }).count == 4)
    }

    @Test("in an archive-organized scan, a game never claims a rom out of an archive the DAT doesn't name for it — only .foundElsewhere, regardless of merge mode")
    func neverClaimsFromARenamedOrUnclaimedArchive() throws {
        // jensyleo's own Finder/RomCenter philosophy directive (2026-08-05):
        // this test used to assert `.correct` — ROMForge used to hunt
        // through any archive the DAT didn't recognize by name for content
        // that could plausibly belong to a game whose own archive was
        // absent (the "user renamed the whole archive" case). That same
        // mechanism is what let a totally unrelated game silently claim a
        // stray shared/padding rom out of someone else's duplicated
        // archive — a real, confusing bug (see this file's git history
        // around 2026-08-05). Every game's roms may now ONLY come from that
        // game's own archive (matched by name), full stop, no matter which
        // Rom merge mode is active — "expected-name.bin" genuinely exists
        // on disk, so it still surfaces as `.foundElsewhere` (informational,
        // never claims), but "Misnamed Game" is never marked `.correct`
        // just because *an* archive somewhere happens to hold it.
        let renamedArchive = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "expected-name.bin", size: 200, crc: "bbbbbbbb", sha1: "2222222222222222222222222222222222222222")
        for mergeMode in [SetMergeMode.split, .merged, .nonMerged] {
            let modeDAT = DATFile(header: dat.header, games: dat.games, mergeMode: mergeMode)
            let report = try ROMMatcher.match(dat: modeDAT, hashedFiles: [renamedArchive])
            let result = report.games.first { $0.game.name == "Misnamed Game" }!
            if case .foundElsewhere(let file) = result.matches[0].status {
                #expect(file == renamedArchive)
            } else {
                Issue.record("expected .foundElsewhere under \(mergeMode), got \(result.matches[0].status)")
            }
        }
    }

    @Test("a game needing 2+ roms never claims a single stray shared rom out of an unclaimed archive that isn't actually its own")
    func neverClaimsASingleStrayRomFromAnUnrelatedRenamedArchive() throws {
        // Real bug found live by jensyleo (2026-08-05): duplicating an
        // archive under a new name (e.g. copying `blazstar.zip` to
        // "blazstar copy.zip") made every completely unrelated game whose
        // *any single rom* happened to hash-match *any single file* inside
        // that copy legitimately claim it through the renamed-archive
        // fallback above — even though that archive's own content is
        // overwhelmingly explained by a *different* game. Dozens of
        // still-missing games all showed the duplicated archive's name as
        // their own File Name after claiming just one shared/padding rom.
        let multiRomGame = DATGame(
            name: "Two Rom Game", description: "Two Rom Game", cloneOf: nil, romOf: nil,
            roms: [
                DATRom(name: "shared-padding.bin", size: 900, crc: "f0f0f0f0", md5: nil, sha1: "9090909090909090909090909090909090909090"),
                DATRom(name: "its-own-unique.bin", size: 300, crc: "cccccccc", md5: nil, sha1: "3333333333333333333333333333333333333333"),
            ]
        )
        let dupDAT = DATFile(header: dat.header, games: dat.games + [multiRomGame], mergeMode: dat.mergeMode)
        // "renamed-by-user.zip" contains only the one rom shared by
        // coincidence with "Two Rom Game" — none of that game's other
        // (unique) roms are actually present in it.
        let sharedPaddingInUnrelatedArchive = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "shared-padding.bin", size: 900, crc: "f0f0f0f0", sha1: "9090909090909090909090909090909090909090")
        let report = try ROMMatcher.match(dat: dupDAT, hashedFiles: [sharedPaddingInUnrelatedArchive])

        let result = report.games.first { $0.game.name == "Two Rom Game" }!
        // Not claimed/consumed — but still correctly reported as
        // `.foundElsewhere` (the content genuinely exists on disk, just not
        // in an archive this game may claim as its own), not a silent
        // `.missing` that would hide where it actually is.
        if case .foundElsewhere(let file) = result.matches[0].status {
            #expect(file == sharedPaddingInUnrelatedArchive)
        } else {
            Issue.record("expected .foundElsewhere, got \(result.matches[0].status)")
        }
    }

    @Test("a game never claims from an unclaimed archive via same-size-only coincidences across its several files")
    func neverClaimsViaSizeOnlyCoincidencesAcrossAMultiFileUnclaimedArchive() throws {
        // Real bug found live by jensyleo (2026-08-05, same day, second
        // pass): the first fix (tallying real hash matches per archive)
        // wasn't enough once the *whole* archive was duplicated (e.g.
        // Finder's "blazstar copy.zip", not just one file inside it) —
        // with ~15 files in that unclaimed archive, an unrelated
        // multi-rom game could rack up two "matches" via pure same-size
        // coincidence alone (the size-only fallback tier `candidateIndices`
        // still allows), clearing the >=2 threshold without a single real
        // hash match. Two of this game's roms happen to share a SIZE (not
        // hash) with two different files in the unclaimed archive — this
        // must never be claimed.
        let multiRomGame = DATGame(
            name: "Size Coincidence Game", description: "Size Coincidence Game", cloneOf: nil, romOf: nil,
            roms: [
                DATRom(name: "rom-a.bin", size: 900, crc: "deadbeef", md5: nil, sha1: "dead000000000000000000000000000000dead"),
                DATRom(name: "rom-b.bin", size: 700, crc: "cafefeed", md5: nil, sha1: "cafe000000000000000000000000000000cafe"),
            ]
        )
        let dupDAT = DATFile(header: dat.header, games: dat.games + [multiRomGame], mergeMode: dat.mergeMode)
        // Same sizes, genuinely different content (different CRC/SHA1) —
        // only a size-only fallback match could ever connect these.
        let unrelatedFileA = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "unrelated-a.bin", size: 900, crc: "11110000", sha1: "1111000000000000000000000000000000aaaa")
        let unrelatedFileB = zipEntryHashedFile(archiveName: "renamed-by-user", entryName: "unrelated-b.bin", size: 700, crc: "22220000", sha1: "2222000000000000000000000000000000bbbb")
        let report = try ROMMatcher.match(dat: dupDAT, hashedFiles: [unrelatedFileA, unrelatedFileB])

        let result = report.games.first { $0.game.name == "Size Coincidence Game" }!
        #expect(result.matches[0].status == .missing)
        #expect(result.matches[1].status == .missing)
    }

    @Test("a game with a single hashless (nodump) rom never claims a same-sized file out of a duplicated, unrelated archive")
    func nodumpRomNeverClaimsFromAnUnrelatedDuplicatedArchive() throws {
        // The real mechanism behind jensyleo's live "blazstar copy.zip"
        // report (2026-08-05), confirmed by reading the actual MAME 0.288
        // DAT: "Abacus (Ver 1.0)" and "AN1x Control Synthesizer" (both
        // genuine, unrelated MESS/MAME skeleton drivers) each declare their
        // one real rom as `status="nodump"` — no crc/md5/sha1 at all, just
        // a size (131072 bytes). "blazstar" (NeoGeo) declares ~20 BIOS rom
        // variants that are ALL exactly 131072 bytes. Duplicating the
        // *entire* blazstar.zip under a new name gave every such
        // single-rom, hashless game's own nodump rom a same-size (never
        // same-hash) file to "match" against, via the plain size-only
        // fallback tier — legitimately clearable even under the >=2 tally
        // (single-rom games use a threshold of 1).
        let hashlessSingleRomGame = DATGame(
            name: "Abacus", description: "Abacus (Ver 1.0)", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "abacus_ver1.0_hd64f3048f16.mcu", size: 131072, crc: nil, md5: nil, sha1: nil, status: .nodump)]
        )
        let dupDAT = DATFile(header: dat.header, games: dat.games + [hashlessSingleRomGame], mergeMode: dat.mergeMode)
        // A same-size BIOS variant from the unrelated duplicated archive —
        // genuinely different real content, just coincidentally the same
        // size as the nodump placeholder.
        let sameSizeBIOSVariant = zipEntryHashedFile(archiveName: "blazstar copy", entryName: "sp-s2.sp1", size: 131072, crc: "9036d879", sha1: "4f5ed7105b7128794654ce82b51723e16e389543")
        let report = try ROMMatcher.match(dat: dupDAT, hashedFiles: [sameSizeBIOSVariant])

        let result = report.games.first { $0.game.name == "Abacus" }!
        // An unresolved `nodump` rom (no matching file under its own exact
        // name anywhere in its clone family) reports no match at all —
        // never silently claimed/misnamed as "Ok". The one thing that must
        // never happen: this same-sized stranger sitting in a duplicated,
        // completely unrelated archive getting treated as if it satisfied
        // this rom.
        #expect(result.matches.isEmpty)
        // And the file itself must not have been consumed/claimed either —
        // it's still a real surplus file, not swallowed silently.
        #expect(report.surplusFiles.contains { $0.file == sameSizeBIOSVariant })
    }

    @Test("under Un-merged mode, a game that IS part of a real clone/parent family still never CLAIMS a rom from a renamed archive")
    func nonMergedCloneFamilyStillNeverBorrowsFromAnotherArchive() throws {
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
        let report = try ROMMatcher.match(dat: nonMergedDAT, hashedFiles: [renamedArchive])

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
    func nonMergedStillMatchesOwnArchive() throws {
        let nonMergedDAT = DATFile(header: dat.header, games: dat.games, mergeMode: .nonMerged)
        let ownArchiveFile = zipEntryHashedFile(archiveName: "Correct Game", entryName: "correct.bin", size: 100, crc: "aaaaaaaa", sha1: "1111111111111111111111111111111111111111")
        let report = try ROMMatcher.match(dat: nonMergedDAT, hashedFiles: [ownArchiveFile])

        let result = report.games.first { $0.game.name == "Correct Game" }!
        #expect(result.matches[0].status == .correct(ownArchiveFile))
    }

    @Test("under Merged mode, an unrelated game never steals a rom from a clone's own (still-unrenamed) archive, even though Merged's own game list excludes that clone's name")
    func mergedModeNeverStealsFromAClonesOwnUnrenamedArchive() throws {
        // Real bug found live by jensyleo (2026-08-04): under `.merged`,
        // `DATLoader`'s own game-list filter excludes every clone from
        // `dat.games` entirely (folded into its parent's own entry — see
        // `DATFile.hasClones`'s own doc comment). `ROMMatcher` used to
        // derive `isInClaimedArchive`'s "which archive names are claimed"
        // set directly from that same filtered `dat.games` — so a clone's
        // own physical archive (e.g. `sf2acca.zip`, still sitting on disk
        // unrenamed, exactly as most real collections keep it) read as
        // *unclaimed*, purely because Merged mode's own list no longer
        // mentions its name. A totally unrelated game's blank-socket
        // placeholder rom (a common pattern across many unrelated bootleg
        // boards: an unpopulated EPROM socket, byte-identical by sheer
        // coincidence, not a real relationship) then matched via the
        // renamed-unclaimed-archive fallback against whatever physically
        // sits inside that clone's own archive — a nonsensical link
        // between two completely unconnected games.
        //
        // `allMachineNames` (unlike `games`) still includes "sf2acca" here,
        // exactly like `DATLoader` populates it from the *raw*,
        // pre-layout-planning machine list — this is what keeps its own
        // archive correctly "claimed" no matter which mode `games` itself
        // was built under.
        let parent = DATGame(
            name: "sf2ce", description: "Street Fighter II': Champion Edition", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "own.bin", size: 500, crc: "12121212", md5: nil, sha1: "6666666666666666666666666666666666666666")]
        )
        let unrelated = DATGame(
            name: "topcard", description: "Express Card / Top Card", cloneOf: nil, romOf: nil,
            roms: [DATRom(name: "missing.rom", size: 100, crc: "ffffffff", md5: nil, sha1: "7777777777777777777777777777777777777777")]
        )
        // "sf2acca" (the real clone) is deliberately absent from `games`
        // here — reproducing exactly what Merged mode's own filter does —
        // but present in `allMachineNames`, matching how `DATLoader`
        // actually populates it.
        let mergedDAT = DATFile(
            header: dat.header, games: [parent, unrelated], mergeMode: .merged,
            allMachineNames: ["sf2ce", "sf2acca", "topcard"]
        )
        // The clone's own real archive, still unrenamed, containing a file
        // that just happens to share "missing.rom"'s exact blank-socket
        // byte pattern — coincidence, not a real relationship.
        let cloneArchiveFile = zipEntryHashedFile(archiveName: "sf2acca", entryName: "blank.bin", size: 100, crc: "ffffffff", sha1: "7777777777777777777777777777777777777777")
        let report = try ROMMatcher.match(dat: mergedDAT, hashedFiles: [cloneArchiveFile])

        let result = report.games.first { $0.game.name == "topcard" }!
        #expect(result.matches[0].status == .missing)

        // The unclaimed file itself: not consumed by anyone (`topcard`
        // correctly stayed `.missing` above), so it surfaces as a surplus
        // file — `isInKnownArchive` must be true here (checked against
        // `allMachineNames`, which still lists "sf2acca", not against
        // Merged mode's own `dat.games`, which excludes it) — jensyleo's
        // own gray-file split (2026-08-06): otherwise this genuinely real
        // clone archive would misreport as fully unrecognized junk
        // (`.unknownFile`) under Merged mode specifically, the same class
        // of bug this whole test already guards against for claiming.
        let surplus = try #require(report.surplusFiles.first { $0.file.file.name == "blank.bin" })
        #expect(surplus.isInKnownArchive == true)
    }

    @Test("a nodump rom with no marker pointing at any clone is still resolved by name from ANY archive in its merged family — the real contra/gryzor case")
    func nodumpRomResolvedFromCloneArchiveViaMergedFamily() throws {
        // Real case found live by jensyleo (2026-08-04): `contra` and every
        // one of its clones (including `gryzor`) all redeclare the
        // identical undumped PAL `007766.20d.bin` — no per-clone marker at
        // all pointing at any particular one — yet the user's real dumped
        // file for it happened to sit in `gryzor.zip`, not `contra.zip`.
        // `familyNameMatchIndex` (driven by `mergedFamilyMachineNames`,
        // which Merged mode populates with every archive — parent and
        // clones alike — a game's family drew roms from) is what lets a
        // plain by-name search reach across the whole family instead of
        // just the requested game's own archive.
        let nodumpRom = DATRom(name: "007766.20d.bin", size: 1, crc: nil, md5: nil, sha1: nil, status: .nodump)
        let contra = DATGame(name: "contra", description: "Contra", cloneOf: nil, romOf: nil, roms: [nodumpRom], mergedFamilyMachineNames: ["contra", "gryzor"])
        let familyDAT = DATFile(
            header: DATHeader(name: "Test", description: "Test", version: "1", author: "ROMForge"),
            games: [contra],
            mergeMode: .merged,
            allMachineNames: ["contra", "gryzor"]
        )

        let realDumpInClone = zipEntryHashedFile(archiveName: "gryzor", entryName: "007766.20d.bin", size: 1, crc: "12345678", sha1: "1111111111111111111111111111111111111111")
        let report = try ROMMatcher.match(dat: familyDAT, hashedFiles: [realDumpInClone])

        let match = try #require(report.games.first?.matches.first)
        guard case .nodump(let hashedFile) = match.status else {
            Issue.record("expected .nodump, got \(match.status)")
            return
        }
        #expect(hashedFile.file.url.lastPathComponent == "gryzor.zip")
        #expect(report.surplusFiles.isEmpty, "the file was claimed by the nodump rom, not left over as an unrelated surplus")
    }

    @Test("a surplus file inside an archive whose name matches no DAT machine at all is never marked isInKnownArchive")
    func surplusInGenuinelyUnknownArchiveIsNotMarkedKnown() throws {
        // "TEST 1.zip" — jensyleo's own real, live case (2026-08-06): a
        // screenshot the user zipped up, sitting in a ROM folder. Its
        // archive name matches no DAT machine, so it must never be
        // conflated with a real, recognized archive holding one stray file.
        let junkFile = zipEntryHashedFile(archiveName: "TEST 1", entryName: "Screenshot.png", size: 500, crc: "99999999", sha1: "8888888888888888888888888888888888888888")
        let report = try ROMMatcher.match(dat: dat, hashedFiles: [junkFile])

        let surplus = try #require(report.surplusFiles.first { $0.file.file.name == "Screenshot.png" })
        #expect(surplus.isInKnownArchive == false)
    }
}
