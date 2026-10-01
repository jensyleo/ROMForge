// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Detects whether a given path lives on a network-mounted volume (SMB,
/// AFP, NFS, WebDAV, …) rather than a local disk — jensyleo's own request
/// (2026-10-01), after confirming (real research, Microsoft's own SMB
/// troubleshooting docs) that scanning many small files over a NAS is
/// dominated by per-file round-trip latency, not local CPU/disk throughput,
/// and that raising hashing concurrency well above core count helps hide
/// that latency (more requests in flight) even though it never helps a
/// local, CPU-bound scan. A single `statfs(2)` call answers this: `f_flags
/// & MNT_LOCAL` is Darwin's own, standard way to tell (confirmed via
/// Apple's "Testing for a Network Volume" developer note and the
/// `statfs`/`fstatfs` man page) — the same thing Foundation's own
/// `URLResourceKey.volumeIsLocalKey` reports under the hood, but `statfs`
/// needs no resource-value round trip and works equally well against a
/// path that doesn't exist yet. No entitlement needed either way — this is
/// a plain BSD syscall, not sandboxed/privileged file access, and ROMForge
/// isn't sandboxed regardless (no `.entitlements` file in the project).
///
/// Deliberately does NOT try to identify the specific protocol (SMB vs NFS
/// vs AFP) or measure actual link speed/latency — every real NAS protocol
/// has the same per-file round-trip cost, and no API exposes a reliable
/// "how fast is this link" number without actually probing it (a real
/// read, which is its own added complexity/startup cost for little gain).
/// A plain local/network boolean is the one piece of information that's
/// both cheap and actually reliable — see this file's own git history for
/// the research that justified not going further than this.
enum VolumeLocality {
    static func isNetworkVolume(at url: URL) -> Bool {
        var stat = statfs()
        guard statfs(url.path, &stat) == 0 else { return false }
        return stat.f_flags & UInt32(MNT_LOCAL) == 0
    }
}

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
    /// Auto's own fixed profile for a network-mounted ROM folder — jensyleo's
    /// own request (2026-10-01), applied only when "Number of threads" is
    /// still "Auto" (`0`) AND `sampleURL` resolves to a network volume
    /// (`VolumeLocality.isNetworkVolume`). A manual override always wins
    /// regardless of locality — this only changes what "Auto" itself means.
    /// `16` rather than something derived from core count: the whole point
    /// is that these workers mostly sit blocked on network I/O, not
    /// competing for cores, so core count is the wrong basis entirely here
    /// — see this file's own research-citing doc comment above
    /// (`VolumeLocality`) for why no better number can be derived without
    /// an actual network probe, which isn't worth the added complexity for
    /// this case.
    static let networkVolumeAutoWorkerCount = 16

    static func workerCount(for itemCount: Int, sampleURL: URL? = nil) -> Int {
        let manualOverride = HashingConcurrencySettings.currentOverride()
        let available: Int
        if manualOverride > 0 {
            available = manualOverride
        } else if let sampleURL, VolumeLocality.isNetworkVolume(at: sampleURL) {
            available = networkVolumeAutoWorkerCount
        } else {
            available = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        }
        return max(1, min(available, itemCount))
    }
}
