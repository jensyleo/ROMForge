// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import AppKit
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
    @AppStorage(MaxSubfolderDepthSettings.storageKey) private var maxSubfolderDepth = MaxSubfolderDepthSettings.defaultValue
    @AppStorage(ModificationsEnabledSettings.storageKey) private var modificationsEnabled = false
    @AppStorage(HashingConcurrencySettings.numberOfThreadsKey) private var numberOfThreads = HashingConcurrencySettings.numberOfThreadsDefault
    @AppStorage(FixResultPopupSettings.storageKey) private var showFixResultPopups = true
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
            // jensyleo's own request (2026-09-11): a pop-up after every
            // Fix/File Action write finishes, reporting success (with what
            // it did) or failure (with why) — on by default, but
            // configurable here so it can be turned back off in favor of
            // the Log panel alone, exactly how it worked before this
            // setting existed.
            Section("Notifications") {
                Toggle("Show pop-up after Fix/File Action completes", isOn: $showFixResultPopups)
                Text("Reports success or failure right after a Fix action (or a File Actions Move/Copy/Delete/etc.) finishes — in addition to, never instead of, the Log panel's own line for the same result. Turn this off to go back to Log-only reporting.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Scanning") {
                Toggle("Auto-scan when adding a folder", isOn: $autoScanOnAdd)
                Text("Automatically begins scanning a newly-added ROM folder immediately after adding it, rather than waiting for a manual \"Scan Folder\" click.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Maximum subfolder depth: \(maxSubfolderDepth)", value: $maxSubfolderDepth, in: 1...5)
                    .onChange(of: maxSubfolderDepth) { _, newValue in
                        FolderScanner.maxSubfolderDepth = newValue
                    }
                Text("How many levels of subfolder a scan will descend into below a configured ROM folder — \"1\" covers the common \\(system)/\\(game)/\\(file) layout. Raise this if your folders nest deeper (e.g. an extra \"BATOCERA\"-style folder above the game level: \\(system)/BATOCERA/\\(game)/\\(file) needs \"2\"). A folder nested past this limit is skipped, not scanned — logged as \"Skipped (nested too deep, not scanned)\" rather than silently missed. Kept deliberately capped (never \"unlimited\") so pointing this at something far too broad, like an entire drive, can't silently try to enumerate everything underneath it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // jensyleo's own request (2026-09-11): originally on the Fix
            // tab ("Colocar la opcion de Number of threads y colocar que
            // maximo 100"), moved here right after — "deja esa opcion de
            // performance en general" — since it governs every scan/hash
            // pass in the app (Scan Folder, Find ROMs,
            // Repair from Sibling Sets, etc.), not something specific to
            // "Fix".
            Section("Performance") {
                // jensyleo's own report (2026-09-11): a plain `in: 0...100`
                // range Stepper clamps at each end — climbing from 0 to 100
                // (or back down again) takes 100 individual clicks, and
                // there's no way to get back to "Auto" from 100 except
                // clicking all the way back down. Wraps instead:
                // incrementing past the maximum lands on 0 (Auto), and
                // decrementing below 0 lands on the maximum — the plain
                // `onIncrement`/`onDecrement` Stepper variant, not the
                // `value:in:` one, since that one has no wrap-around concept
                // at all.
                Stepper {
                    HStack {
                        Text("Number of threads")
                        Spacer()
                        Text(numberOfThreads == 0 ? "Auto" : "\(numberOfThreads)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } onIncrement: {
                    numberOfThreads = numberOfThreads >= HashingConcurrencySettings.numberOfThreadsMaximum ? 0 : numberOfThreads + 1
                } onDecrement: {
                    numberOfThreads = numberOfThreads <= 0 ? HashingConcurrencySettings.numberOfThreadsMaximum : numberOfThreads - 1
                }
                // jensyleo's own question (2026-09-11): whether 100 is
                // actually a good value to run at, not just the stepper's
                // ceiling. Recommendation, spelled out here rather than
                // silently picked for him: hashing is CPU-bound (CRC32/MD5/
                // SHA1 over each file's own bytes), so throughput tops out
                // at the number of CPU cores actually available — going
                // past that just means more threads taking turns on the
                // same cores, with added scheduling overhead and no real
                // speedup. "Auto" (0) already targets "every core but one"
                // (`HashingConcurrency`'s own doc comment), which is the
                // right number on every Mac this app runs on without
                // needing to know its exact core count. 100 is offered here
                // purely as a hard, generous ceiling for the rare case of a
                // future many-core Mac or a deliberate experiment — not a
                // number worth typing in on today's hardware.
                Text("0 = Auto (leaves one core free for the rest of the Mac — recommended, and already the right number on any Mac without needing to know its exact core count). Hashing is CPU-bound, so a manual value higher than your Mac's own core count rarely hashes anything faster; 100 is offered as a generous hard ceiling, not a target to actually reach for.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Reset to Defaults") { numberOfThreads = HashingConcurrencySettings.numberOfThreadsDefault }
                    Spacer()
                }
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

/// A pop-up alert after every Fix/File Action write finishes, reporting
/// success or failure (and the reason, for a failure) — jensyleo's own
/// request (2026-09-11): "agrega un mensaje emergente que diga si fue
/// exitoso... y con la información de lo que hizo", plus a separate one
/// specifically for failure and its reason. Deliberately ADDITIVE, never a
/// replacement — every existing Log line (`logSuccess`/`logWarning`/
/// `logError`) stays exactly as it already was; this is purely a second,
/// more visible channel for the same outcome, since jensyleo's own earlier
/// request (2026-08-17, see `LibraryViewModel.logError`'s own doc comment)
/// had explicitly asked for errors to live ONLY in the Log panel, not a
/// separate modal — a preference that's now being reversed, not a
/// contradiction to silently paper over. On by default; toggled off here
/// falls back to exactly that Log-only behavior.
enum FixResultPopupSettings {
    static let storageKey = "ROMForge.fixResultPopups.enabled"

    /// `true` unless the user has explicitly turned this off — a fresh
    /// install's `UserDefaults` has no value for this key at all, and
    /// `bool(forKey:)` returns `false` for a missing key, which would
    /// silently default this OFF instead of the "on by default" jensyleo
    /// asked for; `object(forKey:) == nil` is what actually distinguishes
    /// "never set" from "explicitly turned off".
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) == nil || UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// jensyleo's own request (2026-09-14): scanning the Maintenance folder
/// only ever refreshes the "donor available" (yellow) indicator for THIS
/// folder's own listing — a real rom folder like CPS1, already scanned
/// earlier this session, keeps showing whatever donor state it computed
/// back then until it's genuinely rescanned itself (`scan(system:)` is
/// what actually recomputes `MaintenanceDonorDetector`'s flags, never
/// `loadMaintenanceFolderFiles()` alone). Rather than a silent staleness
/// nobody notices, a one-line informational alert after scanning
/// Maintenance says so — gated by this toggle (on by default) so it can be
/// turned off once the behavior is familiar, same "on by default, opt out"
/// shape as `FixResultPopupSettings` above.
enum MaintenanceRescanNoticeSettings {
    static let storageKey = "ROMForge.maintenanceRescanNotice.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) == nil || UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// jensyleo's own request (2026-09-22): merely SELECTING the Maintenance
/// row for the first time each session used to always trigger a real
/// `loadMaintenanceFolderFiles()` disk read (`isSelectedFolderMaintenanceSubfolder`'s
/// own `.onChange`/`.onAppear` call sites in `LibraryDetailView.swift`) —
/// with the Maintenance root sitting on an unreachable NAS, plain
/// navigation (no Scan ever requested) could stall exactly like the
/// `refreshMaintenanceSubfolderExistsCache()` reachability check this same
/// day's report also flagged. Every other ROM folder row already behaves
/// the opposite way (a plain click never re-reads anything, only an
/// explicit "Scan Folder" does) — this toggle lets Maintenance match that
/// same behavior. On by default (the original, already-shipped behavior);
/// turning it off means Maintenance only ever gets read when the user
/// explicitly asks (an actual "Scan This Folder"/"Scan Maintenance
/// Folder…", or right-clicking a row that needs its own data).
enum MaintenanceAutoScanOnSelectSettings {
    static let storageKey = "ROMForge.maintenanceAutoScanOnSelect.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) == nil || UserDefaults.standard.bool(forKey: storageKey)
    }
}

/// Optional, global "Maintenance folder" — jensyleo's own design
/// (2026-09-02): a read-only donor folder ROMForge never renames, moves,
/// or deletes anything in or from. The user drops new or extra dumps
/// into it over time; Fase 2's "Find ROMs…" action
/// (see `LibraryViewModel.repairFromMaintenanceFolder`) scans it purely
/// to find content that completes a `.missing` rom elsewhere in the
/// currently scanned collection. Entirely optional — `nil` by default —
/// since a user may already keep such a donor folder on their own and
/// just point ROMForge at it occasionally, or never use this feature at
/// all. Global rather than per-system, same reasoning as
/// `MAMEMergeModeSettings`: one donor folder makes sense across every
/// system, not configured separately per DAT.
/// The stored path is the Maintenance ROOT — jensyleo's own request
/// (2026-09-11): "que se cree un folder por cada sistema que se tenga...
/// Manteinance/MAME, Manteinance/NES, etc." Originally a single flat
/// folder scanned as one unit regardless of which system was active;
/// `subfolderURL(for:)` below is what makes "Repair from Maintenance
/// Folder…" scope to just one system's own donors instead of every
/// system's mixed together. An existing flat root from before this
/// change keeps working exactly as before it's ever asked to create a
/// subfolder — the migration is entirely lazy, via `ensureSubfolderExists`,
/// never a one-time forced re-setup.
enum MaintenanceFolderSettings {
    static let storageKey = "ROMForge.maintenanceFolder.path"

    /// jensyleo's own report (2026-09-16): "creo la carpeta de
    /// mantenimiento y no la está mostrando" — a real regression from
    /// this same session's earlier fix (`LibraryDetailView`'s own
    /// `refreshMaintenanceSubfolderExistsCache`, no longer called
    /// unconditionally on every `.onAppear`): creating the Maintenance
    /// root here, in Settings — a SEPARATE window from an already-open
    /// system's detail view — used to be silently picked up because the
    /// old code re-checked disk on every appearance; now it genuinely
    /// isn't, since nothing tells that other window anything changed.
    /// Posted right after every create/backfill below so any open
    /// `LibraryDetailView` can re-check its own subfolder's existence
    /// immediately, without needing to be closed and reopened.
    static let subfoldersDidChange = Notification.Name("ROMForge.maintenanceFolder.subfoldersDidChange")
    /// Posted specifically after a DELIBERATE delete of one system's own
    /// subfolder — jensyleo's own follow-up (2026-09-16): a plain
    /// `fileExists` failure can't tell "genuinely deleted on purpose"
    /// apart from "can't currently reach the NAS/volume it lives on", but
    /// the sidebar row needs to react very differently to each (hide vs.
    /// mark red/unreachable — see `LibraryDetailView`'s own
    /// `maintenanceSubfolderDeleted` doc comment). A separate, explicit
    /// notification is simpler and less error-prone than overloading
    /// `subfoldersDidChange` with a payload.
    static let subfolderDidDelete = Notification.Name("ROMForge.maintenanceFolder.subfolderDidDelete")

    /// `nil` when unset (default) or when the stored path is empty.
    static var folderURL: URL? {
        guard let path = UserDefaults.standard.string(forKey: storageKey), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Reduces a system's own (user-typed, not DAT-declared) name to a
    /// single safe path component — same reasoning as `RebuildPlanner
    /// .safePathComponent` (not exposed outside ROMForgeCore, so
    /// duplicated here rather than widening that type's own access level
    /// just for this one App-side use).
    private static func safeSubfolderName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return (last.isEmpty || last == "." || last == "..") ? "_" : last
    }

    /// This system's OWN subfolder under the Maintenance root — `nil`
    /// whenever the root itself isn't configured yet. "Repair from
    /// Maintenance Folder…" (`LibraryViewModel
    /// .planRepairFromMaintenanceFolderPreviewCount(system:)`) scans ONLY
    /// this, never the whole root, so a donor dropped for one system can
    /// never accidentally satisfy a different system's missing rom.
    static func subfolderURL(for system: RomSystem) -> URL? {
        folderURL?.appendingPathComponent(safeSubfolderName(system.name), isDirectory: true)
    }

    /// Creates this exact system's own subfolder (and the root, if it
    /// somehow doesn't exist either) — idempotent, safe to call on every
    /// app launch/system open. Returns the subfolder URL whether it was
    /// just created or already existed, or `nil` if no root is configured
    /// at all (nothing to create relative to).
    @discardableResult
    static func ensureSubfolderExists(for system: RomSystem) -> URL? {
        guard let subfolder = subfolderURL(for: system) else { return nil }
        try? FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        return subfolder
    }

    /// True when `url` sits inside the Maintenance root itself, or any of
    /// its per-system subfolders — jensyleo's own request (2026-09-11):
    /// "mover, copiar o modificar en las carpetas de mantenimiento, no es
    /// posible". The whole area is documented, deliberately read-only donor
    /// storage (see `subfolderURL(for:)`'s own doc comment) — a new "File
    /// Actions" Move/Copy/Delete/Trash must never touch a file living here,
    /// since that could silently break a repair someone's relying on.
    /// `false` when no Maintenance root is configured at all (nothing to be
    /// inside of).
    static func isUnderMaintenanceFolder(_ url: URL) -> Bool {
        guard let root = folderURL else { return false }
        let rootPath = root.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    /// Permanently deletes this exact system's own subfolder (and
    /// everything a user dropped inside it) — jensyleo's own request
    /// (2026-09-13): "agregar la opción de eliminar Maintenance folder por
    /// sistema (MAME, NES, etc.)". Deliberately per-system, never the whole
    /// Maintenance root at once — a user who wants to stop keeping donor
    /// ROMs for one specific system (freeing disk space, say) shouldn't
    /// have to lose every OTHER system's donor folder along with it. A
    /// no-op (not an error) when the subfolder simply doesn't exist yet —
    /// same "already the desired end state" reasoning `ensureSubfolderExists`
    /// already uses for the create direction. Stays deleted until something
    /// genuinely needs it again (a "Find ROMs…" read,
    /// or explicitly re-running the Settings root setup) — jensyleo's own
    /// report (2026-09-16): it used to be silently re-created empty the
    /// next time this system's own detail view merely opened, which made a
    /// real delete look like it never happened.
    static func deleteSubfolder(for system: RomSystem) throws {
        guard let subfolder = subfolderURL(for: system), FileManager.default.fileExists(atPath: subfolder.path) else { return }
        try FileManager.default.removeItem(at: subfolder)
    }
}

/// How many levels of subfolder a scan descends into below a configured
/// ROM folder before treating a deeper one as "too deep, skip it" —
/// backs `FolderScanner.maxSubfolderDepth` (a mutable `var`, not a
/// compile-time constant, specifically so this setting can drive it).
/// jensyleo's own report (2026-09-10): a real BATOCERA-exported folder
/// nested two extra levels above the game folder, past the safe default
/// of 1, silently skipping every file in every one of those games with
/// no way to reach them short of physically reorganizing the folder —
/// this Settings → General control is that way out. Default stays `1`
/// (unchanged from before this setting existed) rather than jumping to
/// something more permissive by default — the whole POINT of the cap is
/// staying conservative until a real folder layout actually needs more.
enum MaxSubfolderDepthSettings {
    static let storageKey = "ROMForge.scan.maxSubfolderDepth"
    static let defaultValue = 1

    /// Applies the persisted value to `FolderScanner.maxSubfolderDepth` —
    /// call once at app launch so a scan that runs before Settings is
    /// ever opened this session still honors whatever was configured in
    /// an earlier one, not the compiled-in default.
    static func applyPersistedValue() {
        let stored = UserDefaults.standard.object(forKey: storageKey) as? Int ?? defaultValue
        FolderScanner.maxSubfolderDepth = stored
    }
}
