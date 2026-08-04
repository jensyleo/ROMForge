import ROMForgeCore
import SwiftUI

struct ContentView: View {
    @Bindable var store: SystemLibraryStore
    @State private var isShowingAddSheet = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedSystemID) {
                ForEach(groupedSystems, id: \.category) { group in
                    Section(group.category.isEmpty ? "Uncategorized" : group.category) {
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
    }

    /// Non-categorized systems are grouped under a trailing "Uncategorized"
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

    /// Same status→color mapping `LibraryDetailView` uses, so a system's
    /// sidebar dot means the same thing its own detail view would show.
    private func tint(for status: AuditStatus) -> Color {
        switch status {
        case .correct: return .green
        case .incorrect: return .yellow
        case .badDump: return .orange
        case .missing: return .red
        case .surplus: return .gray
        }
    }
}

#Preview {
    ContentView(store: SystemLibraryStore())
}
