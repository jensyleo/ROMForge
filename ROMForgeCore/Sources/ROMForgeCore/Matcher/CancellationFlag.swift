// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A plain, lock-protected cancellation signal — deliberately *not* based on
/// `Task`/`Task.isCancelled`. Real bug found live by jensyleo (2026-08-04):
/// pressing Cancel during a large scan showed the cancellation warning
/// immediately, but the scan kept running all the way to completion
/// regardless. `Task.checkCancellation()` checks sprinkled through
/// `ROMMatcher`/`AuditReporter`/`DiskAuditor`/`DATLoader` fixed most of the
/// pipeline — but `ROMMatcher`'s own single slowest stretch
/// (`computePerGameCandidates`, often multiple minutes on a full MAME DAT)
/// runs its work on `DispatchQueue.concurrentPerform`'s raw GCD worker
/// threads, which are never "inside" any `Task` at all — `Task.isCancelled`
/// there unconditionally reads `false` no matter what, making that check
/// silently pointless exactly where cancellation needed to work most.
///
/// This flag is set directly by `LibraryViewModel.cancelCurrentOperation()`
/// (independent of, and in addition to, cancelling the enclosing `Task`) and
/// polled by those same GCD workers — the only mechanism that can actually
/// interrupt work dispatched that way.
public final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    public init() {}

    public func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }
}
