// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Combines a freshly-scoped scan (only some of a system's ROM folders, or a
/// single file) with the last full/partial report.
///
/// Lived as a `private static func` on the app's own `LibraryViewModel` until
/// 2026-08-06, with no test coverage at all — by which point it had already
/// produced three separate bugs found live by jensyleo (two on 2026-08-04,
/// see the inline comments below, and the cross-folder-duplicate one that
/// finally moved it here). It's a pure function over `AuditReport`, with no
/// UI or actor dependencies whatsoever, so there was never a real reason for
/// it to sit somewhere it couldn't be tested.
public enum ScopedScanMerger {
    /// A "missing" verdict from a scoped scan means only "not found in
    /// *this* scope", never "not found anywhere", so it falls back to
    /// whatever the previous report already knew for that exact (game, rom)
    /// pair rather than overwriting a real match with a false negative.
    /// Matched by game name (and, for disks, the disk's own name) since
    /// that's stable across scans of the same DAT regardless of which folder
    /// a file happens to live in.
    public static func merge(previous: AuditReport, fresh: AuditReport, scopedFolders: [URL]) -> AuditReport {
        var merged: [AuditEntry] = []
        merged.reserveCapacity(fresh.entries.count + previous.entries.count)
        // Single pass over the merged result for all counts, instead of
        // several separate full-array `.filter { }.count` passes — the same
        // redundant-rescan cost `computeScopedStatusCounts` was already
        // fixed for, here too.
        var correct = 0, incorrect = 0, badDump = 0, missing = 0, surplus = 0, unverifiable = 0
        func append(_ entry: AuditEntry) {
            merged.append(entry)
            switch entry.status {
            case .correct: correct += 1
            case .incorrect: incorrect += 1
            case .badDump: badDump += 1
            case .missing: missing += 1
            case .surplus, .surplusInArchive, .unknownFile: surplus += 1
            case .unverifiable: unverifiable += 1
            }
        }

        let scopedPaths = scopedFolders.map(\.path)
        func isInsideScope(_ path: URL) -> Bool {
            scopedPaths.contains { path.path.hasPrefix($0) }
        }

        // Which games did this scan actually touch — i.e. have a REAL file
        // (not a `.foundElsewhere` borrowed path, see its own doc comment)
        // somewhere inside `scopedFolders`, per `fresh`'s own results.
        // Real bug found live by jensyleo (2026-08-04): an earlier version
        // only ever detected "touched" this way for a *single-file* scope
        // (`scopedFolders` naming exactly one game by MAME's own "archive
        // named after the machine" convention) — any whole-*folder* scope
        // (an ordinary "Scan Folder" click, the overwhelmingly common case)
        // fell back to a much weaker per-rom reconciliation that only
        // restored `previous`'s status when fresh reported a rom plain
        // `.missing`. Once `ROMMatcher` started also reporting
        // `.foundElsewhere`/`.hashMismatch` (both map to `.incorrect`, not
        // `.missing`) for a rom it merely couldn't claim in *this* scan's
        // own limited file pool, that per-rom check no longer caught them:
        // scanning one folder (e.g. NEOGEO) could produce a stray
        // `.incorrect` verdict for some *completely different* system's game
        // — and since that verdict wasn't literally `.missing`, the old
        // per-rom check trusted it outright over the real, correct
        // `previous` status, flipping an untouched game's entire row yellow.
        var touchedGameNames: Set<String> = []
        for entry in fresh.entries {
            guard let game = entry.game, entry.foundElsewhereArchiveName == nil, let path = entry.path,
                  isInsideScope(path) else { continue }
            touchedGameNames.insert(game.lowercased())
        }
        // Real bug found live by jensyleo (2026-08-04): a game whose entire
        // fresh footprint is surplus-derived (`entry.game == nil` — e.g.
        // `qsound_hle` under Split, where its only rom is merge-tagged and
        // stripped from its own expected list entirely, so nothing with
        // `game == "qsound_hle"` can ever exist in a Split-mode scan) never
        // satisfied the loop above at all, since that loop only ever looks
        // at entries that already have a real `game`. Untouched by this
        // definition, `qsound_hle`'s *stale* `previous` row got carried
        // forward wholesale instead of being superseded — alongside the
        // fresh scan's own surplus entry for the exact same physical file,
        // producing two contradictory rows for one rom slot: a stale green
        // "Ok" next to a fresh yellow "Not needed here".
        for entry in fresh.entries {
            guard entry.game == nil, let path = entry.path, isInsideScope(path) else { continue }
            touchedGameNames.insert(path.deletingPathExtension().lastPathComponent.lowercased())
        }
        // A single-FILE scope (e.g. "Rescan This File") also names its own
        // touched game directly by filename — needed for the edge case
        // where *every* one of that file's roms came back missing/
        // `.foundElsewhere` (no real in-scope path for the loops above to
        // have found at all), which would otherwise look "untouched".
        for url in scopedFolders {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                touchedGameNames.insert(url.deletingPathExtension().lastPathComponent.lowercased())
            }
        }

        // A rom's own archive is named after its *game* (MAME convention),
        // but a CHD disk's physical filename is the *disk's own* declared
        // name, which often doesn't match its game's name at all (e.g. disk
        // "cap-sf3-3" belongs to game "sfiii") — checked against
        // `entry.name` too, not just `entry.game`, so rescanning one
        // specific `.chd` file is correctly recognized as touching that
        // disk's entry.
        func isTouched(_ entry: AuditEntry, game: String) -> Bool {
            touchedGameNames.contains(game.lowercased()) || touchedGameNames.contains(entry.name.lowercased())
        }

        for entry in fresh.entries {
            guard let game = entry.game else {
                append(entry) // a surplus file found fresh, inside scope
                continue
            }
            if isTouched(entry, game: game) { append(entry) }
            // Untouched games are skipped here entirely — carried forward
            // from `previous` below instead, wholesale.
        }
        for entry in previous.entries {
            guard let game = entry.game else {
                // A surplus file: superseded only if this scan actually
                // re-examined the folder it sits in.
                let wasRescanned = entry.path.map(isInsideScope) ?? false
                if !wasRescanned { append(entry) }
                continue
            }
            // A previous entry whose own real file lives OUTSIDE this scan's
            // scope is still physically sitting on disk — this scan never
            // looked at it, so a "touched" verdict earned entirely inside
            // the scope must never delete it.
            //
            // Real bug found live by jensyleo (2026-08-06, running
            // TESTING.md §9.2 scenario #4): with the same `ghouls.zip`
            // copied into two of the system's ROM folders (OTHER and CPS3),
            // a scoped rescan of either folder claimed that folder's copy
            // fresh, marked "ghouls" touched, and then dropped the *other*
            // folder's perfectly real, still-on-disk entries wholesale — so
            // the game vanished from whichever folder wasn't just scanned,
            // and rescanning that one flipped it straight back, forever.
            // The wholesale-carryover strategy above is right for a game
            // this scan genuinely didn't touch; it was simply never meant
            // to also throw away real files that live somewhere this scan
            // never looked.
            //
            // Deliberately excludes `.isDisk` entries: the caller already
            // folds `previous`'s own disk rows into `fresh` wholesale when
            // disks weren't re-audited, so re-appending one here would
            // duplicate it. And an entry with no `path` at all (a plain
            // `.missing` verdict, which belongs to no folder) is not a real
            // file anywhere, so it stays subject to the `isTouched` rule —
            // otherwise a stale "Missing" row would survive right next to
            // the fresh "Ok" that just superseded it.
            let hasRealFileOutsideScope = !entry.isDisk && (entry.path.map { !isInsideScope($0) } ?? false)
            if hasRealFileOutsideScope || !isTouched(entry, game: game) { append(entry) }
        }

        return AuditReport(entries: merged, correct: correct, incorrect: incorrect, badDump: badDump, missing: missing, surplus: surplus, unverifiable: unverifiable)
    }
}
