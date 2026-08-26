// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// The "Database" search field's own matching rule — moved out of
/// `LibraryDetailView.swift` (2026-08-13, "Grupo A" of the App-logic
/// extraction) so it's unit-testable without opening the app.
///
/// A plain pattern (no `*`/`?`) matches from the *start* of `text` only,
/// case-insensitively — unchanged.
///
/// jensyleo's own report (2026-08-13): a pattern with `*`/`?` used to be
/// fully anchored at BOTH ends (`^...$`) — so `*street` (a wildcard on only
/// one side) meant "ends with street" literally, matching nothing for a
/// real game like "Street Fighter II" (which doesn't end with "street" at
/// all) even though that's exactly the intuitive "contains" search a
/// leading/trailing `*` reads as. Dropped the anchors entirely: `*`/`?` still
/// mean what they always did (any run of characters / exactly one
/// character), but the match can now start anywhere in `text`, not only at
/// its very beginning — so `*street`, `street*`, and `*street*` all now find
/// "Street Fighter II" the same way a plain "contains" search would.
public enum DatabaseSearchMatcher {
    public static func matches(_ text: String, pattern: String) -> Bool {
        guard pattern.contains("*") || pattern.contains("?") else {
            return text.range(of: pattern, options: [.caseInsensitive, .anchored]) != nil
        }
        var regexPattern = ""
        for char in pattern {
            switch char {
            case "*": regexPattern += ".*"
            case "?": regexPattern += "."
            default: regexPattern += NSRegularExpression.escapedPattern(for: String(char))
            }
        }
        guard let regex = try? NSRegularExpression(pattern: regexPattern, options: [.caseInsensitive]) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
