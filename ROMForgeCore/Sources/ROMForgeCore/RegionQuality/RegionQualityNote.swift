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
    /// Which platform this note applies to, as `RomSystem.category` stores it
    /// ("NES", "SNES"…). Titles repeat across platforms ("Contra" exists on
    /// NES, Genesis, Game Boy…), so a note must never fire for another
    /// platform's game. `nil` = any platform.
    public let platform: String?
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
    /// Other regions that are EQUALLY good as `recommendedRegion` — when no
    /// single region clearly wins, the note lists every tied one instead of
    /// crowning just one.
    public let tiedRegions: [String]
    /// Every region that is a best version.
    public var bestRegions: [String] { [recommendedRegion] + tiedRegions }
    /// "Japan or USA" for display.
    public var bestRegionsLabel: String { bestRegions.joined(separator: " or ") }
    /// Short, factual explanation in ROMForge's own words — never source
    /// prose copy-pasted verbatim, even where the source's license would
    /// technically permit it (see `sourceLicense`).
    public let reason: String
    public let sourceURL: String
    public let sourceLicense: String
    public let consultedDate: String

    public init(gameFamily: String, platform: String? = nil, alternateTitles: [String] = [], recommendedRegion: String, tiedRegions: [String] = [], reason: String, sourceURL: String, sourceLicense: String, consultedDate: String) {
        self.gameFamily = gameFamily
        self.platform = platform
        self.alternateTitles = alternateTitles
        self.recommendedRegion = recommendedRegion
        self.tiedRegions = tiedRegions
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
            platform: "NES",
            recommendedRegion: "Japan",
            reason: "The Japanese (Famicom) release has background animation and an intro sequence that the US version cut during localization.",
            sourceURL: "https://gaminghistory101.com/2012/12/07/the-japanese-always-get-the-better-version-contra-famicom/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Rush'n Attack",
            platform: "NES",
            alternateTitles: ["Green Beret"],
            recommendedRegion: "Japan",
            reason: "The Japanese original \"Green Beret\" allows up to 9 rounds of any secondary weapon (vs. 3 on NES), lets you continue at the exact spot you died, and has hidden underground areas in stages 2, 4, and 5 that the NES/Europe release lacks.",
            sourceURL: "https://www.movie-censorship.com/report.php?ID=439710",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Bionic Commando",
            platform: "NES",
            alternateTitles: ["Hitler no Fukkatsu - Top Secret"],
            recommendedRegion: "Japan",
            reason: "The Japanese release \"Hitler no Fukkatsu - Top Secret\" is uncensored (swastikas, Adolf Hitler as the final boss); the US/European releases replace Hitler with \"Master-D\" and the crooked cross with an eagle symbol, equally censored in both.",
            sourceURL: "https://www.movie-censorship.com/report.php?ID=3851",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-09-30"
        ),
        RegionQualityNote(
            gameFamily: "Castlevania III - Dracula's Curse",
            platform: "NES",
            alternateTitles: ["Akumajou Densetsu"],
            recommendedRegion: "Japan",
            reason: "The Famicom cartridge carries the Konami VRC6 chip, adding three extra sound channels; the Western release had to rework the music for the stock NES channels. Japan also keeps the uncensored imagery.",
            sourceURL: "https://en.wikipedia.org/wiki/Castlevania_III:_Dracula's_Curse",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Mr. Gimmick",
            platform: "NES",
            alternateTitles: ["Gimmick!", "Gimmick"],
            recommendedRegion: "Japan",
            reason: "The Japanese cartridge uses the Sunsoft 5B sound chip for extra music channels; the European release has a downgraded stock-NES soundtrack and glitches on NTSC consoles (Europe does give more lives, a difficulty tweak rather than a quality gain).",
            sourceURL: "https://www.hardcoregaming101.net/gimmick/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Life Force - Salamander",
            platform: "NES",
            alternateTitles: ["Life Force", "Salamander"],
            recommendedRegion: "Japan",
            reason: "The Famicom Salamander has an animated title screen, an ending that varies with continues used, up to three options instead of two, and a cleaner HUD.",
            sourceURL: "https://gradius.miraheze.org/wiki/Salamander",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Dragon Warrior",
            platform: "NES",
            alternateTitles: ["Dragon Quest"],
            recommendedRegion: "USA",
            reason: "The NES release replaced the Famicom password system with battery-backed saves that keep HP and MP, and adds directional character sprites and better coastlines.",
            sourceURL: "https://dragon-quest.org/wiki/List_of_version_differences_in_Dragon_Quest_I",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Faxanadu",
            platform: "NES",
            recommendedRegion: "Japan",
            reason: "Japan keeps the original Christian imagery that the Western release removed or altered and lets you name the hero; gameplay and tech are not clearly better in either region.",
            sourceURL: "https://www.hardcoregaming101.net/faxanadu/",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Super Castlevania IV",
            platform: "SNES",
            alternateTitles: ["Akumajou Dracula"],
            recommendedRegion: "Japan",
            reason: "The Western release removed crucifixes, recolored the stage 8 blood and covered bare-chested statues; the Japanese version keeps all of it with otherwise identical gameplay.",
            sourceURL: "https://www.furiouspaul.com/snes/castlevania4/american-vs-japanese.php",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Chrono Trigger",
            platform: "SNES",
            recommendedRegion: "Japan",
            reason: "The Japanese release has the ending artwork and a running item-count display in the status menu that the North American version lacks (minor extras).",
            sourceURL: "https://en.wikipedia.org/wiki/Chrono_Trigger",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Final Fantasy III",
            platform: "SNES",
            alternateTitles: ["Final Fantasy VI"],
            recommendedRegion: "Japan",
            reason: "The US release altered or removed graphics and text (renamed spells and places) and compressed the dialogue to fit the cartridge; the Japanese version is unaltered.",
            sourceURL: "https://en.wikipedia.org/wiki/Final_Fantasy_VI",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Contra III - The Alien Wars",
            platform: "SNES",
            alternateTitles: ["Contra Spirits", "Super Probotector - Alien Rebels"],
            recommendedRegion: "Japan",
            tiedRegions: ["USA"],
            reason: "Japan and USA are roughly equal (Japan is easier, with unlimited continues); the European PAL release replaces the characters with robots and runs with a slower framerate, making it the weakest.",
            sourceURL: "https://en.wikipedia.org/wiki/Contra_III:_The_Alien_Wars",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "EarthBound",
            platform: "SNES",
            alternateTitles: ["Mother 2 - Gyiyg no Gyakushuu"],
            recommendedRegion: "Japan",
            reason: "The US localization removed trademarked logos, hospital red crosses, tombstone crosses and alcohol references and redesigned the cultists; the Japanese version has the original content (the US script adds some jokes, so this means uncensored, not funnier).",
            sourceURL: "https://en.wikipedia.org/wiki/EarthBound",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Secret of Mana",
            platform: "SNES",
            alternateTitles: ["Seiken Densetsu 2"],
            recommendedRegion: "Japan",
            reason: "A large part of the Japanese script was cut from the English version because of cartridge space and a short localization schedule.",
            sourceURL: "https://en.wikipedia.org/wiki/Secret_of_Mana",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Super Ghouls 'N Ghosts",
            platform: "SNES",
            alternateTitles: ["Chou Makaimura"],
            recommendedRegion: "Japan",
            reason: "The Western release swapped church crosses for ankhs and renamed the final boss; the European version also removed enemies and obstacles, making Europe the weakest of the three.",
            sourceURL: "https://en.wikipedia.org/wiki/Super_Ghouls_'n_Ghosts",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
        ),
        RegionQualityNote(
            gameFamily: "Super Mario Kart",
            platform: "SNES",
            recommendedRegion: "USA",
            tiedRegions: ["Japan"],
            reason: "USA and Japan (both NTSC) are equal; the PAL version runs slower on most tracks and is bordered.",
            sourceURL: "http://smkgp150cc.com/SOArules.php?syst=PAL",
            sourceLicense: "Own summary with attribution — not text copied from the source",
            consultedDate: "2026-10-02"
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
    public static func note(forGameName name: String, platform: String? = nil, overrides: [RegionQualityNote] = []) -> RegionQualityNote? {
        let title = baseTitle(for: name)
        func matches(_ note: RegionQualityNote) -> Bool {
            (note.platform == nil || note.platform == platform)
                && (note.gameFamily == title || note.alternateTitles.contains(title))
        }
        if let override = overrides.first(where: matches) { return override }
        return seed.first(where: matches)
    }
}
