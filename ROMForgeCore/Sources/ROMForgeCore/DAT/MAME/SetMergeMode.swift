// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// How a machine's ROMs are laid out into physical archives.
public enum SetMergeMode: String, Equatable, Sendable, Codable, CaseIterable {
    /// Each machine's archive contains only its own declared ROMs; clones
    /// rely on the parent/BIOS archive for anything inherited (what a
    /// Logiqx/MAME DAT already encodes per machine).
    case split
    /// Each machine's archive is self-contained: its own ROMs plus every ROM
    /// inherited from its parent/BIOS chain, so nothing else is required.
    case nonMerged
    /// One archive per parent, containing the parent's own ROMs plus every
    /// direct clone's ROMs; clones produce no archive of their own.
    case merged
}
