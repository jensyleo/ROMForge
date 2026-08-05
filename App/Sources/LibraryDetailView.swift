import AppKit
import ROMForgeCore
import SwiftUI

/// One row of the games tree: a game (parent or clone — clones nest under
/// their parent) or the synthetic "Surplus files" bucket. RomCenter shows a
/// game list on the left and that game's own ROM files on the right instead
/// of mixing both levels into one tree — `entries` holds this node's own
/// ROMs for that right-hand pane.
/// `AuditEntry` isn't `Identifiable` (Core has no UI concerns), so the flat
/// ROM table on the right wraps each one with the same id scheme used
/// elsewhere to look an entry back up from a selection.
private struct RomRow: Identifiable {
    let id: String
    let entry: AuditEntry
}

private struct GameNode: Identifiable {
    let id: String
    let name: String
    let entries: [AuditEntry]
    /// `nil` only for a catalog row shown before any scan has ever run —
    /// see `sourceGame` below. Every other row (real scan result, or the
    /// synthetic "Surplus files"/"Unknown game" bucket) always has a real
    /// status.
    let aggregateStatus: AuditStatus?
    /// True only for the synthetic "Surplus files" bucket — it has entries
    /// (the surplus files themselves) but no real DAT game backs it, so it
    /// needs its own `infoText`/`expectedFileName` rather than the ones
    /// derived from a real game's rom statuses.
    var isSurplusBucket: Bool = false
    /// True only for the separate row `gameNodes(from:)` builds to carry a
    /// game's CHD disk result — jensyleo's own request (2026-07-30): "si el
    /// .zip está OK mostrarlo como Correct, pero separado del .chd" / "si
    /// el .chd está OK mostrarlo como Correct, pero separado del .zip". A
    /// game with both a rom and a CHD disk now gets *two* `GameNode` rows
    /// (same `name`, different `id`) instead of one row whose `entries`
    /// mixed both together — each independently verified and displayed,
    /// so a correct CHD reads as "Correct" even when that same game's rom
    /// is entirely missing, and vice versa. `entries` on this row holds
    /// only that game's disk entry/entries (`isDisk`), never its roms.
    var isDiskRow: Bool = false
    /// Set only for a row built directly from the loaded DAT before any
    /// scan has run (`aggregateStatus == nil`) — lets the "Database"
    /// catalog show real game metadata (description/year/manufacturer/…)
    /// with nothing yet to compare it against, instead of just blank
    /// columns. `entries` is always empty in that case, since there's no
    /// scan result yet to hold one.
    var sourceGame: DATGame?

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
    /// rom was genuinely missing — several completely unrelated bootleg/
    /// gambling machines (e.g. "Express Card / Top Card", sharing nothing
    /// with Street Fighter beyond an identical blank/padding rom) all
    /// showed a misleading "File Name" of `sf2acc.zip`/`sf2accp2.zip`,
    /// implying they physically live in an archive they've never touched.
    /// Both borrowed-path cases are excluded — only a path this game
    /// genuinely, verifiably owns counts.
    ///
    /// A third borrowed-path case found live by jensyleo (2026-08-05):
    /// duplicating an archive under a new name (e.g. `blazstar copy.zip`)
    /// makes `ROMMatcher.isInClaimedArchive` treat it as an "unclaimed/
    /// renamed" archive (its base name matches no DAT game), so any of its
    /// roms that happen to hash-match a *different*, completely unrelated
    /// game gets legitimately claimed by that game via the same
    /// rename-tolerant fallback that lets `archiveMisnamed` (below) detect
    /// a genuinely renamed archive — no `foundElsewhereArchiveName`, no
    /// `requiredByGameDescription`, so the two checks above don't catch it.
    /// Dozens of unrelated missing games (Abacus, AN1x, Win Streak, …) all
    /// showed "blazstar copy.zip" as their File Name, each having grabbed
    /// just one stray shared/filler rom out of it.
    ///
    /// A real renamed archive belongs to one game almost entirely (most or
    /// all of its expected roms show up under that one path); a stray leak
    /// like this contributes only a token one or two. Fixed by requiring
    /// the most-represented candidate path to cover at least half of this
    /// game's own rom entries before trusting it — high enough to keep
    /// `archiveMisnamed` working for a truly renamed archive, low enough to
    /// tolerate a real archive missing a few of its own roms.
    var actualFileName: String? {
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
    var gameName: String {
        firstNonEmpty(\.gameDescription) ?? nonEmpty(sourceGame?.description) ?? name
    }

    /// The archive name the DAT implies for this game — the ".zip per
    /// machine" convention split-mode sets are built around. Not shown for
    /// the synthetic "Surplus files" bucket (no game backs it) or a CHD
    /// disk row (`isDiskRow`) — a disk's own file is never expected to be
    /// named after the machine plus ".zip", so that comparison doesn't
    /// apply to it at all (it would otherwise misreport every correctly-
    /// named `.chd` as "Bad file name").
    var expectedFileName: String? {
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
    var infoText: String {
        guard let aggregateStatus else { return "Not scanned yet" }
        guard !isSurplusBucket else {
            // jensyleo's own question (2026-08-04, Merged mode): see
            // `gameNodes(from:)`'s own `isFullyIdentified` doc comment —
            // an archive with no `dat.games` entry of its own (a clone
            // folded into its parent) but whose entire content is
            // nonetheless fully identified elsewhere reads as its own
            // distinct message, not the genuinely-unknown default.
            guard aggregateStatus == .incorrect, let requiredBy = entries.first?.requiredByGameDescription else {
                return "Unknown game"
            }
            // jensyleo's own request (2026-08-05): make explicit that
            // "Extra" here specifically means "a known duplicate of
            // something already claimed elsewhere" — not a vague/unknown
            // extra file, which reads as plain "Unknown game" instead (see
            // the guard just above).
            return "Extra archive (duplicated), not needed here (required by \(requiredBy))"
        }
        // Real bug found live by jensyleo (2026-08-04): this used to
        // re-derive its own answer from raw `entries` independently of
        // `aggregateStatus` — e.g. unconditionally checking
        // `entries.contains { $0.status == .missing }` for "Incomplete".
        // `aggregateStatus` is the authoritative, scope-aware status (in a
        // "Rom files" folder it's computed from that folder's own entries —
        // see `gameNodes(from:)`'s own `trueStatus`), so re-deriving
        // separately here could disagree with the very icon/color sitting
        // right next to this text — a game showing a green "Ok" checkmark
        // while the text beside it read "Incomplete…". Switching on
        // `aggregateStatus` directly keeps the icon and this text in
        // permanent agreement.
        //
        // A disk row's own entries are already disk-only (`isDiskRow`,
        // never mixed with this game's roms) — a plain status readout is
        // enough; the rom-oriented checks below (file-naming convention,
        // "Rom need fix") don't apply to a CHD at all.
        if isDiskRow {
            switch aggregateStatus {
            case .missing: return "Missing"
            case .incorrect: return "Incorrect"
            case .badDump: return "Bad"
            case .correct, .surplus: return "Correct"
            // A CHD whose DAT entry declares no sha1 at all — undumped
            // media (`CHDDiskStatus.unverifiable`'s own doc comment) — with
            // a same-named file present. Nothing to verify it against, by
            // design, so never "Correct"; the file existing is the best
            // this disk can ever report.
            case .unverifiable: return "Nodump (unverifiable)"
            }
        }
        switch aggregateStatus {
        case .missing: return "Incomplete (rom missing)"
        case .badDump: return "Bad (hash mismatch)"
        case .incorrect:
            // Three different reasons a game reads "Incorrect" overall,
            // checked worst/most-actionable first:
            // - the **archive itself** has the wrong name (its contents,
            //   once matched by hash, are a real known game) — "Bad file
            //   name", fixed by renaming the archive to `expectedFileName`;
            // - the archive's own name is already correct, but one or more
            //   of this game's OWN roms are misnamed/found-elsewhere
            //   (`requiredByGameDescription == nil` distinguishes these
            //   from the case just below) — "Rom need fix", fixed by
            //   renaming/moving entries within the archive instead;
            // - every one of this game's own roms is genuinely fine, and
            //   the only `.incorrect` entry present is a *surplus* file
            //   folded into this row that turned out to be fully
            //   identified, just belonging to a different game
            //   (`requiredByGameDescription != nil` — jensyleo's own
            //   correction, 2026-08-04: this used to stay `.surplus`/
            //   "Extra file in archive" below; reclassified because
            //   "surplus" must mean genuinely unknown, and this file
            //   isn't) — "Extra file, not needed here", fixed by moving it
            //   to the archive that actually wants it.
            let archiveMisnamed = actualFileName != nil && expectedFileName != nil && actualFileName != expectedFileName
            if archiveMisnamed { return "Bad file name" }
            let hasOwnRomProblem = entries.contains { $0.status == .incorrect && $0.requiredByGameDescription == nil }
            return hasOwnRomProblem ? "Rom need fix" : "Extra file (duplicated), not needed here"
        case .correct, .surplus:
            // A surplus entry can end up here (not in its own "Unknown
            // game" bucket) when it's an extra file inside an archive that
            // otherwise matches this exact game — worth calling out
            // explicitly rather than silently reporting "Ok" and hiding
            // that the archive has more in it than the DAT expects.
            if entries.contains(where: { $0.status == .surplus }) { return "Extra file in archive" }
            return "Ok"
        case .unverifiable:
            return "Ok (contains a nodump rom)"
        }
    }

    /// This game's parent, if it's a clone (from the DAT's `cloneof`) —
    /// empty for a parent/original game and for the surplus bucket. Shown
    /// as its own column now that the tree no longer nests clones under
    /// their parent visually.
    var cloneOf: String {
        firstNonEmpty(\.cloneOf) ?? sourceGame?.cloneOf ?? ""
    }
    var chdNames: String {
        firstNonEmpty(\.chdNames) ?? sourceGame.map { $0.disks.map(\.name).joined(separator: ", ") } ?? ""
    }
    var year: String { firstNonEmpty(\.gameYear) ?? sourceGame?.year ?? "" }
    var manufacturer: String { firstNonEmpty(\.gameManufacturer) ?? sourceGame?.manufacturer ?? "" }
    var requiredBiosNames: String {
        firstNonEmpty(\.requiredBiosNames) ?? sourceGame.map { $0.biosSetNames.joined(separator: ", ") } ?? ""
    }
    var deviceRefNames: String {
        firstNonEmpty(\.deviceRefNames) ?? sourceGame.map { $0.deviceRefs.joined(separator: ", ") } ?? ""
    }
    var samplesText: String {
        if entries.contains(where: \.hasSamples) { return "Yes" }
        return sourceGame?.hasSamples == true ? "Yes" : ""
    }
    var biosText: String {
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

/// RomCenter's "Database" tree: predefined categories over the same audit,
/// shown above the games list. "Games with CHD" and "Games with samples"
/// are presence-only (does the DAT declare a disk/sample for this game),
/// not verification — ROMForge doesn't check a `.chd` file's contents or a
/// sample's presence on disk yet, that's still its own future milestone
/// (see ROADMAP.md). "Games with bad dumps" reflects the DAT's own
/// `status="baddump"/"nodump"` claim about the reference dump, independent
/// of what's found locally.
private enum DatabaseFilter: String, CaseIterable, Identifiable {
    case allGames = "All games"
    /// Unlike the other categories (which reflect what the DAT itself
    /// declares about a game), this one reflects the *scan result* — only
    /// games where every one of their roms actually matched by both name
    /// and hash, the same "fully verified" a real audit tool means by it.
    case verifiedGames = "Verified games"
    case originals = "Originals"
    case clones = "Clones"
    case biosFiles = "Bios files"
    case gamesWithCHD = "Games with CHD"
    case gamesWithSamples = "Games with samples"
    case gamesWithBadDumps = "Games with bad dumps"
    var id: String { rawValue }

    /// Placeholder SF Symbols, one per category, standing in for real
    /// custom icon designs — see ROADMAP.md's "Custom icon set" pending
    /// item. Picked for a distinct silhouette per category rather than
    /// literal accuracy (there's no "verified" symbol shaped like the
    /// others, for instance), so at a glance each row still reads as a
    /// different thing instead of a single "tablecells" icon repeated 8
    /// times with no visual distinction at all.
    var symbolName: String {
        switch self {
        case .allGames: return "square.grid.2x2"
        case .verifiedGames: return "checkmark.seal.fill"
        case .originals: return "doc.text"
        case .clones: return "square.on.square"
        case .biosFiles: return "memorychip"
        case .gamesWithCHD: return "opticaldiscdrive"
        case .gamesWithSamples: return "waveform"
        case .gamesWithBadDumps: return "exclamationmark.triangle.fill"
        }
    }
}

/// One row of a "Database" category's expandable children — RomCenter-style
/// real tree nesting, jensyleo's own design call (2026-07-28): a category
/// stays a flat filter for the Games table on the right (clicking it still
/// works exactly as before), but now *also* expands in place to show its
/// actual games as real tree children — and, specifically for "All games",
/// a clone nests under its own parent's row rather than sitting alongside
/// it as an unrelated sibling. Deliberately its own lightweight type rather
/// than reusing `GameNode` directly: one game can be a plain leaf under one
/// category (e.g. "Clones") and a parent-with-children under another (e.g.
/// "All games"), which isn't something `GameNode` needs to represent at all
/// for the flat Games table.
private struct DatabaseTreeNode: Identifiable {
    let id: String
    /// The DAT's own internal machine/game name (e.g. "sf2ee") — what the
    /// Games table's own `GameNode.id` is keyed on (`"game-\(name)"`), so
    /// tapping this leaf can select the exact same row there. Empty for a
    /// `isTruncationNotice` row, which has no real game behind it.
    let machineName: String
    let label: String
    let status: AuditStatus?
    var children: [DatabaseTreeNode]?
    /// True only for the synthetic "…and N more" row a category's own
    /// children get capped with (see `treeChildren(forCategory:)`) — a
    /// plain, non-selectable line, not a real game.
    var isTruncationNotice: Bool = false
}

/// Per-archive cache for `ZipCommentReader`'s result — a plain reference
/// type, not a SwiftUI `@State`/`@Observable`, so filling it while
/// `infoText(for:)` runs during view-body evaluation never mutates SwiftUI
/// state mid-render. Every rom row belonging to the same zip shares one
/// entry, so a table with hundreds of rows from a handful of archives only
/// ever reads each archive's End of Central Directory record once.
private final class ZipCommentCache {
    private var storage: [URL: String?] = [:]

    func comment(forZipAt url: URL) -> String? {
        if let cached = storage[url] { return cached }
        let comment = ZipCommentReader.comment(ofZipAt: url)
        storage[url] = comment
        return comment
    }
}

struct LibraryDetailView: View {
    let system: RomSystem
    /// Called with the full, updated folder list whenever the user adds a
    /// ROM folder from the "Rom files" section — the caller (`ContentView`,
    /// which owns the `SystemLibraryStore`) is responsible for persisting
    /// it. `LibraryDetailView` itself has no direct access to the store.
    let onAddFolder: ([URL]) -> Void
    /// Called with whether the just-loaded DAT declares any clone
    /// (`cloneOf != nil`) game at all — the caller (`ContentView`)
    /// persists it onto this system's own `RomSystem.hasClones`, so
    /// Settings can warn about "Merged" merge mode not making sense for a
    /// clone-less system (e.g. NEOGEO) without needing its own DAT access.
    var onDATAnalyzed: ((Bool) -> Void)?

    @State private var viewModel = LibraryViewModel()
    @State private var selectedGameID: String?
    @State private var selectedRomID: String?
    /// Finder/`NSTableView`-style type-ahead: typing a few characters while
    /// the Games table has focus jumps to the first row whose file name
    /// starts with what's been typed so far — jensyleo's own request
    /// (2026-08-04), so finding one game among tens of thousands doesn't
    /// need scrolling by hand. `SwiftUI`'s `Table` (unlike `NSTableView`)
    /// has no built-in type-select, so this reimplements the classic
    /// pattern by hand: characters accumulate into `typeAheadBuffer`, and
    /// a pause longer than `typeAheadTimeout` since the last keystroke
    /// resets it, rather than a cancellable `Task`/timer — simpler, and
    /// avoids any actor-hopping for what's just a plain buffer reset.
    @State private var typeAheadBuffer: String = ""
    @State private var lastTypeAheadKeystroke: Date = .distantPast
    private static let typeAheadTimeout: TimeInterval = 1.0
    /// Jensyleo's own report (2026-08-04): setting `selectedGameID` alone
    /// does *not* reliably auto-scroll a `Table`'s selection into view on
    /// macOS (unlike `List`, which does) — the row really does get
    /// selected, just off-screen. Captured from a `ScrollViewReader`
    /// wrapping `gameTreeTable`'s `Table` so type-ahead (and anything else
    /// that jumps the selection) can explicitly scroll to it.
    @State private var gameTableScrollProxy: ScrollViewProxy?
    /// A zip's own archive-level comment never changes without the file
    /// itself changing (a rescan already reloads everything fresh), so it's
    /// worth caching per archive path rather than re-parsing the same
    /// zip's End of Central Directory record on every render of every one
    /// of its rom rows. A plain reference-type cache (not `@State`) so
    /// filling it while `infoText(for:)` runs during view-body evaluation
    /// never mutates SwiftUI state mid-render.
    private let zipCommentCache = ZipCommentCache()
    /// The status filter (Correct/Incorrect/Missing/Surplus) is a genuine
    /// multi-select — each status button is an independent on/off toggle,
    /// not a single exclusive choice — so "Correct + Incorrect together,
    /// Missing turned off" is expressible, which a single-value filter
    /// could never represent (it could only ever show one status, or all
    /// four). Tracked as two independent sets rather than one shared value,
    /// since "Database" and "Rom files" want different starting points:
    /// Both contexts default to every status shown — jensyleo's own call
    /// (2026-07-30): "Database" used to default to just Correct, on the
    /// idea that most users open the app to check "is my set good?" —  but
    /// that default is exactly what caused a real, confusing bug (a
    /// genuinely incomplete game read as fully correct simply because
    /// Missing wasn't currently toggled on) to go unnoticed. Defaulting
    /// both contexts to everything visible means nothing is hidden by
    /// surprise; toggling one off to focus on the others is still a single
    /// click away, same as before.
    /// `activeStatusFilters` below resolves to whichever set currently
    /// applies, so the rest of the filtering/UI code doesn't need to care
    /// which context it's in.
    @State private var databaseStatusFilters: Set<AuditStatus> = Set(AuditStatus.allCases)
    @State private var romFolderStatusFilters: Set<AuditStatus> = Set(AuditStatus.allCases)
    @State private var selectedDatabaseFilter: DatabaseFilter? = .allGames
    /// Selecting a "Rom files" folder leaf scopes the *same* audit-driven
    /// Games tree (same columns, same status colors, same selection/detail
    /// flow as every "Database" category) down to just what that folder
    /// contributed, instead of showing a separate raw-disk view — a
    /// missing rom isn't "in" any folder, so it stays visible regardless
    /// (there's nowhere else useful to put it). Mutually exclusive with
    /// `selectedDatabaseFilter`: picking one clears the other.
    @State private var selectedRomFolder: URL?
    /// Resolves to whichever of `databaseStatusFilters`/`romFolderStatusFilters`
    /// currently applies, based on which of "Database"/"Rom files" is active
    /// — so the status buttons, the "Show all" action, and the entry
    /// filtering below all read/write through one name without needing to
    /// know which context they're in.
    private var activeStatusFilters: Set<AuditStatus> {
        get { selectedRomFolder != nil ? romFolderStatusFilters : databaseStatusFilters }
        nonmutating set {
            if selectedRomFolder != nil { romFolderStatusFilters = newValue } else { databaseStatusFilters = newValue }
        }
    }
    /// Whether the "Database"/"Rom files" tree sections are expanded or
    /// collapsed — `@AppStorage` rather than plain `@State` so this
    /// survives relaunching the app, not just the current session.
    @AppStorage("ROMForge.isDatabaseSectionExpanded") private var isDatabaseSectionExpanded = true
    @AppStorage("ROMForge.isRomFilesSectionExpanded") private var isRomFilesSectionExpanded = true
    /// Which "Database" categories are currently expanded in the tree —
    /// not persisted (unlike the two section-level toggles above), since
    /// this is finer-grained per-category state that isn't worth
    /// surviving a relaunch the way the two coarse section headers are.
    @State private var expandedDatabaseCategories: Set<DatabaseFilter> = []
    /// Computed lazily, only the first time a given category is actually
    /// expanded — not eagerly for all 8 categories on every audit-report
    /// change, which would reintroduce the exact "Database"/"Rom files"
    /// full-report-scan lag already flagged as a real, open TODO item.
    /// Cleared (not eagerly recomputed) whenever the underlying data it
    /// was built from changes, so the next expand recomputes fresh.
    @State private var databaseCategoryChildrenCache: [DatabaseFilter: [DatabaseTreeNode]] = [:]
    /// A game's *true*, always-current aggregate status, by its DAT name —
    /// real bug found live (2026-07-28): jensyleo rescanned and the Games
    /// table correctly turned a game red, but the "Database" tree still
    /// showed it green. Root cause: the tree's own cached children
    /// (`databaseCategoryChildrenCache`) freeze each leaf's status at
    /// whatever it was the moment that category was last (re)computed —
    /// correct in the common case, but any gap in exactly when that cache
    /// gets refreshed (an easy thing to get subtly wrong, and clearly
    /// wrong at least once already) leaves a stale color on screen with no
    /// way to tell. This dictionary is the fix: computed directly from
    /// `viewModel.auditReport` — the single, always-fresh source of truth
    /// `cachedGameNodes` itself already trusts — independent of which
    /// category/folder happens to be selected or which categories happen
    /// to be expanded. A tree leaf's displayed status always reads from
    /// here instead of its own frozen `DatabaseTreeNode.status`, so it can
    /// never show a color the Games table itself would disagree with,
    /// regardless of any caching bug in how the tree's own *structure*
    /// (which games appear as children) gets refreshed.
    @State private var gameAggregateStatusByName: [String: AuditStatus] = [:]
    /// `gameNodes` used to be a computed `var`, rebuilt (dictionaries,
    /// filtering, recursive node construction) on every SwiftUI `body`
    /// evaluation — cheap for a hand-built test DAT, but a real MAME DAT
    /// can have tens of thousands of games/entries, and `body` re-evaluates
    /// far more often than the data actually changes (any hover, focus, or
    /// unrelated state change). That pegged the main thread rebuilding the
    /// same huge tree over and over, hanging the app. Cached here instead,
    /// recomputed only when one of its real inputs (the report, the status
    /// filter, or the database filter) actually changes.
    @State private var cachedGameNodes: [GameNode] = []
    /// Debounces the heavy recompute triggered by selecting a "Rom files"
    /// folder — jensyleo's own report (2026-07-30): clicking a folder
    /// sometimes felt "lost"/slow, or needed several attempts, and could
    /// even read as a full freeze on a large collection. Root cause: each
    /// click's `.onChange(of: selectedRomFolder)` ran a full O(entries)
    /// regroup/recount *synchronously* on the main actor (up to ~188k
    /// entries per this file's own comments elsewhere) — several quick
    /// clicks queued that same expensive work multiple times back to
    /// back, each one blocking the next click's hit-testing until it
    /// finished. Cancelling any still-pending recompute before starting a
    /// new one means only the *last* folder actually selected pays that
    /// cost, instead of every intermediate one along the way.
    @State private var pendingFolderRecompute: Task<Void, Never>?
    /// Monotonic counter, bumped once per `selectedRomFolder` change —
    /// jensyleo's own report (2026-08-03): once the recompute in
    /// `pendingFolderRecompute` genuinely runs on a background thread
    /// (`Task.detached`, see that `.onChange`'s own doc comment), two
    /// clicks in quick succession can race for real, and `Task.isCancelled`
    /// alone doesn't stop a slower, older background computation from
    /// finishing *after* a newer one and overwriting its correct result —
    /// cancellation only marks a flag, it doesn't halt in-flight work.
    /// Checked immediately before that task's final `@State` writes: only
    /// a write whose `generation` still matches this counter's *current*
    /// value is actually the most recent request and allowed through.
    @State private var folderRecomputeGeneration = 0
    /// Same caching rationale as `cachedGameNodes`, for the status button
    /// counts: computing all four together once (one scope pass, one
    /// game-grouping pass) instead of `scopedStatusCount(_:)` redoing both
    /// from scratch per status, per render — a real cost on a ~188k-entry
    /// collection when it happened 4x every time `statusSummary` drew.
    /// Doesn't need to recompute on `activeStatusFilters` changes (unlike
    /// `cachedGameNodes`): these counts reflect the current *scope*
    /// regardless of which status toggles happen to be on.
    @State private var cachedScopedStatusCounts: [AuditStatus: Int] = [:]
    /// A fifth, independent toggle — same philosophy as the four status
    /// filters (jensyleo's own call, 2026-07-30): genuinely unrecognized
    /// archives ("Unknown game" — no real DAT game behind them at all,
    /// gray icon) used to always show no matter what; this lets them be
    /// hidden the same way any of the four can be. On by default —
    /// nothing changes until it's turned off.
    @State private var showUnknownArchives = true
    @State private var cachedUnknownArchivesCount = 0
    /// jensyleo's own request (2026-07-30): a quick way back to the old,
    /// single-combined-row-per-game view (rom+CHD folded together, as it
    /// was before the two were split into independent rows) for
    /// comparison — off by default, since the split view is the intended
    /// behavior going forward.
    @State private var combineRomAndCHD = false
    /// Which games have at least one real file inside the currently
    /// selected "Rom files" folder — `scoped(_:)`'s own memo of the same
    /// computation, recomputed once per `recomputeCachedGameData()` call
    /// rather than once *per `scoped(_:)` call* (there are two of those —
    /// `databaseFilteredEntries` and `scopedEntries` — every time the user
    /// clicks a different folder or category). On a real multi-folder MAME
    /// system this loop runs over the DAT's full, unscoped entry list
    /// (hundreds of thousands of `AuditEntry`s, each carrying several
    /// `String`s to `.hasPrefix`-compare) — halving how often it runs
    /// halves a real, user-reported "up to 4 seconds to update" lag on
    /// every click between views.
    @State private var cachedGamesInFolder: Set<String> = []
    /// User's show/hide, reorder, and resize choices for each table's
    /// columns — restored once at launch (`Self.loadCustomization`) and
    /// persisted on every change, so it survives relaunching the app, not
    /// just the current session.
    @State private var gameColumnCustomization = Self.loadCustomization(key: gameColumnCustomizationKey, default: TableColumnCustomization<GameNode>())
    @State private var romColumnCustomization = Self.loadCustomization(key: romColumnCustomizationKey, default: TableColumnCustomization<RomRow>())
    private static let gameColumnCustomizationKey = "ROMForge.gameTableColumnCustomization"
    private static let romColumnCustomizationKey = "ROMForge.romTableColumnCustomization"

    private static func loadCustomization<RowValue: Identifiable>(key: String, default defaultValue: TableColumnCustomization<RowValue>) -> TableColumnCustomization<RowValue> {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(TableColumnCustomization<RowValue>.self, from: data)
        else { return defaultValue }
        return decoded
    }

    private static func persist<RowValue: Identifiable>(_ customization: TableColumnCustomization<RowValue>, key: String) {
        guard let data = try? JSONEncoder().encode(customization) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !LibraryViewModel.modificationsEnabled {
                Label("View-only mode — ROMForge won't rename, move or modify any ROM file.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            if viewModel.isLoadingDAT {
                // Real, reported confusion: switching between two DATs for
                // the same system (e.g. comparing an older MAME version's
                // results) could take a real while, and until now the
                // *entire previous* Games/Database view stayed fully
                // visible and interactive underneath the small loading
                // card the whole time — reading as if it were still
                // current/live data, not a stale snapshot about to be
                // replaced. Blanked outright instead: nothing here is
                // trustworthy again until the new DAT actually finishes
                // loading.
                loadingDATPlaceholder
            } else {
                statusSummary
                Divider()
                // `AutosavingSplitView` (a thin `NSSplitView` wrapper — see its
                // own doc comment for the real story) instead of SwiftUI's
                // `VSplitView`/`HSplitView`: both give a draggable divider for
                // free, but neither remembers where the user leaves it across
                // launches.
                AutosavingSplitView(axis: .stacked, autosaveName: "ROMForge.mainRowsSplit", panes: [
                    SplitPane(minLength: 160) {
                        AutosavingSplitView(axis: .sideBySide, autosaveName: "ROMForge.databaseGamesRomsSplit", panes: [
                            SplitPane(minLength: 150) { databaseList },
                            SplitPane(minLength: 220) { gamesList },
                            SplitPane(minLength: 260) { romsList },
                        ])
                    },
                    SplitPane(minLength: 90) {
                        AutosavingSplitView(axis: .sideBySide, autosaveName: "ROMForge.detailLogSplit", panes: [
                            SplitPane(minLength: 260) { detailPane },
                            SplitPane(minLength: 220) { logPane },
                        ])
                    },
                ])
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(minWidth: 760, minHeight: 480)
        .toolbar {
            ToolbarItemGroup {
                // Scanning only makes sense with a "Rom files" folder in
                // hand — a "Database" category is just a lens on the last
                // report, not a place to scan from — so the button is
                // disabled outright until one is selected, rather than
                // offering a whole-system scan that doesn't fit this view.
                Button("Scan Folder") {
                    viewModel.startScan(system: system, folders: selectedRomFolder.map { [$0] })
                }
                .disabled(viewModel.isBusy || selectedRomFolder == nil)
                .help(
                    selectedRomFolder.map { "Scan only \"\($0.lastPathComponent)\" — other folders keep their last known results" }
                        ?? "Select a folder under \"Rom files\" to scan it"
                )
                // Scans just the one selected game's own archive — the
                // same right-click "Rescan This File" action, offered here
                // too since not every user thinks to right-click first.
                Button("Scan File") { scanSelectedFile() }
                    .disabled(!canScanSelectedFile)
                    .help(scanFileButtonHelpText)
                Button("Fix") { Task { await viewModel.fix(system: system) } }
                    .disabled(!LibraryViewModel.modificationsEnabled || viewModel.auditReport == nil || viewModel.isBusy)
                    .help(
                        LibraryViewModel.modificationsEnabled
                            ? "Rename misnamed ROMs to match the DAT"
                            : "Disabled for now — ROMForge only scans and reports, it won't touch your files"
                    )
                Button("Export Report") { viewModel.exportReport() }
                    .disabled(viewModel.auditReport == nil)
                Button("Export Fixdat") { viewModel.exportFixdat(system: system) }
                    .disabled(viewModel.auditReport == nil)
                    .help("Export a DAT containing only the missing/incorrect entries from this scan")
                // MAME-only for now, and only once a real `mame`
                // executable is configured (Settings → Systems) — see
                // `MAMELauncher`.
                Button {
                    launchSelectedGameInMAME()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(!canLaunchSelectedGameInMAME)
                .help(playButtonHelpText)
            }
        }
        .overlay {
            // While a DAT is loading, `loadingDATPlaceholder` already
            // replaces the whole content area (with its own progress UI
            // and Cancel button) — showing this floating card on top too
            // would just duplicate it.
            if viewModel.isBusy, !viewModel.isLoadingDAT {
                scanProgressOverlay
            }
        }
        .alert(
            "Cancelled",
            isPresented: Binding(
                get: { viewModel.cancelledPhase != nil },
                set: { if !$0 { viewModel.cancelledPhase = nil } }
            )
        ) {
            Button("OK") { viewModel.cancelledPhase = nil }
        } message: {
            Text(cancelledPhaseMessage)
        }
        .onChange(of: activeStatusFilters) {
            selectedGameID = nil; selectedRomID = nil
            recomputeGameNodes()
            refreshExpandedDatabaseCategoryCaches()
        }
        .onChange(of: showUnknownArchives) {
            selectedGameID = nil; selectedRomID = nil
            recomputeGameNodes()
            refreshExpandedDatabaseCategoryCaches()
        }
        .onChange(of: combineRomAndCHD) {
            selectedGameID = nil; selectedRomID = nil
            recomputeGameNodes()
            refreshExpandedDatabaseCategoryCaches()
        }
        .onChange(of: selectedDatabaseFilter) {
            if selectedDatabaseFilter != nil { selectedRomFolder = nil }
            selectedGameID = nil; selectedRomID = nil
            recomputeCachedGameDataSync()
        }
        .onChange(of: selectedGameID) { selectedRomID = nil }
        .onChange(of: selectedRomFolder) {
            selectedGameID = nil; selectedRomID = nil
            // A folder click on a large collection (a full MAME set can
            // have 40,000+ games) does real, O(entries) work — jensyleo's
            // own report (2026-08-03): the app visibly froze for a moment
            // on every single click, even with the debounce below (which
            // only ever stopped a *pileup* of stale recomputes from
            // starting — Swift's cooperative cancellation can't preempt
            // one that's already synchronously running on the main
            // thread, so the *current* click's own work still blocked the
            // UI for its whole duration). Every function this now calls
            // (`Self.recomputeGamesInFolder`, `Self.computeBaseGameNodes`,
            // `Self.computeGameNodes`, `Self.computeScopedStatusCounts`,
            // `Self.computeUnknownArchivesCount`) is `static` and touches
            // no `@State` directly — only plain value-type parameters —
            // specifically so this heavy part can run on a background
            // thread via `Task.detached`, with only the final assignment
            // back on `@MainActor`.
            pendingFolderRecompute?.cancel()
            folderRecomputeGeneration += 1
            let generation = folderRecomputeGeneration
            let hasAuditReport = viewModel.auditReport != nil
            let entries = viewModel.auditReport?.entries ?? []
            let folder = selectedRomFolder
            let preloadedGames = viewModel.preloadedGames
            let databaseFilter = selectedDatabaseFilter
            let aggStatus = gameAggregateStatusByName
            let combine = combineRomAndCHD
            let showUnknown = showUnknownArchives
            let statusFilters = activeStatusFilters
            pendingFolderRecompute = Task.detached(priority: .userInitiated) {
                let gamesInFolder = Self.recomputeGamesInFolder(entries: entries, selectedFolder: folder)
                let scoped = Self.scoped(entries, databaseFilter: databaseFilter, romFolder: folder, gamesInFolder: gamesInFolder)
                let baseNodes = Self.computeBaseGameNodes(
                    hasAuditReport: hasAuditReport, auditEntries: entries,
                    selectedRomFolder: folder, preloadedGames: preloadedGames, selectedDatabaseFilter: databaseFilter,
                    gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine
                )
                let nodes = Self.computeGameNodes(baseNodes: baseNodes, gameAggregateStatusByName: aggStatus, showUnknownArchives: showUnknown, activeStatusFilters: statusFilters)
                let counts = Self.computeScopedStatusCounts(scopedEntries: scoped, gamesByName: Self.gamesByName(preloadedGames))
                let unknownCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
                await MainActor.run {
                    // Guards against out-of-order completion, not just
                    // cancellation: once genuinely concurrent, a slower
                    // background task for a folder the user already
                    // clicked past could otherwise finish *after* the
                    // newer one and stomp its correct, already-displayed
                    // result — `Task.isCancelled` alone doesn't prevent
                    // this (cancellation only marks a flag; it doesn't
                    // stop already-in-flight work from completing). This
                    // monotonic counter directly answers "is this still
                    // the most recent click" at the one moment that
                    // actually matters: right before the write.
                    guard generation == folderRecomputeGeneration else { return }
                    cachedGamesInFolder = gamesInFolder
                    cachedGameNodes = nodes
                    cachedScopedStatusCounts = counts
                    cachedUnknownArchivesCount = unknownCount
                }
            }
        }
        .onChange(of: viewModel.auditReport) {
            // Computed first: `gameNodes(from:)` (inside
            // `recomputeCachedGameDataSync`) reads `gameAggregateStatusByName`
            // for each row's true badge and for the toggle-independent
            // surplus-folding check — it must never see a stale/empty
            // version of it.
            gameAggregateStatusByName = computeGameAggregateStatusByName()
            recomputeCachedGameDataSync()
            refreshExpandedDatabaseCategoryCaches()
        }
        .onChange(of: viewModel.cachedDATFile) {
            // Reads `DATFile.hasClones` (computed once from the raw,
            // pre-layout-planning machine list) rather than re-deriving it
            // from `.games` here — jensyleo's own report (2026-08-04): a
            // real bug found live, `.games.contains { $0.cloneOf != nil }`
            // is structurally guaranteed `false` whenever the DAT happened
            // to load under Rom merge mode "Merged" (which excludes every
            // clone from that list entirely, by design), regardless of
            // whether the system actually has clones — see `DATFile.hasClones`'s
            // own doc comment for the full story of what that silently broke.
            if let dat = viewModel.cachedDATFile {
                onDATAnalyzed?(dat.hasClones)
            }
        }
        .onAppear {
            viewModel.loadPersistedReport(system: system)
            gameAggregateStatusByName = computeGameAggregateStatusByName()
            recomputeCachedGameDataSync()
            refreshExpandedDatabaseCategoryCaches()
            // Loads the DAT immediately, independent of scanning any
            // folder — previously the DAT only ever loaded as the first
            // phase of a real Scan, so simply adding/opening a system with
            // its DAT+folders already selected did nothing until the user
            // pressed "Scan Folder".
            viewModel.startPreloadDAT(system: system)
        }
        .onReceive(NotificationCenter.default.publisher(for: .romForgeResetColumnSizes)) { _ in
            gameColumnCustomization = TableColumnCustomization<GameNode>()
            romColumnCustomization = TableColumnCustomization<RomRow>()
            UserDefaults.standard.removeObject(forKey: Self.gameColumnCustomizationKey)
            UserDefaults.standard.removeObject(forKey: Self.romColumnCustomizationKey)
        }
    }

    /// Replaces the entire Database/Games/detail area while a DAT is
    /// loading — see `body`'s own comment for why: the small floating
    /// `scanProgressOverlay` card alone left the *previous* DAT's full
    /// results fully visible and interactive underneath it, which read as
    /// current when it wasn't. This is the primary content in that state,
    /// not an overlay on top of stale data.
    private var loadingDATPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            if let dat = viewModel.datLoadProgress, dat.total > 0 {
                ProgressView(value: Double(dat.parsed), total: Double(dat.total))
                    .frame(width: 280)
                Text("Loading DAT… \(dat.parsed) of \(dat.total) machines")
                    .foregroundStyle(.secondary)
            } else if let fileRead = viewModel.datFileReadProgress, fileRead.total > 0 {
                ProgressView(value: Double(fileRead.read), total: Double(fileRead.total))
                    .frame(width: 280)
                Text("Reading DAT file… \(Self.formattedBytes(fileRead.read)) of \(Self.formattedBytes(fileRead.total))")
                    .foregroundStyle(.secondary)
            } else if viewModel.isCountingDATMachines {
                if let counting = viewModel.datCountingProgress, counting.total > 0 {
                    ProgressView(value: Double(counting.scanned), total: Double(counting.total))
                        .frame(width: 280)
                } else {
                    ProgressView()
                }
                Text("Counting machines…")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Loading DAT…")
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { viewModel.cancelCurrentOperation() }
                .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // While a new DAT is loading, the *previous* one's name/version
            // would otherwise sit here unchanged (`datHeader` only updates
            // once loading actually finishes) — reading as if it were still
            // current, when the whole games/database view below it is about
            // to change out from under it. A real, reported source of
            // confusion switching between two DATs for the same system.
            Text(viewModel.isLoadingDAT ? "DAT: Loading…" : "DAT: \(viewModel.datHeader.map { "\($0.name) \($0.version)" } ?? system.name)")
                .font(.headline)
            if !viewModel.isLoadingDAT, let worst = viewModel.auditReport?.worstStatus {
                Image(systemName: symbolName(for: worst))
                    .foregroundStyle(tint(for: worst))
                    .help(worst == .correct ? "Everything scanned is correct" : "This system has \(worst.rawValue) items")
            }
        }
    }

    // MARK: - Scan progress

    private var scanProgressOverlay: some View {
        VStack(spacing: 8) {
            if viewModel.isLoadingDAT {
                // A large MAME DAT is tens/hundreds of MB of XML — parsing
                // it can itself take a noticeable while in an unoptimized
                // build, before anything has touched a folder yet. Without
                // its own message this silently looked like "scanning
                // folders" for a phase that hadn't started scanning at all.
                if let dat = viewModel.datLoadProgress, dat.total > 0 {
                    ProgressView(value: Double(dat.parsed), total: Double(dat.total))
                        .frame(width: 240)
                    Text("Loading DAT… \(dat.parsed) of \(dat.total) machines")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let fileRead = viewModel.datFileReadProgress, fileRead.total > 0 {
                    // Reading a real full-driver-set DAT off disk (hundreds
                    // of MB) is itself a real, sometimes slow stretch —
                    // worse and less predictable under iCloud Drive sync
                    // (this app's own ROM folders live there) — that used
                    // to show nothing but a bare, generic spinner with no
                    // indication of what was actually happening.
                    ProgressView(value: Double(fileRead.read), total: Double(fileRead.total))
                        .frame(width: 240)
                    Text("Reading DAT file… \(Self.formattedBytes(fileRead.read)) of \(Self.formattedBytes(fileRead.total))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if viewModel.isCountingDATMachines {
                    // This brief up-front byte-count pass produces the total
                    // the bar above then uses — for a real full-driver-set
                    // DAT (hundreds of MB) it can itself take a few real
                    // seconds, so a real determinate bar (bytes scanned of
                    // the DAT's own size) replaced a bare spinner that used
                    // to read as an unexplained stall for however long it
                    // took.
                    if let counting = viewModel.datCountingProgress, counting.total > 0 {
                        ProgressView(value: Double(counting.scanned), total: Double(counting.total))
                            .frame(width: 240)
                    } else {
                        ProgressView()
                    }
                    Text("Counting machines…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                    Text("Loading DAT…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isMatching {
                // Hashing finishing (100%) doesn't mean the scan itself is
                // done — comparing every hashed file against a large DAT
                // (tens/hundreds of thousands of machines) is its own real,
                // separately-timed phase (this session measured it as long
                // as ~13 minutes before being parallelized). Without its
                // own message, the overlay looked stuck at a frozen 100%
                // hashing bar for however long matching then took. A real
                // determinate bar (`ROMMatcher.match`'s own throttled
                // progress) replaces the bare spinner that used to show
                // here once games start reporting in — the first moment or
                // two before any callback has fired yet still falls back to
                // an indeterminate spinner, since there's nothing to show a
                // fraction of before that.
                if let match = viewModel.matchProgress, match.total > 0 {
                    ProgressView(value: Double(match.completed), total: Double(match.total))
                        .frame(width: 240)
                    Text("Comparing against the database… \(match.completed) of \(match.total) games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(width: 240)
                    Text("Comparing against the database…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let progress = viewModel.scanProgress, progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total))
                    .frame(width: 240)
                // "Calculating" rather than "Hashing" for every algorithm
                // combination, not just CRC32-only — simpler and still
                // accurate (CRC32-only's fast path, see `ZipArchiveHasher`,
                // doesn't decompress/hash at all, just reads a stored
                // checksum, so "Hashing" was actively wrong there; for
                // MD5/SHA1 it's not wrong, just needlessly more specific
                // than this one label needs to be).
                Text("Calculating \(progress.completed) of \(progress.total) files…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let archives = viewModel.archiveListingProgress {
                ProgressView(value: Double(archives.read), total: Double(archives.total))
                    .frame(width: 240)
                Text("Reading archive \(archives.read) of \(archives.total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let filesFound = viewModel.folderScanFilesFound {
                // No known total while walking the folder tree — an
                // indeterminate bar still reads as "something is actively
                // happening" instead of the live count being the only
                // sign of life, which for a big collection can otherwise
                // look identical to a hang for a long stretch.
                ProgressView()
                    .frame(width: 240)
                Text("Scanning folders… \(filesFound) files found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Scanning folders…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel") { viewModel.cancelCurrentOperation() }
                .font(.caption)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    private static func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// Explains the concrete consequence of the phase the user just
    /// cancelled — a bare "cancelled" with no explanation would read as a
    /// bug (why does the report look empty/incomplete?) rather than
    /// something they chose to stop.
    private var cancelledPhaseMessage: String {
        switch viewModel.cancelledPhase {
        case .datLoad:
            return "DAT loading was cancelled before it finished — nothing can be scanned or audited for this system until the DAT loads successfully. Try again when ready."
        case .hashing:
            return "The scan was cancelled before hashing finished — the audit report is now incomplete: files not yet reached will show as missing even if they're actually present. Run Scan again for accurate results."
        case nil:
            return ""
        }
    }

    // MARK: - Log panel

    private var logPane: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Log")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(viewModel.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.logLines.count) {
                    proxy.scrollTo(viewModel.logLines.count - 1, anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Status filter

    /// Four game-level lenses — jensyleo's own confirmed definitions and
    /// priority (2026-08-04): Missing > Bad > Incorrect > Correct (see
    /// `gameCategory(for:)`'s own doc comment for the full rundown):
    /// - **Missing**: at least one rom is genuinely absent. Only
    ///   meaningful browsing "Database" (a DAT-wide catalog question);
    ///   browsing a "Rom files" folder is scoped to real files on disk, so
    ///   a wholly-absent game naturally has nothing to scope into and
    ///   never appears there regardless of this toggle.
    /// - **Bad** (`AuditStatus.badDump`): no missing rom, but at least one
    ///   rom's local file has a hash that doesn't match the DAT's declared
    ///   CRC32/MD5/SHA — a real content problem, not just a naming one.
    /// - **Incorrect**: no missing/Bad rom, but at least one is misnamed or
    ///   found somewhere else the app can see — a naming/location problem
    ///   only, the content itself genuinely matches something real.
    /// - **Correct**: 100% healthy — every rom present, right name, right
    ///   hash.
    /// All four are independent multi-select toggles, same as before.
    private var statusSummary: some View {
        HStack(spacing: 20) {
            // Order: Correct, Incorrect, Bad, Unknown, Missing — jensyleo's
            // own call (2026-07-30).
            statusFilterButton(status: .correct, symbol: "checkmark.circle.fill", tint: .green, count: cachedScopedStatusCounts[.correct] ?? 0, label: "Correct")
            statusFilterButton(status: .incorrect, symbol: "exclamationmark.triangle.fill", tint: .yellow, count: cachedScopedStatusCounts[.incorrect] ?? 0, label: "Incorrect")
            statusFilterButton(status: .badDump, symbol: "exclamationmark.octagon.fill", tint: .orange, count: cachedScopedStatusCounts[.badDump] ?? 0, label: "Bad")
            unknownArchivesFilterButton
            statusFilterButton(status: .missing, symbol: "xmark.circle.fill", tint: .red, count: cachedScopedStatusCounts[.missing] ?? 0, label: "Missing")
            combineRomAndCHDFilterButton
            if activeStatusFilters != Set(AuditStatus.allCases) || !showUnknownArchives || combineRomAndCHD {
                Button("Show all") {
                    activeStatusFilters = Set(AuditStatus.allCases)
                    showUnknownArchives = true
                    combineRomAndCHD = false
                }
                .font(.caption)
            }
        }
    }

    /// `showUnknownArchives`'s own toggle — same look/philosophy as the
    /// four status buttons, just backed by a plain `Bool` instead of
    /// `AuditStatus` membership (an unrecognized archive isn't one of the
    /// four real categories at all — see `computeScopedStatusCounts()`'s
    /// own doc comment).
    private var unknownArchivesFilterButton: some View {
        Button {
            showUnknownArchives.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill").foregroundStyle(.gray)
                Text("Unknown: \(cachedUnknownArchivesCount)")
            }
            .foregroundStyle(showUnknownArchives ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Show/hide archives that don't match any known game at all")
    }

    /// jensyleo's own request (2026-07-30): a quick way back to the old,
    /// single-row-per-game view (rom+CHD folded together) for comparison —
    /// off by default, since separate rows are the intended default going
    /// forward. See `gameNodes(from:)`'s own doc comment for exactly what
    /// changes when this is on.
    private var combineRomAndCHDFilterButton: some View {
        Button {
            combineRomAndCHD.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.merge").foregroundStyle(.secondary)
                Text("Combine ROM+CHD")
            }
            .foregroundStyle(combineRomAndCHD ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .help("Show a game's rom and CHD as one combined row, like before they were split into independent rows — off by default")
    }

    /// Each status is an independent on/off toggle — not a single exclusive
    /// choice — so "Correct + Incorrect together, Missing off" is directly
    /// expressible by clicking each one to the state you want, instead of
    /// only ever being able to isolate one status or show all four. Filters
    /// which *games* appear in the list — see `statusSummary`'s own doc
    /// comment for exactly what each of the four means.
    private func statusFilterButton(status: AuditStatus, symbol: String, tint: Color, count: Int, label: String) -> some View {
        Button {
            if activeStatusFilters.contains(status) { activeStatusFilters.remove(status) } else { activeStatusFilters.insert(status) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text("\(label): \(count)")
            }
            .foregroundStyle(activeStatusFilters.contains(status) ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Leftmost pane: RomCenter's "Database" category tree

    /// RomCenter's real left-pane layout has two separate root nodes — the
    /// DAT's own category tree ("Database": All games/Verified games/...)
    /// and the configured source folders ("Rom files": one leaf per
    /// `RomSystem.romFolderURLs` entry, plus an "Add Folder…" leaf) —
    /// rather than one flat list. Both roots drive the exact same
    /// audit-driven Games tree; clicking a "Database" category filters by
    /// category, clicking a "Rom files" folder scopes to that folder
    /// instead — mutually exclusive, matching what's shown in the Games
    /// pane at any moment.
    private var databaseList: some View {
        // No longer uses `List`'s own `selection:` binding for the
        // "Database" section — a category row now needs both a plain click
        // (select it, exactly as before) *and* its own independent
        // expand/collapse disclosure, which doesn't fit a single-value
        // `List` selection tag. Manual `Button`s + `fontWeight` highlighting
        // instead, matching the same pattern "Rom files" already used below.
        List {
            Section {
                if isDatabaseSectionExpanded {
                    ForEach(DatabaseFilter.allCases) { filter in
                        DisclosureGroup(isExpanded: databaseCategoryExpansion(for: filter)) {
                            ForEach(databaseCategoryChildrenCache[filter] ?? []) { node in
                                databaseTreeNodeRow(node, filter: filter)
                            }
                        } label: {
                            Button {
                                selectedDatabaseFilter = filter
                                selectedRomFolder = nil
                            } label: {
                                Label(filter.rawValue, systemImage: filter.symbolName)
                                    .fontWeight(selectedDatabaseFilter == filter ? .semibold : .regular)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                sectionHeaderButton(title: "Database", systemImage: "cylinder.split.1x2.fill", isExpanded: $isDatabaseSectionExpanded)
            }
            Section {
                if isRomFilesSectionExpanded {
                    ForEach(system.romFolderURLs, id: \.self) { url in
                        Button {
                            selectedDatabaseFilter = nil
                            selectedRomFolder = url
                        } label: {
                            Label(url.lastPathComponent, systemImage: "externaldrive")
                                .fontWeight(selectedRomFolder == url ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                        .help(url.path)
                        .contextMenu {
                            Button("Remove Folder", role: .destructive) {
                                removeRomFolder(url)
                            }
                        }
                    }
                    Button {
                        addRomFolder()
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } header: {
                sectionHeaderButton(title: "Rom files", systemImage: "externaldrive.fill", isExpanded: $isRomFilesSectionExpanded)
            }
        }
        .listStyle(.sidebar)
    }

    /// A system's ROM folders were only ever set once, at creation time in
    /// `AddSystemSheet` — this lets more folders be added later without
    /// recreating the system (losing its DAT/category/scan history). The
    /// new folder shows up in "Rom files" immediately; the caller
    /// (`onAddFolder`, wired to `SystemLibraryStore.update` in
    /// `ContentView`) is responsible for persisting it. A Scan still has
    /// to be run again to actually audit the newly added folder's
    /// contents — adding a folder doesn't retroactively rewrite the last
    /// persisted report.
    private func addRomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more additional folders containing this system's ROMs"
        guard panel.runModal() == .OK else { return }
        var folders = system.romFolderURLs
        var addedFolders: [URL] = []
        for url in panel.urls where !folders.contains(url) {
            folders.append(url)
            addedFolders.append(url)
        }
        guard folders != system.romFolderURLs else { return }
        onAddFolder(folders)
        // After adding, focus shifts to the last added folder so the user can
        // proceed directly to scanning it (jensyleo's own call, 2026-07-30).
        if let lastAdded = addedFolders.last {
            selectedRomFolder = lastAdded
            selectedDatabaseFilter = nil
            // Auto-scan on add if enabled globally (new setting, 2026-07-30)
            if UserDefaults.standard.bool(forKey: "ROMForge.scan.autoScanOnAdd") {
                viewModel.startScan(system: system, folders: [lastAdded])
            }
        }
    }

    /// The "Rom files" tree only ever offered adding a folder, never
    /// removing one — jensyleo's own report: no way to drop a folder once
    /// added, short of recreating the whole system. A folder scoped to the
    /// one just removed clears back to the unscoped "Database" view, since
    /// there's nothing left for it to point at; a Scan still has to be run
    /// again to actually drop that folder's contents from the last
    /// persisted audit report. If this removal empties the system's whole
    /// "Rom files" list, the selection jumps to "Database → All games"
    /// unconditionally (jensyleo's own call, 2026-07-30) — with zero
    /// folders left, whatever "Rom files" item was still selected (even one
    /// other than the one just removed) no longer points at anything real.
    private func removeRomFolder(_ url: URL) {
        var folders = system.romFolderURLs
        folders.removeAll { $0 == url }
        if selectedRomFolder == url || folders.isEmpty {
            selectedRomFolder = nil
            selectedDatabaseFilter = .allGames
        }
        onAddFolder(folders)
        // Purges this folder's entries from the persisted report/scan
        // cache right away — see `LibraryViewModel.removeFolder(_:system:)`'s
        // own doc comment for why this can't just wait for the next scan.
        viewModel.removeFolder(url, system: system)
    }

    /// A tappable Section header — clicking the name (not just a disclosure
    /// triangle) collapses/expands that root, matching how the reference
    /// RomCenter tree behaves (its "▲"/"▼" toggles on a click anywhere on
    /// the row, not a tiny fixed hit target).
    private func sectionHeaderButton(title: String, systemImage: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            isExpanded.wrappedValue.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Label(title, systemImage: systemImage)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Left pane: games (RomCenter's "Selection" list, as a parent/clone tree)

    private var gamesList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(gamesListTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            gameTreeTable
        }
    }

    private var gamesListTitle: String {
        guard let selectedRomFolder else { return "Games (\(cachedGameNodes.count))" }
        return "\(selectedRomFolder.lastPathComponent) — Games (\(cachedGameNodes.count))"
    }

    /// The one audit-driven tree — same columns, same status colors, same
    /// selection/detail flow — used whether browsing by "Database" category
    /// or by "Rom files" folder; only which entries feed it changes
    /// (`databaseFilteredEntries`), not the view itself.
    ///
    /// Columns are user-customizable (right-click a header, or the "＋"
    /// control at its trailing edge, for "Edit Columns…") — show/hide,
    /// reorder, and resize, persisted across launches via
    /// `gameColumnCustomization`. The leading status-icon column is exempt
    /// (`.disabledCustomizationBehavior(.all)`): it's a fixed 20pt glyph,
    /// not something reordering or hiding makes sense for.
    private var gameTreeTable: some View {
        ScrollViewReader { proxy in
            gameTreeTableContent
                .onAppear { gameTableScrollProxy = proxy }
        }
    }

    private var gameTreeTableContent: some View {
        Table(cachedGameNodes, selection: $selectedGameID, columnCustomization: $gameColumnCustomization) {
            TableColumn("") { node in
                if let status = node.aggregateStatus {
                    Image(systemName: symbolName(for: status)).foregroundStyle(tint(for: status))
                } else {
                    // Not scanned yet — a real, DAT-backed game, just with
                    // nothing yet to compare it against.
                    Image(systemName: "circle.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .width(20)
            .customizationID("status")
            .disabledCustomizationBehavior(.all)
            TableColumn("Game name") { node in Text(node.gameName) }
                .customizationID("gameName")
            TableColumn("File name") { node in Text(node.actualFileName ?? node.name) }
                .customizationID("fileName")
            TableColumn("Info") { node in Text(node.infoText) }
                .customizationID("info")
            TableColumn("Expected file name") { node in Text(node.expectedFileName ?? "") }
                .customizationID("expectedFileName")
            TableColumn("Size") { node in Text(totalSizeText(for: node)) }
                .customizationID("size")
                .defaultVisibility(.hidden)
            TableColumn("Clone of") { node in Text(node.cloneOf) }
                .customizationID("cloneOf")
            TableColumn("CHD") { node in Text(node.chdNames) }
                .customizationID("chd")
                .defaultVisibility(.hidden)
            TableColumn("Samples") { node in Text(node.samplesText) }
                .customizationID("samples")
                .defaultVisibility(.hidden)
            // `Table`'s column builder tops out at 10 columns per block —
            // grouped here to fit the rest (BIOS/year/manufacturer/required
            // BIOS/device refs) into one additional slot.
            Group {
                TableColumn("BIOS") { (node: GameNode) in Text(node.biosText) }
                    .customizationID("bios")
                    .defaultVisibility(.hidden)
                TableColumn("Year") { (node: GameNode) in Text(node.year) }
                    .customizationID("year")
                    .defaultVisibility(.hidden)
                TableColumn("Manufacturer") { (node: GameNode) in Text(node.manufacturer) }
                    .customizationID("manufacturer")
                    .defaultVisibility(.hidden)
                TableColumn("Required BIOS") { (node: GameNode) in Text(node.requiredBiosNames) }
                    .customizationID("requiredBios")
                    .defaultVisibility(.hidden)
                TableColumn("Device refs") { (node: GameNode) in Text(node.deviceRefNames) }
                    .customizationID("deviceRefs")
                    .defaultVisibility(.hidden)
            }
        }
        .onChange(of: gameColumnCustomization) { Self.persist(gameColumnCustomization, key: Self.gameColumnCustomizationKey) }
        .onKeyPress(phases: .down) { keyPress in
            handleTypeAheadKeyPress(keyPress)
        }
        // MAME-only, and only once a real `mame` executable is configured
        // — see `MAMELauncher`/`canLaunchMAME(_:)`. Selecting a row via
        // right-click already updates `selectedGameID` (SwiftUI's own
        // `Table` behavior), so `node` below is always the row actually
        // right-clicked, not whatever was selected before.
        .contextMenu(forSelectionType: GameNode.ID.self) { selection in
            if let id = selection.first, let node = cachedGameNodes.first(where: { $0.id == id }) {
                Button {
                    scanFile(node)
                } label: {
                    Label("Rescan This File", systemImage: "arrow.clockwise")
                }
                .disabled(!canScanFile(node))
                Button {
                    launchInMAME(node)
                } label: {
                    Label("Play in MAME", systemImage: "play.fill")
                }
                .disabled(!canLaunchMAME(node))
            }
        }
    }

    /// Matches `keyPress` against the classic type-ahead pattern (see
    /// `typeAheadBuffer`'s own doc comment): only a single, printable,
    /// non-modified character is handled here — everything else (arrows,
    /// return, delete, ⌘-anything) is left `.ignored` so `Table`'s own
    /// keyboard navigation and every other shortcut in this view keeps
    /// working exactly as before.
    private func handleTypeAheadKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.isEmpty || keyPress.modifiers == .shift,
              let character = keyPress.characters.first, keyPress.characters.count == 1,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol else {
            return .ignored
        }
        let now = Date()
        if now.timeIntervalSince(lastTypeAheadKeystroke) > Self.typeAheadTimeout {
            typeAheadBuffer = ""
        }
        lastTypeAheadKeystroke = now
        typeAheadBuffer.append(character)

        // Matches the same "File name" fallback the table itself already
        // shows (`node.actualFileName ?? node.name`, this view's own
        // "File name" column) — jensyleo's own request (2026-08-04) was
        // specifically "el nombre del archivo", not the DAT's own
        // (usually longer, more descriptive) "Game name".
        let lowercasedBuffer = typeAheadBuffer.lowercased()
        guard let match = cachedGameNodes.first(where: { node in
            (node.actualFileName ?? node.name).lowercased().hasPrefix(lowercasedBuffer)
        }) else {
            return .handled
        }
        selectedGameID = match.id
        withAnimation {
            gameTableScrollProxy?.scrollTo(match.id, anchor: .center)
        }
        return .handled
    }

    /// jensyleo's own request (2026-07-28): scanning used to only ever
    /// cover a whole folder (all of "Rom files", or one folder scoped via
    /// "Scan Folder") — no way to rescan just one specific archive without
    /// rescanning everything alongside it. `actualFileURL(for:)` is the
    /// real physical file on disk this game's roms actually live in (the
    /// same one `actualFileName`/`totalSizeText` already derive from), fed
    /// straight into `startScan`'s existing `folders:` scoping — which
    /// already merges a partial rescan into the last full report by path
    /// prefix (`LibraryViewModel.merge`), so scoping it down to one exact
    /// file just narrows that same mechanism further, no new merge logic
    /// needed.
    private func actualFileURL(for node: GameNode) -> URL? {
        node.entries.first(where: { $0.path != nil })?.path
    }

    private func canScanFile(_ node: GameNode) -> Bool {
        !viewModel.isBusy && actualFileURL(for: node) != nil
    }

    private var canScanSelectedFile: Bool {
        selectedGameNode.map(canScanFile) ?? false
    }

    private var scanFileButtonHelpText: String {
        guard let node = selectedGameNode, actualFileURL(for: node) != nil else {
            return "Select a game with a real file on disk to rescan just that one"
        }
        return "Rescan only \(node.actualFileName ?? node.name) — every other file keeps its last known results"
    }

    private func scanSelectedFile() {
        guard let node = selectedGameNode else { return }
        scanFile(node)
    }

    private func scanFile(_ node: GameNode) {
        guard let url = actualFileURL(for: node) else { return }
        viewModel.startScan(system: system, folders: [url])
    }

    /// Sum of every rom's size in a game/archive — `expectedSize` (the
    /// DAT's declared size) when available, falling back to whatever was
    /// actually found for entries the DAT says nothing about (surplus).
    /// Hidden by default: useful for spotting a suspiciously large/small
    /// archive, but not something most users need visible all the time.
    private func totalSizeText(for node: GameNode) -> String {
        let total = node.entries.reduce(Int64(0)) { $0 + ($1.expectedSize ?? $1.actualSize ?? 0) }
        return total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : ""
    }

    // MARK: - Right pane: ROM files of the selected game (RomCenter's file panel)

    private var romsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedGameNode.map { "\($0.name) (\($0.entries.count) files)" } ?? "Select a game")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Table(selectedRomRows, selection: $selectedRomID, columnCustomization: $romColumnCustomization) {
                TableColumn("") { row in
                    romCell(Image(systemName: symbolName(for: row.entry.status)).foregroundStyle(tint(for: row.entry.status)), status: row.entry.status)
                }
                .width(20)
                .customizationID("status")
                .disabledCustomizationBehavior(.all)
                TableColumn("File name") { row in
                    // `path` is nil whenever nothing was actually found on
                    // disk for this rom (status `.missing`) — genuinely
                    // blank, not a rendering glitch, but a bare empty cell
                    // reads as broken, so it gets an explicit placeholder
                    // instead. The expected name still lives in "Rom name".
                    if let fileName = row.entry.path?.lastPathComponent {
                        romCell(Text(fileName), status: row.entry.status)
                    } else {
                        romCell(Text("— not found —").foregroundStyle(.secondary), status: row.entry.status)
                    }
                }
                .customizationID("fileName")
                TableColumn("Rom name") { row in
                    romCell(Text(row.entry.name), status: row.entry.status)
                }
                .customizationID("romName")
                TableColumn("Info") { row in
                    romCell(Text(infoText(for: row.entry)), status: row.entry.status)
                }
                .customizationID("info")
                TableColumn("Size") { row in
                    romCell(Text(sizeText(for: row.entry)), status: row.entry.status)
                }
                .customizationID("size")
                // Used to be one combined "Crc/SHA-1" column that only ever
                // displayed the CRC value — real bug found by jensyleo
                // (2026-07-28): labeled as showing both, but SHA-1 was
                // never actually reachable at all, reading as if SHA-1
                // hashing wasn't really happening even when enabled in
                // Settings. Split into two real columns, matching the
                // existing MD5 column's own pattern exactly.
                TableColumn("CRC") { row in
                    romCell(Text(row.entry.actualCRC ?? row.entry.expectedCRC ?? ""), status: row.entry.status)
                }
                .customizationID("crc")
                TableColumn("SHA-1") { row in
                    romCell(Text(row.entry.actualSHA1 ?? row.entry.expectedSHA1 ?? ""), status: row.entry.status)
                }
                .customizationID("sha1")
                // `Table`'s column builder tops out at 10 columns per
                // block (same limit `gameTreeTable` already hit) — adding
                // the new "SHA-1" column above pushed this table over it,
                // so the trailing, already-hidden-by-default columns move
                // into their own group to fit.
                Group {
                    TableColumn("Folder") { (row: RomRow) in
                        romCell(Text(row.entry.path?.deletingLastPathComponent().lastPathComponent ?? ""), status: row.entry.status)
                    }
                    .customizationID("folder")
                    .defaultVisibility(.hidden)
                    TableColumn("MD5") { (row: RomRow) in
                        romCell(Text(row.entry.actualMD5 ?? row.entry.expectedMD5 ?? ""), status: row.entry.status)
                    }
                    .customizationID("md5")
                    .defaultVisibility(.hidden)
                    TableColumn("Dump status") { (row: RomRow) in
                        romCell(Text(dumpStatusText(for: row.entry)), status: row.entry.status)
                    }
                    .customizationID("dumpStatus")
                    .defaultVisibility(.hidden)
                    TableColumn("Merge name") { (row: RomRow) in
                        romCell(Text(row.entry.mergeName ?? ""), status: row.entry.status)
                    }
                    .customizationID("mergeName")
                    .defaultVisibility(.hidden)
                }
            }
            .onChange(of: romColumnCustomization) { Self.persist(romColumnCustomization, key: Self.romColumnCustomizationKey) }
        }
    }

    /// Wraps a cell in the row's status tint (a lighter background than the
    /// status icon color), RomCenter-style — green/yellow/red/gray rows at a
    /// glance instead of only the leading icon.
    private func romCell(_ content: some View, status: AuditStatus) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(tint(for: status).opacity(0.18))
    }

    private func infoText(for entry: AuditEntry) -> String {
        // A DAT's own baddump/nodump flag is a claim about the reference
        // dump itself — worth surfacing regardless of what ROMForge found
        // (or didn't) locally, so it's layered on top of the match status
        // rather than replacing it.
        var base: String
        switch entry.status {
        // `matchedViaHeaderStrip` means the file only matched once a
        // detected copier header (iNES/Lynx/copier512 — `HeaderSkipRule`)
        // was stripped from it — the file itself still has that header on
        // disk, it just isn't part of what the DAT's own hash describes.
        // Surfaced as a caveat rather than plain "Ok" so it isn't reported
        // identically to a byte-for-byte match — jensyleo's own request
        // (2026-07-30) after reviewing every `infoText` case. **Not yet
        // verified live**: none of NES/Atari Lynx/SNES/Game Boy/PC Engine/
        // Master System/Genesis were available to test this session — the
        // exact wording here needs a real headered dump from one of those
        // systems to confirm it reads right in practice.
        case .correct: base = entry.matchedViaHeaderStrip ? "Ok (header removed to match)" : "Ok"
        // Three distinct reasons an entry reads `.incorrect`, checked in
        // order from most to least specific:
        // - `requiredByGameDescription` set: a *surplus* file (no expected
        //   rom of its own — `game: nil`, see this field's own doc comment)
        //   whose content is nonetheless fully identified as belonging to
        //   a different game's own archive (e.g. a Split-mode clone's zip
        //   still holding a rom its parent's archive actually wants).
        //   jensyleo's own correction (2026-08-04): this used to stay
        //   `.surplus`/"Unrecognized", which is wrong — "surplus" must mean
        //   genuinely unknown, and this is the opposite: fully known,
        //   just currently misplaced. The reverse relationship from
        //   `foundElsewhereArchiveName` below ("no game *here* needs it,
        //   someone else does" vs. "*this* game needs it, found
        //   elsewhere") — worth its own message rather than reusing either.
        // - `foundElsewhereArchiveName` set: this rom *is* expected by its
        //   own game, and isn't really a naming mistake to go fix — the
        //   content is genuinely present, just somewhere else in the scan
        //   — jensyleo's own request (2026-08-04): its own distinct,
        //   reassuring message rather than "Bad name", which implied a
        //   problem the user needs to act on.
        // - Neither: a genuine naming mismatch, "Bad name".
        case .incorrect:
            if let requiredBy = entry.requiredByGameDescription {
                base = "Not needed here (required by \(requiredBy))"
            } else {
                base = entry.foundElsewhereArchiveName.map { "Available in another game (\($0))" } ?? "Bad name"
            }
        // jensyleo's own definition (2026-08-04): a file genuinely sits in
        // this rom's own expected slot, but its CRC32/MD5/SHA doesn't
        // match — distinct from `.isBadDump` below (the DAT's own
        // baddump/nodump claim about the *reference* dump itself); this is
        // ROMForge's own finding about the *local* file.
        case .badDump: base = "Bad (hash mismatch)"
        // The DAT itself declares this rom/disk `optional="yes"` — MAME can
        // run the machine without it, real case found live by jensyleo
        // (2026-08-05) researched from MAME's own DTD (`cubeqst`/`cubeqsta`/
        // `atronic`'s laserdisc). Distinct wording from plain "Missing" so
        // it doesn't read as urgent/blocking the way a truly required
        // absence does.
        case .missing: base = entry.isOptional ? "Missing (optional)" : "Missing"
        case .surplus: base = "Unrecognized"
        // A file genuinely sits in this rom's own expected slot, but the
        // DAT itself declares this rom `nodump` — no CRC/MD5/SHA1 exists to
        // confirm it against, by design (see `RomMatchStatus.nodump`'s own
        // doc comment). Distinct from `.correct` (nothing here was actually
        // verified) and from `.surplus` (the DAT explicitly documents this
        // exact name/slot for this exact machine, so it isn't unrecognized).
        case .unverifiable: base = "Nodump (unverifiable)"
        }
        if entry.isBadDump {
            // For every other status, a file DID get matched/found, so "(bad
            // dump in DAT)" reads as an extra fact about that real file. For
            // `.missing`, nothing was found at all — appending the same
            // suffix read as self-contradictory ("Missing (bad dump in
            // DAT)" implies a bad file was found, when actually none was) —
            // jensyleo's own request (2026-07-30) to review every
            // `infoText` case surfaced this. Worded so the DAT's own claim
            // stays visible (still useful: it tells the user this rom
            // wouldn't have been fixable by re-dumping even if found)
            // without implying presence.
            base = entry.status == .missing ? "Missing (also a known bad dump in DAT)" : "\(base) (bad dump in DAT)"
        }
        // A zip's own archive-level comment (jensyleo's own request,
        // 2026-07-30) — some real romsets carry notes in this field (dump
        // source, fixer credits, "verified good" stamps) that ROMForge
        // otherwise silently discards. Only meaningful for a file that's
        // actually inside a zip (`entry.path` is the containing archive's
        // own URL for a zip-organized scan — see `ScannedFile`/
        // `CollectionHasher`, every entry in the same zip shares that one
        // URL) and only when there's actually a comment to show — nothing
        // is appended for loose files or a zip with no comment set.
        guard let path = entry.path, path.pathExtension.lowercased() == "zip",
              let comment = zipCommentCache.comment(forZipAt: path) else {
            return base
        }
        return "\(base) — \(comment)"
    }

    private func sizeText(for entry: AuditEntry) -> String {
        guard let size = entry.actualSize ?? entry.expectedSize else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// The DAT's own dump-quality claim for this specific rom — distinct
    /// from `infoText`'s "(bad dump in DAT)" suffix, which collapses
    /// `baddump`/`nodump` into one label; this spells out which one.
    private func dumpStatusText(for entry: AuditEntry) -> String {
        switch entry.romDumpStatus {
        case .good, nil: return ""
        case .baddump: return "Bad dump"
        case .nodump: return "No dump"
        }
    }

    // MARK: - Tree building

    /// The current "Database" category or "Rom files" folder scope, applied
    /// to *every* status regardless of which of the four toggles are
    /// currently on — used to size the status buttons themselves (see
    /// `scopedStatusCount(_:)`), so "Correct: 308" means "308 correct roms
    /// in what you're looking at right now", not a DAT-wide total that never
    /// changes no matter where you click.
    private var scopedEntries: [AuditEntry] {
        Self.scoped(
            viewModel.auditReport?.entries ?? [], databaseFilter: selectedDatabaseFilter,
            romFolder: selectedRomFolder, gamesInFolder: cachedGamesInFolder
        )
    }

    /// Just the "Database" category half of `scoped(_:)`'s filtering,
    /// parametrized by an explicit category rather than reading
    /// `selectedDatabaseFilter` — lets the expandable "Database" tree
    /// (`treeChildren(forCategory:)`) compute any category's own children,
    /// not only whichever one happens to be currently selected, without
    /// duplicating this switch a second time.
    private nonisolated static func categoryFiltered(_ entries: [AuditEntry], matching filter: DatabaseFilter) -> [AuditEntry] {
        switch filter {
        case .allGames: return entries
        case .verifiedGames:
            // A game counts as verified only if ALL of its roms matched —
            // filtering individual .correct entries would also surface a
            // few correct roms from an otherwise-incomplete game, which
            // isn't what "verified" means.
            let byGame = Dictionary(grouping: entries.filter { $0.game != nil }, by: { $0.game! })
            let verifiedGameNames = byGame.filter { _, gameEntries in gameEntries.allSatisfy { $0.status == .correct } }.keys
            return entries.filter { entry in entry.game.map(verifiedGameNames.contains) ?? false }
        case .originals: return entries.filter { $0.cloneOf == nil }
        case .clones: return entries.filter { $0.cloneOf != nil }
        case .biosFiles: return entries.filter { $0.isBios }
        case .gamesWithCHD: return entries.filter { $0.hasCHD }
        case .gamesWithSamples: return entries.filter { $0.hasSamples }
        case .gamesWithBadDumps: return entries.filter { $0.isBadDump }
        }
    }

    /// Applies the "Database" category (or "Rom files" folder) scope to an
    /// arbitrary entry list — factored out so it can run either on top of
    /// the status filter (`databaseFilteredEntries`, for the tree) or on
    /// every status at once (`scopedEntries`, for the button counts).
    private nonisolated static func scoped(_ entries: [AuditEntry], databaseFilter: DatabaseFilter?, romFolder: URL?, gamesInFolder: Set<String>) -> [AuditEntry] {
        let categoryFiltered = categoryFiltered(entries, matching: databaseFilter ?? .allGames)

        // A "Rom files" folder scopes the same audit down to what that
        // folder actually contributed. A missing rom has no `path` at all
        // (nothing was found anywhere), so it can't be scoped by path like
        // everything else — but keeping it regardless of folder meant every
        // folder's view flooded with the DAT's entire missing list (tens of
        // thousands of entries belonging to completely unrelated systems),
        // which drowned out combining Correct+Incorrect+Missing into
        // anything useful. Scoped instead to games that already have at
        // least one real file *in this folder* — i.e. incomplete sets this
        // folder is genuinely part of — computed from the full report
        // (not `categoryFiltered`) so it doesn't shift just because the
        // status filter itself changes.
        guard let romFolder else { return categoryFiltered }
        return categoryFiltered.filter { entry in
            // A `.foundElsewhere` entry's own `path` points to whichever
            // OTHER archive actually has the content (see its own doc
            // comment) — it's never this entry's own game's real file, so
            // it must never be trusted to mean "this game is physically in
            // this folder". Real bug found live by jensyleo (2026-08-04):
            // an unowned clone/hack (e.g. NEOGEO's `gpilotsp`) sharing BIOS/
            // inherited content with its real, owned parent (`gpilots.zip`,
            // genuinely inside this folder) got pulled into this folder's
            // own game list purely because that *borrowed* path happened
            // to resolve here — showing a row for a game the user doesn't
            // actually have anything of in this folder at all. Falls
            // through to the `gamesInFolder` check below instead, which
            // only reflects a game's own genuinely-owned files.
            if let path = entry.path, entry.foundElsewhereArchiveName == nil { return path.path.hasPrefix(romFolder.path) }
            return entry.game.map(gamesInFolder.contains) ?? false
        }
    }

    /// Recomputes what `cachedGamesInFolder` should be — call before
    /// `computeGameNodes()`/`computeScopedStatusCounts()` whenever
    /// `selectedRomFolder` or `viewModel.auditReport` itself just changed
    /// (the only two things this actually depends on), so `scoped(_:)` can
    /// read an already-fresh value instead of recomputing it every time
    /// it's called. `static` (see this file's own `.onChange(of:
    /// selectedRomFolder)` doc comment) so it, and everything downstream of
    /// it, can run off the main thread on a large collection without
    /// touching any `@State` directly.
    private nonisolated static func recomputeGamesInFolder(entries: [AuditEntry], selectedFolder: URL?) -> Set<String> {
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

    /// How many *archives* (one ZIP/7z per game/machine, per the split-mode
    /// convention every set here is built around) have each status as their
    /// aggregate, within the current scope — what each status button's
    /// count reflects, regardless of whether that status's own toggle
    /// happens to be on or off right now. Feeds `cachedScopedStatusCounts`.
    ///
    /// This counts games/archives, not individual ROM entries — a single
    /// archive can (and usually does) contain dozens of ROMs, so counting
    /// entries made a folder with a handful of archives report a number in
    /// the thousands, which didn't match anything the user could actually
    /// see or reason about ("NEOGEO" showing "3028" when it holds ~34
    /// archives). One count per archive, using the same worst-status
    /// aggregation the Games tree already shows via its icon, keeps this
    /// consistent with what's visibly in the tree.
    ///
    /// Computes all four statuses in one pass over `scopedEntries` (one
    /// scope filter, one game-grouping dictionary) rather than the four
    /// independent passes a separate `scopedStatusCount(_:)` per button
    /// used to do — on a ~188k-entry collection, redoing that scan/group
    /// 4x per render (once per status button) was real, avoidable work.
    private nonisolated static func computeScopedStatusCounts(scopedEntries: [AuditEntry], gamesByName: [String: DATGame]) -> [AuditStatus: Int] {
        var entriesByGame: [String: [AuditEntry]] = [:]
        var surplusByArchive: [String: [AuditEntry]] = [:]
        for entry in scopedEntries {
            if let game = entry.game {
                entriesByGame[game, default: []].append(entry)
            } else {
                let archiveName = entry.path?.lastPathComponent ?? entry.name
                surplusByArchive[archiveName, default: []].append(entry)
            }
        }
        // Same fold as `gameNodes(from:)`/`computeGameAggregateStatusByName()`
        // — see either's own doc comment, including why this is checked
        // against the DAT's own real catalog (`gamesByName`) rather than
        // "does `entriesByGame` already have this key" (a real game with
        // zero expected roms under the current merge mode, e.g. `qsound_hle`
        // under Split, never gets a key from real entries at all). Without
        // this fold, a game whose only problem is a folded-in "Not needed
        // here" file (now `.incorrect`, see
        // `AuditEntry.requiredByGameDescription`) would count as "Correct"
        // here while its own row reads yellow in the tree right next to
        // this button.
        // Any archive left over below (no `gamesByName` entry to fold
        // into — e.g. a clone excluded from `dat.games` entirely under
        // Merged, see `DATFile.allMachineNames`'s own doc comment) that's
        // still fully identified (`requiredByGameDescription` on every one
        // of its own entries — the exact same `isFullyIdentified` check
        // `gameNodes(from:)` uses to color its row yellow instead of gray)
        // gets counted here too, as one archive under `.incorrect` —
        // closing the gap jensyleo asked about (2026-08-04): a row reading
        // yellow "Extra archive, not needed here" that this header's own
        // "Incorrect: N" never reflected.
        var orphanedFullyIdentifiedCount = 0
        for (archiveName, surplus) in surplusByArchive {
            let matchingGame = (archiveName as NSString).deletingPathExtension
            if gamesByName[matchingGame] != nil {
                entriesByGame[matchingGame, default: []].append(contentsOf: surplus)
            } else if !surplus.isEmpty, surplus.allSatisfy({ $0.requiredByGameDescription != nil || $0.status == .unverifiable }) {
                orphanedFullyIdentifiedCount += 1
            }
        }
        var counts: [AuditStatus: Int] = [:]
        counts[.incorrect] = orphanedFullyIdentifiedCount
        for entries in entriesByGame.values {
            // No folder-scope special case: "Missing" counts the same way in
            // a "Rom files" folder as in "Database" — jensyleo's own
            // correction (2026-08-04), reversing his earlier "Missing is
            // Database-only" rule after it turned out to be the wrong call.
            // `scoped(_:)` has already narrowed `scopedEntries` to games that
            // genuinely own at least one real file *in this folder*, so a
            // `.missing` rom reaching here always belongs to a set this
            // folder really is part of — an incomplete set the user can
            // actually act on, which is exactly when it should read red.
            counts[romOnlyGameCategory(for: entries), default: 0] += 1
        }
        // A genuinely unrecognized archive ("Unknown game") isn't counted
        // under "Bad" (`.badDump`) at all — "Bad" means *known* games with
        // a real content problem (a hash-mismatched rom); an unclaimed
        // archive with no DAT game behind it at all is a different thing
        // entirely (gray/"Unknown"). It gets its own separate
        // `showUnknownArchives` toggle/count instead — see
        // `computeUnknownArchivesCount()`.
        return counts
    }

    /// How many genuinely unrecognized archives ("Unknown game" —
    /// `GameNode.isSurplusBucket`) are in the current scope — reuses
    /// `gameNodes(from:)`'s own already-correct archive-name folding
    /// (an unclaimed file living *inside* an otherwise-known game's
    /// archive doesn't count here at all, it's that game's own surplus
    /// rom instead) rather than a second, simpler-but-wrong count.
    /// Takes the *unfiltered* base node list (before the `showUnknownArchives`/
    /// `activeStatusFilters` toggles apply) — a surplus bucket's presence
    /// here must never depend on `showUnknownArchives` itself, or the
    /// count backing that very toggle's label would read 0 the moment the
    /// toggle is off, which is exactly backwards.
    private nonisolated static func computeUnknownArchivesCount(baseNodes: [GameNode]) -> Int {
        // Excludes a surplus bucket `gameNodes(from:)` reclassified yellow
        // (`.incorrect`, "Extra archive, not needed here…") — jensyleo's
        // own question (2026-08-04): counting a *fully identified* archive
        // under "Unknown" would contradict its own yellow color the moment
        // it's shown; genuinely unrecognized content (`.surplus`) is the
        // only thing this count is meant to mean.
        baseNodes.filter { $0.isSurplusBucket && $0.aggregateStatus == .surplus }.count
    }

    /// Groups entries by game and buckets game-less (surplus) entries into
    /// their own node — every game/clone is its own flat row (no
    /// parent/clone tree nesting: a clone is still its own separate archive
    /// with its own file on disk, and nesting it under its parent hid it
    /// from view unless the parent row was expanded).
    /// Browsing "Database" categories only ever needs the DAT that's
    /// already loaded — it shouldn't have to wait for a folder to be
    /// scanned first (a real bug: opening a freshly-added system, or one
    /// with no persisted report yet, showed a completely empty catalog
    /// until "Scan Folder" was pressed at least once, even though every
    /// game's name/description/BIOS/CHD/year/manufacturer is already known
    /// from the DAT alone). Used only for "Database" categories — a "Rom
    /// files" folder inherently needs real scan data (which file is
    /// actually *in* that folder isn't knowable from the DAT), so that
    /// still waits for a real scan, same as before.
    private nonisolated static func unscannedCatalogNodes(matching filter: DatabaseFilter, preloadedGames games: [DATGame]) -> [GameNode] {
        let categoryFiltered: [DATGame]
        switch filter {
        case .allGames: categoryFiltered = games
        // Both reflect an actual scan result (which roms really matched),
        // not anything the DAT alone can answer — honestly empty here
        // rather than showing something misleadingly labeled.
        case .verifiedGames, .gamesWithBadDumps: categoryFiltered = []
        case .originals: categoryFiltered = games.filter { $0.cloneOf == nil }
        case .clones: categoryFiltered = games.filter { $0.cloneOf != nil }
        case .biosFiles: categoryFiltered = games.filter(\.isBios)
        case .gamesWithCHD: categoryFiltered = games.filter { !$0.disks.isEmpty }
        case .gamesWithSamples: categoryFiltered = games.filter(\.hasSamples)
        }
        return categoryFiltered.map { game in
            GameNode(id: "game-\(game.name)", name: game.name, entries: [], aggregateStatus: nil, sourceGame: game)
        }
    }

    /// `computeGameNodes()`'s real grouping work, factored out so the
    /// "Database" tree's expandable category children (`treeChildren(for:)`
    /// below) can reuse the exact same game/surplus-archive grouping for an
    /// arbitrary category — not just whichever one happens to be currently
    /// selected — without duplicating this logic a second time.
    private nonisolated static func gameNodes(from entries: [AuditEntry], gamesByName: [String: DATGame], gameAggregateStatusByName: [String: AuditStatus], combineRomAndCHD: Bool, isFolderScoped: Bool) -> [GameNode] {
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
        // game", per ClrMamePro/RomCenter convention) instead of being
        // dumped into one combined "Surplus files" bucket — a scan with
        // several stray archives showed them all as one opaque row with no
        // way to tell which archive was which without opening the ROMs
        // pane. Several surplus entries can share one archive (more than
        // one stray file inside the same unrecognized zip), so they're
        // grouped by their containing archive name first.
        var surplusByArchive: [String: [AuditEntry]] = [:]
        var surplusOrder: [String] = []
        for entry in surplusEntries {
            let archiveName = entry.path?.lastPathComponent ?? entry.name
            if surplusByArchive[archiveName] == nil { surplusOrder.append(archiveName) }
            surplusByArchive[archiveName, default: []].append(entry)
        }

        // A surplus file living *inside* an archive that also fully/
        // partially matches a real known game (its own archive is named
        // after that exact game, per the ".zip per machine" convention) is
        // an extra/unexpected file in an otherwise-recognized set — e.g. a
        // stray rom the DAT doesn't call for — not a second, unrelated
        // "Unknown game". Folding it into that same game's own entries
        // instead of a separate phantom row avoids exactly that: two rows
        // both named "dino.zip", one matched and one "Unknown", reading as
        // if the same game were detected twice.
        // Whether an archive name is a *real* known game must never depend
        // on which statuses happen to be toggled visible right now — real
        // bug found live by jensyleo (2026-07-30): with Correct/Incorrect
        // toggled off and only Surplus on, `entriesByGame` (built from this
        // same toggle-filtered `entries` param) has no entry for a
        // perfectly well-matched game at all, so a stray extra file inside
        // its otherwise-fine archive wrongly showed as a separate "Unknown
        // game" instead of folding into that game's own row.
        //
        // Checked against `gamesByName` (the loaded DAT's own real game
        // catalog), not `gameAggregateStatusByName`'s keys — real bug found
        // live by jensyleo (2026-08-04, `qsound_hle` under Split): a real
        // DAT game whose entire expected rom list is empty under the
        // current merge mode (its only rom is `merge=`-tagged, stripped
        // entirely — see `AuditEntry.requiredByGameDescription`'s own
        // Split-mode case) never produces a single `entry.game != nil` row,
        // so it never gets a key in `gameAggregateStatusByName` either
        // (that dict is built purely from scan results). A stray/misplaced
        // file physically inside `qsound_hle.zip` then failed this
        // existence check and became its own "Unknown game" bucket — wrong,
        // since "QSound (HLE)" is a perfectly real, known machine, just one
        // with nothing of its own to expect right now. `gamesByName` is the
        // DAT's own catalog, independent of any scan result at all, so a
        // real game with zero expected roms is still recognized as real.
        for archiveName in surplusOrder {
            let matchingGame = (archiveName as NSString).deletingPathExtension
            guard gamesByName[matchingGame] != nil else { continue }
            if entriesByGame[matchingGame] == nil { gameOrder.append(matchingGame) }
            entriesByGame[matchingGame, default: []].append(contentsOf: surplusByArchive[archiveName] ?? [])
            surplusByArchive.removeValue(forKey: archiveName)
        }
        surplusOrder.removeAll { surplusByArchive[$0] == nil }


        var roots = gameOrder.flatMap { name -> [GameNode] in
            let entries = entriesByGame[name] ?? []
            let romEntries = entries.filter { !$0.isDisk }
            let diskEntries = entries.filter(\.isDisk)

            // `combineRomAndCHD`'s own toggle (off by default): the old,
            // pre-split behavior — one row, rom+CHD entries folded
            // together, for a quick side-by-side comparison against the
            // new default. Bypasses `gameAggregateStatusByName` (which is
            // deliberately rom-only now) since the whole point here is to
            // reproduce how it used to look, mixed status and all.
            if combineRomAndCHD {
                return [GameNode(id: "game-\(name)", name: name, entries: entries, aggregateStatus: gameCategory(for: entries), sourceGame: gamesByName[name])]
            }

            // Split into up to two independent rows — jensyleo's own
            // request (2026-07-30): a game's rom and its CHD disk must
            // each show its own real "Correct"/"Missing"/"Incorrect" as a
            // *separate* row, not folded into one combined row whose text
            // ("Incomplete (rom missing)") drowned out a perfectly correct
            // CHD just because that same game's rom happened to be
            // missing (or vice versa). Most games have only roms (no
            // `isDisk` entries at all) and still get exactly one row, same
            // as before.
            let diskStatus = diskEntries.isEmpty ? nil : gameCategory(for: diskEntries)

            var nodes: [GameNode] = []
            // A missing rom row is skipped entirely when this same game has
            // a CHD that isn't itself also fully missing — jensyleo's own
            // request (2026-07-30: "está el CHD, pero si no está la ROM, no
            // importa, no debe aparecer ese rojo"), reconfirmed after
            // briefly trying the opposite live (2026-08-04, `sfiii3jr1`):
            // showing the missing rom as its own separate red row, right
            // next to that same game's correct green disk row, read as more
            // confusing than helpful for a ROM+CHD game specifically — see
            // `STATES.md` for the full reasoning and the states/messages
            // table this rule is part of. Only applies to a genuinely
            // `.missing` rom (nothing at all found) — an `.incorrect`/
            // misnamed rom still shows, since that's a real, fixable
            // problem worth surfacing regardless of the CHD.
            let romIsMissing = romEntries.allSatisfy { $0.status == .missing }
            let skipMissingRom = romIsMissing && diskStatus != nil && diskStatus != .missing
            if !romEntries.isEmpty, !skipMissingRom {
                // The row's own badge always reflects the game's *true*
                // status — real bug found live by jensyleo (2026-07-28): with
                // the "Missing" status toggle off, `entries` here has already
                // had every missing rom filtered out before this function
                // ever sees it, so a game that's genuinely incomplete (e.g.
                // `gng`, missing 3 real roms) computed as green/"Ok" here,
                // simply because none of its missing rows were still in the
                // (status-toggle-filtered) list to notice. The status toggles
                // are meant to control which *individual rom rows* show in
                // the detail pane on the right (`entries`, unchanged below) —
                // not to make an incomplete game's own row lie about its
                // aggregate status. `gameAggregateStatusByName` (see its own
                // doc comment) is exactly the toggle-independent source of
                // truth already built for this same reason on the "Database"
                // tree side; reused here so the tree and this table can never
                // disagree again — it's already rom-only, matching `romEntries`.
                //
                // In a "Rom files" folder the aggregate comes from this
                // folder's own `romEntries` instead of `gameAggregateStatusByName`
                // (the DAT-wide truth) — NOT to suppress "Missing" (jensyleo
                // corrected that rule on 2026-08-04: Missing must show red in
                // a folder view too, whenever it genuinely applies), but
                // because a system can have several "Rom files" folders and
                // `scoped(_:)` has already dropped the roms this game keeps in
                // a *different* one. Consulting the DAT-wide aggregate here
                // would paint a game red in folder A purely because part of
                // its set legitimately lives in folder B. What survives
                // scoping is exactly the right input: roms genuinely here,
                // plus roms genuinely missing everywhere — so an incomplete
                // set this folder really is part of does read red, and a set
                // merely split across folders doesn't.
                let trueStatus = isFolderScoped
                    ? gameCategory(for: romEntries)
                    : gameAggregateStatusByName[name] ?? gameCategory(for: romEntries)
                nodes.append(GameNode(id: "game-\(name)", name: name, entries: romEntries, aggregateStatus: trueStatus, sourceGame: gamesByName[name]))
            }
            if let diskStatus {
                nodes.append(GameNode(id: "game-\(name)-chd", name: name, entries: diskEntries, aggregateStatus: diskStatus, isDiskRow: true, sourceGame: gamesByName[name]))
            }
            return nodes
        }
        for archiveName in surplusOrder {
            let bucketEntries = surplusByArchive[archiveName] ?? []
            // jensyleo's own question (2026-08-04, Merged mode): a clone
            // excluded from `dat.games` entirely (folded into its parent —
            // e.g. `sf2acca.zip`, a real archive `allMachineNames` now
            // correctly protects from cross-game theft, but which still
            // has no `dat.games` entry of its own to fold this bucket
            // into) reads as gray "Unknown game" even when every single
            // one of its own entries is fully identified as belonging to
            // a real game elsewhere (`requiredByGameDescription` — see its
            // own doc comment). Gray/"Unknown" should mean genuinely no
            // idea what this is; this archive's content is the opposite
            // of that, so it reads yellow/`.incorrect` instead, same as
            // the individual per-file rows already do — never both a
            // gray game-level row and yellow file-level rows for the
            // identical, fully-known content.
            // `.unverifiable` counts as identified too, alongside a real
            // `requiredByGameDescription` — real case found live by jensyleo
            // (2026-08-04): `gryzor.zip` under Merged has every one of its
            // roms accounted for either way (most "not needed here", one a
            // recognized nodump placeholder duplicate — see
            // `SurplusFile.matchesNodumpRomName`'s own doc comment), with
            // nothing genuinely unknown left in it at all.
            let isFullyIdentified = !bucketEntries.isEmpty && bucketEntries.allSatisfy { $0.requiredByGameDescription != nil || $0.status == .unverifiable }
            roots.append(
                GameNode(
                    id: "surplus-\(archiveName)",
                    name: archiveName,
                    entries: bucketEntries,
                    aggregateStatus: isFullyIdentified ? .incorrect : .surplus,
                    isSurplusBucket: true
                )
            )
        }

        // MAME's own `-listxml` output (and a real DAT generally) already
        // lists machines/games in roughly alphabetical order, but unknown
        // archives were only ever appended at the end — sorting the
        // combined list interleaves them where they'd actually sit
        // alphabetically, matching the reference scanner view.
        return roots.sorted {
            ($0.actualFileName ?? $0.name).localizedCaseInsensitiveCompare($1.actualFileName ?? $1.name) == .orderedAscending
        }
    }

    /// Builds a "Database" category's real tree children — lazily,
    /// only when that category is actually expanded (see
    /// `databaseCategoryChildrenCache`). Reuses the exact same
    /// category-filter (`categoryFiltered(_:matching:)`) and game-grouping
    /// (`gameNodes(from:)`)/unscanned-catalog (`unscannedCatalogNodes
    /// (matching:)`) logic the Games table itself already uses for
    /// whichever category happens to be *currently selected* — this just
    /// runs that same logic for an arbitrary category, so a collapsed
    /// category never costs anything and an expanded one shows exactly
    /// what selecting it would show in the Games table.
    ///
    /// Only "All games" gets real parent/clone nesting — a clone's own row
    /// nests under its parent's, RomCenter-style, matching the reference
    /// screenshots this feature was designed from. Every other category
    /// (including "Clones" itself) stays a flat list of siblings — jensyleo's
    /// own call (2026-07-28): "Clones" already means "just the clones",
    /// nesting them under parents that aren't even in that same category
    /// wouldn't make sense.
    /// Drops every category's cached tree children and recomputes only the
    /// ones actually expanded right now — called whenever the underlying
    /// audit data changes (status filters, a new scan). A *collapsed*
    /// category's cache just clears and stays empty until next expanded
    /// (cheap, correct); a category the user is actively looking at gets
    /// refreshed immediately instead of silently going blank until they
    /// collapse and re-expand it by hand.
    private func refreshExpandedDatabaseCategoryCaches() {
        var refreshed: [DatabaseFilter: [DatabaseTreeNode]] = [:]
        for filter in expandedDatabaseCategories {
            refreshed[filter] = treeChildren(forCategory: filter)
        }
        databaseCategoryChildrenCache = refreshed
    }

    /// Synchronous convenience for the sites where only the *display*
    /// filter (`activeStatusFilters`/`showUnknownArchives`/`combineRomAndCHD`)
    /// just changed, not the underlying scope itself — still recomputes
    /// the full base node list (cheaper than the `selectedRomFolder` path
    /// tends to be reported as sluggish, but the same real work either
    /// way), just without the folder/counts side effects that don't
    /// actually change here.
    private func recomputeGameNodes() {
        let baseNodes = Self.computeBaseGameNodes(
            hasAuditReport: viewModel.auditReport != nil, auditEntries: viewModel.auditReport?.entries ?? [],
            selectedRomFolder: selectedRomFolder, preloadedGames: viewModel.preloadedGames, selectedDatabaseFilter: selectedDatabaseFilter,
            gamesInFolder: cachedGamesInFolder, gameAggregateStatusByName: gameAggregateStatusByName, combineRomAndCHD: combineRomAndCHD
        )
        cachedGameNodes = Self.computeGameNodes(baseNodes: baseNodes, gameAggregateStatusByName: gameAggregateStatusByName, showUnknownArchives: showUnknownArchives, activeStatusFilters: activeStatusFilters)
    }

    /// Synchronous convenience for the sites where the underlying scope
    /// itself just changed (`selectedDatabaseFilter`, a fresh
    /// `viewModel.auditReport`, first appearance) — recomputes everything
    /// `recomputeGameNodes()` does, plus `cachedGamesInFolder`,
    /// `cachedScopedStatusCounts`, and `cachedUnknownArchivesCount`. Kept
    /// synchronous (unlike `selectedRomFolder`'s own `Task.detached` path)
    /// since none of these three sites were the one jensyleo actually
    /// reported freezing — see `.onChange(of: selectedRomFolder)`'s own
    /// doc comment for why that one specifically needed to move off the
    /// main thread.
    private func recomputeCachedGameDataSync() {
        cachedGamesInFolder = Self.recomputeGamesInFolder(entries: viewModel.auditReport?.entries ?? [], selectedFolder: selectedRomFolder)
        let baseNodes = Self.computeBaseGameNodes(
            hasAuditReport: viewModel.auditReport != nil, auditEntries: viewModel.auditReport?.entries ?? [],
            selectedRomFolder: selectedRomFolder, preloadedGames: viewModel.preloadedGames, selectedDatabaseFilter: selectedDatabaseFilter,
            gamesInFolder: cachedGamesInFolder, gameAggregateStatusByName: gameAggregateStatusByName, combineRomAndCHD: combineRomAndCHD
        )
        cachedGameNodes = Self.computeGameNodes(baseNodes: baseNodes, gameAggregateStatusByName: gameAggregateStatusByName, showUnknownArchives: showUnknownArchives, activeStatusFilters: activeStatusFilters)
        cachedScopedStatusCounts = Self.computeScopedStatusCounts(scopedEntries: scopedEntries, gamesByName: Self.gamesByName(viewModel.preloadedGames))
        cachedUnknownArchivesCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
    }

    /// Hard cap on how many top-level rows a single category ever renders
    /// inline in the tree — a real, serious bug found live (2026-07-28):
    /// unlike the Games `Table` on the right (already virtualized for
    /// large row counts), a `List` row's `DisclosureGroup` content isn't
    /// lazily virtualized by SwiftUI at all — expanding (or, worse,
    /// *invalidating* an already-expanded category's cache, which rebuilds
    /// its entire `ForEach` from scratch) with tens of thousands of real
    /// rows (a full MAME DAT's "All games" is ~43,000 games) pegged one
    /// core at 100% for minutes, reading as a full app hang/crash. Capping
    /// at a number SwiftUI can actually render instantly, with a plain
    /// "…and N more" notice instead of the rest, is what keeps this
    /// feature safe at MAME's real scale — the Games table (already
    /// scoped to the same category, already handles arbitrarily large
    /// counts) is still there for the full list.
    private static let maxTreeChildrenPerCategory = 200

    private func treeChildren(forCategory filter: DatabaseFilter) -> [DatabaseTreeNode] {
        let nodes: [GameNode]
        if viewModel.auditReport == nil, selectedRomFolder == nil, !viewModel.preloadedGames.isEmpty {
            nodes = Self.unscannedCatalogNodes(matching: filter, preloadedGames: viewModel.preloadedGames)
        } else {
            // Grouped from every entry in this category (not status-
            // filtered — a game's real category must never depend on
            // which rows happen to be visible elsewhere), then the four
            // toggles filter the resulting *games* by that true category.
            // See `statusSummary`'s own doc comment for exactly what each
            // of the four means.
            nodes = Self.gameNodes(
                from: Self.categoryFiltered(viewModel.auditReport?.entries ?? [], matching: filter),
                gamesByName: Self.gamesByName(viewModel.preloadedGames),
                gameAggregateStatusByName: gameAggregateStatusByName, combineRomAndCHD: combineRomAndCHD,
                // This is the "Database" sidebar tree specifically — always
                // the database-wide view, regardless of whatever "Rom
                // files" folder happens to be selected elsewhere right now.
                isFolderScoped: false
            )
            .filter { node in
                    // A surplus bucket `gameNodes(from:)` reclassified
                    // yellow (`.incorrect`, fully identified elsewhere —
                    // see its own `isFullyIdentified` doc comment) is
                    // controlled by that color's own "Incorrect" toggle,
                    // same as every other yellow row — jensyleo's own
                    // question (2026-08-04): only a *genuinely*
                    // unrecognized bucket (`.surplus`) belongs to the
                    // separate "Unknown" toggle at all.
                    if node.isSurplusBucket {
                        return node.aggregateStatus == .surplus ? showUnknownArchives : activeStatusFilters.contains(node.aggregateStatus ?? .surplus)
                    }
                    guard let category = gameAggregateStatusByName[node.name] ?? node.aggregateStatus else { return true }
                    return activeStatusFilters.contains(category)
                }
        }
        let realGames = nodes.filter { !$0.isSurplusBucket }

        guard filter == .allGames else {
            let sorted = realGames.sorted { $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending }
            return capped(sorted.map { leafNode(for: $0) })
        }

        var clonesByParent: [String: [GameNode]] = [:]
        var roots: [GameNode] = []
        let namesPresent = Set(realGames.map(\.name))
        for node in realGames {
            // A clone whose declared parent isn't itself present in this
            // same node list (e.g. the parent's own archive was filtered
            // out, or simply isn't part of this DAT/scan for some reason)
            // surfaces as its own top-level root instead of silently
            // disappearing — every real game still shows up somewhere.
            if !node.cloneOf.isEmpty, namesPresent.contains(node.cloneOf) {
                clonesByParent[node.cloneOf, default: []].append(node)
            } else {
                roots.append(node)
            }
        }

        let sortedRoots = roots.sorted { $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending }
        let cappedRoots = Array(sortedRoots.prefix(Self.maxTreeChildrenPerCategory))
        var result = cappedRoots.map { root -> DatabaseTreeNode in
            let clones = (clonesByParent[root.name] ?? [])
                .sorted { $0.gameName.localizedCaseInsensitiveCompare($1.gameName) == .orderedAscending }
            // Clone children are capped too — a parent with an unusually
            // large clone family (rare, but the same runaway-row risk
            // applies) shouldn't be able to bypass the cap either.
            return leafNode(for: root, children: capped(clones.map { leafNode(for: $0) }))
        }
        if sortedRoots.count > cappedRoots.count {
            result.append(truncationNotice(shown: cappedRoots.count, total: sortedRoots.count))
        }
        return result
    }

    /// Truncates to `maxTreeChildrenPerCategory`, appending a plain,
    /// non-selectable notice row when anything was actually cut — an empty
    /// `children` array here (rather than this whole function returning
    /// early) is the correct "nothing to show" case, not an error.
    private func capped(_ nodes: [DatabaseTreeNode]) -> [DatabaseTreeNode] {
        guard nodes.count > Self.maxTreeChildrenPerCategory else { return nodes }
        var result = Array(nodes.prefix(Self.maxTreeChildrenPerCategory))
        result.append(truncationNotice(shown: result.count, total: nodes.count))
        return result
    }

    private func truncationNotice(shown: Int, total: Int) -> DatabaseTreeNode {
        DatabaseTreeNode(
            id: "truncated-\(shown)-of-\(total)",
            machineName: "",
            label: "…and \(total - shown) more — use the Games table for the full list",
            status: nil,
            children: nil,
            isTruncationNotice: true
        )
    }

    private func leafNode(for game: GameNode, children: [DatabaseTreeNode]? = nil) -> DatabaseTreeNode {
        DatabaseTreeNode(id: game.id, machineName: game.name, label: game.gameName, status: game.aggregateStatus, children: children)
    }

    /// Expands/collapses a "Database" category in place — computing its
    /// children on first expand only (see `databaseCategoryChildrenCache`'s
    /// own doc comment for why this stays lazy).
    private func databaseCategoryExpansion(for filter: DatabaseFilter) -> Binding<Bool> {
        Binding(
            get: { expandedDatabaseCategories.contains(filter) },
            set: { isExpanded in
                if isExpanded {
                    expandedDatabaseCategories.insert(filter)
                    if databaseCategoryChildrenCache[filter] == nil {
                        databaseCategoryChildrenCache[filter] = treeChildren(forCategory: filter)
                    }
                } else {
                    expandedDatabaseCategories.remove(filter)
                }
            }
        )
    }

    /// One row of a "Database" category's expandable tree — recursive,
    /// since a parent game (under "All games" specifically) has its own
    /// clone children nested one level further. A leaf (no children)
    /// selects that exact game in the Games table on the right; a parent's
    /// own row does the same *and* can still be expanded/collapsed to show
    /// its clones.
    // Erased to `AnyView`: this calls itself for a parent's own clone
    // children, and Swift can't infer a recursive `some View` (it would be
    // defining the opaque type in terms of itself) — only actually
    // recurses one level deep in practice (parent → clone), so the type-
    // erasure cost here is negligible.
    private func databaseTreeNodeRow(_ node: DatabaseTreeNode, filter: DatabaseFilter) -> AnyView {
        guard let children = node.children, !children.isEmpty else {
            return AnyView(databaseTreeLeafLabel(node, filter: filter))
        }
        return AnyView(
            DisclosureGroup {
                ForEach(children) { child in databaseTreeNodeRow(child, filter: filter) }
            } label: {
                databaseTreeLeafLabel(node, filter: filter)
            }
        )
    }

    @ViewBuilder
    private func databaseTreeLeafLabel(_ node: DatabaseTreeNode, filter: DatabaseFilter) -> some View {
        if node.isTruncationNotice {
            Text(node.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let isSelected = selectedDatabaseFilter == filter && selectedGameID == node.id
            // Always the live status from `gameAggregateStatusByName`
            // (falling back to the node's own cached one only for a game
            // not found there at all, e.g. a not-yet-scanned catalog
            // entry) — never the tree's own possibly-stale cached
            // `node.status` directly. See `gameAggregateStatusByName`'s
            // own doc comment for the real bug this guards against.
            let liveStatus = gameAggregateStatusByName[node.machineName] ?? node.status
            Button {
                selectedDatabaseFilter = filter
                selectedRomFolder = nil
                selectedGameID = node.id
            } label: {
                HStack(spacing: 4) {
                    // Always a real game here — `treeChildren(forCategory:)`
                    // excludes the synthetic "Unknown game" bucket before
                    // building tree leaves at all.
                    if let status = liveStatus {
                        Image(systemName: symbolName(for: status)).foregroundStyle(tint(for: status))
                    } else {
                        Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                    }
                    Text(node.label)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// The full, *unfiltered* node list for the current scope — before the
    /// `showUnknownArchives`/`activeStatusFilters` toggles apply. Kept as
    /// its own step (rather than folded into `computeGameNodes(baseNodes:...)`
    /// below) so `computeUnknownArchivesCount(baseNodes:)` can share this
    /// exact same pass instead of recomputing `gameNodes(from:)` a second
    /// time over the same entries. `static` — see this file's own
    /// `.onChange(of: selectedRomFolder)` doc comment: this, and everything
    /// it calls, must stay free of any direct `@State` access so it can run
    /// off the main thread on a large collection.
    private nonisolated static func computeBaseGameNodes(
        hasAuditReport: Bool, auditEntries: [AuditEntry], selectedRomFolder: URL?, preloadedGames: [DATGame], selectedDatabaseFilter: DatabaseFilter?,
        gamesInFolder: Set<String>, gameAggregateStatusByName: [String: AuditStatus], combineRomAndCHD: Bool
    ) -> [GameNode] {
        if !hasAuditReport, selectedRomFolder == nil, !preloadedGames.isEmpty {
            return unscannedCatalogNodes(matching: selectedDatabaseFilter ?? .allGames, preloadedGames: preloadedGames)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return gameNodes(
            from: scoped(auditEntries, databaseFilter: selectedDatabaseFilter, romFolder: selectedRomFolder, gamesInFolder: gamesInFolder),
            gamesByName: gamesByName(preloadedGames),
            gameAggregateStatusByName: gameAggregateStatusByName, combineRomAndCHD: combineRomAndCHD,
            isFolderScoped: selectedRomFolder != nil
        )
    }

    /// The loaded DAT's own real game catalog, by lowercased name — see
    /// `gameNodes(from:)`'s own doc comment for why this (not anything
    /// derived from scan *results*) is the right source for "does a real
    /// game exist with this name at all". First-wins on a name collision,
    /// which a real DAT should never have (machine names are its own
    /// primary key) — a plain loop rather than `Dictionary(uniqueKeysWithValues:)`
    /// only so a malformed DAT can never crash this instead of just picking
    /// one arbitrarily.
    private nonisolated static func gamesByName(_ games: [DATGame]) -> [String: DATGame] {
        var result: [String: DATGame] = [:]
        for game in games where result[game.name.lowercased()] == nil {
            result[game.name.lowercased()] = game
        }
        return result
    }

    /// Applies the `showUnknownArchives`/`activeStatusFilters` toggles to
    /// `computeBaseGameNodes(...)`'s result — a separate step (not fused
    /// into it) for the same reason as `computeUnknownArchivesCount(baseNodes:)`
    /// above: both need that same unfiltered pass, just filtered
    /// differently afterward.
    private nonisolated static func computeGameNodes(baseNodes: [GameNode], gameAggregateStatusByName: [String: AuditStatus], showUnknownArchives: Bool, activeStatusFilters: Set<AuditStatus>) -> [GameNode] {
        // Grouped from *every* entry (not status-filtered — a game's real
        // category must never depend on which rows happen to be visible
        // elsewhere), then the four toggles filter the resulting *games*
        // by that true category. See `statusSummary`'s own doc comment
        // for exactly what each of the four means.
        baseNodes.filter { node in
            // A genuinely unrecognized archive ("Unknown game") isn't one
            // of the four real categories at all — it always shows,
            // independent of any toggle (see `computeScopedStatusCounts()`'s
            // own doc comment for why it isn't counted under "Bad" either).
            // A surplus bucket `gameNodes(from:)` reclassified yellow
            // instead (`.incorrect`, fully identified elsewhere — see its
            // own `isFullyIdentified` doc comment) is controlled by that
            // color's own "Incorrect" toggle — jensyleo's own question
            // (2026-08-04): only a genuinely unrecognized bucket belongs
            // to the separate "Unknown" toggle at all.
            if node.isSurplusBucket {
                return node.aggregateStatus == .surplus ? showUnknownArchives : activeStatusFilters.contains(node.aggregateStatus ?? .surplus)
            }
            guard let category = gameAggregateStatusByName[node.name] ?? node.aggregateStatus else { return true }
            return activeStatusFilters.contains(category)
        }
    }

    /// A game's true category — jensyleo's own confirmed definitions and
    /// priority (2026-08-04, superseding the 2026-07-30 ones):
    /// - `.missing`: at least one rom is genuinely absent — outranks
    ///   everything else, since nothing else matters if the game can't
    ///   even run.
    /// - `.badDump` ("Bad"): no missing rom, but at least one rom's local
    ///   file has a hash that doesn't match the DAT's declared CRC32/MD5/
    ///   SHA — a real content problem.
    /// - `.incorrect`: no missing/badDump rom, but at least one rom is
    ///   misnamed or `.foundElsewhere` — a naming/location problem, not a
    ///   content one.
    /// - `.correct`: none of the above.
    /// A stray unclaimed file folded into this game's own row (`.surplus`,
    /// e.g. an extra file physically inside its archive) doesn't affect
    /// this at all — informational only (see `infoText(for:)`'s "Extra
    /// file in archive"), never severe enough to outrank a real rom
    /// status.
    private nonisolated static func gameCategory(for entries: [AuditEntry]) -> AuditStatus {
        // `isOptional` excluded from this check — the DAT's own
        // `optional="yes"` attribute (MAME's own DTD) means MAME can run
        // the machine without this specific rom/disk at all, so its
        // absence shouldn't force the whole game red the way a genuinely
        // required absence does. Real case found live by jensyleo
        // (2026-08-05): none of the 3 real optional `<disk>` entries in a
        // real MAME 0.288 dump are missing/badDump otherwise, so this
        // hasn't been exercised against real absence yet — the reasoning
        // mirrors `.unverifiable`'s own non-severe tier below.
        if entries.contains(where: { $0.status == .missing && !$0.isOptional }) { return .missing }
        if entries.contains(where: { $0.status == .badDump }) { return .badDump }
        if entries.contains(where: { $0.status == .incorrect }) { return .incorrect }
        if entries.contains(where: { $0.status == .correct }) { return .correct }
        // Real case found live by jensyleo (2026-08-04): a game whose ONLY
        // disk is a `<disk>` the DAT declares with no sha1 at all (undumped
        // media — `CHDDiskStatus.unverifiable`'s own doc comment) has no
        // `.correct` entry to fall back on the way a rom aggregate almost
        // always does (a stray `.unverifiable` rom sitting alongside dozens
        // of genuinely `.correct` ones). Silently reporting "Correct" here
        // would claim something was actually verified when nothing was —
        // surfaced as its own status instead, same non-severe tier as
        // `.surplus` (never outranks missing/badDump/incorrect above), just
        // not silently swallowed into a false "Correct" when it's all
        // there is.
        if entries.contains(where: { $0.status == .unverifiable }) { return .unverifiable }
        return .correct
    }

    /// A game's headline status reflects its own roms, not its CHD disk —
    /// jensyleo's own report (2026-07-30): a correct CHD was getting
    /// dragged down to an overall "Bad" by a rom the user has no interest
    /// in owning, because the two used to be folded into one worst-of-all
    /// verdict (`gameCategory(for:)` given a mixed rom+disk array). The
    /// disk's own row still carries its own real, independent status
    /// (`DiskAuditor`'s own entries, `isDisk`); only the *per-game rollup
    /// badge/count* (tree icon, header status, filter counts) is rom-only
    /// now. Falls back to the disk-only category for the rare machine that
    /// declares a CHD but no roms at all — there's nothing else to report
    /// a status from in that case.
    private nonisolated static func romOnlyGameCategory(for entries: [AuditEntry]) -> AuditStatus {
        let romEntries = entries.filter { !$0.isDisk }
        return romEntries.isEmpty ? gameCategory(for: entries) : gameCategory(for: romEntries)
    }

    /// Every real game's current true category, by name — see
    /// `gameAggregateStatusByName`'s own doc comment for why this exists.
    /// Deliberately built from *every* entry in the report, not
    /// `filteredEntries` — a game's real category shouldn't change just
    /// because the user hid, say, "Missing" rows from view elsewhere.
    private func computeGameAggregateStatusByName() -> [String: AuditStatus] {
        guard let entries = viewModel.auditReport?.entries else { return [:] }
        var byGame: [String: [AuditEntry]] = [:]
        var surplusByArchive: [String: [AuditEntry]] = [:]
        for entry in entries {
            if let game = entry.game {
                byGame[game, default: []].append(entry)
            } else {
                let archiveName = entry.path?.lastPathComponent ?? entry.name
                surplusByArchive[archiveName, default: []].append(entry)
            }
        }
        // Same fold `gameNodes(from:)` applies before building each row's
        // own entries (see its own doc comment on why a surplus file
        // inside a known game's archive belongs to that game, not a
        // separate "Unknown game") — done here too, not just there, so a
        // folded-in surplus file's status (e.g. a Split-mode clone's zip
        // still holding a rom that's really the parent's — see
        // `AuditEntry.requiredByGameDescription`) affects this game's
        // aggregate identically whether the user is looking at "Database"
        // (which reads straight from this dictionary) or a "Rom files"
        // folder (which re-derives the same fold locally in `gameNodes`).
        // Real bug found live by jensyleo (2026-08-04): without this,
        // reclassifying that exact file from `.surplus` to `.incorrect`
        // would have flipped a game's badge yellow in a folder view while
        // leaving it green in "Database" for the identical underlying
        // fact — the same class of view-disagreement chased all day
        // already, just for a different field.
        // Checked against the DAT's own real catalog (`gamesByName`), not
        // just "does `byGame` already have this key" — real bug found live
        // by jensyleo (2026-08-04, `qsound_hle` under Split): a real game
        // whose entire expected rom list is empty under the current merge
        // mode (its only rom `merge=`-tagged away entirely) never gets a
        // `byGame` key from real entries at all, so a stray file inside its
        // own archive failed this check too and never got folded in here
        // either — see `gameNodes(from:)`'s own doc comment for the fuller
        // story (this must fold identically to there, or "Database" and a
        // "Rom files" folder view disagree on this exact game).
        let gamesByName = Self.gamesByName(viewModel.preloadedGames)
        for (archiveName, surplus) in surplusByArchive {
            let matchingGame = (archiveName as NSString).deletingPathExtension
            guard gamesByName[matchingGame] != nil else { continue }
            byGame[matchingGame, default: []].append(contentsOf: surplus)
        }
        return byGame.mapValues(Self.romOnlyGameCategory(for:))
    }

    private var selectedGameNode: GameNode? {
        guard let selectedGameID else { return nil }
        return cachedGameNodes.first { $0.id == selectedGameID }
    }

    // MARK: - "Play in MAME"

    /// Deliberately *not* gated on the currently-loaded DAT's own header
    /// (`viewModel.datHeader?.name == "MAME"`, this feature's first cut) —
    /// jensyleo's own call: treat every configured system as MAME for this
    /// feature, full stop, rather than depending on transient DAT-load
    /// state that isn't always populated by the time it matters. If more
    /// than one system/DAT happens to be MAME, the same "Play" action
    /// applies to all of them uniformly, with no per-system distinction.
    /// A non-MAME system's game name simply won't resolve as a machine —
    /// MAME's own error surfaces that, same as an incorrect/missing set
    /// already does; no need for ROMForge to guess ahead of time.
    ///
    /// A synthetic "Unknown game"/"Surplus files" row has no real DAT
    /// machine behind it — nothing for MAME to actually launch.
    private func canLaunchMAME(_ node: GameNode) -> Bool {
        !node.isSurplusBucket && MAMELaunchSettings.executablePath != nil
    }

    private var canLaunchSelectedGameInMAME: Bool {
        selectedGameNode.map(canLaunchMAME) ?? false
    }

    private var playButtonHelpText: String {
        guard MAMELaunchSettings.executablePath != nil else { return "Locate a MAME executable in Settings → Systems first" }
        guard let node = selectedGameNode, !node.isSurplusBucket else { return "Select a game to play it in MAME" }
        return "Launch \(node.gameName) in MAME to test it"
    }

    private func launchSelectedGameInMAME() {
        guard let node = selectedGameNode else { return }
        launchInMAME(node)
    }

    private func launchInMAME(_ node: GameNode) {
        do {
            try MAMELauncher.launch(machineName: node.name, romFolders: system.romFolderURLs) { reason in
                // MAME's own termination handler fires on a background
                // queue, not the main actor `errorMessage` needs to be
                // touched from.
                Task { @MainActor in
                    viewModel.errorMessage = "MAME couldn't run \(node.gameName):\n\n\(reason)"
                }
            }
        } catch let error as MAMELauncher.LaunchError {
            viewModel.errorMessage = error.description
        } catch {
            viewModel.errorMessage = "Failed to launch MAME: \(error.localizedDescription)"
        }
    }

    private var selectedRomRows: [RomRow] {
        (selectedGameNode?.entries ?? []).map { entry in
            RomRow(id: "rom-\(entry.path?.path ?? "")-\(entry.name)-\(entry.game ?? "")", entry: entry)
        }
    }

    private var selectedEntry: AuditEntry? {
        guard let selectedRomID else { return nil }
        return selectedRomRows.first { $0.id == selectedRomID }?.entry
    }

    // MARK: - Detail pane

    /// Two independent sections, shown together whenever both apply: the
    /// selected *game*'s own DAT metadata (year, manufacturer, clone-of,
    /// BIOS/CHD/samples, etc. — everything the DAT declares about the game
    /// itself, not about any one file), and the selected *rom*'s technical
    /// file-level detail (path, hashes) — kept exactly as it was, just
    /// alongside the new game section rather than replacing it. Selecting a
    /// game alone (no rom row yet) still shows something useful instead of
    /// staying blank until a specific rom is picked.
    private var detailPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if let node = selectedGameNode {
                    gameDetailSection(node)
                }
                if let entry = selectedEntry {
                    if selectedGameNode != nil { Divider() }
                    romDetailSection(entry)
                }
                if selectedGameNode == nil && selectedEntry == nil {
                    Text("Select a game to see its details.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    }

    /// Everything the DAT itself declares about the selected game — pulled
    /// from `AuditEntry`'s game-level fields (nil/empty ones are simply
    /// skipped via `infoRow`, since not every DAT/game declares all of
    /// these). Today this is only ever what the loaded DAT already
    /// contains; **future work**: fetch richer metadata (real title,
    /// screenshots, description) from the internet for games the DAT
    /// itself is silent on, caching it locally so it doesn't need
    /// re-fetching on every scan (see TODO.md).
    private func gameDetailSection(_ node: GameNode) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(node.gameName).font(.headline)
            infoRow("Internal name", node.name)
            infoRow("Clone of", node.cloneOf)
            infoRow("Year", node.year)
            infoRow("Manufacturer", node.manufacturer)
            infoRow("BIOS set", node.biosText)
            infoRow("CHD", node.chdNames)
            infoRow("Samples", node.samplesText)
            infoRow("Required BIOS", node.requiredBiosNames)
            infoRow("Device refs", node.deviceRefNames)
            infoRow("Status", node.infoText)
        }
    }

    private func romDetailSection(_ entry: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.name).font(.headline)
            if let game = entry.game {
                Text("Game: \(game)")
            }
            if let cloneOf = entry.cloneOf {
                Text("Clone of: \(cloneOf)")
                    .foregroundStyle(.secondary)
            }
            Text("DAT: \(viewModel.datHeader?.name ?? system.name)")
            Text("Path: \(entry.path?.path ?? "—")")
                .foregroundStyle(.secondary)
            hashLine(label: "CRC32", expected: entry.expectedCRC, actual: entry.actualCRC)
            hashLine(label: "MD5", expected: entry.expectedMD5, actual: entry.actualMD5)
            hashLine(label: "SHA1", expected: entry.expectedSHA1, actual: entry.actualSHA1)
        }
    }

    /// One labeled line of game metadata — skipped entirely when `value`
    /// is empty, so a game whose DAT declares no year/manufacturer/etc.
    /// doesn't show a wall of blank fields.
    private func infoRow(_ label: String, _ value: String) -> some View {
        Group {
            if !value.isEmpty {
                HStack(spacing: 8) {
                    Text(label).bold().frame(width: 100, alignment: .leading)
                    Text(value)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func hashLine(label: String, expected: String?, actual: String?) -> some View {
        // A matched rom's declared hashes always equal its file's computed
        // hashes (the Matcher wouldn't have matched it otherwise), and a
        // missing/surplus entry always has one side nil — so there's no
        // "mismatch" case to highlight here, only "what the DAT expects" vs.
        // "what's on disk, if anything."
        HStack(spacing: 8) {
            Text(label).bold().frame(width: 50, alignment: .leading)
            Text("expected: \(expected ?? "—")")
            Text("actual: \(actual ?? "—")")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// `.surplus` here means a genuinely *unrecognized* row — a real
    /// surplus rom entry, or the synthetic "Unknown game"/unclaimed-
    /// archive bucket — gray, denoting "this doesn't match anything known
    /// at all", not a severity judgment. `gameCategory(for:)` never
    /// returns `.surplus` (it returns `.badDump` directly for a real
    /// game's content problem — orange, distinct from this gray), so this
    /// same function is shared by both individual rom rows and a game's
    /// own aggregate row icon without needing a separate variant.
    private func symbolName(for status: AuditStatus) -> String {
        switch status {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "exclamationmark.triangle.fill"
        case .badDump: return "exclamationmark.octagon.fill"
        case .missing: return "xmark.circle.fill"
        case .surplus: return "questionmark.circle.fill"
        // A distinct icon from `.surplus`'s plain "?" — this content IS
        // known/documented (a DAT-declared `nodump` rom's name), just
        // unverifiable, not genuinely unidentified.
        case .unverifiable: return "questionmark.circle"
        }
    }

    private func tint(for status: AuditStatus) -> Color {
        switch status {
        case .correct: return .green
        case .incorrect: return .yellow
        case .badDump: return .orange
        case .missing: return .red
        case .surplus, .unverifiable: return .gray
        }
    }
}
