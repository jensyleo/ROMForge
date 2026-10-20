// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A candidate rename for an unrecognized local name, found by plain string
/// similarity against every real name in the loaded DAT — jensyleo's own
/// request (2026-09-29): unlike `GoodToolsNameTranslator` (a fixed,
/// deterministic table of known-safe rewrites, silently folded into
/// matching itself), this is a genuine best-effort GUESS, so it is NEVER
/// applied automatically. It only ever surfaces as a suggestion for a "Fix"
/// action the user explicitly confirms per file — a wrong guess here would
/// rename a file to claim an identity it doesn't actually have, which is
/// much worse than leaving it gray.
public struct SimilarNameSuggestion: Equatable, Sendable {
    /// The real DAT name this local name most resembles.
    public let suggestedName: String
    /// 0...1 — `1.0` means character-for-character identical (which would
    /// never reach this far, since an exact match is recognized as correct
    /// long before any suggestion logic runs).
    public let confidence: Double

    public init(suggestedName: String, confidence: Double) {
        self.suggestedName = suggestedName
        self.confidence = confidence
    }
}

public enum SimilarNameSuggester {
    /// Default confidence floor — jensyleo's own number ("90% o más"),
    /// picked specifically so an offered rename is near-certainly the same
    /// title (a typo, a truncation, a stray character) rather than a
    /// different game that merely shares a lot of its name.
    public static let defaultThreshold = 0.90

    /// The best-matching real name for `localName` among `candidateNames`,
    /// or `nil` if nothing clears `threshold`. Comparison is case-
    /// insensitive and ignores a trailing file extension on `localName`
    /// (a DAT name never has one); ties keep whichever candidate came
    /// first in `candidateNames`.
    ///
    /// `isAvailable` — jensyleo's own request (2026-09-29), for when more
    /// than one real DAT name is a close enough match: prefer whichever
    /// candidate the caller reports as NOT already satisfied elsewhere in
    /// the scan (its own real archive present, or another file already
    /// claiming its content) over one that is, but ONLY among genuine
    /// near-ties (within `tieBreakTolerance` of the single best score found)
    /// — real bug found live by jensyleo (2026-09-29): "Duck Tales (U).zip"
    /// scored 80% against the correct "DuckTales (USA)" (already claimed
    /// elsewhere in the same scan by a properly-named copy) and only 60%
    /// against the unrelated "DuckTales 2 (Europe)" (available) — an
    /// earlier version of this preference ALWAYS fell back to the
    /// best-scoring available candidate whenever the true best was taken,
    /// which confidently suggested the wrong GAME entirely instead of
    /// recognizing this file as a plain duplicate of an already-satisfied
    /// one. Restricting the preference to near-ties means it only ever
    /// breaks a genuine tie (two candidates that are both excellent
    /// matches), never substitutes a clearly-inferior different game.
    public static func bestMatch(
        forLocalName localName: String, candidateNames: [String], threshold: Double = defaultThreshold,
        tieBreakTolerance: Double = 0.05,
        isAvailable: (String) -> Bool = { _ in true }
    ) -> SimilarNameSuggestion? {
        var base = localName
        // Only the LAST "." counts as a real extension separator, and only
        // when nothing but the extension itself follows it (no spaces) —
        // real bug found live (2026-09-30) by jensyleo's own request to
        // audit every surplus file's actual best score: a title that's
        // already extension-free but contains a period as part of an
        // abbreviation (`"P.O.W. - Prisoners of War (U)"`, `"Dr. Mario"`,
        // `"G.I. Joe"`, `"M.U.S.C.L.E."`, `"Mr. Gimmick"`, `"Ms. Pac-Man"`,
        // `"R.B.I. Baseball"`, `"U.S. Championship V'Ball"`…) used to have
        // everything after that LAST internal period silently discarded —
        // `"P.O.W. - Prisoners of War (U)"` collapsed to just `"P.O.W"`
        // before comparison, scoring 16% against the correct
        // `"P.O.W. - Prisoners of War (USA)"` instead of the true ~94%. A
        // real trailing extension never has a space between the dot and
        // the end of the string; an abbreviation's period always does
        // (there's always more title after it).
        if let dot = base.lastIndex(of: "."), dot != base.startIndex, !base[dot...].contains(" ") {
            base = String(base[..<dot])
        }
        base = base.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty else { return nil }
        let baseParts = split(base)
        var bestAvailable: (name: String, score: Double)?
        var bestOverall: (name: String, score: Double)?
        for candidate in candidateNames {
            // Titles and "(region)(languages)(revision)" groups are compared
            // separately: a local name that simply omits the groups
            // ("Mario Kart 64") is the same title as "Mario Kart 64 (Europe)
            // (En,De)", and plain whole-string edit distance would punish it
            // for every missing parenthesis.
            let candidateParts = split(candidate)
            var score = 0.0
            // Whole-string similarity (the original measure).
            let maxLen = max(base.count, candidate.count)
            guard maxLen > 0 else { continue }
            if 1 - Double(abs(base.count - candidate.count)) / Double(maxLen) >= threshold {
                score = 1 - Double(levenshteinDistance(base.lowercased(), candidate.lowercased())) / Double(maxLen)
            }
            // Title and tag groups compared separately.
            let titleMax = max(baseParts.title.count, candidateParts.title.count)
            if titleMax > 0, 1 - Double(abs(baseParts.title.count - candidateParts.title.count)) / Double(titleMax) >= (threshold - 0.1) / 0.9 {
                let titleScore = 1 - Double(levenshteinDistance(baseParts.title.lowercased(), candidateParts.title.lowercased())) / Double(titleMax)
                let tagScore: Double
                if baseParts.tags.isEmpty || candidateParts.tags.isEmpty {
                    tagScore = baseParts.tags.isEmpty && candidateParts.tags.isEmpty ? 1 : 0.5
                } else {
                    let tagMax = max(baseParts.tags.count, candidateParts.tags.count)
                    tagScore = 1 - Double(levenshteinDistance(baseParts.tags.lowercased(), candidateParts.tags.lowercased())) / Double(tagMax)
                }
                score = max(score, titleScore * 0.9 + tagScore * 0.1)
            }
            guard score >= threshold else { continue }
            if bestOverall == nil || score > bestOverall!.score + 1e-9 || (abs(score - bestOverall!.score) <= 1e-9 && candidate.count < bestOverall!.name.count) {
                bestOverall = (candidate, score)
            }
            if isAvailable(candidate), bestAvailable == nil || score > bestAvailable!.score + 1e-9 || (abs(score - bestAvailable!.score) <= 1e-9 && candidate.count < bestAvailable!.name.count) {
                bestAvailable = (candidate, score)
            }
        }
        guard let bestOverall else { return nil }
        // Use the available candidate only when it's a genuine near-tie
        // with the true best score — otherwise the true best (even if
        // already taken) is the honest answer, since a caller can still
        // choose not to act on it (or can recognize it as "a duplicate of
        // an already-satisfied game", not a rename target at all).
        let winner = (bestAvailable?.score ?? -1) >= bestOverall.score - tieBreakTolerance ? (bestAvailable ?? bestOverall) : bestOverall
        return SimilarNameSuggestion(suggestedName: winner.name, confidence: winner.score)
    }

    /// "Title (USA) (En)" → ("Title", "(USA) (En)").
    private static func split(_ name: String) -> (title: String, tags: String) {
        guard let open = name.range(of: " (") else { return (name.trimmingCharacters(in: .whitespaces), "") }
        return (String(name[..<open.lowerBound]).trimmingCharacters(in: .whitespaces),
                String(name[open.lowerBound...]).trimmingCharacters(in: .whitespaces))
    }

    /// Classic single-row Levenshtein (edit distance) — insertions,
    /// deletions, substitutions, each cost 1. `O(n*m)` time and `O(min(n,m))`
    /// space (only the previous row is ever needed).
    static func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previousRow = Array(0...b.count)
        var currentRow = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            currentRow[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                currentRow[j] = Swift.min(
                    previousRow[j] + 1,
                    currentRow[j - 1] + 1,
                    previousRow[j - 1] + cost
                )
            }
            previousRow = currentRow
        }
        return previousRow[b.count]
    }
}
