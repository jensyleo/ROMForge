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
    let onDelete: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var newPresetName = ""

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
                    HStack {
                        Text(name)
                        Spacer()
                        Button("Apply") { onApply(name) }
                        Button(role: .destructive) {
                            onDelete(name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
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
        .frame(width: 420)
    }
}
