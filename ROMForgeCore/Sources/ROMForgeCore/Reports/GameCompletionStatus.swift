// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A game/machine's set-completeness verdict — RomVault's own Complete/
/// Partial/Empty/Fixable taxonomy (romvault.com), distinct from
/// `AuditStatus.worst(among:)`'s severity rollup: that answers "what's the
/// single worst thing about this game's roms", this answers "how much
/// actual redownloading, if any, would fixing this game require".
///
/// jensyleo's own request (2026-08-13), part of the GUI/visualization
/// recommendations report: the "Database" tree can already tell you a
/// game is `.incorrect`/`.missing`, but not whether that's a five-second
/// rename (`fixable`) or requires finding real missing content
/// (`partial`/`empty`) — the distinction RomVault's own filters are built
/// around.
public enum GameCompletionStatus: String, Equatable, Sendable, CaseIterable {
    /// Every required rom present with the right content.
    case complete
    /// Every required rom present, none missing — but at least one is
    /// misnamed/misplaced (`.incorrect`). Fixable by rename/move alone,
    /// no new content needed.
    case fixable
    /// Some, but not all, required roms are present.
    case partial
    /// No required rom is present at all.
    case empty

    /// Computes one game's completion status from its own `AuditEntry`
    /// rows. `nil` for an empty list (nothing to judge — e.g. a game with
    /// zero entries under the current merge mode).
    ///
    /// Scoped to rom entries only, falling back to all entries if the game
    /// has none — same `romOnlyGameCategory`-style fold `LibraryDetailView`
    /// already applies elsewhere, so a game's CHD status never affects its
    /// rom completeness verdict (see ROADMAP.md "CHD/ROM independence").
    /// `isOptional` entries are excluded from the required count for the
    /// same reason `gameCategory(for:)` excludes them: MAME itself can run
    /// the machine without them.
    ///
    /// A present-but-`.badDump` rom is never `fixable` — a rename can't
    /// repair wrong content, only wrong naming/location — so it counts as
    /// `partial`, the same "still needs real content" bucket a missing rom
    /// falls into.
    public static func compute(for entries: [AuditEntry]) -> GameCompletionStatus? {
        guard !entries.isEmpty else { return nil }
        let romEntries = entries.filter { !$0.isDisk }
        let scoped = romEntries.isEmpty ? entries : romEntries
        let required = scoped.filter { !$0.isOptional }
        guard !required.isEmpty else { return .complete }

        let missingCount = required.filter { $0.status == .missing }.count
        if missingCount == required.count { return .empty }
        if missingCount > 0 { return .partial }
        if required.contains(where: { $0.status == .badDump }) { return .partial }
        if required.contains(where: { $0.status == .incorrect }) { return .fixable }
        return .complete
    }
}
