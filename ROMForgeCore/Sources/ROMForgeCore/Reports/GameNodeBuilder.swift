// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The free functions that scope, group, and aggregate `AuditEntry`s into
/// `GameNode` rows for the "Database"/"ROM folder" tree — moved out of
/// `LibraryDetailView.swift` (App) into Core (2026-08-13, "Grupo B" of the
/// App-logic extraction, jensyleo's own request) so they're unit-testable.
/// Behavior unchanged, pure relocation; see each function's own history in
/// git/memory for the real bugs its specific checks were added to fix.
public enum GameNodeBuilder {
    /// Applies the "Database" category (or "Rom files" folder) scope to an
    /// arbitrary entry list.
    public static func scoped(_ entries: [AuditEntry], databaseCategory: DatabaseCategory?, romFolder: URL?, gamesInFolder: Set<String>) -> [AuditEntry] {
        let categoryFiltered = (databaseCategory ?? .allGames).apply(to: entries)

        // A "Rom files" folder scopes the same audit down to what that
        // folder actually contributed. A missing rom has no `path` at all,
        // so it can't be scoped by path like everything else — scoped
        // instead to games that already have at least one real file *in
        // this folder*, computed from the full report (not
        // `categoryFiltered`) so it doesn't shift just because the status
        // filter itself changes.
        guard let romFolder else { return categoryFiltered }
        return categoryFiltered.filter { entry in
            // A `.foundElsewhere` entry's own `path` points to whichever
            // OTHER archive actually has the content — it's never this
            // entry's own game's real file, so it must never be trusted to
            // mean "this game is physically in this folder". Falls through
            // to the `gamesInFolder` check below instead, which only
            // reflects a game's own genuinely-owned files.
            if let path = entry.path, entry.foundElsewhereArchiveName == nil { return path.path.hasPrefix(romFolder.path) }
            return entry.game.map(gamesInFolder.contains) ?? false
        }
    }

    /// Which games have at least one real file physically inside
    /// `selectedFolder` — feeds `scoped(_:)`'s own `gamesInFolder`
    /// parameter.
    public static func recomputeGamesInFolder(entries: [AuditEntry], selectedFolder: URL?) -> Set<String> {
        guard let selectedFolder else { return [] }
        return Set(
            entries.compactMap { entry -> String? in
                // Excludes `.foundElsewhere` entries — see `scoped(_:)`'s
                // own doc comment for why their `path` never means "this
                // game's own file", only "where its content was borrowed
                // from".
                guard entry.foundElsewhereArchiveName == nil, let path = entry.path, path.path.hasPrefix(selectedFolder.path) else { return nil }
                return entry.game
            }
        )
    }

    /// How many *archives* (one ZIP/7z per game/machine) have each status
    /// as their aggregate, within the current scope — counts games/
    /// archives, not individual ROM entries, so a folder with a handful of
    /// archives reports a number that matches what's visibly in the tree.
    public static func computeScopedStatusCounts(scopedEntries: [AuditEntry], gamesByName: [String: DATGame]) -> [AuditStatus: Int] {
        var entriesByGame: [String: [AuditEntry]] = [:]
        var surplusByArchive: [String: [AuditEntry]] = [:]
        for entry in scopedEntries {
            if let game = entry.game {
                entriesByGame[game, default: []].append(entry)
            } else {
                surplusByArchive[SurplusArchiveKey.key(for: entry), default: []].append(entry)
            }
        }
        // Checked against the DAT's own real catalog (`gamesByName`), not
        // "does `entriesByGame` already have this key" — a real game with
        // zero expected roms under the current merge mode never gets a key
        // from real entries at all. Without this fold, a game whose only
        // problem is a folded-in "Not needed here" file would count as
        // "Correct" here while its own row reads yellow in the tree.
        // Any archive left over below (no `gamesByName` entry to fold
        // into) with ANY identified content in it gets counted here too,
        // as one archive under `.incorrect` — same
        // `hasAnyIdentifiedContent` check `gameNodes(from:)` uses to color
        // its row yellow instead of gray, so this button's count never
        // disagrees with the rows it filters.
        var orphanedIdentifiedArchiveCount = 0
        for (archiveKey, surplus) in surplusByArchive {
            let matchingGame = (SurplusArchiveKey.displayName(forKey: archiveKey) as NSString).deletingPathExtension
            if gamesByName[matchingGame] != nil {
                entriesByGame[matchingGame, default: []].append(contentsOf: surplus)
            } else if surplus.contains(where: { $0.requiredByGameDescription != nil || $0.status == .unverifiable }) {
                orphanedIdentifiedArchiveCount += 1
            }
        }
        var counts: [AuditStatus: Int] = [:]
        counts[.incorrect] = orphanedIdentifiedArchiveCount
        for entries in entriesByGame.values {
            // No folder-scope special case: "Missing" counts the same way
            // in a "Rom files" folder as in "Database" — `scoped(_:)` has
            // already narrowed `scopedEntries` to games that genuinely own
            // at least one real file *in this folder*, so a `.missing` rom
            // reaching here always belongs to a set this folder really is
            // part of.
            counts[GameStatusRollup.romOnlyGameCategory(for: entries), default: 0] += 1
        }
        // A genuinely unrecognized archive ("Unknown game") isn't counted
        // under "Bad" (`.badDump`) at all — it gets its own separate
        // `computeUnknownArchivesCount` instead.
        return counts
    }

    /// How many genuinely unrecognized archives ("Unknown game" —
    /// `GameNode.isSurplusBucket`) are in the current scope. Takes the
    /// *unfiltered* base node list — a surplus bucket's presence here must
    /// never depend on any visibility toggle applied afterward.
    public static func computeUnknownArchivesCount(baseNodes: [GameNode]) -> Int {
        // Excludes a surplus bucket `gameNodes(from:)` reclassified yellow
        // (`.incorrect`, "not needed here…") — genuinely unrecognized
        // content (`.surplus`) is the only thing this count is meant to
        // mean.
        baseNodes.filter { $0.isSurplusBucket && $0.aggregateStatus == .surplus }.count
    }

    /// Every real game's row for a "Database" category before any scan has
    /// ever run — browsing "Database" categories only ever needs the DAT
    /// that's already loaded, it shouldn't have to wait for a folder to be
    /// scanned first. Used only for "Database" categories — a "Rom files"
    /// folder inherently needs real scan data.
    public static func unscannedCatalogNodes(matching category: DatabaseCategory, preloadedGames games: [DATGame]) -> [GameNode] {
        let categoryFiltered: [DATGame]
        switch category {
        case .allGames, .byManufacturer, .byYear: categoryFiltered = games
        // All reflect an actual scan result (which roms really matched/
        // are missing/misnamed/complete), not anything the DAT alone can
        // answer — honestly empty here rather than showing something
        // misleadingly labeled.
        case .verifiedGames, .gamesWithBadDumps, .gamesWithNodump, .missingGames, .incorrectGames,
             .completeGames, .fixableGames, .partialGames, .emptyGames: categoryFiltered = []
        case .originals: categoryFiltered = games.filter { $0.cloneOf == nil }
        case .clones: categoryFiltered = games.filter { $0.cloneOf != nil }
        case .biosFiles: categoryFiltered = games.filter(\.isBios)
        case .gamesWithCHD: categoryFiltered = games.filter { !$0.disks.isEmpty }
        case .gamesWithSamples: categoryFiltered = games.filter(\.hasSamples)
        case .gamesRequiringBIOS: categoryFiltered = games.filter { !$0.biosSetNames.isEmpty }
        case .gamesWithDeviceRefs: categoryFiltered = games.filter { !$0.deviceRefs.isEmpty }
        }
        return categoryFiltered.map { game in
            GameNode(id: "game-\(game.name)", name: game.name, entries: [], aggregateStatus: nil, sourceGame: game)
        }
    }

    /// Groups entries by game and buckets game-less (surplus) entries into
    /// their own node — every game/clone is its own flat row (no
    /// parent/clone tree nesting: a clone is still its own separate
    /// archive with its own file on disk).
    public static func gameNodes(
        from entries: [AuditEntry], gamesByName: [String: DATGame], gameAggregateStatusByName: [String: AuditStatus],
        combineRomAndCHD: Bool, isFolderScoped: Bool
    ) -> [GameNode] {
        var entriesByGame: [String: [AuditEntry]] = [:]
        var gameOrder: [String] = []
        var surplusEntries: [AuditEntry] = []

        for entry in entries {
            guard let game = entry.game else {
                surplusEntries.append(entry)
                continue
            }
            if entriesByGame[game] == nil {
                gameOrder.append(game)
            }
            entriesByGame[game, default: []].append(entry)
        }

        // Each unrecognized physical archive gets its own row ("Unknown
        // game") instead of being dumped into one combined "Surplus
        // files" bucket. Several surplus entries can share one archive,
        // so they're grouped by their containing archive name first.
        // Keyed by each archive's FULL path, not just its filename, so
        // the same-named archive in several ROM folders stays several
        // distinct rows.
        var surplusByArchive: [String: [AuditEntry]] = [:]
        var surplusOrder: [String] = []
        for entry in surplusEntries {
            let archiveKey = SurplusArchiveKey.key(for: entry)
            if surplusByArchive[archiveKey] == nil { surplusOrder.append(archiveKey) }
            surplusByArchive[archiveKey, default: []].append(entry)
        }

        // A surplus file living *inside* an archive that also fully/
        // partially matches a real known game is an extra/unexpected file
        // in an otherwise-recognized set, not a second, unrelated "Unknown
        // game" — folding it into that same game's own entries avoids two
        // rows both named after the same archive, one matched and one
        // "Unknown". Checked against `gamesByName` (the loaded DAT's own
        // real game catalog), not `gameAggregateStatusByName`'s keys — a
        // real DAT game whose entire expected rom list is empty under the
        // current merge mode never produces a single `entry.game != nil`
        // row, so it never gets a key in `gameAggregateStatusByName`
        // either, but `gamesByName` still recognizes it as real.
        for archiveKey in surplusOrder {
            let matchingGame = (SurplusArchiveKey.displayName(forKey: archiveKey) as NSString).deletingPathExtension
            guard gamesByName[matchingGame] != nil else { continue }
            if entriesByGame[matchingGame] == nil { gameOrder.append(matchingGame) }
            entriesByGame[matchingGame, default: []].append(contentsOf: surplusByArchive[archiveKey] ?? [])
            surplusByArchive.removeValue(forKey: archiveKey)
        }
        surplusOrder.removeAll { surplusByArchive[$0] == nil }

        var roots = gameOrder.flatMap { name -> [GameNode] in
            let entries = entriesByGame[name] ?? []
            let romEntries = entries.filter { !$0.isDisk }
            let diskEntries = entries.filter(\.isDisk)

            // `combineRomAndCHD`'s own toggle (off by default): the old,
            // pre-split behavior — one row, rom+CHD entries folded
            // together. Bypasses `gameAggregateStatusByName` (which is
            // deliberately rom-only now) since the whole point here is to
            // reproduce how it used to look, mixed status and all.
            if combineRomAndCHD {
                return [GameNode(id: "game-\(name)", name: name, entries: entries, aggregateStatus: GameStatusRollup.gameCategory(for: entries), sourceGame: gamesByName[name])]
            }

            // Split into up to two independent rows — a game's rom and
            // its CHD disk each show their own real Correct/Missing/
            // Incorrect as a *separate* row. Most games have only roms
            // (no `isDisk` entries at all) and still get exactly one row.
            let diskStatus = diskEntries.isEmpty ? nil : GameStatusRollup.gameCategory(for: diskEntries)

            var nodes: [GameNode] = []
            // A missing rom row is skipped entirely when this same game
            // has a CHD that isn't itself also fully missing — showing
            // the missing rom as its own separate red row, right next to
            // that same game's correct green disk row, read as more
            // confusing than helpful for a ROM+CHD game specifically. Only
            // applies to a genuinely `.missing` rom (nothing at all
            // found) — an `.incorrect`/misnamed rom still shows, since
            // that's a real, fixable problem worth surfacing regardless
            // of the CHD.
            let romIsMissing = romEntries.allSatisfy { $0.status == .missing }
            let skipMissingRom = romIsMissing && diskStatus != nil && diskStatus != .missing
            if !romEntries.isEmpty, !skipMissingRom {
                // The row's own badge always reflects the game's *true*
                // status, independent of which individual-rom status
                // toggles are currently active — `gameAggregateStatusByName`
                // is the toggle-independent source of truth for that,
                // already rom-only, matching `romEntries`.
                //
                // In a "Rom files" folder the aggregate comes from this
                // folder's own `romEntries` instead of the DAT-wide
                // `gameAggregateStatusByName` — NOT to suppress "Missing",
                // but because a system can have several "Rom files"
                // folders and `scoped(_:)` has already dropped the roms
                // this game keeps in a *different* one. Consulting the
                // DAT-wide aggregate here would paint a game red in
                // folder A purely because part of its set legitimately
                // lives in folder B.
                let trueStatus = isFolderScoped
                    ? GameStatusRollup.gameCategory(for: romEntries)
                    : gameAggregateStatusByName[name] ?? GameStatusRollup.gameCategory(for: romEntries)
                nodes.append(GameNode(id: "game-\(name)", name: name, entries: romEntries, aggregateStatus: trueStatus, sourceGame: gamesByName[name]))
            }
            if let diskStatus {
                nodes.append(GameNode(id: "game-\(name)-chd", name: name, entries: diskEntries, aggregateStatus: diskStatus, isDiskRow: true, sourceGame: gamesByName[name]))
            }
            return nodes
        }
        for archiveKey in surplusOrder {
            let bucketEntries = surplusByArchive[archiveKey] ?? []
            // A clone excluded from `dat.games` entirely (folded into its
            // parent, but still a real archive) reads as gray "Unknown
            // game" even when every single one of its own entries is
            // fully identified as belonging to a real game elsewhere
            // (`requiredByGameDescription`). Gray/"Unknown" should mean
            // genuinely no idea what this is; this archive's content is
            // the opposite of that, so it reads yellow/`.incorrect`
            // instead, same as the individual per-file rows already do.
            // `.unverifiable` counts as identified too, alongside a real
            // `requiredByGameDescription`.
            //
            // ANY identified entry is enough, not all of them — requiring
            // *every* entry to be identified let a couple of junk strays
            // drag the whole row to gray "Unknown game", hiding real roms
            // sitting in the same archive. The junk entries inside keep
            // their own gray "Unrecognized" rows: the archive-level row
            // says "there's something real here", the file-level rows say
            // precisely which parts aren't.
            let hasAnyIdentifiedContent = bucketEntries.contains { $0.requiredByGameDescription != nil || $0.status == .unverifiable }
            roots.append(
                GameNode(
                    // `id` is the archive's full path, so two same-named
                    // archives in different ROM folders stay two
                    // distinct, separately-selectable rows; `name` is
                    // just the filename for display.
                    id: "surplus-\(archiveKey)",
                    name: SurplusArchiveKey.displayName(forKey: archiveKey),
                    entries: bucketEntries,
                    aggregateStatus: hasAnyIdentifiedContent ? .incorrect : .unknownFile,
                    isSurplusBucket: true
                )
            )
        }

        // MAME's own `-listxml` output (and a real DAT generally) already
        // lists machines/games in roughly alphabetical order, but unknown
        // archives were only ever appended at the end — sorting the
        // combined list interleaves them where they'd actually sit
        // alphabetically, matching the reference scanner view.
        //
        // Real slowness found live (2026-08-13, jensyleo: navigating with
        // the keyboard through/from "All games" — ~45,000 rows — felt
        // slow): `localizedCaseInsensitiveCompare` is locale-aware (full
        // ICU collation rules), and was being called here on every one of
        // the O(n log n) comparisons a sort does — for 45,000 rows,
        // roughly 45,000 × log₂(45,000) ≈ 700,000 locale-aware string
        // comparisons, EVERY time this category's nodes are rebuilt (any
        // selection change, scan, or filter toggle). Display ordering has
        // no real dependence on locale-specific collation rules (this
        // isn't sorting user-facing prose), so the sort key is computed
        // ONCE per row up front (`n` calls to `lowercased()`, not `n log
        // n`) and compared with the plain `<` operator (a fast ordinal
        // comparison, no ICU tables) instead.
        let keyed = roots.map { ($0, ($0.actualFileName ?? $0.name).lowercased()) }
        return keyed.sorted { $0.1 < $1.1 }.map(\.0)
    }
}
