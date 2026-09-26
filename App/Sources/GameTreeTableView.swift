import AppKit
import ROMForgeCore
import SwiftUI

/// The Games table (left/main pane) — extracted verbatim out of
/// `LibraryDetailView` on 2026-09-14 as a pure perf refactor, no behavior
/// change intended.
///
/// Why: `gameTreeTableContent` used to be a plain computed `var` directly on
/// `LibraryDetailView`. SwiftUI has no way to know a computed property's
/// body doesn't depend on some *other* `@State` elsewhere on the same giant
/// struct, so ANY state change anywhere in `LibraryDetailView` (including
/// the continuous updates `columnCustomization` fires while a user is
/// mid-drag resizing a column) forced the ENTIRE `LibraryDetailView.body` to
/// re-evaluate — walking through dozens of unrelated computed properties
/// (sidebar trees, detail panes, etc.) on every frame. Making this its own
/// `View`-conforming struct lets SwiftUI diff it independently: only a
/// change to one of the params/bindings below actually re-renders it.
///
/// Every piece of state/data the original property touched is passed in
/// explicitly below — nothing here reaches back into `LibraryDetailView`.
/// Everything that was a `private func`/`private var` on `LibraryDetailView`
/// (status icons, `infoText`, the various fix/trash/copy actions, MAME
/// launch, etc.) stays defined there and is handed down as a plain closure,
/// so this file makes zero behavioral decisions of its own.
struct GameTreeTableView: View {
    // MARK: - Data
    let visibleGameNodes: [GameNode]
    let cachedGameNodes: [GameNode]
    // Real perf bug found live by jensyleo (2026-09-22), same "beachball on
    // right-click" class as `matchedZipArchiveURLsCache`'s own doc comment:
    // this context menu's own closure did `cachedGameNodes.first(where: {
    // $0.id == ... })` — a LINEAR scan over up to ~45,000 rows (the "All
    // games" category, per `cachedGameNodesByID`'s own doc comment in
    // `LibraryDetailView`) — once per right-click, and once per SELECTED
    // row in a multi-selection. `LibraryDetailView` already builds this
    // exact `[String: GameNode]` index alongside `cachedGameNodes` itself
    // for precisely this reason (`cachedGameNodesByID`) — this view just
    // never received it.
    let cachedGameNodesByID: [String: GameNode]
    let cachedOneGameOneROMSummary: OneGameOneROMSummary
    let viewModel: LibraryViewModel
    let system: RomSystem

    // MARK: - Selection / column customization
    @Binding var selection: Set<GameNode.ID>
    // Owned locally (not a `@Binding` into `LibraryDetailView`'s own
    // `@State`) — real perf bug found live by jensyleo (2026-09-22): a
    // `@Binding` into a parent's `@State` still invalidates the PARENT's
    // body on every mutation, no matter how this child itself is
    // structured, so every pixel of a column-resize drag re-evaluated all
    // ~4400 lines of `LibraryDetailView`. Loaded directly from
    // `UserDefaults` as this `@State` property's own default value —
    // SwiftUI only ever evaluates a `@State` default expression the very
    // first time this view's identity appears; every later reconstruction
    // of this same struct (on every parent re-render) keeps the existing
    // storage instead of re-running the default expression, so this is
    // safe to compute here without needing an explicit `init`.
    // `columnCustomizationOverride` is the one remaining path IN from the
    // parent, for the few things that genuinely need to push a value
    // (column presets, "Reset Layout") — a one-shot push, not a
    // continuous two-way binding.
    @State private var columnCustomization = GameTreeTableView.loadStoredColumnCustomization()
    @Binding var columnCustomizationOverride: TableColumnCustomization<GameNode>?
    let persistColumnCustomization: (TableColumnCustomization<GameNode>) -> Void

    // Must match `LibraryDetailView.gameColumnCustomizationKey` exactly —
    // duplicated here (rather than shared) since that constant is
    // `private` to that giant file and this is the only other reader.
    /// jensyleo's own request (2026-09-23): "revisa de nuevo como dejé los
    /// paneles y columnas y de ahora en adelante esas son las opciones por
    /// defecto cuando se instale la app" — captured directly from his own
    /// live `UserDefaults` (`defaults read com.jensyleo.romforge
    /// ROMForge.gameTableColumnCustomization`), same technique already used
    /// for `DatabaseFilterVisibilitySettings.defaultEnabled`/the
    /// `AutosavingSplitView` fractions right below in this same commit.
    /// Purely column widths/order/visibility — no path, folder, NAS, or
    /// any other personal data of his own is in here, only which columns
    /// show and how wide, confirmed by reading this exact JSON before
    /// embedding it (see this feature's own memory note for the full
    /// verification). Used ONLY as the fallback for a fresh install with
    /// no saved value yet — any real customization the user makes from
    /// then on is saved over this and takes over completely.
    private static let defaultColumnCustomizationJSON = """
    {"perColumnState":[{"base":{"explicit":{"_0":"family"}}},{"visibility":{"hidden":{}},"currentWidth":123},{"base":{"explicit":{"_0":"fileName"}}},{"visibility":{"hidden":{}},"currentWidth":158.5},{"base":{"explicit":{"_0":"cloneOf"}}},{"visibility":{"automatic":{}},"currentWidth":148.5},{"base":{"explicit":{"_0":"expectedFileName"}}},{"visibility":{"hidden":{}}},{"base":{"explicit":{"_0":"info"}}},{"currentWidth":124,"visibility":{"automatic":{}}},{"base":{"explicit":{"_0":"gameName"}}},{"visibility":{"automatic":{}},"currentWidth":148.5},{"base":{"explicit":{"_0":"bios"}}},{"visibility":{"visible":{}},"currentWidth":79.5},{"base":{"explicit":{"_0":"requiredBios"}}},{"visibility":{"visible":{}}}],"columnOrder":[{"base":{"explicit":{"_0":"status"}}},{"base":{"explicit":{"_0":"gameName"}}},{"base":{"explicit":{"_0":"fileName"}}},{"base":{"explicit":{"_0":"info"}}},{"base":{"explicit":{"_0":"expectedFileName"}}},{"base":{"explicit":{"_0":"size"}}},{"base":{"explicit":{"_0":"cloneOf"}}},{"base":{"explicit":{"_0":"chd"}}},{"base":{"explicit":{"_0":"samples"}}},{"base":{"explicit":{"_0":"requiredBios"}}},{"base":{"explicit":{"_0":"bios"}}},{"base":{"explicit":{"_0":"year"}}},{"base":{"explicit":{"_0":"manufacturer"}}},{"base":{"explicit":{"_0":"deviceRefs"}}},{"base":{"explicit":{"_0":"cloneOfInternalName"}}},{"base":{"explicit":{"_0":"family"}}},{"base":{"explicit":{"_0":"dependencies"}}},{"base":{"explicit":{"_0":"details"}}},{"base":{"explicit":{"_0":"oneGameOneROM"}}}]}
    """

    private static func loadStoredColumnCustomization() -> TableColumnCustomization<GameNode> {
        if let data = UserDefaults.standard.data(forKey: "ROMForge.gameTableColumnCustomization"),
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<GameNode>.self, from: data) {
            return decoded
        }
        guard let fallbackData = defaultColumnCustomizationJSON.data(using: .utf8),
              let fallback = try? JSONDecoder().decode(TableColumnCustomization<GameNode>.self, from: fallbackData)
        else { return TableColumnCustomization<GameNode>() }
        return fallback
    }

    // MARK: - Keyboard type-ahead
    let handleTypeAheadKeyPress: (KeyPress) -> KeyPress.Result
    // jensyleo's own report (2026-09-15), macOS 27.0: `Table`'s own
    // native arrow-key row navigation stopped working entirely. Actually
    // MOVING the selection on an up/down arrow now happens in
    // `LibraryDetailView`'s own shared event monitor (`activeResultsPane`'s
    // own doc comment there) — this is just how that monitor knows this
    // Table is the one the user last clicked into.
    let onFocusRequested: () -> Void

    // MARK: - Cell content (all previously `private func`s on LibraryDetailView)
    let gameStatusIcon: (GameNode) -> AnyView
    let infoText: (GameNode) -> String
    let zipCommentHelpText: (GameNode) -> String
    let totalSizeText: (GameNode) -> String
    let gameDescription: (String) -> String
    let familyIndicator: (GameNode) -> AnyView
    let dependenciesIndicator: (GameNode) -> AnyView
    let detailsIndicator: (GameNode) -> AnyView

    // MARK: - Context menu actions (all previously `private func`s on LibraryDetailView)
    let scanFile: (GameNode) -> Void
    let canScanFile: (GameNode) -> Bool
    let launchInMAME: (GameNode) -> Void
    let canLaunchMAME: (GameNode) -> Bool
    let revealInFinder: (URL?) -> Void
    let actualFileURL: (GameNode) -> URL?
    let startMoveToTrash: ([URL]) -> Void
    let startDeleteFilesPermanently: ([URL]) -> Void
    let startCopyFilesToFolder: ([URL]) -> Void
    let startMoveFilesToFolder: ([URL]) -> Void
    let startDuplicateFiles: ([URL]) -> Void
    let startCompressFiles: ([URL]) -> Void
    let fixMismatchedFile: ([URL]) -> Void
    let startContextMenuRenameRomsInArchive: ([URL]) -> Void
    let startContextMenuRemoveUselessFiles: ([URL]) -> Void
    // jensyleo's own request (2026-09-22): "Remove Zip Comments" only ever
    // existed as the toolbar's own unscoped, whole-system action — no way
    // to strip just one right-clicked File's own comment.
    let startContextMenuRemoveZipComments: ([URL]) -> Void
    // jensyleo's own request (2026-09-14): "agrega todas las opciones que
    // apliquen en el menú contextual" — a row reading "Duplicated file,
    // not needed here" had no matching right-click action, only the
    // toolbar's own folder-scoped "Remove Redundant Files…"/"Remove
    // Redundant ROMs…".
    let startContextMenuRemoveRedundantFiles: ([URL]) -> Void
    let startContextMenuRemoveRedundantRoms: ([URL]) -> Void
    // jensyleo's own request (2026-09-14): "es más que lógico" that a
    // `.missing` rom already flagged `hasMaintenanceDonor` (the same
    // cheap, already-computed flag `gameStatusIcon`'s own yellow override
    // reads) should offer its own repair right here, not only from the
    // toolbar's whole-system "Fix" dropdown.
    let startRepairFromMaintenanceFolder: ([URL]) -> Void

    var body: some View {
        Table(visibleGameNodes, selection: $selection, columnCustomization: $columnCustomization) {
            TableColumn("") { node in
                gameStatusIcon(node)
            }
            .width(20)
            .customizationID("status")
            .disabledCustomizationBehavior(.all)
            TableColumn("Game name") { node in Text(node.gameName) }
            .customizationID("gameName")
            TableColumn("File name") { node in Text(node.actualFileName ?? node.name) }
                .customizationID("fileName")
            TableColumn("Info") { node in
                Text(infoText(node)).help(zipCommentHelpText(node))
            }
                .customizationID("info")
            TableColumn("Expected file name") { node in Text(node.expectedFileName ?? "") }
                .customizationID("expectedFileName")
            TableColumn("Size") { node in Text(totalSizeText(node)) }
                .customizationID("size")
                .defaultVisibility(.hidden)
            TableColumn("Clone of") { node in Text(node.cloneOf.isEmpty ? "" : gameDescription(node.cloneOf)) }
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
                TableColumn("Family") { (node: GameNode) in familyIndicator(node) }
                    .customizationID("family")
                // Purely informational, like "Family" above — reads
                // `GameNode.dependencyBadges` (ROMForgeCore), itself built
                // only from fields already computed by the scan/DAT load,
                // so this never triggers a re-scan or any extra I/O.
                TableColumn("Dependencies") { (node: GameNode) in dependenciesIndicator(node) }
                    .customizationID("dependencies")
                    .defaultVisibility(.hidden)
                // Separate column from "Dependencies" above (jensyleo's own
                // decision, 2026-08-28) — descriptive machine metadata
                // (MAME's own emulation-quality claim, display orientation,
                // player/coin count), never something the game needs in
                // order to run. Reads `GameNode.detailBadges` (ROMForgeCore),
                // same "already computed by the scan/DAT load" cost-free
                // shape as "Dependencies".
                TableColumn("Details") { (node: GameNode) in detailsIndicator(node) }
                    .customizationID("details")
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
        .onChange(of: columnCustomization) { persistColumnCustomization(columnCustomization) }
        .onChange(of: columnCustomizationOverride) { _, newValue in
            guard let newValue else { return }
            columnCustomization = newValue
        }
        // jensyleo's own report (2026-09-15), confirmed live via screen
        // recording: even with `.focusable()`/`.focused()`/`.onChange(of:
        // selection)`/`.simultaneousGesture` all wired up (the fix that DID
        // work for the sidebar's own plain `List`-based panes), clicking a
        // NEW row here still left arrow keys controlling the ROMS panel's
        // own selection instead of this Table's — macOS 27 apparently
        // doesn't reliably move ACTUAL AppKit key-window focus between two
        // independent `Table` (NSTableView-backed) views side by side, even
        // when SwiftUI's own `@FocusState` claims it did. Rather than keep
        // fighting that per-view focus transfer, arrow-key routing for
        // both this Table and the Roms one is now handled by ONE shared
        // event monitor at `LibraryDetailView`'s own level (see
        // `activeResultsPane`'s own doc comment there) — this Table only
        // needs to report "I'm the one the user last touched" via
        // `onFocusRequested`, on every click here. Only `.simultaneousGesture`
        // now (an earlier version also had `.onChange(of: selection)` —
        // real bug found by code audit, 2026-09-16: `onFocusRequested`'s
        // own same-game-reclick detection compares against the CURRENT
        // selection each time it runs, so having BOTH triggers fire for a
        // single genuine game change ran the closure twice, incorrectly
        // treating the second run as a "reclick" and bumping
        // `romsResetGeneration` for a change that already got its own
        // fresh Roms `.id()`. `.simultaneousGesture` alone already fires
        // reliably for every click, genuine change or not — no need for
        // the second trigger.
        .simultaneousGesture(TapGesture().onEnded { onFocusRequested() })
        .onKeyPress(phases: .down) { keyPress in
            handleTypeAheadKeyPress(keyPress)
        }
        // MAME-only, and only once a real `mame` executable is configured
        // — see `MAMELauncher`/`canLaunchMAME(_:)`. Selecting a row via
        // right-click already updates `selectedGameID` (SwiftUI's own
        // `Table` behavior), so `node` below is always the row actually
        // right-clicked, not whatever was selected before.
        .contextMenu(forSelectionType: GameNode.ID.self) { selection in
            if let id = selection.first, let node = cachedGameNodesByID[id] {
                // jensyleo's own report (2026-09-26, with screenshot): every
                // item in this context menu showed no icon at all, despite
                // each one's own `Label(_:systemImage:)` — a real, known
                // macOS/SwiftUI gap: a plain `Label`'s icon inside
                // `.contextMenu`/`.contextMenu(forSelectionType:)` can
                // silently fall back to `.titleOnly` depending on the
                // exact macOS version, unlike the menu-bar `.commands`
                // menu, which always shows them. Forcing `.titleAndIcon`
                // explicitly (rather than relying on the default) is the
                // cheap, well-known fix — applied ONCE here, to the whole
                // menu's content via `Group`, rather than repeated on every
                // individual `Button` below (including inside the nested
                // "File Actions"/"Fix" submenus) — `.labelStyle` is an
                // environment value, so setting it once here cascades to
                // all of them.
                Group {
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
                    revealInFinder(actualFileURL(node))
                } label: {
                    Label("Reveal in Finder", systemImage: "folder")
                }
                // Real gap found live by jensyleo (2026-09-23): same
                // "every interaction needs a prior scan" rule now applied
                // to "Play in MAME" (`canLaunchMAME`'s own doc comment) —
                // this never checked for one at all either.
                .disabled(actualFileURL(node) == nil || viewModel.auditReport == nil)
                // "Verify ZIP Integrity" temporarily removed from this menu
                // at jensyleo's own explicit request (2026-09-17) — "no
                // está generando mucho problema [beneficio]" relative to
                // the trouble it was causing live while this session was
                // chasing the frozen "Comparing against the database…"
                // overlay text and the `saveReport` write-cost issues that
                // both happened to surface through this same action.
                // `LibraryViewModel.verifyZipIntegrity(system:)` itself is
                // untouched — only this entry point is gone — so re-adding
                // the button here is all it takes to bring it back later.
                // jensyleo's own request (2026-09-10): the toolbar's own
                // "Fix" actions only ever scope to a whole selected ROM
                // folder — "para eso agrega en el menú contextual las
                // opciones de fix del menú asociadas al archivo." Same two
                // actions, same underlying `fix()`/`renameRomsInArchive()`.
                // jensyleo's own follow-up (2026-09-10): "la app no
                // permite selección múltiple" — `selection` here is
                // ALREADY the full multi-selection `Set<GameNode.ID>`
                // (SwiftUI's own `.contextMenu(forSelectionType:)` always
                // provides one; only the Table's own `selection` binding
                // above being a `Set` now is what lets more than one row
                // actually GET selected in the first place). `fileURLs`
                // below is every SELECTED node's own real File, one entry
                // per File — no ViewModel/Core change needed beyond
                // accepting an array, since `urlIsInScope` already treats
                // each as its own exact-path scope, same mechanism "Rescan
                // This File" above already relies on for `scan(folders:)`.
                let fileURLs = selection.compactMap { selectedID in
                    cachedGameNodesByID[selectedID].flatMap(actualFileURL)
                }
                // "File Actions" (Move to Trash, Delete Permanently, Copy/
                // Move to Folder…) — jensyleo's own request (2026-09-11):
                // plain, OS-level operations that don't depend on the DAT
                // or a live `matchReport` at all, unlike "Fix Mismatched
                // File"/"Fix Misnamed ROMs…" below — shown whenever at
                // least one selected row has a real File, regardless of
                // `viewModel.hasMatchReport`.
                if !fileURLs.isEmpty {
                    Divider()
                    Menu {
                        Button {
                            startMoveToTrash(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Move File to Trash…" : "Move \(fileURLs.count) Files to Trash…", systemImage: "trash")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                        Button {
                            startDeleteFilesPermanently(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Delete File Permanently…" : "Delete \(fileURLs.count) Files Permanently…", systemImage: "trash.fill")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                        Divider()
                        Button {
                            startCopyFilesToFolder(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Copy File to Folder…" : "Copy \(fileURLs.count) Files to Folder…", systemImage: "doc.on.doc")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                        Button {
                            startMoveFilesToFolder(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Move File to Folder…" : "Move \(fileURLs.count) Files to Folder…", systemImage: "folder")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                        Divider()
                        Button {
                            startDuplicateFiles(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Duplicate File" : "Duplicate \(fileURLs.count) Files", systemImage: "plus.square.on.square")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                        Button {
                            startCompressFiles(fileURLs)
                        } label: {
                            Label(fileURLs.count == 1 ? "Compress File" : "Compress \(fileURLs.count) Files", systemImage: "archivebox")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    } label: {
                        Label("File Actions", systemImage: "ellipsis.circle")
                    }
                }
                // Same visibility rule as the Roms panel's own context menu
                // below, and for the same reason (jensyleo's own report,
                // 2026-09-10): show each action only when its own real
                // preview count is actually greater than zero, rather than
                // always showing both merely disabled by the write-access
                // gate — offering a "Fix" that's guaranteed to do nothing
                // reads as broken, not as "nothing to fix here".
                //
                // `viewModel.hasMatchReport` is checked FIRST and neither
                // preview function is called at all when it's `false` —
                // jensyleo's own bug report (2026-09-10), screenshot of
                // "Scan Required" popping up from a plain right-click:
                // `planFixPreviewCount`/`planRenameRomsInArchivePreviewCount`
                // both go through `requireMatchReport()`, which triggers
                // that very alert as a SIDE EFFECT whenever there's no live
                // `matchReport` yet (a persisted `auditReport` from a past
                // session already shows real rows on screen without one) —
                // and SwiftUI evaluates this closure just from opening the
                // menu, so merely right-clicking a row was enough to fire
                // it. See `hasMatchReport`'s own doc comment.
                if !fileURLs.isEmpty, viewModel.hasMatchReport {
                    let fixMismatchedFileCount = viewModel.planFixPreviewCount(scopeFolders: fileURLs)
                    let renameRomsCount = viewModel.planRenameRomsInArchivePreviewCount(scopeFolders: fileURLs)
                    // jensyleo's own report (2026-09-13): a row reading
                    // "Extra file in archive" (a surplus entry the DAT
                    // recognizes nothing about, sitting alongside otherwise-
                    // legit roms) had no context-menu action to act on it —
                    // only the toolbar's own folder-scoped "Remove Useless
                    // Files…" existed. Same "only offered when its own
                    // preview count is actually > 0" rule as the two above.
                    let removeUselessCount = viewModel.planRemoveUselessFilesPreviewCount(scopeFolders: fileURLs)
                    let removeRedundantFilesCount = viewModel.planRemoveRedundantFilesPreviewCount(scopeFolders: fileURLs)
                    let removeRedundantRomsCount = viewModel.planRemoveRedundantRomsPreviewCount(scopeFolders: fileURLs)
                    // jensyleo's own request (2026-09-22): a row reading
                    // "Ok — Has ZIP comment" had no context-menu action to
                    // strip just its own comment — only the toolbar's own
                    // unscoped, whole-system "Remove Zip Comments…" existed.
                    let removeZipCommentsCount = viewModel.planRemoveZipCommentsPreviewCount(scopeFolders: fileURLs)
                    // Cheap, already-computed signal (from the same scan
                    // pass `gameStatusIcon`'s own yellow-override reads) —
                    // NOT a fresh Maintenance-folder read, which would mean
                    // hashing that whole folder just to render a right-click
                    // menu. The real (scoped) preview count/confirmation
                    // still runs, same as every other action here, only
                    // after the user actually clicks this.
                    let hasMaintenanceDonor = selection.contains { selectedID in
                        cachedGameNodesByID[selectedID]?.entries.contains(where: \.hasMaintenanceDonor) ?? false
                    }
                    if fixMismatchedFileCount > 0 || renameRomsCount > 0 || removeUselessCount > 0
                        || removeRedundantFilesCount > 0 || removeRedundantRomsCount > 0 || removeZipCommentsCount > 0 || hasMaintenanceDonor {
                        Divider()
                    }
                    if fixMismatchedFileCount > 0 {
                        Button {
                            fixMismatchedFile(fileURLs)
                        } label: {
                            Label(
                                fileURLs.count == 1 ? "Fix Mismatched File" : "Fix \(fileURLs.count) Mismatched Files",
                                systemImage: "wrench.and.screwdriver"
                            )
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if renameRomsCount > 0 {
                        Button {
                            startContextMenuRenameRomsInArchive(fileURLs)
                        } label: {
                            Label(
                                fileURLs.count == 1 ? "Fix Misnamed ROMs Inside This Archive…" : "Fix Misnamed ROMs Inside These \(fileURLs.count) Archives…",
                                systemImage: "wrench.and.screwdriver"
                            )
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if removeUselessCount > 0 {
                        Button(role: .destructive) {
                            startContextMenuRemoveUselessFiles(fileURLs)
                        } label: {
                            // See `LibraryViewModel.planRemoveUselessFilesPreviewKind`'s
                            // own doc comment — this single action can
                            // delete a loose junk File, remove a junk ROM
                            // entry inside an otherwise-known archive, or
                            // both at once, unlike the separate "Remove
                            // Redundant Files…"/"…ROMs…" pair.
                            switch viewModel.planRemoveUselessFilesPreviewKind(scopeFolders: fileURLs) {
                            case .files: Label("Remove Useless File(s)…", systemImage: "trash")
                            case .roms: Label("Remove Useless ROM(s)…", systemImage: "trash")
                            case .mixed: Label("Remove Useless File(s)/ROM(s)…", systemImage: "trash")
                            }
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if removeRedundantFilesCount > 0 {
                        Button(role: .destructive) {
                            startContextMenuRemoveRedundantFiles(fileURLs)
                        } label: {
                            Label("Remove Redundant File(s)…", systemImage: "trash")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if removeRedundantRomsCount > 0 {
                        Button(role: .destructive) {
                            startContextMenuRemoveRedundantRoms(fileURLs)
                        } label: {
                            Label("Remove Redundant ROM(s)…", systemImage: "trash")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if removeZipCommentsCount > 0 {
                        Button {
                            startContextMenuRemoveZipComments(fileURLs)
                        } label: {
                            Label("Remove Zip Comment…", systemImage: "text.badge.xmark")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                    if hasMaintenanceDonor {
                        Button {
                            startRepairFromMaintenanceFolder(fileURLs)
                        } label: {
                            Label("Find ROMs…", systemImage: "wrench.and.screwdriver")
                        }
                        .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                    }
                }
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
}
