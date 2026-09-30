// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// Deterministic, table-driven translation from the old GoodTools-style ROM
/// naming convention (`"Addams Family The (U).zip"`) to the equivalent
/// No-Intro name (`"Addams Family, The (USA)"`) — jensyleo's own real
/// collection (2026-09-29, NES): with "Trust file names" on, ~50% of the
/// "Unknown" gray files turned out to be genuine, correct GoodTools-tagged
/// dumps that simply never match a No-Intro name byte-for-byte, purely
/// because of three fixed, well-known naming differences:
///   1. Region tag shorthand: `(U)`/`(E)`/`(J)`/`(JU)`/etc. instead of
///      No-Intro's own spelled-out `(USA)`/`(Europe)`/`(Japan)`/
///      `(Japan, USA)`/etc.
///   2. Trailing article: `"Foo Bar The"` instead of `"Foo Bar, The"`.
///   3. Apostrophes replaced with a plain space (a filesystem-safety habit
///      from that era): `"Gilligan s Island"` instead of `"Gilligan's
///      Island"`.
///
/// This is intentionally NOT fuzzy/similarity matching — every rewrite
/// here is a fixed, known-safe table lookup, never a guess. The other real
/// ~50% found in that same analysis (fully different/abbreviated titles
/// like `"Batman (U)"` for `"Batman - The Video Game (USA)"`, or DAT
/// entries that merged what used to be separate USA/Europe releases into
/// one `(USA, Europe)` entry) are deliberately NOT covered — those need a
/// curated alias table or manual confirmation, not a rule, and guessing at
/// them risks accepting genuinely different content as a false match.
public enum GoodToolsNameTranslator {
    /// GoodTools' own region-tag vocabulary, mapped to every No-Intro
    /// spelling that tag could plausibly correspond to (broadest/most
    /// common first) — deliberately conservative: only tags this
    /// convention is actually documented to use, no invented ones.
    private static let tagMap: [String: [String]] = [
        "U": ["USA"], "E": ["Europe"], "J": ["Japan"],
        "JU": ["Japan, USA", "USA, Japan"], "UE": ["USA, Europe", "Europe, USA"],
        "JE": ["Japan, Europe"], "JUE": ["Japan, USA, Europe", "World"],
        "W": ["World"], "F": ["France"], "G": ["Germany"], "S": ["Spain"],
        "I": ["Italy"], "K": ["Korea"], "A": ["Australia"], "B": ["Brazil"], "C": ["China"],
    ]

    /// Candidate No-Intro-style names for a GoodTools-style name, WITHOUT
    /// any file extension (see `candidateFileNames(forRawFileName:)` for
    /// the extension-aware wrapper used on a rom/entry's own file name).
    /// Empty when `localName` doesn't end in a recognized `(TAG)` at all —
    /// deliberately narrow, never returns a guess for anything else.
    public static func candidateNames(forLocalName localName: String) -> [String] {
        let trimmed = localName.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(")"), let openParen = trimmed.lastIndex(of: "(") else { return [] }
        let tag = trimmed[trimmed.index(after: openParen)..<trimmed.index(before: trimmed.endIndex)]
        guard !tag.isEmpty, tag.allSatisfy(\.isLetter), let regions = tagMap[tag.uppercased()] else { return [] }
        let stem = String(trimmed[..<openParen]).trimmingCharacters(in: .whitespaces)
        guard !stem.isEmpty else { return [] }
        // Trailing-article reorder — GoodTools kept "The"/"A" at the end
        // of the stem; No-Intro moves it after a comma. Tried alongside
        // the un-reordered stem, never replacing it (either could be the
        // real DAT's own convention for a given title).
        var stems = [stem]
        if stem.hasSuffix(" The") {
            stems.append(String(stem.dropLast(4)).trimmingCharacters(in: .whitespaces) + ", The")
        }
        return stems.flatMap { s in regions.map { "\(s) (\($0))" } }
    }

    /// Same translation, but extension-aware — splits off the trailing
    /// `".ext"` (whatever it is) before translating the stem, and
    /// reattaches it to every candidate. Needed for a rom/archive ENTRY's
    /// own file name (e.g. `"10-Yard Fight (U) .nes"`, note the real,
    /// slightly malformed trailing space before the extension — trimmed
    /// away like any other whitespace by `candidateNames`), as opposed to
    /// an archive's own base name (already extension-free by the time
    /// `indexByArchiveName` builds its lookup).
    public static func candidateFileNames(forRawFileName rawFileName: String) -> [String] {
        guard let lastDot = rawFileName.lastIndex(of: "."), lastDot != rawFileName.startIndex else { return [] }
        let ext = rawFileName[rawFileName.index(after: lastDot)...]
        let base = String(rawFileName[..<lastDot])
        return candidateNames(forLocalName: base).map { "\($0).\(ext)" }
    }

    /// A comparison key that makes GoodTools' own apostrophe-as-space habit
    /// (and any other punctuation difference) a non-issue: lowercased,
    /// every non-alphanumeric character stripped — `"Gilligan's Island"`
    /// and `"Gilligan s Island"` both reduce to `"gilligansisland"`.
    /// Deliberately never applied to two names that AREN'T already the
    /// same real title (this is a comparison key, not a matching
    /// strategy on its own) — always used alongside the region-tag
    /// translation above, never as a substitute for it.
    public static func normalizedKey(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
