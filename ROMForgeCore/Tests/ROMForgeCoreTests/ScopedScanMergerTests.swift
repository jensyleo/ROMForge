// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Testing
@testable import ROMForgeCore

@Suite("ScopedScanMerger")
struct ScopedScanMergerTests {
    private let other = URL(fileURLWithPath: "/roms/CAPCOM/OTHER", isDirectory: true)
    private let cps3 = URL(fileURLWithPath: "/roms/CAPCOM/CPS3", isDirectory: true)

    /// One rom entry of `game`, claimed out of `<folder>/<archive>.zip`.
    private func romEntry(
        game: String, rom: String, archive: String, in folder: URL,
        status: AuditStatus = .correct
    ) -> AuditEntry {
        AuditEntry(
            status: status, game: game, gameDescription: game,
            name: rom, path: folder.appendingPathComponent("\(archive).zip")
        )
    }

    private func missingEntry(game: String, rom: String) -> AuditEntry {
        AuditEntry(status: .missing, game: game, gameDescription: game, name: rom, path: nil)
    }

    private func surplusEntry(name: String, archive: String, in folder: URL, requiredBy: String? = nil) -> AuditEntry {
        AuditEntry(
            status: requiredBy != nil ? .incorrect : .unknownFile, game: nil,
            requiredByGameDescription: requiredBy,
            name: name, path: folder.appendingPathComponent("\(archive).zip")
        )
    }

    private func report(_ entries: [AuditEntry]) -> AuditReport {
        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0, unverifiable = 0
        for entry in entries {
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            }
        }
        return AuditReport(
            entries: entries, correct: correct, incorrect: incorrect, badDump: badDump,
            missing: missing, surplus: surplus, unverifiable: unverifiable
        )
    }

    @Test("the same archive copied into TWO of the system's ROM folders survives a scoped rescan of either one — neither folder's real files are ever dropped")
    func duplicateAcrossFoldersSurvivesAScopedRescanOfEitherFolder() throws {
        // Real bug found live by jensyleo (2026-08-06, running TESTING.md
        // §9.2 scenario #4): `ghouls.zip` copied so it sits in BOTH the
        // OTHER and CPS3 folders of the same system. A scoped rescan of
        // either folder claimed that folder's own copy fresh, marked
        // "ghouls" as touched, and then dropped the *other* folder's
        // perfectly real, still-on-disk entries wholesale — so the game
        // vanished from whichever folder wasn't just scanned, and
        // rescanning that one flipped it straight back. Infinitely.
        let previous = report([
            romEntry(game: "ghouls", rom: "09.4a", archive: "ghouls", in: other),
            romEntry(game: "ghouls", rom: "10.4b", archive: "ghouls", in: other),
            // The full scan that produced `previous` saw both copies and
            // correctly flagged the CPS3 one as a known duplicate.
            surplusEntry(name: "09.4a", archive: "ghouls", in: cps3, requiredBy: "Ghouls'n Ghosts (World)"),
            surplusEntry(name: "10.4b", archive: "ghouls", in: cps3, requiredBy: "Ghouls'n Ghosts (World)"),
        ])
        // Rescanning ONLY CPS3: with just that folder in the file pool, its
        // own `ghouls.zip` is the only one the matcher can see, so it claims
        // it as the game's own archive.
        let fresh = report([
            romEntry(game: "ghouls", rom: "09.4a", archive: "ghouls", in: cps3),
            romEntry(game: "ghouls", rom: "10.4b", archive: "ghouls", in: cps3),
        ])

        let merged = ScopedScanMerger.merge(previous: previous, fresh: fresh, scopedFolders: [cps3])

        // The whole point: OTHER's copy is still physically on disk and this
        // scan never looked at it, so its entries must still be there.
        let inOther = merged.entries.filter { $0.path?.path.hasPrefix(other.path) == true }
        let inCPS3 = merged.entries.filter { $0.path?.path.hasPrefix(cps3.path) == true }
        #expect(inOther.count == 2, "OTHER's real ghouls.zip entries must never be dropped by a scan of CPS3")
        #expect(inCPS3.count == 2, "CPS3's freshly-claimed entries must be present too")
        // Both folder views can therefore show a ghouls row — the
        // Finder-style behavior jensyleo asked for: a folder shows what's
        // physically in it.
        #expect(inOther.allSatisfy { $0.game == "ghouls" })
    }

    @Test("a stale .missing row for a game the scan DID touch is superseded, not carried forward next to the fresh result")
    func staleMissingRowIsSupersededForATouchedGame() throws {
        // The `path == nil` carve-out: a plain "Missing" verdict belongs to
        // no folder at all, so it must stay subject to the touched rule —
        // otherwise the cross-folder fix above would resurrect a stale red
        // "Missing" row right beside the fresh green "Ok" that replaced it.
        let previous = report([missingEntry(game: "ghouls", rom: "09.4a")])
        let fresh = report([romEntry(game: "ghouls", rom: "09.4a", archive: "ghouls", in: cps3)])

        let merged = ScopedScanMerger.merge(previous: previous, fresh: fresh, scopedFolders: [cps3])

        #expect(merged.entries.count == 1)
        #expect(merged.entries.first?.status == .correct)
        #expect(merged.missing == 0)
    }

    @Test("a game living entirely in an unscanned folder is carried forward untouched, even when the scoped scan wrongly reports it missing")
    func untouchedGameInAnotherFolderIsCarriedForward() throws {
        // The original reason this function exists: scanning CPS3 makes the
        // matcher report every OTHER-folder game as missing, purely because
        // those files aren't in this scan's own pool. That false negative
        // must never overwrite the real, previously-known result.
        let previous = report([romEntry(game: "contra", rom: "633e01.12a", archive: "contra", in: other)])
        let fresh = report([missingEntry(game: "contra", rom: "633e01.12a")])

        let merged = ScopedScanMerger.merge(previous: previous, fresh: fresh, scopedFolders: [cps3])

        #expect(merged.entries.count == 1)
        #expect(merged.entries.first?.status == .correct)
        #expect(merged.entries.first?.path?.path.hasPrefix(other.path) == true)
    }

    @Test("a surplus file inside the rescanned folder is superseded, while one in an unscanned folder is kept")
    func surplusEntriesAreScopedByTheirOwnFolder() throws {
        let previous = report([
            surplusEntry(name: "Screenshot.png", archive: "TEST 1", in: cps3),
            surplusEntry(name: "Screenshot.png", archive: "TEST 1", in: other),
        ])
        // The rescan of CPS3 no longer finds anything stray there (the user
        // deleted it), so `fresh` has no surplus entry of its own.
        let merged = ScopedScanMerger.merge(previous: previous, fresh: report([]), scopedFolders: [cps3])

        #expect(merged.entries.count == 1)
        #expect(merged.entries.first?.path?.path.hasPrefix(other.path) == true)
    }

    @Test("a previous disk row is never re-appended when the caller already folded it into fresh — no duplicate CHD rows")
    func diskRowsAreNotDuplicated() throws {
        // `LibraryViewModel` folds `previous`'s own disk rows into `fresh`
        // wholesale whenever disks weren't re-audited, so this function must
        // not also carry them forward from `previous` — hence the `!isDisk`
        // guard on the outside-scope carve-out. Uses a disk whose file lives
        // OUTSIDE the scanned folder, the exact case that guard protects.
        let disk = AuditEntry(
            status: .correct, game: "sfiii3", gameDescription: "Street Fighter III 3rd Strike",
            isDisk: true, name: "cap-sf3-3", path: other.appendingPathComponent("cap-sf3-3.chd")
        )
        let previous = report([disk, romEntry(game: "sfiii3", rom: "sfiii3.rom", archive: "sfiii3", in: cps3)])
        // Caller-style `freshForMerge`: this scan's own rom result for the
        // touched game, plus the previous report's disk rows carried in.
        let fresh = report([romEntry(game: "sfiii3", rom: "sfiii3.rom", archive: "sfiii3", in: cps3), disk])

        let merged = ScopedScanMerger.merge(previous: previous, fresh: fresh, scopedFolders: [cps3])

        #expect(merged.entries.filter(\.isDisk).count == 1, "the disk row must appear exactly once")
    }
}
