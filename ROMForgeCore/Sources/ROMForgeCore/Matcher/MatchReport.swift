// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Outcome of matching one expected `DATRom` against the scanned collection.
public enum RomMatchStatus: Equatable, Sendable {
    /// A local file matches by size and hash, with the exact expected name.
    /// `viaHeaderStrip` is `true` when the match only succeeded once a
    /// detected copier header (iNES/Lynx/copier512, see `HeaderSkipRule`)
    /// was stripped from the file — the file itself still has that header
    /// on disk, it's just not part of what the DAT's own hash describes.
    case correct(HashedFile, viaHeaderStrip: Bool = false)
    /// A local file matches by size and hash, but under a different name.
    case misnamed(HashedFile, viaHeaderStrip: Bool = false)
    /// A rom whose own game is restricted to its own archive only (Un-merged
    /// self-containment, see `ROMMatcher.swift`'s own `strictOwnArchiveOnly`
    /// doc comment) doesn't have this rom in its own archive — but the
    /// content genuinely exists somewhere else in the scan (e.g. a shared
    /// BIOS rom sitting in the BIOS's own archive, where it correctly
    /// belongs). Real bug found live by jensyleo (2026-08-04): reporting
    /// this the same as a truly absent rom (`.missing`) made a fully
    /// intact NEOGEO collection under Rom=Un-merged/Bios=Un-merged show as
    /// "Bad"/incomplete (orange) rather than what it actually is — a pure
    /// naming/organization mismatch (yellow "Incorrect"), since every byte
    /// the game needs is genuinely present and visible to the app, just
    /// not consolidated into one self-contained archive the way Un-merged
    /// expects. Never claims/consumes the file this refers to — whichever
    /// game actually owns it still claims it normally for its own
    /// `.correct`/`.misnamed` result.
    case foundElsewhere(HashedFile)
    /// A local file sits exactly where this rom is expected — same entry
    /// name, in this game's own archive (or, for a loose scan, a file with
    /// this exact name) — but its CRC32/MD5/SHA doesn't match what the DAT
    /// declares. jensyleo's own definition (2026-08-04): a genuine content
    /// problem ("Bad"), distinct from `.missing` (nothing there at all)
    /// and from `.misnamed`/`.foundElsewhere` (right content, wrong name/
    /// location) — the file occupying this rom's own slot is simply
    /// corrupt, a bad dump, or otherwise wrong. Never claims/consumes the
    /// file (same reasoning as `.foundElsewhere`): if that exact file
    /// happens to hash-match some *other* rom by coincidence, that rom
    /// still gets to claim it normally.
    case hashMismatch(HashedFile)
    /// No local file matches by size and hash, anywhere in the scan.
    case missing
}

public struct RomMatch: Equatable, Sendable {
    public let rom: DATRom
    public let status: RomMatchStatus

    public init(rom: DATRom, status: RomMatchStatus) {
        self.rom = rom
        self.status = status
    }
}

public struct GameMatchResult: Equatable, Sendable {
    public let game: DATGame
    public let matches: [RomMatch]

    public init(game: DATGame, matches: [RomMatch]) {
        self.game = game
        self.matches = matches
    }
}

/// A local file that matched no expected ROM this scan claimed it for.
public struct SurplusFile: Equatable, Sendable {
    public let file: HashedFile
    /// Set when the file's content is nonetheless genuinely recognized —
    /// it hash-matches a rom *some* DAT game declares, just not one that
    /// claimed it here (e.g. a clone's own archive still physically
    /// holding a rom Split-mode expects only in the parent's archive; see
    /// `ROMMatcher.match`'s own `romsByHash`). `nil` for a file that
    /// matches nothing in the DAT at all — genuinely unrecognized junk.
    public let requiredByGameDescription: String?

    public init(file: HashedFile, requiredByGameDescription: String? = nil) {
        self.file = file
        self.requiredByGameDescription = requiredByGameDescription
    }
}

/// The full result of matching a `DATFile` against a set of hashed local
/// files: per-game results, plus any local files left over that matched no
/// expected ROM at all (candidates for the "surplus" report).
public struct MatchReport: Equatable, Sendable {
    public let games: [GameMatchResult]
    public let surplusFiles: [SurplusFile]

    public init(games: [GameMatchResult], surplusFiles: [SurplusFile]) {
        self.games = games
        self.surplusFiles = surplusFiles
    }
}
