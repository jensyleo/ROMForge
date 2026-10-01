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
    /// The game's common title with every parenthesized region/language/
    /// revision tag stripped (see `RegionQualityNotes.baseTitle(for:)`) —
    /// e.g. "Contra", not "Contra (USA)" or "Contra (Japan)". Matching by
    /// stripped title rather than the DAT's own `cloneOf` parent name is
    /// deliberate: which region a DAT happens to pick as the "parent" of a
    /// clone family is an arbitrary DAT-authoring choice, not something a
    /// hand-curated note should have to track per DAT.
    public let gameFamily: String
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

    public init(gameFamily: String, recommendedRegion: String, reason: String, sourceURL: String, sourceLicense: String, consultedDate: String) {
        self.gameFamily = gameFamily
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
            reason: "La versión japonesa (Famicom) tiene animaciones de fondo e introducción que la versión USA recortó durante la localización.",
            sourceURL: "https://gaminghistory101.com/2012/12/07/the-japanese-always-get-the-better-version-contra-famicom/",
            sourceLicense: "Resumen propio con atribución — no es texto copiado de la fuente",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Rush'n Attack",
            recommendedRegion: "Japan",
            reason: "El original japonés \"Green Beret\" tiene más vidas, más cargas de arma secundaria y áreas subterráneas extra que la versión NES/Europa.",
            sourceURL: "https://www.movie-censorship.com",
            sourceLicense: "Resumen propio con atribución — no es texto copiado de la fuente",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Bionic Commando",
            recommendedRegion: "Japan",
            reason: "La versión japonesa \"Hitler no Fukkatsu - Top Secret\" no está censurada (esvásticas/Hitler); USA y Europa están censuradas por igual.",
            sourceURL: "https://www.movie-censorship.com",
            sourceLicense: "Resumen propio con atribución — no es texto copiado de la fuente",
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
    /// checking `overrides` (user-provided, Application Support) before
    /// `seed` — a user's own override always wins on a `gameFamily` match.
    public static func note(forGameName name: String, overrides: [RegionQualityNote] = []) -> RegionQualityNote? {
        let family = baseTitle(for: name)
        if let override = overrides.first(where: { $0.gameFamily == family }) { return override }
        return seed.first { $0.gameFamily == family }
    }
}
