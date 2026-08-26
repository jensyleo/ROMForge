// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Detects the TOSEC/GoodTools convention of embedding a file's own CRC32
/// directly in its filename, e.g. `Sonic The Hedgehog [12AB34CD].zip` or
/// `Sonic The Hedgehog (12AB34CD).bin` — external-to-MAME conventions (a
/// native MAME/Logiqx DAT rom name never carries this), but real files a
/// MAME-organized folder can still end up holding (a loose TOSEC/GoodTools
/// dump dropped in, or a surplus file left over from one).
///
/// Deliberately its own, narrower parser rather than reusing
/// `GameNameTagParser` (which reads the *game*-name's region/language tags,
/// a different parenthesized convention entirely) — the two never collide
/// in practice since no real region or language-code group is ever exactly 8
/// hex digits, but keeping this check to that one specific shape (exactly 8
/// hex characters, nothing looser) is what keeps it from ever misreading an
/// unrelated tag as a CRC.
public enum FilenameEmbeddedCRC {
    /// Returns the embedded CRC32, lowercased, if `name` contains exactly one
    /// `[XXXXXXXX]`/`(XXXXXXXX)` group of exactly 8 hexadecimal characters —
    /// the whole point of the convention being a fixed-width, unambiguous
    /// tag. `nil` for any other shape, including a bracketed group that's
    /// almost but not quite 8 hex digits (e.g. a 7-digit typo, or a
    /// TOSEC flag like `[b]`/`[!]` which is never hex-only length-8 anyway).
    public static func embeddedCRC32(inFileName name: String) -> String? {
        let baseName = (name as NSString).deletingPathExtension
        for group in bracketedGroups(in: baseName) {
            let trimmed = group.trimmingCharacters(in: .whitespaces)
            guard trimmed.count == 8, trimmed.allSatisfy(\.isHexDigit) else { continue }
            return trimmed.lowercased()
        }
        return nil
    }

    /// Same depth-tracked scan as `GameNameTagParser.parenthesizedGroups`,
    /// extended to also open/close on `[`/`]` — TOSEC favors brackets for
    /// its own flags, GoodTools favors parens for the CRC tag specifically,
    /// and real collections mix conventions, so both are read the same way
    /// rather than only supporting one.
    private static func bracketedGroups(in name: String) -> [String] {
        var groups: [String] = []
        var depth = 0
        var current = ""
        for char in name {
            switch char {
            case "(", "[":
                depth += 1
                if depth == 1 { current = "" }
            case ")", "]":
                if depth == 1 { groups.append(current) }
                depth = max(0, depth - 1)
            default:
                if depth >= 1 { current.append(char) }
            }
        }
        return groups
    }
}
