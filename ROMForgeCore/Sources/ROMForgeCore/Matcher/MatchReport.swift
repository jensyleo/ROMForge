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
    /// This rom is declared `status="nodump"` in the DAT — real hardware
    /// (commonly a PAL/GAL) that has never been successfully dumped by
    /// anyone, so the DAT itself has no CRC/MD5/SHA1 to check against, only
    /// a placeholder size. A local file sitting in this rom's own expected
    /// slot (matched by name, within this game's own scope) can never be
    /// "correct" — there's nothing to verify it against — but it's also not
    /// "unrecognized junk": the DAT explicitly documents this exact
    /// name/slot for this exact machine. Real case found live by jensyleo
    /// (2026-08-04): `neogeo.cpp`'s `gryzor` clone declares
    /// `007766.20d.bin` (`region="pals"`) this way; the real dumped file
    /// present in `gryzor.zip` was falling through every hash-keyed lookup
    /// (nodump has no hash to index by) straight into the generic surplus
    /// bucket, reported as plain gray "Unrecognized" — indistinguishable
    /// from genuine junk, when RomCenter/ClrMamePro both recognize this
    /// exact by-name-only case and label it accordingly. Claims the file
    /// (unlike `.foundElsewhere`/`.hashMismatch`) since a same-named file in
    /// a nodump rom's own slot has nowhere else it could belong.
    case nodump(HashedFile)
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
    /// True when no game claimed this file and its content matches no known
    /// hash (`requiredByGameDescription` is `nil`), but its own entry NAME
    /// matches some DAT rom declared `nodump` — a rom with no hash to
    /// verify by design, so a leftover/duplicate copy of it can only ever be
    /// recognized by name. See `ROMMatcher.match`'s own `nodumpRomNames` doc
    /// comment for the real duplicate-placeholder case this exists for.
    public let matchesNodumpRomName: Bool
    /// True when this file sits inside an archive (a zip entry, not a loose
    /// file) whose own base name matches some real DAT machine name — from
    /// `DATFile.allMachineNames`, the *raw* list, never `dat.games` (which
    /// under Merged mode excludes every clone; see that field's own doc
    /// comment for the exact cross-game "steal" bug checking the wrong list
    /// caused elsewhere in this same matcher). `false` for a loose file (no
    /// archive concept exists to be "known" or not) and for a file whose
    /// containing archive's name matches nothing in the DAT at all.
    /// jensyleo's own gray-file split (2026-08-06): distinguishes "this
    /// archive is real, but this one entry inside it isn't" (worth a second
    /// look — `AuditStatus.surplusInArchive`) from "nothing about this is
    /// recognized" (`AuditStatus.unknownFile`).
    public let isInKnownArchive: Bool
    /// The DAT machine name (e.g. `"1943"`) this file's containing archive
    /// really belongs to, when that archive turns out to be a whole game's
    /// archive sitting under the wrong filename — so a UI can say "rename
    /// this to `1943.zip`" instead of mislabelling it.
    ///
    /// jensyleo's own criterion (2026-08-06), after renaming `1943.zip` to
    /// `1949.zip` and seeing it reported as a duplicate: an archive counts as
    /// misnamed when **at least 60% of its files are roms of one single
    /// game** (see `ROMMatcher.meetsMisnamedThreshold` for why that exact
    /// number, and for its known limitation), and that game owns no archive
    /// of its own anywhere in the scan.
    ///
    /// Both halves matter. The threshold is what separates a genuinely
    /// renamed archive (38 of 38 files were `1943`'s) from an unrelated
    /// archive that merely happens to share a rom or two (shared hardware
    /// PALs, filler/padding content) — exactly the false positive that sank
    /// the earlier, weaker "≥2 matching roms" version of this idea (see the
    /// 2026-08-05 own-archive-only rewrite). And requiring the game to own
    /// nothing is what keeps a real duplicate labelled a duplicate: if
    /// `1943.zip` also exists, then `1949.zip` genuinely is a spare copy
    /// rather than the game's only, misnamed one.
    ///
    /// `nil` for everything else. Deliberately does NOT cause the game to
    /// claim these roms — a game's roms still only ever come from its own
    /// correctly-named archive (jensyleo's Finder philosophy, 2026-08-05).
    /// This is purely a more accurate label on the misnamed archive itself.
    public let misnamedArchiveForGameName: String?

    public init(
        file: HashedFile, requiredByGameDescription: String? = nil, matchesNodumpRomName: Bool = false,
        isInKnownArchive: Bool = false, misnamedArchiveForGameName: String? = nil
    ) {
        self.file = file
        self.requiredByGameDescription = requiredByGameDescription
        self.matchesNodumpRomName = matchesNodumpRomName
        self.isInKnownArchive = isInKnownArchive
        self.misnamedArchiveForGameName = misnamedArchiveForGameName
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
