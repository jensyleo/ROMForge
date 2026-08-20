// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The states a `Matcher` result collapses into for reporting.
/// jensyleo's own definitions (2026-08-04):
/// - `correct`: right name, right hash.
/// - `incorrect`: right content (hash matches), but the wrong name and/or
///   found somewhere other than where it's expected — a naming/location
///   problem, not a content one.
/// - `badDump`: a file sits exactly where this rom is expected, but its
///   CRC32/MD5/SHA doesn't match — a genuine content problem ("Bad").
/// - `missing`: nothing matching this rom exists anywhere the app can see.
/// - `unverifiable`: a local file sits in a rom's own expected slot (or,
///   for a surplus file, its entry NAME matches a DAT-declared `nodump` rom
///   somewhere — see `SurplusFile.matchesNodumpRomName`), but the rom itself
///   is DAT-declared `nodump` — nothing to check its content against, so it
///   can never be `correct`, but the DAT explicitly documents this exact
///   name/slot, so it isn't unknown either. Added 2026-08-04, real case
///   found live (`gryzor`'s nodump `007766.20d.bin` PAL) — see
///   `RomMatchStatus.nodump`'s own doc comment. Detected by NAME, never by
///   hash — a `nodump` rom has no hash in the DAT by definition, so this can
///   never be reached via a hash search.
///
/// jensyleo's own gray-file unification (2026-08-06), replacing the single
/// `surplus` bucket with two more specific cases after a real, confusing
/// live report (Gryzor's genuinely-correct nodump PAL and two junk
/// screenshot files in "TEST 1"/"TEST 1 2" archives both rendered
/// identically gray, with no way to tell "keep this" from "delete this" at a
/// glance):
/// - `surplusInArchive`: a local file's hash matches NO rom anywhere in the
///   whole DAT, but it sits inside an archive whose own base name IS a real
///   DAT machine name — the archive is recognized, this one entry inside it
///   isn't. Likely a leftover/duplicate/misc file the user should check.
/// - `unknownFile`: a local file's hash matches no rom anywhere in the DAT,
///   AND (for an archive-organized scan) its containing archive's own name
///   isn't a real DAT machine name either, or (for a loose, non-archive
///   scan) there's no archive concept to check at all — genuinely
///   unrecognized junk (e.g. a screenshot, a readme, a backup file dropped
///   into a ROM folder). Should usually just be deleted.
///
/// Deliberately checked by NAME first (`unverifiable`), independent of
/// archive — a nodump rom has no hash, so it can surface in this state no
/// matter which archive it happens to be found in (see
/// `ROMMatcher.match`'s own `nodumpRomNames` doc comment); only once that
/// check fails does the archive-known-or-not distinction between
/// `surplusInArchive`/`unknownFile` apply.
public enum AuditStatus: String, Equatable, Sendable, CaseIterable {
    case correct
    case incorrect
    case badDump
    case missing
    case unverifiable
    /// A local file's hash matches no rom in the DAT at all, but the
    /// archive containing it is a real, recognized DAT machine name.
    case surplusInArchive
    /// A local file's hash matches no rom in the DAT at all, and (for an
    /// archive-organized scan) its containing archive isn't a recognized
    /// DAT machine name either.
    case unknownFile
    /// Legacy value, kept only so an on-disk cached audit row written
    /// before the 2026-08-06 gray-file split still decodes to *something*
    /// sane (`AuditReportDatabase`'s own decode fallback) rather than
    /// failing outright — new code never assigns this. Equivalent in
    /// meaning/severity to `unknownFile`.
    case surplus
    /// A synthetic row `AuditReporter.addingDuplicateSets` appends for a
    /// game whose otherwise-genuine set (`.correct`/`.incorrect`/`.badDump`
    /// roms) is physically present under more than one of the system's own
    /// configured ROM folders (`RomSystem.romFolderURLs`) — a whole extra
    /// copy of a set the user already has, not a naming/content problem
    /// with the set itself. Added 2026-08-19, jensyleo's own request:
    /// multiple ROM folders per system is common (different drives/region
    /// subfolders), and until now a same-named archive sitting in a second
    /// folder was only ever visible indirectly, one rom at a time, as an
    /// ordinary `.incorrect` "Not needed here" surplus row — accurate, but
    /// with no single place that actually says "this whole set is
    /// duplicated across folders."
    ///
    /// Never assigned by `ROMMatcher`/plain `AuditReporter.generate`
    /// itself — only by the dedicated post-pass, run after the real
    /// per-rom statuses are already settled, so this never displaces or
    /// hides the genuine `.correct`/`.incorrect`/`.badDump` row for the
    /// same rom; it's purely an additional, game-level informational row.
    /// Deliberately excluded from `worst(among:)`'s severity ranking (same
    /// tier as `.correct`/`.surplus`) — a duplicate copy elsewhere doesn't
    /// make the primary copy any less correct.
    case duplicateSet
}

/// One row of an audit report: an expected ROM's outcome, or a leftover local
/// file that matched no expected ROM. `expected*` comes from the DAT (absent
/// for surplus files, which the DAT says nothing about); `actual*` comes from
/// hashing the local file (absent for missing ROMs, which have no local file).
public struct AuditEntry: Equatable, Sendable {
    public let status: AuditStatus
    public let game: String?
    /// The DAT's own human-readable name for `game` (its `<description>`,
    /// e.g. "Street Fighter II: The World Warrior (World 910522)") — quite
    /// different from `game` itself, which is the short internal machine
    /// code the archive is named after (e.g. "sf2"). Nil for surplus files,
    /// which have no DAT game backing them.
    public let gameDescription: String?
    /// The parent game's name, if `game` is a clone (from the DAT's
    /// `cloneof`/`romof`) — lets a UI group clone sets under their parent,
    /// RomCenter-style. Nil for parent games and for surplus files.
    public let cloneOf: String?
    /// True when `game` is a MAME BIOS set — lets a UI offer a "Bios files"
    /// filter, RomCenter-style. Always false for surplus files.
    public let isBios: Bool
    /// True when `game` declares a CHD disk in the DAT — presence-only, not
    /// verification: ROMForge doesn't check whether a matching `.chd` file
    /// actually exists or hash-verify it yet (`CHDHeaderReader`/`CHDMatcher`
    /// exist in Core but aren't wired into the scan pipeline). Always false
    /// for surplus files.
    public let hasCHD: Bool
    /// True when `game` declares samples (`<sample>`) in the DAT —
    /// presence-only, same caveat as `hasCHD`. Always false for surplus
    /// files.
    public let hasSamples: Bool
    /// True when this specific rom's DAT entry is flagged `baddump` or
    /// `nodump` — a claim about the reference dump itself, independent of
    /// what's (or isn't) found locally. Always false for surplus files,
    /// which have no DAT entry to flag.
    public let isBadDump: Bool
    /// True when the DAT declares this specific rom/disk `optional="yes"` —
    /// MAME itself can run the machine without it, distinct from `nodump`
    /// (which means "can't verify," not "not needed"). Real case found
    /// live by jensyleo (2026-08-05): 3 `<disk>` entries in a real MAME
    /// 0.288 dump (`cubeqst`/`cubeqsta`/`atronic`), all with a real sha1 —
    /// genuinely dumped content MAME just doesn't require. Always `false`
    /// for surplus files, which have no DAT rom/disk entry to flag, and for
    /// any DAT format without this concept (Logiqx/software-list).
    public let isOptional: Bool
    /// The DAT's own dump-quality claim for this specific rom (`good`,
    /// `baddump`, or `nodump`) — `isBadDump` above collapses the latter two
    /// into one boolean for filtering; this keeps the actual distinction
    /// for display. `nil` for surplus files, which have no DAT rom entry to
    /// carry a status at all.
    public let romDumpStatus: RomDumpStatus?
    /// The `merge="..."` attribute from the DAT (MAME `-listxml`): names
    /// the rom in this machine's parent/BIOS archive that this one is
    /// identical to, i.e. "don't expect this file here, it's already in
    /// the parent's archive". `nil` when the DAT declares none (Logiqx has
    /// no such concept; also nil for surplus files).
    ///
    /// jensyleo's own report (2026-08-18): a "Merge name" column in the
    /// Roms table (removed the same day) never showed anything for any
    /// rom, in any merge mode. Root cause, confirmed by reading
    /// `MAMESetLayoutPlanner`: every one of `splitGame`/`nonMergedGame`/
    /// `mergedGame` filters its own output down to `mergeName == nil`
    /// roms only — a merge-tagged rom is, by definition, resolved to (and
    /// replaced by) its ancestor's own un-tagged declaration before ever
    /// reaching an `AuditEntry`, or dropped entirely when it turns out to
    /// be BIOS content (`foldBiosRoms`'s job instead). So this field is
    /// architecturally always `nil` by the time `AuditReporter` ever sees
    /// it — not a bug in `AuditReporter` itself, just a display column
    /// with no real data to show given how the expected romset is built.
    /// Kept on the model (still meaningful pre-resolution, inside
    /// `MAMESetLayoutPlanner`'s own intermediate `DATRom` values) — only
    /// the dead UI column was removed.
    public let mergeName: String?
    /// Comma-joined names of the CHD disk(s) `game` declares, when any —
    /// `hasCHD` above is presence-only; this is the actual disk name(s) a
    /// user would need to go find. `nil` when `game` declares none.
    public let chdNames: String?
    /// `game`'s release year, when the DAT declares one (MAME
    /// `-listxml`'s `<year>`) — `nil` for formats/entries that don't.
    public let gameYear: String?
    /// `game`'s manufacturer/developer, when the DAT declares one (MAME
    /// `-listxml`'s `<manufacturer>`) — `nil` for formats/entries that
    /// don't.
    public let gameManufacturer: String?
    /// Comma-joined names of BIOS ROM variants `game` itself declares
    /// (MAME `-listxml`'s `<biosset>`) — e.g. several selectable
    /// region/revision BIOSes on one PCB. `nil` when `game` declares none.
    public let requiredBiosNames: String?
    /// Comma-joined names of internal "device" sub-machines `game`
    /// references (MAME `-listxml`'s `<device_ref>`) — a dependency list,
    /// not real games themselves. `nil` when `game` declares none.
    public let deviceRefNames: String?
    /// True when this rom's local file only matched once a detected copier
    /// header (iNES/Lynx/copier512 — see `HeaderSkipRule`) was stripped from
    /// it, rather than matching the DAT's declared hash byte-for-byte as-is.
    /// The file on disk still has that header; it's just not part of what
    /// the DAT's own hash describes. Always `false` for `.missing`/`.surplus`
    /// entries, which never went through a header-strip comparison at all.
    /// Added 2026-07-30, jensyleo's own request after reviewing every
    /// `infoText(for:)` case in `LibraryDetailView.swift` — **not yet
    /// verified live**: none of NES/Atari Lynx/SNES/Game Boy/PC Engine/
    /// Master System/Genesis were available to test this session. Re-check
    /// the actual "Ok, header removed" UI text next time a real headered
    /// dump from one of those systems gets scanned.
    public let matchedViaHeaderStrip: Bool
    /// True only for a `DiskAuditor`-produced row (a CHD, not a rom).
    /// jensyleo's own report (2026-07-30): a game's CHD showing up
    /// correct was still dragged down to an overall "Bad" status by a rom
    /// the user has no interest in owning, because per-game status
    /// aggregation (`gameCategory(for:)` in `LibraryDetailView.swift`)
    /// folded rom and disk entries for the same game into one worst-of-all
    /// verdict. This flag lets that aggregation exclude disk entries from
    /// a game's headline rom-completeness status — the disk's own row
    /// still shows its own real, independent status, it just no longer
    /// contaminates the rom verdict (and vice versa).
    public let isDisk: Bool
    /// Set only for a rom the matcher found genuinely present somewhere
    /// else in the scan — another game's archive, a loose file, a
    /// different path — rather than truly absent (`RomMatchStatus
    /// .foundElsewhere`, see its own doc comment). `nil` for every other
    /// status. Carries the containing archive/file's own name so the UI
    /// can say exactly where it was found ("Available in another game:
    /// neogeo.zip"), jensyleo's own request (2026-08-04) for this to read
    /// as its own distinct, reassuring message rather than a generic "Bad
    /// name" — the point is precisely that this *isn't* a naming mistake
    /// to go fix, it's already correctly organized somewhere else.
    public let foundElsewhereArchiveName: String?
    /// Set for a rediscovered-surplus file — no game claimed it in this
    /// scan, but its content still hash-matches a real rom *some* DAT game
    /// declares (`SurplusFile.requiredByGameDescription`, see its own doc
    /// comment for the real Split-mode case this exists for). This is what
    /// makes `AuditReporter` classify such a file `.incorrect` (a real,
    /// identified, fixable location problem) rather than `.surplus`
    /// (jensyleo's own correction, 2026-08-04: "surplus" must mean
    /// genuinely unrecognized, not "known but currently misplaced"). `nil`
    /// for a genuinely unrecognized surplus file that matches nothing in
    /// the DAT at all, and for every rom/disk entry that has a real
    /// expected `game` of its own.
    public let requiredByGameDescription: String?
    /// The DAT machine name this entry's containing archive really belongs to
    /// when that archive is a whole game's set under the wrong filename — see
    /// `SurplusFile.misnamedArchiveForGameName` for jensyleo's own ≥50%
    /// criterion. Lets a UI say "rename this to `1943.zip`" rather than
    /// mislabelling the archive a duplicate.
    public let misnamedArchiveForGameName: String?
    /// Set only for a `.duplicateSet` row — the path of the OTHER, primary
    /// copy of this same game's set (the earliest-configured ROM folder
    /// that owns it; see `DuplicateSetDetector`'s own doc comment for why
    /// folder order decides which copy is "primary"). `path` on this same
    /// entry is the duplicate copy itself; this is where the real one
    /// already lives. `nil` for every other status.
    public let duplicateSetPrimaryPath: URL?
    public let name: String
    public let path: URL?
    public let expectedSize: Int64?
    public let actualSize: Int64?
    public let expectedCRC: String?
    public let expectedMD5: String?
    public let expectedSHA1: String?
    public let actualCRC: String?
    public let actualMD5: String?
    public let actualSHA1: String?

    public init(
        status: AuditStatus,
        game: String?,
        gameDescription: String? = nil,
        cloneOf: String? = nil,
        isBios: Bool = false,
        hasCHD: Bool = false,
        hasSamples: Bool = false,
        isBadDump: Bool = false,
        isOptional: Bool = false,
        romDumpStatus: RomDumpStatus? = nil,
        mergeName: String? = nil,
        chdNames: String? = nil,
        gameYear: String? = nil,
        gameManufacturer: String? = nil,
        requiredBiosNames: String? = nil,
        deviceRefNames: String? = nil,
        matchedViaHeaderStrip: Bool = false,
        isDisk: Bool = false,
        foundElsewhereArchiveName: String? = nil,
        requiredByGameDescription: String? = nil,
        misnamedArchiveForGameName: String? = nil,
        duplicateSetPrimaryPath: URL? = nil,
        name: String,
        path: URL?,
        expectedSize: Int64? = nil,
        actualSize: Int64? = nil,
        expectedCRC: String? = nil,
        expectedMD5: String? = nil,
        expectedSHA1: String? = nil,
        actualCRC: String? = nil,
        actualMD5: String? = nil,
        actualSHA1: String? = nil
    ) {
        self.status = status
        self.game = game
        self.gameDescription = gameDescription
        self.cloneOf = cloneOf
        self.isBios = isBios
        self.hasCHD = hasCHD
        self.hasSamples = hasSamples
        self.isBadDump = isBadDump
        self.isOptional = isOptional
        self.romDumpStatus = romDumpStatus
        self.mergeName = mergeName
        self.chdNames = chdNames
        self.gameYear = gameYear
        self.gameManufacturer = gameManufacturer
        self.requiredBiosNames = requiredBiosNames
        self.deviceRefNames = deviceRefNames
        self.matchedViaHeaderStrip = matchedViaHeaderStrip
        self.isDisk = isDisk
        self.foundElsewhereArchiveName = foundElsewhereArchiveName
        self.requiredByGameDescription = requiredByGameDescription
        self.misnamedArchiveForGameName = misnamedArchiveForGameName
        self.duplicateSetPrimaryPath = duplicateSetPrimaryPath
        self.name = name
        self.path = path
        self.expectedSize = expectedSize
        self.actualSize = actualSize
        self.expectedCRC = expectedCRC
        self.expectedMD5 = expectedMD5
        self.expectedSHA1 = expectedSHA1
        self.actualCRC = actualCRC
        self.actualMD5 = actualMD5
        self.actualSHA1 = actualSHA1
    }
}

/// A flat, exportable audit of a collection against a DAT, with precomputed
/// counts for the four statuses.
public struct AuditReport: Equatable, Sendable {
    public let entries: [AuditEntry]
    public let correct: Int
    public let incorrect: Int
    public let badDump: Int
    public let missing: Int
    public let surplus: Int
    public let unverifiable: Int
    /// Count of `.duplicateSet` rows only — see that case's own doc
    /// comment. Deliberately its own tally, not folded into `surplus`: a
    /// duplicate copy of a genuinely-owned set is a very different thing
    /// from genuinely unrecognized content, and conflating the two counts
    /// would misreport how many *actual* unknown files exist.
    public let duplicateSets: Int

    public init(
        entries: [AuditEntry], correct: Int, incorrect: Int, badDump: Int = 0, missing: Int, surplus: Int, unverifiable: Int = 0,
        duplicateSets: Int = 0
    ) {
        self.entries = entries
        self.correct = correct
        self.incorrect = incorrect
        self.badDump = badDump
        self.missing = missing
        self.surplus = surplus
        self.unverifiable = unverifiable
        self.duplicateSets = duplicateSets
    }

    /// The single worst status across the whole report — the same
    /// missing > incorrect > correct/surplus severity order used to color a
    /// game node in the UI's tree, rolled all the way up to one badge for
    /// the entire system. `nil` for an empty report (nothing scanned yet).
    ///
    /// Computed from rom entries only (`!isDisk`), falling back to disk
    /// entries only if the report has no roms at all — jensyleo's own call
    /// (2026-07-30, see ROADMAP.md "CHD/ROM independence"): a game's CHD
    /// status must never affect its rom status or vice versa, and that
    /// applies at every rollup level, not just the per-game one. Before
    /// this, a single missing CHD disk anywhere in a large MAME DAT (the
    /// overwhelmingly common case — nobody has every arcade CD/hard-disk
    /// image) permanently pinned this whole-system badge to "Bad" even
    /// when every rom the user actually cares about was perfectly correct.
    public var worstStatus: AuditStatus? {
        let romEntries = entries.filter { !$0.isDisk }
        return AuditStatus.worst(among: (romEntries.isEmpty ? entries : romEntries).map(\.status))
    }
}

extension AuditStatus {
    /// Severity order used to propagate a "worst status" up from a set of
    /// entries to their containing game/system — jensyleo's own confirmed
    /// priority (2026-08-04): `.missing` > `.badDump` > `.incorrect` >
    /// `.correct`/`.surplus`, matching how a DAT-based audit tool should
    /// surface the thing that actually needs attention.
    public static func worst(among statuses: some Sequence<AuditStatus>) -> AuditStatus? {
        var sawBadDump = false
        var sawIncorrect = false
        var sawOther = false
        for status in statuses {
            switch status {
            case .missing: return .missing
            case .badDump: sawBadDump = true
            case .incorrect: sawIncorrect = true
            case .correct, .surplus, .surplusInArchive, .unknownFile, .unverifiable, .duplicateSet: sawOther = true
            }
        }
        if sawBadDump { return .badDump }
        if sawIncorrect { return .incorrect }
        return sawOther ? .correct : nil
    }
}
