// ROMForge — a native ROM collection manager for macOS.
// Copyright (C) 2026 Jensy Leonardo Martínez Cruz
//
// This program is free software under the GNU General Public License v3.0
// or later. It comes with ABSOLUTELY NO WARRANTY. See the LICENSE file.

/// Region and language(s) read from a game's name, e.g.
/// `"Sonic the Hedgehog (USA)"` or `"Final Fantasy VII (Europe) (En,Fr,De)"`.
/// DATs don't carry these as structured fields — No-Intro/TOSEC encode them
/// as parenthesized tags by convention, so this parses that convention
/// rather than reading dedicated XML attributes (there are none).
public struct GameTags: Equatable, Sendable {
    public let region: String?
    public let languages: [String]

    public init(region: String?, languages: [String]) {
        self.region = region
        self.languages = languages
    }
}

public enum GameNameTagParser {
    private static let regions: Set<String> = [
        "usa", "europe", "japan", "world", "asia", "australia", "brazil", "canada",
        "china", "denmark", "finland", "france", "germany", "greece", "hong kong",
        "ireland", "italy", "korea", "netherlands", "norway", "portugal", "russia",
        "spain", "sweden", "taiwan", "uk", "united kingdom",
    ]

    private static let languageCodes: Set<String> = [
        "en", "ja", "fr", "de", "es", "it", "nl", "pt", "sv", "no", "da", "fi",
        "zh", "ko", "pl", "ru", "cs", "hu", "tr", "ar", "el", "he",
    ]

    public static func parse(name: String) -> GameTags {
        var region: String?
        var languages: [String] = []

        for group in parenthesizedGroups(in: name) {
            let trimmed = group.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if region == nil, regions.contains(trimmed.lowercased()) {
                region = trimmed
                continue
            }

            let tokens = trimmed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if languages.isEmpty, tokens.allSatisfy({ languageCodes.contains($0.lowercased()) }) {
                languages = tokens
            }
        }

        return GameTags(region: region, languages: languages)
    }

    private static func parenthesizedGroups(in name: String) -> [String] {
        var groups: [String] = []
        var depth = 0
        var current = ""
        for char in name {
            switch char {
            case "(":
                depth += 1
                if depth == 1 { current = "" }
            case ")":
                if depth == 1 { groups.append(current) }
                depth = max(0, depth - 1)
            default:
                if depth >= 1 { current.append(char) }
            }
        }
        return groups
    }
}
