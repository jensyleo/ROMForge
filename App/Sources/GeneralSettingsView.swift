// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import ROMForgeCore
import SwiftUI

/// App-wide (not per-system) preferences — hash algorithms and scanning behavior.
/// `@AppStorage` under these exact keys is also what `HashAlgorithmSettings.current`
/// reads directly from `UserDefaults`, so this view and `LibraryViewModel`'s actual
/// scans always agree on the same three flags without any extra plumbing.
struct GeneralSettingsView: View {
    @AppStorage(HashAlgorithmSettings.crc32Key) private var computeCRC32 = true
    @AppStorage(HashAlgorithmSettings.md5Key) private var computeMD5 = true
    @AppStorage(HashAlgorithmSettings.sha1Key) private var computeSHA1 = true
    @AppStorage("ROMForge.scan.autoScanOnAdd") private var autoScanOnAdd = false
    @AppStorage(ModificationsEnabledSettings.storageKey) private var modificationsEnabled = false
    @State private var showModificationsConfirmation = false

    var body: some View {
        Form {
            Section("Write access") {
                Toggle("Enable file modifications", isOn: Binding(
                    get: { modificationsEnabled },
                    set: { newValue in
                        if newValue && !modificationsEnabled {
                            showModificationsConfirmation = true
                        } else {
                            modificationsEnabled = newValue
                        }
                    }
                ))
                Text("Allows rebuilding, repairing, renaming, and moving ROM files. Disabled by default for safety. Files are never overwritten — failed operations leave the originals untouched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Scanning") {
                Toggle("Auto-scan when adding a folder", isOn: $autoScanOnAdd)
                Text("Automatically begins scanning a newly-added ROM folder immediately after adding it, rather than waiting for a manual \"Scan Folder\" click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Hash algorithms") {
                // Every DAT format ROMForge reads declares at least CRC32
                // (the cheapest of the three, and the one every real DAT
                // tool falls back to) — MD5/SHA1 add real CPU cost on top
                // of it, especially across a large collection, without
                // improving verification for a rom the DAT only ever
                // declares a CRC for. Disabling one never causes a false
                // "missing": `ROMMatcher` only compares a hash both the DAT
                // declares *and* was actually computed, falling back to
                // whichever hash(es) remain enabled.
                Toggle("CRC32", isOn: $computeCRC32)
                    .disabled(computeCRC32 && !computeMD5 && !computeSHA1)
                Toggle("MD5", isOn: $computeMD5)
                    .disabled(computeMD5 && !computeCRC32 && !computeSHA1)
                Toggle("SHA1", isOn: $computeSHA1)
                    .disabled(computeSHA1 && !computeCRC32 && !computeMD5)
            }
            Text("At least one algorithm must stay enabled. Fewer algorithms means faster scans, at the cost of only being able to confirm a rom against whichever hash(es) the DAT and this list have in common.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .confirmationDialog(
            "Enable File Modifications?",
            isPresented: $showModificationsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Enable", role: .destructive) { modificationsEnabled = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ROMForge will be able to rename, move, and rebuild ROM files on disk to match the loaded DAT. Files are never overwritten — a failed operation leaves the original untouched — but this is real, on-disk file activity. You can turn this back off at any time.")
        }
    }
}

/// A single, global Rom/Bios merge mode — not per-system anymore. jensyleo's
/// own call (2026-07-27): having to configure this separately for every
/// MAME DAT/system (e.g. two `RomSystem`s comparing different MAME
/// versions) made no sense for "how do I want MAME sets laid out on disk",
/// which doesn't vary by *which* MAME DAT happens to be loaded. `current`/
/// `currentBios` are read directly from `UserDefaults` (same pattern as
/// `HashAlgorithmSettings`) so `LibraryViewModel`, not a View, can use them
/// without the property wrapper.
enum MAMEMergeModeSettings {
    static let mergeModeKey = "ROMForge.mame.mergeMode"
    static let biosMergeModeKey = "ROMForge.mame.biosMergeMode"

    /// `.nonMerged`: every game's archive is fully self-contained — the
    /// least likely to leave something unexpectedly "missing" due to a
    /// parent/BIOS archive not also being present, at the cost of more
    /// disk space per collection. Rom merge mode defaults to `.nonMerged`
    /// (jensyleo's own call, 2026-07-27, as this session's manual-testing
    /// starting point). Bios merge mode defaults to `.split` instead
    /// (jensyleo's own call, 2026-07-28) — the BIOS kept as its own
    /// separate archive, the more common real-world convention; a brief
    /// stretch where both defaulted to `.nonMerged` together was this
    /// session's own earlier testing starting point, not a permanent
    /// choice.
    static let defaultMergeMode: SetMergeMode = .nonMerged
    static let defaultBiosMergeMode: SetMergeMode = .split

    static var current: SetMergeMode {
        get { stored(mergeModeKey, default: defaultMergeMode) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: mergeModeKey) }
    }

    static var currentBios: SetMergeMode {
        get { stored(biosMergeModeKey, default: defaultBiosMergeMode) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: biosMergeModeKey) }
    }

    private static func stored(_ key: String, default fallback: SetMergeMode) -> SetMergeMode {
        guard let raw = UserDefaults.standard.string(forKey: key), let mode = SetMergeMode(rawValue: raw) else {
            return fallback
        }
        return mode
    }
}

/// A plain (non-View) reader for the same `@AppStorage` keys above — used
/// from `LibraryViewModel`, which isn't a View and can't use the property
/// wrapper directly.
enum HashAlgorithmSettings {
    static let crc32Key = "ROMForge.hashAlgorithm.crc32"
    static let md5Key = "ROMForge.hashAlgorithm.md5"
    static let sha1Key = "ROMForge.hashAlgorithm.sha1"

    /// Falls back to `.all` if every algorithm somehow ended up disabled
    /// (shouldn't happen — the toggles above refuse to let the last one
    /// turn off — but a directly-edited `UserDefaults` plist could still
    /// produce it) rather than silently hashing nothing at all.
    static var current: HashAlgorithms {
        let defaults = UserDefaults.standard
        var result: HashAlgorithms = []
        if defaults.object(forKey: crc32Key) == nil || defaults.bool(forKey: crc32Key) { result.insert(.crc32) }
        if defaults.object(forKey: md5Key) == nil || defaults.bool(forKey: md5Key) { result.insert(.md5) }
        if defaults.object(forKey: sha1Key) == nil || defaults.bool(forKey: sha1Key) { result.insert(.sha1) }
        return result.isEmpty ? .all : result
    }
}

/// Write-permission gate for Phase 2 (rebuild/repair/rename/move/delete) — jensyleo's
/// own design (2026-08-31): all destructive operations require this to be explicitly
/// enabled first, with a one-time confirmation dialog explaining what turning it on
/// means. Defaults to `false` (read-only mode) so the app stays safe until the user
/// deliberately opts in.
enum ModificationsEnabledSettings {
    static let storageKey = "ROMForge.modifications.enabled"

    /// Returns the persisted enabled state — always `false` on first install.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}
