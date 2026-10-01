// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

import Foundation

/// A hand-curated note that one region's release of a game is objectively
/// more complete/less censored than another — jensyleo's own idea
/// (2026-09-30 conversation about Contra/Rush'n Attack/Bionic Commando),
/// researched and costed 2026-10-01. See ROADMAP.md's own "region-quality
/// visual indicator" section for the full research trail (why no existing
/// dataset/API covers this — TCRF is prose-only wiki, ScreenScraper/
/// LaunchBox/IGDB's "Region Priority" is a user preference, not an
/// objective judgment — so this really does need hand curation).
///
/// Never auto-derived from a DAT — this is editorial/historical knowledge
/// (extra content, removed censorship, bug fixes), not something a CRC/
/// hash encodes.
public struct RegionQualityNote: Codable, Equatable, Sendable {
    /// The game's common (usually Western) title with every parenthesized
    /// region/language/revision tag stripped (see `RegionQualityNotes
    /// .baseTitle(for:)`) — e.g. "Contra", not "Contra (USA)"/"Contra
    /// (Japan)". Matching by stripped title rather than the DAT's own
    /// `cloneOf` parent name is deliberate: which region a DAT happens to
    /// pick as the "parent" of a clone family is an arbitrary
    /// DAT-authoring choice, not something a hand-curated note should have
    /// to track per DAT.
    public let gameFamily: String
    /// Real bug found live (2026-10-01, "barrido exhaustivo"): a No-Intro
    /// DAT doesn't always use the SAME base title across regions — a
    /// Japan-exclusive original is often cataloged under its own real
    /// Japanese title, not "<Western title> (Japan)". Two of this file's
    /// own 3 seed entries hit this exactly: "Bionic Commando" (US/EU) is
    /// "Hitler no Fukkatsu - Top Secret" (Japan) in the DAT, and "Rush'n
    /// Attack" (US/EU) is "Green Beret" (Japan) — neither would ever match
    /// `gameFamily` by stripped-title alone. Every OTHER base title this
    /// same game is known by in a DAT (stripped the same way as
    /// `gameFamily`) goes here — empty for the common case where every
    /// region genuinely shares one title (e.g. "Contra").
    public let alternateTitles: [String]
    /// The recommended region, exactly as it appears in a game's own name
    /// tag (e.g. "Japan") — compared against `GameNameTagParser.parse(name:)
    /// .region`.
    public let recommendedRegion: String
    /// Short, factual explanation in ROMForge's own words — never source
    /// prose copy-pasted verbatim, even where the source's license would
    /// technically permit it (see `sourceLicense`).
    public let reason: String
    public let sourceURL: String
    public let sourceLicense: String
    public let consultedDate: String

    public init(gameFamily: String, alternateTitles: [String] = [], recommendedRegion: String, reason: String, sourceURL: String, sourceLicense: String, consultedDate: String) {
        self.gameFamily = gameFamily
        self.alternateTitles = alternateTitles
        self.recommendedRegion = recommendedRegion
        self.reason = reason
        self.sourceURL = sourceURL
        self.sourceLicense = sourceLicense
        self.consultedDate = consultedDate
    }
}

public enum RegionQualityNotes {
    /// Proof-of-concept seed — exactly the 3 titles already researched live
    /// this session, not a claim of broad coverage. Curating more entries
    /// is real, ongoing research work (see ROADMAP.md's own cost analysis)
    /// — this seed exists to make the feature real and testable, not to be
    /// comprehensive.
    public static let seed: [RegionQualityNote] = [
        RegionQualityNote(
            gameFamily: "Contra",
            recommendedRegion: "Japan",
            reason: "The Japanese (Famicom) release has background animation and an intro sequence that the US version cut during localization.",
            sourceURL: "https://gaminghistory101.com/2012/12/07/the-japanese-always-get-the-better-version-contra-famicom/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Rush'n Attack",
            alternateTitles: ["Green Beret"],
            recommendedRegion: "Japan",
            reason: "The Japanese original \"Green Beret\" allows up to 9 rounds of any secondary weapon (vs. 3 on NES), lets you continue at the exact spot you died, and has hidden underground areas in stages 2, 4, and 5 that the NES/Europe release lacks.",
            sourceURL: "https://www.movie-censorship.com/report.php?ID=439710",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Bionic Commando",
            alternateTitles: ["Hitler no Fukkatsu - Top Secret"],
            recommendedRegion: "Japan",
            reason: "The Japanese release \"Hitler no Fukkatsu - Top Secret\" is uncensored (swastikas, Adolf Hitler as the final boss); the US/European releases replace Hitler with \"Master-D\" and the crooked cross with an eagle symbol, equally censored in both.",
            sourceURL: "https://www.movie-censorship.com/report.php?ID=3851",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
    ]

    /// Strips every parenthesized tag group from a game name and trims the
    /// result — "Contra (USA)" → "Contra", "Green Beret (Asia) (En)
    /// (Kaiser) (Pirate)" → "Green Beret". Deliberately simple (no attempt
    /// to distinguish a "real" subtitle in parentheses from a region tag —
    /// no real No-Intro/TOSEC game title puts its own subtitle in
    /// parentheses, that convention is reserved for tags) rather than
    /// reusing `GameNameTagParser` (which only extracts region/language,
    /// not the remaining base title).
    public static func baseTitle(for name: String) -> String {
        var result = ""
        var depth = 0
        for char in name {
            if char == "(" { depth += 1; continue }
            if char == ")" { depth = max(0, depth - 1); continue }
            if depth == 0 { result.append(char) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Looks up a curated note for `name` by its stripped base title,
    /// matching either `gameFamily` itself OR any of its own
    /// `alternateTitles` (see that field's own doc comment for why a
    /// single title isn't enough) — checking `overrides` (user-provided,
    /// Application Support) before `seed`, a user's own override always
    /// winning on a match.
    public static func note(forGameName name: String, overrides: [RegionQualityNote] = []) -> RegionQualityNote? {
        let title = baseTitle(for: name)
        func matches(_ note: RegionQualityNote) -> Bool {
            note.gameFamily == title || note.alternateTitles.contains(title)
        }
        if let override = overrides.first(where: matches) { return override }
        return seed.first(where: matches)
    }
}
