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
    var selectedSystemID: RomSystem.ID?

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
        try? AuditDatabaseLocation.open().removeSystem(system.id.uuidString)
    }

    private static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("ROMForge", isDirectory: true).appendingPathComponent("systems.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        systems = (try? JSONDecoder().decode([RomSystem].self, from: data)) ?? []
        selectedSystemID = systems.first?.id
    }

    private func save() {
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(systems) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
