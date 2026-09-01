// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import SwiftUI

/// Settings → "Fix" tab — Fase 2 Step 5. Parallels ClrMamePro's own
/// Preferences → Fix tab (see ROADMAP.md's own screenshot review of it,
/// 2026-08-20): every policy that governs what the "Fix" action actually
/// does, gathered in one place rather than folded into "General". Built as
/// a shell first: every toggle here exists and persists (`FixPreferences
/// Settings`) even for items with no real action behind them yet — see
/// that type's own per-key doc comments for which ones are actually wired
/// versus still just a checkbox. An unwired toggle is visibly disabled with
/// a "not yet connected" caption rather than silently doing nothing.
struct FixSettingsView: View {
    @AppStorage(FixPreferencesSettings.testArchivesKey) private var testArchives = FixPreferencesSettings.testArchivesDefault
    @AppStorage(FixPreferencesSettings.renameFilesKey) private var renameFiles = FixPreferencesSettings.renameFilesDefault
    @AppStorage(FixPreferencesSettings.removeUselessFilesKey) private var removeUselessFilesAuto = FixPreferencesSettings.removeUselessFilesDefault
    @AppStorage(FixPreferencesSettings.corruptedFilesPolicyKey) private var corruptedFilesPolicy = FixPreferencesSettings.corruptedFilesPolicyDefault
    @AppStorage(FixPreferencesSettings.corruptedFilesMoveToPathKey) private var corruptedFilesMoveToPath = ""

    @AppStorage(FixPreferencesSettings.renameRomsKey) private var renameRoms = FixPreferencesSettings.renameRomsDefault
    @AppStorage(FixPreferencesSettings.removeUselessRomsKey) private var removeUselessRoms = FixPreferencesSettings.removeUselessRomsDefault
    @AppStorage(FixPreferencesSettings.findMissingRomsKey) private var findMissingRoms = FixPreferencesSettings.findMissingRomsDefault
    @AppStorage(FixPreferencesSettings.createDummyRomsKey) private var createDummyRoms = FixPreferencesSettings.createDummyRomsDefault
    @AppStorage(FixPreferencesSettings.fixSamplesKey) private var fixSamples = FixPreferencesSettings.fixSamplesDefault
    @AppStorage(FixPreferencesSettings.removeZipCommentsKey) private var removeZipComments = FixPreferencesSettings.removeZipCommentsDefault
    @AppStorage(FixPreferencesSettings.unzipAndRezipKey) private var unzipAndRezip = FixPreferencesSettings.unzipAndRezipDefault
    @AppStorage(FixPreferencesSettings.allowMultipleRomFormatsKey) private var allowMultipleRomFormats = FixPreferencesSettings.allowMultipleRomFormatsDefault
    @AppStorage(FixPreferencesSettings.setsCasePolicyKey) private var setsCasePolicy = FixPreferencesSettings.setsCasePolicyDefault
    @AppStorage(FixPreferencesSettings.romsCasePolicyKey) private var romsCasePolicy = FixPreferencesSettings.romsCasePolicyDefault

    var body: some View {
        Form {
            Section("Test & Verify") {
                Toggle("Test archives before fixing", isOn: $testArchives)
                Text("Runs a ZIP integrity check (local-header vs central-directory CRC32) on every archive before \"Fix\" does anything else, and applies the \"Corrupted files\" policy below to whatever it finds. Off by default — a full integrity pass reads every archive's data twice, worth paying for only when you suspect real corruption.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Rename") {
                Toggle("Rename files to match the DAT", isOn: $renameFiles)
                Text("Renames a misnamed archive (or loose file) in place to the name its DAT entry declares. This is what the toolbar's own \"Fix\" button already does — turning this off here disables that specific part of \"Fix\" without disabling the whole action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Rename roms inside archives", isOn: $renameRoms)
                Text("Renames a misnamed rom entry inside an otherwise-correctly-named zip via the toolbar's own \"Rename ROMs Inside Archives…\" action, which always confirms regardless of this toggle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Remove") {
                Toggle("Remove useless files automatically during Fix", isOn: $removeUselessFilesAuto)
                Text("Deletes every file the DAT recognizes nothing about at all. Always destructive — the standalone \"Remove Useless Files…\" toolbar action always asks for confirmation regardless of this toggle; this setting only controls whether the general \"Fix\" pass also does it without a separate prompt each time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Remove useless roms inside archives", isOn: $removeUselessRoms)
                Text("Same underlying action as the toggle above — \"Remove Useless Files…\" already removes a zip-internal unrecognized entry without touching anything else in that archive. Kept as its own toggle to mirror ClrMamePro's own panel; there's nothing to configure differently between the two yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Corrupted files") {
                Picker("When a file is confirmed corrupt", selection: $corruptedFilesPolicy) {
                    ForEach(CorruptedFilesPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                if corruptedFilesPolicy == .moveTo {
                    HStack {
                        Text(corruptedFilesMoveToPath.isEmpty ? "No folder chosen" : corruptedFilesMoveToPath)
                            .font(.caption)
                            .foregroundStyle(corruptedFilesMoveToPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseCorruptedFilesFolder() }
                    }
                }
                Text("Only takes effect when \"Test archives before fixing\" above is on — this policy applies to whatever that pass flags as internally inconsistent. \"Move to\" (the default) is reversible; \"Delete\" asks for a one-time confirmation the first time you switch to it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Case") {
                Picker("Sets case (archive names)", selection: $setsCasePolicy) {
                    ForEach(FileCasePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                Picker("Roms case (entry names)", selection: $romsCasePolicy) {
                    ForEach(FileCasePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(true)
                Text("\"Sets case\" not yet connected — reuses the rename machinery above once it's wired to a real action. \"Roms case\" additionally needs the same central-directory rewrite noted elsewhere on this tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Not yet available") {
                Toggle("Find missing roms in scavenging folders", isOn: $findMissingRoms).disabled(true)
                Toggle("Create dummy roms for nodump entries", isOn: $createDummyRoms).disabled(true)
                Toggle("Fix samples", isOn: $fixSamples).disabled(true)
                Toggle("Remove zip comments", isOn: $removeZipComments).disabled(true)
                Toggle("Unzip and rezip every archive", isOn: $unzipAndRezip).disabled(true)
                Toggle("Allow multiple rom formats", isOn: $allowMultipleRomFormats).disabled(true)
                Text("Each needs its own not-yet-built infrastructure (a scavenging-folder setting, a placeholder-file format, sample-file inventory, a batch rewrite entry point, or a second output format besides ZIP) — kept here, visibly inert, so this tab already reflects the full scope of ClrMamePro's own Fix panel rather than only what's done so far.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseCorruptedFilesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a quarantine folder for confirmed-corrupt files"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        corruptedFilesMoveToPath = url.path
    }
}
