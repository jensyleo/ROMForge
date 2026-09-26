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
    // jensyleo's own report (2026-09-16): "Cuando remuevo todo el sistema
    // ¿Se borra todo lo asociado?" — real bug: `SystemLibraryStore.remove`
    // already deletes the systems-list entry, the SQLite audit report rows,
    // the scan cache, and the DAT cache, but never touched that system's
    // own Maintenance subfolder (`MaintenanceFolderSettings
    // .deleteSubfolder`, previously only reachable from a manual button in
    // Settings) — removing a system silently orphaned any donor ROMs left
    // there. "Remove" from the sidebar also had NO confirmation at all
    // before this, so a misclick could lose a whole system with zero
    // warning. Now: a confirmation dialog, with an explicit second,
    // separately-destructive choice for the Maintenance subfolder — never
    // deleted silently as a side effect of the first choice.
    @State private var pendingSystemRemoval: RomSystem?

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
                    // jensyleo's own live value (2026-09-23, "esos son los
                    // tamaños que vamos a dejar por defecto") lands at
                    // effectively the same clamped-to-minimum result, just
                    // captured exactly instead of an approximate 0.01.
                    defaultFractions: [0.06122448979591837, 0.9380952380952381]
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
            AddSystemSheet { system in
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
            preloadOtherSystemsInBackground()
        }
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
        .confirmationDialog(
            "Remove \"\(pendingSystemRemoval?.name ?? "")\"?",
            isPresented: Binding(
                get: { pendingSystemRemoval != nil },
                set: { if !$0 { pendingSystemRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove System", role: .destructive) {
                if let system = pendingSystemRemoval {
                    store.remove(system)
                }
                pendingSystemRemoval = nil
            }
            Button("Remove System and Delete Maintenance Folder", role: .destructive) {
                if let system = pendingSystemRemoval {
                    store.remove(system)
                    try? MaintenanceFolderSettings.deleteSubfolder(for: system)
                    NotificationCenter.default.post(name: MaintenanceFolderSettings.subfolderDidDelete, object: nil, userInfo: ["systemID": system.id])
                }
                pendingSystemRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingSystemRemoval = nil }
        } message: {
            Text("Forgets this system, its scan cache, and its saved audit report. Your actual ROM files are never touched. This system's own Maintenance subfolder (if any) is kept by default, in case you re-add this system later — choose \"Delete Maintenance Folder\" to also permanently remove it and every donor ROM inside it.")
        }
    }

    private var sidebarList: some View {
        List(selection: $store.selectedSystemID) {
            ForEach(groupedSystems, id: \.category) { group in
                Section(group.category.isEmpty ? "SYSTEM" : group.category) {
                    ForEach(group.systems) { system in
                        // jensyleo's own request (2026-09-16): "quita ese
                        // punto rojo al lado de MAME" — the per-system
                        // last-scan-status dot removed from the sidebar
                        // row entirely.
                        Text(system.name)
                        .tag(system.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingSystemRemoval = system
                            } label: {
                                Label("Remove…", systemImage: "trash")
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
                }, toolbarController: toolbarController, isSidebarVisible: $isSidebarVisible)
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

    /// jensyleo's own request (2026-09-26), after a full-session slowness
    /// audit: "para el tema de primera vez que inicia la app... has que la
    /// app haga un trabajo en background para ir precargando estos
    /// elementos." Only the initially-selected system gets its DAT/report
    /// loaded normally (`LibraryDetailView`'s own `.onAppear`) — every OTHER
    /// configured system stayed genuinely cold until first visited, which
    /// then paid the SAME "first time" cost the user was noticing at
    /// launch, just deferred to whenever they actually switched to it. This
    /// warms `LibraryViewModel.sharedDATCache`/`sharedAuditReportCache` for
    /// every one of THOSE systems, one low-priority background `Task`
    /// each, right after launch — so switching to any of them later, no
    /// matter how much later, already finds a warm cache instead of a cold
    /// SQLite read.
    ///
    /// A throwaway `LibraryViewModel()` per system is used only for
    /// `preloadDAT` (an ordinary `async` instance method whose own
    /// `Task { await self.preloadDAT(...) }` — see `startPreloadDAT` —
    /// already keeps that instance alive for exactly as long as the load
    /// takes, via its own strong closure capture; no separate lifetime
    /// management needed here). The persisted-report half instead uses the
    /// dedicated `static preloadPersistedReportInBackground`, which needs no
    /// instance at all. `.utility`/`.background` priority throughout — this
    /// should never compete with whichever system the user is ACTUALLY
    /// looking at right now for CPU or I/O bandwidth.
    private func preloadOtherSystemsInBackground() {
        let otherSystems = store.systems.filter { $0.id != store.selectedSystemID }
        for system in otherSystems {
            Task.detached(priority: .background) {
                let warmer = await LibraryViewModel()
                await warmer.preloadDAT(system: system)
            }
            Task.detached(priority: .background) {
                await LibraryViewModel.preloadPersistedReportInBackground(system: system)
            }
        }
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
