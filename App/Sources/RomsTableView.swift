import AppKit
import ROMForgeCore
import SwiftUI

/// The Roms panel (right pane, RomCenter's own file panel) — extracted
/// verbatim out of `LibraryDetailView` on 2026-09-14, same pure-extraction
/// perf refactor as `GameTreeTableView`, for the same reason: this used to
/// be a plain computed `var` (`romsList`) directly on `LibraryDetailView`,
/// so ANY `@State` change anywhere else in that giant struct — including
/// `gameColumnCustomization` firing continuously while a user drags a
/// column in the OTHER table — forced this whole panel to re-evaluate too.
/// As its own `View` struct, it only re-renders when one of the params/
/// bindings below actually changes.
///
/// No behavior change intended: every cell-rendering/action function this
/// used from `LibraryDetailView` stays defined there and is handed down as
/// a plain closure.
struct RomsTableView: View {
    // MARK: - Data
    let selectedGameNode: GameNode?
    let selectedRomRows: [RomRow]
    let viewModel: LibraryViewModel

    // MARK: - Selection / column customization
    @Binding var selection: Set<String>
    // Owned locally, loaded straight from `UserDefaults` as this `@State`
    // property's own default value — same fix, same reasoning, as
    // `GameTreeTableView.columnCustomization`'s own doc comment (real
    // perf bug found live by jensyleo, 2026-09-22: a `@Binding` into
    // `LibraryDetailView`'s own `@State` invalidated that whole ~4400-line
    // view on every column-resize frame, regardless of this already being
    // its own extracted `View` struct).
    @State private var columnCustomization = RomsTableView.loadStoredColumnCustomization()
    @Binding var columnCustomizationOverride: TableColumnCustomization<RomRow>?
    let persistColumnCustomization: (TableColumnCustomization<RomRow>) -> Void

    // Must match `LibraryDetailView.romColumnCustomizationKey` exactly —
    // duplicated here (rather than shared) since that constant is
    // `private` to that giant file and this is the only other reader.
    /// See `GameTreeTableView.defaultColumnCustomizationJSON`'s own doc
    /// comment — same request, same capture technique, same guarantee
    /// (pure column widths/order/visibility, no personal data).
    private static let defaultColumnCustomizationJSON = """
    {"perColumnState":[{"base":{"explicit":{"_0":"fileName"}}},{"visibility":{"hidden":{}},"currentWidth":100},{"base":{"explicit":{"_0":"crc"}}},{"visibility":{"hidden":{}},"currentWidth":217},{"base":{"explicit":{"_0":"info"}}},{"visibility":{"automatic":{}},"currentWidth":266},{"base":{"explicit":{"_0":"romName"}}},{"visibility":{"visible":{}},"currentWidth":128},{"base":{"explicit":{"_0":"size"}}},{"currentWidth":158.5,"visibility":{"hidden":{}}},{"base":{"explicit":{"_0":"sha1"}}},{"visibility":{"hidden":{}},"currentWidth":123}]}
    """

    private static func loadStoredColumnCustomization() -> TableColumnCustomization<RomRow> {
        if let data = UserDefaults.standard.data(forKey: "ROMForge.romTableColumnCustomization"),
           let decoded = try? JSONDecoder().decode(TableColumnCustomization<RomRow>.self, from: data) {
            return decoded
        }
        guard let fallbackData = defaultColumnCustomizationJSON.data(using: .utf8),
              let fallback = try? JSONDecoder().decode(TableColumnCustomization<RomRow>.self, from: fallbackData)
        else { return TableColumnCustomization<RomRow>() }
        return fallback
    }

    // MARK: - Cell content (all previously `private func`s on LibraryDetailView)
    let romCell: (AnyView, AuditEntry) -> AnyView
    let romStatusIcon: (AuditEntry) -> AnyView
    let romNameText: (AuditEntry) -> String
    let infoText: (AuditEntry) -> String
    let zipCommentHelpText: (AuditEntry) -> String
    let sizeText: (AuditEntry) -> String
    let dumpStatusText: (AuditEntry) -> String
    let entryKindText: (AuditEntry) -> String

    // MARK: - Context menu actions (all previously `private func`s on LibraryDetailView)
    let startContextMenuRenameRomsInArchive: ([URL], Set<String>) -> Void
    // jensyleo's own report (2026-09-19): this panel's own context menu only
    // ever offered "Fix This Misnamed ROM…" plus the plain file actions
    // (`romEntryActionsMenuItems`) — every OTHER per-rom Fix action the
    // Games table's own context menu already has ("Remove Redundant
    // ROM(s)…", "Find ROMs…") was simply never wired
    // here, a real gap rather than a deliberate exclusion. Unlike "Fix
    // Mismatched File" (deliberately excluded — see this file's own
    // `.contextMenu` doc comment below), both of these genuinely operate on
    // ROM content, not on a File as a whole, so they belong here.
    let startContextMenuRemoveRedundantRoms: ([URL]) -> Void
    let startRepairFromMaintenanceFolder: ([URL]) -> Void
    let romEntryActionsMenuItems: ([RomRow]) -> AnyView
    // jensyleo's own report (2026-09-15), macOS 27.0: confirmed live (via
    // screen recording) that per-`Table` `.focusable()`/`.focused()` can't
    // reliably move real AppKit focus between this Table and the Games
    // one — arrow-key routing for both now lives in one shared event
    // monitor in `LibraryDetailView` (`activeResultsPane`'s own doc
    // comment there); this just reports "I'm the one the user last
    // clicked into".
    let onFocusRequested: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedGameNode.map { "\($0.name) (\($0.entries.count) files)" } ?? "Select a game")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Table(selectedRomRows, selection: $selection, columnCustomization: $columnCustomization) {
                TableColumn("") { row in
                    romCell(romStatusIcon(row.entry), row.entry)
                }
                .width(20)
                .customizationID("status")
                .disabledCustomizationBehavior(.all)
                TableColumn("File name") { row in
                    // jensyleo's own report (2026-09-10): "revisa el ZIP tú
                    // mismo y verás" — `path?.lastPathComponent` is the
                    // CONTAINER's own filename ("awbios.zip") for a
                    // zip-entry rom, the SAME string for every rom inside
                    // it, never the entry's own actual name. This column
                    // is what a user reads to see "what's really in
                    // there" — `actualEntryName` (`AuditEntry`'s own doc
                    // comment) IS that, for both a loose file (where it
                    // equals `path?.lastPathComponent` anyway) and a zip
                    // entry (where it's genuinely different). Falls back
                    // to `path?.lastPathComponent` only for an entry that
                    // predates this field (an on-disk cache/database row
                    // saved before it existed — nil until the next scan).
                    // `nil` overall whenever nothing was actually found on
                    // disk for this rom (status `.missing`) — genuinely
                    // blank, not a rendering glitch, but a bare empty cell
                    // reads as broken, so it gets an explicit placeholder
                    // instead. The expected name still lives in "Rom name".
                    if let fileName = row.entry.actualEntryName ?? row.entry.path?.lastPathComponent {
                        romCell(AnyView(Text(fileName)), row.entry)
                    } else {
                        romCell(AnyView(Text("— not found —").foregroundStyle(.secondary)), row.entry)
                    }
                }
                .customizationID("fileName")
                TableColumn("Rom name") { row in
                    romCell(AnyView(Text(romNameText(row.entry))), row.entry)
                }
                .customizationID("romName")
                TableColumn("Info") { row in
                    romCell(AnyView(Text(infoText(row.entry)).help(zipCommentHelpText(row.entry))), row.entry)
                }
                .customizationID("info")
                TableColumn("Size") { row in
                    romCell(AnyView(Text(sizeText(row.entry))), row.entry)
                }
                .customizationID("size")
                // Used to be one combined "Crc/SHA-1" column that only ever
                // displayed the CRC value — real bug found by jensyleo
                // (2026-07-28): labeled as showing both, but SHA-1 was
                // never actually reachable at all, reading as if SHA-1
                // hashing wasn't really happening even when enabled in
                // Settings. Split into two real columns, matching the
                // existing MD5 column's own pattern exactly.
                TableColumn("CRC") { row in
                    romCell(AnyView(Text(row.entry.actualCRC ?? row.entry.expectedCRC ?? "")), row.entry)
                }
                .customizationID("crc")
                TableColumn("SHA-1") { row in
                    romCell(AnyView(Text(row.entry.actualSHA1 ?? row.entry.expectedSHA1 ?? "")), row.entry)
                }
                .customizationID("sha1")
                // `Table`'s column builder tops out at 10 columns per
                // block (same limit `gameTreeTable` already hit) — adding
                // the new "SHA-1" column above pushed this table over it,
                // so the trailing, already-hidden-by-default columns move
                // into their own group to fit.
                Group {
                    TableColumn("Folder") { (row: RomRow) in
                        romCell(AnyView(Text(row.entry.path?.deletingLastPathComponent().lastPathComponent ?? "")), row.entry)
                    }
                    .customizationID("folder")
                    .defaultVisibility(.hidden)
                    TableColumn("MD5") { (row: RomRow) in
                        romCell(AnyView(Text(row.entry.actualMD5 ?? row.entry.expectedMD5 ?? "")), row.entry)
                    }
                    .customizationID("md5")
                    .defaultVisibility(.hidden)
                    TableColumn("Dump status") { (row: RomRow) in
                        romCell(AnyView(Text(dumpStatusText(row.entry))), row.entry)
                    }
                    .customizationID("dumpStatus")
                    .defaultVisibility(.hidden)
                    TableColumn("Type") { (row: RomRow) in
                        romCell(AnyView(Text(entryKindText(row.entry))), row.entry)
                    }
                    .customizationID("entryKind")
                    .defaultVisibility(.hidden)
                }
            }
            .onChange(of: columnCustomization) { persistColumnCustomization(columnCustomization) }
            .onChange(of: columnCustomizationOverride) { _, newValue in
                guard let newValue else { return }
                columnCustomization = newValue
            }
            // jensyleo's own report (2026-09-16): "estoy en Contra 3 y
            // subo al siguiente (Nintendo Super System BIOS) y la celda se
            // mueve a la derecha" — a `Table`'s own horizontal scroll
            // position isn't reset just because its content/selection
            // changed underneath it; switching to a game whose Roms have
            // fewer columns' worth of content left the viewport wherever a
            // WIDER previous game had scrolled it. This view is already
            // torn down and recreated on every genuine game change (see
            // `romsList`'s own `.id(...)` in `LibraryDetailView`) —
            // `.defaultScrollAnchor` re-applies to that fresh instance,
            // pinning it back to the leading column instead of inheriting
            // wherever the previous instance happened to be scrolled.
            .defaultScrollAnchor(.topLeading)
            // jensyleo's own request (2026-09-10): "todo esto que estamos
            // haciendo debe aplicar también al panel de más allá a la
            // derecha. Renombrar roms de auna o varias, también se debe
            // poder" — the ROM-level Fix action the Games table's own
            // context menu already has, mirrored here, entry-level and
            // restricted to ONLY the specific rows selected (`entryKeys`,
            // below), not every fixable entry sharing their same container
            // — jensyleo's own follow-up report (2026-09-10): "selecciono 2
            // roms y me renombra las 4". See `LibraryViewModel
            // .renameRomsInArchive`'s own `entryKeys` doc comment.
            //
            // Deliberately NO "Fix Mismatched File" here — jensyleo's own
            // explicit instruction (2026-09-10), after seeing it appear for
            // a selection of already-"Ok" rows sharing a container that
            // genuinely did have an unrelated File-level issue elsewhere in
            // it: "no debe aparecer nunca en el menú de más a la derecha,
            // porque esta situación ahí no existe y puede prestarse para
            // fallas en la app". This panel shows ROM ENTRIES, not Files —
            // a File-level rename acts on the whole container regardless of
            // which entries happen to be selected, which reads as
            // confusing/risky from a per-ROM list. The Games table (one row
            // per File) is the only place that action is offered.
            // `.labelStyle(.titleAndIcon)` forced via `Group` — macOS/SwiftUI's
            // `.contextMenu` otherwise silently drops each `Button`'s `Label`
            // icon (title-only), unlike menu-bar `.commands`. Confirmed via a
            // real screenshot (jensyleo, 2026-09-26) that icons were genuinely
            // missing here despite every `Label(_:systemImage:)` already
            // being correct in code.
            .contextMenu(forSelectionType: String.self) { selection in
              Group {
                let selectedRows = selection.compactMap { selectedID in selectedRomRows.first(where: { $0.id == selectedID }) }
                let containerURLs = Array(Set(selectedRows.compactMap(\.entry.path)))
                let entryKeys = Set(selectedRows.compactMap { row -> String? in
                    guard let containerURL = row.entry.path, let currentName = row.entry.actualEntryName else { return nil }
                    return LibraryViewModel.entryScopeKey(containerURL: containerURL, currentEntryName: currentName)
                })
                // Hidden entirely — not just disabled — unless its own real
                // preview count is actually greater than zero, using the
                // exact same `planRenameRomsInArchivePreviewCount` the
                // confirmation dialog itself relies on, so "would this
                // button do anything" and "what actually happens on click"
                // can never disagree. Deliberately NOT based on the
                // selected rows' own displayed status ("Ok" vs "Bad name")
                // — the count can still be > 0 purely from a case policy
                // re-style even when every row already reads "Ok".
                //
                // `viewModel.hasMatchReport` checked FIRST, same reason as
                // the Games table's own context menu above — jensyleo's own
                // bug report (2026-09-10) of "Scan Required" popping up from
                // a plain right-click, before Fix was ever asked for. See
                // `hasMatchReport`'s own doc comment.
                let renameRomsCount = viewModel.hasMatchReport
                    ? viewModel.planRenameRomsInArchivePreviewCount(scopeFolders: containerURLs, entryKeys: entryKeys)
                    : 0
                if !containerURLs.isEmpty, renameRomsCount > 0 {
                    Button {
                        startContextMenuRenameRomsInArchive(containerURLs, entryKeys)
                    } label: {
                        Label(
                            selectedRows.count == 1 ? "Fix This Misnamed ROM…" : "Fix These \(selectedRows.count) Misnamed ROMs…",
                            systemImage: "wrench.and.screwdriver"
                        )
                    }
                    .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                }
                // Same "only offered when its own real preview count is
                // actually greater than zero" rule as the rename button
                // just above, and the exact same reasoning: a "Fix" that's
                // guaranteed to do nothing reads as broken, not as "nothing
                // to fix here". Scoped to the whole container(s), same as
                // the Games table's own identical action — a redundant-ROM
                // sweep is never restricted to just the clicked row(s), any
                // more than it is there.
                let removeRedundantRomsCount = viewModel.hasMatchReport
                    ? viewModel.planRemoveRedundantRomsPreviewCount(scopeFolders: containerURLs)
                    : 0
                if !containerURLs.isEmpty, removeRedundantRomsCount > 0 {
                    Button(role: .destructive) {
                        startContextMenuRemoveRedundantRoms(containerURLs)
                    } label: {
                        Label("Remove Redundant ROM(s)…", systemImage: "trash")
                    }
                    .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                }
                // Cheap, already-computed signal (same as the Games table's
                // own `hasMaintenanceDonor` check) — never a fresh
                // Maintenance-folder read just to render a right-click menu.
                if selectedRows.contains(where: \.entry.hasMaintenanceDonor) {
                    Button {
                        startRepairFromMaintenanceFolder(containerURLs)
                    } label: {
                        Label("Find ROMs…", systemImage: "wrench.and.screwdriver")
                    }
                    .disabled(!LibraryViewModel.modificationsEnabled || viewModel.isBusy)
                }
                romEntryActionsMenuItems(selectedRows)
              }
              .labelStyle(.titleAndIcon)
            }
            .onChange(of: selection) { onFocusRequested() }
            // See `GameTreeTableView`'s own matching `.simultaneousGesture`
            // doc comment — same fix, same reason: re-clicking an
            // already-selected row here never fires the `onChange` above.
            .simultaneousGesture(TapGesture().onEnded { onFocusRequested() })
        }
    }
}
