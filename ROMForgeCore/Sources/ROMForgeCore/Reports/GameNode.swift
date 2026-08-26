// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// One row of the games tree: a game (parent or clone — clones nest under
/// their parent) or the synthetic "Surplus files" bucket. RomCenter shows a
/// game list on the left and that game's own ROM files on the right instead
/// of mixing both levels into one tree — `entries` holds this node's own
/// ROMs for that right-hand pane.
///
/// Moved out of `LibraryDetailView.swift` (App) into Core (2026-08-13,
/// "Grupo B" of the App-logic extraction, jensyleo's own request) — this
/// type never actually had any SwiftUI dependency (every property is a
/// plain value type), it was just declared in a View file. Behavior
/// unchanged, pure relocation; see `GameNodeBuilder` for the free functions
/// that build/aggregate these.
public struct GameNode: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let entries: [AuditEntry]
    /// `nil` only for a catalog row shown before any scan has ever run —
    /// see `sourceGame` below. Every other row (real scan result, or the
    /// synthetic "Surplus files"/"Unknown game" bucket) always has a real
    /// status.
    public let aggregateStatus: AuditStatus?
    /// True only for the synthetic "Surplus files" bucket — it has entries
    /// (the surplus files themselves) but no real DAT game backs it, so it
    /// needs its own `infoText`/`expectedFileName` rather than the ones
    /// derived from a real game's rom statuses.
    public var isSurplusBucket: Bool = false
    /// True only for the separate row `GameNodeBuilder.gameNodes(from:)`
    /// builds to carry a game's CHD disk result — a game with both a rom
    /// and a CHD disk gets *two* `GameNode` rows (same `name`, different
    /// `id`) instead of one row whose `entries` mixed both together — each
    /// independently verified and displayed, so a correct CHD reads as
    /// "Correct" even when that same game's rom is entirely missing, and
    /// vice versa. `entries` on this row holds only that game's disk
    /// entry/entries (`isDisk`), never its roms.
    public var isDiskRow: Bool = false
    /// Set only for a row built directly from the loaded DAT before any
    /// scan has run (`aggregateStatus == nil`) — lets the "Database"
    /// catalog show real game metadata (description/year/manufacturer/…)
    /// with nothing yet to compare it against, instead of just blank
    /// columns. `entries` is always empty in that case, since there's no
    /// scan result yet to hold one.
    public var sourceGame: DATGame?
    /// `sourceGame`'s real BIOS machine (via `romOf` — see `DATGame
    /// .resolvedBiosMachineName`'s own doc comment), precomputed by
    /// `GameNodeBuilder.unscannedCatalogNodes` while it still has every
    /// other `DATGame` in the DAT on hand to resolve the chain against.
    /// `requiredBiosNames` below only ever needs this as its catalog-view
    /// fallback (`entries` is always empty pre-scan, so `firstNonEmpty`
    /// never has anything to find), and a lone `GameNode` has no such
    /// lookup of its own to resolve it lazily. `nil` for every scanned row
    /// (its real `AuditEntry.requiredBiosNames`, already resolved the same
    /// way by `AuditReporter`, covers it instead) and for a game with no
    /// BIOS dependency.
    public var resolvedBiosMachineName: String?

    public init(
        id: String, name: String, entries: [AuditEntry], aggregateStatus: AuditStatus?,
        isSurplusBucket: Bool = false, isDiskRow: Bool = false, sourceGame: DATGame? = nil,
        resolvedBiosMachineName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.entries = entries
        self.aggregateStatus = aggregateStatus
        self.isSurplusBucket = isSurplusBucket
        self.resolvedBiosMachineName = resolvedBiosMachineName
        self.isDiskRow = isDiskRow
        self.sourceGame = sourceGame
    }

    /// The archive actually found on disk for this game, if any — every
    /// rom of a split-mode game lives in the same one archive, so any
    /// entry with a local `path` names it. `nil` when nothing at all was
    /// found (every rom missing), matching ClrMamePro/RomCenter's own
    /// scanner view, which leaves this blank rather than guessing.
    ///
    /// Real bug found live by jensyleo (2026-08-04, Merged mode): an
    /// entry's `path` doesn't always mean "this is *my* archive" — a
    /// `.foundElsewhere` rom's `path` is where its content was *borrowed*
    /// from (see `foundElsewhereArchiveName`'s own doc comment), and a
    /// folded-in surplus entry that turned out to belong to another game
    /// (`requiredByGameDescription`) points at *that* game's archive, not
    /// this one's. Taking the first `path != nil` entry unconditionally
    /// picked up one of those borrowed paths whenever a game's every real
    /// rom was genuinely missing. Both borrowed-path cases are excluded —
    /// only a path this game genuinely, verifiably owns counts.
    ///
    /// A third borrowed-path case found live by jensyleo (2026-08-05):
    /// duplicating an archive under a new name makes `ROMMatcher
    /// .isInClaimedArchive` treat it as an "unclaimed/renamed" archive, so
    /// any of its roms that happen to hash-match a completely unrelated
    /// game get legitimately claimed by that game too. A real renamed
    /// archive belongs to one game almost entirely; a stray leak like this
    /// contributes only a token one or two. Fixed by requiring the
    /// most-represented candidate path to cover at least half of this
    /// game's own rom entries before trusting it.
    public var actualFileName: String? {
        let owned = entries.filter { $0.path != nil && $0.foundElsewhereArchiveName == nil && $0.requiredByGameDescription == nil }
        guard !owned.isEmpty else { return nil }
        var countsByPath: [URL: Int] = [:]
        for entry in owned { countsByPath[entry.path!, default: 0] += 1 }
        guard let (bestPath, bestCount) = countsByPath.max(by: { $0.value < $1.value }) else { return nil }
        guard bestCount * 2 >= entries.count else { return nil }
        return bestPath.lastPathComponent
    }

    /// The DAT's own human-readable name (its `<description>`, e.g.
    /// "Street Fighter II: The World Warrior (World 910522)") — much more
    /// descriptive than `name`, which is just the short internal machine
    /// code the archive is named after (e.g. "sf2"). Falls back to `name`
    /// if the DAT declared no description (a Logiqx DAT missing one, or
    /// the synthetic "Surplus files"/unrecognized-archive bucket, which
    /// has no real DAT game behind it at all).
    public var gameName: String {
        firstNonEmpty(\.gameDescription) ?? nonEmpty(sourceGame?.description) ?? name
    }

    /// The archive name the DAT implies for this game — the ".zip per
    /// machine" convention split-mode sets are built around. Not shown for
    /// the synthetic "Surplus files" bucket (no game backs it) or a CHD
    /// disk row (`isDiskRow`) — a disk's own file is never expected to be
    /// named after the machine plus ".zip".
    public var expectedFileName: String? {
        (isSurplusBucket || isDiskRow) ? nil : "\(name).zip"
    }

    /// A one-line ClrMamePro/RomCenter-style summary of this game's status
    /// — "Ok" only when every rom matched by both name and hash; otherwise
    /// the most specific thing wrong, checked worst-first. Distinguishes
    /// two different kinds of "misnamed", which a rename-fix would handle
    /// completely differently:
    /// - the **archive itself** has the wrong name (its contents, once
    ///   matched by hash, are a real known game) — "Bad file name", fixed
    ///   by renaming the archive to `expectedFileName`;
    /// - the archive's own name is already correct, but one or more roms
    ///   **inside** it are misnamed — "Rom need fix", fixed by renaming
    ///   entries within the archive instead.
    public var infoText: String {
        guard let aggregateStatus else { return "Not scanned yet" }
        guard !isSurplusBucket else {
            // An archive with no `dat.games` entry of its own (a clone
            // folded into its parent) but whose entire content is
            // nonetheless fully identified elsewhere reads as its own
            // distinct message, not the genuinely-unknown default. This
            // whole archive is one game's set under the wrong filename
            // (at least half its files are that game's roms, and that
            // game owns no archive of its own). Checked before the
            // duplicate message below, since a misnamed archive also has
            // a `requiredByGameDescription` and would otherwise fall into
            // it. Scans for the FIRST entry that actually carries the
            // value, rather than reading `entries.first` — a real bug
            // found live by jensyleo (2026-08-06): the first entry in an
            // archive can be a stray junk file with no
            // `misnamedArchiveForGameName` while later entries are fully
            // identified roms. Order inside an archive is arbitrary, so
            // nothing may depend on it.
            if let expected = entries.compactMap(\.misnamedArchiveForGameName).first {
                return "Bad file name — rename to \(expected).zip"
            }
            guard aggregateStatus == .incorrect,
                  let requiredBy = entries.compactMap(\.requiredByGameDescription).first
            else {
                return "Unknown game"
            }
            // Leads with "Duplicated" specifically to mean "a known
            // duplicate of something already claimed elsewhere" — not a
            // vague/unknown extra file, which reads as plain "Unknown
            // game" instead (see the guard just above).
            return "Duplicated archive, not needed here (required by \(requiredBy))"
        }
        // A disk row's own entries are already disk-only (`isDiskRow`,
        // never mixed with this game's roms) — a plain status readout is
        // enough; the rom-oriented checks below (file-naming convention,
        // "Rom need fix") don't apply to a CHD at all.
        if isDiskRow {
            switch aggregateStatus {
            case .missing: return "Missing"
            case .incorrect: return "Incorrect"
            case .badDump: return "Bad"
            case .correct, .surplus, .surplusInArchive, .unknownFile: return "Correct"
            // A CHD whose DAT entry declares no sha1 at all — undumped
            // media — with a same-named file present. Nothing to verify
            // it against, by design, so never "Correct"; the file
            // existing is the best this disk can ever report.
            case .unverifiable: return "Nodump (unverifiable)"
            // `DuplicateSetDetector` only ever produces rom-level rows
            // (`isDisk: false`), never for a disk — `gameCategory`/
            // `romOnlyGameCategory` also never return this for a disk row.
            // Unreachable in practice, only present for exhaustiveness.
            case .duplicateSet: return "Correct"
            }
        }
        switch aggregateStatus {
        case .missing: return "Incomplete (rom missing)"
        case .badDump: return "Bad (hash mismatch)"
        case .incorrect:
            // Three different reasons a game reads "Incorrect" overall,
            // checked worst/most-actionable first:
            // - the **archive itself** has the wrong name — "Bad file
            //   name", fixed by renaming the archive to `expectedFileName`;
            // - the archive's own name is already correct, but one or
            //   more of this game's OWN roms are misnamed/found-elsewhere
            //   (`requiredByGameDescription == nil` distinguishes these
            //   from the case just below) — "Rom need fix";
            // - every one of this game's own roms is genuinely fine, and
            //   the only `.incorrect` entry present is a *surplus* file
            //   folded into this row that turned out to be fully
            //   identified, just belonging to a different game
            //   (`requiredByGameDescription != nil`) — "Duplicated file,
            //   not needed here".
            let archiveMisnamed = actualFileName != nil && expectedFileName != nil && actualFileName != expectedFileName
            if archiveMisnamed { return "Bad file name" }
            // This game owns no archive at all, yet every one of its roms
            // is visible inside ONE other archive — that archive is this
            // game's whole set under the wrong filename. `actualFileName`
            // is nil here precisely because every entry is
            // `.foundElsewhere`, so the check above can't catch this case.
            if actualFileName == nil, let expected = expectedFileName {
                let borrowedArchives = Set(entries.compactMap(\.foundElsewhereArchiveName))
                if borrowedArchives.count == 1, let wrongName = borrowedArchives.first, wrongName != expected {
                    return "Bad file name — rename \(wrongName) to \(expected)"
                }
            }
            let hasOwnRomProblem = entries.contains { $0.status == .incorrect && $0.requiredByGameDescription == nil }
            return hasOwnRomProblem ? "Rom need fix" : "Duplicated file, not needed here"
        case .correct, .surplus, .surplusInArchive, .unknownFile:
            // A surplus entry can end up here (not in its own "Unknown
            // game" bucket) when it's an extra file inside an archive that
            // otherwise matches this exact game — worth calling out
            // explicitly rather than silently reporting "Ok".
            if entries.contains(where: { $0.status == .unknownFile }) { return "Unknown file in archive" }
            if entries.contains(where: { $0.status == .surplus || $0.status == .surplusInArchive }) { return "Extra file in archive" }
            return "Ok"
        case .unverifiable:
            return "Ok (contains a nodump rom)"
        // Same reasoning as the disk-row switch above — `GameStatusRollup
        // .gameCategory` never returns `.duplicateSet` as a game's own
        // aggregate; only present for exhaustiveness.
        case .duplicateSet:
            return "Ok"
        }
    }

    /// This game's parent, if it's a clone (from the DAT's `cloneof`) —
    /// empty for a parent/original game and for the surplus bucket.
    public var cloneOf: String {
        firstNonEmpty(\.cloneOf) ?? sourceGame?.cloneOf ?? ""
    }
    public var chdNames: String {
        firstNonEmpty(\.chdNames) ?? sourceGame.map { $0.disks.map(\.name).joined(separator: ", ") } ?? ""
    }
    public var year: String { firstNonEmpty(\.gameYear) ?? sourceGame?.year ?? "" }
    public var manufacturer: String { firstNonEmpty(\.gameManufacturer) ?? sourceGame?.manufacturer ?? "" }
    public var requiredBiosNames: String {
        firstNonEmpty(\.requiredBiosNames) ?? resolvedBiosMachineName ?? ""
    }
    public var deviceRefNames: String {
        firstNonEmpty(\.deviceRefNames) ?? sourceGame.map { $0.deviceRefs.joined(separator: ", ") } ?? ""
    }
    public var samplesText: String {
        if entries.contains(where: \.hasSamples) { return "Yes" }
        return sourceGame?.hasSamples == true ? "Yes" : ""
    }
    public var biosText: String {
        if entries.contains(where: \.isBios) { return "Yes" }
        return sourceGame?.isBios == true ? "Yes" : ""
    }

    /// Every rom in a game shares the same game-level metadata (year,
    /// manufacturer, clone parent, etc.), so the first entry that actually
    /// has a value speaks for the whole game/archive.
    private func firstNonEmpty(_ keyPath: KeyPath<AuditEntry, String?>) -> String? {
        entries.lazy.compactMap { $0[keyPath: keyPath] }.first(where: { !$0.isEmpty })
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}
