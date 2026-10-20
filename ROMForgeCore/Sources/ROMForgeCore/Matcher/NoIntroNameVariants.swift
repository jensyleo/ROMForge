// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Two fixed, deterministic differences between common local names and
/// No-Intro's own, used only by "Ignore CRC/hash verification" name matching
/// (real case, 2026-10-19, N64):
///   1. Revision letters: older sets write "(Rev A)"/"(Rev B)" where No-Intro
///      writes "(Rev 1)"/"(Rev 2)".
///   2. Language groups: No-Intro adds "(En,Ja)"-style language tags a local
///      name often lacks ("Yoshi's Story (USA)" vs "Yoshi's Story (USA) (En,Ja)").
///      Matching without them is only ever used when exactly ONE DAT game
///      remains — never a guess between several.
public enum NoIntroNameVariants {
    /// "(Rev A)" → "(Rev 1)", "(Rev B)" → "(Rev 2)"… `nil` when the name has
    /// no single-letter revision tag.
    public static func numericRevision(_ name: String) -> String? {
        guard let range = name.range(of: #"\(Rev ([A-Za-z])\)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let letter = name[range].dropFirst(5).first!.uppercased().unicodeScalars.first!.value
        guard letter >= 65, letter <= 90 else { return nil }
        return name.replacingCharacters(in: range, with: "(Rev \(letter - 64))")
    }

    /// `name` without its language-list groups ("(En,Fr,De)", "(En,Ja+En)").
    public static func withoutLanguageGroups(_ name: String) -> String {
        var result = ""
        var depth = 0
        var group = ""
        for char in name {
            if char == "(" {
                depth += 1
                if depth == 1 { group = ""; continue }
            }
            if char == ")", depth == 1 {
                depth = 0
                let tokens = group.split(whereSeparator: { $0 == "," || $0 == "+" }).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                let isLanguageList = !tokens.isEmpty && tokens.allSatisfy { GameNameDetails.languageNames[$0] != nil }
                if !isLanguageList { result += "(\(group))" }
                continue
            }
            if depth >= 1 { group.append(char) } else { result.append(char) }
        }
        return result.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }
}
