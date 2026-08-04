// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Shared worker-count policy for `FileHasher`/`CollectionHasher`'s
/// concurrent hashing — used to be `ProcessInfo.processInfo
/// .activeProcessorCount` outright, which pegged every core at once during a
/// big scan and made the rest of the Mac (including ROMForge's own UI
/// thread) noticeably sluggish. Leaving one core free keeps the machine
/// responsive while hashing runs, at the cost of a small amount of raw
/// hashing throughput — a deliberate trade given this is a foreground GUI
/// app's background work, not a batch job with the machine to itself.
enum HashingConcurrency {
    static func workerCount(for itemCount: Int) -> Int {
        let available = max(1, ProcessInfo.processInfo.activeProcessorCount - 1)
        return max(1, min(available, itemCount))
    }
}
