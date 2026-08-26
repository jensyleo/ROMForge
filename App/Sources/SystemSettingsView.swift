// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
import ROMForgeCore
import SwiftUI

/// ROMForge's ⌘, Settings window — the conventional macOS home for
/// configuration that isn't part of the main content flow. Two tabs:
/// "Systems" (MAME's executable location and global Rom/Bios merge mode,
/// this view) and "General" (`GeneralSettingsView`, the rest of the
/// app-wide preferences) — see `AppSettingsView`, which hosts both.
///
/// This used to list every configured *system* here, each with its own
/// separate Rom/Bios merge mode — jensyleo's own call (2026-07-27): having
/// to configure that separately per MAME DAT/system (e.g. two systems
/// comparing different MAME versions side by side) made no sense for a
/// setting that isn't really about any *specific* DAT at all. There's now
/// just one fixed "MAME" entry, and the merge mode it configures
/// (`MAMEMergeModeSettings`, a global `UserDefaults`-backed setting) applies
/// to every MAME system uniformly, regardless of which one is currently
/// loaded/selected.
///
/// The MAME executable path (`MAMEMergeSettingsForm`'s own "MAME
/// executable" section) lives here too, not in "General" — jensyleo's own
/// call (2026-07-30): every setting about *how MAME itself behaves* (which
/// binary, how its sets are laid out) belongs together under "Systems", the
/// same place more systems besides MAME will eventually be configured,
/// rather than split across two tabs for no reason tied to what each
/// setting actually configures.
struct SystemSettingsView: View {
    var store: SystemLibraryStore

    var body: some View {
        HStack(spacing: 0) {
            List(selection: .constant(Optional("MAME"))) {
                Text("MAME").tag("MAME")
            }
            .listStyle(.sidebar)
            .frame(width: 170)

            Divider()

            MAMEMergeSettingsForm(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum SettingsTab: Hashable {
    case systems
    case general
    case viewOptions
}

/// Hosts both Settings tabs at a shared window size — `SystemSettingsView`
/// used to set its own `.frame` directly, back when it was the only tab.
///
/// `TabView` is given an explicit `selection` binding + a `.tag()` per tab
/// rather than relying on its own implicit/automatic selection tracking —
/// without them, clicking "General" visually did nothing at all (confirmed
/// both by a real click and by automated testing: the "Systems" tab stayed
/// highlighted/selected no matter what was clicked). Driving selection
/// explicitly is the standard, reliable fix for this exact known SwiftUI
/// quirk.
struct AppSettingsView: View {
    @Bindable var store: SystemLibraryStore
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralSettingsView()
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(SettingsTab.general)
                // jensyleo's own request (2026-08-12): a dedicated tab for
                // layout/visibility toggles — see `ViewOptionsSettingsView`'s
                // own doc comment for why this is separate from "General".
                ViewOptionsSettingsView(store: store)
                    .tabItem { Label("View Options", systemImage: "sidebar.squares.leading") }
                    .tag(SettingsTab.viewOptions)
                SystemSettingsView(store: store)
                    .tabItem { Label("Systems", systemImage: "list.bullet") }
                    .tag(SettingsTab.systems)
            }
            Divider()
            // jensyleo's own request (2026-07-30): a visible "Done" button
            // to close the window, alongside — not instead of — the
            // native traffic-light close button a `Settings{}` scene
            // already has.
            HStack {
                Spacer()
                Button("Done") { dismissWindow() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            // jensyleo's own request (2026-08-13): Escape should close this
            // window too, same as Enter already does via "Done"'s own
            // `.defaultAction` shortcut above — this settings window has no
            // actual "Cancel" (every toggle/setting here applies live, there's
            // nothing to discard), so `.cancelAction` here just means "the
            // same close" as `.defaultAction`, not a separate revert. Hidden
            // (`.opacity(0)` + zero frame) rather than a second visible
            // button — there's genuinely only one action to offer, this just
            // gives it a second key that triggers it.
            Button("Close") { dismissWindow() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        // Enlarged (was 620×460) and made resizable with a floor rather
        // than a hard fixed size — jensyleo's own request (2026-07-30):
        // several controls (the merge-mode warning text, in particular)
        // wrapped awkwardly in the old fixed size.
        .frame(minWidth: 760, minHeight: 560)
    }

    @Environment(\.dismissWindow) private var dismissWindow
}

private struct MAMEMergeSettingsForm: View {
    var store: SystemLibraryStore
    @AppStorage(MAMEMergeModeSettings.mergeModeKey) private var mergeModeRaw = MAMEMergeModeSettings.defaultMergeMode.rawValue
    @AppStorage(MAMEMergeModeSettings.biosMergeModeKey) private var biosMergeModeRaw = MAMEMergeModeSettings.defaultBiosMergeMode.rawValue
    @AppStorage(MAMELaunchSettings.executablePathKey) private var mamePath = ""
    /// jensyleo's own request (2026-08-13): "esas View Options llévalas a
    /// la sección MAME de System, tiene más sentido" — moved here from
    /// `ViewOptionsSettingsView` (itself moved there from `GeneralSettingsView`
    /// just before that, in the same conversation) after realizing every
    /// `DatabaseFilter` branch is a MAME-shaped concept, and "Systems" →
    /// "MAME" is where every other MAME-specific setting already lives
    /// (the executable path, both merge modes) — not "View Options",
    /// which is about panel layout in general, not any one system's own
    /// configuration. See `DatabaseFilterVisibilitySettings`'s own doc
    /// comment (`ViewOptionsSettingsView.swift`, where the storage/logic
    /// itself still lives — only this Form's own UI moved) for the
    /// storage format.
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey) private var enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue
    /// Snapshot of both merge-mode values from the moment this form
    /// appeared — jensyleo's own request (2026-07-30): warn that a
    /// changed merge/BIOS mode needs every system's folders rescanned to
    /// actually take effect (a MAME DAT is only ever re-parsed under the
    /// new layout the next time it's loaded — see this file's own
    /// existing "Changes re-parse a system's DAT..." caption below, which
    /// this banner makes hard to miss instead of easy to skip past).
    @State private var mergeModeAtAppear: String?
    @State private var biosMergeModeAtAppear: String?
    @State private var didPurgeMAMEFiles = false
    @State private var purgedMAMEFileCount = 0

    private var mergeModeChangedSinceAppear: Bool {
        guard let mergeModeAtAppear, let biosMergeModeAtAppear else { return false }
        return mergeModeAtAppear != mergeModeRaw || biosMergeModeAtAppear != biosMergeModeRaw
    }

    /// `false` only once the currently-selected system's DAT has actually
    /// been loaded and confirmed to have zero clone (`cloneOf != nil`)
    /// games at all (e.g. NEOGEO — every machine is its own standalone
    /// entry) — `nil` (never scanned yet) or `true` shows the normal,
    /// unrestricted picker. See `RomSystem.hasClones`'s own doc comment
    /// for why this is a *contextual warning*, not a hard restriction:
    /// merge mode stays a genuinely global setting (jensyleo's own call,
    /// 2026-07-27), so this can only ever warn about the system that
    /// happens to be selected right now, not gate the setting itself.
    private var selectedSystemHasNoClones: Bool {
        store.selectedSystem?.hasClones == false
    }

    private var mergeMode: Binding<SetMergeMode> {
        Binding(
            get: { SetMergeMode(rawValue: mergeModeRaw) ?? MAMEMergeModeSettings.defaultMergeMode },
            set: { mergeModeRaw = $0.rawValue }
        )
    }
    private var biosMergeMode: Binding<SetMergeMode> {
        Binding(
            get: { SetMergeMode(rawValue: biosMergeModeRaw) ?? MAMEMergeModeSettings.defaultBiosMergeMode },
            set: { biosMergeModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            if mergeModeChangedSinceAppear {
                Label("Rom/Bios merge mode changed — rescan every MAME system's folders for this to actually take effect.", systemImage: "arrow.clockwise.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
            Section("MAME executable") {
                // Presence of a path is the toggle itself — leaving it
                // empty is how this feature stays off, rather than a
                // separate on/off switch that could disagree with whether
                // a real binary is actually configured. MAME-only for now
                // (per jensyleo's own request) — not a generic "launch in
                // any emulator" setting. Moved here from "General"
                // (jensyleo's own call, 2026-07-30) — see this file's own
                // doc comment for why.
                HStack {
                    Text(mamePath.isEmpty ? "Not configured" : mamePath)
                        .font(.caption)
                        .foregroundStyle(mamePath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    // "Default" loads the conventional Homebrew install
                    // location directly — jensyleo's own call (2026-07-30):
                    // that's where `brew install mame` actually puts the
                    // real executable on every current Mac, so most users
                    // never need "Locate…"'s file panel at all.
                    Button("Default") { mamePath = MAMELaunchSettings.homebrewDefaultPath }
                    Button("Locate…") { locateMAME() }
                    if !mamePath.isEmpty {
                        Button("Clear") { mamePath = "" }
                    }
                }
                Text("Lets you launch the selected game directly in MAME to test it, from a game's context menu or the \"Play\" toolbar button — only for MAME systems, and only once a real `mame` executable is located here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Purge MAME Auxiliary Files") {
                        purgedMAMEFileCount = MAMEAuxiliaryFilesPurger.purge()
                        didPurgeMAMEFiles = true
                    }
                    Spacer()
                }
                Text("Clears whatever MAME itself has written under its own working directory while running a game launched from here (\"cfg\"/\"nvram\"/\"snap\", and a machine-specific \"diff\" scratch overlay for any hard disk MAME treats as writable) — per-game settings, screenshots, and in-progress hard-disk state, none of it anything ROMForge needs to keep. Never touches your ROMs, DATs, or any scan result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("MAME") {
                // Confirmed against a real reference MAME frontend's own
                // Settings dialog: "Rom merge mode" and "Bios merge mode"
                // are two fully independent Merged/Split/Un-merged
                // choices — neither implies or gates the other. Only
                // meaningful for a MAME `-listxml` DAT (Logiqx/
                // software-list DATs have no merge concept — these
                // pickers just go unused for those). Applies to every
                // MAME system uniformly — see this file's own doc comment
                // for why this is no longer per-system.
                GroupBox("Rom merge mode") {
                    Picker("", selection: mergeMode) {
                        Text("Merged (All ROM in parent)").tag(SetMergeMode.merged)
                        Text("Split (Only specific ROM in clone set)").tag(SetMergeMode.split)
                        Text("Un-merged (All ROM in parent and clones) — Recommended").tag(SetMergeMode.nonMerged)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .padding(.top, 4)
                    // jensyleo's own request (2026-08-05): make ROMForge's
                    // own recommendation visible in the UI itself, not just
                    // in code comments/`MAMEMergeModeSettings.defaultMergeMode`'s
                    // own doc comment (which is already `.nonMerged` for
                    // exactly this reason). Shown whenever a mode OTHER than
                    // the recommended one is selected — an always-on nudge
                    // back toward it, distinct from the `.merged`-specific
                    // caution below (which explains a concrete pitfall of
                    // that one choice; this explains why Un-merged is the
                    // better default in general).
                    if mergeMode.wrappedValue != .nonMerged {
                        Label {
                            Text("Un-merged is recommended: every game's archive is fully self-contained, so nothing can show as \"incomplete\" just because a parent's or clone's own separate archive happens to be missing or misplaced. The trade-off is disk space (shared content is duplicated across archives) — usually a fine trade for auditing/managing a collection rather than running it on space-limited original hardware.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "star.fill").foregroundStyle(.blue)
                        }
                        .padding(.top, 4)
                    }
                    // Jensyleo's own request (2026-08-04): real confusion
                    // happened live over exactly this — a game showing
                    // "incomplete"/"Bad" under Merged, mistaken for a bug,
                    // when it was actually correct: `gpilots`, `maglord`,
                    // `mslug2`-`mslug5`, `nitd` (among others) all have
                    // real clone/hack/bootleg variants in the DAT, and
                    // Merged requires the parent's single archive to also
                    // contain every one of those clones' own unique roms —
                    // not just the parent's. A permanent, always-visible
                    // caution here (not only the contextual "this specific
                    // system has no clones at all" note further down)
                    // since this applies to *any* system with real clones,
                    // which is the common case, not the exception.
                    if mergeMode.wrappedValue == .merged {
                        Label {
                            Text("With \"Merged\", a parent game will likely show as incomplete if you don't also have its clones' own unique roms — Merged expects ONE archive to contain the parent's roms *and* every one of its clones' own content, not just the parent's. Use with caution.")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        }
                        .padding(.top, 4)
                    }
                }

                GroupBox("Bios merge mode") {
                    Picker("", selection: biosMergeMode) {
                        Text("Merged (BIOS in parent)").tag(SetMergeMode.merged)
                        Text("Split (BIOS in separate file)").tag(SetMergeMode.split)
                        Text("Un-merged (BIOS in parent and clones)").tag(SetMergeMode.nonMerged)
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                    .padding(.top, 4)
                }

                // Contextual note, not a restriction — see
                // `selectedSystemHasNoClones`'s own doc comment. Only
                // shown once the currently-selected system's DAT has
                // actually confirmed it has no clones at all; silent for
                // any system with a real parent/clone family, or one not
                // scanned yet.
                //
                // Rewritten (2026-08-03) after a real bug fix changed what's
                // actually true here: `MAMESetLayoutPlanner.mergedGame` used
                // to skip a `mergeName == nil` filter its two sibling
                // functions already applied, so "Merged" alone injected a
                // clone-less machine's `merge=`-tagged BIOS-variant
                // redeclarations into its own expected rom list — genuinely
                // different from "Split"/"Un-merged", and worth a specific
                // warning about picking one of those two instead. Now that
                // that's fixed, all three Rom merge mode choices produce the
                // literal same result for a machine with no clones (there's
                // simply no parent/clone relationship for any of them to
                // act on) — so the old wording ("pick Split or Un-merged
                // instead of Merged") is no longer accurate; it's not that
                // Merged is worse here, it's that none of the three matter
                // at all anymore. Also dropped the old BIOS-merged aside —
                // that's real (`DATLoader.swift`'s own `biosMode != .merged
                // || !machine.isBios` filter drops a BIOS machine's own
                // standalone archive entry under Bios-Merged), but it's
                // general Bios-Merged-mode behavior for *any* MAME system
                // with a BIOS dependency, clones or not — unrelated to this
                // specific "no clones" fact, and confusingly implied
                // otherwise by sharing one message with it.
                if selectedSystemHasNoClones {
                    Label {
                        Text("\"\(store.selectedSystem?.name ?? "This system")\" has no clone games at all (every machine is its own standalone entry) — Rom merge mode has no real effect here. \"Split\", \"Merged\", and \"Un-merged\" all produce the exact same result, since there's no parent/clone relationship for any of them to act on.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "info.circle.fill").foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            Text("Applies to every MAME system. Changes re-parse a system's DAT the next time it's opened or scanned.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Restore Default Settings") {
                    mergeMode.wrappedValue = MAMEMergeModeSettings.defaultMergeMode
                    biosMergeMode.wrappedValue = MAMEMergeModeSettings.defaultBiosMergeMode
                }
                .help("Resets MAME's Rom/Bios merge mode back to ROMForge's own defaults")
                Spacer()
            }
            Section("Database tree branches") {
                // jensyleo's own request (2026-08-11): let the user pick
                // which branches show at all in the "Database" sidebar tree
                // — the tree grew from 8 categories to 14 the same day
                // (manufacturer/year regroupings, plus four more reusing
                // existing scan-result fields), and not every one of those
                // will be useful to every collection. One `Toggle` per
                // `DatabaseFilter` case, in declaration order, so this list
                // and the tree's own top-to-bottom order always match.
                ForEach(DatabaseFilter.allCases) { filter in
                    Toggle(filter.rawValue, isOn: Binding(
                        get: { DatabaseFilterVisibilitySettings.isEnabled(filter, in: enabledDatabaseFiltersRaw) },
                        set: { enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.setEnabled($0, for: filter, in: enabledDatabaseFiltersRaw) }
                    ))
                }
                HStack {
                    Button("Reset to Defaults") {
                        enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue
                    }
                    // jensyleo's own request (2026-08-12): a quick way to
                    // the two extremes, alongside "Reset to Defaults" —
                    // "Select Minimum" leaves only "All games" on (the one
                    // branch every other unscanned/empty-state code path
                    // already assumes exists, see `minimumEnabled`'s own
                    // doc comment), "Select None" empties the tree
                    // entirely. Neither touches `defaultRawValue` itself,
                    // so "Reset to Defaults" still returns to whatever the
                    // user's own real setup was, not to either extreme.
                    Button("Select Minimum") {
                        enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.minimumRawValue
                    }
                    Button("Select None") {
                        enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.noneRawValue
                    }
                }
            }
            Text("Controls which branches appear under \"Database\" in the library view's sidebar. Unchecking one just hides it — it never deletes anything, and re-checking it (or Reset to Defaults) brings it straight back. MAME-specific for now — a future console system will get its own equivalent section here, not this same list.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear {
            mergeModeAtAppear = mergeModeRaw
            biosMergeModeAtAppear = biosMergeModeRaw
        }
        .alert("MAME Auxiliary Files Purged", isPresented: $didPurgeMAMEFiles) {
            Button("OK") {}
        } message: {
            Text(
                purgedMAMEFileCount > 0
                    ? "Removed \(purgedMAMEFileCount) item\(purgedMAMEFileCount == 1 ? "" : "s") (\"cfg\"/\"diff\"/\"snap\" and anything else MAME had written there)."
                    : "Nothing was there yet — there was nothing to remove."
            )
        }
    }

    private func locateMAME() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the real `mame` executable (e.g. Homebrew's \(MAMELaunchSettings.homebrewDefaultPath))"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        mamePath = url.path
    }
}
