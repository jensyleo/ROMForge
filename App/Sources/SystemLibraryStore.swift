// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
import Observation

/// Persists the sidebar's list of configured systems as JSON in Application
/// Support. A plain JSON file is proportionate here — the multi-table
/// SQLite/SwiftData catalog described in the roadmap is a v2.0+ concern for
/// scraped metadata, not for this simple name+DAT+folder list.
@Observable
@MainActor
final class SystemLibraryStore {
    private(set) var systems: [RomSystem] = []
    /// Persisted to `UserDefaults` on every change (`didSet` below) — jensyleo's
    /// own report (2026-09-29), right after switching back and forth between
    /// MAME and NES: every relaunch jumped back to whichever system happens to
    /// be first in `systems` (effectively "whichever was added first," MAME in
    /// practice), regardless of which one was actually being worked on when the
    /// app quit. `load()` now restores this instead of always defaulting to
    /// `systems.first`.
    var selectedSystemID: RomSystem.ID? {
        didSet {
            guard selectedSystemID != oldValue else { return }
            if let selectedSystemID {
                UserDefaults.standard.set(selectedSystemID.uuidString, forKey: Self.lastSelectedSystemIDKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.lastSelectedSystemIDKey)
            }
        }
    }

    private static let lastSelectedSystemIDKey = "ROMForge.lastSelectedSystemID"

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        load()
    }

    var selectedSystem: RomSystem? {
        systems.first { $0.id == selectedSystemID }
    }

    func add(_ system: RomSystem) {
        systems.append(system)
        selectedSystemID = system.id
        save()
    }

    /// Replaces a system's stored config in place (matched by id) — used
    /// for in-place edits like adding another ROM folder after the system
    /// was already created, rather than only ever at creation time via
    /// `AddSystemSheet`.
    func update(_ system: RomSystem) {
        guard let index = systems.firstIndex(where: { $0.id == system.id }) else { return }
        systems[index] = system
        save()
    }

    func remove(_ system: RomSystem) {
        systems.removeAll { $0.id == system.id }
        if selectedSystemID == system.id {
            selectedSystemID = systems.first?.id
        }
        save()
        ScanCacheLocation.remove(for: system)
        DATCacheLocation.remove(for: system)
        // Cleans up ROMForge's own internal copy of this system's DAT
        // (`DATStorageLocation`), if it has one and no remaining system
        // still shares it — a no-op for an external path the user still
        // owns, or one still referenced by another system.
        DATStorageLocation.removeIfOrphaned(system.datURL, keeping: systems)
        // jensyleo's own report (2026-09-16): "verifica que cuando se quite
        // el sistema se purgue toda la información" — a real, if harmless,
        // orphan found during that audit: this system's own persisted
        // "last selected Database filter / ROM folder" UserDefaults key
        // (`LibraryDetailView.lastSelectionKey(for:)`) was never removed
        // here, so it lived on forever under this system's UUID.
        UserDefaults.standard.removeObject(forKey: LibraryDetailView.lastSelectionKey(for: system))
        // `removeSystem` is a full SQLite `DELETE` of every row belonging
        // to this one system — for a real, large MAME system that can be
        // hundreds of thousands of rows. Found live (2026-08-13, same pass
        // as `LibraryViewModel.removeFolder`/`loadPersistedReport`'s own
        // cases) running synchronously on `@MainActor` here. The sidebar
        // itself already reflects the removal the moment `systems` above
        // changes — nothing here needs to finish before the UI moves on,
        // so this is fire-and-forget rather than awaited.
        let systemID = system.id.uuidString
        Task.detached(priority: .utility) {
            try? AuditDatabaseLocation.open().removeSystem(systemID)
        }
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ROMForge", isDirectory: true).appendingPathComponent("systems.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        systems = (try? JSONDecoder().decode([RomSystem].self, from: data)) ?? []
        // One-time migration — jensyleo's own report (2026-10-01): a system
        // saved before `AddSystemSheet`'s category picker existed has
        // `category == ""`, which the sidebar (`ContentView.groupedSystems`)
        // buckets into its own separate "SYSTEM" section instead of
        // grouping it with same-kind systems added since (e.g. a real
        // "MAME" system landing apart from a newly-added "MAME-TEST" one,
        // both actually MAME). Backfills the same historically-correct
        // fallback `isMAMEStyle`'s own default already uses ("every system
        // ROMForge supported until now WAS a MAME system") — `category`
        // itself didn't get the same backfill until now. A non-MAME legacy
        // system (shouldn't exist in practice, `isMAMEStyle` only defaults
        // `true`) falls back to "Otros" rather than staying empty.
        var migrated = false
        systems = systems.map { system in
            guard system.category.isEmpty else { return system }
            migrated = true
            var updated = system
            updated.category = system.isMAMEStyle ? SystemCategoryKind.mame.rawValue : SystemCategoryKind.other.rawValue
            return updated
        }
        if migrated { save() }
        let lastSelectedID = UserDefaults.standard.string(forKey: Self.lastSelectedSystemIDKey).flatMap(UUID.init(uuidString:))
        selectedSystemID = systems.first { $0.id == lastSelectedID }?.id ?? systems.first?.id
    }

    private func save() {
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(systems) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
