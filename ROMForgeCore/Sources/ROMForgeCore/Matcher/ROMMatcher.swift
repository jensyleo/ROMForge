// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Dispatch
import Foundation

/// Compares expected ROMs (from a `DATFile`) against hashed local files,
/// matching on size and whichever hashes the DAT declares (CRC/MD5/SHA1) —
/// never on filename alone, per the "no unverified reporting" design rule.
///
/// Candidates are looked up through a hash index rather than a linear scan,
/// so matching a large DAT (tens of thousands of ROMs) against a large
/// collection stays roughly linear instead of quadratic.
public enum ROMMatcher {
    /// `onProgress`, when given, is called periodically (throttled — not
    /// once per game, which would be tens of thousands of calls on a full
    /// MAME DAT) with `(gamesProcessed, totalGames)` during phase 1 below —
    /// the expensive part this same doc comment already describes as
    /// having measured over ten minutes on a large real scan. Without it, a
    /// UI has no way to show real progress for however long that phase
    /// takes; the previous state (a bare, indeterminate spinner for the
    /// whole "Comparing against the database…" step) read as a possible
    /// stall no matter how long it actually took.
    ///
    /// `throws` only ever propagates `CancellationError` — real bug found
    /// live by jensyleo (2026-08-04): pressing Cancel mid-scan showed the
    /// "scan cancelled" warning immediately (`LibraryViewModel.cancelCurrentOperation()`
    /// sets that eagerly), but the scan itself kept running all the way to
    /// completion regardless, only reporting "cancelled" once the *entire*
    /// scan had already finished on its own. First attempt (`Task.checkCancellation()`
    /// at entry and between phase 1/phase 2) missed the actual bottleneck
    /// entirely: phase 1 (`computePerGameCandidates`, below) is the
    /// multi-minute part on a large scan, and it runs on
    /// `DispatchQueue.concurrentPerform`'s raw GCD worker threads — which
    /// are never "inside" any `Task` at all, so `Task.isCancelled` there
    /// unconditionally reads `false` no matter what, and checking it would
    /// have been silently pointless. `cancellationFlag` is the fix: a
    /// plain, lock-protected flag `LibraryViewModel` sets directly
    /// (independent of `Task` cancellation entirely) and phase 1's workers
    /// poll periodically — the only mechanism that can actually interrupt
    /// GCD-dispatched work like this.
    public static func match(dat: DATFile, hashedFiles: [HashedFile], onProgress: (@Sendable (Int, Int) -> Void)? = nil, cancellationFlag: CancellationFlag? = nil) throws -> MatchReport {
        try Task.checkCancellation()
        let crcIndex = indexOptional(hashedFiles, by: \.hash.crc32)
        let md5Index = indexOptional(hashedFiles, by: \.hash.md5)
        let sha1Index = indexOptional(hashedFiles, by: \.hash.sha1)
        let sizeIndex = index(hashedFiles, by: \.file.size)
        // Mirror indices over each file's header-stripped identity, when it
        // has one, so a headered console dump (e.g. an iNES ROM with its
        // 16-byte header) can still be found by a headerless DAT entry's
        // declared hash/size.
        let crcIndexStripped = indexStrippedOptional(hashedFiles, by: \.hash.crc32)
        let md5IndexStripped = indexStrippedOptional(hashedFiles, by: \.hash.md5)
        let sha1IndexStripped = indexStrippedOptional(hashedFiles, by: \.hash.sha1)
        let sizeIndexStripped = indexStripped(hashedFiles, by: \.size)

        // A split-set game's own-rom list only ever has entries the DAT
        // considers uniquely its own (parent/BIOS roms are already excluded
        // upstream by `MAMESetLayoutPlanner`) — but a large MAME DAT still
        // has many *unrelated* machines independently declaring the same
        // shared hardware ROM as their own, non-`merge=`, rom (e.g. several
        // arcade PCB reference sets and the `neogeo` BIOS itself all declare
        // `sfix.sfix`/`sm1.sm1`). Matching against one flat pool with
        // first-match-wins meant a machine the user doesn't even own (and
        // has no archive for) could still "steal" a real file belonging to
        // one they do, just by coming first in DAT order — reporting the
        // real one "missing". When the scan is zip-organized, each game is
        // restricted to candidates from its own same-named archive, with no
        // cross-archive fallback: a split-mode game's own roms are only
        // ever expected to live in its own archive, so if that archive
        // isn't present, every one of its roms is correctly "missing"
        // rather than resolved from an unrelated archive. A loose-file
        // scan (no archive concept at all) keeps the original unrestricted
        // pooling, since there's nothing to scope by.
        let archiveNameIndex = indexByArchiveName(hashedFiles)
        let isArchiveOrganized = hashedFiles.contains { $0.file.url.lastPathComponent != $0.file.name }
        // Every hashed file's own entry name, regardless of hash — the only
        // way to detect a genuine "Bad" (`RomMatchStatus.hashMismatch`):
        // something sitting in this rom's own expected slot (same name, own
        // archive) whose *content* is wrong, which by definition a
        // hash-keyed index alone could never find.
        let nameIndex = index(hashedFiles, by: \.file.name)
        // An archive whose own name matches some *other* real DAT game is
        // "claimed" by that game and off-limits to everyone else — this is
        // what stops the cross-machine steal above. An archive whose name
        // matches no DAT game at all isn't claimed by anyone, so it's a
        // legitimate fallback candidate: the common real case is a whole
        // archive renamed by the user (e.g. `sf2.zip` → `street2.zip`),
        // whose contents still hash-match a real game's roms perfectly.
        // Restricting fallback to unclaimed archives only detects that
        // ("Bad file name") without reopening the door to false steals
        // between two archives that both happen to be real game names.
        //
        // Read from `dat.allMachineNames` (the *raw*, pre-layout-planning
        // machine list), not derived from `dat.games` here — real bug
        // found live by jensyleo (2026-08-04, Merged mode): see
        // `DATFile.allMachineNames`'s own doc comment for the exact
        // cross-game "steal" this caused (a clone's own still-unrenamed
        // archive, e.g. `sf2acca.zip`, read as *unclaimed* purely because
        // Merged mode's own `dat.games` excludes every clone by design —
        // reopening the door this check exists to keep shut).
        let allGameNames = dat.allMachineNames
        // Un-merged means every game's own archive must be fully
        // self-contained, full stop — jensyleo's own definition
        // (2026-07-28): a game must never "need" a rom that actually lives
        // in some other game's file, clone/bootleg/parent or otherwise.
        // The renamed-whole-archive fallback above (matching against an
        // *unclaimed* archive) is exactly that — content borrowed from a
        // different archive — so it's disabled entirely under `.nonMerged`,
        // even though it stays available for `.split`/`.merged` scans
        // (where MAME's own layout already expects a clone to lean on its
        // parent's separate archive, so "not on an unrelated real game's
        // archive" is the only restriction that still makes sense there).
        //
        // Gated per-game (not DAT-wide as a single Bool) since — jensyleo's
        // own report (2026-08-03), confirmed live: a system where no game
        // has any clone/parent relationship at all (e.g. NEOGEO — every
        // machine is its own standalone entry) still visibly changed audit
        // results depending on Rom merge mode, even after
        // `MAMESetLayoutPlanner`'s own no-clone no-op fix, because THIS
        // flag used to be `dat.mergeMode == .nonMerged` alone — a single
        // DAT-wide toggle applied to every game regardless of whether it
        // has any clone/parent relationship whatsoever. The entire
        // rationale above ("a game must never need a rom sitting in some
        // other game's file, clone/bootleg/parent or otherwise") is
        // inherently about clone/parent relationships — it has nothing to
        // say about a standalone machine with neither, so restricting its
        // fallback based only on the *system's* merge mode, with no
        // parent/clone of its own to actually protect against, was a real
        // bug: a misnamed/renamed archive that would resolve fine under
        // Split/Merged could show as missing/incorrect under Un-merged for
        // a game this restriction was never meant to touch. A game only
        // qualifies for the stricter behavior under `.nonMerged` if it
        // actually clones something (`cloneOf != nil`) or is itself cloned
        // by something else (`gameNamesWithClones`, below) — a fully
        // standalone game keeps the renamed-archive fallback available
        // regardless of which Rom merge mode is selected.
        let gameNamesWithClones = Set(dat.games.compactMap(\.cloneOf))
        let datMergeModeIsNonMerged = dat.mergeMode == .nonMerged
        @Sendable func strictOwnArchiveOnly(_ game: DATGame) -> Bool {
            guard datMergeModeIsNonMerged else { return false }
            return game.cloneOf != nil || gameNamesWithClones.contains(game.name)
        }

        // Phase 1 (parallel, read-only): scope each game's own roms down to
        // their candidate file indices. This is the expensive part on a
        // large DAT — per-rom hash-index lookups plus, for an
        // archive-organized scan, filtering every candidate against
        // `isInClaimedArchive` (string ops on a file's containing archive
        // name) — and it touches no shared mutable state between games, so
        // it's safe to split across cores. A real scan (two Neo-Geo/CPS1
        // MAME folders merged against the same ~400k-entry DAT) measured
        // this phase pegging a single core for over ten minutes; splitting
        // it across `cores - 1` workers (`HashingConcurrency`, the same
        // policy already used for hashing) cuts that roughly by the same
        // factor, since each game's own candidate computation is completely
        // independent of every other game's.
        let perGameCandidates = computePerGameCandidates(
            games: dat.games, hashedFiles: hashedFiles,
            crcIndex: crcIndex, md5Index: md5Index, sha1Index: sha1Index, sizeIndex: sizeIndex,
            crcIndexStripped: crcIndexStripped, md5IndexStripped: md5IndexStripped, sha1IndexStripped: sha1IndexStripped, sizeIndexStripped: sizeIndexStripped,
            archiveNameIndex: archiveNameIndex, nameIndex: nameIndex, isArchiveOrganized: isArchiveOrganized, allGameNames: allGameNames,
            strictOwnArchiveOnly: strictOwnArchiveOnly, onProgress: onProgress, cancellationFlag: cancellationFlag
        )

        // `computePerGameCandidates`'s own workers bail out early on
        // `cancellationFlag` (see its doc comment), but they can't `throw`
        // across `DispatchQueue.concurrentPerform` — this is where that
        // silent early exit actually turns into the real `CancellationError`
        // the rest of the app already knows how to handle.
        if cancellationFlag?.isCancelled == true { throw CancellationError() }
        try Task.checkCancellation()

        // Phase 2 (sequential, cheap): claim files against the precomputed
        // candidates, in the DAT's own game order — same first-come
        // priority `consumed` always relied on, just against candidate
        // lists that no longer need recomputing here. What's left in this
        // pass is only array indexing and enum comparisons, not string
        // work, so it stays fast even at MAME's full scale.
        var consumed = [Bool](repeating: false, count: hashedFiles.count)
        // Every archive URL a game's own roms actually got claimed from —
        // real bug found live by jensyleo (2026-08-05): `requiredByGameDescription`
        // below used to decide "is this surplus file secretly this game's
        // OWN archive, just an internal duplicate" purely by comparing
        // archive *names* (`sf2acc.zip`'s own name vs. the game named
        // `sf2acc`), which breaks the moment two genuinely different
        // physical archives share the same base name at different
        // paths — e.g. a duplicate `sfiii2.zip` placed in a different
        // subfolder than the real one. Recording the actual claimed URL(s)
        // per game here lets that check compare real paths instead of
        // names, so a same-named-but-different-path duplicate is correctly
        // recognized as a real duplicate (`.incorrect`/"Not needed here"),
        // not silently swallowed as if it were the game's own archive.
        var claimedArchiveURLsByGame: [String: Set<URL>] = [:]
        var gameResults: [GameMatchResult] = []
        gameResults.reserveCapacity(dat.games.count)
        for (gameIndex, (game, romCandidates)) in zip(dat.games, perGameCandidates).enumerated() {
            // Runs on this call's own `Task`, unlike phase 1's
            // `DispatchQueue.concurrentPerform` workers above — safe to
            // check here. Checked every single game, not throttled: real
            // bug found live by jensyleo (2026-08-04, still broken after
            // the previous throttled-every-5000 attempt) — a *single*
            // pathologically expensive game (a hash-less/size-matched rom
            // whose candidate list happens to be huge, scanned linearly by
            // `matches(_:_:)` below) can itself take long enough that
            // skipping 4999 checks in between made this effectively
            // uninterruptible mid-game. `Task.checkCancellation()` is a
            // lock-free read, genuinely negligible next to any real
            // per-game work — no reason to throttle it here at all.
            try Task.checkCancellation()
            var romMatches: [RomMatch] = []
            romMatches.reserveCapacity(romCandidates.count)
            // `nodump` roms (real, confirmed live: MAME's own `sf2stt` set
            // declares both a hashless `nodump` placeholder — e.g. "prg
            // part 1.stt", size only, no crc/md5/sha1 — *and* a properly
            // hashed rom for the exact same byte region under a different
            // name, e.g. "ce91e-a") have no declared hash to narrow their
            // candidates by, so `candidateIndices` falls back to matching
            // *any* file of the right size. Processed in plain DAT order,
            // a `nodump` rom appearing before its hashed sibling would
            // claim that one available file for itself first — leaving
            // the sibling with nothing left to claim and reporting it
            // "missing" even though its own real hash was actually
            // present on disk, just claimed by the wrong (unverifiable)
            // rom slot. Processing every `nodump` rom last, within this
            // game only, guarantees every hash-verifiable rom gets first
            // pick of the files that could satisfy it.
            let orderedRomCandidates = romCandidates.filter { $0.rom.status != .nodump } + romCandidates.filter { $0.rom.status == .nodump }

            // Split into two passes over this one game's roms, rather than
            // deciding each rom's final status in a single pass. Pass A
            // only ever *claims* real files; pass B then classifies
            // whatever's left. The split exists because pass B's
            // `.foundElsewhere` branch needs one fact that isn't knowable
            // until every claim in this game has been attempted: whether
            // this game is genuinely present on disk at all (`gameOwnsRealFiles`).
            var resolvedStatuses = [RomMatchStatus?](repeating: nil, count: orderedRomCandidates.count)
            var isUnresolved = [Bool](repeating: false, count: orderedRomCandidates.count)
            var claimedAnyFile = false

            for (index, candidate) in orderedRomCandidates.enumerated() {
                let rom = candidate.rom
                if let matchIndex = candidate.scopedCandidates.first(where: { !consumed[$0] && matches(hashedFiles[$0], rom) }) {
                    consumed[matchIndex] = true
                    let hashedFile = hashedFiles[matchIndex]
                    if hashedFile.file.url.lastPathComponent != hashedFile.file.name {
                        claimedArchiveURLsByGame[game.name.lowercased(), default: []].insert(hashedFile.file.url)
                    }
                    let viaHeaderStrip = matchKind(hashedFile, rom) == .stripped
                    resolvedStatuses[index] = hashedFile.file.name == rom.name
                        ? .correct(hashedFile, viaHeaderStrip: viaHeaderStrip)
                        : .misnamed(hashedFile, viaHeaderStrip: viaHeaderStrip)
                    claimedAnyFile = true
                } else if rom.status == .nodump {
                    // A `nodump` rom's real content is, by the DAT's own
                    // declaration, unknown/unverifiable — MAME itself
                    // doesn't require it to run, and nothing on disk can
                    // ever "correctly" satisfy it. Once every real,
                    // hash-verifiable rom in this game has already had
                    // first pick above, an unclaimed `nodump` rom isn't a
                    // real problem to surface as "missing" (there's
                    // nothing the user could even do about it).
                    //
                    // Real case found live by jensyleo (2026-08-04):
                    // `gryzor`'s own `007766.20d.bin` — a nodump PAL with no
                    // hash and only a placeholder `size="1"`, so it can
                    // never satisfy `matches()` above even when the real
                    // dumped file is sitting right there in `gryzor.zip`.
                    // Before reporting nothing at all, check whether a file
                    // with this rom's exact name exists anywhere in this
                    // game's merged family of archives (`familyNameMatchIndex`
                    // — this game's own archive plus every clone folded into
                    // it under Merged, see `DATGame.mergedFamilyMachineNames`'s
                    // own doc comment) — if so, it has nowhere else it could
                    // possibly belong, so claim it as `.nodump` rather than
                    // leaving it to fall through every hash-keyed surplus
                    // lookup and read as plain "Unrecognized" (indistinguishable
                    // from genuine junk). Real case found live by jensyleo
                    // (2026-08-04): `contra` and every one of its clones
                    // (including `gryzor`) all redeclare the same undumped
                    // PAL `007766.20d.bin` identically — MAME's own
                    // convention for a chip nobody's dumped on any board
                    // revision — so the rom itself carries no marker
                    // pointing at any one clone, yet the user's real file for
                    // it sits in `gryzor.zip`, not `contra.zip`. If no such
                    // file exists anywhere in the family, there's still
                    // nothing to report — same as before.
                    if let familyIndex = candidate.familyNameMatchIndex, !consumed[familyIndex] {
                        consumed[familyIndex] = true
                        resolvedStatuses[index] = .nodump(hashedFiles[familyIndex])
                        claimedAnyFile = true
                    }
                    continue
                } else {
                    isUnresolved[index] = true
                }
            }

            // Does this game genuinely exist on disk — i.e. did *any* of
            // its own roms actually get claimed from its own (or a
            // legitimately-renamed) archive above? Real bug found live by
            // jensyleo (2026-08-04): a clone the user doesn't own at all
            // (e.g. `1943j` — no `1943j.zip` anywhere, its three genuinely
            // unique roms `bm01b.12d`/`bm02b.13d`/`bm03b.14d` present
            // nowhere in the scan) still showed up yellow/"Bad file name"
            // instead of plain missing, because its ~35 roms *shared with
            // its parent* are visibly sitting in the parent's own
            // `1943.zip` — so `.foundElsewhere` fired for every one of
            // them, pointing at an archive that belongs to a different
            // game entirely. That's a misreading of what `.foundElsewhere`
            // is for: it means "you have this game, but this particular
            // rom of it is filed in the wrong place" — a naming/layout
            // problem worth fixing. It does NOT mean "you don't have this
            // game, but some other game happens to contain roms it would
            // also need", which is just an ordinary absence. The
            // motivating NEOGEO case is on the right side of that line —
            // `mslug.zip` genuinely exists with its own roms claimed, and
            // only the shared BIOS roms live over in `neogeo.zip` — so it
            // still reports `.foundElsewhere` exactly as before. A
            // loose-file scan is exempted: with no archive identity at all
            // there's no such thing as "this game's own file", so
            // `.foundElsewhere` stays available there unconditionally (see
            // `doesNotDoubleMatchTheSameFile`'s own coverage of that case).
            let gameOwnsRealFiles = claimedAnyFile || !isArchiveOrganized

            for (index, candidate) in orderedRomCandidates.enumerated() where isUnresolved[index] {
                let rom = candidate.rom
                if let nameMatchIndex = candidate.nameMatchIndex, !matches(hashedFiles[nameMatchIndex], rom) {
                    // jensyleo's own definition (2026-08-04): checked before
                    // `.foundElsewhere` below — a file genuinely sitting in
                    // this rom's own expected slot (matched by name within
                    // this game's own scope), just with the wrong content,
                    // is a more specific, more actionable problem ("Bad" —
                    // this exact file is corrupt/wrong) than "the real
                    // content merely exists somewhere else". Never
                    // consumed — if this same file happens to coincidentally
                    // hash-match some *other* rom, that rom still claims it
                    // normally via the ordinary path above.
                    resolvedStatuses[index] = .hashMismatch(hashedFiles[nameMatchIndex])
                } else if let elsewhereIndex = candidate.hashVerifiedCandidates.first(where: { index in
                    guard matches(hashedFiles[index], rom) else { return false }
                    // Either this game genuinely exists on disk (so a rom of
                    // it filed elsewhere is a real layout problem), or the
                    // content is sitting in an archive that belongs to *no*
                    // DAT game at all — the signature of a whole archive the
                    // user renamed, which could plausibly be this very game.
                    // Content found only inside *another real game's* archive,
                    // for a game that owns nothing itself, is neither: that's
                    // the `1943j` case above, an ordinary absence.
                    return gameOwnsRealFiles || !isInClaimedArchive(index, hashedFiles: hashedFiles, allGameNames: allGameNames)
                }) {
                    // jensyleo's own rule (2026-08-04): when a rom is
                    // missing from the game's own archive, but the app can
                    // see its real content elsewhere in this same scan,
                    // that's a location/naming problem rather than a true
                    // absence — the case that first surfaced it being a
                    // fully intact NEOGEO collection (every game's own
                    // archive plus one shared `neogeo.zip` BIOS) reporting
                    // every dependent game incomplete, purely because
                    // Un-merged's self-containment rule above correctly
                    // refuses to *claim* a rom sitting in another archive.
                    // Gated on `gameOwnsRealFiles` — see its own comment
                    // for the clone-you-don't-own bug that gate fixes.
                    // Checked against the hash-verified unrestricted pool
                    // while ignoring `consumed`: purely informational,
                    // never a claim, so it can't steal a file from
                    // whichever game genuinely owns it, and doesn't care
                    // whether that owner has been processed yet.
                    resolvedStatuses[index] = .foundElsewhere(hashedFiles[elsewhereIndex])
                } else {
                    resolvedStatuses[index] = .missing
                }
            }

            for (index, candidate) in orderedRomCandidates.enumerated() {
                guard let status = resolvedStatuses[index] else { continue }
                romMatches.append(RomMatch(rom: candidate.rom, status: status))
            }
            gameResults.append(GameMatchResult(game: game, matches: romMatches))
        }

        // Real case found live by jensyleo (2026-08-04): under Split, a
        // clone's own expected rom list deliberately excludes every rom it
        // shares with its parent (`mergeName != nil` — see
        // `MAMESetLayoutPlanner`'s own doc comment; Split expects those to
        // live *only* in the parent's own archive). A user's actual
        // `sf2acc.zip`, however, often still physically contains that
        // shared content too (it's a real, valid rom — just not one Split
        // currently asks *this* archive for) — with nothing in Split's own
        // per-archive scoping ever looking inside `sf2acc.zip` for `sf2ce`'s
        // roms (archives are scoped strictly by name), it was reported as
        // plain gray "Unrecognized" — indistinguishable from genuine random
        // junk, when it's actually known, correct content the DAT declares
        // for a *different* game/mode. `romsByHash` below is the DAT's own
        // full rom list (every game, unfiltered by which are still
        // unconsumed) indexed by whichever hash each rom declares, purely
        // for this one classification — never consulted anywhere a file
        // could actually be *claimed*, so it can't reopen the cross-game
        // "steal" problem the rest of this file guards against.
        let romsByHash = indexRomsByHash(dat.games)
        var gamesByName: [String: DATGame] = [:]
        for game in dat.games where gamesByName[game.name.lowercased()] == nil {
            gamesByName[game.name.lowercased()] = game
        }
        // Every distinct name any DAT rom declares `nodump` — a `nodump` rom
        // has no hash at all, so `romsByHash` above can never recognize a
        // leftover copy of one; this is the name-only equivalent, purely for
        // this one classification (never consulted anywhere a file could
        // actually be *claimed* — same guarantee `romsByHash` already gives).
        // Real case found live by jensyleo (2026-08-04): `contra` (and its
        // whole merged clone family, including `gryzor`) all redeclare the
        // same undumped PAL, `007766.20d.bin`, and the user's actual
        // collection has TWO physical copies of that 1-byte placeholder —
        // one in `contra.zip` (which alone satisfies the one deduped
        // requirement) and one in `gryzor.zip`, left over with nothing to
        // claim it. That leftover copy is still known, documented content
        // (the DAT explicitly names this exact nodump slot), just
        // unverifiable and no longer needed here — reporting it as plain
        // gray "Unrecognized" would be indistinguishable from genuine junk.
        let nodumpRomNames = Set(dat.games.lazy.flatMap(\.roms).filter { $0.status == .nodump }.map { $0.name.lowercased() })
        let surplusFiles = hashedFiles.indices.filter { !consumed[$0] }.map { index -> SurplusFile in
            let file = hashedFiles[index]
            let requiredBy = requiredByGameDescription(for: file, gamesByName: gamesByName, romsByHash: romsByHash, claimedArchiveURLsByGame: claimedArchiveURLsByGame)
            let matchesNodumpName = requiredBy == nil && nodumpRomNames.contains(file.file.name.lowercased())
            return SurplusFile(file: file, requiredByGameDescription: requiredBy, matchesNodumpRomName: matchesNodumpName)
        }
        return MatchReport(games: gameResults, surplusFiles: surplusFiles)
    }

    /// One game's roms, each paired with its scoped candidate file indices
    /// — everything phase 1 above can compute before any file gets claimed.
    /// `hashVerifiedCandidates` is the *unrestricted* (no archive scoping
    /// at all) candidate pool, deliberately excluding the plain size-only
    /// fallback tier `scopedCandidates` still allows (see
    /// `candidateIndices`'s own `allowSizeOnlyFallback` doc comment for the
    /// real cross-game-steal bug this avoids) — consulted whenever
    /// `scopedCandidates` fails to claim a rom, to report `.foundElsewhere`
    /// instead of a true `.missing` (see `RomMatchStatus.foundElsewhere`'s
    /// own doc comment; this applies to every game, not only strict ones).
    /// `nameMatchIndex` is a file within this game's own scope (own
    /// archive, or itself if loose) whose *entry name* matches this rom's
    /// declared name, regardless of hash — the only way to detect
    /// `.hashMismatch` ("Bad"). `familyNameMatchIndex` is the same by-name
    /// lookup, scoped to every archive in `game.mergedFamilyMachineNames`
    /// (this game's own name plus every clone folded into it under Merged —
    /// see that field's own doc comment) rather than just this game's own
    /// archive. Consulted only for an unclaimed `nodump` rom (see
    /// `ROMMatcher.match`'s own nodump-claim logic): such a rom is often
    /// redeclared identically by every member of a merged family, with no
    /// per-rom marker at all pointing at which clone's archive the user's
    /// real dumped file happens to sit in.
    private typealias GameCandidates = [(rom: DATRom, scopedCandidates: [Int], hashVerifiedCandidates: [Int], nameMatchIndex: Int?, familyNameMatchIndex: Int?)]

    /// Computes `GameCandidates` for every game, split across
    /// `HashingConcurrency.workerCount(for:)` worker threads via
    /// `DispatchQueue.concurrentPerform` — a synchronous parallel-for,
    /// deliberately not `async`/`TaskGroup`-based so `ROMMatcher.match`'s
    /// existing synchronous signature (and every one of its many existing
    /// call sites, across the app and ~150 Core tests) doesn't need to
    /// change. Each worker writes only to the disjoint slice of `games` it
    /// was assigned (`chunked`, same splitting helper `CollectionHasher`
    /// already uses), through an `UnsafeMutableBufferPointer` rather than
    /// the `[GameCandidates]` array directly — concurrent writes to
    /// non-overlapping indices of the same backing storage are memory-safe,
    /// but Swift's normal `Array` capture-by-closure `Sendable` checking
    /// can't see that the index ranges never overlap; the raw buffer
    /// pointer sidesteps that without giving up the safety property itself.
    private static func computePerGameCandidates(
        games: [DATGame], hashedFiles: [HashedFile],
        crcIndex: [String: [Int]], md5Index: [String: [Int]], sha1Index: [String: [Int]], sizeIndex: [Int64: [Int]],
        crcIndexStripped: [String: [Int]], md5IndexStripped: [String: [Int]], sha1IndexStripped: [String: [Int]], sizeIndexStripped: [Int64: [Int]],
        archiveNameIndex: [String: [Int]], nameIndex: [String: [Int]], isArchiveOrganized: Bool, allGameNames: Set<String>,
        strictOwnArchiveOnly: @escaping @Sendable (DATGame) -> Bool,
        onProgress: (@Sendable (Int, Int) -> Void)?,
        cancellationFlag: CancellationFlag?
    ) -> [GameCandidates] {
        @Sendable func candidates(for game: DATGame) -> GameCandidates {
            let ownArchiveIndices = Set(archiveNameIndex[game.name.lowercased()] ?? [])
            let gameIsStrict = strictOwnArchiveOnly(game)
            // Every archive belonging to this merged family (already
            // lowercased — see `DATGame.mergedFamilyMachineNames`'s own doc
            // comment) — empty for Split/Non-merged, where it's simply never
            // consulted (`familyNameMatchIndex` below only matters for a
            // `nodump` rom's claim logic).
            let familyArchiveIndices = Set(game.mergedFamilyMachineNames.flatMap { archiveNameIndex[$0] ?? [] })
            return game.roms.map { rom in
                let candidates = candidateIndices(
                    for: rom,
                    crcIndex: crcIndex, md5Index: md5Index, sha1Index: sha1Index, sizeIndex: sizeIndex,
                    crcIndexStripped: crcIndexStripped, md5IndexStripped: md5IndexStripped, sha1IndexStripped: sha1IndexStripped, sizeIndexStripped: sizeIndexStripped
                )
                // For `.foundElsewhere`'s own unrestricted, whole-scan
                // lookup only — deliberately excludes the size-only
                // fallback tier `candidates` above still allows (see
                // `candidateIndices`'s own `allowSizeOnlyFallback` doc
                // comment for the real bug this fixes).
                let hashVerifiedCandidates = candidateIndices(
                    for: rom,
                    crcIndex: crcIndex, md5Index: md5Index, sha1Index: sha1Index, sizeIndex: sizeIndex,
                    crcIndexStripped: crcIndexStripped, md5IndexStripped: md5IndexStripped, sha1IndexStripped: sha1IndexStripped, sizeIndexStripped: sizeIndexStripped,
                    allowSizeOnlyFallback: false
                )
                let nameMatches = nameIndex[rom.name] ?? []
                let nameMatchIndex: Int? = isArchiveOrganized
                    ? nameMatches.first { ownArchiveIndices.contains($0) }
                    : nameMatches.first
                let familyNameMatchIndex: Int? = {
                    guard isArchiveOrganized, !familyArchiveIndices.isEmpty else { return nil }
                    return nameMatches.first { familyArchiveIndices.contains($0) }
                }()
                let scopedCandidates: [Int]
                if !isArchiveOrganized {
                    scopedCandidates = candidates
                } else if gameIsStrict {
                    // Un-merged: this game's roms may only ever come from
                    // its own archive — not even the renamed-whole-archive
                    // fallback below, since that would still mean the game
                    // "needed" a rom sitting in some other file on disk.
                    scopedCandidates = candidates.filter { ownArchiveIndices.contains($0) }
                } else {
                    let inOwnArchive = candidates.filter { ownArchiveIndices.contains($0) }
                    let inUnclaimedArchive = candidates.filter { index in
                        !ownArchiveIndices.contains(index) && !isInClaimedArchive(index, hashedFiles: hashedFiles, allGameNames: allGameNames)
                    }
                    scopedCandidates = inOwnArchive + inUnclaimedArchive
                }
                return (rom, scopedCandidates, hashVerifiedCandidates, nameMatchIndex, familyNameMatchIndex)
            }
        }

        // Throttled to ~200 updates across the whole run regardless of DAT
        // size — reporting every single game (tens of thousands on a full
        // MAME DAT) would flood a UI observer with far more updates than a
        // progress bar can usefully redraw.
        let progressStep = max(1, games.count / 200)
        let progressCounter = onProgress != nil ? ProgressCounter() : nil
        @Sendable func reportProgress() {
            guard let onProgress, let progressCounter else { return }
            let completed = progressCounter.increment()
            if completed % progressStep == 0 || completed == games.count {
                onProgress(completed, games.count)
            }
        }

        // Checked before *every* game, not throttled — real bug found live
        // by jensyleo (2026-08-04): an earlier version only checked every
        // 500 games, which still ran to full completion regardless of when
        // Cancel was pressed. Reading a lock-protected `Bool` is genuinely
        // negligible next to `candidates(for:)`'s own real work (multiple
        // dictionary lookups plus, for an archive-organized scan, string
        // ops per candidate) — there's no actual performance reason to
        // throttle this at all, only a wrong assumption that it needed to
        // be cheap like `reportProgress()`'s UI callback throttling above
        // (a real cross-thread `Task` hop, unlike this). Bails out of
        // *this worker's own* remaining slice only — leftover entries in
        // `results` simply stay at their initial empty value, which is
        // fine, since `match()` discards the whole result and throws once
        // it sees the flag set.
        func isCancelled(_ index: Int) -> Bool {
            cancellationFlag?.isCancelled ?? false
        }

        let workerCount = HashingConcurrency.workerCount(for: games.count)
        guard games.count > 1, workerCount > 1 else {
            var results: [GameCandidates] = []
            results.reserveCapacity(games.count)
            for (index, game) in games.enumerated() {
                if isCancelled(index) { break }
                results.append(candidates(for: game))
                reportProgress()
            }
            return results
        }

        var results = [GameCandidates](repeating: [], count: games.count)
        let chunkSize = (games.count + workerCount - 1) / workerCount
        results.withUnsafeMutableBufferPointer { buffer in
            // `UnsafeMutableBufferPointer` isn't itself `Sendable` (Swift has
            // no way to know its writes below never overlap between
            // workers), so it's boxed to cross into the `@Sendable` closure
            // explicitly — `@unchecked` because the actual safety guarantee
            // (each `chunkIndex` only ever touches its own disjoint
            // `start..<end` slice) is what this whole function's doc comment
            // already establishes, not something the type system can verify
            // on its own.
            let box = UncheckedSendableBox(buffer)
            DispatchQueue.concurrentPerform(iterations: workerCount) { chunkIndex in
                let start = chunkIndex * chunkSize
                guard start < games.count else { return }
                let end = min(start + chunkSize, games.count)
                for i in start..<end {
                    if isCancelled(i) { return }
                    box.value[i] = candidates(for: games[i])
                    reportProgress()
                }
            }
        }
        return results
    }

    /// A thread-safe counter `computePerGameCandidates` increments from
    /// however many concurrent workers `HashingConcurrency` spun up —
    /// `Int` itself isn't safe to mutate from multiple threads without one.
    private final class ProgressCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            count += 1
            return count
        }
    }

    /// Wraps a value that's actually safe to share across threads in this
    /// one specific, hand-verified way, but whose type doesn't itself
    /// conform to `Sendable` — see `computePerGameCandidates`'s only use.
    private struct UncheckedSendableBox<Value>: @unchecked Sendable {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// Prefers the most selective declared hash (CRC, then MD5, then SHA1)
    /// so the candidate bucket is as small as possible; falls back to
    /// indexing by size alone for the rare ROM that declares no hash (or
    /// whose declared hash simply isn't found anywhere in this scan at
    /// all). Each tier combines a file's raw identity with its
    /// header-stripped one (if any) — whichever one exists for a given
    /// file.
    ///
    /// `allowSizeOnlyFallback` — real bug found live by jensyleo
    /// (2026-08-04): the final size-only tier is *never* actually reliable
    /// content verification, just "same size, coincidentally" — safe
    /// enough for `scopedCandidates` (still filtered down afterward to
    /// this game's own archive, or an *unclaimed* one, by `computePerGameCandidates`'s
    /// own archive-scoping) but genuinely dangerous for `.foundElsewhere`'s
    /// own unrestricted, whole-scan lookup, which deliberately ignores
    /// archive-claim status entirely. A game whose real archive is simply
    /// absent (the overwhelmingly common case for a large, mostly-unowned
    /// system folder) has every declared-hash lookup come up empty, so
    /// this always fell through to the size-only tier — meaning `hundreds`
    /// of unrelated games with a common rom size (e.g. many turn-of-the-80s
    /// arcade titles sharing 32768/65536-byte program ROMs) all
    /// "coincidentally" resolved to whatever *one* real archive happened
    /// to contain a same-sized file, all reporting `.foundElsewhere`
    /// pointing at it — resurrecting the exact cross-game "steal" problem
    /// `isInClaimedArchive`/`allGameNames` above was built to prevent in
    /// the first place. `false` here means: only a real, verified
    /// crc/md5/sha1 match may ever satisfy `.foundElsewhere` — never a
    /// bare size coincidence across the entire scan.
    private static func candidateIndices(
        for rom: DATRom,
        crcIndex: [String: [Int]], md5Index: [String: [Int]], sha1Index: [String: [Int]], sizeIndex: [Int64: [Int]],
        crcIndexStripped: [String: [Int]], md5IndexStripped: [String: [Int]], sha1IndexStripped: [String: [Int]], sizeIndexStripped: [Int64: [Int]],
        allowSizeOnlyFallback: Bool = true
    ) -> [Int] {
        if let crc = rom.crc {
            let combined = uniqued((crcIndex[crc] ?? []) + (crcIndexStripped[crc] ?? []))
            if !combined.isEmpty { return combined }
        }
        if let md5 = rom.md5 {
            let combined = uniqued((md5Index[md5] ?? []) + (md5IndexStripped[md5] ?? []))
            if !combined.isEmpty { return combined }
        }
        if let sha1 = rom.sha1 {
            let combined = uniqued((sha1Index[sha1] ?? []) + (sha1IndexStripped[sha1] ?? []))
            if !combined.isEmpty { return combined }
        }
        guard allowSizeOnlyFallback else { return [] }
        return uniqued((sizeIndex[rom.size] ?? []) + (sizeIndexStripped[rom.size] ?? []))
    }

    /// Whether a hashed file lives inside a zip archive whose own name
    /// matches some real DAT game — a loose (non-archive) file is never
    /// "claimed" this way, since there's no archive identity to check.
    private static func isInClaimedArchive(_ index: Int, hashedFiles: [HashedFile], allGameNames: Set<String>) -> Bool {
        let file = hashedFiles[index].file
        guard file.url.lastPathComponent != file.name else { return false }
        let archiveName = file.url.deletingPathExtension().lastPathComponent.lowercased()
        return allGameNames.contains(archiveName)
    }

    /// Every rom the DAT declares, across every game, keyed by whichever
    /// hash(es) it declares — deliberately unfiltered by merge mode/status,
    /// so a rom Split excluded from some clone's own expected list (because
    /// it's inherited from the parent) is still found here under whichever
    /// game *does* still declare it plainly. First-game-wins on a
    /// collision (several unrelated machines, or a whole clone family,
    /// legitimately sharing one hardware rom) — good enough for a
    /// "this content is recognized, here's *a* place it's needed" message;
    /// not meant to enumerate every game that could use it.
    private static func indexRomsByHash(_ games: [DATGame]) -> [String: DATGame] {
        var result: [String: DATGame] = [:]
        for game in games {
            for rom in game.roms {
                for key in [rom.crc, rom.md5, rom.sha1].compactMap({ $0 }) {
                    if result[key] == nil { result[key] = game }
                }
            }
        }
        return result
    }

    /// The DAT game that actually declares this leftover file's content, if
    /// any — see `indexRomsByHash`'s own doc comment and this file's own
    /// `surplusFiles` computation for why an unclaimed file can still be
    /// genuinely recognized content, just not one anything currently asks
    /// *this* archive for.
    ///
    /// Real bug found live by jensyleo (2026-08-04): a genuine *duplicate*
    /// inside a game's own archive (e.g. `qsound_hle.zip` physically
    /// containing `dl-1425.bin` twice — one copy legitimately claimed, the
    /// second left over) also hash-matches this same rom in `romsByHash` —
    /// reporting "Not needed here (required by QSound (HLE))" for a file
    /// sitting right there inside QSound (HLE)'s own archive, "required
    /// by" QSound (HLE) itself, makes no sense: it's needed *here*, it's
    /// just a second copy nothing else claims. Checked directly against
    /// the file's own containing archive's own game (`gamesByName`, looked
    /// up by name rather than trusting `indexRomsByHash`'s first-match-wins
    /// choice — a rom several unrelated games legitimately share, like this
    /// QSound chip audio ROM, could easily have that pick a *different*
    /// game than this exact archive's own, which wouldn't catch the
    /// duplicate at all) — only a rom this file's own game does *not*
    /// itself also declare is ever worth reporting as belonging elsewhere.
    ///
    /// Second real bug found live by jensyleo (2026-08-05, same class):
    /// the "own archive" check above used to be purely *name*-based
    /// (`ownArchiveGameName`, derived only from the file's path) — correct
    /// for the `qsound_hle.zip` case (one archive, a real duplicate rom
    /// inside it), but wrong once two genuinely different physical
    /// archives can share the same base name at different paths (now
    /// possible after `FolderScanner`'s own depth limit permits a
    /// same-named archive to sit in more than one scanned subfolder — real
    /// case: a duplicate `sfiii2.zip` placed inside a `BATOCERA` subfolder,
    /// distinct from the real `sfiii2.zip` ROMMatcher already claimed
    /// elsewhere). `claimedArchiveURLsByGame` fixes this by comparing the
    /// exact claimed *path*, not just the name — a same-named-but-different-
    /// path duplicate is no longer silently swallowed as if it were the
    /// game's own archive; it correctly reports "Not needed here (required
    /// by …)" instead.
    private static func requiredByGameDescription(for file: HashedFile, gamesByName: [String: DATGame], romsByHash: [String: DATGame], claimedArchiveURLsByGame: [String: Set<URL>]) -> String? {
        let fileHashes = [file.hash.crc32, file.hash.md5, file.hash.sha1].compactMap { $0 }
        let isArchiveEntry = file.file.url.lastPathComponent != file.file.name
        if isArchiveEntry {
            let ownArchiveGameName = file.file.url.deletingPathExtension().lastPathComponent.lowercased()
            // Both conditions matter, not just one: `claimedArchiveURLsByGame`
            // alone (checked first, cheaply) rules out the wrong-*path*
            // case (2026-08-05's `sfiii2.zip` bug — a different physical
            // archive that merely shares this one's base name). `ownHashes`
            // (the original 2026-08-04 check) still rules out the
            // wrong-*content* case: `sf2acc.zip` genuinely IS the claimed
            // archive for the clone "sf2acc", but a rom sitting in it that
            // hash-matches its Split-mode *parent* `sf2ce` instead of
            // anything `sf2acc` itself declares must still be attributed to
            // `sf2ce`, not silently swallowed just because the archive
            // itself happens to be "sf2acc"'s own.
            if let ownGame = gamesByName[ownArchiveGameName], claimedArchiveURLsByGame[ownArchiveGameName]?.contains(file.file.url) == true {
                let ownHashes = Set(ownGame.roms.flatMap { [$0.crc, $0.md5, $0.sha1].compactMap { $0 } })
                if fileHashes.contains(where: ownHashes.contains) { return nil }
            }
        }
        for key in fileHashes {
            if let game = romsByHash[key] { return game.description }
        }
        return nil
    }

    private static func uniqued(_ indices: [Int]) -> [Int] {
        var seen = Set<Int>()
        return indices.filter { seen.insert($0).inserted }
    }

    private static func index<Key: Hashable>(_ hashedFiles: [HashedFile], by keyPath: KeyPath<HashedFile, Key>) -> [Key: [Int]] {
        var result: [Key: [Int]] = [:]
        for (offset, file) in hashedFiles.enumerated() {
            result[file[keyPath: keyPath], default: []].append(offset)
        }
        return result
    }

    /// Same as `index`, but for a hash field `HashAlgorithms` may not have
    /// computed for a given file (`nil`) — those files simply aren't
    /// indexable by this particular hash, rather than all colliding into
    /// one giant "nil" bucket that a real declared hash could never
    /// actually look up anyway.
    private static func indexOptional<Key: Hashable>(_ hashedFiles: [HashedFile], by keyPath: KeyPath<HashedFile, Key?>) -> [Key: [Int]] {
        var result: [Key: [Int]] = [:]
        for (offset, file) in hashedFiles.enumerated() {
            guard let key = file[keyPath: keyPath] else { continue }
            result[key, default: []].append(offset)
        }
        return result
    }

    /// Groups zip-entry `HashedFile`s by their containing archive's name
    /// (without extension, lowercased) — a loose file (`url` *is* the file
    /// itself, not a container) has no archive identity and is excluded, so
    /// it never wrongly satisfies another game's archive-scoped lookup.
    private static func indexByArchiveName(_ hashedFiles: [HashedFile]) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for (offset, file) in hashedFiles.enumerated() {
            guard file.file.url.lastPathComponent != file.file.name else { continue }
            let archiveName = file.file.url.deletingPathExtension().lastPathComponent.lowercased()
            result[archiveName, default: []].append(offset)
        }
        return result
    }

    private static func indexStripped<Key: Hashable>(_ hashedFiles: [HashedFile], by keyPath: KeyPath<HeaderStrippedHash, Key>) -> [Key: [Int]] {
        var result: [Key: [Int]] = [:]
        for (offset, file) in hashedFiles.enumerated() {
            guard let stripped = file.headerStripped else { continue }
            result[stripped[keyPath: keyPath], default: []].append(offset)
        }
        return result
    }

    /// `indexOptional`'s counterpart for a header-stripped hash field.
    private static func indexStrippedOptional<Key: Hashable>(_ hashedFiles: [HashedFile], by keyPath: KeyPath<HeaderStrippedHash, Key?>) -> [Key: [Int]] {
        var result: [Key: [Int]] = [:]
        for (offset, file) in hashedFiles.enumerated() {
            guard let stripped = file.headerStripped, let key = stripped[keyPath: keyPath] else { continue }
            result[key, default: []].append(offset)
        }
        return result
    }

    /// A rom matches a file either by its raw (whole-file) identity, or —
    /// if the file has a detected copier header — by its header-stripped
    /// identity, so a headered console dump matches the headerless
    /// identity a No-Intro/Goodxxx-style DAT actually declares. Returns
    /// which of the two paths matched (`nil` for no match) rather than a
    /// plain `Bool` — jensyleo's own request (2026-07-30): a match that
    /// only succeeded once the header was stripped is a real, surfaceable
    /// distinction from a byte-identical file (see `RomMatchStatus`'s own
    /// `viaHeaderStrip` flag and `AuditEntry.matchedViaHeaderStrip`), not
    /// something to report identically as plain "Ok". **Not yet verified
    /// live against a real console dump** — none of NES/Lynx/SNES/Game
    /// Boy/PC Engine/Master System/Genesis were available to test this
    /// session; re-check the actual UI text next time one of those systems
    /// gets a real headered ROM scanned.
    private static func matchKind(_ hashedFile: HashedFile, _ rom: DATRom) -> MatchKind? {
        if matchesRaw(hashedFile, rom) { return .raw }
        if let stripped = hashedFile.headerStripped, matchesStripped(stripped, rom) { return .stripped }
        return nil
    }

    private static func matches(_ hashedFile: HashedFile, _ rom: DATRom) -> Bool {
        matchKind(hashedFile, rom) != nil
    }

    private enum MatchKind {
        case raw
        case stripped
    }

    // A hash field is only ever compared when *both* the DAT declares it
    // and the scan actually computed it (`HashAlgorithms` may have skipped
    // an algorithm for speed) — a rom whose declared CRC the user disabled
    // computing isn't thereby rejected, it's just not confirmed *by that
    // particular hash*; it can still match on whichever hash(es) were
    // computed, or on size alone if none were declared at all.
    private static func matchesRaw(_ hashedFile: HashedFile, _ rom: DATRom) -> Bool {
        guard hashedFile.file.size == rom.size else { return false }
        if let crc = rom.crc, let fileCRC = hashedFile.hash.crc32, crc != fileCRC { return false }
        if let md5 = rom.md5, let fileMD5 = hashedFile.hash.md5, md5 != fileMD5 { return false }
        if let sha1 = rom.sha1, let fileSHA1 = hashedFile.hash.sha1, sha1 != fileSHA1 { return false }
        return true
    }

    private static func matchesStripped(_ stripped: HeaderStrippedHash, _ rom: DATRom) -> Bool {
        guard stripped.size == rom.size else { return false }
        if let crc = rom.crc, let fileCRC = stripped.hash.crc32, crc != fileCRC { return false }
        if let md5 = rom.md5, let fileMD5 = stripped.hash.md5, md5 != fileMD5 { return false }
        if let sha1 = rom.sha1, let fileSHA1 = stripped.hash.sha1, sha1 != fileSHA1 { return false }
        return true
    }
}
