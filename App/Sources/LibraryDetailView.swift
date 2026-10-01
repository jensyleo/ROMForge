import AppKit
import ROMForgeCore
import SwiftUI
import UniformTypeIdentifiers

/// One row of the games tree: a game (parent or clone — clones nest under
/// their parent) or the synthetic "Surplus files" bucket. RomCenter shows a
/// game list on the left and that game's own ROM files on the right instead
/// of mixing both levels into one tree — `entries` holds this node's own
/// ROMs for that right-hand pane.
/// `AuditEntry` isn't `Identifiable` (Core has no UI concerns), so the flat
/// ROM table on the right wraps each one with the same id scheme used
/// elsewhere to look an entry back up from a selection.
// Widened from `private` to internal (2026-09-14, pure-extraction refactor:
// see `GameTreeTableView`/`RomsTableView`) so the Roms table, now its own
// standalone `View` in `RomsTableView.swift`, can reference it — `private`
// at file scope behaves like `fileprivate` in Swift (visible everywhere in
// THIS file already), so this only ever widens visibility to other files in
// the same target, never narrows anything that used to be enforced.
struct RomRow: Identifiable {
    let id: String
    let entry: AuditEntry
}


/// `GameNode` itself now lives in ROMForgeCore (2026-08-13, "Grupo B" of
/// the App-logic extraction) — it never had any SwiftUI dependency, it
/// was just declared in this View file. This alias keeps every existing
/// call site below (`GameNode(...)`, `.isSurplusBucket`, `.infoText`, etc.)
/// unchanged.
// Widened from `private` for the same reason as `RomRow` above — needed by
// `GameTreeTableView.swift`/`RomsTableView.swift`.
typealias GameNode = ROMForgeCore.GameNode

/// RomCenter's "Database" tree: predefined categories over the same audit,
/// shown above the games list. "Games with CHD" and "Games with samples"
/// are presence-only (does the DAT declare a disk/sample for this game),
/// not verification — ROMForge doesn't check a `.chd` file's contents or a
/// sample's presence on disk yet, that's still its own future milestone
/// (see ROADMAP.md). "Games with bad dumps" reflects the DAT's own
/// `status="baddump"/"nodump"` claim about the reference dump, independent
/// of what's found locally.
/// Not `private` — `DatabaseFilterVisibilitySettings` (in
/// `GeneralSettingsView.swift`) needs to enumerate every case to build its
/// per-branch toggle list, and `LibraryDetailView` itself needs to read
/// that setting back to decide which cases `ForEach(DatabaseFilter.allCases)`
/// (in `databaseListContent`) actually shows.
enum DatabaseFilter: String, CaseIterable, Identifiable {
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
    /// jensyleo's own report (2026-08-13): "la base de datos no tiene una
    /// rama para los nodump" — `.gamesWithBadDumps` above collapses BOTH
    /// `baddump` and `nodump` into one branch, so a real "no reference hash
    /// exists at all" game had no branch of its own, mixed in with genuine
    /// bad dumps. See `DatabaseCategory.gamesWithNodump`'s own doc comment
    /// (ROMForgeCore) for the actual filtering distinction.
    case gamesWithNodump = "Games with nodump"
    /// Two RomCenter-style regroupings of the *same* full game list, not a
    /// new subset — jensyleo's own request (2026-08-11): "fabricante y
    /// aparte fecha". Clicking either still scopes the Games table to every
    /// game (same as "All games"), but the tree groups that list by
    /// `<manufacturer>`/`<year>` instead of nesting clones under parents —
    /// see `computeTreeChildren(forCategory:...)`'s own dedicated branch
    /// for these two.
    case byManufacturer = "By manufacturer"
    case byYear = "By year"
    /// Four more branches added the same day, all reusing scan-result
    /// fields `AuditReporter` already computes — jensyleo's own request
    /// (2026-08-11): "coloca todas las que se puedan" once the Settings
    /// visibility toggle existed to make adding more branches safe (each
    /// one the user doesn't actually want just gets switched off, rather
    /// than permanently cluttering the tree). Off by default — see
    /// `DatabaseFilterVisibilitySettings.defaultEnabled`'s own doc comment
    /// for why only these four start disabled.
    case missingGames = "Missing games"
    case incorrectGames = "Incorrect games"
    case gamesRequiringBIOS = "Games requiring BIOS"
    case gamesWithDeviceRefs = "Games with device refs"
    /// RomVault-style set-completeness, one game per bucket — see
    /// `GameCompletionStatus`'s own doc comment for the exact taxonomy and
    /// why it's a different axis from `.missingGames`/`.incorrectGames`
    /// above (those are per-ROM; these are a single verdict per game).
    /// jensyleo's own request (2026-08-13): distinguish "just rename it"
    /// (`fixableGames`) from "actually needs new content"
    /// (`partialGames`/`emptyGames`) at a glance. Scan-result-only, same
    /// as `.verifiedGames`.
    case completeGames = "Complete games"
    case fixableGames = "Fixable games"
    case partialGames = "Partial games"
    case emptyGames = "Empty games"
    /// A physically-present BIOS archive nothing currently in the
    /// collection actually depends on — see `DatabaseCategory
    /// .unusedBiosFiles`/`OrphanedBIOSDetector` (ROMForgeCore) for how it's
    /// computed, and why samples aren't included (no sample-file scanning
    /// exists yet to check one against). Off by default, same as every
    /// other post-2026-08-11 addition below `.emptyGames`.
    case unusedBiosFiles = "Unused BIOS files"
    /// See `DatabaseCategory.filenameCRCMismatches`/`zipCRCInconsistencies`
    /// (ROMForgeCore) for what each actually checks. Off by default, same as
    /// every other post-2026-08-11 addition below `.emptyGames`.
    case filenameCRCMismatches = "Filename CRC mismatches"
    case zipCRCInconsistencies = "ZIP internal CRC inconsistencies"
    /// See `DatabaseCategory.deviceMachines` (ROMForgeCore) for what this
    /// actually separates out — MAME's own internal shared CPU/sound-chip
    /// sub-machines, not real playable games. Off by default, same as every
    /// other post-2026-08-11 addition below `.emptyGames`.
    case deviceMachines = "Device machines"
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
        case .gamesWithNodump: return "questionmark.diamond.fill"
        case .byManufacturer: return "building.2"
        case .byYear: return "calendar"
        case .missingGames: return "questionmark.folder"
        case .incorrectGames: return "pencil.and.outline"
        case .gamesRequiringBIOS: return "cpu"
        case .gamesWithDeviceRefs: return "puzzlepiece"
        case .completeGames: return "checkmark.circle.fill"
        case .fixableGames: return "arrow.triangle.2.circlepath"
        case .partialGames: return "circle.lefthalf.filled"
        case .emptyGames: return "circle.dashed"
        case .unusedBiosFiles: return "archivebox"
        case .filenameCRCMismatches: return "questionmark.text.page"
        case .zipCRCInconsistencies: return "checkmark.shield"
        case .deviceMachines: return "cpu.fill"
        }
    }

    /// Maps 1:1 to `DatabaseCategory` (ROMForgeCore) — the actual
    /// filtering logic now lives there (`categoryFiltered(_:matching:)`
    /// below), so `DatabaseFilter` itself only carries this enum's own
    /// SwiftUI-facing concerns (raw display name, `symbolName`). An
    /// exhaustive switch rather than `DatabaseCategory(rawValue:
    /// rawValue)!` — both enums' raw values are kept identical on purpose,
    /// but a force-unwrap would crash instead of failing to compile if
    /// they ever drifted apart.
    var coreCategory: DatabaseCategory {
        switch self {
        case .allGames: return .allGames
        case .verifiedGames: return .verifiedGames
        case .originals: return .originals
        case .clones: return .clones
        case .biosFiles: return .biosFiles
        case .gamesWithCHD: return .gamesWithCHD
        case .gamesWithSamples: return .gamesWithSamples
        case .gamesWithBadDumps: return .gamesWithBadDumps
        case .gamesWithNodump: return .gamesWithNodump
        case .byManufacturer: return .byManufacturer
        case .byYear: return .byYear
        case .missingGames: return .missingGames
        case .incorrectGames: return .incorrectGames
        case .gamesRequiringBIOS: return .gamesRequiringBIOS
        case .gamesWithDeviceRefs: return .gamesWithDeviceRefs
        case .completeGames: return .completeGames
        case .fixableGames: return .fixableGames
        case .partialGames: return .partialGames
        case .emptyGames: return .emptyGames
        case .unusedBiosFiles: return .unusedBiosFiles
        case .filenameCRCMismatches: return .filenameCRCMismatches
        case .zipCRCInconsistencies: return .zipCRCInconsistencies
        case .deviceMachines: return .deviceMachines
        }
    }

    /// Whether this branch reflects a concept only a MAME-format DAT can
    /// ever declare — parent/clone families, a shared BIOS, CHD discs,
    /// samples, or MAME's own internal "device" sub-machines. A plain
    /// console DAT (No-Intro/Redump/TOSEC, all parsed as Logiqx) never
    /// populates any of these — jensyleo's own request (2026-09-23), start
    /// of real NES support: "hay que hacer ajustes en la GUI de tal manera
    /// que lo de MAME no se mezcle con los demás sistemas." Used to build
    /// the Console kind's own, shorter "Database tree branches" toggle list
    /// in Settings → Systems (`ConsoleSettingsForm`) — the MAME kind's own
    /// list is untouched, still every case, exactly as before.
    var isMAMESpecific: Bool {
        switch self {
        case .clones, .biosFiles, .gamesWithCHD, .gamesWithSamples, .gamesRequiringBIOS,
             .gamesWithDeviceRefs, .unusedBiosFiles, .deviceMachines:
            return true
        default:
            return false
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
    /// The DAT's own `<manufacturer>` for this machine — jensyleo's own
    /// request (2026-08-11), RomCenter-style: shown as trailing secondary
    /// text on the leaf row itself, since this tree (unlike the Games
    /// `Table` on the right) has no separate column concept at all. `nil`
    /// for a catalog row with none declared, or for a category header /
    /// truncation-notice row.
    var manufacturer: String?
    var children: [DatabaseTreeNode]?
    /// True only for the synthetic "…and N more" row a category's own
    /// children get capped with (see `treeChildren(forCategory:)`) — a
    /// plain, non-selectable line, not a real game.
    var isTruncationNotice: Bool = false
    /// Set only on a "Show N more" row — the interactive replacement for a
    /// plain `isTruncationNotice` row when no search is active (see
    /// `databaseCategoryVisibleCap`'s own doc comment). Tapping it bumps
    /// that one category's own visible cap by `treeLoadMoreIncrement` and
    /// nothing else — never the whole remaining category at once.
    var loadMoreFilter: DatabaseFilter?
}

/// Per-archive cache for `ZipCommentReader`'s result — a plain reference
/// type, not a SwiftUI `@State`/`@Observable`, so filling it while
/// `infoText(for:)` runs during view-body evaluation never mutates SwiftUI
/// state mid-render. Every rom row belonging to the same zip shares one
/// entry, so a table with hundreds of rows from a handful of archives only
/// ever reads each archive's End of Central Directory record once.
@MainActor
final class ZipCommentCache {
    /// Shared across every system, not just one `LibraryDetailView` —
    /// jensyleo's own report (2026-09-26), same full-session slowness audit
    /// that added `LibraryViewModel.sharedAuditReportCache`: this used to be
    /// a plain `private let zipCommentCache = ZipCommentCache()` stored
    /// property, so it started completely empty again every time
    /// `LibraryDetailView`'s `.id(system.id)` (`ContentView.swift`) tore
    /// down and recreated the view for a system switch — even switching
    /// BACK to a system already fully warmed moments earlier. Every access
    /// here happens on the main actor already (render-path reads, or a
    /// `MainActor.run` block inside a background recompute), so one shared
    /// instance needs no additional synchronization of its own.
    static let shared = ZipCommentCache()

    private var storage: [URL: String?] = [:]

    /// Cache-only — jensyleo's own premise (2026-10-01), applied globally
    /// and enforced strictly here: "Solo consultar la NAS para escaneos y
    /// Fix. Lo demas debe estar en cache." Used to have a live
    /// `ZipCommentReader` fallback for a not-yet-cached URL; removed after
    /// confirming (full codebase audit, 2026-10-01) every caller of
    /// `infoText`/`zipCommentHelpText` renders exclusively from
    /// `cachedGameNodes`/`cachedGameNodesByID`, both of which the two
    /// preload functions (`triggerCachedGameDataRecompute()`,
    /// `refreshCachedGameDataAfterAuditReportChangeAsync()`) always warm
    /// BEFORE reassigning those arrays, atomically within the same
    /// `MainActor.run` block — no orphan render path exists that could ever
    /// need this fallback. Returns `nil` (same as "no comment") for a URL
    /// genuinely not yet cached rather than reading it live — a real row
    /// should never reach this with a cache miss given the above, so this
    /// is effectively unreachable in practice, not a behavior change for
    /// any real screen.
    func comment(forZipAt url: URL) -> String? {
        storage[url] ?? nil
    }

    /// Cache-only read, never a live NAS fallback — jensyleo's own premise
    /// (2026-10-01), applied globally. Used by the Games-table
    /// context-menu's own preview (`GameTreeTableView`'s "Remove Zip
    /// Comments…" item), which only needs to decide whether to OFFER the
    /// action, not compute its exact real count. Returns `false` (not
    /// "maybe") for a not-yet-cached URL — the item simply doesn't show
    /// until the background preload catches up, rather than ever blocking
    /// a menu-open on disk I/O.
    func hasCachedComment(forZipAt url: URL) -> Bool {
        guard let cached = storage[url], let comment = cached else { return false }
        return !comment.isEmpty
    }

    /// Real bug found live by jensyleo (2026-09-22): "Remove Zip
    /// Comment…" reported success (the comment genuinely IS gone from
    /// the file on disk, and a fresh rescan even re-reports the archive
    /// as no longer having one), yet the SAME running session kept
    /// showing "— Has ZIP comment" for it — this cache never had any way
    /// to forget a URL it once read, so every lookup after the first one
    /// silently returned the stale, pre-removal comment forever, no
    /// matter how many times the archive was rescanned or how successful
    /// the removal actually was. Originally cleared entirely (`invalidateAll()`)
    /// whenever the audit report changed; `invalidate(underAnyOf:)` below
    /// replaced every call site once this cache became shared across
    /// systems (2026-09-26) — a true full wipe would have thrown away every
    /// OTHER system's already-warmed comments too.
    ///
    /// Only forgets URLs that actually live under one of `folders`, so a
    /// scoped scan (e.g. "Remove Zip Comments…" on one folder) doesn't force
    /// a fresh re-read of every
    /// OTHER folder's already-correct, already-cached comments too. See
    /// `LibraryViewModel.lastScanFolders`'s own doc comment for the report
    /// this fixes.
    func invalidate(underAnyOf folders: [URL]) {
        guard !folders.isEmpty else { return }
        let standardizedFolders = folders.map { $0.standardizedFileURL.path }
        storage = storage.filter { url, _ in
            let path = url.standardizedFileURL.path
            return !standardizedFolders.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
    }

    /// Warms the cache with already-computed reads — jensyleo's own report
    /// (2026-09-23), "la app se traba cuando se hace scroll": `Table` on
    /// macOS is virtualized (only visible rows actually render), so
    /// `comment(forZipAt:)`'s own lazy-fill-on-first-read design meant the
    /// FIRST time each newly-scrolled-into-view row's zip got checked, this
    /// synchronously called `ZipCommentReader.comment(ofZipAt:)` — real
    /// disk I/O, right there in the middle of rendering that row — on the
    /// main thread, mid-scroll. For a NAS-backed ROM folder (this app's
    /// whole reason CRC32/hash caching exists at all) that's a real,
    /// per-row network round trip stuttering the scroll itself.
    /// `refreshCachedGameDataAfterAuditReportChangeAsync` already
    /// recomputes the currently-scoped node list in a background
    /// `Task.detached` every time the audit report or selected folder/
    /// category changes — reading every one of THOSE zips' comments there
    /// too (still off the main thread, still bounded to what's about to be
    /// shown, never the whole system) and merging the results in here
    /// BEFORE the user ever starts scrolling means every visible row's
    /// lookup is a cache hit by the time it matters — zero disk I/O left
    /// in the actual per-row render path.
    func preload(_ values: [URL: String?]) {
        for (url, comment) in values {
            storage[url] = comment
        }
    }

    /// Read-only snapshot of the whole cache — captured on `@MainActor`
    /// right before `triggerCachedGameDataRecompute()`'s own `Task.detached`
    /// starts, so that background task can skip re-reading (real, possibly
    /// NAS-backed, disk I/O) any zip it already has a comment for. Real bug
    /// found live by jensyleo (2026-09-26): "se tiende a colgar cuando se da
    /// clic en los rom folder" — the preload loop below had no such check
    /// at all, so EVERY folder click re-read EVERY zip's comment again,
    /// even the tenth time selecting a folder already fully cached.
    ///
    /// Deliberately returns the `Dictionary` itself, NOT `Set(storage.keys)`
    /// — jensyleo's own follow-up report (2026-09-26), general app-wide
    /// slowness right after this fix landed, toggles included: `Dictionary`/
    /// `Set` are copy-on-write value types, so handing back `storage`
    /// directly is an O(1) retain, never actually copied since the caller
    /// only ever reads it — but `Set(storage.keys)` allocates and rehashes
    /// a brand-new `Set` from every key, a real O(n) synchronous pass on
    /// the main thread, on every single trigger (folder click, toggle
    /// flip) once the real collection's cache holds tens of thousands of
    /// entries. Callers check membership with `snapshot[url] != nil`
    /// instead of `.contains(url)`.
    var snapshot: [URL: String?] {
        storage
    }
}

/// The loaded DAT's games indexed by their own lowercased machine name, so
/// resolving one (`gameDescription(forMachineName:)`, for the "Clone of"
/// column) is a single dictionary lookup.
///
/// jensyleo's own report (2026-08-26), root-caused with a sampling profiler
/// on a real divider drag: without this, `gameDescription(forMachineName:)`
/// rebuilt that whole dictionary from `preloadedGames` on *every call* — and
/// it is called once per visible table row, inside the column's own content
/// closure, so it ran again for every row on every layout pass. Dragging a
/// divider re-lays the table out on every mouse-moved event, which made each
/// frame cost (visible rows × the entire DAT); on a full MAME set that is
/// tens of thousands of dictionary insertions and twice as many
/// `lowercased()` allocations per row, per frame. The profile showed
/// `NSHostingView.layout()` → `AppKitOutlineTableCoordinator.update` →
/// `TableColumnList.visitAll` → `gameDescription(forMachineName:)` →
/// `gamesByName(_:)` dominating ROMForge's own time during a drag, which is
/// what made the divider visibly lag behind the mouse.
///
/// A plain reference-type cache rather than `@State`, for the same reason
/// `ZipCommentCache` above is one: it gets filled while the view body is
/// being evaluated, and mutating SwiftUI state mid-render is undefined
/// behavior. Rebuilt only when the underlying game list actually changes
/// (a different DAT, or a reload) — detected by identity of the array's
/// storage plus its count, which is exact for the "same array reused" case
/// and merely rebuilds once more than strictly needed otherwise.
private final class GamesByNameCache {
    private var storage: [String: DATGame] = [:]
    private var sourceCount = -1
    private var sourceFirstName: String?
    private var sourceLastName: String?

    func games(from games: [DATGame]) -> [String: DATGame] {
        if games.count == sourceCount,
           games.first?.name == sourceFirstName,
           games.last?.name == sourceLastName {
            return storage
        }
        var result: [String: DATGame] = [:]
        result.reserveCapacity(games.count)
        for game in games {
            let key = game.name.lowercased()
            if result[key] == nil { result[key] = game }
        }
        storage = result
        sourceCount = games.count
        sourceFirstName = games.first?.name
        sourceLastName = games.last?.name
        return storage
    }
}

/// The five column-preset notifications' listener side, bundled into one
/// `View` extension — see the doc comment where this is applied (inside
/// `LibraryDetailView.body`) for why this isn't five inline `.onReceive`
/// calls instead.
private extension View {
    func columnPresetNotificationHandlers(
        onApply: @escaping (String) -> Void,
        onSave: @escaping (String) -> Void,
        onDelete: @escaping (String) -> Void,
        onRename: @escaping (String, String) -> Void,
        onSetOrder: @escaping ([String]) -> Void
    ) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: .romForgeApplyColumnPreset)) { note in
                guard let name = note.userInfo?["name"] as? String else { return }
                onApply(name)
            }
            .onReceive(NotificationCenter.default.publisher(for: .romForgeSaveColumnPreset)) { note in
                guard let name = note.userInfo?["name"] as? String else { return }
                onSave(name)
            }
            .onReceive(NotificationCenter.default.publisher(for: .romForgeDeleteColumnPreset)) { note in
                guard let name = note.userInfo?["name"] as? String else { return }
                onDelete(name)
            }
            .onReceive(NotificationCenter.default.publisher(for: .romForgeRenameColumnPreset)) { note in
                guard let oldName = note.userInfo?["oldName"] as? String, let newName = note.userInfo?["newName"] as? String else { return }
                onRename(oldName, newName)
            }
            .onReceive(NotificationCenter.default.publisher(for: .romForgeSetColumnPresetOrder)) { note in
                guard let order = note.userInfo?["order"] as? [String] else { return }
                onSetOrder(order)
            }
    }

    /// `true` when the currently configured "Roms case" policy (Settings →
    /// Fix) could actually produce an entry name whose case differs from
    /// what the DAT declares — jensyleo's own request (2026-09-10): don't
    /// show the case-sensitivity caution below when there's nothing to
    /// warn about. `.datafileCase` always produces the DAT's own exact
    /// case; `.dontTouch` is treated identically to it for a genuine
    /// mismatch fix (`RebuildPlanner.mismatchFixName`'s own doc comment —
    /// a mismatch always needs SOME real rename, so `.dontTouch` there
    /// falls back to the DAT's declared case rather than leaving the
    /// wrong name in place) and is a literal no-op for the already-correct
    /// re-styling half (`RebuildPlanner.caseTransformTarget`) — neither can
    /// ever change an entry's case away from the DAT's own.
    func currentRomsCasePolicyRisksCaseMismatch() -> Bool {
        let policy = FixPreferencesSettings.currentRomsCasePolicy()
        return policy != .datafileCase && policy != .dontTouch
    }

    /// Same idea as `currentRomsCasePolicyRisksCaseMismatch` above, for
    /// "Sets case" (File-level) — jensyleo's own follow-up request
    /// (2026-09-10) after adding the ROM-level warning: "Fix Mismatched
    /// Files" carried the exact same risk (a re-styled archive filename no
    /// longer matching the DAT's own case) but never had a confirmation
    /// dialog at all to show it in, an asymmetry with no good reason to
    /// keep.
    func currentSetsCasePolicyRisksCaseMismatch() -> Bool {
        let policy = FixPreferencesSettings.currentSetsCasePolicy()
        return policy != .datafileCase && policy != .dontTouch
    }

    /// Every Fase 2 write action's own confirmation dialog (Rebuild to
    /// Folder, Remove Useless Files, Repair from Sibling Sets, Make
    /// Self-Contained), bundled into ONE modifier and factored out of
    /// `body` — piling each `.confirmationDialog` directly onto `body`'s
    /// already-huge modifier chain made the type-checker time out ("unable
    /// to type-check this expression in reasonable time"); even splitting
    /// them into several SEPARATE extracted modifiers (as Steps 1/3/4/7
    /// each got when they were added one at a time) eventually hit the same
    /// wall once there were enough of them chained on `body` at once — one
    /// modifier covering all four is what actually stayed under the
    /// type-checker's budget.
    func fase2Confirmations(
        rebuildDestination: URL?,
        rebuildOperationCount: Int,
        showRebuild: Binding<Bool>,
        onCopy: @escaping () -> Void,
        onMove: @escaping () -> Void,
        onCancelRebuild: @escaping () -> Void,
        showRemoveUselessFiles: Binding<Bool>,
        removeUselessFilesCount: Int,
        onRemoveUselessFiles: @escaping () -> Void,
        showRepair: Binding<Bool>,
        repairCount: Int,
        onRepair: @escaping () -> Void,
        showMakeSelfContained: Binding<Bool>,
        makeSelfContainedCount: Int,
        onMakeSelfContained: @escaping () -> Void,
        showRenameRomsInArchive: Binding<Bool>,
        renameRomsInArchiveCount: Int,
        onRenameRomsInArchive: @escaping () -> Void
    ) -> some View {
        self
            .confirmationDialog(
                "Rebuild \(rebuildOperationCount) File\(rebuildOperationCount == 1 ? "" : "s")?",
                isPresented: showRebuild,
                titleVisibility: .visible
            ) {
                Button("Copy", action: onCopy)
                Button("Move (removes from source)", role: .destructive, action: onMove)
                Button("Cancel", role: .cancel, action: onCancelRebuild)
            } message: {
                if let rebuildDestination {
                    Text("Every matched ROM will be organized as one subfolder per game inside \"\(rebuildDestination.lastPathComponent)\". Existing files there are never overwritten.")
                }
            }
            .confirmationDialog(
                "Permanently Delete \(removeUselessFilesCount) File\(removeUselessFilesCount == 1 ? "" : "s")?",
                isPresented: showRemoveUselessFiles,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onRemoveUselessFiles)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("These files are recognized as nothing the current DAT declares — not needed by this game or any other. This cannot be undone.")
            }
            .confirmationDialog(
                "Repair \(repairCount) Missing ROM\(repairCount == 1 ? "" : "s") from Sibling Sets?",
                isPresented: showRepair,
                titleVisibility: .visible
            ) {
                Button("Repair", action: onRepair)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each rom is copied from a parent/clone set that already has the exact same content — never invented, never taken from a set that needs it too.")
            }
            .confirmationDialog(
                "Copy \(makeSelfContainedCount) Inherited ROM\(makeSelfContainedCount == 1 ? "" : "s") into Their Own Archives?",
                isPresented: showMakeSelfContained,
                titleVisibility: .visible
            ) {
                Button("Copy", action: onMakeSelfContained)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Each rom is already genuinely present elsewhere in this scan (a BIOS or parent set) — this only adds a copy into each game's own archive, it never removes anything from where it already is.")
            }
            .confirmationDialog(
                "Fix \(renameRomsInArchiveCount) Misnamed ROM\(renameRomsInArchiveCount == 1 ? "" : "s") Inside Their Archives?",
                isPresented: showRenameRomsInArchive,
                titleVisibility: .visible
            ) {
                Button("Fix", action: onRenameRomsInArchive)
                Button("Cancel", role: .cancel) {}
            } message: {
                if currentRomsCasePolicyRisksCaseMismatch() {
                    Text("Changing the case away from \"Datafile Case\" (Settings → Fix → \"Roms case\") makes this entry's name no longer match the DAT exactly. Some tools/emulators are case-sensitive and may then fail to find it — which can stop this game from running there.")
                }
            }
    }

    /// Fase 2 Step 4 (split direction)'s own confirmation dialog — its own
    /// separate modifier rather than a 4th/5th parameter pair added to
    /// `fase2Confirmations` above, whose parameter list is already at the
    /// point another addition risks the same type-checker timeout that
    /// modifier itself exists to avoid.
    func fase2Step4SplitConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Strip \(count) Redundant ROM\(count == 1 ? "" : "s") from Clone Archives?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Strip", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each rom is confirmed present, correctly, in its own parent set's archive — removing it from the clone relies on that parent archive being available whenever this clone is used.")
        }
    }

    /// "Fix All"'s own confirmation dialog — jensyleo's own request
    /// (2026-09-29), the last pending Fase 2 item: runs every fully-
    /// automatic Fix action in one pass (see `LibraryViewModel.fixAll(system:)`'s
    /// own doc comment for the exact order and what's excluded). Its own
    /// separate modifier for the same type-checker reason
    /// `fase2Step4SplitConfirmation` above is — a destructive-role button,
    /// since this can include Remove Useless/Redundant Files/ROMs.
    func fixAllConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Run Fix All — About \(count) Change\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Fix All", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs every fully-automatic Fix action in one pass, in a safe order: fixes names, normalizes the configured set layout (MAME only), repairs missing/bad content from sibling sets and the Maintenance folder, then permanently removes useless and redundant files/roms, and finishes with zip comments, Samples, and BIOS/Complementary Chips housekeeping. Only \"Rebuild to Folder…\" is excluded, since it needs a destination you'd have to pick yourself.")
        }
    }

    /// "Find ROMs…"'s own confirmation dialog, its
    /// own separate modifier for the same reason `fase2Step4SplitConfirmation`
    /// above is. jensyleo's own request (2026-09-14): "fusionalo con
    /// repair from maintenance folder" — this one action now covers BOTH
    /// filling a `.missing` rom AND replacing a `.badDump` rom's bad
    /// content with a verified-correct copy, so the wording no longer
    /// says "Missing" specifically.
    func repairFromMaintenanceFolderConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Repair \(count) ROM\(count == 1 ? "" : "s") from the Maintenance Folder?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Repair", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each missing rom is filled in, and each hash-mismatched rom's bad content is replaced, using a verified-correct copy found in the read-only Maintenance folder configured in Settings → Systems → MAME, or in any of the system's own configured ROM folders. Nothing there is ever renamed, moved, or deleted.")
        }
    }

    /// The Roms panel's own entry-level File Actions (Extract/Trash/Delete)
    /// — jensyleo's own request (2026-09-13): the same kind of File Actions
    /// the Games table already offers, available here too regardless of a
    /// rom's own DAT status, adapted for the fact an entry is often INSIDE
    /// a `.zip` rather than loose (see `LibraryViewModel.RomEntryTarget`'s
    /// own doc comment). Bundled into one modifier for the same reason
    /// `fase2Confirmations` already bundles several — three separate
    /// `confirmationDialog`s would each cost their own closure against the
    /// type-checker's budget.
    func romEntryActionsConfirmations(
        showExtract: Binding<Bool>,
        extractCount: Int,
        extractDestination: URL?,
        onExtract: @escaping () -> Void,
        showTrash: Binding<Bool>,
        trashCount: Int,
        onTrash: @escaping () -> Void,
        showDelete: Binding<Bool>,
        deleteCount: Int,
        onDelete: @escaping () -> Void
    ) -> some View {
        self
            .confirmationDialog(
                "Extract \(extractCount) Rom\(extractCount == 1 ? "" : "s") to Folder?",
                isPresented: showExtract,
                titleVisibility: .visible
            ) {
                Button("Extract", action: onExtract)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let extractDestination {
                    Text("Copied out into \"\(extractDestination.lastPathComponent)\" as plain loose files. The source (including any containing archive) is left untouched.")
                }
            }
            .confirmationDialog(
                "Move \(trashCount) Rom\(trashCount == 1 ? "" : "s") to the Trash?",
                isPresented: showTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive, action: onTrash)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("A loose rom goes to the real Finder Trash (recoverable from there). A rom inside a `.zip` has just its own entry removed from that archive — every other rom in it is untouched, and this part cannot be undone.")
            }
            .confirmationDialog(
                "Permanently Delete \(deleteCount) Rom\(deleteCount == 1 ? "" : "s")?",
                isPresented: showDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDelete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone. A rom inside a `.zip` has just its own entry removed — every other rom in that same archive is untouched.")
            }
    }

    /// "Remove Redundant Files" — its own separate modifier for the same
    /// reason `fase2Step4SplitConfirmation` above is. jensyleo's own
    /// request (2026-09-13): the exact complement of "Remove Useless
    /// Files" — targets a LOOSE file the DAT genuinely recognizes, just not
    /// needed at this exact location because another game already claims
    /// an equivalent copy elsewhere.
    func removeRedundantFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Permanently Delete \(count) Redundant File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each of these files is recognized DAT content, but a duplicate copy that isn't needed at this exact location — another game already has an equivalent copy elsewhere in this scan. This cannot be undone.")
        }
    }

    /// "Organize BIOS Files" — jensyleo's own request (2026-09-23), same
    /// separate-modifier reasoning as every other Fase 2 confirmation
    /// factored out of `fase2Confirmations` above.
    func organizeBIOSFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        lines: [String],
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Organize \(count) BIOS File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Organize", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            // jensyleo's own request (2026-09-23), right after asking what
            // this action does exactly and worrying about losing BIOS
            // files he already has: list every BIOS it actually found by
            // name, not just a bare count — see `LibraryViewModel
            // .planOrganizeBIOSFilesPreviewLines`'s own doc comment.
            Text("Each BIOS file found across this system's own ROM folders is moved into the configured BIOS folder. A redundant further copy is only ever removed once another copy is confirmed safe elsewhere. This cannot be undone.\n\n" + lines.joined(separator: "\n"))
        }
    }

    /// "Organize Complementary Chips" — same shape as
    /// `organizeBIOSFilesConfirmation` right above.
    func organizeComplementaryChipsConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        lines: [String],
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Organize \(count) Complementary Chip File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Organize", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each complementary chip file found across this system's own ROM folders is moved into the configured Complementary Chips folder. A redundant further copy is only ever removed once another copy is confirmed safe elsewhere. This cannot be undone.\n\n" + lines.joined(separator: "\n"))
        }
    }

    /// "Remove Redundant ROMs" — the archive-entry counterpart to
    /// `removeRedundantFilesConfirmation` just above; same reasoning.
    func removeRedundantRomsConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Permanently Remove \(count) Redundant Rom\(count == 1 ? "" : "s") from Their Archives?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each of these roms is recognized DAT content, but a duplicate ENTRY inside an archive that isn't needed at this exact location — another game already has an equivalent copy elsewhere in this scan. Only the entry is removed, never its containing archive. This cannot be undone.")
        }
    }

    /// "Create Dummy ROMs" — placeholder for `nodump` entries — its own
    /// separate modifier for the same reason `fase2Step4SplitConfirmation`
    /// above is.
    func createDummyRomsConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Create \(count) Dummy Rom\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Create", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each placeholder is a zero-byte stand-in for a rom the DAT itself declares \"nodump\" — no official dump exists to verify against, so this can never be a real dump, only a presence marker.")
        }
    }

    /// "Fix Samples" — its own separate modifier for the same reason
    /// `fase2Step4SplitConfirmation` above is.
    func collectSamplesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Collect \(count) Sample Zip\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Collect", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each zip is copied, unmodified, from this system's own ROM folders into the Samples folder configured in Settings → Systems → MAME. Matched by filename only — MAME's own DAT declares no hash for samples, so this can never verify content, only presence.")
        }
    }

    /// "Remove Zip Comments" — its own separate modifier for the same
    /// reason `fase2Step4SplitConfirmation` above is.
    func removeZipCommentsConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Remove Comments from \(count) Archive\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Strips each matched archive's own trailing ZIP comment, in place. Nothing else about the archive changes.")
        }
    }

    /// "Fix Misnamed ROMs Inside Their Archives…", scoped to a single File
    /// from the Games table's own context menu — its own separate modifier
    /// so it can't share (and so clobber) the toolbar's own folder-scoped
    /// confirmation state.
    func contextMenuRenameRomsInArchiveConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Fix \(count) Misnamed ROM\(count == 1 ? "" : "s") Inside This Archive?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Fix", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            if currentRomsCasePolicyRisksCaseMismatch() {
                Text("Changing the case away from \"Datafile Case\" (Settings → Fix → \"Roms case\") makes this entry's name no longer match the DAT exactly. Some tools/emulators are case-sensitive and may then fail to find it — which can stop this game from running there.")
            }
        }
    }

    /// "Fix Mismatched Files" — the File-level twin of
    /// `contextMenuRenameRomsInArchiveConfirmation` above, added for the
    /// same reason (2026-09-10): a re-styled archive filename can stop
    /// matching the DAT's own case just as easily as a re-styled ROM
    /// entry can. One modifier, reused by both the toolbar's own
    /// folder-scoped action and the Games table context menu's
    /// single-File action — each passes its own state so neither can
    /// clobber the other's pending confirmation.
    func fixMismatchedFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Fix \(count) Mismatched File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Fix", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            if currentSetsCasePolicyRisksCaseMismatch() {
                Text("Changing the case away from \"Datafile Case\" (Settings → Fix → \"Sets case\") makes this File's name no longer match the DAT exactly. Some tools/emulators are case-sensitive and may then fail to find it — which can stop this game from running there.")
            }
        }
    }

    /// "Remove Useless Files" (context menu, scoped to selected File(s)) —
    /// its own separate modifier for the same reason
    /// `fase2Step4SplitConfirmation` above is. Always shown (unlike
    /// `fixMismatchedFilesConfirmation`'s "skip if not risky" shortcut) —
    /// this one is always destructive, never a mere re-styling.
    func contextMenuRemoveUselessFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Permanently Delete \(count) File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These files are recognized as nothing the current DAT declares — not needed by this game or any other. This cannot be undone.")
        }
    }

    /// "Remove Redundant File(s)" (context menu, scoped to selected
    /// File(s)) — jensyleo's own request (2026-09-14): "agrega todas las
    /// opciones que apliquen en el menú contextual" after noticing a row
    /// reading "Duplicated file, not needed here" had no matching
    /// right-click action, only the toolbar's own folder-scoped "Remove
    /// Redundant Files…". Same shape as
    /// `contextMenuRemoveUselessFilesConfirmation` just above.
    func contextMenuRemoveRedundantFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Permanently Delete \(count) Redundant File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These loose files are recognized by the DAT, but the content is a duplicate already present somewhere else this scan already covers — not needed here. This cannot be undone.")
        }
    }

    /// The archive-entry counterpart to
    /// `contextMenuRemoveRedundantFilesConfirmation` just above — same
    /// "recognized, but not needed HERE" case, at the ROM-inside-an-archive
    /// level instead of the whole-file level.
    func contextMenuRemoveRedundantRomsConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Permanently Remove \(count) Redundant ROM\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These roms are recognized by the DAT, but the content is a duplicate already present somewhere else this scan already covers — not needed here. This cannot be undone.")
        }
    }

    /// Fase 2 Step 8's own confirmation dialog, its own separate modifier
    /// for the same reason `fase2Step4SplitConfirmation` above is.
    func handleCorruptedFilesConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Handle \(count) Corrupted File\(count == 1 ? "" : "s")?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Handle", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Applies the \"Corrupted files\" policy configured in Settings → Fix (Delete or Move to a quarantine folder) to every rom confirmed internally corrupt.")
        }
    }

    /// Fase 2 Step 4 (Merged direction)'s own confirmation dialog, its own
    /// separate modifier for the same reason `fase2Step4SplitConfirmation`
    /// above is. Its own wording is deliberately more explicit than every
    /// other Fase 2 confirmation — this is the only action that deletes a
    /// WHOLE archive rather than one entry inside it.
    func convertToMergedConfirmation(
        isPresented: Binding<Bool>,
        count: Int,
        onConfirm: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            "Merge \(count) Clone\(count == 1 ? "" : "s") Into Their Parent — Deleting Each Clone's Own Archive?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Merge and Delete", role: .destructive, action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Each clone's own unique roms are copied into its parent's archive FIRST — the clone's own archive is only deleted afterward, and only if every one of its roms was copied successfully. A clone whose migration fails partway through is left completely untouched.")
        }
    }

    /// "File Actions" (Move to Trash, Delete Permanently, Copy/Move to
    /// Folder…) confirmation dialogs — jensyleo's own request (2026-09-11):
    /// plain, OS-level operations on whatever Files are currently selected,
    /// independent of the DAT. Own separate modifier, same reasoning as
    /// `fase2Step4SplitConfirmation`/`convertToMergedConfirmation` above.
    func fileActionsConfirmations(
        urlCount: Int,
        destination: URL?,
        showMoveToTrash: Binding<Bool>,
        onMoveToTrash: @escaping () -> Void,
        showDeletePermanently: Binding<Bool>,
        onDeletePermanently: @escaping () -> Void,
        showCopyToFolder: Binding<Bool>,
        onCopyToFolder: @escaping () -> Void,
        showMoveToFolder: Binding<Bool>,
        onMoveToFolder: @escaping () -> Void,
        replaceFilenames: [String],
        showReplaceExisting: Binding<Bool>,
        onReplaceExisting: @escaping () -> Void
    ) -> some View {
        self
            .confirmationDialog(
                "Move \(urlCount) File\(urlCount == 1 ? "" : "s") to the Trash?",
                isPresented: showMoveToTrash,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive, action: onMoveToTrash)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sent to the Finder Trash — recoverable from there until it's emptied. This system will need a rescan afterward.")
            }
            .confirmationDialog(
                "Permanently Delete \(urlCount) File\(urlCount == 1 ? "" : "s")?",
                isPresented: showDeletePermanently,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: onDeletePermanently)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone — unlike \"Move to Trash\", these files are removed immediately and permanently.")
            }
            .confirmationDialog(
                "Copy \(urlCount) File\(urlCount == 1 ? "" : "s")?",
                isPresented: showCopyToFolder,
                titleVisibility: .visible
            ) {
                Button("Copy", action: onCopyToFolder)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let destination {
                    Text("Copied into \"\(destination.lastPathComponent)\". The originals are left untouched.")
                }
            }
            .confirmationDialog(
                "Move \(urlCount) File\(urlCount == 1 ? "" : "s")?",
                isPresented: showMoveToFolder,
                titleVisibility: .visible
            ) {
                Button("Move", role: .destructive, action: onMoveToFolder)
                Button("Cancel", role: .cancel) {}
            } message: {
                if let destination {
                    Text("Moved into \"\(destination.lastPathComponent)\", removed from their current location. This system will need a rescan afterward.")
                }
            }
            // jensyleo's own request (2026-09-30) — see
            // `showReplaceExistingConfirmation`'s own doc comment. Deliberately
            // its own, separate dialog (not folded into the Copy/Move ones
            // above) so the message can name the exact colliding filenames
            // — those two above fire unconditionally on every Copy/Move,
            // long before it's known whether anything actually collides.
            .confirmationDialog(
                "Replace \(replaceFilenames.count) Existing File\(replaceFilenames.count == 1 ? "" : "s")?",
                isPresented: showReplaceExisting,
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive, action: onReplaceExisting)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Already exists at the destination: \(replaceFilenames.joined(separator: ", ")). Replacing overwrites it permanently — the current copy there cannot be recovered afterward.")
            }
    }

    /// jensyleo's own request (2026-09-30) — see `GameTreeTableView`'s own
    /// "Rename to…" context-menu button doc comment. A separate modifier
    /// (not folded into `fileActionsConfirmations` above) since it needs
    /// its own two pieces of state (`url`/`suggestion`) that function has
    /// no reason to know about.
    func renameToSimilarNameConfirmation(
        url: URL?, suggestion: SimilarNameSuggestion?, isPresented: Binding<Bool>, onConfirm: @escaping () -> Void
    ) -> some View {
        self.confirmationDialog(
            "Rename \"\(url?.lastPathComponent ?? "")\"?",
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Rename", action: onConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            if let suggestion {
                Text("To \"\(suggestion.suggestedName)\(url?.pathExtension.isEmpty == false ? ".\(url!.pathExtension)" : "")\" — a \(Int((suggestion.confidence * 100).rounded()))% name match. This is a best-effort GUESS based on the name alone, not a verified content match — the DAT still can't confirm this file's actual content.")
            }
        }
    }

    /// The pop-up alert after a Fix/File Action finishes — jensyleo's own
    /// request (2026-09-11), additive to (never a replacement for) the Log
    /// panel's own lines for the same result; see `LibraryViewModel
    /// .postFixResultPopup`'s own doc comment. `isPresented`'s `set` clears
    /// `alert` (via `onDismiss`) so the same result can never be shown
    /// twice — same one-shot pattern this file already uses for
    /// `cancelledPhase`.
    func fixResultAlert(
        alert: LibraryViewModel.FixResultAlert?,
        onDismiss: @escaping () -> Void
    ) -> some View {
        self.alert(
            alert?.title ?? "",
            isPresented: Binding(get: { alert != nil }, set: { if !$0 { onDismiss() } }),
            presenting: alert
        ) { _ in
            Button("OK") { onDismiss() }
        } message: { alert in
            Text(alert.message)
        }
    }
}

/// What kind of volume a configured ROM folder actually lives on —
/// jensyleo's own request (2026-09-16), testing with ROM folders on a NAS:
/// a visual distinction between local disk, a removable/external drive
/// (pendrive, external HDD), and a network share (SMB, AFP, NFS). Detected
/// via `URLResourceValues`, never assumed from the path string — a mounted
/// network share's local mount point looks like any other folder path.
enum RomFolderVolumeKind: Equatable {
    case local
    case removable
    case network
    case unknown

    var symbolName: String {
        switch self {
        case .local: "internaldrive"
        case .removable: "externaldrive.fill"
        case .network: "externaldrive.connected.to.line.below"
        case .unknown: "externaldrive"
        }
    }

    var helpSuffix: String {
        switch self {
        case .local: " (local disk)"
        case .removable: " (removable/external drive)"
        case .network: " (network volume)"
        case .unknown: ""
        }
    }

    /// Real filesystem call — `.volumeIsLocalKey` for a network mount
    /// (SMB/AFP/NFS) can itself round-trip over the network, so this must
    /// only ever run off `@MainActor` (see `refreshRomFolderVolumeKindCache`'s
    /// own doc comment). `.volumeIsLocalKey` is the authoritative signal
    /// for "network or not"; `.volumeIsRemovableKey`/`.volumeIsInternalKey`
    /// then distinguish a local-but-removable drive (USB stick, external
    /// HDD) from the internal boot disk.
    static func detect(for url: URL) -> RomFolderVolumeKind {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        ]) else {
            return .unknown
        }
        if values.volumeIsLocal == false {
            return .network
        }
        if values.volumeIsRemovable == true || values.volumeIsEjectable == true || values.volumeIsInternal == false {
            return .removable
        }
        return .local
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
    /// jensyleo's own request (2026-08-18): "junta todos los export en un
    /// mismo lado" — `ContentView`'s own "Export Report…" (a whole-collection
    /// HTML report, not scoped to this one system) used to live in the
    /// sidebar's toolbar, visually separated from "Export Fix DAT…"/"Export
    /// List to CSV…" here. Rather than duplicate `ContentView`'s access to
    /// `SystemLibraryStore` (which this view has no business needing just
    /// to render one more button), the action itself stays owned by
    /// `ContentView` and is simply invoked from a button placed next to
    /// this view's own exports instead.
    var onExportCollectionReport: (() -> Void)?
    /// The shared, real AppKit toolbar (see `ROMForgeToolbar.swift`'s own
    /// doc comment) — `ContentView` owns it since it's this window's true
    /// root content; this view only ever contributes its own "detail"
    /// region of items to it. `nil` only in previews/tests that construct
    /// this view without a real window around it.
    var toolbarController: ROMForgeToolbarController?
    /// `ContentView`'s own sidebar-visibility toggle — a `Binding` (not a
    /// plain callback like `onExportCollectionReport`) since Column
    /// Presets needs to both *read* the current value (to save it into a
    /// new preset) and *write* it (to restore a saved one). `nil` only in
    /// previews/tests.
    var isSidebarVisible: Binding<Bool>?
    /// jensyleo's own request (2026-08-12): "que la primera vista que tenga
    /// sea siempre la última antes de cerrar la app" — restores whichever
    /// "Database" category or "ROM folder" this exact system had selected
    /// the last time it was open, instead of always starting fresh at
    /// `.allGames`. Falls back, in order, to this system's first configured
    /// ROM folder (if it has one) or its first currently-*enabled* "Database"
    /// branch (see `DatabaseFilterVisibilitySettings`) when there's no saved
    /// selection yet — a first run, a system whose only saved selection no
    /// longer exists (a removed folder, a branch since disabled in
    /// Settings), or a `RomSystem` with zero ROM folders configured at all.
    /// Set via a custom `init` (not the properties' own inline defaults)
    /// since restoring needs this specific `system`'s own `id` and
    /// `romFolderURLs` — unavailable to a plain `= .allGames` default.
    init(
        system: RomSystem, onAddFolder: @escaping ([URL]) -> Void, onDATAnalyzed: ((Bool) -> Void)? = nil,
        onExportCollectionReport: (() -> Void)? = nil, toolbarController: ROMForgeToolbarController? = nil,
        isSidebarVisible: Binding<Bool>? = nil
    ) {
        self.system = system
        self.onAddFolder = onAddFolder
        self.onDATAnalyzed = onDATAnalyzed
        self.onExportCollectionReport = onExportCollectionReport
        self.toolbarController = toolbarController
        self.isSidebarVisible = isSidebarVisible
        let restored = Self.restoreLastSelection(for: system)
        _selectedDatabaseFilter = State(initialValue: restored.databaseFilter)
        _selectedRomFolder = State(initialValue: restored.romFolder)
    }

    // Not `private` — `SystemLibraryStore.remove(_:)` also needs this exact
    // key to purge the persisted selection when a system is removed
    // (jensyleo's own report, 2026-09-16: "verifica que cuando se quite el
    // sistema se purgue toda la información" — this was a real, if
    // harmless, orphaned UserDefaults key left behind on every removal).
    static func lastSelectionKey(for system: RomSystem) -> String {
        "ROMForge.system.\(system.id.uuidString).lastSelection"
    }

    /// Encodes either a selected "Database" filter or a selected "ROM
    /// folder" (never both — see `selectedRomFolder`'s own doc comment on
    /// why they're mutually exclusive) into one plain string, since
    /// `UserDefaults` has no native "one of these two types" storage.
    private static func restoreLastSelection(for system: RomSystem) -> (databaseFilter: DatabaseFilter?, romFolder: URL?) {
        if let raw = UserDefaults.standard.string(forKey: lastSelectionKey(for: system)) {
            if raw.hasPrefix("database:") {
                let name = String(raw.dropFirst("database:".count))
                if let filter = DatabaseFilter(rawValue: name) { return (filter, nil) }
            } else if raw.hasPrefix("romfolder:") {
                let path = String(raw.dropFirst("romfolder:".count))
                let url = URL(fileURLWithPath: path)
                // Only trusted if this folder is still actually configured
                // on this system — one removed since the last launch
                // shouldn't silently resurrect itself as the selection.
                if system.romFolderURLs.contains(url) { return (nil, url) }
            }
        }
        if let firstFolder = system.romFolderURLs.first {
            return (nil, firstFolder)
        }
        let enabledRaw = UserDefaults.standard.string(forKey: DatabaseFilterVisibilitySettings.storageKey(forMAME: system.isMAMEStyle))
            ?? DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: system.isMAMEStyle)
        return (DatabaseFilterVisibilitySettings.enabledFilters(from: enabledRaw).first ?? .allGames, nil)
    }

    /// `.onChange(of: selectedDatabaseFilter)`'s own handler — pulled out
    /// into a named function (not an inline closure) purely so the Swift
    /// type-checker doesn't have to fold it into the same already-huge
    /// modifier-chain expression `body` builds; inlined here it started
    /// timing out compilation ("unable to type-check this expression in
    /// reasonable time") once nearby `.onReceive`/`.sheet` modifiers were
    /// added/removed for Fase 2 work (2026-08-31) — no behavior change,
    /// same statements as before.
    /// `.onChange(of: viewModel.cachedDATFile)`'s own handler — pulled out
    /// for the same type-checker-timeout reason as
    /// `handleSelectedDatabaseFilterChange()` just below; no behavior
    /// change, same statements as before.
    private func handleCachedDATFileChange() {
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
        // Real regression found live (2026-08-24): the star/"Show Only
        // 1G1R" hiding never showed up for a system that hadn't been
        // scanned yet — `onAppear`'s own
        // `refreshCachedGameDataAfterAuditReportChangeAsync()` call
        // runs before `startPreloadDAT` has actually finished loading
        // the DAT, so it computes `cachedOneGameOneROMSummary` from an
        // still-empty `preloadedGames`. Nothing recomputed it again
        // once the DAT genuinely finished loading — this `onChange`
        // fires exactly then, so it's the right place to redo that
        // computation for real, same as `.onChange(of: regionOrderRaw)`
        // already does for a region-priority change.
        //
        // Skipped while `loadPersistedReport` is still in flight —
        // jensyleo's own report (2026-09-17): once that SQLite read got
        // fast enough (~1.6s, down from 6.5s), the DAT (~1s) now
        // routinely finishes loading BEFORE the report does, so this call
        // used to run its whole expensive pipeline (`OneGameOneROMSelector.compute`
        // alone ~200ms over a 50k-game DAT) against a still-empty report,
        // just to have it thrown away moments later when the real,
        // definitive one supersedes it via `.onChange(of: viewModel.auditReport)`.
        // Still runs for a genuinely never-scanned system, where
        // `isLoadingPersistedReport` settles to `false` once `loadReport`
        // comes back `nil` — the actual case this call exists for.
        if !viewModel.isLoadingPersistedReport {
            refreshCachedGameDataAfterAuditReportChangeAsync()
        }
        // The Maintenance folder's own match pass (`loadMaintenanceFolderFiles()`)
        // needs a real DAT to color anything — if it's being browsed before
        // the DAT finished loading, redo it now that one's actually here.
        if isSelectedFolderMaintenanceSubfolder {
            loadMaintenanceFolderFiles()
        }
    }

    private func handleSelectedDatabaseFilterChange() {
        if selectedDatabaseFilter != nil { selectedRomFolder = nil }
        selectedGameID = nil; selectedRomID = nil
        selectedGameFamilyRootMachineName = nil
        // Real bug found live by jensyleo (2026-08-11): clicking a
        // "Database" category (All games/Clones/Bios files/…) still
        // called the SYNCHRONOUS `recomputeCachedGameDataSync()` here —
        // the exact same class of main-thread-blocking freeze already
        // fixed for "Rom files" folder clicks back on 2026-08-03 (see
        // `triggerCachedGameDataRecompute()`'s own doc comment), just
        // never applied to this sibling trigger. Blocking the main
        // thread on a full MAME DAT's ~43,000 games doesn't just freeze
        // the UI — a click landing *during* that block gets queued by
        // AppKit rather than dropped, so it's delivered late once the
        // block finally ends, reading as "the app didn't receive my
        // click" or "I had to click twice" (jensyleo's own reports,
        // same day). Switched to the same detached-with-generation-guard
        // pattern the folder path already uses.
        triggerCachedGameDataRecompute()
        persistLastSelection()
    }

    /// Called from `.onChange(of: selectedDatabaseFilter)`/`.onChange(of:
    /// selectedRomFolder)` — see `restoreLastSelection(for:)`'s own doc
    /// comment for the encoding this writes.
    private func persistLastSelection() {
        let raw: String?
        if let selectedRomFolder {
            raw = "romfolder:\(selectedRomFolder.path)"
        } else if let selectedDatabaseFilter {
            raw = "database:\(selectedDatabaseFilter.rawValue)"
        } else {
            raw = nil
        }
        UserDefaults.standard.set(raw, forKey: Self.lastSelectionKey(for: system))
    }

    /// Drives the selected "Rom files" folder row's highlight color —
    /// jensyleo's own request (2026-08-11): a selected folder only ever
    /// showed bold text, unlike a selected row in the Games/roms tables to
    /// the right (a real filled background). `.active` (this window is key)
    /// tints the row with the system accent color, same as a native
    /// `List`/`NSTableView` selection; `.inactive` (app/window not focused)
    /// dims it to gray — matching that same native behavior, where a
    /// selection stays visible but unobtrusive once focus moves elsewhere.
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var viewModel = LibraryViewModel()
    /// The Games table's own REAL selection — jensyleo's own request
    /// (2026-09-10): "la app no permite selección múltiple". A `Table`
    /// bound to a `Set<ID>` (rather than a single optional `ID?`) is what
    /// actually lets ⌘/⇧-click select more than one row at all; every
    /// OTHER piece of this view that only ever needed "the" selected game
    /// keeps reading/writing through `selectedGameID` below, which is
    /// backed by this same Set.
    @State private var selectedGameIDs: Set<String> = []
    /// Backward-compatible single-selection proxy over `selectedGameIDs`
    /// above — reads/writes its FIRST element, so every existing
    /// single-game call site (the detail panel, type-ahead, category-tree
    /// sync, keyboard navigation) keeps meaning exactly what it always
    /// did: "the" selected game, or the first of several when more than
    /// one is now selected. A computed property, not `@State` itself —
    /// `$selectedGameID` binding syntax is never used anywhere in this
    /// file (only the Table's own selection binds to `$selectedGameIDs`
    /// directly), so this needed no further plumbing.
    private var selectedGameID: String? {
        get { selectedGameIDs.first }
        nonmutating set { selectedGameIDs = newValue.map { [$0] } ?? [] }
    }
    /// The Roms table's own REAL selection — same multi-selection
    /// treatment as `selectedGameIDs` above, jensyleo's own request
    /// (2026-09-10): "Renombrar roms de una o varias, también se debe
    /// poder" (the right-hand Roms panel, not just the Games table).
    @State private var selectedRomIDs: Set<String> = []
    /// Backward-compatible single-selection proxy over `selectedRomIDs`
    /// above — same shape as `selectedGameID`'s own proxy, for the same
    /// reason: every existing single-rom call site (the detail pane's own
    /// `selectedEntry`) keeps meaning "the" selected rom, or the first of
    /// several when more than one is now selected.
    private var selectedRomID: String? {
        get { selectedRomIDs.first }
        nonmutating set { selectedRomIDs = newValue.map { [$0] } ?? [] }
    }
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
    /// jensyleo's own request (2026-08-12): "Games" re-draws every row of
    /// `displayedGameNodes` on every selection change in the sidebar — at
    /// "All games" scale (~45,000 rows) that's the dominant remaining cost
    /// once the sidebar's own locale-comparison sort was fixed. Capped the
    /// same way the sidebar tree already caps a big category
    /// (`databaseCategoryVisibleCap`/`maxTreeChildrenPerCategory`): only the
    /// first `gamesTableVisibleCap` rows of `displayedGameNodes` actually
    /// reach the `Table`, with a "Show more" control below it bumping this
    /// by `Self.treeLoadMoreIncrement` — reused rather than a new constant,
    /// since it's already exactly the page size this should grow by.
    /// Reset to `Self.maxTreeChildrenPerCategory` by `resetGamesTableVisibleCap()`
    /// on every fresh selection (category/folder/family), so switching
    /// categories always starts back at the fast, capped first page.
    @State private var gamesTableVisibleCap: Int = Self.maxTreeChildrenPerCategory
    /// A zip's own archive-level comment never changes without the file
    /// itself changing (a rescan already reloads everything fresh), so it's
    /// worth caching per archive path rather than re-parsing the same
    /// zip's End of Central Directory record on every render of every one
    /// of its rom rows. A plain reference-type cache (not `@State`) so
    /// filling it while `infoText(for:)` runs during view-body evaluation
    /// never mutates SwiftUI state mid-render.
    private let zipCommentCache = ZipCommentCache.shared
    /// See `GamesByNameCache`'s own doc comment — this is what keeps the
    /// "Clone of" column from rebuilding the whole DAT index once per row,
    /// per layout pass.
    private let gamesByNameCache = GamesByNameCache()
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
    /// True when `selectedRomFolder` IS this system's own Maintenance
    /// subfolder — jensyleo's own request (2026-09-11) that clicking it
    /// shows it in the Games panel like any other folder, but it must NEVER
    /// actually be scanned/fixed like one (a donor file matching the DAT by
    /// design would otherwise get silently folded into this system's own
    /// audit as if it were part of the real collection). Checked by
    /// "Scan Folder"'s own `isEnabled` above; Fix's own scope already
    /// self-limits to whatever's actually in `matchReport` for this path, so
    /// nothing additional is needed there as long as this folder is never
    /// scanned into one in the first place.
    private var isSelectedFolderMaintenanceSubfolder: Bool {
        selectedRomFolder != nil && selectedRomFolder == MaintenanceFolderSettings.subfolderURL(for: system)
    }

    /// Raw disk contents of the Maintenance subfolder, shown in place of the
    /// (always-empty, by design) audited Games table when it's selected —
    /// jensyleo's own request (2026-09-13): a plain, Finder-style listing
    /// (name/size/modified only, no Correct/Incorrect/Missing status), since
    /// this folder is a donor source that's deliberately never compared
    /// against the DAT or folded into duplicate-detection — see
    /// `isSelectedFolderMaintenanceSubfolder`'s own doc comment on why.
    /// Populated by `loadMaintenanceFolderFiles()`; never written to.
    @State private var maintenanceFolderFiles: [ScannedFile] = []
    @State private var isLoadingMaintenanceFolderFiles = false

    /// Lists this system's own Maintenance subfolder AND, when the DAT is
    /// already loaded, hashes and matches those files against it — jensyleo's
    /// own correction (2026-09-13), after a first pass that only listed raw
    /// files: "debe verse igual que las otras [carpetas]... con colores y
    /// todo. Exactamente igual" — a donor rom that's genuinely Correct (or
    /// Bad/Misnamed) must show that same real, colored status any other ROM
    /// folder would, not a flat "not scanned yet" placeholder. This match is
    /// its own entirely independent `ROMMatcher.match` call — its result
    /// NEVER touches `viewModel.auditReport`/`matchReport` (the real,
    /// official audit), so nothing here can affect this system's own
    /// Correct/Incorrect/Missing counts, duplicate-set detection, or any
    /// Fix action's own scope. Only the DISPLAY reuses the exact same
    /// `GameNodeBuilder` pipeline every other folder's own colored Games
    /// table already goes through — see `maintenanceGameNodes`'s own doc
    /// comment. A missing/unset folder just clears everything rather than
    /// erroring: the empty-state message already covers that case with its
    /// own wording.
    private func loadMaintenanceFolderFiles() {
        guard let folderURL = MaintenanceFolderSettings.subfolderURL(for: system) else {
            maintenanceFolderFiles = []
            maintenanceGameNodes = []
            maintenanceFolderReadErrorMessage = nil
            return
        }
        isLoadingMaintenanceFolderFiles = true
        maintenanceFolderFilesLoadGeneration += 1
        let generation = maintenanceFolderFilesLoadGeneration
        let preloadedGames = viewModel.preloadedGames
        let dat = viewModel.cachedDATFile
        let combine = combineRomAndCHD
        let viewModel = viewModel
        // jensyleo's own report (2026-09-19), a real screenshot: "Scan All
        // Folders" (which owns `viewModel.isBusy`/`scanProgress`/
        // `matchProgress`/`isMatching` for its own real run) and this
        // Maintenance-folder auto-load (triggered independently by
        // selection/DAT changes) can genuinely overlap — and since both
        // used to drive the exact SAME shared fields, the result was TWO
        // progress bars fighting over one set of numbers, shown at once.
        // "Unifica el criterio... que sea global, no solo para este caso":
        // rather than inventing a second flag, this claims the SAME
        // `isBusy` every other busy action already respects — if
        // something else already holds it, this run steps aside entirely
        // (no progress reporting, exactly like before this file's
        // 2026-09-19 change) rather than racing it for the same fields.
        let ownsProgressReporting = !viewModel.isBusy
        if ownsProgressReporting {
            viewModel.isBusy = true
        }
        // jensyleo's own report (2026-09-14): this used to re-read AND
        // re-hash the whole Maintenance folder from scratch every single
        // time it ran — selecting it in the sidebar, a DAT reload, the
        // toolbar button — taking real seconds against a real (~250MB)
        // Maintenance folder and reading as "stuck" when re-triggered
        // back-to-back. Reuses the SAME session-level cache
        // `LibraryViewModel.scan(system:)` already built for its own
        // donor-detection pass (`cachedMaintenanceDonorFiles`) — whichever
        // of the two runs first saves the other a redundant re-hash of the
        // exact same folder; both still respect the same invalidation
        // rule (only a real "Scan Maintenance Folder"/"Scan All Folders"
        // forces a fresh read).
        // jensyleo's own report (2026-09-16): "el problema persiste" — the
        // NAS-disconnected fix above never even ran, because this session
        // already had a successful hash pass cached from earlier (while
        // the NAS was still connected), and that stale cache was trusted
        // blindly regardless of whether the folder can currently be
        // reached at all. `maintenanceSubfolderUnreachable` (this same
        // view's own sidebar-row check) is the freshest signal available —
        // skip the cache and force a real, current read whenever it says
        // this folder is currently unreachable.
        let cachedHashedFiles = maintenanceSubfolderUnreachable ? nil : viewModel.cachedMaintenanceDonorFiles(matchingFolderPath: folderURL.path)
        // jensyleo's own follow-up report (2026-09-14): caching the hash
        // pass alone didn't fix "sigue igual" — a real, separate bug: this
        // ran as a plain (non-detached) `Task`, which inherits the calling
        // MainActor context. `FolderScanner.scan`/`ROMMatcher.match`/
        // `AuditReporter.generate`/`computeBaseGameNodes` are all plain
        // SYNCHRONOUS functions (no `await` of their own), so on a cache
        // MISS they ran straight on the main thread for however long a
        // real ~250MB scan+match takes — freezing the whole UI solid,
        // including the `ProgressView`'s own animation, which is exactly
        // why the message looked frozen/broken rather than merely slow.
        // `Task.detached` moves all of that off the main thread, same
        // pattern `LibraryViewModel.scan(system:)` already uses for its
        // own heavy work — only the final state writes below still hop
        // back to `@MainActor`.
        Task.detached(priority: .userInitiated) { [combine, dat, preloadedGames, viewModel, ownsProgressReporting] in
            let hashed: [HashedFile]
            let files: [ScannedFile]
            // jensyleo's own report (2026-09-16): with the NAS
            // disconnected, this used to log "Maintenance folder: found 0
            // file(s)" — a SUCCESS line — and the Games panel said "it's
            // currently empty", both flatly wrong: `try?` here was
            // silently collapsing a genuine "couldn't reach it" error
            // (`ScannerError.folderNotFound`, exactly what an unreachable
            // NAS mount throws) into the same empty array a truly empty
            // folder produces. The two are never the same thing and must
            // never be reported the same way — captured explicitly here so
            // the caller (`readError`, below) can tell them apart.
            var readErrorMessage: String?
            // jensyleo's own report (2026-09-19): this only ever showed a
            // bare indeterminate "Reading the Maintenance folder…" spinner,
            // with no numbers, even though a real (uncached) read+hash+
            // match pass here can take genuinely as long as the same pass
            // does for an ordinary ROM folder. Wired to the exact same
            // `viewModel` progress fields (`archiveListingProgress`,
            // `scanProgress`, `isMatching`, `matchProgress`) `scan(system:
            // folders:)` already drives — `scanProgressOverlay` already
            // knows how to render all of them, so this reuses that same
            // real, determinate bar instead of inventing a second one.
            var archiveListedHandler: (@Sendable (Int, Int) -> Void)?
            var hashProgressHandler: (@Sendable (ScanProgress) -> Void)?
            if ownsProgressReporting {
                archiveListedHandler = { [weak viewModel] read, total in
                    Task { @MainActor in viewModel?.archiveListingProgress = (read, total) }
                }
                hashProgressHandler = { [weak viewModel] progress in
                    Task { @MainActor in
                        viewModel?.archiveListingProgress = nil
                        viewModel?.scanProgress = progress
                    }
                }
            }
            if let cachedHashedFiles {
                hashed = cachedHashedFiles
                files = cachedHashedFiles.map(\.file).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } else {
                do {
                    let scanned = try FolderScanner.scan(paths: [folderURL]).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                    files = scanned
                    hashed = scanned.isEmpty ? [] : ((try? await CollectionHasher.hash(scannedFiles: scanned, algorithms: HashAlgorithmSettings.current, onProgress: hashProgressHandler, onArchiveListed: archiveListedHandler)) ?? [])
                } catch {
                    readErrorMessage = error.localizedDescription
                    files = []
                    hashed = []
                }
            }
            var nodes: [GameNode] = []
            if let dat, !hashed.isEmpty {
                if ownsProgressReporting {
                    await MainActor.run {
                        viewModel.scanProgress = nil
                        viewModel.isMatching = true
                        viewModel.matchProgress = nil
                    }
                }
                var matchProgressHandler: (@Sendable (Int, Int) -> Void)?
                if ownsProgressReporting {
                    matchProgressHandler = { [weak viewModel] completed, total in
                        Task { @MainActor in viewModel?.matchProgress = (completed, total) }
                    }
                }
                // jensyleo's own report (2026-09-29), right after adding
                // NES: the main folder scan (`LibraryViewModel.scan`) already
                // honors "Ignore CRC/hash verification for console/computer systems",
                // but this Maintenance-folder preview match had its own,
                // separate `ROMMatcher.match(...)` call that never passed
                // `nameOnlyMatching` at all — it always fell back to `false`
                // (hash-verified) regardless of the toggle, so a donor file
                // sitting in Maintenance would silently need a byte-perfect
                // hash match to preview as usable, even with the toggle on.
                if let matchReport = try? ROMMatcher.match(
                    dat: dat, hashedFiles: hashed, onProgress: matchProgressHandler,
                    nameOnlyMatching: !system.isMAMEStyle && MatchingPreferencesSettings.nameOnlyMatchingEnabled
                ),
                   let auditReport = try? AuditReporter.generate(from: matchReport)
                {
                    let aggStatus = Self.computeGameAggregateStatusByName(entries: auditReport.entries, preloadedGames: preloadedGames)
                    let gamesInFolder = Self.recomputeGamesInFolder(entries: auditReport.entries, selectedFolder: folderURL)
                    nodes = Self.computeBaseGameNodes(
                        hasAuditReport: true, auditEntries: auditReport.entries, selectedRomFolder: folderURL,
                        preloadedGames: preloadedGames, selectedDatabaseFilter: nil,
                        gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine
                    )
                }
            }
            await MainActor.run {
                // Always reset, even on a stale/discarded generation — this
                // run is the only one that ever claimed `isBusy`/the shared
                // progress fields in the first place when
                // `ownsProgressReporting` is true (a cache hit, or stepping
                // aside for an already-busy main scan, never touches them
                // at all), so nothing else could be relying on them still
                // being set once this specific run is done.
                if ownsProgressReporting {
                    viewModel.archiveListingProgress = nil
                    viewModel.scanProgress = nil
                    viewModel.isMatching = false
                    viewModel.matchProgress = nil
                    viewModel.isBusy = false
                }
                if cachedHashedFiles == nil, !hashed.isEmpty {
                    viewModel.cacheMaintenanceDonorFiles(folderPath: folderURL.path, files: hashed)
                }
                // Discard this result if a NEWER load has started since —
                // see `maintenanceFolderFilesLoadGeneration`'s own doc
                // comment. Note `isLoadingMaintenanceFolderFiles` is
                // deliberately NOT reset here on a stale hit: the newer,
                // still-in-flight run already owns that flag's next
                // (correct) transition to `false`.
                guard generation == maintenanceFolderFilesLoadGeneration else { return }
                maintenanceFolderFiles = files
                maintenanceGameNodes = nodes
                isLoadingMaintenanceFolderFiles = false
                // Only counts as "genuinely checked and confirmed empty"
                // when there was no read error — jensyleo's own doc
                // comment above on why the two must never be conflated.
                // Left `false` on a read failure so the NEXT attempt
                // (reconnecting, then reselecting/re-scanning) still tries
                // a real read instead of trusting this failed one's own
                // (wrong) "empty" result.
                hasLoadedMaintenanceFolderFilesOnce = readErrorMessage == nil
                maintenanceFolderReadErrorMessage = readErrorMessage
                if let readErrorMessage {
                    viewModel.logError("Couldn't read the Maintenance folder: \(readErrorMessage)")
                } else {
                    viewModel.logSuccess("Maintenance folder: found \(files.count) file(s).")
                }
            }
        }
    }

    /// The plain-selection counterpart to `loadMaintenanceFolderFiles()` —
    /// see `hasLoadedMaintenanceFolderFilesOnce`'s own doc comment for why
    /// this exists at all. Call this from anywhere that merely means "the
    /// Maintenance folder just became the selected one" (a sidebar click,
    /// this view first appearing already pointed at it); call
    /// `loadMaintenanceFolderFiles()` directly, unconditionally, from
    /// anywhere that means "its own real content might have changed" (an
    /// explicit Scan action, deleting/recreating its subfolder, a DAT
    /// reload).
    private func loadMaintenanceFolderFilesIfNeeded() {
        // jensyleo's own request (2026-09-22), added a toggle for this
        // after reporting a real live case: with the Maintenance root on
        // an unreachable NAS, merely SELECTING this row (no Scan ever
        // requested) still triggered a real disk read here — every other
        // ROM folder row never re-reads anything on a plain click, only
        // an explicit Scan does. `MaintenanceAutoScanOnSelectSettings`
        // (Settings → General → "Scanning") lets Maintenance match that
        // same behavior when turned off; on (the original, already-
        // shipped default) keeps reading it automatically the first time
        // each session, exactly as before.
        guard MaintenanceAutoScanOnSelectSettings.isEnabled else { return }
        guard !hasLoadedMaintenanceFolderFilesOnce else { return }
        loadMaintenanceFolderFiles()
    }

    /// jensyleo's own report (2026-09-13): "scan maintenance folder no
    /// funciona" — `loadMaintenanceFolderFiles()` on its own DID refresh
    /// the list, but silently, in the background, unless the Maintenance
    /// subfolder happened to already be the one selected in the sidebar
    /// (`isSelectedFolderMaintenanceSubfolder` is what actually gates
    /// showing `maintenanceFolderFilesList` at all) — from the toolbar
    /// button alone, with some other folder/game selected, nothing visibly
    /// changed, reading as completely broken. This also selects the
    /// Maintenance subfolder itself first, so the refreshed listing is
    /// immediately what's on screen — same as clicking it directly in the
    /// sidebar, just from the toolbar instead.
    /// - Parameter navigateToFolder: `true` (the toolbar's own "Scan
    ///   Maintenance Folder" action) selects the Maintenance subfolder so
    ///   the just-refreshed listing is immediately what's on screen — see
    ///   this function's own history below for why that's the right
    ///   default there. `false` (the sidebar row's own context menu,
    ///   jensyleo's own request, 2026-09-22: "que no te haga saltar a ese
    ///   folder, que se quede donde está") refreshes Maintenance's data in
    ///   the background without disturbing whatever's currently selected —
    ///   `loadMaintenanceFolderFiles()` below never depended on
    ///   `selectedRomFolder` in the first place, so this is safe either way.
    private func startScanMaintenanceFolder(navigateToFolder: Bool = true) {
        if navigateToFolder {
            // `selectedDatabaseFilter` and `selectedRomFolder` are mutually
            // exclusive (see `selectedRomFolder`'s own doc comment) and the
            // Games panel's own branch checks `selectedDatabaseFilter` FIRST —
            // real bug just found live by jensyleo: the log correctly showed
            // "found N file(s)" but the panel itself never changed, because a
            // Database category was still selected and this function, unlike
            // every real sidebar click (see line ~4062), wasn't clearing it.
            selectedDatabaseFilter = nil
            selectedRomFolder = MaintenanceFolderSettings.subfolderURL(for: system)
            selectedGameID = nil
            selectedRomID = nil
        }
        // jensyleo's own request (2026-09-14), after a real live bug this
        // exact gap caused: `MaintenanceDonorDetector`'s own "donor
        // available" flag is only ever computed as part of a REAL scan of
        // this system's own ROM folders (`LibraryViewModel.scan`), never by
        // `loadMaintenanceFolderFiles()` alone — so browsing Maintenance in
        // a session that never ran a real Scan first showed donor
        // indicators computed against a STALE or nonexistent match report.
        // "Cuando se escanee la carpeta de mantenimiento, fuerza a que se
        // escaneen las otras carpetas si se va a trabajar con ellas" — if
        // this system hasn't been scanned yet this session, run a real
        // "Scan All Folders" first, THEN refresh the Maintenance listing
        // against its up-to-date result, instead of silently showing
        // donor colors that might not reflect what's actually on disk.
        // This is the one action that means "Maintenance itself just
        // changed, trust nothing cached about it" — invalidate before
        // refreshing the listing below so any scan running from here on
        // (this one, or a later "Scan Folder"/"Scan All Folders") re-reads
        // the real folder instead of reusing a now-possibly-stale cache.
        viewModel.invalidateMaintenanceDonorCache()
        if viewModel.hasMatchReport {
            // A real scan already ran this session — Maintenance's own
            // listing is about to refresh, but every OTHER already-scanned
            // folder's own "donor available" coloring is computed from
            // THAT earlier scan and won't reflect whatever just changed in
            // Maintenance until it's rescanned itself. jensyleo's own
            // request (2026-09-14): a one-line reminder, configurable in
            // Settings → General, instead of silent staleness.
            loadMaintenanceFolderFiles()
            if MaintenanceRescanNoticeSettings.isEnabled {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "Rescan Other Folders to Update Their View"
                alert.informativeText = "The Maintenance folder's own listing just refreshed, but any other ROM folder already scanned this session keeps showing whatever donor availability it computed earlier — rescan it (Scan → Scan Folder/Scan All Folders) to bring its own \"Missing (available in Maintenance folder)\" coloring up to date."
                alert.addButton(withTitle: "OK")
                alert.showsSuppressionButton = true
                alert.runModal()
                if alert.suppressionButton?.state == .on {
                    UserDefaults.standard.set(false, forKey: MaintenanceRescanNoticeSettings.storageKey)
                }
            }
        } else {
            Task {
                await viewModel.scan(system: system)
                loadMaintenanceFolderFiles()
            }
        }
    }

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
    /// Whether each of the five main panels shows at all — see
    /// `PanelVisibilitySettings`'s own doc comment
    /// (`ViewOptionsSettingsView.swift`) for the storage keys and why this
    /// reads them directly rather than duplicating the setting.
    /// Split (2026-08-12) into two independent toggles — what used to be
    /// one combined "Database / ROM folder sidebar" switch — since
    /// `databaseList` itself is really two separate trees (see its own doc
    /// comment: mutually exclusive selection, already their own draggable
    /// split). `visibleTopPanes` shows the whole `databaseList` pane
    /// whenever either half is on; `databaseList` itself decides which of
    /// its own two halves to actually render.
    @AppStorage(PanelVisibilitySettings.showDatabaseTreeKey) private var showDatabaseTree = true
    @AppStorage(PanelVisibilitySettings.showRomFolderTreeKey) private var showRomFolderTree = true
    @AppStorage(PanelVisibilitySettings.showGamesPanelKey) private var showGamesPanel = true
    @AppStorage(PanelVisibilitySettings.showRomsPanelKey) private var showRomsPanel = true
    @AppStorage(PanelVisibilitySettings.showDetailPanelKey) private var showDetailPanel = true
    @AppStorage(PanelVisibilitySettings.showLogPanelKey) private var showLogPanel = true
    @AppStorage(DependencyColumnSettings.showBiosKey) private var showBiosBadge = true
    @AppStorage(DependencyColumnSettings.showCHDKey) private var showCHDBadge = true
    @AppStorage(DependencyColumnSettings.showHardwareKey) private var showHardwareBadge = true
    @AppStorage(DependencyColumnSettings.showSamplesKey) private var showSamplesBadge = true
    @AppStorage(DetailColumnSettings.showDriverStatusKey) private var showDriverStatusBadge = true
    @AppStorage(DetailColumnSettings.showDisplayKey) private var showDisplayBadge = true
    @AppStorage(DetailColumnSettings.showPlayersKey) private var showPlayersBadge = true
    @AppStorage(DetailPanelGameFieldSettings.showFileNameKey) private var showDetailGameFileName = true
    @AppStorage(DetailPanelGameFieldSettings.showExpectedFileNameKey) private var showDetailExpectedFileName = true
    @AppStorage(DetailPanelGameFieldSettings.showSizeKey) private var showDetailGameSize = true
    @AppStorage(DetailPanelGameFieldSettings.showOneGameOneROMKey) private var showDetailOneGameOneROM = true
    @AppStorage(DetailPanelGameFieldSettings.showInfoKey) private var showDetailInfo = true
    @AppStorage(DetailPanelGameFieldSettings.showCloneOfKey) private var showDetailGameCloneOf = true
    @AppStorage(DetailPanelGameFieldSettings.showRequiredBiosKey) private var showDetailRequiredBios = true
    @AppStorage(DetailPanelGameFieldSettings.showCHDKey) private var showDetailCHD = true
    @AppStorage(DetailPanelGameFieldSettings.showSamplesKey) private var showDetailSamples = true
    @AppStorage(DetailPanelGameFieldSettings.showBiosKey) private var showDetailBios = true
    @AppStorage(DetailPanelGameFieldSettings.showYearKey) private var showDetailYear = true
    @AppStorage(DetailPanelGameFieldSettings.showManufacturerKey) private var showDetailManufacturer = true
    @AppStorage(DetailPanelGameFieldSettings.showCategoryKey) private var showDetailCategory = true
    @AppStorage(DetailPanelGameFieldSettings.showDeviceRefsKey) private var showDetailDeviceRefs = true
    @AppStorage(DetailPanelGameFieldSettings.showCloneOfInternalNameKey) private var showDetailCloneOfInternalName = true
    @AppStorage(DetailPanelGameFieldSettings.showFamilyKey) private var showDetailFamily = true
    @AppStorage(DetailPanelGameFieldSettings.showDependenciesKey) private var showDetailDependencies = true
    @AppStorage(DetailPanelGameFieldSettings.showDetailsKey) private var showDetailDetails = true
    @AppStorage(DetailPanelGameFieldSettings.fieldOrderKey) private var gameFieldOrderRaw = DetailGameField.allCases.map(\.rawValue).joined(separator: ",")
    @AppStorage(DetailPanelRomFieldSettings.showFileNameKey) private var showDetailRomFileName = true
    @AppStorage(DetailPanelRomFieldSettings.showInfoKey) private var showDetailRomInfo = true
    @AppStorage(DetailPanelRomFieldSettings.showSizeKey) private var showDetailRomSize = true
    @AppStorage(DetailPanelRomFieldSettings.showCRCKey) private var showDetailRomCRC = true
    @AppStorage(DetailPanelRomFieldSettings.showSHA1Key) private var showDetailRomSHA1 = true
    @AppStorage(DetailPanelRomFieldSettings.showFolderKey) private var showDetailRomFolder = true
    @AppStorage(DetailPanelRomFieldSettings.showMD5Key) private var showDetailRomMD5 = true
    @AppStorage(DetailPanelRomFieldSettings.showDumpStatusKey) private var showDetailRomDumpStatus = true
    @AppStorage(DetailPanelRomFieldSettings.showTypeKey) private var showDetailRomType = true
    @AppStorage(DetailPanelRomFieldSettings.showSerialKey) private var showDetailRomSerial = true
    @AppStorage(DetailPanelRomFieldSettings.showSHA256Key) private var showDetailRomSHA256 = true
    @AppStorage(DetailPanelRomFieldSettings.showHeaderKey) private var showDetailRomHeader = true
    private var visibleTopPanes: [SplitPane] {
        var panes: [SplitPane] = []
        if showDatabaseTree || showRomFolderTree { panes.append(SplitPane(minLength: 150) { databaseList }) }
        if showGamesPanel { panes.append(SplitPane(minLength: 220) { gamesList }) }
        if showRomsPanel { panes.append(SplitPane(minLength: 260) { romsList }) }
        return panes
    }
    private var visibleBottomPanes: [SplitPane] {
        var panes: [SplitPane] = []
        if showDetailPanel { panes.append(SplitPane(minLength: 260) { detailPane }) }
        if showLogPanel { panes.append(SplitPane(minLength: 220) { logPane }) }
        return panes
    }
    @AppStorage("ROMForge.isDatabaseSectionExpanded") private var isDatabaseSectionExpanded = true
    @AppStorage("ROMForge.isRomFilesSectionExpanded") private var isRomFilesSectionExpanded = true
    /// Which "Database" branches the user has actually left switched on —
    /// see `DatabaseFilterVisibilitySettings`'s own doc comment
    /// (`GeneralSettingsView.swift`) for the storage format and default
    /// split (the 10 pre-existing branches on, the 4 added alongside this
    /// toggle off). Read here rather than duplicating the setting, so
    /// General Settings and the tree itself can never disagree about which
    /// branches are visible.
    // Real gap found live by jensyleo (2026-09-23): this used to read ONE
    // key shared by every system regardless of kind — see
    // `DatabaseFilterVisibilitySettings.storageKey(forMAME:)`'s own doc
    // comment. Both per-kind keys are declared unconditionally (a
    // property-wrapper key must be a constant, it can't reference `system`
    // — `LibraryDetailView` has no custom `init` to work around that) and
    // `enabledDatabaseFiltersRaw` below just picks the one that matches the
    // CURRENT system — still fully reactive to either key changing
    // elsewhere (e.g. Settings), since both remain real `@AppStorage`.
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey(forMAME: true)) private var enabledDatabaseFiltersRawMAME = DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: true)
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey(forMAME: false)) private var enabledDatabaseFiltersRawConsole = DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: false)
    private var enabledDatabaseFiltersRaw: String {
        system.isMAMEStyle ? enabledDatabaseFiltersRawMAME : enabledDatabaseFiltersRawConsole
    }
    private var visibleDatabaseFilters: [DatabaseFilter] {
        DatabaseFilterVisibilitySettings.enabledFilters(from: enabledDatabaseFiltersRaw)
    }
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
    /// Filters the "Database" tree by game name/manufacturer — jensyleo's
    /// own alternative proposal (2026-08-11) once a flattened, uncapped
    /// "All games" (commit `b7a394b`) froze the app solid on a real click:
    /// rendering thousands of `DisclosureGroup`/`List` rows synchronously is
    /// what actually costs real time, not which container holds them — so
    /// the only genuinely safe way to "see the whole category" is to never
    /// need all its rows on screen at once in the first place. A non-empty
    /// search narrows a real MAME DAT's ~43,000 "All games" down to however
    /// many actually match, almost always small, so `treeChildren(forCategory:)`
    /// skips its normal 500-row cap while this is active (see its own use of
    /// `databaseSearchText` below) — still bounded by `maxSearchResultsCap`
    /// as a defensive backstop, never fully unbounded.
    @State private var databaseSearchText: String = ""
    /// Per-category "load more" — jensyleo's own request alongside the
    /// search bar: rather than only ever offering the fixed 500-row preview
    /// plus "use the Games table for the full list", a plain click grows
    /// that one category's own inline cap by `treeLoadMoreIncrement` at a
    /// time. Each click still only ever renders one bounded increment's
    /// worth of *new* rows — never the whole remaining category at once —
    /// so this can never reproduce the `b7a394b` freeze, no matter how many
    /// times a category gets expanded; it just takes that many clicks to
    /// reach the end of a genuinely huge one. Resets to `nil` (falls back to
    /// `maxTreeChildrenPerCategory`) whenever the category's own cache is
    /// dropped (collapsed, or the underlying data changed) — a stale raised
    /// cap for a category the user isn't even looking at anymore isn't worth
    /// carrying forward.
    @State private var databaseCategoryVisibleCap: [DatabaseFilter: Int] = [:]
    /// Which game rows (parents with clone children, under "All games") are
    /// currently expanded in the "Database" tree — jensyleo's own request
    /// (2026-08-11): pressing the right-arrow key while standing on a game
    /// row should open its own clone disclosure, matching `NSOutlineView`'s
    /// native keyboard behavior (Finder's list view, System Settings' own
    /// sidebar, etc.). Needed as its own explicit `@State` (rather than
    /// each `DisclosureGroup` managing its own internal expansion) because
    /// a key press has to be able to *set* this from outside the
    /// `DisclosureGroup` itself — see `gameTreeNodeExpansion(for:)`.
    @State private var expandedGameTreeNodes: Set<String> = []
    /// Debounce/cancellation plumbing for
    /// `refreshExpandedDatabaseCategoryCachesAsync(debounced:)` — same
    /// generation-counter pattern as `pendingFolderRecompute`/
    /// `folderRecomputeGeneration`, kept separate since this recompute (the
    /// "Database" tree specifically) fires independently of, and far more
    /// often than, that one (every keystroke vs. every click).
    @State private var pendingDatabaseTreeRecompute: Task<Void, Never>?
    @State private var databaseTreeRecomputeGeneration = 0
    /// Captured from the "Database" category tree's own `List`/
    /// `ScrollViewReader` (`databaseSectionPane`) — jensyleo's own report
    /// (2026-08-11): pressing ↓ repeatedly past whatever's currently visible
    /// didn't scroll the list at all; the selection kept moving (tracked
    /// correctly in `selectedGameID`/`selectedDatabaseFilter`/
    /// `selectedRomFolder`) but scrolled off-screen with nothing bringing it
    /// back into view, which read as focus having silently jumped to the
    /// unrelated Games table on the right. `moveDatabaseSelection(by:)`
    /// calls `scrollTo` on this right after moving — same pattern already
    /// used for the Games table itself, see `gameTableScrollProxy`'s own
    /// doc comment. Split into its own separate proxy (2026-08-12, alongside
    /// `romFolderListScrollProxy` below) once "Database" and "ROM folder"
    /// became two independent `List`s/scroll regions in their own right —
    /// `scrollTo` only ever works within the same `ScrollViewReader` that
    /// produced a given proxy.
    @State private var databaseListScrollProxy: ScrollViewProxy?
    /// Same role as `databaseListScrollProxy`, for the separate "ROM
    /// folder" `List` (`romFolderSectionPane`) — see that property's own
    /// doc comment for why one proxy no longer covers both.
    @State private var romFolderListScrollProxy: ScrollViewProxy?
    /// jensyleo's own report (2026-08-13): up/down/left/right stopped doing
    /// anything at all in "Database" — confirmed live with `AXFocusedUIElement`
    /// pointing at the window itself, not any control inside it. Neither
    /// pane's `List` uses a `selection:` binding (a category/leaf row needs
    /// its own click + independent disclosure, see `databaseSectionPane`'s
    /// own doc comment), so clicking a row's `Button` selects it but never
    /// makes anything an actual SwiftUI focus target — `.onKeyPress`, which
    /// only ever fires for a view that's itself focused or an ancestor of
    /// whatever is, then has nothing to bubble from at all. `.focusable()` +
    /// `.focused($isDatabasePaneFocused)` on the pane, claimed explicitly
    /// inside every row-selecting action in it (category headers, tree
    /// leaves, "Load more"), fixes that at the source instead of hoping a
    /// click happens to grant focus on its own.
    @FocusState private var isDatabasePaneFocused: Bool
    /// Same fix, for the "ROM folder" pane — see `isDatabasePaneFocused`'s
    /// own doc comment.
    @FocusState private var isRomFolderPaneFocused: Bool

    /// jensyleo's own report (2026-09-15), confirmed live via a screen
    /// recording: after clicking a NEW row in the Games table (a genuine
    /// `selection` value change, not merely a re-click), arrow keys kept
    /// moving the ROMS table's own selection instead — `.focusable()`/
    /// `.focused()` per-`Table`, the exact fix that already works for the
    /// sidebar's plain `List`-based panes above, turned out NOT to
    /// reliably move real AppKit key-window focus between two independent
    /// `Table` (NSTableView-backed) views side by side on macOS 27, even
    /// though SwiftUI's own `@FocusState` claimed it had. Rather than keep
    /// fighting that per-view focus transfer, both tables now just report
    /// "the user last clicked into me" via a plain closure
    /// (`GameTreeTableView`/`RomsTableView`'s own `onFocusRequested`),
    /// recorded here — and a single shared `NSEvent` monitor
    /// (`installResultsArrowKeyMonitor()`, called from `.onAppear`) does
    /// the actual up/down dispatch, sidestepping the unreliable
    /// cross-Table focus transfer entirely.
    private enum ResultsPane { case games, roms }
    @State private var activeResultsPane: ResultsPane = .games
    /// jensyleo's own report (2026-09-16): `romsList`'s own `.id(selectedGameNode
    /// ?.id)` correctly forces the Roms `Table` to rebuild (clearing its own
    /// stale selection highlight — see that modifier's own doc comment for
    /// why a rebuild, not just clearing the `selection` binding, was needed)
    /// whenever the selected GAME actually changes — but re-clicking the
    /// SAME already-selected game never changes that `id` at all, so
    /// nothing forces a rebuild then, and the Roms selection stayed stuck.
    /// Bumped ONLY on a same-game reclick (see `lastGamesClickID`'s own doc
    /// comment) and folded into that `.id(...)` so that specific case still
    /// forces the rebuild — a real perf issue found by code audit
    /// (2026-09-16): an earlier version of this fix bumped it on EVERY
    /// click in the Games table, forcing a full Roms `Table` rebuild (every
    /// `TableColumn`/context-menu closure) on the single most common
    /// interaction in the whole app, even though a genuine game change
    /// already gets a fresh `.id()` for free from `selectedGameNode?.id`
    /// alone.
    @State private var romsResetGeneration = 0
    /// The Games selection `onFocusRequested` last saw, so it can tell a
    /// genuine game change (does nothing extra — `.id(selectedGameNode?.id)`
    /// already handles it) apart from a same-game reclick (bumps
    /// `romsResetGeneration`, since the `.id()` alone wouldn't change).
    @State private var lastGamesClickID: String?
    /// Real bug found live by jensyleo (2026-09-15) in the FIRST version of
    /// this fix: gating the monitor on `!isDatabasePaneFocused &&
    /// !isRomFolderPaneFocused` assumed clicking a Games/Roms row would
    /// naturally take real AppKit focus away from the sidebar — but since
    /// neither Table claims `.focusable()`/`.focused()` anymore (the whole
    /// point of this fix, see this monitor's own doc comment), a sidebar
    /// pane's `@FocusState` never gets told to relinquish once true, so it
    /// stays true FOREVER after the first sidebar click. The monitor then
    /// always stepped aside, and the sidebar's own (correctly-working)
    /// `.onKeyPress` kept eating every arrow key even after clicking into
    /// Games/Roms. Tracked explicitly instead: `true` only while
    /// Games/Roms was the last of the four panes actually clicked, set
    /// `false` at every one of the sidebar's own `isDatabasePaneFocused`/
    /// `isRomFolderPaneFocused = true` call sites.
    @State private var resultsPaneIsActive = false
    /// The token `NSEvent.addLocalMonitorForEvents` returns — held so
    /// `.onDisappear` can remove it; never leave a monitor installed after
    /// this view goes away, or every keystroke in every other window
    /// keeps running its handler for nothing.
    @State private var resultsArrowKeyMonitor: Any?

    /// Installs the monitor `activeResultsPane`'s own doc comment
    /// describes. Deliberately steps ASIDE (returns the event untouched)
    /// whenever the sidebar's own `isDatabasePaneFocused`/
    /// `isRomFolderPaneFocused` is true — that pane's own `.onKeyPress`
    /// already handles its arrows correctly (it's a plain `List`, not a
    /// `Table`, and was never affected by this bug), so this monitor must
    /// never steal from it. NSEvent key codes 125 (down), 126 (up), 121
    /// (Page Down), and 116 (Page Up) are the only ones ever intercepted;
    /// everything else passes through completely unmodified, exactly as if
    /// this monitor didn't exist. Page Up/Down added (2026-09-29) —
    /// jensyleo's own report, same large-ROM-folder case as
    /// `moveGameSelection(by:)`'s own cap-expansion doc comment: neither
    /// key did anything at all before, since the native `Table`'s own
    /// handling is exactly what this whole monitor exists to route around.
    private func installResultsArrowKeyMonitor() {
        guard resultsArrowKeyMonitor == nil else { return }
        resultsArrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard resultsPaneIsActive else { return event }
            switch event.keyCode {
            case 125:
                if activeResultsPane == .games { moveGameSelection(by: 1) } else { moveRomSelection(by: 1) }
                return nil
            case 126:
                if activeResultsPane == .games { moveGameSelection(by: -1) } else { moveRomSelection(by: -1) }
                return nil
            case 121:
                if activeResultsPane == .games { moveGameSelection(by: Self.pageStepRowCount) } else { moveRomSelection(by: Self.pageStepRowCount) }
                return nil
            case 116:
                if activeResultsPane == .games { moveGameSelection(by: -Self.pageStepRowCount) } else { moveRomSelection(by: -Self.pageStepRowCount) }
                return nil
            default:
                // Type-ahead (typing a letter to jump to a game) — Games
                // only, same reasoning as `handleGamesTypeAheadKeyDown`'s
                // own doc comment. Any other key (including every
                // modified combination) falls through completely
                // unmodified, so ⌘-anything, Return, Delete, etc. still
                // reach their normal handling elsewhere.
                if activeResultsPane == .games, handleGamesTypeAheadKeyDown(event) {
                    return nil
                }
                return event
            }
        }
    }

    /// How many rows Page Up/Down move at once — an approximation of a
    /// screenful in this dense a `Table`, not tied to the window's actual
    /// current height (which would need a live row-height/viewport
    /// measurement this app doesn't track anywhere else).
    private static let pageStepRowCount = 20

    private func removeResultsArrowKeyMonitor() {
        if let resultsArrowKeyMonitor {
            NSEvent.removeMonitor(resultsArrowKeyMonitor)
        }
        resultsArrowKeyMonitor = nil
    }

    @State private var romFolderReorderMonitor: Any?
    /// The drag's own starting Y, in the same top-left "window" coordinate
    /// space `romFolderRowFrames` already uses (via `reportReorderFrame`'s
    /// own `.global` `GeometryReader`) — captured once at mouse-down, so
    /// every subsequent `.leftMouseDragged` can compute a running
    /// translation the same way `DragGesture.translation` used to.
    @State private var romFolderReorderStartY: CGFloat?

    /// jensyleo's own report (2026-09-17): "⌘-arrastrar se pone a mover un
    /// poco, queda congelado, y después no permite hacer ningún otro
    /// intento" — root-caused live via temporary debug logging: macOS 27's
    /// `NSTableView` (a `List` row's own backing) claims the mouse-dragged
    /// event stream at the AppKit level as soon as it recognizes a drag
    /// starting on one of its cells, a layer BELOW where SwiftUI's
    /// `.highPriorityGesture` can arbitrate — so `ReorderGripHandle`'s own
    /// `DragGesture` got exactly one `onChanged` and then total silence,
    /// including no `onEnded` on mouse-up, permanently "stuck".
    ///
    /// Fixed the same way `resultsArrowKeyMonitor` above already fixed an
    /// earlier macOS 27 regression (cross-`Table` keyboard routing): bypass
    /// SwiftUI's gesture system entirely and track raw mouse events via a
    /// local `NSEvent` monitor, which sees every event BEFORE any gesture
    /// recognizer (AppKit's or SwiftUI's) gets a chance to claim it — it
    /// can never be starved out by `NSTableView`'s own tracking the way a
    /// child SwiftUI gesture could be.
    ///
    /// Hit-testing uses `romFolderRowFrames` (already published by every
    /// row's own `reportReorderFrame(_:)`) — a mouse-down only starts a
    /// drag when ⌘ is held AND the click lands within the trailing ~32pt
    /// of some row's own frame (approximately where its grip icon sits;
    /// generous on purpose, since this only ever needs to distinguish
    /// "clicked near the grip" from "clicked the row's own selectable
    /// area" a few dozen points to its left). Every event this monitor
    /// doesn't recognize as part of an active reorder is returned
    /// untouched, so it never affects any other click/drag anywhere else
    /// in the app.
    private func installRomFolderReorderMonitor() {
        guard romFolderReorderMonitor == nil else { return }
        romFolderReorderMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            switch event.type {
            case .leftMouseDown:
                if NSEvent.modifierFlags.contains(.command),
                   let point = windowTopLeftPoint(for: event),
                   let index = romFolderGripIndex(at: point) {
                    draggingRomFolderIndex = index
                    dragPreviewRomFolderIndex = index
                    dragRomFolderOffset = 0
                    romFolderReorderStartY = point.y
                    return nil
                }
                // jensyleo's own report (2026-09-19): selecting a ROM
                // folder sometimes needed a second click to actually take —
                // the same root cause as the reorder-grip regression this
                // monitor already exists to work around: `NSTableView` can
                // claim the mouse-down event at the AppKit level before
                // SwiftUI's own `.onTapGesture` gets a chance to recognize
                // it, so the first click's own gesture sometimes never
                // fires. Applying the selection directly from the raw
                // event guarantees it lands on the very first physical
                // click; the event is still returned unmodified
                // afterward, so `NSTableView`'s own normal handling
                // (hover, focus, etc.) proceeds exactly as it did before.
                if let point = windowTopLeftPoint(for: event) {
                    if let hitIndex = romFolderRowIndex(at: point), localRomFolderOrder.indices.contains(hitIndex) {
                        selectRomFolder(localRomFolderOrder[hitIndex])
                    }
                }
                return event
            case .leftMouseDragged:
                guard let from = draggingRomFolderIndex, let startY = romFolderReorderStartY,
                      let point = windowTopLeftPoint(for: event)
                else { return event }
                let translation = point.y - startY
                dragRomFolderOffset = translation
                let rowHeight = ReorderGripHandle.measuredRowPitch(at: from, rowFrames: romFolderRowFrames, fallback: 32)
                let steps = (translation / rowHeight).rounded()
                let target = min(max(from + Int(steps), 0), max(localRomFolderOrder.count - 1, 0))
                if dragPreviewRomFolderIndex != target {
                    dragPreviewRomFolderIndex = target
                }
                return nil
            case .leftMouseUp:
                guard let from = draggingRomFolderIndex else { return event }
                if let to = dragPreviewRomFolderIndex, from != to {
                    moveRomFolder(from: from, to: to)
                }
                draggingRomFolderIndex = nil
                dragPreviewRomFolderIndex = nil
                dragRomFolderOffset = 0
                romFolderReorderStartY = nil
                return nil
            default:
                return event
            }
        }
    }

    private func removeRomFolderReorderMonitor() {
        if let romFolderReorderMonitor {
            NSEvent.removeMonitor(romFolderReorderMonitor)
        }
        romFolderReorderMonitor = nil
    }

    /// Converts an `NSEvent`'s own window-relative, bottom-left-origin
    /// `locationInWindow` into the same top-left-origin space
    /// `reportReorderFrame(_:)`'s `.global` `GeometryReader` already
    /// reports `romFolderRowFrames` in — both ultimately anchored to this
    /// same window's own root, so comparing the two directly is safe
    /// without ever needing real screen coordinates.
    private func windowTopLeftPoint(for event: NSEvent) -> CGPoint? {
        guard let window = event.window else { return nil }
        let contentHeight = window.contentView?.bounds.height ?? window.frame.height
        return CGPoint(x: event.locationInWindow.x, y: contentHeight - event.locationInWindow.y)
    }

    /// Which ROM folder row (if any) a point sits over, restricted to
    /// roughly where that row's own grip icon actually is (its trailing
    /// ~32pt) — see `installRomFolderReorderMonitor`'s own doc comment.
    private func romFolderGripIndex(at point: CGPoint) -> Int? {
        for (index, frame) in romFolderRowFrames {
            let gripMinX = frame.maxX - 32
            if point.x >= gripMinX, point.x <= frame.maxX, point.y >= frame.minY, point.y <= frame.maxY {
                return index
            }
        }
        return nil
    }

    /// Which ROM folder row (if any) a point sits over, anywhere within its
    /// full frame — unlike `romFolderGripIndex(at:)`, not restricted to the
    /// grip's own trailing edge. Used by `installRomFolderReorderMonitor`'s
    /// plain-click fallback below, which needs to recognize a click
    /// anywhere on the row, not just near the grip.
    ///
    /// jensyleo's own report (2026-09-19): a click landing exactly on the
    /// hairline boundary between two rows sometimes hit neither frame at
    /// all — adjacent rows' own published frames don't always share a
    /// perfectly touching edge (sub-pixel rounding from SwiftUI's layout),
    /// so a point sitting in that gap fails `frame.contains(point)` for
    /// both. When that happens, this falls back to the row whose bottom
    /// edge is closest just above the point — jensyleo's own preference:
    /// a border-zone click should count as hitting the row ABOVE it, not
    /// the one below.
    private func romFolderRowIndex(at point: CGPoint) -> Int? {
        for (index, frame) in romFolderRowFrames where frame.contains(point) {
            return index
        }
        let boundaryTolerance: CGFloat = 6
        return romFolderRowFrames
            .filter { _, frame in
                point.x >= frame.minX && point.x <= frame.maxX && point.y >= frame.maxY && point.y - frame.maxY <= boundaryTolerance
            }
            // The row whose bottom edge sits closest to (just above) the
            // point — i.e. the largest `maxY` among the candidates found.
            .max { $0.value.maxY < $1.value.maxY }
            .map(\.key)
    }
    /// A local mirror of `system.romFolderURLs`, rendered by
    /// `romFolderListContent` instead of `system.romFolderURLs` directly —
    /// jensyleo's own report (2026-08-13): reordering with the ↑/↓ buttons
    /// stayed "igual de lenta" (~1s) even after switching to a Release
    /// build and to position-based `ForEach` identity, ruling out both an
    /// unoptimized build and a `List` row-move animation as the cause.
    /// What's actually on the critical path for *any* edit that goes
    /// through `onAddFolder`: it flows all the way out to `ContentView`,
    /// into `SystemLibraryStore.update(_:)`, and back down as a changed
    /// `system` value — and since `system` is a plain stored property (not
    /// something narrower SwiftUI can diff around), that forces this
    /// entire `LibraryDetailView`'s `body` — including the Games `Table`,
    /// which on this system's real MAME DAT holds tens of thousands of
    /// rows — to fully re-evaluate before the reordered "ROM folder" list
    /// can even show its new order. Rendering from this local `@State`
    /// instead means the reorder itself updates instantly, from a diff
    /// against only 6-ish rows — `onAddFolder` (and whatever it costs
    /// elsewhere) still happens, just no longer gates what the user
    /// actually sees change. Kept in sync with `system.romFolderURLs`
    /// on appear and whenever it changes from somewhere else entirely
    /// (Settings' "Reset ROM Folder View"/purge actions, another window).
    @State private var localRomFolderOrder: [URL] = []
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
    /// Presentation-only parent/clone family read (MAME's own `cloneof`
    /// tree) against `gameAggregateStatusByName` — never an audit category
    /// of its own, just a "3/5 clones present" badge and a "clone present,
    /// parent missing" highlight in the Games table. Recomputed alongside
    /// `gameAggregateStatusByName` itself, from the same already-scanned
    /// data — see `ParentCloneSummary`'s own doc comment.
    @State private var cachedParentCloneSummary = ParentCloneSummary(cloneCompletionByParent: [:], clonesMissingParent: [])
    /// Same "computed alongside `preloadedGames`, never a scan/audit
    /// category" philosophy as `cachedParentCloneSummary` right above —
    /// this one only ever depends on the loaded DAT's own descriptions and
    /// `regionOrderRaw` (never on `gameAggregateStatusByName`/any scan
    /// result at all), so a family's own preferred variant and star don't
    /// change just because a rescan happened. See `OneGameOneROMSummary`'s
    /// own doc comment.
    @State private var cachedOneGameOneROMSummary = OneGameOneROMSummary.empty
    /// How many rows in the CURRENT scope (folder/category) "Show Only
    /// 1G1R" is actually hiding right now — jensyleo's own report
    /// (2026-08-25): with the toolbar button gone, nothing in the Games
    /// table itself said whether the toggle was doing anything, so a
    /// family with no recognized-region duplicates (nothing to hide) read
    /// exactly like the filter being broken. Surfaced in `gamesListTitle`.
    @State private var cachedHiddenOneGameOneROMCount = 0
    /// "Show only 1G1R" — jensyleo's own spec (2026-08-19) called this a
    /// one-off, un-persisted display filter (a plain `@State`, toggled from
    /// the toolbar). Moved to `@AppStorage` (2026-08-24) alongside its own
    /// move from the toolbar into Settings → View Options → "1G1R" — once
    /// it's a Settings toggle rather than a toolbar action button, leaving
    /// it as ephemeral `@State` would mean it silently reset to "off" every
    /// relaunch despite living right next to `regionOrderRaw` (a genuine,
    /// persisted preference) in the same Settings section, which would
    /// read as broken rather than intentional.
    @AppStorage(OneGameOneROMSettings.showOnlyKey) private var show1G1ROnly = false
    /// The user's own region-priority order (Settings → View Options),
    /// read here as the raw comma-joined string `RegionOrderSettings`
    /// itself owns — `@AppStorage` so a change there is picked up the next
    /// time this recomputes, without this view needing its own copy of
    /// that settings UI.
    @AppStorage(RegionOrderSettings.storageKey) private var regionOrderRaw = RegionOrderSettings.defaultRawValue
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
    /// `cachedGameNodes` indexed by `id` — `selectedGameNode` used to
    /// linear-scan `cachedGameNodes` (tens of thousands of nodes for "All
    /// games") on every single one of its ~9 call sites, independently,
    /// every time SwiftUI re-evaluated `body` while a game was selected —
    /// real, repeated O(9n) work found live (2026-08-13 performance audit,
    /// "Ciclo A"). Set alongside `cachedGameNodes` itself, at every one of
    /// its own assignment sites (via `Self.indexByID(_:)`), rather than via
    /// `.onChange(of: cachedGameNodes)` — `GameNode` isn't `Equatable`, and
    /// making it so just to detect a change would add its own O(n) full
    /// field-by-field array comparison on every mutation, defeating the
    /// point.
    @State private var cachedGameNodesByID: [String: GameNode] = [:]
    /// The machine name of a "Database" tree parent currently scoping the
    /// Games table down to just its own clone family — jensyleo's own
    /// report (2026-08-13), with a screenshot: landing on a parent game in
    /// the tree (one with clone children nested under it there) used to
    /// leave "Games" showing the *whole* category with that one row merely
    /// scrolled-to/highlighted — confusing next to a category that can
    /// hold tens of thousands of unrelated rows. `nil` means "no family
    /// scope active" — the normal, full-category view, still used for any
    /// leaf with no clone family of its own (a childless game, or a clone
    /// leaf itself), a "Database" category header, or a "ROM folder"
    /// selection. Applied as a plain filter over the already-computed
    /// `cachedGameNodes` (`displayedGameNodes`, below) rather than its own
    /// separate recompute pipeline — cheap enough (one linear filter pass)
    /// to not need the background-task machinery `cachedGameNodes` itself
    /// has for its own, genuinely expensive regroup/sort.
    @State private var selectedGameFamilyRootMachineName: String?
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
    /// new one means only the *last* selection actually made pays that
    /// cost, instead of every intermediate one along the way. Shared by
    /// both a "Rom files" folder click and a "Database" category click
    /// (added 2026-08-11) — see `triggerCachedGameDataRecompute()`'s own
    /// doc comment for why one shared task/counter pair is correct for
    /// both rather than each needing its own.
    @State private var pendingFolderRecompute: Task<Void, Never>?
    /// True only during `refreshCachedGameDataAfterAuditReportChangeAsync()`'s
    /// own zip-comment preload tail — jensyleo's own report (2026-10-01),
    /// after a real NES scan: that preload used to be a fire-and-forget
    /// `Task.detached`, started mid-scan (right as `viewModel.auditReport`
    /// changes) and never awaited by `scan()` itself, so it could keep
    /// reading zip comments off disk/NAS well AFTER `viewModel.isBusy` went
    /// false and the progress overlay disappeared — "the bar says done" and
    /// "the scan is actually done" were two different moments. This flag
    /// keeps the SAME overlay up through that tail (`.overlay` below now
    /// checks `viewModel.isBusy || isPreloadingZipComments`), with its own
    /// weighted slice in `overallScanFraction`. Never true for
    /// `triggerCachedGameDataRecompute()` (the folder-click path) — that one
    /// never shows the scan overlay in the first place (clicking a folder
    /// isn't a "scan"), so there's no overlay for it to keep alive.
    @State private var isPreloadingZipComments = false
    /// Monotonic counter, bumped once per `triggerCachedGameDataRecompute()`
    /// call — jensyleo's own report (2026-08-03): once the recompute in
    /// `pendingFolderRecompute` genuinely runs on a background thread
    /// (`Task.detached`, see that function's own doc comment), two clicks
    /// in quick succession can race for real, and `Task.isCancelled`
    /// alone doesn't stop a slower, older background computation from
    /// finishing *after* a newer one and overwriting its correct result —
    /// cancellation only marks a flag, it doesn't halt in-flight work.
    /// Checked immediately before that task's final `@State` writes: only
    /// a write whose `generation` still matches this counter's *current*
    /// value is actually the most recent request and allowed through.
    @State private var folderRecomputeGeneration = 0
    /// When the *previous* `triggerCachedGameDataRecompute()` call
    /// happened — jensyleo's own report (2026-08-19): a single, isolated
    /// "Rom folder" click still paid `keyboardNavigationDebounceDelay`'s
    /// own fixed 80ms before the recompute even started, on top of however
    /// long the recompute itself takes, because the debounce ran
    /// unconditionally. That delay only ever earns its keep during an
    /// actual burst (arrow-key repeat, rapid clicks) — a click landing
    /// more than `keyboardNavigationDebounceDelay` after the previous one
    /// isn't part of any burst, so it now skips the artificial wait
    /// entirely and starts the real work immediately.
    @State private var lastFolderRecomputeTriggerAt: ContinuousClock.Instant?
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
    /// columns — persisted on every change under
    /// `gameColumnCustomizationKey`/`romColumnCustomizationKey`, so it
    /// survives relaunching the app, not just the current session.
    ///
    /// Real perf bug found live by jensyleo (2026-09-22): even after
    /// `GameTreeTableView`/`RomsTableView` were split out into their own
    /// `View` structs (2026-09-14, see that file's own doc comment) purely
    /// to isolate re-renders, the live customization value stayed `@State`
    /// HERE on `LibraryDetailView` (~4400 lines) with the child only
    /// holding a `@Binding` into it — and mutating a parent's `@State`
    /// ALWAYS invalidates the OWNING view's body, regardless of how the
    /// value is actually consumed downstream. Every pixel of a
    /// column-resize drag (and, less obviously, anything else that
    /// happened to touch this same giant view's state around the same
    /// time — reported as stutter on scroll/folder-switch too)
    /// re-evaluated the entire `LibraryDetailView.body`. Each child now
    /// owns its own live `@State`, loaded directly from `UserDefaults` at
    /// this same key (`GameTreeTableView.loadStoredColumnCustomization()`/
    /// `RomsTableView.loadStoredColumnCustomization()`) — this view no
    /// longer holds a live copy of the value at all. Cross-cutting
    /// features that genuinely need to push a value INTO the child from
    /// here (column presets, "Reset Layout") go through
    /// `gameColumnCustomizationOverride`/`romColumnCustomizationOverride`
    /// instead — a one-shot push, not a continuous two-way binding — and
    /// reading the CURRENT value (saving a preset) reads straight from
    /// `UserDefaults` instead, since the child already persists there on
    /// every change via `persistColumnCustomization`.
    ///
    /// One-shot pushes into each child's own local customization state —
    /// see the doc comment just above. Set to non-nil to push a value in;
    /// the child applies it and the parent never needs to clear it back to
    /// nil itself (a fresh non-nil value is a new, distinct
    /// `TableColumnCustomization` each time, so SwiftUI always sees a
    /// genuine change even if applied twice in a row).
    @State private var gameColumnCustomizationOverride: TableColumnCustomization<GameNode>?
    @State private var romColumnCustomizationOverride: TableColumnCustomization<RomRow>?
    /// Snapshot of whatever columns were showing right before one of the
    /// special, app-managed rows (BIOS, Complementary Chips) got selected
    /// — `nil` whenever neither is currently selected. jensyleo's own
    /// request (2026-09-24): "como la vista de BIOS es específica,
    /// considero que hay que dejarle unas columnas solo para esta vista"
    /// (later, 2026-09-24, extended verbatim to Complementary Chips: "hay
    /// que darle las mismas opciones de columnas... debe ser prácticamente
    /// igual que BIOS") — reuses the EXISTING column-preset mechanism
    /// (`columnPresets`/`applyColumnPreset`) rather than hand-building a
    /// `TableColumnCustomization` in code: that type's own on-disk shape
    /// is undocumented/private, and every other place this file constructs
    /// one is by decoding JSON actually captured from a real, live
    /// `defaults read` — never invented. A preset named exactly "BIOS" (or
    /// "Complementary Chips", saved the normal way via "Save Column
    /// Preset…" while that row is selected) auto-applies here; leaving the
    /// row restores whatever was showing right before, so switching back
    /// to an ordinary ROM folder doesn't leave the special-row-only
    /// columns behind. One shared snapshot suffices — only one of these
    /// rows can ever be selected at a time.
    @State private var columnCustomizationBeforeSpecialRow: (game: TableColumnCustomization<GameNode>, rom: TableColumnCustomization<RomRow>, sidebarVisible: Bool?)?
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

    /// A named snapshot of both tables' column customization together (show/
    /// hide, order, width) — jensyleo's own request (2026-08-18): "Compacta"
    /// vs "Detallada"-style saved view presets, on top of the show/hide/
    /// reorder that already existed. Stored pre-encoded (`Data`, not the
    /// generic `TableColumnCustomization<RowValue>` itself) since `GameNode`/
    /// `RomRow` are two different row types and a single dictionary value
    /// type can't hold both generically — round-tripping through `Data` is
    /// exactly what `gameColumnCustomization`/`romColumnCustomization`
    /// themselves already do for their own single-table persistence above.
    private struct ColumnPreset: Codable {
        let gameData: Data
        let romData: Data
        /// jensyleo's own request (2026-08-19): "el column preset no tiene
        /// en cuenta el sidebar" — a preset now also remembers whether the
        /// Systems sidebar was shown or hidden. `Optional` (not a plain
        /// `Bool`) so a preset saved before this field existed decodes
        /// fine (`nil`, meaning "leave the sidebar as it is" — see
        /// `applyColumnPreset`) instead of failing to decode at all.
        var sidebarVisible: Bool?
    }

    @State private var columnPresets: [String: ColumnPreset] = Self.loadColumnPresets()
    /// jensyleo's own report (2026-08-26): a fase 1 leftover — presets
    /// listed `.keys.sorted()` (alphabetical, the only order a plain
    /// `[String: ColumnPreset]` dictionary can offer), with no way to put a
    /// frequently-used preset near the top. A separate `[String]` holds the
    /// user's own order; reconciled against the real keys on every read
    /// (`loadOrderedColumnPresetNames()`) rather than trusted blindly, same
    /// "merge saved order with current reality" shape already used for the
    /// toolbar's own saved item order.
    @State private var columnPresetOrder: [String] = Self.loadColumnPresetOrder()
    /// Fase 2 Step 1 "Rebuild to Folder…" state — `rebuildDestination`/
    /// `rebuildOperationCount` are set together right after the user picks a
    /// folder (`startRebuildToFolder()`), then read by the confirmation
    /// dialog's own buttons before either is cleared.
    @State private var rebuildDestination: URL?
    @State private var rebuildOperationCount = 0
    @State private var showRebuildConfirmation = false
    /// "Fix All" state — jensyleo's own request (2026-09-29). `fixAllCount`
    /// is set by `startFixAll()`'s own async preview
    /// (`LibraryViewModel.planFixAllPreviewCount(system:)`) right before
    /// showing the confirmation dialog.
    @State private var fixAllCount = 0
    @State private var showFixAllConfirmation = false
    /// "File Actions" (Move to Trash, Delete Permanently, Copy/Move to
    /// Folder…) state — jensyleo's own request (2026-09-11). `pendingFile
    /// ActionURLs` is set by whichever `start*` function fires (toolbar
    /// dropdown or Games-table context menu, both operate on the SAME
    /// selection-derived File URLs); `pendingFileActionDestination` is only
    /// set for the two folder-picker actions. Both cleared once their own
    /// confirmation is answered either way.
    @State private var pendingFileActionURLs: [URL] = []
    @State private var pendingFileActionDestination: URL?
    @State private var showMoveToTrashConfirmation = false
    @State private var showDeletePermanentlyConfirmation = false
    @State private var showCopyToFolderConfirmation = false
    @State private var showMoveToFolderConfirmation = false
    /// jensyleo's own request (2026-09-30), after "Copy File(s) to…" simply
    /// refused with "Refusing to overwrite existing file" and no way to
    /// say "yes, replace it": `commitCopyFilesToFolder`/
    /// `commitMoveFilesToFolder` check `LibraryViewModel
    /// .existingDestinationFilenames` first; if any of `pendingFileActionURLs`'
    /// own names already exist at `pendingFileActionDestination`, THIS
    /// dialog (not the plain Copy/Move one above) asks explicitly before
    /// committing. `pendingReplaceIsMove` remembers which of the two
    /// actions to actually run once confirmed, since both share this one
    /// dialog and `pendingFileActionURLs`/`Destination`. Deliberately never
    /// Finder's "Keep Both" (" 2" suffix) — see
    /// `existingDestinationFilenames`'s own doc comment for why that would
    /// be actively harmful here.
    @State private var pendingReplaceFilenames: [String] = []
    @State private var pendingReplaceIsMove = false
    @State private var showReplaceExistingConfirmation = false
    /// jensyleo's own request (2026-09-30) — see `GameTreeTableView`'s own
    /// "Rename to…" context-menu button doc comment for the real "Battle
    /// City (J).zip" (57%) case this exists for. `pendingSimilarNameURL`/
    /// `Suggestion` are set together by `startRenameToSimilarNameSuggestion`,
    /// right before showing this dialog; cleared together once answered
    /// either way.
    @State private var pendingSimilarNameURL: URL?
    @State private var pendingSimilarNameSuggestion: SimilarNameSuggestion?
    @State private var showRenameToSimilarNameConfirmation = false
    /// Fase 2 Step 7 "Remove Useless Files…" state — same preview-then-
    /// confirm shape as the rebuild state above, its own separate dialog.
    @State private var removeUselessFilesCount = 0
    @State private var showRemoveUselessFilesConfirmation = false
    /// Fase 2 Step 3 "Repair from Sibling Sets…" state — same preview-then-
    /// confirm shape as the two above.
    @State private var repairFromSiblingSetsCount = 0
    @State private var showRepairFromSiblingSetsConfirmation = false
    @State private var createDummyRomsCount = 0
    @State private var showCreateDummyRomsConfirmation = false
    @State private var removeZipCommentsCount = 0
    @State private var showRemoveZipCommentsConfirmation = false
    @State private var collectSamplesCount = 0
    @State private var showCollectSamplesConfirmation = false
    /// Fase 2 Step 4 "Make Self-Contained…" state — same preview-then-
    /// confirm shape as the others above.
    @State private var makeSelfContainedCount = 0
    @State private var showMakeSelfContainedConfirmation = false
    /// Fase 2 Step 6 "Fix Misnamed ROMs Inside Their Archives…" state —
    /// same preview-then-confirm shape as the others above.
    @State private var renameRomsInArchiveCount = 0
    @State private var showRenameRomsInArchiveConfirmation = false
    /// Fase 2 Step 4 "Strip Redundant ROMs (Split)…" state — same preview-
    /// then-confirm shape as the others above. Its own separate
    /// `.confirmationDialog` modifier (`fase2Step4SplitConfirmation`) rather
    /// than folded into `fase2Confirmations` — that modifier's own
    /// parameter list was already at the type-checker's practical limit
    /// (see its own doc comment).
    @State private var convertToSplitCount = 0
    @State private var showConvertToSplitConfirmation = false

    /// "Fix Mismatched Files" (toolbar, folder-scoped) — jensyleo's own
    /// follow-up request (2026-09-10): give this the same preview-then-
    /// confirm-when-risky treatment `renameRomsInArchiveCount`/
    /// `showRenameRomsInArchiveConfirmation` already have, since a
    /// re-styled archive filename risks the exact same DAT-case mismatch
    /// a re-styled ROM entry does.
    @State private var fixMismatchedFilesCount = 0
    @State private var showFixMismatchedFilesConfirmation = false

    /// Per-FILE Fix, from the Games table's own context menu — jensyleo's
    /// own request (2026-09-10): the toolbar's "Fix" actions only ever
    /// scope to a whole selected ROM folder ("Scan Folder"'s own scope);
    /// this is the same "Fix Misnamed ROMs Inside Their Archives…" but
    /// scoped to the ONE right-clicked File instead, mirroring "Rescan
    /// This File"'s own relationship to "Scan Folder". A dedicated pair of
    /// state, kept separate from `renameRomsInArchiveCount`/
    /// `showRenameRomsInArchiveConfirmation` above (the toolbar's own,
    /// folder-scoped flow) so the two can't clobber each other's pending
    /// confirmation. `contextMenuFixFileURL` remembers WHICH file the
    /// confirmation is for, captured at preview time — `urlIsInScope`
    /// (`LibraryViewModel`) already treats a single file URL as a scope
    /// exactly as it does a folder (an operation's own path must equal it,
    /// not just share a prefix), so no Core/ViewModel change was needed to
    /// support this, only new call sites.
    @State private var contextMenuRenameRomsInArchiveCount = 0
    @State private var showContextMenuRenameRomsInArchiveConfirmation = false
    @State private var contextMenuFixFileURLs: [URL] = []
    /// Non-empty ONLY when this confirmation's own trigger came from the
    /// Roms panel's own multi-selection (specific entries within one
    /// already-selected game) rather than the Games table's (whole Files)
    /// — see `LibraryViewModel.renameRomsInArchive`'s own `entryKeys`
    /// parameter doc comment for why this distinction has to exist at all.
    @State private var contextMenuRenameRomsInArchiveEntryKeys: Set<String> = []

    /// "Fix Mismatched File" (context menu, single-File-scoped) — the
    /// File-level twin of `contextMenuRenameRomsInArchiveCount`/
    /// `showContextMenuRenameRomsInArchiveConfirmation`/
    /// `contextMenuFixFileURL` above, kept as its own dedicated trio for
    /// the same reason those are separate from the toolbar's own state:
    /// two independent pending confirmations must never be able to
    /// clobber each other.
    @State private var contextMenuFixMismatchedFilesCount = 0
    @State private var showContextMenuFixMismatchedFilesConfirmation = false
    @State private var contextMenuFixMismatchedFileURLs: [URL] = []

    /// "Remove Useless Files" (context menu, scoped to the selected
    /// File(s)) — jensyleo's own report (2026-09-13): scanning a folder
    /// with deliberately-planted unrecognized entries showed "Extra file
    /// in archive" on the affected row, but nothing in the context menu
    /// could actually act on it — the toolbar's own "Remove Useless
    /// Files…" only ever scopes to the SELECTED ROM FOLDER (itself
    /// narrowed to that, 2026-09-13, after this same action used to run
    /// system-wide by mistake), never to a row right-clicked in the Games
    /// table. Same dedicated-state pattern as `contextMenuFixMismatchedFilesCount`
    /// above, for the same can't-clobber-each-other reason.
    @State private var contextMenuRemoveUselessFilesCount = 0
    @State private var showContextMenuRemoveUselessFilesConfirmation = false
    @State private var contextMenuRemoveUselessFilesURLs: [URL] = []

    /// "Remove Zip Comments" (context menu, scoped to selected File(s)) —
    /// real gap found live by jensyleo (2026-09-22): only the toolbar's
    /// own unscoped, whole-system version existed. Same dedicated-state
    /// pattern as `contextMenuRemoveUselessFilesCount` above, for the same
    /// can't-clobber-each-other reason (the toolbar's own
    /// `removeZipCommentsCount`/`showRemoveZipCommentsConfirmation`).
    @State private var contextMenuRemoveZipCommentsCount = 0
    @State private var showContextMenuRemoveZipCommentsConfirmation = false
    @State private var contextMenuRemoveZipCommentsURLs: [URL] = []

    /// "Remove Redundant File(s)"/"Remove Redundant ROM(s)" (context menu,
    /// scoped to selected File(s)) — same dedicated-state pattern as
    /// `contextMenuRemoveUselessFilesCount` just above, for the same
    /// can't-clobber-each-other reason.
    @State private var contextMenuRemoveRedundantFilesCount = 0
    @State private var showContextMenuRemoveRedundantFilesConfirmation = false
    @State private var contextMenuRemoveRedundantFilesURLs: [URL] = []
    @State private var contextMenuRemoveRedundantRomsCount = 0
    @State private var showContextMenuRemoveRedundantRomsConfirmation = false
    @State private var contextMenuRemoveRedundantRomsURLs: [URL] = []

    /// "Find ROMs…" state — same preview-then-confirm
    /// shape as "Repair from Sibling Sets…", except the preview itself
    /// scans an external folder and so needs an `await`, unlike every
    /// other Fase 2 preview here (all instant, matchReport-only lookups).
    @State private var repairFromMaintenanceFolderCount = 0
    @State private var showRepairFromMaintenanceFolderConfirmation = false
    /// The exact scope `startRepairFromMaintenanceFolder` just planned its
    /// preview against — `commitRepairFromMaintenanceFolder` must execute
    /// against this SAME scope, not always the whole system, or
    /// `repairFromMaintenanceFolder`'s own `scopeCoveredByLastScan` check
    /// disagrees with what was actually just previewed.
    @State private var repairFromMaintenanceFolderScope: [URL] = []
    @State private var removeRedundantFilesCount = 0
    @State private var showRemoveRedundantFilesConfirmation = false
    @State private var removeRedundantRomsCount = 0
    @State private var showRemoveRedundantRomsConfirmation = false
    @State private var organizeBIOSFilesCount = 0
    @State private var organizeBIOSFilesLines: [String] = []
    @State private var showOrganizeBIOSFilesConfirmation = false
    /// Cached result of `viewModel.planOrganizeBIOSFilesPreviewCount() > 0`
    /// — real report caught live (2026-09-24), jensyleo: "la app se tiende
    /// a poner lenta, sobre todo cuando se da click en las romfolder y en
    /// los scroll." Root cause: `organizeBIOSFilesAvailable` (this file's
    /// own toolbar `isEnabled` gate) originally called that function
    /// DIRECTLY, and a computed property referenced from the toolbar gets
    /// re-evaluated on every render of this whole view — including every
    /// ROM-folder click and (since the toolbar is part of this same view
    /// hierarchy) most scroll-triggered re-renders too. That function
    /// walks every BIOS machine plus the surplus-file list looking for a
    /// duplicate — cheap once, but not something to redo dozens of times a
    /// second. Exactly the same class of bug as the 2026-09-22 "beachball"
    /// incidents (preview counts run uncached from a render path) — same
    /// fix: compute it ONCE per real scan result
    /// (`.onChange(of: viewModel.auditReport)` below), never from `body`.
    @State private var organizeBIOSFilesAvailableCache = false
    @State private var organizeComplementaryChipsCount = 0
    @State private var organizeComplementaryChipsLines: [String] = []
    @State private var showOrganizeComplementaryChipsConfirmation = false
    /// Same reasoning as `organizeBIOSFilesAvailableCache`'s own doc
    /// comment — learned that lesson up front this time, cached from the
    /// start rather than computed live from `isEnabled`.
    @State private var organizeComplementaryChipsAvailableCache = false
    /// The Roms panel's own entry-level File Actions state — jensyleo's own
    /// request (2026-09-13). `pendingRomEntryTargets` is shared by all
    /// three actions (only one is ever pending at a time, gated by its own
    /// `show...` flag); `pendingRomEntryDestination` only matters for
    /// Extract.
    @State private var pendingRomEntryTargets: [LibraryViewModel.RomEntryTarget] = []
    @State private var pendingRomEntryDestination: URL?
    @State private var showExtractRomEntriesConfirmation = false
    @State private var showMoveRomEntriesToTrashConfirmation = false
    @State private var showDeleteRomEntriesPermanentlyConfirmation = false
    /// Fase 2 Step 8 "Handle Corrupted Files…" state — same preview-then-
    /// confirm shape, own separate confirmation modifier for the same
    /// reason.
    @State private var handleCorruptedFilesCount = 0
    @State private var showHandleCorruptedFilesConfirmation = false
    /// Fase 2 Step 4 "Merge Clones (Merged)…" state — same preview-then-
    /// confirm shape, own separate confirmation modifier for the same
    /// reason.
    @State private var convertToMergedCount = 0
    @State private var showConvertToMergedConfirmation = false
    /// Which "ROM folder" row is currently being ⌘-dragged, if any — see
    /// `ColumnPresetsPanel.draggingName`'s own doc comment
    /// (`ViewOptionsSettingsView.swift`) for why this lives one level up
    /// from `ReorderGripHandle` itself.
    /// Non-nil drives the "Remove Folder…" confirmation dialog — jensyleo's
    /// own request (2026-09-14): removing a configured ROM folder used to
    /// happen immediately on click, with no way to back out of an
    /// accidental one.
    @State private var pendingRomFolderRemoval: URL?
    /// Drives the Maintenance subfolder's own "Delete Maintenance
    /// Subfolder…" confirmation, reached from its sidebar row's context
    /// menu — jensyleo's own request (2026-09-14). Same underlying
    /// `MaintenanceFolderSettings.deleteSubfolder(for:)` Settings → General
    /// already offers per-system; just reachable here too.
    @State private var pendingMaintenanceSubfolderDeletionFromSidebar = false
    // jensyleo's own report (2026-09-16), testing against a NAS-mounted
    // (SMB) ROM folder: "Hay lentitud en la visualización, cuando paso
    // entre carpetas... cuando es local la visualización [es rápida]" —
    // root-caused to THIS exact check: `FileManager.default.fileExists`
    // used to run inline inside the sidebar row's own body, which
    // re-executes on every re-render of that row, including every single
    // click on ANY other ROM folder (`selectedRomFolder` changing is what
    // drives this row's own highlight). Locally `fileExists` is
    // essentially free; over SMB/AFP it's a real network round-trip, so
    // every folder click was paying that cost again for a check that had
    // nothing to do with the folder just clicked. Now cached here and only
    // recomputed when it can actually change (system, or a genuine
    // create/delete of the subfolder) — never merely from re-rendering.
    //
    // jensyleo's own report (2026-09-16): "se perdió de vista la carpeta
    // de mantenimiento" after a relaunch — turned out to be macOS itself
    // dropping the NAS connection at that exact moment, not a deleted
    // folder; then, right after that fix, a NEW report on cold launch with
    // the NAS already offline: "las otras [ROM folder rows] sí se ven,
    // unifica eso" — a real, correct point. Every ordinary ROM folder row
    // is ALWAYS shown regardless of whether it can currently be verified
    // (`romFolderRow`, below — a configured reference stays visible, red
    // only once a scan proves it unreachable). This row used to work the
    // opposite way — hidden by DEFAULT until a check proved it existed —
    // which is exactly backwards from every other row in this same list.
    // Rebuilt on the same two-flag model `LibraryViewModel
    // .lastScanUnreachableFolders` uses for ROM folders:
    /// `true` only after a DELIBERATE delete (all three delete entry
    /// points) — the one and only thing that actually hides this row.
    /// Never set by a mere failed existence check.
    @State private var maintenanceSubfolderDeleted = false
    /// `true` only after a completed check confirms the subfolder can't
    /// currently be reached — drives the same red/⚠️ styling
    /// `romFolderRow` already uses for an unreachable ROM folder. Starts
    /// `false` (optimistic, same as every ROM folder row's own un-scanned
    /// default) so this row renders normally on the very first frame,
    /// never hidden just because nothing has checked it yet.
    @State private var maintenanceSubfolderUnreachable = false
    /// jensyleo's own request (2026-09-16), testing with ROM folders on a
    /// NAS: "debería haber un distintivo... cuando la carpeta está en el
    /// disco local o está en un pendrive, un disco duro externo o
    /// conectado a una NAS (SMB, AFS, etc.)". Computed off-`@MainActor`
    /// (`URLResourceValues` for a network path is itself a real round
    /// trip — same class of cost `maintenanceSubfolderUnreachable`'s own
    /// doc comment just fixed) and cached here, keyed by folder URL, never
    /// recomputed on a plain re-render.
    @State private var romFolderVolumeKindCache: [URL: RomFolderVolumeKind] = [:]
    @State private var romFolderVolumeKindRefreshGeneration = 0
    @State private var draggingRomFolderIndex: Int?
    @State private var dragPreviewRomFolderIndex: Int?
    @State private var dragRomFolderOffset: CGFloat = 0
    @State private var romFolderRowFrames: [Int: CGRect] = [:]

    /// jensyleo's own report (2026-09-17): "⌘-arrastrar se pone a mover
    /// un poco, queda congelado, y después no permite hacer ningún otro
    /// intento" — a macOS 27 event-delivery quirk (the same class already
    /// seen elsewhere this session for keyboard/focus) can apparently stop
    /// delivering further drag events mid-gesture, so `ReorderGripHandle`'s
    /// own `.onEnded` never runs and `draggingRomFolderIndex` never gets
    /// reset back to `nil` — permanently "stuck" believing a drag is still
    /// in progress, which then blocks every later attempt (the ghost
    /// overlay/opacity dimming all key off this same value). Called from
    /// every plain click in this list as a self-heal: harmless when
    /// nothing is actually stuck, but recovers on the very next ordinary
    /// interaction instead of requiring the app to be relaunched.
    private func resetStuckRomFolderDragIfNeeded() {
        guard draggingRomFolderIndex != nil || dragPreviewRomFolderIndex != nil else { return }
        draggingRomFolderIndex = nil
        dragPreviewRomFolderIndex = nil
        dragRomFolderOffset = 0
    }

    /// Selects `url` as the active ROM folder — shared by the row's own
    /// `.onTapGesture` and `installRomFolderReorderMonitor`'s raw-mouse
    /// fallback below, so both paths stay in lockstep instead of drifting
    /// apart if only one of them gets updated later.
    private func selectRomFolder(_ url: URL) {
        resetStuckRomFolderDragIfNeeded()
        selectedDatabaseFilter = nil
        selectedRomFolder = url
        isRomFolderPaneFocused = true
        resultsPaneIsActive = false
        // jensyleo's own instruction (2026-09-16): "la app solo debe
        // iniciar, los escaneos se deben hacer por parte del usuario" — the
        // volume-kind icon (local/removable/NAS) no longer computes itself
        // automatically on `.onAppear`; only ever recomputed when the user
        // genuinely interacts with this list (a click here) — never on the
        // app launching.
        if romFolderVolumeKindCache[url] == nil {
            refreshRomFolderVolumeKindCache()
        }
    }
    static let columnPresetsKey = "ROMForge.columnPresets"
    static let columnPresetOrderKey = "ROMForge.columnPresetOrder"

    private static func loadColumnPresets() -> [String: ColumnPreset] {
        guard let data = UserDefaults.standard.data(forKey: columnPresetsKey),
              let decoded = try? JSONDecoder().decode([String: ColumnPreset].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func persistColumnPresets(_ presets: [String: ColumnPreset]) {
        guard let data = try? JSONEncoder().encode(presets) else { return }
        UserDefaults.standard.set(data, forKey: columnPresetsKey)
    }

    private static func loadColumnPresetOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: columnPresetOrderKey) ?? []
    }

    /// The only thing Settings' own inline preset UI (`ViewOptionsSettingsView
    /// .ColumnPresetsPanel`, a different window entirely) needs from this
    /// view's private preset storage — the display names, in the same
    /// reconciled order `orderedPresetNames` computes below, without
    /// exposing `ColumnPreset` itself (Settings never touches the actual
    /// column data, only names, by design — every real action still routes
    /// back here as a notification).
    static func loadOrderedColumnPresetNames() -> [String] {
        let presets = loadColumnPresets()
        let order = loadColumnPresetOrder()
        let existing = Set(presets.keys)
        let kept = order.filter { existing.contains($0) }
        let missing = presets.keys.filter { !order.contains($0) }.sorted()
        return kept + missing
    }

    private func persistColumnPresetOrder() {
        UserDefaults.standard.set(columnPresetOrder, forKey: Self.columnPresetOrderKey)
    }

    private func saveColumnPreset(named name: String) {
        // Reads the LIVE value from `UserDefaults`, not the `@State` above
        // — see that property's own doc comment: the child table now owns
        // live mutation and persists there on every change, so this is
        // the current, real value without needing a two-way binding back
        // to this giant view.
        let currentGameCustomization = Self.loadCustomization(key: Self.gameColumnCustomizationKey, default: TableColumnCustomization<GameNode>())
        let currentRomCustomization = Self.loadCustomization(key: Self.romColumnCustomizationKey, default: TableColumnCustomization<RomRow>())
        guard !name.isEmpty,
              let gameData = try? JSONEncoder().encode(currentGameCustomization),
              let romData = try? JSONEncoder().encode(currentRomCustomization)
        else { return }
        columnPresets[name] = ColumnPreset(gameData: gameData, romData: romData, sidebarVisible: isSidebarVisible?.wrappedValue)
        Self.persistColumnPresets(columnPresets)
        if !columnPresetOrder.contains(name) {
            columnPresetOrder.append(name)
            persistColumnPresetOrder()
        }
    }

    /// Called from `.onChange(of: selectedRomFolder)` — see
    /// `columnCustomizationBeforeSpecialRow`'s own doc comment for the
    /// full reasoning. Entering either special row snapshots the current
    /// columns (once) and applies a preset literally named after that row
    /// ("BIOS"/"Complementary Chips") if the user has saved one; leaving
    /// both restores that snapshot. Only one of `specialRowsAndPresetNames`
    /// can ever be `selectedRomFolder` at a time, so one shared snapshot
    /// is safe.
    private var specialRowsAndPresetNames: [(folder: URL?, presetName: String)] {
        guard system.isMAMEStyle else { return [] }
        return [
            (BIOSFolderSettings.folderURL, "BIOS"),
            (ComplementaryChipsFolderSettings.folderURL, "Complementary Chips"),
        ]
    }

    private func applyOrRestoreBIOSColumnsIfNeeded() {
        if let match = specialRowsAndPresetNames.first(where: { $0.folder != nil && $0.folder == selectedRomFolder }) {
            if columnCustomizationBeforeSpecialRow == nil {
                columnCustomizationBeforeSpecialRow = (
                    Self.loadCustomization(key: Self.gameColumnCustomizationKey, default: TableColumnCustomization<GameNode>()),
                    Self.loadCustomization(key: Self.romColumnCustomizationKey, default: TableColumnCustomization<RomRow>()),
                    isSidebarVisible?.wrappedValue
                )
            }
            if columnPresets[match.presetName] != nil {
                applyColumnPreset(named: match.presetName)
            }
        } else if let saved = columnCustomizationBeforeSpecialRow {
            Self.persist(saved.game, key: Self.gameColumnCustomizationKey)
            gameColumnCustomizationOverride = saved.game
            Self.persist(saved.rom, key: Self.romColumnCustomizationKey)
            romColumnCustomizationOverride = saved.rom
            if let sidebarVisible = saved.sidebarVisible {
                isSidebarVisible?.wrappedValue = sidebarVisible
            }
            columnCustomizationBeforeSpecialRow = nil
        }
    }

    private func applyColumnPreset(named name: String) {
        guard let preset = columnPresets[name] else { return }
        if let decoded = try? JSONDecoder().decode(TableColumnCustomization<GameNode>.self, from: preset.gameData) {
            Self.persist(decoded, key: Self.gameColumnCustomizationKey)
            // One-shot push into the child's own local state — see
            // `gameColumnCustomizationOverride`'s own doc comment.
            gameColumnCustomizationOverride = decoded
        }
        if let decoded = try? JSONDecoder().decode(TableColumnCustomization<RomRow>.self, from: preset.romData) {
            Self.persist(decoded, key: Self.romColumnCustomizationKey)
            romColumnCustomizationOverride = decoded
        }
        if let sidebarVisible = preset.sidebarVisible {
            isSidebarVisible?.wrappedValue = sidebarVisible
        }
    }

    private func deleteColumnPreset(named name: String) {
        columnPresets.removeValue(forKey: name)
        Self.persistColumnPresets(columnPresets)
        columnPresetOrder.removeAll { $0 == name }
        persistColumnPresetOrder()
    }

    /// jensyleo's own report (2026-08-18): the sheet only let you create a
    /// new preset or delete one — no way to rename an existing one, or to
    /// overwrite it with the layout as it stands right now without
    /// retyping its exact name into the "new preset" field. Renaming keeps
    /// the preset's own saved data untouched (just moves it to a new
    /// dictionary key); a no-op if `newName` is empty, already taken by a
    /// different preset, or identical to `oldName`.
    private func renameColumnPreset(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != oldName, columnPresets[trimmed] == nil,
              let preset = columnPresets[oldName]
        else { return }
        columnPresets.removeValue(forKey: oldName)
        columnPresets[trimmed] = preset
        Self.persistColumnPresets(columnPresets)
        if let index = columnPresetOrder.firstIndex(of: oldName) {
            columnPresetOrder[index] = trimmed
        } else {
            columnPresetOrder.append(trimmed)
        }
        persistColumnPresetOrder()
    }

    /// Every Fase 2 write action, as the "Fix" toolbar button's own
    /// dropdown menu — see `detailToolbarActions`'s own "fix" entry for
    /// why they live here instead of each getting a separate toolbar
    /// button. Each sub-action's own `isEnabled`/gating logic is unchanged
    /// from when it was a standalone button; only where it's declared
    /// moved.
    /// Which Fix actions are actually offered right now, while jensyleo
    /// works through manual testing of each one — jensyleo's own request
    /// (2026-09-09): "Hay muchos FIX y nos podemos confundir para pruebas...
    /// solo dejes 2 y los vamos agregando de poco". Every action below is
    /// fully implemented; this just narrows what's exposed in the "Fix"
    /// dropdown at any given time. Add an id here once its own action has
    /// been manually verified.
    // jensyleo's own report (2026-09-10) and follow-up decision: setting
    // "Sets case" to Uppercase and running "Fix Mismatched Files" on an
    // already-correct collection logged "nothing to fix" — correctly, at
    // the time, since a case policy there only STYLED a mismatch repair,
    // and re-casing an already-correct name was a SEPARATE "Apply Case
    // Policy…" action. jensyleo's own read on seeing two actions sharing
    // one setting: "o es una o es la otra" — unify them, and while at it,
    // matching the DAT is the whole reason this app exists, not something
    // that needs its own toggle. So `fix()`/`renameRomsInArchive()` now
    // unconditionally do both (repair a wrong name, styled per case
    // policy; re-style an already-correct one, same policy) in one pass —
    // exactly ClrMamePro's own single "Fix" model — and "Apply Case
    // Policy…" was removed outright as a separate action rather than kept
    // as a redundant second door to the same result.
    // jensyleo's own decisions (2026-09-13): "makeSelfContained" and
    // "convertToSplit" were each briefly enabled here, then deliberately
    // taken back out — "Esa opción no la voy a implementar [probar].
    // Documenta para que alguien lo active si lo considera útil... Solo
    // voy a implementar el de Find ROMs." Both actions stay fully
    // implemented and reachable by re-adding their id here (see
    // TESTING.es.md's own §11.6/§11.8 notes for why jensyleo skipped
    // manual testing of them) — nothing about either feature was
    // removed, only its exposure in this dropdown. "Find ROMs"
    // (`repairFromMaintenanceFolder`) is what he's testing next instead.
    // jensyleo's own request (2026-09-13): "prueba tu todas las otras
    // opciones así no las vaya yo a implementar" — every remaining action
    // WAS enabled here temporarily for Claude's own live GUI testing pass
    // (createDummyRoms, removeZipComments, makeSelfContained succeeded;
    // convertToSplit's own confirmation correctly found 1,212 real
    // candidates but was cancelled rather than run system-wide;
    // handleCorruptedFiles/convertToMerged/collectSamples never reached).
    // jensyleo's own follow-up the same day: "deja solo lo que yo he
    // probado, mas lo de Find ROMS, que es lo que voy a probar yo" — this
    // set now reflects only jensyleo's OWN manually-verified actions
    // (fixMisnamed/renameRomsInArchive/removeUselessFiles, per
    // TESTING.es.md's own confirmations) plus "Find ROMs"
    // (repairFromMaintenanceFolder), which he's testing next. Every other
    // action Claude tested stays fully implemented and reachable by
    // re-adding its id here whenever jensyleo is ready for it himself.
    private static let fixActionsEnabledForTesting: Set<String> = [
        "fixMisnamed", "renameRomsInArchive", "removeUselessFiles", "repairFromMaintenanceFolder",
        // jensyleo's own request (2026-09-14), right after live-testing
        // "Find ROMs…" himself and discovering its own real, honest gap:
        // it only ever ADDS a missing rom, so a repaired game's own
        // now-obsolete leftover content (e.g. `gng.zip`'s old `gg3.bin`/
        // `gg4.bin`/`gg5.bin`, superseded by the newly-added `mm_c_03`/
        // `mm_c_04`/`mm_c_05`) stays behind as a "Duplicated file, not
        // needed here" row — "Remove Redundant Files/ROMs…" is exactly
        // the cleanup step for that, so he asked to test it too.
        "removeRedundantFiles", "removeRedundantRoms",
        // jensyleo's own request (2026-09-14): "actívalos y los pruebo
        // mañana" — next in the queue, alongside "Remove Redundant
        // Files/ROMs…" above.
        "removeZipComments",
        // jensyleo's own request (2026-09-24): "Si" — activado para que lo
        // pruebe, justo después de validar el flujo de creación de la
        // carpeta BIOS (ver `BIOSFolderSettings`'s own doc comment).
        "organizeBIOSFiles",
        // jensyleo's own request (2026-09-24): "habilítaselo" — right
        // after finishing "Organize Complementary Chips…", same as BIOS.
        "organizeComplementaryChips",
        // jensyleo's own request (2026-09-29): "Fix All" itself — its own
        // gating (`fixAll(system:enabledActionIDs:)`) already restricts
        // what it actually RUNS to whichever of the ids above are also
        // listed here, so exposing its own toolbar button doesn't bypass
        // the staged rollout of any individual action still missing from
        // this set.
        "fixAll",
    ]

    private var fixSubActions: [ToolbarAction] {
        [
            // The last pending Fase 2 item — jensyleo's own request
            // (2026-09-29): a single action that runs every fully-automatic
            // Fix in one pass, ClrMamePro-style. See `LibraryViewModel
            // .fixAll(system:)`'s own doc comment for the exact order and
            // what's deliberately excluded (only "Rebuild to Folder…", the
            // one action needing a destination picked by hand). The tooltip
            // spells this out up front — same "explain the scope before
            // anyone has to click to find out" treatment as "Matching" in
            // Settings → General.
            ToolbarAction(
                id: "fixAll", title: "Fix All…", systemImage: "wand.and.stars",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Run every fully-automatic Fix action in one pass — names, set layout, repairs, cleanup, and housekeeping — in a safe order. Only \"Rebuild to Folder…\" is excluded, since it needs a destination you'd have to pick yourself."
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startFixAll()
            },
            ToolbarAction(
                id: "fixMisnamed", title: "Fix Mismatched Files",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Fix a mismatched File's name AND re-style an already-correct one, both per \"Sets case\" in Settings → Fix\(selectedRomFolder.map { " — only inside \"\($0.lastPathComponent)\"" } ?? "")"
                    : "Disabled for now — ROMForge only scans and reports, it won't touch your files"
            ) {
                startFixMismatchedFiles()
            },
            // Fase 2 Step 1: "classic rebuild" — copies every matched ROM
            // into a chosen folder as `<game name>/<rom name>`. Gated the
            // same way as "Fix Mismatched Files" above; the destination-folder
            // picker and count-preview confirmation live in
            // `startRebuildToFolder()`.
            ToolbarAction(
                id: "rebuildToFolder", title: "Rebuild to Folder…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Copy (or move) every matched ROM into a chosen folder, organized as one subfolder per game"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startRebuildToFolder()
            },
            // Fase 2 Step 3: repairs a missing rom by borrowing it from a
            // sibling parent/clone set that already has it — never invents
            // a new location, never touches a set with no existing anchor
            // of its own (see `RebuildPlanner.planCrossSetRepair`'s own doc
            // comment).
            ToolbarAction(
                id: "repairFromSiblingSets", title: "Repair from Sibling Sets…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Fill in a missing rom by copying it from a sibling parent/clone set that already has it"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startRepairFromSiblingSets()
            },
            // Fase 2 Step 4, "non-merged" direction — copies in every rom
            // the matcher already found genuinely present elsewhere in the
            // scan but not yet inside a game's own archive. "Split" is the
            // sibling action below; "Merged" isn't offered yet (see
            // `RebuildPlanner.planConvertToNonMerged`'s own doc comment for
            // why).
            ToolbarAction(
                id: "makeSelfContained", title: "Make Self-Contained…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Copy every inherited rom (BIOS/parent) into each game's own archive, so it needs nothing else to run"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startMakeSelfContained()
            },
            // Fase 2 Step 6 (ROM-level half — the File-level half is
            // "Fix Mismatched Files" above): renames a misnamed ROM entry
            // inside an otherwise-correctly-named archive File via
            // add-then-remove (see `RebuildPlanner.planRenameRomsInArchive`'s
            // own doc comment).
            ToolbarAction(
                id: "renameRomsInArchive", title: "Fix Misnamed ROMs Inside Their Archives…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Fix a misnamed ROM entry AND re-style an already-correct one inside an otherwise-correctly-named archive File, both per \"Roms case\" in Settings → Fix\(selectedRomFolder.map { " — only inside \"\($0.lastPathComponent)\"" } ?? "")"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startRenameRomsInArchive()
            },
            // Fase 2 Step 4, "split" direction — the inverse of "Make
            // Self-Contained…" above: strips a rom back out of a clone's
            // own archive once the parent already has the exact same
            // content correctly (see `RebuildPlanner.planConvertToSplit`'s
            // own doc comment). Never touches the parent's own archive.
            ToolbarAction(
                id: "convertToSplit", title: "Strip Redundant ROMs (Split)…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Remove a rom from a clone's own archive once its parent already has the exact same content"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startConvertToSplit()
            },
            // Fase 2 Step 8: applies whichever "Corrupted files" policy is
            // configured in Settings → Fix to every rom
            // `ZipIntegrityAuditor` confirms is internally corrupt (see
            // `RebuildPlanner.planCorruptedFilesPolicy`'s own doc comment).
            ToolbarAction(
                id: "handleCorruptedFiles", title: "Handle Corrupted Files…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Apply the \"Corrupted files\" policy configured in Settings → Fix to every internally-corrupt rom"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startHandleCorruptedFiles()
            },
            // Fase 2 Step 4, "Merged" direction — the only Fase 2 action
            // that deletes a WHOLE archive rather than one entry inside
            // it. Safe by construction, not by a separate check: each
            // clone's own delete is the LAST operation in its own group
            // (see `RebuildPlanner.planConvertToMerged`'s own doc
            // comment), so it only ever runs once every rom that clone
            // needed migrated into its parent has already succeeded.
            ToolbarAction(
                id: "convertToMerged", title: "Merge Clones (Merged)…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Fold each clone's own unique roms into its parent's archive, then delete the clone's whole archive"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startConvertToMerged()
            },
            // Fase 2 Step 7: permanently deletes every file the DAT
            // recognizes nothing about at all (today's "surplus"/unknown-
            // file status, including one unrecognized entry inside an
            // otherwise-good zip). The most destructive action in the app —
            // its own confirmation dialog is deliberately separate from
            // every other Fase 2 confirmation.
            // Repairs a `.missing` rom by borrowing it from the optional,
            // read-only "Maintenance folder" configured in Settings →
            // General — a donor folder the user drops new/extra dumps
            // into over time; never touched, renamed, or deleted from
            // (see `RebuildPlanner.planRepairFromMaintenanceFolder`'s own
            // doc comment). Distinct from "Repair from Sibling Sets…"
            // above, which only ever borrows from within this same scan.
            // jensyleo's own request (2026-09-14): "fusionalo con repair
            // from maintenance folder. A la larga es lo mismo" — this one
            // action now ALSO replaces a `.badDump` rom's bad content with
            // a verified-correct donor copy (previously a separate
            // "Replace Corrupted ROMs…" entry) — see `RebuildPlanner
            // .planReplaceCorruptedRoms`'s own doc comment for the
            // remove-then-add overwrite that case needs that a plain fill
            // doesn't; `planRepairFromMaintenanceFolderPreviewCount` plans
            // both kinds together from one single donor-folder read.
            // `skipConfirmation: true` — jensyleo's own follow-up
            // (2026-09-14): "quitar ese mensaje emergente, la
            // funcionalidad mantenla. Deja solo mensajes emergentes para
            // casos de eliminación" — a popup confirmation now stays
            // reserved for genuinely destructive actions (Remove Useless/
            // Redundant Files/ROMs, below); this one only ever COPIES from
            // the read-only Maintenance folder, never deletes/overwrites
            // anything irrecoverably, matching the context-menu version's
            // own no-confirmation behavior.
            ToolbarAction(
                id: "repairFromMaintenanceFolder", title: "Find ROMs…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Fill in a missing rom, or replace a hash-mismatched rom's bad content, by copying a verified-correct copy from the optional, read-only Maintenance folder configured in Settings → Systems → MAME"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                // Real gap found live by jensyleo (2026-09-22): unlike "Fix
                // Mismatched Files" right above (which already scopes its
                // own toolbar call to `selectedRomFolder`), this always
                // passed `scopeFolders: []` — forcing "the LAST scan must
                // have covered the WHOLE system" (`scopeCoveredByLastScan`'s
                // own `.wholeSystem` requirement) even for someone working
                // folder-by-folder on a NAS specifically to avoid re-reading
                // everything. `scopeFolders` already fully supports scoping
                // both which donor search ALSO covers (see this action's
                // own doc comment, point 2) and which folder gets verified
                // afterward — nothing here ever needed the whole system.
                startRepairFromMaintenanceFolder(scopeFolders: selectedRomFolder.map { [$0] } ?? [], skipConfirmation: true)
            },
            // jensyleo's own correction (2026-09-13), after live-testing
            // this himself: it deleted surplus files across every
            // configured ROM folder at once, not just the one he'd
            // selected — "Remove Useless Files… debe actuar solo en la
            // carpeta SELECCIONADA." Now requires a real ROM folder
            // selected (never the whole system, and never the read-only
            // Maintenance subfolder — same exclusion `isEnabled`/help
            // already applies to "Scan Folder") before it's even
            // clickable.
            ToolbarAction(
                id: "removeUselessFiles", title: "Remove Useless Files…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy
                    && selectedRomFolder != nil && !isSelectedFolderMaintenanceSubfolder,
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : isSelectedFolderMaintenanceSubfolder
                        ? "The Maintenance folder is a read-only donor area — nothing here is ever deleted"
                        : selectedRomFolder != nil
                            ? "Permanently delete every file inside \"\(selectedRomFolder!.lastPathComponent)\" the DAT recognizes nothing about at all"
                            : "Select a ROM folder first — this only ever acts on the folder currently selected"
            ) {
                startRemoveUselessFiles()
            },
            // jensyleo's own request (2026-09-13): the exact complement of
            // "Remove Useless Files" above — targets a LOOSE file the DAT
            // DOES recognize, just not needed at this exact location
            // because another game already claims an equivalent copy
            // elsewhere ("Not needed here (required by X)"). Same
            // selected-folder-only scoping and Maintenance-folder
            // exclusion as "Remove Useless Files…".
            ToolbarAction(
                id: "removeRedundantFiles", title: "Remove Redundant Files…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy
                    && selectedRomFolder != nil && !isSelectedFolderMaintenanceSubfolder,
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : isSelectedFolderMaintenanceSubfolder
                        ? "The Maintenance folder is a read-only donor area — nothing here is ever deleted"
                        : selectedRomFolder != nil
                            ? "Permanently delete every loose file inside \"\(selectedRomFolder!.lastPathComponent)\" that's a redundant duplicate of content the DAT recognizes elsewhere"
                            : "Select a ROM folder first — this only ever acts on the folder currently selected"
            ) {
                startRemoveRedundantFiles()
            },
            // "Remove Redundant Files…"'s own archive-entry counterpart —
            // same "recognized, but not needed HERE" definition, just for a
            // rom sitting inside a `.zip` rather than loose on disk.
            ToolbarAction(
                id: "removeRedundantRoms", title: "Remove Redundant ROMs…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy
                    && selectedRomFolder != nil && !isSelectedFolderMaintenanceSubfolder,
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : isSelectedFolderMaintenanceSubfolder
                        ? "The Maintenance folder is a read-only donor area — nothing here is ever deleted"
                        : selectedRomFolder != nil
                            ? "Permanently remove every archive entry inside \"\(selectedRomFolder!.lastPathComponent)\" that's a redundant duplicate of content the DAT recognizes elsewhere"
                            : "Select a ROM folder first — this only ever acts on the folder currently selected"
            ) {
                startRemoveRedundantRoms()
            },
            // jensyleo's own request (2026-09-11): "implementa: Create dummy
            // roms for nodump entries" — see `RebuildPlanner
            // .planCreateDummyRoms`'s own doc comment for exactly which
            // roms qualify (a genuinely `.missing` slot whose DAT entry is
            // declared `nodump` — never a rom that already has some file
            // sitting in its spot).
            ToolbarAction(
                id: "createDummyRoms", title: "Create Dummy ROMs…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Create a zero-byte placeholder for every missing rom the DAT declares \"nodump\""
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startCreateDummyRoms()
            },
            // jensyleo's own request (2026-09-11): "implementa: ... Remove
            // zip comments" — strips the trailing comment field from every
            // matched `.zip` (`RebuildPlanner.planRemoveZipComments`).
            ToolbarAction(
                id: "removeZipComments", title: "Remove Zip Comments…",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Strip the trailing comment field from every matched archive inside the selected folder, in place"
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startRemoveZipComments()
            },
            // jensyleo's own request (2026-09-11): "implementalo, es clave
            // para MAME" — populates the MAME Samples folder (Settings →
            // Systems → MAME) from this system's own configured ROM
            // folders, matched purely by filename (`RebuildPlanner
            // .planCollectSamples`'s own doc comment covers why: MAME's
            // DAT declares a sample's NAME only, never a hash). Unlike
            // every other Fix action, this doesn't need a prior scan at
            // all — its own real prerequisite is samples support being
            // enabled with a folder configured.
            ToolbarAction(
                id: "collectSamples", title: "Fix Samples…",
                isEnabled: LibraryViewModel.modificationsEnabled && SamplesFolderSettings.folderURL != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? (SamplesFolderSettings.folderURL != nil
                        ? "Copy any matching sample zip found in this system's own ROM folders into the Samples folder"
                        : "Disabled for now — enable samples support and choose a folder in Settings → Systems → MAME first")
                    : "Disabled for now — enable file modifications in Settings → General first"
            ) {
                startCollectSamples()
            },
            // jensyleo's own request (2026-09-23): "quiero que vayas
            // preparando la característica adicional de que se cree una
            // carpeta llamada BIOS donde la idea es que la app tome las
            // BIOS que identifique en las rom folder y las mueva allá" —
            // point 3 of that request is explicit this belongs ONLY here
            // (the toolbar's own "Fix" menu), never a per-row context menu
            // item. Whole-system only, same reasoning `organizeBIOSFiles`'s
            // own doc comment gives — a BIOS can be referenced by games
            // under any of this system's configured ROM folders, not just
            // whichever one happens to be selected.
            ToolbarAction(
                id: "organizeBIOSFiles", title: "Organize BIOS Files…", systemImage: "cpu",
                // jensyleo's own request (2026-09-24): "debe ser dinámica,
                // si en los escaneos se detectan BIOS en los rom folder la
                // opción se debe activar" — unlike most other Fix actions
                // here (which enable on preconditions alone — a scan
                // exists, a folder's selected — and only compute their own
                // real preview count on click), this one also checks
                // `organizeBIOSFilesAvailable` so the button reads as truly
                // inert when the last scan found nothing to organize, not
                // just "click it to find out". Cheap enough to compute on
                // every render — it only walks this DAT's own BIOS
                // machines (a handful) plus their own surplus duplicates,
                // never the whole collection.
                isEnabled: LibraryViewModel.modificationsEnabled && BIOSFolderSettings.folderURL != nil
                    && viewModel.auditReport != nil && !viewModel.isBusy && organizeBIOSFilesAvailable,
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : BIOSFolderSettings.folderURL == nil
                        ? "Disabled for now — enable a BIOS folder in Settings → Systems → MAME first"
                        : !organizeBIOSFilesAvailable
                            ? "Nothing to organize — no BIOS files found outside the configured BIOS folder in the current scan"
                            : "Move every BIOS file found across this system's own ROM folders into the configured BIOS folder, removing redundant copies once confirmed safe elsewhere"
            ) {
                startOrganizeBIOSFiles()
            },
            // jensyleo's own request (2026-09-24): "lo mismo que BIOS pero
            // para los demás chips" — see `RebuildPlanner
            // .planOrganizeComplementaryChips`'s own doc comment for the
            // exact `isDevice`-vs-`isBios` distinction, sourced against
            // MAME's own official documentation. Same dynamic-enable
            // reasoning as "Organize BIOS Files…" right above.
            ToolbarAction(
                id: "organizeComplementaryChips", title: "Organize Complementary Chips…", systemImage: "puzzlepiece.extension",
                isEnabled: LibraryViewModel.modificationsEnabled && ComplementaryChipsFolderSettings.folderURL != nil
                    && viewModel.auditReport != nil && !viewModel.isBusy && organizeComplementaryChipsAvailable,
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : ComplementaryChipsFolderSettings.folderURL == nil
                        ? "Disabled for now — enable a Complementary Chips folder in Settings → Systems → MAME first"
                        : !organizeComplementaryChipsAvailable
                            ? "Nothing to organize — no complementary chip files found outside the configured Complementary Chips folder in the current scan"
                            : "Move every complementary chip file found across this system's own ROM folders into the configured Complementary Chips folder, removing redundant copies once confirmed safe elsewhere"
            ) {
                startOrganizeComplementaryChips()
            },
        ].filter { Self.fixActionsEnabledForTesting.contains($0.id) }
    }

    /// The real File URL for each row in `selectedGameIDs` that actually has
    /// one — same computation the Games table's own context menu already
    /// does from its `selection` parameter (`actualFileURL(for:)`), factored
    /// out here so the TOOLBAR's own "File Actions" dropdown (which has no
    /// `.contextMenu` selection parameter to read — it operates on whatever
    /// is CURRENTLY selected, not a scoped ROM folder like "Fix" does) can
    /// share the exact same selection-to-Files mapping.
    private var selectedFileURLs: [URL] {
        selectedGameIDs.compactMap { selectedID in
            cachedGameNodesByID[selectedID].flatMap(actualFileURL(for:))
        }
    }

    /// The "File Actions" toolbar button's own dropdown menu — jensyleo's
    /// own request (2026-09-11): "cosas de sistema operativo como eliminar
    /// y copiar a otra carpeta... en un boton del menu que se llame File
    /// action". Plain, OS-level operations on `selectedFileURLs`,
    /// independent of the DAT — unlike "Fix"'s own sub-actions, these don't
    /// need `viewModel.auditReport != nil` at all, only a real selection.
    private var fileActionsSubActions: [ToolbarAction] {
        [
            ToolbarAction(
                id: "moveToTrash", title: selectedFileURLs.count == 1 ? "Move File to Trash…" : "Move Files to Trash…", systemImage: "trash",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Send the selected File(s) to the Trash — recoverable from there"
            ) {
                startMoveToTrash(selectedFileURLs)
            },
            ToolbarAction(
                id: "deleteFilesPermanently", title: selectedFileURLs.count == 1 ? "Delete File Permanently…" : "Delete Files Permanently…", systemImage: "trash.fill",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Permanently delete the selected File(s) — cannot be undone"
            ) {
                startDeleteFilesPermanently(selectedFileURLs)
            },
            ToolbarAction(
                id: "copyFilesToFolder", title: selectedFileURLs.count == 1 ? "Copy File to Folder…" : "Copy Files to Folder…", systemImage: "doc.on.doc",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Copy the selected File(s) into a folder you choose, leaving the originals untouched"
            ) {
                startCopyFilesToFolder(selectedFileURLs)
            },
            ToolbarAction(
                id: "moveFilesToFolder", title: selectedFileURLs.count == 1 ? "Move File to Folder…" : "Move Files to Folder…", systemImage: "folder",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Move the selected File(s) into a folder you choose, removing them from their current location"
            ) {
                startMoveFilesToFolder(selectedFileURLs)
            },
            // jensyleo's own follow-up request (2026-09-11): "Duplicate"/
            // "Compress", same two remaining Finder-style actions on this
            // list. Neither confirms first (see `startDuplicateFiles`'s own
            // doc comment).
            ToolbarAction(
                id: "duplicateFiles", title: selectedFileURLs.count == 1 ? "Duplicate File" : "Duplicate Files", systemImage: "plus.square.on.square",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Create a copy of each selected File right next to it, Finder-style"
            ) {
                startDuplicateFiles(selectedFileURLs)
            },
            ToolbarAction(
                id: "compressFiles", title: selectedFileURLs.count == 1 ? "Compress File" : "Compress Files", systemImage: "archivebox",
                isEnabled: LibraryViewModel.modificationsEnabled && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                help: !LibraryViewModel.modificationsEnabled ? "Disabled for now — enable file modifications in Settings → General first" : selectedFileURLs.isEmpty ? "Select one or more Files in the list first" : "Pack the selected File(s) into a new .zip alongside them, Finder-style"
            ) {
                startCompressFiles(selectedFileURLs)
            },
        ]
    }

    /// The "Export" toolbar button's own dropdown menu — see
    /// `detailToolbarActions`'s own "export" entry for why these three live
    /// here instead of each getting a separate toolbar button. Each sub-
    /// action's own `isEnabled`/gating logic is unchanged from when it was
    /// a standalone button; only where it's declared moved.
    private var exportSubActions: [ToolbarAction] {
        var subs: [ToolbarAction] = []
        if let onExportCollectionReport {
            subs.append(
                ToolbarAction(id: "exportReport", title: "Export Report…", systemImage: "doc.richtext", help: "Save a printable HTML report combining every configured system's last scan") {
                    onExportCollectionReport()
                }
            )
        }
        subs.append(
            ToolbarAction(
                id: "exportFixDat", title: "Export Fix DAT…", systemImage: "square.and.arrow.up",
                isEnabled: viewModel.auditReport != nil && !viewModel.isBusy,
                help: "Save a DAT containing only this scan's missing/incorrect entries"
            ) {
                exportFixDat()
            }
        )
        subs.append(
            ToolbarAction(
                id: "exportListCSV", title: "Export List to CSV…", systemImage: "tablecells",
                isEnabled: !cachedGameNodes.isEmpty && !viewModel.isBusy,
                help: "Save the currently displayed games list as a CSV file"
            ) {
                exportGameListCSV()
            }
        )
        return subs
    }

    /// This view's own contribution to the shared toolbar's "detail"
    /// region — same 9 actions (and the same enabled/help logic) the old
    /// SwiftUI `.toolbar` block used to declare directly; recomputed on
    /// every render exactly like that block was, `ToolbarHost` just
    /// forwards the result into `ROMForgeToolbarController` instead of
    /// SwiftUI managing it.
    // jensyleo's own request (2026-08-19): "revisa como deje el orden de
    // los botones... y déjalos así por defecto" — this order (checked live
    // against a screenshot of the app's own real toolbar after ⌘-drag
    // reordering) is now the app's own default, not just a customization
    // that happened to stick: Scan File, Scan Folder, Scan All Folders,
    // Fix, Play, Export Report…, Export Fix DAT…, Export List to CSV…,
    // Column Presets…
    /// The "Scan" toolbar button's own dropdown menu — jensyleo's own
    /// request (2026-09-13): "Scan All Folders" never touched the
    /// Maintenance folder (correct — see `isSelectedFolderMaintenanceSubfolder`'s
    /// own doc comment on why it must never be folded into this system's
    /// own audit), so he asked for a separate way to refresh ITS OWN
    /// listing, and — rather than a 4th standalone toolbar icon —
    /// consolidating "Scan File"/"Scan Folder"/"Scan All Folders" plus this
    /// new one into a single "Scan" dropdown, same `subActions` pattern
    /// "Fix"/"Export"/"File Actions" already use just below.
    ///
    /// "Scan Maintenance Folder…" is deliberately NOT another
    /// `viewModel.startScan(...)` call — that path feeds this system's own
    /// `MatchReport`/audit, which the Maintenance folder must never enter.
    /// It only re-runs `loadMaintenanceFolderFiles()`, the same plain
    /// Finder-style listing refresh `.onChange(of: selectedRomFolder)`
    /// already triggers on selection — this just lets it be refreshed
    /// on demand too (e.g. after dropping in new donor files without
    /// re-selecting the folder).
    private var scanSubActions: [ToolbarAction] {
        [
            ToolbarAction(id: "scanFile", title: "Scan File", systemImage: "doc.text.magnifyingglass", isEnabled: canScanSelectedFile, help: scanFileButtonHelpText) {
                scanSelectedFile()
            },
            ToolbarAction(
                id: "scanFolder", title: "Scan Folder", systemImage: "folder",
                isEnabled: !viewModel.isBusy && selectedRomFolder != nil && !isSelectedFolderMaintenanceSubfolder,
                help: isSelectedFolderMaintenanceSubfolder
                    ? "The Maintenance folder is a read-only donor area — it's never scanned into this system's own audit"
                    : selectedRomFolder.map { "Scan only \"\($0.lastPathComponent)\" — other folders keep their last known results" }
                        ?? "Select a folder under \"Rom files\" to scan it"
            ) {
                viewModel.startScan(system: system, folders: selectedRomFolder.map { [$0] })
            },
            ToolbarAction(
                id: "scanAllFolders", title: "Scan All Folders", systemImage: "folder.fill",
                isEnabled: !viewModel.isBusy && !system.romFolderURLs.isEmpty,
                help: "Scan every configured \"Rom files\" folder for this system, one after another"
            ) {
                viewModel.startScan(system: system)
            },
            ToolbarAction(
                id: "scanMaintenanceFolder", title: "Scan Maintenance Folder", systemImage: "shippingbox",
                isEnabled: !isLoadingMaintenanceFolderFiles && MaintenanceFolderSettings.subfolderURL(for: system) != nil,
                help: MaintenanceFolderSettings.subfolderURL(for: system) != nil
                    ? "Refresh this system's own Maintenance folder listing — never part of the audit, only a raw disk re-read"
                    : "Set a Maintenance folder location in Settings → Systems → MAME first"
            ) {
                // jensyleo's own request (2026-09-22), extending the same
                // rule already applied to the sidebar's own context-menu
                // "Scan This Folder" — requesting a scan from a menu
                // should never itself jump the whole panel over to
                // Maintenance; only actually clicking that row does. See
                // `startScanMaintenanceFolder`'s own doc comment.
                startScanMaintenanceFolder(navigateToFolder: false)
            },
            // jensyleo's own request (2026-09-24): "olvidaste colocar la
            // opción en el menú desplegable de Scan BIOS folder" — right
            // after adding "Scan This Folder" to the sidebar row's own
            // context menu; this is the same real scan
            // (`viewModel.startScan`, never a special read-only pass —
            // see this folder's own `LibraryViewModel.effectiveScanFolders`
            // doc comment on why it's part of the real audit), just
            // reachable from the toolbar's "Scan" dropdown too, mirroring
            // "Scan Maintenance Folder" right above. Deliberately never
            // navigates to the BIOS row on click, same reasoning as that
            // action's own doc comment.
            ToolbarAction(
                id: "scanBIOSFolder", title: "Scan BIOS Folder", systemImage: "cpu",
                isEnabled: !viewModel.isBusy && system.isMAMEStyle && BIOSFolderSettings.folderURL != nil,
                help: (system.isMAMEStyle ? BIOSFolderSettings.folderURL : nil) != nil
                    ? "Scan only the BIOS folder — other folders keep their last known results"
                    : "Enable a BIOS folder in Settings → Systems → MAME first"
            ) {
                if let biosFolder = BIOSFolderSettings.folderURL {
                    viewModel.startScan(system: system, folders: [biosFolder]) { warnIfSpecialFolderEmpty(biosFolder, kind: "BIOS") }
                }
            },
            ToolbarAction(
                id: "scanComplementaryChipsFolder", title: "Scan Complementary Chips Folder", systemImage: "puzzlepiece.extension",
                isEnabled: !viewModel.isBusy && system.isMAMEStyle && ComplementaryChipsFolderSettings.folderURL != nil,
                help: (system.isMAMEStyle ? ComplementaryChipsFolderSettings.folderURL : nil) != nil
                    ? "Scan only the Complementary Chips folder — other folders keep their last known results"
                    : "Enable a Complementary Chips folder in Settings → Systems → MAME first"
            ) {
                if let chipsFolder = ComplementaryChipsFolderSettings.folderURL {
                    viewModel.startScan(system: system, folders: [chipsFolder]) { warnIfSpecialFolderEmpty(chipsFolder, kind: "Complementary Chips") }
                }
            },
            ToolbarAction(
                id: "scanSamplesFolder", title: "Scan Samples Folder", systemImage: "speaker.wave.2",
                isEnabled: !viewModel.isBusy && system.isMAMEStyle && SamplesFolderSettings.folderURL != nil,
                help: (system.isMAMEStyle ? SamplesFolderSettings.folderURL : nil) != nil
                    ? "Scan only the Samples folder — other folders keep their last known results"
                    : "Enable a Samples folder in Settings → Systems → MAME first"
            ) {
                if let samplesFolder = SamplesFolderSettings.folderURL {
                    viewModel.startScan(system: system, folders: [samplesFolder]) { warnIfSpecialFolderEmpty(samplesFolder, kind: "Samples") }
                }
            },
        ]
    }

    private var detailToolbarActions: [ToolbarAction] {
        var actions: [ToolbarAction] = [
            ToolbarAction(
                id: "scan", title: "Scan", systemImage: "doc.text.magnifyingglass",
                isEnabled: true,
                help: "Scan File, Scan Folder, Scan All Folders, the BIOS, Complementary Chips, or Samples folder, or refresh the Maintenance folder listing",
                action: {},
                subActions: scanSubActions
            ),
            // A single "Fix" dropdown button gathers every Fase 2 write
            // action under one icon — jensyleo's own request (2026-09-01):
            // "no crees un icono por cada fix, crea un submenu en el icono
            // FIX" (each write action was getting its own separate toolbar
            // button, one per Fase 2 step landed). `subActions` makes this
            // an `NSMenuToolbarItem` (see `ToolbarAction.subActions`'s own
            // doc comment) — clicking it shows this menu instead of running
            // an action directly.
            ToolbarAction(
                id: "fix", title: "Fix", systemImage: "wrench.and.screwdriver",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Rebuild, repair, and remove-file actions for this scan"
                    : "Disabled for now — ROMForge only scans and reports, it won't touch your files",
                action: {},
                subActions: fixSubActions
            ),
            ToolbarAction(id: "play", title: "Play", systemImage: "play.fill", isEnabled: canLaunchSelectedGameInEmulator, help: playButtonHelpText) {
                launchSelectedGameInEmulator()
            },
            // "Show Only 1G1R" moved to Settings → View Options → "1G1R"
            // (jensyleo's own request, 2026-08-24) — now a persisted
            // `@AppStorage` toggle there (see `show1G1ROnly`'s own doc
            // comment) rather than a toolbar action button, so it no
            // longer belongs in this list at all.
        ]
        // A single "Export" dropdown gathers every export action under one
        // icon — jensyleo's own request (2026-09-11): "Los 3 iconos de
        // export dejarlo en uno solo que se despliegan las opciones como en
        // el de FIX", the same consolidation "Fix" itself already got
        // (2026-09-01) for the same reason: three separate toolbar buttons
        // for what's really one category of action. `subActions` makes
        // this an `NSMenuToolbarItem` exactly like "Fix" (see
        // `ToolbarAction.subActions`'s own doc comment) — clicking it shows
        // this menu instead of running an action directly. The top-level
        // button stays enabled whenever at least one export is actually
        // possible; each sub-action still gates itself individually inside
        // the menu, same as "Fix"'s own sub-actions do.
        actions.append(
            ToolbarAction(
                id: "export", title: "Export", systemImage: "square.and.arrow.up",
                isEnabled: !exportSubActions.isEmpty,
                help: "Export this scan's results as a report, a Fix DAT, or a CSV list",
                action: {},
                subActions: exportSubActions
            )
        )
        // A "File Actions" dropdown for plain, OS-level file management
        // (Move to Trash, Delete Permanently, Copy/Move to Folder…) —
        // jensyleo's own request (2026-09-11): "eliminar y copiar a otra
        // carpeta... en un boton del menu que se llame File action", same
        // one-icon-many-actions dropdown shape as "Fix"/"Export" above.
        // Operates on whatever is currently selected in the Games table
        // (`selectedFileURLs`), unlike "Fix" (which scopes to a whole ROM
        // folder) or "Export" (which needs no selection at all) — enabled
        // only when at least one File is actually selected.
        actions.append(
            ToolbarAction(
                id: "fileActions", title: "File Actions", systemImage: "ellipsis.circle",
                // jensyleo's own request (2026-09-17): gated on
                // `viewModel.auditReport != nil` too now, matching "Fix"
                // above — a File could be "selected" in the table before
                // any scan ever ran (a never-scanned catalog view can
                // still show rows), and acting on it then had nothing
                // real (an up-to-date report) to fall back on if
                // something needed re-checking afterward.
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !selectedFileURLs.isEmpty && !viewModel.isBusy,
                // jensyleo's own hands-on QA pass (2026-09-11): this only
                // ever explained the "nothing selected" reason, unlike
                // every sibling dropdown ("Fix") — a real file could be
                // selected while modifications are still disabled in
                // Settings → General, and the tooltip silently never said
                // so, same class of gap "Fix"'s own help text already
                // avoids.
                help: !LibraryViewModel.modificationsEnabled
                    ? "Disabled for now — enable file modifications in Settings → General first"
                    : viewModel.auditReport == nil
                        ? "Scan this system first"
                        : selectedFileURLs.isEmpty
                            ? "Select one or more Files in the list first"
                            : "Move to Trash, delete, copy, move, duplicate, or compress the selected File(s)",
                action: {},
                subActions: fileActionsSubActions
            )
        )
        // "Column Presets…" moved to Settings → View Options → "Columns"
        // (jensyleo's own request, 2026-08-24) — it's a layout preference,
        // not a per-scan action, so it belongs alongside every other
        // display toggle rather than sitting in the same toolbar as
        // Scan/Fix/Export. `.romForgeShowColumnPresetsSheet` (posted by
        // that Settings button) is how it still reaches this exact sheet
        // without duplicating `columnPresets`'s own load/save/apply logic
        // there — same "notify the live window" shape as
        // `SavedViewStatePurger.scanResultsPurgedNotification` above.
        return actions
    }

    var body: some View {
        // jensyleo's own type-checker wall, hit again adding "File Actions"
        // (2026-09-11) — same "unable to type-check this expression in
        // reasonable time" this file's own confirmation-dialog modifiers
        // already ran into once (see `fase2Confirmations`'s own doc
        // comment): one continuous chained expression this long eventually
        // exceeds the type-checker's budget regardless of how each
        // individual modifier is itself already factored out. Splitting
        // the chain into two separate statements (`let content = ...`,
        // then `return content....`) — rather than adding yet another
        // parameter to an existing modifier function — is what actually
        // keeps it under budget, the same fix this exact comment predicted
        // future additions would eventually need.
        let content = VStack(alignment: .leading, spacing: 12) {
            header
            if !LibraryViewModel.modificationsEnabled {
                Label("View-only mode — ROMForge won't rename, move or modify any ROM file.", systemImage: "eye")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            // jensyleo's own report (2026-08-11): "la imagen de fondo
            // desaparece durante el Rescan" — a rescan that needed to
            // reload the DAT (e.g. right after changing Rom merge mode)
            // blanked this ENTIRE area to a bare loading card, hiding
            // whatever the user was just looking at. That blanking was a
            // deliberate fix for a different, narrower case (switching
            // between two genuinely different DATs for the same system,
            // e.g. comparing MAME versions — see `header`'s own doc
            // comment, which still applies: the DAT name/version there
            // still reads "Loading…" rather than the stale previous one).
            // jensyleo's own call once shown both options: never blank this
            // area at all — keep whatever was already visible up, with
            // `scanProgressOverlay` (below) on top, exactly like every
            // other busy state already works (folder/category clicks,
            // scanning, matching). `scanProgressOverlay` already has its
            // own `isLoadingDAT` branch with the identical progress UI
            // `loadingDATPlaceholder` used to duplicate, so nothing about
            // the loading feedback itself was lost — only the full-screen
            // wipe.
            statusSummary
            Divider()
            // `AutosavingSplitView` (a thin `NSSplitView` wrapper — see its
            // own doc comment for the real story) instead of SwiftUI's
            // `VSplitView`/`HSplitView`: both give a draggable divider for
            // free, but neither remembers where the user leaves it across
            // launches.
            // jensyleo's own request (2026-08-12): each of the five main
            // panels below can be switched off entirely from Settings →
            // View Options (`PanelVisibilitySettings`) — `visibleTopPanes`/
            // `visibleBottomPanes` build each row's own pane list from
            // whichever of its panels are still switched on, and the row
            // itself collapses to nothing (rather than an empty, still-
            // resizable sliver) if every one of its panels is off.
            // Default fractions below (2026-09-23) — jensyleo's own explicit
            // request: "revisa como deje los paneles y de ahora en adelante
            // esos son los tamaños que vamos a dejar por defecto." Captured
            // directly from his own live `UserDefaults` at the moment of
            // that request (`defaults read com.jensyleo.romforge
            // ROMForge.splitFractions.ROMForge.<name>`), same technique
            // already used for `DatabaseFilterVisibilitySettings.defaultEnabled`.
            // Only ever applies on a genuinely fresh install/first launch —
            // any real drag the user makes persists over these from then on,
            // exactly like `sidebarDetailSplit`'s own `defaultFractions`
            // right above already works.
            AutosavingSplitView(axis: .stacked, autosaveName: "ROMForge.mainRowsSplit", panes: [
                SplitPane(minLength: visibleTopPanes.isEmpty ? 0 : 160) {
                    Group {
                        if !visibleTopPanes.isEmpty {
                            AutosavingSplitView(
                                axis: .sideBySide, autosaveName: "ROMForge.databaseGamesRomsSplit", panes: visibleTopPanes,
                                defaultFractions: [0.1391982182628062, 0.5244988864142539, 0.3348181143281366]
                            )
                        }
                    }
                },
                SplitPane(minLength: visibleBottomPanes.isEmpty ? 0 : 90) {
                    Group {
                        if !visibleBottomPanes.isEmpty {
                            AutosavingSplitView(
                                axis: .sideBySide, autosaveName: "ROMForge.detailLogSplit", panes: visibleBottomPanes,
                                defaultFractions: [0.5003711952487008, 0.4988864142538976]
                            )
                        }
                    }
                },
            ], defaultFractions: [0.7336065573770492, 0.2650273224043716])
        }
        .padding()
        .frame(minWidth: 760, minHeight: 480)
        // jensyleo's own request (2026-08-19): the real, hand-built AppKit
        // toolbar (see `ROMForgeToolbar.swift`'s own doc comment for the
        // full "why" — SwiftUI's own `.toolbar(id:)` never got AppKit to
        // set `allowsUserCustomization` from this nested a view, and a
        // first attempt at going straight to AppKit broke the app outright
        // while `ContentView` still used `NavigationSplitView`; see that
        // controller's own doc comment for the full story). This view only
        // ever contributes its own "detail" region's current action list;
        // `ContentView` owns installing/updating the toolbar itself.
        .background(
            Group {
                if let toolbarController {
                    ToolbarHost(region: "detail", actions: detailToolbarActions, controller: toolbarController)
                }
            }
        )
        .overlay {
            // Covers `isLoadingDAT` too now (2026-08-11) — `scanProgressOverlay`
            // already has its own DAT-loading branch with the same progress
            // UI `loadingDATPlaceholder` used to duplicate; see `body`'s own
            // doc comment above (right before `statusSummary`) for why the
            // full-screen blank this used to avoid double-showing with is
            // gone entirely now, not just narrowed.
            if viewModel.isBusy || isPreloadingZipComments {
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
        // jensyleo's own request (2026-09-09): opening an already-scanned
        // system shows its persisted results immediately, which leaves
        // every Fix button reading as enabled (`auditReport != nil`) even
        // when no write action has anything LIVE to act on yet — a real
        // scan this session (as opposed to loading yesterday's saved
        // report) never ran. Deliberately NOT disabling the buttons for
        // this (an earlier pass did — jensyleo's own follow-up report:
        // "eso no es intuitivo... indica con un mensaje 'Scan first'" — a
        // silently-disabled button explains nothing): every write action's
        // own preview/execute function now calls `requireMatchReport()`
        // first, which pops this alert immediately on click instead of
        // the button doing nothing or logging a message nobody was
        // watching.
        .alert(
            "Scan Required",
            isPresented: Binding(
                get: { viewModel.scanRequiredAlertIsPresented },
                set: { viewModel.scanRequiredAlertIsPresented = $0 }
            )
        ) {
            Button("OK") { viewModel.scanRequiredAlertIsPresented = false }
        } message: {
            Text("This system hasn't been scanned yet this session. Run \"Scan Folder\" or \"Scan All Folders\" first.")
        }
        // "Rescan Required" — jensyleo's own decision (2026-09-10): the
        // "el último scan es el que aplica" rule (`LibraryViewModel
        // .scopeCoveredByLastScan`) blocks a Fix whose target wasn't part
        // of the most recent Scan, and needs the SAME "alert on click, not
        // just a log line" treatment as "Scan Required" above — a log line
        // alone was easy to miss, and hiding the Fix option instead would
        // read as a mystery disappearance (the exact complaint that already
        // happened once with "Fix Mismatched File"). `isPresented` is
        // driven by the message itself being non-nil rather than a
        // separate `Bool`, since the text varies per call.
        .alert(
            "Rescan Required",
            isPresented: Binding(
                get: { viewModel.rescanRequiredAlertMessage != nil },
                set: { if !$0 { viewModel.rescanRequiredAlertMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.rescanRequiredAlertMessage = nil }
        } message: {
            Text(viewModel.rescanRequiredAlertMessage ?? "")
        }
        // Same reasoning as "Rescan Required" right above — real report,
        // live (2026-09-24): "si activo la opción sin configurar la
        // carpeta me sale el error en el log pero la app no muestra
        // mensaje." See `LibraryViewModel
        // .configurationRequiredAlertMessage`'s own doc comment.
        .alert(
            "Configuration Required",
            isPresented: Binding(
                get: { viewModel.configurationRequiredAlertMessage != nil },
                set: { if !$0 { viewModel.configurationRequiredAlertMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.configurationRequiredAlertMessage = nil }
        } message: {
            Text(viewModel.configurationRequiredAlertMessage ?? "")
        }
        // Same reasoning as "Configuration Required" right above — real
        // request, jensyleo (2026-09-24): "si no encuentra nada avise
        // desde la app, no solo desde el log."
        .alert(
            "Nothing Found",
            isPresented: Binding(
                get: { viewModel.scanFoundNothingAlertMessage != nil },
                set: { if !$0 { viewModel.scanFoundNothingAlertMessage = nil } }
            )
        ) {
            Button("OK") { viewModel.scanFoundNothingAlertMessage = nil }
        } message: {
            Text(viewModel.scanFoundNothingAlertMessage ?? "")
        }
        .onChange(of: activeStatusFilters) {
            selectedGameID = nil; selectedRomID = nil
            triggerCachedGameDataRecompute()
            refreshExpandedDatabaseCategoryCachesAsync(debounced: false)
        }
        .onChange(of: showUnknownArchives) {
            selectedGameID = nil; selectedRomID = nil
            triggerCachedGameDataRecompute()
            refreshExpandedDatabaseCategoryCachesAsync(debounced: false)
        }
        .onChange(of: combineRomAndCHD) {
            selectedGameID = nil; selectedRomID = nil
            triggerCachedGameDataRecompute()
            refreshExpandedDatabaseCategoryCachesAsync(debounced: false)
        }
        .onChange(of: show1G1ROnly) {
            selectedGameID = nil; selectedRomID = nil
            triggerCachedGameDataRecompute()
        }
        // A region-priority change (Settings → View Options) can flip which
        // variant a family's own star/hide belongs to — needs the full
        // `refreshCachedGameDataAfterAuditReportChangeAsync()` path (not
        // just `triggerCachedGameDataRecompute()`) since `cachedOneGameOneROMSummary`
        // itself, not merely the Games-table filter reading it, has to be
        // recomputed.
        .onChange(of: regionOrderRaw) {
            refreshCachedGameDataAfterAuditReportChangeAsync()
        }
        .onChange(of: selectedDatabaseFilter) { handleSelectedDatabaseFilterChange() }
        .onChange(of: selectedGameID) { selectedRomID = nil }
        .onChange(of: selectedRomFolder) {
            selectedGameID = nil; selectedRomID = nil
            selectedGameFamilyRootMachineName = nil
            triggerCachedGameDataRecompute()
            persistLastSelection()
            // The Maintenance subfolder's own plain listing
            // (`maintenanceFolderFilesList`) is never part of the audited
            // Games tree `triggerCachedGameDataRecompute()` refreshes above
            // — it needs its own, separate load the FIRST time the
            // selected folder becomes it (never on every re-selection —
            // see `loadMaintenanceFolderFilesIfNeeded`'s own doc comment).
            if isSelectedFolderMaintenanceSubfolder {
                loadMaintenanceFolderFilesIfNeeded()
            } else {
                maintenanceFolderFiles = []
            }
            applyOrRestoreBIOSColumnsIfNeeded()
        }
        .onChange(of: viewModel.auditReport) {
            // See `ZipCommentCache.invalidate(underAnyOf:)`'s own doc
            // comment — a real scan can change (or remove) any archive's
            // own ZIP comment, and this cache has no other way to notice.
            //
            // Scoped to `viewModel.lastScanFolders` when this scan was
            // itself scoped (see that property's own doc comment for the
            // "more than a minute to refresh" report this fixes) — a
            // whole-system scan (`nil`) means every one of THIS system's
            // own folders was covered, so those are what gets invalidated.
            //
            // Never a true `invalidateAll()` anymore — jensyleo's own
            // report (2026-09-26): now that this cache is shared across
            // every system (`ZipCommentCache.shared`, so re-visiting an
            // already-warmed system doesn't start cold again), a true
            // whole-cache wipe here would also throw away every OTHER
            // system's already-warmed comments just because THIS one
            // finished a scan.
            zipCommentCache.invalidate(underAnyOf: viewModel.lastScanFolders ?? system.romFolderURLs)
            refreshCachedGameDataAfterAuditReportChangeAsync()
            // See `organizeBIOSFilesAvailableCache`'s own doc comment —
            // recomputed here, once per real scan result, never from a
            // render path.
            organizeBIOSFilesAvailableCache = viewModel.hasMatchReport && viewModel.planOrganizeBIOSFilesPreviewCount() > 0
            organizeComplementaryChipsAvailableCache = viewModel.hasMatchReport && viewModel.planOrganizeComplementaryChipsPreviewCount() > 0
        }
        // jensyleo's own report (2026-08-12): "Purge Database View"
        // (Settings → View Options) cleared the on-disk scan data, but this
        // exact window — if already open at the time — kept showing its
        // existing in-memory report regardless, "esto no debería pasar".
        // `viewModel.clearScanResults()` sets `auditReport = nil`, which
        // the `.onChange(of: viewModel.auditReport)` right above already
        // reacts to correctly — no separate recompute needed here.
        .onReceive(NotificationCenter.default.publisher(for: SavedViewStatePurger.scanResultsPurgedNotification)) { _ in
            viewModel.clearScanResults()
        }
        .onChange(of: viewModel.cachedDATFile) { handleCachedDATFileChange() }
        .onAppear {
            installResultsArrowKeyMonitor()
            installRomFolderReorderMonitor()
            viewModel.loadPersistedReport(system: system)
            refreshCachedGameDataAfterAuditReportChangeAsync()
            organizeBIOSFilesAvailableCache = viewModel.hasMatchReport && viewModel.planOrganizeBIOSFilesPreviewCount() > 0
            organizeComplementaryChipsAvailableCache = viewModel.hasMatchReport && viewModel.planOrganizeComplementaryChipsPreviewCount() > 0
            // Loads the DAT immediately, independent of scanning any
            // folder — previously the DAT only ever loaded as the first
            // phase of a real Scan, so simply adding/opening a system with
            // its DAT+folders already selected did nothing until the user
            // pressed "Scan Folder".
            viewModel.startPreloadDAT(system: system)
            // jensyleo's own report (2026-09-16): deleting a system's
            // Maintenance subfolder (Settings, or the sidebar's own
            // "Remove System and Delete Maintenance Folder") looked like it
            // "didn't work" because simply opening/re-opening this exact
            // detail view immediately recreated it empty via this call —
            // used to run unconditionally on every `.onAppear`. Removed:
            // jensyleo's explicit choice is that a deleted subfolder should
            // stay gone until it's genuinely needed again, not reappear
            // just from viewing the system. The real, still-lazy creation
            // now happens only where the subfolder is actually about to be
            // read from (`LibraryViewModel`'s own Maintenance-folder-files
            // loading) or explicitly, in Settings, right after the
            // Maintenance root itself is (re)configured.
            //
            // Covers the case where `selectedRomFolder` is ALREADY the
            // Maintenance subfolder the moment this view appears (restored
            // from a previous session) — `.onChange(of: selectedRomFolder)`
            // above only fires on a later change, never for that initial
            // value.
            if isSelectedFolderMaintenanceSubfolder {
                loadMaintenanceFolderFilesIfNeeded()
            }
        }
        .onDisappear {
            removeResultsArrowKeyMonitor()
            removeRomFolderReorderMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: .romForgeResetColumnSizes)) { _ in
            UserDefaults.standard.removeObject(forKey: Self.gameColumnCustomizationKey)
            UserDefaults.standard.removeObject(forKey: Self.romColumnCustomizationKey)
            // One-shot push into each child's own local state — see
            // `gameColumnCustomizationOverride`'s own doc comment.
            gameColumnCustomizationOverride = TableColumnCustomization<GameNode>()
            romColumnCustomizationOverride = TableColumnCustomization<RomRow>()
        }
        // Column-preset management lives inline in Settings → View Options →
        // Panels now (jensyleo's own request, 2026-08-31 — see
        // `.romForgeApplyColumnPreset`'s own doc comment in `ROMForgeApp.swift`
        // for why: a separate sheet meant closing+reopening Settings' own
        // sheet around it, which felt sluggish no matter how fast that
        // round-trip itself was made). This view still owns every real
        // mutation — Settings' UI only ever asks for one via these five
        // notifications, never touches `columnPresets`/`columnPresetOrder`
        // directly. Bundled into one `View` extension (not five chained
        // `.onReceive` calls inline here) so the type-checker sees a single
        // opaque-`some View`-returning call at this spot rather than five
        // more closures piled onto an already-huge modifier chain — inlined,
        // this started timing out compilation ("unable to type-check this
        // expression in reasonable time").
        .columnPresetNotificationHandlers(
            onApply: { applyColumnPreset(named: $0) },
            onSave: { saveColumnPreset(named: $0) },
            onDelete: { deleteColumnPreset(named: $0) },
            onRename: { renameColumnPreset(from: $0, to: $1) },
            onSetOrder: { columnPresetOrder = $0; persistColumnPresetOrder() }
        )
        .fase2Confirmations(
            rebuildDestination: rebuildDestination,
            rebuildOperationCount: rebuildOperationCount,
            showRebuild: $showRebuildConfirmation,
            onCopy: { commitRebuildToFolder(move: false) },
            onMove: { commitRebuildToFolder(move: true) },
            onCancelRebuild: { rebuildDestination = nil },
            showRemoveUselessFiles: $showRemoveUselessFilesConfirmation,
            removeUselessFilesCount: removeUselessFilesCount,
            onRemoveUselessFiles: commitRemoveUselessFiles,
            showRepair: $showRepairFromSiblingSetsConfirmation,
            repairCount: repairFromSiblingSetsCount,
            onRepair: commitRepairFromSiblingSets,
            showMakeSelfContained: $showMakeSelfContainedConfirmation,
            makeSelfContainedCount: makeSelfContainedCount,
            onMakeSelfContained: commitMakeSelfContained,
            showRenameRomsInArchive: $showRenameRomsInArchiveConfirmation,
            renameRomsInArchiveCount: renameRomsInArchiveCount,
            onRenameRomsInArchive: commitRenameRomsInArchive
        )
        .fase2Step4SplitConfirmation(
            isPresented: $showConvertToSplitConfirmation,
            count: convertToSplitCount,
            onConfirm: commitConvertToSplit
        )
        .fixAllConfirmation(
            isPresented: $showFixAllConfirmation,
            count: fixAllCount,
            onConfirm: commitFixAll
        )
        .repairFromMaintenanceFolderConfirmation(
            isPresented: $showRepairFromMaintenanceFolderConfirmation,
            count: repairFromMaintenanceFolderCount,
            onConfirm: commitRepairFromMaintenanceFolder
        )
        .removeRedundantFilesConfirmation(
            isPresented: $showRemoveRedundantFilesConfirmation,
            count: removeRedundantFilesCount,
            onConfirm: commitRemoveRedundantFiles
        )
        .removeRedundantRomsConfirmation(
            isPresented: $showRemoveRedundantRomsConfirmation,
            count: removeRedundantRomsCount,
            onConfirm: commitRemoveRedundantRoms
        )
        .organizeBIOSFilesConfirmation(
            isPresented: $showOrganizeBIOSFilesConfirmation,
            count: organizeBIOSFilesCount,
            lines: organizeBIOSFilesLines,
            onConfirm: commitOrganizeBIOSFiles
        )
        .organizeComplementaryChipsConfirmation(
            isPresented: $showOrganizeComplementaryChipsConfirmation,
            count: organizeComplementaryChipsCount,
            lines: organizeComplementaryChipsLines,
            onConfirm: commitOrganizeComplementaryChips
        )
        .createDummyRomsConfirmation(
            isPresented: $showCreateDummyRomsConfirmation,
            count: createDummyRomsCount,
            onConfirm: commitCreateDummyRoms
        )
        .removeZipCommentsConfirmation(
            isPresented: $showRemoveZipCommentsConfirmation,
            count: removeZipCommentsCount,
            onConfirm: commitRemoveZipComments
        )
        .collectSamplesConfirmation(
            isPresented: $showCollectSamplesConfirmation,
            count: collectSamplesCount,
            onConfirm: commitCollectSamples
        )
        .contextMenuRenameRomsInArchiveConfirmation(
            isPresented: $showContextMenuRenameRomsInArchiveConfirmation,
            count: contextMenuRenameRomsInArchiveCount,
            onConfirm: commitContextMenuRenameRomsInArchive
        )
        .removeZipCommentsConfirmation(
            isPresented: $showContextMenuRemoveZipCommentsConfirmation,
            count: contextMenuRemoveZipCommentsCount,
            onConfirm: commitContextMenuRemoveZipComments
        )
        .fixMismatchedFilesConfirmation(
            isPresented: $showFixMismatchedFilesConfirmation,
            count: fixMismatchedFilesCount,
            onConfirm: commitFixMismatchedFiles
        )
        .fixMismatchedFilesConfirmation(
            isPresented: $showContextMenuFixMismatchedFilesConfirmation,
            count: contextMenuFixMismatchedFilesCount,
            onConfirm: commitContextMenuFixMismatchedFile
        )
        .contextMenuRemoveUselessFilesConfirmation(
            isPresented: $showContextMenuRemoveUselessFilesConfirmation,
            count: contextMenuRemoveUselessFilesCount,
            onConfirm: commitContextMenuRemoveUselessFiles
        )
        .contextMenuRemoveRedundantFilesConfirmation(
            isPresented: $showContextMenuRemoveRedundantFilesConfirmation,
            count: contextMenuRemoveRedundantFilesCount,
            onConfirm: commitContextMenuRemoveRedundantFiles
        )
        .contextMenuRemoveRedundantRomsConfirmation(
            isPresented: $showContextMenuRemoveRedundantRomsConfirmation,
            count: contextMenuRemoveRedundantRomsCount,
            onConfirm: commitContextMenuRemoveRedundantRoms
        )
        .renameToSimilarNameConfirmation(
            url: pendingSimilarNameURL, suggestion: pendingSimilarNameSuggestion,
            isPresented: $showRenameToSimilarNameConfirmation,
            onConfirm: commitRenameToSimilarNameSuggestion
        )
        .handleCorruptedFilesConfirmation(
            isPresented: $showHandleCorruptedFilesConfirmation,
            count: handleCorruptedFilesCount,
            onConfirm: commitHandleCorruptedFiles
        )
        .convertToMergedConfirmation(
            isPresented: $showConvertToMergedConfirmation,
            count: convertToMergedCount,
            onConfirm: commitConvertToMerged
        )
        return content
        .fileActionsConfirmations(
            urlCount: pendingFileActionURLs.count,
            destination: pendingFileActionDestination,
            showMoveToTrash: $showMoveToTrashConfirmation,
            onMoveToTrash: commitMoveToTrash,
            showDeletePermanently: $showDeletePermanentlyConfirmation,
            onDeletePermanently: commitDeleteFilesPermanently,
            showCopyToFolder: $showCopyToFolderConfirmation,
            onCopyToFolder: commitCopyFilesToFolder,
            showMoveToFolder: $showMoveToFolderConfirmation,
            onMoveToFolder: commitMoveFilesToFolder,
            replaceFilenames: pendingReplaceFilenames,
            showReplaceExisting: $showReplaceExistingConfirmation,
            onReplaceExisting: commitReplaceExisting
        )
        .romEntryActionsConfirmations(
            showExtract: $showExtractRomEntriesConfirmation,
            extractCount: pendingRomEntryTargets.count,
            extractDestination: pendingRomEntryDestination,
            onExtract: commitExtractRomEntries,
            showTrash: $showMoveRomEntriesToTrashConfirmation,
            trashCount: pendingRomEntryTargets.count,
            onTrash: commitMoveRomEntriesToTrash,
            showDelete: $showDeleteRomEntriesPermanentlyConfirmation,
            deleteCount: pendingRomEntryTargets.count,
            onDelete: commitDeleteRomEntriesPermanently
        )
        .fixResultAlert(alert: viewModel.fixResultAlert) { viewModel.fixResultAlert = nil }
    }

    /// Opens the destination-folder picker, then previews the operation
    /// count before showing the confirmation dialog — same dry-run-before-
    /// write caution as every other Fase 2 action.
    private func startRebuildToFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination folder for the rebuilt ROM sets"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        rebuildDestination = destination
        rebuildOperationCount = viewModel.planRebuildPreviewCount(destination: destination, move: false)
        guard rebuildOperationCount > 0 else {
            viewModel.logWarning("Nothing to rebuild — no matched ROMs in the current scan.")
            rebuildDestination = nil
            return
        }
        showRebuildConfirmation = true
    }

    private func commitRebuildToFolder(move: Bool) {
        guard let rebuildDestination else { return }
        Task { await viewModel.rebuildToFolder(system: system, destination: rebuildDestination, move: move) }
        self.rebuildDestination = nil
    }

    /// Previews the delete count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    private func startRemoveUselessFiles() {
        guard let selectedRomFolder else {
            viewModel.logWarning("Select a ROM folder first — \"Remove Useless Files…\" only ever acts on the folder currently selected.")
            return
        }
        removeUselessFilesCount = viewModel.planRemoveUselessFilesPreviewCount(scopeFolders: [selectedRomFolder])
        guard removeUselessFilesCount > 0 else {
            viewModel.logWarning("Nothing to remove — no unrecognized files inside \"\(selectedRomFolder.lastPathComponent)\" in the current scan.")
            return
        }
        showRemoveUselessFilesConfirmation = true
    }

    private func commitRemoveUselessFiles() {
        let scopeFolders = selectedRomFolder.map { [$0] } ?? []
        Task { await viewModel.removeUselessFiles(system: system, scopeFolders: scopeFolders) }
    }

    // MARK: - File Actions (generic, OS-level — jensyleo's own request, 2026-09-11)

    /// jensyleo's own request (2026-09-11): "mover, copiar o modificar en
    /// las carpetas de mantenimiento, no es posible y debe ponerse un
    /// mensaje que informe de esto cuando alguien lo intente hacer" — the
    /// Maintenance folder (root and every per-system subfolder) is
    /// documented, deliberately read-only donor storage
    /// (`MaintenanceFolderSettings.subfolderURL(for:)`'s own doc comment).
    /// Checked BEFORE any confirmation dialog even opens — a bulk action
    /// either fully proceeds or fully refuses, never partially. jensyleo's
    /// own follow-up (2026-09-11): "no solo debe salir un log sino un
    /// mensaje emergente" — a log line alone is easy to miss (the Log panel
    /// can be scrolled past or collapsed); a real, modal `NSAlert` is what
    /// actually gets in front of the person who just tried this, same
    /// synchronous-modal pattern the destination-folder `NSOpenPanel`s
    /// elsewhere in this file already use.
    private func rejectIfUnderMaintenanceFolder(_ urls: [URL]) -> Bool {
        guard urls.contains(where: MaintenanceFolderSettings.isUnderMaintenanceFolder) else { return true }
        let message = "The Maintenance folder is a read-only donor area (Settings → Systems → MAME) — files inside it (or any of its per-system subfolders) can never be moved, copied, duplicated, deleted, or compressed by ROMForge. Move or copy them somewhere else first."
        viewModel.logError(message)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Maintenance Folder Is Read-Only"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        return false
    }

    private func startMoveToTrash(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        pendingFileActionURLs = urls
        showMoveToTrashConfirmation = true
    }

    private func commitMoveToTrash() {
        let urls = pendingFileActionURLs
        pendingFileActionURLs = []
        Task { await viewModel.moveFilesToTrash(system: system, urls: urls) }
    }

    private func startDeleteFilesPermanently(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        pendingFileActionURLs = urls
        showDeletePermanentlyConfirmation = true
    }

    private func commitDeleteFilesPermanently() {
        let urls = pendingFileActionURLs
        pendingFileActionURLs = []
        Task { await viewModel.deleteFilesPermanently(system: system, urls: urls) }
    }

    private func startCopyFilesToFolder(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination folder to copy \(urls.count) file(s) to"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        pendingFileActionURLs = urls
        pendingFileActionDestination = destination
        showCopyToFolderConfirmation = true
    }

    private func commitCopyFilesToFolder() {
        let urls = pendingFileActionURLs
        guard let destination = pendingFileActionDestination else { return }
        let collisions = LibraryViewModel.existingDestinationFilenames(for: urls, in: destination)
        guard collisions.isEmpty else {
            pendingReplaceFilenames = collisions
            pendingReplaceIsMove = false
            showReplaceExistingConfirmation = true
            return
        }
        pendingFileActionURLs = []
        pendingFileActionDestination = nil
        Task { await viewModel.copyFiles(system: system, urls, to: destination) }
    }

    private func startMoveFilesToFolder(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination folder to move \(urls.count) file(s) to"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        pendingFileActionURLs = urls
        pendingFileActionDestination = destination
        showMoveToFolderConfirmation = true
    }

    private func commitMoveFilesToFolder() {
        let urls = pendingFileActionURLs
        guard let destination = pendingFileActionDestination else { return }
        let collisions = LibraryViewModel.existingDestinationFilenames(for: urls, in: destination)
        guard collisions.isEmpty else {
            pendingReplaceFilenames = collisions
            pendingReplaceIsMove = true
            showReplaceExistingConfirmation = true
            return
        }
        pendingFileActionURLs = []
        pendingFileActionDestination = nil
        Task { await viewModel.moveFiles(system: system, urls: urls, to: destination) }
    }

    /// Runs after the user explicitly confirms `showReplaceExistingConfirmation`
    /// — see that state's own doc comment. Re-derives `urls`/`destination`
    /// from the same `pendingFileActionURLs`/`Destination` the original
    /// Copy/Move confirmation already populated (never cleared until this
    /// point, precisely so this second, replace-specific step can still
    /// reach them).
    private func commitReplaceExisting() {
        let urls = pendingFileActionURLs
        guard let destination = pendingFileActionDestination else { return }
        pendingFileActionURLs = []
        pendingFileActionDestination = nil
        let filenames = Set(pendingReplaceFilenames)
        pendingReplaceFilenames = []
        if pendingReplaceIsMove {
            Task { await viewModel.moveFiles(system: system, urls: urls, to: destination, replacingFilenames: filenames) }
        } else {
            Task { await viewModel.copyFiles(system: system, urls, to: destination, replacingFilenames: filenames) }
        }
    }

    /// `GameTreeTableView`'s own "Rename to…" context-menu button — see its
    /// own doc comment. Stores both the URL and the exact suggestion the
    /// user just saw so the confirmation dialog can quote them precisely.
    private func startRenameToSimilarNameSuggestion(_ url: URL, _ suggestion: SimilarNameSuggestion) {
        pendingSimilarNameURL = url
        pendingSimilarNameSuggestion = suggestion
        showRenameToSimilarNameConfirmation = true
    }

    private func commitRenameToSimilarNameSuggestion() {
        guard let url = pendingSimilarNameURL else { return }
        pendingSimilarNameURL = nil
        pendingSimilarNameSuggestion = nil
        Task { await viewModel.renameToSimilarNameSuggestion(system: system, url: url) }
    }

    /// No confirmation dialog — same as Finder's own "Duplicate"/"Compress",
    /// which run immediately with no prompt (never destructive to the
    /// source, unlike Move/Delete/Trash above, which all confirm first).
    private func startDuplicateFiles(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        Task { await viewModel.duplicateFiles(system: system, urls: urls) }
    }

    private func startCompressFiles(_ urls: [URL]) {
        guard !urls.isEmpty, rejectIfUnderMaintenanceFolder(urls) else { return }
        Task { await viewModel.compressFiles(system: system, urls: urls) }
    }

    /// Previews the repair count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    /// Toolbar → "Fix" → "Fix All" — jensyleo's own request (2026-09-29):
    /// preview needs a real (async) count across several sub-actions —
    /// same reasoning `startCollectSamples()` above dispatches through a
    /// `Task`, unlike most other `start*` functions here.
    private func startFixAll() {
        Task {
            fixAllCount = await viewModel.planFixAllPreviewCount(system: system, enabledActionIDs: Self.fixActionsEnabledForTesting)
            guard fixAllCount > 0 else {
                viewModel.logWarning("Nothing to fix — every automatic Fix action already has nothing to do.")
                return
            }
            showFixAllConfirmation = true
        }
    }

    private func commitFixAll() {
        Task {
            await viewModel.fixAll(system: system, enabledActionIDs: Self.fixActionsEnabledForTesting)
            // "Fix All" can run Remove Zip Comments among its sub-actions;
            // same real root cause as `commitRemoveZipComments` above —
            // `onChange(of: viewModel.auditReport)` never fires for a
            // comment-only change (nothing `Equatable` compares actually
            // differs), so this cache is never invalidated as a side
            // effect of fixAll's own internal scan. Invalidate the whole
            // system directly (fixAll's own removeZipComments call always
            // runs unscoped, i.e. every folder), then force the redraw.
            zipCommentCache.invalidate(underAnyOf: system.romFolderURLs)
            zipCommentTableReloadToken += 1
        }
    }

    private func startRepairFromSiblingSets() {
        repairFromSiblingSetsCount = viewModel.planRepairFromSiblingSetsPreviewCount()
        guard repairFromSiblingSetsCount > 0 else {
            viewModel.logWarning("Nothing to repair from sibling sets — no missing rom has a matching donor in this scan.")
            return
        }
        showRepairFromSiblingSetsConfirmation = true
    }

    private func commitRepairFromSiblingSets() {
        Task { await viewModel.repairFromSiblingSets(system: system) }
    }

    /// Previews the count before showing the confirmation dialog — same
    /// dry-run-before-write caution as every other Fase 2 action.
    private func startCreateDummyRoms() {
        createDummyRomsCount = viewModel.planCreateDummyRomsPreviewCount()
        guard createDummyRomsCount > 0 else {
            viewModel.logWarning("Nothing to create — no missing nodump rom found in this scan.")
            return
        }
        showCreateDummyRomsConfirmation = true
    }

    private func commitCreateDummyRoms() {
        Task { await viewModel.createDummyRoms(system: system) }
    }

    /// jensyleo's own report (2026-09-26): "Remove Zip Comments" from the
    /// toolbar's own Fix menu reported "Nothing to remove" against his real
    /// collection, even though the currently-selected folder visibly had
    /// matched archives with real comments — the same file worked fine
    /// from the Games table's own context menu. Root cause: this was the
    /// ONE Fix action that never scoped itself to `selectedRomFolder` at
    /// all (every sibling action — `startRemoveUselessFiles`,
    /// `startRemoveRedundantFiles`, etc. — does), so it always walked
    /// EVERY folder across the whole system instead of just the one being
    /// looked at. Now matches that same established pattern.
    private func startRemoveZipComments() {
        guard let selectedRomFolder else {
            viewModel.logWarning("Select a ROM folder first — \"Remove Zip Comments…\" only ever acts on the folder currently selected.")
            return
        }
        removeZipCommentsCount = viewModel.planRemoveZipCommentsPreviewCount(scopeFolders: [selectedRomFolder])
        guard removeZipCommentsCount > 0 else {
            viewModel.logWarning("Nothing to remove — no matched archive inside \"\(selectedRomFolder.lastPathComponent)\" in the current scan has a comment.")
            return
        }
        showRemoveZipCommentsConfirmation = true
    }

    private func commitRemoveZipComments() {
        let scopeFolders = selectedRomFolder.map { [$0] } ?? []
        Task {
            await viewModel.removeZipComments(system: system, scopeFolders: scopeFolders)
            // Real root cause found live (2026-09-30, jensyleo: "lo de
            // remover zip comments... no lo vi actualizado en la
            // pantalla"): `.onChange(of: viewModel.auditReport)` is the
            // ONLY other place this cache gets invalidated, but a zip
            // comment lives entirely OUTSIDE `AuditEntry`/`AuditReport` —
            // removing one changes nothing `Equatable` compares, so the
            // recomputed report is value-equal to the old one and
            // `onChange` never fires at all. Invalidating directly here,
            // rather than trusting that side effect, is what actually
            // clears the stale entry — the token bump below only forces
            // `Table` to redraw, which was previously redrawing from the
            // very same poisoned cache.
            zipCommentCache.invalidate(underAnyOf: scopeFolders.isEmpty ? system.romFolderURLs : scopeFolders)
            zipCommentTableReloadToken += 1
        }
    }

    private func startContextMenuRemoveZipComments(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        contextMenuRemoveZipCommentsCount = viewModel.planRemoveZipCommentsPreviewCount(scopeFolders: fileURLs)
        guard contextMenuRemoveZipCommentsCount > 0 else {
            viewModel.logWarning("Nothing to remove\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — no matched archive here has a comment.")
            return
        }
        contextMenuRemoveZipCommentsURLs = fileURLs
        showContextMenuRemoveZipCommentsConfirmation = true
    }

    private func commitContextMenuRemoveZipComments() {
        guard !contextMenuRemoveZipCommentsURLs.isEmpty else { return }
        Task {
            await viewModel.removeZipComments(system: system, scopeFolders: contextMenuRemoveZipCommentsURLs)
            // Same real root cause as `commitRemoveZipComments` above —
            // `onChange(of: viewModel.auditReport)` never fires for a
            // comment-only change, so invalidate directly rather than
            // relying on that side effect.
            zipCommentCache.invalidate(underAnyOf: contextMenuRemoveZipCommentsURLs)
            zipCommentTableReloadToken += 1
        }
    }

    /// Preview itself needs a real (bounded) disk read — see
    /// `LibraryViewModel.planCollectSamplesPreviewCount`'s own doc
    /// comment — so this dispatches through a `Task`, unlike every other
    /// `start*` function above.
    private func startCollectSamples() {
        Task {
            let count = await viewModel.planCollectSamplesPreviewCount(system: system)
            collectSamplesCount = count
            guard count > 0 else {
                viewModel.logWarning("Nothing to collect — no matching sample zip found in this system's own ROM folders.")
                return
            }
            showCollectSamplesConfirmation = true
        }
    }

    private func commitCollectSamples() {
        Task { await viewModel.collectSamples(system: system) }
    }

    /// Previews the count before showing the confirmation dialog — same
    /// dry-run-before-write caution as every other Fase 2 action.
    private func startMakeSelfContained() {
        makeSelfContainedCount = viewModel.planMakeSelfContainedPreviewCount()
        guard makeSelfContainedCount > 0 else {
            viewModel.logWarning("Nothing to copy — every game in this scan is already self-contained.")
            return
        }
        showMakeSelfContainedConfirmation = true
    }

    private func commitMakeSelfContained() {
        Task { await viewModel.makeSelfContained(system: system) }
    }

    /// Previews the rename count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    private func startRenameRomsInArchive() {
        renameRomsInArchiveCount = viewModel.planRenameRomsInArchivePreviewCount(scopeFolders: selectedRomFolder.map { [$0] } ?? [])
        guard renameRomsInArchiveCount > 0 else {
            viewModel.logWarning("Nothing to fix — every rom entry already matches the DAT, styled exactly per \"Roms case\" in Settings → Fix.")
            return
        }
        // jensyleo's own request (2026-09-10): the confirmation exists to
        // warn about a real risk — a re-styled name no longer matching the
        // DAT's own case, which some case-sensitive tools/emulators can't
        // find. With "Roms case" at Datafile Case (or Don't Touch, which
        // behaves identically here — see `currentRomsCasePolicyRisksCaseMismatch`'s
        // own doc comment) that risk doesn't exist, so asking first is
        // just friction with nothing to actually confirm — run directly.
        guard currentRomsCasePolicyRisksCaseMismatch() else {
            commitRenameRomsInArchive()
            return
        }
        showRenameRomsInArchiveConfirmation = true
    }

    private func commitRenameRomsInArchive() {
        Task { await viewModel.renameRomsInArchive(system: system, scopeFolders: selectedRomFolder.map { [$0] } ?? []) }
    }

    /// Toolbar → "Fix Mismatched Files" (folder-scoped) — jensyleo's own
    /// follow-up request (2026-09-10): same preview-then-confirm-only-
    /// when-risky treatment as `startRenameRomsInArchive()` above. Skips
    /// the dialog entirely (runs directly) whenever "Sets case" can't
    /// actually produce a DAT-case mismatch.
    private func startFixMismatchedFiles() {
        fixMismatchedFilesCount = viewModel.planFixPreviewCount(scopeFolders: selectedRomFolder.map { [$0] } ?? [])
        guard fixMismatchedFilesCount > 0 else {
            viewModel.logWarning("Nothing to fix\(selectedRomFolder.map { " inside \"\($0.lastPathComponent)\"" } ?? "") — every File name already matches the DAT, styled exactly per \"Sets case\" in Settings → Fix.")
            return
        }
        guard currentSetsCasePolicyRisksCaseMismatch() else {
            commitFixMismatchedFiles()
            return
        }
        showFixMismatchedFilesConfirmation = true
    }

    private func commitFixMismatchedFiles() {
        Task { await viewModel.fix(system: system, scopeFolders: selectedRomFolder.map { [$0] } ?? []) }
    }

    /// Games table context menu → "Fix Mismatched Files" (this File, or
    /// every File currently selected) — same preview-then-confirm-only-
    /// when-risky shape as `startFixMismatchedFiles()` above, scoped to
    /// `fileURLs` instead of `selectedRomFolder`, using its own dedicated
    /// state (`contextMenuFixMismatchedFilesCount`/
    /// `showContextMenuFixMismatchedFilesConfirmation`/
    /// `contextMenuFixMismatchedFileURLs`) for the same
    /// can't-clobber-each-other reason `startContextMenuRenameRomsInArchive`
    /// has its own. jensyleo's own request (2026-09-10): "la app no
    /// permite selección múltiple" — `fileURLs` becomes `fix(scopeFolders:)`'s
    /// scope, one entry per selected File; `urlIsInScope` already treats
    /// each as an exact-path match rather than a prefix, so several just
    /// means "in scope if it's under ANY of these."
    private func fixMismatchedFile(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        contextMenuFixMismatchedFilesCount = viewModel.planFixPreviewCount(scopeFolders: fileURLs)
        guard contextMenuFixMismatchedFilesCount > 0 else {
            viewModel.logWarning("Nothing to fix\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — every File name already matches the DAT, styled exactly per \"Sets case\" in Settings → Fix.")
            return
        }
        contextMenuFixMismatchedFileURLs = fileURLs
        guard currentSetsCasePolicyRisksCaseMismatch() else {
            commitContextMenuFixMismatchedFile()
            return
        }
        showContextMenuFixMismatchedFilesConfirmation = true
    }

    private func commitContextMenuFixMismatchedFile() {
        guard !contextMenuFixMismatchedFileURLs.isEmpty else { return }
        Task { await viewModel.fix(system: system, scopeFolders: contextMenuFixMismatchedFileURLs) }
    }

    /// Games table context menu → "Fix Misnamed ROMs Inside Their
    /// Archives…" (this File, or every File currently selected) — same
    /// preview-then-confirm shape as the toolbar's own
    /// `startRenameRomsInArchive()`, scoped to `fileURLs` instead of
    /// `selectedRomFolder`. Uses its own dedicated state
    /// (`contextMenuRenameRomsInArchiveCount`/
    /// `showContextMenuRenameRomsInArchiveConfirmation`/
    /// `contextMenuFixFileURLs`) so right-clicking while the toolbar's own
    /// folder-scoped confirmation might independently be pending can't
    /// cross-contaminate either one's outcome.
    private func startContextMenuRenameRomsInArchive(_ fileURLs: [URL], entryKeys: Set<String> = []) {
        guard !fileURLs.isEmpty else { return }
        contextMenuRenameRomsInArchiveCount = viewModel.planRenameRomsInArchivePreviewCount(scopeFolders: fileURLs, entryKeys: entryKeys)
        guard contextMenuRenameRomsInArchiveCount > 0 else {
            viewModel.logWarning("Nothing to fix\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — every rom entry already matches the DAT, styled exactly per \"Roms case\" in Settings → Fix.")
            return
        }
        contextMenuFixFileURLs = fileURLs
        contextMenuRenameRomsInArchiveEntryKeys = entryKeys
        // Same reasoning as `startRenameRomsInArchive()`'s own comment
        // above: nothing to actually confirm when there's no real
        // case-mismatch risk, so skip the dialog and just run it.
        guard currentRomsCasePolicyRisksCaseMismatch() else {
            commitContextMenuRenameRomsInArchive()
            return
        }
        showContextMenuRenameRomsInArchiveConfirmation = true
    }

    private func commitContextMenuRenameRomsInArchive() {
        guard !contextMenuFixFileURLs.isEmpty else { return }
        Task {
            await viewModel.renameRomsInArchive(
                system: system, scopeFolders: contextMenuFixFileURLs, entryKeys: contextMenuRenameRomsInArchiveEntryKeys
            )
        }
    }

    /// Games table context menu → "Remove Useless Files" (this File, or
    /// every File currently selected) — jensyleo's own report (2026-09-13):
    /// a row reading "Extra file in archive" had no way to act on it at
    /// all, since the toolbar's own "Remove Useless Files…" only ever
    /// scopes to the selected ROM FOLDER. Same preview-then-confirm shape
    /// as `fixMismatchedFile` above, always confirmed (never skipped) —
    /// this one is genuinely destructive every time.
    private func startContextMenuRemoveUselessFiles(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        contextMenuRemoveUselessFilesCount = viewModel.planRemoveUselessFilesPreviewCount(scopeFolders: fileURLs)
        guard contextMenuRemoveUselessFilesCount > 0 else {
            viewModel.logWarning("Nothing to remove\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — no unrecognized files here.")
            return
        }
        contextMenuRemoveUselessFilesURLs = fileURLs
        showContextMenuRemoveUselessFilesConfirmation = true
    }

    private func commitContextMenuRemoveUselessFiles() {
        guard !contextMenuRemoveUselessFilesURLs.isEmpty else { return }
        Task { await viewModel.removeUselessFiles(system: system, scopeFolders: contextMenuRemoveUselessFilesURLs) }
    }

    /// The context-menu-scoped counterpart to the toolbar's own
    /// folder-scoped "Remove Redundant Files…"/"Remove Redundant ROMs…" —
    /// jensyleo's own request (2026-09-14), same reasoning
    /// `startContextMenuRemoveUselessFiles` above already documents: a row
    /// reading "Duplicated file, not needed here" had no matching
    /// right-click action.
    private func startContextMenuRemoveRedundantFiles(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        contextMenuRemoveRedundantFilesCount = viewModel.planRemoveRedundantFilesPreviewCount(scopeFolders: fileURLs)
        guard contextMenuRemoveRedundantFilesCount > 0 else {
            viewModel.logWarning("Nothing to remove\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — no redundant files here.")
            return
        }
        contextMenuRemoveRedundantFilesURLs = fileURLs
        showContextMenuRemoveRedundantFilesConfirmation = true
    }

    private func commitContextMenuRemoveRedundantFiles() {
        guard !contextMenuRemoveRedundantFilesURLs.isEmpty else { return }
        Task { await viewModel.removeRedundantFiles(system: system, scopeFolders: contextMenuRemoveRedundantFilesURLs) }
    }

    private func startContextMenuRemoveRedundantRoms(_ fileURLs: [URL]) {
        guard !fileURLs.isEmpty else { return }
        contextMenuRemoveRedundantRomsCount = viewModel.planRemoveRedundantRomsPreviewCount(scopeFolders: fileURLs)
        guard contextMenuRemoveRedundantRomsCount > 0 else {
            viewModel.logWarning("Nothing to remove\(LibraryViewModel.scopeSuffixForLog(fileURLs)) — no redundant roms here.")
            return
        }
        contextMenuRemoveRedundantRomsURLs = fileURLs
        showContextMenuRemoveRedundantRomsConfirmation = true
    }

    private func commitContextMenuRemoveRedundantRoms() {
        guard !contextMenuRemoveRedundantRomsURLs.isEmpty else { return }
        Task { await viewModel.removeRedundantRoms(system: system, scopeFolders: contextMenuRemoveRedundantRomsURLs) }
    }

    /// Previews the strip count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    private func startConvertToSplit() {
        convertToSplitCount = viewModel.planConvertToSplitPreviewCount()
        guard convertToSplitCount > 0 else {
            viewModel.logWarning("Nothing to strip — no clone in this scan has a rom already, exactly, in its parent's own archive.")
            return
        }
        showConvertToSplitConfirmation = true
    }

    private func commitConvertToSplit() {
        Task { await viewModel.convertToSplit(system: system) }
    }

    /// Previews the repair count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    /// Unlike every other "start" function here, the preview itself scans
    /// the Maintenance folder, so it has to run inside a `Task` rather
    /// than synchronously.
    /// `skipConfirmation` — jensyleo's own request (2026-09-14): the
    /// context-menu action already scopes to one specific, deliberately
    /// right-clicked File (unlike the toolbar's own unscoped, whole-system
    /// "Fix" dropdown entry, which keeps the confirmation dialog) and only
    /// ever shows up in the menu at all once `hasMaintenanceDonor` already
    /// confirmed a real donor is staged — the extra confirmation dialog on
    /// top of that was redundant friction, not real safety.
    private func startRepairFromMaintenanceFolder(scopeFolders: [URL] = [], skipConfirmation: Bool = false) {
        repairFromMaintenanceFolderScope = scopeFolders
        Task {
            repairFromMaintenanceFolderCount = await viewModel.planRepairFromMaintenanceFolderPreviewCount(system: system, scopeFolders: scopeFolders)
            // Real bug found live by jensyleo (2026-09-22): the preview
            // count above now correctly returns 0 (and pops its own
            // "Rescan required" alert) when the last Scan didn't cover
            // this scope — but without this check, the code right below
            // ALSO fired its own, contradicting "Nothing to repair —
            // every rom already matches" success alert on top of it,
            // even though nothing was actually checked yet.
            guard viewModel.rescanRequiredAlertMessage == nil else { return }
            guard repairFromMaintenanceFolderCount > 0 else {
                // jensyleo's own report (2026-09-14): clicking this with
                // nothing actually actionable (e.g. only a `.badDump` rom
                // living inside a `.zip` — informational-only for now, see
                // `RebuildPlanner.romsReplaceableFromMaintenanceFolder`'s
                // own doc comment) used to silently do nothing at all,
                // with no explanation. The context menu's own version now
                // hides itself for exactly this case (see
                // `GameTreeTableView`'s own `hasMaintenanceDonor` gate),
                // but the toolbar's unscoped entry has no such cheap
                // pre-check, so it still needs this explicit log line.
                viewModel.logWarning("Nothing to repair from the Maintenance folder\(LibraryViewModel.scopeSuffixForLog(scopeFolders)).")
                // jensyleo's own report (2026-09-22): the donor-scan
                // overlay gave no visible sign of when it finished, and
                // this "nothing found" outcome previously lived ONLY in
                // the Log panel — easy to miss after watching a long,
                // wordless "Scanning folders…" overlay. Mirrors the same
                // `FixResultAlert` popup every real repair/replace action
                // already shows on completion, so this outcome is just as
                // visible as a genuine success or failure.
                if FixResultPopupSettings.isEnabled {
                    viewModel.fixResultAlert = LibraryViewModel.FixResultAlert(
                        title: "Find ROMs",
                        isSuccess: true,
                        message: "Nothing to repair\(LibraryViewModel.scopeSuffixForLog(scopeFolders)) — every rom already matches, or there's no known-good donor in the Maintenance folder for what's missing."
                    )
                }
                return
            }
            if skipConfirmation {
                commitRepairFromMaintenanceFolder()
            } else {
                showRepairFromMaintenanceFolderConfirmation = true
            }
        }
    }

    private func commitRepairFromMaintenanceFolder() {
        let scopeFolders = repairFromMaintenanceFolderScope
        Task { await viewModel.repairFromMaintenanceFolder(system: system, scopeFolders: scopeFolders) }
    }

    /// Scoped to the selected ROM folder only, same as "Remove Useless
    /// Files…" — see `startRemoveUselessFiles`'s own comment for why.
    private func startRemoveRedundantFiles() {
        guard let selectedRomFolder else {
            viewModel.logWarning("Select a ROM folder first — \"Remove Redundant Files…\" only ever acts on the folder currently selected.")
            return
        }
        removeRedundantFilesCount = viewModel.planRemoveRedundantFilesPreviewCount(scopeFolders: [selectedRomFolder])
        guard removeRedundantFilesCount > 0 else {
            viewModel.logWarning("Nothing to remove — no redundant files inside \"\(selectedRomFolder.lastPathComponent)\" in the current scan.")
            return
        }
        showRemoveRedundantFilesConfirmation = true
    }

    private func commitRemoveRedundantFiles() {
        let scopeFolders = selectedRomFolder.map { [$0] } ?? []
        Task { await viewModel.removeRedundantFiles(system: system, scopeFolders: scopeFolders) }
    }

    /// Drives the toolbar action's own dynamic `isEnabled` — see that
    /// ToolbarAction's own doc comment. Real bug hit live (2026-09-24,
    /// jensyleo's own report: the "Scan Required" alert appeared and
    /// wouldn't go away, reappearing the instant "OK" dismissed it) —
    /// `planOrganizeBIOSFilesPreviewCount()` goes through
    /// `requireMatchReport()`, whose job is to trigger that alert as a
    /// SIDE EFFECT whenever there's no scan yet; since `isEnabled` here
    /// gets recomputed on every render (including the very re-render the
    /// alert's own dismissal causes), calling it directly turned one
    /// missing scan into an infinite loop. `hasMatchReport` is the
    /// existing side-effect-free peek built for exactly this situation
    /// (see its own doc comment — the 2026-09-10 report of the same alert
    /// firing from a plain right-click) — checked FIRST, short-circuiting
    /// before ever calling the real preview function.
    private var organizeBIOSFilesAvailable: Bool { organizeBIOSFilesAvailableCache }

    /// Whole-system only — see the toolbar action's own doc comment for why
    /// "Organize BIOS Files…" never scopes to just the selected folder.
    /// Passed as `onComplete` to `viewModel.startScan(...)` for the BIOS/
    /// Complementary Chips/Samples folder specifically — jensyleo's own
    /// request (2026-09-24): "si no encuentra nada avise desde la app, no
    /// solo desde el log." A plain, on-disk emptiness check (not an audit
    /// lookup) so it works uniformly for all three, even Samples, whose
    /// content is never part of the audit at all (see `SamplesFolderSettings
    /// .isUnderSamplesFolder`'s own doc comment).
    private func warnIfSpecialFolderEmpty(_ folder: URL, kind: String) {
        let isEmpty = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?.isEmpty ?? true
        guard isEmpty else { return }
        viewModel.logScanFoundNothing("The \(kind) folder (\"\(folder.lastPathComponent)\") is empty — nothing was found there.")
    }

    private func startOrganizeBIOSFiles() {
        // Real gap found live by jensyleo (2026-09-24), right after
        // `logConfigurationRequired` was added: "no sale el mensaje" — that
        // fix landed on `LibraryViewModel.organizeBIOSFiles`'s OWN guards,
        // but a toolbar click never actually reaches those on this exact
        // path. `startOrganizeBIOSFiles` here runs FIRST (from the toolbar
        // action directly) and, when no BIOS folder is configured,
        // `planOrganizeBIOSFilesPreviewCount()` just returns `0` like any
        // other "nothing to do" case — so this fell into the generic,
        // log-only "Nothing to organize" branch below instead, which never
        // reaches the async function's own guard at all. Checked FIRST,
        // and routed through the same visible alert, so "not configured"
        // reads differently from "configured, but genuinely nothing
        // found".
        guard BIOSFolderSettings.folderURL != nil else {
            viewModel.logConfigurationRequired("No BIOS folder configured — set one in Settings → Systems → MAME first.")
            return
        }
        organizeBIOSFilesCount = viewModel.planOrganizeBIOSFilesPreviewCount()
        guard organizeBIOSFilesCount > 0 else {
            viewModel.logWarning("Nothing to organize — no BIOS files found outside the configured BIOS folder in the current scan.")
            return
        }
        organizeBIOSFilesLines = viewModel.planOrganizeBIOSFilesPreviewLines()
        showOrganizeBIOSFilesConfirmation = true
    }

    private func commitOrganizeBIOSFiles() {
        Task { await viewModel.organizeBIOSFiles(system: system) }
    }

    private var organizeComplementaryChipsAvailable: Bool { organizeComplementaryChipsAvailableCache }

    /// Whole-system only — same reasoning as `startOrganizeBIOSFiles`.
    private func startOrganizeComplementaryChips() {
        // Same real gap as `startOrganizeBIOSFiles`'s own doc comment.
        guard ComplementaryChipsFolderSettings.folderURL != nil else {
            viewModel.logConfigurationRequired("No Complementary Chips folder configured — set one in Settings → Systems → MAME first.")
            return
        }
        organizeComplementaryChipsCount = viewModel.planOrganizeComplementaryChipsPreviewCount()
        guard organizeComplementaryChipsCount > 0 else {
            viewModel.logWarning("Nothing to organize — no complementary chip files found outside the configured Complementary Chips folder in the current scan.")
            return
        }
        organizeComplementaryChipsLines = viewModel.planOrganizeComplementaryChipsPreviewLines()
        showOrganizeComplementaryChipsConfirmation = true
    }

    private func commitOrganizeComplementaryChips() {
        Task { await viewModel.organizeComplementaryChips(system: system) }
    }

    /// Scoped to the selected ROM folder only, same as "Remove Useless
    /// Files…"/"Remove Redundant Files…" above.
    private func startRemoveRedundantRoms() {
        guard let selectedRomFolder else {
            viewModel.logWarning("Select a ROM folder first — \"Remove Redundant ROMs…\" only ever acts on the folder currently selected.")
            return
        }
        removeRedundantRomsCount = viewModel.planRemoveRedundantRomsPreviewCount(scopeFolders: [selectedRomFolder])
        guard removeRedundantRomsCount > 0 else {
            viewModel.logWarning("Nothing to remove — no redundant roms inside \"\(selectedRomFolder.lastPathComponent)\" in the current scan.")
            return
        }
        showRemoveRedundantRomsConfirmation = true
    }

    private func commitRemoveRedundantRoms() {
        let scopeFolders = selectedRomFolder.map { [$0] } ?? []
        Task { await viewModel.removeRedundantRoms(system: system, scopeFolders: scopeFolders) }
    }

    /// Every real ROM Actions target for the Roms panel's own selection —
    /// same Maintenance-folder rejection every other write action here
    /// already applies (`rejectIfUnderMaintenanceFolder`, checked against
    /// each target's own container/file URL, never the entry name).
    private func startExtractRomEntries(_ entries: [LibraryViewModel.RomEntryTarget]) {
        guard !entries.isEmpty, rejectIfUnderMaintenanceFolder(entries.map(\.url)) else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a destination folder to extract \(entries.count) rom(s) to"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        pendingRomEntryTargets = entries
        pendingRomEntryDestination = destination
        showExtractRomEntriesConfirmation = true
    }

    private func commitExtractRomEntries() {
        let entries = pendingRomEntryTargets
        guard let destination = pendingRomEntryDestination else { return }
        pendingRomEntryTargets = []
        pendingRomEntryDestination = nil
        Task { await viewModel.extractRomEntries(system: system, entries, to: destination) }
    }

    private func startMoveRomEntriesToTrash(_ entries: [LibraryViewModel.RomEntryTarget]) {
        guard !entries.isEmpty, rejectIfUnderMaintenanceFolder(entries.map(\.url)) else { return }
        pendingRomEntryTargets = entries
        showMoveRomEntriesToTrashConfirmation = true
    }

    private func commitMoveRomEntriesToTrash() {
        let entries = pendingRomEntryTargets
        pendingRomEntryTargets = []
        Task { await viewModel.moveRomEntriesToTrash(system: system, entries) }
    }

    private func startDeleteRomEntriesPermanently(_ entries: [LibraryViewModel.RomEntryTarget]) {
        guard !entries.isEmpty, rejectIfUnderMaintenanceFolder(entries.map(\.url)) else { return }
        pendingRomEntryTargets = entries
        showDeleteRomEntriesPermanentlyConfirmation = true
    }

    private func commitDeleteRomEntriesPermanently() {
        let entries = pendingRomEntryTargets
        pendingRomEntryTargets = []
        Task { await viewModel.deleteRomEntriesPermanently(system: system, entries) }
    }

    /// Previews the count before showing the confirmation dialog — same
    /// dry-run-before-write caution as every other Fase 2 action.
    private func startHandleCorruptedFiles() {
        handleCorruptedFilesCount = viewModel.planCorruptedFilesPolicyPreviewCount()
        guard handleCorruptedFilesCount > 0 else {
            viewModel.logWarning("Nothing to handle — no internally-corrupt rom found, or the configured policy has nothing to do.")
            return
        }
        showHandleCorruptedFilesConfirmation = true
    }

    private func commitHandleCorruptedFiles() {
        Task { await viewModel.applyCorruptedFilesPolicy(system: system) }
    }

    /// Previews the merge count before showing the confirmation dialog —
    /// same dry-run-before-write caution as every other Fase 2 action.
    private func startConvertToMerged() {
        convertToMergedCount = viewModel.planConvertToMergedPreviewCount()
        guard convertToMergedCount > 0 else {
            viewModel.logWarning("Nothing to merge — no clone in this scan qualifies (see the toolbar action's own help text for what disqualifies one).")
            return
        }
        showConvertToMergedConfirmation = true
    }

    private func commitConvertToMerged() {
        Task { await viewModel.convertToMerged(system: system) }
    }

    /// Strips a trailing parenthetical off a DAT's own declared version
    /// string for display — jensyleo's own report (2026-09-10), screenshot
    /// of "DAT: MAME 0.289 (unknown)": MAME's own `-listxml` `build`
    /// attribute genuinely can contain a parenthetical git/revision suffix
    /// that isn't always meaningful (a dev build with no revision info at
    /// all literally emits "(unknown)") — this only trims it for the
    /// header's own display, never touches the stored `DATHeader.version`
    /// value itself (still the DAT's own exact declared string everywhere
    /// else, e.g. `AuditReportDatabase`'s persisted scan meta).
    private static func displayVersion(_ version: String) -> String {
        guard let parenIndex = version.firstIndex(of: "(") else { return version }
        return version[..<parenIndex].trimmingCharacters(in: .whitespaces)
    }

    private var header: some View {
        // While a new DAT is loading, the *previous* one's name/version
        // would otherwise sit here unchanged (`datHeader` only updates
        // once loading actually finishes) — reading as if it were still
        // current, when the whole games/database view below it is about
        // to change out from under it. A real, reported source of
        // confusion switching between two DATs for the same system.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(
                viewModel.isLoadingDAT
                    ? "DAT: Loading…"
                    : "DAT: \(viewModel.datHeader.map { "\($0.name) \(Self.displayVersion($0.version))" } ?? system.name)"
            )
            .font(.headline)
            lastScanDateLabel
        }
    }

    /// jensyleo's own request (2026-09-14), after twice mistaking a `.badDump`/
    /// `.missing` row loaded straight from `AuditReportDatabase` (via
    /// `loadPersistedReport`, on simply opening an already-scanned system —
    /// by design, so results show instantly) for a live, current problem,
    /// when it was really an old scan's own snapshot the real file had long
    /// since stopped matching: this label surfaces `viewModel.lastScanDate`
    /// so a suspiciously-old timestamp is the FIRST thing that explains a
    /// row that looks wrong — "rescan before trusting this" — rather than
    /// silently letting stale data read as current.
    @ViewBuilder
    private var lastScanDateLabel: some View {
        if let lastScanDate = viewModel.lastScanDate {
            Text("Last scanned \(lastScanDate.formatted(.relative(presentation: .named)))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .help("This system's results as shown were last confirmed by a real scan at \(lastScanDate.formatted(date: .abbreviated, time: .shortened)). If anything looks wrong, rescan first — a persisted report opens instantly but can't know about changes made since.")
        }
    }

    // MARK: - Scan progress

    /// The three NUMERIC scan phases `scanProgressOverlay` can show a
    /// determinate bar for, once the folder walk itself (no known total,
    /// `folderScanFilesFound`, kept as its own indeterminate section) has
    /// finished. `.matchingIndeterminate` covers the brief window after
    /// matching starts but before its first progress callback has fired —
    /// still past both earlier phases, so still worth its own fixed floor
    /// on the combined bar rather than reading as 0%.
    private enum ScanOverallPhase {
        case fixOperations(completed: Int, total: Int)
        case datLoad(parsed: Int, total: Int)
        case datLoadIndeterminate
        case folderWalkIndeterminate
        case listingArchives(read: Int, total: Int)
        case hashing(completed: Int, total: Int)
        case matching(completed: Int, total: Int)
        case matchingIndeterminate
        case postMatchStep(completed: Int, total: Int)
        case saving(completed: Int, total: Int)
        case finalPreload(completed: Int, total: Int)
    }

    /// One shared, monotonically increasing fraction across the three
    /// numeric scan phases above — jensyleo's own report (2026-09-17):
    /// scanning "KONAMI" showed the progress bar "avanza y retrocede".
    /// Root cause: each phase used to drive its OWN independent bar
    /// (`ProgressView(value: phase.completed, total: phase.total)`), so
    /// the bar visibly jumped back down to a low value every time one
    /// phase finished near 100% and the next started fresh from 0% on a
    /// completely different scale (e.g. archives read vs. files hashed vs.
    /// games matched). Weights below are fixed, rough estimates of each
    /// phase's typical relative share of total scan time (matching this
    /// file's own earlier note that a cold hash pass can dwarf matching by
    /// ~35× for a large collection, while archive listing is normally the
    /// cheapest of the three) — not measured per-scan, so the exact
    /// midpoints will be approximate, but the bar is guaranteed to never
    /// move backward, which is the actual bug being fixed here.
    /// Extended 2026-09-23, jensyleo's own report: running a "Fix" action
    /// (its own operation loop, `fixActionProgress`) then rolling straight
    /// into its automatic verification rescan and save (`isSavingReport`)
    /// used to hand off between what were really TWO SEPARATE, unrelated
    /// bars — `fixActionProgress`'s own 0–100% and this function's own
    /// 0–100% for the scan pipeline — so the combined bar visibly jumped
    /// back down to a low value the moment the Fix operations finished and
    /// the rescan's own archive-listing/hashing/matching phases started
    /// fresh, the exact "avanza y retrocede" class of bug this function
    /// already exists to prevent for the three original scan phases below.
    /// "Solución definitiva" (his own words): every phase this app can ever
    /// show DURING one busy/`isBusy` stretch — fixing, listing, hashing,
    /// matching, saving — now shares this SAME one monotonically
    /// increasing fraction, not just the three that already did.
    ///
    /// Extended again 2026-10-01, jensyleo's own report after a real NES
    /// scan: several real phases still ran with the bar completely frozen
    /// (just the label changing) — DAT loading, the folder walk, and every
    /// post-match annotation pass (report generation, CHD audit, duplicate
    /// sets, orphaned BIOS, filename/CRC mismatches, Maintenance donors).
    /// Worse, the zip-comment background preload
    /// (`refreshCachedGameDataAfterAuditReportChangeAsync`'s own tail) kept
    /// reading from disk/NAS well AFTER this bar already reached 100% and
    /// the overlay disappeared — `isPreloadingZipComments` (see that
    /// function's own doc comment) now keeps the overlay up through that
    /// tail too, with its own weighted slice here, so "the bar says done"
    /// and "the scan is actually done" are the same moment again. Every
    /// phase below is now part of the same one monotonic fraction, even
    /// the ones with no real per-item total to report (DAT loading before
    /// its own byte-count pass, the folder walk) — those just hold at
    /// their slice's starting point, exactly like `.matchingIndeterminate`
    /// already did, rather than running on a disconnected 0–100% scale of
    /// their own.
    private func overallScanFraction(_ phase: ScanOverallPhase) -> Double {
        let fixOperationsWeight = 0.10
        let datLoadWeight = 0.05
        let folderWalkWeight = 0.05
        let archiveListingWeight = 0.10
        let hashingWeight = 0.30
        let matchingWeight = 0.20
        let postMatchWeight = 0.05
        let savingWeight = 0.10
        let finalPreloadWeight = 0.05
        let afterFixOps = fixOperationsWeight
        let afterDatLoad = afterFixOps + datLoadWeight
        let afterFolderWalk = afterDatLoad + folderWalkWeight
        let afterListing = afterFolderWalk + archiveListingWeight
        let afterHashing = afterListing + hashingWeight
        let afterMatching = afterHashing + matchingWeight
        let afterPostMatch = afterMatching + postMatchWeight
        let afterSaving = afterPostMatch + savingWeight
        switch phase {
        case .fixOperations(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return fixOperationsWeight * local
        case .datLoad(let parsed, let total):
            let local = total > 0 ? Double(parsed) / Double(total) : 0
            return afterFixOps + datLoadWeight * local
        case .datLoadIndeterminate:
            return afterFixOps
        case .folderWalkIndeterminate:
            return afterDatLoad
        case .listingArchives(let read, let total):
            let local = total > 0 ? Double(read) / Double(total) : 0
            return afterFolderWalk + archiveListingWeight * local
        case .hashing(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return afterListing + hashingWeight * local
        case .matching(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return afterHashing + matchingWeight * local
        case .matchingIndeterminate:
            return afterHashing
        case .postMatchStep(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return afterMatching + postMatchWeight * local
        case .saving(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return afterPostMatch + savingWeight * local
        case .finalPreload(let completed, let total):
            let local = total > 0 ? Double(completed) / Double(total) : 0
            return afterSaving + finalPreloadWeight * local
        }
    }

    private var scanProgressOverlay: some View {
        VStack(spacing: 8) {
            if isPreloadingZipComments {
                // Checked first — see `isPreloadingZipComments`'s own doc
                // comment. This phase genuinely runs AFTER `viewModel
                // .isBusy` has already gone false (the scan itself is done),
                // so it's the only phase ever shown while every other
                // `viewModel.*` busy flag below is already false.
                // No real per-item total is worth plumbing through for this
                // one — it's a single bulk read, not a throttleable loop —
                // so this just holds at the slice's own starting point,
                // same pattern as `.matchingIndeterminate`/`.folderWalkIndeterminate`.
                ProgressView(value: overallScanFraction(.finalPreload(completed: 0, total: 1)))
                    .frame(width: 240)
                Text("Reading ZIP comments…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let fixAction = viewModel.fixActionProgress {
                // jensyleo's own report (2026-09-19): running "Remove
                // Redundant Files…" only ever showed this overlay's generic
                // scan phases ("Scanning folders…", "Saving results…") —
                // both real (its own automatic verification rescan), but
                // nothing named the actual file removal itself while it was
                // happening. Checked first, ahead of every other phase
                // below, for the same reason `isSavingReport` is: whichever
                // Fix/File Action's own real operations are running takes
                // priority over the generic scan pipeline phases that
                // follow it.
                if fixAction.total > 0 {
                    ProgressView(value: overallScanFraction(.fixOperations(completed: fixAction.completed, total: fixAction.total)))
                        .frame(width: 240)
                    Text("\(fixAction.label) \(fixAction.completed) of \(fixAction.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(width: 240)
                    Text(fixAction.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isSavingReport {
                // jensyleo's own report (2026-09-17): after the matching
                // bar reached 100%, the app kept the busy overlay up for a
                // real, separately-timed stretch while `saveReport` wrote
                // the whole report to disk — with no indication that was
                // even what was happening (see `isSavingReport`'s own doc
                // comment for the full story, including why it used to
                // block the main actor entirely rather than just showing
                // the wrong text). Checked first, ahead of every other
                // phase below, since saving always happens last.
                // jensyleo's own report (2026-09-19): this showed a bare,
                // generic spinner with no numbers, unlike every other phase
                // in this same overlay — `AuditReportDatabase.saveReport`
                // now reports real (rows written, total rows to write)
                // progress via `saveReportProgress`, so this is a real
                // determinate bar just like the rest, not a special case.
                if let save = viewModel.saveReportProgress, save.total > 0 {
                    ProgressView(value: overallScanFraction(.saving(completed: save.completed, total: save.total)))
                        .frame(width: 240)
                    Text("Saving results… \(save.completed) of \(save.total) rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: overallScanFraction(.matching(completed: 1, total: 1)))
                        .frame(width: 240)
                    Text("Saving results…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.isLoadingDAT {
                // A large MAME DAT is tens/hundreds of MB of XML — parsing
                // it can itself take a noticeable while in an unoptimized
                // build, before anything has touched a folder yet. Without
                // its own message this silently looked like "scanning
                // folders" for a phase that hadn't started scanning at all.
                if let dat = viewModel.datLoadProgress, dat.total > 0 {
                    ProgressView(value: overallScanFraction(.datLoad(parsed: dat.parsed, total: dat.total)))
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
                    ProgressView(value: overallScanFraction(.datLoad(parsed: Int(clamping: fileRead.read), total: Int(clamping: fileRead.total))))
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
                        ProgressView(value: overallScanFraction(.datLoad(parsed: counting.scanned, total: counting.total)))
                            .frame(width: 240)
                    } else {
                        ProgressView(value: overallScanFraction(.datLoadIndeterminate))
                            .frame(width: 240)
                    }
                    Text("Counting machines…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: overallScanFraction(.datLoadIndeterminate))
                        .frame(width: 240)
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
                //
                // `overallScanFraction(...)` below (not a bare
                // `match.completed`/`match.total` fraction) — jensyleo's
                // own report (2026-09-17): each of these three numeric
                // phases (archive listing, hashing, matching) used to
                // drive its OWN independent 0–100% bar, so the bar visibly
                // "avanza y retrocede" (jumps back down) every time one
                // phase finished near 100% and the next one started fresh
                // from 0% on a totally different scale. One shared,
                // monotonically increasing fraction across all three fixes
                // that, while each phase still shows its own accurate
                // item-count text below the bar.
                if let phase = viewModel.scanPostMatchPhase {
                    // jensyleo's own report (2026-09-19): matching itself
                    // finishing (this same bar at 100%) doesn't mean the
                    // scan is done — several more real, synchronous passes
                    // (disk auditing, duplicate-set detection, orphaned
                    // BIOS, filename/CRC checks, Maintenance donor
                    // detection) still run after it, and used to leave this
                    // text frozen at "N of N games" for however long they
                    // then took, looking indistinguishable from a hang.
                    // None of them are internally progress-reportable (each
                    // is one synchronous pass, not a throttleable per-item
                    // loop) — but jensyleo's own follow-up report
                    // (2026-10-01) was that the bar itself STILL looked
                    // frozen through this whole stretch (only the label
                    // moved), on a real NES collection where several of
                    // these passes genuinely run. `scanPostMatchStepProgress`
                    // (set alongside `phase`, see its own doc comment) at
                    // least advances the bar one fixed step per named pass
                    // — real, if coarse, motion instead of a dead hold.
                    if let step = viewModel.scanPostMatchStepProgress {
                        ProgressView(value: overallScanFraction(.postMatchStep(completed: step.completed, total: step.total)))
                            .frame(width: 240)
                    } else {
                        ProgressView(value: overallScanFraction(.matching(completed: 1, total: 1)))
                            .frame(width: 240)
                    }
                    Text(phase)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let match = viewModel.matchProgress, match.total > 0 {
                    ProgressView(value: overallScanFraction(.matching(completed: match.completed, total: match.total)))
                        .frame(width: 240)
                    Text("Comparing against the database… \(match.completed) of \(match.total) games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView(value: overallScanFraction(.matchingIndeterminate))
                        .frame(width: 240)
                    Text("Comparing against the database…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let progress = viewModel.scanProgress, progress.total > 0 {
                ProgressView(value: overallScanFraction(.hashing(completed: progress.completed, total: progress.total)))
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
                ProgressView(value: overallScanFraction(.listingArchives(read: archives.read, total: archives.total)))
                    .frame(width: 240)
                Text("Reading archive \(archives.read) of \(archives.total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let filesFound = viewModel.folderScanFilesFound {
                // No known total while walking the folder tree, so this
                // can never be a real determinate bar the way the other
                // three numeric phases above are — but jensyleo's own
                // report (2026-09-17), right after those three got a
                // shared linear bar, was that this phase's plain circular
                // spinner now stood out as "el ícono genérico de carga",
                // inconsistent with everything else in this same overlay.
                // `.linear`'s own indeterminate animation (a bar that
                // slides back and forth, never a fixed value) reads as
                // "actively working" exactly like the circular spinner
                // did, just in the same visual language as the rest of
                // this overlay instead of standing out as generic.
                //
                // Switched to a determinate, frozen `overallScanFraction`
                // value instead of a bare indeterminate animation —
                // jensyleo's own report (2026-10-01): this phase used to
                // run on a visually disconnected "animation" rather than
                // being part of the same unified 0–100% scale at all,
                // which is exactly the "part of the scan isn't part of the
                // overall bar" complaint this whole pass fixes. Holds at
                // `.folderWalkIndeterminate`'s fixed slice start, same
                // pattern as `.matchingIndeterminate`.
                ProgressView(value: overallScanFraction(.folderWalkIndeterminate))
                    .frame(width: 240)
                // jensyleo's own request (2026-08-12): "Scan All Folders"
                // (and "Scan Folder", which — see `LibraryViewModel.scan`'s
                // own doc comment — always walks every one of the system's
                // folders regardless of which single one was selected) used
                // to show only a running file count with no way to tell
                // *which* folder it was even counting. Named directly now,
                // via `currentlyScanningFolder`.
                Text(
                    viewModel.currentlyScanningFolder.map { "Scanning \($0.lastPathComponent)…" }
                        ?? "Scanning folders…"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                // The live file count made bigger/bolder than before
                // (2026-09-17) — previously folded into the same small
                // caption line as the folder name, easy to miss as the
                // only real sign of progress during this phase.
                Text("\(filesFound) files found")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(width: 240)
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
            HStack {
                Text("Log")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                // jensyleo's own report (2026-09-10): `.textSelection(.enabled)`
                // on each line (below) only ever lets you select WITHIN one
                // line at a time — SwiftUI doesn't merge separate `Text`
                // views in a `LazyVStack` into one continuous, drag-across
                // selection the way a real multi-line text view would. For
                // actually copying a log out to troubleshoot something (the
                // real need here), a single "copy everything" action is far
                // more useful than fighting that limitation.
                Button {
                    copyLogToClipboard()
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Copy the entire log to the clipboard")
                .disabled(viewModel.logLines.isEmpty)
                // jensyleo's own request (2026-09-11): a way to explicitly
                // start fresh without needing to run a whole new scan
                // (which already clears the log as a side effect).
                Button {
                    viewModel.clearLog()
                } label: {
                    Label("Clear Log", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .help("Clear the log")
                .disabled(viewModel.logLines.isEmpty)
            }
            // A real `NSTextView` (see `LogTextView`'s own doc comment),
            // not a `LazyVStack` of separate `Text` lines — this is what
            // actually lets you select (and ⌘C-copy) an arbitrary range
            // spanning any number of lines, not just within one at a time.
            LogTextView(lines: viewModel.logLines)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Joins every log line's own text with a newline and puts it on the
    /// pasteboard — the one reliable way to get the WHOLE log out for
    /// troubleshooting, since per-line `.textSelection(.enabled)` (above)
    /// can't select across multiple lines at once.
    private func copyLogToClipboard() {
        let fullText = viewModel.logLines.map(\.text).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullText, forType: .string)
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
        // jensyleo's own request (2026-08-12): a real, draggable divider
        // between "Database" and "ROM folder" — the plain `Divider()` row
        // (2026-08-11) only ever drew a static line; the two roots stayed
        // one single `List`/scroll region underneath it, so there was
        // nothing to actually *resize*. Splitting into two independent
        // `List`s inside an `AutosavingSplitView` (the same persisting
        // `NSSplitView` wrapper the app's other panes already use) gives
        // each its own scroll region and a genuinely draggable divider
        // between them, sized and remembered exactly like every other
        // split in this app.
        //
        // Each of the two halves has its own independent visibility toggle
        // now too (`showDatabaseTree`/`showRomFolderTree`, 2026-08-12,
        // splitting what used to be one combined "Database / ROM folder
        // sidebar" switch in View Options) — with only one on, there's
        // nothing left to actually split, so this shows that one pane
        // directly rather than an `AutosavingSplitView` with just one child
        // (which would otherwise still reserve room for a divider that has
        // nothing to divide).
        Group {
            if showDatabaseTree, showRomFolderTree {
                AutosavingSplitView(axis: .stacked, autosaveName: "ROMForge.databaseRomFolderSplit", panes: [
                    SplitPane(minLength: 80) { databaseSectionPane },
                    SplitPane(minLength: 60) { romFolderSectionPane },
                ], defaultFractions: [0.4713584288052373, 0.5270049099836334])
            } else if showDatabaseTree {
                databaseSectionPane
            } else if showRomFolderTree {
                romFolderSectionPane
            }
        }
    }

    /// The "Database" category tree half of `databaseList` — its own `List`
    /// (not shared with "ROM folder" anymore, see `databaseList`'s own doc
    /// comment) plus the search field above it.
    private var databaseSectionPane: some View {
        // No longer uses `List`'s own `selection:` binding — a category row
        // needs both a plain click (select it, exactly as before) *and* its
        // own independent expand/collapse disclosure, which doesn't fit a
        // single-value `List` selection tag. Manual `Button`s + `fontWeight`
        // highlighting instead, matching the same pattern "ROM folder" uses.
        VStack(spacing: 0) {
            databaseSearchField
            ScrollViewReader { proxy in
                databaseCategoryListContent
                    .onAppear { databaseListScrollProxy = proxy }
            }
            // Scoped to just the list, a sibling of `databaseSearchField`
            // above — NOT the shared ancestor `VStack` (where `.onKeyPress`
            // below still lives). Found live (2026-08-13): attaching
            // `.focusable()`/`.focused()` to the same `VStack` that also
            // contains the search `TextField` left `AXFocusedUIElement`
            // pointing at a bare, ambiguous `group` and silently broke
            // every arrow key in this pane — the `TextField`'s own native
            // focusability and this VStack-level one seem to fight over
            // which one SwiftUI/AppKit actually treats as "the" focused
            // responder. Scoping it to just this list (which has no such
            // competing sibling) is what `romFolderSectionPane` already
            // does, and that pane never had this problem.
            .focusable()
            .focused($isDatabasePaneFocused)
            // jensyleo's own report (2026-09-15), right after macOS
            // updated to 27.0: this container's own native focus ring
            // (needed only so `.onKeyPress` below actually receives arrow
            // keys — see `isDatabasePaneFocused`'s own doc comment) used to
            // render subtly/invisibly; macOS 27 now draws it as a large,
            // visible blue rectangle around the whole pane, which reads as
            // a rendering bug rather than "this list currently has
            // keyboard focus". `.focusEffectDisabled()` only suppresses
            // that VISUAL ring — the view stays genuinely focusable and
            // `.onKeyPress` keeps working exactly as before.
            .focusEffectDisabled()
        }
        // jensyleo's own report (2026-08-11): up/down/left/right did
        // nothing while standing on a "Database" row, and — once fixed by
        // attaching these directly to the `List` — arrow keys stopped
        // working again the moment the search field had focus (typing,
        // then arrowing down into results, is the exact flow the search
        // bar was built for). Root cause both times: this section
        // deliberately doesn't use `List`'s own `selection:` binding (a
        // category row needs both a plain click *and* its own independent
        // disclosure — see this view's own top doc comment), so `List`
        // never got native arrow-key handling, and `.onKeyPress` only ever
        // fires on a view that's *itself* focused or an ancestor of
        // whatever currently is — attaching it to the `List` alone meant a
        // key press typed while the search `TextField` (a *sibling* of the
        // `List`, not a descendant) had focus never reached it at all.
        // Attached here instead, on the one `VStack` that's a genuine
        // ancestor of both the search field and the list, so a press
        // bubbles up to this same handler regardless of which of the two
        // currently has focus. Kept here (not moved up to `databaseList`
        // itself) since it now only needs to cover this one pane — scoped
        // to `.database` (jensyleo's own correction, 2026-08-13: crossing
        // into "ROM folder" from here "no debe permitirse", reverting the
        // original cross-section design from 2026-08-11).
        .onKeyPress(.upArrow) { moveDatabaseSelection(by: -1, scope: .database); return .handled }
        .onKeyPress(.downArrow) { moveDatabaseSelection(by: 1, scope: .database); return .handled }
        .onKeyPress(.rightArrow) { expandSelectedDatabaseRow(); return .handled }
        .onKeyPress(.leftArrow) { collapseSelectedDatabaseRow(); return .handled }
    }

    /// The "ROM folder" half of `databaseList` — its own `List`, split out
    /// of what used to be one shared `List` with "Database" (see
    /// `databaseList`'s own doc comment). Needs the same four arrow-key
    /// handlers as `databaseSectionPane`: `AutosavingSplitView` gives each
    /// pane an independent `NSView`, so a key press while this pane (or
    /// nothing in the "Database" pane) has focus wouldn't otherwise reach a
    /// handler attached only up in that other pane. Scoped to `.romFolder`
    /// — see `databaseSectionPane`'s own doc comment for why up/down no
    /// longer cross into "Database" from here either.
    private var romFolderSectionPane: some View {
        ScrollViewReader { proxy in
            romFolderListContent
                .onAppear { romFolderListScrollProxy = proxy }
        }
        // See `isDatabasePaneFocused`'s own doc comment. jensyleo's own
        // report (2026-09-15), right after the macOS 27.0 update: arrow
        // keys stopped reaching these handlers entirely. Root-caused live
        // (via a temporary debug build + `System Events key code`, the
        // only synthetic-input method that reliably drives SwiftUI's
        // `.onKeyPress` — `cliclick`'s own key-press synthesis, oddly,
        // does NOT trigger it on this OS, though that turned out to be a
        // red herring for testing, not the app's real bug): `.focusable()`/
        // `.focused()` MUST come BEFORE `.onKeyPress` in the modifier
        // chain (previously they came after) — macOS 27's SwiftUI runtime
        // is stricter than before about which view identity actually
        // becomes the focus target when these are combined, and the old
        // ordering silently attached the key handlers to the wrong one.
        .focusable()
        .focused($isRomFolderPaneFocused)
        .onKeyPress(.upArrow) { moveDatabaseSelection(by: -1, scope: .romFolder); return .handled }
        .onKeyPress(.downArrow) { moveDatabaseSelection(by: 1, scope: .romFolder); return .handled }
        .onKeyPress(.rightArrow) { expandSelectedDatabaseRow(); return .handled }
        .onKeyPress(.leftArrow) { collapseSelectedDatabaseRow(); return .handled }
        // Same macOS 27 focus-ring fix as `databaseSectionPane`'s own
        // `.focusEffectDisabled()` — see that one's doc comment. This is
        // the exact pane from jensyleo's own screenshot (2026-09-15): the
        // whole "ROM folder" list boxed in a large blue rectangle.
        .focusEffectDisabled()
    }

    /// Search bar for the "Database" tree — see `databaseSearchText`'s own
    /// doc comment for why this, not a bigger cap or a flattened `List`, is
    /// the actually-safe way to reach every row of a huge category.
    private var databaseSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search games… (* ? wildcards)", text: $databaseSearchText)
                .textFieldStyle(.plain)
                // jensyleo's own report (2026-09-29): right after fixing
                // type-ahead to route through the shared event monitor
                // (`handleGamesTypeAheadKeyDown`) instead of a SwiftUI
                // `.onKeyPress`, clicking back into THIS field while
                // `resultsPaneIsActive` was still `true` from an earlier
                // Games click would have made that same monitor keep
                // stealing every keystroke meant for this search box —
                // same "tell the monitor which pane you actually clicked"
                // pattern the sidebar's own tree rows already use.
                .simultaneousGesture(TapGesture().onEnded { resultsPaneIsActive = false })
            if !databaseSearchText.isEmpty {
                Button {
                    databaseSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .padding(6)
        .onChange(of: databaseSearchText) {
            // jensyleo's own request (2026-08-13): "si el árbol de la base
            // de datos está cerrado, pero seleccionado, debería cuando se
            // hace una búsqueda abrirse automáticamente" — a search only
            // ever narrowed a category's own *cached* children
            // (`refreshExpandedDatabaseCategoryCachesAsync` only recomputes
            // whatever's in `expandedDatabaseCategories`), so typing a
            // search while the currently-*selected* category happened to
            // be collapsed silently searched nothing at all — nowhere
            // visible for a match to even appear. Auto-expanding it the
            // moment a real search starts means there's always somewhere
            // for a match to show up, without requiring an extra manual
            // click first.
            if !databaseSearchText.isEmpty {
                if expandedDatabaseCategories.isEmpty {
                    // jensyleo's own follow-up request (2026-09-26): the
                    // fix just above only ever expanded the currently
                    // *selected* category, which could be some OTHER,
                    // narrower category than "All games" (or nothing at
                    // all, e.g. standing on "Rom folder" instead of
                    // "Database") — with literally no tree open yet,
                    // always open "All games" specifically: the one
                    // category that can always answer any search (every
                    // other one is a narrower subset of it), same as the
                    // empty-selection default elsewhere in this file.
                    expandedDatabaseCategories.insert(.allGames)
                } else if let filter = selectedDatabaseFilter, !expandedDatabaseCategories.contains(filter) {
                    expandedDatabaseCategories.insert(filter)
                }
            }
            refreshExpandedDatabaseCategoryCachesAsync(debounced: true)
        }
    }

    private var databaseCategoryListContent: some View {
        List {
            Section {
                if isDatabaseSectionExpanded {
                    ForEach(visibleDatabaseFilters) { filter in
                        // `selectedGameID == nil` too, UNLESS this category
                        // is collapsed — jensyleo's own report (2026-08-13),
                        // with a screenshot: without excluding a selected
                        // leaf, the category header stayed highlighted
                        // exactly like the real selection whenever one of
                        // its OWN VISIBLE leaves was also selected (two rows
                        // both reading as "selected" at once). But that same
                        // blanket exclusion then broke a completely
                        // different, later-reported case: picking a game
                        // from the "Games" table on the right (not a sidebar
                        // leaf at all) also sets `selectedGameID`, which
                        // wrongly killed the header's own highlight even
                        // with the chevron closed — where there's no leaf
                        // row visible at all to conflict with, so nothing to
                        // avoid double-highlighting in the first place. Only
                        // suppress the header's highlight while this
                        // category's own children are actually on screen.
                        let isSelected = selectedDatabaseFilter == filter
                            && (selectedGameID == nil || !databaseCategoryExpansion(for: filter).wrappedValue)
                        DisclosureGroup(isExpanded: databaseCategoryExpansion(for: filter)) {
                            ForEach(databaseCategoryChildrenCache[filter] ?? []) { node in
                                databaseTreeNodeRow(node, filter: filter)
                            }
                        } label: {
                            // jensyleo's own report (2026-08-13): with the
                            // chevron collapsed (no children rows visible
                            // below to "cover" the empty trailing space),
                            // clicking anywhere on this row except the tight
                            // `Label` text/icon itself did nothing — the old
                            // `Button` here only ever covered that tight
                            // content, same root cause (and same fix) as
                            // `databaseTreeLeafLabel`'s own leaf rows: an
                            // `HStack` + `Spacer` + `.contentShape` spanning
                            // the full row width, with a `.simultaneousGesture`
                            // (not `.onTapGesture`/a `Button`, which either
                            // lose the click to or hang against the outline
                            // view's own native mouseDown handling — see that
                            // function's own doc comment for why) doing the
                            // actual selecting.
                            HStack {
                                Label(filter.rawValue, systemImage: filter.symbolName)
                                    .fontWeight(isSelected ? .semibold : .regular)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                TapGesture().onEnded {
                                    selectedDatabaseFilter = filter
                                    selectedRomFolder = nil
                                    // jensyleo's own report (2026-09-29): clicking a
                                    // category header a SECOND time — after having
                                    // selected an individual game inside it — looked
                                    // like the click was being ignored entirely: the
                                    // Games panel stayed frozen on that one game's own
                                    // single-game view instead of returning to the
                                    // category's full list, because `selectedGameID`/
                                    // `selectedGameFamilyRootMachineName` were never
                                    // cleared here — the SAME thing every OTHER
                                    // category-selection path already does (see the
                                    // arrow-key `.category` case just above, and
                                    // `romFolderRow`'s own click handler). This wasn't
                                    // a genuine lost click at all; the tap always
                                    // registered, it just never told the Games panel
                                    // to stop showing the previously-selected game.
                                    selectedGameID = nil
                                    selectedGameFamilyRootMachineName = nil
                                    isDatabasePaneFocused = true
                                    resultsPaneIsActive = false
                                }
                            )
                            .foregroundStyle(isSelected && controlActiveState != .inactive ? Color.white : Color.primary)
                        }
                        // Same real-selection-background treatment as every
                        // other row in this sidebar (leaf games, "Rom
                        // folder" entries) — jensyleo's own request
                        // (2026-08-11), for consistency across the whole
                        // "Database" section, category headers included.
                        .listRowBackground(
                            isSelected
                                ? (controlActiveState == .inactive ? Color.gray.opacity(0.35) : Color.accentColor.opacity(0.85))
                                : Color.clear
                        )
                    }
                }
            } header: {
                sectionHeaderButton(title: "Database", systemImage: "cylinder.split.1x2.fill", isExpanded: $isDatabaseSectionExpanded)
            }
        }
        .listStyle(.sidebar)
    }

    private var romFolderListContent: some View {
        List {
            Section {
                if isRomFilesSectionExpanded {
                    // Sourced from `localRomFolderOrder`, not
                    // `system.romFolderURLs` directly — see that
                    // property's own doc comment for why (the real fix for
                    // "reordenar es igual de lenta"). Position-based
                    // `ForEach` identity (`id: \.offset`, not the URL
                    // itself) was an earlier attempt at the same problem —
                    // kept regardless since it's still correct and harmless
                    // (a swap reads as "this row's content changed in
                    // place" at two indices rather than "a row moved"),
                    // just not what actually fixed it.
                    ForEach(Array(localRomFolderOrder.enumerated()), id: \.offset) { _, url in
                        romFolderRow(for: url)
                    }
                    Button {
                        addRomFolder()
                    } label: {
                        Label("Add Folder…", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    // Read-only Maintenance subfolder — jensyleo's own
                    // request (2026-09-11): "Este folder se debe cargar en
                    // la vista de romfolder con la característica que ese
                    // folder no se le puede escribir." No "Remove Folder",
                    // no reorder grip, never a Fix scope target, never
                    // scanned by "Scan Folder" (see `isMaintenanceFolder`'s
                    // own doc comment for how that's specifically blocked)
                    // — every other row here is a real, user-managed ROM
                    // folder that Scan/Fix can fully act on; this one stays
                    // a donor-only area `MaintenanceFolderSettings`/
                    // `RebuildPlanner.planRepairFromMaintenanceFolder`
                    // already treat as read-only for WRITES. jensyleo's own
                    // follow-up reports (2026-09-11): first, that tapping it
                    // did nothing ("debería permitirme entrar y mostrarme
                    // que en este momento está en blanco"); then, that the
                    // right answer wasn't a separate popover but the SAME
                    // Games panel every other folder already uses ("lo que
                    // debe es permitir ver desde la app, en el panel games,
                    // asi este vacio") — tapping now sets `selectedRomFolder`
                    // exactly like any other row below, which naturally
                    // shows 0 games (nothing here was ever scanned/matched
                    // against the DAT) with `gamesList`'s own new empty-state
                    // message explaining why, rather than a bare empty table.
                    // jensyleo's own report (2026-09-16): this row used to
                    // show whenever a Maintenance ROOT was configured at
                    // all, regardless of whether THIS system's own
                    // subfolder still existed on disk — so deleting it
                    // (Settings, or "Remove System and Delete Maintenance
                    // Folder") looked like it silently failed, since the
                    // row never went away. Now gated on the subfolder
                    // actually existing, matching what deleting it is
                    // supposed to mean; it reappears on its own the next
                    // time something legitimately recreates it (a real
                    // "Find ROMs…" run, or explicitly
                    // via Settings).
                    // jensyleo's own follow-up (2026-09-16): "cuando la NAS
                    // está desconectada, reporta todos los folder menos el
                    // de mantenimiento... unifica eso" — this row now
                    // follows the exact same rule every ordinary ROM folder
                    // row already does: always shown (as long as a
                    // Maintenance root is configured), never hidden just
                    // because it couldn't be verified — only
                    // `maintenanceSubfolderDeleted` (a genuinely deliberate
                    // delete) hides it; `maintenanceSubfolderUnreachable`
                    // only ever adds the same red/⚠️ styling.
                    if !maintenanceSubfolderDeleted,
                       let maintenanceSubfolder = MaintenanceFolderSettings.subfolderURL(for: system) {
                        HStack(spacing: 4) {
                            // jensyleo's own request (2026-09-24): "te
                            // recomiendo ponerle un distintivo a estos
                            // elementos, por ejemplo a la carpeta de
                            // mantenimiento un icono de unas herramientas y
                            // a las de BIOS algo parecido a un chip" —
                            // was `"lock.fill"` (a generic "read-only" mark
                            // shared with nothing else in this sidebar);
                            // a tools icon reads at a glance as "the
                            // donor/repair area", distinct from the BIOS
                            // row's own "cpu.fill" right below.
                            Label(maintenanceSubfolder.lastPathComponent, systemImage: "wrench.and.screwdriver.fill")
                                .foregroundStyle(maintenanceSubfolderUnreachable ? Color.red : Color.secondary)
                            if maintenanceSubfolderUnreachable {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resetStuckRomFolderDragIfNeeded()
                            selectedDatabaseFilter = nil
                            selectedRomFolder = maintenanceSubfolder
                            // jensyleo's own report (2026-09-22): with the
                            // NAS deliberately turned off, plain navigation
                            // between every OTHER ROM folder worked fine
                            // (no disk touch at all — see
                            // `LibraryViewModel.scan`'s own "only a real
                            // Scan reads anything" philosophy), but merely
                            // CLICKING this row alone (no scan requested)
                            // still triggered a real `FileManager
                            // .fileExists` reachability check via
                            // `refreshMaintenanceSubfolderExistsCache()`
                            // below — on an unreachable SMB/AFP-style
                            // share, that call can itself take a real,
                            // noticeable while to time out. Removed: this
                            // row should show whatever was last actually
                            // known (from the last real Scan/"Scan This
                            // Folder"/"Scan Maintenance Folder"), exactly
                            // like every other ROM folder row already
                            // does, never re-verify itself on a plain
                            // click. Still called from every explicit scan
                            // action itself (`startScanMaintenanceFolder`),
                            // so a genuine check still happens whenever the
                            // user actually asks for one.
                        }
                        .listRowBackground(selectedRomFolder == maintenanceSubfolder ? Color.accentColor.opacity(0.85) : Color.clear)
                        .help(
                            maintenanceSubfolderUnreachable
                                ? "Unreachable on the last check — check the connection (NAS/pendrive/external drive) — \(maintenanceSubfolder.path)"
                                : "Maintenance folder (read-only) — click to view it in the Games panel — \(maintenanceSubfolder.path)"
                        )
                        .contextMenu {
                          // `.labelStyle(.titleAndIcon)` forced via `Group`
                          // below — macOS/SwiftUI's `.contextMenu` otherwise
                          // silently drops each `Button`'s `Label` icon
                          // (title-only), unlike menu-bar `.commands`.
                          // Confirmed via a real screenshot (jensyleo,
                          // 2026-09-26).
                          Group {
                            // jensyleo's own request (2026-09-14): "el
                            // Maintenance folder también debe tener esas
                            // mismas opciones de click de contexto" — same
                            // "Scan This Folder" every real ROM folder row
                            // now has, just routed through
                            // `startScanMaintenanceFolder()` (never a real
                            // `viewModel.startScan`, per this folder's own
                            // read-only/never-audited philosophy — see that
                            // function's own doc comment) — and the same
                            // per-system delete already offered in Settings
                            // → General, reachable here too instead of a
                            // trip to Settings.
                            //
                            // `navigateToFolder: false` — jensyleo's own
                            // request (2026-09-22): a context-menu rescan
                            // shouldn't jump the whole panel over to
                            // Maintenance if the user is looking at
                            // something else; only the toolbar's own "Scan
                            // Maintenance Folder" action still does that
                            // (see `startScanMaintenanceFolder`'s own doc
                            // comment).
                            Button {
                                startScanMaintenanceFolder(navigateToFolder: false)
                            } label: {
                                Label("Scan This Folder", systemImage: "arrow.clockwise")
                            }
                            .disabled(isLoadingMaintenanceFolderFiles)
                            Divider()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([maintenanceSubfolder])
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                            Divider()
                            Button(role: .destructive) {
                                pendingMaintenanceSubfolderDeletionFromSidebar = true
                            } label: {
                                Label("Delete Maintenance Subfolder…", systemImage: "trash")
                            }
                          }
                          .labelStyle(.titleAndIcon)
                        }
                    }
                    // BIOS folder — jensyleo's own request (2026-09-24):
                    // "la carpeta BIOS debe quedar cargada en la GUI de la
                    // app", right after confirming its content is now
                    // auto-scanned (`LibraryViewModel.effectiveScanFolders`)
                    // without ever being added to `system.romFolderURLs`.
                    // Unlike the Maintenance row above, this ISN'T a
                    // special, always-empty, never-audited area — it's a
                    // real part of this scan, so tapping it just sets
                    // `selectedRomFolder` exactly like any ordinary ROM
                    // folder row below, and the Games panel's own generic
                    // path-based filtering (`scoped(_:databaseFilter:
                    // romFolder:...)`) shows its real matched games with no
                    // special-case code needed here at all. No reorder
                    // grip, no "Remove Folder" (this folder's lifecycle is
                    // owned by `BIOSFolderSettings` in Settings → Systems →
                    // MAME, not by this per-system list).
                    if system.isMAMEStyle, let biosFolder = BIOSFolderSettings.folderURL {
                        HStack(spacing: 4) {
                            Label(biosFolder.lastPathComponent, systemImage: "cpu.fill")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resetStuckRomFolderDragIfNeeded()
                            selectedDatabaseFilter = nil
                            selectedRomFolder = biosFolder
                        }
                        .listRowBackground(selectedRomFolder == biosFolder ? Color.accentColor.opacity(0.85) : Color.clear)
                        .help("BIOS folder — every scan reads it automatically; \"Organize BIOS Files…\" (toolbar → Fix) moves BIOS files in here — \(biosFolder.path)")
                        .contextMenu {
                          Group {
                            // jensyleo's own request (2026-09-24): "la
                            // carpeta BIOS también debe tener la opción de
                            // escaneo como los rom folder" — same real scan
                            // any ordinary ROM folder row's own "Scan This
                            // Folder" performs (`viewModel.startScan`, not
                            // a special read-only pass like Maintenance's
                            // own "Scan Maintenance Folder" — this folder
                            // IS part of the real audit, see
                            // `LibraryViewModel.effectiveScanFolders`).
                            Button {
                                viewModel.startScan(system: system, folders: [biosFolder]) { warnIfSpecialFolderEmpty(biosFolder, kind: "BIOS") }
                            } label: {
                                Label("Scan This Folder", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isBusy)
                            Divider()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([biosFolder])
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                          }
                          .labelStyle(.titleAndIcon)
                        }
                    }
                    // Complementary Chips folder — same exact treatment as
                    // the BIOS row right above, jensyleo's own request
                    // (2026-09-24): "lo mismo que BIOS pero para los demás
                    // chips."
                    if system.isMAMEStyle, let chipsFolder = ComplementaryChipsFolderSettings.folderURL {
                        HStack(spacing: 4) {
                            Label(chipsFolder.lastPathComponent, systemImage: "puzzlepiece.extension.fill")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resetStuckRomFolderDragIfNeeded()
                            selectedDatabaseFilter = nil
                            selectedRomFolder = chipsFolder
                        }
                        .listRowBackground(selectedRomFolder == chipsFolder ? Color.accentColor.opacity(0.85) : Color.clear)
                        .help("Complementary Chips folder — every scan reads it automatically; \"Organize Complementary Chips…\" (toolbar → Fix) moves shared device files in here — \(chipsFolder.path)")
                        .contextMenu {
                          Group {
                            Button {
                                viewModel.startScan(system: system, folders: [chipsFolder]) { warnIfSpecialFolderEmpty(chipsFolder, kind: "Complementary Chips") }
                            } label: {
                                Label("Scan This Folder", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isBusy)
                            Divider()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([chipsFolder])
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                          }
                          .labelStyle(.titleAndIcon)
                        }
                    }
                    // Samples folder — jensyleo's own request (2026-09-24):
                    // "implementalo" ("lo mismo que BIOS", right after
                    // confirming the risk he wanted avoided: unlike BIOS/
                    // Complementary Chips, a sample has no DAT hash to
                    // match against — its content is filtered OUT of the
                    // audit entirely (see `SamplesFolderSettings
                    // .isUnderSamplesFolder`'s own doc comment), so
                    // selecting this row correctly shows an empty Games
                    // table rather than a table full of spurious "Surplus"
                    // rows. It's still auto-scanned (`effectiveScanFolders`)
                    // and browsable here exactly like BIOS/Complementary
                    // Chips, just with nothing to audit against.
                    if system.isMAMEStyle, let samplesFolder = SamplesFolderSettings.folderURL {
                        HStack(spacing: 4) {
                            Label(samplesFolder.lastPathComponent, systemImage: "speaker.wave.2.fill")
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            resetStuckRomFolderDragIfNeeded()
                            selectedDatabaseFilter = nil
                            selectedRomFolder = samplesFolder
                        }
                        .listRowBackground(selectedRomFolder == samplesFolder ? Color.accentColor.opacity(0.85) : Color.clear)
                        .help("Samples folder — every scan reads it, but its content is never part of this system's own audit (samples have no DAT hash to match against) — \"Fix Samples\" (toolbar → Fix) is what copies matching zips in here — \(samplesFolder.path)")
                        .contextMenu {
                          Group {
                            Button {
                                viewModel.startScan(system: system, folders: [samplesFolder]) { warnIfSpecialFolderEmpty(samplesFolder, kind: "Samples") }
                            } label: {
                                Label("Scan This Folder", systemImage: "arrow.clockwise")
                            }
                            .disabled(viewModel.isBusy)
                            Divider()
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([samplesFolder])
                            } label: {
                                Label("Reveal in Finder", systemImage: "folder")
                            }
                          }
                          .labelStyle(.titleAndIcon)
                        }
                    }
                }
            } header: {
                // jensyleo's own wording call (2026-08-11): "Rom files" →
                // "ROM folder" — this section lists actual folders on disk,
                // not a list of individual files. Only the user-visible
                // label changed here; every internal comment/identifier
                // elsewhere in this file still says "Rom files" (the
                // section's own long-standing internal name), deliberately
                // left alone to avoid a purely cosmetic rename touching
                // dozens of unrelated lines.
                sectionHeaderButton(title: "ROM folder", systemImage: "externaldrive.fill", isExpanded: $isRomFilesSectionExpanded)
            }
        }
        .listStyle(.sidebar)
        // jensyleo's own explicit instruction (2026-09-16): "la app solo
        // debe iniciar, los escaneos se deben hacer por parte del
        // usuario" — confirmed live: opening/reopening the app itself was
        // enough to silently touch the NAS via the Maintenance-existence
        // check, with that row's state visibly flipping depending on
        // whether the NAS happened to be connected at that exact moment,
        // with no scan ever explicitly asked for. That one check no
        // longer runs from `.onAppear` — only a genuine user action does:
        // tapping the Maintenance row itself (see its own `.onTapGesture`),
        // or an explicit "Scan This Folder"/"Scan Folder"/"Scan All
        // Folders"/"Scan Maintenance Folder".
        //
        // jensyleo's own explicit follow-up (2026-09-16): "mantén el 2,
        // ese es más que necesario" — the volume-kind (local/removable/
        // NAS) icon detection stays automatic on `.onAppear`, unlike the
        // Maintenance check above. Still fully off-`@MainActor`
        // (`Task.detached`, see `refreshRomFolderVolumeKindCache`'s own
        // doc comment) so it can never freeze the app the way the
        // Maintenance check briefly did before that fix.
        .onAppear {
            resetStuckRomFolderDragIfNeeded()
            syncLocalRomFolderOrder()
            refreshRomFolderVolumeKindCache()
        }
        .onChange(of: system.romFolderURLs) {
            syncLocalRomFolderOrder()
            refreshRomFolderVolumeKindCache()
        }
        // jensyleo's own report (2026-09-16): "creo la carpeta de
        // mantenimiento y no la está mostrando" — Settings creates/deletes
        // a Maintenance subfolder in a completely separate window; without
        // this, an already-open system's detail view had no way to learn
        // that happened, since the eager on-every-`.onAppear` recheck was
        // deliberately removed earlier this same session. Only ever
        // confirms/clears `maintenanceSubfolderUnreachable` — never touches
        // `maintenanceSubfolderDeleted` (that's `subfolderDidDelete`'s own
        // job, right below), so a plain backfill/create elsewhere can't
        // accidentally "undelete" this row for a system it has nothing to
        // do with.
        .onReceive(NotificationCenter.default.publisher(for: MaintenanceFolderSettings.subfoldersDidChange)) { _ in
            refreshMaintenanceSubfolderExistsCache()
        }
        // A DELIBERATE delete, from any of the three entry points
        // (Settings' per-system button, this same sidebar's own delete
        // below, or "Remove System and Delete Maintenance Folder") — the
        // only thing that actually hides this row (see
        // `maintenanceSubfolderDeleted`'s own doc comment). Filtered to
        // THIS system, since the notification is a plain app-wide
        // broadcast covering every system's own subfolder.
        .onReceive(NotificationCenter.default.publisher(for: MaintenanceFolderSettings.subfolderDidDelete)) { notification in
            guard notification.userInfo?["systemID"] as? RomSystem.ID == system.id else { return }
            maintenanceSubfolderDeleted = true
            maintenanceSubfolderUnreachable = false
        }
        .onPreferenceChange(ReorderRowFramePreferenceKey.self) { romFolderRowFrames = $0 }
        .reorderGhostOverlay(
            draggingIndex: draggingRomFolderIndex,
            dragOffset: dragRomFolderOffset,
            rowFrames: romFolderRowFrames
        ) { index in
            HStack(spacing: 4) {
                Label(
                    localRomFolderOrder.indices.contains(index) ? localRomFolderOrder[index].lastPathComponent : "",
                    systemImage: "externaldrive"
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
        .confirmationDialog(
            "Remove \"\(pendingRomFolderRemoval?.lastPathComponent ?? "")\" from This System?",
            isPresented: Binding(
                get: { pendingRomFolderRemoval != nil },
                set: { if !$0 { pendingRomFolderRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let url = pendingRomFolderRemoval {
                    removeRomFolder(url)
                }
                pendingRomFolderRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRomFolderRemoval = nil }
        } message: {
            Text("This only stops ROMForge from scanning this folder — nothing is deleted from disk. Its own entries are removed from this system's last scan results until you add it back and rescan.")
        }
        .confirmationDialog(
            "Delete This System's Own Maintenance Subfolder?",
            isPresented: $pendingMaintenanceSubfolderDeletionFromSidebar,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                try? MaintenanceFolderSettings.deleteSubfolder(for: system)
                // A deliberate delete, unlike a NAS dropping out from under
                // an existing folder — hides the row outright instead of
                // showing red/unreachable (see `maintenanceSubfolderDeleted`'s
                // own doc comment). Posts the same notification Settings'
                // own delete button does, for consistency (harmless
                // no-op here since this view already updates its own
                // state directly).
                maintenanceSubfolderDeleted = true
                maintenanceSubfolderUnreachable = false
                NotificationCenter.default.post(name: MaintenanceFolderSettings.subfolderDidDelete, object: nil, userInfo: ["systemID": system.id])
                if isSelectedFolderMaintenanceSubfolder { loadMaintenanceFolderFiles() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently deletes this system's own Maintenance subfolder and everything inside it — any donor ROMs dropped there for \"Find ROMs…\" are gone. Every OTHER system's own subfolder is untouched. This cannot be undone, and it stays deleted until something genuinely needs it again (running \"Find ROMs…\", or reconfiguring the Maintenance root in Settings) — simply viewing this system again will not bring it back.")
        }
    }

    /// jensyleo's own final call (2026-08-12), after three drag-and-drop
    /// attempts in a row each traded one problem for another (`.onMove`:
    /// never engaged at all, since a `List` row that's a `Button`
    /// intercepts the mouse-down it needs; whole-row `.onDrag`: dragging
    /// itself improved, but competing with the same `Button`'s own tap
    /// recognizer made a plain click "muy complicado"/unreliable; a
    /// separate small drag-handle + insertion gaps between every row:
    /// fixed the click, but the gaps "se separan demasiado" and shrank the
    /// actual clickable area down to something "muy pequeña"): plain,
    /// always-visible ↑/↓ buttons instead of any drag gesture at all. No
    /// gesture-recognizer conflict is possible when reordering is just two
    /// more `Button`s — this is deliberately the *simple, boring, reliable*
    /// answer after the more visually elegant ones kept costing real
    /// usability. `disabled` at each end takes the place of "can I drop
    /// this last" — moving the last folder down, or the first one up,
    /// just does nothing, rather than needing a special "drop past the
    /// end" target the way any drag-based scheme would.
    @ViewBuilder
    private func romFolderRow(for url: URL) -> some View {
        let index = localRomFolderOrder.firstIndex(of: url)
        // jensyleo's own follow-up (2026-09-16), after the "Scan Failed"
        // pop-up landed: "los recursos que no encontró debería marcarlos
        // en rojo, o colocarles algún distintivo particular" — a folder
        // the LAST scan that actually covered it couldn't reach (NAS
        // offline, pendrive unplugged, etc.) gets its own row tinted red
        // with a warning glyph, on top of (not instead of) the one-time
        // pop-up — a mark that's still visible long after that pop-up's
        // been dismissed, for exactly as long as the folder stays
        // unreachable (see `lastScanUnreachableFolders`'s own doc comment
        // on when it clears).
        let isUnreachable = viewModel.lastScanUnreachableFolders.contains(url)
        HStack(spacing: 4) {
            // jensyleo's own report (2026-08-13): "en rom folder el folder
            // se seleccione con dar click en la línea donde está... toca
            // hacer click en el nombre y es muy incómodo" — the label used
            // to be its own `Button`, so only its own tight text/icon
            // bounds (not the row's own empty trailing space) actually
            // selected anything. A plain `Label` here now, with the whole
            // row's own `.onTapGesture` (below `.contentShape`) doing the
            // selecting instead — the ↑/↓ `Button`s alongside it keep
            // intercepting their own clicks fine, since a tap landing
            // exactly on one of *those* is still claimed by that more
            // specific control first.
            Label(url.lastPathComponent, systemImage: (romFolderVolumeKindCache[url] ?? .unknown).symbolName)
                .fontWeight(selectedRomFolder == url ? .semibold : .regular)
                .foregroundStyle(isUnreachable ? Color.red : Color.primary)
            if isUnreachable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .help("Unreachable on the last scan that covered it — check the connection (NAS/pendrive/external drive) and scan again.")
            }
            Spacer(minLength: 0)
            // jensyleo's own report (2026-08-13): "el área de click sigue
            // siendo muy chica" — an SF Symbol at its natural rendered
            // size is only a handful of points across, and `.borderless`
            // gives it no extra hit-target padding beyond that glyph's own
            // tiny bounding box. `.contentShape(Rectangle())` extends the
            // *tappable* area to the full frame below without changing
            // what's actually drawn, so the target is comfortably clickable
            // even though the chevron itself stays small and unobtrusive.
            // jensyleo's own request (2026-08-13): "por lógica el primero
            // no debería tener flecha de subida y el último de bajada" —
            // a disabled-but-still-visible chevron on an edge row implied
            // there might be somewhere left for it to go; hiding it
            // outright says so more directly.
            // jensyleo's own request (2026-08-31): ⌘-drag this grip to
            // reorder. Evolved from an earlier "Move Up"/"Move Down" menu
            // on the same icon, itself evolved from the original
            // chevron-up/chevron-down pair.
            //
            // jensyleo's own report (2026-09-17): a plain `ReorderGripHandle`
            // (SwiftUI `DragGesture`) stopped working here specifically —
            // this is the one reorderable list actually backed by a real
            // `List`/`NSTableView`, and macOS 27 now claims the drag event
            // stream at the AppKit level before `.highPriorityGesture` ever
            // gets a chance (see `installRomFolderReorderMonitor`'s own doc
            // comment for the full root-cause). This row is now just a
            // plain icon — real tracking happens via that `NSEvent` local
            // monitor instead, keyed off `romFolderRowFrames`'s own
            // published frame for this exact row.
            if let index {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .help("⌘ + clic y arrastra para reordenar")
                    .id(index)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { selectRomFolder(url) }
        .help({
            var text = url.path
            text += (romFolderVolumeKindCache[url] ?? .unknown).helpSuffix
            if isUnreachable { text += " — unreachable on the last scan" }
            return text
        }())
        // A real selection background, not just bold text — see
        // `controlActiveState`'s own doc comment for why this is blue
        // while this window is key and gray otherwise, matching native
        // List/NSTableView selection rather than a static color. A row
        // being ⌘-dragged (jensyleo's own report, 2026-08-31: "no resalta
        // la línea que se va a mover") always wins over the plain selection
        // tint — it's the more useful thing to see while actively dragging,
        // even for the currently-selected row.
        .listRowBackground(
            index != nil && draggingRomFolderIndex == index
                ? Color.accentColor.opacity(0.35)
                : selectedRomFolder == url
                    ? (controlActiveState == .inactive ? Color.gray.opacity(0.35) : Color.accentColor.opacity(0.85))
                    : Color.clear
        )
        .reorderDropIndicator(index.flatMap {
            ReorderGripHandle.dropIndicatorEdge(
                for: $0,
                draggingIndex: draggingRomFolderIndex,
                dragPreviewIndex: dragPreviewRomFolderIndex
            )
        })
        .opacity(index != nil && draggingRomFolderIndex == index ? 0.35 : 1)
        .reportReorderFrame(index ?? -1)
        .foregroundStyle(selectedRomFolder == url && controlActiveState != .inactive ? Color.white : Color.primary)
        .contextMenu {
          Group {
            // jensyleo's own request (2026-09-14): a ROM folder's own
            // context menu had no way to scan just that one folder without
            // first selecting it and reaching for the toolbar's own "Scan"
            // dropdown — same action `scanSubActions`'s own "Scan Folder"
            // entry already performs, just reachable directly from the
            // sidebar row itself.
            Button {
                viewModel.startScan(system: system, folders: [url])
            } label: {
                Label("Scan This Folder", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isBusy)
            Divider()
            Button(role: .destructive) {
                pendingRomFolderRemoval = url
            } label: {
                Label("Remove Folder…", systemImage: "trash")
            }
          }
          .labelStyle(.titleAndIcon)
        }
        // jensyleo's own report (2026-08-13): arrowing down/up through
        // "ROM folder" never scrolled the list — `moveDatabaseSelection(by:)`
        // already calls `romFolderListScrollProxy?.scrollTo(url, ...)` for
        // this exact case, but a `ScrollViewProxy` can only scroll to a
        // view that's actually tagged `.id(url)` somewhere in the `List`;
        // nothing here ever was (the `ForEach` above identifies rows by
        // `\.offset` for its own diffing, which is a different thing
        // entirely) — the call was silently a no-op the whole time.
        .id(url)
    }

    /// Swaps `url` with its immediate neighbor in the given direction —
    /// `by: -1` (up) or `by: 1` (down) — a no-op past either end. Mutates
    /// `localRomFolderOrder` directly (instant, isolated re-render — see
    /// its own doc comment for why) and *also* calls `onAddFolder` to
    /// persist the same order back through `system`/the store, but that
    /// second part is no longer what the user visibly waits on.
    private func moveRomFolder(from index: Int, to newIndex: Int) {
        var folders = localRomFolderOrder
        folders.moveElement(from: index, to: newIndex)
        localRomFolderOrder = folders
        // jensyleo's own report (2026-08-13): "se siente igual" — moving
        // the render to `localRomFolderOrder` (above) didn't actually
        // decouple anything, because `onAddFolder` was still called
        // *synchronously*, in the same action/render pass as the local
        // state write. SwiftUI commits a Button action's state changes as
        // one atomic update — the local write and the expensive
        // `system`-changed re-render (see `localRomFolderOrder`'s own doc
        // comment for why that's expensive: the whole `LibraryDetailView`,
        // Games `Table` included) both had to finish before *anything*
        // could appear on screen, so the local write's own speed never
        // mattered. Deferring `onAddFolder` to the next run-loop turn lets
        // *this* frame commit immediately (just the small local reorder),
        // with the expensive persistence/re-render happening invisibly
        // afterward — nothing the user's looking at changes when it does,
        // since `localRomFolderOrder` already shows the right order.
        DispatchQueue.main.async {
            onAddFolder(folders)
        }
    }

    /// Keeps `localRomFolderOrder` matching `system.romFolderURLs` whenever
    /// they'd otherwise disagree — called on appear, and from every site
    /// that changes `system.romFolderURLs` through some path *other* than
    /// `moveRomFolder` itself (adding/removing a folder here, or a change
    /// from somewhere else entirely — Settings' "Reset ROM Folder View"/
    /// purge actions, another window). A plain equality guard, not an
    /// unconditional overwrite: after `moveRomFolder`'s own `onAddFolder`
    /// call eventually flows back around as a new `system` value, both
    /// sides already agree, so this is a no-op then, not a second write.
    private func syncLocalRomFolderOrder() {
        guard localRomFolderOrder != system.romFolderURLs else { return }
        localRomFolderOrder = system.romFolderURLs
    }

    /// The only place `FileManager.default.fileExists` runs for the
    /// Maintenance-subfolder sidebar row — see `maintenanceSubfolderUnreachable`'s
    /// own doc comment. Called only when the answer can actually have
    /// changed (this view appearing, the system changing, or a real
    /// create/backfill of the subfolder — a DELETE is handled separately,
    /// directly, via `subfolderDidDelete`), never on every re-render.
    /// jensyleo's own report (2026-09-16): "la app se está tratando de
    /// congelar al iniciar, se pone lento la carga" — this used to be a
    /// plain, synchronous `FileManager.fileExists` call, run directly on
    /// `@MainActor` from `.onAppear` for the auto-restored last-selected
    /// system, before the window is even interactive. The Maintenance
    /// root is an arbitrary user-chosen folder — nothing stops it from
    /// living on the same slow/unreachable NAS share as a ROM folder — so
    /// a stalled SMB mount hung the ENTIRE app at launch on this one
    /// check, exactly the class of bug this session already fixed for
    /// `RomFolderVolumeKind.detect` (see its own `Task.detached` doc
    /// comment). Same fix here: the real disk touch moves off the main
    /// actor, generation-guarded so a slow, now-stale check can never
    /// clobber a newer one that's already finished.
    @State private var maintenanceSubfolderExistsRefreshGeneration = 0

    private func refreshMaintenanceSubfolderExistsCache() {
        guard let subfolder = MaintenanceFolderSettings.subfolderURL(for: system) else {
            return
        }
        maintenanceSubfolderExistsRefreshGeneration += 1
        let generation = maintenanceSubfolderExistsRefreshGeneration
        Task.detached(priority: .utility) {
            let exists = FileManager.default.fileExists(atPath: subfolder.path)
            await MainActor.run {
                guard generation == maintenanceSubfolderExistsRefreshGeneration else { return }
                // A confirmed-existing subfolder can never itself be
                // "deleted" — if this system's folder was deleted in
                // Settings and then genuinely recreated, this same check
                // is exactly what clears that stale flag back.
                if exists {
                    maintenanceSubfolderDeleted = false
                    maintenanceSubfolderUnreachable = false
                } else {
                    maintenanceSubfolderUnreachable = true
                }
            }
        }
    }

    /// Off-`@MainActor` by design — `URLResourceValues(forKeys:)` for
    /// `.volumeIsLocalKey`/etc. is a real filesystem call that, over
    /// SMB/AFP, can genuinely block on the network. Called once per
    /// `romFolderListContent`'s own `.onAppear`/`.onChange(of:
    /// system.romFolderURLs)`, never from inside a row's own body.
    /// Generation-guarded exactly like `loadMaintenanceFolderFiles`'s own
    /// stale-result guard, so a slow NAS lookup from a folder set that's
    /// since changed can never clobber a newer, already-finished one.
    private func refreshRomFolderVolumeKindCache() {
        let folders = system.romFolderURLs
        romFolderVolumeKindRefreshGeneration += 1
        let generation = romFolderVolumeKindRefreshGeneration
        Task.detached(priority: .utility) {
            var results: [URL: RomFolderVolumeKind] = [:]
            for folder in folders {
                results[folder] = RomFolderVolumeKind.detect(for: folder)
            }
            await MainActor.run {
                guard generation == romFolderVolumeKindRefreshGeneration else { return }
                // jensyleo's own report (2026-09-17): "⌘-arrastrar para
                // reordenar ya no funciona, y la app 'bugea' la imagen" —
                // reassigning this whole dictionary invalidates this
                // view's ENTIRE `body`, rebuilding every `romFolderRow`
                // (including whichever one is mid-⌘-drag right now) and
                // re-publishing its frame via `ReorderRowFramePreferenceKey`
                // — corrupting `ReorderGripHandle`'s own frame-based drag
                // math and visibly glitching the drag ghost. Two guards:
                // never touch it while a drag is active (the icon can
                // simply wait for the next natural trigger), and skip the
                // reassignment entirely when nothing actually changed
                // (the common case — this fires on every ROM-folder-row
                // tap, not just once), so this table full of icons isn't
                // rebuilt just because something ELSE was clicked.
                guard draggingRomFolderIndex == nil else { return }
                guard romFolderVolumeKindCache != results else { return }
                romFolderVolumeKindCache = results
            }
        }
    }

    /// One flat, top-to-bottom row a keyboard arrow press can land on —
    /// built fresh from current expansion/cache state each time a key is
    /// pressed (cheap: only ever as many rows as are *actually rendered*
    /// right now, never the full unexpanded category), so it always
    /// matches exactly what's on screen. See `databaseListContent`'s own
    /// doc comment for why this exists at all.
    private enum DatabaseSelectableRow {
        case category(DatabaseFilter)
        case game(filter: DatabaseFilter, id: String)
        case romFolder(URL)
    }

    /// Which of the two independent `List`s (`databaseSectionPane`/
    /// `romFolderSectionPane`) an arrow press should navigate within —
    /// jensyleo's own correction (2026-08-13) of the original design: a
    /// single flattened list spanning *both* sections (2026-08-11) let ↑/↓
    /// cross from the bottom of "Database" straight into "ROM folder" and
    /// back — meant, at the time, to match a native sidebar's own
    /// cross-section arrow-key navigation, but jensyleo's own call is that
    /// this specific jump "no debe permitirse". Each pane's own
    /// `.onKeyPress` now passes its own scope, so a press never sees past
    /// its own section's rows.
    private enum DatabaseSelectionScope {
        case database
        case romFolder
    }

    private func flattenedVisibleDatabaseRows(scope: DatabaseSelectionScope) -> [DatabaseSelectableRow] {
        var rows: [DatabaseSelectableRow] = []
        switch scope {
        case .database:
            guard isDatabaseSectionExpanded else { return [] }
            for filter in visibleDatabaseFilters {
                rows.append(.category(filter))
                guard expandedDatabaseCategories.contains(filter) else { continue }
                rows.append(contentsOf: flattenedVisibleDatabaseNodes(databaseCategoryChildrenCache[filter] ?? [], filter: filter))
            }
        case .romFolder:
            guard isRomFilesSectionExpanded else { return [] }
            rows.append(contentsOf: localRomFolderOrder.map { .romFolder($0) })
        }
        return rows
    }

    private func flattenedVisibleDatabaseNodes(_ nodes: [DatabaseTreeNode], filter: DatabaseFilter) -> [DatabaseSelectableRow] {
        var rows: [DatabaseSelectableRow] = []
        for node in nodes {
            // Neither a "Show N more" button nor a plain truncation notice
            // is a real, selectable game — arrow navigation skips both,
            // same as it would skip any other non-selectable UI chrome.
            guard node.loadMoreFilter == nil, !node.isTruncationNotice else { continue }
            rows.append(.game(filter: filter, id: node.id))
            if let children = node.children, !children.isEmpty, expandedGameTreeNodes.contains(node.id) {
                rows.append(contentsOf: flattenedVisibleDatabaseNodes(children, filter: filter))
            }
        }
        return rows
    }

    /// Moves the current "Database" selection to the previous/next visible
    /// row (`by: -1`/`1`) — wraps to the first/last row if nothing is
    /// currently selected there at all, matching `NSOutlineView`'s own
    /// convention of landing on an edge row rather than doing nothing.
    private func moveDatabaseSelection(by offset: Int, scope: DatabaseSelectionScope) {
        let rows = flattenedVisibleDatabaseRows(scope: scope)
        guard !rows.isEmpty else { return }
        let currentIndex = rows.firstIndex { row in
            switch row {
            // Same relaxation as the category header's own `isSelected`
            // (`databaseCategoryListContent`'s doc comment) and for the
            // same reason: `selectedGameID` also gets set by clicking a row
            // in the "Games" table on the right, not only by a sidebar
            // leaf. Requiring it `== nil` unconditionally meant this lookup
            // could no longer find "the category" as the current position
            // once a game was picked that way — jensyleo's own report
            // (2026-08-13): clicking back into the sidebar and pressing an
            // arrow then jumped to the first/last row instead of moving
            // from where the category still visually was. Only still
            // require `selectedGameID == nil` while this category is
            // actually expanded — that's the one case where a real leaf row
            // is also present in `rows` and should legitimately win instead.
            case .category(let filter):
                return selectedDatabaseFilter == filter
                    && (selectedGameID == nil || !databaseCategoryExpansion(for: filter).wrappedValue)
            case .game(let filter, let id): return selectedDatabaseFilter == filter && selectedGameID == id
            case .romFolder(let url): return selectedRomFolder == url
            }
        }
        let newIndex: Int
        if let currentIndex {
            newIndex = max(0, min(rows.count - 1, currentIndex + offset))
        } else {
            newIndex = offset > 0 ? 0 : rows.count - 1
        }
        switch rows[newIndex] {
        case .category(let filter):
            selectedDatabaseFilter = filter
            selectedRomFolder = nil
            selectedGameID = nil
            selectedGameFamilyRootMachineName = nil
            databaseListScrollProxy?.scrollTo(filter.id, anchor: .center)
        case .game(let filter, let id):
            selectedDatabaseFilter = filter
            selectedRomFolder = nil
            selectedGameID = id
            // jensyleo's own report (2026-08-13), with a screenshot: the
            // "Games" panel showed the whole category with the selected
            // row merely scrolled-to/highlighted — landing on a *parent*
            // game (one with its own clone family nested under it in the
            // tree) should instead scope "Games" down to just that parent
            // and its clones, the same way selecting a "ROM folder" scopes
            // it to that folder's own games. See
            // `familyRootMachineName(for:)`'s own doc comment for why a
            // clone *leaf* now gets this same treatment too, scoped to its
            // own parent's family.
            let node = findDatabaseTreeNode(id: id, in: databaseCategoryChildrenCache[filter] ?? [])
            selectedGameFamilyRootMachineName = node.flatMap { familyRootMachineName(for: $0) }
            databaseListScrollProxy?.scrollTo(id, anchor: .center)
            // jensyleo's own report (2026-08-13), with a screenshot: after
            // navigating "Database" (search included), the "Games" panel
            // "se queda con una visual que no está relacionada" — true:
            // the tree's own click/arrow-key handlers always set
            // `selectedGameID` correctly, but never told the Games
            // `Table` to scroll to it, so it just kept showing whatever
            // part of a ~45,000-row list happened to be in view already,
            // unrelated to the row that just got selected off-screen.
            // `revealAndScrollGamesTable(to:)` — see its own doc comment —
            // also expands the visible page first if `id` isn't in it yet.
            revealAndScrollGamesTable(to: id)
        case .romFolder(let url):
            selectedDatabaseFilter = nil
            selectedRomFolder = url
            selectedGameID = nil
            selectedGameFamilyRootMachineName = nil
            romFolderListScrollProxy?.scrollTo(url, anchor: .center)
        }
    }

    /// Right arrow: opens whichever row is currently selected — a category
    /// header (jensyleo's own report, 2026-08-11: this didn't work at all
    /// at first, only game rows did) or a game's own clone disclosure —
    /// does nothing for a childless game, same as `NSOutlineView`'s own
    /// convention of right arrow being a no-op on a row with nothing to
    /// expand.
    private func expandSelectedDatabaseRow() {
        guard let filter = selectedDatabaseFilter else { return }
        // Same relaxation as `moveDatabaseSelection(by:scope:)`'s own
        // `currentIndex` lookup, for the same reason: `selectedGameID` can
        // be set from picking a row in the "Games" table on the right, not
        // only from a sidebar leaf — while this category is collapsed,
        // that's still "standing on the category header" as far as the
        // sidebar's own keyboard focus is concerned, so right arrow should
        // expand it rather than reach for a (possibly unrelated) game's own
        // clone disclosure.
        if selectedGameID == nil || !databaseCategoryExpansion(for: filter).wrappedValue {
            // Standing on the category header itself — same effect as
            // clicking its own disclosure triangle: mark it expanded, and
            // compute its children off the main thread if this is the
            // first time (see `refreshExpandedDatabaseCategoryCachesAsync`'s
            // own doc comment for why this can never be synchronous).
            expandedDatabaseCategories.insert(filter)
            if databaseCategoryChildrenCache[filter] == nil {
                refreshExpandedDatabaseCategoryCachesAsync(debounced: false, only: filter)
            } else {
                scrollDatabaseListToSelectedGameIfNewlyVisible()
            }
            return
        }
        guard let id = selectedGameID,
              let node = findDatabaseTreeNode(id: id, in: databaseCategoryChildrenCache[filter] ?? []),
              let children = node.children, !children.isEmpty
        else { return }
        expandedGameTreeNodes.insert(id)
    }

    /// Left arrow: closes whichever row is currently selected — a category
    /// header or a game's own clone disclosure — a harmless no-op when
    /// there's nothing to close (a childless game, or an already-collapsed
    /// row).
    private func collapseSelectedDatabaseRow() {
        guard let filter = selectedDatabaseFilter else { return }
        // Same relaxation as `expandSelectedDatabaseRow()`'s own doc
        // comment — a game selected via the "Games" table shouldn't make
        // left arrow reach for that game's own clone disclosure instead of
        // collapsing the (already-collapsed) category header it's
        // logically standing on.
        if selectedGameID == nil || !databaseCategoryExpansion(for: filter).wrappedValue {
            expandedDatabaseCategories.remove(filter)
            databaseCategoryVisibleCap.removeValue(forKey: filter)
            return
        }
        guard let id = selectedGameID else { return }
        expandedGameTreeNodes.remove(id)
    }

    private func findDatabaseTreeNode(id: String, in nodes: [DatabaseTreeNode]) -> DatabaseTreeNode? {
        for node in nodes {
            if node.id == id { return node }
            if let children = node.children, let found = findDatabaseTreeNode(id: id, in: children) { return found }
        }
        return nil
    }

    /// Which parent's clone family a selected "Database" tree node should
    /// scope the Games table to — a parent (has its own children in the
    /// tree) scopes to itself; jensyleo's own follow-up report (2026-08-13),
    /// with a screenshot, extended this to a *clone leaf* too: selecting
    /// one showed the whole unrelated category instead of that same
    /// family, since a clone has no children of its own to trigger the
    /// original check. Looks the clone's own parent up from the DAT's
    /// `cloneOf` (via a live scan entry first, falling back to the
    /// preloaded catalog for a game not scanned yet) rather than from the
    /// tree structure itself — clone nesting only exists in the "All
    /// games" category tree in the first place, so a clone selected from
    /// any *other* category (a flat list of siblings there) would
    /// otherwise have no nearby parent node to find at all. `nil` for a
    /// genuinely standalone game (no clone family either way).
    private func familyRootMachineName(for node: DatabaseTreeNode) -> String? {
        if let children = node.children, !children.isEmpty { return node.machineName }
        if let entry = viewModel.auditReport?.entries.first(where: { $0.game == node.machineName }), let cloneOf = entry.cloneOf, !cloneOf.isEmpty {
            return cloneOf
        }
        if let game = viewModel.preloadedGames.first(where: { $0.name == node.machineName }), let cloneOf = game.cloneOf, !cloneOf.isEmpty {
            return cloneOf
        }
        return nil
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
        var folders = system.romFolderURLs
        let addedFolders = ROMFolderPicker.pickFolders(existing: folders)
        guard !addedFolders.isEmpty else { return }
        // jensyleo's own request (2026-08-12): "ROM folder" starts out
        // alphabetical by default — a newly-added folder slots into its
        // alphabetically-correct position among the existing ones, rather
        // than always landing at the end regardless of name. Inserted one
        // at a time into whatever order `folders` is *already* in (not a
        // full re-sort of everything) so this never undoes a manual
        // reorder (the ↑/↓ buttons in `romFolderRow(for:)`) already applied
        // to the folders already there — only decides where a genuinely
        // *new* folder starts out.
        for url in addedFolders.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let insertIndex = folders.firstIndex { $0.lastPathComponent.localizedCaseInsensitiveCompare(url.lastPathComponent) == .orderedDescending } ?? folders.count
            folders.insert(url, at: insertIndex)
        }
        localRomFolderOrder = folders
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
        localRomFolderOrder = folders
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
            // jensyleo's own request (2026-09-13): the Maintenance
            // subfolder must look EXACTLY like every other ROM folder —
            // same Games table, same Roms panel — never a separate,
            // custom-built view. `displayedGameNodes` (see its own doc
            // comment) already returns `maintenanceGameNodes` while this
            // folder is selected, so this branch needs no special case at
            // all: an empty Maintenance folder correctly shows
            // `gamesEmptyStateMessage`'s own maintenance-specific wording,
            // and a non-empty one renders through the exact same
            // `gameTreeTable` every other folder uses.
            // jensyleo's own report (2026-09-14): "al escanear el folder de
            // mantenimiento, no se ve barra de progreso" — reusing
            // `gameTreeTable` for Maintenance (see this whole block's own
            // doc comment above) meant the loading state a plain refresh
            // used to show (`isLoadingMaintenanceFolderFiles`, driving its
            // own `ProgressView` in the now-removed dedicated view) never
            // appeared, so a real, sometimes multi-second hash+match pass
            // against a large Maintenance folder just silently did
            // nothing until it finished — reading as a stalled/broken
            // transition rather than a real background operation.
            if isSelectedFolderMaintenanceSubfolder, isLoadingMaintenanceFolderFiles, !viewModel.isBusy {
                VStack {
                    Spacer(minLength: 24)
                    // jensyleo's own report (2026-09-19): a first attempt at
                    // fixing this drew its OWN copy of `scanProgressOverlay`
                    // right here, which stacked a SECOND real progress bar
                    // on top of the single global one (this view's own
                    // `.overlay { if viewModel.isBusy { scanProgressOverlay } }`)
                    // — same numbers, shown twice. Removing the duplicate
                    // bar left a quieter but still confusing pairing: this
                    // static "Reading the Maintenance folder…" label
                    // sitting behind the global overlay's own "Comparing
                    // against the database…" text, two different messages
                    // on screen for the one thing happening. This branch
                    // now only ever renders while `loadMaintenanceFolderFiles()`
                    // DOESN'T own `isBusy` (see `ownsProgressReporting`'s
                    // own doc comment there) — a cache hit, a genuinely
                    // empty folder, or another action already holding
                    // `isBusy` — so the global overlay and this local label
                    // are never both on screen at once.
                    ProgressView("Reading the Maintenance folder…")
                    Spacer(minLength: 24)
                }
                .frame(maxWidth: .infinity)
            } else if displayedGameNodes.isEmpty {
                gamesEmptyStateMessage
            } else {
                gameTreeTable
            }
            // Same "Show N more" idea as the sidebar tree's own truncation
            // row (`maxTreeChildrenPerCategory`/`treeLoadMoreIncrement`) —
            // see `gamesTableVisibleCap`'s own doc comment for why this
            // exists at all. Only shown once there's actually more beyond
            // the current page.
            if displayedGameNodes.count > gamesTableVisibleCap {
                Button {
                    expandGamesTableVisibleCapIfNeeded()
                } label: {
                    // jensyleo's own request (2026-10-01): "quiero que
                    // coloque el numero total de juegos" — complementing
                    // this row's existing "N left" figure (which only
                    // counts what's still hidden by pagination) with the
                    // actual grand total, so it reads at a glance without
                    // doing the "left + already shown" math yourself.
                    Text("Show \(min(Self.treeLoadMoreIncrement, displayedGameNodes.count - gamesTableVisibleCap)) more (\(displayedGameNodes.count - gamesTableVisibleCap) left) — \(displayedGameNodes.count) total")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
        .onChange(of: selectedDatabaseFilter) { resetGamesTableVisibleCap() }
        .onChange(of: selectedRomFolder) { resetGamesTableVisibleCap() }
        .onChange(of: selectedGameFamilyRootMachineName) {
            resetGamesTableVisibleCap()
            refreshCachedFamilyGameNodes()
        }
    }

    private var gamesListTitle: String {
        let base: String
        // jensyleo's own report (2026-09-14): the Maintenance subfolder's
        // own directory is literally named after the system itself (e.g.
        // "Maintenance/MAME" for a system called "MAME") — this title used
        // to read `selectedRomFolder.lastPathComponent` unconditionally,
        // so browsing it showed the exact same "MAME — Games (N)" title a
        // real system-wide view would, and a donor copy's own genuinely
        // correct status (e.g. a complete `gng.zip` staged as a donor) got
        // mistaken for the REAL collection's own copy of the same game
        // (which can easily still be broken) — a real, confusing bug this
        // makes impossible now.
        if isSelectedFolderMaintenanceSubfolder {
            base = "Maintenance — Games (\(displayedGameNodes.count))"
        } else if let selectedRomFolder {
            base = "\(selectedRomFolder.lastPathComponent) — Games (\(displayedGameNodes.count))"
        } else {
            base = "Games (\(displayedGameNodes.count))"
        }
        guard show1G1ROnly else { return base }
        // jensyleo's own report (2026-08-25): with no toolbar button left
        // to even show the filter is on, a scope where nothing has a
        // recognized-region duplicate (nothing eligible to hide) looked
        // identical to the filter doing nothing at all. Spelling out the
        // count either way — including zero — makes "it's on, and there's
        // just nothing to hide here" distinguishable from "it's not
        // working".
        return base + " · 1G1R hides \(cachedHiddenOneGameOneROMCount)"
    }

    /// Shown instead of a bare empty table whenever `displayedGameNodes` has
    /// nothing to show — jensyleo's own request (2026-09-11): "si cualquier
    /// carpeta esta vacia, debe mostrara un mensaje en la ventana de game."
    /// Started as a special case just for the read-only Maintenance
    /// subfolder (never scanned, so always empty there) but generalizes to
    /// every genuinely empty scope — a real ROM folder with nothing matched
    /// yet, an empty "Database" filter, or no scan having run at all — each
    /// with its own specific wording rather than one generic message that
    /// wouldn't explain WHY nothing's showing.
    private var gamesEmptyStateMessage: some View {
        let text: String
        if isSelectedFolderMaintenanceSubfolder {
            if let maintenanceFolderReadErrorMessage {
                text = "Couldn't read the Maintenance folder: \(maintenanceFolderReadErrorMessage) — check the connection (NAS/pendrive/external drive) and try again."
            } else {
                text = "This is the read-only Maintenance folder — it's currently empty, and never scanned into this system's own audit (donor files only count when \"Find ROMs…\" reads them)."
            }
        } else if let selectedRomFolder {
            text = "\"\(selectedRomFolder.lastPathComponent)\" is empty — no ROMs found here yet."
        } else if viewModel.auditReport == nil {
            text = "Not scanned yet — use \"Scan Folder\" or \"Scan All Folders\" to get started."
        } else if selectedDatabaseFilter != nil {
            text = "No games match this filter."
        } else {
            text = "No games to display."
        }
        return VStack {
            Spacer(minLength: 24)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity)
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

    /// `cachedGameNodes`, narrowed to just a selected parent's own clone
    /// family when `selectedGameFamilyRootMachineName` is set — see that
    /// property's own doc comment. Just returns `cachedFamilyGameNodes`,
    /// kept up to date by `refreshCachedFamilyGameNodes()`.
    ///
    /// jensyleo's own report (2026-08-13): "pasar entre juegos sin clones es
    /// mucho más rápido que cuando sí los tiene" — this used to be a plain
    /// `.filter` over ALL of `cachedGameNodes` (up to ~45,000 rows at "All
    /// games" scale), re-run on every single `body` re-evaluation while a
    /// family was selected (a filter's own review comment, at the time,
    /// judged this "a cost this small" — wrong at that scale: SwiftUI
    /// re-evaluates `body` far more often than once per click). A game with
    /// no clones took neither this filter NOR the `Button.overlay`/gesture
    /// cost at all — `selectedGameFamilyRootMachineName` stays `nil`, so
    /// this whole property was always just handing back the existing array
    /// by reference — which is exactly why only the *clone* case felt slow.
    /// Now a plain, already-computed cache instead, refreshed only when its
    /// real inputs (the selected family or the category/folder's own game
    /// list) actually change.
    private var displayedGameNodes: [GameNode] {
        // jensyleo's own request (2026-09-13): the Maintenance folder must
        // "verse igual que los otros ROM folder... exactamente igual" —
        // same Games table, same Roms detail panel, same columns — while
        // staying true to its own philosophy (never scanned into the real
        // audit, no Fix/write actions, never part of duplicate detection).
        // Reusing the exact same `gameTreeTable`/`selectedRomRows` pipeline
        // with synthetic `GameNode`s (`maintenanceGameNodes`, below) gets
        // the identical look for free, with no separate table/view to keep
        // in sync — `aggregateStatus: nil` on each one reproduces exactly
        // the "Not scanned yet" / dashed-circle look an unscanned catalog
        // row already has, which is the literally correct thing to say
        // here.
        if isSelectedFolderMaintenanceSubfolder { return maintenanceGameNodes }
        guard selectedGameFamilyRootMachineName != nil else { return cachedGameNodes }
        return cachedFamilyGameNodes
    }

    /// Real, colored `GameNode`s for the Maintenance subfolder's own
    /// contents — built by `loadMaintenanceFolderFiles()`'s own independent
    /// `ROMMatcher.match` + `GameNodeBuilder` pass against whichever DAT is
    /// currently loaded (empty until a DAT is loaded, or before the first
    /// load completes). See that function's own doc comment for why this
    /// can never affect the real, official audit.
    @State private var maintenanceGameNodes: [GameNode] = []

    /// jensyleo's own report (2026-09-14): "lo único que se hace es dar
    /// clic en la carpeta de mantenimiento... debe hacer todas las tareas
    /// de visualización [instantáneas] de las otras [carpetas]" — a plain
    /// ROM folder's own row click never re-scans anything; it just shows
    /// `cachedGameNodes`, already computed once. Merely SELECTING the
    /// Maintenance folder (as opposed to genuinely asking to (re)scan it —
    /// "Scan This Folder"/"Scan Maintenance Folder", or a real content
    /// change like deleting its subfolder) shouldn't behave any
    /// differently — this flags "already computed at least once this
    /// session" so the plain-selection call sites below can skip calling
    /// `loadMaintenanceFolderFiles()` again and just show what's already
    /// there, exactly like every other folder already does.
    @State private var hasLoadedMaintenanceFolderFilesOnce = false
    /// jensyleo's own report (2026-09-16), NAS disconnected: the Games
    /// panel said "it's currently empty" for the Maintenance folder when
    /// it genuinely couldn't be READ at all — a real, human-readable
    /// reason a plain "0 files" never conveys. Set alongside
    /// `hasLoadedMaintenanceFolderFilesOnce` in `loadMaintenanceFolderFiles()`'s
    /// own completion; `nil` means the last read succeeded (or none has
    /// run yet).
    @State private var maintenanceFolderReadErrorMessage: String?

    /// Same out-of-order guard `databaseTreeRecomputeGeneration`/
    /// `triggerCachedGameDataRecompute()`'s own generation counters already
    /// use, applied here too — real bug found by code audit (2026-09-14):
    /// two overlapping `loadMaintenanceFolderFiles()` runs (e.g. a fast
    /// double-click on "Scan Maintenance Folder", or switching away from
    /// and back to the Maintenance folder before the first load finished)
    /// had no way to tell an OLDER run's result apart from a newer one —
    /// whichever `Task.detached` happened to finish last always won,
    /// possibly overwriting a newer, more correct result with a stale one.
    @State private var maintenanceFolderFilesLoadGeneration = 0

    /// `maintenanceGameNodes` indexed by `id` — `selectedGameNode`'s own
    /// Maintenance-mode counterpart to `cachedGameNodesByID`.
    private var maintenanceGameNodesByID: [String: GameNode] {
        Self.indexByID(maintenanceGameNodes)
    }

    /// See `displayedGameNodes`'s own doc comment for why this exists.
    /// Recomputed by `refreshCachedFamilyGameNodes()`, called from the same
    /// two `onChange`s that already reset `gamesTableVisibleCap`.
    @State private var cachedFamilyGameNodes: [GameNode] = []

    private func refreshCachedFamilyGameNodes() {
        guard let root = selectedGameFamilyRootMachineName else {
            cachedFamilyGameNodes = []
            return
        }
        cachedFamilyGameNodes = cachedGameNodes.filter { $0.name == root || $0.cloneOf == root }
    }

    /// `displayedGameNodes`, capped to `gamesTableVisibleCap` — see that
    /// property's own doc comment for why. What the `Table` itself actually
    /// renders; `displayedGameNodes.count` (the real, uncapped total) is
    /// still what `gamesListTitle` shows, so the count in the header never
    /// lies about how many games are really in scope.
    private var visibleGameNodes: [GameNode] {
        let all = displayedGameNodes
        guard all.count > gamesTableVisibleCap else { return all }
        return Array(all.prefix(gamesTableVisibleCap))
    }

    private func resetGamesTableVisibleCap() {
        gamesTableVisibleCap = Self.maxTreeChildrenPerCategory
    }

    /// Shared by the manual "Show N more" link and `GameTreeTableView`'s own
    /// `onLastVisibleRowAppeared` — see that closure's own doc comment for
    /// jensyleo's real report (2026-09-30) this exists to fix: reaching the
    /// bottom of the current page used to just stop scrolling dead until
    /// the user moved off the table and clicked the link below it. Guarded
    /// (rather than an unconditional `+=`) since `onLastVisibleRowAppeared`
    /// can fire for a page that's already complete (e.g. the very last, no
    /// longer full page) — nothing to expand there, and bumping the cap
    /// anyway would just make `visibleGameNodes` silently drift ahead of
    /// the real total for no reason.
    private func expandGamesTableVisibleCapIfNeeded() {
        guard displayedGameNodes.count > gamesTableVisibleCap else { return }
        gamesTableVisibleCap += Self.treeLoadMoreIncrement
    }

    /// Thin wrapper handing every piece of state/behavior `GameTreeTableView`
    /// needs down as params/bindings/closures -- see that struct's own doc
    /// comment (`GameTreeTableView.swift`) for why this is its own `View`
    /// now instead of a plain computed property directly on this struct.
    private var gameTreeTableContent: some View {
        GameTreeTableView(
            visibleGameNodes: visibleGameNodes,
            cachedGameNodes: cachedGameNodes,
            cachedGameNodesByID: cachedGameNodesByID,
            cachedOneGameOneROMSummary: cachedOneGameOneROMSummary,
            viewModel: viewModel,
            system: system,
            selection: $selectedGameIDs,
            columnCustomizationOverride: $gameColumnCustomizationOverride,
            persistColumnCustomization: { Self.persist($0, key: Self.gameColumnCustomizationKey) },
            // jensyleo's own suggestion (2026-09-15), after the shared
            // event-monitor fix still wasn't enough on its own: clear the
            // Roms panel's own selection outright on EVERY click here, not
            // only when `selectedGameID`'s own VALUE happens to change
            // (the existing `.onChange(of: selectedGameID) { selectedRomID
            // = nil }` a few hundred lines up misses a same-game reclick).
            // With nothing left selected in Roms, there's no ambiguity for
            // the user to notice even in whatever edge case still slips
            // past `activeResultsPane` itself.
            onFocusRequested: {
                activeResultsPane = .games
                resultsPaneIsActive = true
                selectedRomIDs = []
                // See `lastGamesClickID`'s own doc comment — only a
                // same-game reclick needs the extra bump; a genuine game
                // change already gets a fresh Roms `.id()` for free.
                if selectedGameID == lastGamesClickID {
                    romsResetGeneration += 1
                }
                lastGamesClickID = selectedGameID
            },
            gameStatusIcon: { AnyView(gameStatusIcon(for: $0)) },
            infoText: { infoText(for: $0) },
            zipCommentHelpText: { zipCommentHelpText(for: $0) },
            totalSizeText: { totalSizeText(for: $0) },
            gameDescription: { gameDescription(forMachineName: $0) },
            familyIndicator: { AnyView(familyIndicator(for: $0)) },
            dependenciesIndicator: { AnyView(dependenciesIndicator(for: $0)) },
            detailsIndicator: { AnyView(detailsIndicator(for: $0)) },
            scanFile: scanFile,
            canScanFile: canScanFile,
            launchInMAME: launchInEmulator,
            canLaunchMAME: canLaunchInEmulator,
            revealInFinder: revealInFinder,
            actualFileURL: { actualFileURL(for: $0) },
            startMoveToTrash: startMoveToTrash,
            startDeleteFilesPermanently: startDeleteFilesPermanently,
            startCopyFilesToFolder: startCopyFilesToFolder,
            startMoveFilesToFolder: startMoveFilesToFolder,
            startDuplicateFiles: startDuplicateFiles,
            startCompressFiles: startCompressFiles,
            fixMismatchedFile: fixMismatchedFile,
            startContextMenuRenameRomsInArchive: { startContextMenuRenameRomsInArchive($0) },
            startContextMenuRemoveUselessFiles: startContextMenuRemoveUselessFiles,
            startContextMenuRemoveZipComments: startContextMenuRemoveZipComments,
            startContextMenuRemoveRedundantFiles: startContextMenuRemoveRedundantFiles,
            startContextMenuRemoveRedundantRoms: startContextMenuRemoveRedundantRoms,
            startRepairFromMaintenanceFolder: { startRepairFromMaintenanceFolder(scopeFolders: $0, skipConfirmation: true) },
            onLastVisibleRowAppeared: expandGamesTableVisibleCapIfNeeded,
            renameToSimilarNameSuggestion: startRenameToSimilarNameSuggestion
        )
        // Real bug found live by jensyleo (2026-09-23): "Remove Zip
        // Comment(s)…" (unlike every other Fix/File Action) never visibly
        // refreshed the Games table afterward — the comment genuinely IS
        // gone on disk (confirmed by a fresh manual rescan reporting no
        // comment), `zipCommentCache` genuinely IS invalidated
        // (`.onChange(of: viewModel.auditReport)` above), and
        // `cachedGameNodes` genuinely IS reassigned to a fresh array — none
        // of that is enough here specifically because a zip comment is the
        // ONLY thing this whole app displays that lives entirely OUTSIDE
        // `AuditEntry`/`GameNode`'s own data (a lazy, on-demand disk read
        // purely for display, see `ZipCommentCache`'s own doc comment) —
        // every OTHER action that visibly refreshes changes some REAL field
        // on the row's own `GameNode` (status, name, whatever), which is
        // what actually gives `Table` a reason to redraw that row's cell.
        // `GameNode` isn't `Equatable` and Table's own AppKit-backed
        // diffing has no way to know THIS row's content changed when
        // nothing about its own data did — reassigning `cachedGameNodes`
        // isn't sufficient by itself. `.id(...)` forces this whole Table to
        // be genuinely torn down and rebuilt (selection is preserved, it's
        // a `Binding` owned by the parent, not local state — only the
        // Table's own internal state, like scroll position, resets), which
        // is the one thing guaranteed to make every cell actually
        // re-evaluate `infoText`/`zipCommentHelpText` fresh. Deliberately
        // NOT bumped on every ordinary scan (that would throw away scroll
        // position on every single Fix action) — only these two zip-comment
        // actions ever touch `zipCommentTableReloadToken`, since they're
        // the only ones with this exact "the data Table can see didn't
        // change, but what's on screen must" problem.
        .id(zipCommentTableReloadToken)
    }

    /// See `gameTreeTableContent`'s own `.id(...)` doc comment just above.
    @State private var zipCommentTableReloadToken = 0

    /// Moves the Games table's own selection to the previous/next visible
    /// row — jensyleo's own report (2026-09-15), right after the macOS
    /// 27.0 update: `Table`'s own NATIVE up/down arrow-key row navigation
    /// (the thing `handleTypeAheadKeyPress`'s own doc comment always
    /// assumed would just keep working) stopped working entirely — a
    /// press didn't merely do nothing, it cleared the selection outright.
    /// Root cause: simply having ANY `.onKeyPress` modifier attached
    /// anywhere on a `Table` view now appears to disable that Table's own
    /// built-in arrow-key handling on macOS 27, even when that handler
    /// itself returns `.ignored` for arrow keys (confirmed live, via a
    /// debug build + `System Events key code` — see
    /// `romFolderSectionPane`'s own `.focusable()` doc comment for why
    /// that's the one synthetic-input method that reliably drives
    /// `.onKeyPress` for testing). Rather than depend on a platform
    /// behavior that's now unreliable, this reimplements the navigation
    /// directly — same "flatten the visible rows, find the current index,
    /// move within bounds" shape `moveDatabaseSelection(by:scope:)` already
    /// uses for the sidebar.
    /// Scrolls the Games `Table` to reveal `id`, expanding `gamesTableVisibleCap`
    /// first (deferring the actual scroll one run-loop tick) whenever `id`
    /// sits past the current "Show N more" page — jensyleo's own report
    /// (2026-09-29): clicking a Database game with no clone family now
    /// correctly selects it (see this session's removal of the old
    /// name-only view), but if that game wasn't already within the
    /// current page, nothing visibly scrolled to it — same
    /// `ScrollViewReader.scrollTo` timing gap already fixed for arrow
    /// keys/Page Up-Down/type-ahead in `moveGameSelection(by:)`'s own doc
    /// comment, just centralized here for the two click-driven call sites
    /// (`moveDatabaseSelection(by:scope:)`'s `.game` case, and the sidebar
    /// tree leaf's own tap gesture) that select by id rather than by an
    /// offset from the current selection.
    private func revealAndScrollGamesTable(to id: String) {
        let capNeedsExpansion: Bool
        if let index = displayedGameNodes.firstIndex(where: { $0.id == id }), index >= gamesTableVisibleCap {
            gamesTableVisibleCap = index + 1
            capNeedsExpansion = true
        } else {
            capNeedsExpansion = false
        }
        if capNeedsExpansion {
            DispatchQueue.main.async { [self] in gameTableScrollProxy?.scrollTo(id, anchor: nil) }
        } else {
            gameTableScrollProxy?.scrollTo(id, anchor: nil)
        }
    }

    private func moveGameSelection(by offset: Int) {
        // `displayedGameNodes`, not `visibleGameNodes` — jensyleo's own
        // report (2026-09-29), a large ROM folder (NO_INTRO, 1,776 games):
        // arrow keys (and Page Up/Down, and type-ahead below) all used to
        // clamp to whatever "Show N more" page happened to be currently
        // revealed, so reaching row 201 meant manually clicking "Show
        // more" first — the keyboard alone could never get there. Moving
        // against the FULL list and bumping `gamesTableVisibleCap` to
        // cover the target row (below) fixes all three at once, since
        // Page Up/Down and type-ahead both funnel through this same
        // function/its own cap-expansion pattern.
        let rows = displayedGameNodes
        guard !rows.isEmpty else { return }
        let currentIndex = selectedGameID.flatMap { id in rows.firstIndex { $0.id == id } }
        let newIndex: Int
        if let currentIndex {
            newIndex = max(0, min(rows.count - 1, currentIndex + offset))
        } else {
            // Nothing selected yet — land on an edge row, matching
            // `moveDatabaseSelection(by:scope:)`'s own convention.
            newIndex = offset < 0 ? rows.count - 1 : 0
        }
        let capNeedsExpansion = newIndex >= gamesTableVisibleCap
        if capNeedsExpansion {
            gamesTableVisibleCap = newIndex + 1
        }
        let newID = rows[newIndex].id
        selectedGameID = newID
        // `anchor: nil` (not `.center`) — jensyleo's own report (2026-09-29):
        // a `Table` scrolls both axes, so re-centering on every arrow key
        // press was also re-centering the *horizontal* scroll position,
        // dragging the view toward the right on each key press. `nil`
        // scrolls the minimum needed to bring the row into view instead of
        // jumping to a fixed point, so the horizontal offset is left alone.
        //
        // Deferred one run-loop tick ONLY when the cap juust changed —
        // jensyleo's own report (2026-09-29), past row ~2,100 in a huge ROM
        // folder: Page Down kept moving the real selection (every
        // subsequent press correctly built on the new index), but the
        // Table visibly stopped following it. Classic `ScrollViewReader
        // .scrollTo` timing gap, same one already documented on
        // `scrollDatabaseListToSelectedGameIfNewlyVisible()`'s own doc
        // comment: calling `scrollTo` in the SAME synchronous pass that
        // just bumped `gamesTableVisibleCap` targets a row the `Table`
        // hasn't actually laid out yet (SwiftUI batches the view update),
        // so it's silently a no-op — nothing wrong with the selection
        // itself, just nothing for `scrollTo` to find yet. No gap exists
        // (and no need to defer) when the target row was already within
        // the current page.
        if capNeedsExpansion {
            DispatchQueue.main.async {
                gameTableScrollProxy?.scrollTo(newID, anchor: nil)
            }
        } else {
            gameTableScrollProxy?.scrollTo(newID, anchor: nil)
        }
    }

    /// Matches `event` against the classic type-ahead pattern (see
    /// `typeAheadBuffer`'s own doc comment): only a single, printable,
    /// non-modified character is handled here — everything else (return,
    /// delete, ⌘-anything) is left untouched (returns `false`, and the
    /// shared monitor calling this passes the event straight through).
    ///
    /// Called from `installResultsArrowKeyMonitor`'s own raw `NSEvent`
    /// monitor, NOT a SwiftUI `.onKeyPress` on the Table — jensyleo's own
    /// report (2026-09-29): typed letters kept landing in the sidebar's
    /// "Search games…" field instead of jumping to a game here, no matter
    /// where he'd just clicked. Same root cause as the arrow-key/Page Up-
    /// Down fixes right above this one in that monitor: real AppKit
    /// key-window focus apparently never reliably transfers TO this
    /// `Table` on macOS 27, so a plain `.onKeyPress` (which only fires for
    /// whatever view genuinely holds that focus) simply never ran —
    /// whatever real text field last had focus kept eating every
    /// keystroke instead. Routing through the monitor (which intercepts
    /// events regardless of which view "really" has focus, exactly like
    /// arrow keys already do) fixes this the same way.
    private func handleGamesTypeAheadKeyDown(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let characters = event.charactersIgnoringModifiers, let character = characters.first, characters.count == 1,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol else {
            return false
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
            return true
        }
        selectedGameID = match.id
        // Reveals enough of `displayedGameNodes`'s own "Show N more" page
        // to actually include the match before scrolling to it — jensyleo's
        // own report (2026-09-29): typing used to silently do nothing once
        // the match sat past whatever page was currently revealed (a real
        // risk in a 1,776-game ROM folder), since `scrollTo` has nothing to
        // scroll to for an id the Table hasn't even rendered yet. Same fix
        // as `moveGameSelection(by:)`'s own cap-expansion, just keyed off
        // where the match actually lands rather than an arrow-key offset.
        let matchIndex = displayedGameNodes.firstIndex(where: { $0.id == match.id })
        let capNeedsExpansion = (matchIndex ?? 0) >= gamesTableVisibleCap
        if let matchIndex, capNeedsExpansion {
            gamesTableVisibleCap = matchIndex + 1
        }
        // No `withAnimation` — jensyleo's own request (2026-08-13):
        // animated transitions aren't wanted anywhere in this app, this
        // type-ahead scroll included.
        //
        // Deferred one run-loop tick when the cap just changed — same
        // `ScrollViewReader.scrollTo` timing gap as `moveGameSelection(by:)`'s
        // own identical fix; see that one's doc comment.
        if capNeedsExpansion {
            DispatchQueue.main.async {
                gameTableScrollProxy?.scrollTo(match.id, anchor: nil)
            }
        } else {
            gameTableScrollProxy?.scrollTo(match.id, anchor: nil)
        }
        return true
    }

    /// jensyleo's own request (2026-07-28): scanning used to only ever
    /// cover a whole folder (all of "Rom files", or one folder scoped via
    /// "Scan Folder") — no way to force a re-read of one specific archive
    /// without re-reading everything alongside it. `actualFileURL(for:)` is
    /// the real physical file on disk this game's roms actually live in (the
    /// same one `actualFileName`/`totalSizeText` already derive from), fed
    /// straight into `startScan`'s `folders:` parameter.
    ///
    /// As of 2026-08-06 that parameter no longer scopes what gets *matched*
    /// — every scan matches every folder, so cross-folder duplicates are
    /// always visible (see `LibraryViewModel.scan`'s own doc comment for the
    /// reasoning and the measurements). It now only forces these paths to be
    /// genuinely rehashed rather than served from `ScanCache`, which is
    /// exactly what "rescan *this* file" should mean.
    private func actualFileURL(for node: GameNode) -> URL? {
        // Real bug found live by jensyleo (2026-09-22): for a game
        // genuinely duplicated across two ROM folders (e.g. `kod.zip` in
        // both "OTHER" and "CPS1"), `node.firstOwnedFileURL` always
        // resolves to whichever COPY currently wins the primary/duplicate
        // tie-break (see `ROMMatcher.primaryArchiveIndices`'s own doc
        // comment) — system-wide, regardless of which folder's row the
        // user is actually looking at. Right-clicking "kod.zip" while
        // browsing the LOSING folder ("OTHER", showing "Duplicated
        // archive…") then resolved to the WINNING folder's physical file
        // instead ("CPS1") — "File Actions" either silently acted on the
        // wrong file or (since that entry doesn't even show under this
        // folder's own scope) appeared to offer nothing at all. When a
        // specific ROM folder is selected, prefer whichever of this
        // node's own genuinely-owned entries (same `.foundElsewhere`/
        // `requiredByGameDescription` exclusion `firstOwnedFileURL` itself
        // applies) is physically inside THAT folder — the file the user
        // is actually looking at — before falling back to the system-wide
        // pick for the unscoped ("Database") view, where there's no
        // single folder to prefer.
        if let selectedRomFolder {
            // Only `foundElsewhereArchiveName` means a genuinely BORROWED
            // path (some OTHER archive's own location) — a
            // `requiredByGameDescription`-flagged surplus entry's `path`
            // is always its own real, physical location (the exact file
            // `ROMMatcher` found unclaimed), never borrowed, even when
            // it's folded into another game's row or the game it names
            // has no real copy anywhere — see `SurplusFile`'s own
            // construction: `file.file.url` is always where the actual
            // bytes sit. Safe to include here, unlike `firstOwnedFileURL`'s
            // own stricter exclusion (which exists for a different reason
            // — never presenting a "not needed here" rom as this node's
            // canonical archive when a REAL, unambiguous owned one exists
            // too, not because the path itself is untrustworthy).
            let folderPath = selectedRomFolder.path
            if let scoped = node.entries.first(where: { entry in
                guard let path = entry.path, entry.foundElsewhereArchiveName == nil else { return false }
                return path.path.hasPrefix(folderPath)
            })?.path {
                return scoped
            }
        }
        return node.firstOwnedFileURL
    }

    /// `node.infoText` with the game's own archive comment appended, same
    /// wording/behavior as `infoText(for entry: AuditEntry)`'s own zip
    /// comment suffix below — jensyleo's own follow-up (2026-09-11), after
    /// deciding a dedicated "has a zip comment" column wasn't worth it for
    /// a single boolean: reuses the SAME `ZipCommentCache`/`ZipCommentReader`
    /// already built for the Roms panel (2026-07-30) instead of adding any
    /// new detection. Looked up via `node.actualFileName` (the
    /// majority-vote-verified archive name — see its own doc comment for
    /// why this is safer than just taking any entry's `path`) rather than
    /// `actualFileURL(for:)` above, which can point at a stray borrowed
    /// path for a game with no rom of its own actually present.
    private func infoText(for node: GameNode) -> String {
        var base = node.infoText
        // `SimilarNameSuggester`'s own live preview — jensyleo's own
        // request (2026-09-29): this used to show only in the Roms panel
        // (the rightmost table/detail entry), never in the Games panel
        // (this one) — confusing for a system like NES where a zip holds
        // exactly one rom and both always share the DAT's own single
        // declared name, so there's really only one "Possible match" to
        // show either way. Reuses the exact same live lookup
        // `infoText(for entry:)` already does, keyed off any one of this
        // node's own entries (a surplus/unknown row has exactly one for a
        // single-rom system like this).
        if let path = node.entries.first?.path, let suggestion = viewModel.similarNameSuggestion(forFileAt: path) {
            base += " — Possible match: \(suggestion.suggestedName) (\(Int((suggestion.confidence * 100).rounded()))%)"
        }
        // jensyleo's own request (2026-09-14), applied everywhere this
        // exact "append the archive's own ZIP comment" pattern is used —
        // see `infoText(for entry:)`'s own doc comment for why the raw
        // text moved to a tooltip instead of appearing inline here.
        if let name = node.actualFileName,
           let url = node.entries.first(where: { $0.path?.lastPathComponent == name })?.path,
           url.pathExtension.lowercased() == "zip",
           let comment = zipCommentCache.comment(forZipAt: url), !comment.isEmpty {
            base += " — Has ZIP comment"
        }
        // jensyleo's own request (2026-10-01), per-system opt-in (Settings
        // → Systems → Consoles → "Region-quality hints") — see
        // `RegionQualityNote`'s own doc comment for why this is hand-curated
        // rather than DAT-derived. Two states: this node's own region tag
        // already matches the curated recommendation (a quiet star, nothing
        // actionable), or it doesn't (an info glyph naming which region is
        // actually recommended) — the full reason/source lives in the
        // tooltip (`zipCommentHelpText(for node:)` below), not inline, same
        // "keep the column readable" rule the zip-comment suffix already
        // follows.
        if let note = regionQualityNote(for: node) {
            let ownRegion = GameNameTagParser.parse(name: node.name).region
            base += ownRegion == note.recommendedRegion ? " — ⭐ Recommended version" : " — ℹ️ Better version exists (\(note.recommendedRegion))"
        }
        return base
    }

    /// Per-system opt-in gate for the region-quality hint — see
    /// `RomSystem.regionQualityHintsEnabled`'s own doc comment. Shared by
    /// both the `GameNode` (Games panel) and `AuditEntry` (Roms panel)
    /// call sites below — real gap found live by jensyleo (2026-10-01,
    /// "revisa de nuevo que no se te escape nada"): the feature only
    /// covered the Games panel at first, the Roms panel's own `infoText`/
    /// `zipCommentHelpText(for entry:)` never got the same treatment.
    private func regionQualityNote(forGameName name: String) -> RegionQualityNote? {
        guard system.regionQualityHintsEnabled else { return nil }
        return RegionQualityNotes.note(forGameName: name)
    }

    private func regionQualityNote(for node: GameNode) -> RegionQualityNote? {
        regionQualityNote(forGameName: node.name)
    }

    /// The `GameNode` counterpart to `zipCommentHelpText(for entry:)` —
    /// same reasoning, same tooltip-on-hover fallback for the real text.
    /// Also carries the full region-quality reason/source when one applies
    /// — the inline suffix (`infoText(for node:)` above) only ever shows a
    /// short glyph, the actual explanation only shows on hover.
    private func zipCommentHelpText(for node: GameNode) -> String {
        var parts: [String] = []
        if let name = node.actualFileName,
           let url = node.entries.first(where: { $0.path?.lastPathComponent == name })?.path,
           url.pathExtension.lowercased() == "zip",
           let comment = zipCommentCache.comment(forZipAt: url), !comment.isEmpty {
            parts.append(comment)
        }
        if let note = regionQualityNote(for: node) {
            parts.append("\(note.recommendedRegion) recommended: \(note.reason) (\(note.sourceURL))")
        }
        return parts.joined(separator: "\n")
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

    /// jensyleo's own request (2026-09-11): `canScanFile`/`actualFileURL`
    /// only ever disable this action for a rom with NO recorded path at
    /// all (genuinely Missing since its last scan) — a rom whose path WAS
    /// recorded but got deleted or moved externally, outside ROMForge,
    /// since that last scan still passes that check (the cached path is
    /// non-nil) and only reveals it's gone once the whole rescan quietly
    /// completes and the row flips to Missing on its own. A live
    /// existence check right here, before ever starting that rescan,
    /// surfaces it immediately and explicitly instead.
    private func scanFile(_ node: GameNode) {
        guard let url = actualFileURL(for: node) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else {
            viewModel.logError("File not found: \(url.path)")
            return
        }
        viewModel.startScan(system: system, folders: [url])
    }

    /// Presentation-only "Family" column cell — purely informational, never
    /// an `AuditStatus`/severity of its own (see `AuditStatusTint` for the
    /// precedent of a distinct, non-severity tint, `.duplicateSet`'s blue).
    /// A parent row shows how much of its own clone family is present
    /// ("3/5 clones"); a clone row whose declared parent is absent gets a
    /// small amber warning instead — the two never both apply to the same
    /// row (a row is either a parent or a clone, per the DAT's own
    /// `cloneof`), so at most one of these ever renders.
    @ViewBuilder
    private func familyIndicator(for node: GameNode) -> some View {
        if node.isSurplusBucket || node.isDiskRow {
            EmptyView()
        } else if let completion = cachedParentCloneSummary.cloneCompletionByParent[node.name] {
            Text("\(completion.present)/\(completion.total) clones")
                .font(.caption)
                .foregroundStyle(completion.present == completion.total ? .secondary : Color.orange)
        } else if cachedParentCloneSummary.clonesMissingParent.contains(node.name) {
            Label("Parent missing", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.iconOnly)
                .foregroundStyle(.orange)
                .help("This clone is present, but its parent set (\(node.cloneOf)) is missing from the collection.")
        } else {
            EmptyView()
        }
    }

    /// Short chips for each of `node.dependencyBadges` (BIOS/CHD/Hardware/
    /// Samples) that's both non-empty and still enabled under Settings →
    /// View Options → "Dependencies column" (`DependencyColumnSettings`).
    /// The chip shows only the category word — the real BIOS/CHD/hardware
    /// names go in `.help` (a prior session inlined them into the label
    /// itself and jensyleo reverted it the same day: with `deviceRefNames`
    /// routinely holding half a dozen names, that made the column wrap
    /// across several lines for exactly the games this feature most needs
    /// to help with).
    ///
    /// Each category gets its own subtle background tint instead of a
    /// generic gray capsule, so the chip itself hints "there's more here,
    /// grouped by kind" without adding any visible text or icon: color is
    /// something the eye picks up before it consciously reads the tooltip
    /// affordance, and macOS/SwiftUI already leans on semantic tint colors
    /// elsewhere in this app (e.g. status colors) rather than icons for
    /// this kind of hint.
    @ViewBuilder
    private func dependenciesIndicator(for node: GameNode) -> some View {
        let badges = visibleDependencyBadges(for: node)
        if badges.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(badges) { badge in dependencyChip(for: badge) }
            }
        }
    }

    /// `node.dependencyBadges` filtered down to the categories Settings →
    /// View Options → Dependencies still has switched on — the single
    /// source of truth shared by both the Games table's "Dependencies"
    /// column (`dependenciesIndicator`, above) and the Detail panel's own
    /// "Dependencies" row (`dependenciesDetailRow`, below). jensyleo's own
    /// correction (2026-08-27): the Detail panel first shipped with its
    /// own separate CHD/Samples/Required BIOS/Device refs toggles, which
    /// only confused things — two differently-named settings governing
    /// what looked like the same information in two different places.
    private func visibleDependencyBadges(for node: GameNode) -> [DependencyBadge] {
        node.dependencyBadges.filter { badge in
            switch badge.kind {
            case .bios: return showBiosBadge
            case .chd: return showCHDBadge
            case .hardware: return showHardwareBadge
            case .samples: return showSamplesBadge
            }
        }
    }

    /// The Detail panel's own "Dependencies" row — same badges, same
    /// filtering (`visibleDependencyBadges`) as `dependenciesIndicator`
    /// (the Games table's own "Dependencies" column, unchanged — jensyleo's
    /// own instruction, 2026-08-27: "en el panel... ya estaba, déjalo como
    /// está"), but printed as plain, already-expanded text instead of
    /// hover-tooltip chips. A table cell has no better option than a
    /// tooltip (there's no room for the real names inline — see
    /// `DependencyBadge`'s own doc comment on why `label` is bare), but the
    /// Detail panel has a whole line to itself, so "Dependencies debe
    /// mostrarse sin necesidad del tooltip" (jensyleo's own request) is
    /// just `badge.tooltip` printed directly rather than hidden behind
    /// `.help(_:)`.
    @ViewBuilder
    private func dependenciesDetailRow(_ node: GameNode) -> some View {
        let badges = visibleDependencyBadges(for: node)
        if !badges.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("Dependencies").bold().frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(badges) { badge in dependencyDetailLines(for: badge) }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// One badge's own lines within `dependenciesDetailRow` — jensyleo's
    /// own follow-up: "Hardware" (the one badge whose `tooltip` is itself
    /// multi-line — `CPU:`/`Sound:`/`Other:`, see `GameDependencies
    /// .hardwareTooltip`) used to read as `"Hardware: CPU: …"` glued to the
    /// first sub-line, burying the category name instead of heading its
    /// own details. A multi-line tooltip now gets its own bolded label
    /// line, with the sub-lines beneath it; a single-line tooltip (BIOS,
    /// CHD) keeps the compact "Label: value" this always used, and Samples
    /// (an empty tooltip) still just prints its bare label.
    @ViewBuilder
    private func dependencyDetailLines(for badge: DependencyBadge) -> some View {
        if badge.tooltip.isEmpty {
            Text(badge.label)
        } else if badge.tooltip.contains("\n") {
            VStack(alignment: .leading, spacing: 1) {
                Text(badge.label).fontWeight(.semibold)
                Text(badge.tooltip)
            }
        } else {
            Text("\(badge.label): \(badge.tooltip)")
        }
    }

    /// One chip for a single `DependencyBadge`. An empty `tooltip` (the
    /// Samples badge, which has nothing beyond its own label to say) skips
    /// `.help(_:)` entirely rather than attaching a tooltip that would just
    /// repeat the visible chip text.
    @ViewBuilder
    private func dependencyChip(for badge: DependencyBadge) -> some View {
        let chip = Text(badge.label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(badgeTint(for: badge.kind).opacity(0.18), in: Capsule())
        if badge.tooltip.isEmpty {
            chip
        } else {
            chip.help(badge.tooltip)
        }
    }

    /// One accent per dependency category, purely a visual grouping cue —
    /// arbitrary beyond "distinct and not already meaningful elsewhere in
    /// this table" (this app's status colors already own red/orange/green
    /// as pass/fail signals, so those are avoided here for anything but
    /// Samples, which has no failure state of its own to be confused with).
    private func badgeTint(for kind: DependencyBadge.Kind) -> Color {
        switch kind {
        case .bios: return .blue
        case .chd: return .purple
        case .hardware: return .indigo
        case .samples: return .teal
        }
    }

    // MARK: - "Details" column/row (descriptive metadata, separate from "Dependencies")

    /// Short chips for each of `node.detailBadges` (Emulation/Display/
    /// Players) that's both non-empty and still enabled under Settings →
    /// View Options → "Details" (`DetailColumnSettings`) — exact mirror of
    /// `dependenciesIndicator` above, for the separate "Details" column.
    @ViewBuilder
    private func detailsIndicator(for node: GameNode) -> some View {
        let badges = visibleDetailBadges(for: node)
        if badges.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(badges) { badge in detailChip(for: badge) }
            }
        }
    }

    /// `node.detailBadges` filtered down to the categories Settings → View
    /// Options → Details still has switched on — the single source of truth
    /// shared by both the Games table's "Details" column
    /// (`detailsIndicator`, above) and the Detail panel's own "Details" row
    /// (`detailsDetailRow`, below) — mirrors `visibleDependencyBadges`.
    private func visibleDetailBadges(for node: GameNode) -> [DetailBadge] {
        node.detailBadges.filter { badge in
            switch badge.kind {
            case .driverStatus: return showDriverStatusBadge
            case .display: return showDisplayBadge
            case .players: return showPlayersBadge
            }
        }
    }

    /// The Detail panel's own "Details" row — same badges, same filtering
    /// (`visibleDetailBadges`) as `detailsIndicator`, printed as plain,
    /// already-expanded text — exact mirror of `dependenciesDetailRow`.
    @ViewBuilder
    private func detailsDetailRow(_ node: GameNode) -> some View {
        let badges = visibleDetailBadges(for: node)
        if !badges.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Text("Details").bold().frame(width: 100, alignment: .leading)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(badges) { badge in detailDetailLines(for: badge) }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// One badge's own line(s) within `detailsDetailRow` — mirrors
    /// `dependencyDetailLines`. None of these badges' tooltips are
    /// currently multi-line (unlike "Hardware"'s CPU:/Sound:/Other:), but
    /// the same multi-line handling is kept for consistency should a future
    /// badge (e.g. controls) need it.
    @ViewBuilder
    private func detailDetailLines(for badge: DetailBadge) -> some View {
        if badge.tooltip.isEmpty {
            Text(badge.label)
        } else if badge.tooltip.contains("\n") {
            VStack(alignment: .leading, spacing: 1) {
                Text(badge.label).fontWeight(.semibold)
                Text(badge.tooltip)
            }
        } else {
            Text("\(badge.label): \(badge.tooltip)")
        }
    }

    /// One chip for a single `DetailBadge` — mirrors `dependencyChip`.
    @ViewBuilder
    private func detailChip(for badge: DetailBadge) -> some View {
        let chip = Text(badge.label)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(detailBadgeTint(for: badge.kind).opacity(0.18), in: Capsule())
        if badge.tooltip.isEmpty {
            chip
        } else {
            chip.help(badge.tooltip)
        }
    }

    /// One accent per detail category — distinct from every
    /// `badgeTint(for:)` color above (blue/purple/indigo/teal already used
    /// by "Dependencies") and from this app's own red/orange/green status
    /// colors, same reasoning as `badgeTint(for:)`.
    private func detailBadgeTint(for kind: DetailBadge.Kind) -> Color {
        switch kind {
        case .driverStatus: return .brown
        case .display: return .cyan
        case .players: return .mint
        }
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

    /// Thin wrapper handing every piece of state/behavior `RomsTableView`
    /// needs down as params/bindings/closures -- see that struct's own doc
    /// comment (`RomsTableView.swift`) for why this is its own `View` now
    /// instead of a plain computed property directly on this struct.
    private var romsList: some View {
        RomsTableView(
            selectedGameNode: selectedGameNode,
            selectedRomRows: selectedRomRows,
            viewModel: viewModel,
            selection: $selectedRomIDs,
            columnCustomizationOverride: $romColumnCustomizationOverride,
            persistColumnCustomization: { Self.persist($0, key: Self.romColumnCustomizationKey) },
            romCell: { content, entry in AnyView(romCell(content, entry: entry)) },
            romStatusIcon: { AnyView(romStatusIcon(for: $0)) },
            romNameText: { romNameText(for: $0) },
            infoText: { infoText(for: $0) },
            zipCommentHelpText: { zipCommentHelpText(for: $0) },
            sizeText: { sizeText(for: $0) },
            dumpStatusText: { dumpStatusText(for: $0) },
            entryKindText: { entryKindText(for: $0) },
            startContextMenuRenameRomsInArchive: { startContextMenuRenameRomsInArchive($0, entryKeys: $1) },
            startContextMenuRemoveRedundantRoms: startContextMenuRemoveRedundantRoms,
            startRepairFromMaintenanceFolder: { startRepairFromMaintenanceFolder(scopeFolders: $0, skipConfirmation: true) },
            romEntryActionsMenuItems: { AnyView(romEntryActionsMenuItems(for: $0)) },
            onFocusRequested: { activeResultsPane = .roms; resultsPaneIsActive = true }
        )
        // jensyleo's own report (2026-09-16): setting `selectedRomIDs = []`
        // programmatically (both the pre-existing `.onChange(of:
        // selectedGameID)` and the new explicit clear in `GameTreeTableView`'s
        // own `onFocusRequested`) never visibly cleared this Table's own
        // row highlight on macOS 27 — the same category of bug already
        // found this session where `Table` doesn't reliably react to
        // programmatic state changes the way it does to a direct user
        // click. `.id(selectedGameNode?.id)` forces SwiftUI to tear down
        // and rebuild this ENTIRE Table (not just update its `selection`
        // binding) every time the selected game changes, which resets its
        // internal selection unconditionally — a heavier hammer, but one
        // that doesn't depend on the Table's own binding-driven refresh
        // working correctly.
        .id("\(selectedGameNode?.id ?? "none")#\(romsResetGeneration)")
    }

    /// Factored out of the Roms panel's own `.contextMenu` closure just
    /// above — jensyleo's own request (2026-09-13): "ahí debería permitir
    /// estén o no estén bien, todas las opciones del file actions...
    /// obviamente ahí hay que tener en cuenta que el archivo está
    /// comprimido, por ende también debe tener acciones de descompresión
    /// como Extract file" — unlike "Fix This Misnamed ROM…" above, these
    /// three never depend on a rom's own DAT status
    /// (Correct/Bad/Unknown/Missing), only on there being a real file to
    /// act on at all (`row.entry.path` is nil for a genuinely `.missing`
    /// rom — nothing on disk to extract/trash/delete). `isArchived` mirrors
    /// Core's own `isZipEntry` check (`file.url.lastPathComponent !=
    /// file.name`): a `.zip` entry's own `path` is its CONTAINING archive,
    /// never the entry itself. A separate `@ViewBuilder` function, not
    /// inlined into the `.contextMenu` closure — the combined type-checker
    /// load of everything already in that closure plus this pushed a
    /// `SwiftCompile` past Xcode's own reasonable-time limit.
    @ViewBuilder
    private func romEntryActionsMenuItems(for selectedRows: [RomRow]) -> some View {
        let romEntryTargets: [LibraryViewModel.RomEntryTarget] = selectedRows.compactMap { row in
            guard let path = row.entry.path, let entryName = row.entry.actualEntryName else { return nil }
            return LibraryViewModel.RomEntryTarget(url: path, entryName: entryName, isArchived: path.lastPathComponent != entryName)
        }
        if !romEntryTargets.isEmpty {
            Divider()
            if romEntryTargets.contains(where: \.isArchived) {
                Button {
                    startExtractRomEntries(romEntryTargets)
                } label: {
                    Label(romEntryTargets.count == 1 ? "Extract to Folder…" : "Extract \(romEntryTargets.count) Roms to Folder…", systemImage: "arrow.up.doc")
                }
                .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
            }
            Button {
                startMoveRomEntriesToTrash(romEntryTargets)
            } label: {
                Label(romEntryTargets.count == 1 ? "Move to Trash…" : "Move \(romEntryTargets.count) Roms to Trash…", systemImage: "trash")
            }
            .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
            Button {
                startDeleteRomEntriesPermanently(romEntryTargets)
            } label: {
                Label(romEntryTargets.count == 1 ? "Delete Permanently…" : "Delete \(romEntryTargets.count) Roms Permanently…", systemImage: "trash.fill")
            }
            .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
        }
    }

    /// Selects `url` in a new Finder window — `NSWorkspace`'s own
    /// convention for "show me exactly this file", same as Finder's own
    /// "Reveal in Finder" menu item.
    private func revealInFinder(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Wraps a cell in the row's status tint (a lighter background than the
    /// status icon color), RomCenter-style — green/yellow/red/gray rows at a
    /// glance instead of only the leading icon. Uses `entry.status.tint`
    /// EXCEPT for a `.missing` rom with `hasMaintenanceDonor` set, which
    /// gets `.incorrect`'s own yellow instead — jensyleo's own follow-up
    /// report (2026-09-14), after confirming live that `romStatusIcon(for:)`
    /// already showed the right yellow ICON: the row's own background tint
    /// was still computed straight from `entry.status` (still `.missing`,
    /// still red), so the row still read as plain red at a glance despite
    /// the icon itself already being right.
    private func romCell(_ content: some View, entry: AuditEntry) -> some View {
        let tint = ((entry.status == .missing || entry.status == .badDump) && entry.hasMaintenanceDonor) ? AuditStatus.incorrect.tint : entry.status.tint
        return content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(tint.opacity(0.18))
    }

    /// "Rom name" text — jensyleo's own report (2026-09-13): a surplus/
    /// unrecognized entry (no owning DAT game at all — `entry.game ==
    /// nil`) showed its own real on-disk entry name here (`entry.name`
    /// doubles as "the DAT's declared name" for a matched rom, but the
    /// AuditReporter has nothing else to put there for a file the DAT
    /// declares nothing about), which read as if the DAT actually knew
    /// this file by that name. "Unknown" is accurate; the real on-disk
    /// name still shows in "File name" right next to it.
    ///
    /// Real bug found live by jensyleo (2026-09-22): this used `entry.game
    /// == nil` alone, which is ALSO true for a genuinely RECOGNIZED
    /// surplus rom — one whose content the DAT identifies as belonging to
    /// some OTHER game (`requiredByGameDescription` set, "Recognized
    /// content, but X doesn't have it either") — `k573_dio 2.zip` inside
    /// the Maintenance folder, correctly identified as content "Dance
    /// Dance Revolution 3rd Mix" declares, still showed "Unknown" here.
    /// `AuditReporter` sets `entry.name` to the real, actual entry name
    /// (`hashedFile.file.name`) for EVERY surplus row regardless of
    /// whether it's recognized — only a row that's genuinely unrecognized
    /// (no `requiredByGameDescription` either) has nothing meaningful to
    /// show here at all.
    /// Real bug found live by jensyleo (2026-09-23): a genuinely
    /// unrecognized entry (e.g. a stray "__MACOSX/._foo.bin" AppleDouble
    /// sidecar file macOS itself writes into a zip made from a folder that
    /// once lived on a non-Mac filesystem) showed the literal word
    /// "Unknown" here — "the file DOES have a name" (his own words). The
    /// earlier design (below, now reversed) deliberately hid it to avoid
    /// implying the DAT recognized this entry by that name, but the
    /// "Info" column already says "Unrecognized (inside a known archive)"
    /// — that's the right place for "the DAT doesn't know this", not this
    /// column, which should always just say what the entry is actually
    /// called on disk (`AuditReporter` already sets `entry.name` to the
    /// real entry name for every surplus row, recognized or not).
    private func romNameText(for entry: AuditEntry) -> String {
        entry.name
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
                // jensyleo's own request (2026-09-17): once this same file
                // can actually be repaired from Maintenance (via
                // `hasMaintenanceDonor`, extended the same day to cover
                // this exact case — see `MaintenanceDonorDetector`'s own
                // doc comment), the message should say so FIRST — a fix
                // is available — rather than leading with "not needed
                // here", which reads as a dead end even though
                // right-clicking this same row now offers "Repair from
                // Maintenance Folder…".
                // jensyleo's own real incident (2026-09-19): "Not needed
                // here" reads as "a confirmed, safe spare copy" — true only
                // when `requiredByGameConfirmedRedundant` actually confirms
                // `requiredBy` has this content satisfied somewhere real
                // (see that field's own doc comment on `SurplusFile`). A
                // stray `naomi.zip` got deleted as "safe" this way while
                // NAOMI BIOS's own real archive had ALSO just been removed
                // — nothing here was actually confirming that. Checked
                // AFTER `hasMaintenanceDonor` above, which is its own,
                // separately-verified positive signal (a real donor
                // genuinely exists in Maintenance) and stays exactly as
                // worded.
                // Second round of the same incident, same day:
                // `requiredByGameConfirmedRedundant` ALSO goes true for
                // "duplicate among unclaimed surplus files" even when
                // `requiredBy` has NO real copy anywhere — safe only for a
                // whole, directly-usable unit, never a loose fragment.
                // `requiredByGameOwnerSatisfiedElsewhere` is the strict
                // subset that means `requiredBy` genuinely already has real
                // content — see its own doc comment on `SurplusFile`.
                if entry.hasMaintenanceDonor {
                    base = "Available in Maintenance folder (required by \(requiredBy))"
                } else if entry.requiredByGameOwnerSatisfiedElsewhere {
                    base = "Not needed here (required by \(requiredBy))"
                } else if entry.requiredByGameConfirmedRedundant {
                    base = "Extra copy — an identical file exists elsewhere, but \(requiredBy) still has no real copy"
                } else {
                    base = "Recognized content, but \(requiredBy) doesn't have it either"
                }
            } else if entry.foundElsewhereArchiveName != nil {
                // Same "say a real fix is available FIRST" rule as the
                // `requiredByGameDescription` branch above — real bug found
                // live by jensyleo (2026-09-21): a `.foundElsewhere` rom
                // this game's own archive genuinely lacks (e.g. NAOMI
                // BIOS's `315-6146.bin`, also declared by an unrelated
                // `mvsc2`) kept showing "Available in another game
                // (mvsc2.zip)" even after `MaintenanceDonorDetector`/
                // `RebuildPlanner` were extended to also repair these —
                // the informational "it's borrowed from elsewhere" text
                // was checked BEFORE the "a real donor exists in
                // Maintenance" one, so a genuinely fixable row still read
                // as a dead end and never hinted that right-clicking now
                // offers "Find ROMs…".
                base = entry.hasMaintenanceDonor
                    ? "Available in Maintenance folder"
                    : "Available in another game (\(entry.foundElsewhereArchiveName!))"
            } else {
                base = "Bad name"
            }
        // jensyleo's own definition (2026-08-04): a file genuinely sits in
        // this rom's own expected slot, but its CRC32/MD5/SHA doesn't
        // match — distinct from `.isBadDump` below (the DAT's own
        // baddump/nodump claim about the *reference* dump itself); this is
        // ROMForge's own finding about the *local* file.
        case .badDump:
            base = entry.hasMaintenanceDonor ? "Bad (verified-correct copy available in Maintenance folder)" : "Bad (hash mismatch)"
        // The DAT itself declares this rom/disk `optional="yes"` — MAME can
        // run the machine without it, real case found live by jensyleo
        // (2026-08-05) researched from MAME's own DTD (`cubeqst`/`cubeqsta`/
        // `atronic`'s laserdisc). Distinct wording from plain "Missing" so
        // it doesn't read as urgent/blocking the way a truly required
        // absence does.
        // jensyleo's own follow-up (2026-09-14), after confirming the
        // Roms panel's own yellow icon (`romStatusIcon(for:)`) already
        // worked: the "Info" column's own TEXT still just said plain
        // "Missing", giving no hint of WHY the icon was different —
        // mirrors `.incorrect`'s own `foundElsewhereArchiveName` wording
        // just above, since the underlying idea is the same ("the real
        // content is genuinely available, just not here yet").
        case .missing:
            if entry.hasMaintenanceDonor {
                base = "Missing (available in Maintenance folder)"
            } else {
                base = entry.isOptional ? "Missing (optional)" : "Missing"
            }
        case .surplus, .unknownFile: base = "Unrecognized"
        // jensyleo's own gray-file split (2026-08-06): this specific
        // entry's own archive IS a real, recognized DAT machine name — a
        // more actionable message than plain "Unrecognized" (which reads as
        // "nobody knows what this .zip even is").
        case .surplusInArchive: base = "Unrecognized (inside a known archive)"
        // A file genuinely sits in this rom's own expected slot, but the
        // DAT itself declares this rom `nodump` — no CRC/MD5/SHA1 exists to
        // confirm it against, by design (see `RomMatchStatus.nodump`'s own
        // doc comment). Distinct from `.correct` (nothing here was actually
        // verified) and from `.surplus` (the DAT explicitly documents this
        // exact name/slot for this exact machine, so it isn't unrecognized).
        case .unverifiable: base = "Nodump (unverifiable)"
        // `DuplicateSetDetector`'s own synthetic game-level row — `path` is
        // the duplicate copy this row is about, `duplicateSetPrimaryPath`
        // is where the real/primary copy already lives.
        case .duplicateSet:
            base = entry.duplicateSetPrimaryPath.map { "Duplicate set (also in \($0.lastPathComponent))" } ?? "Duplicate set"
        }
        if entry.isBadDump {
            // For every other status, a file DID get matched/found, so this
            // suffix reads as an extra fact about that real file. For
            // `.missing`, nothing was found at all — appending the same
            // suffix read as self-contradictory ("Missing (bad dump in
            // DAT)" implies a bad file was found, when actually none was) —
            // jensyleo's own request (2026-07-30) to review every
            // `infoText` case surfaced this. Worded so the DAT's own claim
            // stays visible (still useful: it tells the user this rom
            // wouldn't have been fixable by re-dumping even if found)
            // without implying presence.
            //
            // jensyleo's own report (2026-08-13): a screenshot of
            // "Tecmo TPS System" (`coh1002m`), whose `78081g503.ic655` is
            // DAT-declared `nodump` (confirmed directly against the real
            // MAME `-listxml`, no `baddump` anywhere in that machine),
            // showed "Ok (bad dump in DAT)" here — `entry.isBadDump`
            // collapses `baddump`/`nodump` into one boolean (that's its own
            // documented purpose, for the "Games with bad dumps" category
            // filter), but this label always said "bad dump" regardless of
            // which one it actually was. `entry.romDumpStatus` keeps the
            // real distinction — use it to word this correctly instead.
            let dumpKind = entry.romDumpStatus == .nodump ? "nodump" : "bad dump"
            base = entry.status == .missing ? "Missing (also a known \(dumpKind) in DAT)" : "\(base) (\(dumpKind) in DAT)"
        }
        // `SimilarNameSuggester`'s own live preview — jensyleo's own request
        // (2026-09-29): "esa opcion debería indicar algo como 'possible
        // name' en la vista de los paneles en la sección info." Only ever
        // non-nil for a genuinely gray row (`.surplus`/`.unknownFile`/
        // `.surplusInArchive` — every other status already has a real
        // match, hash-verified or otherwise, and never gets a suggestion at
        // all — see `ROMMatcher.annotateSimilarNameSurplusFiles`'s own
        // guard). See `LibraryViewModel.similarNameSuggestion(forFileAt:)`'s
        // own doc comment for why this reads the LIVE scan result, not
        // anything persisted.
        if let path = entry.path, let suggestion = viewModel.similarNameSuggestion(forFileAt: path) {
            base += " — Possible match: \(suggestion.suggestedName) (\(Int((suggestion.confidence * 100).rounded()))%)"
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
        // jensyleo's own request (2026-09-14): showing the RAW comment
        // text here could dump an arbitrary, sometimes long/messy string
        // straight into the Info column — a plain "has a comment" flag is
        // enough to tell the user one exists; the actual text is still one
        // hover away via `zipCommentHelpText(for:)`'s own tooltip.
        if let path = entry.path, path.pathExtension.lowercased() == "zip",
           let comment = zipCommentCache.comment(forZipAt: path), !comment.isEmpty {
            base += " — Has ZIP comment"
        }
        // See `infoText(for node:)`'s own doc comment — same region-quality
        // suffix, keyed off this entry's own game name instead of a
        // `GameNode`'s.
        if let note = regionQualityNote(forGameName: entry.gameDescription ?? entry.game ?? "") {
            let ownRegion = GameNameTagParser.parse(name: entry.gameDescription ?? entry.game ?? "").region
            base += ownRegion == note.recommendedRegion ? " — ⭐ Recommended version" : " — ℹ️ Better version exists (\(note.recommendedRegion))"
        }
        return base
    }

    /// The real comment text `infoText(for entry:)`/`infoText(for node:)`
    /// deliberately no longer inline — shown instead as a `.help()` tooltip
    /// on whichever cell renders that Info text, so the comment itself is
    /// still fully visible on hover without cluttering the table cell.
    private func zipCommentHelpText(for entry: AuditEntry) -> String {
        var parts: [String] = []
        if let path = entry.path, path.pathExtension.lowercased() == "zip",
           let comment = zipCommentCache.comment(forZipAt: path), !comment.isEmpty {
            parts.append(comment)
        }
        if let note = regionQualityNote(forGameName: entry.gameDescription ?? entry.game ?? "") {
            parts.append("\(note.recommendedRegion) recommended: \(note.reason) (\(note.sourceURL))")
        }
        return parts.joined(separator: "\n")
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

    /// Labeled "Dump status" row for the Detail panel's rom section —
    /// jensyleo's own request (2026-08-27) to color this like every other
    /// verdict field: `baddump` gets `AuditStatus.badDump`'s own orange,
    /// `nodump` gets `AuditStatus.unverifiable`'s own dimmed gray (the same
    /// "can't verify, not wrong" reading `dumpStatusText`'s own doc comment
    /// gives it). Skipped entirely when empty (a `good`/undeclared rom),
    /// same "nothing to say, don't show the row" convention as `infoRow` —
    /// this row previously always showed, even with nothing after the
    /// label.
    @ViewBuilder
    private func dumpStatusDetailRow(_ entry: AuditEntry) -> some View {
        let text = dumpStatusText(for: entry)
        if !text.isEmpty {
            let tint: Color = entry.romDumpStatus == .nodump ? AuditStatus.unverifiable.tint : AuditStatus.badDump.tint
            HStack(spacing: 8) {
                Text("Dump status").bold().frame(width: 100, alignment: .leading)
                Text(text).foregroundStyle(tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// `isDisk` is per-entry (a real CHD row); `isBios` is per-game (this
    /// row's own game is a MAME BIOS set, so every one of its rom rows is a
    /// BIOS file) — no per-entry "this individual rom is a BIOS file within
    /// a normal game" case exists, because MAME's own `-listxml` convention
    /// never lists a BIOS's roms inside the machine that requires it (see
    /// `AuditReporter`/`GameNodeBuilder`'s own grouping by `entry.game`) —
    /// there's simply no row here to label that way. Samples (`<sample>`)
    /// never get their own `AuditEntry` at all (`hasSamples` is
    /// presence-only, no name/hash to audit), so there's no "Sample" case
    /// either — every row reaching this function is either a disk, a BIOS
    /// set's own rom, or a plain rom.
    private func entryKindText(for entry: AuditEntry) -> String {
        if entry.isDisk { return "CHD" }
        if entry.isBios { return "BIOS" }
        return "ROM"
    }

    // MARK: - Tree building

    /// Just the "Database" category half of `scoped(_:)`'s filtering,
    /// parametrized by an explicit category rather than reading
    /// `selectedDatabaseFilter` — lets the expandable "Database" tree
    /// (`treeChildren(forCategory:)`) compute any category's own children,
    /// not only whichever one happens to be currently selected, without
    /// duplicating this switch a second time.
    ///
    /// The actual filtering logic moved to `DatabaseCategory.apply(to:)`
    /// (ROMForgeCore, 2026-08-13, "Grupo A" of the App-logic extraction) so
    /// it's unit-testable outside the app — this is now a thin delegate via
    /// `DatabaseFilter.coreCategory`.
    private nonisolated static func categoryFiltered(_ entries: [AuditEntry], matching filter: DatabaseFilter) -> [AuditEntry] {
        filter.coreCategory.apply(to: entries)
    }

    /// Applies the "Database" category (or "Rom files" folder) scope to an
    /// arbitrary entry list — factored out so it can run either on top of
    /// the status filter (`databaseFilteredEntries`, for the tree) or on
    /// every status at once (`scopedEntries`, for the button counts).
    private nonisolated static func scoped(_ entries: [AuditEntry], databaseFilter: DatabaseFilter?, romFolder: URL?, gamesInFolder: Set<String>) -> [AuditEntry] {
        GameNodeBuilder.scoped(entries, databaseCategory: databaseFilter?.coreCategory, romFolder: romFolder, gamesInFolder: gamesInFolder)
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
        GameNodeBuilder.recomputeGamesInFolder(entries: entries, selectedFolder: selectedFolder)
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
    /// Groups a surplus entry by the archive it physically lives in, keyed by
    /// FULL path so two same-named archives in different ROM folders stay two
    /// distinct buckets — jensyleo's own question (2026-08-06): what if the
    /// same archive sits in several folders? Keying by filename alone
    /// collapsed every physically-distinct copy into one bucket, which showed
    /// up as a single row for three real files and as status-button counts
    /// that disagreed with the table beside them.
    ///
    /// Shared by all three places that build these buckets (`gameNodes(from:)`,
    /// `computeScopedStatusCounts`, `computeGameAggregateStatusByName`) so
    /// they can never drift apart on it again.
    private nonisolated static func surplusArchiveKey(for entry: AuditEntry) -> String {
        SurplusArchiveKey.key(for: entry)
    }

    /// The filename to display for a `surplusArchiveKey` — the key itself is
    /// a full path, only ever used for grouping/identity.
    private nonisolated static func surplusDisplayName(forArchiveKey key: String) -> String {
        SurplusArchiveKey.displayName(forKey: key)
    }

    private nonisolated static func computeScopedStatusCounts(scopedEntries: [AuditEntry], gamesByName: [String: DATGame]) -> [AuditStatus: Int] {
        GameNodeBuilder.computeScopedStatusCounts(scopedEntries: scopedEntries, gamesByName: gamesByName)
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
        GameNodeBuilder.computeUnknownArchivesCount(baseNodes: baseNodes)
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
        GameNodeBuilder.unscannedCatalogNodes(matching: filter.coreCategory, preloadedGames: games)
    }

    /// `computeGameNodes()`'s real grouping work, factored out so the
    /// "Database" tree's expandable category children (`treeChildren(for:)`
    /// below) can reuse the exact same game/surplus-archive grouping for an
    /// arbitrary category — not just whichever one happens to be currently
    /// selected — without duplicating this logic a second time.
    /// Body moved to `GameNodeBuilder.gameNodes(from:...)` (ROMForgeCore,
    /// 2026-08-13, "Grupo B" of the App-logic extraction) so it's
    /// unit-testable — thin delegate, every real bug this logic was built
    /// to fix is documented on the Core function itself now.
    private nonisolated static func gameNodes(from entries: [AuditEntry], gamesByName: [String: DATGame], gameAggregateStatusByName: [String: AuditStatus], combineRomAndCHD: Bool, isFolderScoped: Bool) -> [GameNode] {
        GameNodeBuilder.gameNodes(
            from: entries, gamesByName: gamesByName, gameAggregateStatusByName: gameAggregateStatusByName,
            combineRomAndCHD: combineRomAndCHD, isFolderScoped: isFolderScoped
        )
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
    /// audit data changes (status filters, a new scan) or the search text
    /// changes. A *collapsed* category's cache just clears and stays empty
    /// until next expanded (cheap, correct); a category the user is
    /// actively looking at gets refreshed instead of silently going blank
    /// until they collapse and re-expand it by hand. Debounced and
    /// off-main-thread — jensyleo's own report
    /// (2026-08-11): typing in the new "Database" search field made the
    /// whole app "muy lenta". Two causes stacked: every single keystroke
    /// triggered a fresh recompute (no debounce at all), and each one ran
    /// `computeTreeChildren(...)`'s full O(entries) regroup/sort
    /// synchronously on the main thread — exactly the class of bug already
    /// fixed for folder/category clicks by `triggerCachedGameDataRecompute()`,
    /// just never applied to this call site. Waits `searchDebounceDelay`
    /// after the *last* keystroke before doing any real work (so a fast
    /// typist's intermediate states never get computed at all, only the
    /// final one), then does that work in `Task.detached`, guarded by
    /// `databaseTreeRecomputeGeneration` against a slower, older request
    /// finishing after a newer one and stomping its result — same
    /// generation-counter pattern `triggerCachedGameDataRecompute()` already
    /// uses, for the same reason (see its own doc comment).
    /// `only`, when set, recomputes just that one category and merges the
    /// result into the existing cache instead of rebuilding every expanded
    /// category from scratch — jensyleo's own report (2026-08-11): the app
    /// still felt slow even after this whole path moved off the main
    /// thread. Root cause of *that*: a first-expand or a "Show N more"
    /// click affects exactly one category, but this used to recompute
    /// *every* currently-expanded one regardless — with several categories
    /// expanded at once, opening or paging just one of them paid for
    /// redoing all the others too, for no reason. Left `nil` (recompute
    /// every expanded category) only for the two triggers that genuinely
    /// affect all of them at once: the search text changing, and a status/
    /// visibility toggle flipping.
    private func refreshExpandedDatabaseCategoryCachesAsync(debounced: Bool, only: DatabaseFilter? = nil) {
        pendingDatabaseTreeRecompute?.cancel()
        databaseTreeRecomputeGeneration += 1
        let generation = databaseTreeRecomputeGeneration
        let expanded = expandedDatabaseCategories
        let filtersToRecompute = only.map { [$0] } ?? Array(expanded)
        let hasAuditReport = viewModel.auditReport != nil
        let entries = viewModel.auditReport?.entries ?? []
        let folder = selectedRomFolder
        let preloadedGames = viewModel.preloadedGames
        let aggStatus = gameAggregateStatusByName
        let combine = combineRomAndCHD
        let showUnknown = showUnknownArchives
        let statusFilters = activeStatusFilters
        let searchText = databaseSearchText
        let visibleCaps = databaseCategoryVisibleCap
        let existingCache = databaseCategoryChildrenCache
        pendingDatabaseTreeRecompute = Task.detached(priority: .userInitiated) {
            if debounced {
                // A fast typist's every keystroke lands here — only the
                // *last* one within this window should ever pay for a real
                // recompute; `Task.sleep` (not a blocking main-thread timer)
                // so this costs nothing while waiting, and `Task.isCancelled`
                // (checked right after) means an earlier keystroke's own
                // sleep, once superseded, never runs the expensive part at
                // all once cancelled.
                try? await Task.sleep(for: Self.searchDebounceDelay)
                guard !Task.isCancelled else { return }
            }
            var refreshed = existingCache
            for filter in filtersToRecompute {
                // jensyleo's own report (2026-09-26): see
                // `triggerCachedGameDataRecompute()`'s own doc comment —
                // `.cancel()` alone never stops already-running CPU work,
                // so a superseded run of this loop (e.g. the search text
                // changing again before the previous keystroke's recompute
                // finished) used to keep processing every remaining
                // expanded category anyway, purely wasted work genuinely
                // contending with whatever DOES still matter.
                guard !Task.isCancelled else { return }
                refreshed[filter] = Self.computeTreeChildren(
                    forCategory: filter,
                    hasAuditReport: hasAuditReport, auditEntries: entries, selectedRomFolder: folder, preloadedGames: preloadedGames,
                    gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine, showUnknownArchives: showUnknown, activeStatusFilters: statusFilters,
                    searchText: searchText, visibleCap: visibleCaps[filter] ?? Self.maxTreeChildrenPerCategory
                )
            }
            // Anything no longer expanded (collapsed since this task was
            // kicked off) shouldn't linger in the merged result — matches
            // the old always-rebuild-from-scratch behavior for every
            // filter not in `filtersToRecompute` too.
            refreshed = refreshed.filter { expanded.contains($0.key) }
            await MainActor.run {
                // Same out-of-order guard as `triggerCachedGameDataRecompute()`
                // — see its own doc comment for why `Task.isCancelled` alone
                // isn't enough once this genuinely runs concurrently.
                guard generation == databaseTreeRecomputeGeneration else { return }
                databaseCategoryChildrenCache = refreshed
                databaseCategoryVisibleCap = visibleCaps.filter { expanded.contains($0.key) }
                scrollDatabaseListToSelectedGameIfNewlyVisible()
            }
        }
    }

    /// jensyleo's own request (2026-08-13): opening a category's chevron
    /// when a game is already selected (e.g. picked from the "Games" table
    /// on the right while the category itself was still collapsed — see
    /// the category header's own `isSelected`/`moveDatabaseSelection`'s
    /// `currentIndex` doc comments for that whole story) should scroll the
    /// sidebar to reveal it, not leave the newly-expanded list sitting at
    /// the top with the real selection buried off-screen somewhere below.
    /// Called both here (the async/first-expand path) and from
    /// `databaseCategoryExpansion(for:)`'s own setter (the already-cached
    /// path, where there's no async gap to wait out).
    private func scrollDatabaseListToSelectedGameIfNewlyVisible() {
        guard let filter = selectedDatabaseFilter, let id = selectedGameID,
              expandedDatabaseCategories.contains(filter),
              findDatabaseTreeNode(id: id, in: databaseCategoryChildrenCache[filter] ?? []) != nil
        else { return }
        // jensyleo's own report (2026-08-13): calling this synchronously
        // right after the category's own children just got inserted into
        // `databaseCategoryChildrenCache` — same SwiftUI update/frame the
        // new leaf rows are only just now being mounted in — a classic
        // `ScrollViewReader.scrollTo` timing gap: the target `id` doesn't
        // exist in the rendered `List` yet, so there's nothing to scroll
        // to and the call is silently a no-op. Deferring one run-loop tick
        // gives SwiftUI time to actually lay the new rows out first.
        DispatchQueue.main.async {
            databaseListScrollProxy?.scrollTo(id, anchor: .center)
        }
    }

    /// How long to wait after the last keystroke before actually recomputing
    /// the "Database" search results — long enough that normal typing speed
    /// (a character every ~100-150ms) never triggers an intermediate
    /// recompute, short enough that pausing mid-word still feels responsive.
    private static let searchDebounceDelay: Duration = .milliseconds(300)
    /// Short enough that one deliberate click/keypress still feels
    /// instant, long enough that holding/repeating an arrow key in
    /// "Database" (typical OS key-repeat is a step every ~30-50ms) folds
    /// several intermediate selections into just the one the user
    /// actually settles on — see `triggerCachedGameDataRecompute()`'s own
    /// doc comment.
    private static let keyboardNavigationDebounceDelay: Duration = .milliseconds(80)

    /// The async, off-main-thread path for recomputing all of
    /// `cachedGameNodes`/`cachedGamesInFolder`/`cachedScopedStatusCounts`/
    /// `cachedUnknownArchivesCount`, guarded against out-of-order
    /// completion by `folderRecomputeGeneration` — shared by both
    /// `.onChange(of: selectedRomFolder)` and `.onChange(of:
    /// selectedDatabaseFilter)` (added 2026-08-11; originally only the
    /// former had it). `selectedRomFolder`/`selectedDatabaseFilter` are
    /// mutually exclusive (selecting one always clears the other, just
    /// above), so both triggers mean exactly the same thing here: "what's
    /// currently displayed changed, recompute it" — one shared function,
    /// one shared generation counter, rather than two independent copies
    /// that could race each other.
    ///
    /// A large collection (a full MAME set can have 40,000+ games) makes
    /// every function this calls (`Self.recomputeGamesInFolder`,
    /// `Self.computeBaseGameNodes`, `Self.computeGameNodes`,
    /// `Self.computeScopedStatusCounts`, `Self.computeUnknownArchivesCount`)
    /// real, O(entries) work — jensyleo's own report (2026-08-03, for the
    /// folder case only at the time): the app visibly froze for a moment on
    /// every single click. Swift's cooperative cancellation can't preempt
    /// work already running synchronously on the main thread, so merely
    /// cancelling a stale in-flight request doesn't help the *current*
    /// click — the fix has to be running this off the main thread in the
    /// first place. Every function called here is `static` and touches no
    /// `@State` directly (only plain value-type parameters), specifically
    /// so it's safe to run inside `Task.detached`, with only the final
    /// assignment back on `@MainActor`.
    /// jensyleo's own report (2026-08-13): moving through "Database" with
    /// the arrow keys — without ever opening a chevron, so
    /// `flattenedVisibleDatabaseRows` itself is cheap (a couple dozen
    /// collapsed top-level rows at most) — still felt slow. Root cause:
    /// each step selects a different category exactly like a mouse click
    /// would (`.onChange(of: selectedDatabaseFilter)` →
    /// `triggerCachedGameDataRecompute()`), and holding/repeating an arrow
    /// key fires that far faster than anyone clicks — each intermediate
    /// step (even one immediately superseded by the next) still kicked off
    /// its own real rebuild of `cachedGameNodes` for whichever category it
    /// briefly landed on, some of which (e.g. "All games") can be tens of
    /// thousands of rows. `Task.sleep` first, same debounce shape already
    /// used for the search field's own keystroke storm — short enough
    /// (`keyboardNavigationDebounceDelay`) that a single deliberate click
    /// or keypress still feels instant, long enough that a fast run of
    /// repeats collapses into just the row the user actually settles on.
    /// jensyleo's own follow-up report (2026-08-19): even "instant" here
    /// still meant paying the full 80ms before the real work even started,
    /// on top of however long that work itself takes — noticeable for a
    /// single, isolated click. `lastFolderRecomputeTriggerAt`/`isBurst`
    /// (below) now skip the wait entirely unless this call actually
    /// followed another one within the debounce window — i.e. the delay
    /// only applies when a burst is genuinely happening.
    private func triggerCachedGameDataRecompute() {
        pendingFolderRecompute?.cancel()
        // Real bug found live (2026-10-01 audit): `pendingFolderRecompute`
        // is shared with `refreshCachedGameDataAfterAuditReportChangeAsync()`
        // — cancelling it here (e.g. a folder click arriving while that
        // function's own zip-comment preload tail is still in flight) makes
        // that task exit through one of its own early `Task.isCancelled`
        // guards, which never got a chance to reset `isPreloadingZipComments`
        // back to `false` (only its success path did). Left `true` forever,
        // this keeps the scan overlay stuck on screen (`.overlay`'s gate is
        // `viewModel.isBusy || isPreloadingZipComments`), blocking all
        // further interaction. Resetting it here too, since cancelling the
        // shared task for ANY reason means whatever it was doing — including
        // that preload — is no longer relevant to what's about to render.
        isPreloadingZipComments = false
        folderRecomputeGeneration += 1
        let generation = folderRecomputeGeneration
        let now = ContinuousClock.now
        let isBurst = lastFolderRecomputeTriggerAt.map { now - $0 < Self.keyboardNavigationDebounceDelay } ?? false
        lastFolderRecomputeTriggerAt = now
        let hasAuditReport = viewModel.auditReport != nil
        let entries = viewModel.auditReport?.entries ?? []
        let folder = selectedRomFolder
        let preloadedGames = viewModel.preloadedGames
        let databaseFilter = selectedDatabaseFilter
        let aggStatus = gameAggregateStatusByName
        let combine = combineRomAndCHD
        let showUnknown = showUnknownArchives
        let statusFilters = activeStatusFilters
        let hidden1G1RNames = show1G1ROnly ? cachedOneGameOneROMSummary.hiddenWhenFilteredNames : []
        let alreadyCachedZipComments = zipCommentCache.snapshot
        let isMAMEStyle = system.isMAMEStyle
        pendingFolderRecompute = Task.detached(priority: .userInitiated) {
            if isBurst {
                try? await Task.sleep(for: Self.keyboardNavigationDebounceDelay)
                guard !Task.isCancelled else { return }
            }
            // TEMP PERF INSTRUMENTATION (2026-09-26, jensyleo's own report
            // of a single, isolated KONAMI→CPS1 click taking up to 7s) —
            // remove once the bottleneck is confirmed/fixed.
            let pt0 = Date()
            let gamesInFolder = Self.recomputeGamesInFolder(entries: entries, selectedFolder: folder)
            let pt1 = Date()
            let scoped = Self.scoped(entries, databaseFilter: databaseFilter, romFolder: folder, gamesInFolder: gamesInFolder)
            let pt2 = Date()
            let baseNodes = Self.computeBaseGameNodes(
                hasAuditReport: hasAuditReport, auditEntries: entries,
                selectedRomFolder: folder, preloadedGames: preloadedGames, selectedDatabaseFilter: databaseFilter,
                gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine,
                precomputedScoped: scoped
            )
            let pt3 = Date()
            // jensyleo's own report (2026-09-26): "cancellation" via
            // `pendingFolderRecompute?.cancel()` above is purely
            // cooperative — Swift never actually interrupts a detached
            // task's own synchronous CPU work just because `.cancel()` was
            // called on it. A superseded task (e.g. rapidly switching ROM
            // folders) used to keep running this ENTIRE pipeline to
            // completion regardless, genuinely contending for CPU with the
            // NEWER task that's the one that actually matters — self-
            // inflicted contention entirely within ROMForge's own process
            // (matches jensyleo's own observation that ROMForge alone gets
            // slow while every other app stays fluid). Checked here, right
            // before the two most expensive remaining steps
            // (`computeGameNodes`/`indexByID`, the ones the perf log showed
            // taking anywhere from ~1µs to 11+ real seconds under
            // contention), so a stale run bails out immediately instead of
            // still paying that full cost for a result nobody will ever see.
            guard !Task.isCancelled else { return }
            let nodes = Self.computeGameNodes(
                baseNodes: baseNodes, gameAggregateStatusByName: aggStatus, showUnknownArchives: showUnknown,
                activeStatusFilters: statusFilters, hiddenOneGameOneROMNames: hidden1G1RNames
            )
            let pt4 = Date()
            let hiddenCount = baseNodes.filter { hidden1G1RNames.contains($0.name) }.count
            let nodesByID = Self.indexByID(nodes)
            let pt5 = Date()
            guard !Task.isCancelled else { return }
            let counts = Self.computeScopedStatusCounts(scopedEntries: scoped, gamesByName: Self.gamesByName(preloadedGames))
            let unknownCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
            let pt6 = Date()
            // Real gap found live by jensyleo (2026-09-24), right after the
            // 2026-09-23 scroll-hang fix: that fix only preloaded zip
            // comments inside `refreshCachedGameDataAfterAuditReportChangeAsync()`
            // (a real scan finishing) — this SEPARATE recompute path, run
            // every time the SELECTED ROM FOLDER changes, never got the
            // same treatment, so clicking into a folder whose zips hadn't
            // been shown yet this session could still trigger the exact
            // same synchronous, main-thread `ZipCommentReader` disk/NAS
            // reads the earlier fix was supposed to eliminate — read as a
            // random hang precisely because it only happened for a
            // genuinely NOT-yet-cached folder. See `ZipCommentCache
            // .preload(_:)`'s own doc comment.
            //
            // jensyleo's own follow-up report (2026-09-26): even after the
            // "skip already-cached" fix above, the app still genuinely
            // froze on ANY click, "Database" categories included (capping
            // `nodes` itself to a small prefix was tried first and reverted
            // — `nodes` here is the FULL scoped list regardless, the Games
            // `Table` just slices it for display via `gamesTableVisibleCap`,
            // and "Load more" never triggers a fresh recompute — so bounding
            // the preload the same way would have just brought back the
            // 2026-09-23 per-row scroll-hang bug for every row past the
            // first page). Real root cause instead: `Task.detached` still
            // runs on Swift concurrency's own small, COOPERATIVE thread
            // pool (sized to the CPU's core count) — a blocking, synchronous
            // read loop over possibly thousands of NAS-backed files run
            // there doesn't yield that thread back, and each rapid
            // click/toggle starts ANOTHER overlapping `Task.detached` doing
            // the same before the last one finishes (cancellation is
            // cooperative — it doesn't interrupt a blocking call already in
            // flight). Enough of these piling up exhausts that pool
            // entirely, and once it's exhausted, EVERY `await` anywhere in
            // the app — including totally unrelated ones on the main
            // actor — has nowhere left to resume, which reads as the whole
            // app being frozen solid. Moving the actual blocking read loop
            // onto a plain, effectively unbounded `DispatchQueue` (real OS
            // threads, not the constrained cooperative pool) via a checked
            // continuation keeps this same complete, correct preload
            // coverage while never starving the pool other `await`s depend
            // on to make progress at all.
            // Real NAS cost found live (2026-10-01), jensyleo's own report
            // ("solo dar clic en el romfolder... tarda demasiado... viendo
            // que solo tienen que leer un cache local"): the audit report
            // itself IS persisted/cached (SQLite), but `ZipCommentCache` is
            // purely in-memory — every ROM folder not yet visited THIS
            // session still pays one real NAS round-trip per zip here, no
            // matter how old/complete the underlying scan is. Zip file
            // comments are a RomCenter/ClrMamePro/No-Intro-era convention
            // ("— Has ZIP comment" only ever matters for a console/No-Intro
            // DAT) — a real MAME set's own archives are never produced with
            // one, so this entire preload is pure unrewarded NAS cost for
            // `isMAMEStyle` systems. Skipped entirely for those; unchanged
            // for console systems, where it's the real, useful feature.
            let zipURLsToPreload: Set<URL> = isMAMEStyle ? [] : Set(nodes.flatMap { node in
                node.entries.compactMap { entry -> URL? in
                    guard let path = entry.path, path.pathExtension.lowercased() == "zip" else { return nil }
                    return path
                }
            }).subtracting(alreadyCachedZipComments.keys)
            let pt7 = Date()
            let preloadedZipComments = zipURLsToPreload.isEmpty ? [:] : await Self.readZipComments(zipURLsToPreload)
            let pt8 = Date()
            PerfDebugLog.write("""
            triggerCachedGameDataRecompute: entries=\(entries.count) zipURLsToPreload=\(zipURLsToPreload.count) \
            gamesInFolder=\(pt1.timeIntervalSince(pt0))s scoped=\(pt2.timeIntervalSince(pt1))s baseNodes=\(pt3.timeIntervalSince(pt2))s \
            gameNodes=\(pt4.timeIntervalSince(pt3))s indexByID=\(pt5.timeIntervalSince(pt4))s scopedCounts=\(pt6.timeIntervalSince(pt5))s \
            zipURLsSet=\(pt7.timeIntervalSince(pt6))s zipReads=\(pt8.timeIntervalSince(pt7))s TOTAL=\(pt8.timeIntervalSince(pt0))s
            """)
            await MainActor.run {
                // Guards against out-of-order completion, not just
                // cancellation: once genuinely concurrent, a slower
                // background task for a click the user already clicked
                // past could otherwise finish *after* the newer one and
                // stomp its correct, already-displayed result —
                // `Task.isCancelled` alone doesn't prevent this
                // (cancellation only marks a flag; it doesn't stop
                // already-in-flight work from completing). This monotonic
                // counter directly answers "is this still the most recent
                // click" at the one moment that actually matters: right
                // before the write.
                guard generation == folderRecomputeGeneration else { return }
                cachedGamesInFolder = gamesInFolder
                cachedGameNodes = nodes
                zipCommentCache.preload(preloadedZipComments)
                cachedHiddenOneGameOneROMCount = hiddenCount
                refreshCachedFamilyGameNodes()
                cachedGameNodesByID = nodesByID
                cachedScopedStatusCounts = counts
                cachedUnknownArchivesCount = unknownCount
            }
        }
    }

    /// Was `recomputeCachedGameDataSync()` — called synchronously (blocking
    /// the main thread) from `.onAppear` and `.onChange(of: viewModel
    /// .auditReport)`, i.e. every time this view first appears for a system
    /// or a scan just finished. Real cost found live (2026-08-13 performance
    /// audit, "Ciclo A"): switching between two or three already-scanned,
    /// large-DAT systems in the sidebar in quick succession visibly
    /// stuttered on each switch, since both this function AND
    /// `computeGameAggregateStatusByName()` (also called synchronously right
    /// before it, at both sites) are full O(entries) passes over up to
    /// ~188k `AuditEntry`s.
    ///
    /// Folded into one `Task.detached`, same generation-guarded pattern as
    /// `triggerCachedGameDataRecompute()` — the two were never combined into
    /// that existing function because `gameAggregateStatusByName` is itself
    /// one of `triggerCachedGameDataRecompute()`'s *inputs* (folder/category
    /// clicks read the already-correct cached value, they don't need to
    /// recompute it) — only an audit-report change needs to recompute it
    /// too, so this is its own function rather than a flag added to that one.
    /// `refreshExpandedDatabaseCategoryCachesAsync(debounced: false)` is
    /// still called from inside, AFTER `gameAggregateStatusByName` is
    /// updated on the main actor — it captures that value synchronously at
    /// its own call time (same as before), so calling it any earlier would
    /// have it read the stale, pre-update value.
    private func refreshCachedGameDataAfterAuditReportChangeAsync() {
        pendingFolderRecompute?.cancel()
        // Same reset as `triggerCachedGameDataRecompute()`'s own — this
        // function can also cancel an EARLIER run of itself (two scans
        // finishing in quick succession), which would otherwise leave
        // `isPreloadingZipComments` stuck `true` the same way. Harmless to
        // reset unconditionally here even when nothing was stuck — this
        // function sets it back to `true` moments later anyway, for
        // whichever run actually proceeds.
        isPreloadingZipComments = false
        folderRecomputeGeneration += 1
        let generation = folderRecomputeGeneration
        let hasAuditReport = viewModel.auditReport != nil
        let entries = viewModel.auditReport?.entries ?? []
        let folder = selectedRomFolder
        let preloadedGames = viewModel.preloadedGames
        let databaseFilter = selectedDatabaseFilter
        let combine = combineRomAndCHD
        let showUnknown = showUnknownArchives
        let statusFilters = activeStatusFilters
        let show1G1R = show1G1ROnly
        let regionOrder = RegionOrderSettings.order(from: regionOrderRaw)
        let alreadyCachedZipComments = zipCommentCache.snapshot
        let isMAMEStyle = system.isMAMEStyle
        // See `isPreloadingZipComments`'s own doc comment — keeps the scan
        // overlay up through this function's own zip-comment preload tail,
        // which otherwise kept reading disk/NAS well after `viewModel
        // .isBusy` already went false. Never set for MAME, which skips the
        // whole preload below anyway.
        if !isMAMEStyle { isPreloadingZipComments = true }
        pendingFolderRecompute = Task.detached(priority: .userInitiated) {
            // TEMP PERF INSTRUMENTATION (2026-09-17) — remove once the
            // slow-launch bottleneck is identified.
            let t0 = Date()
            let aggStatus = Self.computeGameAggregateStatusByName(entries: entries, preloadedGames: preloadedGames)
            let t1 = Date()
            let parentCloneSummary = ParentCloneSummary.compute(games: preloadedGames, statusByName: aggStatus)
            let t2 = Date()
            let oneGameOneROMSummary = OneGameOneROMSelector.compute(games: preloadedGames, regionOrder: regionOrder)
            let t3 = Date()
            // jensyleo's own report (2026-09-26): see `triggerCachedGameDataRecompute()`'s
            // own doc comment on why this checks cancellation explicitly —
            // `.cancel()` alone never stops a detached task's own
            // already-running CPU work, so a superseded run (this
            // function's OWN prior call, from the previous scan/report
            // change) used to keep burning real CPU competing with the
            // newer one that's the only result anyone will ever see. This
            // is the pipeline that runs after EVERY real scan, so it's the
            // most consequential place to check.
            guard !Task.isCancelled else { return }
            let gamesInFolder = Self.recomputeGamesInFolder(entries: entries, selectedFolder: folder)
            let t4 = Date()
            let scoped = Self.scoped(entries, databaseFilter: databaseFilter, romFolder: folder, gamesInFolder: gamesInFolder)
            let t5 = Date()
            let baseNodes = Self.computeBaseGameNodes(
                hasAuditReport: hasAuditReport, auditEntries: entries,
                selectedRomFolder: folder, preloadedGames: preloadedGames, selectedDatabaseFilter: databaseFilter,
                gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine,
                precomputedScoped: scoped
            )
            let t6 = Date()
            guard !Task.isCancelled else { return }
            let nodes = Self.computeGameNodes(
                baseNodes: baseNodes, gameAggregateStatusByName: aggStatus, showUnknownArchives: showUnknown,
                activeStatusFilters: statusFilters, hiddenOneGameOneROMNames: show1G1R ? oneGameOneROMSummary.hiddenWhenFilteredNames : []
            )
            let t7 = Date()
            let hiddenCount = baseNodes.filter { oneGameOneROMSummary.hiddenWhenFilteredNames.contains($0.name) }.count
            let nodesByID = Self.indexByID(nodes)
            // See `ZipCommentCache.preload(_:)`'s own doc comment — reads
            // every zip comment this newly-scoped node list could ever
            // show, off the main thread, before any of it renders. Skipped
            // entirely for a MAME-style system — see
            // `triggerCachedGameDataRecompute()`'s own doc comment on this
            // same guard for the real NAS cost this avoids.
            let zipURLsToPreload: Set<URL> = isMAMEStyle ? [] : Set(nodes.flatMap { node in
                node.entries.compactMap { entry -> URL? in
                    guard let path = entry.path, path.pathExtension.lowercased() == "zip" else { return nil }
                    return path
                }
            }).subtracting(alreadyCachedZipComments.keys)
            // See `triggerCachedGameDataRecompute()`'s own doc comment on
            // `readZipComments` for why this runs off Swift concurrency's
            // own cooperative thread pool instead of inline here.
            let preloadedZipComments = zipURLsToPreload.isEmpty ? [:] : await Self.readZipComments(zipURLsToPreload)
            let t8 = Date()
            let counts = Self.computeScopedStatusCounts(scopedEntries: scoped, gamesByName: Self.gamesByName(preloadedGames))
            let t9 = Date()
            let unknownCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
            let t10 = Date()
            PerfDebugLog.write("""
            refreshCachedGameData: entries=\(entries.count) preloadedGames=\(preloadedGames.count) \
            aggStatus=\(t1.timeIntervalSince(t0))s parentClone=\(t2.timeIntervalSince(t1))s 1G1R=\(t3.timeIntervalSince(t2))s \
            gamesInFolder=\(t4.timeIntervalSince(t3))s scoped=\(t5.timeIntervalSince(t4))s baseNodes=\(t6.timeIntervalSince(t5))s \
            gameNodes=\(t7.timeIntervalSince(t6))s indexByID=\(t8.timeIntervalSince(t7))s scopedCounts=\(t9.timeIntervalSince(t8))s \
            unknownCount=\(t10.timeIntervalSince(t9))s TOTAL=\(t10.timeIntervalSince(t0))s
            """)
            await MainActor.run {
                // Same out-of-order guard as `triggerCachedGameDataRecompute()`
                // — see its own doc comment.
                guard generation == folderRecomputeGeneration else { return }
                gameAggregateStatusByName = aggStatus
                cachedParentCloneSummary = parentCloneSummary
                cachedOneGameOneROMSummary = oneGameOneROMSummary
                cachedHiddenOneGameOneROMCount = hiddenCount
                cachedGamesInFolder = gamesInFolder
                cachedGameNodes = nodes
                zipCommentCache.preload(preloadedZipComments)
                refreshCachedFamilyGameNodes()
                cachedGameNodesByID = nodesByID
                cachedScopedStatusCounts = counts
                cachedUnknownArchivesCount = unknownCount
                refreshExpandedDatabaseCategoryCachesAsync(debounced: false)
                isPreloadingZipComments = false
            }
        }
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
    /// at a number SwiftUI can actually render without a visible stutter,
    /// with a plain "…and N more" notice instead of the rest, is what keeps
    /// this feature safe at MAME's real scale — the Games table (already
    /// scoped to the same category, already handles arbitrarily large
    /// counts) is still there for the full list.
    ///
    /// Raised from 200 → 500 (jensyleo's own request, 2026-08-11, "liberar
    /// la vista All"), then back down to 200 the same day: jensyleo's own
    /// live report at 500 was "la app se está poniendo lenta", confirming
    /// the linear per-row-cost estimate above — 500 rows of (icon + name +
    /// manufacturer + a `Button`, now also arrow-key-navigable) genuinely
    /// wasn't instant. 200 is back to the last size this same feature was
    /// confirmed comfortable at, before either the manufacturer column or
    /// arrow-key navigation added their own per-row cost on top. The "Show
    /// N more"/search-bar affordances added since (2026-08-11) mean 200 is
    /// no longer a hard ceiling on what's reachable, just the size of the
    /// first, always-fast page.
    // `nonisolated` on these three: plain, immutable `Int` constants, read
    // from both ordinary (main-actor) code and the `nonisolated static`
    // background functions (`computeTreeChildren`, `capped`, etc.) that do
    // the actual heavy lifting off the main thread — without this, Swift 6
    // strict concurrency correctly flags each of those reads as "main
    // actor-isolated property referenced from a nonisolated context",
    // since a plain `static let` defaults to the enclosing (main-actor)
    // type's own isolation. Harmless in practice (an immutable `Int` can
    // never actually race), but `nonisolated` says so to the compiler
    // directly instead of leaving warnings that look like real concurrency
    // bugs on every build.
    private nonisolated static let maxTreeChildrenPerCategory = 200
    /// How many more rows each "Show N more" click reveals — kept equal to
    /// `maxTreeChildrenPerCategory` so every increment costs the same as
    /// the first page did. See `databaseCategoryVisibleCap`'s own doc
    /// comment.
    private nonisolated static let treeLoadMoreIncrement = 200
    /// Defensive backstop for a search whose match count still turns out to
    /// be huge (e.g. a single common substring like "the") — search is
    /// expected to almost always narrow things down far below this, but
    /// nothing here may ever render fully unbounded, on principle, after
    /// `b7a394b`'s freeze.
    private nonisolated static let maxSearchResultsCap = 2000

    /// Thin instance wrapper — snapshots current `@State` into
    /// `Self.computeTreeChildren(...)`'s plain parameters. Only ever called
    /// synchronously from the one remaining site that needs an *immediate*
    /// result (`databaseCategoryExpansion`'s first-expand branch and the
    /// "Show N more" button), never from a rapid-fire trigger like typing —
    /// see `refreshExpandedDatabaseCategoryCachesAsync()`'s own doc comment
    /// for why every other site goes through that instead.
    private func treeChildren(forCategory filter: DatabaseFilter) -> [DatabaseTreeNode] {
        Self.computeTreeChildren(
            forCategory: filter,
            hasAuditReport: viewModel.auditReport != nil, auditEntries: viewModel.auditReport?.entries ?? [],
            selectedRomFolder: selectedRomFolder, preloadedGames: viewModel.preloadedGames,
            gameAggregateStatusByName: gameAggregateStatusByName, combineRomAndCHD: combineRomAndCHD,
            showUnknownArchives: showUnknownArchives, activeStatusFilters: activeStatusFilters,
            searchText: databaseSearchText, visibleCap: databaseCategoryVisibleCap[filter] ?? Self.maxTreeChildrenPerCategory
        )
    }

    /// Whether `text` matches a "Database" search `pattern` — jensyleo's
    /// own request (2026-08-13): "permite usar los comodines * e ? y que
    /// la búsqueda sea más exacta... escribo street y me sale... 64
    /// street. Quiero que la búsqueda sea exacta". Two modes:
    /// - **No wildcard** in `pattern`: a plain case-insensitive *prefix*
    ///   match (`text` must genuinely *start with* `pattern`) — this is
    ///   the "más exacta" half: the old behavior (`localizedCaseInsensitiveContains`)
    ///   matched a substring *anywhere*, so searching "street" also
    ///   matched "64 Street" (the match starts mid-string); a prefix
    ///   match only matches something like "Street Fighter", where the
    ///   query is genuinely how the name begins.
    /// - **`*`/`?` present** in `pattern`: classic shell-glob wildcards —
    ///   `*` matches any run of characters (including none), `?` matches
    ///   exactly one — matched against the *whole* string (implicitly
    ///   anchored at both ends), so a search like `*street*` recovers the
    ///   old "contains anywhere" behavior deliberately, on request, rather
    ///   than by default; `street*` matches only a *leading* "street" (the
    ///   same as the no-wildcard case, spelled explicitly); `*64` matches
    ///   anything *ending* in "64", not reachable at all under plain
    ///   prefix matching.
    private nonisolated static func matchesDatabaseSearch(_ text: String, pattern: String) -> Bool {
        DatabaseSearchMatcher.matches(text, pattern: pattern)
    }

    /// Everything `treeChildren(forCategory:)` used to do directly against
    /// `@State`, now a plain, `nonisolated static` function — jensyleo's own
    /// report (2026-08-11): typing into the new search field made the whole
    /// app "muy lenta". Root cause: every keystroke re-ran this exact
    /// O(entries) regroup/sort/filter *synchronously on the main thread*,
    /// same class of bug as the folder/category-click freezes already fixed
    /// by `triggerCachedGameDataRecompute()` — just never applied here when
    /// the search field was added, and typing fires far more often than a
    /// click ever did. Being `static`/parameter-only (no direct `@State`
    /// access) is what makes it safe to run inside `Task.detached` from
    /// `refreshExpandedDatabaseCategoryCachesAsync()`.
    private nonisolated static func computeTreeChildren(
        forCategory filter: DatabaseFilter,
        hasAuditReport: Bool, auditEntries: [AuditEntry], selectedRomFolder: URL?, preloadedGames: [DATGame],
        gameAggregateStatusByName: [String: AuditStatus], combineRomAndCHD: Bool, showUnknownArchives: Bool, activeStatusFilters: Set<AuditStatus>,
        searchText: String, visibleCap: Int
    ) -> [DatabaseTreeNode] {
        let effectiveCap = searchText.isEmpty ? visibleCap : Self.maxSearchResultsCap
        let nodes: [GameNode]
        if !hasAuditReport, selectedRomFolder == nil, !preloadedGames.isEmpty {
            nodes = Self.unscannedCatalogNodes(matching: filter, preloadedGames: preloadedGames)
        } else {
            // Grouped from every entry in this category (not status-
            // filtered — a game's real category must never depend on
            // which rows happen to be visible elsewhere), then the four
            // toggles filter the resulting *games* by that true category.
            // See `statusSummary`'s own doc comment for exactly what each
            // of the four means.
            nodes = Self.gameNodes(
                from: Self.categoryFiltered(auditEntries, matching: filter),
                gamesByName: Self.gamesByName(preloadedGames),
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
                    // unrecognized bucket belongs to the separate "Unknown"
                    // toggle at all.
                    //
                    // jensyleo's own report (2026-08-13): checking
                    // `aggregateStatus == .surplus` here never actually
                    // matched anything real — `GameNodeBuilder
                    // .gameNodes(from:)` only ever assigns `.unknownFile`
                    // (or `.incorrect`) to a surplus bucket, `.surplus`
                    // itself is legacy/decode-only (see `AuditStatus
                    // .surplus`'s own doc comment) — so a genuinely
                    // unrecognized file (e.g. a real `.7z` with no
                    // matching DAT rom) silently fell into the `else`
                    // branch and was gated by the four status buttons
                    // instead of this dedicated toggle, reading as if it
                    // had vanished entirely. See the same fix in
                    // `computeGameNodes`'s own doc comment for the full
                    // reasoning.
                    if node.isSurplusBucket {
                        return node.aggregateStatus == .unknownFile || node.aggregateStatus == .surplus
                            ? showUnknownArchives : activeStatusFilters.contains(node.aggregateStatus ?? .unknownFile)
                    }
                    guard let category = gameAggregateStatusByName[node.name] ?? node.aggregateStatus else { return true }
                    return activeStatusFilters.contains(category)
                }
        }
        var realGames = nodes.filter { !$0.isSurplusBucket }

        // Search narrows the category down before any capping happens at
        // all — see `databaseSearchText`'s own doc comment for why this,
        // not a bigger cap, is the actually-safe way to reach any row of a
        // huge category. Matches either the game's own display name or its
        // manufacturer — see `matchesDatabaseSearch(_:pattern:)`'s own doc
        // comment for exactly what counts as a match; a game with no
        // manufacturer just never matches on that half.
        //
        // For `.byManufacturer`/`.byYear`/the plain leaf list, filtering
        // each node individually (right here) is correct — those views
        // have no parent/clone nesting to break. `.allGames` is handled
        // separately below, AFTER building the family structure, not here.
        func matchesSearch(_ node: GameNode) -> Bool {
            searchText.isEmpty
                || Self.matchesDatabaseSearch(node.gameName, pattern: searchText)
                || Self.matchesDatabaseSearch((node.entries.first?.gameManufacturer ?? node.sourceGame?.manufacturer) ?? "", pattern: searchText)
        }

        if filter == .byManufacturer || filter == .byYear {
            if !searchText.isEmpty { realGames = realGames.filter(matchesSearch) }
            return groupedTreeChildren(realGames, by: filter, effectiveCap: effectiveCap, searchActive: !searchText.isEmpty)
        }

        guard filter == .allGames else {
            if !searchText.isEmpty { realGames = realGames.filter(matchesSearch) }
            let sorted = sortedByLowercasedKey(realGames, key: \.gameName)
            return capped(sorted.map { leafNode(for: $0) }, to: effectiveCap, filter: filter, searchActive: !searchText.isEmpty)
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

        // jensyleo's own report (2026-09-29): "Contra" es clon de
        // "Probotector" (a genuine, confirmed-correct No-Intro relationship
        // — Probotector Europe is modeled as the actual parent), but
        // searching "Probotector" showed it with no family at all. Root
        // cause: the OLD code filtered `realGames` by the search text
        // BEFORE this parent/clone grouping ran — "Contra" doesn't contain
        // "Probotector" in its own name, so it (and every other clone
        // whose own name doesn't happen to match the search) got dropped
        // before it ever had a chance to be attached to its parent, making
        // a family that genuinely has clones look like it has none. Now
        // grouped from the FULL, unfiltered list first, and only the
        // ROOTS get filtered by search afterward — keeping a root whenever
        // it OR any of its own (still-complete, unfiltered) clones
        // matches, so the whole family always shows together.
        if !searchText.isEmpty {
            roots = roots.filter { root in
                matchesSearch(root) || (clonesByParent[root.name]?.contains(where: matchesSearch) ?? false)
            }
        }

        let sortedRoots = sortedByLowercasedKey(roots, key: \.gameName)
        let cappedRoots = Array(sortedRoots.prefix(effectiveCap))
        var result = cappedRoots.map { root -> DatabaseTreeNode in
            let clones = sortedByLowercasedKey(clonesByParent[root.name] ?? [], key: \.gameName)
            // Clone children are still capped at the fixed default, not
            // `effectiveCap` — a parent with an unusually large clone
            // family (rare, but the same runaway-row risk applies)
            // shouldn't be able to bypass a cap either, and nesting the
            // same "Show more" affordance one level down isn't worth the
            // complexity for what's normally a handful of clones.
            return leafNode(for: root, children: capped(clones.map { leafNode(for: $0) }, to: Self.maxTreeChildrenPerCategory, filter: nil, searchActive: !searchText.isEmpty))
        }
        if sortedRoots.count > cappedRoots.count {
            result.append(loadMoreOrTruncationNotice(shown: cappedRoots.count, total: sortedRoots.count, filter: filter, searchActive: !searchText.isEmpty))
        }
        return result
    }

    /// Groups the full game list by manufacturer or year — jensyleo's own
    /// request (2026-08-11): "Fabricante y aparte fecha", two more
    /// RomCenter-style regroupings of the exact same "All games" list, not
    /// a new subset (see `DatabaseFilter.byManufacturer`/`.byYear`'s own
    /// doc comment). Top-level rows are the distinct manufacturer/year
    /// values themselves (sorted, a game with no declared value falling
    /// into one final "Unknown …" bucket); each one's own children are the
    /// games sharing it, plain leaves — no clone nesting one level further
    /// down, unlike "All games": the whole point here is to regroup by
    /// manufacturer/year, and re-introducing clone-vs-parent structure on
    /// top of that would just be confusing.
    ///
    /// Capped the same two-level way "All games" already is: `effectiveCap`
    /// (governed by search/"Show more" like every other category) bounds
    /// the group count itself; each individual group's own children are
    /// separately capped at the fixed default with a plain, non-interactive
    /// notice (not a nested "Show more" — one group rarely holds more than
    /// a handful of games in practice, so the added complexity of paginating
    /// *within* a group isn't worth it the way paginating the *group list*
    /// clearly is).
    private nonisolated static func groupedTreeChildren(_ games: [GameNode], by filter: DatabaseFilter, effectiveCap: Int, searchActive: Bool) -> [DatabaseTreeNode] {
        let unknownLabel = filter == .byManufacturer ? "Unknown manufacturer" : "Unknown year"
        var gamesByGroup: [String: [GameNode]] = [:]
        for game in games {
            let value = filter == .byManufacturer ? game.manufacturer : game.year
            let key = value.isEmpty ? unknownLabel : value
            gamesByGroup[key, default: []].append(game)
        }
        // The "Unknown …" bucket always sorts last — everything else in
        // plain ascending order (numeric year strings sort correctly as
        // plain strings for any realistic 4-digit range; a stray non-numeric
        // year value just falls back to alphabetical, which is still a
        // reasonable place for it to land).
        let sortedKeys = gamesByGroup.keys.sorted { lhs, rhs in
            if lhs == unknownLabel { return false }
            if rhs == unknownLabel { return true }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        let cappedKeys = Array(sortedKeys.prefix(effectiveCap))
        var result = cappedKeys.map { key -> DatabaseTreeNode in
            let groupGames = sortedByLowercasedKey(gamesByGroup[key] ?? [], key: \.gameName)
            let children = capped(groupGames.map { leafNode(for: $0) }, to: Self.maxTreeChildrenPerCategory, filter: nil, searchActive: searchActive)
            return DatabaseTreeNode(id: "group-\(filter.rawValue)-\(key)", machineName: "", label: "\(key) (\(groupGames.count))", status: nil, children: children)
        }
        if sortedKeys.count > cappedKeys.count {
            result.append(loadMoreOrTruncationNotice(shown: cappedKeys.count, total: sortedKeys.count, filter: filter, searchActive: searchActive))
        }
        return result
    }

    /// Truncates to `cap`, appending either an interactive "Show N more" row
    /// (when `filter` is non-nil and no search is active — a category-level
    /// cap the user can raise a bounded step at a time) or a plain,
    /// non-selectable notice (a clone sub-list, or a search whose match
    /// count still hit the defensive `maxSearchResultsCap` backstop) — an
    /// empty `children` array here (rather than this whole function
    /// returning early) is the correct "nothing to show" case, not an error.
    private nonisolated static func capped(_ nodes: [DatabaseTreeNode], to cap: Int, filter: DatabaseFilter?, searchActive: Bool) -> [DatabaseTreeNode] {
        guard nodes.count > cap else { return nodes }
        var result = Array(nodes.prefix(cap))
        result.append(loadMoreOrTruncationNotice(shown: result.count, total: nodes.count, filter: filter, searchActive: searchActive))
        return result
    }

    private nonisolated static func loadMoreOrTruncationNotice(shown: Int, total: Int, filter: DatabaseFilter?, searchActive: Bool) -> DatabaseTreeNode {
        guard let filter, !searchActive else { return truncationNotice(shown: shown, total: total) }
        return DatabaseTreeNode(
            id: "loadmore-\(filter.rawValue)-\(shown)-of-\(total)",
            machineName: "",
            label: "Show \(min(Self.treeLoadMoreIncrement, total - shown)) more (\(total - shown) left) — or use the Games table for the full list",
            status: nil,
            children: nil,
            isTruncationNotice: false,
            loadMoreFilter: filter
        )
    }

    private nonisolated static func truncationNotice(shown: Int, total: Int) -> DatabaseTreeNode {
        DatabaseTreeNode(
            id: "truncated-\(shown)-of-\(total)",
            machineName: "",
            label: "…and \(total - shown) more — use the Games table for the full list",
            status: nil,
            children: nil,
            isTruncationNotice: true
        )
    }

    private nonisolated static func leafNode(for game: GameNode, children: [DatabaseTreeNode]? = nil) -> DatabaseTreeNode {
        // Any entry carries the same game-level `gameManufacturer` (see
        // `AuditReporter.generate`'s own doc comment: computed once per
        // game, shared by every rom row it produces) — the first one found
        // is enough. Falls back to `sourceGame.manufacturer` (the DAT's own
        // catalog entry) for the unscanned-catalog case (`unscannedCatalogNodes`),
        // whose `entries` is always empty by design (no scan has run yet to
        // produce any) — without this, every game would show no
        // manufacturer at all until the first scan.
        let manufacturer = game.entries.first?.gameManufacturer ?? game.sourceGame?.manufacturer
        return DatabaseTreeNode(id: game.id, machineName: game.name, label: game.gameName, status: game.aggregateStatus, manufacturer: manufacturer, children: children)
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
                        refreshExpandedDatabaseCategoryCachesAsync(debounced: false, only: filter)
                    } else {
                        // Already cached from a previous expand — no async
                        // gap to wait out, so this can scroll immediately
                        // instead of relying on the async path's own
                        // completion call. See `scrollDatabaseListToSelectedGameIfNewlyVisible()`'s
                        // own doc comment.
                        scrollDatabaseListToSelectedGameIfNewlyVisible()
                    }
                } else {
                    expandedDatabaseCategories.remove(filter)
                    databaseCategoryVisibleCap.removeValue(forKey: filter)
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
            // Arrow-key expand/collapse is handled centrally on the
            // enclosing `List` itself, not per-row here — see
            // `databaseListContent`'s own doc comment for why a per-row
            // `.onKeyPress` (the first attempt) never reliably fired.
            DisclosureGroup(isExpanded: gameTreeNodeExpansion(for: node.id)) {
                ForEach(children) { child in databaseTreeNodeRow(child, filter: filter) }
            } label: {
                databaseTreeLeafLabel(node, filter: filter)
            }
        )
    }

    /// Explicit, externally-settable expansion for one game row's own clone
    /// disclosure — see `expandedGameTreeNodes`'s own doc comment for why
    /// this can't just be the `DisclosureGroup`'s usual internal state.
    private func gameTreeNodeExpansion(for id: String) -> Binding<Bool> {
        Binding(
            get: { expandedGameTreeNodes.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedGameTreeNodes.insert(id) } else { expandedGameTreeNodes.remove(id) }
            }
        )
    }

    @ViewBuilder
    private func databaseTreeLeafLabel(_ node: DatabaseTreeNode, filter: DatabaseFilter) -> some View {
        if let loadMoreFilter = node.loadMoreFilter {
            Button {
                let current = databaseCategoryVisibleCap[loadMoreFilter] ?? Self.maxTreeChildrenPerCategory
                databaseCategoryVisibleCap[loadMoreFilter] = current + Self.treeLoadMoreIncrement
                refreshExpandedDatabaseCategoryCachesAsync(debounced: false, only: loadMoreFilter)
                isDatabasePaneFocused = true
                resultsPaneIsActive = false
            } label: {
                Text(node.label)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        } else if node.isTruncationNotice {
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
            HStack(spacing: 4) {
                // Always a real game here — `treeChildren(forCategory:)`
                // excludes the synthetic "Unknown game" bucket before
                // building tree leaves at all. Its own explicit
                // `.foregroundStyle` always wins over the row's ambient
                // one set below, so the red/yellow/green status color
                // stays visible even while this row is selected and
                // tinted with the accent color.
                if let status = liveStatus {
                    Image(systemName: symbolName(for: status)).foregroundStyle(status.tint)
                } else {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                }
                Text(node.label)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                // RomCenter-style manufacturer, trailing — jensyleo's
                // own request (2026-08-11). Secondary/muted so it never
                // competes with the game's own name for attention.
                if let manufacturer = node.manufacturer, !manufacturer.isEmpty {
                    Text(manufacturer)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                // jensyleo's own report (2026-08-13): "haz que seleccionar
                // la fila... sea suficiente... igual que en ROM Folder" —
                // this used to be a `Button` whose label was just the
                // icon+text+manufacturer `HStack`, so only THAT tight
                // content actually caught a click; the row's own
                // `.listRowBackground` highlight already spanned the full
                // row width, misleadingly implying the whole row was
                // clickable when it wasn't.
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            // A plain `.onTapGesture` here (first attempt, same pattern as
            // `romFolderRow(for:)`) never fired: unlike that row, this one
            // is a *child of a `DisclosureGroup`* inside the List — macOS's
            // outline-backed List claims the mouse-down on disclosure child
            // rows for its own row-selection tracking, and `.onTapGesture`
            // is an EXCLUSIVE gesture that competes with it for the click.
            // A second attempt overlaid a real `Button` instead — that
            // avoided losing the click, but caused something worse: a
            // genuine app freeze (confirmed with `sample`), because
            // `NSOutlineView.mouseDown(_:)` runs its own nested tracking
            // loop (`trackEventsMatchingMask:timeout:mode:handler:`) that
            // waits for the matching mouse-up, and SwiftUI's `Button`
            // consumed that mouse-up for its own action before the
            // outline's loop ever saw it, leaving that inner loop stuck
            // waiting forever. `.simultaneousGesture` fixes both: it does
            // NOT claim exclusivity, so it doesn't lose to the outline's
            // own mouseDown, and it doesn't consume the mouse-up either —
            // the outline's tracking loop still completes normally.
            .simultaneousGesture(
                TapGesture().onEnded {
                    selectedDatabaseFilter = filter
                    selectedRomFolder = nil
                    selectedGameID = node.id
                    isDatabasePaneFocused = true
                    resultsPaneIsActive = false
                    // jensyleo's own report (2026-08-13): landing on a parent
                    // game (one with its own clone family nested under it), OR
                    // on one of its own clones, should scope "Games" to that
                    // same family either way — see `familyRootMachineName(for:)`'s
                    // own doc comment.
                    selectedGameFamilyRootMachineName = familyRootMachineName(for: node)
                    // jensyleo's own report (2026-08-13): clicking a leaf here
                    // (search results included) never scrolled the Games
                    // table to reveal the row it just selected — see
                    // `moveDatabaseSelection(by:)`'s own doc comment for the
                    // same fix on the arrow-key path. `revealAndScrollGamesTable(to:)`
                    // also expands the visible page first if the row isn't
                    // in it yet (jensyleo's own follow-up report, 2026-09-29).
                    revealAndScrollGamesTable(to: node.id)
                }
            )
            // A real selection background, not just bold text — same
            // pattern (and same reasoning) as the "ROM folder" section's
            // own row highlight, see `controlActiveState`'s own doc
            // comment: accent-tinted while this window is key, dimmed to
            // gray once it isn't, matching native List/NSTableView
            // selection instead of a static color.
            .listRowBackground(
                isSelected
                    ? (controlActiveState == .inactive ? Color.gray.opacity(0.35) : Color.accentColor.opacity(0.85))
                    : Color.clear
            )
            .foregroundStyle(isSelected && controlActiveState != .inactive ? Color.white : Color.primary)
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
    /// `precomputedScoped`, when given, is this exact same scope's entries
    /// the caller already built via `Self.scoped(...)` for its own use
    /// (e.g. `computeScopedStatusCounts`'s input) — real measured cost
    /// found live (2026-08-25 perf investigation, instrumented with
    /// `CFAbsoluteTimeGetCurrent()` around each stage of a folder click on
    /// a ~324k-entry real MAME collection): a single click was silently
    /// running `scoped(...)`'s own O(entries) filter TWICE — once here by
    /// the caller for its own use, once again inside this function from
    /// the same raw `auditEntries`/`selectedDatabaseFilter`/
    /// `selectedRomFolder`/`gamesInFolder` — for no reason, since both
    /// calls always compute the exact same result. Measured ~104ms for
    /// the standalone `scoped(...)` call plus another duplicate pass
    /// hidden inside the ~148ms `computeBaseGameNodes` step, out of a
    /// ~374ms total per click. Passing the already-built result through
    /// instead of recomputing it removes that duplicate pass entirely.
    /// Falls back to computing it here when a caller has no other need for
    /// it.
    ///
    /// Real bug found live (2026-08-25 performance audit): the four
    /// display-only toggles (`activeStatusFilters`/`showUnknownArchives`/
    /// `combineRomAndCHD`/`show1G1ROnly`) used to call a separate,
    /// synchronous `recomputeGameNodes()` that ran this exact same
    /// ~350ms-per-click O(entries) work directly on the main thread — the
    /// same freeze `triggerCachedGameDataRecompute()` (below) was already
    /// built to fix for folder/category clicks, just left unfixed here.
    /// Measured directly against the real ~324k-entry collection (release
    /// build, `GameNodeBuilder.scoped`+`gameNodes` alone, "All games"):
    /// ~340-380ms per call. Those four toggles now go through
    /// `triggerCachedGameDataRecompute()` too, so the same work runs off
    /// the main thread instead.
    private nonisolated static func computeBaseGameNodes(
        hasAuditReport: Bool, auditEntries: [AuditEntry], selectedRomFolder: URL?, preloadedGames: [DATGame], selectedDatabaseFilter: DatabaseFilter?,
        gamesInFolder: Set<String>, gameAggregateStatusByName: [String: AuditStatus], combineRomAndCHD: Bool,
        precomputedScoped: [AuditEntry]? = nil
    ) -> [GameNode] {
        if !hasAuditReport, selectedRomFolder == nil, !preloadedGames.isEmpty {
            return sortedByLowercasedKey(unscannedCatalogNodes(matching: selectedDatabaseFilter ?? .allGames, preloadedGames: preloadedGames), key: \.name)
        }
        let scopedEntries = precomputedScoped ?? scoped(auditEntries, databaseFilter: selectedDatabaseFilter, romFolder: selectedRomFolder, gamesInFolder: gamesInFolder)
        return gameNodes(
            from: scopedEntries,
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
    /// Real slowness found live (2026-08-13, jensyleo: keyboard navigation
    /// starting from/through "All games" — up to ~45,000 rows — felt
    /// slow). `localizedCaseInsensitiveCompare` is locale-aware (full ICU
    /// collation), and every one of these "Database" tree-building call
    /// sites used to call it once per comparison during a sort — for a
    /// large category, that's on the order of `n log n` locale-aware
    /// string comparisons on every single rebuild. Display ordering here
    /// has no real dependence on locale-specific collation rules, so the
    /// sort key is computed once per element up front (`n` calls to
    /// `lowercased()`) and compared with the plain `<` operator (a fast
    /// ordinal comparison, no ICU tables) instead — same fix as
    /// `GameNodeBuilder`'s own equivalent sort in ROMForgeCore.
    private nonisolated static func sortedByLowercasedKey<T>(_ items: [T], key: (T) -> String) -> [T] {
        items.map { ($0, key($0).lowercased()) }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    private nonisolated static func gamesByName(_ games: [DATGame]) -> [String: DATGame] {
        var result: [String: DATGame] = [:]
        for game in games where result[game.name.lowercased()] == nil {
            result[game.name.lowercased()] = game
        }
        return result
    }

    /// Same display-only transform as `GameTreeTableView`'s own copy (that
    /// file can't reach this one's `private` `gamesByName` above, hence the
    /// duplication — same reasoning as `gameColumnCustomizationKey`'s own
    /// doc comment on why that's duplicated too) — see that copy's own doc
    /// comment for why `GameNode.requiredBiosNames` itself stays a bare
    /// internal machine name and this formatting never touches it.
    private func displayRequiredBiosNames(_ rawNames: String) -> String {
        guard !rawNames.isEmpty else { return rawNames }
        let gamesByName = Self.gamesByName(viewModel.preloadedGames)
        return rawNames.split(separator: ",").map { rawName -> String in
            let trimmed = rawName.trimmingCharacters(in: .whitespaces)
            guard let biosGame = gamesByName[trimmed.lowercased()] else { return trimmed }
            return "\(biosGame.description) / \(biosGame.name).zip"
        }.joined(separator: ", ")
    }

    /// Resolves a raw internal machine name (e.g. the DAT's own `cloneof`
    /// attribute, "dlair") to that game's own human-readable `description`
    /// ("Dragon's Lair (US Rev. F2)") — jensyleo's own report (2026-08-17):
    /// the "Clone of" column/detail row used to show the raw name verbatim,
    /// reading exactly like a "File name" value (they're often identical
    /// strings) right next to "Game name"/"Internal name" rows that make
    /// the real distinction, which reads as confusing/inconsistent. Falls
    /// back to the raw name itself only if no game by that name is found in
    /// the loaded DAT at all (shouldn't normally happen — `cloneof` always
    /// names a real machine in the same DAT).
    private func gameDescription(forMachineName name: String) -> String {
        gamesByNameCache.games(from: viewModel.preloadedGames)[name.lowercased()]?.description ?? name
    }

    /// Applies the `showUnknownArchives`/`activeStatusFilters` toggles to
    /// `computeBaseGameNodes(...)`'s result — a separate step (not fused
    /// into it) for the same reason as `computeUnknownArchivesCount(baseNodes:)`
    /// above: both need that same unfiltered pass, just filtered
    /// differently afterward.
    private nonisolated static func computeGameNodes(
        baseNodes: [GameNode], gameAggregateStatusByName: [String: AuditStatus], showUnknownArchives: Bool,
        activeStatusFilters: Set<AuditStatus>, hiddenOneGameOneROMNames: Set<String> = []
    ) -> [GameNode] {
        // Grouped from *every* entry (not status-filtered — a game's real
        // category must never depend on which rows happen to be visible
        // elsewhere), then the four toggles filter the resulting *games*
        // by that true category. See `statusSummary`'s own doc comment
        // for exactly what each of the four means.
        baseNodes.filter { node in
            guard !hiddenOneGameOneROMNames.contains(node.name) else { return false }
            // A genuinely unrecognized archive ("Unknown game") isn't one
            // of the four real categories at all — it's gated by its own
            // separate "Unknown" toggle instead. A surplus bucket
            // `gameNodes(from:)` reclassified yellow instead (`.incorrect`,
            // fully identified elsewhere — see its own `isFullyIdentified`
            // doc comment) is controlled by that color's own "Incorrect"
            // toggle — jensyleo's own question (2026-08-04): only a
            // genuinely unrecognized bucket belongs to the separate
            // "Unknown" toggle at all.
            //
            // jensyleo's own report (2026-08-13): this used to check
            // `node.aggregateStatus == .surplus` — but `GameNodeBuilder
            // .gameNodes(from:)` never actually assigns `.surplus` to a
            // surplus bucket (`.surplus` is legacy/decode-only — see
            // `AuditStatus.surplus`'s own doc comment); a real surplus
            // bucket gets `.unknownFile` (or `.incorrect`, handled by the
            // `else` branch already). That made the condition always
            // false, so a genuinely unrecognized file (e.g. a real `.7z`
            // with no matching DAT rom) fell through to the `else` branch
            // and was gated by the four status buttons instead of the
            // dedicated "Unknown" toggle — reading as if it had vanished
            // entirely whenever `.unknownFile` wasn't part of whatever the
            // status buttons happened to leave in `activeStatusFilters`.
            if node.isSurplusBucket {
                return node.aggregateStatus == .unknownFile || node.aggregateStatus == .surplus
                    ? showUnknownArchives : activeStatusFilters.contains(node.aggregateStatus ?? .unknownFile)
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
    /// Body moved to `GameStatusRollup.gameCategory(for:)` (ROMForgeCore,
    /// 2026-08-13, "Grupo A" of the App-logic extraction) so it's
    /// unit-testable — this stays as a thin delegate rather than being
    /// removed, so every existing call site above needs no change.
    private nonisolated static func gameCategory(for entries: [AuditEntry]) -> AuditStatus {
        GameStatusRollup.gameCategory(for: entries)
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
        GameStatusRollup.romOnlyGameCategory(for: entries)
    }

    /// Every real game's current true category, by name — see
    /// `gameAggregateStatusByName`'s own doc comment for why this exists.
    /// Deliberately built from *every* entry in the report, not
    /// `filteredEntries` — a game's real category shouldn't change just
    /// because the user hid, say, "Missing" rows from view elsewhere.
    private nonisolated static func computeGameAggregateStatusByName(entries: [AuditEntry], preloadedGames: [DATGame]) -> [String: AuditStatus] {
        var byGame: [String: [AuditEntry]] = [:]
        var surplusByArchive: [String: [AuditEntry]] = [:]
        for entry in entries {
            if let game = entry.game {
                byGame[game, default: []].append(entry)
            } else {
                surplusByArchive[Self.surplusArchiveKey(for: entry), default: []].append(entry)
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
        let gamesByName = Self.gamesByName(preloadedGames)
        for (archiveKey, surplus) in surplusByArchive {
            let matchingGame = (Self.surplusDisplayName(forArchiveKey: archiveKey) as NSString).deletingPathExtension
            guard gamesByName[matchingGame] != nil else { continue }
            byGame[matchingGame, default: []].append(contentsOf: surplus)
        }
        return byGame.mapValues(Self.romOnlyGameCategory(for:))
    }

    private var selectedGameNode: GameNode? {
        guard let selectedGameID else { return nil }
        if isSelectedFolderMaintenanceSubfolder { return maintenanceGameNodesByID[selectedGameID] }
        return cachedGameNodesByID[selectedGameID]
    }

    /// `uniquingKeysWith` keeps the first match, same first-wins semantics
    /// the old `cachedGameNodes.first { $0.id == ... }` linear scan had.
    private nonisolated static func indexByID(_ nodes: [GameNode]) -> [String: GameNode] {
        Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Reads every zip's own archive comment in `urls`, off Swift
    /// concurrency's own cooperative thread pool entirely — see
    /// `triggerCachedGameDataRecompute()`'s own doc comment (jensyleo's
    /// report, 2026-09-26: the app froze solid on literally any click,
    /// "Database" categories included) for the full root-cause. A plain
    /// `DispatchQueue` gets real OS threads on demand, unlike
    /// `Task.detached`, which still shares the small, fixed-size pool
    /// EVERY `await` in the app depends on to make progress — a blocking,
    /// synchronous loop of possibly thousands of NAS reads has no business
    /// running there. `.userInitiated` here is the GCD QoS class (a
    /// scheduling hint for these plain OS threads), unrelated to — and
    /// safe to use alongside — the `Task.detached(priority: .userInitiated)`
    /// callers already run under.
    /// jensyleo's own report (2026-09-26): a single, isolated click from
    /// KONAMI to CPS1 (no burst, nothing else competing) still took up to
    /// 7 real seconds to update. Root cause: this used to read every URL
    /// SEQUENTIALLY, one at a time, in a single dispatched block — moving
    /// the work off Swift concurrency's cooperative pool (the earlier fix,
    /// same day) never made the reads themselves run concurrently. For a
    /// NAS-backed folder, each `ZipCommentReader.comment(ofZipAt:)` is a
    /// real network round trip (open + seek-to-end + read); at even
    /// 50-70ms apiece, ~100 archives in a folder like CPS1 adds up to
    /// exactly this kind of multi-second wait, one file at a time.
    /// `DispatchQueue.concurrentPerform` (same pattern already proven in
    /// `AuditReportDatabase.loadEntries`'s own parallel rowid-partitioned
    /// read, ROMForgeCore) lets the NAS/filesystem serve many of these
    /// small reads at once instead — each worker writes only to its own
    /// disjoint slot in a pre-sized array (no lock needed, no data race),
    /// then the results are zipped back into the URL-keyed dictionary the
    /// caller expects.
    /// `@unchecked Sendable` wrapper for the raw buffer `readZipComments`
    /// below writes into from `DispatchQueue.concurrentPerform` — genuinely
    /// safe (every worker writes only to its own disjoint `index`, never
    /// touching another's slot, same guarantee `AuditReportDatabase
    /// .loadEntries`'s own identical pattern, ROMForgeCore, already
    /// documents), but `UnsafeMutableBufferPointer` itself isn't Sendable,
    /// so the compiler can't verify that on its own — this box is the
    /// explicit, audited assertion that it's fine here, rather than a
    /// plain `var` array silently tripping the same checker with no
    /// documented reasoning at all (real audit finding, 2026-09-26).
    private struct DisjointWriteBuffer: @unchecked Sendable {
        let pointer: UnsafeMutableBufferPointer<String?>
    }

    private static func readZipComments(_ urls: Set<URL>) async -> [URL: String?] {
        guard !urls.isEmpty else { return [:] }
        let orderedURLs = Array(urls)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let rawBuffer = UnsafeMutableBufferPointer<String?>.allocate(capacity: orderedURLs.count)
                rawBuffer.initialize(repeating: nil)
                defer { rawBuffer.deinitialize(); rawBuffer.deallocate() }
                let buffer = DisjointWriteBuffer(pointer: rawBuffer)
                DispatchQueue.concurrentPerform(iterations: orderedURLs.count) { index in
                    buffer.pointer[index] = ZipCommentReader.comment(ofZipAt: orderedURLs[index])
                }
                var results: [URL: String?] = [:]
                results.reserveCapacity(orderedURLs.count)
                for (index, url) in orderedURLs.enumerated() {
                    results[url] = rawBuffer[index]
                }
                continuation.resume(returning: results)
            }
        }
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
    /// Real gap found live by jensyleo (2026-09-23): "las opciones de Play
    /// in MAME, Reveal in Finder siempre deben pedir rescan... toda
    /// interacción con lo que muestra la app debe tener un escaneo previo"
    /// — these two never checked for one at all, unlike every write action
    /// in this app (which already refuse via `scopeCoveredByLastScan`).
    /// `viewModel.auditReport != nil` is the same bar every Fix toolbar
    /// button already uses for "there's a real result to act on" — it's
    /// `true` once EITHER a live scan ran this session OR a past session's
    /// persisted result was restored on open, `false` only for a system
    /// that's genuinely never been scanned at all.
    /// `true` for MAME, `true` for any non-MAME (console/computer) system
    /// — the two kinds this whole feature knows how to launch, gated on
    /// whichever one's own emulator is actually configured
    /// (`isEmulatorInstalled`). Anything else `canLaunchInEmulator(_:)`
    /// already checks (a real scan, a non-surplus row) applies to both.
    /// MAME for an Arcade system; the user's own configured choice
    /// (`ConsoleEmulatorSettings.selected`, Settings → Systems → Consoles)
    /// for a console/computer one — jensyleo's own request (2026-09-29):
    /// unlike MAME, a console system's emulator "no es único," so this is
    /// never hardcoded.
    private var emulatorName: String {
        system.isMAMEStyle ? "MAME" : ConsoleEmulatorSettings.selected.displayName
    }

    /// `true` only when the RIGHT emulator for this system's own kind is
    /// genuinely installed right now — jensyleo's own request (2026-09-29):
    /// "Play in MAME" and its siblings (and now their console-system
    /// counterpart) should only ever appear when that emulator is actually
    /// installed, never just because a stale/explicit setting happens to
    /// be non-empty. See `MAMELaunchSettings.isInstalled`/
    /// `ConsoleEmulatorSettings.isInstalled`'s own doc comments for why
    /// each needed its own re-verified-on-every-call check rather than
    /// trusting a cached path string.
    private var isEmulatorInstalled: Bool {
        system.isMAMEStyle ? MAMELaunchSettings.isInstalled : ConsoleEmulatorSettings.isInstalled
    }

    /// Real gap found live by jensyleo (2026-09-23): "las opciones de Play
    /// in MAME, Reveal in Finder siempre deben pedir rescan... toda
    /// interacción con lo que muestra la app debe tener un escaneo previo"
    /// — these two never checked for one at all, unlike every write action
    /// in this app (which already refuse via `scopeCoveredByLastScan`).
    /// `viewModel.auditReport != nil` is the same bar every Fix toolbar
    /// button already uses for "there's a real result to act on" — it's
    /// `true` once EITHER a live scan ran this session OR a past session's
    /// persisted result was restored on open, `false` only for a system
    /// that's genuinely never been scanned at all.
    ///
    /// For MAME, an unrecognized/"Unknown game" row (`isSurplusBucket`) has
    /// no real DAT machine name behind it — MAME itself needs one to
    /// launch anything at all, so this exclusion is structural, not a
    /// judgment call. For a console/computer system, "Play" launches by
    /// FILE, not by machine name — jensyleo's own report (2026-09-29): a
    /// gray, unrecognized NES file is still a perfectly real, playable ROM
    /// file on disk, the exact same one "Reveal in Finder" (never gated on
    /// `isSurplusBucket` at all) already opens — there's no reason Nestopia/
    /// FCEUX/a custom emulator couldn't open it too, matched to a DAT
    /// entry or not. Gated on `actualFileURL(for:)` instead: `true` for
    /// any row with a genuine file behind it, `isSurplusBucket` or not.
    private func canLaunchInEmulator(_ node: GameNode) -> Bool {
        let hasLaunchableFile = system.isMAMEStyle ? !node.isSurplusBucket : actualFileURL(for: node) != nil
        return hasLaunchableFile && isEmulatorInstalled && viewModel.auditReport != nil
    }

    private var canLaunchSelectedGameInEmulator: Bool {
        selectedGameNode.map(canLaunchInEmulator) ?? false
    }

    private var playButtonHelpText: String {
        guard isEmulatorInstalled else {
            if system.isMAMEStyle { return "Locate a MAME executable in Settings → Systems first" }
            if let installCommand = ConsoleEmulatorSettings.selected.installCommand {
                return "Install \(ConsoleEmulatorSettings.selected.displayName) (`\(installCommand)`) in Settings → Systems → Consoles, or configure one there"
            }
            return "Locate an emulator in Settings → Systems → Consoles first"
        }
        guard viewModel.auditReport != nil else { return "Scan this system at least once first" }
        guard let node = selectedGameNode, canLaunchInEmulator(node) else { return "Select a game to play it in \(emulatorName)" }
        return "Launch \(node.gameName) in \(emulatorName) to test it"
    }

    private func launchSelectedGameInEmulator() {
        guard let node = selectedGameNode else { return }
        launchInEmulator(node)
    }

    /// jensyleo's own request (2026-08-17): a launch failure — which used
    /// to show in its own separate `errorMessage` sheet — belongs in the
    /// Log panel like everything else this view reports, in red so it
    /// still reads as an error at a glance ("mantén el color rojo del
    /// error"). No bespoke presentation to maintain, and no risk of a long
    /// diagnostic distorting the main window's own layout the way the very
    /// first version of this fix (an unbounded inline `Text`) did. Applies
    /// to both `MAMELauncher`/`ConsoleEmulatorLauncher` — this dispatches
    /// to whichever one `system.isMAMEStyle` actually calls for.
    private func launchInEmulator(_ node: GameNode) {
        if system.isMAMEStyle {
            do {
                try MAMELauncher.launch(machineName: node.name, romFolders: system.romFolderURLs) { reason in
                    // MAME's own termination handler fires on a background
                    // queue, not the main actor `logError` needs to be
                    // touched from.
                    Task { @MainActor in
                        viewModel.logError("MAME couldn't run \(node.gameName):\n\n\(reason)")
                    }
                }
            } catch let error as MAMELauncher.LaunchError {
                viewModel.logError(error.description)
            } catch {
                viewModel.logError("Failed to launch MAME: \(error.localizedDescription)")
            }
            return
        }
        guard let fileURL = actualFileURL(for: node) else {
            viewModel.logError("Couldn't find \(node.gameName)'s own file on disk to launch.")
            return
        }
        let emulatorLabel = emulatorName
        do {
            try ConsoleEmulatorLauncher.launch(romFileURL: fileURL) { reason in
                Task { @MainActor in
                    viewModel.logError("\(emulatorLabel) couldn't open \(node.gameName):\n\n\(reason)")
                }
            }
        } catch let error as ConsoleEmulatorLauncher.LaunchError {
            viewModel.logError(error.description)
        } catch {
            viewModel.logError("Failed to launch \(emulatorLabel): \(error.localizedDescription)")
        }
    }

    /// Saves `FixDatExporter`'s own output for the current `auditReport` —
    /// jensyleo's own request (2026-08-18): ClrMamePro/RomVault's own
    /// "Fix-DatFiles", a small DAT holding only what this scan found
    /// missing/incorrect, for another DAT-aware tool (or a plain search)
    /// to target instead of the whole collection. Named after the loaded
    /// DAT itself (falling back to the system's own name) so several
    /// systems' exports don't all collide on one generic filename.
    private func exportFixDat() {
        guard let report = viewModel.auditReport else { return }
        let datName = viewModel.datHeader?.name ?? system.name
        let xml = FixDatExporter.generate(from: report, datName: datName)

        let panel = NSSavePanel()
        panel.title = "Export Fix DAT"
        panel.message = "Contains only this scan's missing/incorrect entries — hand it to another DAT-aware tool to find exactly the gap."
        panel.nameFieldStringValue = "fixDat_\(datName).dat"
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try xml.write(to: url, atomically: true, encoding: .utf8)
            viewModel.log("Exported Fix DAT to \(url.path)")
        } catch {
            viewModel.logError("Failed to export Fix DAT: \(error.localizedDescription)")
        }
    }

    /// Saves `cachedGameNodes` — the games table exactly as currently
    /// rendered, filters/category already applied — as a CSV file.
    /// jensyleo's own request (2026-08-18): RomCenter/ClrMamePro's own
    /// "Save results as text file". Deliberately reads `cachedGameNodes`
    /// rather than re-deriving from `viewModel.auditReport` — the two can
    /// disagree whenever a status filter or "show unknown" toggle is
    /// active, and the point of this export is "what I'm looking at right
    /// now", not the raw underlying report.
    private func exportGameListCSV() {
        guard !cachedGameNodes.isEmpty else { return }
        let header = ["Status", "Game name", "File name", "Info", "Expected file name", "Clone of", "Year", "Manufacturer"]
        let rows = cachedGameNodes.map { node -> [String] in
            [
                node.aggregateStatus.map(String.init(describing:)) ?? "",
                node.gameName,
                node.actualFileName ?? node.name,
                infoText(for: node),
                node.expectedFileName ?? "",
                node.cloneOf.isEmpty ? "" : gameDescription(forMachineName: node.cloneOf),
                node.year,
                node.manufacturer,
            ]
        }
        let csv = ([header] + rows)
            .map { $0.map(Self.csvField).joined(separator: ",") }
            .joined(separator: "\r\n")

        let panel = NSSavePanel()
        panel.title = "Export List to CSV"
        panel.message = "Saves the games list exactly as currently displayed (filters included)."
        panel.nameFieldStringValue = "\(system.name).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            viewModel.log("Exported game list to \(url.path)")
        } catch {
            viewModel.logError("Failed to export CSV: \(error.localizedDescription)")
        }
    }

    /// Quotes `field` only when it actually needs it (contains a comma,
    /// quote, or newline) — RFC 4180's own minimal-quoting convention,
    /// keeps plain values (the vast majority here) readable unquoted.
    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
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

    /// The Roms panel's own counterpart to `moveGameSelection(by:)` — same
    /// macOS 27 native-`Table`-arrow-navigation regression, same fix. See
    /// that function's own doc comment for the full story.
    private func moveRomSelection(by offset: Int) {
        let rows = selectedRomRows
        guard !rows.isEmpty else { return }
        let currentIndex = selectedRomID.flatMap { id in rows.firstIndex { $0.id == id } }
        let newIndex: Int
        if let currentIndex {
            newIndex = max(0, min(rows.count - 1, currentIndex + offset))
        } else {
            newIndex = offset < 0 ? rows.count - 1 : 0
        }
        selectedRomID = rows[newIndex].id
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
            ForEach(gameFieldOrder) { field in gameDetailRow(field, for: node) }
        }
    }

    /// `DetailPanelGameFieldSettings.fieldOrderKey` parsed into the order
    /// `gameDetailSection` actually renders in — jensyleo's own request,
    /// "deja que esto sea organizable por el usuario". A computed property
    /// (not cached in `@State`) so it re-reads fresh, and therefore stays
    /// live, every time the backing `@AppStorage` string changes — the same
    /// "plain `@AppStorage` value, re-derived on every body evaluation"
    /// shape every other cross-window-reactive setting in this view
    /// already uses; see `parseGameFieldOrder`'s own doc comment for the
    /// missing-case fallback.
    private var gameFieldOrder: [DetailGameField] { parseGameFieldOrder(gameFieldOrderRaw) }

    /// One row of `gameDetailSection`, keyed by which `DetailGameField`
    /// `gameFieldOrder` says goes here — the switch itself is the
    /// authoritative mapping from field identity to both its own
    /// `@AppStorage` visibility flag and its actual content, mirroring
    /// `gameTreeTableContent`'s own `TableColumn`s one for one (see
    /// `DetailPanelGameFieldSettings`'s own doc comment for why).
    @ViewBuilder
    private func gameDetailRow(_ field: DetailGameField, for node: GameNode) -> some View {
        switch field {
        case .fileName:
            if showDetailGameFileName { infoRow("File name", node.actualFileName ?? node.name) }
        case .expectedFileName:
            if showDetailExpectedFileName { infoRow("Expected file name", node.expectedFileName ?? "") }
        case .size:
            if showDetailGameSize { infoRow("Size", totalSizeText(for: node)) }
        case .oneGameOneROM:
            if showDetailOneGameOneROM { oneGameOneROMDetailRow(node) }
        case .info:
            if showDetailInfo {
                coloredInfoRow("Info", infoText(for: node), tint: node.aggregateStatus?.tint ?? .secondary)
                regionQualityDetailRow(for: node)
            }
        case .cloneOf:
            if showDetailGameCloneOf {
                infoRow("Clone of", node.cloneOf.isEmpty ? "" : gameDescription(forMachineName: node.cloneOf))
            }
        case .requiredBios:
            if showDetailRequiredBios { infoRow("Required BIOS", displayRequiredBiosNames(node.requiredBiosNames)) }
        case .chd:
            if showDetailCHD { infoRow("CHD", node.chdNames) }
        case .samples:
            if showDetailSamples { infoRow("Samples", node.samplesText) }
        case .bios:
            if showDetailBios { infoRow("BIOS", node.biosText) }
        case .year:
            if showDetailYear { infoRow("Year", node.year) }
        case .manufacturer:
            if showDetailManufacturer { infoRow("Manufacturer", node.manufacturer) }
        case .category:
            if showDetailCategory { infoRow("Category", node.category) }
        case .deviceRefs:
            if showDetailDeviceRefs { infoRow("Device refs", node.deviceRefNames) }
        case .cloneOfInternalName:
            if showDetailCloneOfInternalName { infoRow("Clone of (internal name)", node.cloneOf) }
        case .family:
            if showDetailFamily { familyDetailRow(node) }
        case .dependencies:
            if showDetailDependencies { dependenciesDetailRow(node) }
        case .details:
            if showDetailDetails { detailsDetailRow(node) }
        }
    }

    /// Labeled "1G1R" row for the Detail panel — the exact same star
    /// `gameTreeTableContent`'s own "1G1R" column shows, just with a label
    /// in front of it like every other row here, since `infoRow` only
    /// takes plain text. Skipped entirely when this game isn't its
    /// family's preferred variant, same "nothing to say, don't show the
    /// row" convention as `infoRow`.
    @ViewBuilder
    private func oneGameOneROMDetailRow(_ node: GameNode) -> some View {
        if cachedOneGameOneROMSummary.preferredGameNames.contains(node.name) {
            HStack(spacing: 8) {
                Text("1G1R").bold().frame(width: 100, alignment: .leading)
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .help("The preferred 1G1R variant for this family, per Settings → View Options → \"1G1R region priority\"")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Labeled "Family" row for the Detail panel — same content as
    /// `gameTreeTableContent`'s own "Family" column (`familyIndicator`),
    /// just with a label in front like every other row here. Skipped
    /// entirely under the same conditions `familyIndicator` itself
    /// resolves to `EmptyView` for (a surplus/disk row never reaches here
    /// anyway, so only the "nothing to report" case matters in practice).
    @ViewBuilder
    private func familyDetailRow(_ node: GameNode) -> some View {
        if cachedParentCloneSummary.cloneCompletionByParent[node.name] != nil
            || cachedParentCloneSummary.clonesMissingParent.contains(node.name) {
            HStack(spacing: 8) {
                Text("Family").bold().frame(width: 100, alignment: .leading)
                familyIndicator(for: node)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Full region-quality reason + a clickable source link, shown right
    /// under "Info" in the bottom-left detail panel — jensyleo's own
    /// follow-up (2026-10-01) after confirming the inline "⭐ Recommended
    /// version"/"ℹ️ Better version exists" suffix (`infoText(for node:)`)
    /// and its hover tooltip both work: the full reason deserves a real,
    /// always-visible row here too, not just a tooltip you have to find.
    /// Not a toggleable View Options field (unlike `.family`/`.oneGameOneROM`
    /// right below) — deliberately simpler, since this only ever shows
    /// anything at all for the handful of games with a curated note, same
    /// "nothing to report, don't show the row" rule those two already
    /// follow, just without a separate on/off switch for something this
    /// narrow.
    @ViewBuilder
    private func regionQualityDetailRow(for node: GameNode) -> some View {
        regionQualityDetailRow(forGameName: node.name)
    }

    /// Shared by the Games panel (`for node:`, above) and the Roms panel
    /// (`romDetailSection`'s own call site) — real gap found live by
    /// jensyleo (2026-10-01): this row originally only existed for the
    /// Games panel.
    @ViewBuilder
    private func regionQualityDetailRow(forGameName name: String) -> some View {
        if let note = regionQualityNote(forGameName: name) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Region note").bold().frame(width: 100, alignment: .leading)
                    Text("\(note.recommendedRegion) recommended: \(note.reason)")
                }
                HStack(spacing: 8) {
                    Spacer().frame(width: 100)
                    if let url = URL(string: note.sourceURL) {
                        Link(note.sourceURL, destination: url)
                            .foregroundStyle(.blue)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            // `Link` on macOS doesn't switch the cursor to
                            // the pointing-hand on its own the way a real
                            // web link does — jensyleo's own request
                            // (2026-10-01) to make that affordance explicit.
                            // Real bug found by this session's own audit:
                            // `.push()`/`.pop()` is a global cursor STACK —
                            // `onHover`'s `false` callback isn't guaranteed
                            // to fire if this row disappears mid-hover (this
                            // whole block is conditional on `note != nil`,
                            // so selecting a different game while hovering
                            // the link can remove it without ever un-hovering
                            // first), which would leave an unbalanced push
                            // and the pointing-hand cursor stuck app-wide.
                            // `.set()` has no stack to unbalance — it just
                            // overwrites the current cursor outright, so a
                            // missed "un-hover" call only ever risks the
                            // cursor staying as a hand one frame too long
                            // (corrected by the very next real mouse move),
                            // never stuck forever.
                            .onHover { isHovering in
                                if isHovering {
                                    NSCursor.pointingHand.set()
                                } else {
                                    NSCursor.arrow.set()
                                }
                            }
                    } else {
                        Text(note.sourceURL)
                    }
                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString("\(note.recommendedRegion) recommended: \(note.reason) (\(note.sourceURL))", forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .imageScale(.medium)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .help("Copy this note's full text")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Same field set as the Roms table's own customizable columns
    /// (`romsList`), each showing the exact same content — jensyleo's own
    /// correction (2026-08-27): "la idea es que tenga exactamente los
    /// mismos campos que se pueden configurar en las columnas." "Rom name"
    /// and the status icon aren't separate toggleable rows here because
    /// they're this panel's own always-shown header (`Text(entry.name)`
    /// below) and the status color already applied to every row via
    /// `hashLine`/`romCell`-style tinting elsewhere — matching how the
    /// Games table's own "Game name" column isn't optional either.
    private func romDetailSection(_ entry: AuditEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(romNameText(for: entry)).font(.headline)
            if showDetailRomFileName {
                // Same fix as the Roms table's own "File name" column
                // (`romsList`) — `actualEntryName` is the entry's own REAL
                // current name, distinct from `path?.lastPathComponent`
                // for a zip entry (the CONTAINER's own filename). See that
                // column's own doc comment.
                if let fileName = entry.actualEntryName ?? entry.path?.lastPathComponent {
                    Text("File name: \(fileName)")
                } else {
                    Text("File name: — not found —").foregroundStyle(.secondary)
                }
            }
            if showDetailRomInfo {
                // Colored to match `entry`'s own status icon — same
                // reasoning as the game section's own "Info" row
                // (`coloredInfoRow`): this value IS a verdict, so it gets
                // the same `AuditStatus.tint` that verdict already has
                // everywhere else, rather than staying the plain secondary
                // gray every purely descriptive field here keeps.
                HStack(spacing: 0) {
                    Text("Info: ")
                    Text(infoText(for: entry)).foregroundStyle(entry.status.tint)
                }
                regionQualityDetailRow(forGameName: entry.gameDescription ?? entry.game ?? "")
            }
            if showDetailRomSize {
                Text("Size: \(sizeText(for: entry))")
            }
            if showDetailRomFolder {
                Text("Folder: \(entry.path?.deletingLastPathComponent().lastPathComponent ?? "")")
                    .foregroundStyle(.secondary)
            }
            if showDetailRomCRC { hashLine(label: "CRC", expected: entry.expectedCRC, actual: entry.actualCRC) }
            if showDetailRomSHA1 { hashLine(label: "SHA-1", expected: entry.expectedSHA1, actual: entry.actualSHA1) }
            if showDetailRomMD5 { hashLine(label: "MD5", expected: entry.expectedMD5, actual: entry.actualMD5) }
            if showDetailRomDumpStatus { dumpStatusDetailRow(entry) }
            if showDetailRomType {
                Text("Type: \(entryKindText(for: entry))")
            }
            if let sourceRom = sourceRom(for: entry) {
                if showDetailRomSerial, let serial = sourceRom.serial, !serial.isEmpty {
                    Text("Serial: \(serial)").foregroundStyle(.secondary)
                }
                if showDetailRomSHA256, let sha256 = sourceRom.sha256, !sha256.isEmpty {
                    Text("SHA-256: \(sha256)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
                if showDetailRomHeader, let header = sourceRom.header, !header.isEmpty {
                    Text("Header (iNES): \(header)").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    if let decoded = INESHeaderDecoder.decode(hexString: header) {
                        let mapperLabel = NESAudioExpansionChip.name(forMapper: decoded.mapper).map { " (\($0))" } ?? ""
                        Text("  Mapper \(decoded.mapper)\(mapperLabel) · PRG \(decoded.prgSizeKB)KB · CHR \(decoded.chrSizeKB)KB · \(decoded.mirroring) mirroring · \(decoded.tvSystem)\(decoded.hasBattery ? " · Battery" : "")")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// The DAT's own declared rom this `entry` came from, found by `entry`'s
    /// own `game` name against the loaded DAT directly — needed for fields
    /// (`serial`/`sha256`/`header`) that live only on `DATRom` itself, never
    /// copied into `AuditEntry`/the SQLite audit database the way the hash-
    /// verification fields are (see `DATRom.serial`'s own doc comment for
    /// why: rare enough, No-Intro-only, that persisting them per scanned
    /// row wasn't worth a schema change).
    ///
    /// Deliberately does NOT go through `selectedGameNode` (which needs
    /// `selectedGameID` set) — real bug found live (2026-09-29): clicking
    /// straight into a Roms-table row, without the matching Games-table row
    /// having ever been separately clicked/selected, leaves `selectedGameID`
    /// nil (or stale from whatever was selected before), so every field
    /// gated on `selectedGameNode` silently failed to show at all —
    /// `selectedEntry` is populated from the Roms-table's own selection
    /// regardless, so resolving straight from `entry.game` (present on every
    /// real row) instead of the separate, independently-tracked game
    /// selection fixes it unconditionally.
    private func sourceRom(for entry: AuditEntry) -> DATRom? {
        guard let gameName = entry.game else { return nil }
        return gamesByNameCache.games(from: viewModel.preloadedGames)[gameName.lowercased()]?.roms.first { $0.name == entry.name }
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

    /// Same layout as `infoRow`, but the value itself takes `tint` instead
    /// of the row's own default secondary color — jensyleo's own request
    /// (2026-08-27): only fields that are themselves a verdict (this
    /// game's own "Info", a rom's own "Dump status") get colored, reusing
    /// the exact same `AuditStatus.tint` the row's own status icon already
    /// uses elsewhere, rather than a color invented just for this panel.
    /// Every purely descriptive field (Year, Manufacturer, File name, …)
    /// deliberately keeps `infoRow`'s plain secondary color — color here
    /// means something, so it doesn't get spent on fields with nothing to
    /// signal.
    @ViewBuilder
    private func coloredInfoRow(_ label: String, _ value: String, tint: Color) -> some View {
        if !value.isEmpty {
            HStack(spacing: 8) {
                Text(label).bold().frame(width: 100, alignment: .leading)
                Text(value).foregroundStyle(tint)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
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
    private func maintenanceDonorHelpText(for entry: AuditEntry) -> String {
        entry.status == .missing
            ? "Missing, but a matching donor is staged in the Maintenance folder — run Fix → Find ROMs to pull it in"
            : "Bad (hash mismatch), but a verified-correct copy is staged in the Maintenance folder — run Fix → Find ROMs to replace it"
    }

    /// The Roms panel's own status icon for one entry — same
    /// `symbolName(for:)`/`.tint` every other status icon uses, EXCEPT for a
    /// `.missing` rom with `hasMaintenanceDonor` set (see that field's own
    /// doc comment): jensyleo's own request (2026-09-14), after confirming
    /// "Find ROMs…" already correctly plans this repair, that a donor
    /// already staged in Maintenance must read differently from a rom with
    /// no fix in sight at all. Reuses `.incorrect`'s own icon/tint (a
    /// yellow triangle) rather than inventing a fourth visual language —
    /// "known, fixable, just needs Find ROMs run" is exactly what
    /// `.incorrect` already means everywhere else in this app.
    private func romStatusIcon(for entry: AuditEntry) -> some View {
        if (entry.status == .missing || entry.status == .badDump), entry.hasMaintenanceDonor {
            return Image(systemName: symbolName(for: .incorrect))
                .foregroundStyle(AuditStatus.incorrect.tint)
                .help(maintenanceDonorHelpText(for: entry))
        }
        return Image(systemName: symbolName(for: entry.status))
            .foregroundStyle(entry.status.tint)
            .help("" as String)
    }

    /// The Games table's own status icon for one game row — jensyleo's own
    /// follow-up (2026-09-14), right after confirming `romStatusIcon(for:)`
    /// already worked for the individual ROM row: the GAME's own row (this
    /// table, one row per file) still showed a flat red X for a game with
    /// ANY missing rom, even when every one of those missing roms already
    /// has a donor staged in Maintenance — "el archivo se reporta en color
    /// rojo y debe aparecer en amarillo, en la vista de Rom está OK". Same
    /// override as `romStatusIcon(for:)`: reuses `.incorrect`'s own
    /// icon/tint rather than a new visual language.
    @ViewBuilder
    private func gameStatusIcon(for node: GameNode) -> some View {
        if let status = node.aggregateStatus {
            if status == .missing || status == .incorrect || status == .badDump, node.entries.contains(where: { $0.hasMaintenanceDonor }) {
                Image(systemName: symbolName(for: .incorrect))
                    .foregroundStyle(AuditStatus.incorrect.tint)
                    .help("At least one missing or hash-mismatched rom has a matching donor staged in the Maintenance folder — run Fix → Find ROMs to pull it in")
            } else {
                Image(systemName: symbolName(for: status)).foregroundStyle(status.tint)
            }
        } else {
            // Not scanned yet — a real, DAT-backed game, just with nothing
            // yet to compare it against.
            Image(systemName: "circle.dashed").foregroundStyle(.secondary)
        }
    }

    private func symbolName(for status: AuditStatus) -> String {
        switch status {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "exclamationmark.triangle.fill"
        case .badDump: return "exclamationmark.octagon.fill"
        case .missing: return "xmark.circle.fill"
        // jensyleo's own gray-file split (2026-08-06): three visually
        // distinct icons for the three gray meanings — a genuinely
        // unrecognized file (❓/"?", legacy `.surplus` kept as its synonym),
        // a recognized-archive leftover worth a second look (⚠/triangle),
        // and content that's known/documented but unverifiable by design
        // (a lighter "?" — distinct from plain unrecognized).
        case .surplus, .unknownFile: return "questionmark.circle.fill"
        case .surplusInArchive: return "exclamationmark.triangle"
        case .unverifiable: return "questionmark.circle"
        case .duplicateSet: return "doc.on.doc.fill"
        }
    }

}
