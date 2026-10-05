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
/// setting that isn't really about any *specific* DAT at all. It's still not
/// per-INDIVIDUAL-system today, but it IS per system *kind* now — jensyleo's
/// own request (2026-09-23), start of real NES support: "coloca MAME, NES,
/// SNES, SEGA y demás sistemas y en cada apartado se le puede colocar sus
/// particularidades" (in his own words, one entry per kind, not per exact
/// system name, since a MAME setting still applies uniformly to every MAME
/// system, and nothing NES-specific has come up yet that a SNES system
/// wouldn't also want — see `RomSystem.isMAMEStyle`'s own doc comment for
/// how a system's kind is decided). One entry per DISTINCT kind actually
/// configured — "MAME" always shown (even with zero systems yet, so this
/// screen is never completely empty on first launch), "Consoles" only once
/// at least one non-MAME system exists.
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
    @State private var selectedKind = "MAME"

    private var hasConsoleSystem: Bool {
        store.systems.contains { !$0.isMAMEStyle }
    }

    /// The generic "Consoles" label only earns its keep once it's actually
    /// grouping more than one *distinct* non-MAME system name — jensyleo's
    /// own report (2026-09-29), right after adding NES as the very first
    /// non-MAME system: seeing "CONSOLES" instead of "NES" here reads as if
    /// the app didn't notice which system was actually configured. With
    /// exactly one non-MAME name configured, showing that name directly is
    /// both accurate and clearer; this reverts to "Consoles" on its own,
    /// with no further change needed, the moment a second, differently
    /// named non-MAME system (SNES, say) is added — the tab still shows
    /// (and settings still apply to) every non-MAME system either way, this
    /// only changes its own label.
    private var consoleTabLabel: String {
        let distinctNonMAMENames = Set(store.systems.filter { !$0.isMAMEStyle }.map(\.name))
        return distinctNonMAMENames.count == 1 ? distinctNonMAMENames.first! : "Consoles"
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: Binding(
                get: { Optional(selectedKind) },
                set: { if let newValue = $0 { selectedKind = newValue } }
            )) {
                Text("MAME").tag("MAME")
                if hasConsoleSystem {
                    Text(consoleTabLabel).tag("Consoles")
                }
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            // A console system removed while "Consoles" was selected would
            // otherwise leave this pane showing a row the sidebar no longer
            // lists at all.
            .onChange(of: hasConsoleSystem) { _, stillHasConsole in
                if !stillHasConsole, selectedKind == "Consoles" { selectedKind = "MAME" }
            }

            Divider()

            Group {
                if selectedKind == "Consoles" {
                    ConsoleSettingsForm(store: store)
                } else {
                    MAMEMergeSettingsForm(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private enum SettingsTab: CaseIterable, Hashable {
    case general
    case viewOptions
    case fix
    case systems

    var title: String {
        switch self {
        case .general: return "General"
        case .viewOptions: return "View Options"
        case .fix: return "Fix"
        case .systems: return "Systems"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .viewOptions: return "sidebar.squares.leading"
        case .fix: return "wrench.and.screwdriver"
        case .systems: return "list.bullet"
        }
    }
}

/// The icon-above-label tab switcher classic macOS Preferences windows use
/// — jensyleo's own report (2026-08-27): "quitaste los iconos." A plain
/// SwiftUI `TabView` rendered that way automatically as long as it was the
/// root content of a `Settings { }` scene, which specially cases it into
/// that exact look; hosted in `AppSettingsWindowController`'s own plain
/// `NSWindow` instead (see that type's own doc comment for why), `TabView`
/// falls back to an ordinary macOS top tab strip with no room for an icon
/// at all. This reimplements the look directly — a `Button` per tab, an
/// icon over a caption, a tinted background on whichever is selected — so
/// it no longer depends on which container happens to be hosting it.
private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20))
                        Text(tab.title)
                            .font(.caption)
                    }
                    .frame(width: 74, height: 48)
                    .background(
                        selectedTab == tab ? Color.accentColor.opacity(0.25) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
    }
}

/// Hosts both Settings tabs at a shared window size — `SystemSettingsView`
/// used to set its own `.frame` directly, back when it was the only tab.
struct AppSettingsView: View {
    @Bindable var store: SystemLibraryStore
    /// Closes this window — jensyleo's own request (2026-08-27) that
    /// Settings behave as a genuine app-modal window drove this off
    /// `AppSettingsWindowController`'s own plain `NSWindow` rather than a
    /// SwiftUI `Window`/`WindowGroup` scene, so the `@Environment
    /// (\.dismissWindow)` this used to call (scoped to scene-managed
    /// windows) no longer applies here — this callback (`window.close()`)
    /// is `AppSettingsWindowController`'s own replacement for it.
    var onDone: () -> Void
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(selectedTab: $selectedTab)
            Divider()
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                // jensyleo's own request (2026-08-12): a dedicated tab for
                // layout/visibility toggles — see `ViewOptionsSettingsView`'s
                // own doc comment for why this is separate from "General".
                case .viewOptions:
                    ViewOptionsSettingsView(store: store)
                case .fix:
                    FixSettingsView()
                case .systems:
                    SystemSettingsView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            // jensyleo's own request (2026-07-30): a visible "Done" button
            // to close the window, alongside — not instead of — the
            // native red traffic-light close button
            // `AppSettingsWindowController`'s own `NSWindow` already has.
            HStack {
                Spacer()
                Button("Done") { onDone() }
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
            Button("Close") { onDone() }
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
}

/// The "Maintenance folder" section — its own self-contained view (not
/// duplicated per system kind) so both `MAMEMergeSettingsForm` and
/// `ConsoleSettingsForm` can show and manage the SAME global root. jensyleo's
/// own report (2026-09-29), right after adding NES: the setting lived only
/// under "MAME" (moved there 2026-09-24, for what was at the time the only
/// system kind that existed), so a console-only user had no visible way to
/// see or change it at all — the Maintenance row simply appeared in their
/// own sidebar with nowhere to configure it. `MaintenanceFolderSettings`
/// itself was always documented as covering "every configured system
/// regardless of kind" — this just makes that true from BOTH settings tabs,
/// not only one. Content and behavior are otherwise completely unchanged
/// from before this extraction.
private struct MaintenanceFolderSettingsSection: View {
    var store: SystemLibraryStore
    /// Which systems' own subfolders to actually LIST (with a per-row
    /// "Delete…") in THIS tab — `store.systems.filter(\.isMAMEStyle)` from
    /// `MAMEMergeSettingsForm`, the console-kind equivalent from
    /// `ConsoleSettingsForm`. jensyleo's own report (2026-09-29): viewing
    /// this section from the NES tab listed MAME's own subfolder right
    /// alongside it — technically correct (it IS the same shared root) but
    /// confusing to see from a tab that's otherwise entirely about console
    /// systems. The root itself, and `ensureAllSystemSubfolders()`'s own
    /// backfill, stay genuinely global (`store.systems`, unfiltered) —
    /// only this display list is scoped per tab.
    var relevantSystems: [RomSystem]
    @AppStorage(MaintenanceFolderSettings.storageKey) private var maintenanceFolderPath = ""
    @AppStorage(MaintenanceRescanNoticeSettings.storageKey) private var showMaintenanceRescanNotice = true
    @AppStorage(MaintenanceAutoScanOnSelectSettings.storageKey) private var maintenanceAutoScanOnSelect = true
    /// Holds a candidate root between the folder panel closing and the
    /// user actually confirming its creation (`pickMaintenanceRootLocation()`)
    /// — nothing on disk is touched until confirmed. Also doubles as the
    /// `isPresented` driver for the confirmation dialog itself (non-nil ==
    /// showing).
    @State private var pendingMaintenanceRootCreation: URL?
    /// Non-nil drives the per-system delete confirmation below — the
    /// system whose own Maintenance subfolder is about to be permanently
    /// deleted.
    @State private var pendingMaintenanceSubfolderDeletion: RomSystem?

    var body: some View {
        Section("Maintenance folder") {
            HStack {
                Text(maintenanceFolderPath.isEmpty ? "Not set" : maintenanceFolderPath)
                    .font(.callout)
                    .foregroundStyle(maintenanceFolderPath.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !maintenanceFolderPath.isEmpty {
                    Button("Clear") {
                        maintenanceFolderPath = ""
                        NotificationCenter.default.post(name: MaintenanceFolderSettings.subfoldersDidChange, object: nil)
                    }
                }
                Button("Choose Location…") { pickMaintenanceRootLocation() }
            }
            Text("A read-only donor area — one subfolder per system that opts in below (\"Maintenance/\(store.systems.first?.name ?? "MAME")\", \"Maintenance/NES\", etc.). Drop new or extra ROM dumps into a system's OWN subfolder and \"Find ROMs…\" (the Fix menu) can use them to complete that same system's missing roms — never a different system's, even if two share a rom by coincidence. ROMForge never renames, moves, or deletes anything inside it. Entirely optional at both levels — leave the root unset, or leave a system's own toggle off, if you'd rather keep your own donor folder(s) outside ROMForge for it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !maintenanceFolderPath.isEmpty {
                Text("Off by default for every system, including one you've used this with before — jensyleo's own request (2026-09-29): a newly added system (or one that never opted in) shouldn't get a Maintenance row it never asked for, just because the root above happens to be configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(relevantSystems) { system in
                    HStack {
                        Toggle(system.name, isOn: Binding(
                            get: { system.maintenanceFolderEnabled },
                            set: { newValue in
                                var updated = system
                                updated.maintenanceFolderEnabled = newValue
                                store.update(updated)
                                if newValue { MaintenanceFolderSettings.ensureSubfolderExists(for: updated) }
                                NotificationCenter.default.post(name: MaintenanceFolderSettings.subfoldersDidChange, object: nil)
                            }
                        ))
                        Spacer()
                        if system.maintenanceFolderEnabled {
                            Button("Delete…", role: .destructive) {
                                pendingMaintenanceSubfolderDeletion = system
                            }
                        }
                    }
                }
            }
            Toggle("Notify after scanning the Maintenance folder", isOn: $showMaintenanceRescanNotice)
            Text("Scanning the Maintenance folder only refreshes ITS OWN \"donor available\" coloring — a real ROM folder already scanned earlier this session keeps showing whatever it computed back then until it's rescanned itself. This reminds you to rescan when that might matter.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Read the Maintenance folder the first time it's selected", isOn: $maintenanceAutoScanOnSelect)
            Text("On: clicking the Maintenance row for the first time each session reads its real contents right away, same as before. Off: Maintenance behaves exactly like every other ROM folder — a plain click never touches disk, only an explicit Scan does. Turn this off if the Maintenance root lives on a NAS/drive that isn't always connected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            "Create Maintenance Folder?",
            isPresented: Binding(
                get: { pendingMaintenanceRootCreation != nil },
                set: { if !$0 { pendingMaintenanceRootCreation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Create") {
                if let root = pendingMaintenanceRootCreation {
                    createMaintenanceRoot(at: root)
                }
                pendingMaintenanceRootCreation = nil
            }
            Button("Cancel", role: .cancel) { pendingMaintenanceRootCreation = nil }
        } message: {
            Text("This creates \"\(pendingMaintenanceRootCreation?.path ?? "")\", plus one subfolder inside it for each of your \(store.systems.count) configured system(s).")
        }
        .confirmationDialog(
            "Delete \"\(pendingMaintenanceSubfolderDeletion?.name ?? "")\"'s Maintenance Subfolder?",
            isPresented: Binding(
                get: { pendingMaintenanceSubfolderDeletion != nil },
                set: { if !$0 { pendingMaintenanceSubfolderDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let system = pendingMaintenanceSubfolderDeletion {
                    try? MaintenanceFolderSettings.deleteSubfolder(for: system)
                    NotificationCenter.default.post(name: MaintenanceFolderSettings.subfolderDidDelete, object: nil, userInfo: ["systemID": system.id])
                }
                pendingMaintenanceSubfolderDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingMaintenanceSubfolderDeletion = nil }
        } message: {
            Text("Permanently deletes this system's own Maintenance subfolder and everything inside it — any donor ROMs dropped there for \"Find ROMs…\" are gone. Every OTHER system's own subfolder is untouched. This cannot be undone, and it stays deleted until something genuinely needs it again (running \"Find ROMs…\", or reconfiguring the Maintenance root here) — simply viewing this system again will not bring it back.")
        }
    }

    private func pickMaintenanceRootLocation() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where ROMForge should create (or reuse) its \"Maintenance\" folder"
        guard panel.runModal() == .OK, let parent = panel.urls.first else { return }
        let candidateRoot = parent.appendingPathComponent("Maintenance", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidateRoot.path) {
            maintenanceFolderPath = candidateRoot.path
            ensureAllSystemSubfolders()
        } else {
            pendingMaintenanceRootCreation = candidateRoot
        }
    }

    private func createMaintenanceRoot(at root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        maintenanceFolderPath = root.path
        ensureAllSystemSubfolders()
    }

    /// Backfills a subfolder for every CURRENTLY configured system in one
    /// pass — called right after the root itself is (re)established. A
    /// system added later gets its own the same lazy way
    /// `LibraryDetailView`'s own `.onAppear` already ensures for every
    /// other per-system on-disk location (`ScanCache`, `DATCacheLocation`,
    /// etc.) — no need to revisit this Settings screen for it.
    private func ensureAllSystemSubfolders() {
        for system in store.systems {
            MaintenanceFolderSettings.ensureSubfolderExists(for: system)
        }
        NotificationCenter.default.post(name: MaintenanceFolderSettings.subfoldersDidChange, object: nil)
    }
}

/// Per-system "Fix by name similarity" toggle + threshold slider —
/// jensyleo's own request (2026-09-29), after a real GoodNES-style NES
/// collection turned up many gray/unrecognized files whose actual content
/// is correct but sits under a slightly different name than the DAT
/// declares. Console-only (`ConsoleSettingsForm` is the only caller) —
/// never offered for a MAME system, whose own internal machine names are
/// short and cryptic enough that even a high similarity threshold risks a
/// false match; see `RomSystem.similarNameFixEnabled`'s own doc comment.
private struct SimilarNameFixSettingsSection: View {
    var store: SystemLibraryStore
    var relevantSystems: [RomSystem]
    /// Read live, not cached — jensyleo's own explicit rule (2026-09-29):
    /// this whole feature only ever makes sense alongside "Trust file
    /// names" (`MatchingPreferencesSettings`, General settings), since
    /// suggesting a rename purely from name resemblance is the same kind
    /// of "trust the file name over strict hashing" call that toggle
    /// already represents. `ROMMatcher`/`LibraryViewModel` enforce this
    /// dependency for real (see `LibraryViewModel`'s own `ROMMatcher.match`
    /// call site) — this is purely the UI's own reflection of that same
    /// rule, so a system can't be misconfigured into looking "on" here
    /// while never actually taking effect.
    @AppStorage(MatchingPreferencesSettings.nameOnlyMatchingKey) private var nameOnlyMatchingEnabled = MatchingPreferencesSettings.nameOnlyMatchingDefault

    var body: some View {
        Section("Fix by name similarity") {
            Text("When a File/ROM's own name isn't byte-for-byte what the DAT expects, but it's a close match (a typo, a truncation, a stray character), \"Fix Mismatched Files\"/\"Fix Misnamed ROMs Inside Their Archives…\" can offer to rename it. Off by default — unlike other automatic name-based fixes, this has NO content evidence behind it, purely a resemblance guess, so it stays opt-in per system.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !nameOnlyMatchingEnabled {
                Text("Requires \"Ignore CRC/hash verification for console/computer systems\" (General settings) to be on — a name-resemblance guess only makes sense alongside that same toggle. Every row below is disabled until it's on.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(relevantSystems) { system in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(system.name, isOn: Binding(
                        get: { system.similarNameFixEnabled },
                        set: { newValue in
                            var updated = system
                            updated.similarNameFixEnabled = newValue
                            store.update(updated)
                        }
                    ))
                    .disabled(!nameOnlyMatchingEnabled)
                    if system.similarNameFixEnabled {
                        HStack {
                            Text("Minimum similarity: \(Int((system.similarNameFixThreshold * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { system.similarNameFixThreshold },
                                    set: { newValue in
                                        var updated = system
                                        updated.similarNameFixThreshold = newValue
                                        store.update(updated)
                                    }
                                ),
                                in: 0.50...0.90, step: 0.05
                            )
                        }
                        .disabled(!nameOnlyMatchingEnabled)
                    }
                }
            }
        }
    }
}

/// Per-system opt-in for the region-quality hint badge/Info note — jensyleo's
/// own request (2026-10-01), starting with NES specifically. Console-only,
/// same reasoning as `SimilarNameFixSettingsSection` right above: a MAME
/// system has no concept of regional releases of the same game the way a
/// console DAT does. Off by default, same as every other per-system opt-in
/// here, so an existing system never gains new sidebar/table decoration it
/// never asked for.
private struct RegionQualityHintsSettingsSection: View {
    var store: SystemLibraryStore
    var relevantSystems: [RomSystem]

    var body: some View {
        Section("Region-quality hints") {
            Text("Flags a game ROMForge has a hand-curated note about — e.g. \"the Japanese release has extra content/less censorship than the version you have\". A small, deliberately short seed list (see Help) — most games have no note at all, which is expected, not a sign anything's missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(relevantSystems) { system in
                Toggle(system.name, isOn: Binding(
                    get: { system.regionQualityHintsEnabled },
                    set: { newValue in
                        var updated = system
                        updated.regionQualityHintsEnabled = newValue
                        store.update(updated)
                    }
                ))
            }
        }
    }
}

private struct MAMEMergeSettingsForm: View {
    var store: SystemLibraryStore
    @AppStorage(MAMEMergeModeSettings.mergeModeKey) private var mergeModeRaw = MAMEMergeModeSettings.defaultMergeMode.rawValue
    @AppStorage(MAMEMergeModeSettings.biosMergeModeKey) private var biosMergeModeRaw = MAMEMergeModeSettings.defaultBiosMergeMode.rawValue
    @AppStorage(MAMELaunchSettings.executablePathKey) private var mamePath = ""
    @AppStorage(SamplesFolderSettings.enabledKey) private var samplesEnabled = SamplesFolderSettings.enabledDefault
    @AppStorage(SamplesFolderSettings.pathKey) private var samplesPath = ""
    @AppStorage(BIOSFolderSettings.enabledKey) private var biosEnabled = BIOSFolderSettings.enabledDefault
    @AppStorage(BIOSFolderSettings.pathKey) private var biosPath = ""
    @AppStorage(ComplementaryChipsFolderSettings.enabledKey) private var complementaryChipsEnabled = ComplementaryChipsFolderSettings.enabledDefault
    @AppStorage(ComplementaryChipsFolderSettings.pathKey) private var complementaryChipsPath = ""
    /// Same two-step create pattern as `pendingBIOSFolderCreation` below.
    @State private var pendingComplementaryChipsFolderCreation: URL?
    /// Holds a candidate "<parent>/BIOS" between the folder panel closing
    /// and the user confirming its creation — same two-step pattern as
    /// `GeneralSettingsView.pendingMaintenanceRootCreation`. jensyleo's own
    /// request (2026-09-23): "la opción no me crea la carpeta BIOS como sí
    /// lo hace con la carpeta de mantenimiento. Esto debe ser igual" — an
    /// already-existing "<parent>/BIOS" is adopted immediately, no
    /// confirmation needed; a genuinely new one is only created after this
    /// dialog confirms.
    @State private var pendingBIOSFolderCreation: URL?
    // jensyleo's own request (2026-09-24): "en Panels eso de Dependencias
    // debería estar solo en MAME ¿no crees?" — right after agreeing these
    // are MAME-exclusive concepts shown in a general, not-per-system
    // settings tab (see [[project_romforge_bios_columns_and_devices_review]]
    // in the assistant's own memory for the earlier investigation) — moved
    // here, whole, from `ViewOptionsPanelsTab`. "Details" moved along with
    // it on the same request, even though "Players" is a little more
    // ambiguous (some console DATs also declare player counts) — the
    // user explicitly said "sí" to moving both together.
    @AppStorage(DependencyColumnSettings.showBiosKey) private var showBiosBadge = true
    @AppStorage(DependencyColumnSettings.showCHDKey) private var showCHDBadge = true
    @AppStorage(DependencyColumnSettings.showHardwareKey) private var showHardwareBadge = true
    @AppStorage(DependencyColumnSettings.showSamplesKey) private var showSamplesBadge = true
    @AppStorage(DetailColumnSettings.showDriverStatusKey) private var showDriverStatusBadge = true
    @AppStorage(DetailColumnSettings.showDisplayKey) private var showDisplayBadge = true
    @AppStorage(DetailColumnSettings.showPlayersKey) private var showPlayersBadge = true
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
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey(forMAME: true)) private var enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: true)
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
    /// "Update Database" — jensyleo's own request (2026-09-10): "Poner la
    /// opción de actualizar el DAT... en el caso de MAME se actualiza muy
    /// seguido." Every configured `RomSystem` today is a MAME category-split
    /// of ONE underlying MAME DAT (they all read "DAT: MAME" at the top of
    /// `LibraryDetailView`) — re-picking each one's own `datURL` by hand
    /// every time a newer DAT comes out doesn't scale past a couple of
    /// systems. This one action re-points EVERY configured system at a
    /// single new DAT in one step, placed here (not per-system) for the
    /// same reason merge mode already lives here globally rather than
    /// per-system — jensyleo's own explicit placement instruction:
    /// "Systems -> MAME... así para cada sistema que a futuro le
    /// coloquemos" (a future non-MAME system type would get its own
    /// equivalent section here, not this one).
    ///
    /// jensyleo's own correction (2026-09-10) to the first cut of this,
    /// which only offered a plain file picker under the label "Update DAT
    /// for All Systems…": "eso no es cierto" — a single "load a file"
    /// button doesn't actually cover how a MAME DAT really gets updated in
    /// practice. Two genuinely different sources now offered, mirroring
    /// `AddSystemSheet`'s own two DAT-source buttons exactly:
    /// 1. **Choose DAT File…** — pick any `.dat`/`.xml` already on disk.
    /// 2. **Generate from Installed MAME…** — runs the configured MAME
    ///    executable's own `-listxml` (`MAMEDATGenerator`), same mechanism
    ///    `AddSystemSheet.generateDATFromMAME()` already uses; only offered
    ///    once a MAME executable is actually configured just above.
    /// Holds the resulting file between either source finishing and the
    /// user actually confirming (`confirmationDialog` below) — nothing is
    /// touched until confirmed.
    @State private var pendingDATUpdateURL: URL?
    @State private var isGeneratingDATForUpdate = false
    @State private var generatedDATBytesForUpdate = 0
    @State private var generateDATForUpdateErrorMessage: String?
    @State private var isUpdatingDAT = false
    @State private var didUpdateDAT = false
    @State private var updatedSystemCount = 0

    /// Real gap found live by jensyleo (2026-09-23), start of NES support:
    /// "Update Database" (below) used to re-point EVERY configured
    /// system — MAME and console alike — at a single new DAT, which makes
    /// no sense once a console system exists (an NES No-Intro DAT has
    /// nothing to do with a fresh MAME `-listxml`, and vice versa). Scoped
    /// to MAME-kind systems only, matching this whole form's own scope.
    private var mameSystems: [RomSystem] {
        store.systems.filter(\.isMAMEStyle)
    }

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
            Section("Update Database") {
                HStack {
                    Button("Choose DAT File…") { chooseNewDAT() }
                        .disabled(mameSystems.isEmpty || isUpdatingDAT || isGeneratingDATForUpdate)
                    // Only offered once a real MAME executable is configured
                    // below — nothing to generate from otherwise, same
                    // condition `AddSystemSheet`'s own equivalent button
                    // uses. Moved to the top of this page (2026-09-24,
                    // jensyleo's own request, renamed from "Database" to
                    // "Update Database") — was right after "MAME
                    // executable" before.
                    if MAMELaunchSettings.isInstalled {
                        Button("Generate from Installed MAME…") { generateDATForUpdate() }
                            .disabled(mameSystems.isEmpty || isUpdatingDAT || isGeneratingDATForUpdate)
                    }
                    if isGeneratingDATForUpdate {
                        ProgressView().controlSize(.small)
                        Text("Running mame -listxml… \(generatedDATBytesForUpdate / 1024) KB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if isUpdatingDAT {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                if let generateDATForUpdateErrorMessage {
                    Text(generateDATForUpdateErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("MAME's own database updates often. Either source here re-points EVERY configured MAME system at the resulting DAT in one step, instead of editing each one individually — the last scan result for each affected system is cleared too, so the next Scan re-audits against the new DAT rather than showing stale results from the old one. Console systems are never touched here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if mameSystems.isEmpty {
                    Text("No MAME systems configured yet — add one first (the \"+\" in the sidebar).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            // jensyleo's own report (2026-09-29): moved into its own
            // reusable `MaintenanceFolderSettingsSection` (this file, right
            // above `MAMEMergeSettingsForm`) so `ConsoleSettingsForm` can
            // show and manage this same global setting too — see that
            // struct's own doc comment for why "MAME only" stopped being
            // correct once a console system existed. Position/reasoning
            // for living right after "MAME executable" in THIS form is
            // otherwise unchanged from before the extraction.
            MaintenanceFolderSettingsSection(store: store, relevantSystems: mameSystems)
            // jensyleo's own request (2026-09-23): "quiero que vayas
            // preparando la característica adicional de que se cree una
            // carpeta llamada BIOS donde la idea es que la app tome las
            // BIOS que identifique en las rom folder y las mueva allá" —
            // same enable+path shape as "Samples" right below, for the
            // same reason (a real MAME concept, off by default). The
            // actual move/dedup action itself ("Organize BIOS Files…",
            // toolbar → Fix, never the per-row context menu per that same
            // request's point 3) is `LibraryViewModel.organizeBIOSFiles`.
            // Reordered (2026-09-24, jensyleo's own explicit order) ahead
            // of "Samples" — was the other way around.
            Section("BIOS") {
                Toggle("Enable BIOS folder", isOn: $biosEnabled)
                if biosEnabled {
                    HStack {
                        Text(biosPath.isEmpty ? "No folder chosen" : biosPath)
                            .font(.caption)
                            .foregroundStyle(biosPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseBIOSFolder() }
                        if !biosPath.isEmpty {
                            Button("Clear") { biosPath = "" }
                        }
                    }
                }
                Text("Many arcade boards share a common BIOS machine (neogeo, decocass, etc.) — one that's itself just another entry in the DAT, referenced by every game built on it. \"Organize BIOS Files\" (toolbar → Fix) searches every one of this system's configured ROM folders for each BIOS's own file and moves it in here, removing any further redundant copy only once it's confirmed safe elsewhere. Applies regardless of the Rom/Bios merge mode below. \"Choose…\" picks WHERE — same as the Maintenance folder above — and ROMForge creates (or reuses) a \"BIOS\" folder inside it; nothing is created until you confirm. Once configured, every scan automatically reads this folder too — you never add it as one of your ROM folders yourself, and a BIOS moved here still shows correct, not missing. Tip: to see only the columns that make sense for BIOS browsing, select the BIOS row in \"ROM folder\", arrange the Games table's columns the way you want, then save a column preset named exactly \"BIOS\" (View Options → Panels) — it applies automatically every time you come back to that row, and your previous columns return automatically when you leave it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // jensyleo's own request (2026-09-24), right after a long,
            // sourced investigation (MAME's own official docs,
            // docs.mamedev.org/usingmame/aboutromsets.html: "Device sets
            // contain reusable circuit designs and their associated
            // firmware that appear across multiple, otherwise unrelated
            // arcade boards... categorized as a Device, with the data
            // stored as a Device set" — e.g. NAMCO51.ZIP): "lo mismo que
            // BIOS pero para los demás chips." Same enable+path shape as
            // "BIOS" right above, same reasoning. His own explicit
            // exclusion rule, confirmed against real DAT data and MAME's
            // own driver source: a rom genuinely embedded INSIDE a
            // playable game's own archive (e.g. CPS2's QSound sample
            // roms, `region="qsound"`, declared directly under the game's
            // own `<machine>`) never qualifies — only a rom the DAT models
            // as belonging to the DEVICE's own separate `<machine
            // isdevice="yes">` entry does (e.g. QSound's real firmware,
            // `dl-1425.bin`, confirmed shipping as its own "qsound.zip" in
            // a real MAME romset on archive.org; or Sega's `segadimm`,
            // confirmed as one of the Naomi BIOS-area files distributed
            // alongside naomi.zip/naomigd.zip/jvs13551.zip). See
            // `RebuildPlanner.planOrganizeComplementaryChips`'s own doc
            // comment for exactly why reusing the same mechanics as BIOS
            // (just keyed on `DATGame.isDevice` instead of `isBios`)
            // already enforces this rule with no extra filtering needed.
            Section("Complementary Chips") {
                Toggle("Enable Complementary Chips folder", isOn: $complementaryChipsEnabled)
                if complementaryChipsEnabled {
                    HStack {
                        Text(complementaryChipsPath.isEmpty ? "No folder chosen" : complementaryChipsPath)
                            .font(.caption)
                            .foregroundStyle(complementaryChipsPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseComplementaryChipsFolder() }
                        if !complementaryChipsPath.isEmpty {
                            Button("Clear") { complementaryChipsPath = "" }
                        }
                    }
                }
                Text("Many arcade boards reuse a shared support chip across otherwise-unrelated games — a sound DSP's own firmware, an I/O board's own program, a touchscreen controller — each declared in the DAT as its own separate \"Device\" entry, MAME's own official term (e.g. \"NAMCO51.ZIP\", \"segadimm\", QSound's real \"dl-1425.bin\"). \"Organize Complementary Chips\" (toolbar → Fix) searches every one of this system's configured ROM folders for each such device's own file and moves it in here, removing any further redundant copy only once it's confirmed safe elsewhere — the exact same mechanics as \"BIOS\" above, just for this different DAT category. A chip's rom that's genuinely embedded inside a game's own archive instead (never its own separate device file) is never touched — only a rom the DAT itself models as belonging to a standalone device machine qualifies. \"Choose…\" works the same two-step way as \"BIOS\"/\"Maintenance folder\" above. Once configured, every scan automatically reads this folder too.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // jensyleo's own request (2026-09-11): "que cree su propia
            // carpeta (samples) y que si encuentra los archivos donde sea
            // los cargue en la carpeta de samples... esto debe ser
            // configurable por el usuario desde las opciones de MAME...
            // habrá usuarios que no use juegos con samples entonces no
            // sería necesario activar eso" — off by default (most
            // collections never touch a sample-using game at all), and
            // placed here rather than Settings → General specifically
            // because samples are exclusively a MAME concept (see this
            // file's own doc comment on why the executable path/merge
            // modes live here too). The actual "collect" action itself
            // ("Fix Samples" in the toolbar's "Fix" dropdown, once added
            // to `LibraryDetailView.fixActionsEnabledForTesting`) only
            // ever reads from a system's own configured ROM folders and
            // writes new `<name>.zip` files here — never touches, renames,
            // or deletes anything already in either place.
            Section("Samples") {
                Toggle("Enable samples support", isOn: $samplesEnabled)
                if samplesEnabled {
                    HStack {
                        Text(samplesPath.isEmpty ? "No folder chosen" : samplesPath)
                            .font(.caption)
                            .foregroundStyle(samplesPath.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { chooseSamplesFolder() }
                        if !samplesPath.isEmpty {
                            Button("Clear") { samplesPath = "" }
                        }
                    }
                }
                Text("A handful of early-80s arcade boards (Gorf, Wizard of Wor, Sinistar, Star Wars, Berzerk...) play back original cabinet audio recordings MAME can't synthesize on its own. These are distributed separately from any romset, as one zip per machine named after it (or shared across a family via \"sampleof\") — MAME's own DAT declares only each sample's NAME, never a hash, since there's no dump to verify. \"Fix Samples\" (toolbar → Fix) searches a system's own configured ROM folders for a same-named zip and copies it in here; it never verifies content, only presence. Once configured, every scan automatically reads this folder too — same as BIOS/Complementary Chips, you never add it as one of your ROM folders yourself — but unlike those, its content is deliberately excluded from this system's own audit (a sample has no DAT hash to match against at all, so it would otherwise show as \"Surplus\"); selecting its row in \"ROM folder\" correctly shows an empty Games table.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Rom/Bios Merge Mode") {
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
            // Moved here from View Options → Panels (2026-09-24, jensyleo's
            // own request) — every chip these two sections control (BIOS/
            // CHD/Hardware/Samples/Emulation status/Display/Players) is
            // sourced from a MAME-only DAT concept, so a Console system's
            // settings never had any real effect here to begin with.
            // "Column layouts"/"Dependencies column" (jensyleo's own
            // request, 2026-08-25): folded in from the now-removed
            // "Columns" subtab. Renamed from "Dependencies column" to
            // plain "Dependencies" on 2026-08-27, once it stopped being
            // column-only — see `DependencyColumnSettings`'s own doc
            // comment for why this ended up the ONE toggle set for two
            // different places instead of two separate ones.
            Section("Dependencies (Games table column + Detail panel row)") {
                Toggle("BIOS", isOn: $showBiosBadge)
                Toggle("CHD", isOn: $showCHDBadge)
                Toggle("Hardware", isOn: $showHardwareBadge)
                Toggle("Samples", isOn: $showSamplesBadge)
                Button("Reset to Defaults") {
                    showBiosBadge = true
                    showCHDBadge = true
                    showHardwareBadge = true
                    showSamplesBadge = true
                }
                Text("Which dependency chips show — both in the Games table's own \"Dependencies\" column and in the Detail panel's own \"Dependencies\" row, the exact same chips in both places. Turning one off hides that chip everywhere at once; it never affects scanning, matching, or any other column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // "Details" is deliberately a separate column/section from
            // "Dependencies" above (jensyleo's own decision, 2026-08-28):
            // descriptive machine metadata (MAME's own emulation-quality
            // claim, display orientation, player/coin count) rather than
            // something the game needs in order to run — keeping the two
            // names distinct keeps "Dependencies" meaning exactly what it
            // always has, rather than diluting it with unrelated metadata.
            Section("Details (Games table column + Detail panel row)") {
                Toggle("Emulation status", isOn: $showDriverStatusBadge)
                Toggle("Display", isOn: $showDisplayBadge)
                Toggle("Players", isOn: $showPlayersBadge)
                Button("Reset to Defaults") {
                    showDriverStatusBadge = true
                    showDisplayBadge = true
                    showPlayersBadge = true
                }
                Text("Which detail chips show — both in the Games table's own \"Details\" column and in the Detail panel's own \"Details\" row. Descriptive machine metadata from the DAT (MAME's own emulation status, screen orientation, player/coin count) — never a dependency the game needs to run (see \"Dependencies\" above for that). Turning one off hides that chip everywhere at once; it never affects scanning, matching, or any other column.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        // Confirms BEFORE touching anything — this rewrites every
        // configured system's own `datURL`, not a reversible toggle.
        .confirmationDialog(
            "Update Database?",
            isPresented: Binding(get: { pendingDATUpdateURL != nil }, set: { if !$0 { pendingDATUpdateURL = nil } })
        ) {
            Button("Update \(mameSystems.count) MAME System\(mameSystems.count == 1 ? "" : "s")") {
                if let pendingDATUpdateURL {
                    applyDATUpdate(to: pendingDATUpdateURL)
                }
                pendingDATUpdateURL = nil
            }
            Button("Cancel", role: .cancel) { pendingDATUpdateURL = nil }
        } message: {
            Text(
                "This points every one of your \(mameSystems.count) configured MAME system(s) — \(mameSystems.map(\.name).joined(separator: ", ")) — at \"\(pendingDATUpdateURL?.lastPathComponent ?? "")\" instead of whatever DAT each one currently uses, and clears each one's last scan result (a fresh Scan will be needed). Console systems are never touched here. This can't be undone automatically — pick \"Cancel\" if you meant to update only one specific system instead (not yet possible from here; edit that system directly)."
            )
        }
        .alert("Database Updated", isPresented: $didUpdateDAT) {
            Button("OK") {}
        } message: {
            Text("Re-pointed \(updatedSystemCount) system\(updatedSystemCount == 1 ? "" : "s") at the new DAT and cleared their last scan results. Run Scan Folder/Scan All Folders on each to re-audit against it.")
        }
        // Confirms BEFORE touching disk — this creates a real folder, same
        // reasoning as `GeneralSettingsView`'s own "Create Maintenance
        // Folder?" dialog. jensyleo's own request (2026-09-23): "esto debe
        // ser igual [a Maintenance] y documentado en la app y el help."
        .confirmationDialog(
            "Create BIOS Folder?",
            isPresented: Binding(
                get: { pendingBIOSFolderCreation != nil },
                set: { if !$0 { pendingBIOSFolderCreation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Create") {
                if let root = pendingBIOSFolderCreation {
                    createBIOSFolder(at: root)
                }
                pendingBIOSFolderCreation = nil
            }
            Button("Cancel", role: .cancel) { pendingBIOSFolderCreation = nil }
        } message: {
            Text("This creates \"\(pendingBIOSFolderCreation?.path ?? "")\". Nothing is moved into it until you run \"Organize BIOS Files…\" (toolbar → Fix) yourself.")
        }
        // Same reasoning as "Create BIOS Folder?" right above.
        .confirmationDialog(
            "Create Complementary Chips Folder?",
            isPresented: Binding(
                get: { pendingComplementaryChipsFolderCreation != nil },
                set: { if !$0 { pendingComplementaryChipsFolderCreation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Create") {
                if let root = pendingComplementaryChipsFolderCreation {
                    createComplementaryChipsFolder(at: root)
                }
                pendingComplementaryChipsFolderCreation = nil
            }
            Button("Cancel", role: .cancel) { pendingComplementaryChipsFolderCreation = nil }
        } message: {
            Text("This creates \"\(pendingComplementaryChipsFolderCreation?.path ?? "")\". Nothing is moved into it until you run \"Organize Complementary Chips…\" (toolbar → Fix) yourself.")
        }
    }

    /// Picks the PARENT location the Maintenance root should live under —
    /// same two-step pattern as `chooseBIOSFolder()` below (and originally
    /// `GeneralSettingsView.pickMaintenanceRootLocation()`, before this
    /// whole feature moved here).
    private func chooseNewDAT() {
        let panel = NSOpenPanel()
        // Same "no content-type filter" reasoning as `AddSystemSheet
        // .chooseDAT()` — a `.dat` file's UTI doesn't reliably conform to
        // public.xml even though its content is XML.
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select the new DAT (.dat or .xml — Logiqx/ClrMamePro or MAME -listxml, auto-detected)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copied into ROMForge's own storage right away — see
        // `DATStorageLocation`'s own doc comment for why (jensyleo's own
        // report, 2026-09-29: moving/renaming the original external file
        // afterward used to break every system pointed at it).
        pendingDATUpdateURL = DATStorageLocation.copy(from: url)
    }

    /// Same mechanism as `AddSystemSheet.generateDATFromMAME()` — runs the
    /// configured MAME executable's own `-listxml` via `MAMEDATGenerator`,
    /// then hands the result into the same confirmation flow
    /// `chooseNewDAT()` above uses, rather than applying it immediately.
    private func generateDATForUpdate() {
        isGeneratingDATForUpdate = true
        generateDATForUpdateErrorMessage = nil
        generatedDATBytesForUpdate = 0
        Task {
            do {
                let url = try await MAMEDATGenerator.generate { bytes in
                    Task { @MainActor in generatedDATBytesForUpdate = bytes }
                }
                isGeneratingDATForUpdate = false
                pendingDATUpdateURL = url
            } catch {
                isGeneratingDATForUpdate = false
                generateDATForUpdateErrorMessage = String(describing: error)
            }
        }
    }

    /// Re-points every configured system's `datURL` at `newDATURL`, then
    /// purges each one's last scan result (`SavedViewStatePurger
    /// .purgeScanResults`, the same purge "Purge Database View" already
    /// uses) — a system whose DAT just changed showing its OLD DAT's scan
    /// results until the user happens to rescan would be actively
    /// misleading, not just stale.
    private func applyDATUpdate(to newDATURL: URL) {
        isUpdatingDAT = true
        let systemsToUpdate = mameSystems
        let oldDATURLs = Set(systemsToUpdate.map(\.datURL))
        for system in systemsToUpdate {
            var updated = system
            updated.datURL = newDATURL
            store.update(updated)
        }
        // Cleans up ROMForge's own now-unreferenced internal copy of
        // whatever DAT these systems pointed at before — a no-op for an
        // external path the user still owns, or one still shared by a
        // system not part of this update. See `DATStorageLocation`'s own
        // doc comment.
        for oldURL in oldDATURLs {
            DATStorageLocation.removeIfOrphaned(oldURL, keeping: store.systems)
        }
        Task {
            await SavedViewStatePurger.purgeScanResults(systems: systemsToUpdate)
            isUpdatingDAT = false
            updatedSystemCount = systemsToUpdate.count
            didUpdateDAT = true
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

    private func chooseSamplesFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.message = "Choose (or create) a folder for MAME's own samples zips"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        samplesPath = url.path
    }

    /// Picks the PARENT location the BIOS folder should live under, same
    /// pattern as `GeneralSettingsView.pickMaintenanceRootLocation()` — the
    /// user picks WHERE, ROMForge creates (or reuses) "BIOS" inside it,
    /// rather than requiring an already-existing folder chosen as-is.
    private func chooseBIOSFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where ROMForge should create (or reuse) its \"BIOS\" folder"
        guard panel.runModal() == .OK, let parent = panel.urls.first else { return }
        let candidateRoot = parent.appendingPathComponent("BIOS", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidateRoot.path) {
            biosPath = candidateRoot.path
        } else {
            pendingBIOSFolderCreation = candidateRoot
        }
    }

    private func createBIOSFolder(at root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        biosPath = root.path
    }

    private func chooseComplementaryChipsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose where ROMForge should create (or reuse) its \"Complementary Chips\" folder"
        guard panel.runModal() == .OK, let parent = panel.urls.first else { return }
        let candidateRoot = parent.appendingPathComponent("Complementary Chips", isDirectory: true)
        if FileManager.default.fileExists(atPath: candidateRoot.path) {
            complementaryChipsPath = candidateRoot.path
        } else {
            pendingComplementaryChipsFolderCreation = candidateRoot
        }
    }

    private func createComplementaryChipsFolder(at root: URL) {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        complementaryChipsPath = root.path
    }
}

/// Settings → Systems → "Consoles" — the counterpart to
/// `MAMEMergeSettingsForm` for every non-MAME system (No-Intro/Redump/TOSEC
/// and similar plain Logiqx DATs, e.g. NES). Deliberately short: none of
/// "MAME executable", "Rom/Bios merge mode", or "Samples" mean anything for
/// a console DAT (see `RomSystem.isMAMEStyle`'s own doc comment) — the only
/// thing a console system genuinely needs configured here is which
/// "Database" tree branches show, same as MAME's own section, just with the
/// MAME-only branches (`DatabaseFilter.isMAMESpecific`) left off the list
/// entirely rather than shown-but-permanently-empty. jensyleo's own request
/// (2026-09-23), start of real NES support: "hay que hacer ajustes en la GUI
/// de tal manera que lo de MAME no se mezcle con los demás sistemas."
private struct ConsoleSettingsForm: View {
    var store: SystemLibraryStore
    @AppStorage(DatabaseFilterVisibilitySettings.storageKey(forMAME: false))
    private var enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: false)

    /// Same "Update Database" idea as `MAMEMergeSettingsForm`'s own, scoped
    /// to console systems instead — jensyleo's own request (2026-09-23):
    /// "Update database no aparece en la sección de MAME. Esto ahora debe
    /// quedar en cada sección de consolas." No "Generate from Installed
    /// X…" here at all (unlike MAME's own section) — see
    /// `SystemCategoryKind`'s own doc comment for why: there's no known
    /// generic way to generate a console DAT locally, only to point at one
    /// already downloaded.
    @State private var pendingDATUpdateURL: URL?
    @State private var isUpdatingDAT = false
    @State private var didUpdateDAT = false
    @State private var updatedSystemCount = 0

    /// "Play in <emulator>" — jensyleo's own request (2026-09-29): unlike
    /// MAME (one canonical emulator), a console system's emulator "no es
    /// único," so this is a real, configurable choice rather than
    /// hardcoded. See `ConsoleEmulatorLauncher.swift`'s own doc comment
    /// for why Nestopia/FCEUX are the two listed (both genuinely
    /// installable via Homebrew right now) and why OpenEmu — probably the
    /// more widely-known option — isn't.
    @AppStorage(ConsoleEmulatorSettings.customExecutablePathKey) private var customEmulatorPath = ""
    /// The one console system whose DAT is being replaced — every console
    /// has its own DAT, so the update is never applied to the others.
    @State private var datTargetSystemID: UUID?

    private var datTargetSystem: RomSystem? {
        consoleSystems.first { $0.id == datTargetSystemID }
    }

    private var consoleFilters: [DatabaseFilter] {
        DatabaseFilter.allCases.filter { !$0.isMAMESpecific }
    }

    private var consoleSystems: [RomSystem] {
        store.systems.filter { !$0.isMAMEStyle }
    }

    var body: some View {
        Form {
            Text("Applies to every console-style system (any system whose Platform isn't \"MAME\" — NES, SNES, SEGA Genesis, and similar). DAT and emulator are set per system.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Systems") {
                if consoleSystems.isEmpty {
                    Text("No console systems configured yet — add one first (the \"+\" in the sidebar, Platform set to something other than \"MAME\").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(consoleSystems) { system in
                    consoleSystemRow(system)
                }
                if isUpdatingDAT { ProgressView().controlSize(.small) }
                Text("Each console system has its own DAT and its own emulator. Replacing a DAT clears only that system's last scan result, so the next Scan re-audits against the new DAT. MAME systems are never touched here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // jensyleo's own report (2026-09-29): the Maintenance row
            // appeared in the NES sidebar with nowhere in THIS tab to see
            // or change it — the setting lived only under "MAME" (see
            // `MaintenanceFolderSettingsSection`'s own doc comment). It's
            // the same global root/state either tab edits, not a separate
            // one for consoles.
            MaintenanceFolderSettingsSection(store: store, relevantSystems: consoleSystems)
            SimilarNameFixSettingsSection(store: store, relevantSystems: consoleSystems)
            RegionQualityHintsSettingsSection(store: store, relevantSystems: consoleSystems)
            Section("Database tree branches") {
                ForEach(consoleFilters) { filter in
                    Toggle(filter.title(forMAME: false), isOn: Binding(
                        get: { DatabaseFilterVisibilitySettings.isEnabled(filter, in: enabledDatabaseFiltersRaw) },
                        set: { enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.setEnabled($0, for: filter, in: enabledDatabaseFiltersRaw) }
                    ))
                }
                HStack {
                    Button("Reset to Defaults") {
                        enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.defaultRawValue(forMAME: false)
                    }
                    Button("Select None") {
                        enabledDatabaseFiltersRaw = DatabaseFilterVisibilitySettings.noneRawValue
                    }
                }
            }
            Text("Controls which branches appear under \"Database\" in the library view's sidebar, for console systems only — a MAME system's own list (Settings → Systems → \"MAME\") is entirely separate, so hiding/showing one never affects the other. Unchecking one just hides it — it never deletes anything.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Update Database?",
            isPresented: Binding(get: { pendingDATUpdateURL != nil }, set: { if !$0 { pendingDATUpdateURL = nil } })
        ) {
            Button("Update \(datTargetSystem?.name ?? "System")") {
                if let pendingDATUpdateURL, let target = datTargetSystem {
                    applyDATUpdate(to: pendingDATUpdateURL, system: target)
                }
                pendingDATUpdateURL = nil
            }
            Button("Cancel", role: .cancel) { pendingDATUpdateURL = nil }
        } message: {
            Text("This points \(datTargetSystem?.name ?? "this system") at \"\(pendingDATUpdateURL?.lastPathComponent ?? "")\" instead of its current DAT and clears its last scan result (a fresh Scan will be needed). Other systems are not touched. This can't be undone automatically.")
        }
        .alert("Database Updated", isPresented: $didUpdateDAT) {
            Button("OK") {}
        } message: {
            Text("Re-pointed \(updatedSystemCount) system\(updatedSystemCount == 1 ? "" : "s") at the new DAT and cleared their last scan results. Run Scan Folder/Scan All Folders on each to re-audit against it.")
        }
    }

    private func chooseNewDAT(for system: RomSystem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select the new DAT for \(system.name) (.dat or .xml)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Copied into ROMForge's own storage right away — see
        // `DATStorageLocation`'s own doc comment for why.
        datTargetSystemID = system.id
        pendingDATUpdateURL = DATStorageLocation.copy(from: url)
    }

    /// One row per console system: its DAT and the emulator it plays with.
    @ViewBuilder
    private func consoleSystemRow(_ system: RomSystem) -> some View {
        let options = KnownConsoleEmulator.options(forCategory: system.category)
        let chosen = ConsoleEmulatorSettings.emulator(for: system)
        VStack(alignment: .leading, spacing: 6) {
            Text(system.name).font(.headline)
            HStack {
                Text("DAT: \(system.datURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose DAT…") { chooseNewDAT(for: system) }
                    .disabled(isUpdatingDAT)
            }
            if options.isEmpty {
                Text("Catalog only — there is no emulator to play this platform on macOS, so Play is not offered.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !options.isEmpty {
            Picker("Play games with", selection: Binding(
                get: { chosen.rawValue },
                set: { newValue in
                    var updated = system
                    updated.emulatorRaw = newValue
                    store.update(updated)
                }
            )) {
                ForEach(options) { emulator in
                    Text(emulator.displayName).tag(emulator.rawValue)
                }
            }
            .pickerStyle(.menu)
            if chosen == .custom {
                HStack {
                    Text(customEmulatorPath.isEmpty ? "Not configured" : customEmulatorPath)
                        .font(.caption)
                        .foregroundStyle(customEmulatorPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Locate…") { locateCustomEmulator() }
                    if !customEmulatorPath.isEmpty {
                        Button("Clear") { customEmulatorPath = "" }
                    }
                }
                Text("Pick either a plain command-line emulator executable or a GUI `.app`. This custom emulator is shared by every system set to \"Custom…\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let installed = ConsoleEmulatorSettings.isInstalled(chosen)
            HStack {
                Image(systemName: installed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(installed ? .green : .orange)
                Text(installed
                    ? "\(chosen.displayName) is installed."
                    : chosen.installCommand.map { "\(chosen.displayName) isn't installed yet — run `\($0)` in Terminal." } ?? "No custom emulator configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }
        }
        .padding(.vertical, 4)
    }

    /// "Custom…" emulator choice — same two-button "Locate…"/"Clear"
    /// pattern as MAME's own executable field below, except this accepts
    /// EITHER a plain CLI binary or a `.app` bundle (`canChooseDirectories
    /// = false` still lets an `.app` package through, since macOS treats
    /// it as a file, not a directory, from an `NSOpenPanel`'s own
    /// perspective).
    private func locateCustomEmulator() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the emulator to use for console/computer systems — a command-line executable or a .app"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customEmulatorPath = url.path
    }

    private func applyDATUpdate(to newDATURL: URL, system: RomSystem) {
        isUpdatingDAT = true
        let oldDATURL = system.datURL
        var updated = system
        updated.datURL = newDATURL
        store.update(updated)
        // See `MAMEMergeSettingsForm.applyDATUpdate(to:)`'s own identical
        // cleanup comment.
        DATStorageLocation.removeIfOrphaned(oldDATURL, keeping: store.systems)
        Task {
            await SavedViewStatePurger.purgeScanResults(systems: [updated])
            isUpdatingDAT = false
            updatedSystemCount = 1
            didUpdateDAT = true
        }
    }
}

/// Where MAME's own sample zips live — Settings → Systems → MAME → "Samples"
/// (jensyleo's own explicit placement, 2026-09-11: MAME-exclusive, so it
/// belongs here, not Settings → General). See `RebuildPlanner
/// .planCollectSamples`'s own doc comment for why "Fix Samples" can only
/// ever check PRESENCE, never content — samples have no hash in the DAT.
enum SamplesFolderSettings {
    static let enabledKey = "ROMForge.samples.enabled"
    static let enabledDefault = false
    static let pathKey = "ROMForge.samples.path"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// `nil` when disabled, or enabled with no folder chosen yet.
    static var folderURL: URL? {
        guard isEnabled, let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// True when `url` sits inside the Samples folder — jensyleo's own
    /// request (2026-09-24): "lo mismo que BIOS" (auto-included in the
    /// scan, no manual ROM-folder entry needed), but with an explicit
    /// exclusion he confirmed: unlike BIOS/Complementary Chips (which are
    /// real DAT machines `ROMMatcher` genuinely matches, hash and all), a
    /// sample has no DAT-declared hash at all — the DAT only ever declares
    /// its NAME. Folding Samples folder content into the normal
    /// match/audit pipeline the way BIOS's is would show every sample zip
    /// as "Surplus"/unrecognized in the Games table, since nothing there
    /// would ever claim it. Used to filter Samples folder content OUT of
    /// the scanned-files pool entirely, right where `MaintenanceFolderSettings
    /// .isUnderMaintenanceFolder` already does the same for the
    /// Maintenance folder — same reasoning, same mechanism. `false` when
    /// no Samples folder is configured at all.
    static func isUnderSamplesFolder(_ url: URL) -> Bool {
        guard let root = folderURL else { return false }
        let rootPath = root.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

/// Where "Organize BIOS Files…" (toolbar → Fix) moves every BIOS it finds
/// — Settings → Systems → MAME → "BIOS". jensyleo's own request
/// (2026-09-23): "1: la definimos desde la app, debe tener la opción de
/// crearla" — same enable+path pattern as `SamplesFolderSettings` right
/// above, and placed alongside it for the same reason (a real MAME/DAT
/// concept, not a general app setting). See
/// `RebuildPlanner.planOrganizeBIOSFiles`'s own doc comment for exactly
/// what the action itself does with this folder.
enum BIOSFolderSettings {
    static let enabledKey = "ROMForge.bios.enabled"
    static let enabledDefault = false
    static let pathKey = "ROMForge.bios.path"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// `nil` when disabled, or enabled with no folder chosen yet.
    static var folderURL: URL? {
        guard isEnabled, let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Where "Organize Complementary Chips…" (toolbar → Fix) moves every
/// shared, non-BIOS device it finds — Settings → Systems → MAME →
/// "Complementary Chips". jensyleo's own request (2026-09-24), after a
/// sourced investigation confirming MAME's own official "Device set"
/// concept: "lo mismo que BIOS pero para los demás chips" — same
/// enable+path pattern as `BIOSFolderSettings` right above, for the exact
/// same reason. See `RebuildPlanner.planOrganizeComplementaryChips`'s own
/// doc comment for exactly what the action itself does with this folder.
enum ComplementaryChipsFolderSettings {
    static let enabledKey = "ROMForge.complementaryChips.enabled"
    static let enabledDefault = false
    static let pathKey = "ROMForge.complementaryChips.path"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// `nil` when disabled, or enabled with no folder chosen yet.
    static var folderURL: URL? {
        guard isEnabled, let path = UserDefaults.standard.string(forKey: pathKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
