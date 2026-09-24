// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import ROMForgeCore
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
    @AppStorage(FixPreferencesSettings.removeUselessFilesKey) private var removeUselessFilesAuto = FixPreferencesSettings.removeUselessFilesDefault
    @AppStorage(FixPreferencesSettings.corruptedFilesPolicyKey) private var corruptedFilesPolicy = FixPreferencesSettings.corruptedFilesPolicyDefault
    @AppStorage(FixPreferencesSettings.corruptedFilesMoveToPathKey) private var corruptedFilesMoveToPath = FixPreferencesSettings.corruptedFilesMoveToPathDefault

    @AppStorage(FixPreferencesSettings.removeUselessRomsKey) private var removeUselessRoms = FixPreferencesSettings.removeUselessRomsDefault
    @AppStorage(FixPreferencesSettings.setsCasePolicyKey) private var setsCasePolicy = FixPreferencesSettings.setsCasePolicyDefault
    @AppStorage(FixPreferencesSettings.romsCasePolicyKey) private var romsCasePolicy = FixPreferencesSettings.romsCasePolicyDefault
    @AppStorage(FixPreferencesSettings.missingRomsSearchScopeKey) private var missingRomsSearchScope = FixPreferencesSettings.missingRomsSearchScopeDefault
    @AppStorage(FixPreferencesSettings.chdDuplicatePreferenceKey) private var chdDuplicatePreference = FixPreferencesSettings.chdDuplicatePreferenceDefault

    var body: some View {
        Form {
            // "Test & Verify" section (the "Test archives before fixing"
            // toggle) temporarily removed at jensyleo's own explicit
            // request (2026-09-17), same reasoning as the right-click
            // "Verify ZIP Integrity" action it mirrors (see that removal's
            // own comment in `GameTreeTableView.swift`) — this toggle was
            // ALREADY the "not yet connected" case this view's own header
            // doc comment describes (see `FixSettingsView`'s own doc
            // comment above, and `FixSettingsView.swift:158`'s own note
            // that "Test archives before fixing" is "a separate,
            // not-yet-connected pre-pass toggle"), so hiding it costs
            // nothing functionally. `testArchives`/`FixPreferencesSettings
            // .testArchivesKey` themselves are untouched — only this
            // section's UI is gone — so restoring it is just re-adding
            // this `Section` block.
            //
            // jensyleo's own decision (2026-09-10): correcting a name the
            // DAT disagrees with is unconditional — the whole reason this
            // app, and its "Fix Mismatched Files"/"Fix Misnamed ROMs
            // Inside Their Archives…" actions, exist — so it was never
            // really an optional toggle the way "Test archives" or
            // "Corrupted files" genuinely are. The only real knob for
            // either action is HOW the corrected (or already-correct)
            // name is STYLED, which is what the two pickers below control.
            // A prior version here had a separate "Apply Case Policy…"
            // action that only re-styled an already-correct name, plus two
            // now-removed toggles gating whether a mismatch got fixed at
            // all — jensyleo's own read on seeing them: "o es una o es la
            // otra." Both toolbar actions now do BOTH halves (repair a
            // wrong name; re-style an already-correct one) themselves, in
            // one click, unconditionally.
            // jensyleo's own request (2026-09-11): "para los case poner la
            // palabra case, no fix" — this section is specifically about
            // HOW a name is styled (case), not the "Fix" repair actions
            // themselves (those live on the toolbar's own "Fix" dropdown);
            // renamed from "Fix" to "Case" to say exactly that.
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
                Text("Governs the toolbar's own \"Fix Mismatched Files\" (Sets case) and \"Fix Misnamed ROMs Inside Their Archives…\" (Roms case) — each ALWAYS runs both halves: a genuinely wrong name is corrected TO this style (\"Don't Touch\" still fixes it, using the DAT's own exact declared case — a real mismatch always needs SOME rename), and an ALREADY-correct name is re-styled to it too, in the same click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // ⚠️ COUPLED TO CODE — jensyleo's own instruction
                // (2026-09-10): if a future change to
                // `RebuildPlanner.planRepair`'s hash-identity logic (the
                // "own-archive-wrong-case" loop, added the same day) ever
                // stops being true — e.g. if identifying a container as
                // this game's own were EVER made to require its entries to
                // already be `.correct` again — this sentence must be
                // revisited too. It exists specifically because jensyleo
                // found the two actions were NOT independent at first (a
                // container rename silently required "Roms case" to run
                // first) and had that fixed on the same hash-identity
                // grounds this text now describes.
                Text("Each action fixes its OWN level independently — the archive's own name (Sets case) or the names of the ROMs inside it (Roms case) — regardless of whether the other one has been fixed yet. A ROM is identified by its hash, not by its current name, so either action works whatever state the other is in; run them in any order, or just one of the two.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // jensyleo's own instruction (2026-09-10): "la app se guía
                // por el DAT, por ende es su base para todo... eso debe
                // quedar documentado en la sección case de la app y en el
                // help" — the DAT is the ONLY source of truth this app's own
                // Correct/Incorrect status is ever judged against (see
                // `ROMMatcher`'s exact, case-sensitive `==`), never against
                // whatever ROMForge itself last wrote here. See the Help
                // window's own "Settings — Fix" topic ("The DAT is always
                // the source of truth") for the full explanation.
                Text("⚠️ The DAT is always the source of truth for what counts as \"Correct\"/\"Ok\". Any style here besides Datafile Case makes the styled name differ from the DAT's own exact declared case — the next Scan will report that same File/ROM as Incorrect again, and running Fix again just re-applies this same style, forever. Only Datafile Case can ever produce a name ROMForge's own audit will keep calling Correct.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                // jensyleo's own request (2026-09-10): "hay que poner la
                // opción de restore to defaults en las opciones del Fix
                // para el case" — resets both pickers back to "Datafile
                // Case" (the DAT's own exact declared case), the least
                // surprising default and the one with no case-sensitivity
                // risk at all (see `currentSetsCasePolicyRisksCaseMismatch`/
                // `currentRomsCasePolicyRisksCaseMismatch` in
                // `LibraryDetailView`).
                HStack {
                    Button("Reset to Defaults") {
                        setsCasePolicy = FixPreferencesSettings.setsCasePolicyDefault
                        romsCasePolicy = FixPreferencesSettings.romsCasePolicyDefault
                    }
                    Spacer()
                }
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
                HStack {
                    Button("Reset to Defaults") {
                        removeUselessFilesAuto = FixPreferencesSettings.removeUselessFilesDefault
                        removeUselessRoms = FixPreferencesSettings.removeUselessRomsDefault
                    }
                    Spacer()
                }
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
                Text("Applied by the toolbar's own \"Fix\" dropdown → \"Handle Corrupted Files…\", which always confirms before touching anything (regardless of \"Test archives before fixing\" above, which is a separate, not-yet-connected pre-pass toggle). \"Move to\" needs a folder chosen above; \"Delete\" permanently removes the entry from its archive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reset to Defaults") {
                        corruptedFilesPolicy = FixPreferencesSettings.corruptedFilesPolicyDefault
                        corruptedFilesMoveToPath = FixPreferencesSettings.corruptedFilesMoveToPathDefault
                    }
                    Spacer()
                }
            }

            // jensyleo's own request (2026-09-11): "Colocar la opcion de:
            // Solo buscar ROMS faltantes en la carpeta de mantenimiento o en
            // cualquiera de las declaradas" — governs "Repair from
            // Maintenance Folder…"'s own donor search (`LibraryViewModel
            // .planRepairFromMaintenanceFolderPreviewCount`). Distinct from
            // "Find missing roms in scavenging folders" below (a separate,
            // still-unbuilt feature for arbitrary user-added folders outside
            // any system's own configuration) — this one only ever searches
            // folders the system ALREADY declares (its Maintenance
            // subfolder, and optionally its own configured ROM folders).
            // jensyleo's own request (2026-09-11): "esta opcion... debe
            // estar ligada a la opcion de la pestaña general Maintenance
            // folder, si esta no esta configurado (el folder) no debe
            // aparecer como configurable en la pestaña fix" — this whole
            // scope choice is meaningless without a Maintenance root
            // configured at all: even "+ All ROM Folders" mode still
            // requires the Maintenance subfolder to exist as PART of the
            // search set (`LibraryViewModel
            // .planRepairFromMaintenanceFolderPreviewCount`'s own
            // `searchFolders` always starts from it), so "Repair from
            // Maintenance Folder…" already refuses outright with no
            // Maintenance root set, regardless of this setting's value.
            Section("Find ROMS") {
                if MaintenanceFolderSettings.folderURL != nil {
                    Picker("Search missing ROMs in", selection: $missingRomsSearchScope) {
                        ForEach(MissingRomsSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("\"Maintenance Folder Only\" looks solely at this system's own Maintenance subfolder — donors deliberately staged there. \"+ All ROM Folders\" also searches every one of this system's own currently-configured ROM folders, so a rom that's merely misplaced in a sibling folder (a different drive, a region subfolder, an old backup location) can donate too. Both are strictly read-only — nothing here ever writes to a ROM folder, only reads from it as a possible donor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Reset to Defaults") { missingRomsSearchScope = FixPreferencesSettings.missingRomsSearchScopeDefault }
                        Spacer()
                    }
                } else {
                    Text("No Maintenance folder configured yet")
                        .foregroundStyle(.secondary)
                    Text("This scope choice only applies to \"Repair from Maintenance Folder…\", which needs a Maintenance folder to search in the first place. Set one in Settings → General → \"Maintenance folder\" first, then this becomes configurable here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // jensyleo's own request (2026-09-19), after a real kinst2.chd
            // sitting byte-identical BOTH directly in Nintendo's own ROM
            // folder root AND inside a same-named Nintendo/kinst2/
            // subfolder — a real, common layout ambiguity with no single
            // "obviously right" answer, so ROMForge asks rather than
            // guesses. Affects which copy `DiskAuditor` reports `.correct`
            // (and therefore which one "Remove Redundant Files…" would
            // offer to delete as the leftover) whenever the same disk
            // exists more than once.
            Section("Duplicate CHDs") {
                Picker("When the same CHD exists in more than one place", selection: $chdDuplicatePreference) {
                    ForEach(CHDDuplicatePreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .pickerStyle(.segmented)
                Text("\"Prefer ROM Folder Root\" always treats the copy sitting directly in the ROM folder as correct; \"Prefer Subfolder\" always treats the copy inside a subfolder named after the game as correct. Only matters when the exact same CHD genuinely exists in both places at once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reset to Defaults") { chdDuplicatePreference = FixPreferencesSettings.chdDuplicatePreferenceDefault }
                    Spacer()
                }
            }

            // jensyleo's own request (2026-09-11): "implementa: Create dummy
            // roms for nodump entries, Remove zip comments y Unzip and
            // rezip every archive" — the first two are now fully built
            // (`RebuildPlanner.planCreateDummyRoms`/`planRemoveZipComments`
            // + their own `RebuildExecutor` operations and `LibraryViewModel`
            // actions), so they moved out of "Not yet available" — there's
            // no separate on/off toggle for either (same as "Remove Useless
            // Files…"/"Repair from Sibling Sets…" above, which also have no
            // Settings toggle of their own): each is a standalone action,
            // reachable from the toolbar's own "Fix" dropdown once added to
            // `LibraryDetailView.fixActionsEnabledForTesting` per jensyleo's
            // own one-at-a-time manual-testing policy. "Unzip and rezip
            // every archive" was built the same way, then removed outright
            // the same day (jensyleo: "elimina eso, no lo vamos a usar, no
            // tiene sentido para esta app") — see ROADMAP.md's own note for
            // the reasoning and for a future implementer's exact starting
            // point if that decision is ever revisited.
            // jensyleo's own decision (2026-09-11): "Allow multiple rom
            // formats" removed from the UI outright rather than kept as a
            // disabled toggle — this one is never going to be implemented
            // (see ROADMAP.md's own note on it for the reasoning, and for a
            // future implementer's exact starting point if that changes).
            // "Find missing roms in scavenging folders" removed the same
            // day, same reasoning (jensyleo: "la idea es que solo busque
            // las ROMs para reparación de la carpeta de reparación o de
            // las ya agregadas a Rom Folder") — an arbitrary "scavenging"
            // folder unrelated to a system is explicitly out of scope by
            // design, and "Repair from Maintenance Folder…" + its own
            // Settings → Fix → "Find ROMS" → "Search missing ROMs in"
            // scope picker already covers exactly the two sources this
            // should ever search (the Maintenance subfolder, optionally
            // plus the system's own already-configured ROM folders) — see
            // ROADMAP.md's own note for the full reasoning.
            // "Fix samples" implemented 2026-09-11 (jensyleo: "implementalo,
            // es clave para MAME") as "Fix Samples…" in the toolbar's own
            // "Fix" dropdown, once added to `LibraryDetailView
            // .fixActionsEnabledForTesting` — its own on/off toggle and
            // folder setting live in Settings → Systems → MAME →
            // "Samples" (MAME-exclusive, per jensyleo's own explicit
            // placement instruction), not here. With it gone, "Not yet
            // available" has nothing left in it — removed entirely rather
            // than kept as an empty section; a future genuinely-deferred
            // item gets it back.
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
