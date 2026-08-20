// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import ROMForgeCore
import SwiftUI

/// The one `AuditStatus → Color` mapping the whole App layer uses —
/// `ContentView`'s sidebar status dot and `LibraryDetailView`'s status
/// icons/row tints used to each keep their own copy of this exact switch
/// (found duplicated verbatim during a 2026-08-18 code audit, including the
/// same 2026-08-06 gray-file-split doc comment pasted twice). Kept here
/// rather than on `AuditStatus` itself in ROMForgeCore — Core is
/// deliberately UI-agnostic (no SwiftUI/AppKit dependency), so a `Color`
/// belongs in the App layer that actually renders one.
extension AuditStatus {
    var tint: Color {
        switch self {
        case .correct: return .green
        case .incorrect: return .yellow
        case .badDump: return .orange
        case .missing: return .red
        // jensyleo's own gray-file split (2026-08-06): the "check me,
        // might be junk" tier reads as a fuller gray than the "correct by
        // definition, just unverifiable" tier — see `AuditStatus`'s own
        // doc comment for the full reasoning behind the split.
        case .surplus, .surplusInArchive, .unknownFile: return .gray
        case .unverifiable: return .gray.opacity(0.5)
        // Distinct from every "problem" tint above — a duplicate set
        // elsewhere isn't wrong, it's a whole extra copy of something
        // already correctly owned. Blue reads as "informational" rather
        // than "needs fixing", matching every other tint's own severity
        // signal.
        case .duplicateSet: return .blue
        }
    }
}
