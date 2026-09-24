// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The `fixPreferences.numberOfThreads` `UserDefaults` key/default,
/// governing `HashingConcurrency.workerCount(for:)`'s manual override —
/// Settings → Fix → "Number of threads" (jensyleo's own request,
/// 2026-09-11). Lives in Core, not the App-side `FixPreferencesSettings`
/// enum every other Fix-tab key lives in, specifically so `HashingConcurrency`
/// (Core) can read it directly without Core ever importing App — the App's
/// own `FixPreferencesSettings.numberOfThreadsKey`/`Default` just re-export
/// these two constants, so there's still exactly one source of truth for the
/// key string and default, the same way every other `*Settings` enum in this
/// app already reads its own live `UserDefaults` value on every access
/// (`ModificationsEnabledSettings.isEnabled`, `MaintenanceFolderSettings
/// .folderURL`) rather than caching it.
public enum HashingConcurrencySettings {
    public static let numberOfThreadsKey = "fixPreferences.numberOfThreads"
    /// `0` means "Auto" — `HashingConcurrency.workerCount(for:)`'s own
    /// core-count-minus-one policy below, unchanged from before this
    /// setting existed. A fresh install's `UserDefaults` has no value for
    /// this key at all, which reads back as `0` via `integer(forKey:)`
    /// (Foundation's own documented behavior for a missing key), so `0` is
    /// simultaneously the explicit "Auto" choice AND the correct default
    /// for a user who's never opened this setting — no separate "has this
    /// ever been set" check needed.
    public static let numberOfThreadsDefault = 0
    /// jensyleo's own hard ceiling for the Settings UI's stepper (2026-09-11)
    /// — see that Picker/Stepper's own doc comment in `FixSettingsView` for
    /// why 100 is offered as a hard ceiling to type up to, not a
    /// recommendation for what to actually run.
    public static let numberOfThreadsMaximum = 100

    /// Clamped to `0...numberOfThreadsMaximum` on read — protects against a
    /// directly-edited `UserDefaults` plist (or a future stray bug) ever
    /// requesting a runaway thread count no Mac should actually spin up.
    static func currentOverride() -> Int {
        max(0, min(numberOfThreadsMaximum, UserDefaults.standard.integer(forKey: numberOfThreadsKey)))
    }
}

/// Shared worker-count policy for `FileHasher`/`CollectionHasher`'s
/// concurrent hashing — used to be `ProcessInfo.processInfo
/// .activeProcessorCount` outright, which pegged every core at once during a
/// big scan and made the rest of the Mac (including ROMForge's own UI
/// thread) noticeably sluggish. Leaving one core free keeps the machine
/// responsive while hashing runs, at the cost of a small amount of raw
/// hashing throughput — a deliberate trade given this is a foreground GUI
/// app's background work, not a batch job with the machine to itself.
/// `HashingConcurrencySettings.numberOfThreadsKey` (Settings → Fix) can
/// override this automatic policy with a specific worker count.
enum HashingConcurrency {
    static func workerCount(for itemCount: Int) -> Int {
        let manualOverride = HashingConcurrencySettings.currentOverride()
        let available = manualOverride > 0 ? manualOverride : max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        return max(1, min(available, itemCount))
    }
}
