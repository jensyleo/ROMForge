// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// How a confirmed-bad archive is handled — the "Corrupted files" three-way
/// policy from ClrMamePro's own Fix panel (see ROADMAP.md's own review of
/// it). Lives in `ROMForgeCore` (moved here from the App target,
/// 2026-09-01) so `RebuildPlanner` can plan directly from a value of this
/// type instead of the App target translating its own persisted setting
/// into ad-hoc parameters at every call site.
public enum CorruptedFilesPolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case delete
    case moveTo

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .delete: return "Delete"
        case .moveTo: return "Move to…"
        }
    }
}

/// How a rename target's case is chosen — applied independently to
/// archive-level names ("Sets case") and entry-level names inside an
/// archive ("Roms case"). "Datafile case" means: whatever case the DAT's
/// own declared name already uses, verbatim — distinct from "Don't touch"
/// (leave the existing on-disk name's case alone, even if it disagrees with
/// the DAT). Lives in `ROMForgeCore` (moved here from the App target,
/// 2026-09-01) for the same reason as `CorruptedFilesPolicy` above.
public enum FileCasePolicy: String, CaseIterable, Identifiable, Sendable {
    case dontTouch
    case uppercase
    case lowercase
    case datafileCase

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dontTouch: return "Don't Touch"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .datafileCase: return "Datafile Case"
        }
    }
}
