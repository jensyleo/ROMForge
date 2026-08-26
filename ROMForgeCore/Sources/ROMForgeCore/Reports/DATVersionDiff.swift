// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// One "old name → new name" candidate rename, found by matching rom
/// hashes rather than game names — the strong signal a DAT update actually
/// renamed a set (MAME's own convention when a name turns out to collide,
/// gets corrected, or is standardized) as opposed to genuinely adding one
/// game and dropping another that happen to be unrelated.
public struct DATRenameCandidate: Equatable, Sendable {
    public let oldName: String
    public let newName: String
    /// The rom name (as declared in the OLD DAT) whose hash triggered this
    /// match — shown alongside the pair so a human can sanity-check the
    /// signal itself rather than take "possible rename" on faith.
    public let matchedRomName: String

    public init(oldName: String, newName: String, matchedRomName: String) {
        self.oldName = oldName
        self.newName = newName
        self.matchedRomName = matchedRomName
    }
}

/// Added/removed/possibly-renamed games between two versions of the same
/// DAT — pure metadata comparison, never touches a scanned collection or
/// its audit. `oldFile`/`newFile` mirror `DATVersionDiff.compare`'s own
/// parameter names so a caller can tell which side is which without
/// re-reading the call site.
public struct DATVersionDiff: Equatable, Sendable {
    public let added: [DATGame]
    public let removed: [DATGame]
    public let renamed: [DATRenameCandidate]

    public init(added: [DATGame], removed: [DATGame], renamed: [DATRenameCandidate]) {
        self.added = added
        self.removed = removed
        self.renamed = renamed
    }

    /// `oldFile` is whatever earlier/different DAT the user picked to
    /// compare against; `newFile` is the one already loaded/active for the
    /// system in memory — per jensyleo's own UX spec, only one file is ever
    /// picked from disk, the other side is always "whatever's already
    /// loaded".
    ///
    /// Matching is by game `name` (MAME's own machine short-name — the
    /// stable identifier a rename by definition changes, so it can't be
    /// used to detect the rename itself, only to know a name is "new" or
    /// "gone"). A game present under the same name in both files is
    /// neither added nor removed, even if every other field about it
    /// changed (description, year, roms, etc.) — this is a version/name
    /// diff, not a content diff.
    ///
    /// A "possible rename" pairs one removed game with one added game
    /// whenever at least one of the removed game's roms shares a hash
    /// (sha1 preferred, falling back to crc when a rom has no sha1 — same
    /// preference order `ROMMatcher` already uses elsewhere for identity)
    /// with one of the added game's roms. A hash claimed by more than one
    /// removed game, or by more than one added game, is deliberately
    /// excluded as ambiguous rather than resolved by pick order.
    public static func compare(oldFile: DATFile, newFile: DATFile) -> DATVersionDiff {
        // `uniqueKeysWithValues` would trap on two machine names that only
        // differ by case (unique to the DAT parser, but not necessarily
        // after this lowercasing) — a malformed/hand-edited DAT is untrusted
        // input, so first-one-wins here rather than crashing the app.
        func lowercasedByName(_ games: [DATGame]) -> [String: DATGame] {
            games.reduce(into: [String: DATGame]()) { result, game in
                let key = game.name.lowercased()
                if result[key] == nil { result[key] = game }
            }
        }
        let oldByName = lowercasedByName(oldFile.games)
        let newByName = lowercasedByName(newFile.games)

        let removedGames = oldFile.games.filter { newByName[$0.name.lowercased()] == nil }
        let addedGames = newFile.games.filter { oldByName[$0.name.lowercased()] == nil }

        // Indexed on BOTH sides — a hash only counts as a usable signal at
        // all when it names exactly one removed game and exactly one added
        // game. A hash shared by two removed games (e.g. a coincidentally
        // identical blank/placeholder rom across two otherwise-unrelated
        // sets) is just as ambiguous as one shared by two added games —
        // either way there's no single confident pairing to report, so
        // both are excluded up front rather than resolved by pick order.
        var removedGamesByHash: [String: Set<String>] = [:]
        for game in removedGames {
            for rom in game.roms {
                for hash in romIdentityHashes(rom) {
                    removedGamesByHash[hash, default: []].insert(game.name)
                }
            }
        }
        var addedGamesByHash: [String: Set<String>] = [:]
        for game in addedGames {
            for rom in game.roms {
                for hash in romIdentityHashes(rom) {
                    addedGamesByHash[hash, default: []].insert(game.name)
                }
            }
        }

        var renames: [DATRenameCandidate] = []
        // A removed game can only ever pair with exactly one added game —
        // once matched, both names are removed from further consideration
        // so the same pair never appears twice in `renamed` for two
        // different hash hits (the first hash hit found, in rom order,
        // wins).
        var claimedOldNames: Set<String> = []
        var claimedNewNames: Set<String> = []
        for removedGame in removedGames {
            guard !claimedOldNames.contains(removedGame.name) else { continue }
            for rom in removedGame.roms {
                let hashes = romIdentityHashes(rom)
                guard !hashes.isEmpty else { continue }
                guard let hash = hashes.first(where: { hash in
                    removedGamesByHash[hash]?.count == 1 && addedGamesByHash[hash]?.count == 1
                }) else { continue }
                guard let newName = addedGamesByHash[hash]?.first, !claimedNewNames.contains(newName) else { continue }
                claimedOldNames.insert(removedGame.name)
                claimedNewNames.insert(newName)
                renames.append(DATRenameCandidate(oldName: removedGame.name, newName: newName, matchedRomName: rom.name))
                break
            }
        }

        return DATVersionDiff(added: addedGames, removed: removedGames, renamed: renames)
    }

    /// Sha1 preferred over crc (lower collision risk, same preference
    /// `ROMMatcher` already applies for rom identity elsewhere) — both are
    /// included when present so a rom missing one hash still gets to
    /// participate in matching via whichever it does have. A `nodump` rom
    /// declares no real hash at all and is correctly excluded (an empty
    /// result here), never treated as a coincidental match against another
    /// equally hash-less entry.
    private static func romIdentityHashes(_ rom: DATRom) -> [String] {
        [rom.sha1, rom.crc].compactMap { $0 }.filter { !$0.isEmpty }
    }
}
