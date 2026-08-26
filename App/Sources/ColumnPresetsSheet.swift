// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// jensyleo's own request (2026-08-18): named, saved column layouts for
/// the Games/Roms tables — "Compacta" vs "Detallada" — on top of the
/// show/hide/reorder/resize that already existed per-column.
/// `LibraryDetailView` owns the actual `TableColumnCustomization` state
/// and their persistence; this sheet only ever calls back into it, the
/// same separation `AddSystemSheet` already uses for its own callback.
struct ColumnPresetsSheet: View {
    let presetNames: [String]
    let onApply: (String) -> Void
    let onSave: (String) -> Void
    /// jensyleo's own report (2026-08-18): the first version only offered
    /// create-new/delete — no way to overwrite an existing preset with the
    /// layout as it stands right now without retyping its exact name into
    /// the "new preset" field below. Same underlying action as `onSave`
    /// (`LibraryDetailView`'s dictionary assignment already overwrites),
    /// just reachable directly from that preset's own row.
    let onUpdate: (String) -> Void
    /// (oldName, newName) — a no-op on `LibraryDetailView`'s side if
    /// `newName` is blank or already taken by a different preset.
    let onRename: (String, String) -> Void
    let onDelete: (String) -> Void
    /// jensyleo's own report (2026-08-26): a fase 1 leftover — the list
    /// had no way to reorder presets, only the alphabetical order a
    /// dictionary's keys happen to sort into. `List`'s own drag-to-
    /// reorder (via `ForEach.onMove`) needs no extra UI on macOS — the
    /// row itself is draggable once this is wired up.
    let onMove: (IndexSet, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newPresetName = ""
    /// Which row is mid-rename, if any — only one at a time, editing state
    /// lives here rather than per-row since `List` rows are only ever
    /// plain `String`s (no per-row model to attach it to).
    @State private var renamingName: String?
    @State private var renameText = ""

    /// jensyleo's own report (2026-08-18): "Apply"/"Update" fired the
    /// instant they were clicked — Apply silently discards whatever
    /// column layout is on screen right now, Update silently overwrites a
    /// saved preset's own data, and a stray click in a list of several
    /// presets is an easy, hard-to-notice mistake either way. Routed
    /// through one confirmation dialog rather than two separate ones so
    /// both read consistently and share the same dismiss/cancel handling.
    private enum PendingAction: Identifiable {
        case apply(String)
        case update(String)
        var id: String {
            switch self {
            case .apply(let name): return "apply:\(name)"
            case .update(let name): return "update:\(name)"
            }
        }
    }
    @State private var pendingAction: PendingAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Column Presets")
                .font(.title3.bold())

            if presetNames.isEmpty {
                Text("No presets saved yet — save the current column layout below to create one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(presetNames, id: \.self) { name in
                        if renamingName == name {
                            HStack {
                                TextField("Name", text: $renameText, onCommit: { commitRename(from: name) })
                                    .textFieldStyle(.roundedBorder)
                                Button("Save") { commitRename(from: name) }
                                Button("Cancel") { renamingName = nil }
                            }
                        } else {
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                                    .help("Drag to reorder")
                                Text(name)
                                Spacer()
                                Button("Apply") { pendingAction = .apply(name) }
                                Button("Update") { pendingAction = .update(name) }
                                    .help("Overwrite this preset with the column layout as it stands right now")
                                Button {
                                    renamingName = name
                                    renameText = name
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                                .help("Rename")
                                Button(role: .destructive) {
                                    onDelete(name)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .onMove(perform: onMove)
                }
                .frame(minHeight: 120, maxHeight: 220)
            }

            Divider()

            HStack {
                TextField("New preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save Current Layout") {
                    onSave(newPresetName)
                    newPresetName = ""
                }
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                    // jensyleo's own report (2026-08-26): this sheet only
                    // ever opens via a button in the Settings window (see
                    // `.romForgeShowColumnPresetsSheet`'s own doc comment
                    // in `LibraryDetailView.swift`), presented on the main
                    // library window because that's where the preset
                    // logic already lives — which makes the library
                    // window key the instant the sheet appears, burying
                    // Settings behind it. Dismissing just leaves the
                    // library window in front; explicitly re-activating
                    // Settings here is what actually returns to "the
                    // menu right before this one" instead of leaving the
                    // user staring at the main window they didn't ask
                    // for. Deferred one runloop turn so it runs after the
                    // sheet's own dismiss animation starts tearing down,
                    // not racing it.
                    //
                    // A first attempt matched `$0.title == "Settings"` —
                    // confirmed live (2026-08-26) that's wrong: SwiftUI's
                    // macOS Settings window titles itself after the
                    // currently selected top-level tab's own label
                    // (`AppSettingsView`'s `TabView`, not this sheet), so
                    // it read "View Options" when that tab was active, not
                    // literally "Settings" — the plain string match never
                    // found it. Matching against every real tab name
                    // (`SystemSettingsView.swift`'s own three
                    // `Label(...)` titles) instead of one hardcoded guess.
                    DispatchQueue.main.async {
                        let settingsTabTitles: Set<String> = ["General", "View Options", "Systems"]
                        NSApp.windows.first(where: { settingsTabTitles.contains($0.title) })?.makeKeyAndOrderFront(nil)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible
        ) {
            Button(confirmationActionTitle) { confirmPendingAction() }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: {
            Text(confirmationMessage)
        }
    }

    private func commitRename(from oldName: String) {
        onRename(oldName, renameText)
        renamingName = nil
    }

    private func confirmPendingAction() {
        switch pendingAction {
        case .apply(let name):
            onApply(name)
        case .update(let name):
            onUpdate(name)
        case nil:
            break
        }
        pendingAction = nil
    }

    private var confirmationTitle: String {
        switch pendingAction {
        case .apply(let name): return "Apply \"\(name)\"?"
        case .update(let name): return "Update \"\(name)\"?"
        case nil: return ""
        }
    }

    private var confirmationActionTitle: String {
        switch pendingAction {
        case .apply: return "Apply"
        case .update: return "Update"
        case nil: return ""
        }
    }

    private var confirmationMessage: String {
        switch pendingAction {
        case .apply(let name): return "This replaces the current column layout for both tables with \"\(name)\"."
        case .update(let name): return "This overwrites \"\(name)\" with the column layout as it stands right now."
        case nil: return ""
        }
    }
}
