// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import ROMForgeCore
import SwiftUI

struct AddSystemSheet: View {
    /// Existing categories from other configured systems, offered so the
    /// user doesn't have to retype "Nintendo" the same way every time.
    var existingCategories: [String] = []
    let onAdd: (RomSystem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var datURL: URL?
    @State private var romFolderURLs: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add System")
                .font(.headline)

            TextField("Name (e.g. Super Nintendo)", text: $name)
                .textFieldStyle(.roundedBorder)

            TextField("Category (optional, e.g. Nintendo)", text: $category)
                .textFieldStyle(.roundedBorder)
            if !existingCategories.isEmpty {
                HStack(spacing: 6) {
                    Text("Existing:").font(.caption).foregroundStyle(.secondary)
                    ForEach(existingCategories, id: \.self) { existing in
                        Button(existing) { category = existing }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundStyle(.blue)
                    }
                }
            }

            HStack {
                Button("Select DAT…") { chooseDAT() }
                Text(datURL?.lastPathComponent ?? "No DAT selected")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("ROM Folders").font(.subheadline)
                    Spacer()
                    Button("Add Folder…") { addROMFolder() }
                }
                if romFolderURLs.isEmpty {
                    Text("No folders selected — a collection can span more than one.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    List {
                        ForEach(romFolderURLs, id: \.self) { url in
                            HStack {
                                Text(url.path)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button {
                                    romFolderURLs.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 80)
                }
            }

            // Rom/Bios merge mode used to be configured here per system —
            // it's now one global setting (Settings → Systems → "MAME")
            // that applies to every MAME system uniformly, since it isn't
            // really a per-DAT preference (see `RomSystem`'s own doc
            // comment for the full reasoning).
            Text("MAME's Rom/Bios merge mode is configured once for every system, in Settings (⌘,) → Systems.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add") { add() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || datURL == nil || romFolderURLs.isEmpty)
            }
        }
        .padding()
        .frame(width: 500, height: 420)
    }

    private func chooseDAT() {
        let panel = NSOpenPanel()
        // No content-type filter: DAT files show up with all sorts of
        // extensions in the wild (.dat, .xml, sometimes none at all), and a
        // ".dat" file's UTI doesn't conform to public.xml even though its
        // content is XML — restricting to .xml silently hid .dat files from
        // the picker entirely. Real validation happens when it's parsed.
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a DAT (.dat or .xml — Logiqx/ClrMamePro or MAME -listxml, auto-detected)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        datURL = url
        if name.isEmpty {
            name = url.deletingPathExtension().lastPathComponent
        }
    }

    private func addROMFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select one or more folders containing this system's ROMs"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !romFolderURLs.contains(url) {
            romFolderURLs.append(url)
        }
    }

    private func add() {
        guard let datURL, !romFolderURLs.isEmpty else { return }
        onAdd(
            RomSystem(
                name: name.trimmingCharacters(in: .whitespaces),
                category: category.trimmingCharacters(in: .whitespaces),
                datURL: datURL,
                romFolderURLs: romFolderURLs
            )
        )
        dismiss()
    }
}
