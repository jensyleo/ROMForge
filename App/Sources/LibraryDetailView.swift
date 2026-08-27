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
private struct RomRow: Identifiable {
    let id: String
    let entry: AuditEntry
}

/// `GameNode` itself now lives in ROMForgeCore (2026-08-13, "Grupo B" of
/// the App-logic extraction) — it never had any SwiftUI dependency, it
/// was just declared in this View file. This alias keeps every existing
/// call site below (`GameNode(...)`, `.isSurplusBucket`, `.infoText`, etc.)
/// unchanged.
private typealias GameNode = ROMForgeCore.GameNode

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
private final class ZipCommentCache {
    private var storage: [URL: String?] = [:]

    func comment(forZipAt url: URL) -> String? {
        if let cached = storage[url] { return cached }
        let comment = ZipCommentReader.comment(ofZipAt: url)
        storage[url] = comment
        return comment
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
    /// Called right after a scan/fix actually changes `viewModel.auditReport`
    /// — lets `ContentView` refresh just this one system's cached sidebar
    /// status dot instead of re-reading `AuditReportDatabase` for every
    /// configured system on every render (see `ContentView.statusCache`'s
    /// own doc comment for the real cost this avoids).
    var onAuditReportChanged: (() -> Void)?

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
        isSidebarVisible: Binding<Bool>? = nil, onAuditReportChanged: (() -> Void)? = nil
    ) {
        self.system = system
        self.onAddFolder = onAddFolder
        self.onDATAnalyzed = onDATAnalyzed
        self.onExportCollectionReport = onExportCollectionReport
        self.toolbarController = toolbarController
        self.isSidebarVisible = isSidebarVisible
        self.onAuditReportChanged = onAuditReportChanged
        let restored = Self.restoreLastSelection(for: system)
        _selectedDatabaseFilter = State(initialValue: restored.databaseFilter)
        _selectedRomFolder = State(initialValue: restored.romFolder)
    }

    private static func lastSelectionKey(for system: RomSystem) -> String {
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
        let enabledRaw = UserDefaults.standard.string(forKey: DatabaseFilterVisibilitySettings.storageKey) ?? DatabaseFilterVisibilitySettings.defaultRawValue
        return (DatabaseFilterVisibilitySettings.enabledFilters(from: enabledRaw).first ?? .allGames, nil)
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
    private let zipCommentCache = ZipCommentCache()
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
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey) private var enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue
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
    /// jensyleo's own report (2026-08-26): a fase 1 leftover — the sheet
    /// listed presets `.keys.sorted()` (alphabetical, the only order a
    /// plain `[String: ColumnPreset]` dictionary can offer), with no way
    /// to put a frequently-used preset near the top. A separate `[String]`
    /// holds the user's own drag order; reconciled against the real keys
    /// on every read (`orderedPresetNames`) rather than trusted blindly,
    /// same "merge saved order with current reality" shape already used
    /// for the toolbar's own saved item order.
    @State private var columnPresetOrder: [String] = Self.loadColumnPresetOrder()
    @State private var isShowingColumnPresetsSheet = false
    @State private var isShowingDATCompareSheet = false
    private static let columnPresetsKey = "ROMForge.columnPresets"
    private static let columnPresetOrderKey = "ROMForge.columnPresetOrder"

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

    private func persistColumnPresetOrder() {
        UserDefaults.standard.set(columnPresetOrder, forKey: Self.columnPresetOrderKey)
    }

    /// The saved order, with any preset it doesn't mention (created since
    /// the user last reordered, or a fresh install with no saved order at
    /// all) appended alphabetically at the end, and any name it mentions
    /// that no longer exists (deleted/renamed) dropped — never trusts
    /// `columnPresetOrder` to already be in sync with `columnPresets`.
    private var orderedPresetNames: [String] {
        let existing = Set(columnPresets.keys)
        let kept = columnPresetOrder.filter { existing.contains($0) }
        let missing = columnPresets.keys.filter { !columnPresetOrder.contains($0) }.sorted()
        return kept + missing
    }

    private func saveColumnPreset(named name: String) {
        guard !name.isEmpty,
              let gameData = try? JSONEncoder().encode(gameColumnCustomization),
              let romData = try? JSONEncoder().encode(romColumnCustomization)
        else { return }
        columnPresets[name] = ColumnPreset(gameData: gameData, romData: romData, sidebarVisible: isSidebarVisible?.wrappedValue)
        Self.persistColumnPresets(columnPresets)
        if !columnPresetOrder.contains(name) {
            columnPresetOrder.append(name)
            persistColumnPresetOrder()
        }
    }

    /// Applies a drag reorder from the sheet's own `List` — operates on
    /// `orderedPresetNames` (what the sheet actually displayed when the
    /// drag happened), not the raw, possibly-stale `columnPresetOrder`.
    private func moveColumnPresets(from source: IndexSet, to destination: Int) {
        var names = orderedPresetNames
        names.move(fromOffsets: source, toOffset: destination)
        columnPresetOrder = names
        persistColumnPresetOrder()
    }

    private func applyColumnPreset(named name: String) {
        guard let preset = columnPresets[name] else { return }
        if let decoded = try? JSONDecoder().decode(TableColumnCustomization<GameNode>.self, from: preset.gameData) {
            gameColumnCustomization = decoded
            Self.persist(decoded, key: Self.gameColumnCustomizationKey)
        }
        if let decoded = try? JSONDecoder().decode(TableColumnCustomization<RomRow>.self, from: preset.romData) {
            romColumnCustomization = decoded
            Self.persist(decoded, key: Self.romColumnCustomizationKey)
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
    private var detailToolbarActions: [ToolbarAction] {
        var actions: [ToolbarAction] = [
            ToolbarAction(id: "scanFile", title: "Scan File", systemImage: "doc.text.magnifyingglass", isEnabled: canScanSelectedFile, help: scanFileButtonHelpText) {
                scanSelectedFile()
            },
            ToolbarAction(
                id: "scanFolder", title: "Scan Folder", systemImage: "folder",
                isEnabled: !viewModel.isBusy && selectedRomFolder != nil,
                help: selectedRomFolder.map { "Scan only \"\($0.lastPathComponent)\" — other folders keep their last known results" }
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
                id: "fix", title: "Fix", systemImage: "wrench.and.screwdriver",
                isEnabled: LibraryViewModel.modificationsEnabled && viewModel.auditReport != nil && !viewModel.isBusy,
                help: LibraryViewModel.modificationsEnabled
                    ? "Rename misnamed ROMs to match the DAT"
                    : "Disabled for now — ROMForge only scans and reports, it won't touch your files"
            ) {
                Task { await viewModel.fix(system: system) }
            },
            ToolbarAction(id: "play", title: "Play", systemImage: "play.fill", isEnabled: canLaunchSelectedGameInMAME, help: playButtonHelpText) {
                launchSelectedGameInMAME()
            },
            // "Show Only 1G1R" moved to Settings → View Options → "1G1R"
            // (jensyleo's own request, 2026-08-24) — now a persisted
            // `@AppStorage` toggle there (see `show1G1ROnly`'s own doc
            // comment) rather than a toolbar action button, so it no
            // longer belongs in this list at all.
        ]
        if let onExportCollectionReport {
            actions.append(
                ToolbarAction(id: "exportReport", title: "Export Report…", systemImage: "doc.richtext", help: "Save a printable HTML report combining every configured system's last scan") {
                    onExportCollectionReport()
                }
            )
        }
        actions.append(
            ToolbarAction(
                id: "exportFixDat", title: "Export Fix DAT…", systemImage: "square.and.arrow.up",
                isEnabled: viewModel.auditReport != nil && !viewModel.isBusy,
                help: "Save a DAT containing only this scan's missing/incorrect entries"
            ) {
                exportFixDat()
            }
        )
        actions.append(
            ToolbarAction(
                id: "exportListCSV", title: "Export List to CSV…", systemImage: "tablecells",
                isEnabled: !cachedGameNodes.isEmpty && !viewModel.isBusy,
                help: "Save the currently displayed games list as a CSV file"
            ) {
                exportGameListCSV()
            }
        )
        actions.append(
            ToolbarAction(
                id: "compareDATVersions", title: "Compare DAT Versions…", systemImage: "arrow.left.arrow.right",
                isEnabled: viewModel.cachedDATFile != nil && !viewModel.isBusy,
                help: "Compare the currently loaded DAT against an older/different version — added, removed, and possibly-renamed games"
            ) {
                isShowingDATCompareSheet = true
            }
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
        VStack(alignment: .leading, spacing: 12) {
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
            AutosavingSplitView(axis: .stacked, autosaveName: "ROMForge.mainRowsSplit", panes: [
                SplitPane(minLength: visibleTopPanes.isEmpty ? 0 : 160) {
                    Group {
                        if !visibleTopPanes.isEmpty {
                            AutosavingSplitView(axis: .sideBySide, autosaveName: "ROMForge.databaseGamesRomsSplit", panes: visibleTopPanes)
                        }
                    }
                },
                SplitPane(minLength: visibleBottomPanes.isEmpty ? 0 : 90) {
                    Group {
                        if !visibleBottomPanes.isEmpty {
                            AutosavingSplitView(axis: .sideBySide, autosaveName: "ROMForge.detailLogSplit", panes: visibleBottomPanes)
                        }
                    }
                },
            ])
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
            if viewModel.isBusy {
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
        .onChange(of: selectedDatabaseFilter) {
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
        .onChange(of: selectedGameID) { selectedRomID = nil }
        .onChange(of: selectedRomFolder) {
            selectedGameID = nil; selectedRomID = nil
            selectedGameFamilyRootMachineName = nil
            triggerCachedGameDataRecompute()
            persistLastSelection()
        }
        .onChange(of: viewModel.auditReport) {
            refreshCachedGameDataAfterAuditReportChangeAsync()
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
            refreshCachedGameDataAfterAuditReportChangeAsync()
        }
        .onAppear {
            viewModel.loadPersistedReport(system: system)
            refreshCachedGameDataAfterAuditReportChangeAsync()
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
        .onReceive(NotificationCenter.default.publisher(for: .romForgeShowColumnPresetsSheet)) { _ in
            isShowingColumnPresetsSheet = true
        }
        .onChange(of: viewModel.auditReport) { onAuditReportChanged?() }
        .sheet(isPresented: $isShowingColumnPresetsSheet) {
            ColumnPresetsSheet(
                presetNames: orderedPresetNames,
                onApply: { name in
                    applyColumnPreset(named: name)
                    isShowingColumnPresetsSheet = false
                },
                onSave: { name in saveColumnPreset(named: name) },
                onUpdate: { name in saveColumnPreset(named: name) },
                onRename: { oldName, newName in renameColumnPreset(from: oldName, to: newName) },
                onDelete: { name in deleteColumnPreset(named: name) },
                onMove: { source, destination in moveColumnPresets(from: source, to: destination) }
            )
        }
        .sheet(isPresented: $isShowingDATCompareSheet) {
            datVersionCompareSheetContent
        }
    }

    @ViewBuilder
    private var datVersionCompareSheetContent: some View {
        if let cachedDATFile = viewModel.cachedDATFile {
            DATVersionCompareSheet(currentDAT: cachedDATFile, systemName: system.name)
        }
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
                    .foregroundStyle(worst.tint)
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
                // jensyleo's own request (2026-08-12): "Scan All Folders"
                // (and "Scan Folder", which — see `LibraryViewModel.scan`'s
                // own doc comment — always walks every one of the system's
                // folders regardless of which single one was selected) used
                // to show only a running file count with no way to tell
                // *which* folder it was even counting. Named directly now,
                // via `currentlyScanningFolder`.
                Text(
                    viewModel.currentlyScanningFolder.map { "Scanning \($0.lastPathComponent)… \(filesFound) files found" }
                        ?? "Scanning folders… \(filesFound) files found"
                )
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
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.isError ? Color.red : Color.primary)
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
                ])
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
        .onKeyPress(.upArrow) { moveDatabaseSelection(by: -1, scope: .romFolder); return .handled }
        .onKeyPress(.downArrow) { moveDatabaseSelection(by: 1, scope: .romFolder); return .handled }
        .onKeyPress(.rightArrow) { expandSelectedDatabaseRow(); return .handled }
        .onKeyPress(.leftArrow) { collapseSelectedDatabaseRow(); return .handled }
        // See `isDatabasePaneFocused`'s own doc comment.
        .focusable()
        .focused($isRomFolderPaneFocused)
    }

    /// Search bar for the "Database" tree — see `databaseSearchText`'s own
    /// doc comment for why this, not a bigger cap or a flattened `List`, is
    /// the actually-safe way to reach every row of a huge category.
    private var databaseSearchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search games… (* ? wildcards)", text: $databaseSearchText)
                .textFieldStyle(.plain)
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
            if !databaseSearchText.isEmpty, let filter = selectedDatabaseFilter, !expandedDatabaseCategories.contains(filter) {
                expandedDatabaseCategories.insert(filter)
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
                                    isDatabasePaneFocused = true
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
        .onAppear { syncLocalRomFolderOrder() }
        .onChange(of: system.romFolderURLs) { syncLocalRomFolderOrder() }
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
            Label(url.lastPathComponent, systemImage: "externaldrive")
                .fontWeight(selectedRomFolder == url ? .semibold : .regular)
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
            Group {
                if let index, index > 0 {
                    Button {
                        moveRomFolder(url, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Move up")
                }
            }
            Group {
                if let index, index < localRomFolderOrder.count - 1 {
                    Button {
                        moveRomFolder(url, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .help("Move down")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDatabaseFilter = nil
            selectedRomFolder = url
            isRomFolderPaneFocused = true
        }
        .help(url.path)
        // A real selection background, not just bold text — see
        // `controlActiveState`'s own doc comment for why this is blue
        // while this window is key and gray otherwise, matching native
        // List/NSTableView selection rather than a static color.
        .listRowBackground(
            selectedRomFolder == url
                ? (controlActiveState == .inactive ? Color.gray.opacity(0.35) : Color.accentColor.opacity(0.85))
                : Color.clear
        )
        .foregroundStyle(selectedRomFolder == url && controlActiveState != .inactive ? Color.white : Color.primary)
        .contextMenu {
            Button("Remove Folder", role: .destructive) {
                removeRomFolder(url)
            }
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
    private func moveRomFolder(_ url: URL, by offset: Int) {
        var folders = localRomFolderOrder
        guard let index = folders.firstIndex(of: url) else { return }
        let newIndex = index + offset
        guard folders.indices.contains(newIndex) else { return }
        folders.swapAt(index, newIndex)
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
            gameTableScrollProxy?.scrollTo(id, anchor: .center)
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
            gameTreeTable
            // Same "Show N more" idea as the sidebar tree's own truncation
            // row (`maxTreeChildrenPerCategory`/`treeLoadMoreIncrement`) —
            // see `gamesTableVisibleCap`'s own doc comment for why this
            // exists at all. Only shown once there's actually more beyond
            // the current page.
            if displayedGameNodes.count > gamesTableVisibleCap {
                Button {
                    gamesTableVisibleCap += Self.treeLoadMoreIncrement
                } label: {
                    Text("Show \(min(Self.treeLoadMoreIncrement, displayedGameNodes.count - gamesTableVisibleCap)) more (\(displayedGameNodes.count - gamesTableVisibleCap) left)")
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
        if let selectedRomFolder {
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
        guard selectedGameFamilyRootMachineName != nil else { return cachedGameNodes }
        return cachedFamilyGameNodes
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

    private var gameTreeTableContent: some View {
        Table(visibleGameNodes, selection: $selectedGameID, columnCustomization: $gameColumnCustomization) {
            TableColumn("") { node in
                if let status = node.aggregateStatus {
                    Image(systemName: symbolName(for: status)).foregroundStyle(status.tint)
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
            TableColumn("Clone of") { node in Text(node.cloneOf.isEmpty ? "" : gameDescription(forMachineName: node.cloneOf)) }
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
                // jensyleo's own request (2026-08-17): "Clone of" now shows
                // the parent's readable description, not its raw internal
                // machine name — this hidden-by-default column keeps the
                // raw name available for anyone who wants it, same
                // convention as every other column here.
                TableColumn("Clone of (internal name)") { (node: GameNode) in Text(node.cloneOf) }
                    .customizationID("cloneOfInternalName")
                    .defaultVisibility(.hidden)
                TableColumn("Family") { (node: GameNode) in familyIndicator(for: node) }
                    .customizationID("family")
                // Purely informational, like "Family" above — reads
                // `GameNode.dependencyBadges` (ROMForgeCore), itself built
                // only from fields already computed by the scan/DAT load,
                // so this never triggers a re-scan or any extra I/O.
                TableColumn("Dependencies") { (node: GameNode) in dependenciesIndicator(for: node) }
                    .customizationID("dependencies")
                    .defaultVisibility(.hidden)
                // Independent of `show1G1ROnly` — jensyleo's own spec
                // (2026-08-19, moved to its own column 2026-08-25): the
                // star is always visible so a family's preferred variant
                // reads at a glance even with the toggle off, only the
                // actual hiding is gated by it.
                TableColumn("1G1R") { (node: GameNode) in
                    if cachedOneGameOneROMSummary.preferredGameNames.contains(node.name) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .help("The preferred 1G1R variant for this family, per Settings → View Options → \"1G1R region priority\"")
                    }
                }
                .customizationID("oneGameOneROM")
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
                Button {
                    revealInFinder(actualFileURL(for: node))
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                .disabled(actualFileURL(for: node) == nil)
                Button {
                    Task { await viewModel.verifyZipIntegrity(system: system) }
                } label: {
                    Label("Verify ZIP Integrity", systemImage: "checkmark.shield")
                }
                .disabled(viewModel.isBusy || viewModel.auditReport == nil)
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
        // No `withAnimation` — jensyleo's own request (2026-08-13):
        // animated transitions aren't wanted anywhere in this app, this
        // type-ahead scroll included.
        gameTableScrollProxy?.scrollTo(match.id, anchor: .center)
        return .handled
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
        let badges = node.dependencyBadges.filter { badge in
            switch badge.kind {
            case .bios: return showBiosBadge
            case .chd: return showCHDBadge
            case .hardware: return showHardwareBadge
            case .samples: return showSamplesBadge
            }
        }
        if badges.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(badges) { badge in
                    Text(badge.label)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(badgeTint(for: badge.kind).opacity(0.18), in: Capsule())
                        .help(badge.tooltip)
                }
            }
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
                    romCell(Image(systemName: symbolName(for: row.entry.status)).foregroundStyle(row.entry.status.tint), status: row.entry.status)
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
                    TableColumn("Type") { (row: RomRow) in
                        romCell(Text(entryKindText(for: row.entry)), status: row.entry.status)
                    }
                    .customizationID("entryKind")
                    .defaultVisibility(.hidden)
                }
            }
            .onChange(of: romColumnCustomization) { Self.persist(romColumnCustomization, key: Self.romColumnCustomizationKey) }
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
    /// glance instead of only the leading icon.
    private func romCell(_ content: some View, status: AuditStatus) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.18))
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
        pendingFolderRecompute = Task.detached(priority: .userInitiated) {
            if isBurst {
                try? await Task.sleep(for: Self.keyboardNavigationDebounceDelay)
                guard !Task.isCancelled else { return }
            }
            let gamesInFolder = Self.recomputeGamesInFolder(entries: entries, selectedFolder: folder)
            let scoped = Self.scoped(entries, databaseFilter: databaseFilter, romFolder: folder, gamesInFolder: gamesInFolder)
            let baseNodes = Self.computeBaseGameNodes(
                hasAuditReport: hasAuditReport, auditEntries: entries,
                selectedRomFolder: folder, preloadedGames: preloadedGames, selectedDatabaseFilter: databaseFilter,
                gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine,
                precomputedScoped: scoped
            )
            let nodes = Self.computeGameNodes(
                baseNodes: baseNodes, gameAggregateStatusByName: aggStatus, showUnknownArchives: showUnknown,
                activeStatusFilters: statusFilters, hiddenOneGameOneROMNames: hidden1G1RNames
            )
            let hiddenCount = baseNodes.filter { hidden1G1RNames.contains($0.name) }.count
            let nodesByID = Self.indexByID(nodes)
            let counts = Self.computeScopedStatusCounts(scopedEntries: scoped, gamesByName: Self.gamesByName(preloadedGames))
            let unknownCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
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
        pendingFolderRecompute = Task.detached(priority: .userInitiated) {
            let aggStatus = Self.computeGameAggregateStatusByName(entries: entries, preloadedGames: preloadedGames)
            let parentCloneSummary = ParentCloneSummary.compute(games: preloadedGames, statusByName: aggStatus)
            let oneGameOneROMSummary = OneGameOneROMSelector.compute(games: preloadedGames, regionOrder: regionOrder)
            let gamesInFolder = Self.recomputeGamesInFolder(entries: entries, selectedFolder: folder)
            let scoped = Self.scoped(entries, databaseFilter: databaseFilter, romFolder: folder, gamesInFolder: gamesInFolder)
            let baseNodes = Self.computeBaseGameNodes(
                hasAuditReport: hasAuditReport, auditEntries: entries,
                selectedRomFolder: folder, preloadedGames: preloadedGames, selectedDatabaseFilter: databaseFilter,
                gamesInFolder: gamesInFolder, gameAggregateStatusByName: aggStatus, combineRomAndCHD: combine,
                precomputedScoped: scoped
            )
            let nodes = Self.computeGameNodes(
                baseNodes: baseNodes, gameAggregateStatusByName: aggStatus, showUnknownArchives: showUnknown,
                activeStatusFilters: statusFilters, hiddenOneGameOneROMNames: show1G1R ? oneGameOneROMSummary.hiddenWhenFilteredNames : []
            )
            let hiddenCount = baseNodes.filter { oneGameOneROMSummary.hiddenWhenFilteredNames.contains($0.name) }.count
            let nodesByID = Self.indexByID(nodes)
            let counts = Self.computeScopedStatusCounts(scopedEntries: scoped, gamesByName: Self.gamesByName(preloadedGames))
            let unknownCount = Self.computeUnknownArchivesCount(baseNodes: baseNodes)
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
                refreshCachedFamilyGameNodes()
                cachedGameNodesByID = nodesByID
                cachedScopedStatusCounts = counts
                cachedUnknownArchivesCount = unknownCount
                refreshExpandedDatabaseCategoryCachesAsync(debounced: false)
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
        if !searchText.isEmpty {
            realGames = realGames.filter { node in
                Self.matchesDatabaseSearch(node.gameName, pattern: searchText)
                    || Self.matchesDatabaseSearch((node.entries.first?.gameManufacturer ?? node.sourceGame?.manufacturer) ?? "", pattern: searchText)
            }
        }

        if filter == .byManufacturer || filter == .byYear {
            return groupedTreeChildren(realGames, by: filter, effectiveCap: effectiveCap, searchActive: !searchText.isEmpty)
        }

        guard filter == .allGames else {
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
                    // same fix on the arrow-key path.
                    gameTableScrollProxy?.scrollTo(node.id, anchor: .center)
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
        return cachedGameNodesByID[selectedGameID]
    }

    /// `uniquingKeysWith` keeps the first match, same first-wins semantics
    /// the old `cachedGameNodes.first { $0.id == ... }` linear scan had.
    private nonisolated static func indexByID(_ nodes: [GameNode]) -> [String: GameNode] {
        Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

    /// jensyleo's own request (2026-08-17): a MAME launch failure — which
    /// used to show in its own separate `errorMessage` sheet — belongs in
    /// the Log panel like everything else this view reports, in red so it
    /// still reads as an error at a glance ("mantén el color rojo del
    /// error"). No bespoke presentation to maintain, and no risk of a long
    /// diagnostic (a full "did you mean" candidate list for an unknown
    /// MAME sub-system) distorting the main window's own layout the way
    /// the very first version of this fix (an unbounded inline `Text`) did.
    private func launchInMAME(_ node: GameNode) {
        do {
            try MAMELauncher.launch(machineName: node.name, romFolders: system.romFolderURLs) { reason in
                // MAME's own termination handler fires on a background
                // queue, not the main actor `logError` needs to be touched
                // from.
                Task { @MainActor in
                    viewModel.logError("MAME couldn't run \(node.gameName):\n\n\(reason)")
                }
            }
        } catch let error as MAMELauncher.LaunchError {
            viewModel.logError(error.description)
        } catch {
            viewModel.logError("Failed to launch MAME: \(error.localizedDescription)")
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
                node.infoText,
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
            infoRow("Clone of", node.cloneOf.isEmpty ? "" : gameDescription(forMachineName: node.cloneOf))
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
                Text("Clone of: \(gameDescription(forMachineName: cloneOf))")
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
