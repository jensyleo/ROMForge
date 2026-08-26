// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import ROMForgeCore
import SwiftUI

/// jensyleo's own request (2026-08-19): "Compare DAT Versions…" — detect
/// added/removed/possibly-renamed games between the system's currently
/// loaded DAT and an older/different version the user picks from disk.
/// Pure metadata comparison (`DATVersionDiff`, ROMForgeCore) — never
/// touches the scanned collection or its audit, matching this app's own
/// read-only mode.
struct DATVersionCompareSheet: View {
    /// Already-loaded DAT for the system — the "new" side, per jensyleo's
    /// own spec: only the "old" file is ever picked from disk, this one is
    /// always whatever's already active in memory.
    let currentDAT: DATFile
    let systemName: String

    @Environment(\.dismiss) private var dismiss
    @State private var oldDATURL: URL?
    @State private var diff: DATVersionDiff?
    @State private var errorMessage: String?
    @State private var isComparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compare DAT Versions")
                .font(.title3.bold())

            HStack {
                Button("Choose Older DAT…") { chooseOldDAT() }
                if let oldDATURL {
                    Text(oldDATURL.lastPathComponent)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if isComparing {
                ProgressView("Comparing…")
            } else if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.callout)
            } else if let diff {
                diffContent(diff)
            } else {
                Text("Pick an older or different version of this system's own DAT to compare against what's currently loaded (\"\(systemName)\").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                if diff != nil {
                    Button("Export as Text…") { exportAsText() }
                }
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }

    @ViewBuilder
    private func diffContent(_ diff: DATVersionDiff) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                diffSection(title: "Added (\(diff.added.count))", rows: diff.added.map { "\($0.name) — \($0.description)" })
                diffSection(title: "Removed (\(diff.removed.count))", rows: diff.removed.map { "\($0.name) — \($0.description)" })
                diffSection(
                    title: "Possible Renames (\(diff.renamed.count))",
                    rows: diff.renamed.map { "\($0.oldName) → \($0.newName)  (matched rom: \($0.matchedRomName))" }
                )
            }
        }
    }

    @ViewBuilder
    private func diffSection(title: String, rows: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if rows.isEmpty {
                Text("None").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(.system(.callout, design: .monospaced))
                }
            }
        }
    }

    /// No content-type filter — same reasoning as `AddSystemSheet`'s own
    /// `chooseDAT()`: real DAT files show up under all sorts of
    /// extensions, and validation happens at parse time regardless.
    private func chooseOldDAT() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select the older/different DAT to compare against \"\(systemName)\"'s currently loaded one"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        oldDATURL = url
        compare(url: url)
    }

    private func compare(url: URL) {
        diff = nil
        errorMessage = nil
        isComparing = true
        // Same mode the system is already using — `mergeMode`/`biosMergeMode`
        // only reshape how a MAME `-listxml` machine's roms are laid out
        // into archives; comparing under mismatched modes would report
        // roms as "moved" purely from that, not from anything the DAT
        // itself actually changed.
        let mergeMode = MAMEMergeModeSettings.current
        let biosMergeMode = MAMEMergeModeSettings.currentBios
        Task {
            do {
                let oldFile = try DATLoader.load(contentsOf: url, mergeMode: mergeMode, biosMergeMode: biosMergeMode)
                let result = DATVersionDiff.compare(oldFile: oldFile, newFile: currentDAT)
                await MainActor.run {
                    diff = result
                    isComparing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Couldn't load that DAT: \(error.localizedDescription)"
                    isComparing = false
                }
            }
        }
    }

    /// Plain, greppable text — same "one section per category, blank line
    /// between" shape the on-screen sections already use, just flattened.
    private func exportAsText() {
        guard let diff else { return }
        var lines: [String] = ["Compare DAT Versions — \(systemName)", ""]
        lines.append("Added (\(diff.added.count)):")
        lines.append(contentsOf: diff.added.isEmpty ? ["  None"] : diff.added.map { "  \($0.name) — \($0.description)" })
        lines.append("")
        lines.append("Removed (\(diff.removed.count)):")
        lines.append(contentsOf: diff.removed.isEmpty ? ["  None"] : diff.removed.map { "  \($0.name) — \($0.description)" })
        lines.append("")
        lines.append("Possible Renames (\(diff.renamed.count)):")
        lines.append(contentsOf: diff.renamed.isEmpty
            ? ["  None"]
            : diff.renamed.map { "  \($0.oldName) → \($0.newName)  (matched rom: \($0.matchedRomName))" })
        let text = lines.joined(separator: "\n")

        let panel = NSSavePanel()
        panel.title = "Export DAT Comparison"
        panel.nameFieldStringValue = "datCompare_\(systemName).txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
