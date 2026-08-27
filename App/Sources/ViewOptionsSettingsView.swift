// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import ROMForgeCore
import SwiftUI

/// Which of `LibraryDetailView`'s six main panels ("Database" tree, "ROM
/// folder" tree, Games, Roms, Detail, Log) actually show — jensyleo's own
/// request (2026-08-12): "crea la opción de desaparecer los paneles". All
/// six default to visible (today's existing behavior, unchanged) — this is
/// purely opt-in decluttering, not a new default layout. A plain (non-View)
/// reader, same pattern as `HashAlgorithmSettings`/`MAMEMergeModeSettings`:
/// `LibraryDetailView` reads these directly via `@AppStorage` under the
/// same keys, so this view and the actual layout can never disagree about
/// which panels are showing.
///
/// "Database" and "ROM folder" were one combined toggle at first (same
/// day) — split into two independent ones on jensyleo's own follow-up
/// request, since `databaseList` is really two separate trees (mutually
/// exclusive selection, already their own draggable split within the
/// sidebar) rather than one indivisible panel.
enum PanelVisibilitySettings {
    static let showDatabaseTreeKey = "ROMForge.view.showDatabaseTree"
    static let showRomFolderTreeKey = "ROMForge.view.showRomFolderTree"
    static let showGamesPanelKey = "ROMForge.view.showGamesPanel"
    static let showRomsPanelKey = "ROMForge.view.showRomsPanel"
    static let showDetailPanelKey = "ROMForge.view.showDetailPanel"
    static let showLogPanelKey = "ROMForge.view.showLogPanel"
}

/// "Show only 1G1R" (`LibraryDetailView`'s Games-table filter) — moved from
/// a toolbar action button to this `@AppStorage`-backed toggle (jensyleo's
/// own request, 2026-08-24), alongside its own move into Settings → View
/// Options → "1G1R". Same one-key-enum convention as
/// `PanelVisibilitySettings`/`DependencyColumnSettings` above, kept in its
/// own tiny enum (rather than inlined as a raw string literal both here and
/// in `LibraryDetailView`) so the two can never disagree on the key name.
enum OneGameOneROMSettings {
    static let showOnlyKey = "ROMForge.view.show1G1ROnly"
}

/// Which of `DependencyBadge.Kind` cases show — jensyleo's own request
/// (2026-08-20), alongside naming real BIOS/hardware names in each chip's
/// own label: some collections care about BIOS/CHD dependencies but find
/// the "Hardware" chip (routinely half a dozen device names) too busy for
/// their taste, or vice versa. All four default to visible (today's
/// existing behavior, unchanged) — same `@AppStorage`-backed,
/// plain-enum-of-keys pattern as `PanelVisibilitySettings` above.
///
/// Originally named for the Games table's own "Dependencies" column, its
/// only home at the time. Since 2026-08-27 it also governs the Detail
/// panel's own "Dependencies" row (`LibraryDetailView
/// .dependenciesDetailRow`) — deliberately the SAME toggle set, not a
/// second one: jensyleo's own correction after the Detail panel first
/// shipped with its own separate CHD/Samples/etc. toggles, which just
/// duplicated this one under different names. Read directly by
/// `LibraryDetailView` under these same keys, both places, so column,
/// Detail panel, and this settings view can never disagree about what's
/// showing.
enum DependencyColumnSettings {
    static let showBiosKey = "ROMForge.view.showBiosBadge"
    static let showCHDKey = "ROMForge.view.showCHDBadge"
    static let showHardwareKey = "ROMForge.view.showHardwareBadge"
    static let showSamplesKey = "ROMForge.view.showSamplesBadge"
}

/// Which fields show in the Detail panel's game section (jensyleo's own
/// "rezago de fase 1" request, 2026-08-27) — same "hides a field, never
/// discards anything" configurability as `DependencyColumnSettings` above,
/// applied to `LibraryDetailView.gameDetailSection`. All default to
/// visible (today's existing behavior, unchanged). Read directly by
/// `LibraryDetailView` under these same keys, same one-source-of-truth
/// pattern as `PanelVisibilitySettings`.
///
/// jensyleo's own correction (2026-08-27, second pass): the first version
/// of this had its own small, hand-picked field list (Internal name/Clone
/// of/Year/Manufacturer/BIOS set/Status) that didn't actually match the
/// Games table's own real, already-customizable column list (screenshotted
/// directly from that table's own right-click menu: Game name/File name/
/// Expected file name/Size/1G1R/Info/Clone of/Required BIOS/CHD/Samples/
/// BIOS/Year/Manufacturer/Device refs/Clone of (internal name)/Family/
/// Dependencies). This now has one key per REAL column that list offers
/// (skipping only "Game name", this panel's own always-shown headline, and
/// "Dependencies", still governed by the shared `DependencyColumnSettings`
/// toggle set — see `LibraryDetailView.dependenciesDetailRow`), named and
/// ordered to match that menu exactly, so a field can never appear here
/// under a name/order that doesn't correspond to anything a user has
/// actually seen as a column.
enum DetailPanelGameFieldSettings {
    static let showFileNameKey = "ROMForge.view.detail.game.showFileName"
    static let showExpectedFileNameKey = "ROMForge.view.detail.game.showExpectedFileName"
    static let showSizeKey = "ROMForge.view.detail.game.showSize"
    static let showOneGameOneROMKey = "ROMForge.view.detail.game.showOneGameOneROM"
    static let showInfoKey = "ROMForge.view.detail.game.showInfo"
    static let showCloneOfKey = "ROMForge.view.detail.game.showCloneOf"
    static let showRequiredBiosKey = "ROMForge.view.detail.game.showRequiredBios"
    static let showCHDKey = "ROMForge.view.detail.game.showCHD"
    static let showSamplesKey = "ROMForge.view.detail.game.showSamples"
    static let showBiosKey = "ROMForge.view.detail.game.showBios"
    static let showYearKey = "ROMForge.view.detail.game.showYear"
    static let showManufacturerKey = "ROMForge.view.detail.game.showManufacturer"
    static let showDeviceRefsKey = "ROMForge.view.detail.game.showDeviceRefs"
    static let showCloneOfInternalNameKey = "ROMForge.view.detail.game.showCloneOfInternalName"
    static let showFamilyKey = "ROMForge.view.detail.game.showFamily"
}

/// Same idea as `DetailPanelGameFieldSettings`, for
/// `LibraryDetailView.romDetailSection`'s own fields — jensyleo's own
/// correction (2026-08-27): this first shipped with its own field set
/// (Game/Clone of/DAT/Path) that didn't correspond to anything, when the
/// actual request was "exactamente los mismos campos que se pueden
/// configurar en las columnas" — the Roms table's own real, already
/// customizable columns (`romsList`'s own `customizationID`s: fileName,
/// info, size, crc, sha1, folder, md5, dumpStatus — `romName`/`status`
/// excluded, since those are this panel's own always-shown header/icon,
/// not optional fields). Field names and content below match those
/// columns exactly (e.g. "Folder" shows the containing folder's name,
/// same as the column, not the full path this used to show).
enum DetailPanelRomFieldSettings {
    static let showFileNameKey = "ROMForge.view.detail.rom.showFileName"
    static let showInfoKey = "ROMForge.view.detail.rom.showInfo"
    static let showSizeKey = "ROMForge.view.detail.rom.showSize"
    static let showCRCKey = "ROMForge.view.detail.rom.showCRC"
    static let showSHA1Key = "ROMForge.view.detail.rom.showSHA1"
    static let showFolderKey = "ROMForge.view.detail.rom.showFolder"
    static let showMD5Key = "ROMForge.view.detail.rom.showMD5"
    static let showDumpStatusKey = "ROMForge.view.detail.rom.showDumpStatus"
    static let showTypeKey = "ROMForge.view.detail.rom.showType"
}

/// New Settings tab, alongside "General" and "Systems" — jensyleo's own
/// request (2026-08-12), a dedicated home for layout/visibility toggles
/// distinct from `GeneralSettingsView`'s scanning/hashing/database-branch
/// preferences. Named "View Options" rather than folded into "General":
/// this is specifically about what's *shown on screen*, not how a scan
/// itself behaves.
private enum ViewOptionsSubtab: Hashable {
    case general
    case panels
    case oneGameOneROM
}

/// New Settings tab, alongside "General" and "Systems" — jensyleo's own
/// request (2026-08-12), a dedicated home for layout/visibility toggles
/// distinct from `GeneralSettingsView`'s scanning/hashing/database-branch
/// preferences. Named "View Options" rather than folded into "General":
/// this is specifically about what's *shown on screen*, not how a scan
/// itself behaves.
///
/// Reorganized into its own nested subtabs (jensyleo's own request,
/// 2026-08-24) once a single flat `Form` grew to eight sections mixing
/// panel visibility, column layout, and 1G1R together — "General" (the
/// purge/reset actions that don't belong to any one of the others),
/// "Panels", and "1G1R".
///
/// A separate "Columns" subtab (panel/preset button + the Dependencies
/// chip toggles) existed briefly (2026-08-24 to 2026-08-25) — folded back
/// into "Panels" on jensyleo's own follow-up request once renaming the
/// preset button to "Manage Panel Presets…" made "Panels" the more
/// logical home for it, which then left "Columns" holding only the four
/// Dependencies toggles — too thin to justify its own subtab. Both are
/// "what shows in the UI" concerns either way, so they share one tab now.
///
/// A first version (2026-08-24) used a second, nested `TabView` here —
/// exactly the same explicit `selection` + `.tag()` pattern that works fine
/// for `AppSettingsView`'s own *outer* tab bar. Confirmed live (2026-08-25)
/// that it doesn't work one level down: clicking "Panels"/"Columns"/"1G1R"
/// highlighted the clicked tab but never actually swapped the content —
/// `AppSettingsView`'s own already-selected "View Options" tab kept showing
/// whatever subtab was selected when it first appeared. A `TabView` nested
/// directly inside another `TabView` is a known bad combination on macOS —
/// the inner one doesn't reliably get its own hit-testing/selection once
/// it's not the outermost tab-bar-owning view — so this now drives the same
/// four cases with a plain segmented `Picker` + `switch`, which never
/// involves a second `TabView` at all.
struct ViewOptionsSettingsView: View {
    var store: SystemLibraryStore
    @State private var selectedSubtab: ViewOptionsSubtab = .general

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedSubtab) {
                Text("General").tag(ViewOptionsSubtab.general)
                Text("Panels").tag(ViewOptionsSubtab.panels)
                Text("1G1R").tag(ViewOptionsSubtab.oneGameOneROM)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            switch selectedSubtab {
            case .general:
                ViewOptionsGeneralTab(store: store)
            case .panels:
                ViewOptionsPanelsTab()
            case .oneGameOneROM:
                ViewOptions1G1RTab()
            }
        }
    }
}

/// "General" subtab — the purge/reset actions that aren't really about
/// panels, columns, or 1G1R specifically, just leftover layout/scan-data
/// housekeeping. Exactly the three sections ("Saved layout", "Saved scan
/// results", "ROM folder order") that used to sit at the top level here
/// before the 2026-08-24 subtab split, unchanged otherwise.
private struct ViewOptionsGeneralTab: View {
    var store: SystemLibraryStore
    @State private var didPurgeDatabase = false
    @State private var purgedDatabaseCount = 0
    @State private var didResetFolderOrder = false
    @State private var resetFolderOrderCount = 0

    var body: some View {
        Form {
            // "Saved layout" moved to the "Panels" subtab (jensyleo's own
            // request, 2026-08-25) — it resets remembered split sizes and
            // selections, which is a panel-layout concern like everything
            // else there, not really "general" housekeeping the way
            // "Saved scan results"/"ROM folder order" below are.
            Section("Saved scan results") {
                // jensyleo's own follow-up request (2026-08-12): "que purge
                // la vista de la base de datos para volver a escanear los
                // folders después. Esto para evitar errores de apreciación
                // de parte del usuario" — a distinct, separate action from
                // "Purge Saved Views" (above): clears every system's own
                // last scan result, forcing a fresh "Scan Folder"/"Scan All
                // Folders" before anything shows again, specifically so a
                // genuinely stale audit report can never be sitting behind
                // whatever layout/selection happens to be showing.
                Button("Purge Database View", role: .destructive) {
                    Task {
                        purgedDatabaseCount = await SavedViewStatePurger.purgeScanResults(systems: store.systems)
                        didPurgeDatabase = true
                    }
                }
                Text("Clears every configured system's last scan result (both its cached file hashes and its saved audit report) — every system reads as \"not scanned yet\" afterward, and needs a fresh Scan to show anything in \"Database\"/\"ROM folder\" again. Never touches any remembered layout/selection — see \"Purge Saved Views\" above for that.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("ROM folder order") {
                // jensyleo's own request (2026-08-12), right after adding
                // ⌘-drag reordering to "ROM folder": a way back to the
                // alphabetical starting order for every system at once,
                // undoing any manual dragging — the per-system, one-folder-
                // at-a-time "Add Folder…" insertion already keeps new
                // folders alphabetical, but has no way to fix up folders
                // that have since been dragged out of order by hand.
                Button("Reset ROM Folder View") {
                    resetFolderOrderCount = RomFolderOrderResetter.resetToAlphabetical(store: store)
                    didResetFolderOrder = true
                }
                Text("Puts every configured system's \"ROM folder\" list back into alphabetical order, undoing any manual ⌘-drag reordering. Doesn't add, remove, or rescan any folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Database View Purged", isPresented: $didPurgeDatabase) {
            Button("OK") {}
        } message: {
            Text(
                purgedDatabaseCount > 0
                    ? "Cleared the last scan result for \(purgedDatabaseCount) system\(purgedDatabaseCount == 1 ? "" : "s"). Each one now needs a fresh scan before \"Database\"/\"ROM folder\" show anything again."
                    : "No system had a saved scan result — there was nothing to clear."
            )
        }
        .alert("ROM Folder Order Reset", isPresented: $didResetFolderOrder) {
            Button("OK") {}
        } message: {
            Text(
                resetFolderOrderCount > 0
                    ? "Re-sorted \"ROM folder\" alphabetically for \(resetFolderOrderCount) system\(resetFolderOrderCount == 1 ? "" : "s")."
                    : "Every system's \"ROM folder\" list was already alphabetical — nothing to change."
            )
        }
    }
}

/// "Panels" subtab — visibility and content of `LibraryDetailView`'s six
/// main panels (Database, ROM folder, Games, Roms, Detail, Log). Every
/// section here is named after one or more of those same six, with its
/// on-screen location spelled out, per jensyleo's own 2026-08-27
/// correction — see this view's own leading `Text` for the full map.
private struct ViewOptionsPanelsTab: View {
    @AppStorage(PanelVisibilitySettings.showDatabaseTreeKey) private var showDatabaseTree = true
    @AppStorage(PanelVisibilitySettings.showRomFolderTreeKey) private var showRomFolderTree = true
    @AppStorage(PanelVisibilitySettings.showGamesPanelKey) private var showGamesPanel = true
    @AppStorage(PanelVisibilitySettings.showRomsPanelKey) private var showRomsPanel = true
    @AppStorage(PanelVisibilitySettings.showDetailPanelKey) private var showDetailPanel = true
    @AppStorage(PanelVisibilitySettings.showLogPanelKey) private var showLogPanel = true
    @AppStorage(DependencyColumnSettings.showBiosKey) private var showBiosBadge = true
    @AppStorage(DependencyColumnSettings.showCHDKey) private var showCHDBadge = true
    @AppStorage(DependencyColumnSettings.showHardwareKey) private var showHardwareBadge = true
    @AppStorage(DependencyColumnSettings.showSamplesKey) private var showSamplesBadge = true
    @AppStorage(DetailPanelGameFieldSettings.showFileNameKey) private var showDetailGameFileName = true
    @AppStorage(DetailPanelGameFieldSettings.showExpectedFileNameKey) private var showDetailExpectedFileName = true
    @AppStorage(DetailPanelGameFieldSettings.showSizeKey) private var showDetailGameSize = true
    @AppStorage(DetailPanelGameFieldSettings.showOneGameOneROMKey) private var showDetailOneGameOneROM = true
    @AppStorage(DetailPanelGameFieldSettings.showInfoKey) private var showDetailInfo = true
    @AppStorage(DetailPanelGameFieldSettings.showCloneOfKey) private var showDetailGameCloneOf = true
    @AppStorage(DetailPanelGameFieldSettings.showRequiredBiosKey) private var showDetailRequiredBios = true
    @AppStorage(DetailPanelGameFieldSettings.showCHDKey) private var showDetailCHD = true
    @AppStorage(DetailPanelGameFieldSettings.showSamplesKey) private var showDetailSamples = true
    @AppStorage(DetailPanelGameFieldSettings.showBiosKey) private var showDetailBios = true
    @AppStorage(DetailPanelGameFieldSettings.showYearKey) private var showDetailYear = true
    @AppStorage(DetailPanelGameFieldSettings.showManufacturerKey) private var showDetailManufacturer = true
    @AppStorage(DetailPanelGameFieldSettings.showDeviceRefsKey) private var showDetailDeviceRefs = true
    @AppStorage(DetailPanelGameFieldSettings.showCloneOfInternalNameKey) private var showDetailCloneOfInternalName = true
    @AppStorage(DetailPanelGameFieldSettings.showFamilyKey) private var showDetailFamily = true
    @AppStorage(DetailPanelRomFieldSettings.showFileNameKey) private var showDetailRomFileName = true
    @AppStorage(DetailPanelRomFieldSettings.showInfoKey) private var showDetailRomInfo = true
    @AppStorage(DetailPanelRomFieldSettings.showSizeKey) private var showDetailRomSize = true
    @AppStorage(DetailPanelRomFieldSettings.showCRCKey) private var showDetailRomCRC = true
    @AppStorage(DetailPanelRomFieldSettings.showSHA1Key) private var showDetailRomSHA1 = true
    @AppStorage(DetailPanelRomFieldSettings.showFolderKey) private var showDetailRomFolder = true
    @AppStorage(DetailPanelRomFieldSettings.showMD5Key) private var showDetailRomMD5 = true
    @AppStorage(DetailPanelRomFieldSettings.showDumpStatusKey) private var showDetailRomDumpStatus = true
    @AppStorage(DetailPanelRomFieldSettings.showTypeKey) private var showDetailRomType = true
    @State private var didPurgeViews = false
    @State private var purgedViewCount = 0

    var body: some View {
        Form {
            // jensyleo's own correction (2026-08-27): with several
            // sections all naming their own subset of panels/fields, it
            // became unclear which on-screen area each one actually
            // touched ("se volvió confuso... no se está entendiendo
            // nada"). This upfront map, plus a location in every panel
            // name below (both here and in every following section
            // header), is the fix — every name a toggle/section uses is
            // now also the name printed at that exact spot on screen.
            Text("ROMForge's library window has six panels: **Database**/**ROM folder** (left sidebar tree, whichever is selected), **Games** and **Roms** (the two tables across the top), and **Detail** and **Log** (the two areas across the bottom). Sections below are named after these same six.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Panel visibility") {
                Toggle("Database (left sidebar)", isOn: $showDatabaseTree)
                Toggle("ROM folder (left sidebar)", isOn: $showRomFolderTree)
                Toggle("Games (top-left table)", isOn: $showGamesPanel)
                Toggle("Roms (top-right table)", isOn: $showRomsPanel)
                Toggle("Detail (bottom-left)", isOn: $showDetailPanel)
                Toggle("Log (bottom-right)", isOn: $showLogPanel)
                Button("Reset to Defaults") {
                    showDatabaseTree = true
                    showRomFolderTree = true
                    showGamesPanel = true
                    showRomsPanel = true
                    showDetailPanel = true
                    showLogPanel = true
                }
                Text("Hides a whole panel, freeing its space for the ones left showing — never discards anything, and re-checking a box (or Reset to Defaults) brings it straight back where it was.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // jensyleo's own request (2026-08-13): "esas View Options
            // llévalas a la sección MAME de System, tiene más sentido" —
            // the "Database tree branches" toggles that briefly lived here
            // moved to `SystemSettingsView`'s own "MAME" section instead
            // (Settings → Systems → MAME) once it became clear every
            // `DatabaseFilter` branch is a MAME-specific concept, and
            // that's where every *other* MAME-specific setting (the
            // executable path, both merge modes) already lives — not
            // here, which is about panel layout in general. The storage
            // enum (`DatabaseFilterVisibilitySettings`, below in this
            // file) stayed regardless of where its own UI lives.
            Section("Games/Roms table column layouts") {
                Button("Manage Column Presets…") {
                    NotificationCenter.default.post(name: .romForgeShowColumnPresetsSheet, object: nil)
                }
                Text("Save or switch between named column layouts for both tables (Games and Roms) — opens the same sheet the toolbar's own \"Column Presets…\" button used to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // "Column layouts"/"Dependencies column" (jensyleo's own
            // request, 2026-08-25): folded in from the now-removed
            // "Columns" subtab — see this file's own `ViewOptionsSubtab`
            // doc comment for why. Renamed from "Dependencies column" to
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
            // "Otro rezago de fase 1" (jensyleo's own request, 2026-08-27,
            // second pass): "la idea es que tenga exactamente los mismos
            // campos que se pueden configurar en las columnas" — matched
            // against a screenshot of the Games table's own real
            // right-click column menu this time, not approximated by hand.
            // One toggle per real column that list offers (skipping "Game
            // name", this panel's own always-shown headline), named and
            // ordered to match that menu exactly. "Dependencies" is
            // deliberately NOT a toggle here — see "Dependencies" above,
            // which already covers it (and, within it, CHD/Samples/
            // Required BIOS/Device refs as chips) for this panel too;
            // those same four also get their OWN plain-text toggle below,
            // matching the Games table itself offering both a standalone
            // column AND the summarized "Dependencies" chip for each.
            Section("Detail panel (bottom-left) — game fields") {
                Toggle("File name", isOn: $showDetailGameFileName)
                Toggle("Expected file name", isOn: $showDetailExpectedFileName)
                Toggle("Size", isOn: $showDetailGameSize)
                Toggle("1G1R", isOn: $showDetailOneGameOneROM)
                Toggle("Info", isOn: $showDetailInfo)
                Toggle("Clone of", isOn: $showDetailGameCloneOf)
                Toggle("Required BIOS", isOn: $showDetailRequiredBios)
                Toggle("CHD", isOn: $showDetailCHD)
                Toggle("Samples", isOn: $showDetailSamples)
                Toggle("BIOS", isOn: $showDetailBios)
                Toggle("Year", isOn: $showDetailYear)
                Toggle("Manufacturer", isOn: $showDetailManufacturer)
                Toggle("Device refs", isOn: $showDetailDeviceRefs)
                Toggle("Clone of (internal name)", isOn: $showDetailCloneOfInternalName)
                Toggle("Family", isOn: $showDetailFamily)
                Button("Reset to Defaults") {
                    showDetailGameFileName = true
                    showDetailExpectedFileName = true
                    showDetailGameSize = true
                    showDetailOneGameOneROM = true
                    showDetailInfo = true
                    showDetailGameCloneOf = true
                    showDetailRequiredBios = true
                    showDetailCHD = true
                    showDetailSamples = true
                    showDetailBios = true
                    showDetailYear = true
                    showDetailManufacturer = true
                    showDetailDeviceRefs = true
                    showDetailCloneOfInternalName = true
                    showDetailFamily = true
                }
                Text("\"Dependencies\" shows here too, as its own row of chips — see the \"Dependencies\" section above to hide any of those.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Detail panel (bottom-left) — rom fields") {
                Toggle("File name", isOn: $showDetailRomFileName)
                Toggle("Info", isOn: $showDetailRomInfo)
                Toggle("Size", isOn: $showDetailRomSize)
                Toggle("CRC", isOn: $showDetailRomCRC)
                Toggle("SHA-1", isOn: $showDetailRomSHA1)
                Toggle("Folder", isOn: $showDetailRomFolder)
                Toggle("MD5", isOn: $showDetailRomMD5)
                Toggle("Dump status", isOn: $showDetailRomDumpStatus)
                Toggle("Type", isOn: $showDetailRomType)
                Button("Reset to Defaults") {
                    showDetailRomFileName = true
                    showDetailRomInfo = true
                    showDetailRomSize = true
                    showDetailRomCRC = true
                    showDetailRomSHA1 = true
                    showDetailRomFolder = true
                    showDetailRomMD5 = true
                    showDetailRomDumpStatus = true
                    showDetailRomType = true
                }
                Text("The exact same fields as the Roms table's own columns (\"Rom name\" and the status icon always show here, same as this panel's own header — not optional, same as the Games table's own \"Game name\" column isn't either). A field with no value is still skipped automatically — these toggles only control fields that DO have a value.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // "Saved layout" moved here from "General" (jensyleo's own
            // request, 2026-08-25) — it resets remembered split sizes and
            // selections, a panel-layout concern like everything else on
            // this subtab. See `ViewOptionsGeneralTab`'s own doc comment.
            Section("Saved layout") {
                Button("Purge Saved Views") {
                    purgedViewCount = SavedViewStatePurger.purgeViews()
                    didPurgeViews = true
                }
                Text("Clears every remembered split-panel size and every system's remembered last-selected \"Database\"/\"ROM folder\" view — takes effect the next time you switch to (or reopen) that system, or on next launch, not instantly in a window already open. Falls back then to this system's first ROM folder (or first enabled \"Database\" branch) and each split's original proportions, exactly like a fresh install. Never touches any scan result — see \"Purge Database View\" (General) for that. Panel visibility and the \"Database\" branch visibility settings are untouched too — use their own \"Reset to Defaults\" for those.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .alert("Saved Views Purged", isPresented: $didPurgeViews) {
            Button("OK") {}
        } message: {
            Text(
                purgedViewCount > 0
                    ? "Removed \(purgedViewCount) saved item\(purgedViewCount == 1 ? "" : "s") (remembered selections and/or split-panel sizes). Switch systems (or reopen this one) to see the fallback view."
                    : "Nothing was saved yet — there was nothing to remove."
            )
        }
    }
}

/// "1G1R" subtab — region priority (unchanged from before the split) plus
/// "Show Only 1G1R" itself (jensyleo's own request, 2026-08-24: moved here
/// from a toolbar action button, now a persisted `@AppStorage` toggle — see
/// `show1G1ROnly`'s own doc comment in `LibraryDetailView` for why it's no
/// longer ephemeral `@State` once it lives in Settings instead of the
/// toolbar).
private struct ViewOptions1G1RTab: View {
    @AppStorage(OneGameOneROMSettings.showOnlyKey) private var show1G1ROnly = false
    @AppStorage(RegionOrderSettings.storageKey) private var regionOrderRaw = RegionOrderSettings.defaultRawValue

    var body: some View {
        Form {
            Section("1G1R filter") {
                Toggle("Show Only 1G1R", isOn: $show1G1ROnly)
                Text("Hides every parent/clone family's non-preferred region variant in the Games table, per the region priority below — a variant with no recognized region is never hidden. Presentation-only: never touches a file, never re-scans.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Region priority") {
                // Plain up/down reordering rather than a draggable `List` —
                // this app has no existing draggable-list-in-a-Form
                // pattern to follow (the "ROM folder" ⌘-drag reordering
                // lives in a `List` inside `LibraryDetailView`'s own
                // sidebar, a different context entirely), and a short,
                // fixed-length list of region names doesn't need anything
                // more elaborate than "move this one up/down one slot".
                ForEach(Array(RegionOrderSettings.order(from: regionOrderRaw).enumerated()), id: \.element) { index, region in
                    HStack {
                        Text("\(index + 1). \(region)")
                        Spacer()
                        Button {
                            regionOrderRaw = RegionOrderSettings.rawValue(
                                for: RegionOrderSettings.moved(RegionOrderSettings.order(from: regionOrderRaw), fromOffsets: [index], toOffset: index - 1)
                            )
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .disabled(index == 0)
                        Button {
                            regionOrderRaw = RegionOrderSettings.rawValue(
                                for: RegionOrderSettings.moved(RegionOrderSettings.order(from: regionOrderRaw), fromOffsets: [index], toOffset: index + 2)
                            )
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(index == RegionOrderSettings.order(from: regionOrderRaw).count - 1)
                    }
                }
                Button("Reset to Defaults") {
                    regionOrderRaw = RegionOrderSettings.defaultRawValue
                }
                Text("Which region wins when \"Show Only 1G1R\" above has to pick one variant per parent/clone family — earlier in this list beats later. A variant whose own description names none of these regions never competes at all: it stays visible either way, and never takes the family's own star.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Which `DatabaseFilter` branches show in the "Database" sidebar tree —
/// jensyleo's own request (2026-08-11): as the tree grew past the original 8
/// categories, let the user turn individual ones off rather than always
/// showing every branch that's ever been added. Stored as a comma-joined
/// list of `rawValue`s (see `enabledDatabaseFiltersRaw`'s own doc comment
/// for why, not a `Set` directly) under one `@AppStorage` key shared by
/// this settings view and `LibraryDetailView.databaseCategoryListContent`.
enum DatabaseFilterVisibilitySettings {
    static let storageKey = "ROMForge.database.enabledFilters"

    /// jensyleo's own instruction (2026-08-12): "revisa como deje la vista
    /// de la base de datos y deja esa por defecto" — captured directly from
    /// this app's own live `UserDefaults` at the moment of that request
    /// (`defaults read com.jensyleo.romforge ROMForge.database.enabledFilters`),
    /// not the original 10-branch set the toggle itself first shipped with
    /// a day earlier (2026-08-11). Whatever the user actually settles on
    /// through the toggles below is what "Reset to Defaults" now restores.
    static let defaultEnabled: Set<DatabaseFilter> = [
        .allGames, .verifiedGames, .originals, .clones, .gamesWithCHD, .gamesRequiringBIOS,
    ]

    /// jensyleo's own instruction (2026-08-12), same live-`UserDefaults`
    /// capture technique as `defaultEnabled` above, taken moments later
    /// once the user had pared the tree down further through the toggles:
    /// "revisa lo que deje de configuración de base de datos y deja esos
    /// como Minimum". Genuinely their own chosen minimal set, not this
    /// file's own earlier guess of "just `.allGames` alone".
    static let minimumEnabled: Set<DatabaseFilter> = [.allGames, .verifiedGames, .originals]

    static var defaultRawValue: String { rawValue(for: defaultEnabled) }
    static var minimumRawValue: String { rawValue(for: minimumEnabled) }
    static var noneRawValue: String { "" }

    private static func rawValue(for filters: Set<DatabaseFilter>) -> String {
        DatabaseFilter.allCases.filter(filters.contains).map(\.rawValue).joined(separator: ",")
    }

    static func isEnabled(_ filter: DatabaseFilter, in rawValue: String) -> Bool {
        rawValue.split(separator: ",").map(String.init).contains(filter.rawValue)
    }

    static func setEnabled(_ isEnabled: Bool, for filter: DatabaseFilter, in rawValue: String) -> String {
        var enabled = Set(rawValue.split(separator: ",").map(String.init))
        if isEnabled { enabled.insert(filter.rawValue) } else { enabled.remove(filter.rawValue) }
        // Keeps declaration order (not `Set`'s own arbitrary order) so the
        // stored string — and anything that ever re-derives a `[DatabaseFilter]`
        // from it — stays stable and predictable across launches.
        return DatabaseFilter.allCases.map(\.rawValue).filter(enabled.contains).joined(separator: ",")
    }

    /// The actual, ordered list `databaseCategoryListContent` iterates —
    /// `LibraryDetailView`'s own read side of this setting.
    static func enabledFilters(from rawValue: String) -> [DatabaseFilter] {
        let enabled = Set(rawValue.split(separator: ",").map(String.init))
        return DatabaseFilter.allCases.filter { enabled.contains($0.rawValue) }
    }
}

/// Region priority for "Show only 1G1R" (`LibraryDetailView`'s toolbar
/// toggle) — jensyleo's own spec (2026-08-19): user-editable, defaulting to
/// `RegionCatalog.defaultOrder` (World > USA > Europe > Japan > Asia, then
/// everything else this recognizes). Same comma-joined-`rawValue`-under-one-
/// key convention as `DatabaseFilterVisibilitySettings` just above, and for
/// the same reason: an ordered list, not a `Set`, and order itself is the
/// whole point here (unlike that one, where only membership matters).
enum RegionOrderSettings {
    static let storageKey = "ROMForge.oneGameOneROM.regionOrder"
    static var defaultRawValue: String { rawValue(for: RegionCatalog.defaultOrder) }

    static func rawValue(for order: [String]) -> String {
        order.joined(separator: ",")
    }

    /// Never returns empty — a blank/corrupt stored value (first launch
    /// before this key existed, or a hand-edited `UserDefaults`) falls back
    /// to `RegionCatalog.defaultOrder` rather than leaving 1G1R with no
    /// regions to rank at all.
    static func order(from rawValue: String) -> [String] {
        let split = rawValue.split(separator: ",").map(String.init)
        return split.isEmpty ? RegionCatalog.defaultOrder : split
    }

    static func moved(_ order: [String], fromOffsets source: IndexSet, toOffset destination: Int) -> [String] {
        var result = order
        result.move(fromOffsets: source, toOffset: destination)
        return result
    }
}

/// "Reset ROM Folder View" — jensyleo's own request (2026-08-12), the
/// undo counterpart to ⌘-drag reordering (`LibraryDetailView.romFolderRow(for:)`):
/// puts every configured system's `romFolderURLs` back into alphabetical
/// order, in place, at whatever position each system already occupies in
/// `store.systems` — a pure reordering, never adding/removing a folder or
/// touching any scan result.
enum RomFolderOrderResetter {
    @MainActor
    @discardableResult
    static func resetToAlphabetical(store: SystemLibraryStore) -> Int {
        var changedCount = 0
        for system in store.systems {
            let sorted = system.romFolderURLs.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            guard sorted != system.romFolderURLs else { continue }
            var updated = system
            updated.romFolderURLs = sorted
            store.update(updated)
            changedCount += 1
        }
        return changedCount
    }
}

/// Two independent, deliberately-separate purges — jensyleo's own request
/// (2026-08-12): "un botón que permita purgar las vistas", then, once a
/// first version combined this with clearing scan data too, the explicit
/// correction "Purge Saved Views dejalo para resetar las vistas y [crea]
/// purge database view para clear[ar] la vista de lo que se ve en los rom
/// folders y haya que volver a escanear" — each button now touches only
/// its own half, never the other's.
enum SavedViewStatePurger {
    private static let lastSelectionPrefix = "ROMForge.system."
    private static let lastSelectionSuffix = ".lastSelection"
    private static let splitFractionsPrefix = "ROMForge.splitFractions."

    /// Posted once `purgeScanResults(systems:)` finishes clearing the *on-disk*
    /// scan data — jensyleo's own report (2026-08-12): clearing
    /// `AuditReportDatabase`/`ScanCache` alone didn't stop an already-open
    /// `LibraryDetailView` from keeping its existing in-memory
    /// `LibraryViewModel.auditReport`, so "Database"/"ROM folder" kept
    /// showing the old (already-deleted-from-disk) content regardless —
    /// "esto no debería pasar". Every `LibraryDetailView` observes this and
    /// calls `LibraryViewModel.clearScanResults()` on its own `viewModel` in
    /// response, so a window that's open *right now* reflects the purge
    /// immediately rather than only on its next fresh open.
    static let scanResultsPurgedNotification = Notification.Name("ROMForge.scanResultsPurged")

    /// "Purge Saved Views" — layout/selection only, never touches any scan
    /// result. Writes a *dynamic* number of keys (one
    /// `ROMForge.system.<id>.lastSelection` per system, one
    /// `ROMForge.splitFractions.<autosaveName>` per split), so there's no
    /// fixed list of keys to remove the way `ViewOptionsSettingsView`'s own
    /// panel-visibility "Reset to Defaults" can just reassign a handful of
    /// `@AppStorage` properties — this instead scans every stored key by
    /// prefix. Returns how many keys were actually removed, purely for the
    /// confirmation alert (see `ViewOptionsSettingsView`'s own doc comment
    /// on why that alert exists at all).
    @discardableResult
    static func purgeViews() -> Int {
        let defaults = UserDefaults.standard
        let matchingKeys = defaults.dictionaryRepresentation().keys.filter { key in
            (key.hasPrefix(lastSelectionPrefix) && key.hasSuffix(lastSelectionSuffix)) || key.hasPrefix(splitFractionsPrefix)
        }
        for key in matchingKeys {
            defaults.removeObject(forKey: key)
        }
        return matchingKeys.count
    }

    /// "Purge Database View" — every configured system's own last scan
    /// result only, never touches any remembered layout/selection. Needs
    /// the actual list of configured systems (not just a `UserDefaults`
    /// key pattern) since each one's scan result lives in its own
    /// `ScanCache` file plus a row in the shared `AuditReportDatabase`,
    /// both keyed by `RomSystem` rather than by any predictable string.
    /// Returns how many systems actually had a database row cleared,
    /// purely for the confirmation alert.
    /// A full `AuditReportDatabase` wipe (one SQLite `DELETE` of every row
    /// per system) — real slowness found live (2026-08-13, same pass that
    /// found `LibraryViewModel.removeFolder`/`loadPersistedReport`'s own
    /// cases): a real MAME system's report can run to hundreds of
    /// thousands of rows, and this used to run synchronously on
    /// `@MainActor` directly from the "Purge Database View" button's
    /// action closure, looped over every configured system. Now `async`,
    /// with the actual delete work in a detached task — the caller (this
    /// button's own action, a plain `Task { }`, main-actor by default)
    /// only awaits the result.
    @discardableResult
    static func purgeScanResults(systems: [RomSystem]) async -> Int {
        let clearedSystemCount = await Task.detached(priority: .userInitiated) {
            var clearedSystemCount = 0
            // Best-effort per system — one system's database row failing to
            // delete (a locked file, a corrupt row) shouldn't stop the rest
            // from being purged, and a missing `ScanCache` file is already the
            // correct end state, not an error.
            let auditDatabase = try? AuditDatabaseLocation.open()
            for system in systems {
                ScanCacheLocation.remove(for: system)
                guard let auditDatabase else { continue }
                if (try? auditDatabase.removeSystem(system.id.uuidString)) != nil {
                    clearedSystemCount += 1
                }
            }
            return clearedSystemCount
        }.value
        // Posted after the `await` returns, so it runs on the caller's own
        // actor rather than the detached task above — `LibraryDetailView`'s
        // `.onReceive` for this notification calls `viewModel
        // .clearScanResults()`, which mutates `@MainActor` state; posting
        // from a background thread would deliver it there too.
        NotificationCenter.default.post(name: scanResultsPurgedNotification, object: nil)
        return clearedSystemCount
    }
}
