// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Rolls a game's own `AuditEntry` rows up into one headline `AuditStatus` —
/// moved out of `LibraryDetailView.swift` (App) into Core (2026-08-13,
/// jensyleo's own request to make the App's game-aggregation logic
/// unit-testable, "Grupo A" of the App-logic extraction discussed the same
/// day) so it can be exercised by `swift test` directly, the same way
/// `GameCompletionStatus.compute(for:)` already is. Behavior is unchanged
/// from the original App-side functions — this is a pure relocation.
public enum GameStatusRollup {
    /// `isOptional` excluded from this check — the DAT's own
    /// `optional="yes"` attribute (MAME's own DTD) means MAME can run the
    /// machine without this specific rom/disk at all, so its absence
    /// shouldn't force the whole game red the way a genuinely required
    /// absence does.
    public static func gameCategory(for entries: [AuditEntry]) -> AuditStatus {
        if entries.contains(where: { $0.status == .missing && !$0.isOptional }) { return .missing }
        if entries.contains(where: { $0.status == .badDump }) { return .badDump }
        if entries.contains(where: { $0.status == .incorrect }) { return .incorrect }
        if entries.contains(where: { $0.status == .correct }) { return .correct }
        // A game whose only disk is DAT-declared with no sha1 at all
        // (undumped media) has no `.correct` entry to fall back on —
        // surfaced as its own status instead of silently claiming
        // something was actually verified when nothing was.
        if entries.contains(where: { $0.status == .unverifiable }) { return .unverifiable }
        return .correct
    }

    /// A game's headline status reflects its own roms, not its CHD disk —
    /// see ROADMAP.md "CHD/ROM independence": a correct CHD must never drag
    /// down an otherwise-correct rom set, and vice versa.
    public static func romOnlyGameCategory(for entries: [AuditEntry]) -> AuditStatus {
        let romEntries = entries.filter { !$0.isDisk }
        return romEntries.isEmpty ? gameCategory(for: entries) : gameCategory(for: romEntries)
    }
}
