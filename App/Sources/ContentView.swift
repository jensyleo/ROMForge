import AppKit
import ROMForgeCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: SystemLibraryStore
    @State private var isShowingAddSheet = false
    // jensyleo's own request (2026-08-05): the app should detect its own
    // native (Homebrew) dependencies proactively and tell the user exactly
    // how to install whatever's missing, rather than fail unpredictably
    // later. Checked once per launch here (`ContentView`'s own body, per
    // `ROMForgeApp`'s doc comment on where one-time startup logic belongs)
    // — real bug this closes: `CHDLZMADecompressor` used to `link "lzma"`
    // unconditionally (see `HomebrewDylibLoader`'s own doc comment), making
    // liblzma's exact presence a hard requirement just to *launch* the app
    // at all, with no message of any kind if it was missing. Loading it
    // lazily instead means a missing dependency no longer crashes launch —
    // this check is what turns "silently degraded" into "clearly explained".
    @State private var missingDependencies: [HomebrewLibraryDependency] = []
    // jensyleo's own request (2026-08-19): the real AppKit-backed toolbar
    // (see `ROMForgeToolbar.swift`'s own doc comment for the full "why").
    // Owned here since `ContentView` is this window's true root content —
    // shared with `LibraryDetailView` (passed down through its own init)
    // so each contributes its own region without either needing to know
    // about the other's items.
    @State private var toolbarController = ROMForgeToolbarController()
    // jensyleo's own request (2026-08-19): "todo debe quedar visualmente
    // como está" — `NavigationSplitView`'s own sidebar-toggle button is
    // gone now that it's no longer used at all (see below), so this
    // reconstructs it by hand as a toolbar action instead. `false` swaps
    // the sidebar branch out of the view hierarchy entirely (not just
    // hidden/zero-width) — `detailContent` alone then has the window's
    // full width, matching what the native toggle used to do.
    //
    // `@AppStorage`, not a plain `@State` — jensyleo's own report
    // (2026-08-19): hiding the sidebar (even after saving that into a
    // Column Preset) still came back visible on the next launch, because
    // a plain `@State` only ever lives in memory for the current run.
    // Applying a preset with a saved `sidebarVisible` still overrides this
    // afterward, same as any other preference here.
    @AppStorage("ROMForge.isSidebarVisible") private var isSidebarVisible = true
    /// jensyleo's own report (2026-08-19): the app "se pone lenta por
    /// momentos" — traced to `lastKnownStatus(for:)` opening/closing a
    /// real SQLite connection (`AuditDatabaseLocation.open()` +
    /// `loadReport`, both real disk I/O) for *every* sidebar row, on
    /// *every* render of `sidebarList` (any selection change, any system
    /// added/removed). Cached here instead, refreshed only at the specific
    /// moments a status could actually have changed — see `refreshStatusCache()`.
    @State private var statusCache: [RomSystem.ID: AuditStatus?] = [:]

    var body: some View {
        Group {
            if isSidebarVisible {
                // jensyleo's own report (2026-08-19): `NavigationSplitView`
                // manages its own `NSToolbar` internally (it needs a slot
                // in it for its own sidebar-toggle button) — assigning
                // `window.toolbar` directly ourselves (`ROMForgeToolbarController`,
                // for real "Customize Toolbar…"/⌘-drag reordering) fought
                // that for ownership and broke the app outright (the
                // entire sidebar and most toolbar buttons vanished,
                // confirmed live). `AutosavingSplitView` — already used
                // elsewhere in this app for exactly this kind of
                // persisted, resizable split — is a plain `NSSplitView`
                // wrapper that claims no toolbar of its own, which is
                // what makes owning `window.toolbar` here safe.
                // jensyleo's own report (2026-08-19): this view's default
                // (nothing saved yet) split used to be a plain even 1/N —
                // fine for panes that genuinely trade off screen space
                // evenly, wrong here, where the sidebar is just a short
                // list of configured systems. Shrunk as far as
                // `sidebarMinLength` below allows on jensyleo's own
                // explicit follow-up request ("achícalo al máximo
                // posible") — a user's own drag still overrides this and
                // persists from then on, exactly like every other
                // `AutosavingSplitView` in this app.
                AutosavingSplitView(
                    axis: .sideBySide, autosaveName: "ROMForge.sidebarDetailSplit",
                    panes: [
                        SplitPane(minLength: Self.sidebarMinLength) { sidebarList },
                        SplitPane(minLength: 400) { detailContent },
                    ],
                    // A deliberately tiny target (well below `sidebarMinLength`
                    // in absolute pixels on any real window) — the divider's
                    // own min-coordinate clamp is what actually determines
                    // the floor from here, not this fraction's precision.
                    defaultFractions: [0.01, 0.99]
                )
            } else {
                detailContent
            }
        }
        .background(
            ToolbarHost(
                region: "sidebar",
                actions: [
                    // jensyleo's own request (2026-08-19): checked live
                    // (screenshot of the app's own real toolbar) — "Add
                    // System" comes first, then the icon-only sidebar
                    // toggle.
                    ToolbarAction(
                        id: "addSystem", title: "Add System", systemImage: "plus.circle.fill",
                        help: "Add a new system (DAT + ROM folders)"
                    ) {
                        isShowingAddSheet = true
                    },
                    // Icon-only, no visible "Toggle Sidebar" text —
                    // matches the convention most macOS sidebar-toggle
                    // buttons use.
                    ToolbarAction(
                        id: "toggleSidebar", title: "Toggle Sidebar", systemImage: "sidebar.left",
                        help: "Show or hide the Systems sidebar", showsLabel: false
                    ) {
                        isSidebarVisible.toggle()
                    },
                ],
                controller: toolbarController
            )
        )
        .sheet(isPresented: $isShowingAddSheet) {
            AddSystemSheet(existingCategories: existingCategories) { system in
                store.add(system)
            }
        }
        // jensyleo's own request (2026-08-13): "todo lo necesario para que
        // la app sea lo más rápida posible, transiciones animadas no me
        // interesan. Los mensajes de carga sí son necesarios" — disables
        // every *implicit* SwiftUI animation app-wide from this one root
        // (List row insertion/removal/reorder, DisclosureGroup expand/
        // collapse, sidebar selection, and any future one that isn't
        // explicitly opted back in) rather than hunting down each
        // individual transition one at a time. Deliberately does NOT
        // touch any loading indicator: every `ProgressView` in this app is
        // AppKit-backed (`NSProgressIndicator`) and spins via its own
        // internal animation mechanism, entirely independent of SwiftUI's
        // `Transaction` system — this can't and doesn't affect it, exactly
        // as asked ("los mensajes de carga sí son necesarios").
        .transaction { $0.disablesAnimations = true }
        .onAppear {
            missingDependencies = HomebrewLibraryDependency.all.filter { !HomebrewDylibLoader.isAvailable($0) }
            refreshStatusCache()
        }
        // Covers adding/removing a system, and — the case that actually
        // matters day to day — switching away from whichever system was
        // just scanned/fixed, so its sidebar dot reflects the fresh result
        // without paying the SQLite cost on every single render.
        .onChange(of: store.systems.count) { refreshStatusCache() }
        .onChange(of: store.selectedSystemID) { refreshStatusCache() }
        .alert(
            "Missing dependency",
            isPresented: Binding(
                get: { !missingDependencies.isEmpty },
                set: { if !$0 { missingDependencies = [] } }
            ),
            presenting: missingDependencies.first
        ) { _ in
            Button("OK") { missingDependencies = [] }
        } message: { dependency in
            Text(dependencyAlertMessage(for: dependency))
        }
    }

    private var sidebarList: some View {
        List(selection: $store.selectedSystemID) {
            ForEach(groupedSystems, id: \.category) { group in
                Section(group.category.isEmpty ? "SYSTEM" : group.category) {
                    ForEach(group.systems) { system in
                        HStack(spacing: 6) {
                            if let status = statusCache[system.id] ?? nil {
                                Circle()
                                    .fill(status.tint)
                                    .frame(width: 8, height: 8)
                                    .help("Last scan: \(status.rawValue)")
                            }
                            Text(system.name)
                        }
                        .tag(system.id)
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                store.remove(system)
                            }
                        }
                    }
                }
            }
        }
    }

    private var detailContent: some View {
        Group {
            if let system = store.selectedSystem {
                LibraryDetailView(system: system, onAddFolder: { updatedFolders in
                    var updated = system
                    updated.romFolderURLs = updatedFolders
                    store.update(updated)
                }, onDATAnalyzed: { hasClones in
                    guard system.hasClones != hasClones else { return }
                    var updated = system
                    updated.hasClones = hasClones
                    store.update(updated)
                }, onExportCollectionReport: {
                    exportCollectionReport()
                }, toolbarController: toolbarController, isSidebarVisible: $isSidebarVisible, onAuditReportChanged: {
                    refreshStatus(for: system.id)
                })
                .id(system.id)
            } else {
                ContentUnavailableView(
                    "No System Selected",
                    systemImage: "square.stack.3d.up",
                    description: Text("Add a system with a DAT and a ROM folder to get started.")
                )
                // `LibraryDetailView` (which normally owns the "detail"
                // region) isn't instantiated at all while nothing's
                // selected — without this, its last set of items would
                // stay stuck on the toolbar after deselecting a system.
                .background(ToolbarHost(region: "detail", actions: [], controller: toolbarController))
            }
        }
    }

    /// Step-by-step, copy-pasteable Homebrew instructions — jensyleo's own
    /// request: not just "something is missing," but exactly what to run
    /// and what to do afterward. Only one dependency is checked today
    /// (`xz`/liblzma, for CHD's LZMA codec) — see `HomebrewLibraryDependency.all`'s
    /// own doc comment for why libFLAC isn't listed yet.
    private func dependencyAlertMessage(for dependency: HomebrewLibraryDependency) -> String {
        """
        ROMForge couldn't find "\(dependency.formula)", needed for \(dependency.neededFor). \
        This only affects that specific feature — everything else in the app works normally.

        To install it:
        1. Open Terminal.
        2. Run: brew install \(dependency.formula)
           (if Homebrew itself isn't installed, see brew.sh first)
        3. Quit and reopen ROMForge.
        """
    }

    /// The narrowest the sidebar is ever allowed to shrink to (by drag or
    /// by default) — small enough to still show a short system name
    /// without truncating too aggressively, per jensyleo's own request
    /// (2026-08-19) to shrink the default as far as practical.
    private static let sidebarMinLength: CGFloat = 90

    /// Non-categorized systems are grouped under a trailing "SYSTEM"
    /// section instead of a flat list, RomCenter-style. Skipping grouping
    /// entirely when nobody uses categories yet would save a section header,
    /// but keeping it consistent is simpler and one empty-label group reads
    /// fine either way.
    private var groupedSystems: [(category: String, systems: [RomSystem])] {
        let categories = Set(store.systems.map(\.category))
        let ordered = categories.filter { !$0.isEmpty }.sorted() + (categories.contains("") ? [""] : [])
        return ordered.map { category in
            (category: category, systems: store.systems.filter { $0.category == category })
        }
    }

    private var existingCategories: [String] {
        Set(store.systems.map(\.category)).filter { !$0.isEmpty }.sorted()
    }

    /// The persisted worst status from this system's last real scan, if
    /// any — one real SQLite open/close per system, so this is only ever
    /// called from `refreshStatusCache()` (a handful of well-defined
    /// moments), never straight from `sidebarList`'s own render anymore.
    private func lastKnownStatus(for system: RomSystem) -> AuditStatus? {
        guard let db = try? AuditDatabaseLocation.open() else { return nil }
        return (try? db.loadReport(systemID: system.id.uuidString))?.worstStatus
    }

    private func refreshStatusCache() {
        for system in store.systems {
            statusCache[system.id] = lastKnownStatus(for: system)
        }
    }

    /// Called from `LibraryDetailView` right after a scan/fix actually
    /// changes its `auditReport` — refreshing just the one system that
    /// could plausibly have a new status, instead of every configured
    /// system, and only at the moment it's genuinely needed.
    private func refreshStatus(for systemID: RomSystem.ID) {
        guard let system = store.systems.first(where: { $0.id == systemID }) else { return }
        statusCache[systemID] = lastKnownStatus(for: system)
    }

    /// Saves `CollectionReportExporter`'s HTML and opens it in the default
    /// browser right after — printing it is then just the browser's own
    /// ⌘P, which is the entire point of generating plain HTML for this
    /// instead of building a separate print pipeline.
    private func exportCollectionReport() {
        let html = CollectionReportExporter.generate(systems: store.systems)

        let panel = NSSavePanel()
        panel.title = "Export Collection Report"
        panel.message = "A printable HTML report combining every configured system's last scan."
        panel.nameFieldStringValue = "ROMForge Collection Report.html"
        panel.allowedContentTypes = [.html]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

}

#Preview {
    ContentView(store: SystemLibraryStore())
}
