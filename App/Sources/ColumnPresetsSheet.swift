// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

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

    @Environment(\.dismiss) private var dismiss
    @State private var newPresetName = ""
    /// Which row is mid-rename, if any — only one at a time, editing state
    /// lives here rather than per-row since `List` rows are only ever
    /// plain `String`s (no per-row model to attach it to).
    @State private var renamingName: String?
    @State private var renameText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Column Presets")
                .font(.title3.bold())

            if presetNames.isEmpty {
                Text("No presets saved yet — save the current column layout below to create one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                List(presetNames, id: \.self) { name in
                    if renamingName == name {
                        HStack {
                            TextField("Name", text: $renameText, onCommit: { commitRename(from: name) })
                                .textFieldStyle(.roundedBorder)
                            Button("Save") { commitRename(from: name) }
                            Button("Cancel") { renamingName = nil }
                        }
                    } else {
                        HStack {
                            Text(name)
                            Spacer()
                            Button("Apply") { onApply(name) }
                            Button("Update") { onUpdate(name) }
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
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func commitRename(from oldName: String) {
        onRename(oldName, renameText)
        renamingName = nil
    }
}
