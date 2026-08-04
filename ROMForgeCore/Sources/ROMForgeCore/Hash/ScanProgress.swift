// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A snapshot of how many files have been hashed so far, out of the total
/// this scan will process.
public struct ScanProgress: Sendable, Equatable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }
}

/// A thread-safe completed/total counter shared across `FileHasher`'s
/// concurrent workers and `CollectionHasher`'s zip-entry hashing, so a scan
/// doing both loose-file and zip-entry hashing reports one continuous
/// progress count instead of two resetting phases.
///
/// Throttles the actual callback invocation (roughly 200 updates across the
/// whole scan) so a collection of tens of thousands of files doesn't flood
/// the caller — typically a SwiftUI view model — with an update per file.
public final class ScanProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = 0
    private let total: Int
    private let reportEvery: Int
    private let onProgress: @Sendable (ScanProgress) -> Void

    public init(total: Int, onProgress: @escaping @Sendable (ScanProgress) -> Void) {
        self.total = total
        self.reportEvery = max(1, total / 200)
        self.onProgress = onProgress
    }

    /// Marks one more file as done. Safe to call from any thread/task,
    /// including concurrently from multiple `TaskGroup` workers.
    public func increment() {
        // The callback runs while still holding the lock — it's cheap
        // (typically just publishing a value to a view model), and doing
        // so guarantees callers see reports in true increment order even
        // when multiple concurrent workers race to report at once.
        lock.lock()
        defer { lock.unlock() }
        completed += 1
        if completed % reportEvery == 0 || completed == total {
            onProgress(ScanProgress(completed: completed, total: total))
        }
    }
}
