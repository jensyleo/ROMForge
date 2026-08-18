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

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSystemID) {
                ForEach(groupedSystems, id: \.category) { group in
                    Section(group.category.isEmpty ? "SYSTEM" : group.category) {
                        ForEach(group.systems) { system in
                            HStack(spacing: 6) {
                                if let status = lastKnownStatus(for: system) {
                                    Circle()
                                        .fill(tint(for: status))
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
            .navigationTitle("Systems")
            .toolbar {
                // `.navigation` keeps this in its own group next to the
                // sidebar toggle, separate from the detail view's own
                // Scan/Fix/Export buttons — with only a generic
                // (unplaced) `ToolbarItem`, all five ended up competing
                // for the same space and "Add System" (least visually
                // weighted, icon-only) was the one macOS collapsed into
                // the "»" overflow menu on anything less than a very wide
                // window. `.titleAndIcon` also gives it a visible label
                // instead of a bare "+", so it doesn't need explaining.
                ToolbarItem(placement: .navigation) {
                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Label("Add System", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .help("Add a new system (DAT + ROM folders)")
                }
            }
            .sheet(isPresented: $isShowingAddSheet) {
                AddSystemSheet(existingCategories: existingCategories) { system in
                    store.add(system)
                }
            }
        } detail: {
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
                })
                .id(system.id)
            } else {
                ContentUnavailableView(
                    "No System Selected",
                    systemImage: "square.stack.3d.up",
                    description: Text("Add a system with a DAT and a ROM folder to get started.")
                )
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
    /// any — read straight from `AuditReportDatabase` rather than kept as
    /// view state, since it only needs to be current when the sidebar row
    /// itself redraws (e.g. after navigating back to this list).
    private func lastKnownStatus(for system: RomSystem) -> AuditStatus? {
        guard let db = try? AuditDatabaseLocation.open() else { return nil }
        return (try? db.loadReport(systemID: system.id.uuidString))?.worstStatus
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

    /// Same status→color mapping `LibraryDetailView` uses, so a system's
    /// sidebar dot means the same thing its own detail view would show.
    private func tint(for status: AuditStatus) -> Color {
        switch status {
        case .correct: return .green
        case .incorrect: return .yellow
        case .badDump: return .orange
        case .missing: return .red
        // jensyleo's own gray-file split (2026-08-06): the "check me,
        // might be junk" tier (surplusInArchive/unknownFile/legacy surplus)
        // renders as a fuller, more attention-grabbing gray than the
        // "this is correct by definition" tier (unverifiable/nodump) — see
        // `AuditStatus`'s own doc comment for the full reasoning.
        case .surplus, .surplusInArchive, .unknownFile: return .gray
        case .unverifiable: return .gray.opacity(0.5)
        }
    }
}

#Preview {
    ContentView(store: SystemLibraryStore())
}
